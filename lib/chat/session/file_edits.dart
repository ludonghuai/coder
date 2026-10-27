import '../../kernel/agent_kernel.dart';
import '../../kernel/kernel_types.dart';
import '../chat_session_overlay.dart';

// The kernel's revert facets (§9): whether it plans reverts at all, whether
// one can be planned now, and the two calls. `revertTurn` is the host's
// own (it reads the pending edits); these four only ask the kernel.

/// Whether a revert can be planned and done now (§3.3, §3.5).
bool canPlanRevertOf(ChatSessionOverlayHost host) =>
    switch (host.agentKernel) {
      final PlansReverts kernel => kernel.canRevertNow,
      _ => false,
    };

/// Whether the kernel plans reverts at all: its entry never falls back
/// to the host's own undo (the kernel holds the stack, §9).
bool plansRevertsOf(ChatSessionOverlayHost host) =>
    host.agentKernel is PlansReverts;

/// What a revert from [sinceTurn] on would do; nothing is written.
Future<RevertPlan> revertPlanOf(
  ChatSessionOverlayHost host,
  String sinceTurn,
) => switch (host.agentKernel) {
  final PlansReverts kernel => kernel.revertPlan(sinceTurn: sinceTurn),
  _ => Future.error(UnsupportedError('revertPlan')),
};

/// Does what [revertPlan] planned for [sinceTurn], each file on its own.
Future<RevertOutcome> applyRevertOf(
  ChatSessionOverlayHost host,
  String sinceTurn,
) => switch (host.agentKernel) {
  final PlansReverts kernel => kernel.applyRevert(sinceTurn: sinceTurn),
  _ => Future.error(UnsupportedError('applyRevert')),
};
