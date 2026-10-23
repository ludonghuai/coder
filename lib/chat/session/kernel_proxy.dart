part of '../chat_session.dart';

// What the kernel can do, as the session projects it: health and history,
// commands, usage, MCP servers, forking, queuing and renaming. Each facet
// is read live from the kernel, null where it does not declare it.

KernelHealth _healthOf(ChatSession owner) => owner._kernel.health;

/// Whether the conversation it continues is still being read.
bool _loadingHistoryOf(ChatSession owner) => switch (owner._kernel) {
  LoadsHistory(:final loadingHistory) => loadingHistory,
  _ => false,
};

/// Whether there is more of that conversation before what was read.
bool _hasEarlierHistoryOf(ChatSession owner) => switch (owner._kernel) {
  LoadsHistory(:final hasEarlierHistory) => hasEarlierHistory,
  _ => false,
};

/// Whether that is being read.
bool _loadingEarlierOf(ChatSession owner) => switch (owner._kernel) {
  LoadsHistory(:final loadingEarlier) => loadingEarlier,
  _ => false,
};

/// Reads some more of the conversation, before what was.
Future<void> _loadEarlierOf(ChatSession owner) => switch (owner._kernel) {
  final LoadsHistory kernel => kernel.loadEarlier(),
  _ => Future.value(),
};

/// The id the kernel keeps this conversation under, once known.
String? _sessionIdOf(ChatSession owner) => owner._kernel.sessionId;

/// Completes once the kernel has stopped, after [dispose].
Future<void> _stoppedOf(ChatSession owner) => owner._kernel.stopped;

/// Tries the kernel again after it failed.
void _restartOf(ChatSession owner) => owner._kernel.restart();

List<KernelCommand> _commandsOf(ChatSession owner) => switch (owner._kernel) {
  final ProvidesCommands kernel => kernel.commands,
  _ => const [],
};

bool _hasCommandsOf(ChatSession owner) => owner._kernel is ProvidesCommands;

/// Files matching an `@` query; null when the kernel does not look.
Future<List<FileSuggestion>> Function(String query)? _suggestFilesOf(
  ChatSession owner,
) => switch (owner._kernel) {
  final SuggestsFiles kernel => kernel.suggestFiles,
  _ => null,
};

ContextUsage? _contextOf(ChatSession owner) => switch (owner._kernel) {
  final ReportsContext kernel =>
    owner._transcript.usage ??
        ContextUsage(window: kernel.contextWindow, used: 0),
  _ => null,
};

/// Cost and account limits; null when the kernel does not report them.
UsageStats? _statsOf(ChatSession owner) => switch (owner._kernel) {
  final ReportsUsage kernel =>
    owner._transcript.stats ?? UsageStats(limits: kernel.accountLimits),
  _ => null,
};

/// Asks for the account's limits now (see [ReportsUsage.refreshUsage]).
void _refreshUsageOf(ChatSession owner) {
  if (owner._kernel case final ReportsUsage kernel) {
    unawaited(kernel.refreshUsage());
  }
}

/// When the usage limit the agent stopped at resets (see
/// [ReportsUsageLimit]); null with none hit, and while a turn runs.
DateTime? _usageLimitResetsAtOf(ChatSession owner) =>
    switch (owner._kernel) {
      ReportsUsageLimit(:final usageLimitResetsAt) when !owner.isStreaming =>
        usageLimitResetsAt,
      _ => null,
    };

/// Whether the next message is held to the account's usage limit: not
/// once on another provider's model.
bool _usageLimitAppliesOf(ChatSession owner) => switch (owner._kernel) {
  ReportsUsageLimit(:final usageLimitApplies) => usageLimitApplies,
  _ => true,
};

/// Whether an agent on [model] can go on by itself once the usage limit
/// it stopped at resets: on the account's own plan, which says when.
bool _continuesAfterLimitOf(ChatSession owner, String model) =>
    switch (owner._kernel) {
      final ReportsUsageLimit kernel => kernel.usageLimitAppliesTo(model),
      _ => false,
    };

/// Whether pictures sent with a message are taken: by the protocol
/// ([AcceptsImages]), or as files it is told of ([AcceptsImageFiles]).
bool _acceptsImagesOf(ChatSession owner) =>
    owner._kernel is AcceptsImages || owner._kernel is AcceptsImageFiles;

/// Whether the file open in the editor goes with each message
/// ([AcceptsEditorContext]): its chip shows in the composer, and the
/// message carries it.
bool _acceptsEditorContextOf(ChatSession owner) =>
    owner._kernel is AcceptsEditorContext;

/// What the user would likely send next: offered while the agent waits
/// for them.
String? _promptSuggestionOf(ChatSession owner) => switch (owner._kernel) {
  final SuggestsPrompts kernel
      when !owner.isStreaming && owner.pendingInteraction == null =>
    kernel.promptSuggestion,
  _ => null,
};

/// The kernel's MCP servers; null when it has none to manage, empty
/// until first reported.
List<McpServer>? _mcpServersOf(ChatSession owner) => switch (owner._kernel) {
  final ManagesMcpServers kernel => kernel.mcpServers ?? const [],
  _ => null,
};

void _refreshMcpServersOf(ChatSession owner) {
  if (owner._kernel case final ManagesMcpServers kernel) kernel.refreshMcpServers();
}

void _setMcpServerEnabledOf(
  ChatSession owner,
  McpServer server,
  bool enabled,
) {
  if (owner._kernel case final ManagesMcpServers kernel) {
    kernel.setMcpServerEnabled(server.name, enabled);
  }
}

void _reconnectMcpServerOf(ChatSession owner, McpServer server) {
  if (owner._kernel case final ManagesMcpServers kernel) {
    kernel.reconnectMcpServer(server.name);
  }
}

/// Starts signing in to [server]: the page to open for the user, if any.
Future<Uri?> _authenticateMcpServerOf(
  ChatSession owner,
  McpServer server,
) async => switch (owner._kernel) {
  final ManagesMcpServers kernel => kernel.authenticateMcpServer(
    server.name,
  ),
  _ => null,
};

bool _canEditMessagesOf(ChatSession owner) =>
    owner._kernel is RewindsConversation;

/// Messages can be sent while the agent works.
bool _canQueueOf(ChatSession owner) => owner._kernel is QueuesMessages;

bool _canRenameOf(ChatSession owner) => owner._kernel is RenamesSession;

/// Whether its kernel confirms a rename itself: the list then waits for
/// its `SessionRenamed` rather than change ahead of it (F25). False for a
/// kernel that does not say so (Claude Code's path, unchanged).
bool _renameConfirmedOf(ChatSession owner) => switch (owner._kernel) {
  final ConfirmsRename kernel => kernel.renameConfirmed,
  _ => false,
};

/// Whether its kernel names sessions itself: the host titles none (F1.3).
bool _ownsTitleOf(ChatSession owner) => owner._kernel is GeneratesTitles;

/// The title picked while a turn ran (§3.5); null when none waits.
String? _pendingTitleOf(ChatSession owner) => switch (owner._kernel) {
  final DefersRename kernel => kernel.pendingTitle,
  _ => null,
};

/// Whether the conversation can be copied into a new one (see [fork]).
bool _canForkOf(ChatSession owner) => switch (owner._kernel) {
  final ForksConversation kernel => kernel.canFork,
  _ => false,
};

/// Copies the conversation into a new session titled [title] (see
/// [ForksConversation.fork]): all of it but a turn under way; null when
/// it could not.
Future<SessionRecord?> _forkOf(ChatSession owner, {required String title}) async {
  if (owner._kernel case final ForksConversation kernel when kernel.canFork) {
    final before = switch (owner._transcript.activeTurn) {
      final turn? when owner._transcript.indexOf(turn) != null => turn,
      _ => null,
    };
    return kernel.fork(before: before, title: title);
  }
  return null;
}
