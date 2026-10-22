import 'dart:convert';
import 'dart:io';

import 'package:baocode/kernel/thincoder/thincoder_config_file.dart';
import 'package:baocode/kernel/thincoder/thincoder_config_store.dart';
import 'package:bao_remote/local.dart' show AppPaths;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The store over a folder of its own (§27.3 / §27.7): T118–T125 and
/// T128–T130, and what the write path leans on (U16).
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('thincoder-config');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File configIn([String name = 'config.json']) => File(p.join(root.path, name));

  /// The files of [dir] whose name starts with [prefix], in order.
  List<File> filesStarting(Directory dir, String prefix) => [
    for (final entity
        in dir.listSync()..sort((a, b) => a.path.compareTo(b.path)))
      if (entity is File && p.basename(entity.path).startsWith(prefix)) entity,
  ];

  List<File> backups() => filesStarting(root, 'config.json.bak');
  List<File> temps() => filesStarting(root, 'config.json.tmp-');

  group('reading (§27.2)', () {
    test('T118: a missing file, or a missing folder, reads as an empty config '
        'and makes nothing', () async {
      final file = File(p.join(root.path, 'not-there', 'config.json'));
      final store = ThincoderConfigStore(file: file);

      final document = await store.read();

      expect(document.exists, isFalse);
      expect(document.providers, isEmpty);
      expect(document.defaultModel, isNull);
      expect(document.missing, ThincoderModelMissing.noProvider);
      expect(file.parent.existsSync(), isFalse);
      expect(file.existsSync(), isFalse);
    });

    test('a file that is not a JSON object is refused, not read as empty', () {
      for (final text in ['{not json', '[]', '', '{"a":']) {
        final file = configIn()..writeAsStringSync(text);
        final store = ThincoderConfigStore(file: file);
        expect(
          () => store.read(),
          throwsA(
            isA<ThincoderConfigException>().having(
              (error) => error.reason,
              'reason',
              ThincoderConfigFailure.invalidJson,
            ),
          ),
          reason: text,
        );
        // Nothing of the file was touched.
        expect(file.readAsStringSync(), text);
      }
    });
  });

  group('saving (§27.3)', () {
    test('T119: a provider lands in providers[] and defaultModel, written the '
        'CLI’s way, with no backup of an old file', () async {
      final file = configIn()..writeAsStringSync('{}\n');
      final store = ThincoderConfigStore(file: file);

      final result = await store.saveProvider(
        name: 'openai',
        baseURL: 'https://api.example.com/v1/',
        apiKey: 'sk-test-1234',
        model: 'gpt-5',
      );

      expect(result, isA<ThincoderSaved>());
      final raw = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      // Trailing slashes gone, as the CLI normalizes them (config-io.mjs:152).
      expect(raw['providers'], [
        {
          'name': 'openai',
          'baseURL': 'https://api.example.com/v1',
          'apiKey': 'sk-test-1234',
        },
      ]);
      expect(raw['defaultModel'], 'openai:gpt-5');
      // Two spaces, a final newline, no BOM (config-io.mjs:83).
      final text = file.readAsStringSync();
      expect(text, startsWith('{\n  "providers": [\n'));
      expect(text, endsWith('}\n'));
      expect(text.codeUnitAt(0), isNot(0xfeff));
      // The write is the read-back: what was asked reads back.
      final saved = result as ThincoderSaved;
      expect(saved.document.defaultModel, 'openai:gpt-5');
      expect(saved.document.providers.single.apiKey, 'sk-test-1234');
      // No old file: nothing to keep aside (§27.11: no rolling backup).
      expect(backups(), isEmpty);
      expect(temps(), isEmpty);
    });

    test('T120: every key but providers[] and defaultModel is left exactly as '
        'it was', () async {
      final before = {
        r'$schema': 'https://example.test/thincoder.schema.json',
        'agent': {
          'advisor': {'provider': 'x'},
          'consultModels': [
            {'provider': 'x', 'model': 'm1'},
          ],
          'engineering': true,
        },
        'subagentModels': {'reviewer': 'x:m1'},
        'providers': [
          {
            'name': 'x',
            'apiKey': 'k-old',
            'format': 'anthropic',
            'proxy': true,
          },
        ],
        'defaultModel': 'x:m1',
      };
      final file = configIn()..writeAsStringSync('${jsonEncode(before)}\n');
      final store = ThincoderConfigStore(file: file);

      final result = await store.saveProvider(
        name: 'y',
        baseURL: 'https://y.example.test',
        apiKey: 'k-new',
        model: 'm2',
      );
      expect(result, isA<ThincoderSaved>());

      final after = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      // The judged comparison (§27.3): both sides without the two keys it
      // may write, keys sorted, no whitespace.
      expect(rest(after), rest(before));
      // And the other entry keeps what only it has.
      final x = (after['providers'] as List)
          .cast<Map<String, Object?>>()
          .firstWhere((entry) => entry['name'] == 'x');
      expect(x['format'], 'anthropic');
      expect(x['proxy'], isTrue);
      expect(after['defaultModel'], 'y:m2');
    });

    test('T121: a provider already there is updated in place — its keys kept, '
        'its retired model gone, a blank key keeping the one it has', () async {
      final file = configIn()
        ..writeAsStringSync(
          '${jsonEncode({
            'providers': [
              {'name': 'x', 'baseURL': 'https://old.example.test/', 'apiKey': 'old-key', 'model': 'retired-model', 'format': 'anthropic', 'maxTokens': 4096},
            ],
            'defaultModel': 'x:old-model',
          })}\n',
        );
      final store = ThincoderConfigStore(file: file);

      final result = await store.saveProvider(
        name: 'x',
        baseURL: 'https://new.example.test',
        apiKey: 'new-key',
        model: 'new-model',
      );
      expect(result, isA<ThincoderSaved>());

      final raw = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final providers = (raw['providers'] as List).cast<Map<String, Object?>>();
      expect(providers, hasLength(1));
      expect(providers.single['baseURL'], 'https://new.example.test');
      expect(providers.single['apiKey'], 'new-key');
      expect(providers.single.containsKey('model'), isFalse);
      expect(providers.single['format'], 'anthropic');
      expect(providers.single['maxTokens'], 4096);
      expect(raw['defaultModel'], 'x:new-model');

      // Edited again with the key left blank (D115): the key it has stays.
      final again = await store.saveProvider(
        name: 'x',
        baseURL: 'https://newer.example.test',
        apiKey: '',
        model: 'new-model',
      );
      expect(again, isA<ThincoderSaved>());
      final kept = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      expect(
        (kept['providers'] as List)
            .cast<Map<String, Object?>>()
            .single['apiKey'],
        'new-key',
      );
    });

    test('T122: a write that cannot land is an ioError, with the old file as '
        'it was and nothing left behind', () async {
      // A folder that cannot be made: its parent is a file.
      final blocked = configIn('blocked')..writeAsStringSync('not a folder');
      final file = File(p.join(blocked.path, 'config.json'));
      final result = await ThincoderConfigStore(file: file).saveProvider(
        name: 'x',
        baseURL: 'https://x.example.test',
        apiKey: 'k',
        model: 'm',
      );
      expect(reasonOf(result), ThincoderConfigFailure.ioError);
      expect(backups(), isEmpty);
      expect(temps(), isEmpty);

      // A folder only its owner may change (POSIX; Windows has no such
      // mode).
      if (!Platform.isWindows) {
        final readonly = Directory(p.join(root.path, 'readonly'))..createSync();
        final existing = File(p.join(readonly.path, 'config.json'));
        const before = '{"providers":[],"defaultModel":"a:b"}\n';
        existing.writeAsStringSync(before);
        Process.runSync('chmod', ['0500', readonly.path]);
        try {
          final failed = await ThincoderConfigStore(file: existing)
              .saveProvider(
                name: 'x',
                baseURL: 'https://x.example.test',
                apiKey: 'k',
                model: 'm',
              );
          expect(reasonOf(failed), ThincoderConfigFailure.ioError);
          expect(existing.readAsStringSync(), before);
          expect(
            [for (final entity in readonly.listSync()) p.basename(entity.path)],
            ['config.json'],
          );
        } finally {
          Process.runSync('chmod', ['0700', readonly.path]);
        }
      }
    });

    test('T123: a file that is not JSON is refused — no write, no backup, no '
        'temp file', () async {
      const broken = '{not json';
      final file = configIn()..writeAsStringSync(broken);
      final result = await ThincoderConfigStore(file: file).saveProvider(
        name: 'x',
        baseURL: 'https://x.example.test',
        apiKey: 'k',
        model: 'm',
      );
      expect(reasonOf(result), ThincoderConfigFailure.invalidJson);
      expect(file.readAsStringSync(), broken);
      expect(backups(), isEmpty);
      expect(temps(), isEmpty);
    });

    test('T128: a file changed while saving is not written over: the conflict '
        'is said, the other side kept, one backup left', () async {
      final ours = '{"providers":[],"defaultModel":"a:b"}\n';
      final file = configIn()..writeAsStringSync(ours);
      // Their version, written between the first stat and the second: the
      // seam stands in for the other process.
      final theirs =
          '{"providers":[{"name":"z","apiKey":"other"}],'
          '"defaultModel":"z:o"}\n';
      var stats = 0;
      final store = ThincoderConfigStore(
        file: file,
        modified: (_) {
          stats++;
          if (stats == 1) return DateTime(2026);
          file.writeAsStringSync(theirs);
          return DateTime(2027);
        },
      );

      final result = await store.saveProvider(
        name: 'mine',
        baseURL: 'https://mine.example.test',
        apiKey: 'k',
        model: 'm',
      );

      expect(reasonOf(result), ThincoderConfigFailure.conflict);
      // Nothing of ours was written: the file is theirs, byte for byte.
      expect(file.readAsBytesSync(), utf8.encode(theirs));
      final left = backups();
      expect(left, hasLength(1));
      expect(left.single.readAsStringSync(), theirs);
      expect(temps(), isEmpty);
      // No rolling `config.json.bak`: the backup is the conflict's alone
      // (§27.11).
      expect(File(p.join(root.path, 'config.json.bak')).existsSync(), isFalse);
      // The reason says where the other side's version is.
      expect(
        (result as ThincoderSaveFailed).detail,
        contains(left.single.path),
      );
    });

    test('T129: a read-back that does not match fails the save, the file left '
        'as this save wrote it', () async {
      final file = configIn()..writeAsStringSync('{}\n');
      final store = ThincoderConfigStore(
        file: file,
        // What the CLI would read if it had dropped defaultModel.
        readBack: (_) => '{"providers":[]}',
      );

      final result = await store.saveProvider(
        name: 'x',
        baseURL: 'https://x.example.test',
        apiKey: 'k',
        model: 'm',
      );

      expect(reasonOf(result), ThincoderConfigFailure.verifyFailed);
      // Checked, not rolled back.
      final raw = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      expect(raw['defaultModel'], 'x:m');
      expect((raw['providers'] as List).single, {
        'name': 'x',
        'baseURL': 'https://x.example.test',
        'apiKey': 'k',
      });
    });

    test('T130: a name or a Base URL that would not be read is refused; a '
        'providers that is not a list is replaced by one', () async {
      const before = '{"providers":[],"defaultModel":"a:b"}\n';
      final file = configIn()..writeAsStringSync(before);
      final store = ThincoderConfigStore(file: file);

      Future<void> refused(String name, String baseURL) async {
        final result = await store.saveProvider(
          name: name,
          baseURL: baseURL,
          apiKey: 'k',
          model: 'm',
        );
        expect(
          reasonOf(result),
          ThincoderConfigFailure.invalidField,
          reason: name,
        );
        expect(file.readAsStringSync(), before);
      }

      // A name the CLI would filter out, or cut defaultModel at.
      await refused('', 'https://x.example.test');
      await refused('   ', 'https://x.example.test');
      await refused('a:b', 'https://x.example.test');
      // A Base URL with nothing in it.
      await refused('x', '');
      await refused('x', '   ');
      expect(backups(), isEmpty);
      expect(temps(), isEmpty);

      // providers that is not a list: read as none, written as one.
      final notList = configIn('not-list.json')
        ..writeAsStringSync('{"providers":{"x":1},"defaultModel":"a:b"}\n');
      final other = ThincoderConfigStore(file: notList);
      expect((await other.read()).providersNotList, isTrue);
      final saved = await other.saveProvider(
        name: 'x',
        baseURL: 'https://x.example.test',
        apiKey: 'k',
        model: 'm',
      );
      expect(saved, isA<ThincoderSaved>());
      expect((saved as ThincoderSaved).providersWasNotList, isTrue);
      final raw =
          jsonDecode(notList.readAsStringSync()) as Map<String, Object?>;
      expect(raw['providers'], [
        {'name': 'x', 'baseURL': 'https://x.example.test', 'apiKey': 'k'},
      ]);
    });
  });

  test('a save with no model is refused: defaultModel would name none the CLI '
      'could read (F24 ③)', () async {
    const before = '{"providers":[],"defaultModel":"a:b"}\n';
    final file = configIn()..writeAsStringSync(before);
    final result = await ThincoderConfigStore(file: file).saveProvider(
      name: 'x',
      baseURL: 'https://x.example.test',
      apiKey: 'k',
      model: '   ',
    );
    expect(reasonOf(result), ThincoderConfigFailure.invalidField);
    expect(file.readAsStringSync(), before);
    expect(backups(), isEmpty);
    expect(temps(), isEmpty);
  });

  group('where it writes (§27.2)', () {
    test(
      'T124: THINCODER_CONFIG_DIR names the folder as it is, else the home '
      'the environment gives; the machine’s own ~/.thincoder is not touched',
      () async {
        final named = Directory(p.join(root.path, 'named'))..createSync();
        final environment = {
          'THINCODER_CONFIG_DIR': ' ${named.path} ',
          'HOME': root.path,
          'USERPROFILE': root.path,
        };
        // As it is, trimmed: the CLI spells no `~` out (config-io.mjs:32).
        expect(resolveThincoderConfigDir(environment), named.path);
        expect(
          thincoderConfigFile(environment).path,
          p.join(named.path, 'config.json'),
        );
        expect(
          resolveThincoderConfigDir({'THINCODER_CONFIG_DIR': r'~/tc'}),
          r'~/tc',
        );
        // No such key: `<home>/.thincoder`, as the CLI would.
        expect(
          thincoderConfigFile({'HOME': root.path, 'USERPROFILE': root.path})
              .path,
          p.join(root.path, '.thincoder', 'config.json'),
        );

        // A save through the environment's answer stays where it names; the
        // machine's own folder is as it was.
        final own = Directory(
          p.join(AppPaths.home(Platform.environment), '.thincoder'),
        );
        final ownBefore = own.existsSync() ? own.statSync().modified : null;
        final store = ThincoderConfigStore(
          file: thincoderConfigFile(environment),
        );
        expect(await store.read().then((document) => document.exists), isFalse);
        final result = await store.saveProvider(
          name: 'x',
          baseURL: 'https://x.example.test',
          apiKey: 'k',
          model: 'm',
        );
        expect(result, isA<ThincoderSaved>());
        expect(File(p.join(named.path, 'config.json')).existsSync(), isTrue);
        expect(own.existsSync() ? own.statSync().modified : null, ownBefore);
        expect(
          [for (final entity in named.listSync()) p.basename(entity.path)],
          ['config.json'],
        );
      },
    );
  });

  group('what the CLI reads (U14)', () {
    test('T125: the CLI’s own reader takes what was written — the offline '
        'firmware for the real one', () async {
      final file = configIn();
      final result = await ThincoderConfigStore(file: file).saveProvider(
        name: 'openai',
        baseURL: 'https://api.example.com/v1/',
        apiKey: 'sk-test-1234',
        model: 'gpt-5',
      );
      expect(result, isA<ThincoderSaved>());

      final core = p.join(
        Directory.current.path,
        'thincoder',
        'thincoder-core',
        'config-io.mjs',
      );
      if (!File(core).existsSync()) {
        markTestSkipped('no thincoder-core next to this checkout');
        return;
      }
      final ProcessResult run;
      try {
        run = await Process.run('node', [
          '--input-type=module',
          '-e',
          'import { _setConfigPathForTest, resolveProviders } from '
              '${jsonEncode(Uri.file(core).toString())};'
              '_setConfigPathForTest(${jsonEncode(file.path)});'
              'console.log(JSON.stringify(resolveProviders()));',
        ]);
      } on ProcessException {
        markTestSkipped('no node on this machine (U14)');
        return;
      }
      expect(run.exitCode, 0, reason: '${run.stderr}');
      final read = jsonDecode((run.stdout as String).trim());
      expect(read['activeProvider'], 'openai');
      expect(read['providers'], [
        {
          'name': 'openai',
          'baseURL': 'https://api.example.com/v1',
          'apiKey': 'sk-test-1234',
        },
      ]);
    });
  });

  test('U16: a temp file renamed over one that is there replaces it', () {
    // What the write path relies on, on this machine's filesystem: Windows
    // included, where a rename over an existing file may be refused.
    final target = configIn('target.json')..writeAsStringSync('old');
    final temp = configIn('temp.json')..writeAsStringSync('new');
    temp.renameSync(target.path);
    expect(target.readAsStringSync(), 'new');
    expect(temp.existsSync(), isFalse);
  });
}

/// The failure [result] names, or null for one that went through.
ThincoderConfigFailure? reasonOf(ThincoderSaveResult result) =>
    result is ThincoderSaveFailed ? result.reason : null;

/// [raw] with `providers` and `defaultModel` gone, keys sorted, no
/// whitespace: what "every other key is left exactly as it was" is judged
/// by (§27.3).
String rest(Map<String, Object?> raw) {
  final copy = jsonDecode(jsonEncode(raw)) as Map<String, Object?>
    ..remove('providers')
    ..remove('defaultModel');
  return canonicalJson(copy);
}

String canonicalJson(Object? value) {
  if (value is Map) {
    final keys = [for (final key in value.keys) '$key']..sort();
    return '{${[for (final key in keys) '${jsonEncode(key)}:${canonicalJson(value[key])}'].join(',')}}';
  }
  if (value is List) {
    return '[${[for (final item in value) canonicalJson(item)].join(',')}]';
  }
  return jsonEncode(value);
}
