import 'dart:io';

import 'package:baocode/diagnostics/hang_reports.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory logs;

  setUp(() async {
    logs = await Directory.systemTemp.createTemp('baocode-hang-reports');
  });

  tearDown(() => logs.delete(recursive: true));

  void report(String name) => File(p.join(logs.path, 'hangs', name))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('a thread stack');

  void watermark(String text) =>
      File(p.join(logs.path, 'hangs.seen')).writeAsStringSync(text);

  String watermarkText() =>
      File(p.join(logs.path, 'hangs.seen')).readAsStringSync();

  /// What one start wrote: each line's category and message.
  List<(String, String)> check() {
    final lines = <(String, String)>[];
    HangReports(
      logsDir: logs.path,
      write: (category, message) => lines.add((category, message)),
      now: () => DateTime(2026, 10, 26, 3, 52),
    ).check();
    return lines;
  }

  test('a report since the watermark is one line, and the watermark moves', () {
    report('hang-20261025-205400-111.txt');
    report('hang-20261026-010000-222.txt');
    watermark('hang-20261025-205400-111.txt\n2026-10-26T00:00:00\n');
    final lines = check();
    expect(lines, hasLength(1));
    expect(lines.single.$1, 'hang');
    expect(
      lines.single.$2,
      '1 new reports since 2026-10-26T00:00:00（${hangsFolderOf(logs.path)}）',
    );
    expect(
      watermarkText().split('\n').first,
      'hang-20261026-010000-222.txt',
    );
  });

  test('nothing since the watermark writes nothing and touches nothing', () {
    report('hang-20261026-010000-222.txt');
    watermark('hang-20261026-010000-222.txt\n2026-10-26T00:00:00\n');
    final before = watermarkText();
    final lines = check();
    expect(lines, isEmpty);
    expect(watermarkText(), before);
  });

  test('a first start counts every report, not the dumps, since 首次启动', () {
    report('hang-20261025-205400-111.txt');
    report('hang-20261025-210000-222.txt');
    report('hang-20261025-211000-333.txt');
    report('hang-20261025-211000-333.dmp');
    final lines = check();
    expect(lines, hasLength(1));
    expect(lines.single.$2, contains('3 new reports since 首次启动'));
    expect(
      watermarkText().split('\n').first,
      'hang-20261025-211000-333.txt',
    );
  });

  test('a watermark with no time of its own reads the report name', () {
    report('hang-20261025-205400-111.txt');
    report('hang-20261026-010000-222.txt');
    watermark('hang-20261025-205400-111.txt\n');
    final lines = check();
    expect(lines.single.$2, contains('since 2026-10-25T20:54:00'));
  });

  test('no hangs folder writes nothing and leaves no watermark', () {
    final lines = check();
    expect(lines, isEmpty);
    expect(File(p.join(logs.path, 'hangs.seen')).existsSync(), isFalse);
  });
}
