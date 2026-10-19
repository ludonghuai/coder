import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:baocode/browser/browser_bridge.dart' show BrowserError;
import 'package:baocode/host_tools/host_mcp_server.dart';
import 'package:baocode/host_tools/host_tools.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tool the endpoint gives, in [group] (a browser tool's by default).
HostTool _tool(
  String name, {
  String group = 'browser',
  bool picturesOnly = false,
  Object answer = 'ok',
  Future<Object> Function(Map<String, Object?> input)? run,
}) => HostTool(
  name: name,
  description: 'A tool: $name.',
  inputSchema: const {'type': 'object'},
  group: group,
  picturesOnly: picturesOnly,
  run: (input, call) async => run == null ? answer : await run(input),
);

void main() {
  late String url;
  late String sessionToken;

  /// The tools registered by the test, taken out after it.
  final registered = <String>[];

  void register(HostTool tool) {
    HostTools.register(tool);
    registered.add(tool.name);
  }

  /// Calls [path] with [token] (the session's when none is named; the
  /// empty string sends none at all).
  Future<({int status, String body, String? challenge})> call({
    String? token,
    Object? message,
    String text = '',
    String method = 'POST',
    String path = '/mcp',
    List<int>? bytes,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:${Uri.parse(url).port}$path'),
      );
      final bearer = token ?? sessionToken;
      if (bearer.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      }
      final body =
          bytes ?? utf8.encode(message == null ? text : jsonEncode(message));
      request.headers.contentType = ContentType.json;
      request.contentLength = body.length;
      request.add(body);
      final response = await request.close();
      return (
        status: response.statusCode,
        body: await utf8.decoder.bind(response).join(),
        challenge: response.headers.value(HttpHeaders.wwwAuthenticateHeader),
      );
    } finally {
      client.close(force: true);
    }
  }

  Map<String, Object?> bodyOf(
    ({int status, String body, String? challenge}) response,
  ) => (jsonDecode(response.body) as Map).cast<String, Object?>();

  Map<String, Object?> rpc(
    Object id,
    String method, [
    Map<String, Object?>? params,
  ]) => {'jsonrpc': '2.0', 'id': id, 'method': method, 'params': ?params};

  setUp(() async {
    // The test binding answers every request of its own with 400: this
    // endpoint is on the machine itself.
    HttpOverrides.global = null;
    await HostMcpServer.shutdown();
    HostMcpServer.exposedGroups = {'browser'};
    url = (await HostMcpServer.ensure())!;
    sessionToken = HostMcpServer.issue('s1', '/project')!.token;
  });

  tearDown(() async {
    await HostMcpServer.shutdown();
    HostMcpServer.exposedGroups = {'browser'};
    HostTools.instruct('browser', null);
    for (final name in registered) {
      HostTools.unregister(name);
    }
    registered.clear();
  });

  test('T1: the token is the door — none, a wrong one, and the wrong '
      'door are all turned away', () async {
    final none = await call(token: '');
    expect(none.status, 401);
    // It says what it wants, and says nothing more.
    expect(none.challenge, 'Bearer');
    expect(none.body, isEmpty);
    expect((await call(token: 'not a token')).status, 401);
    // The client's GET: 405 is how it learns to stay on POST.
    expect((await call(method: 'GET')).status, 405);
    expect((await call(path: '/other')).status, 404);
    // With the session's token it answers.
    expect((await call(message: rpc(0, 'ping'))).status, 200);
  });

  test('T2: the handshake answers the protocol it was asked, its tools and '
      "the browser group's instructions", () async {
    register(_tool('browser_open'));
    HostTools.instruct('browser', 'Only the tabs shared with BaoCode.');

    final reply = bodyOf(
      await call(
        message: rpc(0, 'initialize', {
          'protocolVersion': '2024-11-05',
          'capabilities': <String, Object?>{},
          'clientInfo': {'name': 'thincoder', 'version': '0.13.0'},
        }),
      ),
    );
    final result = reply['result'] as Map;
    expect(result['protocolVersion'], '2024-11-05');
    expect((result['capabilities'] as Map).containsKey('tools'), isTrue);
    expect((result['serverInfo'] as Map)['name'], 'baocode');
    expect('${result['instructions']}', contains('Only the tabs shared'));
  });

  test('T3: only the exposed group is listed, and not the pictures-only '
      'tool', () async {
    register(_tool('browser_open'));
    register(_tool('browser_screenshot', picturesOnly: true));
    register(_tool('generate_image', group: 'images'));

    final reply = bodyOf(await call(message: rpc(1, 'tools/list')));
    final tools = ((reply['result'] as Map)['tools'] as List).cast<Map>();
    expect([for (final tool in tools) tool['name']], ['browser_open']);
  });

  test('T4: a call answers with the text it gave', () async {
    register(_tool('browser_open', answer: 'Tab [12] Example — '));
    final reply = bodyOf(
      await call(
        message: rpc(2, 'tools/call', {
          'name': 'browser_open',
          'arguments': {'url': 'https://example.com'},
        }),
      ),
    );
    expect(reply['result'], {
      'content': [
        {'type': 'text', 'text': 'Tab [12] Example — '},
      ],
    });
    expect((reply['result'] as Map).containsKey('isError'), isFalse);
  });

  test(
    'T5: a tool that throws is answered as failed, with what it said',
    () async {
      register(
        _tool(
          'browser_open',
          run: (_) async =>
              throw const BrowserError('No browser is connected: install it.'),
        ),
      );
      final reply = bodyOf(
        await call(
          message: rpc(3, 'tools/call', {
            'name': 'browser_open',
            'arguments': <String, Object?>{},
          }),
        ),
      );
      expect(reply['result'], {
        'content': [
          {'type': 'text', 'text': 'No browser is connected: install it.'},
        ],
        'isError': true,
      });
    },
  );

  test('T6: a tool it does not have is answered as failed', () async {
    final reply = bodyOf(
      await call(
        message: rpc(4, 'tools/call', {
          'name': 'nope',
          'arguments': <String, Object?>{},
        }),
      ),
    );
    expect(reply['result'], {
      'content': [
        {'type': 'text', 'text': 'No tool nope.'},
      ],
      'isError': true,
    });
  });

  test('T7: a picture is folded into a line of text', () async {
    register(
      _tool(
        'browser_open',
        answer: [claudeSdkText('Shot:'), claudeSdkImage('aGk=', 'image/png')],
      ),
    );
    final reply = bodyOf(
      await call(
        message: rpc(5, 'tools/call', {
          'name': 'browser_open',
          'arguments': <String, Object?>{},
        }),
      ),
    );
    final content = ((reply['result'] as Map)['content'] as List).cast<Map>();
    expect(content, hasLength(2));
    expect(content.map((block) => block['type']), ['text', 'text']);
    expect(content.last['text'], isNotEmpty);
  });

  test('T8: a group taken out of the exposed set is neither listed nor '
      'called', () async {
    register(_tool('browser_open'));
    // The session lists it first: what it was given is known.
    expect(
      ((bodyOf(await call(message: rpc(6, 'tools/list')))['result']
              as Map)['tools'] as List)
          .map((tool) => (tool as Map)['name']),
      ['browser_open'],
    );
    HostMcpServer.exposedGroups = {};

    final list = bodyOf(await call(message: rpc(7, 'tools/list')));
    expect((list['result'] as Map)['tools'], isEmpty);

    final called = bodyOf(
      await call(
        message: rpc(8, 'tools/call', {
          'name': 'browser_open',
          'arguments': <String, Object?>{},
        }),
      ),
    );
    expect(called['result'], {
      'content': [
        {'type': 'text', 'text': HostMcpServer.off},
      ],
      'isError': true,
    });

    // The switch itself (§5.2): the tools leave the registry once a
    // session has them — a call of one is refused as off, not as unknown.
    HostMcpServer.exposedGroups = {'browser'};
    HostTools.unregister('browser_open');
    final stale = bodyOf(
      await call(
        message: rpc(9, 'tools/call', {
          'name': 'browser_open',
          'arguments': <String, Object?>{},
        }),
      ),
    );
    expect(stale['result'], {
      'content': [
        {'type': 'text', 'text': HostMcpServer.off},
      ],
      'isError': true,
    });
  });

  test('T9: a token taken back is turned away', () async {
    HostMcpServer.revoke(sessionToken);
    expect((await call(message: rpc(8, 'tools/list'))).status, 401);
  });

  test('T10: broken JSON and an unknown method are protocol errors', () async {
    final broken = await call(text: '{"jsonrpc": "2.0", "id": 1');
    expect(broken.status, 200);
    expect((bodyOf(broken)['error'] as Map)['code'], -32700);

    final unknown = bodyOf(await call(message: rpc(9, 'resources/list')));
    expect(unknown['error'], {
      'code': -32601,
      'message': 'Method not found: resources/list',
    });
  });

  test('T10②: a cancellation gives up the call under way', () async {
    final begun = Completer<void>();
    register(
      HostTool(
        name: 'browser_open',
        description: 'Waits.',
        inputSchema: const {'type': 'object'},
        group: 'browser',
        run: (input, call) async {
          begun.complete();
          await call.cancelled;
          return 'given up';
        },
      ),
    );
    final answer = call(
      message: rpc(11, 'tools/call', {
        'name': 'browser_open',
        'arguments': <String, Object?>{},
      }),
    );
    await begun.future;
    final cancelled = await call(
      message: {
        'jsonrpc': '2.0',
        'method': 'notifications/cancelled',
        'params': {'requestId': 11},
      },
    );
    expect(cancelled.status, 202);
    final reply = bodyOf(await answer);
    expect(((reply['result'] as Map)['content'] as List).single, {
      'type': 'text',
      'text': 'given up',
    });
  });

  test('T17: a body over a megabyte is refused', () async {
    final body = utf8.encode(
      '{"jsonrpc":"2.0","id":1,"method":"ping","x":"'
      '${'a' * HostMcpServer.maxBodyBytes}"}',
    );
    final reply = await call(bytes: body);
    expect(reply.status, 413);
  });

  test('T18: a heartbeat is answered', () async {
    final reply = bodyOf(await call(message: rpc(10, 'ping')));
    expect(reply['id'], 10);
    expect(reply['result'], isEmpty);
  });
}
