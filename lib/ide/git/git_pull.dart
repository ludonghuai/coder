// What pulling a branch's upstream comes to: the mode the automatic fetch
// and the Get button pull in, what the automatic fetch may veto, the
// outcome, and which issue a repository shows when both sides have one.
// The pull itself runs in IdeGitRepository.pullFromUpstream.

import 'git_autofetch.dart';
import 'git_model.dart';

/// How a pull merges: [fastForwardOnly] moves the branch where it can and
/// fails where it cannot (the automatic fetch, never a merge commit);
/// [merge] merges the upstream, a merge commit where the branch diverged
/// (the Get button).
enum IdeGitPullMode { fastForwardOnly, merge }

/// The automatic fetch's veto: given the status read after the fetch and
/// the files the upstream changes, whether to pull, and why not when it
/// says no (null for nothing to do).
typedef IdeGitPullVeto = ({bool pull, IdeGitAutoFetchIssue? issue}) Function(
  IdeGitState state,
  List<String> incoming,
);

/// What a pull came to: the repository's top level (the late buffer check
/// uses it), the files an update changed (absolute paths, to reload), and
/// the issue that stopped or shadowed it (null when all went well).
class IdeGitPullOutcome {
  const IdeGitPullOutcome({
    required this.root,
    this.updated = const [],
    this.issue,
  });

  final String root;
  final List<String> updated;
  final IdeGitAutoFetchIssue? issue;
}

/// Which issue a repository shows when a pull's fetch failed and its
/// merge or skip came to one of its own: one the user must act on
/// outranks a skip (a working tree with changes must not hide a sign-in
/// Git needs), and between two of the same weight the pull's stands (it is
/// about the working tree).
IdeGitAutoFetchIssue? ideGitPullIssue(
  IdeGitAutoFetchIssue? fetch,
  IdeGitAutoFetchIssue? pull,
) {
  if (fetch == null || pull == null) return pull ?? fetch;
  if (pull.needsAttention != fetch.needsAttention) {
    return pull.needsAttention ? pull : fetch;
  }
  return pull;
}
