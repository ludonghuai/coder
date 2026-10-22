import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

// Reading and writing the thincoder CLI's config.json (§27.2 / §27.3): the
// one file the kernel reads its providers from. Only `providers[]` and the
// top-level `defaultModel` are written; every other key stays as it is.

/// One entry of `providers[]`, as Settings → Models (thincoder) lists it
/// (`thincoder-core/config.mjs:1-12`).
class ThincoderProvider {
  const ThincoderProvider({
    required this.name,
    required this.baseURL,
    required this.apiKey,
  });

  final String name;
  final String baseURL;

  /// The key as the file holds it — never shown as it is: [maskedKey] is
  /// what a page shows (the CLI's own face masks it the same way,
  /// `thincoder-desktop/src/main/providers.mjs`).
  final String apiKey;

  /// The key's last four characters behind dots (`••••1234`), or dots
  /// alone; empty when the file has no key. A key of four characters or
  /// fewer shows no part of itself.
  String get maskedKey {
    if (apiKey.isEmpty) return '';
    final shown = apiKey.length > 4 ? apiKey.substring(apiKey.length - 4) : '';
    return '••••$shown';
  }
}

/// Why a new session has no model to start with (§27.5 ④): the CLI's own
/// two reasons, said again here.
enum ThincoderModelMissing { noProvider, noDefaultModel }

/// `config.json` as the settings page reads it.
class ThincoderConfigDocument {
  const ThincoderConfigDocument({
    required this.file,
    required this.exists,
    required this.providers,
    required this.defaultModel,
    this.providersNotList = false,
  });

  /// The file read.
  final File file;

  /// Whether it is there: a missing file (or folder) reads as an empty
  /// config, and the first save makes it (§27.2).
  final bool exists;

  /// The entries the CLI would read (`config-io.mjs:148-150`): those that
  /// are objects with a name.
  final List<ThincoderProvider> providers;

  /// The model a new session starts with, `provider:model`; null when the
  /// file does not set one.
  final String? defaultModel;

  /// Whether the file's `providers` was something other than a list: a save
  /// replaces it with one, and the page says so (§27.4).
  final bool providersNotList;

  /// The provider [defaultModel] names, and its model: null when unset or
  /// not of the `provider:model` shape the CLI reads at the first `:`
  /// (`config-io.mjs:168-172`).
  ({String provider, String model})? get defaultModelRef {
    final value = defaultModel;
    if (value == null) return null;
    final at = value.indexOf(':');
    if (at <= 0 || at == value.length - 1) return null;
    return (provider: value.substring(0, at), model: value.substring(at + 1));
  }

  /// What is missing for a new session to have a model; null when nothing
  /// is (§27.5 ④).
  ThincoderModelMissing? get missing {
    if (providers.isEmpty) return ThincoderModelMissing.noProvider;
    if (defaultModel == null) return ThincoderModelMissing.noDefaultModel;
    return null;
  }
}

/// Why a read or a save did not go through: the five states the page says
/// (§27.5 ⑦).
enum ThincoderConfigFailure {
  invalidJson,
  invalidField,
  conflict,
  ioError,
  verifyFailed,
}

/// A read that did not go through: what was wrong, and with which file.
class ThincoderConfigException implements Exception {
  const ThincoderConfigException(this.reason, this.file, [this.detail]);

  final ThincoderConfigFailure reason;
  final File file;

  /// What exactly, in a line (`the provider name is empty`), where the
  /// reason alone does not say it.
  final String? detail;

  @override
  String toString() =>
      'ThincoderConfigException(${reason.name}): ${file.path}'
      '${detail == null ? '' : ' — $detail'}';
}

/// What a save did.
sealed class ThincoderSaveResult {
  const ThincoderSaveResult();
}

/// Written, read back, and found as written: [document] is the file now.
final class ThincoderSaved extends ThincoderSaveResult {
  const ThincoderSaved(this.document, {this.providersWasNotList = false});

  final ThincoderConfigDocument document;

  /// Whether the file's `providers` was not a list and was replaced by one
  /// holding this entry (§27.4).
  final bool providersWasNotList;
}

/// Not written — but for [ThincoderConfigFailure.verifyFailed], where it was
/// written and read back differently.
final class ThincoderSaveFailed extends ThincoderSaveResult {
  const ThincoderSaveFailed(this.reason, this.file, [this.detail]);

  final ThincoderConfigFailure reason;
  final File file;

  /// A line more where there is one: the field that did not pass, the
  /// backup a conflict left, what the read-back found.
  final String? detail;
}

/// Reads and writes the CLI's `config.json` (§27.3): the steps in the order
/// they are judged, nothing written before every check passed and the file
/// was not changed meanwhile.
class ThincoderConfigStore {
  ThincoderConfigStore({required this.file, this.modified, this.readBack});

  /// The file written: the CLI's own (see `thincoderConfigFile`), or one a
  /// test gives.
  final File file;

  /// The file's last change, as the concurrency gate compares it; null when
  /// the file is missing (`config-io.mjs:60-64` catches the same way). A
  /// test scripts it to change the file between the two reads (T128).
  @visibleForTesting
  final DateTime? Function(File file)? modified;

  /// What the read-back after a write reads: the file's own text, or one a
  /// test scripts (T129).
  @visibleForTesting
  final String Function(File file)? readBack;

  /// The file as it is now; a missing file (or folder) reads as an empty
  /// config (§27.2). Throws [ThincoderConfigException] for what a save
  /// would refuse to overwrite.
  Future<ThincoderConfigDocument> read() async {
    final (raw, exists) = _readRaw();
    return _document(raw, exists: exists, providersNotList: _notList(raw));
  }

  /// Writes [name]'s provider entry and the model a new session starts
  /// with (§27.3): read → parse → check and merge → the concurrency gate →
  /// a temp file over the target → 0600 → read back.
  ///
  /// [apiKey] empty keeps the key the entry has (D115): a key is never
  /// shown back, so a blank field means "leave it".
  Future<ThincoderSaveResult> saveProvider({
    required String name,
    required String baseURL,
    required String apiKey,
    required String model,
  }) async {
    try {
      return _saveProvider(
        name: name,
        baseURL: baseURL,
        apiKey: apiKey,
        model: model,
      );
    } on ThincoderConfigException catch (error) {
      return ThincoderSaveFailed(error.reason, error.file, error.detail);
    } on FileSystemException catch (error) {
      return ThincoderSaveFailed(
        ThincoderConfigFailure.ioError,
        file,
        error.message,
      );
    }
  }

  ThincoderSaveResult _saveProvider({
    required String name,
    required String baseURL,
    required String apiKey,
    required String model,
  }) {
    // 1: the baseline the gate compares, taken before the read
    // (`config-io.mjs:60-64`: stat → read, the safe direction).
    final t0 = _modified();
    // 2–3: what is there now (missing reads as an empty config), parsed — a
    // file that is not a JSON object is refused here, never overwritten
    // (`config-io.mjs:64-72`).
    final (raw, _) = _readRaw();
    final providersNotList = _notList(raw);
    // 4: the fields, then the merge — every check before anything is
    // written (§27.4).
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return _invalid('the provider name is empty');
    }
    if (trimmedName.contains(':')) {
      return _invalid(
        'the provider name holds ":" — defaultModel is read at the first '
        'one, and would be cut in the wrong place',
      );
    }
    final trimmedBaseURL = baseURL.trim();
    if (trimmedBaseURL.isEmpty) return _invalid('the Base URL is empty');
    // A model is what `defaultModel` names: none would leave the file with
    // one the CLI reads as no model at all (`handlers-session.mjs:51`), and
    // a session's model menu emptier than before (§27.3 step 4 checks the
    // four fields).
    final trimmedModel = model.trim();
    if (trimmedModel.isEmpty) return _invalid('the model is empty');
    // As the CLI normalizes it when it reads (`config-io.mjs:152`).
    final normalized = trimmedBaseURL.replaceFirst(RegExp(r'/+$'), '');
    final trimmedKey = apiKey.trim();

    final entries = <Object?>[
      if (raw['providers'] case final List<Object?> list) ...list,
    ];
    var expectedKey = trimmedKey;
    final at = entries.indexWhere(
      (entry) => entry is Map && entry['name'] == trimmedName,
    );
    if (at >= 0) {
      // An entry there: its own keys stay, `baseURL` and `apiKey` written,
      // `model` gone (retired — `config-io.mjs:153-154`).
      final entry = entries[at] as Map;
      final previousKey = entry['apiKey'];
      expectedKey = trimmedKey.isNotEmpty
          ? trimmedKey
          : previousKey is String
          ? previousKey
          : '';
      entry['baseURL'] = normalized;
      entry['apiKey'] = expectedKey;
      entry.remove('model');
    } else {
      entries.add(<String, Object?>{
        'name': trimmedName,
        'baseURL': normalized,
        'apiKey': expectedKey,
      });
    }
    raw['providers'] = entries;
    final expectedModel = '$trimmedName:$trimmedModel';
    raw['defaultModel'] = expectedModel;

    // 5: the gate's only reading, before anything is written.
    final t1 = _modified();
    // 6: changed meanwhile ⇒ nothing of ours is written; the other side's
    // version is copied aside (`config-io.mjs:76-80`).
    if (t0 != t1) {
      String? backup;
      try {
        if (file.existsSync()) {
          backup = '${file.path}.bak-${DateTime.now().millisecondsSinceEpoch}';
          file.copySync(backup);
        }
      } on FileSystemException {
        // The backup failing does not hide the conflict.
        backup = null;
      }
      return ThincoderSaveFailed(
        ThincoderConfigFailure.conflict,
        file,
        backup == null ? null : 'the file as it was changed is at $backup',
      );
    }

    // 7: a temp file beside it, then over it (`config-io.mjs:81-84`).
    final text = '${const JsonEncoder.withIndent('  ').convert(raw)}\n';
    _write(text);
    // 8: 0600, best effort (POSIX only — `config-io.mjs:84`).
    _chmod();
    // 9: what came back is what was asked.
    final readBack = this.readBack;
    final String written;
    if (readBack != null) {
      written = readBack(file);
    } else {
      try {
        written = file.readAsStringSync();
      } on FileSystemException catch (error) {
        // Written, and not to be checked: said as what it is (§27.3-9).
        return _verifyFailed(
          'the file could not be read back: ${error.message}',
        );
      }
    }
    return _verify(
      written,
      expectedModel: expectedModel,
      name: trimmedName,
      apiKey: expectedKey,
      providersWasNotList: providersNotList,
    );
  }

  /// What the read-back found: the file as written, or why it was not.
  ThincoderSaveResult _verify(
    String text, {
    required String expectedModel,
    required String name,
    required String apiKey,
    required bool providersWasNotList,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return _verifyFailed('the file read back is not JSON');
    }
    if (decoded is! Map<String, Object?>) {
      return _verifyFailed('the file read back is not a JSON object');
    }
    if (decoded['defaultModel'] != expectedModel) {
      return _verifyFailed(
        'defaultModel reads "${decoded['defaultModel']}", not '
        '"$expectedModel"',
      );
    }
    final entry = switch (decoded['providers']) {
      final List<Object?> entries =>
        entries
            .whereType<Map>()
            .where((entry) => entry['name'] == name)
            .firstOrNull,
      _ => null,
    };
    if (entry == null) return _verifyFailed('provider "$name" is not there');
    if (entry['apiKey'] != apiKey) {
      return _verifyFailed('provider "$name" reads another key');
    }
    return ThincoderSaved(
      _document(decoded, exists: true, providersNotList: providersWasNotList),
      providersWasNotList: providersWasNotList,
    );
  }

  ThincoderSaveFailed _invalid(String detail) =>
      ThincoderSaveFailed(ThincoderConfigFailure.invalidField, file, detail);

  ThincoderSaveFailed _verifyFailed(String detail) =>
      ThincoderSaveFailed(ThincoderConfigFailure.verifyFailed, file, detail);

  /// The file's contents as a map, and whether it is there; throws
  /// [ThincoderConfigException] when what is there cannot be read as one.
  (Map<String, Object?>, bool) _readRaw() {
    if (!file.existsSync()) return (<String, Object?>{}, false);
    final String text;
    try {
      text = file.readAsStringSync();
    } on FileSystemException catch (error) {
      throw ThincoderConfigException(
        ThincoderConfigFailure.ioError,
        file,
        error.message,
      );
    } on FormatException {
      // Not UTF-8: not what the CLI could read either.
      throw ThincoderConfigException(ThincoderConfigFailure.invalidJson, file);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (error) {
      throw ThincoderConfigException(
        ThincoderConfigFailure.invalidJson,
        file,
        error.message,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw ThincoderConfigException(
        ThincoderConfigFailure.invalidJson,
        file,
        'not a JSON object',
      );
    }
    return (decoded, true);
  }

  DateTime? _modified() {
    final scripted = modified;
    if (scripted != null) return scripted(file);
    try {
      return file.statSync().modified;
    } on FileSystemException {
      return null;
    }
  }

  /// Writes [text] beside the file and moves it over; a move that fails
  /// (a lock on Windows, another volume) writes the target itself instead.
  void _write(String text) {
    final directory = file.parent;
    directory.createSync(recursive: true);
    final tmp = File(
      p.join(
        directory.path,
        '${p.basename(file.path)}.tmp-$pid-'
        '${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    try {
      tmp.writeAsStringSync(text, flush: true);
    } on FileSystemException {
      _delete(tmp);
      rethrow;
    }
    try {
      tmp.renameSync(file.path);
      return;
    } on FileSystemException {
      _delete(tmp);
    }
    file.writeAsStringSync(text, flush: true);
  }

  void _delete(File tmp) {
    try {
      if (tmp.existsSync()) tmp.deleteSync();
    } on FileSystemException {
      // Nothing to clean up, or not ours to.
    }
  }

  void _chmod() {
    if (Platform.isWindows) return;
    try {
      Process.runSync('chmod', ['600', file.path]);
    } on Object {
      // Best effort: the file holds the keys (see §27.11).
    }
  }

  static bool _notList(Map<String, Object?> raw) =>
      raw['providers'] != null && raw['providers'] is! List;

  ThincoderConfigDocument _document(
    Map<String, Object?> raw, {
    required bool exists,
    required bool providersNotList,
  }) => ThincoderConfigDocument(
    file: file,
    exists: exists,
    providers: [
      for (final entry in switch (raw['providers']) {
        final List<Object?> entries => entries,
        _ => const <Object?>[],
      })
        if (entry is Map &&
            entry['name'] is String &&
            (entry['name'] as String).isNotEmpty)
          ThincoderProvider(
            name: entry['name'] as String,
            baseURL: entry['baseURL'] is String
                ? entry['baseURL'] as String
                : '',
            apiKey: entry['apiKey'] is String ? entry['apiKey'] as String : '',
          ),
    ],
    defaultModel: switch (raw['defaultModel']) {
      final String value when value.isNotEmpty => value,
      _ => null,
    },
    providersNotList: providersNotList,
  );
}
