import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../chat/chat_models.dart';
import '../../models/model_provider.dart';
import '../../platform/event_log.dart';
import '../agent_kernel.dart';
import '../kernel_event.dart';
import '../kernel_types.dart';
import 'thincoder_events.dart';
import 'thincoder_locator.dart';
import 'thincoder_process.dart';
import 'thincoder_protocol.dart';
import 'thincoder_session_ref.dart';
import 'thincoder_transport.dart';

/// Adapts `thincoder acp` to [AgentKernel].
///
/// One process per session, started when its conversation is shown: ACP
/// over its stdin and stdout, one JSON object per line. Its sessions are
/// the ones the user's terminal keeps (the same slots in the same folder),
/// its modes and settings are what it reports them to be, and pictures go
/// to files the agent is told of — which its protocol cannot carry (F6).
///
/// What it does not have — plans as cards, forks, rewind, background
/// tasks — it does not declare, and the UI leaves those parts out.
class ThincoderKernel
    with KernelEventSource
    implements
        AgentKernel,
        ThincoderSink,
        SelectsMode,
        SelectsModel,
        SelectsEffort,
        SelectsPermission,
        ReportsContext,
        LoadsHistory,
        AcceptsImageFiles,
        QueuesMessages {
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

  /// The turn under way: its id, when it began, whether the agent took it
  /// up on its own (§19.2); automatic turns, and one held for a turn's end.
  String? _turn;
  DateTime? _turnStarted;
  bool _turnUnprompted = false;
  int _autoTurns = 0;
  ({String id, Object? kind})? _pendingAuto;
  final Set<String> _sent = {};

  /// Messages sent while a turn runs, in the order sent; [_next] first.
  final List<KernelTurn> _queue = [];
  KernelTurn? _next;

  /// Asked for while a turn runs: the process goes once it is over.
  bool _releaseWanted = false;

  /// Pending approvals: our request id → the agent's request to answer.
  final Map<String, ThincoderRequest> _approvals = {};

  // --- Lifecycle --------------------------------------------------------------

  @override
  KernelHealth get health => _health;

  @override
  String? get sessionId => _sessionId;

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
          // Nothing but the protocol's basics: no `fs` routing (the
          // agent's own reads and writes stay local), no terminal login
          // (D12). What is not said is unsupported.
          'clientCapabilities': <String, Object?>{},
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
    final resume = _context.resume;
    if (resume != null && !_recordGone) {
      await _openRecord(connection, resume);
    } else if (!await _pickUpKept(connection)) {
      await _openNew(connection);
    }
    _sessionId = switch (_slot) {
      final String slot => ThincoderSessionRef.combine(_cwd, slot),
      null => null,
    };
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
  ) async {
    final slot = ThincoderSessionRef.slotOf(resume.id) ?? resume.id;
    _slot = slot;
    if (_loaded) {
      if (!await _pickUp(connection, 'session/resume', slot)) {
        _recordGone = true;
        await _openNew(connection);
      }
      return;
    }
    // Loading replays the conversation: shown as it comes, and said to be
    // loading until it is all there.
    _events.begin();
    _loadingHistory = true;
    emitInfoChanged();
    try {
      _loaded = await _pickUp(connection, 'session/load', slot);
      if (!_loaded) {
        _recordGone = true;
        await _openNew(connection);
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
  ) async {
    try {
      _events.optionsFrom(
        await connection.request(method, {'sessionId': slot}),
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
  Future<bool> _pickUpKept(ThincoderConnection connection) async {
    final slot = _slot;
    if (slot == null) return false;
    return _pickUp(connection, 'session/resume', slot);
  }

  /// A session of its own, the first one (§3.5).
  Future<void> _openNew(ThincoderConnection connection) async {
    final created = await connection.request('session/new', {
      'cwd': _cwd,
      'mcpServers': <Object?>[],
    });
    _slot = switch (created['sessionId']) {
      final String id when id.isNotEmpty => id,
      final Object id => '$id',
      _ => null,
    };
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
    _releaseWanted = false;
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
    if (_turn != null || _starting != null) {
      _releaseWanted = true;
      return;
    }
    _closeSession();
    _teardown();
    _setHealth(KernelHealth.idle);
  }

  @override
  void dispose() {
    _disposed = true;
    _closeSession();
    _teardown();
    closeEvents();
  }

  // --- The conversation -------------------------------------------------------

  @override
  void send(KernelTurn turn) {
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
    // (F6), before anything is said of the message.
    final attached = _attachImages(turn);
    if (_disposed) return;
    emit(
      ItemUpserted(
        nextSeq,
        turn.id,
        UserMessageItem(text: attached.text, images: attached.images),
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
    try {
      // A turn's answer comes only when the turn ends, and a turn has no
      // upper bound: this request is not on the connection's clock (§3.4).
      final answer = await _connection!.request('session/prompt', {
        'sessionId': slot,
        'prompt': [
          {'type': 'text', 'text': attached.text},
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
    _events.begin();
    _turn = id;
    _turnUnprompted = unprompted;
    _turnStarted = DateTime.now();
    emit(TurnStarted(nextSeq, id, unprompted: unprompted));
  }

  /// An automatic turn's start or end (§19.2): taken up, held for a
  /// turn's end (D57), taken back before it starts (D62), ended (D63).
  void _turnReport(Object? mark) {
    final report = mark is Map ? mark : null;
    final phase = report?['phase'];
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

  /// Ends the turn under way: its item done, the approvals the agent was
  /// left waiting on resolved, and how long it took.
  void _endTurn({required bool interrupted}) {
    final turn = _turn;
    if (turn == null) return;
    _turn = null;
    _turnUnprompted = false;
    _events.closePiece();
    _resolveApprovals();
    final started = _turnStarted;
    _turnStarted = null;
    emit(
      TurnEnded(
        nextSeq,
        turn,
        interrupted: interrupted,
        worked: started == null
            ? null
            : DateTime.now().difference(started),
      ),
    );
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
    if (_releaseWanted) {
      _releaseWanted = false;
      release();
    }
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

  // --- Approvals --------------------------------------------------------------

  /// The agent asks leave for a tool (`session/request_permission`): put to
  /// the user as it asked, and answered by [answer].
  bool _serverRequest(ThincoderRequest request) {
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
  }

  // --- The choices ------------------------------------------------------------

  @override
  late final KernelChoiceSource mode = _Choice(
    options: () => _events.optionsOf('mode', _modeIcon),
    // The mode last reported — by the session's own word, or by
    // `current_mode_update` (§3.6); never one it has not taken up (D20).
    selected: () => _events.mode,
    select: (id) {
      if (id != 'plan' && id != 'normal') return;
      unawaited(_setMode(id));
    },
  );

  /// The approval switch the agent reports (F13): the terminal's `/auto`.
  @override
  late final KernelChoiceSource permission = _Choice(
    options: () => _events.configOf('autoApprove') == null
        ? const []
        : const [
            KernelOption(
              'ask',
              'Ask',
              Icons.front_hand_outlined,
              'Ask before each tool call',
            ),
            KernelOption(
              'auto',
              'Auto',
              Icons.fast_forward_rounded,
              'Tools run without asking — the same switch as /auto in the '
                  'terminal',
              caution: true,
            ),
          ],
    // What the agent last reported; never what was asked for (D20).
    selected: () => _events.configOf('autoApprove')?['currentValue'] == true
        ? 'auto'
        : 'ask',
    select: (id) => unawaited(_config('autoApprove', id == 'auto')),
  );

  @override
  late final KernelChoiceSource model = _Choice(
    options: () => _events.optionsOf('model', (value) => Icons.bolt_rounded),
    selected: () => _events.selected('model'),
    select: (id) => unawaited(_config('model', id)),
  );

  /// Whether the agent reports thinking levels (F14; an empty list is none).
  bool get _hasThinkingLevels =>
      (_events.configOf('thinkingLevel')?['options'] as List?)
          ?.isNotEmpty ??
      false;

  List<KernelOption> _thinkingLevels() => [
    for (final option
        in _events.optionsOf('thinkingLevel', (_) => Icons.speed_rounded))
      KernelOption(option.id, effortLabel(option.id), option.icon, ''),
  ];

  String? _thinkingChoice() => _hasThinkingLevels
      ? _events.selected('thinkingLevel')
      : _events.thinking
      ? 'on'
      : 'off';

  @override
  late final ModelSetting effort = _ModelSetting(
    toggles: () => !_hasThinkingLevels,
    optionsFor: (_) => _hasThinkingLevels
        ? _thinkingLevels()
        : _events.configOf('thinking') == null
        ? const []
        : const [
            KernelOption(
              'on',
              'Thinking',
              Icons.psychology_outlined,
              'Let the model think before it answers',
            ),
          ],
    selected: _thinkingChoice,
    selectedFor: (_) => _thinkingChoice(),
    // A switch flips; a level is picked as named (the agent's word, D20).
    select: (model, id) {
      if (_hasThinkingLevels) {
        unawaited(_config('thinkingLevel', id));
        return;
      }
      if (id != 'on') return;
      unawaited(_config('thinking', !_events.thinking));
    },
  );

  static IconData _modeIcon(String value) => switch (value) {
    'plan' => Icons.checklist_rounded,
    'normal' => Icons.all_inclusive_rounded,
    _ => Icons.tune_rounded,
  };

  Future<void> _setMode(String mode) async {
    try {
      await _connection!.request('session/set_mode', {
        'sessionId': _slot,
        'mode': mode,
      });
    } on Object catch (error) {
      appEvent('thincoder', 'set_mode($mode) failed: $error');
    }
  }

  Future<void> _config(String configId, Object? value) async {
    try {
      final answer = await _connection!.request('session/set_config_option', {
        'sessionId': _slot,
        'configId': configId,
        'value': value,
      });
      _events.optionsFrom(answer);
    } on Object catch (error) {
      // Shown as it stands: the report is the agent's (D20).
      appEvent('thincoder', 'set_config_option($configId) failed: $error');
    }
  }

  // --- Pictures ---------------------------------------------------------------

  /// The most one picture may be, as the terminal takes them
  /// (`attachments.mjs:33`).
  static const imageMaxBytes = 15000000;

  /// The most a message's pictures together may be (`attachments.mjs:36`).
  static const turnMaxBytes = 30000000;

  static const _letters = '0123456789abcdefghijklmnopqrstuvwxyz';
  static final _random = math.Random();

  /// The pictures of [turn] as the message to send: each saved where the
  /// agent runs (`<cwd>/.thincoder/tmp/paste-<runId>-<i>.<ext>`, the
  /// terminal's own naming) and named in the text; what is too big, or
  /// cannot be written, dropped and counted (F6).
  ({String text, List<ImageAttachment> images, int dropped}) _attachImages(
    KernelTurn turn,
  ) {
    final parts = [
      if (turn.text.trim().isNotEmpty) turn.text,
      ...turn.notes,
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

/// A choice over state the kernel holds: options and selection read live
/// (the form Claude Code's adapter keeps).
class _Choice implements KernelChoiceSource {
  _Choice({
    required this._options,
    required this._selected,
    required this._select,
  });

  final List<KernelOption> Function() _options;
  final String? Function() _selected;
  final void Function(String id) _select;
  List<KernelOption> _cache = const [];

  /// The same list while unchanged, so pickers keep their identity.
  @override
  List<KernelOption> get options {
    final fresh = _options();
    if (!listEquals(fresh, _cache)) _cache = fresh;
    return _cache;
  }

  @override
  String? get selected => _selected();

  @override
  void select(String id) {
    if (id != selected) _select(id);
  }
}

/// A setting that goes with the model, read live.
class _ModelSetting implements ModelSetting {
  _ModelSetting({
    required this._optionsFor,
    required this._selected,
    required this._selectedFor,
    required this._select,
    this._toggles,
  });

  final List<KernelOption> Function(String model) _optionsFor;
  final String? Function() _selected;
  final String? Function(String model) _selectedFor;
  final void Function(String model, String id) _select;

  final bool Function()? _toggles;

  @override
  bool get toggle => _toggles?.call() ?? false;

  @override
  List<KernelOption> optionsFor(String model) => _optionsFor(model);

  @override
  String? get selected => _selected();

  @override
  String? selectedFor(String model) => _selectedFor(model);

  @override
  void select(String model, String id) => _select(model, id);
}
