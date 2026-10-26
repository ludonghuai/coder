import 'dart:convert';
import 'dart:io';

import 'package:baocode/kernel/thincoder/thincoder_process_io.dart';
import 'package:baocode/kernel/thincoder/thincoder_transport.dart';
import 'package:baocode/platform/child_process_registry.dart';
import 'package:baocode/platform/process_host.dart' hide ProcessSignal;
import 'package:baocode/platform/process_host_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late IsolateProcessHostBackend backend;
  late ThincoderProcessRegistry previousRegistry;
  final children = <int>{};

  ProcessSpec command(String script, [List<String> arguments = const []]) =>
      ProcessSpec('node', ['-e', script, ...arguments]);

  Future<HostedProcess> start(ProcessSpec spec) async {
    final process = await ProcessHost.start(spec);
    children.add(process.pid);
    return process;
  }

  Future<void> stopChild(int pid) async {
    if (!children.remove(pid)) return;
    Process.killPid(pid, ProcessSignal.sigkill);
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('process-host-test');
    backend = IsolateProcessHostBackend(
      acknowledgementTimeout: const Duration(milliseconds: 250),
    );
    ProcessHost.useForTest(backend);
    previousRegistry = ThincoderProcess.registry;
    ThincoderProcess.registry = ThincoderProcessRegistry(
      file: File(p.join(temp.path, 'state', 'thincoder-processes.json')),
      lookup: (_) async => null,
      signal: (_) => false,
    );
  });

  tearDown(() async {
    ProcessHost.useForTest(null);
    await backend.resetForTest();
    await processHostBackendForTest.resetForTest();
    ThincoderProcess.registry = previousRegistry;
    for (final child in children.toList()) {
      await stopChild(child);
    }
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('T14: a hosted process echoes ordered writes and returns its exit code',
      () async {
    final process = await start(
      command(
        "process.stdin.on('data',(chunk)=>process.stdout.write(chunk));"
        "process.stdin.on('end',()=>process.exit(7));",
      ),
    );
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();

    process.write(utf8.encode('first\n'));
    process.write(utf8.encode('second\n'));
    process.closeStdin();

    expect(await stdout, 'first\nsecond\n');
    expect(await stderr, isEmpty);
    expect(await process.exitCode, 7);
    await stopChild(process.pid);
  });

  test('T15: a one-shot run matches Process.run', () async {
    final spec = command(
      "process.stdout.write('out');process.stderr.write('err');process.exit(3);",
    );
    final hosted = await ProcessHost.run(spec);
    final direct = await Process.run(spec.executable, spec.arguments);

    expect(hosted.exitCode, direct.exitCode);
    expect(hosted.stdout, direct.stdout);
    expect(hosted.stderr, direct.stderr);
    expect(hosted.exitCode, 3);
    expect(hosted.stdout, 'out');
    expect(hosted.stderr, 'err');
  });

  test('T21: spawn failure is explicit and maps to ThincoderUnavailable',
      () async {
    ProcessHost.useForTest(_FailingBackend());
    final spec = command('process.exit(0)');
    await expectLater(
      ProcessHost.start(spec),
      throwsA(
        isA<ProcessHostUnavailable>()
            .having((error) => error.cause, 'cause', isA<ProcessException>())
            .having(
              (error) => '$error',
              'original information',
              contains('injected spawn failure'),
            ),
      ),
    );

    await expectLater(
      ThincoderProcess.start(
        ThincoderLaunch(
          cwd: temp.path,
          executable: p.join(temp.path, 'missing-thincoder'),
        ),
      ),
      throwsA(
        isA<ThincoderUnavailable>().having(
          (error) => '$error',
          'detail',
          contains('injected spawn failure'),
        ),
      ),
    );
  });

  test('T22a: proxy death fails an outstanding call on every platform',
      () async {
    final process = await start(command('setInterval(()=>{},1000);'));
    final exited = expectLater(
      process.exitCode,
      throwsA(isA<ProcessHostUnavailable>()),
    );

    await backend.killProxyForTest();
    await exited.timeout(const Duration(seconds: 2));
    await stopChild(process.pid);
  });

  test('T22b: the next start rebuilds once without replaying old work',
      () async {
    final marker = File(p.join(temp.path, 'old-process-count'));
    final process = await start(
      command(
        "require('fs').appendFileSync(process.argv[1],'x');"
        'setInterval(()=>{},1000);',
        [marker.path],
      ),
    );
    final exited = expectLater(
      process.exitCode,
      throwsA(isA<ProcessHostUnavailable>()),
    );
    final generation = backend.generation;

    await backend.killProxyForTest();
    await exited;
    final replacement = await start(command('process.exit(0)'));
    expect(backend.generation, generation + 1);
    expect(await replacement.exitCode, 0);
    expect(marker.readAsStringSync(), 'x', reason: 'old work was not replayed');

    await stopChild(process.pid);
    await stopChild(replacement.pid);
  });

  test(
    'T22c: an orphan is reaped by ChildProcessRegistry on POSIX',
    () async {
      final file = File(p.join(temp.path, 'registry', 'children.json'));
      final before = ChildProcessRegistry(
        file: file,
        ownPid: 100,
        lookup: (_) async => null,
        signal: (_) => false,
      );
      await before.add(3456, command: 'node old-process');
      final reaped = <int>[];
      final nextRun = ChildProcessRegistry(
        file: file,
        ownPid: 200,
        lookup: (_) async => (parent: 1, command: 'node old-process'),
        signal: (child) {
          reaped.add(child);
          return true;
        },
      );

      await nextRun.reaped;
      expect(reaped, [3456]);
    },
    skip: Platform.isWindows ? 'no ps on Windows' : false,
  );

  test('T22d: a stop that meets a dead proxy still completes', () async {
    final pidFile = File(p.join(temp.path, 'child-pid'));
    await ThincoderProcess.start(
      ThincoderLaunch(
        // Not [temp]: Windows locks a running process's working directory, and
        // the tear-down below deletes that one.
        cwd: Directory.systemTemp.path,
        executable: 'node',
        arguments: [
          '-e',
          "require('fs').writeFileSync(process.argv[1],"
          "String(process.pid)+String.fromCharCode(10));"
          'setInterval(()=>{},1000);',
          pidFile.path,
        ],
      ),
    );
    final child = await _awaitedPid(pidFile);
    try {
      // Nothing reaches the proxy any more, so the stop's kill is dropped and
      // it waits on an exit that only the pending request's timeout ends —
      // which fails the exit the stop was waiting for.
      await backend.closeProxyChannelForTest();
      final pending = expectLater(
        ProcessHost.run(command('process.exit(0)')),
        throwsA(isA<ProcessHostUnavailable>()),
      );
      final stopping = ThincoderProcess.stopAll();
      await pending;
      await stopping.timeout(const Duration(seconds: 5));
    } finally {
      Process.killPid(child, ProcessSignal.sigkill);
    }
  });

  test('T22e: a proxy death leaves the orphan recorded for a later run',
      () async {
    final pidFile = File(p.join(temp.path, 'child-pid'));
    final transport = await ThincoderProcess.start(
      ThincoderLaunch(
        cwd: Directory.systemTemp.path,
        executable: 'node',
        arguments: [
          '-e',
          "require('fs').writeFileSync(process.argv[1],"
          "String(process.pid)+String.fromCharCode(10));"
          'setInterval(()=>{},1000);',
          pidFile.path,
        ],
      ),
    );
    final child = await _awaitedPid(pidFile);
    try {
      await backend.killProxyForTest();
      await transport.exited;
      await ThincoderProcess.registry.flush();
      expect(
        ThincoderProcess.registry.file.readAsStringSync(),
        contains('"pid":$child'),
        reason: 'the next run is the only one that can end it now',
      );
    } finally {
      Process.killPid(child, ProcessSignal.sigkill);
    }
  });

  test('T23: an unreachable channel fails and the next start rebuilds',
      () async {
    final process = await start(command('setInterval(()=>{},1000);'));
    final exited = expectLater(
      process.exitCode,
      throwsA(isA<ProcessHostUnavailable>()),
    );
    await backend.closeProxyChannelForTest();
    final generation = backend.generation;

    await expectLater(
      ProcessHost.run(command('process.exit(0)')),
      throwsA(isA<ProcessHostUnavailable>()),
    );
    await exited;
    final replacement = await start(command('process.exit(0)'));
    expect(backend.generation, generation + 1);
    expect(await replacement.exitCode, 0);

    await stopChild(process.pid);
    await stopChild(replacement.pid);
  });
}

/// The pid a child writes once it runs: starting it returns before it does.
Future<int> _awaitedPid(File file) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    // The line break comes with the digits: a torn write cannot be parsed.
    final text = file.existsSync() ? file.readAsStringSync() : '';
    if (text.endsWith('\n')) return int.parse(text.trim());
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw StateError('No pid in ${file.path}');
}

final class _FailingBackend implements ProcessHostBackend {
  ProcessException get error => ProcessException(
    'missing-thincoder',
    const [],
    'injected spawn failure',
    2,
  );

  @override
  Future<HostedProcess> start(ProcessSpec spec) => Future.error(error);

  @override
  Future<HostedRun> run(
    ProcessSpec spec, {
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) => Future.error(error);

  @override
  Future<void> stopAll() async {}
}
