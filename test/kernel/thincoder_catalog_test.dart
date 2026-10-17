import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:baocode/kernel/thincoder/thincoder_catalog.dart';
import 'package:baocode/kernel/thincoder/thincoder_mock.dart';
import 'package:baocode/kernel/thincoder/thincoder_transport.dart';

/// A connection the test counts and traces.
class _Tracked implements ThincoderTransport {
  _Tracked(this.agent, this.onClose);

  final ThincoderMock agent;
  final void Function() onClose;

  @override
  Stream<Map<String, Object?>> get messages => agent.messages;

  @override
  void write(Map<String, Object?> message) => agent.write(message);

  @override
  Future<void> get exited => agent.exited;

  @override
  void close() {
    onClose();
    agent.close();
  }
}

/// A connection whose closing leaves the agent running — one machine, its
/// slots kept, a new connection per call (`ThincoderCatalog`'s D4 shape).
class _Kept implements ThincoderTransport {
  _Kept(this.agent);

  final ThincoderMock agent;

  @override
  Stream<Map<String, Object?>> get messages => agent.messages;

  @override
  void write(Map<String, Object?> message) => agent.write(message);

  @override
  Future<void> get exited => agent.exited;

  @override
  void close() {}
}

void main() {
  test('lists a folder\'s sessions, their ids carrying the folder (D5)',
      () async {
    final agent = ThincoderMock(
      cwd: '/p',
      slots: const [
        {
          'sessionId': '3',
          'updatedAt': '2026-10-15T09:30:00.000Z',
          'title': 'From the terminal',
        },
        {'sessionId': '1', 'updatedAt': '2026-10-14T11:00:00.000Z'},
      ],
    );
    final catalog = ThincoderCatalog(connect: (cwd) async => agent);

    final sessions = await catalog.sessionsIn('/p');
    expect(sessions.map((session) => session.id), ['/p|3', '/p|1']);
    expect(sessions.first.title, 'From the terminal');
    expect(sessions.last.title, '');
    expect(sessions.first.cwd, '/p');
    expect(sessions.first.updatedAt.isUtc, isFalse);
    expect(
      sessions.first.updatedAt,
      DateTime.utc(2026, 10, 15, 9, 30).toLocal(),
    );
    // The handshake first, one request, and nothing else.
    expect(agent.requests('initialize'), hasLength(1));
    expect(agent.requests('session/list').single['params'], isEmpty);
  });

  test('a session that does not say when it was written: the epoch', () async {
    final agent = ThincoderMock(cwd: '/p', slots: const [{'sessionId': '2'}]);
    final catalog = ThincoderCatalog(connect: (cwd) async => agent);
    final sessions = await catalog.sessionsIn('/p');
    expect(sessions.single.updatedAt, DateTime.fromMillisecondsSinceEpoch(0));
  });

  test('each call opens its own connection, and closes it', () async {
    var opened = 0;
    var closed = 0;
    final catalog = ThincoderCatalog(
      connect: (cwd) async {
        opened++;
        return _Tracked(ThincoderMock(cwd: cwd), () => closed++);
      },
    );
    await catalog.sessionsIn('/a');
    await catalog.sessionsIn('/b');
    expect(opened, 2);
    expect(closed, 2, reason: 'nothing stays running between refreshes (D4)');
  });

  test('one call at a time, however many are asked for', () async {
    var live = 0;
    var most = 0;
    final catalog = ThincoderCatalog(
      connect: (cwd) async {
        live++;
        most = math.max(most, live);
        return _Tracked(ThincoderMock(cwd: cwd), () => live--);
      },
    );
    await Future.wait([
      catalog.sessionsIn('/a'),
      catalog.sessionsIn('/b'),
      catalog.delete('/a|1'),
      catalog.sessionsIn('/c'),
    ]);
    expect(most, 1, reason: 'one process at a time (D6)');
    expect(live, 0);
  });

  test('deleting splits the id, asks for its slot, and it is listed no more',
      () async {
    // One agent across the calls, as a machine keeps its slots.
    final agent = ThincoderMock(cwd: '/p');
    final catalog = ThincoderCatalog(connect: (cwd) async => _Kept(agent));
    expect((await catalog.sessionsIn('/p')).map((s) => s.id), ['/p|3']);

    await catalog.delete('/p|3');
    expect(agent.requests('session/delete').single['params'], {
      'sessionId': '3',
    });
    expect(await catalog.sessionsIn('/p'), isEmpty);
  });

  test('deleting one that is gone does nothing', () async {
    // The agent answers -32602 for a slot it does not have
    // (`handlers-slots.mjs:209`): not an error to the host.
    final catalog = ThincoderCatalog(
      connect: (cwd) async => ThincoderMock(cwd: cwd),
    );
    await catalog.delete('/p|9');
    await catalog.delete('/p|9');
  });

  test('an id that is not one of ours opens nothing', () async {
    var opened = 0;
    final catalog = ThincoderCatalog(
      connect: (cwd) async {
        opened++;
        return ThincoderMock(cwd: cwd);
      },
    );
    await catalog.delete('aaaaaaaa-1111-4111-8111-111111111111');
    expect(opened, 0);
  });

  test('no projects of its own (D6)', () async {
    final catalog = ThincoderCatalog(connect: (_) async => ThincoderMock());
    expect(await catalog.projects(), isEmpty);
  });

  test('a call that cannot be made says so, and the next still works',
      () async {
    var first = true;
    final catalog = ThincoderCatalog(
      connect: (cwd) async {
        if (first) {
          first = false;
          throw const ThincoderUnavailable('thincoder is not installed');
        }
        return ThincoderMock(cwd: cwd);
      },
    );
    await expectLater(
      catalog.sessionsIn('/p'),
      throwsA(isA<ThincoderUnavailable>()),
    );
    expect(
      (await catalog.sessionsIn('/p')).map((session) => session.id),
      ['/p|3'],
      reason: 'the queue is not blocked by a call that failed',
    );
  });
}
