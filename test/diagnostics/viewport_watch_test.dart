import 'dart:io';

import 'package:baocode/diagnostics/viewport_watch.dart';
import 'package:baocode/platform/event_log.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  testWidgets('a ratio change writes one line, with both values and size', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.5;
    tester.view.physicalSize = const Size(3840, 2088);
    final lines = <String>[];
    final watch = ViewportWatch(write: lines.add);
    expect(lines, isEmpty, reason: 'the first look only records');

    tester.view.devicePixelRatio = 2.25;
    watch.didChangeMetrics();
    expect(lines, hasLength(1));
    expect(
      lines.single,
      matches(RegExp(r'^view \d+ dpr 1\.5 -> 2\.25 size \d+x\d+$')),
    );

    // Nothing changed: nothing written.
    watch.didChangeMetrics();
    expect(lines, hasLength(1));

    tester.view.devicePixelRatio = 1.5;
    watch.didChangeMetrics();
    expect(lines, hasLength(2));
    expect(
      lines.last,
      matches(RegExp(r'^view \d+ dpr 2\.25 -> 1\.5 size \d+x\d+$')),
    );
    await tester.pump();
  });

  testWidgets('a change while the window is inactive still writes', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.5;
    final lines = <String>[];
    final watch = ViewportWatch(write: lines.add);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.view.devicePixelRatio = 2.25;
    watch.didChangeMetrics();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(lines, hasLength(1));
    expect(lines.single, contains('dpr 1.5 -> 2.25'));
    await tester.pump();
  });

  testWidgets('a ratio change reaches the log through the binding', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final logs = Directory.systemTemp.createTempSync('baocode-viewport');
    final previous = EventLog.current;
    EventLog.current = EventLog(logs.path);
    addTearDown(() {
      EventLog.current = previous;
      logs.deleteSync(recursive: true);
    });
    tester.view.devicePixelRatio = 1.5;
    tester.view.physicalSize = const Size(3840, 2088);
    // The observer registered as `ViewportWatch.start()` would, so that a
    // real metrics change (the setters tell the binding) is what is read.
    final watch = ViewportWatch();
    WidgetsBinding.instance.addObserver(watch);
    addTearDown(() => WidgetsBinding.instance.removeObserver(watch));
    tester.view.devicePixelRatio = 2.25;
    tester.platformDispatcher.onMetricsChanged?.call();
    tester.view.devicePixelRatio = 1.5;
    tester.platformDispatcher.onMetricsChanged?.call();
    await tester.pump();
    final written = [
      for (final line
          in File(p.join(logs.path, 'events.log')).readAsLinesSync())
        if (line.contains('[viewport]')) line,
    ];
    expect(written, hasLength(2));
    expect(written[0], contains('dpr 1.5 -> 2.25'));
    expect(written[1], contains('dpr 2.25 -> 1.5'));
  });
}
