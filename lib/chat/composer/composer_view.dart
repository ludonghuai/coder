part of 'composer.dart';

// The view face of the composer: its lifecycle, the box it builds, the
// editor inside it and the heights it keeps to.

void _initStateOf(ChatComposerState state) {
  state._padTrailingTokens();
  state._images = state._referredImages();
  state._hasContent = state._controller.text.trim().isNotEmpty;
  state._controller.addListener(state._handleEditorChanged);
  state._focusNode.addListener(state._handleFocusChanged);
  state.widget.draft?.addListener(state._handleDraftChanged);
  ComposerPolishSetting.changes?.addListener(state._handleSettingsChanged);
  EditorContextSetting.changes?.addListener(state._handleSettingsChanged);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!state.mounted) return;
    state._focusNode.requestFocus();
    state._takeDraftFiles();
    state._takeDraftMessage();
  });
}

void _didUpdateWidgetOf(ChatComposerState state, ChatComposer oldWidget) {
  if (!identical(oldWidget.draft, state.widget.draft)) {
    oldWidget.draft?.removeListener(state._handleDraftChanged);
    state.widget.draft?.addListener(state._handleDraftChanged);
  }
}

/// Settings → General's: the Polish button, and whether the file open in
/// the editor goes with each message.
void _handleSettingsChangedOf(ChatComposerState state) {
  if (state.mounted) state._setState(() {});
}

void _disposeOf(ChatComposerState state) {
  state.widget.draft?.removeListener(state._handleDraftChanged);
  ComposerPolishSetting.changes?.removeListener(state._handleSettingsChanged);
  EditorContextSetting.changes?.removeListener(state._handleSettingsChanged);
  FloatingRegistry.closePopover(state._menuOwner);
  state._clickWindow?.cancel();
  state._controller.dispose();
  state._focusNode.dispose();
  state._scrollController.dispose();
}

void focusOf(ChatComposerState state) => state._focusNode.requestFocus();

void _didChangeDependenciesOf(ChatComposerState state) {
  state._editor = null;
}

/// An input method is composing text: a composition not empty. A macOS
/// one may leave an empty one (its letters deleted, or after a commit)
/// until its next: not composing, or the keys (Tab, Enter) went to the
/// editor (#143).
bool _isComposingOf(ChatComposerState state) => state._controller.isComposing;

void _handleFocusChangedOf(ChatComposerState state) {
  if (!state._focusNode.hasFocus) {
    state._closeMenu();
  } else {
    // Focused, the caret in view: an edit's opens scrolled to its end.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final selection = state._controller.selection;
      if (state.mounted && state._focusNode.hasFocus && selection.isValid) {
        state._editorKey.currentState?.ensureVisible(selection.extentOffset);
      }
    });
  }
  state._setState(() {});
}

/// The text area's own scroll position (it scrolls past its maximum
/// height), or null before it is laid out.
ScrollPosition? editorScrollPositionOf(ChatComposerState state) =>
    state._scrollController.hasClients ? state._scrollController.position : null;

Widget buildOf(ChatComposerState state, BuildContext context) {
  state._shownBuilt = state._shownOfText();
  final focused = state._focusNode.hasFocus;
  final suggestion = state.widget.onSubmit == null
      ? state.widget.session.promptSuggestion
      : null;
  // Its key follows the keybindings (the window builds again when they
  // change).
  final suggestionKey = suggestion == null
      ? null
      : ChatKeys.keyLabel(
          ChatCommandIds.acceptPromptSuggestion,
          ChatComposerState._suggestionKeyContext,
        );
  if (suggestion != state._suggestion || suggestionKey != state._suggestionKey) {
    state._suggestion = suggestion;
    state._suggestionKey = suggestionKey;
    state._editor = null; // The placeholder shows them.
  }
  final colors = themeColors;
  if (!identical(colors, state._editorColors)) {
    state._editorColors = colors;
    state._editor = null;
  }
  // Before what is built is told by it (see [_buildInputs]).
  state._editor ??= state._buildEditor(context);
  final inputs = state._buildInputs();
  if (state._built case final built? when listEquals(inputs, state._builtFrom)) {
    return built;
  }
  state._builtFrom = inputs;
  return state._built = FloatingLayer(
    visible: state._trigger != null,
    // Above the composer at the trigger character; below it when there
    // is no room above.
    placement: (side: FloatingSide.top, align: FloatingAlign.start),
    anchorRect: (box) =>
        Rect.fromLTWH(box.left + state._menuX, box.top, 1, box.height),
    // Clicks in the menu are not outside the editor.
    tapRegionGroupId: state._focusNode,
    outerTapRegionGroupId: state.widget.tapRegionGroupId,
    builder: state._buildMenu,
    child: FileDropRegion(
      delegate: state,
      child: DragTarget<StashDragData>(
        onWillAcceptWithDetails: (details) =>
            details.data.references.isNotEmpty,
        onAcceptWithDetails: (details) =>
            state._dropStashes(details.offset, details.data.references),
        builder: (context, stashes, _) => DragTarget<FileDragData>(
          onWillAcceptWithDetails: (details) => details.data.files.isNotEmpty,
          onMove: (details) => state._showGhost(details.offset, details.data.files),
          onLeave: (_) => state._hideGhost(),
          onAcceptWithDetails: (details) =>
              state._dropFiles(details.offset, details.data.files, here: false),
          builder: (context, candidates, rejected) => state._buildBox(
            focused: focused || state._ghostAt != null || stashes.isNotEmpty,
          ),
        ),
      ),
    ),
  );
}

/// All that [build] reads, as it is now: the widget's, the state's, and
/// the session's that the toolbar shows. A kernel's options are the same
/// list while they do not change; the kernel among these, the picks'
/// callbacks built with it stay its.
List<Object?> _buildInputsOf(ChatComposerState state) {
  final session = state.widget.session;
  final l10n = state.context.l10n;
  const input = {ChatContextKeys.inChatInput: true};
  state._hovers = (
    mode: ChatKeys.titleWithKey(
      l10n.composerSetMode,
      ChatCommandIds.openModePicker,
      input,
    ),
    model: ChatKeys.titleWithKey(
      l10n.composerPickModel,
      ChatCommandIds.openModelPicker,
      input,
    ),
    ring: ChatKeys.titleWithKey(
      l10n.composerContextUsage,
      ChatCommandIds.toggleContextPanel,
      const {...input, ChatContextKeys.inChat: true},
    ),
  );
  final model = session.models;
  return [
    session,
    state.widget.onSubmit == null,
    state.widget.tapRegionGroupId,
    state.widget.contextPanelOpen,
    state.widget.onToggleContextPanel,
    state._focusNode.hasFocus,
    state._ghostAt != null,
    state._shownBuilt,
    state._editor,
    state._polishing,
    ComposerPolishSetting.current(),
    l10n,
    themeColors,
    state._hovers,
    session.kernel,
    state._showsStop,
    session.btestOn,
    session.btestRun?.id,
    session.btestRun?.line,
    session.btestRun?.face,
    session.btestRun?.traversal,
    // The two switches (§9.1): the line reads them with no run, and the
    // pills read them always.
    session.btestTraversal,
    session.btestWrite,
    session.health.noModel,
    session.context?.fraction,
    for (final choice in [
      session.kernelChoice,
      session.modes,
      session.permissions,
      model,
    ]) ...[choice?.options, choice?.selected],
    // What the model's label says of its settings (see
    // SessionModelPicker): their lists are made anew each time.
    if (model != null)
      for (final setting in session.modelSettings(model.selected.id)) ...[
        setting.kind,
        setting.selected,
        setting.options.firstOrNull,
      ],
  ];
}

Widget _buildBoxOf(ChatComposerState state, {required bool focused}) {
  return GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTap: state._focusNode.requestFocus,
    child: AnimatedContainer(
      key: state._boxKey,
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        // The agents window's chat input, editing a sent message too:
        // the color of every bubble, and their line; typed into, the line
        // turns a little towards the accent.
        color: AppColors.bubbleFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.bubbleBorder(focused: focused)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.widget.session.btestOn) BtestStatusLine(
            session: state.widget.session,
            tapRegionGroupId: state.widget.tapRegionGroupId,
            focusNode: state._focusNode,
          ),
          ComposerImages(
            images: state._pool,
            child: state._editor!,
          ),
          if (state._editorContext case final editor?)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: EditorContextChip(
                  editor: editor.toContext(),
                  onDismiss: state._dismissEditorContext,
                ),
              ),
            ),
          state._buildToolbar(),
        ],
      ),
    ),
  );
}

Widget _buildEditorOf(ChatComposerState state, BuildContext context) {
  // Slim overlay scrollbar for when the text exceeds the max height.
  return ScrollbarTheme(
    data: ScrollbarTheme.of(context).copyWith(
      thickness: const WidgetStatePropertyAll(4),
      crossAxisMargin: 3,
    ),
    child: Scrollbar(
      controller: state._scrollController,
      // Desktop scroll behavior would add a second, default scrollbar to
      // the editor's scroll view.
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: state._buildEditorBody(context),
      ),
    ),
  );
}

Widget _buildEditorBodyOf(ChatComposerState state, BuildContext context) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
    child: ClipRect(
      child: ComposerCaret(
        editorKey: state._editorKey,
        child: Listener(
          onPointerDown: state._handleClickDown,
          onPointerUp: state._handleClickUp,
          onPointerCancel: (_) => state._clickDownAt = null,
          child: Listener(
            onPointerDown: state._handleMenuPointerDown,
            onPointerUp: state._handleMenuPointerUp,
            onPointerCancel: (_) => state._menuPressAt = null,
            child: state._buildMarkdownEditor(context),
          ),
        ),
      ),
    ),
  );
}

/// Grows with content up to 10 lines, or a third of the window on short
/// windows, then scrolls internally.
double _maxEditorHeightOf(ChatComposerState state, BuildContext context) {
  final byWindow = MediaQuery.sizeOf(context).height / 3;
  return math.max(
    ChatComposerState._minEditorHeight,
    math.min(ChatComposerState._lineHeight * ChatComposerState._maxEditorLines, byWindow),
  );
}

Widget _buildMarkdownEditorOf(ChatComposerState state, BuildContext context) {
  final colors = themeColors;
  final base = DefaultTextStyle.of(context).style.merge(ChatComposerState._textStyle);
  return ConstrainedBox(
    constraints: BoxConstraints(
      minHeight: ChatComposerState._minEditorHeight,
      maxHeight: state._maxEditorHeight(context),
    ),
    child: MarkdownEditor(
      key: state._editorKey,
      controller: state._controller,
      focusNode: state._focusNode,
      scrollController: state._scrollController,
      shrinkWrap: true,
      embeds: const ComposerChips(),
      // A suggested prompt, then the key that takes it as the keybindings
      // label it (`Tab`); alone when it has none. On one line.
      placeholder: switch ((state._suggestion, state._suggestionKey)) {
        (final suggestion?, final key?) => '$suggestion    $key',
        (final suggestion?, null) => suggestion,
        (null, _) => context.l10n.composerPlaceholder,
      }.replaceAll(RegExp(r'[\x00-\x1f]+'), ' '),
      onKey: state._handleKey,
      onPaste: state._paste,
      style: MarkdownEditorStyle(
        text: base,
        selection: AppColors.textSelection,
        caret: colors['editorCursor.foreground'],
        placeholder: TextStyle(
          color: colors['agentsChatInput.placeholderForeground'],
        ),
      ),
    ),
  );
}
