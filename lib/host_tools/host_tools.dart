// Tools of the app's own that an agent can call: an MCP server that lives
// in the app rather than in a process of its own. Claude Code is told of
// it at launch (`--mcp-config`, type `sdk`) and as it is initialized
// (`sdkMcpServers`), and sends what it says to it as control requests
// (`mcp_message`), whose answers go back the same way.
//
// The registry belongs to the app, not to one kernel: its name says what
// it is, so the same tools serve every kernel that reaches them.

import 'dart:async';

import '../kernel/claude_code/claude_sdk_tools.dart';

export '../kernel/claude_code/claude_sdk_tools.dart'
    show
        ClaudeSdkTool,
        ClaudeSdkCall,
        claudeSdkImage,
        claudeSdkText,
        ClaudeSdkGate;

typedef HostTool = ClaudeSdkTool;
typedef HostToolCall = ClaudeSdkCall;

/// The app's server and its tools (registered as their features start).
abstract final class HostTools {
  /// The server's name: its tools are `mcp__baocode__<name>` to the agent.
  static const server = 'baocode';

  static final Map<String, HostTool> _tools = {};

  /// The calls under way, by their session and request's id (each
  /// session counts its own): to cancel them.
  static final Map<(String?, Object), Completer<void>> _calls = {};

  static void register(HostTool tool) => _tools[tool.name] = tool;

  static void unregister(String name) => _tools.remove(name);

  /// The tools in [group], in the order they were registered: what a
  /// server exposing that group alone gives.
  static List<HostTool> byGroup(String group) => [
    for (final tool in _tools.values)
      if (tool.group == group) tool,
  ];

  /// Whether any tool is in one of [groups]: a server exposing those has
  /// something to give.
  static bool anyIn(Set<String> groups) =>
      _tools.values.any((tool) => groups.contains(tool.group));

  /// The tool [name], as the registry keys it (no `mcp__baocode__`
  /// prefix): a call's card, from the tool it answers.
  static HostTool? lookup(String name) => _tools[name];

  /// What each feature tells the agent of its tools, by feature: the
  /// server's instructions, in the agent's system prompt.
  static final Map<String, String> _instructions = {};

  /// Has the server tell the agent [text] for [feature]; null takes it
  /// back.
  static void instruct(String feature, String? text) => text == null
      ? _instructions.remove(feature)
      : _instructions[feature] = text;

  /// Which tools, by name, an agent working in a folder is offered, and
  /// which features' instructions it is told (see [ClaudeSdkGate]); all of
  /// them when null.
  static ClaudeSdkGate? gate;

  /// Whether [tool] is offered an agent working in [cwd]: the gate's say,
  /// or every tool's when there is none.
  static bool offersTool(String cwd, String tool) =>
      gate?.offersTool(cwd, tool) ?? true;

  /// Whether what [feature] tells of its tools is told an agent working in
  /// [cwd]: the gate's say, or all of it when there is none.
  static bool tellsFeature(String cwd, String feature) =>
      gate?.tellsFeature(cwd, feature) ?? true;

  /// The tool an agent calls [name] (`mcp__baocode__<name>`), if one of
  /// this server's.
  static HostTool? called(String name) {
    const prefix = 'mcp__${server}__';
    return name.startsWith(prefix)
        ? _tools[name.substring(prefix.length)]
        : null;
  }

  /// The tool an ACP agent names [name] (`baocode_<name>`), if one of this
  /// server's: the MCP face's naming.
  static HostTool? named(String name) => name.startsWith('${server}_')
      ? _tools[name.substring(server.length + 1)]
      : null;

  /// Whether there is any tool: the server is only given then.
  static bool get any => _tools.isNotEmpty;

  /// The servers to launch Claude Code with: this one, if it has tools.
  static List<String> get servers => any ? const [server] : const [];

  /// The servers to launch an agent working in [cwd] with: this one, if it
  /// offers that agent a tool.
  static List<String> serversFor(String cwd) =>
      _tools.keys.any((name) => offersTool(cwd, name))
      ? const [server]
      : const [];

  /// The answer to [message] (JSON-RPC) for the server.
  static Future<Map<String, Object?>> handle(
    Map<String, Object?> message,
    HostToolCall call,
  ) async {
    final id = message['id'];
    final params = (message['params'] as Map?)?.cast<String, Object?>() ?? {};
    Map<String, Object?> result(Map<String, Object?> result) => {
      'jsonrpc': '2.0',
      'id': id ?? 0,
      'result': result,
    };
    switch (message['method']) {
      case 'initialize':
        final told = [
          for (final MapEntry(key: feature, value: text)
              in _instructions.entries)
            if (tellsFeature(call.cwd, feature)) text,
        ];
        return result({
          'protocolVersion': params['protocolVersion'] ?? '2024-11-05',
          'capabilities': {'tools': <String, Object?>{}},
          'serverInfo': {'name': server, 'version': '1.0.0'},
          if (told.isNotEmpty) 'instructions': told.join('\n\n'),
        });
      case 'tools/list':
        return result({
          'tools': [
            for (final tool in _tools.values)
              if (offersTool(call.cwd, tool.name))
                {
                  'name': tool.name,
                  'description': tool.description,
                  'inputSchema': tool.inputSchema,
                  if (tool.alwaysLoad) '_meta': {'anthropic/alwaysLoad': true},
                },
          ],
        });
      case 'tools/call':
        final tool = switch (params['name']) {
          final String name when offersTool(call.cwd, name) => _tools[name],
          _ => null,
        };
        final input =
            (params['arguments'] as Map?)?.cast<String, Object?>() ?? {};
        if (tool == null) {
          return result({
            'content': [
              {'type': 'text', 'text': 'No tool ${params['name']}.'},
            ],
            'isError': true,
          });
        }
        // Given up as the turn stops, or as the agent says.
        final cancel = Completer<void>();
        final key = (call.sessionId, id ?? cancel);
        _calls[key] = cancel;
        unawaited(
          call.cancelled?.then((_) {
            if (!cancel.isCompleted) cancel.complete();
          }),
        );
        try {
          final answer = await tool.run(
            input,
            HostToolCall(
              cwd: call.cwd,
              sessionId: call.sessionId,
              cancelled: cancel.future,
              toolUseId: switch (params['_meta']) {
                {'claudecode/toolUseId': final String id} => id,
                _ => null,
              },
            ),
          );
          return result({
            'content': switch (answer) {
              final List<Object?> blocks => blocks,
              _ => [claudeSdkText('$answer')],
            },
          });
        } on Object catch (error) {
          return result({
            'content': [
              {'type': 'text', 'text': '$error'},
            ],
            'isError': true,
          });
        } finally {
          if (_calls[key] == cancel) _calls.remove(key);
        }
      case 'notifications/cancelled':
        if (_calls.remove((call.sessionId, params['requestId']))
            case final cancel? when !cancel.isCompleted) {
          cancel.complete();
        }
        return result({});
      case final String method when method.startsWith('notifications/'):
        return result({});
      default:
        return {
          'jsonrpc': '2.0',
          'id': id ?? 0,
          'error': {
            'code': -32601,
            'message': 'Method not found: ${message['method']}',
          },
        };
    }
  }
}
