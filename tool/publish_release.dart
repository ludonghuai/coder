// Publishes a release to GitHub, where installed apps find their updates:
// the installer and the manifest (docs/design/distribution.md). Run from
// anywhere in the repository, after tool/build_windows.dart and
// tool/release_manifest.dart:
//
//   set /p GITHUB_TOKEN=GitHub PAT:
//   dart run tool/publish_release.dart --version 1.6.1 \
//     --setup build/installers/BaoCode-1.6.1-setup.exe \
//     --manifest build/installers/latest.json \
//     --notes release-notes/1.6.1.zh.md
//
// In this order, so that nothing points at a file that is not there yet:
//
//  1. The release tagged v<version>: the one there is used again; a draft a
//     run that failed left behind is found among the drafts and used again;
//     none at all is made, as a draft. A draft is not "the latest": installed
//     apps keep finding the release before it until step 3.
//  2. The two files, each under its own name, the installer first and the
//     manifest last: the asset of that name already there is deleted, then
//     the file goes up. Run again, it ends with the same two assets.
//  3. The release is made public (draft=false, prerelease=false; no change
//     when it already was): releases/latest/download/latest.json is this one
//     from then on, with both assets there.
//  4. Both are read back: the size on GitHub against the file's.
//
// A work tree with changes in it is refused: what is released has to be in
// the commit the tag points at. --dry-run prints what it would ask GitHub,
// and asks nothing.
//
// The token is a classic PAT's, `repo`, or a fine-grained one's `Contents:
// read and write` on this repository, which is unverified until the first
// run (docs/design/distribution.md §15 U5).
import 'dart:convert';
import 'dart:io';

import 'package:baocode/update/update_manifest.dart';
import 'package:baocode/update/version.dart';

/// Where the token is: it may write the repository's releases.
const _tokenVariable = 'GITHUB_TOKEN';

/// GitHub's API for this fork's repository, and where an asset goes up.
const _repositoryApi = 'https://api.github.com/repos/$updateRepository';
const _repositoryUploads =
    'https://uploads.github.com/repos/$updateRepository/releases';

const _usage = '''
Usage:
  dart run tool/publish_release.dart --setup <setup.exe>
      --manifest <latest.json> [--version <version>]
      [--notes <text|file>] [--dry-run]

The release is tagged v<version>, which is pubspec.yaml's unless given;
--notes is the release's body. \$$_tokenVariable holds a token that may
write the repository's releases.''';

Future<void> main(List<String> arguments) async {
  final options = _parse(arguments);
  if (options.containsKey('help')) {
    stdout.writeln(_usage);
    return;
  }
  final dryRun = options.containsKey('dry-run');
  final token = Platform.environment[_tokenVariable]?.trim() ?? '';
  if (token.isEmpty) {
    _fail(
      '\$$_tokenVariable is not set: it is a GitHub token that may write '
      'the releases of $updateRepository.\n\n$_usage',
    );
  }
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final version = AppVersion.parse(
    options['version'] ?? _pubspecVersion(File('${root.path}/pubspec.yaml')),
  );
  final tag = 'v${version.marketing}';
  final files = [
    ('--setup', File(_given(options, 'setup'))),
    ('--manifest', File(_given(options, 'manifest'))),
  ];
  for (final (option, file) in files) {
    if (!file.existsSync()) _fail('No such file ($option): ${file.path}');
  }
  final notes = switch (options['notes']) {
    final value? => _textOrFile(value),
    null => '',
  };

  // What is released has to be in a commit: the tag is this one.
  final dirty = _git(root, ['status', '--porcelain'])
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList();
  if (dirty.isNotEmpty) {
    _fail(
      'The work tree has changes in it, so what would be released is not '
      'in any commit:\n${dirty.map((line) => '  $line').join('\n')}\n'
      'Commit them, or put them aside, and run this again.',
    );
  }
  final head = _git(root, ['rev-parse', 'HEAD']);

  if (dryRun) {
    _printPlan(tag, head, files);
    return;
  }

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30)
    ..userAgent = 'BaoCode-publish-release';
  try {
    final github = _GitHub(client, token);
    stdout.writeln(
      'Releasing $tag from ${head.substring(0, 7)} into $updateRepository',
    );
    final id = await github.releaseFor(tag, commit: head, notes: notes);

    // 2. Each file under its name: the one there is deleted, then the file.
    final before = await github.assets(id);
    for (final (_, file) in files) {
      final name = file.uri.pathSegments.last;
      for (final asset in before.where((asset) => asset['name'] == name)) {
        stdout.writeln('  deleting the asset named $name (${asset['id']})');
        await github.deleteAsset(asset['id']! as int);
      }
      stdout.writeln('  uploading $name (${file.lengthSync()} bytes)');
      await github.upload(id, file, name);
    }

    // 3. Public: the latest release from now on, both assets there.
    final published = await github.publish(id);
    stdout.writeln(
      '  public: draft=${published['draft']}, '
      'prerelease=${published['prerelease']}',
    );

    // 4. Read back: each one's size on GitHub against the file's.
    final after = await github.assets(id);
    for (final (_, file) in files) {
      final name = file.uri.pathSegments.last;
      final asset = after.where((asset) => asset['name'] == name).firstOrNull;
      if (asset == null) _fail('$name is not on $tag after the upload.');
      final size = asset['size'];
      if (size != file.lengthSync()) {
        _fail('$name is $size bytes on GitHub, not ${file.lengthSync()}.');
      }
      stdout.writeln('  $name: $size bytes  ${asset['browser_download_url']}');
    }
    stdout
      ..writeln()
      ..writeln(
        'Released: https://github.com/$updateRepository/releases/tag/$tag',
      );
  } finally {
    client.close(force: true);
  }
}

/// What the run would ask GitHub, in the order it would.
void _printPlan(String tag, String head, List<(String, File)> files) {
  final commit = head.substring(0, 7);
  final names = [for (final (_, file) in files) file.uri.pathSegments.last];
  final sizes = [for (final (_, file) in files) '${file.lengthSync()} bytes'];
  final setup = '$_repositoryUploads/<id>/assets?name=${names[0]}';
  final manifest = '$_repositoryUploads/<id>/assets?name=${names[1]}';
  stdout
    ..writeln('Dry run: nothing is sent.')
    ..writeln('  repository  $updateRepository')
    ..writeln('  tag         $tag at $commit')
    ..writeln('  1. GET    $_repositoryApi/releases/tags/$tag')
    ..writeln('              200: that release, used again')
    ..writeln(
      '              404: GET $_repositoryApi/releases?per_page=100 — a '
      'draft tagged $tag',
    )
    ..writeln('                   found there is used again; where none:')
    ..writeln('     POST   $_repositoryApi/releases')
    ..writeln(
      '              draft=true, prerelease=false, '
      'target_commitish=$commit, body=<the notes>',
    )
    ..writeln('  2. GET    $_repositoryApi/releases/<id>/assets')
    ..writeln('     DELETE $_repositoryApi/releases/assets/<asset id>')
    ..writeln('              each asset named ${names.join(' or ')}')
    ..writeln('     POST   $setup')
    ..writeln('              ${sizes[0]}')
    ..writeln('     POST   $manifest')
    ..writeln('              ${sizes[1]}')
    ..writeln('  3. PATCH  $_repositoryApi/releases/<id>')
    ..writeln('              draft=false, prerelease=false')
    ..writeln('  4. GET    $_repositoryApi/releases/<id>/assets')
    ..writeln('              each size against the file\'s');
}

/// GitHub's API, as [token] allows it to be written to.
class _GitHub {
  _GitHub(this.client, this.token);

  final HttpClient client;
  final String token;

  /// The release tagged [tag]: the one there is, else a draft of it (a run
  /// that failed may have left one, which the tag endpoint need not name),
  /// else one made now as a draft. The id it gives is the release's.
  Future<int> releaseFor(
    String tag, {
    required String commit,
    required String notes,
  }) async {
    final published = await _call(
      'GET',
      '$_repositoryApi/releases/tags/$tag',
      also: const {HttpStatus.notFound},
    );
    if (published case final Map<String, Object?> release) {
      stdout.writeln('  the release for $tag is there: used again');
      return release['id'] as int;
    }
    final drafts = await _call('GET', '$_repositoryApi/releases?per_page=100');
    final draft = (drafts! as List)
        .whereType<Map<String, Object?>>()
        .where((release) => release['tag_name'] == tag)
        .firstOrNull;
    if (draft != null) {
      stdout.writeln('  a draft for $tag is there: used again');
      return draft['id'] as int;
    }
    stdout.writeln('  no release for $tag: making it a draft');
    final made = await _call(
      'POST',
      '$_repositoryApi/releases',
      body: {
        'tag_name': tag,
        'name': tag,
        'body': notes,
        'draft': true,
        'prerelease': false,
        'target_commitish': commit,
      },
    );
    return (made! as Map<String, Object?>)['id'] as int;
  }

  /// The assets [release] has now.
  Future<List<Map<String, Object?>>> assets(int release) async {
    final list = await _call(
      'GET',
      '$_repositoryApi/releases/$release/assets?per_page=100',
    );
    return (list! as List).whereType<Map<String, Object?>>().toList();
  }

  Future<void> deleteAsset(int asset) =>
      _call('DELETE', '$_repositoryApi/releases/assets/$asset');

  /// [file] as the asset named [name].
  Future<void> upload(int release, File file, String name) => _call(
    'POST',
    '$_repositoryUploads/$release/assets?name=${Uri.encodeQueryComponent(name)}',
    file: file,
  );

  /// [release], public: the latest one from now on.
  Future<Map<String, Object?>> publish(int release) async {
    final published = await _call(
      'PATCH',
      '$_repositoryApi/releases/$release',
      body: {'draft': false, 'prerelease': false},
    );
    return published! as Map<String, Object?>;
  }

  /// [method] [url], with [body] (JSON) or [file] as what it sends: the
  /// response's JSON (null when there is none). The statuses in [also] are
  /// answers too, their JSON null; any other failure says what GitHub said.
  Future<Object?> _call(
    String method,
    String url, {
    Object? body,
    File? file,
    Set<int> also = const {},
  }) async {
    final request = await client.openUrl(method, Uri.parse(url));
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      request.headers.contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.add(bytes);
    } else if (file != null) {
      request.headers.contentType = ContentType('application', 'octet-stream');
      request.contentLength = file.lengthSync();
      await request.addStream(file.openRead());
    }
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    if (also.contains(response.statusCode)) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _fail('$method $url: HTTP ${response.statusCode}\n$text');
    }
    return text.trim().isEmpty ? null : jsonDecode(text);
  }
}

/// pubspec.yaml's `version:` line, for the release when --version is not
/// given.
String _pubspecVersion(File pubspec) {
  final match = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  if (match == null) _fail('No "version:" line in ${pubspec.path}');
  return match.group(1)!;
}

/// [name]'s value, which the release cannot be made without.
String _given(Map<String, String?> options, String name) {
  if (options[name] case final value?) return value;
  _fail('--$name is missing.\n\n$_usage');
}

/// [value] itself, or the file it names.
String _textOrFile(String value) {
  final file = File(value);
  return file.existsSync() ? file.readAsStringSync().trim() : value;
}

String _git(Directory root, List<String> arguments) {
  final result = Process.runSync('git', arguments, workingDirectory: root.path);
  if (result.exitCode != 0) {
    _fail('git ${arguments.join(' ')}: ${result.stderr}');
  }
  return (result.stdout as String).trim();
}

/// `--name value` pairs; `--flag` alone for those without one.
Map<String, String?> _parse(List<String> arguments) {
  const flags = {'dry-run', 'help'};
  const valued = {'version', 'setup', 'manifest', 'notes'};
  final options = <String, String?>{};
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    final name = argument.startsWith('--') ? argument.substring(2) : null;
    if (name == null || !(flags.contains(name) || valued.contains(name))) {
      _fail('Unknown argument: $argument\n\n$_usage');
    }
    if (flags.contains(name)) {
      options[name] = null;
    } else if (i + 1 < arguments.length) {
      options[name] = arguments[++i];
    } else {
      _fail('--$name needs a value.\n\n$_usage');
    }
  }
  return options;
}

Never _fail(String message) {
  stderr.writeln('\n$message');
  exit(1);
}
