// The project's files for the composer's `@` menu, as the terminal names
// them: relative to the project, `/`-separated, a folder with a `/` after it.
import 'dart:io';

import 'package:path/path.dart' as p;

import '../kernel_types.dart' show FileSuggestion;

/// Folders never worth listing (a suggestion is about source files).
const _skipped = {
  '.git',
  '.dart_tool',
  '.thincoder',
  '.idea',
  '.vscode',
  'node_modules',
  'build',
  'dist',
  'out',
  'target',
  'coverage',
  '.gradle',
  '.next',
};

/// What [root] holds, as suggestions: refreshed at most every [cacheFor].
class ProjectSuggestions {
  ProjectSuggestions({this.limit = 20, this.cacheFor = const Duration(seconds: 2)});

  final int limit;
  final Duration cacheFor;

  String? _root;
  DateTime? _listedAt;
  List<String> _paths = const [];

  /// The suggestions for [query] among [root]'s files (none when [root] is
  /// not a directory, or holds nothing to suggest).
  Future<List<FileSuggestion>> of(String? root, String query) async {
    if (root == null) return const [];
    await _refresh(root);
    final needle = query.trim().toLowerCase();
    final ranked = [
      for (final path in _paths) if (_matches(path, needle)) path,
    ]..sort((a, b) => _score(a, needle).compareTo(_score(b, needle)));
    return [
      for (final path in ranked.take(limit)) FileSuggestion(path),
    ];
  }

  Future<void> _refresh(String root) async {
    final now = DateTime.now();
    if (_root == root &&
        _listedAt != null &&
        now.difference(_listedAt!) < cacheFor) {
      return;
    }
    _root = root;
    _listedAt = now;
    _paths = await _list(root);
  }

  /// Every file under [root], relative and `/`-separated (folders of
  /// [_skipped] and dot-folders left out, not descended into); empty when it
  /// cannot be read.
  static Future<List<String>> _list(String root) async {
    final out = <String>[];
    Future<void> walk(Directory directory, String relative) async {
      if (out.length >= 20000) return;
      final List<FileSystemEntity> entries;
      try {
        entries = await directory.list(followLinks: false).toList();
      } on Object {
        return;
      }
      for (final entity in entries) {
        final name = p.basename(entity.path);
        if (_skipped.contains(name) || name.startsWith('.')) continue;
        final path = relative.isEmpty ? name : '$relative/$name';
        if (entity is Directory) {
          out.add('$path/');
          await walk(entity, path);
        } else {
          out.add(path);
        }
        if (out.length >= 20000) return;
      }
    }

    try {
      await walk(Directory(root), '');
    } on Object {
      return const [];
    }
    return out;
  }

  /// Whether [path] answers [needle]: every character of it in order, and
  /// (for a query with a folder in it) anywhere in the path — else in the
  /// file's name alone, so `composer` finds `lib/chat/composer.dart`.
  static bool _matches(String path, String needle) {
    if (needle.isEmpty) return true;
    final haystack = needle.contains('/') ? path : p.posix.basename(path);
    var at = 0;
    for (final letter in needle.replaceAll('/', '').split('')) {
      final found = haystack.indexOf(letter, at);
      if (found < 0) return false;
      at = found + 1;
    }
    return true;
  }

  /// Lower is better: a name that starts with the query, then a name that
  /// has it at all, then a shorter path.
  static int _score(String path, String needle) {
    if (needle.isEmpty) return path.length;
    final name = p.posix.basename(path).toLowerCase();
    final atName = name.startsWith(needle);
    final atPath = path.toLowerCase().contains(needle);
    return (atName ? 0 : atPath ? 1000 : 2000) + path.length;
  }
}
