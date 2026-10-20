import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;

/// Inline editor for a title: Enter saves, Esc cancels; blank or past 80
/// stays open, saying why (§9).
class InlineRenameField extends StatefulWidget {
  const InlineRenameField({
    super.key,
    required this.initial,
    required this.onDone,
    this.style,
    this.checksTitle = true,
  });

  final String initial;

  /// The new text, or null when cancelled.
  final ValueChanged<String?> onDone;

  /// [AppColors.textPrimary] at 12.5 when null.
  final TextStyle? style;

  /// Whether it takes a title: blank and past 80 refused (§9); a name that
  /// may be cleared (a host's) says false.
  final bool checksTitle;
  @override
  State<InlineRenameField> createState() => _InlineRenameFieldState();
}

class _InlineRenameFieldState extends State<InlineRenameField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initial.length,
        );
  final FocusNode _focus = FocusNode();
  bool _done = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _finish(_controller.text);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String? _errorIn(String title) {
    if (!widget.checksTitle) return null;
    final trimmed = title.trim();
    if (trimmed.isEmpty) return context.l10n.renameTitleRequired;
    // 80: the kernel's own limit (`MAX_TITLE_LENGTH`, design §3.1 / U5).
    return trimmed.length > 80
        ? context.l10n.renameTitleTooLong
        : null;
  }

  void _finish(String? title) {
    if (_done) return;
    final error = title == null ? null : _errorIn(title);
    if (error != null) {
      setState(() => _error = error);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
      return;
    }
    _done = true;
    widget.onDone(title);
  }

  @override
  Widget build(BuildContext context) {
    // An input box, focused, as upstream's inline rename.
    final colors = themeColors;
    final border = OutlineInputBorder(
      borderSide: BorderSide(color: colors['focusBorder']),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => _finish(null),
      },
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        onSubmitted: _finish,
        onChanged: (_) { if (_error != null) setState(() => _error = null); },
        style:
            widget.style ??
            TextStyle(color: AppColors.textPrimary, fontSize: 12.5),
        cursorColor: AppColors.text,
        cursorHeight: 14,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          filled: true,
          fillColor: colors['input.background'],
          enabledBorder: border,
          focusedBorder: border,
          suffixText: _error,
          suffixStyle: TextStyle(color: colors['errorForeground'], fontSize: 10.5),
        ),
      ),
    );
  }
}
