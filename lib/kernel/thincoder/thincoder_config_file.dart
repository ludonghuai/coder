import 'dart:io';

import 'package:bao_remote/local.dart' show AppPaths;
import 'package:path/path.dart' as p;

import 'thincoder_locator.dart';

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

/// The environment the CLI runs in, which is where its config is: the one
/// `ThincoderLocator.launch` starts it with — the user's shell's, and, for
/// the build a distribution carries, that build's own folder. Written by
/// Settings → Models (thincoder), so that the page writes the file the CLI
/// reads.
Future<Map<String, String>> Function() thincoderEnvironment =
    ThincoderLocator.environment;
