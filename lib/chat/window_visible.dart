import 'package:flutter/widgets.dart';

/// Whether the app's window is visible: visible while the lifecycle is
/// `resumed`, or before there is a state yet; hidden otherwise (`inactive`,
/// `hidden`, `paused`, `detached`).
///
/// The one place that watches the lifecycle for it. A view that must not
/// rebuild — and so must not draw a frame — while the window is out of sight
/// subscribes to [changed] rather than adding an observer of its own, so one
/// observer serves them all.
///
/// Hiding is read as the lifecycle leaving `resumed` — not as the window being
/// covered: `inactive` is the state the requirement names, and the one another
/// window in front puts it in.
abstract final class WindowVisible {
  static bool _started = false;
  static bool _visible = true;
  static final _Changed _changed = _Changed();

  /// Watches the lifecycle from now on — once, and for the app's whole run:
  /// idempotent, so the watch outlives whichever view asked for it.
  static void start() {
    if (_started) return;
    _started = true;
    _visible = _of(WidgetsBinding.instance.lifecycleState);
    WidgetsBinding.instance.addObserver(const _Lifecycle());
  }

  /// Visible now: resumed, or no state yet.
  static bool get isVisible => _visible;

  /// Notified when [isVisible] changes.
  static Listenable get changed => _changed;

  static bool _of(AppLifecycleState? state) => switch (state) {
    null || AppLifecycleState.resumed => true,
    _ => false,
  };
}

/// The one observer: tells [WindowVisible] when the state became another
/// visibility. Nothing else listens to the lifecycle for this.
final class _Lifecycle with WidgetsBindingObserver {
  const _Lifecycle();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = WindowVisible._of(state);
    if (visible == WindowVisible._visible) return;
    WindowVisible._visible = visible;
    WindowVisible._changed.notify();
  }
}

final class _Changed extends ChangeNotifier {
  void notify() => notifyListeners();
}
