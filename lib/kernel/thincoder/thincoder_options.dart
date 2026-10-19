import 'package:flutter/widgets.dart';

import '../kernel_types.dart';

/// One reported config option as the picker lists it: a model under its
/// provider (the part before the first colon), its own name alone in the
/// row; every other option as it was reported.
KernelOption thincoderOption(
  String id,
  String value,
  String name,
  IconData Function(String) icon,
) {
  final colon = id == 'model' ? value.indexOf(':') : -1;
  if (colon <= 0) return KernelOption(value, name, icon(value), '');
  final provider = value.substring(0, colon);
  // What the agent named it, without the provider it was listed under
  // (a name with no such prefix — a plain title — stays as it is).
  final stripped = name.startsWith('$provider:')
      ? name.substring(provider.length + 1)
      : name;
  return KernelOption(
    value,
    stripped.isEmpty ? value.substring(colon + 1) : stripped,
    icon(value),
    '',
    group: KernelOptionGroup(provider, provider),
  );
}
