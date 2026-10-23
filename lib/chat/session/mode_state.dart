part of '../chat_session.dart';

// The kernel and the settings it offers, as the pickers show them: which
// kernel it may switch to, its modes, permissions and per-model settings,
// and what is in effect (SPLIT-3). The class keeps one delegate per member.

/// A choice a kernel offers (its model, its mode, the kernel itself): the
/// options, the one in effect, and how to pick another.
class KernelChoice {
  const KernelChoice({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<KernelOption> options;
  final KernelOption selected;
  final ValueChanged<KernelOption> onSelected;
}

/// A setting picked beside a model, e.g. its effort (see [ModelSetting]).
class ModelSettingChoice {
  const ModelSettingChoice({
    required this.kind,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.toggle = false,
  });

  /// The kernel's setting it is; null for the app's own, shown beside them
  /// (`chat.resumeAfterLimitReset`, in the model picker).
  final KernelChoiceKind? kind;
  final List<KernelOption> options;

  /// What is in effect, or would stay so with the model picked; null
  /// while not known.
  final KernelOption? selected;

  /// Whether this setting is on or off, shown and picked as a switch: what
  /// it shows under an option is not a check but a switch, and picking it
  /// leaves the menu open (see [ComposerPicker]).
  final bool toggle;

  /// Picks the option, and the model with it.
  final ValueChanged<KernelOption> onSelected;
}

/// Once the conversation has started, its kernel stays: kernels cannot
/// read each other's sessions.
bool _kernelLockedOf(ChatSession owner) =>
    owner._transcript.length > 0 || owner.kernelContext.resume != null;

/// Null once locked, or with nothing to choose from.
KernelChoice? _kernelChoiceOf(ChatSession owner) {
  if (owner.kernelLocked || owner.kernels.length < 2) return null;
  return KernelChoice(
    options: owner._kernelOptions,
    selected: owner._kernelOptions[owner.kernels.indexOf(owner.kernel)],
    onSelected: (option) =>
        owner.setKernel(owner.kernels.firstWhere((k) => k.id == option.id)),
  );
}

void _setKernelOf(ChatSession owner, KernelDescriptor descriptor) {
  if (owner.kernelLocked || descriptor.id == owner.kernel.id) return;
  owner._switching = Stopwatch()..start(); // t0 (§25.5).
  unawaited(owner._subscription?.cancel());
  // Kept warm rather than disposed: before the first message there is no
  // conversation to protect, and the switch back skips the start.
  owner._warm[owner._kernel.descriptor.id] = owner._kernel;
  owner._transcript = Transcript(
    changes: [for (final edit in owner._transcript.edits) edit.change],
  );
  owner._turns.clear();
  owner._prependedSeen = 0;
  owner._connect(descriptor);
  owner._publishBtest();
  // The view never went away, so its attach will not come again: the new
  // kernel is started here, or it would sit unstarted and say nothing of
  // what it offers (mode, model) until the first message.
  if (owner._views > 0) {
    owner._kernel.prepare();
    owner._startReview();
  }
  owner._readSwitch();
  owner._notify();
}

/// `timing: kernel-switch` (§25.5), once the kernel switched to is ready.
void _readSwitchOf(ChatSession owner) {
  final clock = owner._switching;
  if (clock == null || owner._kernel.health.status != KernelHealthStatus.ready) return;
  owner._switching = null;
  appEvent('thincoder', 'timing: kernel-switch ${clock.elapsedMilliseconds}ms');
}

KernelChoice? _modelsOf(ChatSession owner) => switch (owner._kernel) {
  final SelectsModel kernel => owner._choice(kernel.model),
  _ => null,
};

/// Whether picking [model] (one of [models]' options) restarts the
/// conversation's agent on another upstream: asked first.
bool _switchRestartsOf(ChatSession owner, String model) =>
    switch (owner._kernel) {
      final ConfirmsModelSwitch kernel => kernel.switchRestarts(model),
      _ => false,
    };

/// The model picked while a turn ran, to be applied when it is over: null
/// when none waits.
String? _pendingModelOf(ChatSession owner) => switch (owner._kernel) {
  final DefersModelSwitch kernel => kernel.pendingModel,
  _ => null,
};

KernelChoice? _modesOf(ChatSession owner) {
  final choice = switch (owner._kernel) {
    final SelectsMode kernel => owner._choice(kernel.mode),
    _ => null,
  };
  if (choice == null) return null;
  return KernelChoice(
    options: [...choice.options, ChatSession._btestOption],
    selected: owner._btest.on ? ChatSession._btestOption : choice.selected,
    onSelected: (option) {
      if (option.id == ChatSession._btestId) {
        owner.setBtest(true);
        return;
      }
      owner.setBtest(false);
      choice.onSelected(option);
    },
  );
}

KernelChoice? _permissionsOf(ChatSession owner) => switch (owner._kernel) {
  final SelectsPermission kernel => owner._choice(kernel.permission),
  _ => null,
};

/// The settings that go with [model] (one of [models]' options), in
/// the order they are picked in: only those with a choice to make.
List<ModelSettingChoice> _modelSettingsOf(ChatSession owner, String model) => [
  for (final (kind, setting) in owner._modelSettings)
    if (setting.optionsFor(model) case final options when options.isNotEmpty)
      ModelSettingChoice(
        kind: kind,
        options: options,
        // Another model's own, not the one in use's.
        selected: options
            .where((o) => o.id == setting.selectedFor(model))
            .firstOrNull,
        toggle: setting.toggle,
        onSelected: (option) => setting.select(model, option.id),
      ),
];

/// The choice [kind] as it stands, e.g. for a new agent to start with.
String? _selectedOf(ChatSession owner, KernelChoiceKind kind) => switch (kind) {
  KernelChoiceKind.model => owner.models?.selected.id,
  KernelChoiceKind.mode => owner.modes?.selected.id,
  KernelChoiceKind.permission => owner.permissions?.selected.id,
  KernelChoiceKind.effort ||
  KernelChoiceKind.context ||
  KernelChoiceKind.fast =>
    owner._modelSettings
        .where((setting) => setting.$1 == kind)
        .firstOrNull
        ?.$2
        .selected,
};

KernelChoice? _choiceOf(ChatSession owner, KernelChoiceSource source) {
  final options = source.options;
  if (options.isEmpty) return null;
  return KernelChoice(
    options: options,
    selected: options.firstWhere(
      (option) => option.id == source.selected,
      orElse: () => options.first,
    ),
    onSelected: (option) => source.select(option.id),
  );
}
