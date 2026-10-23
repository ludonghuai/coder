import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:path/path.dart' as p;

import '../browser/btest/btest_card.dart';
import '../browser/btest/btest_mode.dart';
import '../browser/btest/btest_policy.dart' show BtestTraversal;
import '../browser/btest/btest_run_state.dart';
import '../kernel/agent_kernel.dart';
import '../kernel/kernel_event.dart';
import '../kernel/kernel_registry.dart';
import '../kernel/kernel_types.dart';
import '../kernel/transcript.dart';
import '../platform/event_log.dart';
import '../remote/remote_location.dart';
import 'chat_feed.dart';
import 'chat_models.dart';
import 'composer/composer_draft.dart';
import 'composer/paste_store.dart';
import 'editor_context_setting.dart';
import 'mock_conversation.dart';
import 'open_editor.dart';
import 'review/change_review.dart';
import 'review/change_reviews.dart';
import 'review/review_store.dart';

part 'session/mode_state.dart';
part 'session/kernel_proxy.dart';
part 'session/transcript_proxy.dart';
part 'session/file_edits.dart';
part 'session/file_paths.dart';
part 'session/send_contexts.dart';
part 'session/session_commands.dart';
part 'session/lifecycle.dart';

/// Opens the review of a project's changes (see [ChangeReview.open]).
typedef ChangeReviewOpener = Future<ChangeReview?> Function(
  String root, {
  String? session,
});

/// A message submitted from the composer.
class ComposerMessage {
  const ComposerMessage({
    required this.text,
    this.mentions = const [],
    this.images = const [],
  });

  final String text;
  final List<String> mentions;
  final List<ImageAttachment> images;

  bool get isEmpty => text.trim().isEmpty && mentions.isEmpty && images.isEmpty;
}

/// One agent conversation, as the UI sees it, over an [AgentKernel].
///
/// It keeps only these things:
/// - the [Transcript], the kernel's conversation as reported;
/// - which kernel runs it, and where ([KernelContext]);
/// - the review of what it changed in the project ([ChangeReview]), where
///   there is one;
/// - UI state the kernel never hears of (changes kept, what is typed and
///   not sent).
///
/// Everything else (the status row, tasks, pending changes, the question
/// waiting, the model in effect) is projected from those or read from the
/// kernel. The UI reaches what the kernel can do through the facets here,
/// null when the kernel does not declare it.
class ChatSession extends ChangeNotifier implements ChatFeed, MarksTurns {
  ChatSession({
    KernelDescriptor? kernel,
    List<KernelDescriptor>? kernels,
    this.kernelContext = const KernelContext(),
    int historyCount = MockConversation.itemCount,
    List<FileChange> changes = const [],
    ContextUsage? usage,
    this.quietAfterText = const Duration(seconds: 5),
    ChangeReviewOpener? openReview,
  }) : kernels = kernels ?? KernelRegistry.all,
       _openReview =
           openReview ?? (reviewSupported ? ChangeReview.open : null) {
    _transcript = Transcript(
      historyCount: historyCount,
      history: historyCount > 0 ? MockConversation.itemAt : null,
      changes: changes,
      usage: usage ?? (historyCount > 0 ? MockConversation.usage : null),
    );
    _connect(kernel ?? this.kernels.first);
  }

  /// Kernels this session may switch to before its first message.
  final List<KernelDescriptor> kernels;

  /// Where its kernel works, and the session it continues.
  final KernelContext kernelContext;

  /// How long the status row keeps hidden after the agent's text, with
  /// nothing new: the text is most often followed at once, by a tool or the
  /// turn's end, and the row would only flash.
  final Duration quietAfterText;

  /// What is typed in its composer and not sent, while another
  /// conversation shows.
  final ComposerDraft draft = ComposerDraft();

  @override
  ({int index, ComposerDraft draft})? editing;

  /// The subagents opened in its view, one in the other (their ids,
  /// outermost first): shown again when the view comes back to it.
  List<String> openAgents = const [];

  late AgentKernel _kernel;
  StreamSubscription<KernelEvent>? _subscription;
  late Transcript _transcript;

  /// The conversation's btest state (§3.1): the host's own overlay, kept
  /// here and shared with the tool layer under its session key.
  late final BtestState _btest = _openBtest();

  /// Opens it with the values the settings keep (§9.1, F11): the mode and
  /// the two switches carry over a restart, and nothing is written here.
  BtestState _openBtest() =>
      BtestMode.of(kernelContext.cwd, _kernel.sessionId)..fromSettings();

  /// Whether btest, the host's third mode, is on (§3.1).
  bool get btestOn => _btest.on;

  /// The run under way, or null between runs (§3.3).
  BtestRun? get btestRun => _btest.run;

  /// Picks btest beside the kernel's modes; picking another one turns it
  /// off (§3.1: normal / plan end it).
  void setBtest(bool on) {
    if (_btest.on == on) return;
    _btest.on = on;
    // Leaving with a run open drops it: a run's rules are btest's, and it
    // is never ended after the mode is off (§9: ended, or made void).
    if (!on) _btest.end();
    _publishBtest();
    notifyListeners();
  }

  /// Keeps the state under the session it is now (§3.1): a conversation
  /// gets its id after its first message.
  void _publishBtest() => BtestMode.bind(
    _btest,
    cwd: kernelContext.cwd,
    sessionId: _kernel.sessionId,
  );

  /// How the next run walks (§9.1): the status line's traversal switch,
  /// kept in `btest.traversal` so the next session reads it back.
  BtestTraversal get btestTraversal => _btest.traversal;

  /// Picks it (§9.1): the switch alone. A run under way keeps the traversal
  /// it started with; only the next run takes this (§9.1, #40).
  void setBtestTraversal(BtestTraversal value) {
    if (_btest.traversal == value) return;
    _btest.traversal = value;
    notifyListeners();
  }

  /// Whether the next run may act (§9.1): the status line's write switch,
  /// kept in `btest.mode`; before it is picked, `btest.readonly` stands.
  bool get btestWrite => _btest.write;

  /// Picks it (§9.1): the switch alone — a run under way keeps its own.
  void setBtestWrite(bool value) {
    // Compared as the switch's own value, not as what it resolves to: a pick
    // that lands on the setting's value is still a pick, and rule A's text
    // then says where the write came from (§3.7).
    if (_btest.writePicked && _btest.write == value) return;
    _btest.write = value;
    notifyListeners();
  }

  /// The turns the kernel reported (see [MarksTurns]), for the folds.
  final List<TurnMark> _turns = [];

  /// How many items were put before the others, as last seen.
  int _prependedSeen = 0;

  @override
  List<TurnMark> get turns => _turns;

  /// Changes reported at or below this sequence were kept.
  int _keptSeq = -1;

  /// Changes kept file by file: those to a path reported at or below its
  /// sequence.
  final Map<String, int> _keptPaths = {};

  void _connect(KernelDescriptor descriptor) => _connectOf(this, descriptor);
  /// The kernels switched away from before the conversation started, kept
  /// warm: switching back to one skips its start and the handshake its
  /// choices wait for. Dropped once the conversation starts (the kernel is
  /// then the conversation's own) and with the session.
  final Map<String, AgentKernel> _warm = {};
  Stopwatch? _switching; // A switch's t0 (§25.5): read once it is ready.

  void _dropWarm() => _dropWarmOf(this);
  void _apply(KernelEvent event) {
    // A frame may land between `cancel()` and the kernel letting go: there is
    // then no listener left to tell.
    if (_disposed) return;
    // A rename is the session's, not the conversation's: it sets the title
    // the workspace takes, and is not a turn's event.
    if (event case SessionRenamed(:final title)) {
      _renamed = title;
      notifyListeners();
      return;
    }
    final before = _transcript.length;
    final atMessage = event is Rewound && _cutsAtMessage(event, before);
    final changed = event is! KernelInfoChanged && _transcript.apply(event);
    if (changed) _markTurn(event, before, atMessage);
    if (event is KernelInfoChanged || changed) {
      _publishBtest();
      _cache.clear();
      _timeQuiet();
      _reviewEvent(event);
      if (kernelLocked) _dropWarm();
      _readSwitch();
      notifyListeners();
    }
  }

  /// Whether [event] cuts the history at a message sent: the prompt of the
  /// turn after it, which that turn does not own.
  bool _cutsAtMessage(Rewound event, int before) {
    final at = switch (event.itemId) {
      final id? => _transcript.indexOf(id) ?? event.index,
      null => event.index,
    };
    if (at == null || at < 0 || at >= before) return false;
    return _transcript.itemAt(at) is UserMessageItem;
  }

  /// Keeps the turn [event] tells of in [_turns]: every turn from where it
  /// starts, and how long it worked, for the transcript it changed.
  void _markTurn(KernelEvent event, int before, bool atMessage) {
    switch (event) {
      case TurnStarted(:final turnId, :final unprompted):
        final start = _transcript.length;
        // Its message, under the turn's id (a queued one may land early).
        final prompt = unprompted ? null : _transcript.indexOf(turnId) ?? start;
        _turns.add((
          turnId: turnId,
          start: start,
          prompt: prompt,
          worked: null,
        ));
      case TurnEnded(:final turnId, :final interrupted, :final worked):
        // A turn the history no longer holds is not told of any more.
        for (var i = _turns.length - 1; i >= 0; i--) {
          final mark = _turns[i];
          if (mark.turnId != turnId) continue;
          _turns[i] = (
            turnId: turnId,
            start: mark.start,
            prompt: mark.prompt,
            worked: interrupted ? null : worked,
          );
          break;
        }
      case HistoryPrepended():
        final moved = _transcript.prepended - _prependedSeen;
        _prependedSeen = _transcript.prepended;
        if (moved == 0) break;
        for (var i = 0; i < _turns.length; i++) {
          final mark = _turns[i];
          _turns[i] = (
            turnId: mark.turnId,
            start: mark.start + moved,
            prompt: mark.prompt == null ? null : mark.prompt! + moved,
            worked: mark.worked,
          );
        }
      case Rewound():
        // What it cut away, or cut into, is no turn any more.
        final cut = _transcript.length;
        int? nearest;
        while (_turns.isNotEmpty && _turns.last.start >= cut) {
          nearest = _turns.last.start;
          _turns.removeLast();
        }
        // A turn the cut runs into, or took items from, goes too — unless
        // the cut is at the message that began the next turn: that message
        // is the next turn's, and this turn ended before it.
        final crossed =
            (nearest != null ? nearest > cut : before > cut) && !atMessage;
        if (crossed && _turns.isNotEmpty) _turns.removeLast();
      default:
    }
  }

  // --- The review of its changes ----------------------------------------------

  final ChangeReviewOpener? _openReview;

  /// The review of the changes, while it opens; null when there is none.
  Future<ChangeReviews?>? _reviewOpening;
  ChangeReviews? _review;

  /// The review, while it holds: null before it opened, or once it failed
  /// (the changes are then those the kernel reported).
  ChangeReviews? get _activeReview => switch (_review) {
    final review? when review.failure == null => review,
    _ => null,
  };

  /// Opens the review of the project (each of its folders, in a
  /// multi-folder workspace), the first time.
  void _startReview() {
    if (_reviewOpening != null) return;
    final open = _openReview;
    final root = kernelContext.cwd;
    if (open == null || root == null) return;
    _reviewOpening =
        ChangeReviews.open(
          [root, ...?kernelContext.workspace?.call()?.folders],
          open: open,
          session: kernelContext.resume?.id,
        ).then((review) {
          if (review == null) return null;
          if (_disposed) {
            review.dispose();
            return null;
          }
          _review = review
            ..session = sessionId
            ..addListener(_reviewChanged);
          unawaited(review.refresh());
          notifyListeners();
          return review;
        }, onError: (Object _) => null);
  }

  void _reviewChanged() {
    if (!_disposed) notifyListeners();
  }

  void _reviewEvent(KernelEvent event) {
    final review = _review;
    if (review == null) return;
    review.session = sessionId;
    switch (event) {
      case TurnEnded():
        unawaited(review.refresh());
      case FileEdited(:final change, :final original):
        review.report(change, original: original);
      case ChangesReverted():
        unawaited(review.refresh());
      default:
    }
  }

  Timer? _quietTimer;
  bool _quiet = false;

  /// Times the quiet after the agent's text, anew on every change.
  void _timeQuiet() {
    _quietTimer?.cancel();
    _quiet = false;
    if (!isStreaming || _last is! AssistantTextItem) return;
    _quietTimer = Timer(quietAfterText, () {
      _quiet = true;
      notifyListeners();
    });
  }

  ChatItem? get _last => _transcript.length == 0
      ? null
      : _transcript.itemAt(_transcript.length - 1);

  // --- The kernel -------------------------------------------------------------

  KernelDescriptor get kernel => _kernel.descriptor;

  KernelHealth get health => _healthOf(this);
  bool get loadingHistory => _loadingHistoryOf(this);
  bool get hasEarlierHistory => _hasEarlierHistoryOf(this);
  /// How many items were put before the others by [loadEarlier] so far: the
  /// indexes of those there were moved by as many.
  int get prependedCount => _transcript.prepended;
  bool get loadingEarlier => _loadingEarlierOf(this);
  Future<void> loadEarlier() => _loadEarlierOf(this);
  String? get sessionId => _sessionIdOf(this);
  Future<void> get stopped => _stoppedOf(this);
  void restart() => _restartOf(this);
  int _views = 0;

  void attach() => _attachOf(this);
  void detach() => _detachOf(this);
  bool get kernelLocked => _kernelLockedOf(this);
  late final List<KernelOption> _kernelOptions = [
    for (final descriptor in kernels) descriptor.option,
  ];

  KernelChoice? get kernelChoice => _kernelChoiceOf(this);
  void setKernel(KernelDescriptor descriptor) => _setKernelOf(this, descriptor);
  void _readSwitch() => _readSwitchOf(this);
  // --- Facets: what the kernel declares ------------------------------------------

  KernelChoice? get models => _modelsOf(this);
  bool switchRestarts(String model) => _switchRestartsOf(this, model);
  String? get pendingModel => _pendingModelOf(this);
  /// btest's option in the same picker as the kernel's modes (§3.1, §9:
  /// `btest` is not translated).
  static const _btestId = 'btest';
  static const _btestOption = KernelOption(
    _btestId,
    'btest',
    Icons.science_outlined,
    'Browser business testing: one run on the real pages, the expectations '
        'read from the files, one report at the end',
  );

  KernelChoice? get modes => _modesOf(this);
  KernelChoice? get permissions => _permissionsOf(this);
  List<ModelSettingChoice> modelSettings(String model) => _modelSettingsOf(this, model);
  List<(KernelChoiceKind, ModelSetting)> get _modelSettings => [
    if (_kernel case final SelectsContextSize kernel)
      (KernelChoiceKind.context, kernel.contextSize),
    if (_kernel case final SelectsEffort kernel)
      (KernelChoiceKind.effort, kernel.effort),
    if (_kernel case final SelectsFast kernel)
      (KernelChoiceKind.fast, kernel.fast),
  ];

  String? selected(KernelChoiceKind kind) => _selectedOf(this, kind);
  KernelChoice? _choice(KernelChoiceSource source) => _choiceOf(this, source);
  List<KernelCommand> get commands => _commandsOf(this);
  bool get hasCommandSource => _hasCommandsOf(this);
  Future<List<FileSuggestion>> Function(String query)? get suggestFiles => _suggestFilesOf(this);
  ContextUsage? get context => _contextOf(this);
  UsageStats? get stats => _statsOf(this);
  void refreshUsage() => _refreshUsageOf(this);
  DateTime? get usageLimitResetsAt => _usageLimitResetsAtOf(this);
  bool get usageLimitApplies => _usageLimitAppliesOf(this);
  bool continuesAfterLimit(String model) => _continuesAfterLimitOf(this, model);
  bool get acceptsImages => _acceptsImagesOf(this);
  bool get acceptsEditorContext => _acceptsEditorContextOf(this);
  String? get promptSuggestion => _promptSuggestionOf(this);
  List<McpServer>? get mcpServers => _mcpServersOf(this);
  void refreshMcpServers() => _refreshMcpServersOf(this);
  void setMcpServerEnabled(McpServer server, bool enabled) => _setMcpServerEnabledOf(this, server, enabled);
  void reconnectMcpServer(McpServer server) => _reconnectMcpServerOf(this, server);
  Future<Uri?> authenticateMcpServer(McpServer server) async => _authenticateMcpServerOf(this, server);
  @override
  bool get canEditMessages => _canEditMessagesOf(this);
  bool get canQueue => _canQueueOf(this);
  bool get canRename => _canRenameOf(this);
  bool get renameConfirmed => _renameConfirmedOf(this);
  bool get ownsTitle => _ownsTitleOf(this);
  String? get pendingTitle => _pendingTitleOf(this);
  bool get canFork => _canForkOf(this);
  Future<SessionRecord?> fork({required String title}) async => _forkOf(this, title: title);
  // --- Projections ------------------------------------------------------------

  @override
  bool get isStreaming => _isStreamingOf(this);
  @override
  bool get isUnprompted => _isUnpromptedOf(this);
  bool get canSend => _canSendOf(this);
  InteractionRequest? get pendingInteraction => _pendingInteractionOf(this);
  /// The plan the agent last wrote this run, and the sequence it was
  /// reported at: higher each time it writes it again.
  ({String path, int seq})? get plan => _transcript.plan;

  PlanItem? get awaitingPlan => _awaitingPlanOf(this);
  ((Transcript, int, int), PlanItem?)? _awaitingPlan;

  bool get canStartPlan => _canStartPlanOf(this);
  void startPlan(String text) => _startPlanOf(this, text);
  int get lastTurnEndSeq => _lastTurnEndSeqOf(this);
  String? get lastReply => _lastReplyOf(this);
  bool get lastTurnInterrupted => _lastTurnInterruptedOf(this);
  bool get lastTurnUnprompted => _lastTurnUnpromptedOf(this);
  @override
  int get itemCount => _itemCountOf(this);
  @override
  ChatItem itemAt(int index) => _itemAtOf(this, index);
  bool get _statusVisible => _statusVisibleOf(this);
  List<KernelTask>? get tasks => _tasksOf(this);
  List<KernelTask> get terminalTasks => _terminalTasksOf(this);
  void stopTask(KernelTask task) => _stopTaskOf(this, task);
  bool get canStopTasks => _canStopTasksOf(this);
  @override
  VoidCallback? moveToBackgroundAt(int index) => _moveToBackgroundAtOf(this, index);
  VoidCallback? moveToBackgroundOf(String? id) => _moveToBackgroundOfOf(this, id);
  /// The subagent [task] runs, wherever it shows: in the conversation
  /// itself or in another subagent's (one a subagent started). With the ids
  /// of those leading to it, outermost first and its own last: the path a
  /// [SubagentFeed] takes.
  ///
  /// Found by the tool call that started it; where the kernel did not say
  /// which, by its description, among those still running.
  ({AgentItem agent, List<String> path})? agentOf(KernelTask task) {
    final id = task.toolUseId;
    bool matches(AgentItem agent) => id != null
        ? agent.id == id
        : agent.status == CommandStatus.running &&
              agent.description == task.description;
    ({AgentItem agent, List<String> path})? within(
      AgentItem agent,
      List<String> path,
    ) {
      final own = agent.id;
      if (own == null) return null;
      final here = [...path, own];
      if (matches(agent)) return (agent: agent, path: here);
      for (final child in agent.children.reversed) {
        if (child is AgentItem) {
          if (within(child, here) case final found?) return found;
        }
      }
      return null;
    }

    if (id == null && task.kind != KernelTaskKind.agent) return null;
    for (var index = _transcript.length - 1; index >= 0; index--) {
      if (_transcript.itemAt(index) case final AgentItem agent) {
        if (within(agent, const []) case final found?) return found;
      }
    }
    return null;
  }

  String? commandOf(String? id) => _commandOfOf(this, id);
  @override
  VoidCallback? stopAt(int index) => _stopAtOf(this, index);
  VoidCallback? stopOf(String? id) => _stopOfOf(this, id);
  KernelTask? _runningTask(String? toolUseId) => toolUseId == null
      ? null
      : _transcript.tasks
            .where(
              (task) =>
                  task.toolUseId == toolUseId &&
                  task.status == CommandStatus.running,
            )
            .firstOrNull;

  List<TodoEntry> get todos => _todosOf(this);
  KernelGoal? get goal => _goalOf(this);
  KernelGoal? _dismissedGoal;

  void dismissGoal() => _dismissGoalOf(this);
  void setGoal(String condition) => _setGoalOf(this, condition);
  void clearGoal() => _clearGoalOf(this);
  String? get root => _rootOf(this);
  List<FileChange> get fileChanges => _fileChangesOf(this);
  List<String> get filesSeen => _filesSeenOf(this);
  List<String> _filesSeen = const [];

  p.Context get paths => _pathsOf(this);
  String _absolute(String path) => _absoluteOf(this, path);
  Iterable<({int seq, FileChange change, String? turnId})> get _pendingEdits {
    final settled = math.max(_keptSeq, _transcript.revertedSeq);
    return _transcript.edits.where(
      (edit) =>
          edit.seq > settled &&
          edit.seq > (_keptPaths[_absolute(edit.change.path)] ?? -1),
    );
  }

  void keepAllChanges() => _keepAllChangesOf(this);
  void keepChanges(List<FileChange> changes) => _keepChangesOf(this, changes);
  VoidCallback? get undoAllChanges => _undoAllChangesOf(this);
  String? get revertTurn => _revertTurnOf(this);
  bool get canPlanRevert => _canPlanRevertOf(this);
  bool get plansReverts => _plansRevertsOf(this);
  Future<RevertPlan> revertPlan(String sinceTurn) => _revertPlanOf(this, sinceTurn);
  Future<RevertOutcome> applyRevert(String sinceTurn) => _applyRevertOf(this, sinceTurn);
  /// What the host itself put in the conversation (§9): after the kernel's.
  final List<NoticeItem> _notices = [];

  /// Puts [notice] at the conversation's end: the host's own (§9: a
  /// revert's summary), the kernel sending none of it.
  void addNotice(NoticeItem notice) {
    _notices.add(notice);
    notifyListeners();
  }

  ValueChanged<List<FileChange>>? get undoChanges => _undoChangesOf(this);
  Future<String> Function()? originalOf(FileChange change) => _originalOfOf(this, change);
  /// The review of the agent's changes while it holds (the editor keeps
  /// and undoes them part by part with it); null without one.
  ChangeReviews? get changeReview => _activeReview;

  final Map<Symbol, Object> _cache = {};
  int _cacheVersion = -1;

  int get lastImageNumber => _lastImageNumberOf(this);
  T _cached<T extends Object>(Symbol key, T Function() compute) {
    if (_cacheVersion != _transcript.version) {
      _cache.clear();
      _cacheVersion = _transcript.version;
    }
    return _cache.putIfAbsent(key, compute) as T;
  }

  // --- Commands ---------------------------------------------------------------

  /// The file the agent was last told is open, once told (see
  /// [_editorNotes]).
  OpenEditor? _toldEditor;
  bool _toldOfEditor = false;

  List<String> _editorNotes(OpenEditor? editor) => _editorNotesOf(this, editor);
  static List<EditorContext> _contexts(Iterable<OpenEditor> editors) => _contextsOf(editors);
  /// Sends [message]; [now], taken up at once, the turn running stopped
  /// for it (rather than queued behind it). With a plan awaiting (see
  /// [awaitingPlan]), it says what should change in it.
  ///
  /// [editor] gives the file open in the editor beside the chat, where
  /// there is one. A kernel that takes it with each message
  /// ([AcceptsEditorContext]) is given it with this one unless
  /// [editorContext] is false (dismissed for this draft) or the
  /// `chat.editorContext` setting is off; the rest are told of it as it
  /// changes.
  void send(
    ComposerMessage message, {
    bool now = false,
    OpenEditor? Function()? editor,
    bool editorContext = true,
  }) {
    if (message.isEmpty || !canSend) return;
    final takesContext = _kernel is AcceptsEditorContext;
    final open = takesContext && editorContext && EditorContextSetting.current()
        ? editor?.call()
        : null;
    final turn = KernelTurn(
      id: newTurnId(),
      // Pastes too long to send, kept in files the agent reads; a remote
      // project's agent cannot, and is sent them.
      text: switch (kernelContext.cwd) {
        final cwd? when RemoteLocation.isRemote(cwd) => message.text.trim(),
        _ => PasteStore.offload(message.text.trim()),
      },
      mentions: message.mentions,
      images: acceptsImages ? message.images : const [],
      contexts: [
        if (open != null) ..._contexts([open]),
        ..._btestContexts(),
      ],
      now: now,
      notes: takesContext || editor == null ? const [] : _editorNotes(editor()),
    );
    // A turn about to start: what was put back since the last is no
    // longer pending.
    if (_review case final review? when !isStreaming) {
      unawaited(review.refresh());
    }
    _kernel.send(turn);
  }

  /// What btest adds to the turn being assembled (§3.2): the card on the
  /// first turn in the mode, the line that ends it on the first turn after
  /// — counted from the conversation itself, never from a flag in memory.
  List<EditorContext> _btestContexts() {
    final told = BtestCard.forTurn(on: _btest.on, transcript: _toldTexts());
    if (told == null) return const [];
    return [
      TextContext(key: BtestCard.contextKey, name: 'btest', text: told),
    ];
  }

  /// Every text the conversation holds, for the card count: the messages',
  /// and the notes of the contexts sent with them.
  Iterable<String> _toldTexts() sync* {
    for (var i = 0; i < _transcript.length; i++) {
      if (_transcript.itemAt(i) case final UserMessageItem message) {
        yield message.text;
        for (final context in message.contexts) {
          yield context.editorNote;
        }
      }
    }
  }

  static final _random = math.Random.secure();

  /// A random UUID (v4): kernels may use it as the message's id.
  static String newTurnId() {
    String hex(int length) =>
        [for (var i = 0; i < length; i++) _random.nextInt(16).toRadixString(16)]
            .join();
    final variant = (8 + _random.nextInt(4)).toRadixString(16);
    return '${hex(8)}-${hex(4)}-4${hex(3)}-$variant${hex(3)}-${hex(12)}';
  }

  /// The messages sent while the agent works, waiting their turn, with
  /// their ids: the next first. Not in the conversation until taken up.
  List<(String, UserMessageItem)> get queued => _transcript.queued;

  /// Takes back the queued message [id].
  void cancelQueued(String id) {
    if (_kernel case final QueuesMessages kernel) {
      unawaited(kernel.cancelQueued(id));
    }
  }

  /// Takes back the queued message [id] to be edited: into the composer's
  /// [draft], once taken back (not if it started meanwhile).
  Future<void> editQueued(String id) async {
    final message = _transcript.queued
        .where((queued) => queued.$1 == id)
        .firstOrNull
        ?.$2;
    if (message == null) return;
    if (_kernel case final QueuesMessages kernel
        when await kernel.cancelQueued(id) && !_disposed) {
      draft.restore(message.text, message.images);
    }
  }

  /// Takes up the queued message [id] now: the turn running stops for it.
  void sendQueuedNow(String id) {
    if (_kernel case final QueuesMessages kernel) kernel.sendQueuedNow(id);
  }

  /// Resends the user message at [index] as [message]: everything after it
  /// is discarded and the turn runs again from there.
  @override
  void editMessage(int index, ComposerMessage message) {
    if (_kernel case final RewindsConversation kernel
        when !message.isEmpty && itemAt(index) is UserMessageItem) {
      stop();
      var turns = 0;
      String? lastSeen;
      for (var i = index; i < _transcript.length; i++) {
        if (_transcript.itemAt(i) case UserMessageItem(:final queued)) {
          turns++;
          if (!queued) lastSeen = _transcript.idAt(i) ?? lastSeen;
        }
      }
      // Sent once the agent has gone back: turned down, it would follow
      // all of the conversation.
      unawaited(
        kernel
            .rewind(
              itemId: _transcript.idAt(index) ?? '$index',
              index: index,
              turns: turns,
              lastSeen: lastSeen,
            )
            .then((rewound) {
              if (rewound && !_disposed) send(message);
            }),
      );
    }
  }

  void stop() => _stopOf(this);
  void answer(InteractionAnswer answer) => _answerOf(this, answer);
  void rename(String title) => _renameOf(this, title);
  String? _renamed;

  /// The name it was last given in the agent itself (Claude Code's
  /// `/rename`), once: null after.
  String? takeRenamed() {
    final renamed = _renamed;
    _renamed = null;
    return renamed;
  }

  void discardChanges() => _discardChangesOf(this);
  bool _disposed = false;

  /// Tells its listeners: the part files' functions reach `notifyListeners`
  /// through here, as the protected member is the class's own to call.
  void _notify() => notifyListeners();

  @override
  void dispose() {
    _disposed = true;
    BtestMode.release(_btest);
    _quietTimer?.cancel();
    _review
      ?..removeListener(_reviewChanged)
      ..dispose();
    unawaited(_subscription?.cancel());
    _kernel.dispose();
    _dropWarm();
    super.dispose();
  }
}
