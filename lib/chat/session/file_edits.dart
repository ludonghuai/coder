part of '../chat_session.dart';

// The files the agent changed, as the UI lists them, and the ways to keep,
// undo or revert them — through the review of the project where it holds,
// else through the kernel. The state they read stays in the class.

/// The project's directory, which [fileChanges]' paths are in (on its
/// host, for a remote one).
String? _rootOf(ChatSession owner) =>
    owner._activeReview?.root ??
    switch (owner.kernelContext.cwd) {
      final cwd? => RemoteLocation.pathOf(cwd),
      null => null,
    };

/// Files changed and neither kept nor undone, one entry per file, with
/// absolute paths where the project is known: as the review of the
/// project has them, else as the kernel reported them.
List<FileChange> _fileChangesOf(ChatSession owner) {
  if (owner._activeReview case final review?) return review.changes;
  return owner._cached(#fileChanges, () {
    final byPath = <String, FileChange>{};
    for (final (seq: _, :change, turnId: _) in owner._pendingEdits) {
      final path = owner._absolute(change.path);
      final before = byPath[path];
      byPath[path] = FileChange(
        path: path,
        added: (before?.added ?? 0) + change.added,
        removed: (before?.removed ?? 0) + change.removed,
      );
    }
    return byPath.values.toList();
  });
}

/// The files the agent read or changed (or was given: a picture a tool
/// returned, saved), absolute: what its text may link to outside the
/// project, and where a file it names by a path gone wrong (relative to
/// some other folder) may be.
///
/// The same list while they stay the same, as the reply streams: what
/// looks a path up in it indexes each list once (FileOpenScope).
List<String> _filesSeenOf(ChatSession owner) =>
    owner._cached(#filesSeen, () {
      final files = {
        for (var i = 0; i < owner._transcript.length; i++)
          if (owner._transcript.itemAt(i) case ToolCallItem(
            :final path,
            :final imageFiles,
          )) ...[
            if (path != null && path.isNotEmpty) owner._absolute(path),
            // The pictures the CLI saved for it: the agent may link them.
            for (final file in imageFiles) owner._absolute(file),
          ],
        for (final edit in owner._transcript.edits)
          owner._absolute(edit.change.path),
      }.toList();
      if (listEquals(files, owner._filesSeen)) return owner._filesSeen;
      return owner._filesSeen = files;
    });

void _keepAllChangesOf(ChatSession owner) {
  owner._keptSeq = owner._transcript.lastSeq;
  owner._keptPaths.clear();
  if (owner._activeReview case final review?) unawaited(review.keepAll());
  owner._cache.clear();
  owner._notify();
}

/// Keeps the changes to [changes]' files: they are no longer listed.
void _keepChangesOf(ChatSession owner, List<FileChange> changes) {
  if (owner._activeReview case final review?) {
    unawaited(review.keep([for (final change in changes) change.path]));
    return;
  }
  for (final change in changes) {
    owner._keptPaths[change.path] = owner._transcript.lastSeq;
  }
  owner._cache.clear();
  owner._notify();
}

/// Puts the pending changes back; null when there is no way to.
VoidCallback? _undoAllChangesOf(ChatSession owner) {
  if (owner._activeReview case final review?) {
    if (!review.changes.any((change) => change.tracked)) return null;
    return () => unawaited(review.undoAll());
  }
  if ((owner._kernel, owner._pendingEdits.firstOrNull?.turnId) case (
    final RevertsChanges kernel,
    final since?,
  )) {
    return () => kernel.revertChanges(sinceTurn: since);
  }
  return null;
}

/// The turn the earliest change not kept or undone came from (F2.1).
String? _revertTurnOf(ChatSession owner) =>
    owner._pendingEdits.firstOrNull?.turnId;

/// Whether a revert can be planned and done now (§3.3, §3.5).
bool _canPlanRevertOf(ChatSession owner) => switch (owner._kernel) {
  final PlansReverts kernel => kernel.canRevertNow,
  _ => false,
};

/// Whether the kernel plans reverts at all: its entry never falls back
/// to the host's own undo (the kernel holds the stack, §9).
bool _plansRevertsOf(ChatSession owner) => owner._kernel is PlansReverts;

/// What a revert from [sinceTurn] on would do; nothing is written.
Future<RevertPlan> _revertPlanOf(ChatSession owner, String sinceTurn) =>
    switch (owner._kernel) {
      final PlansReverts kernel => kernel.revertPlan(sinceTurn: sinceTurn),
      _ => Future.error(UnsupportedError('revertPlan')),
    };

/// Does what [revertPlan] planned for [sinceTurn], each file on its own.
Future<RevertOutcome> _applyRevertOf(ChatSession owner, String sinceTurn) =>
    switch (owner._kernel) {
      final PlansReverts kernel => kernel.applyRevert(sinceTurn: sinceTurn),
      _ => Future.error(UnsupportedError('applyRevert')),
    };

/// Puts [changes]' files back; null when files cannot be undone one by
/// one (no review of the project).
ValueChanged<List<FileChange>>? _undoChangesOf(ChatSession owner) =>
    switch (owner._activeReview) {
      final review? => (changes) => unawaited(
        review.undo([for (final change in changes) change.path]),
      ),
      null => null,
    };

/// Reads the text of [change]'s file before the agent changed it, for a
/// diff; null when it is not known.
Future<String> Function()? _originalOfOf(
  ChatSession owner,
  FileChange change,
) => owner._activeReview?.original(change.path);
