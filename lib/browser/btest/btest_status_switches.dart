import 'package:flutter/material.dart';

import '../../chat/chat_session.dart';
import '../../chat/composer/composer_picker.dart';
import '../../kernel/kernel_types.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import 'btest_policy.dart';

/// btest's status line at the composer's top while the mode is on
/// (design §9): the line, how the round walks, whether it may act, and the
/// run's number — or that none has started. The two switches sit at the
/// line's end (§9.1): with a run under way the line reads the run's own
/// values, while the switches keep what the next run will take.
///
/// Split out of `composer.dart` by SPLIT-6; the composer keeps the call.
class BtestStatusLine extends StatelessWidget {
  const BtestStatusLine({
    super.key,
    required this.session,
    this.tapRegionGroupId,
    this.focusNode,
  });

  /// The conversation whose run and switches the line reads.
  final ChatSession session;

  /// Group of the region around the whole composer, which the switches'
  /// menus count as part of (see `FloatingLayer.outerTapRegionGroupId`).
  final Object? tapRegionGroupId;

  /// The input the switches belong to. Opening a menu focuses it: keys reach
  /// the open menu through it (`FloatingRegistry.handleKey`).
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final run = session.btestRun;
    final traversal = run?.traversal ?? session.btestTraversal;
    final write =
        run == null ? session.btestWrite : run.face == BtestFace.write;
    final face = write ? l10n.btestFaceWrite : l10n.btestFaceReadonly;
    final walking = traversal == BtestTraversal.chain
        ? l10n.btestTraversalDepth
        : l10n.btestTraversalBreadth;
    final text = switch (run) {
      final run? => l10n.btestStatusRun(run.line, walking, face, run.number),
      null => l10n.btestStatusIdle(walking, face),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _switch(
            key: const ValueKey('btest-traversal-switch'),
            options: [
              KernelOption(
                BtestTraversal.chain.name,
                l10n.btestTraversalDepth,
                Icons.arrow_downward_rounded,
                '',
              ),
              KernelOption(
                BtestTraversal.surface.name,
                l10n.btestTraversalBreadth,
                Icons.grid_view_rounded,
                '',
              ),
            ],
            selected: session.btestTraversal.name,
            // The ids are this switch's own options; one that does not parse
            // is left alone rather than written as another value.
            onSelected: (id) {
              if (BtestTraversal.parse(id) case final picked?) {
                session.setBtestTraversal(picked);
              }
            },
          ),
          const SizedBox(width: 2),
          _switch(
            key: const ValueKey('btest-write-switch'),
            options: [
              KernelOption(
                BtestFace.readonly.name,
                l10n.btestFaceReadonly,
                Icons.visibility_outlined,
                '',
              ),
              KernelOption(
                BtestFace.write.name,
                l10n.btestFaceWrite,
                Icons.edit_outlined,
                '',
              ),
            ],
            selected: (session.btestWrite ? BtestFace.write : BtestFace.readonly)
                .name,
            onSelected: (id) {
              if (BtestFace.parse(id) case final picked?) {
                session.setBtestWrite(picked == BtestFace.write);
              }
            },
          ),
        ],
      ),
    );
  }

  /// One of btest's two switches (§9.1): a compact picker — the pill reads
  /// the value in effect, its menu the two. The options are named after the
  /// run's values (`chain` / `surface`, `readonly` / `write`), so the pill
  /// and the report's head line say the same word for the same value.
  ///
  /// A semantics container of its own: the picker's menu is grafted under
  /// its pill in the semantics tree, and that graft needs a node of the
  /// pill's to hang from. The toolbar's pickers get one from the scrollable
  /// row they sit in; here there is none, and without it the desktop
  /// engines reject the update that shows the menu — the check that holds
  /// tests to their semantics tree fails on it, and on Windows the bridge
  /// logs it and can part ways with the framework over it.
  Widget _switch({
    required Key key,
    required List<KernelOption> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) => Semantics(
    container: true,
    child: ComposerPicker(
      key: key,
      options: options,
      selected: options.firstWhere((option) => option.id == selected),
      // The switch names a value, not a feature: no descriptions under them.
      describes: false,
      menuWidth: 150,
      tapRegionGroupId: tapRegionGroupId,
      focusNode: focusNode,
      onSelected: (option) => onSelected(option.id),
    ),
  );
}
