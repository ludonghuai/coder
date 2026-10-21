import 'dart:async';

import '../../platform/event_log.dart';
import 'thincoder_files.dart';
import 'thincoder_locator.dart';
import 'thincoder_process.dart';
import 'thincoder_protocol.dart';
import 'thincoder_transport.dart';

/// What a held process is keyed by (§25.2, D100): where it runs, and whether
/// its handshake says it reads and writes the editor's files — the very bit
/// the kernel sends as `clientCapabilities` (`thincoder_kernel.dart:249-251`).
/// One key's process serves no other: `session/new` takes only its own
/// folder, and the capabilities it answered with are fixed.
typedef ThincoderWarmKey = (String cwd, bool files);

/// A process taken from the pool: its connection — `initialize` answered, so
/// it is never sent again — the transport the kernel owns from here on, and
/// the handshake's answer, which says what that agent takes (§25.2).
typedef ThincoderWarmTake = ({
  ThincoderConnection connection,
  ThincoderTransport transport,
  Map<String, Object?> handshake,
});

/// One process kept warm for the project open now (§25.2): started when the
/// project is opened, `initialize` answered, and no session made — so it
/// holds no slot, and the terminal does not list it. A session then takes it
/// instead of starting one of its own, and pays neither the start (~90 ms)
/// nor the handshake (~364 ms).
///
/// One at most, for one key: another project — or another handshake — takes
/// the place of the one held. A process taken, out of time, or gone is
/// nothing kept. A start that fails cools down for [cooldown], and says
/// nothing to the user: they had not asked for anything yet (D104).
class ThincoderWarm {
  ThincoderWarm({
    ThincoderTransportFactory? start,
    ThincoderLauncher? launch,
    DateTime Function()? clock,
    Timer Function(Duration, void Function())? schedule,
    this.ttl = const Duration(minutes: 10),
    this.cooldown = const Duration(seconds: 60),
  }) : _start = start ?? startThincoderProcess,
       _launchFor = launch ?? ThincoderLocator.launch,
       _clock = clock ?? DateTime.now,
       _schedule = schedule ?? _later;

  /// The pool the kernel takes from and the workspace warms. A test puts one
  /// of its own here — a fake start, a clock it moves — and puts this back in
  /// `finally`.
  static ThincoderWarm instance = ThincoderWarm();

  static Timer _later(Duration delay, void Function() action) =>
      Timer(delay, action);

  final ThincoderTransportFactory _start;
  final ThincoderLauncher _launchFor;
  final DateTime Function() _clock;
  final Timer Function(Duration, void Function()) _schedule;

  /// How long a held process waits for a session before it goes.
  final Duration ttl;

  /// How long a start that failed is not tried again (D104).
  final Duration cooldown;

  /// How long a session waits for a start already under way before it starts
  /// one of its own.
  static const startup = Duration(seconds: 30);

  /// The key served — held, or on its way; null when neither.
  ThincoderWarmKey? _wanted;

  /// The start under way for [_wanted], where one is: never two at once.
  Future<void>? _starting;

  ThincoderConnection? _connection;
  ThincoderTransport? _transport;
  StreamSubscription<Map<String, Object?>>? _subscription;
  Map<String, Object?>? _handshake;
  DateTime? _heldAt;
  Timer? _expiry;
  (ThincoderWarmKey, DateTime)? _failed;

  /// The folder the process serves — held, or on its way; null when none is.
  String? get cwd => _wanted?.$1;

  /// Starts a process for this key ahead of the session that will use it, and
  /// answers its handshake. Nothing when this key is served already, and
  /// nothing while a start for it that failed is cooling down. [files] is the
  /// handshake's own bit: whether the kernel it serves has the host's files.
  Future<void> warm(String cwd, {required bool files}) {
    final key = (cwd, files);
    if (cwd.isEmpty) return Future.value();
    if (_wanted == key) {
      if (_starting case final starting?) return starting;
      if (_heldAt != null) return Future.value();
    }
    if (_failed case (final failed, final at)
        when failed == key && _clock().difference(at) < cooldown) {
      return Future.value();
    }
    // One process at a time: the one under way, or the one held, makes way.
    final before = _starting;
    _wanted = key;
    Future<void> run() async {
      if (before != null) await before;
      // Another project came after: this one is not to be.
      if (_wanted != key) return;
      if (_connection != null || _transport != null) {
        drop('project-switch');
        _wanted = key;
      }
      await _hold(key);
    }

    final starting = run();
    _starting = starting;
    return starting.whenComplete(() {
      if (identical(_starting, starting)) _starting = null;
    });
  }

  /// The process held for [key], if one is held and still in time: its whole
  /// connection — the handshake answered — with the transport, which is the
  /// caller's from here on, and that handshake's answer. Null when none is
  /// held for this key, the one held is out of time, or its process left.
  ThincoderWarmTake? take(ThincoderWarmKey key) {
    final held = _heldAt;
    final connection = _connection;
    final transport = _transport;
    final handshake = _handshake;
    if (_wanted != key ||
        held == null ||
        connection == null ||
        transport == null ||
        handshake == null) {
      return null;
    }
    if (_clock().difference(held) >= ttl) {
      drop('ttl');
      return null;
    }
    // Handed over whole: the kernel writes and listens from here on, and ends
    // the process with its own release — nothing of it stays held (D64).
    _forget(close: false);
    return (
      connection: connection,
      transport: transport,
      handshake: handshake,
    );
  }

  /// The process for [key] — held now, or one on its way for it, waited for
  /// no longer than [startup]: the session would pay that start itself.
  Future<ThincoderWarmTake?> takeWhenReady(ThincoderWarmKey key) async {
    if (_wanted == key && _heldAt == null) {
      if (_starting case final starting?) {
        await starting.timeout(startup, onTimeout: () {});
      }
    }
    return take(key);
  }

  /// Lets the held process go, saying why in the terminal's log: another
  /// project's, out of time, or a process that left (§25.2 / D104).
  void drop(String reason) {
    if (_wanted == null && _connection == null && _transport == null) return;
    _forget();
    appEvent('thincoder', 'warm: dropped $reason');
  }

  /// Keeps nothing more: the process ends, unless it was handed over.
  void _forget({bool close = true}) {
    _expiry?.cancel();
    _expiry = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    final connection = _connection;
    final transport = _transport;
    _connection = null;
    _transport = null;
    _handshake = null;
    _heldAt = null;
    _wanted = null;
    if (close) {
      connection?.close();
      transport?.close();
    }
  }

  /// Starts the process for [key] and answers its handshake: held on success,
  /// nothing kept on failure — no word to the user either way (D104).
  Future<void> _hold(ThincoderWarmKey key) async {
    ThincoderTransport? transport;
    try {
      transport = await _start(await _launchFor(key.$1)).timeout(startup);
      // Let go of while it started: it ends with what was asked of it.
      if (_wanted != key) {
        transport.close();
        return;
      }
      final connection = _connection = ThincoderConnection(transport.write);
      _subscription = transport.messages.listen((message) {
        // Taken, or let go of: what comes is the kernel's own to read.
        if (!identical(_connection, connection)) return;
        if (message['type'] == ThincoderExit.type) return drop('exited');
        connection.receive(message);
      });
      final answer = await connection.request('initialize', {
        'protocolVersion': 1,
        'clientCapabilities': key.$2
            ? ThincoderFiles.capabilities
            : const <String, Object?>{},
      });
      if (_wanted != key) {
        unawaited(_subscription?.cancel());
        _subscription = null;
        _connection = null;
        transport.close();
        return;
      }
      _transport = transport;
      _handshake = answer;
      _heldAt = _clock();
      _expiry = _schedule(ttl, () {
        if (_wanted == key && _heldAt != null) drop('ttl');
      });
      appEvent('thincoder', 'warm: held ${key.$1}');
    } on Object catch (error) {
      unawaited(_subscription?.cancel());
      _subscription = null;
      _connection = null;
      transport?.close();
      if (_wanted != key) return;
      _forget();
      _failed = (key, _clock());
      appEvent('thincoder', 'warm: dropped failed: $error');
    }
  }
}
