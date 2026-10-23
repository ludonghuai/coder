part of 'thincoder_kernel.dart';

// The inbound face of the kernel: the messages the process sends — a frame of
// the session, the turn boundary's mark in it, the first content's timing, and
// the process leaving. The class keeps the delegation and the two mark keys.

void _receiveOf(ThincoderKernel owner, Map<String, Object?> message) {
  if (message['type'] == ThincoderExit.type) {
    owner._exited(message);
    return;
  }
  owner._connection?.receive(message);
}

/// `timing: first-frame` (§25.6): the first frame carrying content, once.
void _noteFirstFrameOf(ThincoderKernel owner, Map<String, Object?> update) {
  final clock = owner._firstFrame;
  if (clock == null) return;
  if (!ThincoderKernel._content.contains(update['sessionUpdate'])) return;
  owner._firstFrame = null;
  appEvent('thincoder', 'timing: first-frame ${clock.elapsedMilliseconds}ms');
}

void _notificationOf(
  ThincoderKernel owner,
  String method,
  Map<String, Object?> params,
) {
  if (method != 'session/update') {
    // E4 留痕: what it says that this adapter does not know.
    appEvent('thincoder', 'ignored notification $method');
    return;
  }
  final update = (params['update'] as Map?)?.cast<String, Object?>();
  if (update == null) return;
  owner._noteFirstFrame(update);
  // A turn boundary's mark is this adapter's, not a subagent's (F16).
  final meta = update['_meta'];
  if (update['sessionUpdate'] == 'session_info_update' &&
      meta is Map && meta.containsKey(ThincoderKernel._turnKey)) {
    owner._turnReport(meta[ThincoderKernel._turnKey]);
    return;
  }
  owner._events.update(update);
  // The last subagent may have left with this frame: the release asked
  // for is taken up after the macrotask it waits (D64).
  owner._releaseWhenIdle();
}
