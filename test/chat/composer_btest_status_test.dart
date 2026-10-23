import 'package:baocode/browser/btest/btest_mode.dart';
import 'package:baocode/browser/btest/btest_policy.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// btest's status line and the two switches at its end (design §9.1 · §7 #37
// / #38 / #40): what the line reads with no run and during one, that a click
// writes the switch back, and that a run under way keeps its own values.
void main() {
  setUp(() {
    BtestMode.reset();
    BtestSettings.values = {
      BtestSettings.allowHostsKey: const ['booking.dev.example.com'],
      BtestSettings.readonlyKey: true,
    };
  });

  tearDown(() {
    BtestMode.reset();
    BtestSettings.values = null;
  });

  /// The composer with btest on, as the app shows it: every change of the
  /// session builds the box again.
  Future<ChatSession> pumpComposer(
    WidgetTester tester, {
    Locale locale = const Locale('zh'),
    void Function(ChatSession session)? before,
  }) async {
    final session = ChatSession(historyCount: 0);
    addTearDown(session.dispose);
    session.setBtest(true);
    before?.call(session);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        locale: locale,
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
    return session;
  }

  /// The state the host's own tools see for [session]: the one its switches
  /// and its run are kept in.
  BtestState stateOf(ChatSession session) =>
      BtestMode.find(session.kernelContext.cwd, session.sessionId)!;

  /// The run a host's `btest_run_start` would have made.
  void startRun(
    BtestState state, {
    BtestFace face = BtestFace.readonly,
    BtestTraversal traversal = BtestTraversal.surface,
  }) {
    state.start(
      line: '航次',
      repoRoot: 'D:/repos/v2-timecharter',
      startUrl: 'https://charter.dev.example.com/list',
      env: BtestEnv.test,
      face: face,
      traversal: traversal,
      expectFile: 'D:/qa/v2-timecharter/航次.md',
      qaRoot: 'D:/qa',
      commitRange: 'abc1234',
      baseline: null,
      cases: const [],
    );
  }

  Future<void> openSwitch(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> pick(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('a session starts from the defaults, and the switches write '
      'no setting (#37)', (tester) async {
    final session = await pumpComposer(tester, locale: const Locale('en'));
    expect(session.btestTraversal, BtestTraversal.surface);
    expect(session.btestWrite, isFalse, reason: 'btest.readonly is on');
    expect(find.text('btest · not started · surface · readonly'), findsOne);

    // Moved, then read back: the settings are as they were.
    final settings = Map<String, Object?>.of(BtestSettings.values!);
    session.setBtestTraversal(BtestTraversal.chain);
    session.setBtestWrite(true);
    await tester.pump();
    expect(find.text('btest · not started · chain · write'), findsOne);
    expect(BtestSettings.values, settings, reason: 'the switches persist none');

    // A restart: a new session starts from the settings again.
    final again = await pumpComposer(tester, locale: const Locale('en'));
    expect(again.btestTraversal, BtestTraversal.surface);
    expect(again.btestWrite, isFalse);
    expect(find.text('btest · not started · surface · readonly'), findsOne);
  });

  testWidgets('a session starts write-allowed when the default read-only is '
      'off (#37)', (tester) async {
    BtestSettings.values![BtestSettings.readonlyKey] = false;
    final session = await pumpComposer(tester);
    expect(session.btestTraversal, BtestTraversal.surface);
    expect(session.btestWrite, isTrue);
    expect(find.text('btest · 待开始 · 广度 · 允许写'), findsOne);
  });

  testWidgets('picking 深度 writes it back, and the line reads it (#38)', (
    tester,
  ) async {
    final session = await pumpComposer(tester);
    expect(find.text('btest · 待开始 · 广度 · 只读'), findsOne);

    await openSwitch(tester, 'btest-traversal-switch');
    await pick(tester, '深度');
    expect(session.btestTraversal, BtestTraversal.chain);
    expect(find.text('btest · 待开始 · 深度 · 只读'), findsOne);

    await openSwitch(tester, 'btest-write-switch');
    await pick(tester, '允许写');
    expect(session.btestWrite, isTrue);
    expect(find.text('btest · 待开始 · 深度 · 允许写'), findsOne);
  });

  testWidgets('a run reads its own values; a click moves the switch alone '
      '(#38, #40)', (tester) async {
    final session = await pumpComposer(
      tester,
      before: (session) => startRun(stateOf(session)),
    );
    expect(find.text('btest · 航次 · 广度 · 只读 · run 1'), findsOne);

    await openSwitch(tester, 'btest-traversal-switch');
    await pick(tester, '深度');
    expect(
      session.btestTraversal,
      BtestTraversal.chain,
      reason: 'the click moved the switch',
    );
    expect(
      session.btestRun!.traversal,
      BtestTraversal.surface,
      reason: 'this run keeps what it started with',
    );
    expect(
      find.text('btest · 航次 · 广度 · 只读 · run 1'),
      findsOne,
      reason: 'the line reads the run, never the switch',
    );
  });
}
