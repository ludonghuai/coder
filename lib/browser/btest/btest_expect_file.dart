import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

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

/// The expect file of a run `docs/qa/<line>.md` (design §3.4): its cases,
/// its text and its SHA-256 — the write-back baseline `btest_run_start`
/// hands back, and what `btest_run_end` compares the file against.
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

  /// Why [path] cannot be a run's `expectFile`, or null: it is relative to
  /// the repository, under `docs/qa/`, and a Markdown file (§3.3).
  static String? relativeProblem(String path) {
    final ref = path.trim();
    if (ref.isEmpty) return 'expectFile is required';
    if (p.isAbsolute(ref) || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(ref)) {
      return 'expectFile must be relative to repoRoot, not "$ref"';
    }
    final parts = p.posix.split(ref.replaceAll('\\', '/'));
    if (parts.any((part) => part == '..' || part == '.')) {
      return 'expectFile must not step out of repoRoot: "$ref"';
    }
    final normalized = parts.where((part) => part.isNotEmpty).join('/');
    if (!normalized.startsWith('docs/qa/')) {
      return 'expectFile must be under docs/qa/ (the fixed form '
          'docs/qa/<line>.md), not "$ref"';
    }
    if (!normalized.endsWith('.md')) {
      return 'expectFile must be a .md file, not "$ref"';
    }
    return null;
  }

  /// [expectFile] (relative to [repoRoot]) as an absolute path.
  static String resolve(String repoRoot, String expectFile) => p.normalize(
    p.join(repoRoot, expectFile.trim().replaceAll('/', p.separator)),
  );

  /// Why [file] (absolute) may not be written, or null: its nearest
  /// existing folder must be a directory (§3.3, `expectFile`'s check).
  static String? writableProblem(String file) {
    var folder = p.dirname(file);
    while (true) {
      final type = FileSystemEntity.typeSync(folder);
      if (type == FileSystemEntityType.directory) return null;
      if (type != FileSystemEntityType.notFound) {
        return '${p.dirname(file)} cannot be written: $folder is not a folder';
      }
      final up = p.dirname(folder);
      if (up == folder) return null;
      folder = up;
    }
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
  /// by a write-back). Completes with what was appended.
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
