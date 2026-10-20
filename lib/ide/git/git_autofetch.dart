// The policy of the automatic Git fetch: the settings that turn it on, the
// decision whether a repository can be fast-forwarded, and what a failure
// means for the user. No Git runs here: the engine
// (git_autofetch_engine.dart) runs it, and asks this.

import 'package:flutter/foundation.dart' show listEquals;
import 'package:path/path.dart' as p;

import '../../l10n/l10n.dart';
import 'git_model.dart';
import 'git_service.dart';

/// settings.json's: whether the workspace's repositories are fetched as the
/// app runs (VS Code's `git.autofetch`, which also takes `"all"`).
const gitAutofetchSetting = 'git.autofetch';

/// settings.json's: whether a fetched branch is fast-forwarded when it can
/// be (VS Code's `git.autofetch` does both; here they are two switches).
const gitAutoPullSetting = 'git.autoPull';

/// settings.json's: how many seconds pass between two fetches (VS Code's
/// `git.autofetchPeriod`).
const gitAutofetchPeriodSetting = 'git.autofetchPeriod';

/// The period with no setting: VS Code's default, three minutes.
const gitDefaultAutofetchPeriod = 180;

/// The shortest and longest period a setting may ask for.
const gitMinAutofetchPeriod = 30;
const gitMaxAutofetchPeriod = 3600;

/// Whether [value] (the setting) turns the automatic fetch on: only `false`
/// turns it off; unset, `true` and `"all"` leave it on.
bool ideGitAutofetchEnabled(Object? value) => value != false;

/// Whether [value] (the setting) turns the fast-forward on: only `false`
/// turns it off.
bool ideGitAutoPullEnabled(Object? value) => value != false;

/// [value] (the setting) as seconds: a number over 0, kept within
/// [gitMinAutofetchPeriod] and [gitMaxAutofetchPeriod]; not a number (or
/// not over 0) is [gitDefaultAutofetchPeriod].
int ideGitAutofetchPeriod(Object? value) {
  final seconds = switch (value) {
    final int value => value,
    final double value when value.isFinite => value.round(),
    _ => null,
  };
  if (seconds == null || seconds <= 0) return gitDefaultAutofetchPeriod;
  return seconds.clamp(gitMinAutofetchPeriod, gitMaxAutofetchPeriod);
}

/// Why the automatic fetch did not do what a repository's remote offered: a
/// failure Git reported, or a skip the decision made. [auth] wants a
/// sign-in the app cannot give; [conflict] is Git refusing (local changes it
/// would overwrite, a branch that cannot be fast-forwarded, a tag that would
/// be clobbered); [buffered] is a skip where unsaved buffers hold files the
/// remote changed; [network] and [proxy] are a remote or a proxy that could
/// not be reached; [other] is anything else Git said; [dirty], [diverged]
/// and [limit] skip a working tree with changes, a branch that moved on its
/// own, and a status too long to read.
enum IdeGitAutoFetchKind {
  auth,
  conflict,
  buffered,
  network,
  proxy,
  other,
  dirty,
  diverged,
  limit;

  /// Whether the user has to do something about it: those alone notify.
  bool get needsAttention => switch (this) {
    auth || conflict || buffered => true,
    _ => false,
  };
}

/// The last thing the automatic fetch did not do in a repository, and why.
class IdeGitAutoFetchIssue {
  const IdeGitAutoFetchIssue(
    this.kind, {
    this.paths = const [],
    this.detail = '',
  });

  final IdeGitAutoFetchKind kind;

  /// The files both the remote changed and an unsaved buffer holds, as
  /// absolute paths (what [decideAutoPull] found).
  final List<String> paths;

  /// Git's own words, cut short: under the reason in a tooltip, never in a
  /// notification. Empty for a skip.
  final String detail;

  bool get needsAttention => kind.needsAttention;

  /// What tells this problem from another: the same one is told once.
  String get key => '${kind.name}\u0000${paths.join('\u0000')}';

  @override
  bool operator ==(Object other) =>
      other is IdeGitAutoFetchIssue &&
      other.kind == kind &&
      other.detail == detail &&
      listEquals(other.paths, paths);

  @override
  int get hashCode => Object.hash(kind, detail, Object.hashAll(paths));
}

/// What one repository's turn of the automatic fetch comes to.
enum IdeGitAutoPullAction {
  /// Fast-forward: the branch is behind, clean, and no buffer holds what
  /// the remote changed.
  pull,
  nothing,
  dirty,
  diverged,
  limit,
  buffered,
}

/// The issue a skip is shown as; null where there is nothing to show
/// ([IdeGitAutoPullAction.pull] and [IdeGitAutoPullAction.nothing]).
extension IdeGitAutoPullActionIssue on IdeGitAutoPullAction {
  IdeGitAutoFetchKind? get issueKind => switch (this) {
    IdeGitAutoPullAction.pull || IdeGitAutoPullAction.nothing => null,
    IdeGitAutoPullAction.dirty => IdeGitAutoFetchKind.dirty,
    IdeGitAutoPullAction.diverged => IdeGitAutoFetchKind.diverged,
    IdeGitAutoPullAction.limit => IdeGitAutoFetchKind.limit,
    IdeGitAutoPullAction.buffered => IdeGitAutoFetchKind.buffered,
  };
}

/// What [decideAutoPull] came to: the action, and for
/// [IdeGitAutoPullAction.buffered] the files that stopped it.
class IdeGitAutoPullDecision {
  const IdeGitAutoPullDecision(this.action, [this.intersecting = const []]);

  final IdeGitAutoPullAction action;

  /// The files both the remote changed and an unsaved buffer holds, as
  /// absolute paths.
  final List<String> intersecting;
}

/// Why a repository stops before its remote's files are read (and so before
/// the buffered check), or null to go on. [IdeGitAutoPullAction.nothing] is
/// a repository with nothing to do: no branch, no upstream, no commits
/// behind.
IdeGitAutoPullAction? ideGitAutoPullBlocker({
  required IdeGitHead head,
  required bool hasChanges,
  required bool didHitLimit,
}) {
  if (head.branch == null || head.upstream == null || head.unborn) {
    return IdeGitAutoPullAction.nothing;
  }
  if (head.behind == 0) return IdeGitAutoPullAction.nothing;
  if (head.ahead > 0) return IdeGitAutoPullAction.diverged;
  if (didHitLimit) return IdeGitAutoPullAction.limit;
  if (hasChanges) return IdeGitAutoPullAction.dirty;
  return null;
}

/// What to do with one repository: fast-forward it, or the reason not to.
/// [incomingPaths] and [dirtyPaths] are compared in the same path space:
/// [paths] (the workspace's), its [p.Context.normalize], and on Windows
/// without case.
IdeGitAutoPullDecision decideAutoPull({
  required IdeGitHead head,
  required bool hasChanges,
  required bool didHitLimit,
  required Iterable<String> dirtyPaths,
  required Iterable<String> incomingPaths,
  p.Context? paths,
}) {
  final blocker = ideGitAutoPullBlocker(
    head: head,
    hasChanges: hasChanges,
    didHitLimit: didHitLimit,
  );
  if (blocker != null) return IdeGitAutoPullDecision(blocker);
  final context = paths ?? p.context;
  final dirty = {
    for (final path in dirtyPaths) ideGitAutoPullKey(context, path),
  };
  final intersecting = [
    for (final path in incomingPaths)
      if (dirty.contains(ideGitAutoPullKey(context, path))) path,
  ];
  return intersecting.isEmpty
      ? const IdeGitAutoPullDecision(IdeGitAutoPullAction.pull)
      : IdeGitAutoPullDecision(IdeGitAutoPullAction.buffered, intersecting);
}

/// [path] as both sides of [decideAutoPull]'s comparison spell it: the
/// workspace's normalization, and lower case on Windows (its files are the
/// same in either case).
String ideGitAutoPullKey(p.Context paths, String path) {
  final normalized = paths.normalize(path);
  return paths.style == p.Style.windows ? normalized.toLowerCase() : normalized;
}

/// The stderr words that make a failure the user must act on, and those
/// that make it one to retry quietly; the first match wins.
const _failurePatterns = <(String, IdeGitAutoFetchKind)>[
  ('authentication failed', IdeGitAutoFetchKind.auth),
  ('could not read username', IdeGitAutoFetchKind.auth),
  ('terminal prompts disabled', IdeGitAutoFetchKind.auth),
  ('permission denied (publickey)', IdeGitAutoFetchKind.auth),
  ('403', IdeGitAutoFetchKind.auth),
  ('401', IdeGitAutoFetchKind.auth),
  ('407', IdeGitAutoFetchKind.auth),
  ('repository not found', IdeGitAutoFetchKind.auth),
  ('would be overwritten', IdeGitAutoFetchKind.conflict),
  ('not possible to fast-forward', IdeGitAutoFetchKind.conflict),
  ('would clobber existing tag', IdeGitAutoFetchKind.conflict),
  ('unresolved conflict', IdeGitAutoFetchKind.conflict),
  ('not concluded your', IdeGitAutoFetchKind.conflict),
  ('could not resolve host', IdeGitAutoFetchKind.network),
  ('failed to connect', IdeGitAutoFetchKind.network),
  ('connection timed out', IdeGitAutoFetchKind.network),
  ('connection reset', IdeGitAutoFetchKind.network),
  ('unable to access', IdeGitAutoFetchKind.network),
  ('rpc failed', IdeGitAutoFetchKind.network),
  ('early eof', IdeGitAutoFetchKind.network),
  ('remote end hung up', IdeGitAutoFetchKind.network),
  ('did not respond within', IdeGitAutoFetchKind.network),
  ('connect tunnel failed', IdeGitAutoFetchKind.proxy),
  ('proxy connect aborted', IdeGitAutoFetchKind.proxy),
];

/// [error] as the issue it is: which kind it is told as, and Git's words
/// for the tooltip. [IdeGitException]'s message holds the stderr (cut to
/// 500 characters by [IdeGitService]).
IdeGitAutoFetchIssue ideGitFailureOf(Object error) {
  final message = error is IdeGitException ? error.message : '$error';
  final lower = message.toLowerCase();
  for (final (pattern, kind) in _failurePatterns) {
    if (lower.contains(pattern)) {
      return IdeGitAutoFetchIssue(kind, detail: message);
    }
  }
  return IdeGitAutoFetchIssue(IdeGitAutoFetchKind.other, detail: message);
}

/// [issue]'s reason, as the status bar, a repository's tooltip and a
/// notification say it; [repository] is the root folder's name.
String ideGitAutoFetchMessage(
  AppLocalizations l10n,
  IdeGitAutoFetchIssue issue, {
  required String repository,
}) => switch (issue.kind) {
  IdeGitAutoFetchKind.dirty => l10n.gitAutoFetchDirty,
  IdeGitAutoFetchKind.diverged => l10n.gitAutoFetchDiverged,
  IdeGitAutoFetchKind.limit => l10n.gitAutoFetchLimit,
  IdeGitAutoFetchKind.buffered => l10n.gitAutoFetchBuffered(
    repository,
    _filesOf(l10n, issue.paths),
  ),
  IdeGitAutoFetchKind.network => l10n.gitAutoFetchNetwork,
  IdeGitAutoFetchKind.proxy => l10n.gitAutoFetchProxy,
  IdeGitAutoFetchKind.auth => l10n.gitAutoFetchAuth(repository),
  IdeGitAutoFetchKind.conflict => l10n.gitAutoFetchConflict(repository),
  IdeGitAutoFetchKind.other => l10n.gitAutoFetchOther(repository),
};

/// [issue]'s reason with Git's own words under it, for a tooltip: a
/// notification never carries them.
String ideGitAutoFetchTooltip(
  AppLocalizations l10n,
  IdeGitAutoFetchIssue issue, {
  required String repository,
}) {
  final message = ideGitAutoFetchMessage(l10n, issue, repository: repository);
  return issue.detail.isEmpty ? message : '$message\n${issue.detail}';
}

/// The first three of [paths] by name, with "and more" where there are more.
String _filesOf(AppLocalizations l10n, List<String> paths) {
  final names = [for (final path in paths.take(3)) p.basename(path)].join(', ');
  return paths.length > 3 ? l10n.gitAutoFetchFilesMore(names) : names;
}

/// [time] as the status bar shows the last fetch: `02:15`, or `10-19 02:15`
/// before [now]'s day.
String ideGitFetchedAt(DateTime time, {DateTime? now}) {
  final today = now ?? DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  final clock = '${two(time.hour)}:${two(time.minute)}';
  final sameDay =
      time.year == today.year &&
      time.month == today.month &&
      time.day == today.day;
  return sameDay ? clock : '${two(time.month)}-${two(time.day)} $clock';
}
