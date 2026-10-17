import 'dart:async';

import '../agent_kernel.dart';
import 'thincoder_locator.dart';
import 'thincoder_process.dart';
import 'thincoder_protocol.dart';
import 'thincoder_session_ref.dart';
import 'thincoder_transport.dart';

/// Opens a connection in [cwd] for one call, and closes it with the
/// transport; the real one starts `thincoder acp` there.
typedef ThincoderConnector = Future<ThincoderTransport> Function(String cwd);

/// The sessions thincoder keeps (F2): the same slots in the same folder
/// the user's terminal has, listed with `session/list`.
///
/// A slot belongs to the process's own folder (its single cwd), so listing
/// one project means opening a connection there, asking, and closing it
/// again: nothing stays running between refreshes (D4). One call at a
/// time: a refresh asks for each project, and a process each at once is
/// what D6 refused.
class ThincoderCatalog implements SessionCatalog {
  ThincoderCatalog({ThincoderConnector? connect}) : _connect = connect ?? _start;

  final ThincoderConnector _connect;

  static Future<ThincoderTransport> _start(String cwd) async =>
      startThincoderProcess(await ThincoderLocator.launch(cwd));

  /// What is running now, and what follows it.
  Future<void> _queue = Future.value();

  /// No projects of its own (D6): the protocol lists one folder's sessions,
  /// and the host asks for each of its projects in turn.
  @override
  Future<List<ProjectRecord>> projects() async => const <ProjectRecord>[];

  @override
  Future<List<SessionRecord>> sessionsIn(String cwd) => _serial(() async {
    final brief = await _open(cwd);
    try {
      final answer = await brief.connection.request('session/list');
      return [
        for (final session in answer['sessions'] as List? ?? const [])
          if (session is Map) _record(session.cast<String, Object?>(), cwd),
      ];
    } finally {
      await brief.close();
    }
  });

  @override
  Future<void> delete(String id) {
    final ref = ThincoderSessionRef.split(id);
    // Not an id of ours: nothing to delete.
    if (ref == null) return Future.value();
    final (cwd, slot) = ref;
    return _serial(() async {
      final brief = await _open(cwd);
      try {
        await brief.connection.request('session/delete', {'sessionId': slot});
      } on ThincoderRpcError catch (error) {
        // One that is gone (or never was): nothing to do.
        if (error.code != -32602) rethrow;
      } finally {
        await brief.close();
      }
    });
  }

  /// A short-lived connection to [cwd], its handshake made: what a call of
  /// the session family needs.
  Future<_BriefConnection> _open(String cwd) async {
    final transport = await _connect(cwd);
    final connection = ThincoderConnection(transport.write);
    final subscription = transport.messages.listen(connection.receive);
    try {
      await connection.request('initialize', {
        'protocolVersion': 1,
        'clientCapabilities': <String, Object?>{},
      });
    } on Object {
      await subscription.cancel();
      transport.close();
      rethrow;
    }
    return _BriefConnection(connection, subscription, transport);
  }

  /// One at a time, in the order asked.
  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _queue.then((_) => work());
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  /// [session] as the host keeps it: its id the project's and the slot's
  /// together (D5: slots are numbered per project).
  static SessionRecord _record(Map<String, Object?> session, String cwd) =>
      SessionRecord(
        id: ThincoderSessionRef.combine(cwd, '${session['sessionId']}'),
        title: '${session['title'] ?? ''}',
        updatedAt: _timeOf(session['updatedAt']),
        cwd: cwd,
      );

  /// When the agent says the session was last written; the epoch when it
  /// does not say (an old slot may carry no time).
  static DateTime _timeOf(Object? updatedAt) => switch (updatedAt) {
    final String text => DateTime.tryParse(text)?.toLocal() ?? _unknown,
    _ => _unknown,
  };

  static final _unknown = DateTime.fromMillisecondsSinceEpoch(0);
}

/// A connection opened for one call, and everything that goes with it.
class _BriefConnection {
  _BriefConnection(this.connection, this.subscription, this.transport);

  final ThincoderConnection connection;
  final StreamSubscription<Map<String, Object?>> subscription;
  final ThincoderTransport transport;

  /// Lets the agent's answers and notifications go, and ends the process.
  Future<void> close() async {
    await subscription.cancel();
    transport.close();
  }
}
