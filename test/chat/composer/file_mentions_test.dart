// The `@` menu's file lookup: the project's listing, filtered by what was
// typed after the `@`.
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:baocode/chat/composer/file_mentions.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_quick_open.dart';

/// The project's files, in memory.
class _Files implements IdeFileService {
  _Files(this.paths);

  final List<String> paths;

  @override
  Future<String> read(String path, {bool force = false}) async => '';

  @override
  Future<List<IdeFile>> list(String directory) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late String root;
  late List<String> paths;
  late IdeFileIndex index;
  late FileMentions mentions;

  setUp(() {
    root = p.normalize('/project');
    paths = [
      for (final name in [
        'lib/chat/composer/composer.dart',
        'lib/chat/chat_session.dart',
        'lib/ide/ide_quick_open.dart',
        'README.md',
      ])
        p.joinAll([root, ...p.posix.split(name)]),
    ];
    final files = _Files(paths);
    index = IdeFileIndex(
      files,
      root,
      lister: (_, _) async => IdeFileListing([...paths]..sort()),
    );
    mentions = FileMentions(files: files, paths: p.context, index: index);
  });

  test('a typed prefix finds the file it names', () async {
    final typed = await mentions.suggest('comp');
    expect(
      [for (final suggestion in typed) suggestion.label],
      contains('composer.dart'),
      reason: 'what the user types after @ must narrow to the file',
    );
  });

  test('a second query after a first still finds it', () async {
    await mentions.suggest('chat');
    final typed = await mentions.suggest('comp');
    expect([for (final suggestion in typed) suggestion.label],
        contains('composer.dart'));
  });

  test('a query no file answers is empty, not everything', () async {
    expect(await mentions.suggest('zzzz'), isEmpty);
  });
}
