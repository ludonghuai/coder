import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../chat/chat_models.dart';
import '../../platform/event_log.dart';
import '../agent_kernel.dart';
import '../kernel_event.dart';
import 'thincoder_protocol.dart';

/// The agent's own reads and writes (`fs/read_text_file`,
/// `fs/write_text_file`), through the host's files (F18): what the editor
/// holds where a file is open — unsaved changes and all — and otherwise the
/// file service of the project.
///
/// This is the single authority on which paths are the project's (D74): the
/// session's folder and its workspace folders, compared after links are
/// resolved. A write lands on disk and is reported as the change it made,
/// so the review surface keeps working (D79); one the host refuses — the
/// editor has unsaved changes — is said in the conversation (D80).
class ThincoderFiles {
  ThincoderFiles({
    required this.cwd,
    required this.folders,
    required this.files,
    required this.emit,
    required this.nextSeq,
    required this.turnId,
  });

  /// What the kernel's `initialize` declares (F18): only this connection —
  /// the catalog's short-lived one declares nothing (D73).
  static const capabilities = <String, Object?>{
    'fs': {'readTextFile': true, 'writeTextFile': true},
  };

  /// The session's folder, as the agent runs in it.
  final String Function() cwd;

  /// The workspace folders besides [cwd] the session may work in.
  final List<String> Function() folders;

  /// The host's files; null when the host gives none.
  final KernelFiles? Function() files;

  /// Where what this makes goes.
  final void Function(KernelEvent event) emit;
  final int Function() nextSeq;

  /// The turn under way, if any: a change it wrote is that turn's.
  final String? Function() turnId;

  /// Handles [request] where it is one of the files'; false leaves it to
  /// the kernel (which refuses an unknown method, E4).
  bool handle(ThincoderRequest request) {
    switch (request.method) {
      case 'fs/read_text_file':
        unawaited(_read(request));
        return true;
      case 'fs/write_text_file':
        unawaited(_write(request));
        return true;
      default:
        return false;
    }
  }

  Future<void> _read(ThincoderRequest request) async {
    final path = _allowed(request.params['path'], request);
    if (path == null) return;
    final host = files();
    if (host == null) {
      request.refuse(-32603, 'the host gives no files to read');
      return;
    }
    try {
      request.answer({'content': await host.readText(path)});
    } on KernelFilesException catch (error) {
      request.refuse(error.code, error.message);
    } on Object catch (error) {
      request.refuse(-32603, '$error');
    }
  }

  Future<void> _write(ThincoderRequest request) async {
    final content = request.params['content'];
    if (content is! String) {
      request.refuse(-32602, 'content must be a string');
      return;
    }
    final path = _allowed(request.params['path'], request);
    if (path == null) return;
    final host = files();
    if (host == null) {
      request.refuse(-32603, 'the host gives no files to write');
      return;
    }
    String? before;
    try {
      before = await host.writeText(path, content);
    } on KernelFilesException catch (error) {
      _refused(error.message);
      request.refuse(error.code, error.message);
      return;
    } on Object catch (error) {
      _refused('$error');
      request.refuse(-32603, '$error');
      return;
    }
    // The write landed: report it, and only it — a failure of the reporting
    // is not a failed write.
    final counts = _counts(before, content);
    emit(
      FileEdited(
        nextSeq(),
        FileChange(
          path: path,
          added: counts.added,
          removed: counts.removed,
          kind: before == null ? FileChangeKind.added : FileChangeKind.modified,
        ),
        turnId: turnId(),
        original: OriginalText(before),
      ),
    );
    request.answer(const <String, Object?>{});
  }

  /// [raw] as an allowed path, resolved; null — refused as -32602, and said
  /// in the conversation — when it is not one.
  String? _allowed(Object? raw, ThincoderRequest request) {
    if (raw is! String || raw.trim().isEmpty) {
      request.refuse(-32602, 'a path is required');
      return null;
    }
    final path = _canonical(_absolute(raw));
    for (final root in [cwd(), ...folders()]) {
      final resolved = _canonical(_absolute(root));
      if (p.context.equals(resolved, path) ||
          p.context.isWithin(resolved, path)) {
        return path;
      }
    }
    appEvent('thincoder', 'fs: refused a path outside the project: $raw');
    final message = 'refused a path outside the project: $raw';
    _refused(message);
    request.refuse(-32602, message);
    return null;
  }

  /// [raw] against the session's folder when it is relative.
  String _absolute(String raw) =>
      p.isAbsolute(raw) ? p.normalize(raw) : p.normalize(p.join(cwd(), raw));

  /// [path] with the links it goes through resolved, so that a link out of
  /// the project is out of it; one that does not exist is resolved by its
  /// nearest existing ancestor.
  static String _canonical(String path) {
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

  /// What a refused write is told of in the conversation (D80).
  void _refused(String message) {
    final seq = nextSeq();
    emit(ItemUpserted(seq, 'fs:$seq', NoticeItem(NoticeKind.error, message)));
  }

  /// [before] to [after], line by line: how many lines were added and
  /// removed (the longest common subsequence, as the Claude face counts).
  static ({int added, int removed}) _counts(String? before, String after) {
    List<String> split(String text) =>
        text.isEmpty ? const [] : text.split('\n');
    final a = split(before ?? '');
    final b = split(after);
    if (a.length * b.length > 250000) {
      // Too large for the table: all of one replaced by the other.
      return (added: b.length, removed: a.length);
    }
    final common = List.generate(
      a.length + 1,
      (_) => List.filled(b.length + 1, 0),
    );
    for (var i = a.length - 1; i >= 0; i--) {
      for (var j = b.length - 1; j >= 0; j--) {
        common[i][j] = a[i] == b[j]
            ? common[i + 1][j + 1] + 1
            : (common[i + 1][j] > common[i][j + 1]
                  ? common[i + 1][j]
                  : common[i][j + 1]);
      }
    }
    final kept = common[0][0];
    return (added: b.length - kept, removed: a.length - kept);
  }
}
