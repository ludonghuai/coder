// The contract between a ChatSession and the app's own overlay: what the
// host opens to it, and what the overlay gives back — the items it adds,
// the turn marks it keeps, btest's state, and the hooks the host calls as
// it connects, switches, sends, mounts and releases.
//
// This file imports no ChatSession: the session modules import it alone, so
// they build and merge apart from the host's own source.

import 'package:flutter/foundation.dart';

import '../browser/btest/btest_policy.dart' show BtestTraversal;
import '../browser/btest/btest_run_state.dart' show BtestRun;
import '../kernel/agent_kernel.dart';
import '../kernel/kernel_event.dart';
import '../kernel/kernel_types.dart';
import '../kernel/transcript.dart';
import 'chat_models.dart';
import 'open_editor.dart';

/// A choice a kernel offers (its model, its mode, the kernel itself): the
/// options, the one in effect, and how to pick another.
class KernelChoice {
  const KernelChoice({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<KernelOption> options;
  final KernelOption selected;
  final ValueChanged<KernelOption> onSelected;
}

/// A setting picked beside a model, e.g. its effort (see [ModelSetting]).
class ModelSettingChoice {
  const ModelSettingChoice({
    required this.kind,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.toggle = false,
  });

  /// The kernel's setting it is; null for the app's own, shown beside them
  /// (`chat.resumeAfterLimitReset`, in the model picker).
  final KernelChoiceKind? kind;
  final List<KernelOption> options;

  /// What is in effect, or would stay so with the model picked; null
  /// while not known.
  final KernelOption? selected;

  /// Whether this setting is on or off, shown and picked as a switch: what
  /// it shows under an option is not a check but a switch, and picking it
  /// leaves the menu open (see [ComposerPicker]).
  final bool toggle;

  /// Picks the option, and the model with it.
  final ValueChanged<KernelOption> onSelected;
}

/// The host as the overlay sees it: the few public projections its modules
/// read, and the one way it tells its listeners. Nothing of the host's
/// private state is reachable through it.
abstract interface class ChatSessionOverlayHost {
  KernelContext get kernelContext;
  AgentKernel get agentKernel;
  Transcript get transcript;
  bool get canSend;
  void notifyListeners();
}

/// One conversation's overlay: the app's own state kept beside the host's
/// (see [BaocodeSessionOverlay]), and the hooks that keep it in step with
/// the host's life.
abstract interface class ChatSessionOverlay {
  /// What the host itself put in the conversation, after the transcript's
  /// own items and before the live status row.
  List<ChatItem> get items;
  List<TurnMark> get turns;
  void addNotice(NoticeItem notice);

  bool get btestOn;
  BtestRun? get btestRun;
  BtestTraversal get btestTraversal;
  bool get btestWrite;
  void setBtest(bool on);
  void setBtestTraversal(BtestTraversal value);
  void setBtestWrite(bool value);

  /// [base] as the modes picker shows it: btest beside the kernel's own
  /// modes when the kernel offers any.
  KernelChoice? wrapModes(KernelChoice? base);

  /// Called before the host applies [event] to its transcript: where the
  /// turn bookkeeping reads the conversation from.
  void onEventBefore(ChatSessionOverlayHost host, KernelEvent event);

  /// Called once the transcript has taken [event], before the review and
  /// the listeners hear of it. [changed] is the transcript's own answer;
  /// [sessionChanged] the host's, which also counts [KernelInfoChanged].
  void onEventAfter(
    ChatSessionOverlayHost host,
    KernelEvent event, {
    required bool changed,
    required bool sessionChanged,
  });

  /// A view came to the conversation, or left it.
  void onAttach(ChatSessionOverlayHost host);
  void onDetach(ChatSessionOverlayHost host);

  /// A switch to [next] starts: the clock it is timed by.
  void onKernelChanging(ChatSessionOverlayHost host, KernelDescriptor next);

  /// Keeps [kernel] while another runs, where switching back to it should
  /// skip its start; true when it was kept (the host disposes it otherwise).
  bool cacheKernel(AgentKernel kernel);

  /// The kernel kept for [descriptor] by [cacheKernel], taken back; null
  /// when none was kept, or when it failed and was let go here.
  AgentKernel? restoreKernel(KernelDescriptor descriptor);

  /// The switch is done: the new kernel is in.
  void onKernelChanged(ChatSessionOverlayHost host);

  /// [turn] as it is sent: what the overlay adds to it, if anything.
  KernelTurn beforeSend(
    ChatSessionOverlayHost host,
    KernelTurn turn,
    OpenEditor? editor,
  );

  /// The conversation is disposed: what the overlay kept goes.
  void onDispose(ChatSessionOverlayHost host);
}
