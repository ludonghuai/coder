part of 'composer.dart';

// The menu face of the composer: the /command and @mention menu — what
// it offers, where it sits, how it is registered — and the keys the
// composer answers.

/// Asks the kernel for files matching [trigger], and shows them ahead of
/// the conversations. Answers to older queries are dropped.
Future<void> _lookUpFilesOf(
  ChatComposerState state,
  _Trigger trigger,
  Future<List<Suggestion>> Function(String query) suggest,
) async {
  final lookup = ++state._lookups;
  final List<Suggestion> files;
  try {
    files = await suggest(trigger.query);
  } on Object {
    return;
  }
  final current = state._trigger;
  if (!state.mounted ||
      lookup != state._lookups ||
      current == null ||
      !current.sameAnchor(trigger) ||
      current.query != trigger.query) {
    return;
  }
  state._setState(() {
    state._matches = [
      for (final suggestion in files)
        SuggestionMatch(
          suggestion,
          fuzzyMatch(suggestion.label, trigger.query)?.indexes ?? const [],
        ),
      ...state._rankOthers(trigger.query),
    ];
    state._highlighted = state._highlighted.clamp(0, math.max(0, state._matches.length - 1));
  });
  state._syncMenuRegistration();
}

/// Flutter lays out a line whose only content is an inline widget taller
/// than a line with text, so a token must never end a line: when it does
/// (e.g. the space after it was deleted), add a space after it, part of
/// the edit that left it there, and leave the caret where it was. Sending
/// trims it. Returns true if it edited.
bool _padTrailingTokensOf(ChatComposerState state) {
  final text = state._controller.text;
  for (final run in MdAtoms.parse(text).reversed) {
    final end = run.end;
    if (end < text.length && text[end] != '\n') continue;
    state._controller.amend(end, end, ' ');
    return true;
  }
  return false;
}

_Trigger? _findTriggerOf(ChatComposerState state, String text) {
  final selection = state._controller.selection;
  if (!selection.isCollapsed || selection.baseOffset < 1) return null;
  final caret = math.min(selection.baseOffset, text.length);

  // A space, a line's end, or a tag's either end.
  bool isBoundary(String char) =>
      char.trim().isEmpty || char == MdAtoms.open || char == MdAtoms.close;
  // Only at the end of a query: a caret moved into existing text (e.g.
  // `/re|view`) is not typing one.
  if (caret < text.length && !isBoundary(text[caret])) return null;
  // A / or an @ starting the word the caret ends: a command, or a file or
  // a conversation to refer to.
  final vocabulary = ComposerVocabulary.read(state.context);
  final mentions =
      vocabulary.sessions != null ||
      vocabulary.suggestFiles != null ||
      vocabulary.stashes != null;
  for (var i = caret - 1; i >= 0; i--) {
    final char = text[i];
    if (isBoundary(char)) return null;
    if (i > 0 && !isBoundary(text[i - 1])) continue;
    final query = text.substring(i + 1, caret);
    if (char == '/') return _Trigger(SuggestionKind.command, i, query);
    if (char == '@' && mentions) {
      return _Trigger(SuggestionKind.file, i, query);
    }
  }
  return null;
}

/// Horizontal caret position of [offset] relative to the composer box.
double _caretXOf(ChatComposerState state, int offset) {
  final caret = state._editorKey.currentState?.caretRect(offset);
  final box = state._boxKey.currentContext?.findRenderObject() as RenderBox?;
  if (caret == null || box == null || !box.attached) return 12;
  final x = box.globalToLocal(caret.topLeft).dx - 8;
  return x.clamp(0, math.max(0, box.size.width - SuggestionMenu.width));
}

void _closeMenuOf(ChatComposerState state) {
  if (state._trigger != null) state._dismissedTrigger = state._trigger;
  state._trigger = null;
  state._syncMenuRegistration();
}

void _syncMenuRegistrationOf(ChatComposerState state) {
  final open = state._trigger != null;
  if (open == state._menuRegistered) return;
  state._menuRegistered = open;
  if (open) {
    FloatingRegistry.openPopover(state._menuOwner, () {
      if (state.mounted) state._setState(state._closeMenu);
    });
  } else {
    FloatingRegistry.closePopover(state._menuOwner);
  }
}

void _moveHighlightOf(ChatComposerState state, int delta) {
  if (state._matches.isEmpty) return;
  state._setState(() {
    state._highlighted = (state._highlighted + delta) % state._matches.length;
  });
}

void _acceptOf(ChatComposerState state, int index) {
  final trigger = state._trigger;
  if (trigger == null || index >= state._matches.length) return;
  final suggestion = state._matches[index].suggestion;
  final caret = state._controller.selection.baseOffset;
  final ComposerEmbed token;
  if (suggestion.kind == SuggestionKind.stash) {
    final stash = ComposerVocabulary.read(state.context).stash
        ?.call(int.parse(suggestion.id));
    if (stash == null) return;
    token = ComposerStashEmbed.of(stash);
  } else if (suggestion.kind == SuggestionKind.file ||
      suggestion.kind == SuggestionKind.folder) {
    token = ComposerTokenEmbed.file(
      suggestion.value,
      directory: suggestion.kind == SuggestionKind.folder,
    );
  } else {
    token = ComposerTokenEmbed.fromSuggestion(suggestion);
  }
  // The token and a space after it, so the token is never the last thing
  // on its line (see [_padTrailingTokens]).
  final tag = '${token.atom} ';
  state._controller
    ..breakUndo()
    ..replace(
      trigger.start,
      caret,
      tag,
      selection: TextSelection.collapsed(offset: trigger.start + tag.length),
    )
    ..breakUndo();
  state._focusNode.requestFocus();
}

KeyEventResult _handleKeyOf(ChatComposerState state, KeyEvent event) {
  if (event is KeyUpEvent || state._isComposing) return KeyEventResult.ignored;
  // Run by the window's keybindings (it sees keys first).
  if (ChatKeys.isHandled(event)) return KeyEventResult.handled;
  // An open picker menu (or tooltip) takes arrows, Enter and Esc first.
  if (FloatingRegistry.handleKey(event) case final result?) return result;
  // Then the keybindings: Enter sends, the menu's keys…
  return ChatKeys.dispatch(event) ?? KeyEventResult.ignored;
}

bool _caretAtStartOf(ChatComposerState state) {
  final selection = state._controller.selection;
  return selection.isCollapsed && selection.baseOffset <= 0;
}

bool _caretAtEndOf(ChatComposerState state) {
  final selection = state._controller.selection;
  return selection.isCollapsed &&
      selection.baseOffset >= state._controller.length;
}

Object? chatContextKeyOf(ChatComposerState state, String key) => switch (key) {
  ChatContextKeys.inChatInput ||
  'inputFocus' ||
  'textInputFocus' => state._focusNode.hasFocus,
  ChatContextKeys.inputHasText => state._hasContent,
  // As upstream: at the very start, and the very end.
  ChatContextKeys.cursorAtTop => state._caretAtStart,
  ChatContextKeys.cursorAtBottom => state._caretAtEnd,
  ChatContextKeys.suggestWidgetVisible => state._trigger != null,
  ChatContextKeys.hasPromptSuggestion => state._suggestion != null,
  ChatContextKeys.currentlyEditing => state.widget.onSubmit != null,
  _ => null,
};

Map<String, VoidCallback> chatCommandsOf(ChatComposerState state) {
  final menu = state._trigger != null;
  final history = state.widget.onSubmit == null;
  return {
    // Always: with nothing to send, Enter does nothing (no new line).
    ChatCommandIds.submit: state._submit,
    // Paste the clipboard as plain text, past the long-paste tag.
    ChatCommandIds.pasteRaw: () => unawaited(state._paste(raw: true)),
    ChatCommandIds.cancelEdit: ?state.widget.onCancel,
    if (history && (state._historyAt ?? state._sentPrompts().length) > 0)
      ChatCommandIds.showPreviousPrompt: () => state._showPrompt(-1),
    if (history && state._historyAt != null)
      ChatCommandIds.showNextPrompt: () => state._showPrompt(1),
    if (state._suggestion != null)
      ChatCommandIds.acceptPromptSuggestion: state._acceptSuggestion,
    if (state._modePickerKey.currentState case final picker?)
      ChatCommandIds.openModePicker: picker.toggle,
    if (state.widget.session.modes case final modes?)
      ChatCommandIds.nextMode: () => state._nextMode(modes),
    if (state._modelPickerKey.currentState case final picker?)
      ChatCommandIds.openModelPicker: picker.toggle,
    if (WindowControls.canPickFiles)
      ChatCommandIds.attachContext: state._attachContext,
    if (menu) ...{
      ChatCommandIds.selectNextSuggestion: () => state._moveHighlight(1),
      ChatCommandIds.selectPrevSuggestion: () => state._moveHighlight(-1),
      if (state._matches.isNotEmpty)
        ChatCommandIds.acceptSelectedSuggestion: () => state._accept(state._highlighted),
      ChatCommandIds.hideSuggestWidget: () => state._setState(state._closeMenu),
    },
  };
}

bool chatComposingOf(ChatComposerState state) => state._isComposing;

/// Picks the mode after the one picked, back to the first after the
/// last.
void _nextModeOf(ChatComposerState state, KernelChoice modes) {
  final options = modes.options;
  final at = options.indexWhere((o) => o.id == modes.selected.id);
  modes.onSelected(options[(at + 1) % options.length]);
}

Widget _buildMenuOf(ChatComposerState state, BuildContext context) {
  return SuggestionMenu(
    title: state._menuKind == SuggestionKind.file
        ? context.l10n.composerMentions
        : context.l10n.composerCommands,
    matches: state._matches,
    highlighted: state._highlighted,
    onHighlight: (index) => state._setState(() => state._highlighted = index),
    onSelect: state._accept,
  );
}
