import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ide/ide_dialog.dart';
import '../../kernel/kernel_types.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_models.dart';
import '../chat_session.dart';
import 'interaction_panel.dart';

/// Whether [plan] has nothing to do or to tell (§9): no file to put back,
/// to skip, or to call unrevertable.
bool isRevertPlanEmpty(RevertPlan plan) =>
    plan.files.isEmpty && plan.skipped.isEmpty && plan.unrevertable.isEmpty;

/// The reason [reason] as [l10n] words it (§9); the kernel's own words when
/// it is one this build does not know.
String revertReason(AppLocalizations l10n, String reason) => switch (reason) {
  'changed' => l10n.revertReasonChanged,
  'oversize' => l10n.revertReasonOversize,
  'evicted' => l10n.revertReasonEvicted,
  'after-unknown' => l10n.revertReasonAfterUnknown,
  _ => reason,
};

/// What the revert did, in one line of the conversation's own (§9): the
/// three counts, zero ones left out.
String revertSummary(AppLocalizations l10n, RevertOutcome outcome) => [
  if (outcome.files.isNotEmpty)
    l10n.revertSummaryRestored(outcome.files.length),
  if (outcome.skipped.isNotEmpty)
    l10n.revertSummarySkipped(outcome.skipped.length),
  if (outcome.unrevertable.isNotEmpty)
    l10n.revertSummaryUnrevertable(outcome.unrevertable.length),
].join(' · ');

/// Reverts [sinceTurn]'s files for [session]: planned by the kernel, put to
/// the user ([confirm]), then done once they agree (§9, D-SG5).
///
/// Nothing is written unless [confirm] says so: a plan refused, or nothing
/// to revert ([empty]), leaves the files as they were (A7). [blocked] says
/// a turn started meanwhile; [done] takes the outcome, e.g. to show it.
Future<RevertOutcome?> revertFiles(
  ChatSession session,
  String sinceTurn, {
  required Future<bool> Function(RevertPlan plan) confirm,
  required AppLocalizations l10n,
  Future<void> Function()? empty,
  Future<void> Function()? blocked,
  Future<void> Function(RevertOutcome outcome)? done,
}) async {
  final plan = await session.revertPlan(sinceTurn);
  if (isRevertPlanEmpty(plan)) {
    await empty?.call();
    return null;
  }
  if (!await confirm(plan)) return null;
  // A turn may have started while the dialog stood (§3.5): it waits.
  if (!session.canPlanRevert) {
    await blocked?.call();
    return null;
  }
  final outcome = await session.applyRevert(sinceTurn);
  // The kernel sends none of the summary itself: the host words it (§9).
  final summary = revertSummary(l10n, outcome);
  if (summary.isNotEmpty) {
    session.addNotice(NoticeItem(NoticeKind.info, summary));
  }
  await done?.call(outcome);
  return outcome;
}

/// Reverts [sinceTurn]'s files for [session], through its dialogs: the
/// kernel's plan, the confirmation (Cancel the default), the result (§9).
/// A revert that cannot run is already told in the conversation (G8).
Future<void> revertFilesFrom(
  BuildContext context,
  ChatSession session,
  String sinceTurn,
) async {
  final l10n = context.l10n;
  try {
    await revertFiles(
      session,
      sinceTurn,
      l10n: l10n,
      empty: () => showIdeDialog(
        context,
        message: l10n.revertNothingToRevert,
        buttons: [l10n.commonOk],
        cancel: null,
        type: IdeDialogType.info,
      ),
      confirm: (plan) => _confirm(context, plan),
      blocked: () => showIdeDialog(context, message: l10n.revertTurnInFlight,
          buttons: [l10n.commonOk], cancel: null, type: IdeDialogType.info),
      done: (outcome) => _showResult(context, outcome),
    );
  } on Object {
    // The kernel said why, in the conversation already (§9).
  }
}

Future<bool> _confirm(BuildContext context, RevertPlan plan) async {
  if (!context.mounted) return false;
  return await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: true,
        barrierLabel: context.l10n.commonDismiss,
        barrierColor: const Color(0x80000000),
        pageBuilder: (context, _, _) => _RevertDialog(plan),
      ) ??
      false;
}

Future<void> _showResult(BuildContext context, RevertOutcome outcome) async {
  if (!context.mounted) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: context.l10n.commonDismiss,
    barrierColor: const Color(0x80000000),
    pageBuilder: (context, _, _) => _RevertResultDialog(outcome),
  );
}

String _name(String path, String? displayPath) => displayPath ?? path;

String _skipLine(AppLocalizations l10n, RevertSkip skip) =>
    '${_name(skip.path, skip.displayPath)} · ${revertReason(l10n, skip.reason)}';

/// The groups of what a plan leaves alone: skipped, then unrevertable.
List<(String, List<String>)> _planGroups(
  AppLocalizations l10n,
  RevertPlan plan,
) => [
  if (plan.skipped.isNotEmpty)
    (l10n.revertGroupSkipped, [
      for (final skip in plan.skipped) _skipLine(l10n, skip),
    ]),
  if (plan.unrevertable.isNotEmpty)
    (l10n.revertUnrevertable, [
      for (final skip in plan.unrevertable) _skipLine(l10n, skip),
    ]),
];

/// The groups of what a revert did, zero ones left out (§9).
List<(String, List<String>)> _outcomeGroups(
  AppLocalizations l10n,
  RevertOutcome outcome,
) => [
  if (outcome.files.isNotEmpty)
    (l10n.revertGroupRestored, [
      for (final file in outcome.files) _name(file.path, file.displayPath),
    ]),
  ..._planGroups(l10n, outcome),
  if (outcome.failed.isNotEmpty)
    (l10n.revertGroupFailed, [
      for (final failure in outcome.failed)
        '${_name(failure.path, failure.displayPath)} · ${failure.error}',
    ]),
];

/// The kernel's plan, put before the user (§9): the files it puts back,
/// those it leaves and why, and what doing it would lose.
class _RevertDialog extends StatelessWidget {
  const _RevertDialog(this.plan);

  final RevertPlan plan;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _DialogFrame(
      title: l10n.revertTitle,
      body: [
        Text(
          l10n.revertFileCount(plan.files.length),
          style: TextStyle(color: AppColors.text, fontSize: 13),
        ),
        if (plan.files.isNotEmpty) ...[
          const SizedBox(height: 6),
          _Lines([
            for (final file in plan.files) _name(file.path, file.displayPath),
          ]),
        ],
        for (final (title, lines) in _planGroups(l10n, plan)) ...[
          _GroupTitle(title),
          _Lines(lines),
        ],
        const SizedBox(height: 10),
        Text(
          l10n.revertWarning,
          style: TextStyle(color: themeColors['errorForeground'], fontSize: 12),
        ),
      ],
      actions: [
        PanelButton(
          label: l10n.commonCancel,
          onTap: () => Navigator.pop(context, false),
        ),
        PanelButton(
          label: l10n.revertConfirm,
          primary: true,
          onTap: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}

/// What a revert did (§9): each group with its count, none with nothing.
class _RevertResultDialog extends StatelessWidget {
  const _RevertResultDialog(this.outcome);

  final RevertOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _DialogFrame(
      title: l10n.revertDone,
      body: [
        for (final (title, lines) in _outcomeGroups(l10n, outcome)) ...[
          _GroupTitle('$title (${lines.length})'),
          _Lines(lines),
        ],
      ],
      actions: [
        PanelButton(
          label: l10n.commonClose,
          primary: true,
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

/// The dialogs' box: [title], then [children], [actions] under them; Escape
/// and Enter take the default (Cancel, or closing).
class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.title,
    required this.body,
    required this.actions,
  });

  final String title;
  final List<Widget> body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.pop(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): close,
        const SingleActivator(LogicalKeyboardKey.enter): close,
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...body,
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (final (i, action) in actions.indexed) ...[
                        if (i > 0) const SizedBox(width: 8),
                        action,
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A group's name over its lines.
class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 2),
    child: Text(
      text,
      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
    ),
  );
}

/// A plan's lines, scrolled past the confirmation's twelve.
class _Lines extends StatelessWidget {
  const _Lines(this.lines);

  final List<String> lines;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 18.0 * 12),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            SizedBox(
              height: 18,
              child: Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: themeColors['editorWidget.foreground'],
                  fontFamily: AppFonts.mono,
                  fontFamilyFallback: AppFonts.monoFallbacks,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
