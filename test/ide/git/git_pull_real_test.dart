@TestOn('vm')
library;

import 'dart:io';

import 'package:baocode/ide/git/git_autofetch_engine.dart';
import 'package:baocode/ide/git/git_pull.dart';
import 'package:baocode/ide/git/git_repository.dart';
import 'package:baocode/ide/git/git_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The pull from a branch's upstream against real Git (no network: a bare
/// origin and two clones in the system's temporary folder): the Get
/// button's merge and rollback, and the automatic fetch's one round.
void main() {
  final hasGit = () {
    try {
      return Process.runSync('git', ['--version']).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }();
  final skip = hasGit ? false : 'Git is not installed';

  late Directory temp;
  late String origin;
  late String mainClone;
  late String otherClone;

  Future<ProcessResult> run(String root, List<String> arguments) =>
      Process.run('git', arguments, workingDirectory: root);

  Future<ProcessResult> git(String root, List<String> arguments) async {
    final result = await run(root, arguments);
    expect(
      result.exitCode,
      0,
      reason: 'git ${arguments.join(' ')}\n${result.stdout}\n${result.stderr}',
    );
    return result;
  }

  Future<String> out(String root, List<String> arguments) async =>
      (await git(root, arguments)).stdout.toString().trim();

  Future<void> write(String root, String relative, String text) async {
    final file = File(p.join(root, relative));
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  Future<void> commit(
    String root,
    Map<String, String> files,
    String message,
  ) async {
    for (final MapEntry(:key, :value) in files.entries) {
      await write(root, key, value);
    }
    await git(root, ['add', '-A']);
    await git(root, ['commit', '-q', '-m', message]);
  }

  Future<void> configure(String root) async {
    final hooks = Directory(p.join(temp.path, 'no-hooks'))..createSync();
    for (final (key, value) in [
      ('user.name', 'Ada'),
      ('user.email', 'ada@example.com'),
      ('commit.gpgsign', 'false'),
      ('core.hooksPath', hooks.path),
      ('core.autocrlf', 'false'),
    ]) {
      await git(root, ['config', key, value]);
    }
  }

  String head(String root) => p.join(root, '.git', 'MERGE_HEAD');
  bool merging(String root) => File(head(root)).existsSync();

  IdeGitRepository repository(String root) => IdeGitRepository(
    IdeGitService(root, watcher: (_) => const Stream.empty()),
    refreshDelay: Duration.zero,
  );

  /// A conflict of the local branch and its upstream, left in progress.
  Future<void> mergeInProgress() async {
    await commit(mainClone, {'a.txt': 'local\n'}, 'Local');
    await commit(otherClone, {'a.txt': 'remote\n'}, 'Remote');
    await git(otherClone, ['push', '-q', 'origin', 'main']);
    await git(mainClone, ['fetch', '-q', '--all', '--tags']);
    final merged = await run(mainClone, ['merge', '--no-edit', 'origin/main']);
    expect(merged.exitCode, isNot(0), reason: '${merged.stdout}');
    expect(merging(mainClone), isTrue);
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('baocode_pull_');
    final root = p.normalize(await temp.resolveSymbolicLinks());
    origin = p.join(root, 'origin.git');
    mainClone = p.join(root, 'main');
    otherClone = p.join(root, 'other');
    await git(root, ['init', '-q', '--bare', '-b', 'main', origin]);
    final seed = p.join(root, 'seed');
    await git(root, ['clone', '-q', origin, seed]);
    await configure(seed);
    await write(seed, 'a.txt', 'a1\n');
    await write(seed, 'b.txt', 'b1\n');
    await git(seed, ['add', '-A']);
    await git(seed, ['commit', '-q', '-m', 'Initial commit']);
    await git(seed, ['push', '-q', '-u', 'origin', 'main']);
    // The machine's core.autocrlf may be on: the clones' first checkout
    // would then differ from the index and read as local changes.
    await git(root, ['clone', '-q', '-c', 'core.autocrlf=false', origin, mainClone]);
    await git(root, ['clone', '-q', '-c', 'core.autocrlf=false', origin, otherClone]);
    await configure(mainClone);
    await configure(otherClone);
  });

  tearDown(() => temp.delete(recursive: true));

  test('P1: clean and behind, the button pulls the commits down', () async {
    await commit(otherClone, {'one.txt': '1\n', 'two.txt': '2\n'}, 'Two more');
    await commit(otherClone, {'three.txt': '3\n'}, 'Third');
    await git(otherClone, ['push', '-q', 'origin', 'main']);
    final repo = repository(mainClone);
    addTearDown(repo.dispose);
    final before = await out(mainClone, ['rev-parse', 'HEAD']);

    final outcome = await repo.pullFromUpstream(mode: IdeGitPullMode.merge);

    expect(await out(mainClone, ['rev-parse', 'HEAD']), isNot(before));
    expect(
      await out(mainClone, ['rev-parse', 'HEAD']),
      await out(mainClone, ['rev-parse', 'origin/main']),
    );
    expect(File(p.join(mainClone, 'one.txt')).existsSync(), isTrue);
    expect(
      outcome.updated.map(p.basename),
      unorderedEquals(['one.txt', 'two.txt', 'three.txt']),
    );
    expect(outcome.issue, isNull);
    expect(repo.state!.head.behind, 0);
    expect(merging(mainClone), isFalse);
  }, skip: skip);

  test('P2: already up to date, nothing changes', () async {
    final repo = repository(mainClone);
    addTearDown(repo.dispose);
    final before = await out(mainClone, ['rev-parse', 'HEAD']);

    final outcome = await repo.pullFromUpstream(mode: IdeGitPullMode.merge);

    expect(await out(mainClone, ['rev-parse', 'HEAD']), before);
    expect(outcome.updated, isEmpty);
    expect(outcome.issue, isNull);
    expect(merging(mainClone), isFalse);
  }, skip: skip);

  test('P3: a local change the remote also made is refused before the '
      'merge, and kept', () async {
    await write(mainClone, 'a.txt', 'local\n');
    await commit(otherClone, {'a.txt': 'remote\n'}, 'Remote a');
    await git(otherClone, ['push', '-q', 'origin', 'main']);
    final repo = repository(mainClone);
    addTearDown(repo.dispose);

    await expectLater(
      repo.pullFromUpstream(mode: IdeGitPullMode.merge),
      throwsA(
        isA<IdeGitException>().having(
          (error) => error.message,
          'message',
          contains('overwritten'),
        ),
      ),
    );
    expect(await File(p.join(mainClone, 'a.txt')).readAsString(), 'local\n');
    expect(merging(mainClone), isFalse);
    expect(await File(p.join(mainClone, 'a.txt')).readAsString(), isNot(contains('<<<<<<<')));
  }, skip: skip);

  test('P4: staged changes are refused before the merge; the index stays',
      () async {
    await write(mainClone, 'a.txt', 'staged\n');
    await git(mainClone, ['add', 'a.txt']);
    await commit(otherClone, {'a.txt': 'remote\n'}, 'Remote a');
    await git(otherClone, ['push', '-q', 'origin', 'main']);
    final repo = repository(mainClone);
    addTearDown(repo.dispose);

    await expectLater(
      repo.pullFromUpstream(mode: IdeGitPullMode.merge),
      throwsA(isA<IdeGitException>()),
    );
    expect(await out(mainClone, ['diff', '--cached', '--name-only']), 'a.txt');
    expect(
      (await out(mainClone, ['diff', '--cached'])),
      contains('+staged'),
    );
    expect(await File(p.join(mainClone, 'a.txt')).readAsString(), 'staged\n');
    expect(merging(mainClone), isFalse);
  }, skip: skip);

  test('P5: diverged without a conflict, the merge commit has two parents',
      () async {
    await commit(mainClone, {'local.txt': 'local\n'}, 'Local file');
    await commit(otherClone, {'remote.txt': 'remote\n'}, 'Remote file');
    await git(otherClone, ['push', '-q', 'origin', 'main']);
    final repo = repository(mainClone);
    addTearDown(repo.dispose);

    final outcome = await repo.pullFromUpstream(mode: IdeGitPullMode.merge);

    final parents = (await out(mainClone, ['rev-list', '--parents', '-n', '1', 'HEAD'])).split(' ');
    expect(parents, hasLength(3), reason: 'a merge commit: its two parents');
    expect(File(p.join(mainClone, 'local.txt')).existsSync(), isTrue);
    expect(File(p.join(mainClone, 'remote.txt')).existsSync(), isTrue);
    expect(outcome.updated.map(p.basename), contains('remote.txt'));
    expect(outcome.issue, isNull);
    expect(merging(mainClone), isFalse);
  }, skip: skip);

  test('P6: a conflicting merge is rolled back, the local text kept', () async {
    await commit(mainClone, {'a.txt': 'local\n'}, 'Local a');
    await commit(otherClone, {'a.txt': 'remote\n'}, 'Remote a');
    await git(otherClone, ['push', '-q', 'origin', 'main']);
    final repo = repository(mainClone);
    addTearDown(repo.dispose);

    await expectLater(
      repo.pullFromUpstream(mode: IdeGitPullMode.merge),
      throwsA(
        isA<IdeGitException>().having(
          (error) => error.message,
          'message',
          allOf(isNotEmpty, contains('a.txt')),
        ),
      ),
    );
    final text = await File(p.join(mainClone, 'a.txt')).readAsString();
    expect(text, 'local\n');
    expect(text, isNot(contains('<<<<<<<')));
    expect(merging(mainClone), isFalse);
  }, skip: skip);

  test('P6a: a rollback keeps the local changes the conflict did not touch',
      () async {
    await write(mainClone, 'b.txt', 'local b\n');
    await commit(mainClone, {'a.txt': 'local\n'}, 'Local a');
    await commit(otherClone, {'a.txt': 'remote\n'}, 'Remote a');
    await git(otherClone, ['push', '-q', 'origin', 'main']);
    final repo = repository(mainClone);
    addTearDown(repo.dispose);

    await expectLater(
      repo.pullFromUpstream(mode: IdeGitPullMode.merge),
      throwsA(isA<IdeGitException>()),
    );
    expect(await File(p.join(mainClone, 'b.txt')).readAsString(), 'local b\n');
    expect(await File(p.join(mainClone, 'a.txt')).readAsString(), 'local\n');
    expect(merging(mainClone), isFalse);
  }, skip: skip);

  test('P7: a merge already in progress is refused and left alone', () async {
    await mergeInProgress();
    final repo = repository(mainClone);
    addTearDown(repo.dispose);

    await expectLater(
      repo.pullFromUpstream(mode: IdeGitPullMode.merge),
      throwsA(
        isA<IdeGitException>().having(
          (error) => error.message,
          'message',
          contains('merge is in progress'),
        ),
      ),
    );
    expect(merging(mainClone), isTrue);
    await git(mainClone, ['merge', '--abort']);
  }, skip: skip);

  test('P8: no upstream, or a detached head, is refused; nothing moves',
      () async {
    await git(mainClone, ['checkout', '-q', '-b', 'feature']);
    final repo = repository(mainClone);
    addTearDown(repo.dispose);
    final before = await out(mainClone, ['status', '--porcelain']);

    await expectLater(
      repo.pullFromUpstream(mode: IdeGitPullMode.merge),
      throwsA(
        isA<IdeGitException>().having(
          (error) => error.message,
          'message',
          contains('no upstream'),
        ),
      ),
    );
    expect(await out(mainClone, ['status', '--porcelain']), before);

    await git(mainClone, ['checkout', '-q', '--detach', 'origin/main']);
    await expectLater(
      repo.pullFromUpstream(mode: IdeGitPullMode.merge),
      throwsA(isA<IdeGitException>()),
    );
    expect(await out(mainClone, ['status', '--porcelain']), isEmpty);
  }, skip: skip);

  test('S1: without a merge in progress, merging() is false', () async {
    final service = IdeGitService(mainClone);
    expect(await service.merging(), isFalse);
  }, skip: skip);

  test('S2: with a merge in progress, merging() is true', () async {
    await mergeInProgress();
    final service = IdeGitService(mainClone);
    expect(await service.merging(), isTrue);
    await git(mainClone, ['merge', '--abort']);
    expect(await service.merging(), isFalse);
  }, skip: skip);

  test('T1: one automatic round fetches and fast-forwards a clean branch',
      () async {
    await commit(otherClone, {'one.txt': '1\n', 'two.txt': '2\n'}, 'Two more');
    await git(otherClone, ['push', '-q', 'origin', 'main']);
    final repo = repository(mainClone);
    await repo.refresh();
    final reloaded = <String>[];
    final settings = ChangeNotifier();
    final engine = IdeGitAutoFetch(
      repositories: () => [(mainClone, repo)],
      documents: () => const [],
      reload: (paths) async => reloaded.addAll(paths),
      setting: (key) => null,
      paths: p.context,
      settingsChanges: settings,
      onNeedsAttention: (issue, root) {},
    );
    addTearDown(() {
      engine.dispose();
      settings.dispose();
      repo.dispose();
    });
    final before = await out(mainClone, ['rev-parse', 'HEAD']);

    await engine.runNow();
    await Future<void>.delayed(Duration.zero);

    expect(await out(mainClone, ['rev-parse', 'HEAD']), isNot(before));
    expect(
      await out(mainClone, ['rev-parse', 'HEAD']),
      await out(mainClone, ['rev-parse', 'origin/main']),
    );
    expect(repo.state!.head.behind, 0);
    expect(reloaded.map(p.basename), unorderedEquals(['one.txt', 'two.txt']));
    expect(repo.autoFetchIssue, isNull);
    expect(merging(mainClone), isFalse);
  }, skip: skip);
}
