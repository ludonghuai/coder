import 'package:baocode/browser/btest/btest_mode.dart';
import 'package:baocode/browser/btest/btest_policy.dart';
import 'package:baocode/browser/btest/btest_tool_gate.dart';
import 'package:baocode/browser/browser_bridge.dart' show BrowserError;
import 'package:baocode/host_tools/host_tools.dart';
import 'package:flutter_test/flutter_test.dart';

// The btest gate every browser tool call passes (§3.4 / §3.7), as the
// browser library wires it: which hosts the call targets (the entry urls it
// names, else the page the tab is on), the exempt pair, and a session with
// btest off passing untouched. The policy's own rules are
// `btest_policy_test.dart`; the refusals here are checked for naming the
// tool and the gate it did not meet, never only for the happy path.
void main() {
  const cwd = '/project';
  const session = '1';
  const allowed = 'booking.dev.example.com';
  const startUrl = 'https://booking.dev.example.com/booking';

  late HostToolCall call;
  late List<int> asked;

  setUp(() {
    BtestMode.reset();
    BtestSettings.values = {
      BtestSettings.allowHostsKey: [allowed],
      BtestSettings.prodHostsKey: ['prod.example.com'],
      BtestSettings.readonlyKey: true,
    };
    call = const HostToolCall(cwd: cwd, sessionId: session);
    asked = [];
  });

  tearDown(() {
    BtestMode.reset();
    BtestSettings.values = null;
  });

  /// The state a session's btest leaves: on, and with a run started when
  /// [run] is true.
  void open({
    bool on = true,
    bool run = true,
    BtestFace face = BtestFace.write,
  }) {
    final state = BtestMode.of(cwd, session)..on = on;
    if (!run) return;
    state.start(
      line: '订舱',
      repoRoot: '/repos/v2-timecharter',
      startUrl: startUrl,
      env: BtestEnv.test,
      face: face,
      traversal: BtestTraversal.surface,
      scenarios: const [
        (id: 'S1', scenario: '提交订舱', role: '货代操作员', pre: '已登录', branch: '主路径'),
      ],
      expectFile: '/qa/v2-timecharter/订舱.md',
      qaRoot: '/qa',
      baseline: null,
      cases: const [],
      commitRange: 'abc1234',
    );
  }

  /// The page a tab is on, as the browser library answers it; counted, so a
  /// call that must not ask can say so.
  Future<String?> tabHost(int tabId) async {
    asked.add(tabId);
    return switch (tabId) {
      5 => allowed,
      6 => 'evil.example.com',
      _ => null,
    };
  }

  /// The refusal [tool]'s call gets, or null when it passes.
  Future<String?> refusal(String tool, Map<String, Object?> input) async {
    try {
      await BtestToolGate.check(tool, input, call, tabHost: tabHost);
      return null;
    } on BrowserError catch (error) {
      return error.message;
    }
  }

  test(
    'a session with btest off passes untouched, and no tab is asked',
    () async {
      open(on: false);
      expect(await refusal('browser_click', {'tabId': 5, 'ref': 1}), isNull);
      expect(
        await refusal('browser_evaluate', {'tabId': 5, 'expression': 'x'}),
        isNull,
      );
      expect(asked, isEmpty, reason: 'the gate is not part of a plain session');
    },
  );

  test(
    'btest on with no run refuses, naming the tool and the run gate',
    () async {
      open(run: false);
      final message = await refusal('browser_click', {'tabId': 5});
      expect(message, contains('browser_click'));
      expect(message, contains('no active run'));
      expect(message, contains('btest_run_start'));
    },
  );

  test('the two tools that start and end a run pass without one', () async {
    open(run: false);
    expect(
      await refusal('btest_run_start', {'line': '订舱'}),
      isNull,
      reason: 'otherwise a run could never start (§3.3)',
    );
    expect(await refusal('btest_run_end', {'runId': 'run-1'}), isNull);
  });

  test(
    'the host an entry url names is the one judged, and the refusal names it',
    () async {
      open();
      final message = await refusal('browser_navigate', {
        'tabId': 5,
        'url': 'https://evil.example.com/x',
      });
      expect(message, contains('browser_navigate'));
      expect(message, contains('evil.example.com'));
      expect(
        message,
        contains('startUrl'),
        reason: 'the unmet gate is the run entry, not the allow list',
      );
      expect(asked, isEmpty, reason: 'an entry url needs no tab lookup');
    },
  );

  test(
    'with no url, the page its tab is on decides; an allowed host passes',
    () async {
      open();
      expect(
        await refusal('browser_click', {'tabId': 5, 'ref': 1}),
        isNull,
        reason: 'the tab is on a host the user allowed',
      );
      expect(asked, [5]);
    },
  );

  test(
    'a tab on a host not allowed is refused, naming the tool and the host',
    () async {
      open();
      final message = await refusal('browser_click', {'tabId': 6, 'ref': 1});
      expect(message, contains('browser_click'));
      expect(message, contains('evil.example.com'));
      expect(message, contains('btest.allowHosts'));
    },
  );

  test('a tab whose page is not known is refused, not let through', () async {
    open();
    final message = await refusal('browser_click', {'tabId': 7, 'ref': 1});
    expect(message, contains('browser_click'));
    expect(message, contains('target host is unknown'));
  });

  test(
    'a readonly run takes a reading script and refuses a writing one',
    () async {
      open(face: BtestFace.readonly);
      expect(
        await refusal('browser_evaluate', {
          'tabId': 5,
          'expression': 'document.title',
          'readOnly': true,
        }),
        isNull,
      );
      final message = await refusal('browser_evaluate', {
        'tabId': 5,
        'expression': 'document.title',
      });
      expect(message, contains('browser_evaluate'));
      expect(message, contains('readOnly'));
    },
  );

  test('a tool with no tab id is judged without a host', () async {
    open();
    expect(await refusal('browser_tabs', {}), isNull);
    expect(asked, isEmpty);
  });
}
