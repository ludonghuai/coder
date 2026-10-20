import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../chat/chat_models.dart';
import '../../host_tools/host_mcp_server.dart';
import '../../host_tools/host_tools.dart';
import '../../models/model_provider.dart';
import '../../platform/event_log.dart';
import '../agent_kernel.dart';
import '../kernel_event.dart';
import '../kernel_types.dart';
import 'thincoder_events.dart';
import 'thincoder_files.dart';
import 'thincoder_locator.dart';
import 'thincoder_process.dart';
import 'thincoder_protocol.dart';
import 'thincoder_session_ref.dart';
import 'thincoder_transport.dart';

part 'thincoder_choices.dart';

/// Adapts `thincoder acp` to [AgentKernel].
///
/// One process per session, started when its conversation is shown: ACP
/// over its stdin and stdout, one JSON object per line. Its sessions are
/// the ones the user's terminal keeps (the same slots in the same folder),
/// its modes and settings are what it reports them to be, and pictures go
/// to files the agent is told of, or as native image blocks (F6 / F19).
///
/// What it does not have — plans as cards, forks, rewind, background
/// tasks — it does not declare, and the UI leaves those parts out.
class ThincoderKernel
    with KernelEventSource
    implements
        AgentKernel,
        DefersModelSwitch,
        ThincoderSink,
        SelectsMode,
        SelectsModel,
        SelectsEffort,
        SelectsPermission,
        ReportsContext,
        LoadsHistory,
        AcceptsImageFiles,
        AcceptsEditorContext,
        QueuesMessages,
        RenamesSession,
        PlansReverts,
        GeneratesTitles,
        DefersRename {
  ThincoderKernel(
    this.descriptor,
    this._context, {
    ThincoderTransportFactory? start,
    ThincoderLauncher? launch,
  }) : _start = start ?? startThincoderProcess,
       _launchFor = launch ?? ThincoderLocator.launch {
    _events = ThincoderEvents(this);
    _sessionId = _context.resume?.id;
  }

  @override
  final KernelDescriptor descriptor;
  final KernelContext _context;
  final ThincoderTransportFactory _start;
  final ThincoderLauncher _launchFor;

  /// What the agent reports, as the events the host shows (§3.6).
  late final ThincoderEvents _events;

  ThincoderTransport? _transport;
  ThincoderConnection? _connection;
  StreamSubscription<Map<String, Object?>>? _subscription;
  Future<void>? _starting;

  KernelHealth _health = KernelHealth.idle;
  String? _sessionId;
  bool _disposed = false;
  Future<void> _stopped = Future.value();

  /// The slot the agent keeps the session under: what the wire names it by
  /// (the host sees [sessionId]).
  String? _slot;

  /// Whether this kernel loaded the conversation already: a later start
  /// resumes it rather than loading (and replaying) it again (§3.5).
  bool _loaded = false;

  /// Whether the record's slot was forgotten (§3.5): the agent no longer
  /// had it, so it is not looked for again — what was started in its place
  /// is what a later start picks up.
  bool _recordGone = false;

  /// Whether the conversation is still being read (see [loadingHistory]).
  bool _loadingHistory = false;

  /// The version the agent reported at the handshake.
  String? _version;

  /// Takes HTTP MCP servers (`mcpCapabilities.http`), and the host tools'
  /// leave this session holds.
  bool _httpMcp = false;
  String? _mcpToken;

  /// Whether the handshake took pictures as native image blocks (F19).
  bool _nativeImages = false;

  /// The turn under way: its id, when it began, whether the agent took it
  /// up on its own (§19.2); automatic turns, and one held for a turn's end.
  String? _turn;
  DateTime? _turnStarted;
  bool _turnUnprompted = false;
  int _autoTurns = 0;
  ({String id, Object? kind})? _pendingAuto;
  final Set<String> _sent = {};

  /// The model picked while a turn runs or a switch is out (F21): written
  /// once neither is in the way.
  String? _modelTarget;
  bool _modelDeferred = false;
  bool _modelSending = false;

  /// The title picked while a turn runs or a write is out (§3.5): written
  /// once neither is in the way.
  String? _titleTarget;
  bool _titleDeferred = false;
  bool _titleSending = false;

  /// A title picked before the session was made (§3.4): sent once it is.
  String? _pendingTitle;

  /// The turn the latest prompt was sent under, and the automatic turns
  /// that belong to it (§3.3): a revert from one starts at the prompt's.
  String? _lastPromptTurn;
  final Map<String, String> _autoTurnOf = {};

  /// Messages sent while a turn runs, in the order sent; [_next] first.
  final List<KernelTurn> _queue = [];
  KernelTurn? _next;

  /// Asked for while a turn or a subagent is live: the process goes once
  /// nothing of either is left (§19.2, D64).
  bool _releaseWanted = false;

  /// The one macrotask a release waits, letting the digest turn that
  /// follows a subagent's end come in first (D64).
  Timer? _releaseCheck;

  /// Whether the suspension window is open (D65): the process waits it out.
  bool _watching = false;

  /// Pending approvals: our request id → the agent's request to answer.
  final Map<String, ThincoderRequest> _approvals = {};

  /// The files the agent reads and writes through the host (F18).
  late final ThincoderFiles _files = ThincoderFiles(
    cwd: () => _cwd,
    folders: () => _context.workspace?.call()?.folders ?? const [],
    files: () => _context.files,
    emit: emit,
    nextSeq: () => nextSeq,
    turnId: () => _turn,
  );

  // --- Lifecycle --------------------------------------------------------------

  @override
  KernelHealth get health => _health;

  @override
  String? get sessionId => _sessionId;

  @override
  String? get pendingModel => _modelDeferred ? _modelTarget : null;

  @override
  String? get pendingTitle => _titleDeferred ? _titleTarget : null;

  @override
  Future<void> get stopped => _stopped;

  @override
  bool get loadingHistory => _loadingHistory;

  // The whole session is replayed once, at open (`session/load`), so there is
  // nothing older to ask for: the list never pages in earlier turns.
  @override
  bool get hasEarlierHistory => false;

  @override
  bool get loadingEarlier => false;

  @override
  Future<void> loadEarlier() => Future<void>.value();

  @override
  int get contextWindow => _events.contextWindow;

  void _setHealth(KernelHealth health) {
    _health = health;
    emitInfoChanged();
  }

  bool get _running =>
      _connection != null && _health.status == KernelHealthStatus.ready;

  String get _cwd => _context.cwd ?? _context.resume?.cwd ?? '.';

  /// Starts the process, if not yet, and waits until its session is up.
  Future<void> _ensureStarted() {
    if (_disposed) return Future.error(StateError('disposed'));
    if (_running) return Future.value();
    return _starting ??= _launch().whenComplete(() => _starting = null);
  }

  Future<void> _launch() async {
    // One process at a time on a session: the last one, if restarted.
    await _stopped;
    _setHealth(const KernelHealth(KernelHealthStatus.starting));
    try {
      final transport = await _start(await _launchFor(_cwd));
      if (_disposed) {
        transport.close();
        return;
      }
      _transport = transport;
      final connection = _connection = ThincoderConnection(transport.write);
      connection
        ..onRequest = _serverRequest
        ..onNotification = _notification;
      _subscription = transport.messages.listen(_receive);
      _handshake(
        await connection.request('initialize', {
          'protocolVersion': 1,
          // The files the agent edits go through the editor where a host
          // gives one (F18); otherwise nothing but the protocol's basics,
          // and no terminal login ever (D12). What is not said is
          // unsupported.
          'clientCapabilities': _context.files == null
              ? const <String, Object?>{}
              : ThincoderFiles.capabilities,
        }),
      );
      await _openSession();
      // Said of, never blocked (D13): the session goes on all the same.
      if (ThincoderLocator.belowVerified(_version)) {
        emit(
          ItemUpserted(
            nextSeq,
            'version:$_version',
            NoticeItem(
              NoticeKind.warning,
              'thincoder $_version is older than the '
              '${ThincoderLocator.verifiedVersion} this BaoCode was checked '
              'against; some things may not work.',
            ),
          ),
        );
      }
      _setHealth(KernelHealth.ready);
      _applyStartMode();
      // Let go of while this was coming up: done now (§3.5).
      if (_releaseWanted && _turn == null) {
        _releaseWanted = false;
        _closeSession();
        _teardown();
        _setHealth(KernelHealth.idle);
      }
    } on ThincoderUnavailable catch (error) {
      _fail(error.message, error.detail);
      rethrow;
    } on ThincoderRpcError catch (error) {
      _fail(
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
      _fail('thincoder could not start', '$error');
      rethrow;
    }
  }

  /// Starts the conversation: the record resumed, the session this kernel
  /// already had, or a new one (§3.5).
  Future<void> _openSession() async {
    final connection = _connection!;
    final servers = await _hostMcpServers();
    final resume = _context.resume;
    if (resume != null && !_recordGone) {
      await _openRecord(connection, resume, servers);
    } else if (!await _pickUpKept(connection, servers)) {
      await _openNew(connection, servers);
    }
    _sessionId = switch (_slot) {
      final String slot => ThincoderSessionRef.combine(_cwd, slot),
      null => null,
    };
    // Named before it was made: sent now that it is (§3.4).
    if (_pendingTitle case final title? when _slot != null) {
      _pendingTitle = null;
      rename(title);
    }
  }

  /// The host tools' server for the agent, when its handshake takes HTTP
  /// MCP servers and an exposed group has a tool to give (§4.2); null keeps
  /// `mcpServers` out, which every CLI takes (F4).
  Future<List<Map<String, Object?>>?> _hostMcpServers() async {
    if (!_httpMcp || !HostTools.anyIn(HostMcpServer.exposedGroups)) return null;
    if (await HostMcpServer.ensure() == null) return null;
    final grant = HostMcpServer.issue(_sessionId ?? '', _cwd);
    if (grant == null) return null;
    _mcpToken = grant.token;
    return [grant.server];
  }

  /// The record's session: its history loaded once (replayed), and resumed
  /// rather than loaded again after that (§3.5). One gone from the agent's
  /// library (deleted in the terminal) is forgotten — and the record's
  /// slot with it, never looked for again: a session of its own is started
  /// in its place, and a later start picks that up. A record that never
  /// could start would be a start that never ends.
  Future<void> _openRecord(
    ThincoderConnection connection,
    SessionRecord resume,
    List<Map<String, Object?>>? servers,
  ) async {
    final slot = ThincoderSessionRef.slotOf(resume.id) ?? resume.id;
    _slot = slot;
    if (_loaded) {
      if (!await _pickUp(connection, 'session/resume', slot, servers)) {
        _recordGone = true;
        await _openNew(connection, servers);
      }
      return;
    }
    // Loading replays the conversation: shown as it comes, and said to be
    // loading until it is all there.
    _events.begin();
    _loadingHistory = true;
    emitInfoChanged();
    try {
      _loaded = await _pickUp(connection, 'session/load', slot, servers);
      if (!_loaded) {
        _recordGone = true;
        await _openNew(connection, servers);
      }
    } finally {
      _loadingHistory = false;
      _events.closePiece();
      emitInfoChanged();
    }
  }

  /// Asks the agent for [slot] by [method] (`session/load` or
  /// `session/resume`), and whether it still had it: one gone from its own
  /// library (deleted in the terminal) is forgotten here, and the caller
  /// starts a new session instead (§3.5 — one handling for both).
  Future<bool> _pickUp(
    ThincoderConnection connection,
    String method,
    String slot,
    List<Map<String, Object?>>? servers,
  ) async {
    try {
      _events.optionsFrom(
        await connection.request(method, {
          'sessionId': slot,
          'cwd': _cwd,
          'mcpServers': ?servers,
        }),
      );
      return true;
    } on ThincoderRpcError catch (error) {
      if (!error.gone) rethrow;
      _slot = null;
      return false;
    }
  }

  /// The session this kernel had before a release — kept in memory for
  /// exactly this (§3.5) — picked up rather than started over. Whether
  /// there was one to pick up: one gone from the agent's own library
  /// (deleted in the terminal) is not, and a new one is made instead.
  Future<bool> _pickUpKept(
    ThincoderConnection connection,
    List<Map<String, Object?>>? servers,
  ) async {
    final slot = _slot;
    if (slot == null) return false;
    return _pickUp(connection, 'session/resume', slot, servers);
  }

  /// A session of its own, the first one (§3.5).
  Future<void> _openNew(
    ThincoderConnection connection,
    List<Map<String, Object?>>? servers,
  ) async {
    final created = await connection.request('session/new', {
      'cwd': _cwd,
      'mcpServers': ?servers,
    });
    _slot = switch (created['sessionId']) {
      final String id when id.isNotEmpty => id,
      final Object id => '$id',
      _ => null,
    };
    // The grant went out with the empty session id session/new was made
    // with: give it the one the session got, so its calls are keyed by it
    // (two new sessions could otherwise collide on a request id).
    if (_mcpToken case final token? when _slot != null) {
      HostMcpServer.rebind(token, _slot!);
    }
    _events.optionsFrom(created);
  }

  /// The mode the host starts the session in (D11: only `mode` — the
  /// host's other settings are Claude Code's shape and would point
  /// thincoder wrong).
  void _applyStartMode() {
    final wanted = _context.settings[KernelChoiceKind.mode.name];
    if (wanted is! String || (wanted != 'plan' && wanted != 'normal')) return;
    if (wanted == _events.mode) return;
    unawaited(_setMode(wanted));
  }

  /// The handshake's word, kept in the terminal's log (E4).
  void _handshake(Map<String, Object?> answer) {
    final info = (answer['agentInfo'] as Map?)?.cast<String, Object?>();
    _version = '${info?['version'] ?? ''}';
    if (_version!.isEmpty) _version = null;
    final caps =
        (answer['agentCapabilities'] as Map?)?.cast<String, Object?>();
    _httpMcp = (caps?['mcpCapabilities'] as Map?)?['http'] == true;
    final promptCaps = caps?['promptCapabilities'];
    _nativeImages = promptCaps is Map && promptCaps['image'] == true;
    appEvent(
      'thincoder',
      'handshake: protocol ${answer['protocolVersion']} · '
          'agent ${info?['name']} ${_version ?? 'unnamed'} · '
          'auth ${(answer['authMethods'] as List?)?.length ?? 0}',
    );
  }

  void _fail(String message, String? detail) {
    _teardown();
    _setHealth(
      KernelHealth(
        KernelHealthStatus.failed,
        message: message,
        detail: detail,
      ),
    );
  }

  void _teardown() {
    if (_mcpToken case final token?) {
      HostMcpServer.revoke(token);
      _mcpToken = null;
    }
    _releaseCheck?.cancel();
    _releaseCheck = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _connection?.close();
    _connection = null;
    _resolveApprovals(refuse: true);
    if (_transport case final transport?) {
      // A process that will not end is not waited on for ever.
      _stopped = transport.exited.timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
      transport.close();
    }
    _transport = null;
    _loadingHistory = false;
    // What waited goes with the session: none of it was sent.
    for (final turn in [..._queue, ?_next]) {
      emit(ItemRemoved(nextSeq, turn.id));
    }
    _queue.clear();
    _next = null;
    _pendingAuto = null;
    _dropModelOf();
    _dropTitleOf();
    _lastPromptTurn = null;
    _autoTurnOf.clear();
    _watching = false;
    _events.closePiece();
    // The subagents it ran are gone with it (F11): nothing is left saying
    // it runs for ever.
    _events.endSubagents();
  }

  /// Tells the agent the session is over, best effort: it releases the
  /// slot's claim (§3.5).
  void _closeSession() {
    final slot = _slot;
    final connection = _connection;
    if (slot == null || connection == null) return;
    unawaited(
      connection
          .request('session/close', {'sessionId': slot})
          .catchError((_) => const <String, Object?>{}),
    );
  }

  @override
  void prepare() {
    // The view is back: a release asked for as it left is called off, and
    // the macrotask it waited is over with it (D64).
    _releaseWanted = false;
    _releaseCheck?.cancel();
    _releaseCheck = null;
    if (_health.status == KernelHealthStatus.failed) return;
    unawaited(_ensureStarted().catchError((_) {}));
  }

  @override
  void restart() {
    _teardown();
    _setHealth(KernelHealth.idle);
    prepare();
  }

  @override
  void release() {
    if (_disposed) return;
    // Nothing running, and nothing on its way: nothing to let go of.
    if (_transport == null && _starting == null) return;
    // Done with the turn under way, rather than cut short — and with a
    // start still under way too, which [_launch] takes up once it is up.
    // A live subagent is one to wait for as well (D64): the suspension
    // window behind it may still bring a digest turn.
    _releaseWanted = true;
    _releaseWhenIdle();
  }

  /// Nothing under way, no subagent live, no window open: the process can
  /// go (D64 / D65).
  bool get _canClose =>
      _turn == null &&
      _starting == null &&
      !_events.hasLiveSubagents &&
      !_watching;

  /// Takes the release — or the session over (D66) — once [_canClose]: after
  /// one macrotask of silence, so the digest turn that follows a subagent's
  /// end comes in first (D64). A frame that brings one keeps the process; the
  /// turn's end takes it up again.
  void _releaseWhenIdle() {
    if (!_releaseWanted || !_canClose) return;
    // Nothing is up to let go of: nothing to wait for.
    if (_transport == null && _starting == null) {
      _releaseWanted = false;
      return;
    }
    // A zero-duration timer is the macrotask Timer.run makes (§19.2, D64).
    _releaseCheck ??= Timer(Duration.zero, () {
      _releaseCheck = null;
      if (!_releaseWanted || !_canClose) return;
      _releaseWanted = false;
      _closeSession();
      _teardown();
      _setHealth(KernelHealth.idle);
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final turn in [..._queue, ?_next]) {
      emit(ItemRemoved(nextSeq, turn.id));
    }
    _queue.clear();
    _next = null;
    _pendingAuto = null;
    _dropModelOf(); _dropTitleOf();
    // The panel is gone: what it was asked is answered as cancelled (D66).
    _resolveApprovals(refuse: true);
    closeEvents(); // The host's surface goes at once (D66).
    if (_canClose) {
      _closeSession();
      _teardown();
      return;
    }
    // Work is still in the process: its turns are saved as they end, so
    // this is the session over, not the work cut short (D66).
    _releaseWanted = true;
    _releaseWhenIdle();
  }

  // --- The conversation -------------------------------------------------------

  @override
  void send(KernelTurn turn) {
    if (_disposed) return;
    if (!_sent.add(turn.id)) return;
    _queue.add(turn);
    // While a turn runs it waits its own: shown in the queue panel, nothing
    // written or saved of it until then (§18.2-①).
    if (_turn != null) {
      emit(ItemUpserted(nextSeq, turn.id,
          UserMessageItem(text: turn.text, images: turn.images, queued: true)));
      return;
    }
    _drain();
  }

  /// Starts the message waiting, unless a turn runs: the one taken up next
  /// ([sendQueuedNow]) or the queue's head. Whether one started.
  bool _drain() {
    if (_turn != null) return false;
    final next = _next ?? (_queue.isEmpty ? null : _queue.removeAt(0));
    _next = null;
    if (next == null) return false;
    _beginTurn(next.id);
    unawaited(_deliver(next));
    return true;
  }

  Future<void> _deliver(KernelTurn turn) async {
    // The pictures go where the agent runs, as the terminal keeps them
    // (F6), or as native image blocks where the agent takes them (F19).
    final native = _nativeImages;
    final attached = native ? _nativePrompt(turn) : _attachImages(turn);
    // The files open in the editor, each one once (F17): said after the
    // user's own words, as system reminders.
    final contexts = _contexts(turn.contexts);
    final text = [
      if (attached.text.trim().isNotEmpty) attached.text,
      for (final context in contexts) context.editorNote,
    ].join('\n\n');
    if (_disposed) return;
    emit(
      ItemUpserted(
        nextSeq,
        turn.id,
        UserMessageItem(
          text: attached.text,
          images: attached.images,
          contexts: contexts,
        ),
      ),
    );
    if (attached.dropped > 0) {
      emit(
        ItemUpserted(
          nextSeq,
          'dropped:${turn.id}',
          NoticeItem(
            NoticeKind.warning,
            '${attached.dropped} image(s) went unsent: one may be at most '
            '${imageMaxBytes ~/ 1000000} MB, a message '
            '${turnMaxBytes ~/ 1000000} MB.',
          ),
        ),
      );
    }
    if (_turn != turn.id) return;
    try {
      await _ensureStarted();
    } on Object catch (error) {
      if (!_disposed && _turn == turn.id) {
        emit(
          ItemUpserted(
            nextSeq,
            'error:${turn.id}',
            NoticeItem(NoticeKind.error, _health.message ?? '$error'),
          ),
        );
        _endTurn(interrupted: true);
      }
      return;
    }
    final slot = _slot;
    if (_turn != turn.id || slot == null) return;
    _lastPromptTurn = turn.id;
    try {
      // A turn's answer comes only when the turn ends, and a turn has no
      // upper bound: this request is not on the connection's clock (§3.4).
      final answer = await _connection!.request('session/prompt', {
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
      if (_turn != turn.id) return;
      _endTurn(interrupted: answer['stopReason'] == 'cancelled');
    } on Object catch (error) {
      if (_turn != turn.id) return;
      emit(
        ItemUpserted(
          nextSeq,
          'error:${turn.id}',
          NoticeItem(NoticeKind.error, '$error'),
        ),
      );
      _endTurn(interrupted: true);
    }
  }

  void _beginTurn(String id, {bool unprompted = false}) {
    // An automatic turn is its prompt turn's for a revert (§3.3).
    if (unprompted && _lastPromptTurn != null) {
      _autoTurnOf[id] = _lastPromptTurn!;
    }
    _events.begin();
    _turn = id;
    _turnUnprompted = unprompted;
    _turnStarted = DateTime.now();
    emit(TurnStarted(nextSeq, id, unprompted: unprompted));
  }

  /// A turn's start or end, or the window's (§19.2): taken up, held for a
  /// turn's end (D57), taken back before it starts (D62), ended (D63).
  void _turnReport(Object? mark) {
    final report = mark is Map ? mark : null;
    final phase = report?['phase'];
    if (phase == 'watch') {
      final on = report?['on'];
      if (on is bool) {
        _watching = on;
        if (!on) _releaseWhenIdle();
      } else {
        appEvent('thincoder', 'a watch frame with an on not a boolean: $on');
      }
      return;
    }
    final ok = report?['ok'];
    final pending = _pendingAuto;
    if (phase == 'start' && _turn == null) {
      appEvent('thincoder', 'an automatic turn (${report!['kind']})');
      _beginTurn('auto:${++_autoTurns}', unprompted: true);
    } else if (phase == 'start' && !_turnUnprompted && pending == null) {
      _pendingAuto = (id: 'auto:${++_autoTurns}', kind: report!['kind']);
    } else if (phase == 'end' && _turn != null && _turnUnprompted) {
      if (ok != null && ok is! bool) {
        appEvent('thincoder', 'a turn end with an ok not a boolean: $ok');
      }
      _endTurn(interrupted: ok == false);
    } else if (phase == 'end' && _turn != null && pending != null) {
      _pendingAuto = null;
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
  void _dropModelOf() {
    _modelTarget = null;
    _modelDeferred = false;
    _modelSending = false;
    emitInfoChanged();
  }

  /// Ends the turn under way: its item done, the approvals the agent was
  /// left waiting on resolved, and how long it took and what it spent.
  void _endTurn({required bool interrupted}) {
    final turn = _turn;
    if (turn == null) return;
    _turn = null;
    _turnUnprompted = false;
    _events.closePiece();
    _resolveApprovals();
    final started = _turnStarted;
    _turnStarted = null;
    final spent = _events.turnSpent;
    emit(
      TurnEnded(
        nextSeq,
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
    unawaited(_pumpModelOf(this));
    unawaited(_pumpTitle(this));
    // An automatic turn reported while this one ran goes first (D57).
    if (_pendingAuto case final pending?) {
      _pendingAuto = null;
      appEvent('thincoder', 'an automatic turn (${pending.kind})');
      _beginTurn(pending.id, unprompted: true);
      return;
    }
    // What waits goes first: letting the process go would drop it — the
    // release asked for stays for the turn after (D53).
    if (_drain()) return;
    _releaseWhenIdle();
  }

  @override
  void cancel() {
    final turn = _turn;
    if (turn == null) return;
    if (_slot == null || _connection == null) {
      // Nothing is running on the agent's side yet: the turn ends here.
      _endTurn(interrupted: true);
      return;
    }
    // The agent cancels the turn: its answer to `session/prompt`
    // (`stopReason: 'cancelled'`) is what ends it here (§3.6).
    unawaited(
      _connection!
          .request('session/cancel', {'sessionId': _slot})
          .catchError((_) => const <String, Object?>{}),
    );
  }

  /// Takes back a message still waiting: out of the queue, off the panel.
  /// One already sent is not taken back ([cancel] stops the turn instead).
  @override
  Future<bool> cancelQueued(String turnId) async {
    if (_next?.id == turnId) {
      _next = null;
    } else {
      final at = _queue.indexWhere((turn) => turn.id == turnId);
      if (at < 0) return false;
      _queue.removeAt(at);
    }
    emit(ItemRemoved(nextSeq, turnId));
    return true;
  }

  /// Takes up the waiting message [turnId] first: the turn running stops
  /// for it, the rest keep their order.
  @override
  void sendQueuedNow(String turnId) {
    // Already the one taken up next: only the turn running is in the way.
    if (_next?.id == turnId) {
      if (_turn != null) cancel();
      return;
    }
    final at = _queue.indexWhere((turn) => turn.id == turnId);
    if (at < 0) return;
    final ahead = _next;
    _next = _queue.removeAt(at);
    if (ahead != null) _queue.insert(0, ahead);
    if (_turn == null) {
      _drain();
    } else {
      cancel();
    }
  }

  // --- Renaming and reverting ---------------------------------------------------

  /// No turn under way, none reported, and a live connection to ask (§3.5).
  @override
  bool get canRevertNow => _turn == null && _pendingAuto == null && _running;

  @override
  void rename(String title) {
    // Before the session is made: kept for when it is (§3.4).
    if (_slot == null) {
      _pendingTitle = title;
      return;
    }
    _titleTarget = title;
    // A turn under way keeps the write back: it would land behind it (§3.5).
    if (_turn != null || _pendingAuto != null || _titleSending) {
      _titleDeferred = true;
      emitInfoChanged();
      return;
    }
    _titleDeferred = false;
    unawaited(_pumpTitle(this));
  }

  void _dropTitleOf() {
    _titleTarget = null; _titleDeferred = false; _titleSending = false;
    emitInfoChanged();
  }

  @override
  Future<RevertPlan> revertPlan({required String sinceTurn}) async =>
      _planOf(await _revert(sinceTurn, true));

  @override
  Future<RevertOutcome> applyRevert({required String sinceTurn}) async {
    final answer = await _revert(sinceTurn, false);
    final outcome = RevertOutcome(
      files: _revertFiles(answer['files']),
      skipped: _revertSkips(answer['skipped']),
      unrevertable: _revertSkips(answer['unrevertable']),
      failed: _revertFailures(answer['failed']),
    );
    // The host words the summary in its own language (§9, D-SG12); only
    // files put back clear its pending list (D-SG11).
    if (outcome.files.isNotEmpty) emit(ChangesReverted(nextSeq));
    return outcome;
  }

  /// `session/revert` for [sinceTurn]: its plan ([dryRun]), else what it did
  /// (§3.1). An automatic turn is the prompt turn it belongs to (§3.3).
  Future<Map<String, Object?>> _revert(String sinceTurn, bool dryRun) async {
    final connection = _connection, slot = _slot;
    final turn = _autoTurnOf[sinceTurn] ?? sinceTurn;
    if (connection == null || slot == null) {
      _revertFailed(sinceTurn, 'no session to revert in');
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
      _revertFailed(sinceTurn, '$error');
      rethrow;
    }
  }

  void _revertFailed(String sinceTurn, String reason) => emit(
    ItemUpserted(nextSeq, 'revert:$sinceTurn',
        NoticeItem(NoticeKind.error, 'Could not revert: $reason')),
  );

  // --- Approvals --------------------------------------------------------------

  /// The agent asks leave for a tool (`session/request_permission`): put to
  /// the user as it asked, and answered by [answer].
  bool _serverRequest(ThincoderRequest request) {
    if (_files.handle(request)) return true;
    if (request.method != 'session/request_permission') return false;
    final toolCall =
        (request.params['toolCall'] as Map?)?.cast<String, Object?>() ??
        const {};
    final options = [
      for (final option in request.params['options'] as List? ?? const [])
        if (option is Map) option.cast<String, Object?>(),
    ];
    final always = options
        .where((option) => option['optionId'] == 'approve_always')
        .firstOrNull;
    if (always == null) {
      // The panel's three values are what the agent sends (D19): without
      // them there is nothing to answer here, so it is refused — and said
      // in the log, since the agent reads that as a refusal.
      appEvent(
        'thincoder',
        'a permission request without approve_always: '
        '${[for (final option in options) option['optionId']]}',
      );
      return false;
    }
    final title = '${toolCall['title'] ?? ''}';
    final id = 'approval:${request.id}';
    _approvals[id] = request;
    emit(
      InteractionRequested(
        nextSeq,
        ApprovalRequest(
          id: id,
          title: title.isEmpty ? 'Approve a tool' : title,
          toolName: title.isEmpty ? 'tool' : title,
          preview: ThincoderEvents.preview(toolCall['content']),
          alwaysAllowLabel: '${always['name'] ?? 'Approve for this session'}',
        ),
      ),
    );
    return true;
  }

  @override
  void answer(String requestId, InteractionAnswer answer) {
    final request = _approvals.remove(requestId);
    if (request == null) return;
    emit(InteractionResolved(nextSeq, requestId));
    // The panel's three rows, as the agent's three options (D19). A reason
    // has no channel in the protocol (§14-2): not sent.
    final optionId = switch (answer) {
      ApprovalAnswer(decision: ApprovalDecision.allowOnce) => 'approve_once',
      ApprovalAnswer(decision: ApprovalDecision.allowAlways) =>
        'approve_always',
      _ => 'reject',
    };
    request.answer({
      'outcome': {'outcome': 'selected', 'optionId': optionId},
    });
    // "For this session" is the terminal's `/auto` switch, written too (D20).
    if (optionId == 'approve_always') {
      unawaited(_config('autoApprove', true));
    }
  }

  /// Drops what is waiting on the user: told the turn is over, and — for
  /// [refuse], when the kernel is going — answered as cancelled, which the
  /// agent takes as a refusal (T26).
  void _resolveApprovals({bool refuse = false}) {
    if (_approvals.isEmpty) return;
    for (final MapEntry(key: id, value: request) in _approvals.entries) {
      if (refuse) {
        request.answer({
          'outcome': {'outcome': 'cancelled'},
        });
      }
      emit(InteractionResolved(nextSeq, id));
    }
    _approvals.clear();
  }

  // --- What the agent reports -------------------------------------------------

  void _receive(Map<String, Object?> message) {
    if (message['type'] == ThincoderExit.type) {
      _exited(message);
      return;
    }
    _connection?.receive(message);
  }

  void _exited(Map<String, Object?> message) {
    final wasReady = _health.status == KernelHealthStatus.ready;
    final code = switch (message['code']) {
      final int code => code,
      final num code => code.toInt(),
      _ => -1,
    };
    final stderr = '${message['stderr'] ?? ''}'.trim();
    _teardown();
    if (_turn != null) {
      emit(
        ItemUpserted(
          nextSeq,
          'exit:${_turn!}',
          const NoticeItem(NoticeKind.error, 'thincoder stopped unexpectedly'),
        ),
      );
      _endTurn(interrupted: true);
    }
    if (_disposed) return;
    if (code == 0 && wasReady) {
      // It left of its own accord: the next use starts it again.
      _setHealth(KernelHealth.idle);
      return;
    }
    final lines = stderr.split('\n');
    final printed = lines
        .skip(lines.length > 12 ? lines.length - 12 : 0)
        .join('\n');
    _fail(
      'thincoder stopped',
      [
        if (printed.isNotEmpty) printed,
        if (message['executable'] case final String executable)
          'The one run: $executable',
      ].join('\n\n'),
    );
  }

  /// The automatic turn's mark in a `session_info_update` (§19.2).
  static const _turnKey = 'thincoder.dev/turn';

  void _notification(String method, Map<String, Object?> params) {
    if (method != 'session/update') {
      // E4 留痕: what it says that this adapter does not know.
      appEvent('thincoder', 'ignored notification $method');
      return;
    }
    final update = (params['update'] as Map?)?.cast<String, Object?>();
    if (update == null) return;
    // A turn boundary's mark is this adapter's, not a subagent's (F16).
    final meta = update['_meta'];
    if (update['sessionUpdate'] == 'session_info_update' &&
        meta is Map && meta.containsKey(_turnKey)) {
      _turnReport(meta[_turnKey]);
      return;
    }
    _events.update(update);
    // The last subagent may have left with this frame: the release asked
    // for is taken up after the macrotask it waits (D64).
    _releaseWhenIdle();
  }

  // --- The choices ------------------------------------------------------------

  @override
  late final KernelChoiceSource mode = _modeOf(this);

  /// The approval switch the agent reports (F13): the terminal's `/auto`.
  @override
  late final KernelChoiceSource permission = _permissionOf(this);

  @override
  late final KernelChoiceSource model = _modelOf(this);

  @override
  late final ModelSetting effort = _effortOf(this);

  Future<void> _setMode(String mode) => _setModeOf(this, mode);

  Future<void> _config(String configId, Object? value) =>
      _configOf(this, configId, value);

  // --- Pictures ---------------------------------------------------------------

  /// The most one picture may be, as the terminal takes them
  /// (`attachments.mjs:33`).
  static const imageMaxBytes = 15000000;

  /// The most a message's pictures together may be (`attachments.mjs:36`).
  static const turnMaxBytes = 30000000;

  static const _letters = '0123456789abcdefghijklmnopqrstuvwxyz';
  static final _random = math.Random();

  /// The turn's [contexts], one per file (its canonical absolute path):
  /// the same file said twice is said once.
  static List<EditorContext> _contexts(List<EditorContext> contexts) {
    final seen = <String>{};
    return [
      for (final context in contexts)
        if (seen.add(context.dedupeKey)) context,
    ];
  }

  /// The pictures of [turn] as the message to send: each saved where the
  /// agent runs (`<cwd>/.thincoder/tmp/paste-<runId>-<i>.<ext>`, the
  /// terminal's own naming) and named in the text; what is too big, or
  /// cannot be written, dropped and counted (F6).
  ({String text, List<ImageAttachment> images, int dropped}) _attachImages(
    KernelTurn turn,
  ) {
    final parts = [
      if (turn.text.trim().isNotEmpty) turn.text,
    ];
    var dropped = 0;
    final images = <ImageAttachment>[];
    final paths = <String>[];
    if (turn.images.isNotEmpty) {
      final runId = _runId();
      final dir = p.join(_cwd, '.thincoder', 'tmp');
      var budget = turnMaxBytes;
      for (final (index, image) in turn.images.indexed) {
        final ext = _imageExtension(image.mediaType);
        final bytes = image.bytes.length;
        final over = ext == null || bytes == 0 || bytes > imageMaxBytes;
        if (over || bytes > budget) {
          dropped++;
          continue;
        }
        try {
          Directory(dir).createSync(recursive: true);
          final file = File(p.join(dir, 'paste-$runId-$index.$ext'));
          file.writeAsBytesSync(image.bytes);
          paths.add(file.path);
          budget -= bytes;
          images.add(image);
        } on FileSystemException catch (error) {
          dropped++;
          appEvent('thincoder', 'an image was not written: ${error.message}');
        }
      }
    }
    if (paths.isNotEmpty) {
      parts.add('[Attached images: ${paths.join(' | ')}]');
    }
    return (text: parts.join('\n\n'), images: images, dropped: dropped);
  }

  /// [turn]'s pictures as native image blocks (F19), under the same limits.
  ({String text, List<ImageAttachment> images, int dropped}) _nativePrompt(
    KernelTurn turn,
  ) {
    var dropped = 0;
    final images = <ImageAttachment>[];
    var budget = turnMaxBytes;
    for (final image in turn.images) {
      final ext = _imageExtension(image.mediaType);
      final bytes = image.bytes.length;
      if (ext == null || bytes == 0 || bytes > imageMaxBytes || bytes > budget) {
        dropped++;
        continue;
      }
      budget -= bytes;
      images.add(image);
    }
    return (text: turn.text, images: images, dropped: dropped);
  }

  /// The extension of a picture of [mediaType], as the terminal names it;
  /// null for one it does not take.
  static String? _imageExtension(String mediaType) => switch (mediaType) {
    'image/png' => 'png',
    'image/jpeg' => 'jpg',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    _ => null,
  };

  /// What a run of saved pictures is named under: when, and a little
  /// chance (`Date.now().toString(36) + 4 random`).
  static String _runId() => [
    DateTime.now().millisecondsSinceEpoch.toRadixString(36),
    for (var i = 0; i < 4; i++) _letters[_random.nextInt(_letters.length)],
  ].join();
}

Future<void> _pumpTitle(ThincoderKernel kernel) async {
  final target = kernel._titleTarget;
  if (target == null || kernel._titleSending || kernel._turn != null ||
      kernel._pendingAuto != null || kernel._releaseWanted) {
    return;
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
