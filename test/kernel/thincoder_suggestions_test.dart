// The `@` menu's suggestions: what a project holds, ranked for a query.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:baocode/kernel/thincoder/thincoder_suggestions.dart';

void main() {
  late Directory root;

  /// [paths] written under a fresh project (a trailing `/` makes a folder).
  void project(List<String> paths) {
    for (final path in paths) {
      final file = File(p.joinAll([root.path, ...p.posix.split(path)]));
      file.parent.createSync(recursive: true);
      if (path.endsWith('/')) {
        Directory(file.path).createSync(recursive: true);
      } else {
        file.writeAsStringSync('');
      }
    }
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('suggestions');
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<List<String>> of(String query, {ProjectSuggestions? suggester}) async {
    final suggestions = await (suggester ?? ProjectSuggestions()).of(
      root.path,
      query,
    );
    return [for (final suggestion in suggestions) suggestion.path];
  }

  test('lists files relative to the project, paths `/`-separated', () async {
    project(['lib/a.dart', 'README.md', 'src/nested/b.dart']);
    // Two characters on: a shorter query is left to the host's own listing.
    expect(await of(''), isEmpty);
    expect(
      await of('a.'),
      containsAll(['lib/a.dart']),
    );
    expect(await of('src'), ['src/']);
    expect(await of('a.'), isNot(contains(p.join('lib', 'a.dart'))));
  });

  test('a bare query matches names anywhere; a slash one matches the path',
      () async {
    project(['lib/chat/composer.dart', 'lib/editor/composer_view.dart']);
    // A prefix of the name, as typed after `@`.
    expect(await of('comp'), contains('lib/chat/composer.dart'));
    final byName = await of('composer');
    expect(byName, containsAll(['lib/chat/composer.dart', 'lib/editor/composer_view.dart']));
    // The name that starts with it comes first.
    expect(byName.first, 'lib/chat/composer.dart');
    // With a folder in the query, only that folder's answer.
    expect(await of('chat/composer'), ['lib/chat/composer.dart']);
  });

  test('skips what a suggestion is never for', () async {
    project([
      '.git/config',
      'node_modules/pkg/index.js',
      'build/out.js',
      '.dart_tool/x',
      'lib/keep.dart',
    ]);
    expect(await of('ke'), ['lib/keep.dart']);
  });

  test('lists folders with a `/` after them, and not twice in one cache',
      () async {
    project(['lib/a.dart']);
    final suggester = ProjectSuggestions();
    expect(await of('li', suggester: suggester), contains('lib/'));
    // Added while the cache holds: not seen until it lapses.
    project(['lib/late.dart']);
    expect(await of('late', suggester: suggester), isEmpty);
    final fresh = ProjectSuggestions(cacheFor: Duration.zero);
    expect(await of('late', suggester: fresh), ['lib/late.dart']);
  });

  test('nothing for a folder that is not one', () async {
    expect(await ProjectSuggestions().of(p.join(root.path, 'missing'), ''), isEmpty);
  });

  test('no matches, no suggestions', () async {
    project(['lib/a.dart']);
    expect(await of('zzzz'), isEmpty);
  });
}
