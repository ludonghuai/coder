import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../remote/remote_location.dart';

/// A case of an expect file (design §3.4): its ID and its title, as
/// `## CASE-BKG-001 新建订舱单并提交` gives them.
class BtestCase {
  const BtestCase(this.id, this.title);

  final String id;
  final String title;

  @override
  String toString() => title.isEmpty ? id : '$id $title';
}

/// Where a run's write-back of its expect file stands (§3.3, check 1).
enum BtestWrite {
  written,
  notWritten,
  created;

  String get label => switch (this) {
    BtestWrite.written => 'written',
    BtestWrite.notWritten => 'not written',
    BtestWrite.created => 'created',
  };
}

/// Which of §3.4's four branches gave a run's QA root; the return names it.
enum BtestQaSource {
  setting('设置值'),
  workspace('工作区根'),
  parentFallback('父目录兜底');

  const BtestQaSource(this.label);

  /// How `btest_run_start`'s return marks it.
  final String label;
}

/// Where a run's expect file goes (§3.4): the QA root — one per session
/// workspace, outside every business repository — and the branch that gave
/// it, so `btest_run_start` can show both.
class BtestQaRoot {
  const BtestQaRoot(this.root, this.source, {this.reason});

  /// The resolved root, absolute.
  final String root;

  /// The branch that gave it (§3.4, in order, first hit wins).
  final BtestQaSource source;

  /// Why it fell back (branch 3 / 4's named reason), or why a configured
  /// root still lies inside the business repository; null otherwise.
  final String? reason;

  /// The expect file of business line [line] of the repository at
  /// [repoRoot]: `<root>/<repository name>/<line>.md` (§3.4).
  String fileOf(String repoRoot, String line) =>
      p.join(root, p.basename(repoRoot), '$line.md');

  /// §3.4's four branches, in order, first hit wins; `problem` is what
  /// stops a run — a configured root that is not absolute — else null.
  ///
  /// [cwd] is the call's working folder as the host tool layer has it
  /// (`HostToolCall.cwd`), i.e. the session's workspace root. It is the
  /// whole anchor: `'.'` or any other non-absolute value means the
  /// workspace root is not known, and the run falls back to the
  /// repository's parent folder rather than resolving a relative place
  /// (§3.4, "链尾是 `'.'`").
  static ({BtestQaRoot? root, String? problem}) resolve({
    required String repoRoot,
    required String cwd,
    String? configured,
    required String setting,
  }) {
    final repo = p.normalize(repoRoot);
    final parent = BtestQaRoot(
      p.join(p.dirname(repo), 'qa'),
      BtestQaSource.parentFallback,
    );
    BtestQaRoot fallBack(String reason) =>
        BtestQaRoot(parent.root, parent.source, reason: reason);

    final value = configured?.trim() ?? '';
    if (value.isNotEmpty) {
      if (!p.isAbsolute(value)) {
        return (
          root: null,
          problem: '$setting must be an absolute path, not "$value"',
        );
      }
      final root = p.normalize(value);
      return (
        root: BtestQaRoot(
          root,
          BtestQaSource.setting,
          reason: p.equals(repo, root) || p.isWithin(repo, root)
              ? 'QA 根在业务仓内'
              : null,
        ),
        problem: null,
      );
    }

    final workspace = cwd.trim();
    if (RemoteLocation.isRemote(workspace)) {
      return (root: fallBack('工作区根是远端位置'), problem: null);
    }
    if (!p.isAbsolute(workspace)) {
      return (root: fallBack('工作区根不可得'), problem: null);
    }
    final here = p.normalize(workspace);
    if (p.equals(here, repo)) {
      return (root: fallBack('工作区根即业务仓'), problem: null);
    }
    if (p.isWithin(here, repo)) {
      return (
        root: BtestQaRoot(p.join(here, 'qa'), BtestQaSource.workspace),
        problem: null,
      );
    }
    return (root: fallBack('仓在工作区根之外'), problem: null);
  }
}

/// The expect file of a run, `<qaRoot>/<repository>/<line>.md` (design
/// §3.4): its cases, its text and its SHA-256 — the write-back baseline
/// `btest_run_start` hands back, and what `btest_run_end` compares the file
/// against.
class BtestExpect {
  const BtestExpect({
    required this.path,
    this.text,
    this.hash,
    this.cases = const [],
  });

  /// Where it is (absolute).
  final String path;

  /// What it holds; null when there is no file.
  final String? text;

  /// SHA-256 of [text] in hex; null when there is no file (`absent`).
  final String? hash;

  /// Its cases, in order.
  final List<BtestCase> cases;

  bool get absent => text == null;

  /// Reads [path]; a missing file is [absent] rather than an error.
  static BtestExpect read(String path) {
    final file = File(path);
    if (!file.existsSync()) return BtestExpect(path: path);
    final text = file.readAsStringSync();
    return BtestExpect(
      path: path,
      text: text,
      hash: hashOf(text),
      cases: casesOf(text),
    );
  }

  /// SHA-256 of [text] in hex: the baseline's form.
  static String? hashOf(String? text) =>
      text == null ? null : sha256.convert(utf8.encode(text)).toString();

  static final _caseLine = RegExp(r'^## (CASE-[A-Za-z0-9_.-]+)\s*(.*)$');

  /// The `## CASE-…` headings of [text], a fenced block's left out: the
  /// file's own examples are not its cases.
  static List<BtestCase> casesOf(String text) {
    final cases = <BtestCase>[];
    var fenced = false;
    for (final line in text.split('\n')) {
      final trimmed = line.trimRight();
      if (trimmed.trimLeft().startsWith('```')) {
        fenced = !fenced;
        continue;
      }
      if (fenced) continue;
      final match = _caseLine.firstMatch(trimmed);
      if (match != null) cases.add(BtestCase(match[1]!, match[2]!.trim()));
    }
    return cases;
  }

  /// The case index `btest_run_start` returns (§3.3, item 2).
  String get indexText => cases.isEmpty
      ? '(no case yet: the file has no "## CASE-" section)'
      : [for (final one in cases) '$one'].join('\n');

  /// Whether the file was written back since [baseline] (§3.3, check 1):
  /// no baseline and a file now = created; the same hash = not written;
  /// another hash = written.
  static BtestWrite statusOf({
    required String? baseline,
    required BtestExpect now,
  }) {
    if (baseline == null) {
      return now.absent ? BtestWrite.notWritten : BtestWrite.created;
    }
    return now.hash == baseline ? BtestWrite.notWritten : BtestWrite.written;
  }

  /// Why [line] cannot name a run's expect file, or null: the file is
  /// `<line>.md`, so the business line is a name — non-empty and without a
  /// path separator (§3.3: the file is derived, never a path input).
  static String? lineProblem(String? line) {
    final name = line?.trim() ?? '';
    if (name.isEmpty) return 'line is required';
    if (name.contains('/') || name.contains('\\')) {
      return 'line must be a business-line name, not a path: "$name"';
    }
    return null;
  }

  /// The file's first form (§3.4, first generation): its header alone —
  /// cases are written once they are seen, never guessed.
  static String skeleton({
    required String line,
    required String repo,
    required String startUrl,
    required String env,
    String? role,
    String? commitRange,
    DateTime? at,
  }) =>
      '# $line（$repo）业务线\n'
      '\n'
      '> 环境：$env · 起点：$startUrl'
      '${role == null || role.trim().isEmpty ? '' : ' · 角色：${role.trim()}'}\n'
      '> 更新：${dateOf(at)} · 变更范围：'
      '${commitRange?.trim().isNotEmpty ?? false ? commitRange!.trim() : 'git log --oneline -30'}\n'
      '\n';

  /// Appends a `## <date> 修订建议` section to [path], keeping every line
  /// already there (§3.4: a file someone else changed is never overwritten
  /// by a write-back). The write-back is the agent's own file write; the
  /// host only validates it ([statusOf]) and never calls this — the rule is
  /// carried by the mode card, and this is its reference implementation.
  /// Completes with what was appended.
  static String appendRevision(String path, {String? body, DateTime? at}) {
    final file = File(path);
    final text = file.existsSync() ? file.readAsStringSync() : '';
    final added = [
      if (text.isNotEmpty && !text.endsWith('\n')) '',
      if (text.isNotEmpty) '',
      '## ${dateOf(at)} 修订建议',
      '',
      if (body?.trim().isNotEmpty ?? false) body!.trim(),
    ].join('\n');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('$text$added\n');
    return added;
  }

  /// `YYYY-MM-DD`, [at] or today.
  static String dateOf(DateTime? at) {
    final date = at ?? DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }
}
