import 'dart:io';

import 'package:baocode/browser/btest/btest_expect_file.dart';
import 'package:baocode/browser/btest/btest_mode.dart';
import 'package:baocode/browser/browser_bridge.dart' show BrowserError;
import 'package:baocode/host_tools/host_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// The expect file (design §3.3 / §3.4): the index and the SHA-256 a run
// starts with, the write-back reading it ends with, and the way a file
// someone else changed is kept.
void main() {
  late Directory folder;
  late File source;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('btest_expect');
    source = File(p.join(folder.path, 'docs', 'qa', '订舱.md'));
    source.parent.createSync(recursive: true);
    source.writeAsStringSync(
      '# 订舱\n\n'
      '> 环境：dev · 起点：https://x/booking\n\n'
      '## CASE-BKG-001 新建订舱单并提交\n'
      '- source: old\n'
      '- expectFrom: 强 · docs/vibe-coding.md §3.1\n\n'
      '## CASE-BKG-002 改单\n'
      '- source: new\n',
    );
  });

  tearDown(() => folder.deleteSync(recursive: true));

  group('read', () {
    test('gives the case index and the SHA-256 baseline', () {
      final read = BtestExpect.read(source.path);
      expect(read.absent, isFalse);
      expect(read.cases.map((one) => one.id), [
        'CASE-BKG-001',
        'CASE-BKG-002',
      ]);
      expect(read.cases.first.title, '新建订舱单并提交');
      expect(read.hash, BtestExpect.hashOf(read.text));
      expect(read.hash, hasLength(64));
      expect(read.indexText, contains('CASE-BKG-002 改单'));
    });

    test('a missing file is absent, not an error', () {
      final read = BtestExpect.read(p.join(folder.path, 'docs', 'qa', 'x.md'));
      expect(read.absent, isTrue);
      expect(read.hash, isNull);
      expect(read.cases, isEmpty);
      expect(read.indexText, contains('no case yet'));
    });

    test('a fenced example is not a case', () {
      source.writeAsStringSync(
        '## CASE-A-1 real\n'
        '```\n'
        '## CASE-A-2 an example\n'
        '```\n',
      );
      expect(
        BtestExpect.casesOf(source.readAsStringSync()).map((one) => one.id),
        ['CASE-A-1'],
      );
    });

    test('is a SHA-256, as the standard reads', () {
      expect(
        BtestExpect.hashOf('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });

  group('the write-back reading (§3.3, check 1)', () {
    test('created from absent, written after a write, not written without', () {
      final absent = BtestExpect.read(
        p.join(folder.path, 'docs', 'qa', 'new.md'),
      );
      expect(
        BtestExpect.statusOf(baseline: null, now: absent),
        BtestWrite.notWritten,
      );
      final now = BtestExpect.read(source.path);
      expect(BtestExpect.statusOf(baseline: null, now: now), BtestWrite.created);
      expect(
        BtestExpect.statusOf(baseline: now.hash, now: now),
        BtestWrite.notWritten,
      );
      final baseline = now.hash;
      source.writeAsStringSync('${now.text}## CASE-BKG-003 取消\n');
      final after = BtestExpect.read(source.path);
      expect(
        BtestExpect.statusOf(baseline: baseline, now: after),
        BtestWrite.written,
      );
      expect(BtestWrite.written.label, 'written');
      expect(BtestWrite.notWritten.label, 'not written');
    });
  });

  group('a file someone else changed (#8)', () {
    test('is appended to, never overwritten', () {
      final before = source.readAsStringSync();
      final added = BtestExpect.appendRevision(
        source.path,
        body: 'CASE-BKG-001 的预期应与 docs/vibe-coding.md §3.2 对齐',
        at: DateTime(2026, 10, 23),
      );
      final after = source.readAsStringSync();
      expect(after, startsWith(before), reason: 'every line kept');
      expect(added, contains('## 2026-10-23 修订建议'));
      expect(after, contains('## 2026-10-23 修订建议'));
      expect(after, contains('§3.2'));
      expect(after, contains('## CASE-BKG-002 改单'));
    });
  });

  group('the first form (§3.4)', () {
    test('is its header alone, no case guessed', () {
      final skeleton = BtestExpect.skeleton(
        line: '订舱',
        repo: 'v2-booking',
        startUrl: 'https://x/booking',
        env: 'dev',
        role: '货代操作员',
        commitRange: 'abc1234',
        at: DateTime(2026, 10, 23),
      );
      expect(skeleton, startsWith('# 订舱（v2-booking）业务线'));
      expect(skeleton, contains('环境：dev · 起点：https://x/booking'));
      expect(skeleton, contains('角色：货代操作员'));
      expect(skeleton, contains('2026-10-23'));
      expect(skeleton, isNot(contains('## CASE-')));
    });
  });

  group('the path rules (§3.3)', () {
    test('expectFile stays under docs/qa and is relative', () {
      expect(BtestExpect.relativeProblem('docs/qa/订舱.md'), isNull);
      expect(
        BtestExpect.relativeProblem(p.join(folder.path, 'docs', 'qa', 'x.md')),
        contains('relative'),
      );
      expect(
        BtestExpect.relativeProblem('notes/订舱.md'),
        contains('docs/qa/'),
      );
      expect(BtestExpect.relativeProblem('docs/qa/订舱.txt'), contains('.md'));
      expect(BtestExpect.relativeProblem('docs/qa/../x.md'), contains('step out'));
      expect(BtestExpect.resolve('/repo', 'docs/qa/订舱.md'), isNotEmpty);
    });

    test('a folder that is a file cannot hold the file', () {
      final blocker = File(p.join(folder.path, 'blocked'));
      blocker.writeAsStringSync('');
      expect(
        BtestExpect.writableProblem(p.join(blocker.path, 'qa', 'x.md')),
        contains('not a folder'),
      );
      expect(
        BtestExpect.writableProblem(p.join(folder.path, 'docs', 'qa', 'x.md')),
        isNull,
      );
    });
  });

  group('btest_run_end (§3.3, check table)', () {
    const startUrl = 'https://booking.dev.example.com/booking';
    const host = 'booking.dev.example.com';

    late BtestState state;
    late HostToolCall call;
    late Directory repo;

    setUp(() {
      BtestMode.reset();
      BtestSettings.values = {
        BtestSettings.allowHostsKey: [host],
        BtestSettings.prodHostsKey: ['prod.example.com'],
      };
      repo = Directory.systemTemp.createTempSync('btest_end');
      Directory(p.join(repo.path, '.git')).createSync();
      Directory(p.join(repo.path, 'docs', 'qa')).createSync(recursive: true);
      call = HostToolCall(cwd: repo.path, sessionId: '2');
      state = BtestMode.of(repo.path, '2')..on = true;
    });

    tearDown(() {
      BtestMode.reset();
      BtestSettings.values = null;
      repo.deleteSync(recursive: true);
    });

    Future<Map<String, Object?>> begin() async {
      await BtestTools.all.first.run({
        'line': '订舱',
        'repoRoot': repo.path,
        'startUrl': startUrl,
        'env': 'test',
        'mode': 'write',
        'expectFile': 'docs/qa/订舱.md',
        'commitRange': 'abc1234',
      }, call);
      return const {};
    }

    Map<String, Object?> report({
      List<Object?> issues = const [],
      Map<String, Object?> over = const {},
    }) => {
      'runId': state.run!.id,
      'coveredCases': const ['CASE-BKG-001'],
      'issues': issues,
      'blockers': const [],
      'unconfirmedDiffs': const [],
      'uncovered': const [],
      ...over,
    };

    test('all four readings are green once the file is written back (#2)', () async {
      final file = File(p.join(repo.path, 'docs', 'qa', '订舱.md'));
      file.writeAsStringSync(
        '## CASE-BKG-001 新建订舱单并提交\n'
        '- expectFrom: 强 · docs/vibe-coding.md §3.1\n',
      );
      await begin();
      file.writeAsStringSync(
        '## CASE-BKG-001 新建订舱单并提交\n'
        '- expectFrom: 强 · docs/vibe-coding.md §3.1\n'
        '- last: 2026-10-23 pass\n',
      );
      BtestGate.check(
        'browser_navigate',
        {'tabId': 1, 'url': startUrl},
        call,
        hosts: const [host],
        targeted: true,
      );
      final answer = '${await BtestTools.all.last.run(report(
            issues: [
              {
                'caseId': 'CASE-BKG-001',
                'step': '点提交',
                'symptom': '列表无新单',
                'expectRef': '强 · docs/vibe-coding.md §3.1',
              },
            ],
          ), call)}';
      expect(answer, contains('expectFile: written'));
      expect(answer, contains('三尾注字段：blockers / unconfirmedDiffs / uncovered 都在'));
      expect(answer, contains('coveredCases 1/1 在索引'));
      expect(answer, contains('入口=1'));
      expect(answer, contains('操作真实性：'));
      expect(answer, isNot(contains('warning:')), reason: 'nothing missing');
    });

    test('the file not written back is named, and the run still ends (#9)', () async {
      await begin();
      final answer = '${await BtestTools.all.last.run(report(), call)}';
      expect(answer, contains('expectFile: not written'));
      expect(answer, contains('warning: expectFile: not written'));
      expect(state.run, isNull, reason: 'the run is over all the same');
    });

    test('a missing tail key is named', () async {
      await begin();
      final payload = report()..remove('uncovered');
      final answer = '${await BtestTools.all.last.run(payload, call)}';
      expect(answer, contains('缺 uncovered'));
    });

    test('a case outside the index is named', () async {
      await begin();
      final answer = '${await BtestTools.all.last.run(report(
            issues: [
              {'caseId': 'CASE-NOPE-9', 'expectRef': ''},
            ],
          ), call)}';
      expect(answer, contains('not in the index'));
      expect(answer, contains('expectRef is empty'));
    });

    test('a detour in the run without its report line is counted out (§3.3 4-④)', () async {
      await begin();
      BtestGate.check(
        'browser_navigate',
        {'tabId': 1, 'url': startUrl},
        call,
        hosts: const [host],
        targeted: true,
      );
      BtestGate.check(
        'browser_navigate',
        {
          'tabId': 1,
          'url': 'https://booking.dev.example.com/agreement',
          'detour': '无菜单入口',
        },
        call,
        hosts: const [host],
        targeted: true,
      );
      final answer = '${await BtestTools.all.last.run(report(), call)}';
      expect(answer, contains('绕道对账'));
      expect(answer, contains('run 记了 1 条'));
    });

    test('an end without a run, or for another run, is refused', () async {
      Future<String?> said(Future<Object> answer) async {
        try {
          await answer;
          return null;
        } on BrowserError catch (error) {
          return error.message;
        }
      }

      expect(
        await said(
          BtestTools.all.last.run(const {
            'coveredCases': <String>[],
            'issues': <Object?>[],
            'blockers': <Object?>[],
            'unconfirmedDiffs': <Object?>[],
            'uncovered': <Object?>[],
          }, call),
        ),
        contains('no active run'),
      );
      await begin();
      expect(
        await said(
          BtestTools.all.last.run(report(over: {'runId': 'run-9'}), call),
        ),
        contains("is not this session's run"),
      );
    });
  });
}
