import 'dart:ui' show FlutterView;

import 'package:flutter/widgets.dart';

import '../platform/event_log.dart';

/// Writes to the event log ([appEvent], under `viewport`) each change of a
/// view's device pixel ratio: the ratio before and after, and the size it
/// draws at. This machine has displays at 1.5 beside 2.25, and `events.log`
/// told nothing: view 0 was always `@1.5`, never a ratio change — so a
/// window that "grows over the whole screen and shrinks back" left no trace.
///
/// Only a ratio change writes a line: a window merely resized is
/// [AppEventWatch]'s to tell (`views`), and a line for every resize would
/// bury both.
class ViewportWatch with WidgetsBindingObserver {
  /// Starts from the views the engine has now: a line only for a change
  /// after this.
  ViewportWatch({void Function(String message)? write})
    : _write = write ?? ((message) => appEvent('viewport', message)) {
    _seen = _metricsOf(WidgetsBinding.instance.platformDispatcher.views);
  }

  static ViewportWatch? _current;

  /// Starts watching, once.
  static void start() {
    if (_current != null) return;
    final watch = _current = ViewportWatch();
    WidgetsBinding.instance.addObserver(watch);
  }

  final void Function(String message) _write;

  /// Each view's metrics as last seen: the one source is the engine's
  /// `views`, not `View.of` or `MediaQuery` (both derive from it).
  Map<int, _ViewMetrics> _seen = {};

  @override
  void didChangeMetrics() {
    final views = _metricsOf(WidgetsBinding.instance.platformDispatcher.views);
    for (final MapEntry(key: id, value: now) in views.entries) {
      final before = _seen[id];
      // A view seen for the first time is recorded, not announced: its
      // coming is `views`' line.
      if (before != null && before.ratio != now.ratio) {
        _write('view $id dpr ${before.ratio} -> ${now.ratio} size ${now.size}');
      }
    }
    _seen = views;
  }

  static Map<int, _ViewMetrics> _metricsOf(Iterable<FlutterView> views) => {
    for (final view in views) view.viewId: _ViewMetrics.of(view),
  };
}

/// What a view says about its ratio and the size it draws at, logical.
final class _ViewMetrics {
  const _ViewMetrics(this.ratio, this.size);

  factory _ViewMetrics.of(FlutterView view) {
    final ratio = view.devicePixelRatio;
    final size = view.physicalSize;
    return _ViewMetrics(
      ratio,
      '${(size.width / ratio).round()}x${(size.height / ratio).round()}',
    );
  }

  final double ratio;

  /// `<logical width>x<logical height>`.
  final String size;
}
