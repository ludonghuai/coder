part of '../chat_session.dart';

// The conversation as the UI reads it: what streams, what waits on the
// user, the status row, tasks run beside it, and the goal. Everything is
// projected from the transcript; the fields it caches stay in the class.

bool _isStreamingOf(ChatSession owner) => owner._transcript.activeTurn != null;

bool _isUnpromptedOf(ChatSession owner) =>
    owner._transcript.activeTurnUnprompted;

/// Whether the composer may send now.
bool _canSendOf(ChatSession owner) => !owner.isStreaming || owner.canQueue;

InteractionRequest? _pendingInteractionOf(ChatSession owner) =>
    owner._transcript.pendingInteraction;

/// The plan put to the user for them to start (see [startPlan]): the
/// last round's, until a message is sent after it.
PlanItem? _awaitingPlanOf(ChatSession owner) {
  if (owner._kernel is! StartsPlans) return null;
  // Looked up once a change: asked on each, as the turn streams.
  final key = (owner._transcript, owner._transcript.version, owner._transcript.length);
  if (owner._awaitingPlan case (final at, final plan) when at == key) return plan;
  PlanItem? found;
  for (var i = owner._transcript.length - 1; i >= 0; i--) {
    final item = owner._transcript.itemAt(i);
    if (item is UserMessageItem) break;
    if (item is PlanItem) {
      if (item.status == PlanStatus.awaiting) found = item;
      break;
    }
  }
  owner._awaitingPlan = (key, found);
  return found;
}

/// Whether the plan awaiting can be started now: not while the turn
/// that put it is still under way.
bool _canStartPlanOf(ChatSession owner) =>
    owner.awaitingPlan != null && !owner.isStreaming;

/// Starts the plan awaiting: out of planning, into building with the
/// approvals and the model picked, [text] sent to say so.
void _startPlanOf(ChatSession owner, String text) {
  if (!owner.canStartPlan) return;
  (owner._kernel as StartsPlans).startBuilding();
  owner.send(ComposerMessage(text: text));
}

/// Sequence of the last turn to end, to tell whether it was seen.
int _lastTurnEndSeqOf(ChatSession owner) => owner._transcript.lastTurnEndSeq;

/// What the agent said last, if it said anything after the last message
/// sent (this run, or in the history read).
String? _lastReplyOf(ChatSession owner) {
  for (var i = owner._transcript.length - 1; i >= 0; i--) {
    switch (owner._transcript.itemAt(i)) {
      case UserMessageItem():
        return null;
      case AssistantTextItem(:final text) when text.trim().isNotEmpty:
        return text;
      default:
    }
  }
  return null;
}

/// Whether the last turn to end was stopped rather than done.
bool _lastTurnInterruptedOf(ChatSession owner) =>
    owner._transcript.lastTurnInterrupted;

/// Whether the last turn to end was one the agent took up on its own,
/// e.g. about a background subagent's report.
bool _lastTurnUnpromptedOf(ChatSession owner) =>
    owner._transcript.lastTurnUnprompted;

/// The history, and a status row at its end while a turn runs: the agent
/// is live. Hidden (but there, to come and go smoothly) where something
/// else says so, or it would only flash.
int _itemCountOf(ChatSession owner) =>
    owner._transcript.length +
    owner._notices.length +
    (owner.isStreaming ? 1 : 0);

ChatItem _itemAtOf(ChatSession owner, int index) {
  if (index < owner._transcript.length) return owner._transcript.itemAt(index);
  final notice = index - owner._transcript.length;
  if (notice < owner._notices.length) return owner._notices[notice];
  // Waiting on its model unless its kernel says otherwise.
  final output = owner._transcript.output;
  return switch (owner._transcript.activity?.kind) {
    KernelActivityKind.compacting => LiveStatusItem(
      'Compacting conversation',
      visible: owner._statusVisible,
      output: output,
      startedAt: owner._transcript.turnStartedAt,
    ),
    _ => LiveStatusItem(
      'Planning next move',
      whimsical: true,
      visible: owner._statusVisible,
      output: output,
      startedAt: owner._transcript.turnStartedAt,
      cue: MusingCue.after(owner._last),
    ),
  };
}

/// Not while the agent waits on the user; nor after a thought under way,
/// which says so itself; nor after its text, unless all has been quiet
/// for [quietAfterText].
bool _statusVisibleOf(ChatSession owner) {
  if (owner.pendingInteraction != null) return false;
  return switch (owner._last) {
    ThinkingItem() =>
      !owner._transcript.isStreamingAt(owner._transcript.length - 1),
    AssistantTextItem() => owner._quiet,
    _ => true,
  };
}

/// Tasks running beside the conversation, gone once they end (their
/// outcome stays on their step); null when none runs.
List<KernelTask>? _tasksOf(ChatSession owner) {
  final running = owner._cached(
    #tasks,
    () => [
      for (final task in owner._transcript.tasks)
        if (task.background && task.status == CommandStatus.running) task,
    ],
  );
  return running.isEmpty ? null : running;
}

/// Background commands, including completed ones for their output tabs.
List<KernelTask> _terminalTasksOf(ChatSession owner) => owner._cached(
  #terminalTasks,
  () => [
    for (final task in owner._transcript.tasks)
      if (task.background && task.kind == KernelTaskKind.command) task,
  ],
);

void _stopTaskOf(ChatSession owner, KernelTask task) {
  if (owner._kernel case final RunsBackgroundTasks kernel) kernel.stopTask(task.id);
}

/// Whether the kernel can stop what runs beside the conversation: the
/// ones that cannot (thincoder's subagents — F11) show it with no stop
/// button.
bool _canStopTasksOf(ChatSession owner) =>
    owner._kernel is RunsBackgroundTasks;

/// Moves what the item at [index] runs (a command, a subagent) to the
/// background, so the turn goes on; null unless the kernel reports it
/// running in the foreground.
VoidCallback? _moveToBackgroundAtOf(ChatSession owner, int index) =>
    index < owner._transcript.length
    ? owner.moveToBackgroundOf(owner._transcript.idAt(index))
    : null;

/// As [moveToBackgroundAt], for what the tool call [id] runs, wherever it
/// shows (e.g. in a subagent).
VoidCallback? _moveToBackgroundOfOf(ChatSession owner, String? id) {
  if ((owner._kernel, owner._runningTask(id)) case (
    final RunsBackgroundTasks kernel,
    KernelTask(background: false),
  )) {
    return () => kernel.moveToBackground(id!);
  }
  return null;
}

/// The command the tool call [id] ran, in the conversation itself: what a
/// background command's task does.
String? _commandOfOf(ChatSession owner, String? id) {
  final index = id == null ? null : owner._transcript.indexOf(id);
  if (index == null) return null;
  return switch (owner._transcript.itemAt(index)) {
    TerminalItem(:final command) when command.isNotEmpty => command,
    _ => null,
  };
}

/// Stops the subagent at [index]; null unless it runs as a task.
VoidCallback? _stopAtOf(ChatSession owner, int index) =>
    index < owner._transcript.length
    ? owner.stopOf(owner._transcript.idAt(index))
    : null;

/// Stops what the tool call [id] runs, e.g. a subagent; null unless it
/// runs as a task the kernel can stop.
VoidCallback? _stopOfOf(ChatSession owner, String? id) =>
    switch (owner._runningTask(id)) {
      final task? when owner._kernel is RunsBackgroundTasks =>
        () => owner.stopTask(task),
      _ => null,
    };

List<TodoEntry> _todosOf(ChatSession owner) => owner._transcript.todos;

/// The goal the agent works toward (`/goal`), if any: just met, it is
/// still here, met, until [dismissGoal].
KernelGoal? _goalOf(ChatSession owner) => switch (owner._transcript.goal) {
  final goal? when !identical(goal, owner._dismissedGoal) => goal,
  _ => null,
};

/// Hides the [goal] there is; a new one shows again.
void _dismissGoalOf(ChatSession owner) {
  if (owner.goal == null) return;
  owner._dismissedGoal = owner._transcript.goal;
  owner._notify();
}

/// Sets [condition] as the goal, in place of any there is, and sets the
/// agent to work toward it. At once: Claude Code takes up `/goal` only
/// between turns.
void _setGoalOf(ChatSession owner, String condition) =>
    owner.send(ComposerMessage(text: '/goal ${condition.trim()}'), now: true);

/// Clears the goal there is, at once.
void _clearGoalOf(ChatSession owner) =>
    owner.send(const ComposerMessage(text: '/goal clear'), now: true);
