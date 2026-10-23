/// Closing a run (design §3.3): `btest_run_end`'s five checks and the
/// payload helpers they read with. Split out of `btest_mode.dart` by
/// SPLIT-5 — the tool's schema and description stay there, the checks and
/// their readings live here.
library;

import 'dart:io';

import '../../host_tools/host_tools.dart';
import '../browser_bridge.dart' show BrowserError;
import 'btest_expect_file.dart';
import 'btest_mode.dart';
import 'btest_policy.dart';
import 'btest_run_state.dart' show BtestRun, btestText;
import 'btest_weights.dart';

/// `btest_run_end` (§3.3): checks the payload against the run — the expect
/// file written back, the tail and break keys, the coverage, what the run
/// counted, the weights table — closes the run and hands back the readings
/// the report is headed with.
Future<Object> btestEndRun(
  Map<String, Object?> input,
  HostToolCall call,
) async {
  final state = BtestMode.find(call.cwd, call.sessionId);
  if (state == null || !state.on) {
    throw const BrowserError(
      'btest_run_end refused: btest is not on in this session',
    );
  }
  final run = state.run;
  if (run == null) {
    throw const BrowserError(
      'btest_run_end refused: no active run in this session',
    );
  }
  final said = btestText(input['runId']);
  if (said != null && said != run.id) {
    throw BrowserError(
      'btest_run_end refused: "$said" is not this session\'s run '
      '(${run.id})',
    );
  }

  final checks = <String>[];
  final warnings = <String>[];

  // 1. The expect file, against the baseline run_start took.
  var write = BtestWrite.notWritten;
  var unreadable = false;
  try {
    final now = BtestExpect.read(run.expectFile);
    write = BtestExpect.statusOf(baseline: run.baseline, now: now);
  } on FileSystemException catch (error) {
    unreadable = true;
    warnings.add(
      'expectFile: not written — ${error.message.isEmpty ? error.osError : error.message}',
    );
  }
  checks.add(
    '1. 预期文件写回：expectFile: ${write.label}（${run.expectFile}；'
    '基线 ${run.baseline == null ? 'absent' : _short(run.baseline!)}）',
  );
  if (!unreadable && write == BtestWrite.notWritten) {
    warnings.add(
      'expectFile: not written — write it back before btest_run_end '
      '(design §3.4)',
    );
  }

  // 2. The three tail sections' keys; a chain round's breaks too.
  final missing = [
    for (final key in ['blockers', 'unconfirmedDiffs', 'uncovered'])
      if (input[key] is! List) key,
  ];
  final chain = _chainBreaks(run, input['chainBreaks']);
  checks.add(
    '2. 尾注与断点键：${missing.isEmpty ? 'blockers / unconfirmedDiffs / '
              'uncovered 都在' : '缺 ${missing.join(' / ')}'}${chain.text}',
  );
  if (missing.isNotEmpty) {
    warnings.add(
      'the payload lacks ${missing.join(', ')} — an empty array is fine, '
      'the key must be there',
    );
  }
  warnings.addAll(chain.problems);

  // 3. The coverage, against the index run_start returned.
  final index = {for (final one in run.cases) one.id};
  final coveredInput = input['coveredCases'];
  final covered = [
    if (coveredInput is List)
      for (final id in coveredInput) '$id',
  ];
  final outside = [
    for (final id in covered)
      if (!index.contains(id)) id,
  ];
  final issuesInput = input['issues'];
  if (input.containsKey('issues') && issuesInput is! List) {
    warnings.add(
      'issues is not a list — an empty array is fine, the field must be one',
    );
  }
  final issues = [
    if (issuesInput is List)
      for (final issue in issuesInput)
        if (issue is Map) issue.cast<String, Object?>(),
  ];
  final unpointed = <String>[];
  for (final (i, issue) in issues.indexed) {
    final caseId = btestText(issue['caseId']);
    if (caseId == null) {
      unpointed.add('issues[${i + 1}].caseId is empty');
    } else if (!index.contains(caseId)) {
      unpointed.add('issues[${i + 1}].caseId "$caseId" is not in the index');
    }
    if (btestText(issue['expectRef']) == null) {
      unpointed.add('issues[${i + 1}].expectRef is empty');
    }
  }
  // The pending items (§3.10): the run never judges them, but each must
  // point at a case and say whether it is a diff or a pending rule.
  final diffsInput = input['unconfirmedDiffs'];
  final diffs = [
    if (diffsInput is List)
      for (final diff in diffsInput)
        if (diff is Map) diff.cast<String, Object?>(),
  ];
  final unconfirmed = <String>[];
  for (final (i, diff) in diffs.indexed) {
    if (btestText(diff['caseId']) == null) {
      unconfirmed.add('unconfirmedDiffs[${i + 1}].caseId is empty');
    }
    final kind = btestText(diff['kind']);
    if (kind == null || !_diffKinds.contains(kind)) {
      unconfirmed.add(
        'unconfirmedDiffs[${i + 1}].kind must be diff or pending, not '
        '"${kind ?? ''}"',
      );
    }
  }
  checks.add(
    '3. 覆盖对账：coveredCases ${covered.length - outside.length}/'
    '${covered.length} 在索引；issues ${issues.length} 条，'
    '${unpointed.isEmpty ? 'caseId 与 expectRef 都在' : '${unpointed.length} 处不合格'}；'
    'unconfirmedDiffs ${diffs.length} 条，'
    '${unconfirmed.isEmpty ? 'caseId 与 kind 都在' : '${unconfirmed.length} 处不合格'}',
  );
  if (coveredInput is! List) {
    warnings.add(
      'coveredCases is not a list — the field is required (an empty array '
      'is fine)',
    );
  }
  if (outside.isNotEmpty) {
    warnings.add(
      'coveredCases: ${outside.join(', ')} not in the run\'s case index',
    );
  }
  warnings.addAll(unpointed);
  warnings.addAll(unconfirmed);

  // 4. What the run itself counted. 入口 is the declared entry alone; a
  // detour is a legal entry and is read apart (§3.8).
  final declared = run.declared;
  if (declared.isEmpty) {
    warnings.add('入口=0 — the run did not enter by its startUrl '
        '(${run.startUrl})');
  } else if (!BtestPolicy.sameUrl(declared.first.url, run.startUrl)) {
    warnings.add(
      '入口=${declared.first.url} is not the run\'s startUrl '
      '(${run.startUrl})',
    );
  }
  if (run.scriptsDenied > 0) {
    warnings.add(
      'evaluate 写值被拒 ${run.scriptsDenied} 次 — that is the reading of '
      'a script trying to write, not a pass',
    );
  }
  if (run.replayDenied > 0) {
    warnings.add(
      'replay 被拒 ${run.replayDenied} 次 — that is the reading of a script '
      'bypassing the form, not a pass',
    );
  }
  final detoured = [
    for (final issue in issues)
      if (btestText(issue['detour']) != null) issue,
  ];
  if (run.detours.length != detoured.length) {
    warnings.add(
      '绕道对账：run 记了 ${run.detours.length} 条，报告绕道行 '
      '${detoured.length} 条（差 ${(run.detours.length - detoured.length).abs()}）',
    );
  }
  // 4-③'s reconcile: the run's fallback count is what the payload's
  // noVisibleText[] and the report's 无可见文字 rows must both read.
  final noVisibleInput = input['noVisibleText'];
  final noVisible = [
    if (noVisibleInput is List) for (final one in noVisibleInput) one,
  ];
  if (run.fallbackTargets != noVisible.length) {
    warnings.add(
      '无可见文字对账：ref/selector 兜底 ${run.fallbackTargets} 次，'
      'noVisibleText 记了 ${noVisible.length} 条'
      '（差 ${(run.fallbackTargets - noVisible.length).abs()}）',
    );
  }
  checks.add('4. ${run.truthLine(noVisibleText: noVisible.length)}');

  // 5. The weights table (§3.9): on disk with its eight classes, and every
  // `已修` marker naming a class the table holds.
  final weights = BtestWeights.check(run.qaRoot);
  final String weightText;
  if (weights.problem case final problem?) {
    weightText = problem;
  } else if (weights.missing.isNotEmpty) {
    weightText = '缺类目 ${weights.missing.join(' / ')}（类目不得删）';
  } else {
    weightText = '${BtestWeights.pathOf(run.qaRoot)} 在盘，八类齐';
  }
  checks.add('5. 权重表：$weightText');
  if (weights.problem case final problem?) {
    warnings.add('权重表：$problem');
  }
  if (weights.missing.isNotEmpty) {
    warnings.add(
      '权重表缺类目 ${weights.missing.join(' / ')} — 类目不得删（§3.9）',
    );
  }
  warnings.addAll(weights.warnings);

  state.end();
  return [
    'btest ${run.id} closed.',
    '收尾检查表（五项机械读数；第 4 项即报告头一行）：',
    ...checks,
    if (warnings.isNotEmpty) ...[
      '',
      for (final warning in warnings) 'warning: $warning',
    ],
    '',
    '报告头：${run.truthLine(noVisibleText: noVisible.length)}',
  ].join('\n');
}

/// The kinds an `unconfirmedDiffs` entry may take (§3.3, check 3): a diff
/// between runs, or a rule the user still has to rule on.
const _diffKinds = {'diff', 'pending'};

/// Check 2's chain half (§3.3): a chain run sends `chainBreaks` (an empty
/// array is fine), and every break's four fields are filled, its reason one
/// of the four named ones. `cause` is optional (§3.9): absent when no
/// subagent was sent, and when it stands it must say something — the host
/// judges the shape alone, never whether the conclusion is true. A surface
/// run needs none.
({String text, List<String> problems}) _chainBreaks(
  BtestRun run,
  Object? value,
) {
  if (run.traversal != BtestTraversal.chain) {
    return (text: '', problems: const []);
  }
  if (value is! List) {
    return (
      text: '；chainBreaks 缺键（chain 轮必带，可为空数组）',
      problems: const [
        'chainBreaks is missing — a chain run sends the key, even as []',
      ],
    );
  }
  final problems = <String>[];
  for (final (i, one) in value.indexed) {
    final item = one is Map
        ? one.cast<String, Object?>()
        : const <String, Object?>{};
    for (final field in const ['path', 'at', 'reason', 'verified']) {
      if (btestText(item[field]) == null) {
        problems.add('chainBreaks[${i + 1}].$field is empty');
      }
    }
    final reason = btestText(item['reason']);
    if (reason != null && !BtestPolicy.chainBreakReasons.contains(reason)) {
      problems.add(
        'chainBreaks[${i + 1}].reason "$reason" is not one of '
        '门控 / 无权限 / 数据不足 / 没有下一步',
      );
    }
    // A null is the field left out (nothing was found); a blank or a
    // non-string is a cause that says nothing.
    if (item['cause'] case final cause? when btestText(cause) == null) {
      problems.add(
        cause is String
            ? 'chainBreaks[${i + 1}].cause is empty'
            : 'chainBreaks[${i + 1}].cause must be one string',
      );
    }
  }
  return (
    text: '；chainBreaks ${value.length} 条'
        '${problems.isEmpty ? '，四字段齐' : '，${problems.length} 处不合格'}',
    problems: problems,
  );
}

String _short(String hash) => hash.length <= 12 ? hash : hash.substring(0, 12);
