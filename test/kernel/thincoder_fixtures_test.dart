import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/thincoder/thincoder_kernel.dart';
import 'package:baocode/kernel/thincoder/thincoder_mock.dart';
import 'package:baocode/kernel/thincoder/thincoder_session_ref.dart';
import 'package:baocode/kernel/thincoder/thincoder_transport.dart';
import 'package:baocode/kernel/transcript.dart';

/// The kernel's descriptor, as the registry gives it (not made here).
final _descriptor = KernelDescriptor(
  id: 'thincoder',
  label: 'thincoder',
  icon: Icons.smart_toy_outlined,
  description: 'The agent of the user’s terminal',
  create: (_) => throw UnimplementedError('not made here'),
);

void main() {
  final fixtures =
      [
            for (final entity
                in Directory('test/fixtures/thincoder').listSync())
              if (entity is File && entity.path.endsWith('.ndjson')) entity,
          ]
          ..sort((a, b) => a.path.compareTo(b.path));

  test('there are recordings to replay', () {
    expect(fixtures, isNotEmpty);
  });

  for (final file in fixtures) {
    test('${p.basenameWithoutExtension(file.path)}: the frames replay', () {
      return replay(file.path);
    });
  }
}

/// Replays one recording: its frames into the kernel, its `client` lines
/// held against what the kernel writes, its `expect` checked at the end.
Future<void> replay(String path) async {
  final lines = [
    for (final line in File(path).readAsLinesSync())
      if (line.trim().isNotEmpty)
        (jsonDecode(line) as Map).cast<String, Object?>(),
  ];
  final header = lines.first;
  final cwd = '${header['cwd'] ?? '/project'}';
  final resume = switch (header['resume']) {
    final String slot => SessionRecord(
      id: ThincoderSessionRef.combine(cwd, slot),
      title: 'From the terminal',
      updatedAt: DateTime.utc(2026, 10, 15),
      cwd: cwd,
    ),
    _ => null,
  };

  final peer = ThincoderReplay();
  final transcript = Transcript();
  final kernel = ThincoderKernel(
    _descriptor,
    KernelContext(cwd: cwd, resume: resume),
    start: (_) async => peer,
    launch: (cwd) async =>
        ThincoderLaunch(cwd: cwd, executable: '/recorded/thincoder'),
  );
  final subscription = kernel.events.listen(transcript.apply);
  addTearDown(() {
    unawaited(subscription.cancel());
    kernel.dispose();
  });

  kernel.prepare();
  var turns = 0;
  for (final line in lines.skip(1)) {
    if (line['client'] case final Map<Object?, Object?> expected) {
      final actual = await peer
          .next()
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw StateError(
              'nothing was written, where the recording has $expected',
            ),
          );
      expect(actual, expected, reason: '$path: $expected');
      continue;
    }
    if (line['server'] case final Map<Object?, Object?> frame) {
      peer.push(frame.cast<String, Object?>());
      await pumpEventQueue();
      continue;
    }
    if (line['turn'] case final String text) {
      turns++;
      kernel.send(KernelTurn(id: 'turn-$turns', text: text));
      await pumpEventQueue();
      continue;
    }
    if (line['answer'] case final String optionId) {
      final pending = transcript.pendingInteraction;
      if (pending == null) fail('$path: nothing is waiting on the user');
      kernel.answer(pending.id, ApprovalAnswer(_decision(optionId)));
      await pumpEventQueue();
      continue;
    }
    if (line['cancel'] == true) {
      kernel.cancel();
      await pumpEventQueue();
      continue;
    }
    if (line['expect'] case final Map<Object?, Object?> expected) {
      _check(path, kernel, transcript, expected);
      continue;
    }
    fail('$path: a line this replay does not know: $line');
  }
  await pumpEventQueue(times: 60);
}

ApprovalDecision _decision(String optionId) => switch (optionId) {
  'approve_once' => ApprovalDecision.allowOnce,
  'approve_always' => ApprovalDecision.allowAlways,
  _ => ApprovalDecision.deny,
};

void _check(
  String path,
  ThincoderKernel kernel,
  Transcript transcript,
  Map<Object?, Object?> expected,
) {
  if (expected['items'] case final List<Object?> items) {
    expect(_shown(transcript), [for (final item in items) '$item'],
        reason: path);
  }
  if (expected['agents'] case final List<Object?> agents) {
    expect(_agents(transcript), [for (final agent in agents) '$agent'],
        reason: path);
  }
  if (expected['tasks'] case final List<Object?> tasks) {
    expect(_running(transcript), [for (final task in tasks) '$task'],
        reason: path);
  }
  if (expected['health'] case final String health) {
    expect(kernel.health.status.name, health, reason: path);
  }
  if (expected['sessionId'] case final String id) {
    expect(kernel.sessionId, id, reason: path);
  }
  if (expected['usage'] case final Map<Object?, Object?> usage) {
    expect(transcript.usage?.used, usage['used'], reason: path);
    expect(transcript.usage?.window, usage['size'], reason: path);
  }
  if (expected['interrupted'] case final bool interrupted) {
    expect(transcript.lastTurnInterrupted, interrupted, reason: path);
  }
  if (expected['loading'] case final bool loading) {
    expect(kernel.loadingHistory, loading, reason: path);
  }
}

/// What the conversation shows, one line an item; thoughts, which only a
/// live session streams, left out.
List<String> _shown(Transcript transcript) => [
  for (var i = 0; i < transcript.length; i++)
    ?_line(transcript.itemAt(i)),
];

/// Each subagent card and its own conversation (F12), one a line.
List<String> _agents(Transcript transcript) => [
  for (var i = 0; i < transcript.length; i++)
    if (transcript.itemAt(i) case final AgentItem card)
      ...['${card.description} (${card.id})', ..._children(card)],
];

/// A subagent's own items, one a line: its thoughts, text and tools.
List<String> _children(AgentItem card) => [
  for (final child in card.children) ?_line(child, thoughts: true),
];

/// An item as a line, or null for what the conversation leaves out.
String? _line(ChatItem item, {bool thoughts = false}) => switch (item) {
  UserMessageItem(:final text) => 'user: ${text.split('\n').first}',
  AssistantTextItem(:final text) => 'text: ${text.split('\n').first}',
  ThinkingItem(:final text) when thoughts =>
    'thought: ${text.split('\n').first}',
  ThinkingItem() => null,
  ToolCallItem(:final kind, :final label, :final target, :final status) =>
    'tool ${status.name}: ${label ?? kind.name} $target',
  TerminalItem(:final command, :final status) =>
    'terminal ${status.name}: $command',
  NoticeItem(:final kind, :final text) => 'notice ${kind.name}: $text',
  AgentItem(:final description, :final status, :final activity) =>
    'agent ${status.name}: $description${activity == null ? '' : ' · $activity'}',
  _ => null,
};

/// The tasks the strip shows: what runs beside the conversation (F11).
List<String> _running(Transcript transcript) => [
  for (final task in transcript.tasks)
    if (task.background && task.status == CommandStatus.running) task.id,
];
