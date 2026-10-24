part of 'btest_mode.dart';

/// btest's own settings, in settings.json (§4: the settings page's two host
/// lists and the read-only default).
abstract final class BtestSettings {
  /// The hosts a browser action may reach at all; empty refuses every one.
  static const allowHostsKey = 'btest.allowHosts';

  /// The hosts that are production: a write action never reaches one, and
  /// an empty list refuses writes (§3.7 rule B).
  static const prodHostsKey = 'btest.prodHosts';

  /// Whether a run that does not say its mode starts read-only (§9).
  static const readonlyKey = 'btest.readonly';

  /// The folder expect files go in; empty derives it from the session's
  /// workspace root (§3.4).
  static const qaRootKey = 'btest.qaRoot';

  /// Whether the mode was on when its session closed (§9.1, F11).
  static const onKey = 'btest.on';

  /// The traversal the last session picked (§9.1, F11): `chain` / `surface`.
  static const traversalKey = 'btest.traversal';

  /// The write switch the last session picked (§9.1, F11): `readonly` /
  /// `write`.
  static const modeKey = 'btest.mode';

  /// A test's values, in place of settings.json's.
  @visibleForTesting
  static Map<String, Object?>? values;

  static Set<String> get allowHosts => hostsOf(_read(allowHostsKey));
  static Set<String> get prodHosts => hostsOf(_read(prodHostsKey));

  /// Read-only unless the user turned it off.
  static bool get readonlyByDefault => _read(readonlyKey) != false;

  /// The configured QA root, trimmed; null when the setting is empty (the
  /// path is then derived, §3.4).
  static String? get qaRoot => switch (_read(qaRootKey)) {
    final String text when text.trim().isNotEmpty => text.trim(),
    _ => null,
  };

  /// Whether btest was on (§9.1, F11): `btest.on` holds a bool, and only
  /// `true` turns the mode on — a string or a number is not one.
  static bool get on => _read(onKey) == true;

  /// The traversal the last session picked (§9.1); null when the key is
  /// missing or holds anything but `chain` / `surface` — the reader then
  /// falls back to the built-in `surface`.
  static BtestTraversal? get traversal => switch (_read(traversalKey)) {
    final String text => BtestTraversal.parse(text),
    _ => null,
  };

  /// The write switch the last session picked (§9.1); null when the key is
  /// missing or holds anything but `readonly` / `write` — the switch then
  /// stays unpicked and `btest.readonly` stands (§9.1「写初始」).
  static bool? get write {
    final face = switch (_read(modeKey)) {
      final String text => BtestFace.parse(text),
      _ => null,
    };
    return face == null ? null : face == BtestFace.write;
  }

  /// The setting [key]'s value, as settings.json keeps it now.
  static Object? _read(String key) {
    if (values case final values?) return values[key];
    try {
      return SettingsFiles.instance.settings[key];
    } on Object {
      // No data folder to read from: nothing is configured, and an empty
      // list refuses rather than allows (fail-closed).
      return null;
    }
  }

  /// Keeps [key] as [value] in settings.json; null removes it (what
  /// `update` means, `user_settings.dart:26-27`). A test's [values] takes
  /// the change in place of the file, so a test never writes the machine's
  /// settings. A write that fails is one debugPrint and nothing else: the
  /// session keeps the value it just took, and the next one reads what the
  /// file still holds (§9.1, KD-30 ③).
  static void put(String key, Object? value) {
    if (values case final values?) {
      if (value == null) {
        values.remove(key);
      } else {
        values[key] = value;
      }
      return;
    }
    unawaited(
      SettingsFiles.instance.settings.update(key, value).catchError((
        Object error,
      ) {
        debugPrint('$key not kept: $error');
      }),
    );
  }

  /// A settings.json list of hosts, normalized lower case; anything else is
  /// none.
  static Set<String> hostsOf(Object? value) => {
    if (value is List) for (final host in value) ?_hostOf('$host'),
  };

  /// A text field's line as the list it sets: hosts by comma or space; none
  /// for blank.
  static List<String>? listOf(String text) {
    final hosts = [
      for (final host in text.split(RegExp(r'[,\s]+'))) ?_hostOf(host),
    ];
    return hosts.isEmpty ? null : hosts;
  }

  /// [text] as a host alone: what someone types as a URL
  /// (`https://v2-dev.example.com/`) becomes `v2-dev.example.com`, which is
  /// what the gate compares against (`Uri.host`). Without this a list can look
  /// filled and never match — a prod host would go unprotected, and an allow
  /// list would refuse everything.
  static String? _hostOf(String text) {
    final value = text.trim();
    if (value.isEmpty) return null;
    final asUrl = Uri.tryParse(value.contains('://') ? value : '//$value');
    final host = asUrl?.host.trim().toLowerCase() ?? '';
    if (host.isNotEmpty) return host;
    return value.toLowerCase();
  }
}
