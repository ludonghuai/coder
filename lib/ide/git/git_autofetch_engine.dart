// The workspace-level automatic Git fetch: every repository of the
// workspace is fetched as the app runs (and when the window comes back to
// the front), and a branch that is clean, behind its upstream and free of
// buffered conflicts is fast-forwarded. Network failures are retried
// quietly; only what needs the user is told.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'git_autofetch.dart';
import 'git_model.dart';
import 'git_pull.dart';
import 'git_repository.dart';

/// An open document, as the engine sees it: where it is, and whether it has
/// unsaved changes.
typedef IdeGitAutoFetchDocument = ({String path, bool dirty, bool isFile});

/// The automatic fetch and fast-forward of a workspace's repositories.
///
/// One per IDE workbench: the workbench is what stays alive with its
/// workspace (a Source Control view comes and goes), and the repositories
/// are the workspace's. Its rounds never overlap: a round that is asked for
/// again is the one running.
class IdeGitAutoFetch {
  IdeGitAutoFetch({
    required this.repositories,
    required this.documents,
    required this.reload,
    required this.setting,
    required this.paths,
    required this.settingsChanges,
    required this.onNeedsAttention,
    this.workspaceChanges,
    this.emptyRetryDelay = discoveryDelay,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now {
    settingsChanges.addListener(_settingsChanged);
    workspaceChanges?.addListener(_workspaceChanged);
    _enabledSeen = _enabled;
    _periodSeen = _period;
  }

  /// The workspace's repositories with their roots, as Source Control lists
  /// them.
  final List<(String root, IdeGitRepository git)> Function() repositories;

  /// The documents open in the workspace.
  final List<IdeGitAutoFetchDocument> Function() documents;

  /// Reads [paths] again in the workspace's open documents.
  final Future<void> Function(Iterable<String> paths) reload;

  /// settings.json's value for [key].
  final Object? Function(String key) setting;

  /// The workspace's paths: the roots' spelling, and how its paths are
  /// compared.
  final p.Context paths;

  /// settings.json, as it changes.
  final Listenable settingsChanges;

  /// Told when an issue needs the user; never twice for the same one.
  final void Function(IdeGitAutoFetchIssue issue, String root) onNeedsAttention;

  /// The workspace, as repositories are found in it.
  final Listenable? workspaceChanges;

  final DateTime Function() clock;

  /// How many repositories are fetched at once: seventeen Git processes at
  /// the same moment make the proxy and the handles stutter.
  static const workers = 4;

  /// How long after start the first round runs: the scan of the workspace
  /// and the first screen come first.
  static const startDelay = Duration(seconds: 3);

  /// How long after new repositories are found their round runs.
  static const discoveryDelay = Duration(seconds: 2);

  /// How soon a round that found no repository is retried: the workspace
  /// may still be discovering them (a few times, then the period).
  final Duration emptyRetryDelay;

  /// How many rounds in a row may find no repository before the retry
  /// leaves it to the period.
  static const emptyRetryLimit = 3;

  /// How long a resume waits after a round started: alt-tabbing back and
  /// forth does not fetch each time.
  static const resumeDebounce = Duration(seconds: 5);

  Timer? _startTimer;
  Timer? _periodTimer;
  Timer? _discoveryTimer;
  Future<void>? _running;
  DateTime? _startedAt;

  /// The rounds in a row that found no repository (see [emptyRetryDelay]).
  int _emptyRounds = 0;

  /// The switch and the period as they were last seen: a settings change
  /// that leaves them alone has nothing to reschedule.
  bool _enabledSeen = false;
  Duration _periodSeen = Duration.zero;
  final Set<String> _knownRoots = {};

  /// The last issue told, by repository: the same one is told once.
  final Map<String, String> _notified = {};
  bool _disposed = false;

  /// The fetches under way, by repository: one a second workbench asks for
  /// is the one running, not another.
  static final Map<String, Future<void>> _inFlight = {};

  /// Forgets the fetches under way, for a test that starts its own.
  @visibleForTesting
  static void clearInFlight() => _inFlight.clear();

  /// Whether the automatic fetch is on: the total switch, which also stops
  /// any fast-forward.
  bool get _enabled => ideGitAutofetchEnabled(setting(gitAutofetchSetting));

  /// Whether fetched commits are fast-forwarded into the branch.
  bool get _autoPull => ideGitAutoPullEnabled(setting(gitAutoPullSetting));

  /// Seconds between two rounds.
  Duration get _period => Duration(
    seconds: ideGitAutofetchPeriod(setting(gitAutofetchPeriodSetting)),
  );

  /// Starts: the first round after [startDelay], then one per period.
  void start() {
    if (_disposed || !_enabled) return;
    _emptyRounds = 0;
    _startTimer?.cancel();
    _startTimer = Timer(startDelay, () => unawaited(runNow()));
  }

  /// Fetches now, unless a round is running (that one is returned) or the
  /// switch is off: then nothing runs, and nothing is scheduled.
  Future<void> runNow() {
    if (_disposed) return Future.value();
    if (!_enabled) {
      _cancelTimers();
      return Future.value();
    }
    final running = _running;
    if (running != null) return running;
    _startedAt = clock();
    late final Future<void> round;
    round = _run().whenComplete(() {
      if (identical(_running, round)) _running = null;
      if (!_disposed) _scheduleNext();
    });
    return _running = round;
  }

  /// The window came back to the front: a round, unless one started less
  /// than [resumeDebounce] ago.
  void resume() {
    if (_disposed || !_enabled) return;
    final startedAt = _startedAt;
    if (startedAt != null && clock().difference(startedAt) < resumeDebounce) {
      return;
    }
    unawaited(runNow());
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelTimers();
    settingsChanges.removeListener(_settingsChanged);
    workspaceChanges?.removeListener(_workspaceChanged);
  }

  void _cancelTimers() {
    _startTimer?.cancel();
    _periodTimer?.cancel();
    _discoveryTimer?.cancel();
  }

  void _scheduleNext() {
    _periodTimer?.cancel();
    if (_disposed || !_enabled) return;
    _periodTimer = Timer(_period, () => unawaited(runNow()));
  }

  void _settingsChanged() {
    if (_disposed) return;
    final enabled = _enabled;
    final period = _period;
    final turnedOn = enabled && !_enabledSeen;
    final periodChanged = enabled && period != _periodSeen;
    _enabledSeen = enabled;
    _periodSeen = period;
    if (!enabled) {
      _cancelTimers();
      return;
    }
    // Another setting was written: the next round stays when it was.
    if (!turnedOn && !periodChanged) return;
    // Turned on, or asked for another period: the next round comes like a
    // start's, not a whole period away.
    _cancelTimers();
    start();
  }

  void _workspaceChanged() {
    if (_disposed || !_enabled) return;
    final roots = <String>{};
    try {
      for (final (_, git) in repositories()) {
        roots.add(git.service.root);
      }
    } catch (_) {
      return;
    }
    final added = roots.difference(_knownRoots);
    if (added.isEmpty) return;
    _knownRoots.addAll(added);
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer(discoveryDelay, () => unawaited(runNow()));
  }

  /// One round: every repository once, [workers] at a time. A repository
  /// that fails, or is busy with something the user asked for, is left for
  /// the next round.
  Future<void> _run() async {
    final snapshot = <(String, IdeGitRepository)>[];
    try {
      final seen = <String>{};
      for (final (_, git) in repositories()) {
        final root = git.service.root;
        if (seen.add(root)) snapshot.add((root, git));
      }
    } catch (_) {
      _retryWhenEmpty();
      return;
    }
    if (snapshot.isEmpty) {
      _retryWhenEmpty();
      return;
    }
    _emptyRounds = 0;
    var next = 0;
    Future<void> worker() async {
      while (!_disposed) {
        final index = next++;
        if (index >= snapshot.length) return;
        try {
          await _round(snapshot[index]);
        } catch (_) {
          // Whatever went wrong with one repository, the others go on.
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < math.min(workers, snapshot.length); i++) worker(),
    ]);
  }

  /// A round with no repository can be the workspace still discovering
  /// them (the engine attaches before the scan ends): retried a few seconds
  /// apart, then left to the period.
  void _retryWhenEmpty() {
    if (_disposed || !_enabled) return;
    if (_emptyRounds >= emptyRetryLimit) return;
    _emptyRounds++;
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer(emptyRetryDelay, () => unawaited(runNow()));
  }

  Future<void> _round((String, IdeGitRepository) entry) async {
    final (root, git) = entry;
    if (git.busy) return;
    // One fetch of a repository in this process: a second workbench showing
    // it (its folder, or a folder in it) waits for this one.
    final key = git.state?.root ?? root;
    if (_inFlight.containsKey(key)) return;
    late final Future<void> work;
    work = _fetchAndPull(git).whenComplete(() {
      if (identical(_inFlight[key], work)) _inFlight.remove(key);
    });
    _inFlight[key] = work;
    await work;
  }

  Future<void> _fetchAndPull(IdeGitRepository git) async {
    IdeGitAutoFetchIssue? issue;
    var updated = const <String>[];
    String? root;
    if (_autoPull && !_disposed) {
      try {
        final outcome = await git.pullFromUpstream(
          mode: IdeGitPullMode.fastForwardOnly,
          veto: _veto,
        );
        issue = outcome.issue;
        updated = outcome.updated;
        root = outcome.root;
      } catch (error) {
        issue = ideGitFailureOf(error);
      }
    } else {
      try {
        await git.fetch();
      } catch (error) {
        issue = ideGitFailureOf(error);
      }
    }
    if (_disposed) return;
    if (updated.isNotEmpty) {
      try {
        await reload(updated);
      } catch (_) {
        // The workspace could not read them again (it may be going): the
        // files on disk are updated all the same.
      }
      if (_disposed) return;
      // A buffer that took one of the files while the merge ran: the
      // reload left it as it was.
      final wanted = {
        for (final path in updated) ideGitAutoPullKey(paths, path),
      };
      final late = [
        for (final path in _dirtyUnder(root ?? git.service.root))
          if (wanted.contains(ideGitAutoPullKey(paths, path))) path,
      ];
      if (late.isNotEmpty) {
        issue = IdeGitAutoFetchIssue(
          IdeGitAutoFetchKind.buffered,
          paths: late,
        );
      }
    }
    git.autoFetchIssue = issue;
    final tellRoot = git.service.root;
    final told = _notified[tellRoot];
    if (issue == null) {
      _notified.remove(tellRoot);
    } else if (issue.key != told) {
      if (issue.needsAttention) {
        _notified[tellRoot] = issue.key;
        onNeedsAttention(issue, tellRoot);
      } else {
        // A skip the user need not act on: what was told before is over.
        _notified.remove(tellRoot);
      }
    }
  }

  /// Whether a repository's branch may be pulled this round, and why not:
  /// the A policy (clean, behind, no buffer over the upstream's files),
  /// then the switch again — turned off in the middle of a round, nothing
  /// more changes the working tree.
  ({bool pull, IdeGitAutoFetchIssue? issue}) _veto(
    IdeGitState state,
    List<String> incoming,
  ) {
    final blocker = ideGitAutoPullBlocker(
      head: state.head,
      hasChanges: state.resources.isNotEmpty,
      didHitLimit: state.didHitLimit,
    );
    if (blocker != null) {
      final kind = blocker.issueKind;
      return (
        pull: false,
        issue: kind == null ? null : IdeGitAutoFetchIssue(kind),
      );
    }
    final decision = decideAutoPull(
      head: state.head,
      hasChanges: state.resources.isNotEmpty,
      didHitLimit: state.didHitLimit,
      dirtyPaths: _dirtyUnder(state.root),
      incomingPaths: incoming,
      paths: paths,
    );
    if (decision.action != IdeGitAutoPullAction.pull) {
      final kind = decision.action.issueKind;
      return (
        pull: false,
        issue: kind == null
            ? null
            : IdeGitAutoFetchIssue(kind, paths: decision.intersecting),
      );
    }
    if (_disposed || !_enabled) return (pull: false, issue: null);
    return (pull: true, issue: null);
  }

  /// The open documents with unsaved changes under [repositoryRoot] (the
  /// repository's top level).
  List<String> _dirtyUnder(String repositoryRoot) => [
    for (final document in documents())
      if (document.isFile &&
          document.dirty &&
          paths.isWithin(repositoryRoot, document.path))
        document.path,
  ];
}
