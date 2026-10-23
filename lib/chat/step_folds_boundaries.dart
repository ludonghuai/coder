part of 'step_folds.dart';

// The boundary-union face of the folds (#72): the windows the folds scan in,
// a turn's own boundary merged over a message's where they meet. The scan
// that consumes them stays in step_folds.dart.

/// A window the folds scan: where a turn starts, the message that began it
/// (none when the agent took it up on its own), and how long it worked.
typedef _TurnBoundary = ({int start, int? prompt, Duration? worked});

/// The windows the folds scan in `[from, count]`, ascending: those the
/// messages sent make, and those the turns make, merged where they meet
/// (a turn wins over a message there, a later turn over an earlier).
List<_TurnBoundary> _boundariesOf(
  StepFolds folds,
  int from,
  int count,
  List<TurnMark> turns,
) {
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
      if (folds._items[i] case UserMessageItem(queued: false, :final worked)) {
        boundaries.add((start: i, prompt: i, worked: worked));
      }
      i++;
    }
    // The message at the same place, if any, is the turn's own.
    if (i == mark.start && i < count && folds._items[i] is UserMessageItem) i++;
    boundaries.add((
      start: mark.start,
      prompt: mark.prompt,
      worked: mark.worked,
    ));
  }
  for (; i < count; i++) {
    if (folds._items[i] case UserMessageItem(queued: false, :final worked)) {
      boundaries.add((start: i, prompt: i, worked: worked));
    }
  }
  return boundaries;
}
