part of 'thincoder_kernel.dart';

// The conversation face of the kernel: a message sent and what waits behind
// it, the turn under way and its end, a cancel, and the queue's own moves.
// The class keeps the delegation.

void sendOf(ThincoderKernel owner, KernelTurn turn) {
  if (owner._disposed) return;
  if (!owner._sent.add(turn.id)) return;
  owner._queue.add(turn);
  // While a turn runs it waits its own: shown in the queue panel, nothing
  // written or saved of it until then (§18.2-①).
  if (owner._turn != null) {
    owner.emit(ItemUpserted(owner.nextSeq, turn.id,
        UserMessageItem(text: turn.text, images: turn.images, queued: true)));
    return;
  }
  owner._drain();
}

/// Starts the message waiting, unless a turn runs: the one taken up next
/// ([sendQueuedNow]) or the queue's head. Whether one started.
bool _drainOf(ThincoderKernel owner) {
  if (owner._turn != null) return false;
  final next = owner._next ?? (owner._queue.isEmpty ? null : owner._queue.removeAt(0));
  owner._next = null;
  if (next == null) return false;
  owner._beginTurn(next.id);
  unawaited(owner._deliver(next));
  return true;
}

Future<void> _deliverOf(ThincoderKernel owner, KernelTurn turn) async {
  // The pictures go where the agent runs, as the terminal keeps them
  // (F6), or as native image blocks where the agent takes them (F19).
  final native = owner._nativeImages;
  final attached = native ? owner._nativePrompt(turn) : owner._attachImages(turn);
  // The files open in the editor, each one once (F17): said after the
  // user's own words, as system reminders.
  final contexts = ThincoderKernel._contexts(turn.contexts);
  final text = [
    if (attached.text.trim().isNotEmpty) attached.text,
    for (final context in contexts) context.editorNote,
  ].join('\n\n');
  if (owner._disposed) return;
  owner.emit(
    ItemUpserted(
      owner.nextSeq,
      turn.id,
      UserMessageItem(
        text: attached.text,
        images: attached.images,
        contexts: contexts,
      ),
    ),
  );
  if (attached.dropped > 0) {
    owner.emit(
      ItemUpserted(
        owner.nextSeq,
        'dropped:${turn.id}',
        NoticeItem(
          NoticeKind.warning,
          '${attached.dropped} image(s) went unsent: one may be at most '
          '${ThincoderKernel.imageMaxBytes ~/ 1000000} MB, a message '
          '${ThincoderKernel.turnMaxBytes ~/ 1000000} MB.',
        ),
      ),
    );
  }
  if (owner._turn != turn.id) return;
  // The turn waits for the process: said, so that the wait is not silent.
  if (owner._health.status != KernelHealthStatus.ready) owner._sayWaiting();
  try {
    await owner._ensureStarted();
  } on Object catch (error) {
    if (!owner._disposed && owner._turn == turn.id) {
      owner.emit(
        ItemUpserted(
          owner.nextSeq,
          'error:${turn.id}',
          NoticeItem(NoticeKind.error, owner._health.message ?? '$error'),
        ),
      );
      owner._endTurn(interrupted: true);
    }
    return;
  }
  final slot = owner._slot;
  if (owner._turn != turn.id || slot == null) return;
  owner._lastPromptTurn = turn.id;
  // `timing: first-frame` takes off where the prompt goes out (§25.6).
  owner._firstFrame = Stopwatch()..start();
  try {
    // A turn's answer comes only when the turn ends, and a turn has no
    // upper bound: this request is not on the connection's clock (§3.4).
    final answer = await owner._connection!.request('session/prompt', {
      'sessionId': slot,
      'turnId': turn.id,
      'prompt': [
        if (!native || text.isNotEmpty) {'type': 'text', 'text': text},
        if (native)
          for (final image in attached.images)
            {
              'type': 'image',
              'mimeType': image.mediaType,
              'data': base64Encode(image.bytes),
            },
      ],
    }, ThincoderConnection.noTimeout);
    if (owner._turn != turn.id) return;
    owner._endTurn(interrupted: answer['stopReason'] == 'cancelled');
  } on Object catch (error) {
    if (owner._turn != turn.id) return;
    owner.emit(
      ItemUpserted(
        owner.nextSeq,
        'error:${turn.id}',
        NoticeItem(NoticeKind.error, '$error'),
      ),
    );
    owner._endTurn(interrupted: true);
  }
}

void _beginTurnOf(ThincoderKernel owner, String id, {bool unprompted = false}) {
  // An automatic turn is its prompt turn's for a revert (§3.3).
  if (unprompted && owner._lastPromptTurn != null) {
    owner._autoTurnOf[id] = owner._lastPromptTurn!;
  }
  owner._events.begin();
  owner._turn = id;
  owner._turnUnprompted = unprompted;
  owner._turnStarted = DateTime.now();
  owner.emit(TurnStarted(owner.nextSeq, id, unprompted: unprompted));
}

/// A turn's start or end, or the window's (§19.2): taken up, held for a
/// turn's end (D57), taken back before it starts (D62), ended (D63).
void _turnReportOf(ThincoderKernel owner, Object? mark) {
  final report = mark is Map ? mark : null;
  final phase = report?['phase'];
  if (phase == 'watch') {
    final on = report?['on'];
    if (on is bool) {
      owner._watching = on;
      if (!on) owner._releaseWhenIdle();
    } else {
      appEvent('thincoder', 'a watch frame with an on not a boolean: $on');
    }
    return;
  }
  final ok = report?['ok'];
  final pending = owner._pendingAuto;
  if (phase == 'start' && owner._turn == null) {
    appEvent('thincoder', 'an automatic turn (${report!['kind']})');
    owner._beginTurn('auto:${++owner._autoTurns}', unprompted: true);
  } else if (phase == 'start' && !owner._turnUnprompted && pending == null) {
    owner._pendingAuto = (id: 'auto:${++owner._autoTurns}', kind: report!['kind']);
  } else if (phase == 'end' && owner._turn != null && owner._turnUnprompted) {
    if (ok != null && ok is! bool) {
      appEvent('thincoder', 'a turn end with an ok not a boolean: $ok');
    }
    owner._endTurn(interrupted: ok == false);
  } else if (phase == 'end' && owner._turn != null && pending != null) {
    owner._pendingAuto = null;
    appEvent(
      'thincoder',
      'an automatic turn (${pending.kind}) ended before it was taken up',
    );
  } else {
    appEvent('thincoder', 'a turn report to leave alone: $mark');
  }
}

/// Forgets the model picked while a turn ran: none applies any more
/// (F21).
void _dropModelOfOf(ThincoderKernel owner) {
  owner._modelTarget = null;
  owner._modelDeferred = false;
  owner._modelSending = false;
  owner.emitInfoChanged();
}

/// Ends the turn under way: its item done, the approvals the agent was
/// left waiting on resolved, and how long it took and what it spent.
void _endTurnOf(ThincoderKernel owner, {required bool interrupted}) {
  final turn = owner._turn;
  if (turn == null) return;
  owner._turn = null;
  owner._turnUnprompted = false;
  owner._events.closePiece();
  owner._resolveApprovals();
  final started = owner._turnStarted;
  owner._turnStarted = null;
  owner._firstFrame = null; // The turn's first frame is its own (§25.6).
  final spent = owner._events.turnSpent;
  owner.emit(
    TurnEnded(
      owner.nextSeq,
      turn,
      interrupted: interrupted,
      worked: started == null
          ? null
          : DateTime.now().difference(started),
      usage: spent == 0 ? null : TurnUsage(spentTokens: spent),
    ),
  );
  // The model picked while this turn ran goes before the next prompt
  // (F21): the config line first, so the next turn runs on it.
  unawaited(_pumpModelOf(owner));
  unawaited(_pumpTitle(owner));
  // An automatic turn reported while this one ran goes first (D57).
  if (owner._pendingAuto case final pending?) {
    owner._pendingAuto = null;
    appEvent('thincoder', 'an automatic turn (${pending.kind})');
    owner._beginTurn(pending.id, unprompted: true);
    return;
  }
  // What waits goes first: letting the process go would drop it — the
  // release asked for stays for the turn after (D53).
  if (owner._drain()) return;
  owner._releaseWhenIdle();
}

void cancelOf(ThincoderKernel owner) {
  final turn = owner._turn;
  if (turn == null) return;
  if (owner._slot == null || owner._connection == null) {
    // Nothing is running on the agent's side yet: the turn ends here.
    owner._endTurn(interrupted: true);
    return;
  }
  // The agent cancels the turn: its answer to `session/prompt`
  // (`stopReason: 'cancelled'`) is what ends it here (§3.6).
  unawaited(
    owner._connection!
        .request('session/cancel', {'sessionId': owner._slot})
        .catchError((_) => const <String, Object?>{}),
  );
}

/// Takes back a message still waiting: out of the queue, off the panel.
/// One already sent is not taken back ([cancel] stops the turn instead).
Future<bool> cancelQueuedOf(ThincoderKernel owner, String turnId) async {
  if (owner._next?.id == turnId) {
    owner._next = null;
  } else {
    final at = owner._queue.indexWhere((turn) => turn.id == turnId);
    if (at < 0) return false;
    owner._queue.removeAt(at);
  }
  owner.emit(ItemRemoved(owner.nextSeq, turnId));
  return true;
}

/// Takes up the waiting message [turnId] first: the turn running stops
/// for it, the rest keep their order.
void sendQueuedNowOf(ThincoderKernel owner, String turnId) {
  // Already the one taken up next: only the turn running is in the way.
  if (owner._next?.id == turnId) {
    if (owner._turn != null) owner.cancel();
    return;
  }
  final at = owner._queue.indexWhere((turn) => turn.id == turnId);
  if (at < 0) return;
  final ahead = owner._next;
  owner._next = owner._queue.removeAt(at);
  if (ahead != null) owner._queue.insert(0, ahead);
  if (owner._turn == null) {
    owner._drain();
  } else {
    owner.cancel();
  }
}

/// No turn under way, none reported, and a live connection to ask (§3.5).
bool canRevertNowOf(ThincoderKernel owner) =>
    owner._turn == null && owner._pendingAuto == null && owner._running;
