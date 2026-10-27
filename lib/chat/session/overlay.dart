import '../../browser/btest/btest_mode.dart';
import '../../browser/btest/btest_policy.dart' show BtestTraversal;
import '../../browser/btest/btest_run_state.dart';
import '../../kernel/agent_kernel.dart';
import '../../kernel/kernel_event.dart';
import '../../kernel/kernel_types.dart';
import '../chat_models.dart';
import '../chat_session_overlay.dart';
import '../open_editor.dart';
import 'lifecycle.dart';
import 'mode_state.dart';
import 'send_contexts.dart';
import 'transcript_proxy.dart';

/// The app's own overlay on a [ChatSessionOverlayHost]: what the host's
/// source does not keep — the kernels kept warm across a switch, the turn
/// marks, the notices the host itself puts in the conversation, and btest's
/// state — kept with the hooks that move it along (see the contract,
/// `chat_session_overlay.dart`).
///
/// It reads the host only through [ChatSessionOverlayHost]: no private
/// member of the host is reachable here, so this module builds and merges
/// beside the host's own source.
class BaocodeSessionOverlay implements ChatSessionOverlay {
  BaocodeSessionOverlay(this.host);

  /// The host it was made for: the overlay's own state is read without a
  /// host argument (the pickers read btest's), so it keeps this one.
  final ChatSessionOverlayHost host;

  /// btest's state (§3.1), opened at its first use under the conversation
  /// it is then: the values the settings keep are read on opening (§9.1,
  /// F11), and nothing is written here.
  BtestState? _btest;

  BtestState get _state => _btest ??=
      BtestMode.of(host.kernelContext.cwd, host.agentKernel.sessionId)
        ..fromSettings();

  /// The turns the kernel reported (see [MarksTurns]), for the folds.
  final List<TurnMark> _turns = [];

  /// How many items were put before the others, as last seen.
  int _prependedSeen = 0;

  /// What the host itself put in the conversation (§9): after the kernel's.
  final List<NoticeItem> _notices = [];

  /// The kernels switched away from before the conversation started, kept
  /// warm: switching back to one skips its start and the handshake its
  /// choices wait for. Dropped once the conversation starts (the kernel is
  /// then the conversation's own) and with the session.
  final Map<String, AgentKernel> _warm = {};

  /// A switch's t0 (§25.5): read once it is ready.
  Stopwatch? _switching;

  /// Where the transcript stood before the event being applied, and whether
  /// it cuts at the message that began the next turn (see [cutsAtMessage]).
  int _before = 0;
  bool _atMessage = false;

  @override
  List<ChatItem> get items => _notices;

  @override
  List<TurnMark> get turns => _turns;

  @override
  void addNotice(NoticeItem notice) {
    _notices.add(notice);
    host.notifyListeners();
  }

  // --- btest -------------------------------------------------------------------

  @override
  bool get btestOn => _state.on;

  @override
  BtestRun? get btestRun => _state.run;

  /// How the next run walks (§9.1): the status line's traversal switch,
  /// kept in `btest.traversal` so the next session reads it back.
  @override
  BtestTraversal get btestTraversal => _state.traversal;

  /// Whether the next run may act (§9.1): the status line's write switch,
  /// kept in `btest.mode`; before it is picked, `btest.readonly` stands.
  @override
  bool get btestWrite => _state.write;

  /// Picks btest beside the kernel's modes; picking another one turns it
  /// off (§3.1: normal / plan end it).
  @override
  void setBtest(bool on) {
    final state = _state;
    if (state.on == on) return;
    state.on = on;
    // Leaving with a run open drops it: a run's rules are btest's, and it
    // is never ended after the mode is off (§9: ended, or made void).
    if (!on) state.end();
    _publishBtest();
    host.notifyListeners();
  }

  /// Picks it (§9.1): the switch alone. A run under way keeps the traversal
  /// it started with; only the next run takes this.
  @override
  void setBtestTraversal(BtestTraversal value) {
    final state = _state;
    if (state.traversal == value) return;
    state.traversal = value;
    host.notifyListeners();
  }

  /// Picks it (§9.1): the switch alone — a run under way keeps its own.
  @override
  void setBtestWrite(bool value) {
    final state = _state;
    // Compared as the switch's own value, not as what it resolves to: a pick
    // that lands on the setting's value is still a pick, and rule A's text
    // then says where the write came from (§3.7).
    if (state.writePicked && state.write == value) return;
    state.write = value;
    host.notifyListeners();
  }

  /// Keeps the state under the session it is now (§3.1): a conversation
  /// gets its id after its first message. Nothing is created here for a
  /// conversation that never used btest.
  void _publishBtest() {
    final state = _btest;
    if (state == null) return;
    BtestMode.bind(
      state,
      cwd: host.kernelContext.cwd,
      sessionId: host.agentKernel.sessionId,
    );
  }

  @override
  KernelChoice? wrapModes(KernelChoice? base) => wrapModesOf(
    base,
    btestOn: _state.on,
    setBtest: setBtest,
  );

  // --- The host's lifecycle ----------------------------------------------------

  @override
  void onEventBefore(ChatSessionOverlayHost host, KernelEvent event) {
    _before = host.transcript.length;
    _atMessage = event is Rewound && cutsAtMessage(host.transcript, event, _before);
  }

  @override
  void onEventAfter(
    ChatSessionOverlayHost host,
    KernelEvent event, {
    required bool changed,
    required bool sessionChanged,
  }) {
    if (changed) {
      _prependedSeen = markTurnOf(
        _turns,
        _prependedSeen,
        event,
        host.transcript,
        before: _before,
        atMessage: _atMessage,
      );
    }
    if (!sessionChanged) return;
    _publishBtest();
    // The conversation started: its kernel stays, and the warm ones go.
    if (host.transcript.length > 0 || host.kernelContext.resume != null) {
      dropWarmKernels(_warm);
    }
    if (readKernelSwitch(_switching, host.agentKernel)) _switching = null;
  }

  @override
  void onAttach(ChatSessionOverlayHost host) {
    // The host has prepared its kernel and started its review by now.
    final opened = startOpenTiming();
    if (host.canSend) readInputReady(opened);
  }

  @override
  void onDetach(ChatSessionOverlayHost host) {
    // The view count and the release stay the host's.
  }

  @override
  void onKernelChanging(ChatSessionOverlayHost host, KernelDescriptor next) {
    _switching = Stopwatch()..start(); // t0 (§25.5).
  }

  @override
  bool cacheKernel(AgentKernel kernel) => cacheWarmKernel(_warm, kernel);

  @override
  AgentKernel? restoreKernel(KernelDescriptor descriptor) =>
      restoreWarmKernel(_warm, descriptor);

  @override
  void onKernelChanged(ChatSessionOverlayHost host) {
    _turns.clear();
    _prependedSeen = 0;
    _publishBtest();
    // A kernel kept warm is ready the moment it comes back: its line is read
    // here, not on an event it will never send. A cold one stays pending and
    // the first event reads it (§25.5).
    if (readKernelSwitch(_switching, host.agentKernel)) _switching = null;
  }

  @override
  KernelTurn beforeSend(
    ChatSessionOverlayHost host,
    KernelTurn turn,
    OpenEditor? editor,
  ) {
    final contexts = <EditorContext>[
      if (editor != null) ...contextsOf([editor]),
      ...btestContextsOf(_state, host.transcript),
    ];
    if (contexts.isEmpty) return turn;
    return KernelTurn(
      id: turn.id,
      text: turn.text,
      mentions: turn.mentions,
      images: turn.images,
      contexts: [...turn.contexts, ...contexts],
      now: turn.now,
      notes: turn.notes,
    );
  }

  @override
  void onDispose(ChatSessionOverlayHost host) {
    if (_btest case final state?) BtestMode.release(state);
    dropWarmKernels(_warm);
  }
}
