import 'dart:io';

import 'package:baocode/browser/btest/btest_expect_file.dart';
import 'package:baocode/browser/btest/btest_mode.dart';
import 'package:baocode/browser/browser_bridge.dart' show BrowserError;
import 'package:baocode/host_tools/host_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// The expect file (design §3.3 / §3.4): the index and the SHA-256 a run
// starts with, the write-back reading it ends with, the way a file someone
// else changed is kept, and where the file goes — the QA root's four
// branches, never inside the business repository.
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

  group('the QA root (§3.4: four branches)', () {
    late Directory workspace;
    late String repoRoot;

    setUp(() {
      workspace = Directory.systemTemp.createTempSync('btest_qa');
      // The workspace holds repos/v2-booking; repos2 is a same-prefix
      // sibling and must never read as "below the workspace".
      repoRoot = p.join(workspace.path, 'repos', 'v2-booking');
      Directory(p.join(repoRoot, '.git')).createSync(recursive: true);
    });

    tearDown(() => workspace.deleteSync(recursive: true));

    ({BtestQaRoot? root, String? problem}) resolve({
      String? configured,
      String? cwd,
      String? repo,
    }) => BtestQaRoot.resolve(
      repoRoot: repo ?? repoRoot,
      cwd: cwd ?? p.join(workspace.path, 'repos'),
      configured: configured,
      setting: BtestSettings.qaRootKey,
    );

    test('branch 1: a configured root is used as it is (#25)', () {
      final configured = p.join(workspace.path, 'elsewhere', 'qa');
      final answer = resolve(configured: configured);
      expect(answer.problem, isNull);
      expect(answer.root!.root, p.normalize(configured));
      expect(answer.root!.source, BtestQaSource.setting);
      expect(answer.root!.source.label, '设置值');
      expect(answer.root!.reason, isNull);
    });

    test('branch 1: a configured root inside the repository is used and named', () {
      final inside = resolve(configured: p.join(repoRoot, 'qa'));
      expect(inside.root!.root, p.join(repoRoot, 'qa'));
      expect(inside.root!.reason, 'QA 根在业务仓内');
      expect(
        resolve(configured: repoRoot).root!.reason,
        'QA 根在业务仓内',
        reason: 'the repository itself is inside the repository',
      );
    });

    test('branch 1: a root that is not absolute is refused by name', () {
      final answer = resolve(configured: p.join('qa', 'nested'));
      expect(answer.root, isNull);
      expect(answer.problem, contains('btest.qaRoot'));
      expect(answer.problem, contains('absolute'));
      expect(answer.problem, contains('nested'));
    });

    test('branch 2: a repository below the workspace gives <workspace>/qa (#24)', () {
      final answer = resolve();
      expect(answer.root!.root, p.join(workspace.path, 'repos', 'qa'));
      expect(answer.root!.source, BtestQaSource.workspace);
      expect(answer.root!.source.label, '工作区根');
      expect(answer.root!.reason, isNull);
      expect(
        answer.root!.fileOf(repoRoot, '订舱'),
        p.join(workspace.path, 'repos', 'qa', 'v2-booking', '订舱.md'),
      );
    });

    test('branch 2: nested repositories of one workspace share a root (#26)', () {
      final nested = p.join(workspace.path, 'repos', 'clientA', 'v2-timecharter');
      final one = resolve().root!;
      final other = resolve(repo: nested).root!;
      expect(one.root, p.join(workspace.path, 'repos', 'qa'));
      expect(one.root, other.root);
      expect(
        other.fileOf(nested, '船期'),
        p.join(workspace.path, 'repos', 'qa', 'v2-timecharter', '船期.md'),
      );
    });

    test('branch 2 is strict and by path segment: repos2 is not below repos', () {
      final sibling = p.join(workspace.path, 'repos2', 'v2-booking');
      final answer = resolve(repo: sibling);
      expect(answer.root!.root, p.join(workspace.path, 'repos2', 'qa'));
      expect(answer.root!.source, BtestQaSource.parentFallback);
      expect(answer.root!.reason, '仓在工作区根之外');
    });

    test('branch 3: a workspace that is the repository falls to its parent (#27)', () {
      final answer = resolve(cwd: repoRoot);
      expect(answer.root!.root, p.join(workspace.path, 'repos', 'qa'));
      expect(answer.root!.source, BtestQaSource.parentFallback);
      expect(answer.root!.source.label, '父目录兜底');
      expect(answer.root!.reason, '工作区根即业务仓');
      expect(
        p.isWithin(repoRoot, answer.root!.fileOf(repoRoot, '订舱')),
        isFalse,
        reason: 'the file is never written into the repository',
      );
    });

    test('branch 4: a workspace root that is not known falls back and says so', () {
      for (final cwd in ['.', '', 'relative/folder']) {
        final answer = resolve(cwd: cwd);
        expect(answer.root!.root, p.join(workspace.path, 'repos', 'qa'));
        expect(answer.root!.source, BtestQaSource.parentFallback);
        expect(answer.root!.reason, '工作区根不可得', reason: 'cwd=$cwd');
      }
    });

    test('branch 4: a remote workspace root is named as one', () {
      final answer = resolve(cwd: 'ssh://host/home/xinbo/repos');
      expect(answer.root!.reason, '工作区根是远端位置');
      expect(answer.root!.source, BtestQaSource.parentFallback);
    });

    test('branch 4: a repository outside the workspace falls back', () {
      final outside = p.join(workspace.path, 'other', 'v2-booking');
      final answer = resolve(repo: outside);
      expect(answer.root!.root, p.join(workspace.path, 'other', 'qa'));
      expect(answer.root!.reason, '仓在工作区根之外');
    });

    test('the business line is a name, never a path', () {
      expect(BtestExpect.lineProblem('订舱'), isNull);
      expect(BtestExpect.lineProblem(' 订舱 '), isNull);
      expect(BtestExpect.lineProblem(null), contains('required'));
      expect(BtestExpect.lineProblem(''), contains('required'));
      expect(BtestExpect.lineProblem('   '), contains('required'));
      expect(BtestExpect.lineProblem('订舱/x'), contains('business-line name'));
      expect(BtestExpect.lineProblem(r'订舱\x'), contains('business-line name'));
    });
  });

  group('btest_run_start (§3.3 · §3.4)', () {
    const startUrl = 'https://booking.dev.example.com/booking';
    const host = 'booking.dev.example.com';

    late Directory sandbox;
    late Directory repo;
    late BtestState state;
    late HostToolCall call;

    setUp(() {
      BtestMode.reset();
      BtestSettings.values = {
        BtestSettings.allowHostsKey: [host],
        BtestSettings.prodHostsKey: ['prod.example.com'],
      };
      sandbox = Directory.systemTemp.createTempSync('btest_start');
      repo = Directory(p.join(sandbox.path, 'repo'))..createSync();
      Directory(p.join(repo.path, '.git')).createSync();
      state = BtestMode.of(sandbox.path, '2')..on = true;
      call = HostToolCall(cwd: sandbox.path, sessionId: '2');
    });

    tearDown(() {
      BtestMode.reset();
      BtestSettings.values = null;
      sandbox.deleteSync(recursive: true);
    });

    Map<String, Object?> input([Map<String, Object?> over = const {}]) => {
      'line': '订舱',
      'repoRoot': repo.path,
      'startUrl': startUrl,
      'env': 'test',
      'mode': 'write',
      'commitRange': 'abc1234',
      ...over,
    };

    Future<Object> begin([Map<String, Object?> over = const {}]) =>
        BtestTools.all.first.run(input(over), call);

    void useQaRoot(String root) => BtestSettings.values = {
      ...BtestSettings.values!,
      BtestSettings.qaRootKey: root,
    };

    test('branch 2: the workspace root gives <workspace>/qa, and the folder is made (#24)', () async {
      final file = p.join(sandbox.path, 'qa', 'repo', '订舱.md');
      final answer = '${await begin()}';
      expect(answer, contains('2. expectFile（解析后的绝对路径）: $file'));
      expect(answer, contains('来源=工作区根'));
      expect(answer, isNot(contains('降级原因')));
      expect(Directory(p.dirname(file)).existsSync(), isTrue);
      expect(Directory(p.join(sandbox.path, 'qa', 'repo', '.git')).existsSync(),
          isFalse, reason: 'no repository is initialized');
      expect(Directory(p.join(sandbox.path, 'qa', '.git')).existsSync(), isFalse);
      expect(
        Directory(p.join(repo.path, 'qa')).existsSync(),
        isFalse,
        reason: 'the business repository is never written into',
      );
    });

    test('branch 1: a configured root is used, and the path returned is absolute (#25)', () async {
      final root = p.join(sandbox.path, 'configured', 'qa');
      useQaRoot(root);
      final file = p.join(root, 'repo', '订舱.md');
      final answer = '${await begin()}';
      expect(answer, contains('2. expectFile（解析后的绝对路径）: $file'));
      expect(answer, contains('来源=设置值'));
      expect(state.run!.expectFile, file,
          reason: 'the run reads and writes the returned path, nothing else');
      expect(Directory(p.dirname(file)).existsSync(), isTrue);
      expect(Directory(p.join(root, '.git')).existsSync(), isFalse);
    });

    test('branch 1: a root inside the repository is used and named', () async {
      useQaRoot(p.join(repo.path, 'qa'));
      final answer = '${await begin()}';
      expect(answer, contains('来源=设置值'));
      expect(answer, contains('降级原因=QA 根在业务仓内'));
    });

    test('branch 1: a root that is not absolute refuses the run by name', () async {
      useQaRoot(p.join('qa', 'nested'));
      await expectLater(
        begin(),
        throwsA(
          isA<BrowserError>().having(
            (error) => error.message,
            'message',
            allOf(contains('btest.qaRoot'), contains('absolute')),
          ),
        ),
      );
      expect(state.run, isNull, reason: 'no run is made');
    });

    test('branch 3: a workspace that is the repository falls to its parent (#27)', () async {
      call = HostToolCall(cwd: repo.path, sessionId: '3');
      state = BtestMode.of(repo.path, '3')..on = true;
      final file = p.join(sandbox.path, 'qa', 'repo', '订舱.md');
      final answer = '${await begin()}';
      expect(answer, contains('2. expectFile（解析后的绝对路径）: $file'));
      expect(answer, contains('来源=父目录兜底'));
      expect(answer, contains('降级原因=工作区根即业务仓'));
      expect(
        Directory(p.join(repo.path, 'qa')).existsSync(),
        isFalse,
        reason: 'the repository keeps no qa/ folder of its own',
      );
    });

    test('branch 4: a workspace root of "." falls back and says so', () async {
      call = HostToolCall(cwd: '.', sessionId: '4');
      state = BtestMode.of('.', '4')..on = true;
      final file = p.join(sandbox.path, 'qa', 'repo', '订舱.md');
      final answer = '${await begin()}';
      expect(answer, contains('2. expectFile（解析后的绝对路径）: $file'));
      expect(answer, contains('来源=父目录兜底'));
      expect(answer, contains('降级原因=工作区根不可得'));
      expect(
        Directory(p.dirname(file)).existsSync(),
        isTrue,
        reason: 'the fallback place is resolved, never a relative one',
      );
    });

    test('two nested repositories of one workspace get one QA root (#26)', () async {
      final nested = Directory(p.join(sandbox.path, 'clientA', 'v2-timecharter'))
        ..createSync(recursive: true);
      Directory(p.join(nested.path, '.git')).createSync();
      final one = '${await begin()}';
      state.end();
      final other = '${await begin({'repoRoot': nested.path, 'line': '船期'})}';
      expect(
        one,
        contains('2. expectFile（解析后的绝对路径）: '
            '${p.join(sandbox.path, 'qa', 'repo', '订舱.md')}'),
      );
      expect(
        other,
        contains('2. expectFile（解析后的绝对路径）: '
            '${p.join(sandbox.path, 'qa', 'v2-timecharter', '船期.md')}'),
      );
      expect(one, contains('来源=工作区根'));
      expect(other, contains('来源=工作区根'));
    });

    test('a folder that cannot be made refuses the run, naming qaRoot (#28)', () async {
      final blocker = File(p.join(sandbox.path, 'blocked'))
        ..writeAsStringSync('');
      final root = p.join(blocker.path, 'qa');
      useQaRoot(root);
      try {
        await begin();
        fail('the run must be refused');
      } on BrowserError catch (error) {
        expect(error.message, contains('qaRoot'));
        expect(error.message, contains(root));
        expect(error.message, contains('cannot be created'));
      }
      expect(state.run, isNull, reason: 'no run is made');
    });
  });

  group('btest_run_end (§3.3, check table)', () {
    const startUrl = 'https://booking.dev.example.com/booking';
    const host = 'booking.dev.example.com';

    late Directory sandbox;
    late Directory repo;
    late BtestState state;
    late HostToolCall call;

    String expectPath(Directory sandbox) =>
        p.join(sandbox.path, 'qa', 'repo', '订舱.md');

    setUp(() {
      BtestMode.reset();
      BtestSettings.values = {
        BtestSettings.allowHostsKey: [host],
        BtestSettings.prodHostsKey: ['prod.example.com'],
      };
      sandbox = Directory.systemTemp.createTempSync('btest_end');
      repo = Directory(p.join(sandbox.path, 'repo'))..createSync();
      Directory(p.join(repo.path, '.git')).createSync();
      File(expectPath(sandbox))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '## CASE-BKG-001 新建订舱单并提交\n'
          '- expectFrom: 强 · docs/vibe-coding.md §3.1\n',
        );
      call = HostToolCall(cwd: sandbox.path, sessionId: '2');
      state = BtestMode.of(sandbox.path, '2')..on = true;
    });

    tearDown(() {
      BtestMode.reset();
      BtestSettings.values = null;
      sandbox.deleteSync(recursive: true);
    });

    Future<Map<String, Object?>> begin() async {
      await BtestTools.all.first.run({
        'line': '订舱',
        'repoRoot': repo.path,
        'startUrl': startUrl,
        'env': 'test',
        'mode': 'write',
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
      final file = File(expectPath(sandbox));
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
      expect(answer, contains(expectPath(sandbox)));
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
