import 'dart:io';

import 'package:baocode/browser/btest/btest_mode.dart';
import 'package:baocode/browser/browser_bridge.dart' show BrowserError;
import 'package:baocode/host_tools/host_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// The close-out gate (design §3.3.1, cases #49–#60): a report answers every
// declared scenario and every legal case before the same run may close.
void main() {
  const line = '订舱';
  const host = 'booking.dev.example.com';
  const startUrl = 'https://booking.dev.example.com/booking';

  late Directory sandbox;
  late Directory repo;
  late File expectFile;
  late BtestState state;
  late HostToolCall call;

  void writeExpect(String text) => expectFile.writeAsStringSync(text);

  setUp(() {
    BtestMode.reset();
    BtestSettings.values = {
      BtestSettings.allowHostsKey: [host],
      BtestSettings.prodHostsKey: ['prod.example.com'],
      BtestSettings.readonlyKey: true,
    };
    sandbox = Directory.systemTemp.createTempSync('btest_run_end');
    repo = Directory(p.join(sandbox.path, 'repo'))..createSync();
    Directory(p.join(repo.path, '.git')).createSync();
    expectFile = File(p.join(sandbox.path, 'qa', 'repo', '$line.md'))
      ..parent.createSync(recursive: true);
    writeExpect(
      [
        for (final id in const ['CASE-001', 'CASE-002', 'CASE-003'])
          '## $id 既有用例\n'
              '- origin: 无（存量）\n'
              '- expectFrom: 强 · docs/vibe-coding.md §3.1\n',
      ].join('\n'),
    );
    state = BtestMode.of(sandbox.path, '1')..on = true;
    call = HostToolCall(cwd: sandbox.path, sessionId: '1');
  });

  tearDown(() {
    BtestMode.reset();
    BtestSettings.values = null;
    sandbox.deleteSync(recursive: true);
  });

  List<Map<String, Object?>> declarations(int count) => [
    for (var i = 1; i <= count; i++)
      {
        'scenario': '场景 $i',
        'role': '角色 $i',
        'pre': '初始状态 $i',
        'branch': '分支 $i',
      },
  ];

  Map<String, Object?> startInput({Object? scenarios = sentinel}) => {
    'line': line,
    'repoRoot': repo.path,
    'startUrl': startUrl,
    'env': 'test',
    'mode': 'write',
    'commitRange': 'abc1234',
    if (!identical(scenarios, sentinel)) 'scenarios': scenarios,
  };

  Future<String> start({int count = 1, Object? scenarios}) async {
    final input = startInput(scenarios: scenarios ?? declarations(count));
    return '${await BtestTools.all.first.run(input, call)}';
  }

  Map<String, Object?> issue(
    String caseId, [
    Map<String, Object?> over = const {},
  ]) => {
    'caseId': caseId,
    'step': '点提交',
    'symptom': '状态未推进',
    'evidence': const {'kind': 'field', 'readout': '提交前=待审核；提交后=待审核'},
    'severity': '高',
    'pre': '已登录；无草稿',
    'expectRef': '强 · docs/vibe-coding.md §3.1',
    ...over,
  };

  Map<String, Object?> report([Map<String, Object?> over = const {}]) => {
    'runId': state.run!.id,
    'coveredCases': [for (final one in state.run!.cases) one.id],
    'issues': const <Object?>[],
    'scenarioResults': [
      for (final one in state.run!.scenarios)
        {'id': one.id, 'verdict': 'pass', 'evidence': '证据 ${one.id}'},
    ],
    'blockers': const <Object?>[],
    'unconfirmedDiffs': const <Object?>[],
    'uncovered': const <Object?>[],
    'noVisibleText': const <Object?>[],
    ...over,
  };

  Future<String> end([Map<String, Object?> over = const {}]) async =>
      '${await BtestTools.all.last.run(report(over), call)}';

  Future<String> refusal(Future<Object> Function() action) async {
    try {
      await action();
      fail('the call must be refused');
    } on BrowserError catch (error) {
      return error.message;
    }
  }

  test('run_start requires and freezes the declared scenario matrix', () async {
    var said = await refusal(
      () => BtestTools.all.first.run(startInput(scenarios: []), call),
    );
    expect(said, contains('scenarios must be a non-empty array'));
    expect(state.run, isNull);

    final blank = declarations(2)..[1]['role'] = '  ';
    said = await refusal(
      () => BtestTools.all.first.run(startInput(scenarios: blank), call),
    );
    expect(said, contains('scenarios[2].role is empty'));
    expect(state.run, isNull);

    final answer = await start(count: 2);
    expect(answer, contains('S1 · 场景=场景 1 · 角色=角色 1'));
    expect(answer, contains('S2 · 场景=场景 2 · 角色=角色 2'));
    expect(state.run!.scenarios.map((one) => one.id), ['S1', 'S2']);
  });

  test(
    '#49 three declared pass rows close and become the report first block',
    () async {
      await start(count: 3);
      final answer = await end();
      expect(answer, contains('报告首块（声明场景矩阵）'));
      expect(
        answer,
        contains('| S3 | 场景 3 | 角色 3 | 初始状态 3 | 分支 3 | pass | 证据 S3 |'),
      );
      expect(answer, contains('收尾检查表（四项机械读数'));
      expect(state.run, isNull);
    },
  );

  test(
    '#50 zero coverage plus zero issues refuses without closing; retry passes',
    () async {
      await start();
      final id = state.run!.id;
      final said = await refusal(
        () => BtestTools.all.last.run(
          report({'coveredCases': const <Object?>[]}),
          call,
        ),
      );
      expect(said, contains('R1 空轮：零覆盖 + 零 issue'));
      expect(state.run?.id, id);
      final answer = await end();
      expect(answer, contains('btest $id closed'));
      expect(state.run, isNull);
    },
  );

  test('#51 every missing issue field is listed in one refusal', () async {
    await start();
    final said = await refusal(
      () => BtestTools.all.last.run(
        report({
          'issues': [
            issue('CASE-001', {'pre': ''}),
            issue('CASE-002', {'step': '', 'severity': ''}),
          ],
        }),
        call,
      ),
    );
    expect(said, contains('issues[1].pre'));
    expect(said, contains('issues[2].step'));
    expect(said, contains('issues[2].severity'));
    expect(state.run, isNotNull);
  });

  test(
    '#52 missing, unknown, duplicate and malformed scenario rows list together',
    () async {
      await start(count: 3);
      final said = await refusal(
        () => BtestTools.all.last.run(
          report({
            'scenarioResults': [
              {'id': 'S1', 'verdict': 'pass', 'evidence': ' '},
              {'id': 'S2', 'verdict': 'ok'},
              {'id': 'S9', 'verdict': 'pass', 'evidence': 'x'},
              {'id': 'S1', 'verdict': 'pass', 'evidence': 'x'},
            ],
          }),
          call,
        ),
      );
      expect(said, contains('lacks declared scenario S3'));
      expect(said, contains('id "S9" is unknown'));
      expect(said, contains('id "S1" is duplicated'));
      expect(
        said,
        contains('verdict must be pass / fail / blocked / uncovered'),
      );
      expect(said, contains('scenarioResults[1].evidence is empty'));
    },
  );

  test(
    '#53 an index case needs coverage or a reasoned uncovered row',
    () async {
      await start();
      final covered = ['CASE-001', 'CASE-002'];
      final said = await refusal(
        () => BtestTools.all.last.run(report({'coveredCases': covered}), call),
      );
      expect(said, contains('R4 case CASE-003'));
      expect(state.run, isNotNull);
      final answer = await end({
        'coveredCases': covered,
        'uncovered': [
          {'caseId': 'CASE-003', 'branch': '改单', 'why': '缺账号'},
        ],
      });
      expect(answer, contains('closed'));
    },
  );

  test('#54 a fail scenario without its issue is refused', () async {
    await start();
    final said = await refusal(
      () => BtestTools.all.last.run(
        report({
          'scenarioResults': [
            {
              'id': 'S1',
              'verdict': 'fail',
              'evidence': '提交后状态未推进',
              'caseId': 'CASE-001',
            },
          ],
        }),
        call,
      ),
    );
    expect(said, contains('R5'));
    expect(said, contains('S1'));
    expect(said, contains('CASE-001'));
    expect(state.run, isNotNull);
  });

  test(
    '#55 zero issues with a reasoned blocked row is honest and passes',
    () async {
      await start(count: 2);
      final answer = await end({
        'scenarioResults': [
          {'id': 'S1', 'verdict': 'pass', 'evidence': '证据 S1'},
          {
            'id': 'S2',
            'verdict': 'blocked',
            'why': '无第二个角色账号，本轮未验',
            'evidence': '不应替代阻塞原因',
          },
        ],
      });
      expect(
        answer,
        contains(
          '| S2 | 场景 2 | 角色 2 | 初始状态 2 | 分支 2 | blocked | 无第二个角色账号，本轮未验 |',
        ),
      );
      expect(answer, isNot(contains('不应替代阻塞原因')));
      expect(state.run, isNull);
    },
  );

  test(
    '#56 an R2 refusal consumes nothing; the same run closes after repair',
    () async {
      await start();
      final id = state.run!.id;
      final failing = {
        'issues': [
          issue('CASE-001', {'symptom': ''}),
        ],
        'scenarioResults': [
          {
            'id': 'S1',
            'verdict': 'fail',
            'evidence': '证据 S1',
            'caseId': 'CASE-001',
          },
        ],
      };
      final said = await refusal(
        () => BtestTools.all.last.run(report(failing), call),
      );
      expect(said, contains('R2 issues[1].symptom is empty'));
      expect(state.run?.id, id);
      final answer = await end({
        'issues': [issue('CASE-001')],
        'scenarioResults': failing['scenarioResults']!,
      });
      expect(answer, contains('btest $id closed'));
      expect(answer, contains('收尾检查表（四项机械读数'));
    },
  );

  test(
    '#57 a same-round new case is a legal covered and issue reference',
    () async {
      await start();
      expectFile.writeAsStringSync(
        '${expectFile.readAsStringSync()}\n'
        '## CASE-004 本轮新缺陷\n'
        '- origin: 本轮新发现\n'
        '- expectFrom: 强 · docs/vibe-coding.md §3.1\n',
      );
      final answer = await end({
        'coveredCases': ['CASE-001', 'CASE-002', 'CASE-003', 'CASE-004'],
        'issues': [issue('CASE-004')],
        'scenarioResults': [
          {
            'id': 'S1',
            'verdict': 'fail',
            'evidence': '证据 CASE-004',
            'caseId': 'CASE-004',
          },
        ],
      });
      expect(answer, contains('closed'));
      expect(answer, isNot(contains('not in the index')));
      expect(state.run, isNull);
    },
  );

  test('#58 a new case must carry origin and expectFrom before closing', () async {
    await start();
    expectFile.writeAsStringSync(
      '${expectFile.readAsStringSync()}\n'
      '## CASE-005 本轮新缺陷\n'
      '- expectFrom: 强 · docs/vibe-coding.md §3.1\n',
    );
    final payload = {
      'coveredCases': ['CASE-001', 'CASE-002', 'CASE-003', 'CASE-005'],
      'issues': [issue('CASE-005')],
      'scenarioResults': [
        {
          'id': 'S1',
          'verdict': 'fail',
          'evidence': '证据 CASE-005',
          'caseId': 'CASE-005',
        },
      ],
    };
    var said = await refusal(
      () => BtestTools.all.last.run(report(payload), call),
    );
    expect(said, contains('CASE-005 lacks origin'));
    expect(state.run, isNotNull);

    final text = expectFile.readAsStringSync();
    final field = text.lastIndexOf(
      '- expectFrom: 强 · docs/vibe-coding.md §3.1',
    );
    expect(field, greaterThan(0));
    expectFile.writeAsStringSync(
      text.replaceRange(
        field,
        field + '- expectFrom: 强 · docs/vibe-coding.md §3.1'.length,
        '- origin: 本轮新发现',
      ),
    );
    said = await refusal(() => BtestTools.all.last.run(report(payload), call));
    expect(said, contains('CASE-005 lacks expectFrom'));
    expect(state.run, isNotNull);

    expectFile.writeAsStringSync(
      '${expectFile.readAsStringSync()}- expectFrom: 强 · docs/vibe-coding.md §3.1\n',
    );
    final answer = await end(payload);
    expect(answer, contains('closed'));
  });

  test('#59 an existing weights file is neither read into the report nor rewritten', () async {
    final table = File(p.join(sandbox.path, 'qa', 'weights.md'))
      ..writeAsStringSync('# offline audit material\nnot a runtime table\n');
    final before = table.readAsBytesSync();
    final opened = await start();
    expect(opened, isNot(contains('weights')));
    expect(opened, isNot(contains('权重表')));
    final closed = await end();
    expect(closed, isNot(contains('weights')));
    expect(closed, isNot(contains('权重表')));
    expect(closed, contains('收尾检查表（四项机械读数'));
    expect(table.readAsBytesSync(), before);
  });

  test(
    '#60 pass, fail and uncovered rows reconcile with the issue line',
    () async {
      await start(count: 3);
      final answer = await end({
        'issues': [issue('CASE-002')],
        'scenarioResults': [
          {'id': 'S1', 'verdict': 'pass', 'evidence': '证据 S1'},
          {
            'id': 'S2',
            'verdict': 'fail',
            'evidence': '证据 S2',
            'caseId': 'CASE-002',
          },
          {'id': 'S3', 'verdict': 'uncovered', 'why': '缺账号'},
        ],
      });
      expect(
        answer,
        contains('| S1 | 场景 1 | 角色 1 | 初始状态 1 | 分支 1 | pass | 证据 S1 |'),
      );
      expect(
        answer,
        contains(
          '| S2 | 场景 2 | 角色 2 | 初始状态 2 | 分支 2 | fail | 证据 S2 · 问题行 #1 |',
        ),
      );
      expect(
        answer,
        contains('| S3 | 场景 3 | 角色 3 | 初始状态 3 | 分支 3 | uncovered | 缺账号 |'),
      );
      expect(state.run, isNull);
    },
  );

  test('scenario report cells escape pipes and flatten line breaks', () async {
    await start(
      scenarios: [
        {
          'scenario': '场景|一\n下',
          'role': '角色|二',
          'pre': '初始|三',
          'branch': '分支|四',
        },
      ],
    );
    final answer = await end({
      'scenarioResults': [
        {'id': 'S1', 'verdict': 'pass', 'evidence': '证据|五\n六'},
      ],
    });
    expect(
      answer,
      contains(r'| S1 | 场景\|一 下 | 角色\|二 | 初始\|三 | 分支\|四 | pass | 证据\|五 六 |'),
    );
  });
}

const sentinel = Object();
