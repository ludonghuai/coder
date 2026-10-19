// Tools of the app's own that an agent can call: an MCP server that lives
// in the app rather than in a process of its own. Claude Code is told of
// it at launch (`--mcp-config`, type `sdk`) and as it is initialized
// (`sdkMcpServers`), and sends what it says to it as control requests
// (`mcp_message`), whose answers go back the same way.
//
// The registry belongs to the app, not to one kernel: its name says what
// it is, so the same tools serve every kernel that reaches them.

import 'dart:async';

import '../chat/chat_models.dart' show ToolCallItem, ToolKind;

/// Where a tool is called from: the agent's working directory (its
/// project's path, as the workspace has it) and its session.
class HostToolCall {
  const HostToolCall({
    required this.cwd,
    this.sessionId,
    this.cancelled,
    this.toolUseId,
  });

  final String cwd;
  final String? sessionId;

  /// The tool use it answers, as Claude Code says (`_meta`'s
  /// `claudecode/toolUseId`): its step's in the conversation
  /// ([ToolCallItem.callId]).
  final String? toolUseId;

  /// Completes once the call is given up: the turn stopped, or the agent
  /// cancelled it. A tool that waits long (on the user, say) stops then.
  final Future<void>? cancelled;
}

/// One tool: its name, what it does and the JSON schema of its input, for
/// the model; [run] answers a call with text, or MCP content blocks (a
/// list of them: text, an image), or throws to say it failed.
class HostTool {
  const HostTool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.run,
    this.kind,
    this.summary,
    this.files,
    this.alwaysLoad = false,
    this.group = '',
    this.picturesOnly = false,
  });

  final String name;
  final String description;
  final Map<String, Object?> inputSchema;
  final Future<Object> Function(Map<String, Object?> input, HostToolCall call)
  run;

  /// The step a call is in the conversation; else any MCP tool's.
  final ToolKind? kind;

  /// What a call is about, in a few words, from its input and (once
  /// answered) what it answered: the step's line, when the agent did not
  /// say it (an input's `description`, as Bash's).
  final String Function(Map<String, Object?> input, String? output)? summary;

  /// The files its pictures were saved to, one each, from what it answered
  /// ([ToolCallItem.imageFiles]): in place of the CLI's copies.
  final List<String> Function(String output)? files;

  /// Always in the model's prompt, never deferred behind Claude Code's tool
  /// search (where it would see only its name): for a tool it should think
  /// of unprompted.
  final bool alwaysLoad;

  /// The group of tools it belongs to (`'browser'`, `'images'`): a server
  /// that exposes one group alone gives only its tools.
  final String group;

  /// Whether its answer is pictures alone: a client whose protocol cannot
  /// carry them (ACP's MCP face, §12-1) is not given it.
  final bool picturesOnly;
}

/// An image as MCP content, for a tool's answer.
Map<String, Object?> claudeSdkImage(String base64, String mimeType) => {
  'type': 'image',
  'data': base64,
  'mimeType': mimeType,
};

/// Text as MCP content, for a tool's answer.
Map<String, Object?> claudeSdkText(String text) => {
  'type': 'text',
  'text': text,
};

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
        return result({
          'protocolVersion': params['protocolVersion'] ?? '2024-11-05',
          'capabilities': {'tools': <String, Object?>{}},
          'serverInfo': {'name': server, 'version': '1.0.0'},
          if (_instructions.isNotEmpty)
            'instructions': _instructions.values.join('\n\n'),
        });
      case 'tools/list':
        return result({
          'tools': [
            for (final tool in _tools.values)
              {
                'name': tool.name,
                'description': tool.description,
                'inputSchema': tool.inputSchema,
                if (tool.alwaysLoad) '_meta': {'anthropic/alwaysLoad': true},
              },
          ],
        });
      case 'tools/call':
        final tool = _tools[params['name']];
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
