// The app's own tools as an MCP server on the machine itself: the ACP
// branch of the host tool channel (design host-tool-channel §4-§5).
//
// Claude Code reaches the same tools through its control channel
// ([HostTools.handle]); a kernel that takes MCP servers over ACP is given
// this server's loopback URL and a token of its own, and calls it over
// HTTP. One registry, one executor, two transports.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../platform/event_log.dart';
import 'host_tools.dart';

/// A session's leave to call the app's tools: its token, the folder its
/// calls run in, and the session they belong to.
class _Grant {
  const _Grant(this.token, this.sessionId, this.cwd);

  final String token;
  final String sessionId;
  final String cwd;
}

/// The app's tools, for ACP agents: a Streamable HTTP MCP endpoint on
/// 127.0.0.1, a token to a session, and the registry's own
/// [HostTools.handle] behind it — the groups [exposedGroups] alone, without
/// the tools whose answer is pictures (D8).
abstract final class HostMcpServer {
  /// The groups given over MCP: the whitelist, this batch the browser's
  /// alone. Empty rolls the channel back: no tool is offered and none runs
  /// (§14), and a later session is given no server at all.
  static Set<String> exposedGroups = {'browser'};

  /// Beyond this a request body is refused (413).
  static const maxBodyBytes = 1 << 20;

  /// What a browser tool's call is refused with once its group is no longer
  /// exposed (F3: said, never pretended).
  static const off = "BaoCode's browser tools are off (Settings → Browser).";

  static const _path = '/mcp';

  static HttpServer? _server;
  static Future<String?>? _starting;

  /// The grants in force, by their token: a session's leave ends when it is
  /// revoked (its teardown), or with the process.
  static final Map<String, _Grant> _grants = {};

  /// The tools given over the wire, by name and group: one called after
  /// its feature took it away (the browser's switch, §5.2) is refused as
  /// off, not as unknown.
  static final Map<String, String> _given = {};

  /// How many tokens were taken back: what a test reads a teardown by.
  @visibleForTesting
  static int revocations = 0;

  static final _random = Random.secure();

  /// The endpoint, once up.
  static String? get url => switch (_server) {
    final server? => 'http://127.0.0.1:${server.port}$_path',
    null => null,
  };

  /// Starts the endpoint, if it is not up: its URL; null when it could not
  /// start — one line in the app's log, and the session goes on without it
  /// (§5.1).
  static Future<String?> ensure() {
    if (_server != null) return Future.value(url);
    return _starting ??= _bind().whenComplete(() => _starting = null);
  }

  static Future<String?> _bind() async {
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      server.listen((request) => unawaited(_serve(request)));
      return url;
    } on Object catch (error) {
      appEvent('thincoder', 'the host tools server did not start: $error');
      return null;
    }
  }

  /// Gives [token]'s grant the [sessionId] its session got: its calls are
  /// keyed by it, where session/new's grant went out with the empty one
  /// (two of those could collide on a request id).
  static void rebind(String token, String sessionId) {
    final grant = _grants[token];
    if (grant == null || sessionId.isEmpty) return;
    _grants[token] = _Grant(token, sessionId, grant.cwd);
  }

  /// A token for [sessionId] (its calls run in [cwd]), and the entry an ACP
  /// session request gives its agent; null while the endpoint is not up.
  /// One a request: a new leave each time a session starts.
  static ({String token, Map<String, Object?> server})? issue(
    String sessionId,
    String cwd,
  ) {
    final endpoint = url;
    if (endpoint == null) return null;
    final token = _token();
    _grants[token] = _Grant(token, sessionId, cwd);
    return (
      token: token,
      server: {
        'type': 'http',
        'name': HostTools.server,
        'url': endpoint,
        'headers': [
          {'name': 'Authorization', 'value': 'Bearer $token'},
        ],
        // This server is the client's own (D5): the end that sent the
        // request, on the loopback.
        '_meta': {'baocode.dev/trusted': true},
      },
    );
  }

  /// Takes a session's leave back: its token answers 401 from here on.
  static void revoke(String token) {
    if (_grants.remove(token) != null) revocations++;
  }

  /// Closes the endpoint: a test's, after its sessions. The app sets no
  /// exit hook — the process's end takes the socket with it (D7).
  @visibleForTesting
  static Future<void> shutdown() async {
    final server = _server;
    _server = null;
    _starting = null;
    _grants.clear();
    _given.clear();
    await server?.close(force: true);
  }

  /// 32 random bytes, base64url without its padding: 43 characters, in no
  /// file and in no URL (D6).
  static String _token() {
    final bytes = Uint8List(32);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.uri.path != _path) {
        return await _empty(response, HttpStatus.notFound);
      }
      // What the client's GET is answered with: 405, which is how it knows
      // to stay on POST alone.
      if (request.method != 'POST') {
        return await _empty(response, HttpStatus.methodNotAllowed);
      }
      final grant = _grantOf(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      if (grant == null) {
        response.headers.set(HttpHeaders.wwwAuthenticateHeader, 'Bearer');
        return await _empty(response, HttpStatus.unauthorized);
      }
      final body = await _read(request);
      if (body == null) {
        return await _empty(response, HttpStatus.requestEntityTooLarge);
      }
      final Object? message;
      try {
        message = jsonDecode(utf8.decode(body));
      } on FormatException {
        return await _send(response, _parseError());
      }
      if (message is! Map) return await _send(response, _parseError());
      final decoded = message.cast<String, Object?>();
      final call = HostToolCall(cwd: grant.cwd, sessionId: grant.sessionId);
      if (decoded['method'] case final String method
          when method.startsWith('notifications/')) {
        // The one with something to do here (§4.6): a call under way is
        // given up; the rest are acknowledged alone.
        if (method == 'notifications/cancelled') {
          await HostTools.handle(decoded, call);
        }
        return await _empty(response, HttpStatus.accepted);
      }
      await _send(response, await _answer(decoded, call));
    } on Object catch (error) {
      appEvent('thincoder', 'a host tools request failed: $error');
      try {
        await _empty(response, HttpStatus.internalServerError);
      } on Object {
        // The client left, or the answer was already on its way.
      }
    }
  }

  static _Grant? _grantOf(String? header) {
    if (header == null || !header.startsWith('Bearer ')) return null;
    return _grants[header.substring('Bearer '.length)];
  }

  /// The request's body, or null when it is over [maxBodyBytes]. The rest
  /// is read too, so the client is answered rather than reset.
  static Future<Uint8List?> _read(HttpRequest request) async {
    final bytes = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in request) {
      length += chunk.length;
      if (length <= maxBodyBytes) bytes.add(chunk);
    }
    return length > maxBodyBytes ? null : bytes.takeBytes();
  }

  static Future<Map<String, Object?>> _answer(
    Map<String, Object?> message,
    HostToolCall call,
  ) async {
    final id = message['id'];
    final method = message['method'];
    final params = message['params'];
    if (params != null && params is! Map) {
      return _invalidParams(id);
    }
    if (method == 'ping') {
      return {'jsonrpc': '2.0', 'id': id ?? 0, 'result': <String, Object?>{}};
    }
    switch (method) {
      case 'tools/list':
        final answer = await HostTools.handle(message, call);
        final result = answer['result'];
        if (result is Map) {
          final tools = <Map>[];
          for (final tool in result['tools'] as List? ?? const []) {
            if (tool is! Map || !_offered(tool['name'])) continue;
            final name = '${tool['name']}';
            _given[name] = HostTools.lookup(name)?.group ?? '';
            tools.add(tool);
          }
          result['tools'] = tools;
        }
        return answer;
      case 'tools/call':
        final name = switch (params) {
          final Map params => params['name'],
          _ => null,
        };
        if (name is! String) return _invalidParams(id);
        final tool = HostTools.lookup(name);
        if (tool != null && !_offered(name)) {
          return _isError(
            id,
            tool.picturesOnly || tool.group != 'browser'
                ? 'No tool $name.'
                : off,
          );
        }
        // Given to this session once, and taken away since (§5.2).
        if (tool == null && _given[name] == 'browser') {
          return _isError(id, off);
        }
        final answer = await HostTools.handle(message, call);
        _foldPictures(answer);
        return answer;
      default:
        return HostTools.handle(message, call);
    }
  }

  /// Whether [name] is one the endpoint offers: in an exposed group, and
  /// not a tool whose answer is pictures alone.
  static bool _offered(Object? name) =>
      switch (name is String ? HostTools.lookup(name) : null) {
        final tool? => !tool.picturesOnly && exposedGroups.contains(tool.group),
        null => false,
      };

  static Map<String, Object?> _parseError() => {
    'jsonrpc': '2.0',
    'id': null,
    'error': {'code': -32700, 'message': 'Parse error'},
  };

  static Map<String, Object?> _invalidParams(Object? id) => {
    'jsonrpc': '2.0',
    'id': id ?? 0,
    'error': {'code': -32602, 'message': 'Invalid params'},
  };

  static Map<String, Object?> _isError(Object? id, String text) => {
    'jsonrpc': '2.0',
    'id': id ?? 0,
    'result': {
      'content': [claudeSdkText(text)],
      'isError': true,
    },
  };

  /// The pictures of an answer, as a line of text: the ACP transport's
  /// client cannot carry an image block to its model (D8, §12-1).
  static void _foldPictures(Map<String, Object?> answer) {
    final result = answer['result'];
    if (result is! Map) return;
    final content = result['content'];
    if (content is! List) return;
    result['content'] = [
      for (final block in content)
        if (block is Map && block['type'] == 'image')
          claudeSdkText('[A picture, which the user sees in the conversation.]')
        else
          block,
    ];
  }

  static Future<void> _empty(HttpResponse response, int status) async {
    response.statusCode = status;
    await response.close();
  }

  static Future<void> _send(
    HttpResponse response,
    Map<String, Object?> body,
  ) async {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }
}
