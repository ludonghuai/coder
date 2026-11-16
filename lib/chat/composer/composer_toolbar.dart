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
                  if (permission != null) ...[
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
        if (ComposerPolishSetting.current()) ...[
          _PolishButton(
            busy: state._polishing,
            enabled: state._polishing || state._shownBuilt!.polishable,
            onTap: () => unawaited(state._polish()),
          ),
          const SizedBox(width: 2),
        ],
        if ((state.widget.onToggleContextPanel, context) case (
          final onToggle?,
          final usage?,
        )) ...[
          ContextMeter(
            usage: usage,
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
