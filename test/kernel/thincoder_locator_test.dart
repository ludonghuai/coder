import 'dart:io';

import 'package:baocode/kernel/thincoder/thincoder_locator.dart';
import 'package:baocode/kernel/thincoder/thincoder_process_io.dart';
import 'package:baocode/kernel/thincoder/thincoder_transport.dart';
import 'package:baocode/platform/data_dir.dart';
import 'package:bao_remote/local.dart' show ClaudeEnvironment;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The runtime a distribution carries, beside the app's executable
/// (§26.4 / §26.11): T112, T112a, T112b, T113, T113a, T113b, T114, T115a,
/// T115b and T117a.
void main() {
  late Directory root;
  late DataDirectory previousData;

  setUp(() {
    root = Directory.systemTemp.createTempSync('thincoder-locator');
    previousData = DataDirectory.current;
    DataDirectory.current = DataDirectory(p.join(root.path, 'data'));
  });

  tearDown(() {
    DataDirectory.current = previousData;
    ThincoderPathSetting.current = () => null;
    ThincoderLocator.candidatesOverride = null;
    ThincoderLocator.executableDirectoryOverride = null;
    ThincoderLocator.isMacOverride = null;
    ClaudeEnvironment.use(null);
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// The folder the app's executable is in, made, with [name] to tell two
  /// apart.
  String executableFolder([String name = 'app']) {
    final dir = p.join(root.path, name);
    Directory(dir).createSync(recursive: true);
    return dir;
  }

  /// The runtime a Windows distribution carries in [executableDirectory],
  /// both parts made; answers the CLI's entry file.
  String putRuntime(String executableDirectory) {
    final runtime = p.join(executableDirectory, 'runtime');
    final entry = File(p.join(runtime, 'thincoder', 'bin', 'thincoder.cjs'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('');
    File(p.join(runtime, 'node', 'node.exe'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('');
    return entry.path;
  }

  /// A thincoder a PATH, or a setting, names: a file that is there.
  String putCli() {
    final file = File(p.join(root.path, 'bin', 'thincoder'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('');
    return file.path;
  }

  /// The environment the app is run with, saying nothing about a thincoder.
  Map<String, String> environment() => {
    'PATH': '',
    'HOME': root.path,
    'USERPROFILE': root.path,
  };

  group('no runtime beside the app', () {
    test(
      'T112: the PATH is looked at as it always was (the Windows shape)',
      () async {
        final app = executableFolder();
        ThincoderLocator.executableDirectoryOverride = app;
        ThincoderLocator.isMacOverride = false;
        expect(ThincoderLocator.builtinBuild(), isNull);

        // The list is `candidates()`' own, unchanged (`:137-160`).
        const windows = {
          'PATH': r'C:\a;D:\b',
          'APPDATA': r'C:\Users\me\AppData\Roaming',
        };
        expect(ThincoderLocator.candidates(windows), [
          p.join(r'C:\a', 'thincoder.cmd'),
          p.join(r'C:\a', 'thincoder.exe'),
          p.join(r'D:\b', 'thincoder.cmd'),
          p.join(r'D:\b', 'thincoder.exe'),
          p.join(r'C:\Users\me\AppData\Roaming', 'npm', 'thincoder.cmd'),
          p.join(r'C:\Users\me\AppData\Roaming', 'npm', 'thincoder.exe'),
        ]);

        var asked = 0;
        final installed = putCli();
        ThincoderLocator.candidatesOverride = (_) {
          asked++;
          return [installed];
        };
        final env = environment();
        ClaudeEnvironment.use(env);
        expect(await ThincoderLocator.locate(env), installed);
        expect(asked, 1);

        final launch = await ThincoderLocator.launch('/project');
        expect(launch.executable, installed);
        expect(launch.arguments, ['acp']);
        expect(launch.environment, equals(env));
        expect(
          launch.environment.containsKey(ThincoderLocator.configDirVariable),
          isFalse,
        );
      },
      skip: Platform.isWindows ? false : 'the Windows candidate list',
    );

    test('T112a: the Mac app carries its runtime under Contents/Resources, '
        'and without one the PATH is looked at', () async {
      final contents = p.join(root.path, 'BaoCode.app', 'Contents');
      final macos = p.join(contents, 'MacOS');
      Directory(macos).createSync(recursive: true);

      // The rule itself, from a folder that need not be there: the function
      // reads nothing (pure), and takes the platform as a parameter.
      final absent = p.join(root.path, 'nowhere', 'MacOS');
      expect(
        ThincoderLocator.runtimeRootOf(absent, isMac: true),
        p.join(root.path, 'nowhere', 'Resources', 'runtime'),
      );
      expect(
        ThincoderLocator.runtimeRootOf(absent, isMac: false),
        p.join(absent, 'runtime'),
      );
      expect(
        ThincoderLocator.runtimeRootOf(macos, isMac: true),
        p.join(contents, 'Resources', 'runtime'),
      );

      // Nothing under Resources: no runtime.
      expect(
        ThincoderLocator.builtinBuild(executableDirectory: macos, isMac: true),
        isNull,
      );
      // A Windows runtime in the same folder is not one the Mac looks at.
      putRuntime(macos);
      expect(
        ThincoderLocator.builtinBuild(executableDirectory: macos, isMac: true),
        isNull,
      );

      // On a Mac the candidates are the five kinds it always had.
      if (!Platform.isWindows) {
        expect(
          ThincoderLocator.candidates({'PATH': '/a:/b', 'HOME': root.path}),
          [
            '/a/thincoder',
            '/b/thincoder',
            p.join(root.path, '.local', 'bin', 'thincoder'),
            '/usr/local/bin/thincoder',
            '/opt/homebrew/bin/thincoder',
          ],
        );
      }

      var asked = 0;
      final installed = putCli();
      ThincoderLocator.candidatesOverride = (_) {
        asked++;
        return [installed];
      };
      ThincoderLocator.executableDirectoryOverride = macos;
      ThincoderLocator.isMacOverride = true;
      expect(await ThincoderLocator.locate(environment()), installed);
      expect(asked, 1);
    });

    test('T112b: half a runtime is no runtime — the PATH is asked', () async {
      final env = environment();
      ClaudeEnvironment.use(env);
      final installed = putCli();
      var asked = 0;
      ThincoderLocator.candidatesOverride = (_) {
        asked++;
        return [installed];
      };
      for (final half in ['entry', 'node']) {
        final app = executableFolder(half);
        ThincoderLocator.executableDirectoryOverride = app;
        ThincoderLocator.isMacOverride = false;
        final runtime = p.join(app, 'runtime');
        final only = half == 'entry'
            ? p.join(runtime, 'thincoder', 'bin', 'thincoder.cjs')
            : p.join(runtime, 'node', 'node.exe');
        File(only)
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('');

        expect(ThincoderLocator.builtinBuild(), isNull);
        final before = asked;
        expect(await ThincoderLocator.locate(env), installed);
        expect(asked, before + 1);
        final launch = await ThincoderLocator.launch('/project');
        expect(launch.environment, equals(env));
        expect(
          launch.environment.containsKey(ThincoderLocator.configDirVariable),
          isFalse,
        );
      }
    });
  });

  group('a runtime beside the app', () {
    test('T113: it is the build run, and the PATH is never asked', () async {
      final app = executableFolder();
      final entry = putRuntime(app);
      ThincoderLocator.executableDirectoryOverride = app;
      ThincoderLocator.isMacOverride = false;
      var asked = 0;
      ThincoderLocator.candidatesOverride = (_) {
        asked++;
        return const [];
      };
      final env = environment();
      ClaudeEnvironment.use(env);

      final build = await ThincoderLocator.locateBuild(env);
      expect(build.display, entry, reason: 'what Settings shows');
      expect(p.basename(build.executable), 'node.exe');
      expect(await ThincoderLocator.locate(env), build.executable);
      expect(asked, 0, reason: 'a candidate list is not even made');

      final launch = await ThincoderLocator.launch('/project');
      expect(p.basename(launch.executable), 'node.exe');
      expect(launch.arguments, [entry, 'acp']);
      expect(ThincoderLocator.throughShell(launch.executable), isFalse);
      expect(asked, 0);
    });

    test('T113a: on the Mac it is the one under Contents/Resources', () async {
      final contents = p.join(root.path, 'BaoCode.app', 'Contents');
      final macos = p.join(contents, 'MacOS');
      Directory(macos).createSync(recursive: true);
      final runtime = p.join(contents, 'Resources', 'runtime');
      final entry = File(p.join(runtime, 'thincoder', 'bin', 'thincoder.cjs'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('');
      File(p.join(runtime, 'node', 'node'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('');
      ThincoderLocator.executableDirectoryOverride = macos;
      ThincoderLocator.isMacOverride = true;
      var asked = 0;
      ThincoderLocator.candidatesOverride = (_) {
        asked++;
        return const [];
      };
      ClaudeEnvironment.use(environment());

      // What Settings shows is the CLI's file; what is run is node.
      expect((await ThincoderLocator.locateBuild()).display, entry.path);
      expect(await ThincoderLocator.locate(), p.join(runtime, 'node', 'node'));
      expect(asked, 0);
      final launch = await ThincoderLocator.launch('/project');
      expect(p.basename(launch.executable), 'node');
      expect(launch.arguments, [entry.path, 'acp']);
    });

    test(
      'T113b: one that will not start is said of, not fallen back from',
      () async {
        final app = executableFolder();
        putRuntime(app); // node.exe is an empty file: it cannot run.
        ThincoderLocator.executableDirectoryOverride = app;
        ThincoderLocator.isMacOverride = false;
        var asked = 0;
        ThincoderLocator.candidatesOverride = (_) {
          asked++;
          return const [];
        };
        ClaudeEnvironment.use(environment());

        final status = await ThincoderLocator.status();
        expect(status, isA<ThincoderFailed>());
        final message = (status as ThincoderFailed).message;
        expect(message, contains(p.join(app, 'runtime', 'node', 'node.exe')));
        expect(message, contains('built-in runtime could not start'));

        // Its files are there, so it is still the build that would run.
        expect(
          await ThincoderLocator.locate(),
          p.join(app, 'runtime', 'node', 'node.exe'),
        );
        expect(asked, 0);
      },
    );

    test(
      'T114: a path set that is not there is said of, this one not used',
      () async {
        final app = executableFolder();
        putRuntime(app);
        ThincoderLocator.executableDirectoryOverride = app;
        ThincoderLocator.isMacOverride = false;
        final missing = p.join(root.path, 'not-there', 'thincoder');
        ThincoderPathSetting.current = () => missing;
        var asked = 0;
        ThincoderLocator.candidatesOverride = (_) {
          asked++;
          return [putCli()];
        };
        ClaudeEnvironment.use(environment());

        await expectLater(
          ThincoderLocator.locate(),
          throwsA(
            isA<ThincoderUnavailable>()
                .having((error) => error.message, 'message', contains(missing))
                .having((error) => error.detail, 'detail', contains(missing)),
          ),
        );
        final status = await ThincoderLocator.status();
        expect(status, isA<ThincoderFailed>());
        expect((status as ThincoderFailed).message, contains(missing));
        expect(asked, 0);
      },
    );
  });

  group('the data folder (§26.5)', () {
    test('T115a: the runtime gets a folder of its own', () async {
      final app = executableFolder();
      putRuntime(app);
      ThincoderLocator.executableDirectoryOverride = app;
      ThincoderLocator.isMacOverride = false;
      final env = environment();
      ClaudeEnvironment.use(env);

      final launch = await ThincoderLocator.launch('/project');
      // The settings page resolves the file to write from the same
      // environment, so both name one folder.
      expect(await ThincoderLocator.environment(), equals(launch.environment));
      final folder = DataDirectory.current.thincoderDataDir;
      expect(
        folder,
        p.join(DataDirectory.current.path, 'runtime-data', 'thincoder'),
      );
      expect(p.isAbsolute(folder), isTrue);
      expect(launch.environment[ThincoderLocator.configDirVariable], folder);
      // Nothing else in the environment moved.
      expect(
        {...launch.environment}..remove(ThincoderLocator.configDirVariable),
        equals(env),
      );
    });

    test(
      'T115b: with none, the environment is the one it always was',
      () async {
        final app = executableFolder();
        ThincoderLocator.executableDirectoryOverride = app;
        ThincoderLocator.isMacOverride = false;
        final env = environment();
        ClaudeEnvironment.use(env);
        final installed = putCli();
        ThincoderLocator.candidatesOverride = (_) => [installed];

        // Found on the PATH.
        final found = await ThincoderLocator.launch('/project');
        expect(
          found.environment.containsKey(ThincoderLocator.configDirVariable),
          isFalse,
        );
        expect(found.environment, equals(env));
        // The page's own folder: `~/.thincoder`, as it always was.
        expect(await ThincoderLocator.environment(), equals(env));

        // Set in Settings, and a good path.
        ThincoderPathSetting.current = () => installed;
        final named = await ThincoderLocator.launch('/project');
        expect(named.executable, installed);
        expect(
          named.environment.containsKey(ThincoderLocator.configDirVariable),
          isFalse,
        );
        expect(named.environment, equals(env));
      },
    );
  });

  test('T117a: the runtime’s process is still listed as a thincoder one', () {
    final registry = ThincoderProcessRegistry(
      file: File(p.join(root.path, 'state', 'thincoder-processes.json')),
    );
    expect(
      registry.file.path,
      endsWith(p.join('state', 'thincoder-processes.json')),
    );
    const command =
        r'C:\apps\BaoCode\runtime\node\node.exe '
        r'C:\apps\BaoCode\runtime\thincoder\bin\thincoder.cjs acp';
    expect(registry.recognizes(command), isTrue);
    expect(
      registry.recognizes(
        r'C:\apps\BaoCode\runtime\node\node.exe '
        r'C:\apps\BaoCode\runtime\thincoder\bin\thincoder.cjs',
      ),
      isFalse,
      reason: 'no session was asked for',
    );

    // The line the kernel starts has both words in it, whatever the app's
    // folder.
    final app = executableFolder();
    putRuntime(app);
    ThincoderLocator.executableDirectoryOverride = app;
    ThincoderLocator.isMacOverride = false;
    final build = ThincoderLocator.builtinBuild()!;
    final started = [build.executable, ...build.arguments].join(' ');
    expect(started, contains('thincoder.cjs'));
    expect(started, contains('acp'));
    // And the app's own list is the one it always was.
    expect(
      p.basename(ThincoderProcess.registry.file.path),
      'thincoder-processes.json',
    );
  });
}
