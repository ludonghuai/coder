import 'dart:async';
import 'dart:convert';

import 'process_host_stub.dart'
    if (dart.library.io) 'process_host_io.dart' as platform;

/// Signals understood by the host. Keeping this small value type here makes
/// the public contract usable on the web without importing dart:io.
final class ProcessSignal {
  const ProcessSignal._(this.name);

  final String name;

  static const sigterm = ProcessSignal._('sigterm');
  static const sigkill = ProcessSignal._('sigkill');
}

/// All the parameters of one process creation; the fields have the same
/// meaning as their dart:io namesakes.
final class ProcessSpec {
  const ProcessSpec(
    this.executable,
    this.arguments, {
    this.workingDirectory,
    this.environment,
    this.includeParentEnvironment = true,
    this.runInShell = false,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
  final bool includeParentEnvironment;
  final bool runInShell;
}

/// A long-running process held by the process-host isolate. Bytes and
/// signals cross one ordered message channel; Process objects themselves do
/// not cross isolates.
final class HostedProcess {
  factory HostedProcess({
    required int pid,
    required Stream<List<int>> stdout,
    required Stream<List<int>> stderr,
    required Future<int> exitCode,
    required void Function(List<int> bytes) write,
    required void Function() closeStdin,
    required void Function(ProcessSignal signal) kill,
  }) {
    return HostedProcess._(
      pid,
      stdout,
      stderr,
      exitCode,
      write,
      closeStdin,
      kill,
    );
  }

  HostedProcess._(
    this.pid,
    this.stdout,
    this.stderr,
    this._exitCode,
    this._write,
    this._closeStdin,
    this._kill,
  );

  final int pid;
  final Stream<List<int>> stdout;
  final Stream<List<int>> stderr;
  final Future<int> _exitCode;
  final void Function(List<int> bytes) _write;
  final void Function() _closeStdin;
  final void Function(ProcessSignal signal) _kill;

  Future<int> get exitCode => _exitCode;

  void write(List<int> bytes) => _write(bytes);

  void closeStdin() => _closeStdin();

  void kill([
    ProcessSignal signal = ProcessSignal.sigterm,
  ]) => _kill(signal);
}

/// The decoded result of a one-shot command.
final class HostedRun {
  const HostedRun({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// The real backend owns one proxy isolate. Tests may supply an inline fake.
abstract interface class ProcessHostBackend {
  Future<HostedProcess> start(ProcessSpec spec);

  Future<HostedRun> run(
    ProcessSpec spec, {
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  });

  Future<void> stopAll();
}

/// A proxy could not be started, or an established proxy stopped answering.
/// There is deliberately no fallback to Process on the window isolate.
final class ProcessHostUnavailable implements Exception {
  const ProcessHostUnavailable(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message: $cause';
}

/// Creates processes away from the window isolate.
abstract final class ProcessHost {
  static ProcessHostBackend? _backend;

  static ProcessHostBackend get _current =>
      _backend ??= platform.createProcessHostBackend();

  static Future<HostedProcess> start(ProcessSpec spec) async {
    try {
      return await _current.start(spec);
    } on ProcessHostUnavailable {
      rethrow;
    } on Object catch (error) {
      throw ProcessHostUnavailable(
        'The process host could not start ${spec.executable}',
        cause: error,
      );
    }
  }

  static Future<HostedRun> run(
    ProcessSpec spec, {
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) async {
    try {
      return await _current.run(
        spec,
        stdoutEncoding: stdoutEncoding,
        stderrEncoding: stderrEncoding,
      );
    } on ProcessHostUnavailable {
      rethrow;
    } on Object catch (error) {
      throw ProcessHostUnavailable(
        'The process host could not run ${spec.executable}',
        cause: error,
      );
    }
  }

  /// Ends the normal child processes held by the proxy. Detached processes
  /// are outside this host and are never killed here.
  static Future<void> stopAll() => _current.stopAll();

  /// Installs [backend] for a test; null restores the lazy proxy backend.
  static void useForTest(ProcessHostBackend? backend) {
    _backend = backend;
  }
}
