import 'chat_models.dart';

/// What a fold holds.
enum StepFoldKind {
  /// A run of quick steps: thoughts, reads, searches, commands.
  steps,

  /// A finished turn's work, all before its answer.
  work,
}

/// Items [start] to [end] (exclusive) of a history, shown as one line that
/// opens to them.
class StepFold {
  const StepFold(this.kind, this.start, this.end, {this.worked});

  final StepFoldKind kind;
  final int start;
  final int end;

  /// How long the turn worked, for [StepFoldKind.work].
  final Duration? worked;

  /// The same for as long as the fold stands: a run of steps grows at its
  /// end, never its start.
  (StepFoldKind, int) get key => (kind, start);
}

/// What one row of the history shows: the line of each fold it begins,
/// and its own item unless a closed fold hides it.
typedef StepRow = ({StepFold? work, StepFold? steps, bool item});

/// A window the folds scan: where a turn starts, the message that began it
/// (none when the agent took it up on its own), and how long it worked.
typedef _TurnBoundary = ({int start, int? prompt, Duration? worked});

/// How a history folds: each run of at least two quick steps into one line
/// ("Read 3 files, ran 2 commands"), and each finished turn's work into
/// one line before its answer ("Worked for 4m 32s"). Edits, subagents and
/// the agent's words stand apart: they break a run. A plan's card is never
/// folded.
///
/// Thoughts one after another, nothing between them, show as one (see
/// [mergeThoughts]): its row is the first's, the others show nothing.
class StepFolds {
  StepFolds._(
    this._steps,
    this._work,
    this._liveEnd,
    this._turnEnds,
    this._items,
    this._thoughtRuns,
    this._thoughtOf,
  );

  /// Nothing folded.
  ///
  /// Shared: it is where a view starts, before its first fold. Never grown
  /// in place — [extend] would grow every view holding it.
  static final none = StepFolds._(
    <StepFold?>[],
    <StepFold?>[],
    null,
    <int, int>{},
    <ChatItem>[],
    <int, int>{},
    <int?>[],
  );

  /// Folds the [count] items given by [itemAt]. While [live], the last turn
  /// is under way: it does not fold yet. [turns], when kept, say where the
  /// turns start (see [TurnMark]): each turn folds its own work only.
  factory StepFolds.of(
    int count,
    ChatItem Function(int index) itemAt, {
    required bool live,
    List<TurnMark> turns = const [],
  }) {
    final folds = StepFolds._(
      List<StepFold?>.filled(count, null, growable: true),
      List<StepFold?>.filled(count, null, growable: true),
      null,
      <int, int>{},
      [for (var i = 0; i < count; i++) itemAt(i)],
      <int, int>{},
      List<int?>.filled(count, null, growable: true),
    );
    return folds.._rescan(0, live: live, turns: turns);
  }

  final List<StepFold?> _steps;
  final List<StepFold?> _work;
  final List<ChatItem> _items;

  /// Where each run of thoughts shown as one ends, by where it starts.
  final Map<int, int> _thoughtRuns;

  /// For each thought shown in an earlier one's row, where that run starts.
  final List<int?> _thoughtOf;

  /// How many items it holds.
  int get count => _items.length;

  /// Where item [index] shows: the start of the run of thoughts it is one
  /// with, else itself.
  int rowOf(int index) => index >= 0 && index < _thoughtOf.length
      ? _thoughtOf[index] ?? index
      : index;

  /// Folds [count] items, [itemAt] giving them all, on from [this] as it
  /// was for the items before them: the last turn is read again, the
  /// history before stands as it was. Grows it in place, and returns it.
  StepFolds extend(
    int count,
    ChatItem Function(int index) itemAt, {
    required bool live,
    List<TurnMark> turns = const [],
  }) {
    assert(count >= _items.length, 'extend grows; it never cuts');
    if (count > _items.length) {
      _items.addAll([for (var i = _items.length; i < count; i++) itemAt(i)]);
      _steps.length = count;
      _work.length = count;
      _thoughtOf.length = count;
    }
    final from = _tailFrom(itemAt, count, turns);
    // A turn that was under way and has just ended (a prompt came after
    // it) folds now: it too is scanned again.
    final liveFrom = _liveStart;
    final start = liveFrom != null && liveFrom < from ? liveFrom : from;
    // What a turn ending changes may sit in place: its prompt's time, its
    // status row's place taken by the answer. Read again, not kept.
    for (var i = start; i < count; i++) {
      _items[i] = itemAt(i);
    }
    _steps.fillRange(start, count, null);
    _work.fillRange(start, count, null);
    _thoughtOf.fillRange(start, count, null);
    _thoughtRuns.removeWhere((run, _) => run >= start);
    _merged.removeWhere((run, _) => run >= start);
    // Only what a window read again ended at before: a turn's close moves
    // as its answer grows, and its start may sit before the mark (a queued
    // message taken up first). Nothing read again keeps every entry.
    if (start < count) _turnEnds.removeWhere((last, _) => last >= start);
    _rescan(start, live: live, turns: turns);
    return this;
  }

  /// Item [index] from now on is [item] (it grew): what the run of thoughts
  /// it is in shows is made again, with its new words.
  void refreshTail(int index, ChatItem item) {
    if (index < 0 || index >= _items.length) return;
    _items[index] = item;
    _merged.remove(rowOf(index));
  }

  /// The first item the last turn reaches back to: where it starts when the
  /// feed keeps its turns, else its prompt, or the start of a run of
  /// thoughts or steps the history ends in.
  int _tailFrom(
    ChatItem Function(int index) itemAt,
    int count,
    List<TurnMark> turns,
  ) {
    if (turns.isNotEmpty) {
      final start = turns.last.start;
      // A mark out of the history is no boundary: the messages tell.
      if (start >= 0 && start <= count) return start;
    }
    var prompt = 0;
    for (var i = count - 1; i >= 0; i--) {
      if (itemAt(i) case UserMessageItem(queued: false)) {
        prompt = i;
        break;
      }
    }
    var thoughts = count;
    while (thoughts > 0 && itemAt(thoughts - 1) is ThinkingItem) {
      thoughts--;
    }
    var steps = count;
    while (steps > 0 && isQuickStep(itemAt(steps - 1))) {
      steps--;
    }
    final first = prompt < thoughts ? prompt : thoughts;
    return first < steps ? first : steps;
  }

  /// Scans the items from [from] on as [of] scans them all: the runs of
  /// thoughts and steps, and the turns' work.
  void _rescan(int from, {required bool live, required List<TurnMark> turns}) {
    final count = _items.length;
    for (var start = from; start < count;) {
      if (_items[start] is! ThinkingItem) {
        start++;
        continue;
      }
      var end = start + 1;
      while (end < count && _items[end] is ThinkingItem) {
        end++;
      }
      if (end - start >= 2) {
        _thoughtRuns[start] = end;
        _thoughtOf.fillRange(start + 1, end, start);
      }
      start = end;
    }

    for (var start = from; start < count;) {
      if (!isQuickStep(_items[start])) {
        start++;
        continue;
      }
      var end = start;
      var actions = 0;
      while (end < count && isQuickStep(_items[end])) {
        if (_items[end] is! ThinkingItem) actions++;
        end++;
      }
      if (actions >= 2) {
        final fold = StepFold(StepFoldKind.steps, start, end);
        _steps.fillRange(start, end, fold);
      }
      start = end;
    }

    final windows = _boundaries(from, count, turns);
    for (var t = 0; t < windows.length; t++) {
      // The turn under way, and any queued after it, are not done.
      if (live && t == windows.length - 1) break;
      final window = windows[t];
      final start = window.start;
      final worked = window.worked;
      if (worked == null) continue;
      var last = t + 1 < windows.length ? windows[t + 1].start - 1 : count - 1;
      while (last > start && _items[last] is UserMessageItem) {
        last--;
      }
      // Ending in thoughts, it ends at the row they show in; its footer, if
      // it has a message to take it, there.
      final footer = window.prompt ?? start;
      if (last > start) _turnEnds[_thoughtOf[last] ?? last] = footer;
      if (last <= start || _items[last] is! AssistantTextItem) continue;
      // The answer: the words after its last step, thoughts among them.
      var answer = last;
      for (var i = last; i > start; i--) {
        if (_items[i] is AssistantTextItem) {
          answer = i;
        } else if (_items[i] is! ThinkingItem) {
          break;
        }
      }
      // A plan's card stands out of it: the work folded is what came
      // after the last (carrying it out, once approved); the planning
      // before stays as it is.
      var fold = start;
      while (fold < answer && _items[fold] is UserMessageItem) {
        fold++;
      }
      for (var i = answer - 1; i >= fold; i--) {
        if (_items[i] is PlanItem) {
          fold = i + 1;
          break;
        }
      }
      final shown = _items
          .sublist(fold, answer)
          .where((item) => item is! ThinkingItem)
          .length;
      if (shown < 2) continue;
      final work = StepFold(StepFoldKind.work, fold, answer, worked: worked);
      _work.fillRange(fold, answer, work);
    }

    var liveEnd = count;
    if (count > 0 && _items[count - 1] is LiveStatusItem) liveEnd--;
    _liveEnd = live ? liveEnd : null;
    _liveStart = live && windows.isNotEmpty ? windows.last.start : null;
  }

  /// The windows the folds scan in `[from, count]`, ascending: those the
  /// messages sent make, and those the turns make, merged where they meet
  /// (a turn wins over a message there, a later turn over an earlier).
  List<_TurnBoundary> _boundaries(int from, int count, List<TurnMark> turns) {
    final marks = <TurnMark>[];
    var after = count;
    for (var i = turns.length - 1; i >= 0; i--) {
      final mark = turns[i];
      if (mark.start < from) break;
      // A mark out of the history, or out of order, is no boundary. One at
      // its end is: the turn under way has no items yet.
      if (mark.start < 0 || mark.start > count || mark.start > after) continue;
      // The same place as the one after it: the later turn is the one.
      if (marks.isNotEmpty && marks.last.start == mark.start) continue;
      marks.add(mark);
      after = mark.start;
    }
    final boundaries = <_TurnBoundary>[];
    var i = from;
    for (final mark in marks.reversed) {
      while (i < mark.start) {
        if (_items[i] case UserMessageItem(queued: false, :final worked)) {
          boundaries.add((start: i, prompt: i, worked: worked));
        }
        i++;
      }
      // The message at the same place, if any, is the turn's own.
      if (i == mark.start && i < count && _items[i] is UserMessageItem) i++;
      boundaries.add((
        start: mark.start,
        prompt: mark.prompt,
        worked: mark.worked,
      ));
    }
    for (; i < count; i++) {
      if (_items[i] case UserMessageItem(queued: false, :final worked)) {
        boundaries.add((start: i, prompt: i, worked: worked));
      }
    }
    return boundaries;
  }

  /// The runs of thoughts as one, as asked for.
  final Map<int, ThinkingItem> _merged = {};

  /// What row [index] shows of [item], the item there: the thoughts of the
  /// run it starts as one, else [item] itself.
  ChatItem shownAt(int index, ChatItem item) {
    final end = _thoughtRuns[index];
    if (end == null) return item;
    return _merged[index] ??= mergeThoughts([
      for (var i = index; i < end; i++) _items[i] as ThinkingItem,
    ]);
  }

  /// Whether item [index] is a thought shown in an earlier one's row.
  bool _mergedAway(int index) =>
      index < _thoughtOf.length && _thoughtOf[index] != null;

  /// The last item row [index] shows: of a run of thoughts it starts, the
  /// run's last.
  int _rowEnd(int index) => switch (_thoughtRuns[index]) {
    final end? => end - 1,
    null => index,
  };

  /// For the last item of each finished turn timed, its prompt's index.
  final Map<int, int> _turnEnds;

  /// The prompt of the finished turn item [index] ends, if it ends one.
  int? turnEndingAt(int index) => _turnEnds[index];

  /// Where the live turn's items end (before its status row); null when
  /// no turn is under way.
  int? _liveEnd;

  /// The start of the window the turn under way is in, while one is: what to
  /// scan again when it ends.
  int? _liveStart;

  /// The run of steps item [index] is in, if folded.
  StepFold? stepsAt(int index) => index < _steps.length ? _steps[index] : null;

  /// The turn's work item [index] is in, if folded.
  StepFold? workAt(int index) => index < _work.length ? _work[index] : null;

  /// What row [index] (holding [item]) shows, with the folds [isOpen]
  /// says are open.
  StepRow rowAt(int index, ChatItem item, bool Function(StepFold) isOpen) {
    final work = workAt(index);
    final workLine = work?.start == index ? work : null;
    if (work != null && !isOpen(work)) {
      // Pictures made stand out of it, as the answer would show them.
      return (work: workLine, steps: null, item: standsOutOfWork(item));
    }
    final own = !_mergedAway(index);
    final steps = stepsAt(index);
    if (steps == null) return (work: workLine, steps: null, item: own);
    final stepsLine = steps.start == index ? steps : null;
    // Closed, a run still under way shows its last step as it goes.
    final shown =
        own &&
        (isOpen(steps) ||
            (_rowEnd(index) == steps.end - 1 &&
                steps.end == _liveEnd &&
                isUnderWay(shownAt(index, item))));
    return (work: workLine, steps: stepsLine, item: shown);
  }
}

/// Whether [item] is a quick step, folded with others like it: a thought,
/// or a tool call that only looks around or runs something. Not an edit
/// (shown on its own), a subagent, a message to another agent, a goal
/// proposed, pictures made, a refused call, nor a command left running in
/// the background.
bool isQuickStep(ChatItem item) => switch (item) {
  ThinkingItem() => true,
  ToolCallItem(:final kind, :final status) =>
    status != ToolStatus.denied &&
        switch (kind) {
          ToolKind.edit ||
          ToolKind.agent ||
          ToolKind.message ||
          ToolKind.goal ||
          ToolKind.image => false,
          _ => true,
        },
  TerminalItem(:final background) => !background,
  _ => false,
};

/// Whether [item] shows though its turn's work is folded: pictures an
/// image model made, which are what the user asked for.
bool standsOutOfWork(ChatItem item) => switch (item) {
  ToolCallItem(kind: ToolKind.image, :final status, :final images) =>
    status == ToolStatus.succeeded && images.isNotEmpty,
  _ => false,
};

/// Whether [item] is still going: a thought streaming, a call or command
/// running.
bool isUnderWay(ChatItem item) => switch (item) {
  ThinkingItem(:final streaming) => streaming,
  ToolCallItem(:final status) => status == ToolStatus.running,
  TerminalItem(:final status, :final background) =>
    status == CommandStatus.running && !background,
  _ => false,
};

/// [thoughts], one after another, as one: their words a blank line apart,
/// their times added up. A model may think in many parts in one reply
/// (each kept apart, to be sent back as it was), most without words: one
/// thought to the user, as long as they all took. Still streaming while
/// one of them is, its time counting on from where the others' ends.
ThinkingItem mergeThoughts(List<ThinkingItem> thoughts) {
  final took = thoughts.fold(0, (sum, thought) => sum + (thought.seconds ?? 0));
  final streaming = thoughts.where((thought) => thought.streaming).lastOrNull;
  return ThinkingItem(
    text: [
      for (final thought in thoughts)
        if (thought.text.trim() case final text when text.isNotEmpty) text,
    ].join('\n\n'),
    tokens: thoughts.fold(0, (sum, thought) => sum + thought.tokens),
    seconds: streaming == null ? took : null,
    startedAt: streaming?.startedAt?.subtract(Duration(seconds: took)),
  );
}

/// What a quick step did, as a run's line counts it.
enum StepAction { read, search, list, fetch, run, browse, use }

/// The steps of a run, counted by what they did.
class StepTally {
  StepTally(Iterable<ChatItem> items) {
    for (final item in items) {
      final action = switch (item) {
        ToolCallItem(:final kind) => switch (kind) {
          ToolKind.read => StepAction.read,
          ToolKind.grep || ToolKind.search => StepAction.search,
          ToolKind.listDir => StepAction.list,
          ToolKind.web => StepAction.fetch,
          ToolKind.command => StepAction.run,
          ToolKind.browser => StepAction.browse,
          _ => StepAction.use,
        },
        TerminalItem(:final command) => commandAction(command),
        _ => null,
      };
      if (action != null) counts[action] = (counts[action] ?? 0) + 1;
      if (item case ThinkingItem(:final seconds?)) thought += seconds;
    }
  }

  /// By action, in the order the line says them.
  final Map<StepAction, int> counts = {};

  /// Seconds spent thinking, all thoughts together.
  int thought = 0;
}

/// What a shell command does, as far as its words tell: one that only
/// prints files reads, one that looks for something searches. Anything
/// else (chained, redirected, editing in place) runs.
StepAction commandAction(String command) {
  var line = command.trim();
  // Where it runs says nothing of what it does.
  line = line.replaceFirst(RegExp(r'^cd\s+[^;&|]+&&\s*'), '');
  // Nor does where its errors go.
  line = line.replaceAll(RegExp(r'\s2>(&1|/dev/null)'), '');
  if (line.contains(RegExp(r'[\n;>]|&&|\|\|'))) return StepAction.run;
  final words = line.split('|').first.trim().split(RegExp(r'\s+'));
  return switch (words.first) {
    'cat' || 'head' || 'tail' || 'nl' || 'bat' || 'less' => StepAction.read,
    'sed' when words.contains('-n') && !words.any((w) => w.startsWith('-i')) =>
      StepAction.read,
    'grep' || 'egrep' || 'rg' || 'ag' || 'find' || 'fd' => StepAction.search,
    'ls' || 'tree' => StepAction.list,
    _ => StepAction.run,
  };
}
