/// The weights table `<qaRoot>/weights.md` (design §3.9): the historical
/// defect density a run walks by — eight classes, their measured counts and
/// the checkpoints each maps to. One file per QA root, shared by the
/// repositories of one workspace; the file is the user's to edit, and the
/// host only ever creates it when absent.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// One class of the weights table: its name, its measured count and the
/// checkpoints it maps to (§3.9).
class BtestWeightClass {
  const BtestWeightClass(this.name, this.count, this.checkpoints);

  final String name;
  final int count;
  final String checkpoints;
}

/// Where a run's effective order came from (§3.3, item 6).
enum BtestWeightsSource {
  /// The file on disk — including the one this run wrote on first sight.
  file('file'),

  /// The built-in defaults, because the file could not be read or written.
  builtIn('built-in');

  const BtestWeightsSource(this.label);

  /// How `btest_run_start`'s return marks it.
  final String label;
}

/// The eight classes of the built-in default (§3.9): the 924-entry
/// clustering, by title keyword — counts are data, never a rule.
const btestDefaultWeights = <BtestWeightClass>[
  BtestWeightClass('刷新 / 数据丢失', 58, '[P10] · [P05]'),
  BtestWeightClass('报错 / 异常', 52, '[P01]'),
  BtestWeightClass('为空 / 空态', 40, '[P17]'),
  BtestWeightClass('筛选 / 查询', 35, '[P09]'),
  BtestWeightClass('金额 / 数字', 31, '[P04] · [J6]'),
  BtestWeightClass('按钮 / 交互', 24, '[P11]'),
  BtestWeightClass('英文 / 文案', 22, '[P16] · [P01]'),
  BtestWeightClass('重复提交', 20, '[P06] · [J2]'),
];

/// Check 5's reading of the table (§3.3): the default classes the file no
/// longer holds, a file that cannot be read at all, and the `已修` marker
/// lines that match no class.
typedef BtestWeightsCheck = ({
  List<String> missing,
  String? problem,
  List<String> warnings,
});

/// A run's weights reading (§3.3, item 6 / check 5): where the table is,
/// where its order came from, the effective order and what to warn about.
class BtestWeights {
  const BtestWeights({
    required this.path,
    required this.source,
    required this.order,
    required this.warnings,
  });

  /// The table's absolute path, `<qaRoot>/weights.md`.
  final String path;

  final BtestWeightsSource source;

  /// The effective order (§3.9): count descending, the `已修` classes moved
  /// to the end (still walked once), `已复现` left where the count puts it.
  final List<BtestWeightClass> order;

  /// One line per thing the reading could not honour; empty when it could.
  final List<String> warnings;

  /// The effective order as one line (§3.3, item 6): the classes by name,
  /// in the order the round walks them.
  String get orderLine => [for (final one in order) one.name].join(' → ');

  /// The file of one QA root (§3.9: one per root, not per repository).
  static String pathOf(String qaRoot) => p.join(qaRoot, 'weights.md');

  /// Reads the table, or writes it first (§3.9): a missing file is written
  /// from the defaults, and that write is the run's source — `file`, no
  /// warning (first run and re-creation after a delete read the same); a
  /// file that cannot be read or written leaves the defaults, `built-in`,
  /// with one warning. Never blocks a run.
  static BtestWeights ensure(String qaRoot, {DateTime? at}) {
    final path = pathOf(qaRoot);
    final file = File(path);
    if (!file.existsSync()) {
      try {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(defaultText(at: at));
      } on FileSystemException catch (error) {
        return _builtIn(
          path,
          'weights.md 写不出（$path：${_reason(error)}）；本轮按内置默认八类跑',
        );
      }
    }
    final String text;
    try {
      text = file.readAsStringSync();
    } on FileSystemException catch (error) {
      return _builtIn(
        path,
        'weights.md 读不出（$path：${_reason(error)}）；本轮按内置默认八类跑',
      );
    }
    final parsed = parse(text);
    if (parsed == null) {
      return _builtIn(
        path,
        'weights.md 解析不出类目（$path）；本轮按内置默认八类跑',
      );
    }
    return BtestWeights(
      path: path,
      source: BtestWeightsSource.file,
      order: orderOf(parsed.classes, parsed.fixed),
      warnings: parsed.warnings,
    );
  }

  /// Check 5's reading (§3.3): the file on disk with the eight classes, and
  /// the `已修` markers that name a class the table does not hold.
  static BtestWeightsCheck check(String qaRoot) {
    final path = pathOf(qaRoot);
    final file = File(path);
    if (!file.existsSync()) {
      return (
        missing: const <String>[],
        problem: 'weights.md 不在盘上（$path）',
        warnings: const <String>[],
      );
    }
    final String text;
    try {
      text = file.readAsStringSync();
    } on FileSystemException catch (error) {
      return (
        missing: const <String>[],
        problem: 'weights.md 读不出（$path：${_reason(error)}）',
        warnings: const <String>[],
      );
    }
    final parsed = parse(text);
    if (parsed == null) {
      return (
        missing: const <String>[],
        problem: 'weights.md 解析不出类目（$path）',
        warnings: const <String>[],
      );
    }
    final names = {for (final one in parsed.classes) one.name};
    return (
      missing: [
        for (final one in btestDefaultWeights)
          if (!names.contains(one.name)) one.name,
      ],
      problem: null,
      warnings: parsed.warnings,
    );
  }

  /// §3.9's order: count descending; a class marked `已修` goes to the end
  /// (still walked once); `已复现` changes nothing. Ties keep file order,
  /// and a class someone added beyond the eight sorts with the rest.
  static List<BtestWeightClass> orderOf(
    List<BtestWeightClass> classes,
    Set<String> fixed,
  ) {
    final indexed = [for (final (index, one) in classes.indexed) (index, one)];
    indexed.sort((a, b) {
      final aFixed = fixed.contains(a.$2.name);
      final bFixed = fixed.contains(b.$2.name);
      if (aFixed != bFixed) return aFixed ? 1 : -1;
      final byCount = b.$2.count.compareTo(a.$2.count);
      return byCount != 0 ? byCount : a.$1.compareTo(b.$1);
    });
    return [for (final (_, one) in indexed) one];
  }

  /// The table's first form (§3.9): the eight built-in classes and the
  /// markers section the AI only ever appends to.
  static String defaultText({DateTime? at}) => [
    '# btest 权重表（历史缺陷密度）',
    '',
    '> 由来：51marine-issue-audit-20261021/issues-v2dev.json（聚类样本 924 条，'
        '按标题关键词聚类）· 首建 ${_date(at)}',
    '> 两个读数的口径不同：**905** = 语料全量条目数（需求档 `:74`）· '
        '**924** = 进聚类的条目数；差额来源设计位未复算（§10 第 10 条）',
    '',
    '| 类 | 条数 | 检查点 |',
    '|---|---|---|',
    for (final one in btestDefaultWeights)
      '| ${one.name} | ${one.count} | ${one.checkpoints} |',
    '',
    '## 标记',
    '',
    '- 已修：<类> — <证据> · <日期>',
    '- 已复现：<类> — <run id> · <日期>',
    '',
  ].join('\n');

  /// The classes in [text], the class names its `已修` markers name, and the
  /// marker lines that match no class; null when no table row parses at all.
  ///
  /// A class name matches literally, trimmed — a name that drifted is named
  /// in a warning rather than silently left unsorted (§3.9).
  static ({
    List<BtestWeightClass> classes,
    Set<String> fixed,
    List<String> warnings,
  })?
  parse(String text) {
    final lines = text.split('\n');
    final classes = <BtestWeightClass>[];
    final rowWarnings = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('|')) continue;
      final cells = [for (final cell in trimmed.split('|')) cell.trim()];
      // '| 类 | 条数 | 检查点 |' splits to ['', '类', '条数', '检查点', ''];
      // a last row may leave its closing pipe out and still parses.
      if (cells.length < 4) continue;
      final name = cells[1];
      if (name.isEmpty || name == '类') continue;
      final countText = cells[2];
      // The header's separator row: --- or :---:.
      if (RegExp(r'^[-:]*$').hasMatch(countText)) continue;
      final count = int.tryParse(countText);
      if (count == null) {
        rowWarnings.add(
          'weights.md 的行「$name」条数读不出（"$countText"）'
          '—— 该行不参与排序',
        );
        continue;
      }
      classes.add(
        BtestWeightClass(name, count, cells.length > 3 ? cells[3] : ''),
      );
    }
    if (classes.isEmpty) return null;
    final names = {for (final one in classes) one.name};
    final fixed = <String>{};
    final warnings = <String>[...rowWarnings];
    for (final line in lines) {
      final match = _fixedMarker.firstMatch(line.trim());
      if (match == null) continue;
      final rest = match[1]!.trim();
      // The template's own placeholder (`<类>`) is an example, not a mark.
      if (rest.startsWith('<')) continue;
      final name = rest.split('—').first.trim();
      if (name.isEmpty) continue;
      if (names.contains(name)) {
        fixed.add(name);
      } else {
        warnings.add(
          'weights.md 的「已修：$name」对不上表内的任一「类」（逐字匹配）'
          '—— 该类不会被排到末尾（§3.9）',
        );
      }
    }
    return (classes: classes, fixed: fixed, warnings: warnings);
  }

  /// A `- 已修：<类> — <证据>` line; the class is what comes after the colon
  /// up to the em dash.
  static final _fixedMarker = RegExp(r'^-\s*已修\s*[:：]\s*(.*)$');

  static BtestWeights _builtIn(String path, String warning) => BtestWeights(
    path: path,
    source: BtestWeightsSource.builtIn,
    order: orderOf(btestDefaultWeights, const {}),
    warnings: [warning],
  );

  static String _reason(FileSystemException error) =>
      error.osError?.message ?? error.message;

  /// `YYYY-MM-DD`, [at] or today.
  static String _date(DateTime? at) {
    final date = at ?? DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }
}
