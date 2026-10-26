import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart'
    show AppLifecycleState, Icons, SizedBox, Size;
import 'package:flutter/widgets.dart' show debugOnRebuildDirtyWidget;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:super_sliver_list/super_sliver_list.dart';

import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/widgets/chat_item_view.dart';
import 'package:baocode/diagnostics/stall_watch.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/thincoder/thincoder_kernel.dart';
import 'package:baocode/kernel/thincoder/thincoder_mock.dart';
import 'package:baocode/kernel/thincoder/thincoder_process_io.dart';
import 'package:baocode/kernel/thincoder/thincoder_transport.dart';
import 'package:baocode/main.dart';
import 'package:baocode/platform/event_log.dart';
import 'package:baocode/platform/process_host.dart' hide ProcessSignal;
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';

/// The integration index this file answers to: `test/RTM.md`, one test per
/// row, the row's number the test's own.
///
/// The app is mounted whole and driven from the sidebar: what a row asserts
/// is the result a user sees, not the mechanism that brings it about.
void main() {
  testWidgets(
    '1-1 switching between two chats five times: each switch starts one '
    'process, and the window never stalls',
    (tester) async {
      final app = await _open(tester);
      final workspace = app.workspace;

      final a = workspace.threads.firstWhere((t) => t.title == 'Chat a1');
      final b = workspace.threads.firstWhere((t) => t.title == 'Chat a2');

      // Five switches, each to the chat not shown: A→B→A→B→A from whichever
      // one the app opened by itself.
      for (var switching = 0; switching < 5; switching++) {
        final target = identical(workspace.selected, a) ? b : a;
        final starts = app.host.starts;

        await tester.tap(
          find.descendant(
            of: find.byType(Sidebar),
            matching: find.text(target.title),
          ),
        );
        // 6 × 50 ms: the switch is over in 300 ms, and the pumps in between
        // are what lets the handshake's turns run.
        for (var step = 0; step < 6; step++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        // The chat asked for is the one shown, its process started once, and
        // inside 300 ms it is usable: its rows are there, the input takes.
        expect(workspace.selected, same(target));
        expect(app.host.starts, starts + 1);
        expect(
          find.textContaining('Hi — what would you like to do?'),
          findsWidgets,
        );
        expect(target.session.health.status, KernelHealthStatus.ready);
        expect(target.session.canSend, isTrue);
      }

      // The log these five switches write to never saw the window thread held
      // long enough to be a stall.
      final log = File(EventLog.current!.path).readAsStringSync();
      expect(log, contains('[thincoder]'), reason: 'the log is live');
      expect(log, isNot(contains('[stall]')));
      app.done();
    },
  );

  testWidgets(
    '2-1 the window out of sight while the reply streams: nothing is redrawn, '
    'and coming back shows all of it where it was left',
    (tester) async {
      final app = await _open(tester, turns: 2);
      final session = app.session;

      // A reply under way: what it says from here is this test's to send.
      session.send(const ComposerMessage(text: 'go on'));
      await _pumpFor(tester, const Duration(milliseconds: 300));
      app.say('Start. ');
      await _pumpFor(tester, const Duration(milliseconds: 50));
      expect(find.textContaining('Start.', findRichText: true), findsWidgets);
      final counter = _countRebuilds();

      // Pointed at another window: the reply goes on arriving, unseen.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      for (var i = 0; i < 120; i++) {
        app.say('w$i ');
        await _pumpFor(tester, const Duration(milliseconds: 8));
      }

      // Not a row rebuilt, not a word shown: nothing was drawn for it.
      expect(counter.items, 0);
      expect(find.textContaining('w119', findRichText: true), findsNothing);

      // The window thread was not held either: the log has no stall.
      final log = File(EventLog.current!.path).readAsStringSync();
      expect(log, contains('[thincoder]'), reason: 'the log is live');
      expect(log, isNot(contains('[stall]')));

      // Pointed back: one build brings the whole reply in, where it was left.
      counter.reset();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      final rows = find.byType(ChatItemView).evaluate().length;
      expect(rows, greaterThan(0));
      expect(counter.items, rows);
      expect(find.textContaining('w119', findRichText: true), findsWidgets);
      final position = _list(tester).controller!.position;
      expect(position.pixels, closeTo(position.maxScrollExtent, 1));

      // Up from the bottom, out of sight again, and back: the place it was
      // read at is the place it is left at (T2b's reading, from the entry).
      position.jumpTo(position.maxScrollExtent / 2);
      await tester.pump();
      final left = position.pixels;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        app.say('u$i ');
        await _pumpFor(tester, const Duration(milliseconds: 8));
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(position.pixels, closeTo(left, 1));

      app.done();
    },
  );

  testWidgets(
    '3-1 a long conversation streaming: the final text is right, and each '
    'delta costs the same in a short history as in a long one',
    (tester) async {
      // Long first (500 turns = 1000 items), then short (20 turns): what a
      // delta costs must not follow the history.
      final long = await _stream(tester, turns: 500);
      final short = await _stream(tester, turns: 20);

      // The history is 25 times longer, the cost of a delta is the same, item
      // for item: it does not follow what is behind the reply.
      expect(long.perDelta, short.perDelta);
      // A delta is not free, and it is not the conversation either: what the
      // short history cost bounds it.
      expect(short.perDelta.reduce(math.max), lessThan(100));
    },
  );
}

/// Streams 120 deltas into [turns] turns of history, the whole app mounted;
/// what each delta cost in rows rebuilt, and how many rows there were.
Future<({List<int> perDelta, int rows})> _stream(
  WidgetTester tester, {
  required int turns,
}) async {
  final app = await _open(tester, turns: turns);
  // The history is in before anything is sent: its last turn is on screen,
  // where the list opens.
  expect(
    find.textContaining('Answer ${turns - 1}.', findRichText: true),
    findsWidgets,
    reason: 'the history of $turns turns is loaded',
  );

  app.session.send(const ComposerMessage(text: 'go on'));
  await _pumpFor(tester, const Duration(milliseconds: 300));

  final counter = _countRebuilds();
  final perDelta = <int>[];
  for (var i = 0; i < 120; i++) {
    counter.reset();
    app.say('w$i ');
    await _pumpFor(tester, const Duration(milliseconds: 8));
    perDelta.add(counter.items);
  }

  // What was said is what shows, when the list has come to rest.
  expect(find.textContaining('w119', findRichText: true), findsWidgets);
  final rows = find.byType(ChatItemView).evaluate().length;
  app.done();
  return (perDelta: perDelta, rows: rows);
}

/// The app, mounted: its one kernel behind a scripted agent, the agent's
/// history in, and the chat it opened ready to take a message.
Future<_App> _open(WidgetTester tester, {int turns = 0}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final temp = Directory.systemTemp.createTempSync('chat-flows');
  addTearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  // The log the app writes to: the [stall] reading is taken from it.
  final previousLog = EventLog.current;
  EventLog.current = EventLog(p.join(temp.path, 'logs'));
  // The watchdog the app starts (main.dart), on the clock it reads in the app.
  // It is started once the app is up: what it counts from there on is the
  // window thread being held, not the time this test spent setting the app up.
  final stall = StallWatch();

  // A session's process starts through the host: the fake backend is where
  // the switches are counted, and the agent behind it is the test's.
  final host = _ScriptedHost(replay: _replayOf(turns));
  ProcessHost.useForTest(host);
  final previousRegistry = ThincoderProcess.registry;
  ThincoderProcess.registry = _InstantRegistry(
    file: File(p.join(temp.path, 'state', 'thincoder-processes.json')),
  );
  addTearDown(() {
    stall.stop();
    ProcessHost.useForTest(null);
    ThincoderProcess.registry = previousRegistry;
    EventLog.current = previousLog;
  });

  late final KernelDescriptor thincoder;
  thincoder = KernelDescriptor(
    id: 'thincoder',
    label: 'thincoder',
    icon: Icons.smart_toy_outlined,
    description: 'The agent of the user’s terminal',
    catalog: _KeptCatalog(_records),
    create: (context) => ThincoderKernel(
      thincoder,
      context,
      // Only where the executable is looked for is the test's: the process
      // itself is made by the host above.
      launch: (cwd) async =>
          ThincoderLaunch(cwd: cwd, executable: '/mock/thincoder'),
    ),
  );
  final workspace = Workspace(
    kernels: [thincoder],
    preferences: MemoryPreferenceStore(),
  );
  // A tree of its own: a case that mounts the app twice starts the second one
  // with nothing of the first left standing.
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  // The app disposes the workspace it was given, with the tree.
  await tester.pumpWidget(BaoCodeApp(workspace: workspace));
  await tester.runAsync(workspace.load);
  await tester.pump();
  stall.start();

  // A chat picked from the sidebar, as a user does: its process starts and
  // its history is read in, which is what makes it usable.
  final opening = workspace.threads.firstWhere((t) => t.title == 'Chat a2');
  await tester.tap(
    find.descendant(
      of: find.byType(Sidebar),
      matching: find.text(opening.title),
    ),
  );
  ChatSession? opened;
  for (var i = 0; i < 400; i++) {
    if (opening.session.health.status == KernelHealthStatus.ready &&
        !opening.session.loadingHistory) {
      opened = opening.session;
      break;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(opened, isNotNull, reason: 'the opened chat is ready');
  // The last of the history laid out, if there is any.
  await _pumpFor(tester, const Duration(milliseconds: 50));
  final app = _App(
    host: host,
    workspace: workspace,
    session: opened!,
    stall: stall,
  );
  app.agent.hold = app.hold;
  return app;
}

/// One chat conversation's history, as the agent replays it: [turns] turns of
/// a question and its answer — or, for none, the agent's own greeting.
List<Map<String, Object?>> _replayOf(int turns) => turns == 0
    ? ThincoderMock.defaultReplay
    : [
        for (var n = 0; n < turns; n++) ...[
          {
            'sessionUpdate': 'user_message_chunk',
            'content': {'type': 'text', 'text': 'Question $n'},
          },
          {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': 'Answer $n.'},
          },
        ],
      ];

/// The history's list on screen.
SuperListView _list(WidgetTester tester) =>
    tester.widget<SuperListView>(find.byType(SuperListView));

/// Pumps until [total] has gone by, a frame at a time.
Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 8);
  for (var gone = Duration.zero; gone < total; gone += step) {
    await tester.pump(step);
  }
}

/// Counts the rows built from here on, until the test ends.
Counter _countRebuilds() {
  final counter = Counter();
  debugOnRebuildDirtyWidget = (element, _) {
    if (element.widget is ChatItemView) counter.items++;
  };
  addTearDown(() => debugOnRebuildDirtyWidget = null);
  return counter;
}

final class Counter {
  int items = 0;

  void reset() => items = 0;
}

/// The app as a test drives it.
final class _App {
  _App({
    required this.host,
    required this.workspace,
    required this.session,
    required this.stall,
  });

  final _ScriptedHost host;
  final Workspace workspace;

  /// The watchdog the app started: stopped with the test, before the tree
  /// goes (its timer is periodic).
  final StallWatch stall;

  /// The chat the app opened.
  final ChatSession session;

  /// The agent behind that chat's process: the process the app started.
  ThincoderMock get agent => host.agents.last;

  /// Lets the agent's turn on: nothing is said that is not the test's.
  final Completer<void> hold = Completer<void>();

  /// What the reply says next, as the agent reports it.
  void say(String text) {
    final prompt =
        agent.requests('session/prompt').last['params']!
            as Map<String, Object?>;
    agent.push({
      'jsonrpc': '2.0',
      'method': 'session/update',
      'params': {
        'sessionId': prompt['sessionId'],
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': text},
        },
      },
    });
  }

  /// The turn let go and the watchdog stopped: the app left as it was.
  void done() {
    if (!hold.isCompleted) hold.complete();
    stall.stop();
  }
}

/// The project the sessions run in: what the sidebar lists before the app
/// starts anything.
const _project = '/tmp/a';

final _records = [
  SessionRecord(
    id: '$_project|1',
    title: 'Chat a1',
    updatedAt: DateTime(2026, 10, 26, 9, 30),
    cwd: _project,
  ),
  SessionRecord(
    id: '$_project|2',
    title: 'Chat a2',
    updatedAt: DateTime(2026, 10, 26, 9, 0),
    cwd: _project,
  ),
];

/// The sessions an agent reports: the two the sidebar lists.
const _shelf = <Map<String, Object?>>[
  {
    'sessionId': '1',
    'updatedAt': '2026-10-26T09:30:00.000Z',
    'title': 'Chat a1',
  },
  {
    'sessionId': '2',
    'updatedAt': '2026-10-26T09:00:00.000Z',
    'title': 'Chat a2',
  },
];

/// A registry whose reaping — the one step that reads the file system — is
/// already done: under the fake clock a real read never comes back, and what
/// a previous run left behind is not this test's subject.
final class _InstantRegistry extends ThincoderProcessRegistry {
  _InstantRegistry({required super.file})
    : super(lookup: (_) async => null, signal: (_) => false);

  @override
  Future<void> get reaped => Future.value();
}

/// A catalog over [_records]: no file is read, the sessions are the test's.
final class _KeptCatalog implements SessionCatalog {
  _KeptCatalog(this.records);

  final List<SessionRecord> records;

  @override
  Future<List<ProjectRecord>> projects() async => [
    for (final path in {for (final record in records) record.cwd})
      ProjectRecord(
        path: path,
        sessions: [
          for (final record in records)
            if (record.cwd == path) record,
        ],
      ),
  ];

  @override
  Future<List<SessionRecord>> sessionsIn(String cwd) async => [
    for (final record in records)
      if (record.cwd == cwd) record,
  ];

  @override
  Future<void> delete(String id) async {}
}

/// The process host with scripted agents behind it: every `start` is one
/// process the app asked for, and the agent it talks to speaks ACP as the
/// terminal's does.
final class _ScriptedHost implements ProcessHostBackend {
  _ScriptedHost({this.replay = const []});

  /// What a session's history replays as.
  final List<Map<String, Object?>> replay;

  final List<ThincoderMock> agents = [];

  /// How many processes the app started.
  int get starts => agents.length;

  @override
  Future<HostedProcess> start(ProcessSpec spec) async {
    final agent = ThincoderMock(
      cwd: spec.workingDirectory ?? _project,
      slots: _shelf,
      replay: replay,
      // A turn says nothing by itself: what the reply says is the test's to
      // send, and the turn stays open until it lets go.
      turn: const [],
    );
    agents.add(agent);
    final stdout = StreamController<List<int>>();
    final exited = Completer<int>();
    agent.messages.listen((message) {
      if (!stdout.isClosed) stdout.add(utf8.encode('${jsonEncode(message)}\n'));
    });
    void gone() {
      if (exited.isCompleted) return;
      exited.complete(0);
      unawaited(stdout.close());
    }

    return HostedProcess(
      pid: 4100 + agents.length,
      stdout: stdout.stream,
      stderr: Stream<List<int>>.empty(),
      exitCode: exited.future,
      write: (bytes) {
        for (final line in const LineSplitter().convert(utf8.decode(bytes))) {
          if (line.trim().isEmpty) continue;
          agent.write((jsonDecode(line) as Map).cast<String, Object?>());
        }
      },
      closeStdin: () {},
      kill: (signal) => gone(),
    );
  }

  @override
  Future<HostedRun> run(
    ProcessSpec spec, {
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) async => throw const ProcessHostUnavailable('not scripted here');

  @override
  Future<void> stopAll() async {}
}
