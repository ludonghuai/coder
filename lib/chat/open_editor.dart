import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:flutter/services.dart' show TextSelection;

import 'chat_models.dart';

/// The file in front in the editor beside a conversation (the IDE's, the
/// side panel's): the agent is told of it with the user's next message, as
/// Claude Code is told of the file open in an IDE.
class OpenEditor {
  const OpenEditor(
    this.path, {
    this.line,
    this.selectedLines,
    this.selectedText,
  });

  /// Where the cursor of [selection] is in [snapshot], [path]'s text, and
  /// the lines and text it selects.
  factory OpenEditor.at(
    String path,
    DocumentSnapshot snapshot,
    TextSelection? selection,
  ) {
    if (selection == null || !selection.isValid) return OpenEditor(path);
    int lineAt(int offset) => snapshot.positionAtOffset(offset).lineNumber;
    final line = lineAt(selection.extentOffset);
    if (selection.isCollapsed) return OpenEditor(path, line: line);
    final first = lineAt(selection.start);
    final end = snapshot.positionAtOffset(selection.end);
    // Up to the start of a line, as a line selected whole is: not that one.
    final last = end.column == 1 && end.lineNumber > first
        ? end.lineNumber - 1
        : end.lineNumber;
    final length = snapshot.text.length;
    return OpenEditor(
      path,
      line: line,
      selectedLines: (first, last),
      selectedText: snapshot.text.substring(
        selection.start.clamp(0, length),
        selection.end.clamp(0, length),
      ),
    );
  }

  final String path;

  /// The cursor's line, from 1.
  final int? line;

  /// The first and last lines selected, from 1, where something is.
  final (int, int)? selectedLines;

  /// The text selected, where something is.
  final String? selectedText;

  /// The most of [selectedText] the agent is told: a selection of a whole
  /// long file would weigh on every message after.
  static const maxSelectedText = EditorContext.maxSelectedText;

  /// This file as a message's context carries it.
  EditorContext toContext() => EditorContext(
    path,
    line: line,
    selectedLines: selectedLines,
    selectedText: selectedText,
  );

  /// What Claude Code is told: the code selected with it.
  String get note => toContext().note;

  /// What the agent is told once no file is open where one was.
  static const closedNote =
      '<system-reminder>The user no longer has a file open in the '
      'editor.</system-reminder>';

  @override
  bool operator ==(Object other) =>
      other is OpenEditor &&
      other.path == path &&
      other.line == line &&
      other.selectedLines == selectedLines &&
      other.selectedText == selectedText;

  @override
  int get hashCode => Object.hash(path, line, selectedLines, selectedText);
}
