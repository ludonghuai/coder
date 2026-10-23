import 'package:path/path.dart' as p;

// The editor-context face of the chat models: the file open in the editor
// beside a conversation as a message is sent, and the text contexts that
// have no file behind them.

/// The file open in the editor beside a conversation, as a message is sent:
/// its path, the cursor's line and what is selected.
class EditorContext {
  const EditorContext(
    this.path, {
    this.line,
    this.selectedLines,
    this.selectedText,
  });

  /// The most of [selectedText] the agent is told: a selection of a whole
  /// long file would weigh on every message after.
  static const maxSelectedText = 10000;

  /// Where the file is, absolute.
  final String path;

  /// The cursor's line, from 1; null with a file open but no cursor (the
  /// editor's state not up, a selection that is not valid, a media
  /// document).
  final int? line;

  /// The first and last lines selected, from 1, where something is.
  final (int, int)? selectedLines;

  /// The text selected, where something is.
  final String? selectedText;

  /// The file's name, for the chip the message shows.
  String get name => p.basename(path);

  /// [path] absolute and normalized: one file is one context a turn.
  String get dedupeKey => p.normalize(p.absolute(path));

  /// What Claude Code is told of it: the selection where there is one, the
  /// cursor line where there is no selection, the path alone otherwise.
  String get note {
    final opened = switch ((line, _lines)) {
      (_, final lines?) => 'The user selected $lines of $path in the editor',
      (final line?, null) =>
        'The user has $path open in the editor, the cursor on line $line',
      _ => 'The user has $path open in the editor',
    };
    return _reminder(opened, _selectedText());
  }

  /// What thincoder is told of it: the cursor's line with a selection too;
  /// with no cursor, the path alone.
  String get editorNote {
    if (line == null) {
      return _reminder('The user has $path open in the editor', '. ');
    }
    final opened = switch (_lines) {
      final lines? =>
        'The user has $path open in the editor, the cursor on line $line; '
            'the user selected $lines of $path in the editor',
      null => 'The user has $path open in the editor, the cursor on line $line',
    };
    return _reminder(opened, _lines == null ? '. ' : _selectedText());
  }

  String? get _lines => switch (selectedLines) {
    (final first, final last) when first == last => 'line $first',
    (final first, final last) => 'lines $first-$last',
    null => null,
  };

  String _selectedText() => switch (selectedText) {
    final text? when text.length > maxSelectedText =>
      ':\n${text.substring(0, maxSelectedText)}\n'
          '[${text.length - maxSelectedText} more characters selected, '
          'not shown: read the file for them]\n\n',
    final text? when text.isNotEmpty => ':\n$text\n\n',
    _ => '. ',
  };

  static String _reminder(String opened, String selected) =>
      '<system-reminder>$opened$selected'
      'This may or may not be related to the current task.</system-reminder>';
}

/// A turn's context that has no file behind it: the host's own words to the
/// agent, told as they are (btest's mode card, and the line that ends it).
class TextContext extends EditorContext {
  const TextContext({
    required String key,
    required this.name,
    required this.text,
  }) : super(key);

  /// What it shows as, where a file's name would.
  @override
  final String name;

  /// What the agent is told, as it stands.
  final String text;

  /// The same context never repeats: [path] (its key) as it is, not a path
  /// made absolute.
  @override
  String get dedupeKey => path;

  @override
  String get note => text;

  @override
  String get editorNote => text;
}
