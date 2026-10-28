import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:bao_markdown/bao_markdown.dart';

import '../../browser/btest/btest_status_switches.dart';
import '../../kernel/agent_kernel.dart';
import '../../kernel/kernel_types.dart';
import '../../keybindings/chat_keybindings.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show WorkbenchColors, themeColors;
import '../chat_keys.dart';
import '../chat_models.dart';
import '../chat_session.dart';
import '../editor_context_setting.dart';
import '../open_editor.dart';
import '../stop_confirmation.dart';
import '../floating/floating_layer.dart';
import '../floating/floating_placement.dart';
import '../floating/floating_registry.dart';
import '../../workspace/window_controls.dart';
import '../widgets/hover_builder.dart';
import 'composer_caret.dart';
import 'composer_controller.dart';
import 'composer_draft.dart';
import 'composer_embeds.dart';
import 'composer_files.dart';
import 'composer_images.dart';
import 'composer_mock_data.dart';
import 'composer_picker.dart';
import 'composer_polish.dart';
import 'editor_context_chip.dart';
import 'pickers_row.dart';
import 'session_model_picker.dart';
import 'kernel_option_text.dart';
import 'file_drop.dart';
import 'suggestion_menu.dart';
import '../../ide/ide_hover.dart';
import '../../ide/ide_spinning.dart';
import '../../theme/codicons.dart';
import '../../ide/file_service.dart' show IdeFileService;
import '../../ide/ide_notifications.dart';
import 'remote_drops.dart';

part 'composer_toolbar.dart';
part 'composer_editing.dart';
part 'composer_menu.dart';
part 'composer_pointer.dart';
part 'composer_view.dart';
part 'composer_message.dart';

/// An open query: a /command's (a slash starting a word), or a mention's
/// (an @ starting a word: a file, a folder or a conversation);
/// [query] is the text between it and the caret.
class _Trigger {
  const _Trigger(this.kind, this.start, this.query);

  /// [SuggestionKind.command], or [SuggestionKind.file] for a mention.
  final SuggestionKind kind;

  /// Where the slash or the @ is.
  final int start;
  final String query;

  bool sameAnchor(_Trigger? other) =>
      other != null && other.kind == kind && other.start == start;
}

/// The chat input: an editor of plain text (bao_markdown's, see
/// [ComposerController]) with tags in it.
///
/// The dock's composer sends to [session]. With [onSubmit] it edits instead
/// (e.g. a sent message reopened in the history): it starts from
/// [initialText], shows no stop button or context ring, and Esc calls
/// [onCancel].
///
/// Its keys are keybindings (see [ChatCommandIds]): Enter sends, ↑ at its
/// start shows the messages sent before, the / menu's keys…
///
/// Files come in as tags of their paths (images as images, where the
/// conversation takes them): dragged onto it from other apps or from the
/// IDE, pasted after a copy, or picked (Add Context…). Code copied from the
/// IDE's editor pastes as a tag of its lines (see [CopiedCode]), and text
/// too long to lay out as a tag of it (see [PastedText]).
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.session,
    this.contextPanelOpen = false,
    this.onToggleContextPanel,
    this.initialText,
    this.initialImages = const [],
    this.onSubmit,
    this.onCancel,
    this.tapRegionGroupId,
    this.draft,
    this.openEditor,
    this.hostFiles,
  });

  final ChatSession session;
  final bool contextPanelOpen;
  final VoidCallback? onToggleContextPanel;

  /// Text to start from; `@paths`, `[path:lines]` and a leading `/command`
  /// in it become tags again.
  final String? initialText;

  /// Images to start from (the message being edited had them).
  final List<ImageAttachment> initialImages;
  final ValueChanged<ComposerMessage>? onSubmit;
  final VoidCallback? onCancel;

  /// Group of a [TapRegion] around this composer: its menus, which open in
  /// the overlay, count as inside it.
  final Object? tapRegionGroupId;

  /// Where what is typed is kept while the composer is gone; once saved,
  /// it starts from there rather than [initialText] and [initialImages].
  final ComposerDraft? draft;

  /// The file open in the editor beside the chat (see [ChatSession.send]).
  final OpenEditor? Function()? openEditor;

  /// A remote project's host's files, where files of this machine's put
  /// in (let go from another app, pasted, picked) are copied first, for its
  /// agent to read (see [RemoteDrops]); null for a local project.
  final IdeFileService? hostFiles;

  @override
  State<ChatComposer> createState() => ChatComposerState();
}

class ChatComposerState extends State<ChatComposer>
    with ChatKeyTarget
    implements FileDropDelegate {
  static const _fontSize = 13.5;
  static TextStyle get _textStyle => TextStyle(
    color: AppColors.textPrimary,
    fontSize: _fontSize,
    height: 1.5,
    // Center glyphs in the line box so the custom caret lines up with them.
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const _lineHeight = _fontSize * 1.5;

  /// Resting height of the text area: roomier than one line, and it keeps
  /// the composer at the height it had with the old context row.
  static const _minEditorHeight = _lineHeight + 28;
  static const _maxEditorLines = 10;

  late final ComposerController _controller = _createController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'Composer');
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<MarkdownEditorState> _editorKey = GlobalKey();
  final GlobalKey _boxKey = GlobalKey();
  final GlobalKey<ComposerPickerState> _modePickerKey = GlobalKey();
  final GlobalKey<ComposerPickerState> _modelPickerKey = GlobalKey();

  bool _hasContent = false;

  /// Polish asked, its answer awaited (see [_polish]).
  bool _polishing = false;

  /// The file open in the editor when taken off this draft (see
  /// [EditorContextChip]): the next message carries none of it until the
  /// editor moves.
  OpenEditor? _dismissedEditor;

  /// Every image put in, by number, kept until sent: the text's references
  /// pick which go (see [_images]), so one taken out and brought back by
  /// undo is still there. Replaced, not changed, for the references
  /// showing them to see it.
  late Map<int, ImageAttachment> _pool = _initialPool();

  /// The images that go: those the text refers to, in its order, once
  /// each. Derived from the text alone, as it changes.
  List<ImageAttachment> _images = const [];
  _Trigger? _trigger;
  _Trigger? _dismissedTrigger;
  List<SuggestionMatch> _matches = const [];

  /// The conversations the open @ offers, as they were when it was typed.
  List<Suggestion> _sessions = const [];

  /// The stashes the open @ offers, after the files, as they were when it
  /// was typed.
  List<Suggestion> _stashes = const [];

  /// What an @ offers besides files: stashes, then conversations.
  List<SuggestionMatch> _rankOthers(String query) => [
    ...rankGroupedSuggestions(_stashes, query),
    ...rankGroupedSuggestions(_sessions, query),
  ];

  /// Tells Flutter what changed: the part files' functions reach
  /// `setState` through here, as the protected member is the class's
  /// own to call.
  void _setState(VoidCallback fn) => setState(fn);

  // The faces are split out, each a part of this library: the toolbar
  // (composer_toolbar.dart), editing (composer_editing.dart), the menu
  // (composer_menu.dart), the pointer (composer_pointer.dart), the view
  // (composer_view.dart) and the message (composer_message.dart). The
  // fields stay here, with a one-line delegate for each member.

  /// Whether the menu lists a mention's files and conversations or the
  /// commands: kept as it closes, for it to fade out as it was.
  SuggestionKind _menuKind = SuggestionKind.command;
  int _highlighted = 0;
  double _menuX = 0;

  Map<int, ImageAttachment> _initialPool() => _initialPoolOf(this);

  ComposerController _createController() => _createControllerOf(this);

  Future<bool> _paste({bool raw = false}) => _pasteOf(this, raw: raw);

  int _nextPastedNumber() => _nextPastedNumberOf(this);

  @override
  void initState() {
    super.initState();
    _initStateOf(this);
  }

  @override
  void didUpdateWidget(covariant ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _didUpdateWidgetOf(this, oldWidget);
  }

  void _handleSettingsChanged() => _handleSettingsChangedOf(this);

  @override
  void dispose() {
    _disposeOf(this);
    super.dispose();
  }

  void focus() => focusOf(this);

  // --- Images --------------------------------------------------------------

  /// At most this many per message.
  static const _maxImages = 20;

  Iterable<({int number, int offset})> _references() => _referencesOf(this);

  List<ImageAttachment> _referredImages() => _referredImagesOf(this);

  Future<void> _addImages(List<ImageAttachment> images, {int? at}) => _addImagesOf(this, images, at: at);

  Future<List<ImageAttachment?>> _numbered(
    List<ImageAttachment?> images,
  ) => _numberedOf(this, images);

  Future<void> insertFiles(
    List<ComposerFile> files, {
    int? at,
    bool here = false,
  }) => insertFilesOf(this, files, at: at, here: here);

  Future<List<ComposerFile>?> _copyToHost(List<ComposerFile> files) => _copyToHostOf(this, files);

  Future<String> _picturesIn(String text) => _picturesInOf(this, text);

  void _insertTags(List<ComposerEmbed> tags, {int? at}) => _insertTagsOf(this, tags, at: at);

  bool get _canSend => _canSendOf(this);

  // --- Suggested prompt ----------------------------------------------------

  /// What the agent suggests sending next, shown as the placeholder of an
  /// empty dock composer; Tab takes it.
  String? _suggestion;

  /// The key that takes it, as the keybindings have it now: shown after
  /// it; none when unbound.
  String? _suggestionKey;

  /// The context keys where the suggested prompt's key applies.
  static const _suggestionKeyContext = {
    ChatContextKeys.inChatInput: true,
    ChatContextKeys.hasPromptSuggestion: true,
    ChatContextKeys.inputHasText: false,
  };

  void _acceptSuggestion() => _acceptSuggestionOf(this);

  ScrollPosition? get editorScrollPosition => editorScrollPositionOf(this);

  /// The editor subtree, built once and reused so that keystrokes (which
  /// rebuild this state for the menu and send button) do not build it
  /// again. Rebuilt only when an inherited dependency (theme, window size),
  /// the color theme or the placeholder changes.
  Widget? _editor;

  /// [_shownOfText] when the box was last built.
  _ShownOfText? _shownBuilt;

  /// The color theme's colors [_editor] was built with.
  WorkbenchColors? _editorColors;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _didChangeDependenciesOf(this);
  }

  // --- Editor state --------------------------------------------------------

  bool get _isComposing => _isComposingOf(this);

  void _handleFocusChanged() => _handleFocusChangedOf(this);

  void _takeDraftFiles() => _takeDraftFilesOf(this);

  void _takeDraftMessage() => _takeDraftMessageOf(this);

  void _saveDraft() => _saveDraftOf(this);

  /// Taking up [_handleDraftChanged]'s text: not the user's edit.
  bool _takingDraft = false;

  void _handleDraftChanged() => _handleDraftChangedOf(this);

  static bool _inAtom(String text, int offset) => _inAtomOf(text, offset);

  _ShownOfText _shownOfText() => _shownOfTextOf(this);

  bool _hasWords() => _hasWordsOf(this);

  int? _wordsVersion;
  bool _words = false;

  void _handleEditorChanged() => _handleEditorChangedOf(this);

  int _lookups = 0;

  Future<void> _lookUpFiles(
    _Trigger trigger,
    Future<List<Suggestion>> Function(String query) suggest,
  ) => _lookUpFilesOf(this, trigger, suggest);

  bool _padTrailingTokens() => _padTrailingTokensOf(this);

  _Trigger? _findTrigger(String text) => _findTriggerOf(this, text);

  double _caretX(int offset) => _caretXOf(this, offset);

  // --- Suggestions ---------------------------------------------------------

  void _closeMenu() => _closeMenuOf(this);

  /// Identifies the suggestion menu to [FloatingRegistry].
  final Object _menuOwner = Object();
  bool _menuRegistered = false;

  void _syncMenuRegistration() => _syncMenuRegistrationOf(this);

  void _moveHighlight(int delta) => _moveHighlightOf(this, delta);

  void _accept(int index) => _acceptOf(this, index);

  // --- Keyboard ------------------------------------------------------------

  KeyEventResult _handleKey(KeyEvent event) => _handleKeyOf(this, event);

  bool get _caretAtStart => _caretAtStartOf(this);

  bool get _caretAtEnd => _caretAtEndOf(this);

  @override
  Object? chatContextKey(String key) => chatContextKeyOf(this, key);

  @override
  Map<String, VoidCallback> get chatCommands => chatCommandsOf(this);

  @override
  bool get chatComposing => chatComposingOf(this);

  void _nextMode(KernelChoice modes) => _nextModeOf(this, modes);

  Future<void> _attachContext() => _attachContextOf(this);

  // --- Drag and drop -----------------------------------------------------
  //
  // Files dragged over the composer, from other apps (see [FileDrops]) or
  // from the IDE ([FileDragData]), show where they would go: their tags,
  // faint, in the text at the pointer, the text making room for them. Let
  // go, the tags take their place.

  /// Where the placeholder is in the text, while a drag is over it.
  int? _ghostAt;

  /// The placeholder and the space after it, as they are in the text.
  String _ghost = '';

  /// What the placeholder shows.
  List<ComposerFile> _ghostFiles = const [];

  /// The placeholder is being put in or taken out: no edit of the user's
  /// (see [_handleEditorChanged]), and nothing to undo.
  bool _ghosting = false;

  int _dropOffset(Offset position) => _dropOffsetOf(this, position);

  void _dropStashes(Offset position, List<StashReference> stashes) => _dropStashesOf(this, position, stashes);

  void _showGhost(Offset position, List<ComposerFile> files) => _showGhostOf(this, position, files);

  void _hideGhost() => _hideGhostOf(this);

  void _removeGhost() => _removeGhostOf(this);

  void _editGhost(VoidCallback edit) => _editGhostOf(this, edit);

  @override
  void fileDragOver(Offset position, List<ComposerFile> files) => fileDragOverOf(this, position, files);

  @override
  void fileDragLeave() => fileDragLeaveOf(this);

  @override
  void fileDrop(Offset position, List<ComposerFile> files) => fileDropOf(this, position, files);

  void _dropFiles(
    Offset position,
    List<ComposerFile> files, {
    required bool here,
  }) => _dropFilesOf(this, position, files, here: here);

  // --- Prompt history ------------------------------------------------------
  //
  // As upstream's chat input history: ↑ at the start of the input shows
  // the message sent before, ↓ at its end the one after, and past the last,
  // what was being typed.

  /// Where in [_sentPrompts] the history shows (their count: what was
  /// being typed); null when it does not.
  int? _historyAt;

  /// What was being typed when the history was opened.
  String? _historyDraft;

  /// The text the history put in: once it is edited, it is the message
  /// typed, and the history closes.
  String? _historyShown;
  bool _recalling = false;

  List<String> _sentPrompts() => _sentPromptsOf(this);

  void _leaveHistory() => _leaveHistoryOf(this);

  void _showPrompt(int step) => _showPromptOf(this, step);

  // --- Polish --------------------------------------------------------------

  /// The text as the model is given it to polish (see [composerPolishText]).
  ComposerPolishText _polishText() => composerPolishText(_controller.text);

  /// Has the auxiliary model polish the text into a clearer, more specific
  /// prompt (Enhance prompt), its tags, images, code and links kept as they
  /// are, the agent's last turn told to know what it answers; put in its place as one change (⌘Z takes it back), unless the
  /// text changed meanwhile. Why not, in a notification.
  Future<void> _polish() async {
    if (_polishing) return;
    final asked = _polishText();
    if (!asked.hasWords) return;
    final before = _controller.text;
    final notifications = IdeNotificationsScope.maybeOf(context);
    final l10n = context.l10n;
    setState(() => _polishing = true);
    try {
      final String polished;
      try {
        polished = await polishComposerText(
          asked,
          reply: widget.session.lastTurnReply,
          model: widget.session.selected(KernelChoiceKind.model),
          location: widget.session.kernelContext.cwd,
        );
      } on ComposerPolishException catch (error) {
        notifications?.notify(
          IdeSeverity.error,
          l10n.composerPolishFailed(error.message ?? l10n.stashAiNoAnswer),
        );
        return;
      }
      if (!mounted || _controller.text != before) return;
      // One change of its own to undo: not merged with what was typed just
      // before it, nor with what is typed next.
      _controller
        ..breakUndo()
        ..replace(
          0,
          _controller.length,
          polished,
          selection: TextSelection.collapsed(offset: polished.length),
        )
        ..breakUndo();
      _focusNode.requestFocus();
    } finally {
      if (mounted) setState(() => _polishing = false);
    }
  }

  // --- Submit --------------------------------------------------------------

  ComposerMessage _buildMessage() => _buildMessageOf(this);

  OpenEditor? get _editorContext => _editorContextOf(this);

  void _dismissEditorContext() => _dismissEditorContextOf(this);

  bool get _showsStop => _showsStopOf(this);

  void _submit() => _submitOf(this);

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) => buildOf(this, context);

  /// What [build] made, and of what ([_buildInputs]): the same again
  /// while none of it changed, so that the session's every change (an
  /// answer's each word, streaming) does not build the box again, its
  /// pickers and buttons.
  Widget? _built;
  List<Object?>? _builtFrom;

  /// The hovers of the toolbar's mode and model pickers and its context
  /// ring, with the keys that do the same in the input.
  late ({String mode, String model, String ring}) _hovers;

  List<Object?> _buildInputs() => _buildInputsOf(this);

  Widget _buildBox({required bool focused}) => _buildBoxOf(this, focused: focused);

  Widget _buildMenu(BuildContext context) => _buildMenuOf(this, context);

  Widget _buildEditor(BuildContext context) => _buildEditorOf(this, context);

  Widget _buildEditorBody(BuildContext context) => _buildEditorBodyOf(this, context);

  // --- Context menu -------------------------------------------------------
  //
  // A right click opens the system's menu, the caret first put at the
  // click, unless the click is on a selection.

  /// Where a right click went down; null for other presses.
  Offset? _menuPressAt;

  void _handleMenuPointerDown(PointerDownEvent event) => _handleMenuPointerDownOf(this, event);

  void _handleMenuPointerUp(PointerUpEvent event) => _handleMenuPointerUpOf(this, event);

  Future<void> _showContextMenu(Offset position) => _showContextMenuOf(this, position);

  void _selectAll() => _selectAllOf(this);

  // --- Double-click -------------------------------------------------------
  //
  // A double-click with nothing selected selects everything; with text
  // selected it selects a word, as the editor does. Told apart here rather
  // than by the editor: a real click often moves the pointer a pixel or
  // two, past where a drag starts, and then it sees no double-click at all.

  /// How far a press may move and still be a click.
  static const _clickSlop = 6.0;

  /// Where the current plain press came down; null for other presses.
  Offset? _clickDownAt;

  /// Open from a click's up while a press near it is that click's double.
  Timer? _clickWindow;
  Offset? _clickUpAt;

  /// Whether text was selected when the last first click came down.
  bool _clickOnSelection = false;

  /// Whether the current press is a double-click's second.
  bool _secondClick = false;

  void _handleClickDown(PointerDownEvent event) => _handleClickDownOf(this, event);

  void _handleClickUp(PointerUpEvent event) => _handleClickUpOf(this, event);

  double _maxEditorHeight(BuildContext context) => _maxEditorHeightOf(this, context);

  Widget _buildMarkdownEditor(BuildContext context) => _buildMarkdownEditorOf(this, context);

  Widget _buildToolbar() => _buildToolbarOf(this);
}

/// Polish, Enhance prompt as it says (see [ChatComposerState._polish]): a
/// sparkle, spinning while the model answers; faint with no words to polish.
class _PolishButton extends StatelessWidget {
  const _PolishButton({
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    final active = enabled && !busy;
    final icon = Icon(
      busy ? Codicons.loading : Codicons.sparkle,
      size: 14,
      color: enabled ? colors['icon.foreground'] : AppColors.textFaint,
    );
    return IdeHover(
      message: busy ? l10n.composerPolishing : l10n.composerPolishHint,
      child: HoverBuilder(
        cursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
        builder: (context, hovered) => GestureDetector(
          // Keeps the editor's focus.
          onTapDown: (_) {},
          onTap: active ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 23,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active && hovered
                  ? colors['toolbar.hoverBackground']
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: busy ? IdeSpinning(icon) : icon,
          ),
        ),
      ),
    );
  }
}

class _ContextRing extends StatelessWidget {
  const _ContextRing({
    required this.fraction,
    required this.active,
    required this.tooltip,
    required this.onTap,
  });

  final double fraction;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return IdeHover(
      message: tooltip,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 23,
            height: 22,
            // The ring keeps its square: the box is taller than it.
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active
                  ? colors['toolbar.activeBackground']
                  : hovered
                  ? colors['toolbar.hoverBackground']
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: SizedBox.square(
              dimension: 13,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: fraction),
                duration: const Duration(milliseconds: 400),
                builder: (context, value, _) => CustomPaint(
                  painter: _RingPainter(
                    value,
                    track: colors['disabledForeground'],
                    arc: colors['icon.foreground'],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// As upstream's context usage widget: the track `disabledForeground`, the
/// arc `icon.foreground`.
class _RingPainter extends CustomPainter {
  _RingPainter(this.fraction, {required this.track, required this.arc});

  final double fraction;
  final Color track;
  final Color arc;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect.deflate(1),
      0,
      math.pi * 2,
      false,
      stroke..color = track,
    );
    canvas.drawArc(
      rect.deflate(1),
      -math.pi / 2,
      math.pi * 2 * fraction.clamp(0, 1),
      false,
      stroke..color = arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.track != track ||
      oldDelegate.arc != arc;
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.streaming,
    required this.enabled,
    required this.onSend,
    required this.onStop,
  });

  final bool streaming;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final active = streaming || enabled;
    final colors = themeColors;
    // As upstream's submit button: the primary button's colors; disabled,
    // none but the disabled icon.
    final foreground = colors['button.foreground'];
    // With the keys that do the same, as the keybindings have them.
    const input = {ChatContextKeys.inChatInput: true};
    return IdeHover(
      message: streaming
          ? ChatKeys.titleWithKey(
              context.l10n.composerStop,
              ChatCommandIds.cancel,
              {...input, ChatContextKeys.requestInProgress: true},
            )
          : ChatKeys.titleWithKey(
              context.l10n.cmdChatSubmit,
              ChatCommandIds.submit,
              input,
            ),
      child: HoverBuilder(
        cursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
        builder: (context, hovered) => GestureDetector(
          onTap: streaming ? onStop : (enabled ? onSend : null),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: !active
                  ? Colors.transparent
                  : hovered
                  ? colors['button.hoverBackground']
                  : colors['button.background'],
              shape: BoxShape.circle,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: streaming
                  ? Container(
                      key: const ValueKey('stop'),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: foreground,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    )
                  : Icon(
                      key: const ValueKey('send'),
                      Icons.arrow_upward_rounded,
                      size: 15,
                      color: active ? foreground : AppColors.textFaint,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

typedef _ShownOfText = ({
  Object menu,
  Map<int, ImageAttachment> pool,
  bool canSend,
  bool polishable,
});
