import 'package:baocode/diagnostics/stall_watch.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ten ticks with nothing in the way write nothing', (tester) async {
    var now = Duration.zero;
    final lines = <String>[];
    final watch = StallWatch(elapsed: () => now, write: lines.add)..start();
    for (var tick = 0; tick < 10; tick++) {
      now += const Duration(milliseconds: 250);
      await tester.pump(const Duration(milliseconds: 250));
    }
    watch.stop();
    expect(lines, isEmpty);
  });

  testWidgets('an 800 ms block writes one line, gap 800 ms', (tester) async {
    var now = Duration.zero;
    final lines = <String>[];
    final watch = StallWatch(elapsed: () => now, write: lines.add)..start();
    now += const Duration(milliseconds: 250);
    await tester.pump(const Duration(milliseconds: 250));
    // The thread held for 800 ms: the next tick arrives 1050 ms late, and
    // what it writes is the part beyond the period.
    now += const Duration(milliseconds: 1050);
    await tester.pump(const Duration(milliseconds: 250));
    watch.stop();
    expect(lines, hasLength(1));
    expect(lines.single, contains('gap 800 ms;'));
  });

  testWidgets('the threshold is 400 ms: 400 writes, 399 does not', (
    tester,
  ) async {
    var now = Duration.zero;
    final lines = <String>[];
    final watch = StallWatch(elapsed: () => now, write: lines.add)..start();
    now += const Duration(milliseconds: 250);
    await tester.pump(const Duration(milliseconds: 250));
    now += const Duration(milliseconds: 649);
    await tester.pump(const Duration(milliseconds: 250));
    expect(lines, isEmpty, reason: 'gap 399 ms');
    now += const Duration(milliseconds: 650);
    await tester.pump(const Duration(milliseconds: 250));
    watch.stop();
    expect(lines, hasLength(1));
    expect(lines.single, contains('gap 400 ms;'));
  });

  testWidgets('a block while the window is inactive still writes', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    var now = Duration.zero;
    final lines = <String>[];
    final watch = StallWatch(elapsed: () => now, write: lines.add)..start();
    now += const Duration(milliseconds: 250);
    await tester.pump(const Duration(milliseconds: 250));
    now += const Duration(milliseconds: 1050);
    await tester.pump(const Duration(milliseconds: 250));
    watch.stop();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(lines, hasLength(1));
    expect(lines.single, allOf(contains('gap 800 ms;'), contains('inactive')));
  });

  testWidgets('hidden or paused writes nothing', (tester) async {
    var now = Duration.zero;
    final lines = <String>[];
    final watch = StallWatch(elapsed: () => now, write: lines.add)..start();
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      now += const Duration(milliseconds: 1050);
      await tester.pump(const Duration(milliseconds: 250));
    }
    watch.stop();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(lines, isEmpty);
  });
}
