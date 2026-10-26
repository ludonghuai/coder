import 'dart:async';
import 'dart:convert';
import 'dart:io' hide ProcessSignal;
import 'dart:io' as io show ProcessSignal;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'process_host.dart';

final IsolateProcessHostBackend _defaultBackend = IsolateProcessHostBackend();

ProcessHostBackend createProcessHostBackend() => _defaultBackend;

/// Test control for the one default backend; production callers use
/// [ProcessHost] instead.
@visibleForTesting
IsolateProcessHostBackend get processHostBackendForTest => _defaultBackend;

/// The real backend. One proxy is reused until it dies; a later request makes
/// one replacement and never replays an earlier request.
final class IsolateProcessHostBackend implements ProcessHostBackend {
  IsolateProcessHostBackend({
    this.acknowledgementTimeout = const Duration(seconds: 30),
  });

  final Duration acknowledgementTimeout;
  _Proxy? _proxy;
  Future<_Proxy>? _starting;
  int _generation = 0;

  @visibleForTesting
  int get generation => _generation;

  Future<_Proxy> _ensureProxy() {
    final current = _proxy;
    if (current != null && current.alive) return Future.value(current);
    return _starting ??= _Proxy.spawn(acknowledgementTimeout).then((proxy) {
      _proxy = proxy;
      _generation++;
      return proxy;
    }).whenComplete(() => _starting = null);
  }

  @override
  Future<HostedProcess> start(ProcessSpec spec) async {
    final proxy = await _ensureProxy();
    return proxy.start(spec);
  }

  @override
  Future<HostedRun> run(
    ProcessSpec spec, {
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) async {
    final proxy = await _ensureProxy();
    return proxy.run(
      spec,
      stdoutEncoding: stdoutEncoding,
      stderrEncoding: stderrEncoding,
    );
  }

  @override
  Future<void> stopAll() async {
    final starting = _starting;
    final proxy = _proxy ?? (starting == null ? null : await starting);
    if (proxy == null || !proxy.alive) return;
    await proxy.stopAll();
  }

  @visibleForTesting
  Future<void> killProxyForTest() async {
    final starting = _starting;
    final proxy = _proxy ?? (starting == null ? null : await starting);
    proxy?._isolate.kill(priority: Isolate.immediate);
  }

  @visibleForTesting
  Future<void> closeProxyChannelForTest() async {
    final starting = _starting;
    final proxy = _proxy ?? (starting == null ? null : await starting);
    if (proxy == null) throw StateError('No process-host proxy is running');
    await proxy._closeChannelForTest();
  }

  @visibleForTesting
  Future<void> resetForTest() async {
    final starting = _starting;
    final proxy = _proxy ?? (starting == null ? null : await starting);
    if (proxy == null) return;
    proxy._isolate.kill(priority: Isolate.immediate);
    proxy._fail(const ProcessHostUnavailable('Process-host test reset'));
    _proxy = null;
  }
}

final class _Pending {
  _Pending(this.id);

  final int id;
  bool acknowledged = false;
  final result = Completer<Object?>();
  Timer? timer;
}

final class _Proxy {
  _Proxy._(
    this._isolate,
    this._responses,
    this._exit,
    this._errors,
    this.acknowledgementTimeout,
  ) {
    _responseSubscription = _responses.listen(_onMessage);
    _exitSubscription = _exit.listen((_) {
      _fail(
        ProcessHostUnavailable(
          'The process-host isolate stopped',
          cause: _lastError,
        ),
      );
    });
    _errorSubscription = _errors.listen((message) {
      _lastError = '$message';
    });
  }

  final Isolate _isolate;
  final ReceivePort _responses;
  final ReceivePort _exit;
  final ReceivePort _errors;
  final Duration acknowledgementTimeout;
  final _ready = Completer<SendPort>();
  final _pending = <int, _Pending>{};
  final _processes = <int, _ClientProcess>{};
  late final StreamSubscription<Object?> _responseSubscription;
  late final StreamSubscription<Object?> _exitSubscription;
  late final StreamSubscription<Object?> _errorSubscription;
  SendPort? _requests;
  String? _lastError;
  int _nextId = 1;
  bool alive = true;

  static Future<_Proxy> spawn(Duration acknowledgementTimeout) async {
    final responses = ReceivePort();
    final exit = ReceivePort();
    final errors = ReceivePort();
    Isolate isolate;
    try {
      isolate = await Isolate.spawn(
        _serveProcessHost,
        responses.sendPort,
        onExit: exit.sendPort,
        onError: errors.sendPort,
      );
    } on Object catch (error) {
      responses.close();
      exit.close();
      errors.close();
      throw ProcessHostUnavailable(
        'The process-host isolate could not start',
        cause: error,
      );
    }
    final proxy = _Proxy._(
      isolate,
      responses,
      exit,
      errors,
      acknowledgementTimeout,
    );
    try {
      proxy._requests = await proxy._ready.future.timeout(
        acknowledgementTimeout,
      );
      return proxy;
    } on Object catch (error) {
      isolate.kill(priority: Isolate.immediate);
      proxy._fail(
        ProcessHostUnavailable(
          'The process-host isolate did not answer',
          cause: error,
        ),
      );
      rethrow;
    }
  }

  Future<HostedProcess> start(ProcessSpec spec) async {
    _checkAlive();
    final response = await _request('start', _specMessage(spec));
    final values = response as Map<Object?, Object?>;
    if (values['error'] != null) {
      throw _startFailure(spec, values);
    }
    final key = values['key']! as int;
    final process = _ClientProcess(this, key, values['pid']! as int);
    _processes[key] = process;
    return process.hosted;
  }

  Future<HostedRun> run(
    ProcessSpec spec, {
    required Encoding? stdoutEncoding,
    required Encoding? stderrEncoding,
  }) async {
    _checkAlive();
    final response = await _request('run', _specMessage(spec));
    final values = response as Map<Object?, Object?>;
    if (values['error'] != null) {
      throw ProcessHostUnavailable(
        'The process host could not run ${spec.executable}',
        cause: values['error'],
      );
    }
    return HostedRun(
      exitCode: values['exitCode']! as int,
      stdout: (stdoutEncoding ?? systemEncoding).decode(
        values['stdout']! as Uint8List,
      ),
      stderr: (stderrEncoding ?? systemEncoding).decode(
        values['stderr']! as Uint8List,
      ),
    );
  }

  Future<void> stopAll() async {
    _checkAlive();
    await _request('stopAll', const {});
  }

  Future<void> _closeChannelForTest() async {
    _checkAlive();
    await _request('debugCloseChannel', const {});
  }

  Future<Object?> _request(String command, Map<String, Object?> values) {
    final id = _nextId++;
    final pending = _Pending(id);
    _pending[id] = pending;
    pending.timer = Timer(acknowledgementTimeout, () {
      _fail(
        ProcessHostUnavailable(
          'The process-host channel stopped answering ($command)',
        ),
      );
      _isolate.kill(priority: Isolate.immediate);
    });
    _requests!.send({'id': id, 'command': command, ...values});
    return pending.result.future;
  }

  void _sendControl(String command, int key, [Map<String, Object?>? values]) {
    if (!alive) return;
    _requests!.send({
      'id': _nextId++,
      'command': command,
      'key': key,
      ...?values,
    });
  }

  void _onMessage(Object? message) {
    if (message is! Map) return;
    if (message['command'] == 'ready') {
      if (!_ready.isCompleted) _ready.complete(message['port'] as SendPort);
      return;
    }
    final id = message['id'];
    if (id is int && message.containsKey('ack')) {
      final pending = _pending[id];
      if (pending != null && !pending.acknowledged) {
        pending.timer?.cancel();
        pending.acknowledged = true;
      }
      return;
    }
    final kind = message['kind'];
    if (id is int && kind == 'result') {
      final pending = _pending.remove(id);
      if (pending != null) {
        pending.timer?.cancel();
        if (!pending.result.isCompleted) {
          pending.result.complete(message['value']);
        }
      }
      return;
    }
    final key = message['key'];
    if (key is! int) return;
    final process = _processes[key];
    if (process == null) return;
    switch (kind) {
      case 'stdout':
        process._stdout.add(message['bytes'] as Uint8List);
      case 'stderr':
        process._stderr.add(message['bytes'] as Uint8List);
      case 'stdoutDone':
        process._stdoutDone();
      case 'stderrDone':
        process._stderrDone();
      case 'streamError':
        process._streamError('${message['stream']}', '${message['error']}');
      case 'exit':
        process._exited(message['code']! as int);
    }
  }

  void _checkAlive() {
    if (!alive) {
      throw ProcessHostUnavailable(
        'The process host is unavailable',
        cause: _lastError,
      );
    }
  }

  void _fail(ProcessHostUnavailable error) {
    if (!alive) return;
    alive = false;
    for (final pending in _pending.values) {
      pending.timer?.cancel();
      if (!pending.result.isCompleted) pending.result.completeError(error);
    }
    _pending.clear();
    for (final process in [..._processes.values]) {
      process._failed(error);
    }
    _processes.clear();
    if (!_ready.isCompleted) _ready.completeError(error);
    unawaited(_responseSubscription.cancel());
    unawaited(_exitSubscription.cancel());
    unawaited(_errorSubscription.cancel());
    _responses.close();
    _exit.close();
    _errors.close();
  }

  static Map<String, Object?> _specMessage(ProcessSpec spec) => {
    'executable': spec.executable,
    'arguments': spec.arguments,
    'workingDirectory': spec.workingDirectory,
    'environment': spec.environment,
    'includeParentEnvironment': spec.includeParentEnvironment,
    'runInShell': spec.runInShell,
  };

  static ProcessHostUnavailable _startFailure(
    ProcessSpec spec,
    Map<Object?, Object?> response,
  ) {
    if (response['processException'] == true) {
      return ProcessHostUnavailable(
        'The process host could not start ${spec.executable}',
        cause: ProcessException(
          spec.executable,
          spec.arguments,
          '${response['error']}',
          response['errorCode']! as int,
        ),
      );
    }
    return ProcessHostUnavailable(
      'The process host could not start ${spec.executable}',
      cause: response['error'],
    );
  }
}

final class _ClientProcess {
  _ClientProcess(this._proxy, this.key, int pid) {
    hosted = HostedProcess(
      pid: pid,
      stdout: _stdout.stream,
      stderr: _stderr.stream,
      exitCode: _exit.future,
      write: _write,
      closeStdin: _closeStdin,
      kill: _kill,
    );
  }

  final _Proxy _proxy;
  final int key;
  final _stdout = StreamController<List<int>>();
  final _stderr = StreamController<List<int>>();
  final _exit = Completer<int>();
  late final HostedProcess hosted;
  bool _stdoutClosed = false;
  bool _stderrClosed = false;

  void _write(List<int> bytes) {
    if (!_proxy.alive || _exit.isCompleted) {
      throw StateError('The hosted process is no longer available');
    }
    _proxy._sendControl('write', key, {'bytes': Uint8List.fromList(bytes)});
  }

  void _closeStdin() {
    if (!_proxy.alive || _exit.isCompleted) return;
    _proxy._sendControl('closeStdin', key);
  }

  void _kill(ProcessSignal signal) {
    if (!_proxy.alive || _exit.isCompleted) return;
    _proxy._sendControl('kill', key, {'signal': signal.name});
  }

  void _stdoutDone() {
    if (_stdoutClosed) return;
    _stdoutClosed = true;
    unawaited(_stdout.close());
    _maybeRemove();
  }

  void _stderrDone() {
    if (_stderrClosed) return;
    _stderrClosed = true;
    unawaited(_stderr.close());
    _maybeRemove();
  }

  void _streamError(String stream, Object error) {
    (stream == 'stdout' ? _stdout : _stderr).addError(error);
  }

  void _exited(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
    _maybeRemove();
  }

  void _failed(ProcessHostUnavailable error) {
    if (!_exit.isCompleted) _exit.completeError(error);
    _stdoutDone();
    _stderrDone();
  }

  void _maybeRemove() {
    if (_exit.isCompleted && _stdoutClosed && _stderrClosed) {
      _proxy._processes.remove(key);
    }
  }
}

Future<void> _serveProcessHost(SendPort replies) async {
  final requests = ReceivePort();
  replies.send({'command': 'ready', 'port': requests.sendPort});
  final processes = <int, _ServerProcess>{};
  var nextKey = 1;

  Future<void> start(Map<Object?, Object?> message) async {
    final id = message['id']! as int;
    replies.send({'id': id, 'ack': true});
    final executable = message['executable']! as String;
    try {
      final process = await Process.start(
        executable,
        (message['arguments']! as List).cast<String>(),
        workingDirectory: message['workingDirectory'] as String?,
        environment: (message['environment'] as Map?)?.cast<String, String>(),
        includeParentEnvironment: message['includeParentEnvironment']! as bool,
        runInShell: message['runInShell']! as bool,
      );
      final key = nextKey++;
      final hosted = _ServerProcess(key, process, replies, () {
        processes.remove(key);
      });
      processes[key] = hosted;
      replies.send({
        'id': id,
        'kind': 'result',
        'value': {'key': key, 'pid': process.pid},
      });
      hosted.forward();
    } on ProcessException catch (error) {
      replies.send({
        'id': id,
        'kind': 'result',
        'value': {
          'error': error.message,
          'errorCode': error.errorCode,
          'processException': true,
        },
      });
    } on Object catch (error) {
      replies.send({
        'id': id,
        'kind': 'result',
        'value': {'error': '$error'},
      });
    }
  }

  Future<void> run(Map<Object?, Object?> message) async {
    final id = message['id']! as int;
    replies.send({'id': id, 'ack': true});
    try {
      final result = await Process.run(
        message['executable']! as String,
        (message['arguments']! as List).cast<String>(),
        workingDirectory: message['workingDirectory'] as String?,
        environment: (message['environment'] as Map?)?.cast<String, String>(),
        includeParentEnvironment: message['includeParentEnvironment']! as bool,
        runInShell: message['runInShell']! as bool,
        stdoutEncoding: null,
        stderrEncoding: null,
      );
      replies.send({
        'id': id,
        'kind': 'result',
        'value': {
          'exitCode': result.exitCode,
          'stdout': result.stdout as Uint8List,
          'stderr': result.stderr as Uint8List,
        },
      });
    } on Object catch (error) {
      replies.send({
        'id': id,
        'kind': 'result',
        'value': {'error': '$error'},
      });
    }
  }

  Future<void> stopAll(Map<Object?, Object?> message) async {
    final id = message['id']! as int;
    replies.send({'id': id, 'ack': true});
    await Future.wait([for (final process in processes.values) process.stop()]);
    replies.send({'id': id, 'kind': 'result', 'value': null});
  }

  requests.listen((message) {
    if (message is! Map) return;
    final command = message['command'];
    final key = message['key'];
    final process = key is int ? processes[key] : null;
    switch (command) {
      case 'start':
        unawaited(start(message));
      case 'run':
        unawaited(run(message));
      case 'stopAll':
        unawaited(stopAll(message));
      case 'write':
        process?._write(message['bytes'] as Uint8List);
      case 'closeStdin':
        process?._closeStdin();
      case 'kill':
        process?._kill('${message['signal']}');
      case 'debugCloseChannel':
        replies.send({'id': message['id'], 'kind': 'result', 'value': null});
        requests.close();
    }
  });
}

final class _ServerProcess {
  _ServerProcess(this.key, this.process, this.replies, this.remove);

  final int key;
  final Process process;
  final SendPort replies;
  final void Function() remove;
  bool _stdoutClosed = false;
  bool _stderrClosed = false;
  bool _exited = false;

  void forward() {
    process.stdin.done.then<void>((_) {}, onError: (Object _) {});
    process.stdout.listen(
      (bytes) => _send('stdout', bytes),
      onError: (Object error) => _sendError('stdout', error),
      onDone: () {
        _stdoutClosed = true;
        replies.send({'kind': 'stdoutDone', 'key': key});
        _maybeRemove();
      },
    );
    process.stderr.listen(
      (bytes) => _send('stderr', bytes),
      onError: (Object error) => _sendError('stderr', error),
      onDone: () {
        _stderrClosed = true;
        replies.send({'kind': 'stderrDone', 'key': key});
        _maybeRemove();
      },
    );
    unawaited(
      process.exitCode.then((code) {
        _exited = true;
        replies.send({'kind': 'exit', 'key': key, 'code': code});
        _maybeRemove();
      }),
    );
  }

  /// Pipes hand over [Uint8List]s; a chunk of any other [List] shape is
  /// copied rather than cast, so that it cannot end the output silently.
  void _send(String kind, List<int> bytes) {
    replies.send({
      'kind': kind,
      'key': key,
      'bytes': bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    });
  }

  void _sendError(String stream, Object error) {
    replies.send({
      'kind': 'streamError',
      'key': key,
      'stream': stream,
      'error': '$error',
    });
  }

  void _write(Uint8List bytes) {
    if (_exited) return;
    process.stdin.add(bytes);
  }

  void _closeStdin() {
    unawaited(process.stdin.close().catchError((_) {}));
  }

  void _kill(String signal) {
    if (_exited) return;
    process.kill(switch (signal) {
      'sigkill' => io.ProcessSignal.sigkill,
      _ => io.ProcessSignal.sigterm,
    });
  }

  Future<void> stop() async {
    _closeStdin();
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      process.kill(io.ProcessSignal.sigkill);
    }
  }

  void _maybeRemove() {
    if (_exited && _stdoutClosed && _stderrClosed) remove();
  }
}
