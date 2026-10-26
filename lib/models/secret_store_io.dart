import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../platform/data_dir.dart';
import '../platform/process_host.dart';
import 'secret_store.dart';

/// The system's keychain: the login keychain on macOS, the user's DPAPI
/// on Windows, the Secret Service on Linux (a file only the user reads
/// where there is none).
SecretStore systemSecretStore() {
  if (Platform.isMacOS) return KeychainSecretStore();
  if (Platform.isWindows) {
    return DpapiSecretStore(p.join(DataDirectory.current.path, 'secrets'));
  }
  return SecretServiceStore(
    fallback: FileSecretStore(p.join(DataDirectory.current.path, 'secrets')),
  );
}

/// Runs [executable] with [arguments], [input] on its stdin.
typedef SecretCommand = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? input,
});

/// The default [SecretCommand]: the process the host starts, in its own
/// isolate.
///
/// One PowerShell launch is some 460 ms on Windows, and every launch made
/// on the window thread froze the window for that long — a storm of them
/// every five minutes held it for six seconds (2026-10-26).
Future<ProcessResult> _run(
  String executable,
  List<String> arguments, {
  String? input,
}) async {
  try {
    final process = await ProcessHost.start(ProcessSpec(executable, arguments));
    // Leniently: what goes to stderr is not always UTF-8 (PowerShell's
    // progress, in the system's code page on a Chinese Windows).
    const decoder = Utf8Decoder(allowMalformed: true);
    // Listened to from the start, an error carried into a value: one on a
    // stream nothing is listening to yet would be reported as unhandled,
    // and this store's failure is a [SecretStoreException].
    var out = '';
    var err = '';
    Object? streamError;
    final read = Future.wait<void>([
      process.stdout
          .transform(decoder)
          .join()
          .then<void>((text) {
            out = text;
          }, onError: (Object error) {
            streamError = error;
          }),
      process.stderr
          .transform(decoder)
          .join()
          .then<void>((text) {
            err = text;
          }, onError: (Object error) {
            streamError = error;
          }),
    ]);
    if (input != null) {
      try {
        process.write(utf8.encode(input));
      } on StateError {
        // Gone already: its exit code and stderr say why.
      }
    }
    process.closeStdin();
    final code = await process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    // A grace, not a wait: a process killed above may leave its pipes to a
    // child, and the answer then is what came, with the exit code saying
    // the rest.
    await read.timeout(
      const Duration(seconds: 5),
      onTimeout: () => const <void>[],
    );
    if (streamError != null) {
      throw SecretStoreException('The secret could not be reached: $streamError');
    }
    return ProcessResult(process.pid, code, out, err);
  } on ProcessHostUnavailable catch (error) {
    throw SecretStoreException('The secret could not be reached: $error');
  }
}

/// The macOS login keychain, through `security`: generic passwords of
/// the service `BaoCode`, by account. The secret goes on its stdin (in
/// hex), never in a command line.
class KeychainSecretStore implements SecretStore {
  KeychainSecretStore({@visibleForTesting SecretCommand? run})
    : _command = run ?? _run;

  final SecretCommand _command;

  static const service = 'BaoCode';

  /// `security`'s "not found".
  static const _notFound = 44;

  @override
  Future<String?> read(String id) async {
    final result = await _command('/usr/bin/security', [
      'find-generic-password',
      '-s',
      service,
      '-a',
      id,
      '-w',
    ]);
    if (result.exitCode == _notFound) return null;
    if (result.exitCode != 0) throw _failed('read', result);
    final value = '${result.stdout}'.replaceFirst(RegExp(r'\r?\n$'), '');
    return value.isEmpty ? null : value;
  }

  @override
  Future<void> write(String id, String value) async {
    final hex = [
      for (final byte in utf8.encode(value))
        byte.toRadixString(16).padLeft(2, '0'),
    ].join();
    // Interactive: the command, the secret in it, read from stdin.
    final result = await _command('/usr/bin/security', [
      '-i',
    ], input: 'add-generic-password -U -s $service -a ${_quote(id)} -X $hex\n');
    if (result.exitCode != 0 || '${result.stderr}'.contains('error')) {
      throw _failed('kept', result);
    }
  }

  @override
  Future<void> delete(String id) async {
    final result = await _command('/usr/bin/security', [
      'delete-generic-password',
      '-s',
      service,
      '-a',
      id,
    ]);
    if (result.exitCode != 0 && result.exitCode != _notFound) {
      throw _failed('removed', result);
    }
  }

  static String _quote(String text) => '"${text.replaceAll('"', '')}"';
}

/// The user's DPAPI on Windows, through PowerShell: each secret encrypted
/// for the user, in a file of [directory].
class DpapiSecretStore implements SecretStore {
  DpapiSecretStore(this.directory, {@visibleForTesting SecretCommand? run})
    : _command = run ?? _run;

  final String directory;
  final SecretCommand _command;

  /// What each secret came to, per run: a decryption is a PowerShell
  /// launch, and a secret is read as often as it is needed (the forge
  /// reads its token on every request — some 120 launches in 36 seconds
  /// every five minutes, measured 2026-10-26). One decryption each, then.
  final Map<String, String> _values = {};

  /// The secrets being decrypted right now: a second [read] of one waits
  /// for that launch instead of starting another.
  final Map<String, Future<String?>> _reading = {};

  /// How many times each secret was changed here: a decryption that was
  /// under way when it changed does not write its answer over the change.
  final Map<String, int> _changed = {};

  /// No progress: PowerShell's first run of a session prepares its modules
  /// with a progress record on stderr.
  static const _prelude =
      r'$ErrorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; '
      r'Add-Type -AssemblyName System.Security; ';

  File _file(String id) => File(p.join(directory, '${_safe(id)}.dpapi'));

  Future<ProcessResult> _powershell(String script, String input) => _command(
    'powershell.exe',
    ['-NoProfile', '-NonInteractive', '-Command', _prelude + script],
    input: input,
  );

  @override
  Future<String?> read(String id) async {
    final kept = _values[id];
    if (kept != null) return kept;
    final pending = _reading[id];
    if (pending != null) return pending;
    final changed = _changed[id] ?? 0;
    final reading = _decrypt(id);
    _reading[id] = reading;
    try {
      final value = await reading;
      // Kept only if the secret was not changed while it was being read:
      // what its file holds now is not what this launch read.
      if (value != null && (_changed[id] ?? 0) == changed) _values[id] = value;
      return value;
    } finally {
      _reading.remove(id);
    }
  }

  /// [id]'s secret out of its file: null when there is no file. A failure
  /// is not remembered — the next [read] tries again.
  Future<String?> _decrypt(String id) async {
    final file = _file(id);
    if (!file.existsSync()) return null;
    final result = await _powershell(
      r'$b = [Convert]::FromBase64String([Console]::In.ReadToEnd().Trim()); '
      r'$p = [Security.Cryptography.ProtectedData]::Unprotect($b, $null, "CurrentUser"); '
      r'[Console]::Out.Write([Convert]::ToBase64String($p))',
      await file.readAsString(),
    );
    if (result.exitCode != 0) throw _failed('read', result);
    try {
      return utf8.decode(base64.decode('${result.stdout}'.trim()));
    } on FormatException {
      throw const SecretStoreException(
        'The key could not be read: what is kept is not what this build wrote',
      );
    }
  }

  @override
  Future<void> write(String id, String value) async {
    final result = await _powershell(
      r'$b = [Convert]::FromBase64String([Console]::In.ReadToEnd().Trim()); '
      r'$p = [Security.Cryptography.ProtectedData]::Protect($b, $null, "CurrentUser"); '
      r'[Console]::Out.Write([Convert]::ToBase64String($p))',
      base64.encode(utf8.encode(value)),
    );
    if (result.exitCode != 0) throw _failed('kept', result);
    final file = _file(id);
    await file.parent.create(recursive: true);
    await file.writeAsString('${result.stdout}'.trim(), flush: true);
    _values[id] = value;
    _changed[id] = (_changed[id] ?? 0) + 1;
  }

  @override
  Future<void> delete(String id) async {
    _values.remove(id);
    _changed[id] = (_changed[id] ?? 0) + 1;
    final file = _file(id);
    if (file.existsSync()) await file.delete();
  }
}

/// The Secret Service (GNOME Keyring, KWallet), through `secret-tool`;
/// [fallback] where it is not installed.
class SecretServiceStore implements SecretStore {
  SecretServiceStore({
    required this.fallback,
    @visibleForTesting SecretCommand? run,
  }) : _command = run ?? _run;

  final SecretStore fallback;
  final SecretCommand _command;

  Future<bool>? _available;

  Future<bool> get _hasTool => _available ??= _command('which', [
    'secret-tool',
  ]).then((result) => result.exitCode == 0, onError: (_) => false);

  List<String> _attributes(String id) => ['service', 'baocode', 'account', id];

  @override
  Future<String?> read(String id) async {
    if (!await _hasTool) return fallback.read(id);
    final result = await _command('secret-tool', [
      'lookup',
      ..._attributes(id),
    ]);
    // Not found: exit 1 and nothing said.
    if (result.exitCode != 0) {
      if ('${result.stderr}'.trim().isEmpty) return fallback.read(id);
      throw _failed('read', result);
    }
    final value = '${result.stdout}';
    return value.isEmpty ? null : value;
  }

  @override
  Future<void> write(String id, String value) async {
    if (!await _hasTool) return fallback.write(id, value);
    final result = await _command('secret-tool', [
      'store',
      '--label=BaoCode: $id',
      ..._attributes(id),
    ], input: value);
    if (result.exitCode != 0) throw _failed('kept', result);
    await fallback.delete(id);
  }

  @override
  Future<void> delete(String id) async {
    if (await _hasTool) {
      await _command('secret-tool', ['clear', ..._attributes(id)]);
    }
    await fallback.delete(id);
  }
}

/// Files only the user reads (0600, in a folder of 0700): for where the
/// system keeps no secrets.
class FileSecretStore implements SecretStore {
  FileSecretStore(this.directory);

  final String directory;

  File _file(String id) => File(p.join(directory, _safe(id)));

  @override
  Future<String?> read(String id) async {
    final file = _file(id);
    if (!file.existsSync()) return null;
    final value = await file.readAsString();
    return value.isEmpty ? null : value;
  }

  @override
  Future<void> write(String id, String value) async {
    final folder = Directory(directory);
    if (!folder.existsSync()) {
      await folder.create(recursive: true);
      await _mode(directory, '700');
    }
    final file = _file(id);
    // Made empty and closed to others before the secret goes in.
    await file.writeAsString('');
    await _mode(file.path, '600');
    await file.writeAsString(value, flush: true);
  }

  /// [path] to [mode], who may read it: 0700 a folder, 0600 a file.
  /// Nothing on Windows, which has no chmod — nor this store
  /// ([systemSecretStore]).
  static Future<void> _mode(String path, String mode) async {
    if (Platform.isWindows) return;
    await Process.run('chmod', [mode, path]);
  }

  @override
  Future<void> delete(String id) async {
    final file = _file(id);
    if (file.existsSync()) await file.delete();
  }
}

/// [id] as a file name.
String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

SecretStoreException _failed(String what, ProcessResult result) {
  final said = '${result.stderr}'.trim();
  return SecretStoreException(
    'The key could not be $what${said.isEmpty ? ' (exit ${result.exitCode})' : ': $said'}',
  );
}
