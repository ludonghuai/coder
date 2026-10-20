import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_kernel_files.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/kernel/agent_kernel.dart';

/// A temp folder that goes when the test does.
Directory _temp() {
  final dir = Directory.systemTemp.createTempSync('ide-kernel-files');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// An open workspace over [dir], its files the machine's own.
IdeWorkspace _space(Directory dir) {
  final space = IdeWorkspace(dir.path, files: IdeFileService(dir.path));
  addTearDown(space.dispose);
  return space;
}

/// Opens [name] in [space], with [buffer] unsaved when given.
Future<({String path, IdeDocument doc})> _open(
  IdeWorkspace space,
  String name, {
  String disk = 'on disk\n',
  String? buffer,
}) async {
  final path = p.join(space.root, name);
  File(path).writeAsStringSync(disk);
  await space.open(path);
  final doc = space.documentOf(path)!;
  if (buffer != null) doc.text = buffer;
  return (path: path, doc: doc);
}

void main() {
  test(
    'a read of an open file is the editor text, unsaved changes and all',
    () async {
      final dir = _temp();
      final space = _space(dir);
      final (:path, :doc) = await _open(space, 'a.dart', buffer: 'my buffer\n');
      final files = IdeKernelFiles(spaces: () => [space]);
      expect(await files.readText(path), 'my buffer\n');
      expect(doc.dirty, isTrue);
    },
  );

  test('a read of a file not open is the file', () async {
    final dir = _temp();
    final space = _space(dir);
    final path = p.join(dir.path, 'a.dart');
    File(path).writeAsStringSync('on disk\n');
    final files = IdeKernelFiles(spaces: () => [space]);
    expect(await files.readText(path), 'on disk\n');
  });

  test('a write over unsaved changes is refused, and shown to read', () async {
    final dir = _temp();
    final space = _space(dir);
    final (:path, :doc) = await _open(space, 'a.dart', buffer: 'my buffer\n');
    final files = IdeKernelFiles(spaces: () => [space]);

    await expectLater(
      files.writeText(path, 'the agent\n'),
      throwsA(
        isA<KernelFilesException>().having(
          (error) => error.message,
          'message',
          contains('unsaved changes'),
        ),
      ),
    );
    await pumpEventQueue();

    // The user's buffer and the disk are as they were.
    expect(doc.text, 'my buffer\n');
    expect(doc.savedText, 'on disk\n');
    expect(File(path).readAsStringSync(), 'on disk\n');

    // And the agent's text is beside it, read-only, titled as not applied.
    final diff = space.documents.singleWhere((d) => d.diff != null);
    expect(diff.readOnly, isTrue);
    expect(diff.label, "Agent's change (not applied)");
    expect(diff.text, 'the agent\n');
    expect(diff.diff!.text.value, 'my buffer\n');
  });

  test(
    'a dirty buffer in any window holding the file refuses, and reads',
    () async {
      final dir = _temp();
      final one = _space(dir);
      final two = _space(dir);
      final (:path, :doc) = await _open(one, 'a.dart');
      await two.open(path);
      final second = two.documentOf(path)!..text = 'second window buffer\n';
      final files = IdeKernelFiles(spaces: () => [one, two]);

      // A read is the first open tab's text: two windows may show different
      // buffers, and one of them is what the edit is based on.
      expect(await files.readText(path), 'on disk\n');

      await expectLater(
        files.writeText(path, 'the agent\n'),
        throwsA(isA<KernelFilesException>()),
      );
      await pumpEventQueue();

      expect(File(path).readAsStringSync(), 'on disk\n');
      expect(doc.text, 'on disk\n');
      expect(second.text, 'second window buffer\n');
      expect(two.documents.any((d) => d.diff != null), isTrue);
      expect(one.documents.any((d) => d.diff != null), isFalse);
    },
  );

  test(
    'a write over a clean open file lands, and the editor follows',
    () async {
      final dir = _temp();
      final space = _space(dir);
      final (:path, :doc) = await _open(space, 'a.dart');
      final files = IdeKernelFiles(spaces: () => [space]);

      expect(await files.writeText(path, 'new text\n'), 'on disk\n');
      expect(File(path).readAsStringSync(), 'new text\n');
      expect(doc.text, 'new text\n');
      expect(doc.savedText, 'new text\n');
      expect(doc.dirty, isFalse);
    },
  );

  test('a write to a file not open lands, nothing to reload', () async {
    final dir = _temp();
    final space = _space(dir);
    final path = p.join(dir.path, 'a.dart');
    File(path).writeAsStringSync('on disk\n');
    final files = IdeKernelFiles(spaces: () => [space]);

    expect(await files.writeText(path, 'new text\n'), 'on disk\n');
    expect(File(path).readAsStringSync(), 'new text\n');
    expect(space.documents, isEmpty);
  });

  test('a write to a file not there yet makes it', () async {
    final dir = _temp();
    final space = _space(dir);
    final path = p.join(dir.path, 'new.dart');
    final files = IdeKernelFiles(spaces: () => [space]);

    expect(await files.writeText(path, 'made\n'), isNull);
    expect(File(path).readAsStringSync(), 'made\n');
  });

  test(
    'a path of no open workspace is a local file, read and written',
    () async {
      final dir = _temp();
      final path = p.join(dir.path, 'a.dart');
      File(path).writeAsStringSync('on disk\n');
      final files = IdeKernelFiles(spaces: () => const <IdeWorkspace>[]);

      expect(await files.readText(path), 'on disk\n');
      expect(await files.writeText(path, 'new text\n'), 'on disk\n');
      expect(File(path).readAsStringSync(), 'new text\n');
    },
  );

  test('a remote path with no open workspace is refused', () async {
    final files = IdeKernelFiles(spaces: () => const <IdeWorkspace>[]);
    await expectLater(
      files.readText('ssh://host/home/me/a.dart'),
      throwsA(
        isA<KernelFilesException>().having(
          (error) => error.message,
          'message',
          'remote project has no open workspace',
        ),
      ),
    );
  });

  test('a multi-folder workspace takes a file in any of its folders', () async {
    final dir = _temp();
    final one = Directory(p.join(dir.path, 'one'))..createSync();
    final two = Directory(p.join(dir.path, 'two'))..createSync();
    final space = IdeWorkspace(
      one.path,
      files: IdeFileService(one.path),
      roots: [one.path, two.path],
      gitOf: (_) => null,
    );
    addTearDown(space.dispose);
    final path = p.join(two.path, 'a.dart');
    File(path).writeAsStringSync('on disk\n');
    final files = IdeKernelFiles(spaces: () => [space]);
    expect(await files.readText(path), 'on disk\n');
  });

  test('a link-opened folder holds the resolved path and its buffer', () async {
    final dir = _temp();
    final real = Directory(p.join(dir.path, 'real'))..createSync();
    final link = Link(p.join(dir.path, 'link'));
    try {
      link.createSync(real.path);
    } on FileSystemException {
      // A machine that may not make links (Windows without the privilege):
      // there is nothing to test here.
      return;
    }
    final space = _space(Directory(link.path));
    final (:path, :doc) = await _open(space, 'a.dart', buffer: 'my buffer\n');
    // The kernel resolves links before it asks, so the path it passes is the
    // real one while the window spells it through the link.
    final resolved = p.join(real.path, 'a.dart');
    final files = IdeKernelFiles(spaces: () => [space]);

    expect(await files.readText(resolved), 'my buffer\n');
    await expectLater(
      files.writeText(resolved, 'the agent\n'),
      throwsA(isA<KernelFilesException>()),
    );
    await pumpEventQueue();

    expect(doc.text, 'my buffer\n');
    expect(File(resolved).readAsStringSync(), 'on disk\n');
    expect(path, p.join(link.path, 'a.dart'));
  });
}
