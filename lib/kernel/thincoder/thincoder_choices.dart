part of 'thincoder_kernel.dart';

// The choices the kernel offers over what its agent reports: the mode, the
// approval switch, the model, and how much it thinks (F13 / F14). Each is
// read live — what the agent last reported, never what was asked for (D20).

KernelChoiceSource _modeOf(ThincoderKernel kernel) => _Choice(
  options: () => kernel._events.optionsOf('mode', _modeIcon),
  // The mode last reported — by the session's own word, or by
  // `current_mode_update` (§3.6); never one it has not taken up (D20).
  selected: () => kernel._events.mode,
  select: (id) {
    if (id != 'plan' && id != 'normal') return;
    unawaited(_setModeOf(kernel, id));
  },
);

/// The approval switch the agent reports (F13): the terminal's `/auto`.
KernelChoiceSource _permissionOf(ThincoderKernel kernel) => _Choice(
  options: () => kernel._events.configOf('autoApprove') == null
      ? const []
      : const [
          KernelOption(
            'ask',
            'Ask',
            Icons.front_hand_outlined,
            'Ask before each tool call',
          ),
          KernelOption(
            'auto',
            'Auto',
            Icons.fast_forward_rounded,
            'Tools run without asking — the same switch as /auto in the '
                'terminal',
            caution: true,
          ),
        ],
  // What the agent last reported; never what was asked for (D20).
  selected: () =>
      kernel._events.configOf('autoApprove')?['currentValue'] == true
      ? 'auto'
      : 'ask',
  select: (id) => unawaited(_configOf(kernel, 'autoApprove', id == 'auto')),
);

KernelChoiceSource _modelOf(ThincoderKernel kernel) => _Choice(
  // Picked again, the model in effect calls off a waiting switch (F21).
  always: true,
  options: () =>
      kernel._events.optionsOf('model', (value) => Icons.bolt_rounded),
  selected: () => kernel._events.selected('model'),
  select: (id) => _selectModelOf(kernel, id),
);

/// Picks [id] (F21): a turn under way keeps it for its end (D20).
void _selectModelOf(ThincoderKernel kernel, String id) {
  final selected = kernel._events.selected('model');
  if (id == selected && kernel._modelTarget == null) return;
  // The model in effect, picked while one waited: the wait is called off.
  if (kernel._modelDeferred && id == selected) {
    kernel._modelTarget = null;
    kernel._modelDeferred = false;
    kernel.emitInfoChanged();
    return;
  }
  kernel._modelTarget = id;
  // A turn under way keeps the write back: it would land behind it.
  if (kernel._turn != null || kernel._pendingAuto != null) {
    kernel._modelDeferred = true;
    kernel.emitInfoChanged();
    return;
  }
  // A write is out: this one goes after its answer (last wins).
  if (kernel._modelSending) return;
  kernel._modelDeferred = false;
  unawaited(_pumpModelOf(kernel));
}

/// Writes the model waiting once nothing is in the way (F21/D96).
Future<void> _pumpModelOf(ThincoderKernel kernel) async {
  final target = kernel._modelTarget;
  if (target == null || kernel._modelSending || kernel._turn != null ||
      kernel._pendingAuto != null || kernel._releaseWanted) {
    return;
  }
  final connection = kernel._connection;
  final slot = kernel._slot;
  if (connection == null || slot == null) return kernel._dropModelOf();
  kernel._modelDeferred = false;
  kernel._modelSending = true;
  try {
    final answer = await connection.request('session/set_config_option', {
      'sessionId': slot,
      'configId': 'model',
      'value': target,
    });
    // A session let go of meanwhile: its answer lands nowhere.
    if (!identical(connection, kernel._connection)) return;
    kernel._modelSending = false;
    kernel._events.optionsFrom(answer);
    // Picked again while this was out: what was picked last goes next.
    if (kernel._modelTarget != target) return unawaited(_pumpModelOf(kernel));
    kernel._dropModelOf();
  } on Object catch (error) {
    if (!identical(connection, kernel._connection)) return;
    appEvent('thincoder', 'set_config_option(model) failed: $error');
    kernel.emit(
      ItemUpserted(
        kernel.nextSeq,
        'error:model',
        NoticeItem(NoticeKind.error, 'The model switch was not confirmed: $error'),
      ),
    );
    kernel._dropModelOf();
  }
}

/// Whether the agent reports thinking levels (F14; an empty list is none).
bool _hasThinkingLevels(ThincoderKernel kernel) =>
    (kernel._events.configOf('thinkingLevel')?['options'] as List?)
        ?.isNotEmpty ??
    false;

List<KernelOption> _thinkingLevels(ThincoderKernel kernel) => [
  for (final option
      in kernel._events.optionsOf('thinkingLevel', (_) => Icons.speed_rounded))
    KernelOption(option.id, effortLabel(option.id), option.icon, ''),
];

String? _thinkingChoice(ThincoderKernel kernel) => _hasThinkingLevels(kernel)
    ? kernel._events.selected('thinkingLevel')
    : kernel._events.thinking
    ? 'on'
    : 'off';

ModelSetting _effortOf(ThincoderKernel kernel) => _ModelSetting(
  toggles: () => !_hasThinkingLevels(kernel),
  optionsFor: (_) => _hasThinkingLevels(kernel)
      ? _thinkingLevels(kernel)
      : kernel._events.configOf('thinking') == null
      ? const []
      : const [
          KernelOption(
            'on',
            'Thinking',
            Icons.psychology_outlined,
            'Let the model think before it answers',
          ),
        ],
  selected: () => _thinkingChoice(kernel),
  selectedFor: (_) => _thinkingChoice(kernel),
  // A switch flips; a level is picked as named (the agent's word, D20).
  select: (model, id) {
    if (_hasThinkingLevels(kernel)) {
      unawaited(_configOf(kernel, 'thinkingLevel', id));
      return;
    }
    if (id != 'on') return;
    unawaited(_configOf(kernel, 'thinking', !kernel._events.thinking));
  },
);

IconData _modeIcon(String value) => switch (value) {
  'plan' => Icons.checklist_rounded,
  'normal' => Icons.all_inclusive_rounded,
  _ => Icons.tune_rounded,
};

Future<void> _setModeOf(ThincoderKernel kernel, String mode) async {
  final connection = kernel._connection;
  final slot = kernel._slot;
  // Let go of the session (its view left): there is nothing to set it on.
  if (connection == null || slot == null) return;
  try {
    await connection.request('session/set_mode', {
      'sessionId': slot,
      'mode': mode,
    });
  } on Object catch (error) {
    appEvent('thincoder', 'set_mode($mode) failed: $error');
    // The picker offered it; the agent refused it (e.g. plan in engineering
    // mode). Said where the picker was, not only in the log.
    kernel.emit(
      ItemUpserted(
        kernel.nextSeq,
        'error:mode',
        NoticeItem(
          NoticeKind.error,
          'The mode was not switched to $mode: $error',
        ),
      ),
    );
  }
}

Future<void> _configOf(
  ThincoderKernel kernel,
  String configId,
  Object? value,
) async {
  final connection = kernel._connection;
  final slot = kernel._slot;
  // As in [_setModeOf]: the menu may outlive the session it was opened on.
  if (connection == null || slot == null) return;
  try {
    final answer = await connection.request('session/set_config_option', {
      'sessionId': slot,
      'configId': configId,
      'value': value,
    });
    kernel._events.optionsFrom(answer);
  } on Object catch (error) {
    // Shown as it stands: the report is the agent's (D20).
    appEvent('thincoder', 'set_config_option($configId) failed: $error');
  }
}

/// A choice over state the kernel holds: options and selection read live
/// (the form Claude Code's adapter keeps).
class _Choice implements KernelChoiceSource {
  _Choice({
    required this._options,
    required this._selected,
    required this._select,
    this._always = false,
  });

  final List<KernelOption> Function() _options;
  final String? Function() _selected;
  final void Function(String id) _select;
  List<KernelOption> _cache = const [];

  /// Whether a pick is said even when it is the one in effect: to call off
  /// a switch waiting for the turn's end (F21).
  final bool _always;

  /// The same list while unchanged, so pickers keep their identity.
  @override
  List<KernelOption> get options {
    final fresh = _options();
    if (!listEquals(fresh, _cache)) _cache = fresh;
    return _cache;
  }

  @override
  String? get selected => _selected();

  @override
  void select(String id) {
    if (_always || id != selected) _select(id);
  }
}

/// A setting that goes with the model, read live.
class _ModelSetting implements ModelSetting {
  _ModelSetting({
    required this._optionsFor,
    required this._selected,
    required this._selectedFor,
    required this._select,
    this._toggles,
  });

  final List<KernelOption> Function(String model) _optionsFor;
  final String? Function() _selected;
  final String? Function(String model) _selectedFor;
  final void Function(String model, String id) _select;

  final bool Function()? _toggles;

  @override
  bool get toggle => _toggles?.call() ?? false;

  @override
  List<KernelOption> optionsFor(String model) => _optionsFor(model);

  @override
  String? get selected => _selected();

  @override
  String? selectedFor(String model) => _selectedFor(model);

  @override
  void select(String model, String id) => _select(model, id);
}
