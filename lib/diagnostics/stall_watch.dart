import 'dart:async';

import 'package:flutter/widgets.dart';

import '../platform/event_log.dart';
import 'frame_watch.dart';

/// Writes to the event log ([appEvent], under `stall`) a UI thread that
/// could not run its own timer on time: how long it was held beyond the
/// period, and what the app had then (the same state line `[slow]` ends
/// with). `[slow]` needs a frame to have been drawn and overrun; a thread
/// held by synchronous work draws no frame at all, and the freezes users
/// reported that evening (2026-10-25 22:00–23:15) left `[slow]` empty.
///
/// The line means: the thread was busy for the gap's length. Not written
/// while the window is hidden or the machine asleep (`hidden` / `paused`):
/// a night's sleep would read as a gap of hours and drown the "an hour,
/// no false line" reading. What a minimized window's thread does is then
/// unseen — the cost written down rather than guessed around.
final class StallWatch {
  StallWatch({
    this.period = const Duration(milliseconds: 250),
    this.threshold = const Duration(milliseconds: 400),
    Duration Function()? elapsed,
    void Function(String message)? write,
  }) : assert(
         threshold > period,
         'a threshold at or below the period writes a line every tick',
       ),
       _read = elapsed,
       _write = write ?? ((message) => appEvent('stall', message));

  /// How often the thread is asked to run a tick: the measuring grain.
  final Duration period;

  /// The least gap written. Above [period]: a timer's own scheduling
  /// jitter is otherwise enough to trigger.
  final Duration threshold;

  /// The monotonic clock read at each tick; [Stopwatch.elapsed] unless a
  /// test injects its own.
  final Duration Function()? _read;

  final void Function(String message) _write;

  final _clock = Stopwatch();

  Timer? _timer;

  /// The clock's reading at the last tick.
  Duration _last = Duration.zero;

  int _written = 0;

  /// A run's most: a chronic stall writes no more than this.
  static const _most = 200;

  void start() {
    if (_timer != null) return;
    _clock.start();
    _last = _now();
    _timer = Timer.periodic(period, _tick);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _clock.stop();
  }

  Duration _now() => _read?.call() ?? _clock.elapsed;

  void _tick(Timer _) {
    final now = _now();
    // The part beyond the period: the thread's own delay, readable as the
    // time it was held. The raw interval would be a period longer, which
    // the 700–1000 ms reading window of an 800 ms block leaves.
    final gap = now - _last - period;
    _last = now;
    if (gap < threshold) return;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      return;
    }
    if (_written >= _most) return;
    _written++;
    try {
      _write('gap ${gap.inMilliseconds} ms; ${frameWatchState()}');
    } catch (_) {
      // A watchdog is no reason to fail: a full disk, a folder gone.
    }
  }
}
