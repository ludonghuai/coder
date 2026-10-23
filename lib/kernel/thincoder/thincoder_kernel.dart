import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../browser/btest/btest_mode.dart';
import '../../chat/chat_models.dart';
import '../../host_tools/host_mcp_server.dart';
import '../../host_tools/host_tools.dart';
import '../../l10n/l10n.dart';
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
import 'thincoder_suggestions.dart';
import 'thincoder_transport.dart';
import 'thincoder_warm.dart';

part 'thincoder_choices.dart';
part 'thincoder_lifecycle.dart';
part 'thincoder_records.dart';
part 'thincoder_release.dart';
part 'thincoder_turns.dart';
part 'thincoder_title.dart';
part 'thincoder_revert.dart';
part 'thincoder_requests.dart';
part 'thincoder_inbound.dart';
part 'thincoder_images.dart';

/// Adapts `thincoder acp` to [AgentKernel].
///
/// One process per session, started when its conversation is shown: ACP
/// over its stdin and stdout, one JSON object per line. Its sessions are
/// the ones the user's terminal keeps (the same slots in the same folder),
/// its modes and settings are what it reports them to be, and pictures go
/// to files the agent is told of, or as native image blocks (F6 / F19).
///
/// What it does not have — plans as cards, forks, background tasks — it
/// does not declare, and the UI leaves those parts out.
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
        ConfirmsRename,
        PlansReverts,
        RewindsConversation,
        GeneratesTitles,
        SuggestsFiles,
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

  /// The prompt-to-first-content clock `timing: first-frame` reads (§25.6).
  Stopwatch? _firstFrame;

  /// The waiting line's item while a start is under way (§25.3-2), and whether it shows.
  static const _startingId = 'thincoder:starting';
  bool _waiting = false;

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

  /// The title the agent last confirmed (§28.4): the host's own write-back of
  /// it is skipped rather than sent again.
  String? _titleConfirmed;

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
    // The waiting line is a start's own: it goes with it (§25.3-2).
    if (_waiting && health.status != KernelHealthStatus.starting) {
      _waiting = false;
      emit(ItemRemoved(nextSeq, _startingId));
    }
    emitInfoChanged();
  }

  bool get _running =>
      _connection != null && _health.status == KernelHealthStatus.ready;

  String get _cwd => _context.cwd ?? _context.resume?.cwd ?? '.';

  // Starting and the handshake: see thincoder_lifecycle.dart.
  Future<void> _ensureStarted() => _ensureStartedOf(this);

  Future<void> _launch() => _launchOf(this);

  Future<void> _openSession() => _openSessionOf(this);

  Future<List<Map<String, Object?>>?> _hostMcpServers() =>
      _hostMcpServersOf(this);

  // The record, or a session of its own: see thincoder_records.dart.
  Future<void> _openRecord(
    ThincoderConnection connection,
    SessionRecord resume,
    List<Map<String, Object?>>? servers,
  ) => _openRecordOf(this, connection, resume, servers);

  Future<bool> _pickUp(
    ThincoderConnection connection,
    String method,
    String slot,
    List<Map<String, Object?>>? servers,
  ) => _pickUpOf(this, connection, method, slot, servers);

  Future<bool> _pickUpKept(
    ThincoderConnection connection,
    List<Map<String, Object?>>? servers,
  ) => _pickUpKeptOf(this, connection, servers);

  Future<void> _openNew(
    ThincoderConnection connection,
    List<Map<String, Object?>>? servers,
  ) => _openNewOf(this, connection, servers);

  void _applyStartMode() => _applyStartModeOf(this);

  void _handshake(Map<String, Object?> answer) => _handshakeOf(this, answer);

  void _fail(String message, String? detail) => _failOf(this, message, detail);

  // Letting go and starting over: see thincoder_release.dart.
  void _teardown() => _teardownOf(this);

  void _closeSession() => _closeSessionOf(this);

  @override
  void prepare() => prepareOf(this);

  @override
  void restart() => restartOf(this);

  @override
  void release() => releaseOf(this);

  bool get _canClose => _canCloseOf(this);

  void _releaseWhenIdle() => _releaseWhenIdleOf(this);

  @override
  void dispose() => disposeOf(this);

  // --- The conversation -------------------------------------------------------

  // The turns: see thincoder_turns.dart.
  @override
  void send(KernelTurn turn) => sendOf(this, turn);

  bool _drain() => _drainOf(this);

  Future<void> _deliver(KernelTurn turn) => _deliverOf(this, turn);

  void _beginTurn(String id, {bool unprompted = false}) =>
      _beginTurnOf(this, id, unprompted: unprompted);

  void _turnReport(Object? mark) => _turnReportOf(this, mark);

  void _dropModelOf() => _dropModelOfOf(this);

  void _endTurn({required bool interrupted}) =>
      _endTurnOf(this, interrupted: interrupted);

  @override
  void cancel() => cancelOf(this);

  @override
  Future<bool> cancelQueued(String turnId) => cancelQueuedOf(this, turnId);

  @override
  void sendQueuedNow(String turnId) => sendQueuedNowOf(this, turnId);

  // --- Renaming and reverting ---------------------------------------------------

  // A revert can start now: see thincoder_turns.dart.
  @override
  bool get canRevertNow => canRevertNowOf(this);

  // Renaming: see thincoder_title.dart.
  @override
  bool get renameConfirmed => renameConfirmedOf(this);

  @override
  void rename(String title) => renameOf(this, title);

  void _dropTitleOf() => _dropTitleOfOf(this);

  // Reverting and rewinding: see thincoder_revert.dart.
  @override
  Future<RevertPlan> revertPlan({required String sinceTurn}) =>
      revertPlanOf(this, sinceTurn: sinceTurn);

  @override
  Future<RevertOutcome> applyRevert({required String sinceTurn}) =>
      applyRevertOf(this, sinceTurn: sinceTurn);

  Future<Map<String, Object?>> _revert(String sinceTurn, bool dryRun) =>
      _revertOf(this, sinceTurn, dryRun);

  void _revertFailed(String sinceTurn, String reason) =>
      _revertFailedOf(this, sinceTurn, reason);

  // --- Rewinding --------------------------------------------------------------

  @override
  Future<bool> rewind({
    required String itemId,
    required int index,
    required int turns,
    String? lastSeen,
  }) => rewindOf(
    this,
    itemId: itemId,
    index: index,
    turns: turns,
    lastSeen: lastSeen,
  );

  void _rewindFailed(String itemId, String text) =>
      _rewindFailedOf(this, itemId, text);

  // --- Approvals --------------------------------------------------------------

  // What the agent asks leave for: see thincoder_requests.dart.
  bool _serverRequest(ThincoderRequest request) =>
      _serverRequestOf(this, request);

  @override
  void answer(String requestId, InteractionAnswer answer) =>
      answerOf(this, requestId, answer);

  void _resolveApprovals({bool refuse = false}) =>
      _resolveApprovalsOf(this, refuse: refuse);

  static bool _isBrowserTool(String title) => _isBrowserToolOf(title);

  // --- What the agent reports -------------------------------------------------

  // What the agent reports: see thincoder_inbound.dart.
  void _receive(Map<String, Object?> message) => _receiveOf(this, message);

  // Exiting and the waiting line: see thincoder_release.dart.
  void _exited(Map<String, Object?> message) => _exitedOf(this, message);

  void _sayWaiting() => _sayWaitingOf(this);

  void _noteFirstFrame(Map<String, Object?> update) =>
      _noteFirstFrameOf(this, update);

  /// The frames that carry content, not the usage or the options (§25.6).
  static const _content = {
    'agent_message_chunk', 'agent_thought_chunk', 'tool_call', 'tool_call_update',
  };

  /// The automatic turn's mark in a `session_info_update` (§19.2).
  static const _turnKey = 'thincoder.dev/turn';

  void _notification(String method, Map<String, Object?> params) =>
      _notificationOf(this, method, params);

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

  // --- Mention suggestions ----------------------------------------------------
  /// The project's files for the composer's `@` menu: the kernel runs where
  /// the project lives, so it lists them itself (no request to the agent).
  final _suggestions = ProjectSuggestions();
  @override
  Future<List<FileSuggestion>> suggestFiles(String query) =>
      _suggestions.of(_context.cwd, query);
  // --- Pictures ---------------------------------------------------------------

  /// The most one picture may be, as the terminal takes them
  /// (`attachments.mjs:33`).
  static const imageMaxBytes = 15000000;

  /// The most a message's pictures together may be (`attachments.mjs:36`).
  static const turnMaxBytes = 30000000;

  static const _letters = '0123456789abcdefghijklmnopqrstuvwxyz';
  static final _random = math.Random();

  // The pictures and the contexts a turn carries: see thincoder_images.dart.
  static List<EditorContext> _contexts(List<EditorContext> contexts) =>
      _contextsOf(contexts);

  ({String text, List<ImageAttachment> images, int dropped}) _attachImages(
    KernelTurn turn,
  ) => _attachImagesOf(this, turn);

  ({String text, List<ImageAttachment> images, int dropped}) _nativePrompt(
    KernelTurn turn,
  ) => _nativePromptOf(this, turn);

  static String? _imageExtension(String mediaType) =>
      _imageExtensionOf(mediaType);

  static String _runId() => _runIdOf();
}
