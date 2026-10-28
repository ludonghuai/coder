part of 'composer.dart';

// The editing face of the composer: the text and what is put in it —
// images, files and the draft kept while the composer is gone — and
// the atoms the text is edited around.

Map<int, ImageAttachment> _initialPoolOf(ChatComposerState state) {
  if (state.widget.draft case final draft? when draft.saved) {
    return {for (final image in draft.images) ?image.number: image};
  }
  final pool = <int, ImageAttachment>{};
  var next = state.widget.session.lastImageNumber + 1;
  for (final image in state.widget.initialImages) {
    if (image.number case final number?) {
      pool[number] = image;
      next = math.max(next, number + 1);
    }
  }
  // Sent before images were numbered: numbered now.
  for (final image in state.widget.initialImages) {
    if (image.number != null) continue;
    pool[next] = image.withNumber(next);
    next++;
  }
  return pool;
}

ComposerController _createControllerOf(ChatComposerState state) {
  if (state.widget.draft case final draft? when draft.saved) {
    final content = draft.content!;
    final end = content.length;
    return ComposerController(
      text: content,
      selection: TextSelection(
        baseOffset: draft.selection.baseOffset.clamp(0, end),
        extentOffset: draft.selection.extentOffset.clamp(0, end),
      ),
    );
  }
  var text = state.widget.initialText ?? '';
  final numbers = state._pool.keys.toSet();
  // Every image referred to: those the text does not, at its start.
  final referred = {
    for (final match in imageReferencePattern.allMatches(text))
      int.parse(match[1]!),
  };
  final unreferred = numbers.where((n) => !referred.contains(n)).toList();
  if (unreferred.isNotEmpty) {
    text = [unreferred.map(imageReference).join(' '), text].join(' ');
  }
  if (text.isEmpty) return ComposerController();
  final content = composerContentFromText(
    text,
    ComposerVocabulary.read(state.context),
    images: numbers,
  );
  return ComposerController(
    text: content,
    selection: TextSelection.collapsed(offset: content.length),
  );
}

/// Pastes what the clipboard holds: copied files as tags of their paths
/// (images as images), code the IDE's editor copied as a tag of its lines,
/// a picture (a screenshot), or else its plain text, with its `@paths`
/// (and a leading /command) as tags, as the message will show once sent:
/// copied from the history or from elsewhere alike. (What this editor
/// copied itself, its tags and all, the editor pastes back as it was.)
/// Returns false for nothing to paste. With `raw` (⇧⌘V / Ctrl+Shift+V),
/// its text goes in as it is, past the long-paste tag; files and images
/// still come in as such.
Future<bool> _pasteOf(ChatComposerState state, {bool raw = false}) async {
  final files = await WindowControls.readPasteboardFiles();
  if (!state.mounted) return false;
  if (files.isNotEmpty) {
    await state.insertFiles(files, here: true);
    return true;
  }
  final text = await WindowControls.readPasteboardText();
  if (!state.mounted) return false;
  if (text != null && !raw) {
    if (CopiedCode.matching(text) case final code?) {
      state._insertTags([
        ComposerCodeEmbed.of(
          code.withPath(displayPath(code.path, state.widget.session.root)),
        ),
      ]);
      return true;
    }
  }
  if (state.widget.session.acceptsImages) {
    final images = await WindowControls.readPasteboardImages();
    if (images.isNotEmpty) {
      await state._addImages(images);
      return true;
    }
  }
  if (text == null || !state.mounted) return false;
  var plain = MdAtoms.strip(text.replaceAll('\r\n', '\n'));
  if (state.widget.session.acceptsImages) {
    plain = await state._picturesIn(plain);
    if (!state.mounted) return false;
  }
  // Pasted raw, the text goes in as it is, whatever its length: no paste
  // tag (the shortcut is for exactly that), and no attachment offload,
  // which happens as the message is sent (see PasteStore.offload).
  if (!raw && PastedText.isLong(plain)) {
    state._insertTags([
      ComposerPastedTextEmbed.of(
        PastedText(number: state._nextPastedNumber(), text: plain),
      ),
    ]);
    return true;
  }
  final selection = state._controller.selection;
  final start = selection.isValid ? selection.start : state._controller.length;
  final end = selection.isValid ? selection.end : start;
  final content = raw
      ? plain
      : composerContentFromPaste(
          plain,
          ComposerVocabulary.read(state.context),
          atStart: start == 0,
          images: state._pool.keys.toSet(),
        );
  state._controller
    ..breakUndo()
    ..replace(start, end, content)
    ..breakUndo();
  return true;
}

/// The number for a long paste: one past the highest the text has.
int _nextPastedNumberOf(ChatComposerState state) {
  var highest = 0;
  for (final (:embed, start: _, end: _) in state._controller.embeds) {
    if (embed.type == ComposerPastedTextEmbed.type) {
      highest = math.max(
        highest,
        ComposerPastedTextEmbed.decode(embed.data).number,
      );
    }
  }
  return highest + 1;
}

/// The numbers of the images the text refers to, in its order, with
/// where each reference is.
Iterable<({int number, int offset})> _referencesOf(ChatComposerState state) sync* {
  for (final (:embed, :start, end: _) in state._controller.embeds) {
    if (embed.type == ComposerImageEmbed.type) {
      yield (number: ComposerImageEmbed.decode(embed.data), offset: start);
    }
  }
}

List<ImageAttachment> _referredImagesOf(ChatComposerState state) => [
  for (final number in {for (final r in state._references()) r.number})
    ?state._pool[number],
];

/// Puts [images] in at [at] (in place of the selection when null), each
/// as a reference in the text, numbered on from the conversation's last.
Future<void> _addImagesOf(ChatComposerState state, List<ImageAttachment> images, {int? at}) async {
  final added = (await state._numbered(images)).nonNulls;
  if (!state.mounted || added.isEmpty) return;
  state._insertTags([
    for (final image in added) ComposerImageEmbed.of(image.number!),
  ], at: at);
}

/// [images] made ready to send (see [prepareImage]), numbered on from the
/// conversation's last and put in the pool, in their places: null for
/// those that are no images, or past the most a message takes.
Future<List<ImageAttachment?>> _numberedOf(
  ChatComposerState state,
  List<ImageAttachment?> images,
) async {
  final prepared = await Future.wait([
    for (final image in images)
      image == null ? Future<ImageAttachment?>.value() : prepareImage(image),
  ]);
  if (!state.mounted) return [for (final _ in images) null];
  var next =
      math.max(state.widget.session.lastImageNumber, state._pool.keys.fold(0, math.max)) +
      1;
  var room = ChatComposerState._maxImages - state._images.length;
  final numbered = [
    for (final image in prepared)
      image != null && room-- > 0 ? image.withNumber(next++) : null,
  ];
  state._pool = {
    ...state._pool,
    for (final image in numbered.nonNulls) image.number!: image,
  };
  return numbered;
}

/// Puts [files] in at [at] (in place of the selection when null), in
/// their order: each a tag of its path, from the project's root when it
/// is in it, or, for an image the conversation takes, the image. [here],
/// they are this machine's: a remote project's agent is given copies on
/// its host ([ChatComposer.hostFiles]), those that could not be copied
/// left out.
Future<void> insertFilesOf(
  ChatComposerState state,
  List<ComposerFile> files, {
  int? at,
  bool here = false,
}) async {
  if (files.isEmpty) return;
  var images = <ImageAttachment?>[for (final _ in files) null];
  if (state.widget.session.acceptsImages) {
    images = await state._numbered(
      await Future.wait([
        for (final file in files)
          file.maybeImage
              ? WindowControls.readImageFile(file.path)
              : Future<ImageAttachment?>.value(),
      ]),
    );
  }
  if (!state.mounted) return;
  // The pictures go with the message as they are; the rest are copied.
  final List<ComposerFile?> paths = [
    for (final (index, file) in files.indexed)
      images[index] == null ? file : null,
  ];
  if (here && state.widget.hostFiles != null && paths.nonNulls.isNotEmpty) {
    final copies = await state._copyToHost(paths.nonNulls.toList());
    if (!state.mounted) return;
    final copied = copies?.iterator;
    for (var i = 0; i < paths.length; i++) {
      if (paths[i] == null) continue;
      paths[i] = copied != null && copied.moveNext() ? copied.current : null;
    }
  }
  final root = state.widget.session.root;
  state._insertTags([
    for (final (index, file) in files.indexed)
      if (images[index] case final image?)
        ComposerImageEmbed.of(image.number!)
      else if (paths[index] case final path?)
        ComposerTokenEmbed.file(
          displayPath(path.path, root),
          directory: file.directory,
        ),
  ], at: at);
}

/// [files], this machine's, copied onto the remote project's host, how
/// far told in a notification once it takes a moment; null when they
/// could not be, as a notification says.
Future<List<ComposerFile>?> _copyToHostOf(ChatComposerState state, List<ComposerFile> files) async {
  final notifications = IdeNotificationsScope.maybeOf(state.context);
  final l10n = state.context.l10n;
  var done = 0;
  var total = files.length;
  IdeNotification? shown;
  IdeNotificationProgress progress() =>
      IdeNotificationProgress(done.toDouble(), total: total.toDouble());
  final timer = notifications == null
      ? null
      : Timer(const Duration(milliseconds: 300), () {
          shown = notifications.notify(
            IdeSeverity.info,
            l10n.explorerUploading(done, total),
            progress: progress(),
            sticky: true,
          );
        });
  try {
    return await RemoteDrops.copy(
      state.widget.hostFiles!,
      files,
      onProgress: (worked, of) {
        done = worked;
        total = of;
        if (shown case final shown?) {
          notifications!.update(
            shown,
            message: l10n.explorerUploading(done, total),
            progress: progress(),
          );
        }
      },
    );
  } on Object catch (error) {
    notifications?.notify(
      IdeSeverity.error,
      l10n.composerCopyToHostFailed('$error'),
    );
    return null;
  } finally {
    timer?.cancel();
    if (shown case final shown?) notifications!.close(shown);
  }
}

/// [text]'s `@paths` of pictures that go in as such ([pastedAsPicture]:
/// copied out of a stash) as the pictures: read, numbered, and referred
/// to as `[Image #N]`, which the paste makes their tags.
Future<String> _picturesInOf(ChatComposerState state, String text) async {
  final found = <(int, int, String)>[];
  for (var i = 0; i < text.length; i++) {
    if (text[i] != '@' || (i > 0 && text[i - 1].trim().isNotEmpty)) continue;
    if (parseFileReference(text, i)
        case (:final path, directory: false, :final end)
        when pastedAsPicture(path)) {
      found.add((i, end, path));
      i = end - 1;
    }
  }
  if (found.isEmpty) return text;
  final images = await state._numbered(
    await Future.wait([
      for (final (_, _, path) in found) WindowControls.readImageFile(path),
    ]),
  );
  final out = StringBuffer();
  var at = 0;
  for (final (i, (start, end, _)) in found.indexed) {
    final image = images[i];
    if (image == null) continue;
    out
      ..write(text.substring(at, start))
      ..write(imageReference(image.number!));
    at = end;
  }
  out.write(text.substring(at));
  return out.toString();
}

/// Puts [tags] in at [at] (in place of the selection when null), apart
/// from a word before them, each followed by a space, so that none is
/// the last thing on its line (see [_padTrailingTokens]); the caret after
/// them. One edit, undone as one.
void _insertTagsOf(ChatComposerState state, List<ComposerEmbed> tags, {int? at}) {
  if (tags.isEmpty) return;
  final selection = state._controller.selection;
  final end = state._controller.length;
  final start = (at ?? (selection.isValid ? selection.start : end)).clamp(
    0,
    end,
  );
  final replaced = at == null && selection.isValid
      ? math.max(0, selection.end - start)
      : 0;
  final text = state._controller.text;
  final content = StringBuffer();
  if (start > 0 && text[start - 1].trim().isNotEmpty) content.write(' ');
  for (final tag in tags) {
    content
      ..write(tag.atom)
      ..write(' ');
  }
  state._controller
    ..breakUndo()
    ..replace(start, start + replaced, content.toString())
    ..breakUndo();
  state._focusNode.requestFocus();
}

bool _canSendOf(ChatComposerState state) => state._hasContent || state._images.isNotEmpty;

/// Whether [offset] of [text] is inside an atom (after its opening mark,
/// before or at its closing one).
bool _inAtomOf(String text, int offset) {
  if (offset <= 0 || offset > text.length) return false;
  final open = text.lastIndexOf(MdAtoms.open, offset - 1);
  if (open < 0) return false;
  final close = text.lastIndexOf(MdAtoms.close, offset - 1);
  return close < open;
}

/// What the box shows that follows the text, besides the text (which
/// the editor shows itself): the menu, the images, whether the message
/// can be sent and polished. A key typed that changes none of it since
/// the box was built ([_shownBuilt]) does not build it again (its
/// pickers, its buttons).
_ShownOfText _shownOfTextOf(ChatComposerState state) => (
  menu: (state._trigger != null, state._menuX, state._menuKind, state._matches, state._highlighted),
  pool: state._pool,
  canSend: state._canSend,
  polishable: ComposerPolishSetting.current() && state._hasWords(),
);

/// Whether the text has words to polish: read again only once it
/// changed, not each time the session builds the box.
bool _hasWordsOf(ChatComposerState state) {
  final version = state._controller.textVersion;
  if (version != state._wordsVersion) {
    state._wordsVersion = version;
    state._words = state._polishText().hasWords;
  }
  return state._words;
}

void _handleEditorChangedOf(ChatComposerState state) {
  // The placeholder of a drag coming and going: not the user's edit.
  if (state._ghosting) return;
  if (state._padTrailingTokens()) return; // Re-entered with the fixed text.
  state._images = state._referredImages();
  state._saveDraft();
  final text = state._controller.text;
  // Edited, a message recalled from the history is the one typed.
  if (state._historyAt != null && !state._recalling && text != state._historyShown) {
    state._leaveHistory();
  }
  final hasContent = text.trim().isNotEmpty;
  final trigger = state._findTrigger(text);

  if (trigger == null || !trigger.sameAnchor(state._dismissedTrigger)) {
    state._dismissedTrigger = null;
  }
  var visible = trigger != null && state._dismissedTrigger == null;
  final vocabulary = ComposerVocabulary.read(state.context);
  // An @ with no file to look up and no other conversation to refer to
  // stays text.
  if (visible && trigger.kind == SuggestionKind.file) {
    if (!trigger.sameAnchor(state._trigger)) {
      state._sessions = vocabulary.sessions?.call() ?? [];
      state._stashes = vocabulary.stashes?.call() ?? [];
    }
    visible =
        vocabulary.suggestFiles != null ||
        state._sessions.isNotEmpty ||
        state._stashes.isNotEmpty;
  }
  // A / within the message that starts no command's name (e.g. a path's)
  // stays text; and for a kernel with no command source (thincoder's) no
  // panel opens, at the message's start as much as within it. One with a
  // source opens it at a start for any query — none in its list yet, or
  // none matching — so that it can say there are none. The source is the
  // kernel's capability, not its table; the matches come from the same
  // session's vocabulary, which that table fills.
  List<SuggestionMatch>? commands;
  if (visible && trigger != null && trigger.kind == SuggestionKind.command) {
    commands = rankSuggestions(vocabulary.commands, trigger.query);
    visible =
        commands.isNotEmpty ||
        (trigger.start == 0 && state.widget.session.hasCommandSource);
  }

  if (visible) {
    final queryChanged =
        !trigger!.sameAnchor(state._trigger) || trigger.query != state._trigger!.query;
    if (queryChanged) {
      if (trigger.kind == SuggestionKind.file) {
        state._matches = state._rankOthers(trigger.query);
        if (vocabulary.suggestFiles case final suggest?) {
          unawaited(state._lookUpFiles(trigger, suggest));
        }
      } else {
        state._matches =
            commands ?? rankSuggestions(vocabulary.commands, trigger.query);
      }
      state._highlighted = 0;
    }
    state._menuKind = trigger.kind;
    state._highlighted = state._highlighted.clamp(0, math.max(0, state._matches.length - 1));
    state._menuX = state._caretX(trigger.start);
  }
  state._trigger = visible ? trigger : null;
  state._syncMenuRegistration();
  state._hasContent = hasContent;
  if (state._shownOfText() != state._shownBuilt) state._setState(() {});
}
