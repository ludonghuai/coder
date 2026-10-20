import 'package:flutter/foundation.dart';

/// Whether the file open in the editor — its path, the cursor's line and the
/// selection — goes with each message: the `chat.editorContext` setting.
abstract final class EditorContextSetting {
  static const settingKey = 'chat.editorContext';

  /// Written when off; on, the setting is left out.
  static const off = false;

  /// On unless set to false.
  static bool enabled(Object? setting) => setting != false;

  /// The setting as it is now, and what tells it changed; main() points
  /// them at settings.json.
  static bool Function() current = () => true;
  static Listenable? changes;
}
