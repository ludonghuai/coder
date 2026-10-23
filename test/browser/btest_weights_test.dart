import 'dart:io';

import 'package:baocode/browser/btest/btest_weights.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// The weights table (design §3.9): the built-in eight, the file built on
// first sight, the effective order the markers shape, and check 5's
// readings — what a run walks by, and what it must warn about.
void main() {
  late Directory sandbox;
  late String qaRoot;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('btest_weights');
    qaRoot = p.join(sandbox.path, 'qa');
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  /// A minimal table with [rows], for the order cases.
  String tableOf(List<(String, int)> rows) => [
    '# btest 权重表',
    '',
    '| 类 | 条数 | 检查点 |',
    '|---|---|---|',
    for (final (name, count) in rows) '| $name | $count | [P01] |',
    '',
  ].join('\n');

  void writeTable(String text) => File(BtestWeights.pathOf(qaRoot))
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  test('the built-in eight carry their counts and checkpoints (§3.9)', () {
    expect([for (final one in btestDefaultWeights) one.name], [
      '刷新 / 数据丢失',
      '报错 / 异常',
      '为空 / 空态',
      '筛选 / 查询',
      '金额 / 数字',
      '按钮 / 交互',
      '英文 / 文案',
      '重复提交',
    ]);
    expect([for (final one in btestDefaultWeights) one.count], [
      58,
      52,
      40,
      35,
      31,
      24,
      22,
      20,
    ]);
    expect(btestDefaultWeights.first.checkpoints, '[P10] · [P05]');
    expect(btestDefaultWeights[4].checkpoints, '[P04] · [J6]');
    expect(btestDefaultWeights.last.checkpoints, '[P06] · [J2]');
  });

  test('a missing file is built: source file, no warning, eight rows (#33)', () {
    final weights = BtestWeights.ensure(qaRoot);
    expect(weights.source, BtestWeightsSource.file);
    expect(weights.warnings, isEmpty);
    final file = File(BtestWeights.pathOf(qaRoot));
    expect(file.existsSync(), isTrue);
    final text = file.readAsStringSync();
    for (final one in btestDefaultWeights) {
      expect(text, contains('| ${one.name} | ${one.count} |'));
    }
    expect(
      weights.orderLine,
      '刷新 / 数据丢失 → 报错 / 异常 → 为空 / 空态 → 筛选 / 查询 → '
      '金额 / 数字 → 按钮 / 交互 → 英文 / 文案 → 重复提交',
    );
  });

  test('an existing file is read as it is; after a delete it is rebuilt the same (#33)', () {
    BtestWeights.ensure(qaRoot);
    final again = BtestWeights.ensure(qaRoot);
    expect(again.source, BtestWeightsSource.file);
    expect(again.warnings, isEmpty, reason: 'the template placeholder is not a mark');
    File(again.path).deleteSync();
    final rebuilt = BtestWeights.ensure(qaRoot);
    expect(rebuilt.source, BtestWeightsSource.file);
    expect(rebuilt.warnings, isEmpty, reason: 'same reading as the first build');
  });

  test('order: count descending, 已修 to the end, 已复现 in place (§3.9)', () {
    writeTable(
      '${tableOf([
        ('刷新 / 数据丢失', 58),
        ('报错 / 异常', 52),
        ('金额 / 数字', 31),
      ])}\n## 标记\n\n'
      '- 已修：刷新 / 数据丢失 — 2026-10-23 改完\n'
      '- 已复现：金额 / 数字 — run-2 · 2026-10-23\n',
    );
    final weights = BtestWeights.ensure(qaRoot);
    expect(weights.source, BtestWeightsSource.file);
    expect(weights.warnings, isEmpty);
    expect([for (final one in weights.order) one.name], [
      '报错 / 异常',
      '金额 / 数字',
      '刷新 / 数据丢失',
    ]);
  });

  test('a class beyond the eight sorts with the rest (§3.9)', () {
    writeTable(
      tableOf([
        ('刷新 / 数据丢失', 58),
        ('报错 / 异常', 52),
        ('传参 / 跨页', 60),
      ]),
    );
    final weights = BtestWeights.ensure(qaRoot);
    expect([for (final one in weights.order) one.name], [
      '传参 / 跨页',
      '刷新 / 数据丢失',
      '报错 / 异常',
    ]);
  });

  test('a row without its closing pipe still reads; a bad count is named (§3.9)', () {
    writeTable(
      '| 类 | 条数 | 检查点 |\n'
      '|---|---|---|\n'
      '| 刷新 / 数据丢失 | 58 | [P10]\n'
      '| 报错 / 异常 | 五十二 | [P01]\n',
    );
    final weights = BtestWeights.ensure(qaRoot);
    expect([for (final one in weights.order) one.name], ['刷新 / 数据丢失']);
    expect(weights.warnings.single, contains('报错 / 异常'));
    expect(weights.warnings.single, contains('条数读不出'));
  });

  test('a 已修 marker that names no class gets one warning naming it (§3.9)', () {
    writeTable(
      '${tableOf([('刷新 / 数据丢失', 58)])}\n## 标记\n\n'
      '- 已修：刷新/数据丢失 — 名字漂了\n',
    );
    final weights = BtestWeights.ensure(qaRoot);
    expect(weights.warnings.single, contains('已修：刷新/数据丢失'));
    expect(weights.order.single.name, '刷新 / 数据丢失', reason: 'not reordered');
  });

  test('a file that cannot be parsed is built-in, with one warning (#33)', () {
    writeTable('');
    final weights = BtestWeights.ensure(qaRoot);
    expect(weights.source, BtestWeightsSource.builtIn);
    expect(weights.warnings.single, contains('解析不出类目'));
    expect(weights.order.length, 8, reason: 'the built-in eight carry the run');
  });

  test('a file that cannot be written is built-in, with one warning (#33)', () {
    Directory(BtestWeights.pathOf(qaRoot)).createSync(recursive: true);
    final weights = BtestWeights.ensure(qaRoot);
    expect(weights.source, BtestWeightsSource.builtIn);
    expect(weights.warnings.single, contains('写不出'));
    expect(weights.order.length, 8);
  });

  test('check 5 names a deleted class, and a stale marker (§3.3, #33)', () {
    BtestWeights.ensure(qaRoot);
    final path = BtestWeights.pathOf(qaRoot);
    final text = File(path).readAsStringSync();
    File(path).writeAsStringSync(
      '${text.replaceFirst('| 重复提交 | 20 | [P06] · [J2] |\n', '')}'
      '- 已修：没有这一类 — x\n',
    );
    final check = BtestWeights.check(qaRoot);
    expect(check.missing, ['重复提交']);
    expect(check.problem, isNull);
    expect(check.warnings.single, contains('已修：没有这一类'));
  });

  test('check 5 names a table that is not on disk', () {
    final check = BtestWeights.check(qaRoot);
    expect(check.missing, isEmpty);
    expect(check.problem, contains('不在盘上'));
  });
}
