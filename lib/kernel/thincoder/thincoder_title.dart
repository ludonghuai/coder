part of 'thincoder_kernel.dart';

// The title face of the kernel: the rename the agent confirms (§28.3-28.4),
// one held while a turn runs, and the write that follows it. The class keeps
// the delegation.

/// Whether a rename made now would be written and confirmed (§28.3): a
/// slot to write it under, a live connection, and no release on its way.
/// False otherwise — the host changes the list itself, as it always did.
bool renameConfirmedOf(ThincoderKernel owner) =>
    owner._slot != null && owner._running && !owner._releaseWanted;

void renameOf(ThincoderKernel owner, String title) {
  // The title the agent confirmed already (§28.4): the host writing it back
  // after the event is no reason to send it again.
  if (title.trim() == owner._titleConfirmed) return;
  // Before the session is made: kept for when it is (§3.4).
  if (owner._slot == null) {
    owner._pendingTitle = title;
    return;
  }
  owner._titleTarget = title;
  // A turn under way keeps the write back: it would land behind it (§3.5).
  if (owner._turn != null || owner._pendingAuto != null || owner._titleSending) {
    owner._titleDeferred = true;
    owner.emitInfoChanged();
    return;
  }
  owner._titleDeferred = false;
  unawaited(_pumpTitle(owner));
}

void _dropTitleOfOf(ThincoderKernel owner) {
  owner._titleTarget = null; owner._titleDeferred = false; owner._titleSending = false;
  owner.emitInfoChanged();
}

Future<void> _pumpTitle(ThincoderKernel kernel) async {
  final target = kernel._titleTarget;
  if (target == null || kernel._titleSending || kernel._turn != null ||
      kernel._pendingAuto != null) {
    return;
  }
  if (kernel._releaseWanted) {
    // The session is closing (§19.2): the title goes with it — said, not
    // silently dropped (F25②, §28.4). No event: nothing was written.
    appEvent('thincoder', 'set_title: the session is closing');
    kernel.emit(ItemUpserted(kernel.nextSeq, 'error:title',
        NoticeItem(NoticeKind.error,
            'The title was not confirmed: the session is closing')));
    return kernel._dropTitleOf();
  }
  final connection = kernel._connection, slot = kernel._slot;
  if (connection == null || slot == null) {
    // Nothing to write it through (§3.5): said, not silently dropped.
    appEvent('thincoder', 'set_title: no connection');
    kernel.emit(ItemUpserted(kernel.nextSeq, 'error:title',
        NoticeItem(NoticeKind.error,
            'The title was not confirmed: no connection')));
    return kernel._dropTitleOf();
  }
  kernel._titleDeferred = false; kernel._titleSending = true;
  try {
    await connection.request('session/set_title', {
      'sessionId': slot,
      'title': target,
    });
    if (!identical(connection, kernel._connection)) return;
    kernel._titleSending = false;
    kernel._titleConfirmed = target;
    // Written and confirmed: the list follows now (§28.3).
    kernel.emit(SessionRenamed(kernel.nextSeq, target));
    if (kernel._titleTarget != target) return unawaited(_pumpTitle(kernel));
    kernel._dropTitleOf();
  } on Object catch (error) {
    if (!identical(connection, kernel._connection)) return;
    appEvent('thincoder', 'set_title failed: $error');
    kernel.emit(ItemUpserted(kernel.nextSeq, 'error:title',
        NoticeItem(NoticeKind.error, 'The title was not confirmed: $error')));
    kernel._titleSending = false;
    if (kernel._titleTarget != target) return unawaited(_pumpTitle(kernel));
    kernel._dropTitleOf();
  }
}
