import 'dart:async';

import 'package:baocode/ide/git/git_autofetch.dart';
import 'package:baocode/ide/git/git_autofetch_engine.dart';
import 'package:baocode/ide/git/git_model.dart';
import 'package:baocode/ide/git/git_pull.dart';
import 'package:baocode/ide/git/git_repository.dart';
import 'package:baocode/ide/git/git_service.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:bao_remote/local.dart'
    show
        IdeGitOutput,
        gitLocalTimeout,
        gitProcessEnvironmentMap,
        gitRemoteTimeout,
        gitTimeoutFor,
        setGitProcessEnvironment;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fake_git.dart';

final _posix = p.Context(style: p.Style.posix);
final _windows = p.Context(style: p.Style.windows);

/// settings.json under test: a map that tells when it changes.
class _Settings extends ChangeNotifier {
  _Settings([Map<String, Object?> values = const {}]) : _values = {...values};

  final Map<String, Object?> _values;

  Object? operator [](String key) => _values[key];

  void set(String key, Object? value) {
    _values[key] = value;
    notifyListeners();
  }
}

class _Repo {
  _Repo(this.root, p.Context context) : git = FakeGit(root) {
    repository = IdeGitRepository(
      IdeGitService(
        root,
        runner: git.run,
        watcher: (_) => const Stream.empty(),
        pathContext: context,
      ),
      refreshDelay: Duration.zero,
    );
  }

  final String root;
  final FakeGit git;
  late final IdeGitRepository repository;
}

/// A workspace of fake repositories and the engine over it.
class _Harness {
  _Harness({
    p.Context? pathContext,
    List<String> roots = const ['/project'],
    Map<String, Object?> settings = const {},
    Duration emptyRetryDelay = const Duration(milliseconds: 30),
  }) : context = pathContext ?? _posix,
       settings = _Settings(settings) {
    for (final root in roots) {
      repos.add(_Repo(root, context));
    }
    engine = IdeGitAutoFetch(
      repositories: () => [
        for (final repo in repos) (repo.root, repo.repository),
      ],
      documents: () => documents,
      reload: (paths) async => reloaded.addAll(paths),
      setting: (key) => this.settings[key],
      paths: context,
      settingsChanges: this.settings,
      onNeedsAttention: (issue, root) => told.add((root, issue)),
      emptyRetryDelay: emptyRetryDelay,
      clock: () => DateTime(2026, 10, 19, 2, 30),
    );
  }

  final p.Context context;
  final _Settings settings;
  final List<_Repo> repos = [];
  final List<IdeGitAutoFetchDocument> documents = [];
  final List<String> reloaded = [];
  final List<(String, IdeGitAutoFetchIssue)> told = [];
  late final IdeGitAutoFetch engine;

  _Repo get only => repos.single;

  _Repo repo(String root) => repos.firstWhere((repo) => repo.root == root);

  /// Reads every repository's status once, as the workbench does before the
  /// engine's first round.
  Future<void> ready() async {
    for (final repo in repos) {
      await repo.repository.refresh();
    }
  }

  Future<void> round() async {
    await engine.runNow();
    // What the round wrote settles in the microtasks after it.
    await Future<void>.delayed(Duration.zero);
  }

  void dispose() {
    engine.dispose();
    for (final repo in repos) {
      repo.repository.dispose();
    }
  }
}

/// The branch [branch], tracking [upstream], so many commits either way.
IdeGitHead _head({
  String? branch = 'main',
  String? upstream = 'origin/main',
  int ahead = 0,
  int behind = 2,
  bool unborn = false,
}) => IdeGitHead(
  branch: branch,
  upstream: upstream,
  ahead: ahead,
  behind: behind,
  unborn: unborn,
);

IdeGitAutoPullDecision _decide({
  IdeGitHead? head,
  bool hasChanges = false,
  bool didHitLimit = false,
  List<String> dirtyPaths = const [],
  List<String> incomingPaths = const [],
  p.Context? paths,
}) => decideAutoPull(
  head: head ?? _head(),
  hasChanges: hasChanges,
  didHitLimit: didHitLimit,
  dirtyPaths: dirtyPaths,
  incomingPaths: incomingPaths,
  paths: paths ?? _posix,
);

void main() {
  setUp(IdeGitAutoFetch.clearInFlight);

  tearDown(() {
    setGitProcessEnvironment(null);
    IdeGitAutoFetch.clearInFlight();
  });

  group('settings', () {
    test('autofetch is off only where it is false', () {
      expect(ideGitAutofetchEnabled(null), isTrue);
      expect(ideGitAutofetchEnabled(true), isTrue);
      expect(ideGitAutofetchEnabled('all'), isTrue);
      expect(ideGitAutofetchEnabled(false), isFalse);
    });

    test('autoPull is off only where it is false', () {
      expect(ideGitAutoPullEnabled(null), isTrue);
      expect(ideGitAutoPullEnabled(true), isTrue);
      expect(ideGitAutoPullEnabled(false), isFalse);
    });

    test('the period is seconds within 30 and 3600, else three minutes', () {
      expect(ideGitAutofetchPeriod(null), 180);
      expect(ideGitAutofetchPeriod('x'), 180);
      expect(ideGitAutofetchPeriod(0), 180);
      expect(ideGitAutofetchPeriod(-5), 180);
      expect(ideGitAutofetchPeriod(10), 30);
      expect(ideGitAutofetchPeriod(7200), 3600);
      expect(ideGitAutofetchPeriod(60), 60);
      expect(ideGitAutofetchPeriod(90.4), 90);
    });
  });

  group('decideAutoPull', () {
    test('N1: clean, behind and no buffer over the change pulls', () {
      final decision = _decide(incomingPaths: ['/project/lib/a.dart']);
      expect(decision.action, IdeGitAutoPullAction.pull);
      expect(decision.intersecting, isEmpty);
    });

    test('B1: no upstream, detached and unborn have nothing to do', () {
      expect(
        _decide(head: _head(upstream: null)).action,
        IdeGitAutoPullAction.nothing,
      );
      expect(
        _decide(head: _head(branch: null)).action,
        IdeGitAutoPullAction.nothing,
      );
      expect(
        _decide(head: _head(unborn: true)).action,
        IdeGitAutoPullAction.nothing,
      );
      expect(
        _decide(head: _head(behind: 0)).action,
        IdeGitAutoPullAction.nothing,
      );
    });

    test('B2: a change in the working tree does not pull', () {
      expect(_decide(hasChanges: true).action, IdeGitAutoPullAction.dirty);
    });

    test('B3: a branch that kept its own commits does not pull', () {
      expect(
        _decide(head: _head(ahead: 1, behind: 2)).action,
        IdeGitAutoPullAction.diverged,
      );
    });

    test('B4: an unsaved buffer over the same file does not pull', () {
      final decision = _decide(
        dirtyPaths: ['/project/lib/a.dart'],
        incomingPaths: ['/project/lib/a.dart', '/project/lib/b.dart'],
      );
      expect(decision.action, IdeGitAutoPullAction.buffered);
      expect(decision.intersecting, ['/project/lib/a.dart']);
    });

    test('B5: a buffer over another file pulls', () {
      final decision = _decide(
        dirtyPaths: ['/project/lib/b.dart'],
        incomingPaths: ['/project/lib/a.dart'],
      );
      expect(decision.action, IdeGitAutoPullAction.pull);
      expect(decision.intersecting, isEmpty);
    });

    test('B6: a status past its limit does not pull', () {
      expect(
        _decide(didHitLimit: true, hasChanges: true).action,
        IdeGitAutoPullAction.limit,
      );
    });

    test('B15: Windows compares the paths without case', () {
      final decision = _decide(
        dirtyPaths: [r'C:\project\lib\a.dart'],
        incomingPaths: [r'C:\project\Lib\A.dart'],
        paths: _windows,
      );
      expect(decision.action, IdeGitAutoPullAction.buffered);
      expect(decision.intersecting, [r'C:\project\Lib\A.dart']);
    });

    test('elsewhere the case tells two paths apart', () {
      final decision = _decide(
        dirtyPaths: ['/project/lib/a.dart'],
        incomingPaths: ['/project/Lib/A.dart'],
      );
      expect(decision.action, IdeGitAutoPullAction.pull);
    });
  });

  group('failures', () {
    test('E1: a remote that cannot be reached is the network', () {
      final issue = ideGitFailureOf(
        const IdeGitException(
          'Cannot fetch.\nfatal: unable to access https://github.com/a/b/): '
          'Could not resolve host: github.com',
        ),
      );
      expect(issue.kind, IdeGitAutoFetchKind.network);
      expect(issue.needsAttention, isFalse);
      expect(issue.detail, contains('Could not resolve host'));
    });

    test('E2: a sign-in Git cannot ask for is auth', () {
      expect(
        ideGitFailureOf(
          const IdeGitException(
            'Cannot fetch.\nfatal: could not read Username for '
            "'https://github.com': terminal prompts disabled",
          ),
        ).kind,
        IdeGitAutoFetchKind.auth,
      );
      expect(
        ideGitFailureOf(const IdeGitException('error: 403')).kind,
        IdeGitAutoFetchKind.auth,
      );
      // A 403 wins over the "unable to access" the same line carries.
      expect(
        ideGitFailureOf(
          const IdeGitException(
            'fatal: unable to access https://github.com/a/b/: '
            'The requested URL returned error: 403',
          ),
        ).kind,
        IdeGitAutoFetchKind.auth,
      );
    });

    test('E3: a proxy that cannot be reached is the proxy', () {
      expect(
        ideGitFailureOf(
          const IdeGitException('fatal: CONNECT tunnel failed, response 502'),
        ).kind,
        IdeGitAutoFetchKind.proxy,
      );
    });

    test('E6 and B13: what Git refused is a conflict', () {
      for (final message in [
        'error: would clobber existing tag',
        'fatal: Not possible to fast-forward, aborting.',
        'error: Your local changes to the following files would be '
            'overwritten by merge:',
        'error: Merging is not possible because you have unresolved conflict',
        'fatal: Exiting because of an unresolved conflict.',
        'error: You have not concluded your merge (MERGE_HEAD exists).',
      ]) {
        expect(
          ideGitFailureOf(IdeGitException(message)).kind,
          IdeGitAutoFetchKind.conflict,
          reason: message,
        );
      }
    });

    test('anything else is other, with Git\'s words kept', () {
      final issue = ideGitFailureOf(
        const IdeGitException('Cannot fetch.\nerror: cannot lock ref'),
      );
      expect(issue.kind, IdeGitAutoFetchKind.other);
      expect(issue.detail, contains('cannot lock ref'));
      expect(issue.needsAttention, isFalse);
    });

    test('an issue is told once per kind and files', () {
      const first = IdeGitAutoFetchIssue(
        IdeGitAutoFetchKind.buffered,
        paths: ['/project/lib/a.dart'],
      );
      const same = IdeGitAutoFetchIssue(
        IdeGitAutoFetchKind.buffered,
        paths: ['/project/lib/a.dart'],
      );
      const other = IdeGitAutoFetchIssue(IdeGitAutoFetchKind.buffered);
      expect(first, same);
      expect(first.key, same.key);
      expect(first.key, isNot(other.key));
      expect(first.needsAttention, isTrue);
      expect(
        const IdeGitAutoFetchIssue(IdeGitAutoFetchKind.dirty).needsAttention,
        isFalse,
      );
    });

    test('the message names the repository and up to three files', () {
      final l10n = englishLocalizations;
      const issue = IdeGitAutoFetchIssue(
        IdeGitAutoFetchKind.buffered,
        paths: [
          '/project/lib/a.dart',
          '/project/lib/b.dart',
          '/project/lib/c.dart',
          '/project/lib/d.dart',
        ],
      );
      final message = ideGitAutoFetchMessage(
        l10n,
        issue,
        repository: 'project',
      );
      expect(message, contains('project'));
      expect(message, contains('a.dart'));
      expect(message, isNot(contains('d.dart')));
      expect(message, contains('and more'));
    });

    test('the tooltip adds Git\'s words, the notification alone does not', () {
      final l10n = englishLocalizations;
      const issue = IdeGitAutoFetchIssue(
        IdeGitAutoFetchKind.auth,
        detail: 'fatal: Authentication failed',
      );
      expect(
        ideGitAutoFetchMessage(l10n, issue, repository: 'project'),
        isNot(contains('Authentication failed')),
      );
      expect(
        ideGitAutoFetchTooltip(l10n, issue, repository: 'project'),
        contains('Authentication failed'),
      );
    });
  });

  test('the last fetch is a clock, or the day too', () {
    expect(
      ideGitFetchedAt(
        DateTime(2026, 10, 19, 2, 5),
        now: DateTime(2026, 10, 19, 9),
      ),
      '02:05',
    );
    expect(
      ideGitFetchedAt(
        DateTime(2026, 10, 18, 2, 5),
        now: DateTime(2026, 10, 19, 9),
      ),
      '10-18 02:05',
    );
  });

  group('Git processes', () {
    test('remote commands get five minutes, the others one', () {
      expect(gitTimeoutFor(['fetch', '--all', '--tags']), gitRemoteTimeout);
      expect(gitTimeoutFor(['ls-remote', 'origin']), gitRemoteTimeout);
      // A merge writes the working tree: killed early, half a merge stays.
      expect(
        gitTimeoutFor(['merge', '--ff-only', 'origin/main']),
        gitRemoteTimeout,
      );
      expect(
        gitTimeoutFor(['merge', '--no-edit', 'origin/main']),
        gitRemoteTimeout,
      );
      expect(gitTimeoutFor(['merge', '--abort']), gitRemoteTimeout);
      expect(
        gitTimeoutFor(['status', '-z', '--porcelain=v1']),
        gitLocalTimeout,
      );
      // The command is the first argument that is not a global option.
      expect(
        gitTimeoutFor([
          '-c',
          'i18n.logOutputEncoding=UTF-8',
          'blame',
          '--root',
        ]),
        gitLocalTimeout,
      );
      expect(gitTimeoutFor(const []), gitLocalTimeout);
    });

    test('the app adds its variables over the ones Git is given', () {
      expect(gitProcessEnvironmentMap()['GIT_TERMINAL_PROMPT'], '0');
      expect(gitProcessEnvironmentMap().containsKey('HTTPS_PROXY'), isFalse);
      setGitProcessEnvironment(
        () => {
          'HTTPS_PROXY': 'http://127.0.0.1:7890',
          'https_proxy': 'http://127.0.0.1:7890',
          'NO_PROXY': 'localhost',
        },
      );
      final environment = gitProcessEnvironmentMap();
      expect(environment['HTTPS_PROXY'], 'http://127.0.0.1:7890');
      expect(environment['https_proxy'], 'http://127.0.0.1:7890');
      expect(environment['NO_PROXY'], 'localhost');
      expect(environment['GIT_EDITOR'], 'true');
    });

    test('with the proxy off the variables are cleared', () {
      setGitProcessEnvironment(
        () => {
          'HTTP_PROXY': '',
          'http_proxy': '',
          'HTTPS_PROXY': '',
          'https_proxy': '',
        },
      );
      final environment = gitProcessEnvironmentMap();
      expect(environment['HTTP_PROXY'], '');
      expect(environment['HTTPS_PROXY'], '');
    });

    test('the closure is read for each process', () {
      var proxy = 'http://a:1';
      setGitProcessEnvironment(() => {'HTTPS_PROXY': proxy});
      expect(gitProcessEnvironmentMap()['HTTPS_PROXY'], 'http://a:1');
      proxy = 'http://b:2';
      expect(gitProcessEnvironmentMap()['HTTPS_PROXY'], 'http://b:2');
    });
  });

  group('the service', () {
    test('fast-forwards with merge --ff-only', () async {
      final git = FakeGit('/project');
      final service = IdeGitService(
        '/project',
        runner: git.run,
        pathContext: _posix,
      );
      await service.fastForward('origin/main');
      expect(git.callsTo('merge').single, [
        'merge',
        '--ff-only',
        'origin/main',
      ]);
    });

    test('B14: changed paths are under the repository top', () async {
      final git = FakeGit('/project');
      final service = IdeGitService(
        '/project/sub',
        runner: git.run,
        pathContext: _posix,
      );
      await service.repositoryRoot();
      git.changedFiles['HEAD origin/main'] = ['lib/a.dart', 'README.md'];
      expect(await service.changedPaths('HEAD', 'origin/main'), [
        '/project/lib/a.dart',
        '/project/README.md',
      ]);
    });

    test('a repository notes when its remote last came in', () async {
      final git = FakeGit('/project');
      final at = DateTime(2026, 10, 19, 2, 15);
      final repository = IdeGitRepository(
        IdeGitService('/project', runner: git.run, pathContext: _posix),
        refreshDelay: Duration.zero,
        clock: () => at,
      );
      addTearDown(repository.dispose);
      await repository.refresh();
      expect(repository.lastFetchAt, isNull);
      await repository.fetch();
      expect(repository.lastFetchAt, at);
      await repository.fastForward('origin/main');
      expect(git.callsTo('merge').single, [
        'merge',
        '--ff-only',
        'origin/main',
      ]);
    });
  });

  group('the engine', () {
    test('P1: a round with no repository yet is retried sooner than the '
        'period', () async {
      final harness = _Harness(roots: const []);
      addTearDown(harness.dispose);

      // The engine attaches before the workspace's scan has repositories.
      await harness.round();
      final repo = _Repo('/project', harness.context);
      repo.git.status = '## main...origin/main\x00';
      harness.repos.add(repo);

      // The empty round schedules a retry, and the repository is found then.
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(repo.git.callsTo('fetch').single, ['fetch', '--all', '--tags']);
      expect(repo.repository.lastFetchAt, isNotNull);
    });

    test('N1: a clean branch behind is fetched and fast-forwarded', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final repo = harness.only;
      repo.git.status = '## main...origin/main [behind 2]\x00';
      repo.git.changedFiles['HEAD origin/main'] = ['lib/a.dart'];
      await harness.ready();

      await harness.round();

      expect(repo.git.callsTo('fetch').single, ['fetch', '--all', '--tags']);
      expect(repo.git.callsTo('merge').single, [
        'merge',
        '--ff-only',
        'origin/main',
      ]);
      expect(harness.reloaded, ['/project/lib/a.dart']);
      expect(repo.repository.lastFetchAt, isNotNull);
      expect(repo.repository.autoFetchIssue, isNull);
      expect(harness.told, isEmpty);
    });

    test('N2: nothing behind is fetched alone', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final repo = harness.only;
      repo.git.status = '## main...origin/main\x00';
      await harness.ready();

      await harness.round();

      expect(repo.git.callsTo('fetch'), hasLength(1));
      expect(repo.git.callsTo('merge'), isEmpty);
      expect(harness.reloaded, isEmpty);
      expect(repo.repository.autoFetchIssue, isNull);
    });

    test('B2: a change in the working tree keeps the commits out', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final repo = harness.only;
      repo.git.status = '## main...origin/main [behind 2]\x00?? a.txt\x00';
      await harness.ready();

      await harness.round();

      expect(repo.git.callsTo('fetch'), hasLength(1));
      expect(repo.git.callsTo('merge'), isEmpty);
      expect(repo.repository.autoFetchIssue?.kind, IdeGitAutoFetchKind.dirty);
      expect(harness.told, isEmpty);
    });

    test('B3: a branch ahead of its upstream is not pulled', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final repo = harness.only;
      repo.git.status = '## main...origin/main [ahead 1, behind 2]\x00';
      await harness.ready();

      await harness.round();

      expect(repo.git.callsTo('merge'), isEmpty);
      expect(
        repo.repository.autoFetchIssue?.kind,
        IdeGitAutoFetchKind.diverged,
      );
    });

    test(
      'B4: a buffer over the remote\'s file stops the pull until saved',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final repo = harness.only;
        repo.git.status = '## main...origin/main [behind 1]\x00';
        repo.git.changedFiles['HEAD origin/main'] = ['lib/a.dart'];
        harness.documents.add((
          path: '/project/lib/a.dart',
          dirty: true,
          isFile: true,
        ));
        await harness.ready();

        await harness.round();

        expect(repo.git.callsTo('merge'), isEmpty);
        expect(harness.reloaded, isEmpty);
        final issue = repo.repository.autoFetchIssue!;
        expect(issue.kind, IdeGitAutoFetchKind.buffered);
        expect(issue.paths, ['/project/lib/a.dart']);
        expect(harness.told, hasLength(1));
        expect(harness.told.single.$2.kind, IdeGitAutoFetchKind.buffered);

        // Saved: the next round pulls.
        harness.documents.clear();
        await harness.round();
        expect(repo.git.callsTo('merge'), hasLength(1));
        expect(repo.repository.autoFetchIssue, isNull);
      },
    );

    test('B5: a buffer over another file does not stop the pull', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final repo = harness.only;
      repo.git.status = '## main...origin/main [behind 1]\x00';
      repo.git.changedFiles['HEAD origin/main'] = ['lib/a.dart'];
      harness.documents.add((
        path: '/project/lib/b.dart',
        dirty: true,
        isFile: true,
      ));
      await harness.ready();

      await harness.round();

      expect(repo.git.callsTo('merge'), hasLength(1));
      expect(harness.reloaded, ['/project/lib/a.dart']);
    });

    test('B8: with autofetch off no round runs', () async {
      final harness = _Harness(settings: {'git.autofetch': false});
      addTearDown(harness.dispose);
      final repo = harness.only;
      repo.git.status = '## main...origin/main [behind 2]\x00';
      await harness.ready();
      final before = repo.git.calls.length;

      await harness.round();

      expect(repo.git.calls.length, before);
      expect(repo.git.callsTo('fetch'), isEmpty);
      expect(repo.git.callsTo('merge'), isEmpty);
    });

    test('B8: turned off in a round, no fast-forward starts', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final repo = harness.only;
      repo.git.status = '## main...origin/main [behind 2]\x00';
      repo.git.hold = (arguments) async {
        if (arguments.first == 'fetch') {
          harness.settings.set('git.autofetch', false);
        }
      };
      await harness.ready();

      await harness.round();

      expect(repo.git.callsTo('fetch'), hasLength(1));
      expect(repo.git.callsTo('merge'), isEmpty);
      expect(harness.reloaded, isEmpty);
    });

    test('B9: with autoPull off the fetch alone runs', () async {
      final harness = _Harness(settings: {'git.autoPull': false});
      addTearDown(harness.dispose);
      final repo = harness.only;
      repo.git.status = '## main...origin/main [behind 2]\x00';
      await harness.ready();

      await harness.round();

      expect(repo.git.callsTo('fetch'), hasLength(1));
      expect(repo.git.callsTo('merge'), isEmpty);
      expect(repo.repository.autoFetchIssue, isNull);
    });

    test('T5: a status that cannot be read is an issue, not silence',
        () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final repo = harness.only;
      repo.git.status = '## main...origin/main [behind 2]\x00';
      repo.git.answers['status'] = const IdeGitOutput(
        128,
        '',
        'fatal: unable to read the index',
      );
      await harness.ready();

      await harness.round();

      expect(repo.repository.autoFetchIssue?.kind, IdeGitAutoFetchKind.other);
      expect(repo.git.callsTo('merge'), isEmpty);
      expect(harness.reloaded, isEmpty);
    });

    test('T6: a repository busy with the user is left for the next round',
        () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final repo = harness.only;
      repo.git.status = '## main...origin/main [behind 2]\x00';
      await harness.ready();
      final gate = Completer<void>();
      repo.git.hold = (arguments) async {
        if (arguments.first == 'add') await gate.future;
      };
      final staged = repo.repository.stageAll();
      for (var i = 0; i < 20 && repo.git.callsTo('add').isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(repo.repository.busy, isTrue);

      await harness.round();

      expect(repo.git.callsTo('fetch'), isEmpty);
      gate.complete();
      await staged;
    });

    test('T9: the pull reads the status, not the cache', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final repo = harness.only;
      repo.git.status = '## main...origin/main\x00';
      await harness.ready();
      expect(repo.repository.state!.head.behind, 0);

      // The upstream moved after the status the repository holds.
      repo.git.status = '## main...origin/main [behind 2]\x00';
      repo.git.changedFiles['HEAD origin/main'] = ['lib/a.dart'];
      await harness.round();

      expect(repo.git.callsTo('merge').single, [
        'merge',
        '--ff-only',
        'origin/main',
      ]);
      expect(harness.reloaded, ['/project/lib/a.dart']);
      expect(repo.repository.autoFetchIssue, isNull);
    });

    test('T10: fetched commits behind a dirty tree keep the ↓N', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final repo = harness.only;
      repo.git.status = '## main...origin/main [behind 2]\x00?? a.txt\x00';
      await harness.ready();

      await harness.round();

      expect(repo.git.callsTo('fetch'), hasLength(1));
      expect(repo.git.callsTo('merge'), isEmpty);
      expect(repo.repository.autoFetchIssue?.kind, IdeGitAutoFetchKind.dirty);
      expect(repo.repository.state!.head.behind, 2);
    });

    test('a failed merge whose recheck fails is still aborted, with both '
        'errors\' words', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final repo = harness.only;
      repo.git.status = '## main...origin/main\x00';
      repo.git.mergeCommits['origin/main'] = const IdeGitOutput(
        1,
        '',
        'CONFLICT (content): Merge conflict in a.txt',
      );
      var merged = false;
      repo.git.onCommand = (arguments) {
        if (arguments case ['merge', '--no-edit', _]) merged = true;
        if (!merged) return;
        if (arguments case ['rev-parse', '--verify', '-q', 'MERGE_HEAD']) {
          throw const IdeGitException('Cannot read the merge state.');
        }
      };
      await harness.ready();

      Object? failure;
      try {
        await repo.repository.pullFromUpstream(mode: IdeGitPullMode.merge);
      } catch (error) {
        failure = error;
      }

      // The recheck failed, so the merge may have started: it was aborted.
      expect(
        repo.git.callsTo('merge').map((call) => call.join(' ')),
        contains('merge --abort'),
      );
      expect('$failure', contains('CONFLICT (content): Merge conflict in a.txt'));
      expect('$failure', contains('Cannot read the merge state.'));
    });

    test('a failed merge whose recheck fails and abort fails adds every '
        'word', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final repo = harness.only;
      repo.git.status = '## main...origin/main\x00';
      repo.git.mergeCommits['origin/main'] = const IdeGitOutput(
        1,
        '',
        'CONFLICT (content): Merge conflict in a.txt',
      );
      repo.git.abortMerge = const IdeGitOutput(
        128,
        '',
        'fatal: Unable to abort the merge.',
      );
      var merged = false;
      repo.git.onCommand = (arguments) {
        if (arguments case ['merge', '--no-edit', _]) merged = true;
        if (!merged) return;
        if (arguments case ['rev-parse', '--verify', '-q', 'MERGE_HEAD']) {
          throw const IdeGitException('Cannot read the merge state.');
        }
      };
      await harness.ready();

      Object? failure;
      try {
        await repo.repository.pullFromUpstream(mode: IdeGitPullMode.merge);
      } catch (error) {
        failure = error;
      }

      expect('$failure', contains('CONFLICT (content): Merge conflict in a.txt'));
      expect('$failure', contains('Cannot read the merge state.'));
      expect('$failure', contains('Unable to abort the merge.'));
      expect('$failure', contains('Run "git merge --abort" to finish.'));
    });

    test('T8: one repository failing its fetch leaves the other pulling',
        () async {
      final harness = _Harness(roots: ['/a', '/b']);
      addTearDown(harness.dispose);
      final a = harness.repo('/a');
      final b = harness.repo('/b');
      a.git.status = '## main...origin/main [behind 1]\x00';
      a.git.answers['fetch'] = const IdeGitOutput(
        128,
        '',
        'fatal: unable to access https://example.com/a/: '
            'Could not resolve host: example.com',
      );
      b.git.status = '## main...origin/main [behind 1]\x00';
      b.git.changedFiles['HEAD origin/main'] = ['lib/a.dart'];
      await harness.ready();

      await harness.round();

      expect(a.repository.autoFetchIssue?.kind, IdeGitAutoFetchKind.network);
      expect(b.repository.autoFetchIssue, isNull);
      expect(b.git.callsTo('merge'), hasLength(1));
      expect(harness.reloaded, ['/b/lib/a.dart']);
    });

    test(
      'B13: what Git refuses to fast-forward is a conflict, told once',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final repo = harness.only;
        repo.git.status = '## main...origin/main [behind 1]\x00';
        repo.git.merges['origin/main'] = const IdeGitOutput(
          1,
          '',
          'fatal: Not possible to fast-forward, aborting.',
        );
        await harness.ready();

        await harness.round();
        expect(
          repo.repository.autoFetchIssue?.kind,
          IdeGitAutoFetchKind.conflict,
        );
        expect(harness.told, hasLength(1));

        // The same refusal again: the user was already told.
        await harness.round();
        expect(harness.told, hasLength(1));
      },
    );

    test(
      'E1: a network failure is quiet, and the next round recovers',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final repo = harness.only;
        repo.git.status = '## main...origin/main [behind 1]\x00';
        repo.git.answers['fetch'] = const IdeGitOutput(
          128,
          '',
          'fatal: unable to access https://github.com/a/b/: '
              'Could not resolve host: github.com',
        );
        await harness.ready();

        await harness.round();

        expect(
          repo.repository.autoFetchIssue?.kind,
          IdeGitAutoFetchKind.network,
        );
        expect(harness.told, isEmpty);
        // D12: the refs a fetch could not renew still say where the branch
        // has to go, and the pull is safe.
        expect(repo.git.callsTo('merge'), hasLength(1));

        // The network is back.
        repo.git.answers.remove('fetch');
        await harness.round();

        expect(repo.repository.autoFetchIssue, isNull);
        expect(repo.git.callsTo('merge'), hasLength(2));
      },
    );

    test('E2: a sign-in is told once, not every round', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final repo = harness.only;
      repo.git.status = '## main...origin/main [behind 1]\x00';
      repo.git.answers['fetch'] = const IdeGitOutput(
        128,
        '',
        'fatal: Authentication failed for https://github.com/a/b/',
      );
      await harness.ready();

      await harness.round();
      expect(harness.told, hasLength(1));
      expect(harness.told.single.$1, '/project');
      expect(harness.told.single.$2.kind, IdeGitAutoFetchKind.auth);

      await harness.round();
      expect(harness.told, hasLength(1));
    });

    test('E5: one repository failing leaves the others alone', () async {
      final harness = _Harness(roots: ['/a', '/b']);
      addTearDown(harness.dispose);
      final a = harness.repo('/a');
      final b = harness.repo('/b');
      a.git.status = '## main...origin/main [behind 1]\x00';
      a.git.merges['origin/main'] = const IdeGitOutput(
        1,
        '',
        'fatal: Not possible to fast-forward, aborting.',
      );
      b.git.status = '## main...origin/main [behind 1]\x00';
      b.git.changedFiles['HEAD origin/main'] = ['lib/a.dart'];
      await harness.ready();

      await harness.round();

      expect(a.repository.autoFetchIssue?.kind, IdeGitAutoFetchKind.conflict);
      expect(harness.reloaded, ['/b/lib/a.dart']);
      expect(b.repository.autoFetchIssue, isNull);
      expect(b.repository.lastFetchAt, isNotNull);
      expect(harness.told.map((told) => told.$1), ['/a']);
    });

    test('N3: every repository with a new commit is pulled', () async {
      final harness = _Harness(roots: ['/a', '/b', '/c']);
      addTearDown(harness.dispose);
      for (final repo in harness.repos) {
        repo.git.status = '## main...origin/main [behind 3]\x00';
      }
      await harness.ready();

      await harness.round();

      for (final repo in harness.repos) {
        expect(repo.git.callsTo('fetch'), hasLength(1));
        expect(repo.git.callsTo('merge'), hasLength(1));
      }
    });

    test('B15: a Windows path is matched without case', () async {
      final harness = _Harness(pathContext: _windows, roots: [r'C:\project']);
      addTearDown(harness.dispose);
      final repo = harness.only;
      repo.git.status = '## main...origin/main [behind 1]\x00';
      repo.git.changedFiles['HEAD origin/main'] = ['Lib/A.dart'];
      harness.documents.add((
        path: r'C:\project\lib\a.dart',
        dirty: true,
        isFile: true,
      ));
      await harness.ready();

      await harness.round();

      expect(repo.git.callsTo('merge'), isEmpty);
      expect(
        repo.repository.autoFetchIssue?.kind,
        IdeGitAutoFetchKind.buffered,
      );
      expect(harness.told, hasLength(1));
    });

    test('B14: a folder in a repository sees the buffers above it', () async {
      final harness = _Harness(roots: ['/project/sub']);
      addTearDown(harness.dispose);
      final repo = harness.only;
      // The workspace folder is `/project/sub`, in the repository `/project`.
      repo.git.answers['rev-parse'] = const IdeGitOutput(0, '/project\n');
      repo.git.status = '## main...origin/main [behind 1]\x00';
      repo.git.changedFiles['HEAD origin/main'] = ['lib/a.dart'];
      harness.documents.add((
        path: '/project/lib/a.dart',
        dirty: true,
        isFile: true,
      ));
      await harness.ready();

      await harness.round();

      expect(repo.git.callsTo('merge'), isEmpty);
      expect(harness.reloaded, isEmpty);
      expect(
        repo.repository.autoFetchIssue?.kind,
        IdeGitAutoFetchKind.buffered,
      );
      expect(repo.repository.autoFetchIssue?.paths, ['/project/lib/a.dart']);
    });

    test('a sign-in Git needs is told even when the tree is dirty', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final repo = harness.only;
      repo.git.status = '## main...origin/main [behind 1]\x00 M lib/b.dart\x00';
      repo.git.answers['fetch'] = const IdeGitOutput(
        128,
        '',
        'fatal: Authentication failed for https://github.com/a/b/',
      );
      await harness.ready();

      await harness.round();

      expect(repo.repository.autoFetchIssue?.kind, IdeGitAutoFetchKind.auth);
      expect(harness.told, hasLength(1));

      // The same sign-in again: already told.
      await harness.round();
      expect(harness.told, hasLength(1));
    });
  });
}
