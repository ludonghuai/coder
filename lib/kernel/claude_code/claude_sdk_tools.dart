// Tools of the app's own an agent can call: an MCP server that lives in
// the app rather than in a process of its own (Claude Code's "SDK"
// servers). Claude Code is told of it at launch (`--mcp-config`, type
// `sdk`) and as it is initialized (`sdkMcpServers`), and sends what it
// says to it as control requests (`mcp_message`), whose answers go back
// the same way.

import 'dart:async';

import '../../chat/chat_models.dart' show ToolCallItem, ToolKind;

/// Where a tool is called from: the agent's working directory (its
/// project's path, as the workspace has it) and its session.
class ClaudeSdkCall {
  const ClaudeSdkCall({
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
class ClaudeSdkTool {
  const ClaudeSdkTool({
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
  final Future<Object> Function(Map<String, Object?> input, ClaudeSdkCall call)
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
  /// The group of tools it belongs to (`'browser'`, `'images'`).
  final String group;
  /// Whether its answer is pictures alone: a client without them skips it.
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
