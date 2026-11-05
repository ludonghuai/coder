import 'dart:io';

import 'package:bao_remote/local.dart' show AppPaths, ClaudeEnvironment;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../../platform/data_dir.dart';
import '../../platform/event_log.dart';
import '../../platform/process_host.dart';
import 'thincoder_transport.dart';

/// Settings → General → thincoder: the build to run on this machine
/// (`thincoder.path` in settings.json), e.g. one installed somewhere other
/// than the PATH, or a checkout's `bin/thincoder.cjs` (run by node); none
/// set, the one the app carries, else the checkout of the tree it was built
/// from, else the one the PATH finds.
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

/// The one to run would not: the one named in Settings is not there, or
/// the build the app carries will not start.
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

/// Where a [ThincoderBuild] was found.
enum ThincoderBuildKind {
  /// The path set in Settings → General → thincoder.
  named,

  /// The runtime the distribution carries (§26).
  builtin,

  /// The checkout in the source tree the app was built from.
  checkout,

  /// One on the PATH, or where npm puts it.
  installed,
}

/// A thincoder to run: what Settings shows ([display]) and what is started
/// ([executable] with [arguments]).
///
/// The build a distribution carries is node running the CLI's own entry
/// file, so the file the user knows is not the program started: [display]
/// is the entry file, and [executable] the node that runs it. A checkout,
/// or an entry file named in Settings, runs the same way.
class ThincoderBuild {
  const ThincoderBuild({
    required this.display,
    required this.executable,
    this.arguments = const [ThincoderLaunch.command],
    this.kind = ThincoderBuildKind.installed,
  });

  /// The thincoder itself, as the user knows it: the path `In use: …` names.
  final String display;

  /// The program started.
  final String executable;

  /// What [executable] is started with.
  final List<String> arguments;

  /// Where it was found.
  final ThincoderBuildKind kind;

  /// What is run to have it say its version: the same command line, with
  /// `--version` where the subcommand is.
  List<String> get versionArguments => [
    ...arguments.take(arguments.length - 1),
    '--version',
  ];
}

/// Where the thincoder CLI is (`thincoder.path`, else the build the app
/// carries, else the checkout of the tree it was built from, else the
/// PATH), which version is the oldest this adapter was written against, and
/// what to say when there is none.
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

  /// The variable the CLI reads its config folder from (`thincoder-core`:
  /// this one when set, else `~/.thincoder`).
  static const configDirVariable = 'THINCODER_CONFIG_DIR';

  /// How to start thincoder in [cwd]: which build, in the environment the
  /// user's terminal has (so it finds the same Node and the same setup).
  ///
  /// The build a distribution carries gets a config folder of its own
  /// (`<data folder>/runtime-data/thincoder`) in that environment, so that
  /// the CLI keeps to it and the user's `~/.thincoder` is left as it is. One
  /// set in Settings, a checkout, or one found on the PATH gets the
  /// environment unchanged — whether or not the app carries a runtime: it
  /// keeps reading `~/.thincoder`, whose sessions a terminal of the user's
  /// opens and this app lists (§26.5).
  static Future<ThincoderLaunch> launch(String cwd) async {
    final environment = await ClaudeEnvironment.of();
    final builtin = builtinBuild();
    final build = _resolve(environment, builtin);
    appEvent(
      'thincoder',
      'launch: ${switch (build.kind) {
        ThincoderBuildKind.builtin => 'builtin',
        ThincoderBuildKind.checkout => 'checkout',
        ThincoderBuildKind.named || ThincoderBuildKind.installed => 'path',
      }} ${build.display}',
    );
    return ThincoderLaunch(
      cwd: cwd,
      executable: build.executable,
      arguments: build.arguments,
      environment: _withDataFolder(
        environment,
        build.kind == ThincoderBuildKind.builtin,
      ),
    );
  }

  /// The environment thincoder runs in — the one [launch] starts it with:
  /// the user's terminal's, and, for the build a distribution carries, the
  /// config folder that build keeps to. Settings → Models (thincoder)
  /// writes the file this names, so both name one file. With none to run,
  /// the carried build's folder where there is one: the one it would keep.
  static Future<Map<String, String>> environment() async {
    final environment = await ClaudeEnvironment.of();
    final builtin = builtinBuild();
    ThincoderBuild? build;
    try {
      build = _resolve(environment, builtin);
    } on ThincoderUnavailable {
      build = null;
    }
    return _withDataFolder(
      environment,
      build == null
          ? builtin != null
          : build.kind == ThincoderBuildKind.builtin,
    );
  }

  /// [environment] with the config folder of the build the app carries,
  /// when that is the build to run ([builtin]); the same map, unchanged,
  /// otherwise.
  static Map<String, String> _withDataFolder(
    Map<String, String> environment,
    bool builtin,
  ) => !builtin
      ? environment
      : {
          ...environment,
          configDirVariable: DataDirectory.current.thincoderDataDir,
        };

  /// The thincoder to run: the path set in Settings, else the one the
  /// distribution carries, else the checkout of the tree the app was built
  /// from, else the first of [candidates] that is there. Throws
  /// [ThincoderUnavailable] with what to do about it when there is none.
  static Future<ThincoderBuild> locateBuild([
    Map<String, String>? environment,
  ]) async {
    final env = environment ?? await ClaudeEnvironment.of();
    return _resolve(env, builtinBuild());
  }

  /// The thincoder to run: its executable (see [locateBuild]).
  static Future<String> locate([Map<String, String>? environment]) async =>
      (await locateBuild(environment)).executable;

  /// The build [environment] names: the one in Settings (not there: thrown,
  /// never fallen back from), else [builtin] when the distribution carries
  /// one, else the checkout of the tree the app was built from, else the
  /// PATH. With a [builtin], [candidates] is not even built: the PATH is
  /// not looked at where the app carries its own.
  static ThincoderBuild _resolve(
    Map<String, String> environment,
    ThincoderBuild? builtin,
  ) {
    final named = ThincoderPathSetting.current();
    if (named != null) {
      final path = _named(named, environment);
      if (!File(path).existsSync()) {
        throw ThincoderUnavailable(
          'thincoder is not at $path',
          detail:
              '$path does not exist. Correct it in Settings → General → '
              'thincoder, or clear it to run the installed one.',
        );
      }
      // The CLI's own entry file (a checkout's `bin/thincoder.cjs`), which
      // only node runs.
      if (_scriptExtensions.contains(p.extension(path).toLowerCase())) {
        final node = nodeOn(environment);
        if (node == null) {
          throw ThincoderUnavailable(
            'No node to run $path',
            detail:
                'Settings → General → thincoder names a script; install '
                '$nodeRequirement, or name a thincoder program instead.',
          );
        }
        return ThincoderBuild(
          display: path,
          executable: node,
          arguments: [path, ThincoderLaunch.command],
          kind: ThincoderBuildKind.named,
        );
      }
      return ThincoderBuild(
        display: path,
        executable: path,
        kind: ThincoderBuildKind.named,
      );
    }
    if (builtin != null) return builtin;
    if (checkoutBuild(environment) case final checkout?) return checkout;
    final found = candidates(environment)
        .where((path) => File(path).existsSync())
        .firstOrNull;
    if (found != null) return ThincoderBuild(display: found, executable: found);
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

  /// The folder the app's executable is in — the one its runtime sits
  /// beside; a test points it at a temporary one.
  @visibleForTesting
  static String? executableDirectoryOverride;

  /// Whether the platform's rule is the Mac's; [Platform.isMacOS] when null,
  /// so that a test on one machine covers both shapes.
  @visibleForTesting
  static bool? isMacOverride;

  /// The folder a distribution's runtime is in, from the folder its
  /// executable is in: `<dir>/runtime` on Windows, and on macOS
  /// `<dir>/../Resources/runtime` — the executable is in `Contents/MacOS`,
  /// and the runtime in the `Resources` beside that (§26.4).
  static String runtimeRootOf(String executableDirectory, {bool? isMac}) {
    if (isMac ?? Platform.isMacOS) {
      return p.join(p.dirname(executableDirectory), 'Resources', 'runtime');
    }
    return p.join(executableDirectory, 'runtime');
  }

  /// The build the distribution carries, when both of its parts are there:
  /// the CLI's source tree and the node that runs it. Half of one is none —
  /// the PATH is looked at as it always was.
  static ThincoderBuild? builtinBuild({
    String? executableDirectory,
    bool? isMac,
  }) {
    final directory =
        executableDirectory ??
        executableDirectoryOverride ??
        p.dirname(Platform.resolvedExecutable);
    final mac = isMac ?? isMacOverride ?? Platform.isMacOS;
    final root = runtimeRootOf(directory, isMac: mac);
    final entry = p.join(root, 'thincoder', 'bin', 'thincoder.cjs');
    final node = p.join(root, 'node', mac ? 'node' : 'node.exe');
    if (!File(entry).existsSync() || !File(node).existsSync()) return null;
    return ThincoderBuild(
      display: entry,
      executable: node,
      arguments: [entry, ThincoderLaunch.command],
      kind: ThincoderBuildKind.builtin,
    );
  }

  /// The files Settings may name that node runs, not the system.
  static const _scriptExtensions = {'.cjs', '.mjs', '.js'};

  /// How far above the app's own folder its source tree may be: a macOS
  /// build's executable is 8 folders down (`build/macos/Build/Products/
  /// Debug/BaoCode.app/Contents/MacOS`), a Windows one 5.
  static const _treeDepth = 10;

  /// The thincoder checked out in the source tree the app was built from
  /// (`<tree>/thincoder`, the one `tool/build_windows.dart` packages), run
  /// by the machine's own node: a build made from the tree runs the agent
  /// beside it, not whatever the PATH happens to have — and node is the
  /// process started, so stopping it stops the agent (an npm `.cmd` shim
  /// would put `cmd.exe` in between).
  ///
  /// Null where the app does not run from such a tree (an installed one),
  /// where the checkout cannot run as it stands (no `@thincoder/core` link
  /// beside its CLI: `node scripts/dev-link.mjs` makes it), or where there
  /// is no node; and under test, unless [executableDirectory] (or
  /// [executableDirectoryOverride]) says where to look from.
  static ThincoderBuild? checkoutBuild(
    Map<String, String> environment, {
    String? executableDirectory,
  }) {
    final from = executableDirectory ?? executableDirectoryOverride;
    if (from == null && Platform.environment.containsKey('FLUTTER_TEST')) {
      return null;
    }
    var dir = p.absolute(from ?? p.dirname(Platform.resolvedExecutable));
    for (var i = 0; i < _treeDepth; i++) {
      final cli = p.join(dir, 'thincoder', 'thincoder-cli');
      final entry = p.join(cli, 'bin', 'thincoder.cjs');
      if (File(p.join(dir, 'pubspec.yaml')).existsSync() &&
          File(entry).existsSync()) {
        final core = p.join(cli, 'node_modules', '@thincoder', 'core');
        if (!File(p.join(core, 'package.json')).existsSync()) return null;
        final node = nodeOn(environment);
        if (node == null) return null;
        return ThincoderBuild(
          display: entry,
          executable: node,
          arguments: [entry, ThincoderLaunch.command],
          kind: ThincoderBuildKind.checkout,
        );
      }
      final parent = p.dirname(dir);
      if (parent == dir) return null;
      dir = parent;
    }
    return null;
  }

  /// The node [environment]'s PATH finds, else the one Node's installer
  /// puts in place; null when there is none.
  static String? nodeOn(Map<String, String> environment) {
    final path = environment['PATH'] ?? '';
    final List<String> found;
    if (Platform.isWindows) {
      found = [
        for (final entry in path.split(';'))
          if (entry.trim().replaceAll('"', '') case final dir
              when dir.isNotEmpty)
            p.join(dir, 'node.exe'),
        if (environment['PROGRAMFILES'] case final programs?)
          p.join(programs, 'nodejs', 'node.exe'),
      ];
    } else {
      found = [
        for (final dir in path.split(':'))
          if (dir.isNotEmpty) p.join(dir, 'node'),
        '/usr/local/bin/node',
        '/opt/homebrew/bin/node',
      ];
    }
    return found.where((node) => File(node).existsSync()).firstOrNull;
  }

  /// The version [executable] says it is (`thincoder --version`, or
  /// [arguments] in its place); null when it does not run, or does not say.
  static Future<String?> versionOf(
    String executable, {
    Map<String, String>? environment,
    List<String> arguments = const ['--version'],
  }) async {
    try {
      final result = await ProcessHost.run(
        ProcessSpec(
          executable,
          arguments,
          environment: environment,
          includeParentEnvironment: true,
          runInShell: throughShell(executable),
        ),
      );
      return parseVersion('${result.stdout}\n${result.stderr}');
    } on ProcessHostUnavailable catch (error) {
      // Not "no version": the proxy itself is unavailable. Kept null for the
      // caller's existing contract, and said here so that it is in the log.
      appEvent('thincoder', 'version: $error');
      return null;
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
    final builtin = builtinBuild();
    try {
      final build = _resolve(environment, builtin);
      final version = await versionOf(
        build.executable,
        arguments: build.versionArguments,
        environment: environment,
      );
      if (version == null && build.kind == ThincoderBuildKind.builtin) {
        // Its files are there, so it is the build that would run; that it
        // will not is said, and the PATH is not fallen back to (§26.4).
        return ThincoderFailed(
          'The built-in runtime could not start (${build.executable}). '
          'Reinstall BaoCode, or set a path to a thincoder of your own in '
          'Settings → General → thincoder.',
        );
      }
      return ThincoderFound(build.display, version);
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
