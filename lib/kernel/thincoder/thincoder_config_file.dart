import 'dart:io';

import 'package:bao_remote/local.dart' show AppPaths, ClaudeEnvironment;
import 'package:path/path.dart' as p;

// Where the thincoder CLI keeps its config.json, as it reads it
// (thincoder-core/config-io.mjs:32): `THINCODER_CONFIG_DIR` when it names a
// directory, else `~/.thincoder`. Written to by Settings → Models
// (thincoder), whose only write face is `providers[]` and `defaultModel`.

/// The directory the CLI reads its config from: `THINCODER_CONFIG_DIR` when
/// set (as it is, trimmed — the CLI spells no `~` out, `config-io.mjs:32`),
/// else `<home>/.thincoder`.
String resolveThincoderConfigDir(Map<String, String> environment) {
  final named = environment['THINCODER_CONFIG_DIR']?.trim() ?? '';
  return named.isNotEmpty
      ? named
      : p.join(AppPaths.home(environment), '.thincoder');
}

/// The file inside [resolveThincoderConfigDir]: `config.json`.
File thincoderConfigFile(Map<String, String> environment) =>
    File(p.join(resolveThincoderConfigDir(environment), 'config.json'));

/// The environment the CLI runs in, which is where its config is: the
/// user's shell's, as the kernel launches it with (`ClaudeEnvironment.of`,
/// as `thincoder_locator.dart:83` asks it). A directory named by F23 goes in
/// here; the resolution above stays as it is.
Future<Map<String, String>> Function() thincoderEnvironment =
    ClaudeEnvironment.of;
