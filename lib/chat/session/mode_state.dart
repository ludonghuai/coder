import 'package:flutter/material.dart' show Icons;

import '../../kernel/agent_kernel.dart';
import '../../kernel/kernel_types.dart';
import '../chat_session_overlay.dart';

// btest's place beside the kernel's modes (its own option in the same
// picker), and the one kernel facet the host reads from here: the model
// picked while a turn ran.

/// btest's id in the modes picker: a name, not a translated label (§9).
const btestModeId = 'btest';

/// btest's option in the same picker as the kernel's modes (§3.1, §9).
const btestModeOption = KernelOption(
  btestModeId,
  'btest',
  Icons.science_outlined,
  'Browser business testing: one run on the real pages, the expectations '
      'read from the files, one report at the end',
);

/// [base] as the modes picker shows it: btest beside the kernel's own
/// modes when it offers any; none under a kernel without modes. Picking
/// another mode turns btest off (§3.1: normal / plan end it).
KernelChoice? wrapModesOf(
  KernelChoice? base, {
  required bool btestOn,
  required void Function(bool on) setBtest,
}) {
  if (base == null) return null;
  return KernelChoice(
    options: [...base.options, btestModeOption],
    selected: btestOn ? btestModeOption : base.selected,
    onSelected: (option) {
      if (option.id == btestModeId) {
        setBtest(true);
        return;
      }
      setBtest(false);
      base.onSelected(option);
    },
  );
}

/// The model picked while a turn ran, to be applied when it is over: read
/// from the kernel's own facet, never kept as a second copy; null when
/// none waits.
String? pendingModelOf(ChatSessionOverlayHost host) =>
    switch (host.agentKernel) {
      final DefersModelSwitch kernel => kernel.pendingModel,
      _ => null,
    };
