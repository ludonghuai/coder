import 'package:flutter/material.dart';

import '../../ide/ide_hover.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart';
import '../chat_models.dart';

/// The file open in the editor as a message carries it: its icon, its name
/// and the line or the lines selected. The composer's chip takes it off the
/// draft with a ×; a sent message's has none, and is read only.
class EditorContextChip extends StatelessWidget {
  const EditorContextChip({super.key, required this.editor, this.onDismiss});

  final EditorContext editor;

  /// Takes it off the draft: the composer's chip shows it.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = switch ((editor.selectedLines, editor.line)) {
      ((final first, final last), _) when first != last =>
        l10n.editorContextLines(editor.name, first, last),
      (_, final line?) => l10n.editorContextLine(editor.name, line),
      ((final first, _), _) => l10n.editorContextLine(editor.name, first),
      _ => editor.name,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 2, 6, 2),
      decoration: BoxDecoration(
        // As a file's tag in the composer (see ComposerTokenChip).
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: themeColors['chat.requestBorder']),
      ),
      child: SelectionContainer.disabled(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FileIcon(editor.name, size: 14),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
            ),
            if (onDismiss case final onDismiss?) ...[
              const SizedBox(width: 4),
              IdeHover(
                message: l10n.editorContextDismiss,
                // The label below says the same to a screen reader already.
                excludeFromSemantics: true,
                // A button to a screen reader: the icon alone is not one.
                child: Semantics(
                  button: true,
                  label: l10n.editorContextDismiss,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onDismiss,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Codicons.close,
                        size: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The editor contexts a message carries, side by side, read only.
class EditorContextChips extends StatelessWidget {
  const EditorContextChips({super.key, required this.contexts});

  final List<EditorContext> contexts;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final editor in contexts) EditorContextChip(editor: editor),
    ],
  );
}
