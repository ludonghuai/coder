import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../kernel/agent_kernel.dart';
import '../l10n/l10n.dart';
import '../platform/event_log.dart';
import '../remote/remote_location.dart';
import 'file_service.dart';
import 'ide_workspace.dart';

/// The host's files for an agent (F18): what the editor holds where a file
/// is open — unsaved changes and all — and otherwise the project's file
/// service, read before written so that a change on disk is a conflict and
/// not a lost update (D76 / D77).
class IdeKernelFiles implements KernelFiles {
  IdeKernelFiles({
    AppLocalizations Function()? l10n,
    Iterable<IdeWorkspace> Function()? spaces,
    IdeFileService Function(String root)? local,
  }) {
    _l10n = l10n;
    _spaces = spaces;
    _local = local;
  }

  late final AppLocalizations Function()? _l10n;
  late final Iterable<IdeWorkspace> Function()? _spaces;
  late final IdeFileService Function(String root)? _local;

  AppLocalizations get _strings => _l10n?.call() ?? englishLocalizations;

  Iterable<IdeWorkspace> get _open =>
      _spaces?.call() ?? IdeWorkspace.openWorkspaces;

  @override
  Future<String> readText(String path) async {
    final spaces = _spacesOf(path);
    try {
      for (final (space, held) in spaces) {
        final doc = space.documentOf(held);
        if (doc != null) return doc.text;
      }
      if (spaces.isNotEmpty) {
        final (space, held) = spaces.first;
        return await space.files.read(held);
      }
      return await _filesOf(path).read(path);
    } on KernelFilesException {
      rethrow;
    } on Object catch (error) {
      throw KernelFilesException(localizedFileError(_strings, error));
    }
  }

  @override
  Future<String?> writeText(String path, String text) async {
    final spaces = _spacesOf(path);
    if (spaces.isEmpty) {
      try {
        final local = _filesOf(path);
        final before = await _readOrNull(local, path);
        await _writeThrough(local, path, text, before);
        return before;
      } on KernelFilesException {
        rethrow;
      } on Object catch (error) {
        throw KernelFilesException(localizedFileError(_strings, error));
      }
    }
    // Any of them holding unsaved changes refuses the write: the user's own
    // text is left as it is, wherever it is shown.
    for (final (space, held) in spaces) {
      final doc = space.documentOf(held);
      if (doc == null || !doc.dirty) continue;
      unawaited(
        space.openDiff(
          doc.path,
          label: _strings.agentChangeNotApplied,
          original: () async => doc.text,
          modified: () async => text,
        ),
      );
      appEvent(
        'thincoder',
        'fs: a write was refused: unsaved changes in the editor: $path',
      );
      throw KernelFilesException(_strings.agentWriteRefusedUnsaved);
    }
    try {
      final (space, held) = spaces.first;
      final open = space.documentOf(held);
      if (open != null) {
        final before = open.savedText;
        await space.files.write(held, text, expectedText: before);
        await _reload(path);
        return before;
      }
      final before = await _readOrNull(space.files, held);
      await _writeThrough(space.files, held, text, before);
      await _reload(path);
      return before;
    } on KernelFilesException {
      rethrow;
    } on Object catch (error) {
      throw KernelFilesException(localizedFileError(_strings, error));
    }
  }

  /// The open workspaces holding [path], each with the path as that workspace
  /// spells it: the kernel resolves links before it asks here, so a folder
  /// opened through a link (macOS `/var`, say) is handed back its own
  /// spelling — otherwise its unsaved buffer would not be found and the
  /// write would bypass the protection (D77).
  List<(IdeWorkspace, String)> _spacesOf(String path) {
    final target = _canonical(path);
    final found = <(IdeWorkspace, String)>[];
    for (final space in _open) {
      for (final root in space.isMultiRoot ? space.roots : [space.root]) {
        final base = _canonical(root);
        if (!(space.paths.equals(base, target) ||
            space.paths.isWithin(base, target))) {
          continue;
        }
        final remote =
            RemoteLocation.isRemote(root) || RemoteLocation.isRemote(target);
        found.add((
          space,
          remote ? target : p.join(root, p.relative(target, from: base)),
        ));
        break;
      }
    }
    return found;
  }

  /// [path] with the links it goes through resolved; one that does not exist
  /// yet by its nearest existing ancestor — the same spelling the kernel's
  /// `_allowed` works in. Remote paths have no links here.
  String _canonical(String path) {
    if (RemoteLocation.isRemote(path)) return path;
    var existing = path;
    final rest = <String>[];
    while (true) {
      try {
        final resolved = File(existing).resolveSymbolicLinksSync();
        return rest.isEmpty
            ? resolved
            : p.joinAll([resolved, ...rest.reversed]);
      } on FileSystemException {
        final parent = p.dirname(existing);
        if (parent == existing) return path;
        rest.add(p.basename(existing));
        existing = parent;
      }
    }
  }

  /// A file service for [path] with no workspace open: its folder's, local
  /// only — a remote project's has no host here (D74 / §21.8-4).
  IdeFileService _filesOf(String path) {
    if (RemoteLocation.isRemote(path)) {
      throw const KernelFilesException('remote project has no open workspace');
    }
    final root = p.dirname(path);
    return _local?.call(root) ?? IdeFileService(root);
  }

  /// [path]'s text as [files] have it; null when there is no file yet.
  Future<String?> _readOrNull(IdeFileService files, String path) async {
    try {
      return await files.read(path);
    } on IdeFileNotFoundException {
      return null;
    }
  }

  /// Writes [text] to [path] over [before] (none: a new file).
  Future<void> _writeThrough(
    IdeFileService files,
    String path,
    String text,
    String? before,
  ) async {
    if (before != null) {
      await files.write(path, text, expectedText: before);
      return;
    }
    await files.create(path);
    await files.read(path);
    await files.write(path, text, expectedText: '');
  }

  /// Reads the open tabs of [path] again, in every workspace that holds it.
  Future<void> _reload(String path) async {
    for (final (space, held) in _spacesOf(path)) {
      await space.reload([held]);
    }
  }
}
