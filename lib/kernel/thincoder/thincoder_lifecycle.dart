part of 'thincoder_kernel.dart';

// The starting face of the kernel: the process and its handshake, the session
// it opens (a record resumed, one kept, or a new one), the mode it starts in,
// and how a start that cannot go is said. The class keeps the delegation.

/// Starts the process, if not yet, and waits until its session is up.
Future<void> _ensureStartedOf(ThincoderKernel owner) {
  if (owner._disposed) return Future.error(StateError('disposed'));
  if (owner._running) return Future.value();
  return owner._starting ??= owner._launch().whenComplete(() => owner._starting = null);
}

Future<void> _launchOf(ThincoderKernel owner) async {
  // One process at a time on a session: the last one, if restarted.
  await owner._stopped;
  owner._setHealth(const KernelHealth(KernelHealthStatus.starting));
  try {
    // Its own process, started now: one process per session, ended as the
    // view leaves. Nothing is kept warm between sessions.
    final transport = await owner._start(await owner._launchFor(owner._cwd));
    if (owner._disposed) {
      transport.close();
      return;
    }
    owner._transport = transport;
    final connection = owner._connection = ThincoderConnection(transport.write);
    connection
      ..onRequest = owner._serverRequest
      ..onNotification = owner._notification;
    owner._subscription = transport.messages.listen(owner._receive);
    owner._handshake(
      await connection.request('initialize', {
        'protocolVersion': 1,
        // The files the agent edits go through the editor where a host
        // gives one (F18); otherwise nothing but the protocol's basics,
        // and no terminal login ever (D12).
        // What is not said is unsupported.
        'clientCapabilities': owner._context.files == null
            ? const <String, Object?>{}
            : ThincoderFiles.capabilities,
      }),
    );
    await owner._openSession();
    // Said of, never blocked (D13): the session goes on all the same.
    if (ThincoderLocator.belowVerified(owner._version)) {
      owner.emit(
        ItemUpserted(
          owner.nextSeq,
          'version:${owner._version}',
          NoticeItem(
            NoticeKind.warning,
            'thincoder ${owner._version} is older than the '
            '${ThincoderLocator.verifiedVersion} this BaoCode was checked '
            'against; some things may not work.',
          ),
        ),
      );
    }
    owner._setHealth(KernelHealth.ready);
    owner._applyStartMode();
    // Let go of while this was coming up: done now (§3.5).
    if (owner._releaseWanted && owner._turn == null) {
      owner._releaseWanted = false;
      owner._closeSession();
      owner._teardown();
      owner._setHealth(KernelHealth.idle);
    }
  } on ThincoderUnavailable catch (error) {
    owner._fail(error.message, error.detail);
    rethrow;
  } on ThincoderRpcError catch (error) {
    owner._fail(
      error.authRequired
          ? 'thincoder is not logged in'
          : 'thincoder could not start',
      error.authRequired
          ? '${error.message}\n\nSet it up in a terminal '
                '(`${ThincoderLocator.loginCommand}`), then try again.'
          : error.message,
    );
    rethrow;
  } on Object catch (error) {
    owner._fail('thincoder could not start', '$error');
    rethrow;
  }
}

/// Starts the conversation: the record resumed, the session this kernel
/// already had, or a new one (§3.5).
Future<void> _openSessionOf(ThincoderKernel owner) async {
  final connection = owner._connection!;
  final servers = await owner._hostMcpServers();
  final resume = owner._context.resume;
  if (resume != null && !owner._recordGone) {
    await owner._openRecord(connection, resume, servers);
  } else if (!await owner._pickUpKept(connection, servers)) {
    await owner._openNew(connection, servers);
  }
  owner._sessionId = switch (owner._slot) {
    final String slot => ThincoderSessionRef.combine(owner._cwd, slot),
    null => null,
  };
  // Named before it was made: sent now that it is (§3.4).
  if (owner._pendingTitle case final title? when owner._slot != null) {
    owner._pendingTitle = null;
    owner.rename(title);
  }
}

/// The host tools' server for the agent, when its handshake takes HTTP
/// MCP servers and an exposed group has a tool to give (§4.2); null keeps
/// `mcpServers` out, which every CLI takes (F4).
Future<List<Map<String, Object?>>?> _hostMcpServersOf(ThincoderKernel owner) async {
  if (!owner._httpMcp || !HostTools.anyIn(HostMcpServer.exposedGroups)) return null;
  if (await HostMcpServer.ensure() == null) return null;
  final grant = HostMcpServer.issue(owner._sessionId ?? '', owner._cwd);
  if (grant == null) return null;
  owner._mcpToken = grant.token;
  return [grant.server];
}

/// The mode the host starts the session in (D11: only `mode` — the
/// host's other settings are Claude Code's shape and would point
/// thincoder wrong).
void _applyStartModeOf(ThincoderKernel owner) {
  final wanted = owner._context.settings[KernelChoiceKind.mode.name];
  if (wanted is! String || (wanted != 'plan' && wanted != 'normal')) return;
  if (wanted == owner._events.mode) return;
  unawaited(owner._setMode(wanted));
}

/// The handshake's word, kept in the terminal's log (E4).
void _handshakeOf(ThincoderKernel owner, Map<String, Object?> answer) {
  final info = (answer['agentInfo'] as Map?)?.cast<String, Object?>();
  owner._version = '${info?['version'] ?? ''}';
  if (owner._version!.isEmpty) owner._version = null;
  final caps =
      (answer['agentCapabilities'] as Map?)?.cast<String, Object?>();
  owner._httpMcp = (caps?['mcpCapabilities'] as Map?)?['http'] == true;
  final promptCaps = caps?['promptCapabilities'];
  owner._nativeImages = promptCaps is Map && promptCaps['image'] == true;
  appEvent(
    'thincoder',
    'handshake: protocol ${answer['protocolVersion']} · '
        'agent ${info?['name']} ${owner._version ?? 'unnamed'} · '
        'auth ${(answer['authMethods'] as List?)?.length ?? 0}',
  );
}

void _failOf(ThincoderKernel owner, String message, String? detail) {
  owner._teardown();
  owner._setHealth(
    KernelHealth(
      KernelHealthStatus.failed,
      message: message,
      detail: detail,
    ),
  );
}
