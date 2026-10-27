import '../../kernel/agent_kernel.dart';
import '../chat_session_overlay.dart';

// What the kernel can do, as the session projects it where the host's own
// source carries no projection: the command source, the rename and title
// facets, and what a message may carry. Each is read live from the kernel,
// false or null where it does not declare the capability.

/// Whether the kernel offers `/` commands at all: a command source whose
/// table may still be empty (the panel opens, the list may be).
bool hasCommandSourceOf(ChatSessionOverlayHost host) =>
    host.agentKernel is ProvidesCommands;

/// Whether its kernel confirms a rename itself: the list then waits for
/// its `SessionRenamed` rather than change ahead of it (F25). False for a
/// kernel that does not say so (Claude Code's path, unchanged).
bool renameConfirmedOf(ChatSessionOverlayHost host) =>
    switch (host.agentKernel) {
      final ConfirmsRename kernel => kernel.renameConfirmed,
      _ => false,
    };

/// Whether its kernel names sessions itself: the host titles none (F1.3).
bool ownsTitleOf(ChatSessionOverlayHost host) =>
    host.agentKernel is GeneratesTitles;

/// The title picked while a turn ran (§3.5); null when none waits.
String? pendingTitleOf(ChatSessionOverlayHost host) =>
    switch (host.agentKernel) {
      final DefersRename kernel => kernel.pendingTitle,
      _ => null,
    };

/// Whether pictures sent with a message are taken: by the protocol
/// ([AcceptsImages]), or as files it is told of ([AcceptsImageFiles]).
bool acceptsImagesOf(ChatSessionOverlayHost host) =>
    host.agentKernel is AcceptsImages ||
    host.agentKernel is AcceptsImageFiles;

/// Whether the file open in the editor goes with each message
/// ([AcceptsEditorContext]): its chip shows in the composer, and the
/// message carries it.
bool acceptsEditorContextOf(ChatSessionOverlayHost host) =>
    host.agentKernel is AcceptsEditorContext;
