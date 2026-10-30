import 'dart:async';

import 'package:baocode/host_tools/host_tools.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which (folder, tool) pairs are offered, which (folder, feature) pairs are
/// told, and that a tool there may wait on the user (see [ClaudeSdkGate]).
final class _Gate implements ClaudeSdkGate {
  _Gate(this.offered, {this.told = const {}});

  final Set<(String, String)> offered;
  final Set<(String, String)> told;

  @override
  bool offersTool(String cwd, String tool) => offered.contains((cwd, tool));

  @override
  bool tellsFeature(String cwd, String feature) =>
      told.contains((cwd, feature));

  /// Always: these tests say nothing of who is asked.
  @override
  bool asksUser(String cwd) => true;
}

/// A tool that answers [answer], in [group] when one is given.
HostTool _tool(String name, {String group = '', Object answer = 'ok'}) =>
    HostTool(
      name: name,
      description: 'Says it back.',
      inputSchema: const {'type': 'object'},
      group: group,
      run: (input, call) async => answer,
    );

void main() {
  const call = HostToolCall(cwd: '/p', sessionId: 's');

  tearDown(() {
    for (final name in ['echo', 'browser_open', 'generate_image', 'unused']) {
      HostTools.unregister(name);
    }
  });

  test('no tools, no server', () {
    expect(HostTools.any, isFalse);
    expect(HostTools.servers, isEmpty);
  });

  test('a tool always loaded says so, not to be deferred', () async {
    HostTools.register(
      HostTool(
        name: 'echo',
        description: 'Says it back.',
        inputSchema: const {'type': 'object'},
        alwaysLoad: true,
        run: (input, call) async => '',
      ),
    );
    final list = await HostTools.handle({
      'id': 1,
      'method': 'tools/list',
    }, call);
    final tools = (list['result'] as Map)['tools'] as List;
    expect(tools.single, containsPair('_meta', {'anthropic/alwaysLoad': true}));
  });

  test('says its features\' instructions as it is initialized', () async {
    addTearDown(() {
      HostTools.instruct('a', null);
      HostTools.instruct('b', null);
    });
    Future<Map> init() async =>
        (await HostTools.handle({
              'id': 0,
              'method': 'initialize',
            }, call))['result']
            as Map;

    expect((await init()).containsKey('instructions'), isFalse);
    HostTools.instruct('a', 'Do A.');
    HostTools.instruct('b', 'Do B.');
    expect((await init())['instructions'], 'Do A.\n\nDo B.');
    HostTools.instruct('a', null);
    HostTools.instruct('b', null);
    expect((await init()).containsKey('instructions'), isFalse);
  });

  test('lists and calls its tools, failures as errors', () async {
    HostTools.register(
      HostTool(
        name: 'echo',
        description: 'Says it back.',
        inputSchema: const {'type': 'object'},
        run: (input, call) async {
          if (input['fail'] == true) throw StateError('no');
          return '${input['text']} in ${call.cwd}';
        },
      ),
    );
    expect(HostTools.servers, ['baocode']);

    final init = await HostTools.handle({
      'jsonrpc': '2.0',
      'id': 0,
      'method': 'initialize',
      'params': {'protocolVersion': '2025-06-18'},
    }, call);
    expect((init['result'] as Map)['protocolVersion'], '2025-06-18');

    final list = await HostTools.handle({
      'id': 1,
      'method': 'tools/list',
    }, call);
    final tools = (list['result'] as Map)['tools'] as List;
    expect(tools.single, containsPair('name', 'echo'));
    expect((tools.single as Map).containsKey('_meta'), isFalse);

    final ok = await HostTools.handle({
      'id': 2,
      'method': 'tools/call',
      'params': {
        'name': 'echo',
        'arguments': {'text': 'hi'},
      },
    }, call);
    expect(ok['id'], 2);
    expect(ok['result'], {
      'content': [
        {'type': 'text', 'text': 'hi in /p'},
      ],
    });

    final failed = await HostTools.handle({
      'id': 3,
      'method': 'tools/call',
      'params': {
        'name': 'echo',
        'arguments': {'fail': true},
      },
    }, call);
    expect((failed['result'] as Map)['isError'], isTrue);

    final unknown = await HostTools.handle({
      'id': 4,
      'method': 'resources/list',
    }, call);
    expect((unknown['error'] as Map)['code'], -32601);
  });

  test(
    'a call is given up as the agent cancels it, or as the turn stops',
    () async {
      HostTools.register(
        HostTool(
          name: 'echo',
          description: 'Waits.',
          inputSchema: const {'type': 'object'},
          run: (input, call) async {
            await call.cancelled;
            return 'given up';
          },
        ),
      );
      Future<String> answered(Future<Map<String, Object?>> answer) async =>
          (((await answer)['result'] as Map)['content'] as List).single['text']
              as String;

      final cancelled = HostTools.handle({
        'id': 7,
        'method': 'tools/call',
        'params': {'name': 'echo', 'arguments': <String, Object?>{}},
      }, call);
      // Another session's call of the same id is not this one.
      await HostTools.handle({
        'method': 'notifications/cancelled',
        'params': {'requestId': 7},
      }, const HostToolCall(cwd: '/p', sessionId: 'other'));
      await HostTools.handle({
        'method': 'notifications/cancelled',
        'params': {'requestId': 7},
      }, call);
      expect(await answered(cancelled), 'given up');

      final turn = Completer<void>();
      final stopped = HostTools.handle({
        'id': 8,
        'method': 'tools/call',
        'params': {'name': 'echo', 'arguments': <String, Object?>{}},
      }, HostToolCall(cwd: '/p', sessionId: 's', cancelled: turn.future));
      turn.complete();
      expect(await answered(stopped), 'given up');
    },
  );

  // T16: the Claude face answers as it did before the rename, field for
  // field (design A3).
  group('T16: the Claude face is unchanged', () {
    test('initialize answers every field as before', () async {
      final init = await HostTools.handle({
        'jsonrpc': '2.0',
        'id': 0,
        'method': 'initialize',
        'params': {'protocolVersion': '2024-11-05'},
      }, call);
      expect(init, {
        'jsonrpc': '2.0',
        'id': 0,
        'result': {
          'protocolVersion': '2024-11-05',
          'capabilities': {'tools': <String, Object?>{}},
          'serverInfo': {'name': 'baocode', 'version': '1.0.0'},
        },
      });
    });

    test(
      'initialize answers the protocol version it knows when given none',
      () async {
        final init = await HostTools.handle({
          'id': 0,
          'method': 'initialize',
        }, call);
        expect(init['result'], {
          'protocolVersion': '2024-11-05',
          'capabilities': {'tools': <String, Object?>{}},
          'serverInfo': {'name': 'baocode', 'version': '1.0.0'},
        });
      },
    );

    test('tools/list lists every tool, whatever its group', () async {
      HostTools.register(_tool('browser_open', group: 'browser'));
      HostTools.register(_tool('generate_image', group: 'images'));
      HostTools.register(_tool('unused'));

      final list = await HostTools.handle({
        'id': 1,
        'method': 'tools/list',
      }, call);
      expect((list['result'] as Map)['tools'], [
        for (final name in ['browser_open', 'generate_image', 'unused'])
          {
            'name': name,
            'description': 'Says it back.',
            'inputSchema': {'type': 'object'},
          },
      ]);
    });

    test('tools/call answers its content as before', () async {
      HostTools.register(_tool('echo', answer: 'hi in /p'));
      final ok = await HostTools.handle({
        'id': 2,
        'method': 'tools/call',
        'params': {'name': 'echo', 'arguments': <String, Object?>{}},
      }, call);
      expect(ok, {
        'jsonrpc': '2.0',
        'id': 2,
        'result': {
          'content': [
            {'type': 'text', 'text': 'hi in /p'},
          ],
        },
      });

      final missed = await HostTools.handle({
        'id': 3,
        'method': 'tools/call',
        'params': {'name': 'nope', 'arguments': <String, Object?>{}},
      }, call);
      expect(missed['result'], {
        'content': [
          {'type': 'text', 'text': 'No tool nope.'},
        ],
        'isError': true,
      });
    });

    test('an unknown method is refused as before', () async {
      final unknown = await HostTools.handle({
        'jsonrpc': '2.0',
        'id': 4,
        'method': 'resources/list',
      }, call);
      expect(unknown, {
        'jsonrpc': '2.0',
        'id': 4,
        'error': {
          'code': -32601,
          'message': 'Method not found: resources/list',
        },
      });
    });

    test('a cancellation is answered as before', () async {
      final done = await HostTools.handle({
        'id': 5,
        'method': 'notifications/cancelled',
        'params': {'requestId': 9},
      }, call);
      expect(done, {'jsonrpc': '2.0', 'id': 5, 'result': <String, Object?>{}});
    });

    test('called() answers the prefixed name alone', () {
      final tool = _tool('browser_open', group: 'browser');
      HostTools.register(tool);
      expect(HostTools.called('mcp__baocode__browser_open'), same(tool));
      expect(HostTools.called('browser_open'), isNull);
      expect(HostTools.called('mcp__other__browser_open'), isNull);
    });
  });

  test('groups: a server exposing one group alone gives only its tools', () {
    final browser = _tool('browser_open', group: 'browser');
    final images = _tool('generate_image', group: 'images');
    final loose = _tool('unused');
    for (final tool in [browser, images, loose]) {
      HostTools.register(tool);
    }

    expect(HostTools.byGroup('browser'), [browser]);
    expect(HostTools.byGroup('images'), [images]);
    expect(HostTools.byGroup('none'), isEmpty);

    expect(HostTools.anyIn({'browser'}), isTrue);
    expect(HostTools.anyIn({'images', 'browser'}), isTrue);
    expect(HostTools.anyIn({'none'}), isFalse);
    expect(HostTools.anyIn(const {}), isFalse);

    expect(HostTools.lookup('browser_open'), same(browser));
    expect(HostTools.lookup('nope'), isNull);
  });

  test('the gate: a folder is offered its tools alone, and told its features', () async {
    final browser = _tool('browser_open', group: 'browser');
    final images = _tool('generate_image', group: 'images');
    for (final tool in [browser, images]) {
      HostTools.register(tool);
    }
    HostTools.instruct('browser', 'Browse.');
    HostTools.instruct('images', 'Draw.');
    // One tool in `/p`, one feature told there (see [ClaudeSdkGate]).
    HostTools.gate = _Gate({('/p', 'browser_open')}, told: {('/p', 'browser')});
    addTearDown(() {
      HostTools.gate = null;
      HostTools.instruct('browser', null);
      HostTools.instruct('images', null);
    });

    expect(HostTools.offersTool('/p', 'browser_open'), isTrue);
    expect(HostTools.offersTool('/p', 'generate_image'), isFalse);
    expect(HostTools.offersTool('/elsewhere', 'browser_open'), isFalse);
    expect(HostTools.tellsFeature('/p', 'browser'), isTrue);
    expect(HostTools.tellsFeature('/p', 'images'), isFalse);

    expect(HostTools.serversFor('/p'), ['baocode']);
    expect(HostTools.serversFor('/nowhere'), isEmpty);

    final list = await HostTools.handle({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/list',
    }, call);
    expect([
      for (final tool in (list['result'] as Map)['tools'] as List)
        (tool as Map)['name'],
    ], ['browser_open']);

    final told = await HostTools.handle({
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'initialize',
    }, call);
    expect((told['result'] as Map)['instructions'], 'Browse.');

    // Refused, and said so as a tool this folder does not have.
    final refused = await HostTools.handle({
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'tools/call',
      'params': {
        'name': 'generate_image',
        'arguments': <String, Object?>{},
      },
    }, call);
    final result = refused['result'] as Map;
    expect(result['isError'], isTrue);
    expect(((result['content'] as List).single as Map)['text'], 'No tool generate_image.');
  });
}
