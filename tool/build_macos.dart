// Builds the macOS distribution, one for Apple silicon (arm64) and one for
// Intel (x64): each a .dmg that ships the app and a .zip the app updates
// itself from (lib/update/; signed into the release manifest by
// tool/release_manifest.dart). Flutter builds the app once, universal; each
// is that app thinned to one architecture (ditto --arch), about half its
// size. Run from anywhere in the repository:
//
//   dart run tool/build_macos.dart                build, then package
//   dart run tool/build_macos.dart --skip-build   package what is built
//   dart run tool/build_macos.dart --remote-built build the app, take the
//                                                remote server already in
//                                                build/remote/ (CI builds
//                                                it once, for both apps)
//   dart run tool/build_macos.dart --channel      the channel build
//                                                (BAOCODE_CHANNEL; lib/channel/),
//                                                its files named -channel
//   dart run tool/build_macos.dart --remote-release [VERSION]
//                                                take the remote server
//                                                published (the newest
//                                                without VERSION; tool/
//                                                fetch_remote_server.dart)
//                                                instead of building one
//
// They land in build/installers/: BaoCode-<version>-<arch>.dmg and
// BaoCode-<version>-mac-<arch>.zip, arch arm64 or x64 (the channel
// build's ending in -channel: BaoCode-<version>-<arch>-channel.dmg…); beside them,
// remote/<VERSION>/, the remote server's gzipped builds, which the app
// downloads instead of carrying them (tool/build_remote_server.dart), to
// upload with the release.
//
// Signed with a Developer ID and notarised when the environment says how
// (docs/release.md has how to get each):
//
//   BAOCODE_MACOS_SIGN_IDENTITY  the certificate's SHA-1 (40 hex digits, as
//                                `security find-identity -v -p codesigning`
//                                lists it) or its name, "Developer ID
//                                Application: <name> (<team>)"; in a
//                                keychain searched
//   BAOCODE_NOTARY_KEY           an App Store Connect API key (.p8), its path
//   BAOCODE_NOTARY_KEY_ID        that key's ID
//   BAOCODE_NOTARY_ISSUER        its issuer ID
//
// Without an identity the app is signed ad hoc, again: the remote server's
// files put in it after flutter signed it have to be sealed too, or the
// signature is broken and the app refuses the update (lib/update/
// installer_io.dart checks it). Ad hoc, it opens on this machine; Gatekeeper
// refuses it on anyone else's ("BaoCode is damaged and can't be opened").
// Signed but not notarised, it is refused too, with another message.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Where the .app flutter leaves behind goes, and where the disk image is
/// written. Under build/, which the repository already ignores and flutter
/// clean already removes.
const _bundleRelative = 'build/macos/Build/Products/Release/BaoCode.app';
const _installersRelative = 'build/installers';

/// Where each architecture's app is made of the universal one.
const _thinRelative = 'build/macos/thin';

/// The disk image window's background (tool/dmg_background.swift).
const _dmgBackgroundRelative = 'macos/packaging/dmg-background.tiff';

/// The architectures shipped: ditto's and lipo's name for each, and the one
/// in file names and in the manifest's platforms (`macos-arm64`).
const _architectures = {'arm64': 'arm64', 'x86_64': 'x64'};

/// Where the remote server is built (tool/build_remote_server.dart).
const _remoteRelative = 'build/remote';

/// Where one published is taken to (tool/fetch_remote_server.dart).
const _remoteReleaseRelative = 'build/remote-release';

/// The browser's native messaging host, beside the app's executable.
const _browserHost = 'baocode-browser-host';

/// The Node.js release the runtime carries, the SHA-256 of its macOS
/// tarballs, and the version of the thincoder source tree it is built from:
/// checked against these constants, not against each other (as
/// tool/build_windows.dart does). Both architectures' node go in, lipo'd
/// into one binary that `ditto --arch` thins with each app.
const _nodeVersion = 'v24.11.1';
const _nodeSha256 = {
  'arm64': 'b05aa3a66efe680023f930bd5af3fdbbd542794da5644ca2ad711d68cbd4dc35',
  'x64': '096081b6d6fcdd3f5ba0f5f1d44a47e83037ad2e78eada26671c252fe64dd111',
};
const _thincoderVersion = '0.12.76';
const _thincoderFiles = ['bin', 'src', 'package.json', 'LICENSE'];
const _runtimeRequired = [
  'Contents/Resources/runtime/node/node',
  'Contents/Resources/runtime/thincoder/bin/thincoder.cjs',
  'Contents/Resources/runtime/thincoder/LICENSE',
  'Contents/Resources/runtime/THIRD-PARTY-NOTICES.txt',
];

/// The licenses the runtime carries beside the CLI's own (`LICENSE`), which
/// the app ships as they are: what a distribution has to say about what it
/// includes.
const _notices =
    '''
BaoCode's thincoder runtime

runtime/thincoder is the thincoder CLI, MIT licensed; its license is in
runtime/thincoder/LICENSE.

runtime/thincoder/node_modules/@thincoder/core is @thincoder/core, MIT
licensed; its license is in that folder's LICENSE.

runtime/node/node is Node.js $_nodeVersion, MIT licensed, with the licenses
of what it is built from inside it. Node.js's own license and its
third-party notices are published at
https://github.com/nodejs/node/blob/main/LICENSE and in the release it came
from, https://nodejs.org/dist/$_nodeVersion/.
''';

/// What has to be in the .app for it to start. As on Windows, a build that
/// failed late still leaves an .app behind that looks complete — these are
/// what tell the difference.
const _required = [
  'Contents/MacOS/BaoCode',
  'Contents/Info.plist',
  'Contents/Frameworks/FlutterMacOS.framework',
  'Contents/Frameworks/App.framework',
  'Contents/Frameworks/App.framework/Resources/flutter_assets',
  // The terminal's native half (bao_pty's hook/build.dart builds it).
  'Contents/Frameworks/bao_pty.framework',
  // Finder's context menu (macos/FinderExtension), which Settings → General
  // turns on.
  'Contents/PlugIns/FinderExtension.appex',
  // What Chrome runs for BaoCode's extension (macos/BrowserBridge).
  'Contents/MacOS/$_browserHost',
  // The server remote projects run on their host (Linux and macOS, x64 and
  // arm64; tool/build_remote_server.dart): which build, and where it is
  // downloaded from.
  'Contents/Resources/remote/VERSION',
  'Contents/Resources/remote/servers.json',
];

Future<void> main(List<String> arguments) async {
  if (!Platform.isMacOS) {
    _fail(
      'This builds the macOS disk image, and only runs on macOS.\n'
      'On Windows, use tool/build_windows.dart.',
    );
  }
  final skipBuild = arguments.contains('--skip-build');
  final channel = arguments.contains('--channel');
  final edition = channel ? '-channel' : '';
  final releaseAt = arguments.indexOf('--remote-release');
  final remoteRelease = releaseAt < 0
      ? null
      : releaseAt + 1 < arguments.length &&
            !arguments[releaseAt + 1].startsWith('--')
      ? arguments[releaseAt + 1]
      : 'latest';
  final remoteBuilt =
      skipBuild ||
      remoteRelease != null ||
      arguments.contains('--remote-built');

  // The script lives in tool/, so the repository is one level above it.
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final bundle = Directory('${root.path}/$_bundleRelative');
  final installers = Directory('${root.path}/$_installersRelative');
  final remote = Directory(
    '${root.path}/${remoteRelease == null ? _remoteRelative : _remoteReleaseRelative}',
  );
  final version = _readVersion(File('${root.path}/pubspec.yaml'));

  if (!skipBuild) {
    _step('Building the Release app${channel ? ' (the channel build)' : ''}');
    await _run('flutter', [
      'build',
      'macos',
      '--release',
      if (channel) '--dart-define=BAOCODE_CHANNEL=true',
    ], root.path);
  } else {
    _step('Using the app already built');
  }
  if (remoteRelease != null) {
    _step('Taking the remote server published');
    await _run(Platform.resolvedExecutable, [
      'run',
      'tool/fetch_remote_server.dart',
      remoteRelease,
      '--out',
      remote.path,
    ], root.path);
  } else if (!remoteBuilt) {
    _step('Building the remote server');
    await _run(Platform.resolvedExecutable, [
      'run',
      'tool/build_remote_server.dart',
      '--out',
      remote.path,
    ], root.path);
  }

  // Into the .app before it is signed: its files are resources, sealed
  // with the rest. Not the builds themselves, which the app downloads.
  _step('Putting the remote server\'s download list in the app');
  final remoteVersion = _bundleRemote(
    remote,
    Directory('${bundle.path}/Contents/Resources/remote'),
  );

  _step(
    'Putting in the thincoder runtime $_thincoderVersion '
    '(Node.js $_nodeVersion)',
  );
  await _putRuntime(root, bundle);

  _step('Checking the app');
  _checkBundle(bundle, [..._required, ..._runtimeRequired]);
  await _checkUniversal(bundle);
  // An app built before pubspec.yaml's version changed (--skip-build) would
  // be shipped as the new version, and offered as an update to itself.
  final built = await _plist(bundle, 'CFBundleShortVersionString');
  final build = await _plist(bundle, 'CFBundleVersion');
  if (built != version.marketing || build != version.build) {
    _fail(
      'The app is version $built ($build), pubspec.yaml says '
      '${version.full}.\nBuild it again, without --skip-build.',
    );
  }

  // Signed again whatever the identity: flutter's signature does not
  // cover the remote server's files, put in after it, and thinning an app
  // breaks the signature of every binary in it.
  final signing = _Signing.fromEnvironment(root) ?? _Signing(root, '-', null);
  if (signing.adHoc) {
    _step('Signing ad hoc: \$BAOCODE_MACOS_SIGN_IDENTITY is not set');
    stdout.writeln(
      '  It opens on this machine only: Gatekeeper refuses it anywhere\n'
      '  else.',
    );
  } else if (signing.notary == null) {
    _step('Not notarising: \$BAOCODE_NOTARY_KEY is not set');
    stdout.writeln(
      '  Signed but not notarised, the app is still refused by\n'
      '  Gatekeeper on other machines.',
    );
  }

  final createDmg = await _findCreateDmg();
  installers.createSync(recursive: true);
  final made = <File>[];
  for (final MapEntry(key: lipoArch, value: arch) in _architectures.entries) {
    _step('Making the $arch app');
    final app = Directory('${root.path}/$_thinRelative/$arch/BaoCode.app');
    if (app.parent.existsSync()) app.parent.deleteSync(recursive: true);
    app.parent.createSync(recursive: true);
    await _run('ditto', ['--arch', lipoArch, bundle.path, app.path], root.path);
    await _checkArchitecture(app, lipoArch);
    _step(
      'Signing the $arch app${signing.adHoc ? '' : ' as ${signing.identity}'}',
    );
    await signing.signApp(app);

    _step('Making the $arch disk image');
    final dmg = File(
      '${installers.path}/BaoCode-${version.marketing}-$arch$edition.dmg',
    );
    // A window with the app, an arrow and an Applications shortcut to drag
    // it onto, on the background tool/dmg_background.swift draws (the
    // icons where it expects them). create-dmg lays the window out with
    // Finder, which asks this terminal for permission to the first time.
    if (dmg.existsSync()) dmg.deleteSync();
    await _run(createDmg, [
      '--volname',
      'BaoCode ${version.marketing}',
      '--background',
      '${root.path}/$_dmgBackgroundRelative',
      '--window-size',
      '660',
      '400',
      '--icon-size',
      '128',
      '--icon',
      'BaoCode.app',
      '165',
      '145',
      '--hide-extension',
      'BaoCode.app',
      '--app-drop-link',
      '495',
      '145',
      // LZMA: a quarter smaller than the default UDZO's zlib; opens on
      // macOS 10.15 and later (the app needs 12).
      '--format',
      'ULMO',
      '--no-internet-enable',
      dmg.path,
      // The folder the app alone is in: all of it goes in the image.
      app.parent.path,
    ], root.path);
    if (!signing.adHoc) {
      await signing.sign(dmg.path);
      if (signing.notary != null) {
        // Notarising the image notarises the app in it too: the ticket
        // stapled to each is the one for its own signature.
        _step('Notarising the $arch disk image (a few minutes)');
        await signing.notarise(dmg);
        await signing.staple(dmg.path);
        await signing.staple(app.path);
      }
    }

    _step('Making the $arch update archive');
    // What the app downloads to update itself: the .app (stapled when it
    // was notarised), zipped as Finder would (ditto keeps its symlinks,
    // permissions and extended attributes, which a framework's signature
    // depends on).
    final zip = File(
      '${installers.path}/BaoCode-${version.marketing}-mac-$arch$edition.zip',
    );
    if (zip.existsSync()) zip.deleteSync();
    await _run('ditto', [
      '-c',
      '-k',
      '--sequesterRsrc',
      '--keepParent',
      app.path,
      zip.path,
    ], root.path);
    made.addAll([dmg, zip]);
  }

  // None when published already (--remote-release).
  final downloads = Directory('${installers.path}/remote/$remoteVersion');
  final builds = [
    for (final file in remote.listSync())
      if (file is File && file.path.endsWith('.gz')) file,
  ];
  if (builds.isNotEmpty) {
    _step('Putting the remote server\'s builds beside them');
    downloads.createSync(recursive: true);
  }
  final servers = [
    for (final file in builds)
      file.copySync('${downloads.path}/${file.uri.pathSegments.last}'),
  ];

  _step('Done');
  for (final file in [...made, ...servers]) {
    final mb = (file.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
    stdout.writeln('  ${file.path}  ($mb MB)');
  }
  final base = '${installers.path}/BaoCode-${version.marketing}';
  stdout.writeln();
  if (servers.isEmpty) {
    stdout
      ..writeln('The app downloads the remote server published:')
      ..writeln('  https://dl.baocode.dev/releases/remote/$remoteVersion/');
  } else {
    stdout
      ..writeln('Upload the remote server\'s builds, which the app downloads')
      ..writeln('(or publish them with a server-* tag and package with')
      ..writeln('--remote-release):')
      ..writeln(
        '  ${downloads.path}/*  ->  '
        'https://dl.baocode.dev/releases/remote/$remoteVersion/',
      );
  }
  stdout
    ..writeln()
    ..writeln('To publish it as an update, sign the zips into the manifest:')
    ..writeln('  dart run tool/release_manifest.dart \\')
    ..writeln(
      '    --macos-arm64$edition $base-mac-arm64$edition.zip '
      '--dmg-arm64$edition $base-arm64$edition.dmg \\',
    )
    ..writeln(
      '    --macos-x64$edition $base-mac-x64$edition.zip '
      '--dmg-x64$edition $base-x64$edition.dmg',
    );
}

/// Signing with a Developer ID, and notarising, as the environment says
/// (the variables at the top of this file).
class _Signing {
  _Signing(this.root, this.identity, this.notary);

  /// Null when no identity is given (the app is then signed ad hoc).
  static _Signing? fromEnvironment(Directory root) {
    final environment = Platform.environment;
    final identity = environment['BAOCODE_MACOS_SIGN_IDENTITY'] ?? '';
    if (identity.isEmpty) return null;
    final key = environment['BAOCODE_NOTARY_KEY'] ?? '';
    final keyId = environment['BAOCODE_NOTARY_KEY_ID'] ?? '';
    final issuer = environment['BAOCODE_NOTARY_ISSUER'] ?? '';
    if (key.isEmpty) return _Signing(root, identity, null);
    if (keyId.isEmpty || issuer.isEmpty) {
      _fail(
        '\$BAOCODE_NOTARY_KEY is set: \$BAOCODE_NOTARY_KEY_ID and '
        '\$BAOCODE_NOTARY_ISSUER have to be too.',
      );
    }
    if (!File(key).existsSync()) _fail('No API key at $key.');
    return _Signing(root, identity, (key: key, keyId: keyId, issuer: issuer));
  }

  final Directory root;

  /// A Developer ID's name or SHA-1; `-` for ad hoc.
  final String identity;
  bool get adHoc => identity == '-';

  final ({String key, String keyId, String issuer})? notary;

  /// Signs the .app inside out: its frameworks, the browser's host, then the
  /// Finder extension, then the app around them ([sign] says with what). The
  /// host's own signature, Xcode's ad hoc, would not be notarised.
  ///
  /// Not `codesign --deep`: it would give the Finder extension the app's
  /// entitlements, sandbox off, and the system refuses to load an extension
  /// that is not sandboxed. The extension takes its own.
  ///
  /// And the app takes macos/Runner/Release.entitlements, not none: those
  /// turn the sandbox off, which this app needs (it runs the Claude Code
  /// CLI as a child process and reads its sessions under ~/.claude, and
  /// replaces itself to update). Signed without them it would fail at
  /// runtime, not here. Not DebugProfile's either: allow-jit and
  /// network.server are for debugging.
  ///
  /// Once released signed, an update has to be signed by the same team:
  /// the app checks (lib/update/installer_io.dart).
  Future<void> signApp(Directory app) async {
    final frameworks = Directory('${app.path}/Contents/Frameworks');
    for (final entry in frameworks.listSync()) {
      if (entry.path.endsWith('.framework') || entry.path.endsWith('.dylib')) {
        await sign(entry.path);
      }
    }
    await sign('${app.path}/Contents/MacOS/$_browserHost');
    await sign('${app.path}/Contents/Resources/runtime/node/node');
    await sign(
      '${app.path}/Contents/PlugIns/FinderExtension.appex',
      entitlements: 'macos/FinderExtension/FinderExtension.entitlements',
    );
    await sign(app.path, entitlements: 'macos/Runner/Release.entitlements');
    await _run('codesign', [
      '--verify',
      '--deep',
      '--strict',
      '--verbose=2',
      app.path,
    ], root.path);
  }

  /// The hardened runtime and a secure timestamp only with a Developer ID,
  /// which notarising asks for. Not ad hoc: the hardened runtime brings
  /// library validation, which an ad hoc app fails on its own frameworks
  /// (they have no Team ID to share with it), and dyld refuses to load
  /// FlutterMacOS.framework at launch.
  Future<void> sign(String path, {String? entitlements}) => _run('codesign', [
    '--force',
    if (!adHoc) ...['--options', 'runtime', '--timestamp'],
    if (entitlements != null) ...['--entitlements', entitlements],
    '--sign',
    identity,
    path,
  ], root.path);

  /// Sends [file] to Apple's notary service and waits for its verdict;
  /// stops with Apple's log when it is not accepted.
  Future<void> notarise(File file) async {
    final notary = this.notary!;
    final credentials = [
      '--key',
      notary.key,
      '--key-id',
      notary.keyId,
      '--issuer',
      notary.issuer,
    ];
    final result = await Process.run('xcrun', [
      'notarytool',
      'submit',
      file.path,
      ...credentials,
      '--wait',
      '--output-format',
      'json',
    ]);
    final Map<String, Object?> answer;
    try {
      answer = jsonDecode('${result.stdout}') as Map<String, Object?>;
    } on FormatException {
      _fail('notarytool answered:\n${result.stdout}\n${result.stderr}');
    }
    stdout.writeln('  ${answer['status']} (submission ${answer['id']})');
    if (answer['status'] != 'Accepted') {
      final log = await Process.run('xcrun', [
        'notarytool',
        'log',
        '${answer['id']}',
        ...credentials,
      ]);
      _fail('Apple did not notarise ${file.path}:\n${log.stdout}');
    }
  }

  /// Staples the notarisation ticket to [path], trying again a few times:
  /// stapler fetches the ticket from Apple's CloudKit, which can drop the
  /// connection, or not have the ticket yet just after it is accepted.
  Future<void> staple(String path) async {
    for (var attempt = 1; ; attempt++) {
      stdout.writeln('  \$ xcrun stapler staple $path');
      final result = await Process.run('xcrun', ['stapler', 'staple', path]);
      if (result.exitCode == 0) return;
      stdout.writeln('${result.stdout}'.trim());
      stderr.writeln('${result.stderr}'.trim());
      if (attempt == 5) {
        _fail('stapler exited with code ${result.exitCode}, $attempt times.');
      }
      stdout.writeln('  Trying again in ${attempt * 15} seconds');
      await Future<void>.delayed(Duration(seconds: attempt * 15));
    }
  }
}

/// Puts [remote]'s VERSION and servers.json (tool/build_remote_server.dart)
/// in [target], and nothing else: the builds an older run put there go.
/// Answers the VERSION.
String _bundleRemote(Directory remote, Directory target) {
  if (!File('${remote.path}/servers.json').existsSync()) {
    _fail(
      'No remote server built in ${remote.path}.\n'
      'Build it first, without --skip-build '
      '(or: dart run tool/build_remote_server.dart).',
    );
  }
  if (target.existsSync()) target.deleteSync(recursive: true);
  target.createSync(recursive: true);
  for (final name in ['VERSION', 'servers.json']) {
    File('${remote.path}/$name').copySync('${target.path}/$name');
  }
  return File('${remote.path}/VERSION').readAsStringSync().trim();
}

/// Puts the runtime the app carries in Contents/Resources/runtime/: node
/// from the release [_nodeVersion] pins — both architectures' own, lipo'd
/// into one universal binary that `ditto --arch` thins with the app — the
/// thincoder source tree from the repository, and the licenses it carries.
/// Both versions are checked against this script's constants; not verified
/// on a Mac yet (§26.14 U7).
Future<void> _putRuntime(Directory root, Directory bundle) async {
  final source = Directory('${root.path}/thincoder/thincoder-cli');
  final package = File('${source.path}/package.json');
  if (!package.existsSync()) {
    _fail('No ${package.path} to build the runtime from.');
  }
  final declared = (jsonDecode(
    package.readAsStringSync(),
  ) as Map<String, Object?>)['version'];
  if (declared != _thincoderVersion) {
    _fail(
      'The thincoder source tree is $declared; this script expects\n'
      '$_thincoderVersion. Update _thincoderVersion when the tree moves.',
    );
  }

  final runtime = Directory('${bundle.path}/Contents/Resources/runtime');
  if (runtime.existsSync()) runtime.deleteSync(recursive: true);
  final target = Directory('${runtime.path}/thincoder');
  target.createSync(recursive: true);
  for (final name in _thincoderFiles) {
    final from = '${source.path}/$name';
    final to = '${target.path}/$name';
    switch (FileSystemEntity.typeSync(from)) {
      case FileSystemEntityType.directory:
        _copyTree(Directory(from), Directory(to));
      case FileSystemEntityType.file:
        File(from).copySync(to);
      default:
        _fail('No $from in the thincoder source tree.');
    }
  }
  // `@thincoder/core`, where the CLI's bare imports find it: npm's own
  // layout, node_modules/@thincoder/core.
  _copyTree(
    Directory('${root.path}/thincoder/thincoder-core'),
    Directory('${target.path}/node_modules/@thincoder/core'),
  );

  final node = File('${runtime.path}/node/node');
  node.parent.createSync(recursive: true);
  final binaries = [
    for (final arch in _nodeSha256.keys) await _nodeBinary(root, arch),
  ];
  await _run('lipo', [
    '-create',
    for (final binary in binaries) binary.path,
    '-output',
    node.path,
  ], root.path);
  await _run('chmod', ['755', node.path], root.path);
  File('${runtime.path}/THIRD-PARTY-NOTICES.txt').writeAsStringSync(_notices);

  // What was copied runs, and says the version this script expects.
  final result = await Process.run(node.path, [
    '${target.path}/bin/thincoder.cjs',
    '--version',
  ], workingDirectory: root.path);
  final reported = RegExp(r'\d+\.\d+\.\d+')
      .firstMatch('${result.stdout}\n${result.stderr}')
      ?.group(0);
  if (result.exitCode != 0 || reported != _thincoderVersion) {
    _fail(
      'The runtime runs thincoder $reported (exit ${result.exitCode}); this\n'
      'script expects $_thincoderVersion.\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
  stdout.writeln('  runtime/node/node ran thincoder $reported.');
}

/// Node's own `node` for [arch], from the release [_nodeVersion] pins:
/// downloaded into build/node-macos once, checked against [_nodeSha256].
Future<File> _nodeBinary(Directory root, String arch) async {
  final cache = Directory('${root.path}/build/node-macos');
  final tarball = File('${cache.path}/node-$_nodeVersion-darwin-$arch.tar.gz');
  String sha256Of(File file) =>
      sha256.convert(file.readAsBytesSync()).toString();
  if (!tarball.existsSync() || sha256Of(tarball) != _nodeSha256[arch]) {
    final url = Uri.parse(
      'https://nodejs.org/dist/$_nodeVersion/'
      'node-$_nodeVersion-darwin-$arch.tar.gz',
    );
    stdout.writeln('  Downloading $url');
    cache.createSync(recursive: true);
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(url)).close();
      if (response.statusCode != 200) {
        _fail('$url answered ${response.statusCode}.');
      }
      await response.pipe(tarball.openWrite());
    } finally {
      client.close();
    }
    if (sha256Of(tarball) != _nodeSha256[arch]) {
      tarball.deleteSync();
      _fail(
        'The Node.js download is not the one this script expects.\n'
        'After choosing another release, update _nodeVersion and\n'
        '_nodeSha256 in this script.',
      );
    }
  }
  final unpacked = Directory('${cache.path}/$arch');
  if (unpacked.existsSync()) unpacked.deleteSync(recursive: true);
  unpacked.createSync(recursive: true);
  await _run('tar', ['-xzf', tarball.path, '-C', unpacked.path], root.path);
  final node = File(
    '${unpacked.path}/node-$_nodeVersion-darwin-$arch/bin/node',
  );
  if (!node.existsSync()) _fail('No node in the Node.js release for $arch.');
  return node;
}

/// Copies every file of [from] into [to], making the folders they are in.
void _copyTree(Directory from, Directory to) {
  if (!from.existsSync()) _fail('No ${from.path} to put in the runtime.');
  final base = from.path;
  to.createSync(recursive: true);
  for (final entity in from.listSync(recursive: true)) {
    final path = '${to.path}/${entity.path.substring(base.length + 1)}';
    if (entity is Directory) {
      Directory(path).createSync(recursive: true);
    } else if (entity is File) {
      final file = File(path);
      file.parent.createSync(recursive: true);
      entity.copySync(path);
    }
  }
}

/// The version pubspec.yaml carries, as `1.0.0+1`: the whole of it, the part
/// the app shows (CFBundleShortVersionString), and the build number after it
/// (CFBundleVersion).
({String full, String marketing, String build}) _readVersion(File pubspec) {
  final text = pubspec.readAsStringSync();
  final match = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(text);
  if (match == null) {
    _fail('No "version:" line in ${pubspec.path}');
  }
  final full = match.group(1)!;
  final plus = full.indexOf('+');
  return (
    full: full,
    marketing: plus < 0 ? full : full.substring(0, plus),
    build: plus < 0 ? '0' : full.substring(plus + 1),
  );
}

/// The executables in [app]: its own, the browser's host, the Finder
/// extension's, each framework's, and the Node.js the runtime carries.
List<String> _executables(Directory app) => [
  '${app.path}/Contents/MacOS/BaoCode',
  '${app.path}/Contents/MacOS/$_browserHost',
  '${app.path}/Contents/PlugIns/FinderExtension.appex/Contents/MacOS/'
      'FinderExtension',
  // The runtime's node: one universal binary, thinned with the app
  // (`_putRuntime`), or it is not there at all.
  '${app.path}/Contents/Resources/runtime/node/node',
  // A framework's executable is named as the framework: X.framework/X.
  for (final framework in Directory(
    '${app.path}/Contents/Frameworks',
  ).listSync())
    if (framework.path.endsWith('.framework'))
      '${framework.path}/${framework.path.split('/').last.split('.').first}',
];

/// Stops unless every executable in [app] runs on both Apple silicon and
/// Intel: the app each architecture's is thinned from. A framework built
/// for one alone would be missing from the other's, which fails only when
/// it loads it.
Future<void> _checkUniversal(Directory app) async {
  final executables = _executables(app);
  final missing = <String>[];
  for (final executable in executables) {
    final result = await Process.run('lipo', ['-archs', executable]);
    final archs = '${result.stdout}'.trim().split(' ');
    if (result.exitCode != 0 ||
        !archs.contains('arm64') ||
        !archs.contains('x86_64')) {
      missing.add('  $executable: ${'${result.stdout}'.trim()}');
    }
  }
  if (missing.isNotEmpty) {
    _fail(
      'Not universal (arm64 and x86_64), so not for every Mac:\n'
      '${missing.join('\n')}',
    );
  }
  stdout.writeln(
    '  Universal: arm64 and x86_64, ${executables.length} '
    'executables.',
  );
}

/// Stops unless every executable in [app] is for [lipoArch] alone: what
/// `ditto --arch` should have left.
Future<void> _checkArchitecture(Directory app, String lipoArch) async {
  final wrong = <String>[];
  for (final executable in _executables(app)) {
    final result = await Process.run('lipo', ['-archs', executable]);
    if ('${result.stdout}'.trim() != lipoArch) {
      wrong.add('  $executable: ${'${result.stdout}'.trim()}');
    }
  }
  if (wrong.isNotEmpty) {
    _fail('Not $lipoArch alone:\n${wrong.join('\n')}');
  }
}

/// [key] of the app's Info.plist; null when it has none.
Future<String?> _plist(Directory app, String key) async {
  final result = await Process.run('/usr/libexec/PlistBuddy', [
    '-c',
    'Print :$key',
    '${app.path}/Contents/Info.plist',
  ]);
  return result.exitCode == 0 ? '${result.stdout}'.trim() : null;
}

/// Stops unless [directory] holds every one of [required].
void _checkBundle(Directory directory, List<String> required) {
  if (!directory.existsSync()) {
    _fail(
      'No app at ${directory.path}.\n'
      'Build it first, without --skip-build.',
    );
  }
  final missing = [
    for (final item in required)
      if (FileSystemEntity.typeSync('${directory.path}/$item') ==
          FileSystemEntityType.notFound)
        item,
  ];
  if (missing.isEmpty) {
    stdout.writeln('  ${directory.path} looks complete.');
    return;
  }
  _fail(
    'The app at ${directory.path} is incomplete; missing:\n'
    '${missing.map((item) => '  $item').join('\n')}\n'
    '\n'
    'A build that failed late leaves an app that looks whole and will not\n'
    'start. Build it again.',
  );
}

/// Runs [executable], printing the command; stops the script on a non-zero
/// exit.
Future<void> _run(
  String executable,
  List<String> arguments,
  String workingDirectory,
) async {
  stdout.writeln('  \$ $executable ${arguments.join(' ')}');
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  final output = '${result.stdout}'.trim();
  if (output.isNotEmpty) stdout.writeln(output);
  final error = '${result.stderr}'.trim();
  if (error.isNotEmpty) stderr.writeln(error);
  if (result.exitCode != 0) {
    _fail('$executable exited with code ${result.exitCode}.');
  }
}

/// create-dmg (`brew install create-dmg`), which makes the disk image;
/// stops when there is none.
Future<String> _findCreateDmg() async {
  final result = await Process.run('/usr/bin/which', ['create-dmg']);
  final path = '${result.stdout}'.trim();
  if (result.exitCode == 0 && path.isNotEmpty) return path;
  _fail(
    'create-dmg makes the disk image, and is not installed:\n'
    '  brew install create-dmg',
  );
}

void _step(String message) => stdout.writeln('\n==> $message');

Never _fail(String message) {
  stderr.writeln('\n$message');
  exit(1);
}
