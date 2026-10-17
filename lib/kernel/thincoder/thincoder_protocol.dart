import 'dart:async';

import '../../platform/event_log.dart';

/// An error the agent side reported, or one about the connection itself.
class ThincoderRpcError implements Exception {
  const ThincoderRpcError(this.code, this.message, {this.data});

  final int code;
  final String message;
  final Object? data;

  /// Needs the user to set their credentials up (ACP's `-32000`).
  bool get authRequired => code == -32000;

  /// A parameter the agent does not take — a session it does not have
  /// (ACP's `-32602`).
  bool get gone => code == -32602;

  @override
  String toString() => 'JSON-RPC $code: $message';
}

/// A request the agent sent us, waiting on our answer: what the kernel
/// holds while the user decides on an approval.
class ThincoderRequest {
  ThincoderRequest(this.id, this.method, this.params, this._connection);

  /// The agent's own id, to answer under.
  final Object? id;
  final String method;
  final Map<String, Object?> params;
  final ThincoderConnection _connection;
  bool _answered = false;

  /// Whether an answer has gone out.
  bool get answered => _answered;

  /// Answers it with [result] (once; a later answer is ignored).
  void answer(Map<String, Object?> result) {
    if (_answered) return;
    _answered = true;
    _connection._respond(id, result);
  }

  /// Refuses it with an error (once).
  void refuse(int code, String message) {
    if (_answered) return;
    _answered = true;
    _connection._fail(id, code, message);
  }
}

/// The JSON-RPC connection over a transport: our requests and their
/// responses (matched by id), the agent's notifications, and its own
/// requests — answered by [onRequest], or refused as unknown so that the
/// agent never waits on us (E4: a fitting degradation, never a hang).
class ThincoderConnection {
  ThincoderConnection(
    this._write, {
    this.timeout = const Duration(seconds: 60),
  });

  final void Function(Map<String, Object?> message) _write;

  /// How long a request of ours waits for its answer, unless the caller
  /// says otherwise — or says not to be on a clock at all ([noTimeout]).
  final Duration timeout;

  /// The timeout that is no timeout: pass it to [request] for a request
  /// whose answer is to be waited for however long the agent takes.
  /// `session/prompt` is the one that must: its answer comes when the turn
  /// ends, and a turn has no upper bound (§3.4) — a finite limit there
  /// would call a long turn an unanswered one. Every other request keeps
  /// the connection's own [timeout].
  static const Duration noTimeout = Duration.zero;

  /// Handles a request from the agent; false means it is refused with
  /// `-32601` (the agent's own timeout is longer than that).
  bool Function(ThincoderRequest request)? onRequest;

  /// Handles a notification from the agent (`session/update`).
  void Function(String method, Map<String, Object?> params)? onNotification;

  /// Our requests' answers, by the id we sent.
  final Map<String, Completer<Map<String, Object?>>> _pending = {};
  int _next = 0;
  bool _closed = false;

  /// Sends a request of ours; completes with its result, and throws
  /// [ThincoderRpcError] on an error answer or a timeout.
  ///
  /// The answer is waited for [timeout] — the connection's [timeout] unless
  /// one is given here, and not on a clock at all if [noTimeout] is given:
  /// such a request ends with its answer, or with the connection going away
  /// ([failAll]).
  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?> params = const {},
    Duration? timeout,
  ]) {
    if (_closed) {
      return Future.error(
        ThincoderRpcError(-32603, '$method: the connection is closed'),
      );
    }
    final id = 'c${++_next}';
    final done = Completer<Map<String, Object?>>();
    _pending[id] = done;
    _write({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    if (timeout == noTimeout) return done.future;
    return done.future.timeout(
      timeout ?? this.timeout,
      onTimeout: () {
        _pending.remove(id);
        throw ThincoderRpcError(-32603, '$method got no answer');
      },
    );
  }

  /// Takes one message from the agent: its answer to one of ours, a
  /// notification, or a request of its own. Returns whether it was ours to
  /// take.
  bool receive(Map<String, Object?> message) {
    final method = message['method'];
    if (method is String) {
      final params =
          (message['params'] as Map?)?.cast<String, Object?>() ?? const {};
      if (message.containsKey('id')) {
        return _requested(message['id'], method, params);
      }
      onNotification?.call(method, params);
      return true;
    }
    final id = message['id'];
    if (id == null) {
      final error = (message['error'] as Map?)?.cast<String, Object?>();
      appEvent('thincoder', 'protocol error: ${error?['message'] ?? message}');
      return false;
    }
    final done = _pending.remove('$id');
    if (done == null) {
      appEvent('thincoder', 'an answer to no request of ours: id $id');
      return false;
    }
    final error = (message['error'] as Map?)?.cast<String, Object?>();
    if (error != null) {
      done.completeError(
        ThincoderRpcError(
          switch (error['code']) {
            final int code => code,
            final num code => code.toInt(),
            _ => -32603,
          },
          '${error['message'] ?? 'failed'}',
          data: error['data'],
        ),
      );
    } else {
      done.complete(
        (message['result'] as Map?)?.cast<String, Object?>() ?? const {},
      );
    }
    return true;
  }

  bool _requested(Object? id, String method, Map<String, Object?> params) {
    final request = ThincoderRequest(id, method, params, this);
    if (onRequest?.call(request) ?? false) return true;
    // E4 留痕: what the agent asked and we do not do, said in the log.
    appEvent('thincoder', 'refused unknown request $method (-32601)');
    request.refuse(-32601, 'Method not found');
    return true;
  }

  void _respond(Object? id, Map<String, Object?> result) => _write({
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  });

  void _fail(Object? id, int code, String message) => _write({
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  });

  /// Fails every request still waiting, e.g. the agent is gone.
  void failAll(String why) {
    final pending = [..._pending.entries];
    _pending.clear();
    for (final MapEntry(key: id, value: done) in pending) {
      done.completeError(ThincoderRpcError(-32603, '$id: $why'));
    }
  }

  /// No more requests: what is waiting fails.
  void close() {
    _closed = true;
    failAll('the connection is closed');
  }
}
