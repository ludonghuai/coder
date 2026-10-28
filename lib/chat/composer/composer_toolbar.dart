part of 'composer.dart';

// The toolbar face of the composer: the row of pickers and the
// actions beside them; the small widgets they are built from sit with
// upstream's block in composer.dart.

Widget _buildToolbarOf(ChatComposerState state) {
  final session = state.widget.session;
  // Only the dock's composer picks the kernel, and only until it starts.
  final kernel = state.widget.onSubmit == null ? session.kernelChoice : null;
  final mode = session.modes;
  final permission = session.permissions;
  final model = session.models;
  final context = session.context;
  final l10n = state.context.l10n;
  final hasRing = state.widget.onToggleContextPanel != null && context != null;
  KernelOption localized(KernelOption option) => localizedKernelOption(
    l10n,
    session.kernel.id,
    KernelChoiceKind.permission,
    option,
  );
  return Padding(
    padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
    child: Row(
      children: [
        // Takes the room left, so the actions sit at the far end; the
        // model's label cut short to fit, scrolls when even that does not.
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: PickersRow(
                maxWidth: constraints.maxWidth,
                children: [
                  if (kernel != null) ...[
                    ComposerPicker(
                      options: kernel.options,
                      selected: kernel.selected,
                      tapRegionGroupId: state.widget.tapRegionGroupId,
                      focusNode: state._focusNode,
                      onSelected: kernel.onSelected,
                    ),
                    const SizedBox(width: 2),
                  ],
                  if (mode != null) ...[
                    ComposerPicker(
                      key: state._modePickerKey,
                      options: mode.options,
                      selected: mode.selected,
                      emphasized: true,
                      tooltip: state._hovers.mode,
                      tapRegionGroupId: state.widget.tapRegionGroupId,
                      focusNode: state._focusNode,
                      onSelected: mode.onSelected,
                    ),
                    const SizedBox(width: 2),
                  ],
                  if (permission != null &&
                      permission.options.length != 2) ...[
                    ComposerPicker(
                      options: [
                        for (final option in permission.options)
                          localized(option),
                      ],
                      selected: localized(permission.selected),
                      // `context` is the session's here.
                      title: l10n.composerApprovalTitle(session.kernel.label),
                      menuWidth: 290,
                      tapRegionGroupId: state.widget.tapRegionGroupId,
                      focusNode: state._focusNode,
                      onSelected: permission.onSelected,
                    ),
                    const SizedBox(width: 2),
                  ],
                  // With none to pick, one to set up.
                  if (model != null || session.health.noModel)
                    SessionModelPicker(
                      session: session,
                      pickerKey: state._modelPickerKey,
                      tooltip: state._hovers.model,
                      tapRegionGroupId: state.widget.tapRegionGroupId,
                      focusNode: state._focusNode,
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (permission != null && permission.options.length == 2) ...[
          ComposerPermissionSwitch(
            permission: KernelChoice(
              options: [for (final o in permission.options) localized(o)],
              selected: localized(permission.selected),
              onSelected: permission.onSelected,
            ),
            title: l10n.composerApprovalTitle(session.kernel.label),
          ),
          const SizedBox(width: 2),
        ],
        if (ComposerPolishSetting.current()) ...[
          _PolishButton(
            busy: state._polishing,
            enabled: state._polishing || state._shownBuilt!.polishable,
            onTap: () => unawaited(state._polish()),
          ),
          if (hasRing) const SizedBox(width: 2),
        ],
        if ((state.widget.onToggleContextPanel, context) case (
          final onToggle?,
          final usage?,
        )) ...[
          _ContextRing(
            fraction: usage.fraction,
            active: state.widget.contextPanelOpen,
            // Toggle Context Panel's, which has none by default.
            tooltip: state._hovers.ring,
            onTap: onToggle,
          ),
          const SizedBox(width: 2),
        ],
        const SizedBox(width: 2),
        _SendButton(
          streaming: state._showsStop,
          enabled: state._canSend,
          onSend: state._submit,
          onStop: () => stopTurn(state.context, session),
        ),
      ],
    ),
  );
}

/// A two-option permission as a switch: the knob's side, the track's color.
class ComposerPermissionSwitch extends StatelessWidget {
  const ComposerPermissionSwitch({
    super.key,
    required this.permission, required this.title,
  });

  /// The options, the one in effect, and how to pick the other (localized);
  /// and the title for its tooltip, followed by the pick's description.
  final KernelChoice permission;
  final String title;

  @override
  Widget build(BuildContext context) {
    final on = permission.selected.id == permission.options[1].id;
    final next = permission.options[on ? 0 : 1];
    final colors = themeColors;
    return IdeHover(
      message: [title, next.description].where((e) => e.isNotEmpty).join(' · '),
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => Semantics(
          toggled: on, label: title,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => permission.onSelected(next),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              width: 35, height: 20,
              margin: const EdgeInsets.symmetric(vertical: 1),
              padding: const EdgeInsets.all(2),
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: on ? AppColors.autoTrack : hovered
                    ? colors['toolbar.hoverBackground']
                    : Colors.transparent,
                border: on ? null : Border.all(color: AppColors.textFaint),
                borderRadius: BorderRadius.circular(10),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                width: 16, height: 16,
                decoration: BoxDecoration(
                  color: on ? colors['button.foreground'] : AppColors.textMuted,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
