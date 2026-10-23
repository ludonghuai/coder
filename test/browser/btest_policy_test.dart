import 'dart:io';

import 'package:baocode/browser/btest/btest_expect_file.dart';
import 'package:baocode/browser/btest/btest_mode.dart';
import 'package:baocode/browser/btest/btest_policy.dart';
import 'package:baocode/browser/browser_bridge.dart' show BrowserError;
import 'package:baocode/host_tools/host_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// btest's gates (design §3.6 / §3.7 / §7): what a browser call may do in a
// run, what a run may start with, and what its end reads back.
void main() {
  const line = '订舱';
  const host = 'booking.dev.example.com';
  const startUrl = 'https://booking.dev.example.com/booking';

  late Directory sandbox;
  late Directory repo;
  late BtestState state;
  late HostToolCall call;

  setUp(() {
    BtestMode.reset();
    BtestSettings.values = {
      BtestSettings.allowHostsKey: [host],
      BtestSettings.prodHostsKey: ['prod.example.com'],
      BtestSettings.readonlyKey: true,
    };
    // A workspace holding one business repository: the QA root is derived
    // under the workspace (§3.4 branch 2), never inside the repository.
    sandbox = Directory.systemTemp.createTempSync('btest_policy');
    repo = Directory(p.join(sandbox.path, 'repo'))..createSync();
    Directory(p.join(repo.path, '.git')).createSync();
    Directory(p.join(sandbox.path, 'qa', 'repo')).createSync(recursive: true);
    File(p.join(sandbox.path, 'qa', 'repo', '订舱.md')).writeAsStringSync(
      '# 订舱\n\n'
      '## CASE-BKG-001 新建订舱单并提交\n'
      '- expectFrom: 强 · docs/vibe-coding.md §3.1\n\n'
      '## CASE-BKG-002 改单\n',
    );
    state = BtestMode.of(sandbox.path, '1')..on = true;
    call = HostToolCall(cwd: sandbox.path, sessionId: '1');
  });

  tearDown(() {
    BtestMode.reset();
    BtestSettings.values = null;
    sandbox.deleteSync(recursive: true);
  });

  BtestRun start({
    BtestFace face = BtestFace.write,
    BtestEnv env = BtestEnv.test,
    List<BtestCase> cases = const [],
  }) => state.start(
    line: line,
    repoRoot: repo.path,
    startUrl: startUrl,
    env: env,
    face: face,
    expectFile: p.join(sandbox.path, 'qa', 'repo', '订舱.md'),
    commitRange: 'abc1234',
    baseline: null,
    cases: cases,
  );

  /// The refusal [tool] with [input] gets, or null when it passes.
  String? refusal(
    String tool,
    Map<String, Object?> input, {
    List<String> hosts = const [host],
    bool targeted = true,
  }) {
    try {
      BtestGate.check(
        tool,
        input,
        call,
        hosts: hosts,
        targeted: targeted,
      );
      return null;
    } on BrowserError catch (error) {
      return error.message;
    }
  }

  /// The refusal [input] gets at `btest_run_start`, or null.
  Future<String?> startRefusal(Map<String, Object?> input) async {
    try {
      await BtestTools.all.first.run(input, call);
      return null;
    } on BrowserError catch (error) {
      return error.message;
    }
  }

  Map<String, Object?> startInput([Map<String, Object?> over = const {}]) => {
    'line': line,
    'repoRoot': repo.path,
    'startUrl': startUrl,
    'env': 'test',
    'mode': 'write',
    'commitRange': 'abc1234',
    ...over,
  };

  group('a browser call in a run', () {
    test('passes on an allowed host, and counts how it aimed (#1, #21)', () {
      start();
      expect(refusal('browser_click', {'tabId': 1, 'text': '提交'}), isNull);
      expect(refusal('browser_click', {
        'tabId': 1,
        'ref': 12,
      }), isNull);
      expect(state.run!.wordsTargets, 1);
      expect(state.run!.fallbackTargets, 1);
    });

    test('a read-only run lets the reading tools through (#3)', () {
      start(face: BtestFace.readonly);
      for (final tool in ['browser_snapshot', 'browser_network', 'browser_tabs']) {
        expect(
          refusal(tool, {'tabId': 1}),
          isNull,
          reason: '$tool only reads',
        );
      }
    });

    test('a read-only run refuses a click, naming readonly (F5)', () {
      start(face: BtestFace.readonly);
      final said = refusal('browser_click', {'tabId': 1, 'text': '提交'});
      expect(said, contains('mode: readonly'));
      expect(state.run!.denied, 1);
    });

    test('evaluate in a read-only run needs readOnly: true (#4, #5)', () {
      start(face: BtestFace.readonly);
      expect(
        refusal('browser_evaluate', {'tabId': 1, 'expression': 'document.title'}),
        contains('readOnly: true'),
      );
      expect(
        refusal('browser_evaluate', {
          'tabId': 1,
          'expression': 'document.title',
          'readOnly': true,
        }),
        isNull,
      );
    });

    test('a script that writes is refused in every face (#19)', () {
      start(face: BtestFace.write);
      final said = refusal('browser_evaluate', {
        'tabId': 1,
        'expression': "document.querySelector('#a').value='1'",
      });
      expect(said, contains('may not write values from a script'));
      expect(state.run!.scriptsDenied, 1, reason: '4-② counts it');
      expect(
        refusal('browser_evaluate', {
          'tabId': 1,
          'expression': 'document.querySelector("#a").value',
          'readOnly': true,
        }),
        isNull,
        reason: 'reading the bound value is legal',
      );
    });

    test('a write run refuses a production host (#6, #15)', () {
      // Allowed and production at once: env: test does not exempt it.
      BtestSettings.values = {
        BtestSettings.allowHostsKey: [host, 'prod.example.com'],
        BtestSettings.prodHostsKey: ['prod.example.com'],
      };
      start();
      final said = refusal(
        'browser_click',
        {'tabId': 1, 'text': '提交'},
        hosts: const ['prod.example.com'],
      );
      expect(said, contains('production host'));
    });

    test('prodHosts empty refuses writes, naming the setting (#14)', () {
      BtestSettings.values = {
        BtestSettings.allowHostsKey: [host],
        BtestSettings.prodHostsKey: const <String>[],
        BtestSettings.readonlyKey: true,
      };
      start();
      final said = refusal('browser_click', {'tabId': 1, 'text': '提交'});
      expect(said, contains('prodHosts is empty'));
    });

    test('a host outside allowHosts is refused; empty refuses all (#) ', () {
      start();
      expect(
        refusal(
          'browser_snapshot',
          {'tabId': 1},
          hosts: const ['other.example.com'],
        ),
        contains('not in btest.allowHosts'),
      );
      BtestSettings.values = {
        BtestSettings.allowHostsKey: const <String>[],
        BtestSettings.prodHostsKey: ['prod.example.com'],
      };
      expect(
        refusal('browser_snapshot', {'tabId': 1}),
        contains('allowHosts is empty'),
      );
    });

    test('an unknown host is refused, not let through (#3.7)', () {
      start();
      expect(
        refusal('browser_snapshot', {'tabId': 1}, hosts: const []),
        contains('target host is unknown'),
      );
      expect(
        refusal('browser_tabs', {'tabId': 1}, hosts: const [], targeted: false),
        isNull,
        reason: 'no target to judge',
      );
    });

    test('without a run every browser call is refused (#7)', () {
      expect(
        refusal('browser_snapshot', {'tabId': 1}),
        contains('btest_run_start'),
      );
    });

    test('a session without btest is untouched ()', () {
      state.on = false;
      expect(
        refusal('browser_click', {'tabId': 1, 'text': '提交'}),
        isNull,
        reason: 'btest is not on: nothing of it applies',
      );
    });
  });

  group('the entry (§3.6.2)', () {
    test('the first one must be the run startUrl (#17 前段)', () {
      start();
      expect(
        refusal('browser_navigate', {
          'tabId': 1,
          'url': 'https://booking.dev.example.com/other',
        }),
        contains('startUrl'),
      );
      expect(
        refusal('browser_navigate', {'tabId': 1, 'url': '$startUrl/'}),
        isNull,
        reason: 'a trailing slash is not a different entry',
      );
      expect(state.run!.entries.single.tool, 'browser_navigate');
    });

    test('a second one without detour is refused (#17)', () {
      start();
      refusal('browser_navigate', {'tabId': 1, 'url': startUrl});
      final said = refusal('browser_navigate', {
        'tabId': 1,
        'url': 'https://booking.dev.example.com/agreement',
      });
      expect(said, contains('detour'));
      expect(state.run!.entriesDenied, 1);
      expect(state.run!.entries.length, 1);
    });

    test('a second one with detour passes and is recorded (#18)', () {
      start();
      refusal('browser_navigate', {'tabId': 1, 'url': startUrl});
      const detour = '货代协议案无菜单入口，只能手输 URL';
      expect(
        refusal('browser_navigate', {
          'tabId': 1,
          'url': 'https://booking.dev.example.com/agreement',
          'detour': detour,
        }),
        isNull,
      );
      expect(state.run!.detours.single.detour, detour);
      expect(state.run!.entries.length, 2);
      // §3.8's line: one declared entry, the detour read apart (入口=1 …
      // 绕道=1), so a legal detour is not reported as a second entry.
      expect(state.run!.truthLine, contains('入口=1（navigate=1'));
      expect(state.run!.truthLine, contains('绕道=1'));
    });

    test('browser_act navigate steps and browser_open count too (KD-17)', () {
      start();
      expect(
        refusal('browser_open', {'url': startUrl}),
        isNull,
        reason: 'the first entry may come from browser_open',
      );
      expect(
        refusal('browser_act', {
          'tabId': 1,
          'steps': [
            {'action': 'navigate', 'url': 'https://booking.dev.example.com/x'},
          ],
        }),
        contains('detour'),
        reason: 'a navigate step is an entry, and none carries a detour',
      );
      expect(state.run!.entries.length, 1);
    });

    test('back, forward and reload are not entries', () {
      start();
      for (final action in ['back', 'forward', 'reload']) {
        expect(refusal('browser_navigate', {'tabId': 1, 'action': action}), isNull);
      }
      expect(state.run!.entries, isEmpty);
    });

    test('browser_act from a file is refused: its steps cannot be judged', () {
      start();
      expect(
        refusal('browser_act', {'tabId': 1, 'file': 'scripts/steps.json'}),
        contains('cannot be judged'),
      );
      expect(
        refusal('browser_act', {
          'tabId': 1,
          'steps': [
            {'action': 'click', 'text': '提交'},
          ],
        }),
        isNull,
        reason: 'inline steps are judged one by one',
      );
    });

    test('a blank url is refused, not silently no entry', () {
      start();
      expect(
        refusal('browser_navigate', {'tabId': 1, 'url': '   '}),
        contains('url is empty'),
      );
    });

    test('replay is refused as bypassing the form (#20)', () {
      start();
      expect(
        refusal('browser_request', {'tabId': 1, 'id': '7', 'replay': true}),
        contains('replay is refused'),
      );
      expect(
        refusal('browser_request', {'tabId': 1, 'id': '7', 'as': 'curl'}),
        isNull,
        reason: 'reading it as a command is fine',
      );
    });
  });

  group('the state map (§3.1)', () {
    test('two conversations without ids never share a state', () {
      final a = BtestMode.of(repo.path, null);
      final b = BtestMode.of(repo.path, null);
      expect(identical(a, b), isFalse);
      a.on = true;
      expect(b.on, isFalse, reason: 'one conversation\'s mode is its own');
      expect(
        BtestMode.find(repo.path, null),
        isNull,
        reason: 'two anonymous states cannot be told apart',
      );
    });

    test("binding one keeper does not take another one's key", () {
      final a = BtestMode.of(repo.path, 'A');
      final b = BtestMode.of(repo.path, 'B');
      expect(identical(a, b), isFalse);
      BtestMode.bind(a, cwd: repo.path, sessionId: 'A');
      BtestMode.bind(b, cwd: repo.path, sessionId: 'B');
      expect(BtestMode.find(repo.path, 'A'), same(a));
      expect(BtestMode.find(repo.path, 'B'), same(b));
    });
  });

  group('btest_run_start (§3.3)', () {
    test('a session without btest cannot start one (#12)', () async {
      state.on = false;
      expect(await startRefusal(startInput()), contains('not on in this session'));
    });

    test('env: prod with mode: write is refused (rule A, #13)', () async {
      final said = await startRefusal(startInput({'env': 'prod'}));
      expect(said, contains('rule A'));
      expect(said, contains('env: prod'));
      expect(state.run, isNull, reason: 'no run is made');
    });

    test('a missing or illegal field is named (#10)', () async {
      expect(
        await startRefusal(startInput({'repoRoot': ''})),
        contains('repoRoot'),
      );
      expect(
        await startRefusal(startInput({'line': ''})),
        contains('line is required'),
      );
      expect(
        await startRefusal(startInput({'line': '订舱/x'})),
        contains('business-line name'),
      );
      expect(
        await startRefusal(startInput({'startUrl': 'not a url'})),
        contains('startUrl'),
      );
      expect(
        await startRefusal(startInput({'repoRoot': '${repo.path}-missing'})),
        contains('not a folder'),
      );
    });

    test('returns the run, the derived path, the case index and the hash', () async {
      final answer = '${await BtestTools.all.first.run(startInput(), call)}';
      final file = File(p.join(sandbox.path, 'qa', 'repo', '订舱.md'));
      expect(answer, contains('Case index (2)'));
      expect(answer, contains('CASE-BKG-001'));
      expect(answer, contains('新建订舱单并提交'));
      expect(answer, contains(BtestExpect.hashOf(file.readAsStringSync())!));
      expect(answer, contains('2. expectFile（解析后的绝对路径）: ${file.path}'));
      expect(answer, contains('来源=工作区根'));
      expect(answer, contains('先读 ${file.path}'));
      expect(state.run, isNotNull);
    });

    test('a host typed as a URL is read as its host', () {
      // What someone pastes into the field: the gate compares bare hosts, so a
      // URL kept as typed would look configured and never match.
      expect(BtestSettings.listOf('https://v2-dev.navnova.com/'), [
        'v2-dev.navnova.com',
      ]);
      expect(BtestSettings.listOf('v2-dev.navnova.com, https://x.example/a'), [
        'v2-dev.navnova.com',
        'x.example',
      ]);
      expect(BtestSettings.hostsOf(['https://navnova.51marine.com/']), {
        'navnova.51marine.com',
      });
      expect(BtestSettings.listOf('   '), isNull);
    });

    test('a second run while one is open is refused', () async {
      await BtestTools.all.first.run(startInput(), call);
      expect(await startRefusal(startInput()), contains('still open'));
    });
  });
}
