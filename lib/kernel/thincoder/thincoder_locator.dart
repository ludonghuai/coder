import 'dart:io';

import 'package:bao_remote/local.dart' show AppPaths, ClaudeEnvironment;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import 'thincoder_transport.dart';

/// Settings → General → thincoder: the build to run on this machine
/// (`thincoder.path` in settings.json), e.g. one installed somewhere other
/// than the PATH; none set, the one the PATH finds.
abstract final class ThincoderPathSetting {
  static const settingKey = 'thincoder.path';

  /// The path a setting's [value] names; null for none.
  static String? parse(Object? value) => switch (value) {
    final String path when path.trim().isNotEmpty => path.trim(),
    _ => null,
  };

  /// The path set now: main.dart reads it from settings.json.
  static String? Function() current = () => null;
}

/// Where thincoder stands on this machine, as Settings → General shows it.
sealed class ThincoderStatus {
  const ThincoderStatus();
}

/// [path] runs, at [version] when it says one.
class ThincoderFound extends ThincoderStatus {
  const ThincoderFound(this.path, this.version);

  final String path;
  final String? version;
}

/// None is installed, and none is named in Settings.
class ThincoderMissing extends ThincoderStatus {
  const ThincoderMissing();
}

/// The one named in Settings is not there.
class ThincoderFailed extends ThincoderStatus {
  const ThincoderFailed(this.message);

  final String message;
}

/// Where thincoder stands on this machine now.
Future<ThincoderStatus> thincoderStatus() => ThincoderLocator.status();

/// Where thincoder stands, as the line Settings → General shows under its
/// path setting (F7); what failed says why, in the agent's own words.
String thincoderStatusLine(ThincoderStatus status) => switch (status) {
  ThincoderFound(:final path, :final version?) => 'In use: $path ($version)',
  ThincoderFound(:final path) => 'In use: $path',
  ThincoderMissing() => 'None found yet: install it, or set a path to one.',
  ThincoderFailed(:final message) => message,
};

/// Where the thincoder CLI is (`thincoder.path`, else the PATH), which
/// version is the oldest this adapter was written against, and what to say
/// when there is none.
abstract final class ThincoderLocator {
  /// The version this adapter was written against (the one checked on
  /// 2026-10-16). An older one is said of, never blocked (D13); a newer one
  /// is taken as it comes, and the terminal's log says what it reported.
  static const verifiedVersion = '0.12.74';

  /// How to get one, when there is none.
  static const installCommand = 'npm install -g thincoder';

  /// What it needs.
  static const nodeRequirement = 'Node.js 24 or newer';

  /// How the user signs in, in a terminal of their own.
  static const loginCommand = 'thincoder acp --login';

  /// How to start thincoder in [cwd]: which build, in the environment the
  /// user's terminal has (so it finds the same Node and the same setup).
  static Future<ThincoderLaunch> launch(String cwd) async {
    final environment = await ClaudeEnvironment.of();
    return ThincoderLaunch(
      cwd: cwd,
      executable: await locate(environment),
      environment: environment,
    );
  }

  /// The thincoder to run: the path set in Settings, else the first of
  /// [candidates] that is there. Throws [ThincoderUnavailable] with what to
  /// do about it when there is none.
  static Future<String> locate([Map<String, String>? environment]) async {
    final env = environment ?? await ClaudeEnvironment.of();
    final named = ThincoderPathSetting.current();
    if (named != null) {
      final path = _named(named, env);
      if (!File(path).existsSync()) {
        throw ThincoderUnavailable(
          'thincoder is not at $path',
          detail:
              '$path does not exist. Correct it in Settings → General → '
              'thincoder, or clear it to run the installed one.',
        );
      }
      return path;
    }
    final found = candidates(
      env,
    ).where((path) => File(path).existsSync()).firstOrNull;
    if (found != null) return found;
    throw ThincoderUnavailable(
      'thincoder is not installed',
      detail:
          'Install it (`$installCommand`, which needs $nodeRequirement), '
          'then try again — or set the path to one in Settings → General → '
          'thincoder.',
    );
  }

  /// The path [named] stands for in [environment], `~` spelled out.
  static String _named(String named, Map<String, String> environment) {
    if (!named.startsWith('~/') && !named.startsWith(r'~\')) return named;
    final home = AppPaths.home(environment);
    return home.isEmpty ? named : '$home${named.substring(1)}';
  }

  /// Where to look for thincoder, in the order it is tried: the PATH
  /// first, then where npm and the installers put it. Under test, replaced
  /// by [candidatesOverride], so that a test of thincoder not installed
  /// never finds the machine's own.
  @visibleForTesting
  static List<String> Function(Map<String, String> environment)?
  candidatesOverride;

  static List<String> candidates(Map<String, String> environment) {
    if (candidatesOverride case final override?) return override(environment);
    final home = AppPaths.home(environment);
    final path = environment['PATH'] ?? '';
    if (!Platform.isWindows) {
      return [
        for (final dir in path.split(':'))
          if (dir.isNotEmpty) p.join(dir, 'thincoder'),
        p.join(home, '.local', 'bin', 'thincoder'),
        '/usr/local/bin/thincoder',
        '/opt/homebrew/bin/thincoder',
      ];
    }
    final npm = p.join(environment['APPDATA'] ?? home, 'npm');
    return [
      for (final dir in path.split(';'))
        if (dir.isNotEmpty) ...[
          p.join(dir, 'thincoder.cmd'),
          p.join(dir, 'thincoder.exe'),
        ],
      p.join(npm, 'thincoder.cmd'),
      p.join(npm, 'thincoder.exe'),
    ];
  }

  /// The version [executable] says it is (`thincoder --version`); null when
  /// it does not run, or does not say.
  static Future<String?> versionOf(
    String executable, {
    Map<String, String>? environment,
  }) async {
    try {
      final result = await Process.run(
        executable,
        const ['--version'],
        environment: environment,
        includeParentEnvironment: true,
        runInShell: throughShell(executable),
      );
      return parseVersion('${result.stdout}\n${result.stderr}');
    } on Object {
      return null;
    }
  }

  /// The first version number in [text] (`0.12.74`), or null.
  static String? parseVersion(String text) =>
      RegExp(r'\d+\.\d+\.\d+').firstMatch(text)?.group(0);

  /// Whether [version] is older than [verifiedVersion]; false when there is
  /// no version to tell (D13: said of, never blocked).
  static bool belowVerified(String? version) {
    final found = numbers(version);
    final known = numbers(verifiedVersion);
    if (found == null || known == null) return false;
    for (var i = 0; i < 3; i++) {
      if (found[i] != known[i]) return found[i] < known[i];
    }
    return false;
  }

  /// [version]'s three numbers, or null when it names none.
  static List<int>? numbers(String? version) {
    final text = parseVersion(version ?? '');
    if (text == null) return null;
    return [for (final part in text.split('.')) int.parse(part)];
  }

  /// Where thincoder stands now, looked for (never started).
  static Future<ThincoderStatus> status() async {
    final environment = await ClaudeEnvironment.of();
    final named = ThincoderPathSetting.current();
    try {
      final path = await locate(environment);
      return ThincoderFound(
        path,
        await versionOf(path, environment: environment),
      );
    } on ThincoderUnavailable catch (error) {
      return named == null
          ? const ThincoderMissing()
          : ThincoderFailed(error.message);
    }
  }

  /// Whether starting [executable] goes through the shell: only `cmd.exe`
  /// runs npm's `.cmd` shim, which is what `thincoder` is on Windows.
  static bool throughShell(String executable) =>
      Platform.isWindows &&
      const {'.cmd', '.bat'}.contains(p.extension(executable).toLowerCase());
}

/// Builds how to start thincoder in [cwd] (see [ThincoderLocator.launch]).
typedef ThincoderLauncher = Future<ThincoderLaunch> Function(String cwd);
