import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Icons, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
      // The watchdog the app starts (main.dart), on the clock it reads in the
      // app. It is started once the app is up: what it counts from there on is
      // the window thread being held, not the time this test spent setting the
      // app up.
      final stall = StallWatch();

      // A session's process starts through the host: the fake backend is
      // where the switches are counted.
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
          // Only where the executable is looked for is the test's: the
          // process itself is made by the host above.
          launch: (cwd) async =>
              ThincoderLaunch(cwd: cwd, executable: '/mock/thincoder'),
        ),
      );
      final workspace = Workspace(
        kernels: [thincoder],
        preferences: MemoryPreferenceStore(),
      );
      // The app disposes the workspace it was given, with the tree.
      await tester.pumpWidget(BaoCodeApp(workspace: workspace));
      await tester.runAsync(workspace.load);
      await tester.pump();
      stall.start();

      final a = workspace.threads.firstWhere((t) => t.title == 'Chat a1');
      final b = workspace.threads.firstWhere((t) => t.title == 'Chat a2');

      // Five switches, each to the chat not shown: A→B→A→B→A from whichever
      // one the app opened by itself.
      for (var switching = 0; switching < 5; switching++) {
        final target = identical(workspace.selected, a) ? b : a;
        final starts = host.starts;

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
        expect(host.starts, starts + 1);
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
      stall.stop();
    },
  );
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
  {'sessionId': '1', 'updatedAt': '2026-10-26T09:30:00.000Z', 'title': 'Chat a1'},
  {'sessionId': '2', 'updatedAt': '2026-10-26T09:00:00.000Z', 'title': 'Chat a2'},
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
  final List<ThincoderMock> agents = [];

  /// How many processes the app started.
  int get starts => agents.length;

  @override
  Future<HostedProcess> start(ProcessSpec spec) async {
    final agent = ThincoderMock(
      cwd: spec.workingDirectory ?? _project,
      slots: _shelf,
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
