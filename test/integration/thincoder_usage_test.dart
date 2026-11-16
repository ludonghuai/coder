import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Icons, SizedBox, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/panels/context_usage_panel.dart';
import 'package:baocode/chat/widgets/context_meter.dart';
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
import 'package:baocode/usage/usage_prices.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';

/// The integration index this file answers to: `test/RTM.md`, row 10-1 —
/// a thincoder chat's usage as the user reads it: the prompt cache the
/// requests were served from, and what the session cost.
///
/// The app is mounted whole and driven from its own entries (the sidebar,
/// the composer, the context ring); what the case asserts is what a user
/// sees in the context panel, not the mechanism that brings it about.
void main() {
  late UsagePrices previous;

  setUp(() => previous = UsagePrices.current);

  tearDown(() => UsagePrices.current = previous);

  testWidgets(
    '10-1 a thincoder chat shows the cache its requests were served from and '
    'what the session cost',
    (tester) async {
      // The price table a user keeps (Settings → usage): this model reads at
      // 3, writes at 15, and its cached input at 0.3, a million tokens each.
      UsagePrices.current = UsagePrices({
        UsagePrices.key('anthropic', 'claude-sonnet-5'): const ModelPrice(
          input: 3,
          output: 15,
          cacheRead: 0.3,
        ),
      });

      final app = await _open(tester);

      // Two turns with a tool each, a request each, as the CLI reports them
      // (§30.4): the second reads more of the conversation from the cache
      // than the first.
      app.agent.turn.clear();
      app.agent.turn.addAll([
        ..._toolCall('t1', '/tmp/u/a.txt'),
        _frame(1234, input: 900, output: 334, cacheRead: 700),
        _reply('First.'),
      ]);
      app.session.send(const ComposerMessage(text: 'go'));
      await _pumpFor(tester, const Duration(milliseconds: 300));

      app.agent.turn
        ..clear()
        ..addAll([
          ..._toolCall('t2', '/tmp/u/b.txt'),
          _frame(600, input: 500, output: 100, cacheRead: 300),
          _reply('Second.'),
        ]);
      app.session.send(const ComposerMessage(text: 'and on'));
      await _pumpFor(tester, const Duration(milliseconds: 300));

      // The context ring in the row under the conversation, picked: the
      // panel opens.
      await _openPanel(tester);

      // The cache the requests were served from: the last request's share
      // read from it (300 of 500), and the conversation's (1 000 of 1 400).
      expect(find.text('Prompt cache'), findsOneWidget);
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('main chat 71%'), findsOneWidget);

      // What the session cost, by the table: the two requests' own tokens.
      // 200·3 + 700·0.3 + 334·15, and 200·3 + 300·0.3 + 100·15, a millionth
      // of a dollar each — $0.01 in the panel.
      expect(find.text(r'$0.01'), findsOneWidget);

      // The table emptied: a chat started now has no price for the model,
      // and its panel says nothing about cost rather than $0.00.
      UsagePrices.current = UsagePrices();
      final other = app.workspace.threads.firstWhere(
        (thread) => thread.title == 'Chat a1',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(Sidebar),
          matching: find.text(other.title),
        ),
      );
      await _ready(tester, other.session);
      app.agent.turn
        ..clear()
        ..addAll([
          ..._toolCall('t3', '/tmp/u/c.txt'),
          _frame(1234, input: 900, output: 334, cacheRead: 700),
          _reply('Nothing priced.'),
        ]);
      other.session.send(const ComposerMessage(text: 'go'));
      await _pumpFor(tester, const Duration(milliseconds: 300));

      await _openPanel(tester);
      expect(find.text('Prompt cache'), findsOneWidget);
      expect(find.text('78%'), findsOneWidget);
      expect(find.text('main chat 78%'), findsOneWidget);
      expect(find.text('Plan usage'), findsNothing);
      expect(find.text(r'$0.00'), findsNothing);
      app.done();
    },
  );
}

/// One `usage_update` as the CLI writes it (§30.4): the context it filled —
/// `used` the request's prompt and completion together — and the request's
/// own counts under `_meta`: one frame, a request.
Map<String, Object?> _frame(
  int used, {
  required int input,
  required int output,
  required int cacheRead,
}) => {
  'sessionUpdate': 'usage_update',
  'used': used,
  'size': 200000,
  '_meta': {
    'thincoder.dev/usage': {
      'input': input,
      'output': output,
      'cacheRead': cacheRead,
    },
  },
};

Map<String, Object?> _reply(String text) => {
  'sessionUpdate': 'agent_message_chunk',
  'content': {'type': 'text', 'text': text},
};

/// A tool call the agent reports, read and done with: what a turn of work
/// looks like to the conversation.
List<Map<String, Object?>> _toolCall(String id, String path) => [
  {
    'sessionUpdate': 'tool_call',
    'toolCallId': id,
    'title': 'Read $path',
    'kind': 'read',
    'rawInput': {'path': path},
  },
  {
    'sessionUpdate': 'tool_call_update',
    'toolCallId': id,
    'status': 'completed',
    'content': [
      {
        'type': 'content',
        'content': {'type': 'text', 'text': 'read'},
      },
    ],
  },
];

/// The context panel opened, unless it already is: the ring toggles it.
Future<void> _openPanel(WidgetTester tester) async {
  if (find.byType(ContextUsagePanel).evaluate().isEmpty) {
    await tester.tap(find.byType(ContextMeter));
    await _pumpFor(tester, const Duration(milliseconds: 100));
  }
}

/// Pumps until the chat is ready to take a message (its process started and
/// its history read in).
Future<void> _ready(WidgetTester tester, ChatSession session) async {
  for (var i = 0; i < 400; i++) {
    if (session.health.status == KernelHealthStatus.ready &&
        !session.loadingHistory) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('the chat opened is ready');
}

/// The project the sessions run in: what the sidebar lists before the app
/// starts anything.
const _project = '/tmp/u';

final _records = [
  SessionRecord(
    id: '$_project|1',
    title: 'Chat a1',
    updatedAt: DateTime(2026, 11, 15, 9, 30),
    cwd: _project,
  ),
  SessionRecord(
    id: '$_project|2',
    title: 'Chat a2',
    updatedAt: DateTime(2026, 11, 15, 9, 0),
    cwd: _project,
  ),
];

/// The sessions an agent reports: the two the sidebar lists.
const _shelf = <Map<String, Object?>>[
  {'sessionId': '1', 'updatedAt': '2026-11-15T09:30:00.000Z', 'title': 'Chat a1'},
  {'sessionId': '2', 'updatedAt': '2026-11-15T09:00:00.000Z', 'title': 'Chat a2'},
];

/// A registry whose reaping — the one step that reads the file system — is
/// already done: under the fake clock a real read never comes back.
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
  _ScriptedHost();

  final List<ThincoderMock> agents = [];

  /// How many processes the app started.
  int get starts => agents.length;

  @override
  Future<HostedProcess> start(ProcessSpec spec) async {
    final agent = ThincoderMock(
      cwd: spec.workingDirectory ?? _project,
      slots: _shelf,
      // What a turn says is the test's to script; a chat's history is the
      // agent's own greeting.
      turn: [],
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
      pid: 4200 + agents.length,
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

/// The app, mounted: its one kernel behind a scripted agent, the chat it
/// opened ready to take a message.
Future<_App> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final temp = Directory.systemTemp.createTempSync('thincoder-usage');
  addTearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  final previousLog = EventLog.current;
  EventLog.current = EventLog(p.join(temp.path, 'logs'));
  final stall = StallWatch();

  final host = _ScriptedHost();
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
  await tester.pumpWidget(BaoCodeApp(workspace: workspace));
  await tester.runAsync(workspace.load);
  await tester.pump();
  stall.start();

  // A chat picked from the sidebar, as a user does.
  final opening = workspace.threads.firstWhere(
    (thread) => thread.title == 'Chat a2',
  );
  await tester.tap(
    find.descendant(
      of: find.byType(Sidebar),
      matching: find.text(opening.title),
    ),
  );
  await _ready(tester, opening.session);
  await _pumpFor(tester, const Duration(milliseconds: 50));
  return _App(
    host: host,
    workspace: workspace,
    session: opening.session,
    stall: stall,
  );
}

/// Pumps until [total] has gone by, a frame at a time.
Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 8);
  for (var gone = Duration.zero; gone < total; gone += step) {
    await tester.pump(step);
  }
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

  /// The watchdog stopped: the app left as it was.
  void done() => stall.stop();
}
