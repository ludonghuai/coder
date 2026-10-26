import 'dart:convert';

import 'process_host.dart';

/// A browser cannot create a local process.
ProcessHostBackend createProcessHostBackend() => const _StubBackend();

final class _StubBackend implements ProcessHostBackend {
  const _StubBackend();

  static const unavailable = ProcessHostUnavailable(
    'Local processes are available only in the desktop app',
  );

  @override
  Future<HostedProcess> start(ProcessSpec spec) => Future.error(unavailable);

  @override
  Future<HostedRun> run(
    ProcessSpec spec, {
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) => Future.error(unavailable);

  @override
  Future<void> stopAll() async {}
}
