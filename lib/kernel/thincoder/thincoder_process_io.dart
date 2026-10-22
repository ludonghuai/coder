import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../platform/child_process_registry.dart';
import '../../platform/data_dir.dart';
import 'thincoder_locator.dart';
import 'thincoder_transport.dart';

/// thincoder as a child process (`thincoder acp`), over its stdin and
/// stdout.
class ThincoderProcess implements ThincoderTransport {
  ThincoderProcess._(this._process, {this.executable}) {
    _live.add(this);
    unawaited(registry.add(_process.pid));
    _process.stdout
        .transform(_decoder)
        .transform(const LineSplitter())
        .listen(_line, onError: _undecodable, onDone: _stdoutDone);
    _process.stderr
        .transform(_decoder)
        .transform(const LineSplitter())
        .listen(_stderrLine, onError: _undecodable);
    unawaited(_process.exitCode.then(_exited));
  }

  /// What both streams are read with, and not strict about it: a line that
  /// is not UTF-8 takes the replacement character and goes on to [_line],
  /// which drops it as it would any other line that is not protocol. Strict,
  /// the decode error would reach the subscription instead and end the
  /// stream there — and what it printed before it failed is exactly what
  /// says why (its own errors can carry the console's code page on Windows).
  static const _decoder = Utf8Decoder(allowMalformed: true);

  /// A read error on either stream: kept as a stderr line, so that it is in
  /// the report when the process ends.
  void _undecodable(Object error) => _stderrLine('$error');

  /// A transport over [process], e.g. a stand-in process under test.
  @visibleForTesting
  factory ThincoderProcess.forProcess(Process process) =>
      ThincoderProcess._(process);

  /// Where the running processes are kept track of across runs.
  @visibleForTesting
  static ThincoderProcessRegistry registry = ThincoderProcessRegistry(
    file: File(DataDirectory.current.processRegistryFile('thincoder')),
  );

  /// The processes this run of the app started and that still run.
  static final Set<ThincoderProcess> _live = {};

  /// Ends every thincoder process this run started, and waits (up to
  /// [timeout] each) for them to go: done as the app quits, so a turn under
  /// way does not go on unseen, spending tokens, after the app is gone.
  static Future<void> stopAll({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    await Future.wait([
      for (final transport in [..._live]) transport._stop(timeout),
    ]);
    // Their entries gone from the list before the app is.
    await registry.flush();
  }

  /// Ends the processes an earlier run left behind; see
  /// [ThincoderProcessRegistry].
  static Future<void> reapLeftovers() => registry.reaped;

  Future<void> _stop(Duration timeout) async {
    close();
    try {
      await _process.exitCode.timeout(timeout);
    } on TimeoutException {
      _process.kill(ProcessSignal.sigkill);
    }
  }

  static Future<ThincoderTransport> start(ThincoderLaunch launch) async {
    // Left over from a run that ended without stopping them: gone first, so
    // two processes never go on with one session.
    await registry.reaped;
    try {
      final process = await Process.start(
        launch.executable,
        launch.arguments,
        workingDirectory: launch.cwd,
        // The login shell's environment is the whole of it; on Windows it
        // is the app's own, and the child needs the parent's beside it for
        // what `cmd.exe` itself runs on (COMSPEC, PATHEXT, …). None of
        // BaoCode's own proxy variables: thincoder's network is its own.
        environment: launch.environment,
        includeParentEnvironment: Platform.isWindows,
        // An npm shim is a `.cmd`, which only the shell can run.
        runInShell: ThincoderLocator.throughShell(launch.executable),
      );
      return ThincoderProcess._(process, executable: launch.executable);
    } on ProcessException catch (error) {
      // Which file: Windows' own words for it leave `%1` in its place.
      throw ThincoderUnavailable(
        'thincoder could not start',
        detail: '${launch.executable}\n${error.message}',
      );
    }
  }

  final Process _process;

  /// The build run, to name in a report of its failing.
  final String? executable;

  final StreamController<Map<String, Object?>> _messages =
      StreamController.broadcast();

  /// The last lines it printed on stderr, to say why it failed.
  final List<String> _stderr = [];
  static const _stderrLines = 30;

  int? _exitCode;
  bool _stdoutClosed = false;

  @override
  Stream<Map<String, Object?>> get messages => _messages.stream;

  void _line(String line) {
    if (line.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, Object?>) _messages.add(decoded);
    } on FormatException {
      // Not protocol (e.g. a warning printed to stdout): keep it for the
      // failure report.
      _stderrLine(line);
    }
  }

  void _stderrLine(String line) {
    _stderr.add(line);
    if (_stderr.length > _stderrLines) _stderr.removeAt(0);
  }

  void _stdoutDone() {
    _stdoutClosed = true;
    _finish();
  }

  void _exited(int code) {
    _exitCode = code;
    _live.remove(this);
    unawaited(registry.remove(_process.pid));
    _finish();
  }

  /// Ends the stream once both the output is read and the process gone, so
  /// its last messages come before the exit.
  void _finish() {
    final code = _exitCode;
    if (code == null || !_stdoutClosed || _messages.isClosed) return;
    _messages
      ..add(
        ThincoderExit.message(
          code,
          _stderr.join('\n'),
          executable: executable,
        ),
      )
      ..close();
  }

  @override
  void write(Map<String, Object?> message) {
    if (_exitCode != null) return;
    try {
      _process.stdin.writeln(jsonEncode(message));
    } on StateError {
      // Closed under us: the exit message follows.
    }
  }

  @override
  Future<void> get exited => _process.exitCode.then((_) {});

  @override
  void close() {
    if (_exitCode != null) return;
    unawaited(_process.stdin.close().catchError((_) {}));
    _process.kill();
  }
}

/// The thincoder processes the app has running
/// (`thincoder-processes.json`); see [ChildProcessRegistry]. Entries a run
/// recorded without a command line are ended only when they run thincoder
/// with `acp`.
class ThincoderProcessRegistry extends ChildProcessRegistry {
  ThincoderProcessRegistry({
    required super.file,
    super.ownPid,
    super.lookup,
    super.signal,
  }) : super(recognizes: _isThincoder);

  static bool _isThincoder(String command) =>
      command.contains('thincoder') && command.contains('acp');
}
