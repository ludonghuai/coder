part of 'thincoder_kernel.dart';

// The approval face of the kernel: what the agent asks leave for, the answer
// the panel gives, and what is dropped when the turn or the session is over.
// The class keeps the delegation.

/// The agent asks leave for a tool (`session/request_permission`): put to
/// the user as it asked, and answered by [answer].
bool _serverRequestOf(ThincoderKernel owner, ThincoderRequest request) {
  if (owner._files.handle(request)) return true;
  if (request.method != 'session/request_permission') return false;
  final toolCall =
      (request.params['toolCall'] as Map?)?.cast<String, Object?>() ??
      const {};
  final options = [
    for (final option in request.params['options'] as List? ?? const [])
      if (option is Map) option.cast<String, Object?>(),
  ];
  final always = options
      .where((option) => option['optionId'] == 'approve_always')
      .firstOrNull;
  if (always == null) {
    // The panel's three values are what the agent sends (D19): without
    // them there is nothing to answer here, so it is refused — and said
    // in the log, since the agent reads that as a refusal.
    appEvent(
      'thincoder',
      'a permission request without approve_always: '
      '${[for (final option in options) option['optionId']]}',
    );
    return false;
  }
  final title = '${toolCall['title'] ?? ''}';
  // btest answers for its own browser actions (design §3.7): the approval
  // card is pressed away; what may run is judged at the tool itself
  // (KD-13), so this layer needs no parameters.
  if (BtestMode.onFor(owner._cwd, owner._slot) &&
      ThincoderKernel._isBrowserTool(title)) {
    final allow = options.any(
      (option) => option['optionId'] == 'approve_once',
    )
        ? 'approve_once'
        : 'approve_always';
    request.answer({
      'outcome': {'outcome': 'selected', 'optionId': allow},
    });
    return true;
  }
  final id = 'approval:${request.id}';
  owner._approvals[id] = request;
  owner.emit(
    InteractionRequested(
      owner.nextSeq,
      ApprovalRequest(
        id: id,
        title: title.isEmpty ? 'Approve a tool' : title,
        toolName: title.isEmpty ? 'tool' : title,
        preview: ThincoderEvents.preview(toolCall['content']),
        alwaysAllowLabel: '${always['name'] ?? 'Approve for this session'}',
      ),
    ),
  );
  return true;
}

void answerOf(
  ThincoderKernel owner,
  String requestId,
  InteractionAnswer answer,
) {
  final request = owner._approvals.remove(requestId);
  if (request == null) return;
  owner.emit(InteractionResolved(owner.nextSeq, requestId));
  // The panel's three rows, as the agent's three options (D19). A reason
  // has no channel in the protocol (§14-2): not sent.
  final optionId = switch (answer) {
    ApprovalAnswer(decision: ApprovalDecision.allowOnce) => 'approve_once',
    ApprovalAnswer(decision: ApprovalDecision.allowAlways) =>
      'approve_always',
    _ => 'reject',
  };
  request.answer({
    'outcome': {'outcome': 'selected', 'optionId': optionId},
  });
  // "For this session" is the terminal's `/auto` switch, written too (D20).
  if (optionId == 'approve_always') {
    unawaited(owner._config('autoApprove', true));
  }
}

/// Drops what is waiting on the user: told the turn is over, and — for
/// [refuse], when the kernel is going — answered as cancelled, which the
/// agent takes as a refusal (T26).
void _resolveApprovalsOf(ThincoderKernel owner, {bool refuse = false}) {
  if (owner._approvals.isEmpty) return;
  for (final MapEntry(key: id, value: request) in owner._approvals.entries) {
    if (refuse) {
      request.answer({
        'outcome': {'outcome': 'cancelled'},
      });
    }
    owner.emit(InteractionResolved(owner.nextSeq, id));
  }
  owner._approvals.clear();
}

/// Whether [title] names a tool of the browser group, as the kernel names
/// them (`mcp__baocode__browser_click`, `baocode_browser_click`): btest's
/// approval hook answers for those alone (§3.7). A tool this host does
/// not know is not one — a substring that looks like one is no proof.
bool _isBrowserToolOf(String title) {
  final tool =
      HostTools.called(title) ??
      HostTools.named(title) ??
      HostTools.lookup(title);
  return tool?.group == 'browser';
}
