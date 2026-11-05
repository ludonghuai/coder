// Tools of the app's own an agent can call: an MCP server that lives in
// the app rather than in a process of its own (Claude Code's "SDK"
// servers). Claude Code is told of it at launch (`--mcp-config`, type
// `sdk`) and as it is initialized (`sdkMcpServers`), and sends what it
// says to it as control requests (`mcp_message`), whose answers go back
// the same way.

import 'dart:async';

import '../../chat/chat_models.dart' show ToolCallItem, ToolKind;
import '../../host_tools/host_tools.dart';
import '../kernel_types.dart' show ApprovalDecision, ApprovalRequest;

/// Asks the user [request] on the agent's conversation, as the agent's
/// own requests are: what they decided, or null where it was given up
/// (the turn stopped) or no one is there to ask.
typedef ClaudeSdkAsk = Future<ApprovalDecision?> Function(
  ApprovalRequest request,
);

/// Where a tool is called from: the agent's working directory (its
/// project's path, as the workspace has it) and its session.
class ClaudeSdkCall {
  const ClaudeSdkCall({
    required this.cwd,
    this.sessionId,
    this.cancelled,
    this.toolUseId,
    this.ask,
  });

  final String cwd;

  /// Asks the user, on the agent's conversation: its id is the kernel's
  /// to give (the request's own is not kept). None where the kernel cannot.
  final ClaudeSdkAsk? ask;
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
    this.offeredIn,
    this.asksItself = false,
    this.group = '',
    this.picturesOnly = false,
  });

  /// Whether it asks the user itself, each time, whatever the mode
  /// ([ClaudeSdkCall.ask]): the CLI's leave not asked for it too.
  final bool asksItself;

  /// Whether an agent working in a folder (its location) is offered it, as
  /// the tool itself says, besides [HostTools.gate]; everywhere for
  /// null.
  final bool Function(String cwd)? offeredIn;

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

/// Which of the app's tools an agent is offered, by the folder it works in:
/// a bot's are its own, its abilities'; a project's agent has none of
/// them.
abstract interface class ClaudeSdkGate {
  bool offersTool(String cwd, String tool);

  /// Whether what [feature] tells of its tools ([ClaudeSdkTools.instruct])
  /// is told there.
  bool tellsFeature(String cwd, String feature);

  /// Whether a tool called there may wait on the user at the computer (to
  /// pick a model, say): not where there is none to.
  bool asksUser(String cwd);
}

/// The app's server and its tools, as the agent's side names them: a thin
/// face of the app's own registry ([HostTools]), which holds the tools, the
/// calls under way and the gate. The registry belongs to the app, not to one
/// kernel: this name is the one the kernels and the remote host's tools
/// reach it by.
abstract final class ClaudeSdkTools {
  /// The server's name: its tools are `mcp__baocode__<name>` to the agent.
  static const server = HostTools.server;

  static void register(ClaudeSdkTool tool) => HostTools.register(tool);

  static void unregister(String name) => HostTools.unregister(name);

  /// Has the server tell the agent [text] for [feature]; null takes it
  /// back.
  static void instruct(String feature, String? text) =>
      HostTools.instruct(feature, text);

  /// Has the server tell an agent what [text] gives for the folder it
  /// works in (nothing for null) for [feature].
  static void instructFor(String feature, String? Function(String cwd) text) =>
      HostTools.instructFor(feature, text);

  /// The tool an agent calls [name] (`mcp__baocode__<name>`), if one of
  /// this server's.
  static ClaudeSdkTool? called(String name) => HostTools.called(name);

  /// The servers to launch an agent working in [cwd] with: this one, if it
  /// offers that agent a tool.
  static List<String> serversFor(String cwd) => HostTools.serversFor(cwd);

  /// The answer to [message] (JSON-RPC) for the server.
  static Future<Map<String, Object?>> handle(
    Map<String, Object?> message,
    ClaudeSdkCall call,
  ) => HostTools.handle(message, call);
}
