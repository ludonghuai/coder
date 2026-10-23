part of 'composer.dart';

// The pointer face of the composer: files dragged over it, the files
// picked, the context menu, and telling a double-click from a drag.

/// Asks for files (the system's open panel) and puts them in at the
/// caret (upstream's Add Context… picks them in a picker of its own).
Future<void> _attachContextOf(ChatComposerState state) async {
  final files = await WindowControls.pickFiles();
  if (!state.mounted) return;
  await state.insertFiles(files, here: true);
  state._focusNode.requestFocus();
}

/// Where in the text [position] (the window's) would put what is let go
/// there: an offset in the text without the placeholder. Below or
/// beside the text (the toolbar, the pictures), its end.
int _dropOffsetOf(ChatComposerState state, Offset position) {
  final end = state._controller.length - (state._ghostAt == null ? 0 : state._ghost.length);
  final editor = state._editorKey.currentState;
  final area = editor?.viewportRect;
  if (editor == null || area == null || !area.contains(position)) {
    return end;
  }
  var offset = editor.offsetAt(position) ?? end;
  if (state._ghostAt case final ghost? when offset > ghost) {
    offset = math.max(ghost, offset - state._ghost.length);
  }
  return offset.clamp(0, end);
}

/// Stashes dragged from their page, let go at [position]: their tags
/// where the text is there.
void _dropStashesOf(ChatComposerState state, Offset position, List<StashReference> stashes) {
  if (!state.mounted) return;
  final at = state._dropOffset(position);
  final tags = [
    for (final stash in stashes) '${ComposerStashEmbed.of(stash).atom} ',
  ].join();
  state._controller
    ..breakUndo()
    ..replace(
      at,
      at,
      tags,
      selection: TextSelection.collapsed(offset: at + tags.length),
    )
    ..breakUndo();
  state._focusNode.requestFocus();
}

void _showGhostOf(ChatComposerState state, Offset position, List<ComposerFile> files) {
  if (!state.mounted) return;
  final at = state._dropOffset(position);
  if (at == state._ghostAt && listEquals(files, state._ghostFiles)) return;
  final shown = state._ghostAt != null;
  state._editGhost(() {
    state._removeGhost();
    final ghost = '${ComposerGhostEmbed.of(files).atom} ';
    state._controller.replaceUnrecorded(at, at, ghost);
    state._ghostAt = at;
    state._ghost = ghost;
    state._ghostFiles = files;
  });
  // The border shows it.
  if (!shown) state._setState(() {});
}

void _hideGhostOf(ChatComposerState state) {
  if (!state.mounted || state._ghostAt == null) return;
  state._editGhost(state._removeGhost);
  state._setState(() {});
}

void _removeGhostOf(ChatComposerState state) {
  final at = state._ghostAt;
  if (at == null) return;
  final length = state._ghost.length;
  state._ghostAt = null;
  state._ghost = '';
  state._ghostFiles = const [];
  state._controller.replaceUnrecorded(at, at + length, '');
}

void _editGhostOf(ChatComposerState state, VoidCallback edit) {
  state._ghosting = true;
  try {
    edit();
  } finally {
    state._ghosting = false;
  }
}

void fileDragOverOf(ChatComposerState state, Offset position, List<ComposerFile> files) => state._showGhost(
  position,
  // Files an app is still to write (a mail's attachment) have no names
  // yet.
  files.isEmpty ? const [ComposerFile('…')] : files,
);

void fileDragLeaveOf(ChatComposerState state) => state._hideGhost();

/// From another app: this machine's files.
void fileDropOf(ChatComposerState state, Offset position, List<ComposerFile> files) =>
    state._dropFiles(position, files, here: true);

/// [files] let go at [position]; [here], this machine's (else the
/// project's, dragged from the IDE).
void _dropFilesOf(
  ChatComposerState state,
  Offset position,
  List<ComposerFile> files, {
  required bool here,
}) {
  if (!state.mounted) return;
  final at = state._ghostAt ?? state._dropOffset(position);
  state._hideGhost();
  unawaited(state.insertFiles(files, at: at, here: here));
}

void _handleMenuPointerDownOf(ChatComposerState state, PointerDownEvent event) {
  state._menuPressAt =
      event.kind == PointerDeviceKind.mouse &&
          event.buttons == kSecondaryMouseButton
      ? event.position
      : null;
}

void _handleMenuPointerUpOf(ChatComposerState state, PointerUpEvent event) {
  final down = state._menuPressAt;
  state._menuPressAt = null;
  if (down == null || (event.position - down).distance > kTouchSlop) return;
  final selection = state._controller.selection;
  if (state._editorKey.currentState?.offsetAt(event.position) case final at?
      when selection.isCollapsed ||
          at < selection.start ||
          at > selection.end) {
    state._controller.selection = TextSelection.collapsed(offset: at);
  }
  state._focusNode.requestFocus();
  SchedulerBinding.instance
    ..addPostFrameCallback((_) => state._showContextMenu(event.position))
    ..scheduleFrame();
}

Future<void> _showContextMenuOf(ChatComposerState state, Offset position) async {
  if (!state.mounted || !WindowControls.hasNativeMenus) return;
  final selected = !state._controller.selection.isCollapsed;
  final canPaste = await WindowControls.canPaste();
  if (!state.mounted) return;
  final l10n = state.context.l10n;
  final chosen = await WindowControls.showContextMenu(position, [
    NativeMenuItem('cut', l10n.commonCut, key: 'x', enabled: selected),
    NativeMenuItem('copy', l10n.commonCopy, key: 'c', enabled: selected),
    NativeMenuItem('paste', l10n.commonPaste, key: 'v', enabled: canPaste),
    const NativeMenuItem.separator(),
    NativeMenuItem(
      'selectAll',
      l10n.commonSelectAll,
      key: 'a',
      enabled: state._controller.length > 0,
    ),
  ]);
  final editor = state._editorKey.currentState;
  if (!state.mounted || editor == null) return;
  state._focusNode.requestFocus();
  // As their shortcuts do: the selection stays where it is.
  switch (chosen) {
    case 'cut':
      await editor.copy(cut: true);
    case 'copy':
      await editor.copy();
    case 'paste':
      await editor.paste();
    case 'selectAll':
      state._selectAll();
  }
}

void _selectAllOf(ChatComposerState state) => state._controller.selection = TextSelection(
  baseOffset: 0,
  extentOffset: state._controller.length,
);

void _handleClickDownOf(ChatComposerState state, PointerDownEvent event) {
  final plainPress =
      event.kind == PointerDeviceKind.mouse &&
      event.buttons == kPrimaryMouseButton &&
      !HardwareKeyboard.instance.isShiftPressed;
  final upAt = state._clickUpAt;
  state._clickDownAt = plainPress ? event.position : null;
  state._secondClick =
      plainPress &&
      state._clickWindow?.isActive == true &&
      upAt != null &&
      (event.position - upAt).distance <= kDoubleTapSlop;
  state._clickWindow?.cancel();
  state._clickWindow = null;
  // The first click puts any selection away, so ask before it.
  if (!state._secondClick) state._clickOnSelection = !state._controller.selection.isCollapsed;
}

void _handleClickUpOf(ChatComposerState state, PointerUpEvent event) {
  final downAt = state._clickDownAt;
  state._clickDownAt = null;
  if (downAt == null || (event.position - downAt).distance > ChatComposerState._clickSlop) {
    return;
  }
  // A third click is a click again (no window after a second).
  if (state._secondClick) {
    if (state._clickOnSelection) return;
    // After the editor's handling of the up, which comes after this:
    // whatever it made of the press (a word, a caret, a drag of a pixel).
    scheduleMicrotask(() {
      if (state.mounted) state._selectAll();
    });
    return;
  }
  state._clickUpAt = event.position;
  state._clickWindow = Timer(kDoubleTapTimeout, () => state._clickWindow = null);
}
