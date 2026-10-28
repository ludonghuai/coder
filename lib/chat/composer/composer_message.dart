part of 'composer.dart';

// The message face of the composer: the text polished and sent, the
// draft kept, taken up and put back, and the history of sent prompts.

void _acceptSuggestionOf(ChatComposerState state) {
  final suggestion = MdAtoms.strip(state._suggestion ?? '');
  if (suggestion.isEmpty) return;
  state._controller.replace(
    0,
    0,
    suggestion,
    selection: TextSelection.collapsed(offset: suggestion.length),
  );
}

/// The messages sent in this conversation, oldest first, a message sent
/// again in a row once.
List<String> _sentPromptsOf(ChatComposerState state) {
  final session = state.widget.session;
  final prompts = <String>[];
  for (var i = 0; i < session.itemCount; i++) {
    if (session.itemAt(i) case UserMessageItem(:final text)
        when text.trim().isNotEmpty &&
            (prompts.isEmpty || prompts.last != text)) {
      prompts.add(text);
    }
  }
  return prompts;
}

void _leaveHistoryOf(ChatComposerState state) {
  state._historyAt = null;
  state._historyDraft = null;
  state._historyShown = null;
}

/// Shows the message [step] from the one shown (-1: the one before).
void _showPromptOf(ChatComposerState state, int step) {
  final prompts = state._sentPrompts();
  final from = state._historyAt ?? prompts.length;
  final at = from + step;
  if (at < 0 || at > prompts.length) return;
  state._historyDraft ??= state._controller.text;
  final String content;
  if (at == prompts.length) {
    content = state._historyDraft!;
  } else {
    content = composerContentFromPaste(
      prompts[at],
      ComposerVocabulary.read(state.context),
      atStart: true,
    );
  }
  state._recalling = true;
  try {
    // Going back, at the start: ↑ goes on back; going on, at the end.
    state._controller
      ..breakUndo()
      ..replace(
        0,
        state._controller.length,
        content,
        selection: TextSelection.collapsed(
          offset: step < 0 ? 0 : content.length,
        ),
      )
      ..breakUndo();
  } finally {
    state._recalling = false;
  }
  if (at == prompts.length) {
    state._leaveHistory();
  } else {
    state._historyAt = at;
    state._historyShown = state._controller.text;
  }
}

ComposerMessage _buildMessageOf(ChatComposerState state) {
  final text = StringBuffer();
  final mentions = <String>[];
  final code = <String, AppendedText>{};
  for (final piece in composerPieces(state._controller.text)) {
    switch (piece) {
      case final String data:
        text.write(data);
      case ComposerEmbed(type: ComposerImageEmbed.type, :final data):
        text.write(ComposerImageEmbed.plainText(data));
      case ComposerEmbed(type: ComposerCodeEmbed.type, :final data):
        final reference = ComposerCodeEmbed.decode(data);
        text.write(reference.reference);
        code.putIfAbsent(reference.reference, () => reference);
      case ComposerEmbed(type: ComposerPastedTextEmbed.type, :final data):
        final pasted = ComposerPastedTextEmbed.decode(data);
        text.write(pasted.reference);
        code.putIfAbsent(pasted.reference, () => pasted);
      case ComposerEmbed(type: ComposerStashEmbed.type, :final data):
        final stash = ComposerStashEmbed.decode(data);
        text.write(stash.reference);
        code.putIfAbsent(stash.reference, () => stash);
      case ComposerEmbed(type: ComposerTokenEmbed.type, :final data):
        text.write(ComposerTokenEmbed.plainText(data));
        final token = ComposerTokenEmbed.decode(data);
        if ((token.kind == SuggestionKind.file ||
                token.kind == SuggestionKind.folder) &&
            !mentions.contains(token.value)) {
          mentions.add(token.value);
        }
    }
  }
  return ComposerMessage(
    // The lines it refers to after it.
    text: text.toString().trim() + codeAppendix(code.values),
    mentions: mentions,
    images: [...state._images],
  );
}

/// The file open in the editor, as this draft carries it: none for a
/// kernel that does not take it, with the setting off, with no file open,
/// or when taken off this draft (the chip's ×).
OpenEditor? _editorContextOf(ChatComposerState state) {
  if (!state.widget.session.acceptsEditorContext) return null;
  if (!EditorContextSetting.current()) return null;
  final editor = state.widget.openEditor?.call();
  return editor == state._dismissedEditor ? null : editor;
}

/// Takes the file open in the editor off this draft; it comes back once
/// the editor moves.
void _dismissEditorContextOf(ChatComposerState state) {
  state._setState(() => state._dismissedEditor = state.widget.openEditor?.call());
}

/// The dock's composer shows a stop button while a turn runs; an editing
/// composer can always submit (resending stops the running turn).
bool _showsStopOf(ChatComposerState state) =>
    state.widget.onSubmit == null &&
    state.widget.session.isStreaming &&
    !(state.widget.session.canQueue && state._canSend);

void _submitOf(ChatComposerState state) {
  // Empty while a turn runs, messages queued behind it: the first of them
  // taken up now, as its Send Now.
  if (state.widget.onSubmit == null && state.widget.session.isStreaming && !state._canSend) {
    if (state.widget.session.queued.firstOrNull case (final id, _)) {
      state.widget.session.sendQueuedNow(id);
    }
    return;
  }
  if (state._showsStop) return;
  final message = state._buildMessage();
  if (message.text.isEmpty && message.images.isEmpty) return;
  if (state.widget.onSubmit case final onSubmit?) {
    onSubmit(message);
    return;
  }
  state.widget.session.send(
    message,
    editor: state.widget.openEditor,
    // Taken off this draft: this message carries none of it.
    editorContext: state.widget.openEditor?.call() != state._dismissedEditor,
  );
  state._pool = {};
  state._dismissedEditor = null;
  state._controller.clear();
  state._leaveHistory();
  state._saveDraft();
  state._dismissedTrigger = null;
}

/// The files put in the draft from outside (see
/// [ComposerDraft.insertFiles]), as if pasted.
void _takeDraftFilesOf(ChatComposerState state) {
  final files = state.widget.draft?.takeFiles() ?? const <ComposerFile>[];
  if (files.isNotEmpty) unawaited(state.insertFiles(files));
}

/// The message put back in the draft to be edited (see
/// [ComposerDraft.restore]): after what is typed, the caret at its end.
void _takeDraftMessageOf(ChatComposerState state) {
  final message = state.widget.draft?.takeMessage();
  if (message == null) return;
  state._pool = {
    for (final image in message.images) ?image.number: image,
    ...state._pool,
  };
  var text = message.text;
  final referred = {
    for (final match in imageReferencePattern.allMatches(text))
      int.parse(match[1]!),
  };
  final unreferred = [
    for (final image in message.images)
      if (image.number case final number? when !referred.contains(number))
        number,
  ];
  if (unreferred.isNotEmpty) {
    text = [unreferred.map(imageReference).join(' '), text].join(' ');
  }
  final content = composerContentFromText(
    text,
    ComposerVocabulary.read(state.context),
    images: state._pool.keys.toSet(),
  );
  final end = state._controller.length;
  state._controller
    ..breakUndo()
    ..replace(
      end,
      end,
      content,
      selection: TextSelection.collapsed(offset: end + content.length),
    )
    ..breakUndo();
  state._focusNode.requestFocus();
}

/// Keeps what is typed, and where the caret is, in the draft.
void _saveDraftOf(ChatComposerState state) {
  if (state._takingDraft) return;
  state.widget.draft?.save(
    state._controller.text,
    state._controller.selection,
    state._pool.values.toList(),
    by: state,
  );
}

/// The draft typed in by another composer (the same agent's, in another
/// window): its text here too, the caret kept where it was.
void _handleDraftChangedOf(ChatComposerState state) {
  final draft = state.widget.draft;
  if (draft != null && draft.pendingFiles.isNotEmpty) state._takeDraftFiles();
  if (draft?.pendingMessage != null) state._takeDraftMessage();
  if (draft == null || identical(draft.savedBy, state) || !draft.saved) {
    return;
  }
  final current = state._controller.text;
  final content = draft.content!;
  if (current == content) return;
  state._pool = {...state._pool, for (final image in draft.images) ?image.number: image};
  // Only what differs replaced, the caret moved along.
  var start = 0;
  final shorter = math.min(current.length, content.length);
  while (start < shorter &&
      current.codeUnitAt(start) == content.codeUnitAt(start)) {
    start++;
  }
  var end = 0;
  while (end < shorter - start &&
      current.codeUnitAt(current.length - 1 - end) ==
          content.codeUnitAt(content.length - 1 - end)) {
    end++;
  }
  // Not into an atom: one changed is replaced whole.
  while (start > 0 && ChatComposerState._inAtom(current, start)) {
    start--;
  }
  while (end > 0 && ChatComposerState._inAtom(current, current.length - end)) {
    end--;
  }
  state._takingDraft = true;
  try {
    // Not this composer's edit to undo, and its steps no longer the
    // text's.
    state._controller
      ..forgetUndo()
      ..replaceUnrecorded(
        start,
        current.length - end,
        content.substring(start, content.length - end),
      );
  } finally {
    state._takingDraft = false;
  }
}
