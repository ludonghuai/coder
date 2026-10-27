import '../../browser/btest/btest_card.dart';
import '../../browser/btest/btest_mode.dart';
import '../../kernel/transcript.dart';
import '../chat_models.dart';
import '../open_editor.dart';

// What a turn is sent with, gathered here: the editors as contexts (one per
// file), and btest's card or the line that ends it — counted from the
// conversation itself, never from a flag in memory.

/// [editors] as a turn's contexts: one per file, by canonical absolute
/// path (a turn may gather them from several sources).
List<EditorContext> contextsOf(Iterable<OpenEditor> editors) {
  final seen = <String>{};
  final contexts = <EditorContext>[];
  for (final editor in editors) {
    final context = editor.toContext();
    if (seen.add(context.dedupeKey)) contexts.add(context);
  }
  return contexts;
}

/// What btest adds to the turn being assembled (§3.2): the card on the
/// first turn in the mode, the line that ends it on the first turn after.
List<EditorContext> btestContextsOf(BtestState btest, Transcript transcript) {
  final told = BtestCard.forTurn(
    on: btest.on,
    transcript: toldTextsOf(transcript),
  );
  if (told == null) return const [];
  return [TextContext(key: BtestCard.contextKey, name: 'btest', text: told)];
}

/// Every text the conversation holds, for the card count: the messages',
/// and the notes of the contexts sent with them.
Iterable<String> toldTextsOf(Transcript transcript) sync* {
  for (var i = 0; i < transcript.length; i++) {
    if (transcript.itemAt(i) case final UserMessageItem message) {
      yield message.text;
      for (final context in message.contexts) {
        yield context.editorNote;
      }
    }
  }
}
