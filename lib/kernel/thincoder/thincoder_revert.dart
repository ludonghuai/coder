part of 'thincoder_kernel.dart';

// The reverting face of the kernel: a turn's changes put back, the plan that
// says what they were, and the rewind that cuts the conversation. The class
// keeps the delegation.

Future<RevertPlan> revertPlanOf(
  ThincoderKernel owner, {
  required String sinceTurn,
}) async => _planOf(await owner._revert(sinceTurn, true));

Future<RevertOutcome> applyRevertOf(
  ThincoderKernel owner, {
  required String sinceTurn,
}) async {
  final answer = await owner._revert(sinceTurn, false);
  final outcome = RevertOutcome(
    files: _revertFiles(answer['files']),
    skipped: _revertSkips(answer['skipped']),
    unrevertable: _revertSkips(answer['unrevertable']),
    failed: _revertFailures(answer['failed']),
  );
  // The host words the summary in its own language (§9, D-SG12); only
  // files put back clear its pending list (D-SG11).
  if (outcome.files.isNotEmpty) owner.emit(ChangesReverted(owner.nextSeq));
  return outcome;
}

/// `session/revert` for [sinceTurn]: its plan ([dryRun]), else what it did
/// (§3.1). An automatic turn is the prompt turn it belongs to (§3.3).
Future<Map<String, Object?>> _revertOf(
  ThincoderKernel owner,
  String sinceTurn,
  bool dryRun,
) async {
  final connection = owner._connection, slot = owner._slot;
  final turn = owner._autoTurnOf[sinceTurn] ?? sinceTurn;
  if (connection == null || slot == null) {
    owner._revertFailed(sinceTurn, 'no session to revert in');
    throw StateError('no session to revert in');
  }
  try {
    return await connection.request('session/revert', {
      'sessionId': slot,
      'sinceTurn': turn,
      'dryRun': dryRun,
    });
  } on Object catch (error) {
    appEvent('thincoder', 'session/revert($turn) failed: $error');
    owner._revertFailed(sinceTurn, '$error');
    rethrow;
  }
}

void _revertFailedOf(ThincoderKernel owner, String sinceTurn, String reason) =>
    owner.emit(
      ItemUpserted(owner.nextSeq, 'revert:$sinceTurn',
          NoticeItem(NoticeKind.error, 'Could not revert: $reason')),
    );

Future<bool> rewindOf(
  ThincoderKernel owner, {
  required String itemId,
  required int index,
  required int turns,
  String? lastSeen,
}) async {
  // index / turns / lastSeen are the host transcript's own: the agent cuts
  // at the turn id, and the host is cut here with Rewound (§3.3).
  final connection = owner._connection, slot = owner._slot;
  if (connection == null || slot == null) {
    owner._rewindFailed(itemId, 'Could not rewind: no session to rewind in');
    return false;
  }
  try {
    await connection.request('session/rewind', {
      'sessionId': slot,
      'turnId': itemId,
    });
    owner.emit(Rewound(owner.nextSeq, itemId: itemId, index: index));
    // What waited behind the cut is dropped: it would run after the new turn.
    for (final turn in [...owner._queue, ?owner._next]) {
      owner.emit(ItemRemoved(owner.nextSeq, turn.id));
    }
    owner._queue.clear(); owner._next = null;
    return true;
  } on ThincoderRpcError catch (error) {
    // A turn of another run and one that never was are one code (D-SG24);
    // a turn under way is its own.
    owner._rewindFailed(itemId, switch (error.code) {
      -32602 => englishLocalizations.rewindNotInThisRun,
      -32002 => englishLocalizations.rewindTurnInFlight,
      _ => 'Could not rewind: $error',
    });
    return false;
  } on Object catch (error) {
    owner._rewindFailed(itemId, 'Could not rewind: $error');
    return false;
  }
}

/// Says why an edit did not go back (§9): the host's path is silent on false.
void _rewindFailedOf(ThincoderKernel owner, String itemId, String text) =>
    owner.emit(ItemUpserted(owner.nextSeq, 'rewind:$itemId', NoticeItem(NoticeKind.error, text)));

RevertPlan _planOf(Map<String, Object?> answer) => RevertPlan(
    files: _revertFiles(answer['files']),
    skipped: _revertSkips(answer['skipped']),
    unrevertable: _revertSkips(answer['unrevertable']));

List<RevertFile> _revertFiles(Object? list) => [
  for (final entry in list as List? ?? const [])
    if (entry is Map)
      RevertFile('${entry['path']}',
          entry['action'] == 'delete' ? RevertAction.delete : RevertAction.restore,
          displayPath: entry['displayPath'] as String?),
];

List<RevertSkip> _revertSkips(Object? list) => [
  for (final entry in list as List? ?? const [])
    if (entry is Map)
      RevertSkip('${entry['path']}', '${entry['reason']}',
          displayPath: entry['displayPath'] as String?),
];

List<RevertFailure> _revertFailures(Object? list) => [
  for (final entry in list as List? ?? const [])
    if (entry is Map)
      RevertFailure('${entry['path']}', '${entry['error']}',
          displayPath: entry['displayPath'] as String?),
];
