part of '../chat_session.dart';

// The session's own commands: stop the turn, answer the question it
// waits on, rename it, drop what its review kept. Each one word to the
// kernel or the review; nothing is held here.

void _stopOf(ChatSession owner) => owner._kernel.cancel();

void _answerOf(ChatSession owner, InteractionAnswer answer) {
  if (owner.pendingInteraction case final request?) {
    owner._kernel.answer(request.id, answer);
  }
}

void _renameOf(ChatSession owner, String title) {
  if (owner._kernel case final RenamesSession kernel) kernel.rename(title);
}

/// The conversation is deleted: what its review kept goes too.
void _discardChangesOf(ChatSession owner) =>
    unawaited(owner._review?.discard());
