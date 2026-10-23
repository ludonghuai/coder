part of 'thincoder_kernel.dart';

// The letting-go face of the kernel: the process and its session torn down or
// closed, a release taken once nothing is under way, a start over, and what a
// process that leaves says. The class keeps the delegation.

void _teardownOf(ThincoderKernel owner) {
  if (owner._mcpToken case final token?) {
    HostMcpServer.revoke(token);
    owner._mcpToken = null;
  }
  owner._releaseCheck?.cancel();
  owner._releaseCheck = null;
  unawaited(owner._subscription?.cancel());
  owner._subscription = null;
  owner._connection?.close();
  owner._connection = null;
  owner._resolveApprovals(refuse: true);
  if (owner._transport case final transport?) {
    // A process that will not end is not waited on for ever.
    owner._stopped = transport.exited.timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
    transport.close();
  }
  owner._transport = null;
  owner._loadingHistory = false;
  // What waited goes with the session: none of it was sent.
  for (final turn in [...owner._queue, ?owner._next]) {
    owner.emit(ItemRemoved(owner.nextSeq, turn.id));
  }
  owner._queue.clear();
  owner._next = null;
  owner._pendingAuto = null;
  owner._dropModelOf();
  owner._dropTitleOf();
  owner._lastPromptTurn = null;
  owner._autoTurnOf.clear();
  owner._watching = false;
  owner._events.closePiece();
  // The subagents it ran are gone with it (F11): nothing is left saying
  // it runs for ever.
  owner._events.endSubagents();
}

/// Tells the agent the session is over, best effort: it releases the
/// slot's claim (§3.5).
void _closeSessionOf(ThincoderKernel owner) {
  final slot = owner._slot;
  final connection = owner._connection;
  if (slot == null || connection == null) return;
  unawaited(
    connection
        .request('session/close', {'sessionId': slot})
        .catchError((_) => const <String, Object?>{}),
  );
}

void prepareOf(ThincoderKernel owner) {
  // The view is back: a release asked for as it left is called off, and
  // the macrotask it waited is over with it (D64).
  owner._releaseWanted = false;
  owner._releaseCheck?.cancel();
  owner._releaseCheck = null;
  if (owner._health.status == KernelHealthStatus.failed) return;
  unawaited(owner._ensureStarted().catchError((_) {}));
}

void restartOf(ThincoderKernel owner) {
  owner._teardown();
  owner._setHealth(KernelHealth.idle);
  owner.prepare();
}

void releaseOf(ThincoderKernel owner) {
  if (owner._disposed) return;
  // Nothing running, and nothing on its way: nothing to let go of.
  if (owner._transport == null && owner._starting == null) return;
  // Done with the turn under way, rather than cut short — and with a
  // start still under way too, which [_launch] takes up once it is up.
  // A live subagent is one to wait for as well (D64): the suspension
  // window behind it may still bring a digest turn.
  owner._releaseWanted = true;
  owner._releaseWhenIdle();
}

/// Nothing under way, no subagent live, no window open: the process can
/// go (D64 / D65).
bool _canCloseOf(ThincoderKernel owner) =>
    owner._turn == null &&
    owner._starting == null &&
    !owner._events.hasLiveSubagents &&
    !owner._watching;

/// Takes the release — or the session over (D66) — once [_canClose]: after
/// one macrotask of silence, so the digest turn that follows a subagent's
/// end comes in first (D64). A frame that brings one keeps the process; the
/// turn's end takes it up again.
void _releaseWhenIdleOf(ThincoderKernel owner) {
  if (!owner._releaseWanted || !owner._canClose) return;
  // Nothing is up to let go of: nothing to wait for.
  if (owner._transport == null && owner._starting == null) {
    owner._releaseWanted = false;
    return;
  }
  // A zero-duration timer is the macrotask Timer.run makes (§19.2, D64).
  owner._releaseCheck ??= Timer(Duration.zero, () {
    owner._releaseCheck = null;
    if (!owner._releaseWanted || !owner._canClose) return;
    owner._releaseWanted = false;
    owner._closeSession();
    owner._teardown();
    owner._setHealth(KernelHealth.idle);
  });
}

void disposeOf(ThincoderKernel owner) {
  if (owner._disposed) return;
  owner._disposed = true;
  for (final turn in [...owner._queue, ?owner._next]) {
    owner.emit(ItemRemoved(owner.nextSeq, turn.id));
  }
  owner._queue.clear();
  owner._next = null;
  owner._pendingAuto = null;
  owner._dropModelOf(); owner._dropTitleOf();
  // The panel is gone: what it was asked is answered as cancelled (D66).
  owner._resolveApprovals(refuse: true);
  owner.closeEvents(); // The host's surface goes at once (D66).
  if (owner._canClose) {
    owner._closeSession();
    owner._teardown();
    return;
  }
  // Work is still in the process: its turns are saved as they end, so
  // this is the session over, not the work cut short (D66).
  owner._releaseWanted = true;
  owner._releaseWhenIdle();
}

void _exitedOf(ThincoderKernel owner, Map<String, Object?> message) {
  final wasReady = owner._health.status == KernelHealthStatus.ready;
  final code = switch (message['code']) {
    final int code => code,
    final num code => code.toInt(),
    _ => -1,
  };
  final stderr = '${message['stderr'] ?? ''}'.trim();
  owner._teardown();
  if (owner._turn != null) {
    owner.emit(
      ItemUpserted(
        owner.nextSeq,
        'exit:${owner._turn!}',
        const NoticeItem(NoticeKind.error, 'thincoder stopped unexpectedly'),
      ),
    );
    owner._endTurn(interrupted: true);
  }
  if (owner._disposed) return;
  if (code == 0 && wasReady) {
    // It left of its own accord: the next use starts it again.
    owner._setHealth(KernelHealth.idle);
    return;
  }
  final lines = stderr.split('\n');
  final printed = lines
      .skip(lines.length > 12 ? lines.length - 12 : 0)
      .join('\n');
  owner._fail(
    'thincoder stopped',
    [
      if (printed.isNotEmpty) printed,
      if (message['executable'] case final String executable)
        'The one run: $executable',
    ].join('\n\n'),
  );
}

/// Says the turn waits for the process (§25.3-2), once.
void _sayWaitingOf(ThincoderKernel owner) {
  if (owner._waiting) return;
  owner._waiting = true;
  owner.emit(ItemUpserted(owner.nextSeq, ThincoderKernel._startingId,
      const NoticeItem(NoticeKind.warning, 'thincoder is starting…')));
}
