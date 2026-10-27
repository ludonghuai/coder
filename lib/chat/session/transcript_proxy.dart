import '../../kernel/agent_kernel.dart';
import '../../kernel/kernel_event.dart';
import '../../kernel/transcript.dart';
import '../chat_models.dart';
import '../chat_session_overlay.dart';

// The turn marks the host keeps for the folds (see [MarksTurns]), and the
// one projection of what a kernel can stop. The marks are worked out from
// the transcript the host applies: where each turn started, what it was
// asked, and how long it worked.

/// Whether the kernel can stop what runs beside the conversation: the ones
/// that cannot (thincoder's subagents — F11) show it with no stop button.
bool canStopTasksOf(ChatSessionOverlayHost host) =>
    host.agentKernel is RunsBackgroundTasks;

/// Whether [event] cuts the history at a message sent: the prompt of the
/// turn after it, which that turn does not own. Read before the transcript
/// applies the event.
bool cutsAtMessage(Transcript transcript, Rewound event, int before) {
  final at = switch (event.itemId) {
    final id? => transcript.indexOf(id) ?? event.index,
    null => event.index,
  };
  if (at == null || at < 0 || at >= before) return false;
  return transcript.itemAt(at) is UserMessageItem;
}

/// Keeps the turn [event] tells of in [turns]: every turn from where it
/// starts, and how long it worked, for the transcript it changed. Returns
/// the prepended count now seen, for the next call.
///
/// [before] is the transcript's length before [event] applied, [atMessage]
/// whether it cuts at the message that began the next turn (see
/// [cutsAtMessage]).
int markTurnOf(
  List<TurnMark> turns,
  int prependedSeen,
  KernelEvent event,
  Transcript transcript, {
  required int before,
  required bool atMessage,
}) {
  switch (event) {
    case TurnStarted(:final turnId, :final unprompted):
      final start = transcript.length;
      // Its message, under the turn's id (a queued one may land early).
      final prompt = unprompted ? null : transcript.indexOf(turnId) ?? start;
      turns.add((turnId: turnId, start: start, prompt: prompt, worked: null));
    case TurnEnded(:final turnId, :final interrupted, :final worked):
      // A turn the history no longer holds is not told of any more.
      for (var i = turns.length - 1; i >= 0; i--) {
        final mark = turns[i];
        if (mark.turnId != turnId) continue;
        turns[i] = (
          turnId: turnId,
          start: mark.start,
          prompt: mark.prompt,
          worked: interrupted ? null : worked,
        );
        break;
      }
    case HistoryPrepended():
      final moved = transcript.prepended - prependedSeen;
      prependedSeen = transcript.prepended;
      if (moved == 0) break;
      for (var i = 0; i < turns.length; i++) {
        final mark = turns[i];
        turns[i] = (
          turnId: mark.turnId,
          start: mark.start + moved,
          prompt: mark.prompt == null ? null : mark.prompt! + moved,
          worked: mark.worked,
        );
      }
    case Rewound():
      // What it cut away, or cut into, is no turn any more.
      final cut = transcript.length;
      int? nearest;
      while (turns.isNotEmpty && turns.last.start >= cut) {
        nearest = turns.last.start;
        turns.removeLast();
      }
      // A turn the cut runs into, or took items from, goes too — unless
      // the cut is at the message that began the next turn: that message
      // is the next turn's, and this turn ended before it.
      final crossed = (nearest != null ? nearest > cut : before > cut) &&
          !atMessage;
      if (crossed && turns.isNotEmpty) turns.removeLast();
    default:
  }
  return prependedSeen;
}
