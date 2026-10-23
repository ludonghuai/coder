import 'dart:io';

import 'package:baocode/browser/btest/btest_expect_file.dart';
import 'package:baocode/browser/btest/btest_mode.dart';
import 'package:baocode/browser/btest/btest_policy.dart';
import 'package:baocode/browser/btest/btest_run_state.dart';
import 'package:baocode/browser/browser_bridge.dart' show BrowserError;
import 'package:baocode/host_tools/host_tools.dart';
import 'package:baocode/platform/data_dir.dart';
import 'package:baocode/settings/user_settings.dart';
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
    BtestTraversal traversal = BtestTraversal.surface,
    List<BtestCase> cases = const [],
  }) => state.start(
    line: line,
    repoRoot: repo.path,
    startUrl: startUrl,
    env: env,
    face: face,
    traversal: traversal,
    expectFile: p.join(sandbox.path, 'qa', 'repo', '订舱.md'),
    qaRoot: p.join(sandbox.path, 'qa'),
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

    test('a detour on the first entry is not read as one (入口=1)', () {
      start();
      expect(
        refusal('browser_navigate', {
          'tabId': 1,
          'url': startUrl,
          'detour': 'no defect on the first entry',
        }),
        isNull,
      );
      expect(state.run!.declared.length, 1);
      expect(state.run!.detours, isEmpty);
      expect(state.run!.truthLine(noVisibleText: 0), contains('入口=1'));
      expect(state.run!.truthLine(noVisibleText: 0), contains('绕道=0'));
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
      expect(state.run!.truthLine(noVisibleText: 0), contains('入口=1（navigate=1'));
      expect(state.run!.truthLine(noVisibleText: 0), contains('绕道=1'));
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

  group('traversal (§3.9)', () {
    test('absent means surface, and the run says so (#31)', () async {
      final answer = '${await BtestTools.all.first.run(startInput(), call)}';
      expect(state.run!.traversal, BtestTraversal.surface);
      expect(answer, contains('traversal=surface'));
    });

    test('chain is taken and returned (#29)', () async {
      final answer = '${await BtestTools.all.first.run(
        startInput({'traversal': 'chain'}),
        call,
      )}';
      expect(state.run!.traversal, BtestTraversal.chain);
      expect(answer, contains('traversal=chain'));
    });

    test('an illegal value is refused, naming it and both values (#32)', () async {
      final said = await startRefusal(startInput({'traversal': 'depth'}));
      expect(said, contains('traversal'));
      expect(said, contains('chain'));
      expect(said, contains('surface'));
      expect(state.run, isNull, reason: 'no run is made');
    });

    test('the weights table is built and returned (§3.3, item 6, #33)', () async {
      final answer = '${await BtestTools.all.first.run(startInput(), call)}';
      final table = File(p.join(sandbox.path, 'qa', 'weights.md'));
      expect(table.existsSync(), isTrue);
      expect(answer, contains('6. weights（历史缺陷密度表）: ${table.path}'));
      expect(answer, contains('来源=file'));
      expect(answer, contains('生效序：刷新 / 数据丢失 → 报错 / 异常'));
      expect(answer, isNot(contains('warning:')), reason: 'first build is file');
    });
  });

  group('the two switches (§9.1 · §3.3)', () {
    test('point the run when the call says nothing (§7 #35)', () async {
      state.traversal = BtestTraversal.chain;
      state.write = false; // The write switch reads 只读.
      final answer = '${await BtestTools.all.first.run(
        startInput({'mode': null, 'traversal': null}),
        call,
      )}';
      expect(state.run!.traversal, BtestTraversal.chain);
      expect(state.run!.face, BtestFace.readonly);
      expect(answer, contains('traversal=chain'));
      expect(answer, contains('mode=readonly'));
      expect(
        refusal('browser_click', {'tabId': 1, 'text': '提交'}),
        contains('mode: readonly'),
      );
      expect(
        state.run!.truthLine(noVisibleText: 0),
        contains('traversal=chain · mode=readonly'),
      );
    });

    test('a switch never picked reads the setting (§3.3, tier 3)', () async {
      final answer = '${await BtestTools.all.first.run(
        startInput({'mode': null, 'traversal': null}),
        call,
      )}';
      expect(state.run!.traversal, BtestTraversal.surface);
      expect(
        state.run!.face,
        BtestFace.readonly,
        reason: 'btest.readonly is on by default',
      );
      expect(answer, contains('traversal=surface'));
      expect(answer, contains('mode=readonly'));
      state.end();
      BtestSettings.values![BtestSettings.readonlyKey] = false;
      await BtestTools.all.first.run(
        startInput({'mode': null, 'traversal': null}),
        call,
      );
      expect(
        state.run!.face,
        BtestFace.write,
        reason: 'the default read-only is off',
      );
    });

    test('the call overrides both; the switches keep their values (§7 #36)', () async {
      state.traversal = BtestTraversal.surface;
      state.write = true; // 允许写
      final answer = '${await BtestTools.all.first.run(
        startInput({'traversal': 'chain', 'mode': 'readonly'}),
        call,
      )}';
      expect(state.run!.traversal, BtestTraversal.chain);
      expect(state.run!.face, BtestFace.readonly);
      expect(answer, contains('traversal=chain'));
      expect(answer, contains('mode=readonly'));
      expect(state.traversal, BtestTraversal.surface, reason: 'the switch');
      expect(state.write, isTrue, reason: 'the switch');
      expect(
        state.run!.truthLine(noVisibleText: 0),
        contains('traversal=chain · mode=readonly'),
      );
      expect(
        refusal('browser_click', {'tabId': 1, 'text': '提交'}),
        contains('mode: readonly'),
      );
    });

    test('rule A judges the resolved mode: a switch-derived write in prod (§7 #39)', () async {
      state.write = true;
      final said = await startRefusal(startInput({'env': 'prod', 'mode': null}));
      expect(said, contains('env: prod'));
      expect(said, contains('mode: write'));
      expect(said, contains('写开关'), reason: 'an implied write says where it came from');
      expect(state.run, isNull, reason: 'no run is made');
    });

    test('rule A names a setting-derived write too (§7 #39)', () async {
      BtestSettings.values![BtestSettings.readonlyKey] = false;
      final said = await startRefusal(startInput({'env': 'prod', 'mode': null}));
      expect(said, contains('env: prod'));
      expect(said, contains('mode: write'));
      expect(said, contains('设置'));
      expect(state.run, isNull, reason: 'no run is made');
    });

    test('a prod run that resolves to readonly starts (§7 #35)', () async {
      final answer = '${await BtestTools.all.first.run(
        startInput({'env': 'prod', 'mode': null}),
        call,
      )}';
      expect(state.run!.face, BtestFace.readonly);
      expect(answer, contains('mode=readonly'));
    });

    test('a write run the switch set lets a click through (§7 #35)', () async {
      state.write = true; // 允许写
      await BtestTools.all.first.run(
        startInput({'mode': null, 'traversal': null}),
        call,
      );
      expect(state.run!.face, BtestFace.write);
      expect(
        refusal('browser_click', {'tabId': 1, 'text': '提交'}),
        isNull,
        reason: 'the switch set the write face; rule B still lets it through',
      );
    });
  });

  group('the three keys (§9.1, F11)', () {
    test('the picks write their keys, and a new state reads them back (#43)', () async {
      state.on = true;
      state.traversal = BtestTraversal.chain;
      state.write = true;
      expect(BtestSettings.values![BtestSettings.onKey], isTrue);
      expect(BtestSettings.values![BtestSettings.traversalKey], 'chain');
      expect(BtestSettings.values![BtestSettings.modeKey], 'write');

      // A restart: the state is made again and takes the three keys.
      BtestMode.reset();
      final again = BtestMode.of(sandbox.path, '1')..fromSettings();
      expect(again.on, isTrue);
      expect(again.traversal, BtestTraversal.chain);
      expect(again.write, isTrue);
      expect(again.writePicked, isTrue, reason: 'btest.mode was there');

      // A run that says nothing takes both switches (§3.3's priority).
      final answer = '${
        await BtestTools.all.first.run(
          startInput({'mode': null, 'traversal': null}),
          call,
        )
      }';
      expect(again.run!.traversal, BtestTraversal.chain);
      expect(again.run!.face, BtestFace.write);
      expect(answer, contains('traversal=chain'));
      expect(answer, contains('mode=write'));
    });

    test('missing or illegal keys fall back, and reading writes none (#44)', () {
      final keys = BtestSettings.values!
        ..remove(BtestSettings.onKey)
        ..remove(BtestSettings.traversalKey)
        ..remove(BtestSettings.modeKey);
      BtestMode.reset();
      final fresh = BtestMode.of(sandbox.path, '44')..fromSettings();
      expect(fresh.on, isFalse);
      expect(fresh.traversal, BtestTraversal.surface);
      expect(fresh.write, isFalse, reason: 'btest.readonly is on');
      expect(fresh.writePicked, isFalse);
      expect(keys.keys, isNot(contains(BtestSettings.onKey)),
          reason: 'opening a conversation writes none');
      expect(keys.keys, isNot(contains(BtestSettings.traversalKey)));
      expect(keys.keys, isNot(contains(BtestSettings.modeKey)));

      // Illegal values read as the key's absence, and are left as they are.
      keys[BtestSettings.onKey] = 'yes';
      keys[BtestSettings.traversalKey] = 'depth';
      keys[BtestSettings.modeKey] = 'maybe';
      final again = BtestMode.of(sandbox.path, '44b')..fromSettings();
      expect(again.on, isFalse);
      expect(again.traversal, BtestTraversal.surface);
      expect(again.write, isFalse);
      expect(again.writePicked, isFalse);
      expect(keys[BtestSettings.onKey], 'yes', reason: 'not rewritten');
      expect(keys[BtestSettings.traversalKey], 'depth');
      expect(keys[BtestSettings.modeKey], 'maybe');
    });

    test('leaving btest removes the key; a restart is off (#45)', () {
      final keys = BtestSettings.values!;
      final live = BtestMode.of(sandbox.path, '45')..fromSettings();
      live.on = true;
      expect(keys[BtestSettings.onKey], isTrue);
      live.on = false;
      expect(keys.containsKey(BtestSettings.onKey), isFalse,
          reason: 'the key is removed, not set false');
      final again = BtestMode.of(sandbox.path, '45b')..fromSettings();
      expect(again.on, isFalse, reason: 'no old true is read back');
    });

    test('the three keys reach settings.json itself, and a removal takes it out', () async {
      final data = Directory.systemTemp.createTempSync('btest-keys');
      final files = SettingsFiles(DataDirectory(data.path));
      addTearDown(() {
        SettingsFiles.instance = SettingsFiles(DataDirectory.current);
        files.dispose();
        data.deleteSync(recursive: true);
      });
      SettingsFiles.instance = files;
      await files.settings.load();
      // No injected values: the write path is the file itself (§9.1).
      BtestSettings.values = null;
      final live = BtestMode.of(data.path, 'f')..fromSettings();
      live.on = true;
      live.traversal = BtestTraversal.chain;
      live.write = true;
      // A read queued behind the three writes: they have landed by now.
      await files.settings.load();
      expect(files.settings[BtestSettings.onKey], isTrue);
      expect(files.settings[BtestSettings.traversalKey], 'chain');
      expect(files.settings[BtestSettings.modeKey], 'write');

      live.on = false;
      await files.settings.load();
      expect(
        files.settings.values.containsKey(BtestSettings.onKey),
        isFalse,
        reason: 'leaving btest deletes the key',
      );

      // A new state reads the file back.
      final again = BtestMode.of(data.path, 'f2')..fromSettings();
      expect(again.on, isFalse);
      expect(again.traversal, BtestTraversal.chain);
      expect(again.write, isTrue);
    });
  });

  group('btest_run_end payload checks (§3.3)', () {
    Map<String, Object?> report([Map<String, Object?> over = const {}]) => {
      'runId': state.run!.id,
      'coveredCases': const <String>[],
      'issues': const <Object?>[],
      'blockers': const <Object?>[],
      'unconfirmedDiffs': const <Object?>[],
      'uncovered': const <Object?>[],
      'noVisibleText': const <Object?>[],
      ...over,
    };

    Future<Object> end([Map<String, Object?> over = const {}]) =>
        BtestTools.all.last.run(report(over), call);

    test('a chain round sends chainBreaks; empty is fine (#30)', () async {
      await BtestTools.all.first.run(
        startInput({'traversal': 'chain'}),
        call,
      );
      final answer = '${await end({'chainBreaks': const <Object?>[]})}';
      expect(answer, contains('chainBreaks 0 条，四字段齐'));
      expect(answer, isNot(contains('chainBreaks is missing')));
    });

    test('a break missing a field, or with a bad reason, is named (#30)', () async {
      await BtestTools.all.first.run(
        startInput({'traversal': 'chain'}),
        call,
      );
      final answer = '${await end({
        'chainBreaks': [
          {
            'path': '首页 → 详情',
            'at': '审核',
            'reason': '门控',
            'verified': '打开了详情',
          },
          {'path': '首页', 'at': '提交', 'reason': '想不出', 'verified': ''},
        ],
      })}';
      expect(answer, contains('chainBreaks[2].verified is empty'));
      expect(answer, contains('chainBreaks[2].reason "想不出"'));
      expect(answer, isNot(contains('chainBreaks[1].')), reason: 'the first is whole');
    });

    test('a surface round needs no chainBreaks key', () async {
      await BtestTools.all.first.run(startInput(), call);
      final answer = '${await end()}';
      expect(answer, isNot(contains('chainBreaks')));
    });

    test('the head line carries traversal, mode and both reconciled readings (§3.8, 4-②③)', () async {
      await BtestTools.all.first.run(startInput(), call);
      final answer = '${await end()}';
      expect(
        answer,
        contains('traversal=surface · mode=write · 操作真实性：入口=0'
            '（navigate=0 · open=0 · 被拒=0）'),
      );
      expect(answer, contains('replay 放行=0/被拒=0'));
      expect(answer, contains('无可见文字=0'));
    });

    test('a fallback aim without its noVisibleText line is named (4-③)', () async {
      await BtestTools.all.first.run(startInput(), call);
      BtestGate.check(
        'browser_click',
        {'tabId': 1, 'ref': 3},
        call,
        hosts: const [host],
        targeted: true,
      );
      final answer = '${await end()}';
      expect(answer, contains('无可见文字对账'));
      expect(answer, contains('兜底 1 次'));
    });

    test('replay refusals are counted apart (4-②)', () async {
      await BtestTools.all.first.run(startInput(), call);
      expect(
        refusal('browser_request', {'tabId': 1, 'id': '7', 'replay': true}),
        contains('replay'),
      );
      expect(state.run!.replayDenied, 1);
      final answer = '${await end()}';
      expect(answer, contains('replay 放行=0/被拒=1'));
      expect(answer, contains('replay 被拒 1 次'));
    });

    test('two pending items keep their case and kind (#34)', () async {
      await BtestTools.all.first.run(startInput(), call);
      final answer = '${await end({
        'unconfirmedDiffs': [
          {
            'kind': 'pending',
            'caseId': 'CASE-BKG-001',
            'step': '点审核',
            'symptom': '状态未变',
            'expectRef': '弱 · docs/x.md §1',
          },
          {
            'kind': 'pending',
            'caseId': 'CASE-BKG-002',
            'step': '点保存',
            'symptom': '列表未刷新',
            'expectRef': '无权威来源',
          },
        ],
      })}';
      expect(answer, contains('unconfirmedDiffs 2 条，caseId 与 kind 都在'));
      expect(answer, isNot(contains('kind must be')));
    });

    test('a diff with an unknown kind is named', () async {
      await BtestTools.all.first.run(startInput(), call);
      final answer = '${await end({
        'unconfirmedDiffs': [
          {'kind': 'maybe', 'caseId': 'CASE-BKG-001'},
        ],
      })}';
      expect(answer, contains('kind must be diff or pending'));
    });

    test('a payload field of the wrong type is named, not thrown', () async {
      await BtestTools.all.first.run(startInput(), call);
      final answer = '${await end({'issues': 'nope'})}';
      expect(answer, contains('issues is not a list'));
    });

    test('a break with its cause keeps its shape; reason still four (§7 #41)', () async {
      await BtestTools.all.first.run(startInput({'traversal': 'chain'}), call);
      final answer = '${await end({
        'chainBreaks': [
          {
            'path': '首页 → 订舱详情',
            'at': '点编辑',
            'reason': '无权限',
            'verified': '详情页打开了',
            'cause': '详情页编辑入口被角色权限挡住 · repo/lib/booking/detail.dart:88',
          },
        ],
      })}';
      expect(answer, contains('chainBreaks 1 条，四字段齐'));
      expect(answer, isNot(contains('cause is empty')));
      expect(answer, isNot(contains('cause must be')));
      expect(answer, isNot(contains('.reason "')), reason: 'reason is unchanged');
    });

    test('a cause that stands must say something; left out is fine (§7 #41)', () async {
      await BtestTools.all.first.run(startInput({'traversal': 'chain'}), call);
      final without = '${await end({
        'chainBreaks': [
          {
            'path': '首页',
            'at': '列表底',
            'reason': '没有下一步',
            'verified': '翻到最后一页',
          },
        ],
      })}';
      expect(without, contains('chainBreaks 1 条，四字段齐'));
      await BtestTools.all.first.run(startInput({'traversal': 'chain'}), call);
      final blank = '${await end({
        'chainBreaks': [
          {
            'path': '首页',
            'at': '审核',
            'reason': '门控',
            'verified': '打开了列表',
            'cause': '   ',
          },
        ],
      })}';
      expect(blank, contains('chainBreaks[1].cause is empty'));
    });

    test('four breaks close the run, the capped one judged like any (§7 #42)', () async {
      // The cap itself (3 subagents per run, then 未查明（达到本轮研判上限）)
      // is the card's discipline, not a host rule (design §3.3, check 2:
      // shape only) — btest_card_test holds the card to it. Here the host is
      // held to what it can judge: four breaks, causes shaped, run closes.
      await BtestTools.all.first.run(startInput({'traversal': 'chain'}), call);
      Map<String, Object?> breakAt(String at, String reason, [String? cause]) => {
        'path': '首页 → 详情 → $at',
        'at': at,
        'reason': reason,
        'verified': '上一步打开了 $at',
        'cause': ?cause,
      };
      final answer = '${await end({
        'chainBreaks': [
          breakAt('审核', '门控', '审核页在 dev 未开放 · repo/lib/booking/audit.dart:41'),
          breakAt('放单', '无权限', '放单入口只给调度员 · repo/lib/booking/release.dart:88'),
          breakAt('导出', '数据不足', '详情缺柜号，导出不渲染 · repo/lib/booking/export.dart:12'),
          breakAt('签收', '没有下一步', '未查明（达到本轮研判上限）'),
        ],
      })}';
      expect(answer, contains('chainBreaks 4 条，四字段齐'));
      expect(answer, isNot(contains('cause is empty')));
      expect(state.run, isNull, reason: 'the run closes as usual');
    });
  });
}
