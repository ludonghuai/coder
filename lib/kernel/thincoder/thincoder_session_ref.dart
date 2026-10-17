/// A session's id as the host keeps it: the project folder and the slot
/// the agent numbered the session under, `"<cwd>|<slot>"` (D5).
///
/// Slots are numbered per project (each folder has its own slots, from 1),
/// and the host tells sessions apart by their id alone: the bare slot of
/// one project would hide another project's session of the same number.
abstract final class ThincoderSessionRef {
  /// The id of the session the agent keeps as [slot] in [cwd].
  static String combine(String cwd, String slot) => '$cwd|$slot';

  /// The folder and the slot [id] names; null for an id that names neither
  /// (one from elsewhere).
  ///
  /// Split at the last `|`: a Unix path may contain one (rarely — see
  /// design §14-7), the slot never does.
  static (String cwd, String slot)? split(String id) {
    final at = id.lastIndexOf('|');
    if (at <= 0 || at == id.length - 1) return null;
    return (id.substring(0, at), id.substring(at + 1));
  }

  /// The folder of [id], or null.
  static String? cwdOf(String id) => split(id)?.$1;

  /// The slot of [id], or null.
  static String? slotOf(String id) => split(id)?.$2;
}
