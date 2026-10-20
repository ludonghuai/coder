import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/thincoder/thincoder_files.dart';
import 'package:baocode/kernel/thincoder/thincoder_protocol.dart';
import 'package:baocode/platform/event_log.dart';

/// The host's files, as a test gives them: the text a read answers, the text
/// a write had before it, and what it throws instead.
class _FakeFiles implements KernelFiles {
  _FakeFiles({this.text = 'buffer', this.before = 'before'});

  final String? text;
  final String? before;
  Object? failure;
  final List<String> reads = [];
  final List<(String, String)> writes = [];

  @override
  Future<String> readText(String path) async {
    reads.add(path);
    if (failure case final error?) throw error;
    return text!;
  }

  @override
  Future<String?> writeText(String path, String text) async {
    writes.add((path, text));
    if (failure case final error?) throw error;
    return before;
  }
}

/// The handlers over [host], answering the frames a connection takes in.
class _Harness {
  _Harness({
    required this.root,
    required this.host,
    this.folders = const [],
    this.turn,
  }) {
    connection.onRequest = (request) => files.handle(request);
  }

  final String root;
  final KernelFiles host;
  final List<String> folders;
  final String? turn;
  final List<KernelEvent> events = [];
  final List<Map<String, Object?>> frames = [];
  int _seq = 0;

  late final ThincoderConnection connection = ThincoderConnection(frames.add);
  late final ThincoderFiles files = ThincoderFiles(
    cwd: () => root,
    folders: () => folders,
    files: () => host,
    emit: events.add,
    nextSeq: () => ++_seq,
    turnId: () => turn,
  );

  Future<Map<String, Object?>> request(
    String method,
    Map<String, Object?> params, {
    int id = 1,
  }) async {
    connection.receive({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    await pumpEventQueue();
    return frames.singleWhere((frame) => frame['id'] == id);
  }
}

/// A temp folder that goes when the test does.
Directory _temp() {
  final dir = Directory.systemTemp.createTempSync('thincoder-files');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// Keeps what the adapter says it left alone in a log of its own.
Directory _log() {
  final dir = Directory.systemTemp.createTempSync('thincoder-files-events');
  addTearDown(() {
    EventLog.current = null;
    dir.deleteSync(recursive: true);
  });
  EventLog.current = EventLog(dir.path);
  return dir;
}

List<String> _saidLines(Directory dir) {
  final log = File(p.join(dir.path, 'events.log'));
  return log.existsSync() ? log.readAsLinesSync() : const [];
}

void main() {
  test('a read is the host text, unsaved changes and all', () async {
    final dir = _temp();
    final host = _FakeFiles(text: 'my buffer\n');
    final it = _Harness(root: dir.path, host: host);
    final answer = await it.request('fs/read_text_file', {
      'sessionId': '3',
      'path': p.join(dir.path, 'a.dart'),
    });
    expect(answer['result'], {'content': 'my buffer\n'});
    expect(host.reads, [p.join(dir.path, 'a.dart')]);
    expect(it.events, isEmpty);
  });

  test('a write answers {}, and is the change it made', () async {
    final dir = _temp();
    final host = _FakeFiles(before: 'one\ntwo\n');
    final it = _Harness(root: dir.path, host: host, turn: 'turn-1');
    final answer = await it.request('fs/write_text_file', {
      'sessionId': '3',
      'path': p.join(dir.path, 'a.dart'),
      'content': 'one\nthree\n',
    });
    expect(answer['result'], <String, Object?>{});
    expect(host.writes.single.$2, 'one\nthree\n');

    final edited = it.events.whereType<FileEdited>().single;
    expect(edited.change.path, p.join(dir.path, 'a.dart'));
    expect(edited.change.added, 1);
    expect(edited.change.removed, 1);
    expect(edited.change.kind, FileChangeKind.modified);
    expect(edited.turnId, 'turn-1');
    expect((edited.original! as OriginalText).text, 'one\ntwo\n');
  });

  test('a new file is added, its lines all additions', () async {
    final dir = _temp();
    final host = _FakeFiles(before: null);
    final it = _Harness(root: dir.path, host: host);
    await it.request('fs/write_text_file', {
      'path': p.join(dir.path, 'new.dart'),
      'content': 'a\nb\n',
    });
    final edited = it.events.whereType<FileEdited>().single;
    expect(edited.change.kind, FileChangeKind.added);
    expect(edited.change.added, 3);
    expect(edited.change.removed, 0);
    expect((edited.original! as OriginalText).text, isNull);
    expect(edited.turnId, isNull);
  });

  test('a write the host refuses is -32603, and said in the conversation',
      () async {
    final dir = _temp();
    final host = _FakeFiles()
      ..failure = const KernelFilesException('the file has unsaved changes');
    final it = _Harness(root: dir.path, host: host);
    final answer = await it.request('fs/write_text_file', {
      'path': p.join(dir.path, 'a.dart'),
      'content': 'agent\n',
    });
    expect((answer['error']! as Map)['code'], -32603);
    expect((answer['error']! as Map)['message'], 'the file has unsaved changes');
    expect(it.events.whereType<FileEdited>(), isEmpty);
    final notice = it.events.whereType<ItemUpserted>().single.item;
    expect(notice, isA<NoticeItem>());
    expect((notice as NoticeItem).kind, NoticeKind.error);
    expect(notice.text, 'the file has unsaved changes');
  });

  test('a read the file service refuses is -32603 with its own words',
      () async {
    final dir = _temp();
    final host = _FakeFiles()..failure = Exception('Binary files cannot be edited');
    final it = _Harness(root: dir.path, host: host);
    final answer = await it.request('fs/read_text_file', {
      'path': p.join(dir.path, 'a.bin'),
    });
    expect((answer['error']! as Map)['code'], -32603);
    expect('${(answer['error']! as Map)['message']}', contains('Binary'));
    expect(it.events, isEmpty);
  });

  test('a path outside the project is -32602, said and logged', () async {
    final dir = _temp();
    final root = Directory(p.join(dir.path, 'project'))..createSync();
    final outside = p.join(dir.path, 'outside', 'x.txt');
    final host = _FakeFiles();
    final log = _log();
    final it = _Harness(root: root.path, host: host);
    final answer = await it.request('fs/write_text_file', {
      'path': outside,
      'content': 'nope',
    });
    expect((answer['error']! as Map)['code'], -32602);
    expect(host.writes, isEmpty);
    expect(File(outside).existsSync(), isFalse);
    final notice = it.events.whereType<ItemUpserted>().single.item;
    expect((notice as NoticeItem).kind, NoticeKind.error);
    expect(notice.text, contains('outside the project'));
    expect(
      _saidLines(log).where((line) => line.contains('fs: refused a path')),
      hasLength(1),
    );
  });

  test('a path that escapes the project with .. is refused too', () async {
    final dir = _temp();
    final root = Directory(p.join(dir.path, 'project'))..createSync();
    final host = _FakeFiles();
    final it = _Harness(root: root.path, host: host);
    final answer = await it.request('fs/read_text_file', {
      'path': p.join(root.path, '..', 'a.txt'),
    });
    expect((answer['error']! as Map)['code'], -32602);
    expect(host.reads, isEmpty);
  });

  test('a workspace folder is allowed besides the folder', () async {
    final dir = _temp();
    final root = Directory(p.join(dir.path, 'project'))..createSync();
    final other = Directory(p.join(dir.path, 'other'))..createSync();
    final host = _FakeFiles(text: 'there\n');
    final it = _Harness(
      root: root.path,
      host: host,
      folders: [other.path],
    );
    final answer = await it.request('fs/read_text_file', {
      'path': p.join(other.path, 'b.dart'),
    });
    expect(answer['result'], {'content': 'there\n'});
  });

  test('content that is not a string is -32602', () async {
    final dir = _temp();
    final host = _FakeFiles();
    final it = _Harness(root: dir.path, host: host);
    final answer = await it.request('fs/write_text_file', {
      'path': p.join(dir.path, 'a.dart'),
      'content': 7,
    });
    expect((answer['error']! as Map)['code'], -32602);
    expect(host.writes, isEmpty);
  });

  test('a method of another face is left to the kernel: -32601', () async {
    final dir = _temp();
    final it = _Harness(root: dir.path, host: _FakeFiles());
    final answer = await it.request('fs/something_else', const {});
    expect((answer['error']! as Map)['code'], -32601);
    expect(it.events, isEmpty);
  });
}
