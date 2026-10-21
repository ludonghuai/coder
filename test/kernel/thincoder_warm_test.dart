import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:baocode/kernel/thincoder/thincoder_transport.dart';
import 'package:baocode/kernel/thincoder/thincoder_warm.dart';
import 'package:baocode/platform/event_log.dart';

/// A process as the pool starts one: it answers the handshake, records what
/// was written to it, and says it left when the test has it die.
class _Agent implements ThincoderTransport {
  final List<Map<String, Object?>> written = [];
  final StreamController<Map<String, Object?>> _out =
      StreamController<Map<String, Object?>>.broadcast();
  bool closed = false;

  /// What it was asked, by method.
  List<Map<String, Object?>> requests(String method) => [
    for (final message in written)
      if (message['method'] == method) message,
  ];

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  @override
  void write(Map<String, Object?> message) {
    written.add(message);
    if (message['method'] != 'initialize') return;
    _out.add({
      'jsonrpc': '2.0',
      'id': message['id'],
      'result': {
        'protocolVersion': 1,
        'agentCapabilities': <String, Object?>{},
        'authMethods': <Object?>[],
        'agentInfo': {'name': 'thincoder', 'version': '0.12.74'},
      },
    });
  }

  /// The process dies, as a real transport says it: the exit message, then
  /// nothing more.
  void exit() {
    if (_out.isClosed) return;
    _out.add(ThincoderExit.message(1, 'gone'));
    unawaited(_out.close());
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    if (!_out.isClosed) unawaited(_out.close());
  }

  @override
  Future<void> get exited => _out.done;
}

/// A clock the test moves, so that a ten-minute TTL costs nothing.
class _Clock {
  DateTime now = DateTime(2026, 10, 21, 1);

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);
}

/// The pool's own TTL timer: the test moves the clock instead.
class _NoTimer implements Timer {
  @override
  void cancel() {}

  @override
  bool get isActive => false;

  @override
  int get tick => 0;
}

void main() {
  final logs = Directory.systemTemp.createTempSync('warm-test');
  final clock = _Clock();

  setUp(() {
    clock.now = DateTime(2026, 10, 21, 1);
    EventLog.current = EventLog(logs.path);
    final file = File(p.join(logs.path, 'events.log'));
    if (file.existsSync()) file.deleteSync();
  });

  tearDown(() => EventLog.current = null);

  tearDownAll(() {
    if (logs.existsSync()) logs.deleteSync(recursive: true);
  });

  /// What the terminal's log says, the lines with [text].
  List<String> logged(String text) {
    final file = File(p.join(logs.path, 'events.log'));
    if (!file.existsSync()) return const [];
    return [
      for (final line in file.readAsLinesSync())
        if (line.contains(text)) line,
    ];
  }

  /// The pool, and the processes it started.
  (ThincoderWarm, List<_Agent>) make() {
    final agents = <_Agent>[];
    final pool = ThincoderWarm(
      start: (_) async {
        final agent = _Agent();
        agents.add(agent);
        return agent;
      },
      launch: (cwd) async =>
          ThincoderLaunch(cwd: cwd, executable: '/mock/thincoder'),
      clock: clock.call,
      schedule: (_, _) => _NoTimer(),
    );
    return (pool, agents);
  }

  test('a process is held once for a key, its handshake answered (T108)',
      () async {
    final (pool, agents) = make();
    await pool.warm('/p', files: true);
    await pool.warm('/p', files: true);

    expect(agents, hasLength(1));
    expect(agents.single.requests('initialize'), hasLength(1));
    // No session: the terminal does not list it, and no slot is taken (§25.2).
    expect(agents.single.requests('session/new'), isEmpty);
    expect(logged('warm: held'), hasLength(1));

    final take = pool.take(('/p', true));
    expect(take, isNotNull);
    expect(identical(take!.transport, agents.single), isTrue);
    expect(take.handshake['agentInfo'], isA<Map>());
    // Handed over whole: nothing stays held, and the pool does not end it.
    expect(pool.cwd, isNull);
    expect(agents.single.closed, isFalse);
  });

  test('a process out of time is let go, and taking it says so (T109①)',
      () async {
    final (pool, agents) = make();
    await pool.warm('/p', files: true);

    clock.advance(const Duration(minutes: 10));

    expect(pool.take(('/p', true)), isNull);
    expect(agents.single.closed, isTrue);
    expect(logged('warm: dropped ttl'), hasLength(1));
  });

  test('a process that left is nothing held (T109②)', () async {
    final (pool, agents) = make();
    await pool.warm('/p', files: true);

    agents.single.exit();
    await pumpEventQueue();

    expect(pool.take(('/p', true)), isNull);
    expect(logged('warm: dropped exited'), hasLength(1));
  });

  test('a process for another handshake is not taken (T109③)', () async {
    final (pool, agents) = make();
    await pool.warm('/p', files: true);

    // The key is the folder and the handshake's bit: this one is not it.
    expect(pool.take(('/p', false)), isNull);
    expect(agents.single.closed, isFalse);

    await pool.warm('/p', files: false);

    expect(agents, hasLength(2));
    expect(agents.first.closed, isTrue);
    expect(logged('warm: dropped project-switch'), hasLength(1));
    final take = pool.take(('/p', false));
    expect(identical(take?.transport, agents.last), isTrue);
  });

  test('dropping the pool ends the process it held (T109④)', () async {
    final (pool, agents) = make();
    await pool.warm('/p', files: true);

    pool.drop('project-switch');

    expect(pool.take(('/p', true)), isNull);
    expect(agents.single.closed, isTrue);
    expect(logged('warm: dropped project-switch'), hasLength(1));
  });

  test('one process at most: another project takes its place (§25.2)',
      () async {
    final (pool, agents) = make();
    await pool.warm('/p', files: true);

    await pool.warm('/q', files: true);

    expect(agents, hasLength(2));
    expect(agents.first.closed, isTrue);
    expect(pool.cwd, '/q');
    expect(pool.take(('/p', true)), isNull);
    expect(pool.take(('/q', true)), isNotNull);
  });

  test('a start that fails says nothing to the user, and cools down (D104)',
      () async {
    var attempts = 0;
    final pool = ThincoderWarm(
      start: (_) async {
        attempts++;
        throw const ThincoderUnavailable('thincoder is not installed');
      },
      launch: (cwd) async =>
          ThincoderLaunch(cwd: cwd, executable: '/mock/thincoder'),
      clock: clock.call,
      schedule: (_, _) => _NoTimer(),
    );

    await pool.warm('/p', files: true);
    expect(logged('warm: dropped failed'), hasLength(1));

    // Cooling down: not tried again at once.
    await pool.warm('/p', files: true);
    expect(attempts, 1);

    clock.advance(const Duration(seconds: 61));
    await pool.warm('/p', files: true);
    expect(attempts, 2);
    expect(pool.take(('/p', true)), isNull);
  });

  test('a start under way is waited for, and then taken (§25.2)', () async {
    final gate = Completer<void>();
    final agents = <_Agent>[];
    final pool = ThincoderWarm(
      start: (_) async {
        final agent = _Agent();
        agents.add(agent);
        await gate.future;
        return agent;
      },
      launch: (cwd) async =>
          ThincoderLaunch(cwd: cwd, executable: '/mock/thincoder'),
      clock: clock.call,
      schedule: (_, _) => _NoTimer(),
    );

    final warming = pool.warm('/p', files: true);
    // Nothing to take yet: `take` says so, and `takeWhenReady` waits instead —
    // as a session opened by the same action as the project does.
    expect(pool.take(('/p', true)), isNull);
    final taking = pool.takeWhenReady(('/p', true));
    gate.complete();
    await warming;

    final take = await taking;
    expect(identical(take?.transport, agents.single), isTrue);
    expect(agents.single.requests('initialize'), hasLength(1));
  });

  test('a process taken is the kernel\'s: no handshake is written to it again',
      () async {
    final (pool, agents) = make();
    await pool.warm('/p', files: true);

    final take = pool.take(('/p', true))!;
    take.connection.request('session/new', {'cwd': '/p'}).ignore();
    await pumpEventQueue();

    // The pool wrote the handshake and nothing else: the connection it handed
    // over is the one the kernel writes through.
    expect(agents.single.requests('initialize'), hasLength(1));
    expect(agents.single.requests('session/new'), hasLength(1));
  });
}
