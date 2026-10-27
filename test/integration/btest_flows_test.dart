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
import 'package:baocode/theme/app_theme.dart';

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
}
