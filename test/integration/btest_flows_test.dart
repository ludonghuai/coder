import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baocode/browser/btest/btest_card.dart';
import 'package:baocode/browser/btest/btest_mode.dart';
import 'package:baocode/browser/btest/btest_policy.dart';
import 'package:baocode/browser/btest/btest_tool_gate.dart';
import 'package:baocode/browser/browser_bridge.dart' show BrowserError;
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/host_tools/host_tools.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/platform/data_dir.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:path/path.dart' as p;

// The integration index this file answers to: `test/RTM.md`, §4 — the row's
// number the test's own. The composer's mode picker is the user's entry; what
// is asserted is the result a user sees, across ChatSession, the btest card
// and the browser tools' gate together.

/// A kernel that only says what a test tells it to: a ready agent that
/// offers two modes (`normal`, `plan`) and keeps the turns it is sent.
class _Kernel with KernelEventSource implements AgentKernel, SelectsMode {
  _Kernel(this.descriptor);

  @override
  final KernelDescriptor descriptor;

  @override
  KernelHealth get health => KernelHealth.ready;

  @override
  String? get sessionId => '1';

  @override
  late final KernelChoiceSource mode = LocalChoice([
    const KernelOption('normal', 'normal', Icons.circle, ''),
    const KernelOption('plan', 'plan', Icons.circle, ''),
  ]);

  /// What it was sent, in order.
  final List<KernelTurn> turns = [];

  @override
  void send(KernelTurn turn) => turns.add(turn);
  @override
  void answer(String requestId, InteractionAnswer answer) {}
  @override
  void cancel() {}
  @override
  void restart() {}
  @override
  void prepare() {}
  @override
  void release() {}
  @override
  void dispose() => closeEvents();
  @override
  Future<void> get stopped => Future.value();

  /// Reports the last turn it was sent as the user's message, as a kernel
  /// echoes what it took up.
  void echoLastTurn() {
    final turn = turns.last;
    emit(
      ItemUpserted(
        nextSeq,
        'u${turns.length}',
        UserMessageItem(text: turn.text, contexts: turn.contexts),
      ),
    );
  }
}

void main() {
  const cwd = '/project';
  const allowed = 'booking.dev.example.com';
  const startUrl = 'https://booking.dev.example.com/booking';

  setUp(() {
    BtestMode.reset();
    BtestSettings.values = {
      BtestSettings.allowHostsKey: [allowed],
      BtestSettings.prodHostsKey: ['prod.example.com'],
      BtestSettings.readonlyKey: true,
    };
  });

  tearDown(() {
    BtestMode.reset();
    BtestSettings.values = null;
  });

  ({ChatSession session, _Kernel kernel}) makeSession(String folder) {
    late _Kernel kernel;
    final descriptor = KernelDescriptor(
      id: 'test',
      label: 'test',
      icon: Icons.circle,
      description: '',
      create: (_) => kernel,
    );
    kernel = _Kernel(descriptor);
    final session = ChatSession(
      kernel: descriptor,
      kernels: [descriptor],
      kernelContext: KernelContext(cwd: folder),
      historyCount: 0,
    );
    addTearDown(session.dispose);
    return (session: session, kernel: kernel);
  }

  Future<ChatSession> pumpSession(WidgetTester tester, String folder) async {
    final made = makeSession(folder);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AnimatedBuilder(
            animation: made.session,
            builder: (context, _) =>
                ChatComposer(session: made.session, draft: made.session.draft),
          ),
        ),
      ),
    );
    await tester.pump();
    return made.session;
  }

  Future<void> choose(WidgetTester tester, String key, String label) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Directory businessRepo(Directory sandbox) {
    final repo = Directory(p.join(sandbox.path, 'repo'))..createSync();
    Directory(p.join(repo.path, '.git')).createSync();
    return repo;
  }

  File seedExpect(Directory sandbox, List<String> ids) {
    final file = File(p.join(sandbox.path, 'qa', 'repo', '订舱.md'))
      ..parent.createSync(recursive: true);
    file.writeAsStringSync(
      [
        for (final id in ids)
          '## $id 既有用例\n'
              '- origin: 无（存量）\n'
              '- expectFrom: 强 · docs/vibe-coding.md §3.1\n',
      ].join('\n'),
    );
    return file;
  }

  testWidgets(
    '4-1 switching to btest in the composer: the next turn carries the card '
    'once, the browser gate reads the same run, and leaving ends it once',
    (tester) async {
      late _Kernel kernel;
      final descriptor = KernelDescriptor(
        id: 'test',
        label: 'test',
        icon: Icons.circle,
        description: '',
        create: (_) => kernel,
      );
      kernel = _Kernel(descriptor);
      final session = ChatSession(
        kernel: descriptor,
        kernels: [descriptor],
        kernelContext: const KernelContext(cwd: cwd),
        historyCount: 0,
      );
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AnimatedBuilder(
              animation: session,
              builder: (context, _) =>
                  ChatComposer(session: session, draft: session.draft),
            ),
          ),
        ),
      );
      await tester.pump();

      // The user switches to btest from the composer's mode picker.
      await tester.tap(find.text('normal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('btest').last);
      await tester.pumpAndSettle();
      expect(session.btestOn, isTrue);
      expect(find.textContaining('btest ·'), findsOneWidget);

      /// The card the last turn carried, as the agent is told it.
      List<String> cardsOnTheLastTurn() => [
        for (final context in kernel.turns.last.contexts)
          if (context.name == 'btest') context.note,
      ];

      // The next message goes out with the card, exactly once.
      session.send(const ComposerMessage(text: '搜一下订舱'));
      kernel.echoLastTurn();
      await tester.pumpAndSettle();
      expect(cardsOnTheLastTurn(), [BtestCard.text]);

      // The tools read the very state the composer shows: one run, one set
      // of switches.
      final state = BtestMode.find(cwd, session.sessionId)!;
      expect(state.on, session.btestOn);
      expect(state.traversal, session.btestTraversal);
      expect(state.write, session.btestWrite);
      // The run a `btest_run_start` makes takes its face from the switch.
      session.setBtestWrite(false);
      await tester.pump();
      final run = state.start(
        line: '订舱',
        repoRoot: '/repos/v2-timecharter',
        startUrl: startUrl,
        env: BtestEnv.test,
        face: session.btestWrite ? BtestFace.write : BtestFace.readonly,
        traversal: session.btestTraversal,
        scenarios: const [
          (
            id: 'S1',
            scenario: '提交订舱',
            role: '货代操作员',
            pre: '已登录',
            branch: '主路径',
          ),
        ],
        expectFile: '/qa/v2-timecharter/订舱.md',
        qaRoot: '/qa',
        commitRange: 'abc1234',
        baseline: null,
        cases: const [],
      );
      expect(session.btestRun?.id, run.id);

      // A write in a readonly run is refused by the gate, with a reason the
      // user can read.
      try {
        await BtestToolGate.check(
          'browser_click',
          const {'tabId': 1, 'ref': 1},
          const HostToolCall(cwd: cwd, sessionId: '1'),
          tabHost: (_) async => allowed,
        );
        fail('a write in a readonly run must be refused');
      } on BrowserError catch (error) {
        expect(error.message, contains('browser_click'));
        expect(error.message, contains('readonly'));
      }

      // Back to a normal mode from the same picker: the next turn says the
      // mode ended once, and no later turn says it again.
      await tester.tap(find.text('btest').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('normal').last);
      await tester.pumpAndSettle();
      expect(session.btestOn, isFalse);
      expect(find.textContaining('btest ·'), findsNothing);

      session.send(const ComposerMessage(text: '好'));
      kernel.echoLastTurn();
      await tester.pumpAndSettle();
      expect(cardsOnTheLastTurn(), [BtestCard.offText]);

      session.send(const ComposerMessage(text: '继续'));
      kernel.echoLastTurn();
      await tester.pumpAndSettle();
      expect(cardsOnTheLastTurn(), isEmpty, reason: 'the end is said once');
    },
  );

  testWidgets('5-1 btest 收尾：载荷缺项被拒、补齐后同一 run 交出场景矩阵报告', (tester) async {
    final sandbox = Directory.systemTemp.createTempSync('btest-flow-5-1');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final repo = businessRepo(sandbox);
    final expectFile = seedExpect(sandbox, ['CASE-001', 'CASE-002']);
    final session = makeSession(sandbox.path).session..setBtest(true);
    final call = HostToolCall(cwd: sandbox.path, sessionId: session.sessionId);
    await BtestTools.all.first.run({
      'line': '订舱',
      'repoRoot': repo.path,
      'startUrl': startUrl,
      'env': 'test',
      'mode': 'write',
      'commitRange': 'abc1234',
      'scenarios': const [
        {'scenario': '提交订舱', 'role': '货代操作员', 'pre': '无草稿', 'branch': '主路径'},
        {'scenario': '改单复核', 'role': '审核员', 'pre': '已有待审核单', 'branch': '二次复核'},
      ],
    }, call);
    final state = BtestMode.find(sandbox.path, session.sessionId)!;
    final runId = state.run!.id;
    final covered = <String>['CASE-001'];
    final issue = <String, Object?>{
      'caseId': 'CASE-001',
      'step': '点提交',
      'symptom': '提示成功但状态未推进',
      'evidence': const {'kind': 'field', 'readout': '提交后列表状态=待审核'},
      'severity': '高',
      'expectRef': '强 · docs/vibe-coding.md §3.1',
    };
    final results = <Map<String, Object?>>[
      {
        'id': 'S1',
        'verdict': 'fail',
        'evidence': '提交后仍为待审核',
        'caseId': 'CASE-001',
      },
    ];
    final payload = <String, Object?>{
      'runId': runId,
      'coveredCases': covered,
      'issues': [issue],
      'scenarioResults': results,
      'blockers': const <Object?>[],
      'unconfirmedDiffs': const <Object?>[],
      'uncovered': const <Object?>[],
      'noVisibleText': const <Object?>[],
    };

    try {
      await BtestTools.all.last.run(payload, call);
      fail('the incomplete report must be refused');
    } on BrowserError catch (error) {
      expect(error.message, contains('issues[1].pre'));
      expect(error.message, contains('lacks declared scenario S2'));
      expect(error.message, contains('R4 case CASE-002'));
    }
    expect(state.run?.id, runId, reason: 'a refusal does not consume the run');

    issue['pre'] = '已登录；无草稿';
    covered.add('CASE-002');
    results.add({'id': 'S2', 'verdict': 'pass', 'evidence': '复核快照一致'});
    expectFile.writeAsStringSync(
      '${expectFile.readAsStringSync()}\n<!-- 5-1 write-back -->\n',
    );
    final answer = '${await BtestTools.all.last.run(payload, call)}';
    expect(answer, contains('btest $runId closed'));
    expect(
      answer,
      contains('| S1 | 提交订舱 | 货代操作员 | 无草稿 | 主路径 | fail | 提交后仍为待审核 · 问题行 #1 |'),
    );
    expect(
      answer,
      contains('| S2 | 改单复核 | 审核员 | 已有待审核单 | 二次复核 | pass | 复核快照一致 |'),
    );
    expect(state.run, isNull);
  });

  testWidgets('6-1 btest 两个开关跨重启读回', (tester) async {
    final sandbox = Directory.systemTemp.createTempSync('btest-flow-6-1');
    final files = SettingsFiles(DataDirectory(sandbox.path));
    SettingsFiles.instance = files;
    addTearDown(() {
      SettingsFiles.instance = SettingsFiles(DataDirectory.current);
      files.dispose();
      sandbox.deleteSync(recursive: true);
    });
    await tester.runAsync(() async {
      await files.settings.load();
      await files.settings.update(BtestSettings.allowHostsKey, [allowed]);
      await files.settings.update(BtestSettings.prodHostsKey, [
        'prod.example.com',
      ]);
      await files.settings.update(BtestSettings.readonlyKey, true);
    });
    BtestSettings.values = null;
    final repo = businessRepo(sandbox);
    seedExpect(sandbox, ['CASE-001']);

    await pumpSession(tester, sandbox.path);
    await tester.runAsync(() async {
      await tester.tap(find.text('normal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('btest').last);
      await tester.pumpAndSettle();
      await choose(tester, 'btest-traversal-switch', 'chain');
      await choose(tester, 'btest-write-switch', 'write');
      await files.settings.load();
    });
    expect(find.text('btest · not started · chain · write'), findsOne);
    expect(files.settings[BtestSettings.onKey], isTrue);
    expect(files.settings[BtestSettings.traversalKey], 'chain');
    expect(files.settings[BtestSettings.modeKey], 'write');

    BtestMode.reset();
    final second = await pumpSession(tester, sandbox.path);
    expect(second.btestTraversal, BtestTraversal.chain);
    expect(second.btestWrite, isTrue);
    expect(find.text('btest · not started · chain · write'), findsOne);
    final call = HostToolCall(cwd: sandbox.path, sessionId: second.sessionId);
    final opened = await tester.runAsync(
      () async =>
          '${await BtestTools.all.first.run({
            'line': '订舱',
            'repoRoot': repo.path,
            'startUrl': startUrl,
            'env': 'test',
            'commitRange': 'abc1234',
            'scenarios': const [
              {'scenario': '提交订舱', 'role': '货代操作员', 'pre': '无草稿', 'branch': '主路径'},
            ],
          }, call)}',
    );
    expect(opened, contains('traversal=chain'));
    expect(opened, contains('mode=write'));
    BtestMode.find(sandbox.path, second.sessionId)!.end();

    await tester.runAsync(() async {
      await choose(tester, 'btest-traversal-switch', 'surface');
      await files.settings.load();
    });
    expect(files.settings[BtestSettings.traversalKey], 'surface');
    BtestMode.reset();
    final third = await pumpSession(tester, sandbox.path);
    expect(third.btestTraversal, BtestTraversal.surface);
    expect(third.btestWrite, isTrue);
    expect(find.text('btest · not started · surface · write'), findsOne);
  });
}
