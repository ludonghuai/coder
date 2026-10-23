part of '../chat_session.dart';

// What a turn is sent with, gathered here: the image numbered last, the
// note the agent is told of the open editor, and the editors as contexts
// (one per file). The seen flags they read stay in the class.

/// The number of the last image in the conversation (0 before any): a
/// new one is numbered on from it, as Claude Code numbers what is pasted.
/// Counts what its messages say (`[Image #3]`) too, as Claude Code does.
int _lastImageNumberOf(ChatSession owner) =>
    owner._cached(#lastImageNumber, () {
      var last = 0;
      for (var i = 0; i < owner._transcript.length; i++) {
        if (owner._transcript.itemAt(i) case UserMessageItem(
          :final text,
          :final images,
        )) {
          for (final image in images) {
            last = math.max(last, image.number ?? 0);
          }
          for (final match in imageReferencePattern.allMatches(text)) {
            last = math.max(last, int.parse(match[1]!));
          }
        }
      }
      return last;
    });

/// What the agent is told of [editor], the file open beside the chat now:
/// nothing where it was told so already, nor of no file before any.
List<String> _editorNotesOf(ChatSession owner, OpenEditor? editor) {
  if (owner._toldOfEditor ? editor == owner._toldEditor : editor == null) {
    return const [];
  }
  owner._toldOfEditor = true;
  owner._toldEditor = editor;
  return [editor?.note ?? OpenEditor.closedNote];
}

/// [editors] as a turn's contexts: one per file, by canonical absolute
/// path (a turn may gather them from several sources).
List<EditorContext> _contextsOf(Iterable<OpenEditor> editors) {
  final seen = <String>{};
  final contexts = <EditorContext>[];
  for (final editor in editors) {
    final context = editor.toContext();
    if (seen.add(context.dedupeKey)) contexts.add(context);
  }
  return contexts;
}
