import 'dart:io';

import 'package:path/path.dart' as p;

import '../platform/event_log.dart';

/// The folder the window's hang watchdog writes its reports to
/// (`windows/runner/hang_watchdog.h`): [logsDir]'s `hangs`. One definition —
/// the diagnostics upload lists the same folder.
String hangsFolderOf(String logsDir) => p.join(logsDir, 'hangs');

/// Writes to the event log ([appEvent], under `hang`) the hang reports that
/// appeared since the app last started: how many, since when, and where
/// they are. The watchdog kept writing 9 reports with full thread stacks
/// (2026-10-25 20:54–23:44); `events.log` and `errors.log` never said one
/// existed, so nobody knew where to look while three hangs were reported.
///
/// One report is one `hang-*.txt`; its same-named `.dmp` is that report's
/// dump and is not counted again. Nothing new writes nothing at all — a
/// line that is always there teaches nobody to read it.
final class HangReports {
  HangReports({
    required this.logsDir,
    void Function(String category, String message)? write,
    DateTime Function()? now,
  }) : _write = write ?? appEvent,
       _now = now ?? DateTime.now;

  final String logsDir;

  final void Function(String category, String message) _write;

  final DateTime Function() _now;

  String get _folder => hangsFolderOf(logsDir);

  /// The last report seen, then when it was seen (the "since" of the next
  /// line): a start's time is what the next start counts from.
  File get _watermark => File(p.join(logsDir, 'hangs.seen'));

  /// Writes the new reports' line and returns 1, or returns 0 where there
  /// was nothing to report (none new, or a folder that could not be read —
  /// which is said out loud in a line of its own). Reports that appeared
  /// while the app was not running are all new to it.
  int check() {
    final folder = Directory(_folder);
    if (!folder.existsSync()) return 0;
    final List<FileSystemEntity> entries;
    try {
      entries = folder.listSync(followLinks: false);
    } on FileSystemException catch (error) {
      // There but unreadable: said out loud. Coming out as "no reports"
      // would read as the one answer this line exists to deny — that
      // nothing is there.
      _write('hang', 'cannot read $_folder: ${error.message}');
      return 0;
    }
    final reports = [
      for (final entity in entries)
        if (entity is File && _isReport(p.basename(entity.path)))
          p.basename(entity.path),
    ]..sort();
    if (reports.isEmpty) return 0;
    final seen = _readWatermark();
    final fresh = [
      for (final name in reports)
        if (seen == null || name.compareTo(seen.name) > 0) name,
    ];
    if (fresh.isEmpty) return 0;
    _write(
      'hang',
      '${fresh.length} new reports since '
          '${seen == null ? '首次启动' : seen.since}（$_folder）',
    );
    _remember(fresh.last);
    return 1;
  }

  /// `hang-YYYYMMDD-HHMMSS-pid.txt`, the watchdog's own naming.
  static bool _isReport(String name) =>
      name.startsWith('hang-') && name.endsWith('.txt');

  ({String name, String since})? _readWatermark() {
    final String text;
    try {
      text = _watermark.readAsStringSync();
    } on FileSystemException {
      // No watermark: everything there is new, as on the first start.
      return null;
    } on FormatException {
      // A watermark cut short by a crash: read as none — these reports are
      // reported again rather than lost.
      return null;
    }
    final lines = text.split('\n');
    final name = lines.first.trim();
    if (name.isEmpty) return null;
    final seenAt = lines.length > 1 ? lines[1].trim() : '';
    return (name: name, since: seenAt.isNotEmpty ? seenAt : _timeOf(name));
  }

  void _remember(String name) {
    try {
      _watermark.writeAsStringSync('$name\n${_stamp(_now())}\n');
    } on FileSystemException {
      // The next start reports these again: twice is better than lost.
    }
  }

  /// The time in a report's name, for a watermark that had none of its
  /// own.
  static String _timeOf(String report) {
    final time = RegExp(r'^hang-(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})-')
        .firstMatch(report);
    if (time == null) return report;
    return '${time[1]}-${time[2]}-${time[3]}T'
        '${time[4]}:${time[5]}:${time[6]}';
  }

  static String _stamp(DateTime at) {
    final text = at.toIso8601String();
    final dot = text.indexOf('.');
    return dot < 0 ? text : text.substring(0, dot);
  }
}
