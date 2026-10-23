part of 'thincoder_kernel.dart';

// The records face of the kernel: the session a conversation was kept under —
// loaded once, resumed after that — and the new session made when there is
// none to pick up. The class keeps the delegation.

/// The record's session: its history loaded once (replayed), and resumed
/// rather than loaded again after that (§3.5). One gone from the agent's
/// library (deleted in the terminal) is forgotten — and the record's
/// slot with it, never looked for again: a session of its own is started
/// in its place, and a later start picks that up. A record that never
/// could start would be a start that never ends.
Future<void> _openRecordOf(
  ThincoderKernel owner,
  ThincoderConnection connection,
  SessionRecord resume,
  List<Map<String, Object?>>? servers,
) async {
  final slot = ThincoderSessionRef.slotOf(resume.id) ?? resume.id;
  owner._slot = slot;
  if (owner._loaded) {
    if (!await owner._pickUp(connection, 'session/resume', slot, servers)) {
      owner._recordGone = true;
      await owner._openNew(connection, servers);
    }
    return;
  }
  // Loading replays the conversation: shown as it comes, and said to be
  // loading until it is all there.
  owner._events.begin();
  owner._loadingHistory = true;
  owner.emitInfoChanged();
  try {
    owner._loaded = await owner._pickUp(connection, 'session/load', slot, servers);
    if (!owner._loaded) {
      owner._recordGone = true;
      await owner._openNew(connection, servers);
    }
  } finally {
    owner._loadingHistory = false;
    owner._events.closePiece();
    owner.emitInfoChanged();
  }
}

/// Asks the agent for [slot] by [method] (`session/load` or
/// `session/resume`), and whether it still had it: one gone from its own
/// library (deleted in the terminal) is forgotten here, and the caller
/// starts a new session instead (§3.5 — one handling for both).
Future<bool> _pickUpOf(
  ThincoderKernel owner,
  ThincoderConnection connection,
  String method,
  String slot,
  List<Map<String, Object?>>? servers,
) async {
  try {
    owner._events.optionsFrom(
      await connection.request(method, {
        'sessionId': slot,
        'cwd': owner._cwd,
        'mcpServers': ?servers,
      }),
    );
    return true;
  } on ThincoderRpcError catch (error) {
    if (!error.gone) rethrow;
    owner._slot = null;
    return false;
  }
}

/// The session this kernel had before a release — kept in memory for
/// exactly this (§3.5) — picked up rather than started over. Whether
/// there was one to pick up: one gone from the agent's own library
/// (deleted in the terminal) is not, and a new one is made instead.
Future<bool> _pickUpKeptOf(
  ThincoderKernel owner,
  ThincoderConnection connection,
  List<Map<String, Object?>>? servers,
) async {
  final slot = owner._slot;
  if (slot == null) return false;
  return owner._pickUp(connection, 'session/resume', slot, servers);
}

/// A session of its own, the first one (§3.5).
Future<void> _openNewOf(
  ThincoderKernel owner,
  ThincoderConnection connection,
  List<Map<String, Object?>>? servers,
) async {
  final clock = Stopwatch()..start();
  final created = await connection.request('session/new', {
    'cwd': owner._cwd,
    'mcpServers': ?servers,
  });
  appEvent('thincoder', 'timing: session-new ${clock.elapsedMilliseconds}ms');
  owner._slot = switch (created['sessionId']) {
    final String id when id.isNotEmpty => id,
    final Object id => '$id',
    _ => null,
  };
  // The grant went out with the empty session id session/new was made
  // with: give it the one the session got, so its calls are keyed by it
  // (two new sessions could otherwise collide on a request id).
  if (owner._mcpToken case final token? when owner._slot != null) {
    HostMcpServer.rebind(token, owner._slot!);
  }
  owner._events.optionsFrom(created);
}
