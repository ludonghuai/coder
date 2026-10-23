import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:baocode/browser/browser_steps.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/editor_context_setting.dart';
import 'package:baocode/chat/open_editor.dart';
import 'package:baocode/host_tools/host_mcp_server.dart';
import 'package:baocode/host_tools/host_tools.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_kernel_files.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_registry.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/kernel/thincoder/thincoder_catalog.dart';
import 'package:baocode/kernel/thincoder/thincoder_config_store.dart';
import 'package:baocode/kernel/thincoder/thincoder_files.dart';
import 'package:baocode/kernel/thincoder/thincoder_options.dart';
import 'package:baocode/kernel/thincoder/thincoder_kernel.dart';
import 'package:baocode/kernel/thincoder/thincoder_locator.dart';
import 'package:baocode/kernel/thincoder/thincoder_mock.dart';
import 'package:baocode/kernel/thincoder/thincoder_protocol.dart';
import 'package:baocode/kernel/thincoder/thincoder_session_ref.dart';
import 'package:baocode/kernel/thincoder/thincoder_transport.dart';
import 'package:baocode/kernel/thincoder/thincoder_warm.dart';
import 'package:baocode/kernel/transcript.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/platform/data_dir.dart';
import 'package:baocode/platform/event_log.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:bao_remote/local.dart' show ClaudeEnvironment;

/// The kernel's descriptor, as the registry gives it (not made here).
final _descriptor = KernelDescriptor(
  id: 'thincoder',
  label: 'thincoder',
  icon: Icons.smart_toy_outlined,
  description: 'The agent of the user’s terminal',
  create: (_) => throw UnimplementedError('not made here'),
);

/// A kernel over scripted agents, its events applied to a transcript. Each
/// start makes an agent of its own, so that a restart is seen as one.
class _Session {
  _Session({
    KernelContext context = const KernelContext(cwd: '/project'),
    ThincoderMock Function()? make,
    ThincoderLauncher? launch,
  }) : _make = make ?? (() => ThincoderMock(serialInbound: true)) {
    kernel = ThincoderKernel(
      _descriptor,
      context,
      start: (_) async {
        final agent = _make();
        agents.add(agent);
        return agent;
      },
      launch:
          launch ??
          (cwd) async =>
              ThincoderLaunch(cwd: cwd, executable: '/mock/thincoder'),
    );
    _subscription = kernel.events.listen((event) {
      events.add(event);
      transcript.apply(event);
    });
  }

  final ThincoderMock Function() _make;
  late final ThincoderKernel kernel;
  late final StreamSubscription<KernelEvent> _subscription;
  final List<ThincoderMock> agents = [];
  final List<KernelEvent> events = [];
  final Transcript transcript = Transcript();

  /// The agent in use now.
  ThincoderMock get agent => agents.last;

  void send(
    String text, {
    String id = 'turn-1',
    List<ImageAttachment> images = const [],
    List<String> notes = const [],
    List<EditorContext> contexts = const [],
  }) => kernel.send(
    KernelTurn(
      id: id,
      text: text,
      images: images,
      notes: notes,
      contexts: contexts,
    ),
  );

  void dispose() {
    unawaited(_subscription.cancel());
    kernel.dispose();
  }

  /// What the conversation shows, one line an item; thoughts, which only a
  /// live session streams, left out.
  List<String> get shown => [
    for (var i = 0; i < transcript.length; i++)
      switch (transcript.itemAt(i)) {
        UserMessageItem(:final text) => 'user: ${text.split('\n').first}',
        AssistantTextItem(:final text) => 'text: ${text.split('\n').first}',
        ThinkingItem() => '',
        ToolCallItem(:final kind, :final label, :final target, :final status) =>
          'tool ${status.name}: ${label ?? kind.name} $target',
        TerminalItem(:final command, :final status) =>
          'terminal ${status.name}: $command',
        NoticeItem(:final kind, :final text) => 'notice ${kind.name}: $text',
        _ => '',
      },
  ].where((line) => line.isNotEmpty).toList();

  /// The items of one kind.
  List<T> items<T extends ChatItem>() => [
    for (var i = 0; i < transcript.length; i++)
      if (transcript.itemAt(i) case final T item) item,
  ];

  /// Its subagent cards, and the rows the strip would show (F11).
  List<AgentItem> get cards => items<AgentItem>();

  List<KernelTask> get running => [
    for (final task in transcript.tasks)
      if (task.background && task.status == CommandStatus.running) task,
  ];
}

/// Waits for what the kernel does next.
Future<void> settle() => pumpEventQueue(times: 60);

/// A subagent's signal, as thincoder sends it (F11, §15.2): the
/// `session_info_update` variant carrying the `thincoder.dev/subagent` meta.
Map<String, Object?> _signal(
  String role,
  int id,
  String state, [
  Object? progress,
  String? detail,
]) => {
  'jsonrpc': '2.0',
  'method': 'session/update',
  'params': {
    'sessionId': '1',
    'update': {
      'sessionUpdate': 'session_info_update',
      '_meta': {
        'thincoder.dev/subagent': {
          'role': role,
          'id': id,
          'state': state,
          'progress': ?progress,
          'detail': ?detail,
        },
      },
    },
  },
};

/// A `session/update` of any other shape, as the agent writes it.
Map<String, Object?> _update(Map<String, Object?> update) => {
  'jsonrpc': '2.0',
  'method': 'session/update',
  'params': {'sessionId': '1', 'update': update},
};

/// A turn's start or end, or the window's, as thincoder writes it (§19.2):
/// the `session_info_update` variant carrying the `thincoder.dev/turn` meta.
Map<String, Object?> _turn(String phase, {Object? ok, bool? on}) => _update({
  'sessionUpdate': 'session_info_update',
  '_meta': {
    'thincoder.dev/turn': {'phase': phase, if (phase != 'watch') 'kind': 'digest', 'ok': ?ok, 'on': ?on},
  },
});

/// The subagent extension's mark, as thincoder writes it (§16.1).
Map<String, Object?> _marked(Object? mark) => {
  'thincoder.dev/subagent': mark,
};

Map<String, Object?> _agent(String role, int id) =>
    _marked({'role': role, 'id': id});

/// A content frame with a subagent's own mark (§16.1).
Map<String, Object?> _said(
  String role,
  int id,
  String text, {
  bool thought = false,
}) => _update({
  'sessionUpdate': thought ? 'agent_thought_chunk' : 'agent_message_chunk',
  'content': {'type': 'text', 'text': text},
  '_meta': _agent(role, id),
});

/// A frame with no mark: the conversation's own, as it always was.
Map<String, Object?> _reply(String text) => {
  'sessionUpdate': 'agent_message_chunk',
  'content': {'type': 'text', 'text': text},
};

/// A tool frame: a call, or its end ([done]); [by] marks it a subagent's,
/// [meta] gives any `_meta` at all (a mark that names no one).
Map<String, Object?> _tool(
  String id, {
  String kind = 'read',
  Map<String, Object?> raw = const {},
  bool done = false,
  (String, int)? by,
  Object? meta,
}) {
  final update = done
      ? <String, Object?>{
          'sessionUpdate': 'tool_call_update',
          'toolCallId': id,
          'status': 'completed',
        }
      : <String, Object?>{
          'sessionUpdate': 'tool_call',
          'toolCallId': id,
          'title': kind,
          'kind': kind,
          'status': 'in_progress',
          'rawInput': raw,
        };
  if (by != null) meta = _agent(by.$1, by.$2);
  return _update(meta == null ? update : {...update, '_meta': meta});
}

/// A kernel prepared and waiting, as every subagent case begins.
Future<_Session> _ready() async {
  final s = _Session();
  addTearDown(s.dispose);
  s.kernel.prepare();
  await settle();
  return s;
}

List<String> _prompts(_Session s) => [
  for (final r in s.agent.requests('session/prompt'))
    (((r['params'] as Map)['prompt'] as List).single as Map)['text'] as String,
];

Future<void> _let(_Session s, {bool hold = false}) async {
  s.agent.release();
  if (hold) s.agent.hold = Completer<void>();
  await settle();
}

/// Keeps what the adapter says it left alone in a log of its own.
Directory _log() {
  final dir = Directory.systemTemp.createTempSync('thincoder-events');
  addTearDown(() {
    EventLog.current = null;
    dir.deleteSync(recursive: true);
  });
  EventLog.current = EventLog(dir.path);
  return dir;
}

/// The lines in [dir]'s log: what the adapter said it left alone.
List<String> _saidLines(Directory dir) {
  final log = File(p.join(dir.path, 'events.log'));
  return log.existsSync() ? log.readAsLinesSync() : const [];
}

/// How many of those lines say [phrase].
int _saidTimes(Directory dir, String phrase) =>
    _saidLines(dir).where((line) => line.contains(phrase)).length;

void main() {
  group('thincoder kernel', () {
    test('handshakes, and the session is up before the first message', () async {
      final s = _Session();
      addTearDown(s.dispose);

      expect(s.kernel.health.status, KernelHealthStatus.idle);
      s.kernel.prepare();
      await settle();

      expect(s.kernel.health.status, KernelHealthStatus.ready);
      expect(s.agent.requests('initialize').single['params'], {
        'protocolVersion': 1,
        'clientCapabilities': <String, Object?>{},
      });
      expect(s.agent.requests('session/new').single['params'], {
        'cwd': '/project',
      });
      // The host sees the folder and the slot together (D5).
      expect(s.kernel.sessionId, '/project|1');

      // What it offers is what the agent reported (E3).
      expect(s.kernel.mode.selected, 'normal');
      expect(s.kernel.mode.options.map((o) => o.id), ['normal', 'plan']);
      expect(s.kernel.model.selected, 'anthropic:claude-sonnet-5');
      expect(s.kernel.effort.selected, 'on');
      expect(s.kernel.effort.toggle, isTrue);
      expect(
        s.kernel.effort.optionsFor('anthropic:claude-sonnet-5'),
        hasLength(1),
      );

      // Only what it has is declared (the rest the UI leaves out).
      expect(s.kernel, isA<SelectsModel>());
      expect(s.kernel, isA<SelectsMode>());
      expect(s.kernel, isA<SelectsEffort>());
      expect(s.kernel, isA<ReportsContext>());
      expect(s.kernel, isA<LoadsHistory>());
      expect(s.kernel, isA<AcceptsImageFiles>());
      expect(s.kernel, isNot(isA<AcceptsImages>()));
      expect(s.kernel, isNot(isA<StartsPlans>()));
      expect(s.kernel, isNot(isA<RunsBackgroundTasks>()));
      expect(s.kernel, isA<QueuesMessages>());
      expect(s.kernel, isA<RewindsConversation>());
      expect(s.kernel, isA<RenamesSession>());
      expect(s.kernel, isA<PlansReverts>());
      expect(s.kernel, isA<GeneratesTitles>());
      expect(s.kernel, isA<DefersRename>());
    });

    test('a turn streams a thought, text, a tool card and the usage', () async {
      final s = _Session();
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      s.send('hi');
      await s.agent.finished.future;
      await settle();

      expect(s.agent.requests('session/prompt').single['params'], {
        'sessionId': '1',
        'turnId': 'turn-1',
        'prompt': [
          {'type': 'text', 'text': 'hi'},
        ],
      });
      expect(s.shown, [
        'user: hi',
        'text: Let me read that file.',
        'tool succeeded: read main.dart',
        'text: It does nothing yet.',
      ]);
      final tool = s.items<ToolCallItem>().single;
      expect(tool.kind, ToolKind.read);
      expect(tool.path, 'lib/main.dart');
      expect(tool.output, 'void main() {}');
      expect(s.transcript.usage?.used, 1200);
      expect(s.kernel.contextWindow, 200000);
      expect(s.transcript.lastTurnInterrupted, isFalse);
      expect(s.transcript.activeTurn, isNull);
    });

    test('a tool card is replaced as the agent updates it', () async {
      final s = _Session(
        make: () => ThincoderMock(
          turn: const [
            {
              'sessionUpdate': 'tool_call',
              'toolCallId': 't4',
              'title': 'bash',
              'kind': 'execute',
              'status': 'in_progress',
              'rawInput': {'command': 'flutter test'},
            },
            {
              'sessionUpdate': 'tool_call_update',
              'toolCallId': 't4',
              'status': 'failed',
              'content': [
                {
                  'type': 'content',
                  'content': {'type': 'text', 'text': '3 tests failed'},
                },
              ],
            },
            {
              'sessionUpdate': 'tool_call',
              'toolCallId': 't5',
              'title': 'edit',
              'kind': 'edit',
              'status': 'in_progress',
              'rawInput': {'path': 'lib/a.dart'},
            },
            {
              'sessionUpdate': 'tool_call_update',
              'toolCallId': 't5',
              'status': 'completed',
              'content': [
                {
                  'type': 'content',
                  'content': {'type': 'text', 'text': 'OK: edited lib/a.dart'},
                },
              ],
            },
          ],
        ),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      s.send('go');
      await s.agent.finished.future;
      await settle();

      final terminal = s.items<TerminalItem>().single;
      expect(terminal.command, 'flutter test');
      expect(terminal.status, CommandStatus.failed);
      expect(terminal.output, '3 tests failed');
      final edit = s.items<ToolCallItem>().single;
      expect(edit.kind, ToolKind.edit);
      expect(edit.path, 'lib/a.dart');
      expect(edit.target, 'a.dart');
      expect(edit.status, ToolStatus.succeeded);
      expect(edit.output, 'OK: edited lib/a.dart');
    });

    test('what it does not know is left alone, and refused with -32601',
        () async {
      final s = _Session();
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      s.agent
        ..push({
          'jsonrpc': '2.0',
          'method': 'session/update',
          'params': {
            'sessionId': '1',
            'update': {'sessionUpdate': 'something_new', 'x': 1},
          },
        })
        ..push({
          'jsonrpc': '2.0',
          'method': 'session/update',
          'params': {
            'sessionId': '1',
            'update': {'sessionUpdate': 'session_info_update', '_meta': {}},
          },
        })
        ..push({
          'jsonrpc': '2.0',
          'method': 'ledger/changed',
          'params': {'cwd': '/project'},
        })
        ..push({
          'jsonrpc': '2.0',
          'id': 'rpc-9',
          'method': 'terminal/create',
          'params': {'sessionId': '1'},
        });
      await settle();

      final refused = s.agent.written
          .where((message) => message['id'] == 'rpc-9')
          .single;
      expect(refused['error'], {'code': -32601, 'message': 'Method not found'});
      expect(s.shown, isEmpty);

      // The connection is still good: a turn goes through.
      s.send('hi');
      await s.agent.finished.future;
      await settle();
      expect(s.transcript.lastTurnInterrupted, isFalse);
    });

    test('an approval is put to the user, and answered in its own terms',
        () async {
      final s = _Session(make: () => ThincoderMock(askPermission: true));
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      s.send('go');
      await settle();

      final request =
          s.events.whereType<InteractionRequested>().single.request
              as ApprovalRequest;
      expect(request.toolName, 'read');
      expect((request.preview as TextPreview).text, contains('approval'));
      expect(request.alwaysAllowLabel, 'Approve for this session');

      s.kernel
        ..answer(request.id, const ApprovalAnswer(ApprovalDecision.allowOnce))
        // A second answer changes nothing.
        ..answer(request.id, const ApprovalAnswer(ApprovalDecision.deny));
      await s.agent.finished.future;
      await settle();

      final reply = s.agent.written
          .where((message) => message['id'] == 'rpc-1')
          .single;
      expect(reply['result'], {
        'outcome': {'outcome': 'selected', 'optionId': 'approve_once'},
      });
      expect(s.transcript.pendingInteraction, isNull);
      expect(s.items<ToolCallItem>().single.status, ToolStatus.succeeded);
    });

    test('always and reject go out as the agent\'s own options', () async {
      for (final (decision, optionId, failed) in [
        (ApprovalDecision.allowAlways, 'approve_always', false),
        (ApprovalDecision.deny, 'reject', true),
      ]) {
        final s = _Session(make: () => ThincoderMock(askPermission: true));
        addTearDown(s.dispose);
        s.kernel.prepare();
        await settle();
        s.send('go');
        await settle();

        final request =
            s.events.whereType<InteractionRequested>().single.request;
        s.kernel.answer(request.id, ApprovalAnswer(decision));
        await s.agent.finished.future;
        await settle();

        final reply = s.agent.written
            .where((message) => message['id'] == 'rpc-1')
            .single;
        expect(reply['result'], {
          'outcome': {'outcome': 'selected', 'optionId': optionId},
        });
        final tool = s.items<ToolCallItem>().single;
        expect(tool.status, failed ? ToolStatus.failed : ToolStatus.succeeded);
      }
    });

    test('a panel that is never answered does not hold the kernel', () async {
      final s = _Session(make: () => ThincoderMock(askPermission: true));
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      s.send('go');
      await settle();

      // The agent's own five minutes pass, in an instant: refused, and the
      // turn goes on.
      s.agent.timeOutPermission();
      await s.agent.finished.future;
      await settle();

      expect(
        s.agent.written.any(
          (message) => message['id'] == 'rpc-1' && message.containsKey('result'),
        ),
        isFalse,
        reason: 'nothing was answered',
      );
      expect(s.transcript.pendingInteraction, isNull);
      expect(s.items<ToolCallItem>().single.status, ToolStatus.failed);
      expect(s.transcript.lastTurnInterrupted, isFalse);

      s.send('again', id: 'turn-2');
      await settle();
      // The panel works again, and the turn goes through.
      final asked = s.transcript.pendingInteraction;
      if (asked == null) fail('the second approval never came');
      s.kernel.answer(asked.id, const ApprovalAnswer(ApprovalDecision.allowOnce));
      await settle();
      expect(s.events.whereType<TurnEnded>(), hasLength(2));
    });

    test('a disposition with an approval in flight answers it as cancelled',
        () async {
      final s = _Session(make: () => ThincoderMock(askPermission: true));
      s.kernel.prepare();
      await settle();
      s.send('go');
      await settle();
      expect(s.events.whereType<InteractionRequested>(), hasLength(1));

      s.kernel.dispose();
      await s.kernel.stopped;

      final reply = s.agent.written
          .where((message) => message['id'] == 'rpc-1')
          .single;
      expect(reply['result'], {
        'outcome': {'outcome': 'cancelled'},
      });
    });

    test('a session of its own is picked up again after a release',
        () async {
      final s = _Session(
        make: () => ThincoderMock(
          turn: const [],
          // The machine's shelf: the next process finds what the last one
          // left there (§3.5).
          slots: const [
            {'sessionId': '1', 'cwd': '/project'},
          ],
        ),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      s.send('hi');
      await s.agent.finished.future;
      await settle();
      expect(s.kernel.sessionId, '/project|1');

      s.kernel.release();
      await settle();
      s.kernel.prepare();
      await settle();

      // The same session, picked up rather than started over (§3.5, T4).
      expect(s.agents, hasLength(2));
      expect(s.agents.last.requests('session/resume').single['params'], {
        'sessionId': '1',
        'cwd': '/project',
      });
      expect(s.agents.last.requests('session/new'), isEmpty);
      expect(s.kernel.sessionId, '/project|1');
      // What was said is still shown: nothing is replayed.
      expect(s.shown, ['user: hi']);
    });

    test('a session gone from the terminal is made anew, not a failed start',
        () async {
      final shelf = <Map<String, Object?>>[
        {'sessionId': '1', 'cwd': '/project'},
      ];
      final s = _Session(
        make: () => ThincoderMock(turn: const [], slots: shelf),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      expect(s.kernel.sessionId, '/project|1');
      s.kernel.release();
      await settle();
      // Deleted in the terminal while the desktop was away.
      shelf.clear();

      s.kernel.prepare();
      await settle();

      expect(s.agents, hasLength(2));
      expect(s.agents.last.requests('session/resume'), hasLength(1));
      expect(s.agents.last.requests('session/new'), hasLength(1));
      expect(s.kernel.health.status, KernelHealthStatus.ready);
      expect(s.kernel.sessionId, '/project|1');
    });

    test('a record whose session is gone starts one of its own, not a failed '
        'start', () async {
      final s = _Session(
        context: KernelContext(
          cwd: '/project',
          resume: SessionRecord(
            id: '/project|3',
            title: 'From the terminal',
            updatedAt: DateTime.utc(2026, 10, 15),
            cwd: '/project',
          ),
        ),
        // The slot the record names is not on the agent's shelf: deleted in
        // the terminal since then (§14-13).
        make: () => ThincoderMock(turn: const [], slots: const []),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      expect(s.agent.requests('session/load').single['params'], {
        'sessionId': '3',
        'cwd': '/project',
      });
      expect(s.agent.requests('session/new'), hasLength(1));
      expect(s.kernel.health.status, KernelHealthStatus.ready);
      expect(s.kernel.sessionId, '/project|1');
      expect(s.kernel.loadingHistory, isFalse);

      // It goes on as a session of its own: a message is sent and ends.
      s.send('hi');
      await s.agent.finished.future;
      await settle();
      expect(s.agent.requests('session/prompt').single['params'], {
        'sessionId': '1',
        'turnId': 'turn-1',
        'prompt': [
          {'type': 'text', 'text': 'hi'},
        ],
      });
      expect(s.transcript.activeTurn, isNull);
    });

    test('a session made in place of a gone record is picked up after a '
        'release', () async {
      // The slot the record names is not on the agent's shelf: deleted in
      // the terminal since then (§14-13).
      final shelf = <Map<String, Object?>>[];
      final s = _Session(
        context: KernelContext(
          cwd: '/project',
          resume: SessionRecord(
            id: '/project|3',
            title: 'From the terminal',
            updatedAt: DateTime.utc(2026, 10, 15),
            cwd: '/project',
          ),
        ),
        make: () => ThincoderMock(turn: const [], slots: shelf),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      expect(s.agent.requests('session/load').single['params'], {
        'sessionId': '3',
        'cwd': '/project',
      });
      expect(s.agent.requests('session/new'), hasLength(1));
      expect(s.kernel.sessionId, '/project|1');

      // Said something there: a session with a message is one the next
      // process finds on the shelf.
      s.send('hi');
      await s.agent.finished.future;
      await settle();
      s.kernel.release();
      await settle();
      shelf.add({'sessionId': '1', 'cwd': '/project', 'title': 'hi'});

      s.kernel.prepare();
      await settle();

      // The record's dead slot is not loaded again, and nothing is made
      // anew: what was started in its place is picked up (§3.5).
      expect(s.agents, hasLength(2));
      expect(s.agents.last.requests('session/load'), isEmpty);
      expect(s.agents.last.requests('session/new'), isEmpty);
      expect(s.agents.last.requests('session/resume').single['params'], {
        'sessionId': '1',
        'cwd': '/project',
      });
      expect(s.kernel.sessionId, '/project|1');
      // What was said is still shown: nothing is replayed.
      expect(s.shown, ['user: hi']);
    });

    test('a record is loaded (replayed) once, and resumed after that',
        () async {
      final s = _Session(
        context: KernelContext(
          cwd: '/project',
          resume: SessionRecord(
            id: '/project|3',
            title: 'From the terminal',
            updatedAt: DateTime.utc(2026, 10, 15),
            cwd: '/project',
          ),
        ),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      expect(s.agent.requests('session/load').single['params'], {
        'sessionId': '3',
        'cwd': '/project',
      });
      expect(s.kernel.sessionId, '/project|3');
      expect(s.kernel.loadingHistory, isFalse);
      expect(s.shown, [
        'user: Hello from the terminal',
        'text: Hi — what would you like to do?',
        'tool succeeded: read main.dart',
      ]);

      // Out of view and back: the same conversation, resumed rather than
      // replayed (no duplicates).
      s.kernel.release();
      await settle();
      s.kernel.prepare();
      await settle();
      expect(s.agent.requests('session/resume').single['params'], {
        'sessionId': '3',
        'cwd': '/project',
      });
      expect(s.agents.first.requests('session/load'), hasLength(1));
      expect(s.agents.last.requests('session/load'), isEmpty);
      expect(s.shown, hasLength(3));
    });

    test('the history is said to be loading until it is all there', () async {
      final s = _Session(
        context: KernelContext(
          cwd: '/project',
          resume: SessionRecord(
            id: '/project|3',
            title: '',
            updatedAt: DateTime.utc(2026, 10, 15),
            cwd: '/project',
          ),
        ),
        make: () => ThincoderMock()..hold = Completer<void>(),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      expect(s.kernel.loadingHistory, isTrue);
      expect(s.shown, isEmpty);

      s.agent.release();
      await settle();
      expect(s.kernel.loadingHistory, isFalse);
      expect(s.shown, hasLength(3));
    });

    test('a cancel ends the running turn as cancelled', () async {
      final s = _Session(make: () => ThincoderMock()..hold = Completer<void>());
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      s.send('hi');
      await settle();
      expect(s.transcript.activeTurn, 'turn-1');

      s.kernel.cancel();
      s.agent.release();
      await s.agent.finished.future;
      await settle();

      expect(s.agent.requests('session/cancel').single['params'], {
        'sessionId': '1',
      });
      // What was streamed while it ran is closed with it.
      expect(s.events.last, isA<TurnEnded>());
      expect(s.transcript.lastTurnInterrupted, isTrue);
      expect(s.transcript.activeTurn, isNull);
    });

    test('a process that dies mid-turn: interrupted, an error, failed health',
        () async {
      final s = _Session(make: () => ThincoderMock()..hold = Completer<void>());
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      s.send('hi');
      await settle();

      s.agent.crash(code: 1, stderr: 'mock: out of memory');
      await settle();

      expect(s.transcript.lastTurnInterrupted, isTrue);
      expect(
        s.shown.where((line) => line.startsWith('notice error:')),
        ['notice error: thincoder stopped unexpectedly'],
      );
      expect(s.kernel.health.status, KernelHealthStatus.failed);
      expect(s.kernel.health.message, 'thincoder stopped');
      expect(s.kernel.health.detail, contains('mock: out of memory'));
      await s.kernel.stopped;

      // Told to try again: another process is started.
      s.kernel.restart();
      await settle();
      expect(s.agents, hasLength(2));
      expect(s.kernel.health.status, KernelHealthStatus.ready);
      expect(s.agents.last.requests('session/new'), hasLength(1));
    });

    test('a pick is shown only once the agent reports it (D20)', () async {
      final s = _Session();
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      s.kernel.mode.select('plan');
      expect(s.kernel.mode.selected, 'normal', reason: 'not optimistically');
      await settle();
      expect(s.agent.requests('session/set_mode').single['params'], {
        'sessionId': '1',
        'mode': 'plan',
      });
      expect(s.kernel.mode.selected, 'plan');

      s.kernel.model.select('anthropic:claude-opus-5');
      expect(s.kernel.model.selected, 'anthropic:claude-sonnet-5');
      await settle();
      expect(s.agent.requests('session/set_config_option').single['params'], {
        'sessionId': '1',
        'configId': 'model',
        'value': 'anthropic:claude-opus-5',
      });
      expect(s.kernel.model.selected, 'anthropic:claude-opus-5');

      // The switch flips the other way, and says so once the agent does.
      expect(s.kernel.effort.selected, 'on');
      s.kernel.effort.select(s.kernel.model.selected!, 'on');
      expect(s.kernel.effort.selected, 'on');
      await settle();
      expect(s.agent.requests('session/set_config_option').last['params'], {
        'sessionId': '1',
        'configId': 'thinking',
        'value': false,
      });
      expect(s.kernel.effort.selected, 'off');
    });

    test('the approval face follows the report, and waits for it (T51)',
        () async {
      final s = _Session(make: () => ThincoderMock(autoApprove: false));
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      expect(s.kernel, isA<SelectsPermission>());
      expect(s.kernel.permission.options.map((o) => o.id), ['ask', 'auto']);
      expect(s.kernel.permission.options.last.caution, isTrue);
      expect(s.kernel.permission.selected, 'ask');

      s.kernel.permission.select('auto');
      expect(s.kernel.permission.selected, 'ask', reason: 'not optimistically');
      await settle();
      expect(s.agent.requests('session/set_config_option').single['params'], {
        'sessionId': '1',
        'configId': 'autoApprove',
        'value': true,
      });
      expect(s.kernel.permission.selected, 'auto');
    });

    test('always turns auto on with the approval; once and reject do not '
        '(T62)', () async {
      for (final (decision, optionId) in [
        (ApprovalDecision.allowAlways, 'approve_always'),
        (ApprovalDecision.allowOnce, 'approve_once'),
        (ApprovalDecision.deny, 'reject'),
      ]) {
        final s = _Session(
          make: () => ThincoderMock(askPermission: true, autoApprove: false),
        );
        addTearDown(s.dispose);
        s.kernel.prepare();
        await settle();
        s.send('go');
        await settle();

        final request =
            s.events.whereType<InteractionRequested>().single.request;
        s.kernel.answer(request.id, ApprovalAnswer(decision));
        await s.agent.finished.future;
        await settle();

        final reply = s.agent.written.where((m) => m['id'] == 'rpc-1').single;
        expect(reply['result'], {
          'outcome': {'outcome': 'selected', 'optionId': optionId},
        });
        final writes = s.agent.requests('session/set_config_option');
        if (decision != ApprovalDecision.allowAlways) {
          expect(writes, isEmpty);
          continue;
        }
        expect(writes.single['params'], {
          'sessionId': '1',
          'configId': 'autoApprove',
          'value': true,
        });
        expect(s.kernel.permission.selected, 'auto');

        // The next turn's tool call is not put to the user: auto is on.
        s.send('again', id: 'turn-2');
        await settle();
        expect(s.events.whereType<InteractionRequested>(), hasLength(1));
      }
    });

    test('a failed auto write keeps the approval and the switch (T62)',
        () async {
      final s = _Session(
        make: () => ThincoderMock(
          askPermission: true,
          autoApprove: false,
          configError: true,
        ),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      s.send('go');
      await settle();

      final request = s.events.whereType<InteractionRequested>().single.request;
      s.kernel.answer(
        request.id,
        const ApprovalAnswer(ApprovalDecision.allowAlways),
      );
      await s.agent.finished.future;
      await settle();

      final reply = s.agent.written.where((m) => m['id'] == 'rpc-1').single;
      expect(reply['result'], {
        'outcome': {'outcome': 'selected', 'optionId': 'approve_always'},
      });
      expect(s.kernel.permission.selected, 'ask');
      expect(s.kernel.health.status, KernelHealthStatus.ready);
      expect(s.items<ToolCallItem>().single.status, ToolStatus.succeeded);
    });

    test('a refused approval write keeps the face as reported (T59)',
        () async {
      final s = _Session(
        make: () => ThincoderMock(autoApprove: false, configError: true),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      s.kernel.permission.select('auto');
      await settle();
      expect(s.agent.requests('session/set_config_option'), hasLength(1));
      expect(s.kernel.permission.selected, 'ask');
      expect(s.kernel.health.status, KernelHealthStatus.ready);

      s.send('go');
      await settle();
      expect(s.events.whereType<TurnEnded>(), hasLength(1));
    });

    test('a refused level write keeps the effort as reported (T60)', () async {
      final s = _Session(
        make: () => ThincoderMock(
          thinkingLevels: const ['off', 'high', 'max'],
          configError: true,
        ),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      expect(s.kernel.effort.toggle, isFalse);
      expect(s.kernel.effort.selected, 'high');
      s.kernel.effort.select(s.kernel.model.selected!, 'max');
      await settle();
      expect(s.kernel.effort.selected, 'high');
      expect(s.kernel.health.status, KernelHealthStatus.ready);

      s.send('go');
      await settle();
      expect(s.events.whereType<TurnEnded>(), hasLength(1));
    });

    test('auto on: no panel; off: each call is put to the user (T52/T53)',
        () async {
      for (final auto in [true, false]) {
        final s = _Session(
          make: () => ThincoderMock(askPermission: true, autoApprove: auto),
        );
        addTearDown(s.dispose);
        s.kernel.prepare();
        await settle();
        s.send('go');
        await settle();

        final asked = s.events.whereType<InteractionRequested>().toList();
        expect(asked, hasLength(auto ? 0 : 1));
        if (!auto) {
          s.kernel.answer(
            asked.single.request.id,
            const ApprovalAnswer(ApprovalDecision.allowOnce),
          );
          await s.agent.finished.future;
          await settle();
        }
        expect(s.items<ToolCallItem>().single.status, ToolStatus.succeeded);
        expect(s.events.whereType<TurnEnded>(), hasLength(1));
      }
    });

    test('an older agent: no approval face, the thinking switch (T54/T57)',
        () async {
      final s = _Session();
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      expect(s.kernel.permission.options, isEmpty);
      expect(
        s.agent.configOptions.any((o) => o['id'] == 'autoApprove'),
        isFalse,
      );
      expect(s.kernel.effort.toggle, isTrue);
      expect(
        s.kernel.effort.optionsFor(s.kernel.model.selected!).map((o) => o.id),
        ['on'],
      );
    });

    test('a model list from the agent, and a pick that waits (T55)', () async {
      final s = _Session(
        make: () => ThincoderMock(
          models: const [
            'anthropic:claude-sonnet-5',
            'openai:gpt-5',
            'anthropic:claude-opus-5',
          ],
        ),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      expect(s.kernel.model.options.map((o) => o.id), [
        'anthropic:claude-sonnet-5',
        'openai:gpt-5',
        'anthropic:claude-opus-5',
      ]);
      expect(s.kernel.model.options.map((o) => o.group?.id), [
        'anthropic',
        'openai',
        'anthropic',
      ]);
      expect(s.kernel.model.options.first.label, 'claude-sonnet-5');
      expect(s.kernel.model.selected, 'anthropic:claude-sonnet-5');
      s.kernel.model.select('openai:gpt-5');
      expect(s.kernel.model.selected, 'anthropic:claude-sonnet-5');
      await settle();
      expect(s.agent.requests('session/set_config_option').single['params'], {
        'sessionId': '1',
        'configId': 'model',
        'value': 'openai:gpt-5',
      });
      expect(s.kernel.model.selected, 'openai:gpt-5');
    });

    test('a model keeps the name the agent gave it, under its provider', () {
      final option = thincoderOption(
        'model',
        'anthropic:claude-sonnet-5',
        'anthropic:Claude Sonnet 5',
        (_) => Icons.bolt_rounded,
      );
      expect(option.group?.id, 'anthropic');
      expect(option.label, 'Claude Sonnet 5');
    });

    test('thinking levels are a list, named as the app names them (T56)',
        () async {
      final s = _Session(
        make: () => ThincoderMock(
          thinkingLevels: const ['off', 'high', 'max', 'low'],
        ),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      expect(s.kernel.effort.toggle, isFalse);
      expect(
        s.kernel.effort
            .optionsFor(s.kernel.model.selected!)
            .map((o) => o.label),
        ['Off', 'High', 'Max', 'Low'],
      );
      expect(s.kernel.effort.selected, 'high');
      for (final level in ['high', 'low', 'off']) {
        s.kernel.effort.select(s.kernel.model.selected!, level);
        await settle();
        expect(
          s.agent.requests('session/set_config_option').last['params'],
          {'sessionId': '1', 'configId': 'thinkingLevel', 'value': level},
        );
      }
    });

    test('forced thinking keeps thinking on without Off (T57)', () async {
      final s = _Session(
        make: () => ThincoderMock(thinkingLevels: const ['high', 'max']),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      expect(s.kernel.effort.toggle, isFalse);
      expect(
        s.kernel.effort.optionsFor(s.kernel.model.selected!).map((o) => o.id),
        ['high', 'max'],
      );
      expect(s.kernel.effort.selected, 'high');
      expect(
        s.agent.configOptions.singleWhere(
          (o) => o['id'] == 'thinking',
        )['currentValue'],
        isTrue,
      );
    });

    test('levels with nothing to pick fall back to the switch (T58)',
        () async {
      final s = _Session(make: () => ThincoderMock(thinkingLevels: const []));
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      expect(s.kernel.effort.toggle, isTrue);
      expect(
        s.kernel.effort.optionsFor(s.kernel.model.selected!).map((o) => o.id),
        ['on'],
      );
      expect(s.kernel.effort.selected, 'on');
      expect(s.kernel.health.status, KernelHealthStatus.ready);
    });


    test('a start setting is applied once the session is up (D11)', () async {
      final s = _Session(
        context: const KernelContext(
          cwd: '/project',
          settings: {'mode': 'plan', 'model': 'opus', 'effort': 'high'},
        ),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      expect(s.agent.requests('session/set_mode').single['params'], {
        'sessionId': '1',
        'mode': 'plan',
      });
      // The host's other settings are Claude Code's shape: ignored.
      expect(s.agent.requests('session/set_config_option'), isEmpty);
      expect(s.kernel.mode.selected, 'plan');
    });

    test('a version older than the checked one is said of, not blocked',
        () async {
      final s = _Session(make: () => ThincoderMock(version: '0.12.0'));
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      expect(s.kernel.health.status, KernelHealthStatus.ready);
      expect(
        s.items<NoticeItem>().single.kind,
        NoticeKind.warning,
      );
      expect(s.items<NoticeItem>().single.text, contains('0.12.74'));
    });

    test('a session that cannot be made: how to sign in, not a crash',
        () async {
      final s = _Session(make: () => ThincoderMock(authRequired: true));
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      expect(s.kernel.health.status, KernelHealthStatus.failed);
      expect(s.kernel.health.message, 'thincoder is not logged in');
      expect(s.kernel.health.detail, contains('providers[].apiKey'));
      expect(s.kernel.health.detail, contains('thincoder acp --login'));
    });

    test('none installed: how to install one, and no crash', () async {
      final s = _Session(
        launch: (cwd) async => throw ThincoderUnavailable(
          'thincoder is not installed',
          detail: 'Install it (`${ThincoderLocator.installCommand}`, which '
              'needs ${ThincoderLocator.nodeRequirement}), then try again.',
        ),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      expect(s.agents, isEmpty);
      expect(s.kernel.health.status, KernelHealthStatus.failed);
      expect(s.kernel.health.message, 'thincoder is not installed');
      expect(s.kernel.health.detail, contains('npm install -g thincoder'));
      expect(s.kernel.health.detail, contains('Node.js 24'));

      // A message sent anyway is answered with that, and the turn ends.
      s.send('hi');
      await settle();
      expect(
        s.shown.where((line) => line.startsWith('notice error:')),
        ['notice error: thincoder is not installed'],
      );
      expect(s.transcript.lastTurnInterrupted, isTrue);
    });

    test('a release asked for while it is starting is taken up', () async {
      final s = _Session();
      addTearDown(s.dispose);
      s.kernel.prepare();
      // Before anything is up: asked to let go.
      s.kernel.release();
      await settle();

      expect(s.kernel.health.status, KernelHealthStatus.idle);
      expect(s.agent.requests('session/close'), hasLength(1));
      await s.kernel.stopped;
    });

    test('a turn carries the editor context, not the notes (D68)', () async {
      final s = _Session();
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      s.send(
        'look',
        notes: const ['a note the kernel no longer carries'],
        contexts: const [EditorContext('/p/a.dart', line: 3)],
      );
      await s.agent.finished.future;
      await settle();

      final params = s.agent.requests('session/prompt').single['params'] as Map;
      final text = ((params['prompt'] as List).single as Map)['text'] as String;
      // The editor's context goes as its own system reminder; the notes
      // are not thincoder's to carry any more.
      expect(text, startsWith('look\n\n<system-reminder>'));
      expect(text, contains('cursor on line 3'));
      expect(text, isNot(contains('a note the kernel no longer carries')));
      final item = s.items<UserMessageItem>().single;
      expect(item.text, 'look');
      expect(item.contexts, hasLength(1));
    });

    test('a turn carries the file open, its cursor and selection (T77)',
        () async {
      final s = await _ready();
      s.send(
        'look',
        contexts: [
          const EditorContext(
            '/p/a.dart',
            line: 10,
            selectedLines: (3, 5),
            selectedText: 'x\ny\nz',
          ),
        ],
      );
      await s.agent.finished.future;
      await settle();

      final prompt = _prompts(s).single;
      expect(prompt, startsWith('look\n\n<system-reminder>The user has'));
      expect(prompt, contains('/p/a.dart'));
      expect(prompt, contains('cursor on line 10'));
      expect(prompt, contains('lines 3-5'));
      expect(prompt, contains('x\ny\nz'));
      expect(prompt, endsWith('</system-reminder>'));
      final item = s.items<UserMessageItem>().single;
      expect(item.text, 'look');
      expect(item.contexts, hasLength(1));
    });

    test('the same file is said once a turn (T80)', () async {
      final s = await _ready();
      s.send(
        'look',
        contexts: const [
          EditorContext('/p/a.dart', line: 10),
          EditorContext('/p/./a.dart', line: 10),
        ],
      );
      await s.agent.finished.future;
      await settle();

      expect('The user has'.allMatches(_prompts(s).single), hasLength(1));
      expect(s.items<UserMessageItem>().single.contexts, hasLength(1));
    });

    test('pictures are saved where the agent runs, and named in the text',
        () async {
      final root = await Directory.systemTemp.createTemp('baocode-thincoder-');
      addTearDown(() => root.delete(recursive: true));
      final s = _Session(context: KernelContext(cwd: root.path));
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      s.send(
        'what is this',
        images: [
          ImageAttachment(
            bytes: Uint8List.fromList(const [1, 2, 3, 4]),
            mediaType: 'image/png',
          ),
        ],
      );
      await s.agent.finished.future;
      await settle();

      final saved = Directory(p.join(root.path, '.thincoder', 'tmp'))
          .listSync()
          .whereType<File>()
          .toList();
      expect(saved, hasLength(1));
      expect(
        p.basename(saved.single.path),
        matches(RegExp(r'^paste-[0-9a-z]+-0\.png$')),
      );
      final params = s.agent.requests('session/prompt').single['params'] as Map;
      final text = ((params['prompt'] as List).single as Map)['text'] as String;
      expect(text, 'what is this\n\n[Attached images: ${saved.single.path}]');
      // What was sent is what shows (F6), and the picture with it.
      final message = s.items<UserMessageItem>().single;
      expect(message.text, text);
      expect(message.images, hasLength(1));
    });

    test('pictures over the limits are dropped, and the rest go', () async {
      final root = await Directory.systemTemp.createTemp('baocode-thincoder-');
      addTearDown(() => root.delete(recursive: true));
      final s = _Session(context: KernelContext(cwd: root.path));
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      Uint8List big(int megabytes) => Uint8List(megabytes * 1000 * 1000);
      s.send(
        'three of them',
        images: [
          // One over the 15 MB a picture may be.
          ImageAttachment(bytes: big(16), mediaType: 'image/png'),
          ImageAttachment(bytes: Uint8List(10), mediaType: 'image/gif'),
          ImageAttachment(bytes: big(11), mediaType: 'image/jpeg'),
          ImageAttachment(bytes: big(11), mediaType: 'image/webp'),
          // Over the 30 MB a message may carry.
          ImageAttachment(bytes: big(11), mediaType: 'image/png'),
          // A kind the agent does not take.
          ImageAttachment(bytes: Uint8List(10), mediaType: 'image/tiff'),
        ],
      );
      await s.agent.finished.future;
      await settle();

      final saved = Directory(p.join(root.path, '.thincoder', 'tmp'))
          .listSync()
          .whereType<File>()
          .map((file) => p.basename(file.path))
          .toList();
      expect(saved, hasLength(3));
      // Named by where they were in the message, as the terminal names them.
      expect(saved.where((name) => name.endsWith('-1.gif')), hasLength(1));
      expect(saved.where((name) => name.endsWith('-2.jpg')), hasLength(1));
      expect(saved.where((name) => name.endsWith('-3.webp')), hasLength(1));
      expect(
        s.shown.where((line) => line.startsWith('notice warning:')),
        ['notice warning: 3 image(s) went unsent: one may be at most 15 MB, '
            'a message 30 MB.'],
      );
      expect(s.items<UserMessageItem>().single.images, hasLength(3));
    });

    test('T93: a new agent takes the pictures as native image blocks',
        () async {
      final root = await Directory.systemTemp.createTemp('baocode-thincoder-');
      addTearDown(() => root.delete(recursive: true));
      final s = _Session(
        context: KernelContext(cwd: root.path),
        make: () => ThincoderMock(promptImage: true),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      final bytes = Uint8List.fromList(const [1, 2, 3]);
      s.send(
        '看图',
        images: [ImageAttachment(bytes: bytes, mediaType: 'image/png')],
      );
      await s.agent.finished.future;
      await settle();

      final params = s.agent.requests('session/prompt').single['params'] as Map;
      final prompt = (params['prompt'] as List).cast<Map>();
      expect(prompt, hasLength(2));
      expect(prompt.first, {'type': 'text', 'text': '看图'});
      expect(prompt.last['type'], 'image');
      expect(prompt.last['mimeType'], 'image/png');
      expect(base64Decode(prompt.last['data'] as String), bytes);
      // The picture shows in the message, and nothing was written down.
      expect(s.items<UserMessageItem>().single.images, hasLength(1));
      expect(
        Directory(p.join(root.path, '.thincoder', 'tmp')).existsSync(),
        isFalse,
      );
    });

    test('T94: an old agent gets the picture saved and named, as today',
        () async {
      final root = await Directory.systemTemp.createTemp('baocode-thincoder-');
      addTearDown(() => root.delete(recursive: true));
      final s = _Session(context: KernelContext(cwd: root.path));
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      final bytes = Uint8List.fromList(const [1, 2, 3]);
      s.send(
        '看图',
        images: [ImageAttachment(bytes: bytes, mediaType: 'image/png')],
      );
      await s.agent.finished.future;
      await settle();

      final saved = Directory(p.join(root.path, '.thincoder', 'tmp'))
          .listSync()
          .whereType<File>()
          .single;
      expect(saved.readAsBytesSync(), bytes);
      final params = s.agent.requests('session/prompt').single['params'] as Map;
      expect((params['prompt'] as List).single, {
        'type': 'text',
        'text': '看图\n\n[Attached images: ${saved.path}]',
      });
    });

    test('T95: a picture over the limit is dropped, the rest go native',
        () async {
      final root = await Directory.systemTemp.createTemp('baocode-thincoder-');
      addTearDown(() => root.delete(recursive: true));
      final s = _Session(
        context: KernelContext(cwd: root.path),
        make: () => ThincoderMock(promptImage: true),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      final bytes = Uint8List.fromList(const [1, 2, 3]);
      s.send(
        'two of them',
        images: [
          ImageAttachment(
            bytes: Uint8List(ThincoderKernel.imageMaxBytes + 1),
            mediaType: 'image/png',
          ),
          ImageAttachment(bytes: bytes, mediaType: 'image/gif'),
        ],
      );
      await s.agent.finished.future;
      await settle();

      final params = s.agent.requests('session/prompt').single['params'] as Map;
      final prompt = (params['prompt'] as List).cast<Map>();
      expect(prompt, hasLength(2));
      expect(prompt.last['mimeType'], 'image/gif');
      expect(base64Decode(prompt.last['data'] as String), bytes);
      expect(
        s.shown.where((line) => line.startsWith('notice warning:')),
        ['notice warning: 1 image(s) went unsent: one may be at most 15 MB, '
            'a message 30 MB.'],
      );
      expect(s.items<UserMessageItem>().single.images, hasLength(1));
      expect(
        Directory(p.join(root.path, '.thincoder', 'tmp')).existsSync(),
        isFalse,
      );
    });

    test('T95②: pictures over the turn budget are dropped, the rest go native',
        () async {
      final root = await Directory.systemTemp.createTemp('baocode-thincoder-');
      addTearDown(() => root.delete(recursive: true));
      final s = _Session(
        context: KernelContext(cwd: root.path),
        make: () => ThincoderMock(promptImage: true),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      // The first two take 29 of the 30 MB a message may carry (one may be
      // 15): the third comes over the 1 MB left.
      s.send(
        'three of them',
        images: [
          ImageAttachment(
            bytes: Uint8List(ThincoderKernel.imageMaxBytes),
            mediaType: 'image/png',
          ),
          ImageAttachment(
            bytes: Uint8List(14000000),
            mediaType: 'image/gif',
          ),
          ImageAttachment(
            bytes: Uint8List(2000000),
            mediaType: 'image/webp',
          ),
        ],
      );
      await s.agent.finished.future;
      await settle();

      final params = s.agent.requests('session/prompt').single['params'] as Map;
      final prompt = (params['prompt'] as List).cast<Map>();
      expect(prompt, hasLength(3));
      expect(prompt.first, {'type': 'text', 'text': 'three of them'});
      expect(
        [for (final image in prompt.skip(1)) image['mimeType']],
        ['image/png', 'image/gif'],
      );
      expect(
        s.shown.where((line) => line.startsWith('notice warning:')),
        ['notice warning: 1 image(s) went unsent: one may be at most 15 MB, '
            'a message 30 MB.'],
      );
      expect(s.items<UserMessageItem>().single.images, hasLength(2));
      expect(
        Directory(p.join(root.path, '.thincoder', 'tmp')).existsSync(),
        isFalse,
      );
    });
  });

  group('thincoder usage', () {
    /// A kernel over an agent running [script], which the test may change
    /// between turns.
    Future<_Session> ready(List<Map<String, Object?>> script) async {
      final s = _Session(make: () => ThincoderMock(turn: script));
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      return s;
    }

    test('T96: two turns add up, in the footer and the session total',
        () async {
      final script = <Map<String, Object?>>[];
      final session = await ready(script);

      script.addAll([
        {'sessionUpdate': 'usage_update', 'used': 100, 'size': 1000},
        {'sessionUpdate': 'usage_update', 'used': 50},
      ]);
      session.send('one', id: 'turn-1');
      await session.agent.finished.future;
      await settle();

      script
        ..clear()
        ..add({'sessionUpdate': 'usage_update', 'used': 70});
      session.send('two', id: 'turn-2');
      await session.agent.finished.future;
      await settle();

      final ended = session.events.whereType<TurnEnded>().toList();
      expect(ended.map((event) => event.usage?.spentTokens), [150, 70]);
      final messages = session.items<UserMessageItem>();
      expect(messages.first.usage?.spentTokens, 150);
      expect(messages.last.usage?.spentTokens, 70);
      final usage = session.events.whereType<UsageReported>().last.usage;
      expect(usage.sessionSpent, 220);
      expect(usage.window, 1000);
    });

    test('T97: the context is the latest snapshot, the session the sum',
        () async {
      final s = _Session(
        make: () => ThincoderMock(
          turn: const [
            {'sessionUpdate': 'usage_update', 'used': 900, 'size': 1000},
            {'sessionUpdate': 'usage_update', 'used': 950, 'size': 1000},
          ],
        ),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      s.send('one');
      await s.agent.finished.future;
      await settle();

      final usage = s.transcript.usage!;
      expect(usage.used, 950);
      expect(usage.window, 1000);
      expect(usage.sessionSpent, 1850);
    });

    test('T98: usage outside a turn adds to the session, not to one',
        () async {
      final script = <Map<String, Object?>>[];
      final session = await ready(script);

      session.agent.push(
        _update({'sessionUpdate': 'usage_update', 'used': 30, 'size': 1000}),
      );
      await settle();
      expect(session.transcript.usage?.sessionSpent, 30);

      script.add({'sessionUpdate': 'usage_update', 'used': 20});
      session.send('go');
      await session.agent.finished.future;
      await settle();

      final ended = session.events.whereType<TurnEnded>().single;
      expect(ended.usage?.spentTokens, 20);
      expect(session.transcript.usage?.sessionSpent, 50);
    });
  });

  group('thincoder queue', () {
    /// A kernel on a scripted agent (its turn is one step, held), ready.
    Future<_Session> ready() async {
      final s = _Session(
        make: () => ThincoderMock(
          turn: const [{'sessionUpdate': 'usage_update', 'used': 1, 'size': 2}],
        )..hold = Completer<void>(),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      return s;
    }

    test('a message sent while it works waits, then goes (T63)', () async {
      final s = await ready();
      s.send('one');
      await settle();
      s.send('two', id: 'turn-2');
      await settle();
      expect(s.agent.requests('session/prompt'), hasLength(1)); // ①
      expect(s.transcript.queued.single.$1, 'turn-2'); // ②
      expect(s.transcript.queued.single.$2.queued, isTrue);
      expect(s.items<UserMessageItem>().map((item) => item.text), ['one']);
      await _let(s);
      expect(_prompts(s), ['one', 'two']); // ④
      expect(s.transcript.queued, isEmpty);
      expect(s.items<UserMessageItem>().last.queued, isFalse);
    });

    test('they go one at a time, in the order sent (T64)', () async {
      final s = await ready();
      s.send('one');
      await settle();
      s.send('two', id: 'turn-2');
      s.send('three', id: 'turn-3');
      await settle();
      expect(s.transcript.queued.map((q) => q.$1), ['turn-2', 'turn-3']);
      await _let(s, hold: true);
      expect(_prompts(s), ['one', 'two']);
      expect(s.transcript.queued.map((q) => q.$1), ['turn-3']);
      await _let(s, hold: true);
      expect(_prompts(s), ['one', 'two', 'three']);
      await _let(s);
      expect(s.items<UserMessageItem>().map((item) => item.text),
          ['one', 'two', 'three']);
    });

    test('a waiting message is taken back, one already sent is not (T65)',
        () async {
      final s = await ready();
      s.send('one');
      await settle();
      s.send('two', id: 'turn-2');
      s.send('three', id: 'turn-3');
      await settle();
      final before = s.agent.written.length;
      expect(await s.kernel.cancelQueued('turn-3'), isTrue);
      expect(s.transcript.queued.map((q) => q.$1), ['turn-2']);
      expect(s.events.whereType<ItemRemoved>().map((e) => e.id), ['turn-3']);
      expect(await s.kernel.cancelQueued('turn-3'), isFalse);
      expect(await s.kernel.cancelQueued('turn-1'), isFalse); // Already sent.
      expect(s.agent.written, hasLength(before)); // Nothing on the wire.
      await _let(s, hold: true);
      await _let(s);
      expect(_prompts(s), ['one', 'two']); // turn-3 never goes.
      s.agent.hold = Completer<void>();
      s.send('four', id: 'turn-4');
      await settle();
      s.send('five', id: 'turn-5');
      s.send('six', id: 'turn-6');
      await settle();
      s.kernel.sendQueuedNow('turn-6');
      final taken = s.kernel.cancelQueued('turn-6');
      s.agent.hold = Completer<void>();
      expect(await taken, isTrue);
      expect(s.events.whereType<ItemRemoved>().map((e) => e.id),
          ['turn-3', 'turn-6']);
      await _let(s);
      expect(_prompts(s).skip(2), ['four', 'five']); // turn-6 never goes.
    });

    test('one taken up now goes first, the rest keep order (T66)', () async {
      final s = await ready();
      s.send('one');
      await settle();
      s.send('two', id: 'turn-2');
      s.send('three', id: 'turn-3');
      await settle();
      s.kernel.sendQueuedNow('turn-3');
      s.agent.hold = Completer<void>();
      await settle();
      expect(s.agent.requests('session/cancel'), hasLength(1)); // ①
      expect(s.transcript.lastTurnInterrupted, isTrue); // ②
      expect(_prompts(s), ['one', 'three']); // ③
      expect(s.transcript.queued.map((q) => q.$1), ['turn-2']); // ⑤
      await _let(s, hold: true);
      expect(_prompts(s), ['one', 'three', 'two']); // ④
      await _let(s);
      expect(s.items<UserMessageItem>().map((item) => item.text),
          ['one', 'three', 'two']);
      s.agent.hold = Completer<void>();
      s.send('four', id: 'turn-4');
      await settle();
      s.send('five', id: 'turn-5');
      s.send('six', id: 'turn-6');
      await settle();
      s.kernel.sendQueuedNow('turn-6');
      s.kernel.sendQueuedNow('turn-5');
      s.agent.hold = Completer<void>();
      await settle();
      expect(_prompts(s).skip(3), ['four', 'five']);
      await _let(s, hold: true);
      expect(_prompts(s).skip(3), ['four', 'five', 'six']);
      await _let(s);
    });

    test('what waits goes with the session, a failed send stays (T67)',
        () async {
      Future<_Session> waiting() async {
        final s = await ready();
        s.send('one');
        await settle();
        s.send('two', id: 'turn-2');
        await settle();
        return s;
      }

      final dead = await waiting();
      dead.agent.crash();
      await settle();
      expect(dead.transcript.queued, isEmpty);
      expect(dead.items<UserMessageItem>().map((item) => item.text), ['one']);
      expect(dead.events.whereType<ItemRemoved>().map((e) => e.id),
          ['turn-2']);
      final restarted = await waiting();
      restarted.kernel.restart();
      await settle();
      expect(restarted.transcript.queued, isEmpty);
      expect(restarted.items<UserMessageItem>().map((item) => item.text),
          ['one']);
      expect(restarted.events.whereType<ItemRemoved>().map((e) => e.id),
          ['turn-2']);
      final failed = await waiting();
      failed.agent.promptError = true;
      await _let(failed);
      expect(failed.transcript.queued, isEmpty);
      expect(failed.items<UserMessageItem>().map((item) => item.text),
          ['one', 'two']);
      expect(failed.items<NoticeItem>().where((n) => n.kind == NoticeKind.error),
          hasLength(1));
      expect(failed.transcript.lastTurnInterrupted, isTrue);
      failed.agent.promptError = false;
      failed.send('three', id: 'turn-3');
      await settle();
      expect(_prompts(failed), ['one', 'two', 'three']);
    });
  });

  group('thincoder subagents', () {
    test('a card and a row follow one through its life (T28)', () async {
      final s = _Session();
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      s.agent.push(_signal('eng-coder', 2, 'queued', null, 'waiting'));
      await settle();
      expect(s.cards.single.description, 'eng-coder#2');
      expect(s.cards.single.status, CommandStatus.running);
      expect(s.cards.single.activity, 'queued · waiting');
      expect(s.running, isEmpty); // Waiting: the card carries it (D23).

      s.agent.push(_signal('eng-coder', 2, 'async'));
      await settle();
      expect(s.cards.single.activity, isNull);
      expect(s.running.single.id, 'subagent:eng-coder#2');
      expect(s.running.single.description, 'eng-coder#2');
      expect(s.running.single.kind, KernelTaskKind.agent);
      expect(s.running.single.background, isTrue);

      s.agent.push(
        _signal('eng-coder', 2, 'turn', {'turn': 1, 'maxTurns': 100}),
      );
      await settle();
      expect(s.cards.single.activity, 'turn 1/100');
      expect(s.running.single.summary, 'turn 1/100');

      // The one that is there where the pair is not whole; and nothing at
      // all where the report says nothing of a turn (the last word then
      // stands — the forms are fixed, D28).
      s.agent.push(_signal('eng-coder', 2, 'turn', {'turn': 2}));
      await settle();
      expect(s.cards.single.activity, 'turn 2');
      s.agent.push(_signal('eng-coder', 2, 'turn', {'maxTurns': 100}));
      await settle();
      expect(s.cards.single.activity, 'turn 2');

      s.agent.push(_signal('eng-coder', 2, 'settled'));
      await settle();
      expect(s.cards.single.status, CommandStatus.succeeded);
      expect(s.cards.single.duration, isNotNull);
      expect(s.cards.single.activity, isNull);
      expect(s.running, isEmpty); // Settled: its row leaves the strip.
      expect(s.transcript.tasks.single.status, CommandStatus.succeeded);

      s.agent.push(_signal('eng-coder', 2, 'done'));
      await settle();
      expect(s.cards, hasLength(1)); // Idempotent (D25).
      expect(s.cards.single.status, CommandStatus.succeeded);
    });

    test('four run and one waits, counted apart (T29)', () async {
      final s = _Session();
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      for (final (role, id) in [('a', 1), ('b', 2), ('c', 3), ('d', 4)]) {
        s.agent.push(_signal(role, id, 'async'));
      }
      s.agent.push(_signal('e', 5, 'queued', {'position': 1}, 'no slot free'));
      await settle();

      // Four at work — the strip folds more than three into a count of its
      // own — and the waiting one in its card alone (D23).
      expect(
        s.running.map((task) => task.description),
        ['a#1', 'b#2', 'c#3', 'd#4'],
      );
      expect(s.cards, hasLength(5));
      expect(s.cards.last.activity, 'queued · no slot free');
    });

    test('one stopped freezes failed, cancelled ones go (T30/T31/T40)',
        () async {
      final s = _Session();
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      s.agent.push(_signal('a', 1, 'async'));
      s.agent.push(_signal('a', 1, 'turn', {'turn': 1, 'maxTurns': 9}));
      s.agent.push(_signal('a', 1, 'stopped'));
      await settle();
      expect(s.cards.single.status, CommandStatus.failed);
      expect(s.cards.single.duration, isNotNull);
      expect(s.transcript.tasks.single.status, CommandStatus.failed);
      expect(s.running, isEmpty);

      // Cancelled while queued: it never ran, so nothing of it is kept.
      s.agent.push(_signal('b', 2, 'queued', {'position': 1}));
      s.agent.push(_signal('b', 2, 'cancelled'));
      await settle();
      expect(s.cards, hasLength(1));
      expect(s.transcript.tasks, hasLength(1));

      // Cancelled with a row up already: out of contract, taken out all
      // the same — nothing is left saying it runs (T40).
      s.agent.push(_signal('c', 3, 'async'));
      await settle();
      expect(s.running, hasLength(1));
      s.agent.push(_signal('c', 3, 'cancelled'));
      await settle();
      expect(s.cards, hasLength(1));
      expect(s.transcript.tasks, hasLength(1));
      expect(s.running, isEmpty);
    });

    test('unknown states and unreadable reports are left alone (T32/T33)',
        () async {
      final s = _Session();
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      s.agent.push(_signal('a', 1, 'async'));
      s.agent.push(_signal('a', 1, 'turn', {'turn': 2, 'maxTurns': 100}));
      await settle();

      // A state the domain may grow to: nothing is decided of it (E4, D27),
      // and what it could not read is said in the log, never dropped.
      final dir = Directory.systemTemp.createTempSync('thincoder-events');
      addTearDown(() {
        EventLog.current = null;
        dir.deleteSync(recursive: true);
      });
      EventLog.current = EventLog(dir.path);
      final before = s.events.length;
      s.agent.push(_signal('a', 1, 'settling'));
      await settle();
      expect(s.cards.single.status, CommandStatus.running);
      expect(s.cards.single.activity, 'turn 2/100');
      expect(s.running, hasLength(1));
      expect(s.kernel.health.status, KernelHealthStatus.ready);
      expect(
        File(p.join(dir.path, 'events.log')).readAsStringSync(),
        contains('a subagent state it does not know: settling'),
      );

      // Nothing of a subagent, or a shape this adapter cannot read: no
      // event at all, and the log says so too (E4).
      void raw(Object? meta) => s.agent.push(
        _update({'sessionUpdate': 'session_info_update', '_meta': meta}),
      );
      raw(null);
      raw('no map at all');
      raw({
        'thincoder.dev/subagent': {'role': 7, 'id': 2, 'state': 'turn'},
      });
      await settle();
      expect(s.events, hasLength(before));
      expect(s.cards, hasLength(1));
      expect(
        File(p.join(dir.path, 'events.log')).readAsStringSync(),
        contains('to leave alone'),
      );
    });

    test('a digest is text, and the row outlives the turn (T34/T35)', () async {
      final s = _Session(
        make: () => ThincoderMock(
          turn: const [
            {
              'sessionUpdate': 'session_info_update',
              '_meta': {
                'thincoder.dev/subagent': {
                  'role': 'eng-coder',
                  'id': 1,
                  'state': 'async',
                },
              },
            },
            {
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': 'One is at work.'},
            },
          ],
        ),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      s.send('do it');
      await s.agent.finished.future;
      await settle();
      expect(s.transcript.activeTurn, isNull);
      expect(s.running, hasLength(1)); // Hanging on past the turn (T35).

      // The subagent's report arrives on its own: text, not a turn (D26).
      s.agent.push(_update({
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'Three files came back.'},
      }));
      await settle();
      expect(s.transcript.activeTurn, isNull);
      expect(s.events.whereType<TurnStarted>(), hasLength(1));
      expect(s.events.whereType<TurnEnded>(), hasLength(1));
      expect(s.shown, contains('text: Three files came back.'));
      expect(s.running, hasLength(1));

      // Sending while it runs goes on as usual.
      s.send('and again', id: 'turn-2');
      await s.agent.finished.future;
      await settle();
      expect(s.agent.requests('session/prompt'), hasLength(2));
      expect(s.running, hasLength(1));
    });

    test('a process that dies leaves its subagents failed (T36)', () async {
      final s = _Session(make: () => ThincoderMock()..hold = Completer<void>());
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      s.send('go');
      await settle();
      s.agent.push(_signal('a', 1, 'async'));
      await settle();
      expect(s.running, hasLength(1));

      s.agent.crash();
      await settle();
      expect(s.transcript.lastTurnInterrupted, isTrue);
      expect(s.kernel.health.status, KernelHealthStatus.failed);
      expect(s.cards.single.status, CommandStatus.failed);
      expect(s.cards.single.duration, isNotNull);
      expect(s.transcript.tasks.single.status, CommandStatus.failed);
      expect(s.transcript.tasks.single.summary, 'thincoder stopped');
      expect(s.running, isEmpty);
      await s.kernel.stopped;

      // Another process, another subagent of the same name: nothing of the
      // dead one's is written on again (the ids start over with it).
      s.kernel.restart();
      await settle();
      s.agent.push(_signal('a', 1, 'async'));
      await settle();
      expect(s.cards.single.status, CommandStatus.running);
      expect(s.cards.single.activity, isNull);
      expect(s.running, hasLength(1));
    });

    test('a session_info_update that is no subagent is left alone (T37)',
        () async {
      final s = _Session();
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      final before = s.events.length;
      s.agent.push(_update({
        'sessionUpdate': 'session_info_update',
        '_meta': {'title': 'From the terminal'},
      }));
      await settle();
      expect(s.cards, isEmpty);
      expect(s.events, hasLength(before));
      expect(s.kernel.health.status, KernelHealthStatus.ready);
    });

    test('an approval reads with its tool (T38)', () async {
      final s = _Session();
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      s.agent.push(_signal('a', 1, 'async'));
      s.agent.push(
        _signal('a', 1, 'approval', {'turn': 2, 'maxTurns': 100}, 'Bash'),
      );
      await settle();
      expect(s.cards.single.activity, 'approval · Bash');
      expect(s.cards.single.status, CommandStatus.running);
      expect(s.running, hasLength(1));

      s.agent.push(_signal('a', 1, 'approval'));
      await settle();
      expect(s.cards.single.activity, 'approval');
      expect(s.running, hasLength(1));

      s.agent.push(_signal('a', 1, 'settled'));
      await settle();
      expect(s.cards.single.status, CommandStatus.succeeded);
      expect(s.cards.single.duration, isNotNull);
      expect(s.running, isEmpty);
    });

    test('a first frame that is already the last settles at once (T39)',
        () async {
      final s = _Session();
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      s.agent.push(_signal('a', 1, 'settled'));
      s.agent.push(_signal('b', 2, 'stopped'));
      await settle();
      expect(
        s.cards.map((card) => card.status),
        [CommandStatus.succeeded, CommandStatus.failed],
      );
      expect(s.cards.every((card) => card.duration != null), isTrue);
      expect(s.cards[1].description, 'b#2');
      expect(s.running, isEmpty); // Never built: no row of its own.
      expect(s.transcript.tasks, isEmpty);
    });

    test('a report that comes after the end moves nothing (T41)', () async {
      final s = _Session();
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      // Settled, then reported live again in every way it can be: the
      // card that stood down does not move, and its row does not come
      // back to the strip (D31).
      s.agent.push(_signal('a', 1, 'async'));
      s.agent.push(_signal('a', 1, 'turn', {'turn': 1, 'maxTurns': 9}));
      s.agent.push(_signal('a', 1, 'settled'));
      await settle();
      final settled = s.cards.single;
      var before = s.events.length;

      s.agent.push(_signal('a', 1, 'async'));
      s.agent.push(_signal('a', 1, 'queued', {'position': 1}, 'waiting'));
      s.agent.push(_signal('a', 1, 'turn', {'turn': 3, 'maxTurns': 9}));
      s.agent.push(_signal('a', 1, 'approval', null, 'Bash'));
      await settle();
      expect(s.cards.single.status, CommandStatus.succeeded);
      expect(s.cards.single.activity, settled.activity);
      expect(s.cards.single.duration, settled.duration);
      expect(s.running, isEmpty);
      expect(s.events, hasLength(before));

      // The same for one that stopped, and for one a cancel took off the
      // panel: nothing of either is put back (D31).
      s.agent.push(_signal('b', 2, 'async'));
      s.agent.push(_signal('b', 2, 'stopped'));
      await settle();
      final failed = s.cards.last;
      expect(failed.status, CommandStatus.failed);
      before = s.events.length;

      s.agent.push(_signal('b', 2, 'queued', null, 'no slot free'));
      s.agent.push(_signal('b', 2, 'async'));
      await settle();
      expect(s.cards, hasLength(2));
      expect(s.cards.last.status, CommandStatus.failed);
      expect(s.cards.last.activity, failed.activity);
      expect(s.cards.last.duration, failed.duration);
      expect(s.running, isEmpty);
      expect(s.events, hasLength(before));

      s.agent.push(_signal('c', 3, 'async'));
      s.agent.push(_signal('c', 3, 'cancelled'));
      await settle();
      expect(s.cards, hasLength(2)); // Taken out with the cancel (T40).
      before = s.events.length;

      s.agent.push(_signal('c', 3, 'async'));
      s.agent.push(_signal('c', 3, 'queued', {'position': 1}));
      await settle();
      expect(s.cards, hasLength(2));
      expect(s.cards.map((card) => card.description), ['a#1', 'b#2']);
      expect(s.running, isEmpty);
      expect(s.events, hasLength(before));

      // And off the panel is off for good: the states that would end a card
      // are as ignored as the live ones — none of them builds it again
      // (D31).
      s.agent.push(_signal('c', 3, 'settled'));
      s.agent.push(_signal('c', 3, 'stopped'));
      s.agent.push(_signal('c', 3, 'done'));
      s.agent.push(_signal('c', 3, 'settling'));
      await settle();
      expect(s.cards, hasLength(2));
      expect(s.cards.map((card) => card.description), ['a#1', 'b#2']);
      expect(s.running, isEmpty);
      expect(s.events, hasLength(before));

      // A name of its own is not held back by any of this.
      s.agent.push(_signal('d', 4, 'queued', {'position': 1}, 'waiting'));
      await settle();
      expect(s.cards, hasLength(3));
      expect(s.cards.last.description, 'd#4');
      expect(s.cards.last.status, CommandStatus.running);
      expect(s.cards.last.activity, 'queued · waiting');

      // A process coming back starts its ids over: a name a cancel took
      // out of the old process's book is not held against the new one
      // (D31).
      s.kernel.restart();
      await settle();
      s.agent.push(_signal('c', 3, 'async'));
      await settle();
      expect(s.cards, hasLength(4));
      expect(s.cards.last.description, 'c#3');
      expect(s.cards.last.status, CommandStatus.running);
      expect(s.running, hasLength(1));
    });

    test('a subagent\'s content is its own (T42)', () async {
      final s = await _ready();
      s.agent.push(_signal('eng-coder', 2, 'async'));
      s.agent.push(_said('eng-coder', 2, 'Reading.', thought: true));
      s.agent.push(_said('eng-coder', 2, 'Found three.'));
      await settle();
      expect(s.shown, isEmpty); // Nothing of it in the conversation.
      expect(s.transcript.length, 1); // Its card alone.
      final card = s.cards.single;
      expect(card.id, 'subagent:eng-coder#2');
      expect(card.children, hasLength(2));
      expect((card.children[0] as ThinkingItem).text, 'Reading.');
      expect((card.children[1] as AssistantTextItem).text, 'Found three.');
    });

    test('two subagents stream apart, 256 characters at a time (T43)',
        () async {
      final s = await _ready();
      s.agent.push(_signal('a', 1, 'async'));
      s.agent.push(_signal('b', 2, 'async'));
      s.agent.push(_said('a', 1, 'a' * 300));
      for (var i = 0; i < 3; i++) {
        s.agent.push(_said('b', 2, 'b' * 100));
      }
      await settle();
      List<ChatItem> of(String name) =>
          s.cards.firstWhere((card) => card.description == name).children;
      // A's first block is its whole piece (300 ≥ 256); B's card has its
      // first 100, and the next 200 wait (200 < 256).
      expect((of('a#1').single as AssistantTextItem).text, hasLength(300));
      expect((of('b#2').single as AssistantTextItem).text, hasLength(100));
      s.agent.push(_signal('b', 2, 'turn', {'turn': 1, 'maxTurns': 9}));
      await settle();
      expect((of('a#1').single as AssistantTextItem).text, hasLength(300));
      expect((of('b#2').single as AssistantTextItem).text, hasLength(300));
    });

    test('content with no mark is the conversation\'s own (T44)', () async {
      final s = await _ready();
      final dir = _log();
      s.agent.push(_update(_reply('As before.')));
      await settle();
      expect(s.shown, ['text: As before.']);
      expect(s.cards, isEmpty);
      // A frame with no mark is no one's to judge: nothing is said of it.
      expect(_saidLines(dir), isEmpty);
    });

    test('a mark that names no one is dropped, and said once (T45)', () async {
      final s = await _ready();
      final dir = _log();
      // No mark at all: the conversation's own, as it always was.
      s.agent.push(_update({..._reply('first'), '_meta': 'no map'}));
      s.agent.push(_update({..._reply(' second'), '_meta': {'other': 1}}));
      await settle();
      expect(s.items<AssistantTextItem>().single.text, 'first second');
      expect(s.cards, isEmpty);
      // A mark that says a subagent and names none: dropped, and said once.
      for (final mark in <Object?>[
        'eng-coder#2',
        {'role': 7, 'id': 2},
        {'role': 'eng-coder', 'id': '2'},
        {'role': '', 'id': 2},
        {'role': 'eng-coder', 'id': -1},
      ]) {
        s.agent.push(_update({..._reply('lost'), '_meta': _marked(mark)}));
      }
      await settle();
      expect(s.items<AssistantTextItem>().single.text, 'first second');
      expect(s.cards, isEmpty);
      expect(_saidTimes(dir, 'names no one'), 1);
    });

    test('content before its state opens the card first (T46)', () async {
      final s = await _ready();
      // The conversation is writing as the subagent comes in: its piece is
      // not cut (§16.2), only the card opens under it.
      s.agent.push(_update(_reply('a')));
      s.agent.push(_said('eng-coder', 2, 'Before any report.'));
      s.agent.push(_update(_reply('b')));
      await settle();
      expect(s.items<AssistantTextItem>().single.text, 'ab');
      expect(s.cards.single.id, 'subagent:eng-coder#2');
      expect(s.cards.single.status, CommandStatus.running);
      expect(s.running, isEmpty); // No report yet: no row in the strip.
      s.agent.push(_signal('eng-coder', 2, 'async'));
      await settle();
      expect(s.running.single.id, 'subagent:eng-coder#2');
      expect(
        (s.cards.single.children.single as AssistantTextItem).text,
        'Before any report.',
      );
      // A state report's own first sight keeps batch 4's way: the piece the
      // conversation is writing closes there, and the next text starts anew
      // — where the content frame above left it alone (hence 'abc').
      s.agent.push(_update(_reply('c')));
      s.agent.push(_signal('c', 3, 'async'));
      s.agent.push(_update(_reply('d')));
      await settle();
      expect(
        s.items<AssistantTextItem>().map((item) => item.text),
        ['abc', 'd'],
      );
    });

    test('content after a cancel or an end is dropped, said once (T47)',
        () async {
      final s = await _ready();
      final dir = _log();
      s.agent.push(_signal('a', 1, 'async'));
      s.agent.push(_signal('a', 1, 'cancelled'));
      await settle();
      s.agent.push(_said('a', 1, 'late'));
      s.agent.push(_said('a', 1, 'later'));
      await settle();
      expect(s.cards, isEmpty);
      expect(s.shown, isEmpty);
      expect(_saidTimes(dir, 'subagent:a#1'), 1);
      s.agent.push(_signal('b', 2, 'async'));
      s.agent.push(_signal('b', 2, 'settled'));
      await settle();
      s.agent.push(_said('b', 2, 'after'));
      s.agent.push(_said('b', 2, 'again'));
      await settle();
      expect(s.cards.single.status, CommandStatus.succeeded);
      expect(s.cards.single.children, isEmpty);
      expect(_saidTimes(dir, 'subagent:b#2'), 1);
    });

    test('children outlive the turn and go with the process (T48)', () async {
      final s = await _ready();
      s.agent.push(_signal('a', 1, 'async'));
      s.send('one');
      await s.agent.finished.future;
      await settle();
      s.agent.push(_said('a', 1, 'First turn.'));
      await settle();
      expect(s.cards.single.children, hasLength(1));
      // A second turn leaves them where they were.
      s.send('two', id: 'turn-2');
      await s.agent.finished.future;
      await settle();
      expect(s.cards.single.children, hasLength(1));
      s.agent.push(_said('a', 1, 'Second turn.'));
      await settle();
      expect(s.cards.single.children, hasLength(2));
      // The process goes: its card stands frozen, what it said kept with it.
      s.agent.crash();
      await settle();
      expect(s.cards.single.status, CommandStatus.failed);
      expect(s.cards.single.children, hasLength(2));
      await s.kernel.stopped;
      // Another process opens a card of its own: the tape went with it.
      s.kernel.restart();
      await settle();
      s.agent.push(_said('a', 1, 'New process.'));
      await settle();
      expect(s.cards.last.children, hasLength(1));
    });

    test('a subagent speaking does not cut the conversation\'s piece (T49)',
        () async {
      final s = await _ready();
      s.agent.push(_signal('a', 1, 'async'));
      s.agent.push(_update(_reply('a')));
      s.agent.push(_said('a', 1, 'aside'));
      s.agent.push(_update(_reply('b')));
      await settle();
      expect(s.items<AssistantTextItem>().single.text, 'ab');
      final deltas = s.events.whereType<TextDelta>().toList();
      expect(deltas.map((delta) => delta.offset), [0, 1]);
      expect(deltas.map((delta) => delta.id).toSet(), hasLength(1));
      expect(s.cards.single.children, hasLength(1));
    });

    test('tool frames go with their subagent, the conversation its own '
        '(T50)', () async {
      final s = await _ready();
      final dir = _log();
      s.agent.push(_signal('a', 1, 'async'));
      s.agent.push(_signal('b', 2, 'async'));
      s.agent.push(_tool('t1', raw: {'path': 'lib/a'}, by: ('a', 1)));
      s.agent.push(_tool('t1', done: true, by: ('a', 1)));
      s.agent.push(_tool('t2', kind: 'execute', raw: {'command': 'ls'}));
      s.agent.push(_tool('t2', done: true));
      s.agent.push(_tool('t3', kind: 'search', raw: {'pattern': 'm'}, by: ('b', 2)));
      s.agent.push(_tool('t9', done: true, by: ('a', 1))); // No call: let go.
      await settle();
      final a = s.cards.firstWhere((card) => card.description == 'a#1');
      final b = s.cards.firstWhere((card) => card.description == 'b#2');
      expect((a.children.single as ToolCallItem).status, ToolStatus.succeeded);
      expect((b.children.single as ToolCallItem).status, ToolStatus.running);
      expect(s.items<ToolCallItem>(), isEmpty); // Not the conversation's.
      expect(s.items<TerminalItem>().single.command, 'ls'); // Its own, as before.
      // Marks that name no one: the first two shapes are the conversation's.
      for (final (i, meta) in <Object?>[
        'no map',
        {'other': 1},
        {'thincoder.dev/subagent': {'role': 7, 'id': 1}},
        {'thincoder.dev/subagent': {'role': 'a', 'id': '1'}},
      ].indexed) {
        s.agent.push(_tool('t${i + 4}', meta: meta));
      }
      await settle();
      expect(s.items<ToolCallItem>(), hasLength(2));
      expect(_saidTimes(dir, 'names no one'), 1);
      // After its end, a tool frame is dropped and said once for the key.
      s.agent.push(_signal('a', 1, 'settled'));
      await settle();
      s.agent.push(_tool('t7', by: ('a', 1)));
      await settle();
      expect(
        s.cards.firstWhere((card) => card.description == 'a#1').children,
        hasLength(1),
      );
      expect(_saidTimes(dir, 'subagent:a#1'), 1);
      // One a cancel took off the panel: dropped too, and said once for it.
      s.agent.push(_signal('b', 2, 'cancelled'));
      await settle();
      s.agent.push(_tool('t8', by: ('b', 2)));
      await settle();
      expect(s.cards, hasLength(1));
      expect(_saidTimes(dir, 'subagent:b#2'), 1);
    });
  });

  group('thincoder automatic turns', () {
    Future<_Session> held() async {
      final s = _Session(make: () => ThincoderMock()..hold = Completer<void>());
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      return s;
    }

    test('a boundary frame starts a turn the agent took up (T68)', () async {
      final s = await _ready();
      s.agent.push(_turn('start'));
      await settle();
      expect(s.transcript.activeTurnUnprompted, isTrue);
      expect(s.events.whereType<TurnStarted>().single.unprompted, isTrue);
      s.agent.push(_update(_reply('The digest is in: three files.')));
      s.agent.push(_turn('end'));
      await settle();
      expect(s.shown, ['text: The digest is in: three files.']);
      expect(s.transcript.lastTurnUnprompted, isTrue);
      expect(s.transcript.lastTurnInterrupted, isFalse);
      expect(s.transcript.activeTurn, isNull);
    });

    test('a start with the answer is held for that turn\'s end (T69)',
        () async {
      final s = await held();
      s.send('one');
      await settle();
      s.agent.push(_turn('start'));
      await settle();
      expect(s.transcript.activeTurn, 'turn-1'); // The user's turn goes on.
      expect(s.events.whereType<TurnEnded>(), isEmpty);
      await _let(s);
      expect(s.events.whereType<TurnEnded>(), hasLength(1));
      expect(s.events.whereType<TurnStarted>().last.unprompted, isTrue);
      expect(s.transcript.activeTurn, 'auto:1');
      s.agent.push(_turn('end'));
      await settle();
      expect(s.transcript.activeTurn, isNull);
      expect(s.transcript.lastTurnUnprompted, isTrue);
    });

    test('a held start takes the turn before the queue (T69②)', () async {
      final s = await held();
      s.send('one');
      await settle();
      s.send('two', id: 'turn-2');
      await settle();
      s.agent.push(_turn('start'));
      await settle();
      await _let(s);
      expect(_prompts(s), ['one']);
      expect(s.transcript.activeTurn, 'auto:1');
      expect(s.transcript.queued.map((q) => q.$1), ['turn-2']);
      s.agent.push(_turn('end'));
      await settle();
      expect(_prompts(s), ['one', 'two']);
      expect(s.transcript.queued, isEmpty);
    });

    test('a message sent in an automatic turn waits (T70)', () async {
      final s = await _ready();
      s.agent.push(_turn('start'));
      await settle();
      s.send('two');
      await settle();
      expect(s.transcript.queued.single.$1, 'turn-1');
      expect(_prompts(s), isEmpty);
      s.agent.push(_turn('end'));
      await settle();
      expect(_prompts(s), ['two']);
    });

    test('a cancel and a failing end both stop it (T71/T71②)', () async {
      final s = await _ready();
      s.agent.push(_turn('start'));
      await settle();
      s.kernel.cancel();
      await settle();
      expect(s.agent.requests('session/cancel').single['params'], {
        'sessionId': '1',
      });
      s.agent.push(_turn('end', ok: false));
      await settle();
      expect(s.transcript.activeTurn, isNull);
      expect(s.transcript.lastTurnInterrupted, isTrue);
      // An end that fails on the agent's own word: no cancel of ours.
      final t = await _ready();
      t.agent.push(_turn('start'));
      await settle();
      t.agent.push(_turn('end', ok: false));
      await settle();
      expect(t.agent.requests('session/cancel'), isEmpty);
      expect(t.transcript.activeTurn, isNull);
      expect(t.transcript.lastTurnInterrupted, isTrue);
    });

    test('a process that dies in an automatic turn stops it (T72)',
        () async {
      final s = await _ready();
      s.agent.push(_turn('start'));
      s.agent.push(_update(_reply('Half an answer')));
      await settle();
      s.agent.crash();
      await settle();
      expect(s.transcript.activeTurn, isNull);
      expect(s.transcript.lastTurnInterrupted, isTrue);
      expect(s.shown.where((line) => line.startsWith('notice error:')),
          ['notice error: thincoder stopped unexpectedly']);
      expect(s.kernel.health.status, KernelHealthStatus.failed);
      await s.kernel.stopped;
    });

    test('an empty automatic turn is still a turn (T73)', () async {
      final s = await _ready();
      s.agent.push(_turn('start'));
      await settle();
      s.agent.push(_turn('end'));
      await settle();
      expect([...s.shown, ...s.cards], isEmpty);
      expect([s.transcript.lastTurnUnprompted, s.transcript.activeTurn],
          [true, null]);
    });

    test('turn frames out of contract are left alone (T74)', () async {
      final s = await held();
      final dir = _log();
      s.agent.push(
          _update({'sessionUpdate': 'session_info_update', '_meta': 'no map'}));
      s.agent.push(_update({
        'sessionUpdate': 'session_info_update',
        '_meta': {'thincoder.dev/turn': {'phase': 'sideways'}},
      }));
      s.agent.push(_turn('end')); // No turn under way: not its end.
      await settle();
      expect(s.transcript.activeTurn, isNull);
      expect(_saidTimes(dir, 'leave alone'), 3);
      // A user turn goes on: an end while it runs is not its own.
      s.send('one');
      await settle();
      s.agent.push(_turn('end'));
      await settle();
      expect(s.transcript.activeTurn, 'turn-1');
      expect(s.events.whereType<TurnEnded>(), isEmpty);
      expect(_saidTimes(dir, 'leave alone'), 4);
      await _let(s);
      // An automatic turn under way: no second one starts.
      s.agent.push(_turn('start'));
      await settle();
      s.agent.push(_turn('start'));
      await settle();
      expect(s.transcript.activeTurn, 'auto:1');
      expect(s.events.whereType<TurnStarted>().where((e) => e.unprompted),
          hasLength(1));
      expect(_saidTimes(dir, 'leave alone'), 5);
      s.agent.push(_turn('end'));
      await settle();
    });

    test('an end takes a held start back (T74①)', () async {
      final s = await held();
      final dir = _log();
      s.send('one');
      await settle();
      s.agent.push(_turn('start'));
      await settle();
      s.agent.push(_turn('end', ok: true));
      await settle();
      expect(s.transcript.activeTurn, 'turn-1');
      expect(s.events.whereType<TurnStarted>(), hasLength(1));
      expect(s.events.whereType<TurnEnded>(), isEmpty);
      expect(_saidTimes(dir, 'ended before it was taken up'), 1);
      await _let(s);
      expect(s.transcript.activeTurn, isNull);
      expect(s.transcript.lastTurnUnprompted, isFalse);
      expect(s.events.whereType<TurnEnded>().single.interrupted, isFalse);
      // Nothing of it is in the way: the next message goes out at once.
      s.send('two', id: 'turn-2');
      await settle();
      expect(_prompts(s), ['one', 'two']);
    });

    test('an end is taken whatever its ok is (T74②)', () async {
      final s = await _ready();
      final dir = _log();
      s.agent.push(_turn('start'));
      await settle();
      s.agent.push(_turn('end', ok: 'false'));
      await settle();
      expect(s.transcript.activeTurn, isNull);
      expect(s.transcript.lastTurnInterrupted, isFalse);
      expect(_saidTimes(dir, 'ok not a boolean'), 1);
      // An end with the key absent ends it too, and not as interrupted.
      final t = await _ready();
      t.agent.push(_turn('start'));
      await settle();
      t.agent.push(_turn('end'));
      await settle();
      expect(t.transcript.activeTurn, isNull);
      expect(t.transcript.lastTurnInterrupted, isFalse);
      expect(t.events.whereType<TurnEnded>(), hasLength(1));
      expect(_saidTimes(dir, 'ok not a boolean'), 1);
    });

    test('a release waits for a subagent still live (T75①)', () async {
      final s = await _ready();
      s.agent.push(_signal('a', 1, 'queued'));
      await settle();
      s.kernel.release();
      await settle();
      // Waiting is work too: the process stays for it (D64).
      expect(s.agent.requests('session/close'), isEmpty);
      expect(s.kernel.health.status, KernelHealthStatus.ready);
      // It settles: the one macrotask of silence passes, then the session
      // goes.
      s.agent.push(_signal('a', 1, 'settled'));
      await settle();
      expect(s.agent.requests('session/close'), hasLength(1));
      expect(s.kernel.health.status, KernelHealthStatus.idle);
      await s.kernel.stopped;
    });

    test('the digest turn that follows is taken before closing (T75②)',
        () async {
      final s = await _ready();
      s.agent.push(_signal('a', 1, 'async'));
      await settle();
      s.kernel.release();
      await settle();
      expect(s.agent.requests('session/close'), isEmpty);
      // The same window's wake: the subagent settles, and its digest turn
      // starts in the same batch. The turn keeps the process (D64).
      s.agent.push(_signal('a', 1, 'settled'));
      s.agent.push(_turn('start'));
      await settle();
      expect(s.agent.requests('session/close'), isEmpty);
      expect(s.transcript.activeTurn, 'auto:1');
      // The turn's own end takes up the release: one macrotask later.
      s.agent.push(_turn('end'));
      await settle();
      expect(s.agent.requests('session/close'), hasLength(1));
      expect(s.transcript.activeTurn, isNull);
      expect(s.kernel.health.status, KernelHealthStatus.idle);
    });

    test('a view that comes back calls the release off (T75③)', () async {
      final s = await _ready();
      s.agent.push(_signal('a', 1, 'async'));
      await settle();
      s.kernel.release();
      await settle();
      s.kernel.prepare();
      s.agent.push(_signal('a', 1, 'settled'));
      await settle();
      expect(s.agent.requests('session/close'), isEmpty);
      expect(s.kernel.health.status, KernelHealthStatus.ready);
    });

    test('a release waits for the window to close (T76①)', () async {
      final s = await _ready();
      s.agent.push(_turn('watch', on: true));
      s.agent.push(_signal('a', 1, 'async'));
      await settle();
      s.kernel.release();
      await settle();
      // The card settled with no turn up: the window alone holds it (D65).
      s.agent.push(_signal('a', 1, 'settled'));
      await settle();
      expect(s.agent.requests('session/close'), isEmpty);
      s.agent.push(_turn('start'));
      await settle();
      expect(s.transcript.activeTurn, 'auto:1');
      s.agent.push(_turn('end', ok: true));
      await settle();
      expect(s.agent.requests('session/close'), isEmpty);
      s.agent.push(_turn('watch', on: false));
      await settle();
      expect(s.agent.requests('session/close'), hasLength(1));
      expect(s.kernel.health.status, KernelHealthStatus.idle);
      await s.kernel.stopped;
    });

    test('with no window frame the silence still closes it (T76②)', () async {
      final s = await _ready();
      s.agent.push(_signal('a', 1, 'async'));
      await settle();
      s.kernel.release();
      s.agent.push(_signal('a', 1, 'settled'));
      s.agent.push(_turn('start'));
      await settle();
      expect(s.transcript.activeTurn, 'auto:1');
      s.agent.push(_turn('end'));
      await settle();
      expect(s.agent.requests('session/close'), hasLength(1));
      expect(s.kernel.health.status, KernelHealthStatus.idle);
    });

    test('a dispose waits for the window to close (T76③)', () async {
      final s = await _ready();
      s.agent.push(_turn('watch', on: true));
      s.agent.push(_signal('a', 1, 'async'));
      await settle();
      s.kernel.dispose();
      await settle();
      expect(s.agent.requests('session/close'), isEmpty);
      s.send('late'); // Nothing is taken up any more.
      await settle();
      expect(_prompts(s), isEmpty);
      s.agent.push(_signal('a', 1, 'settled'));
      s.agent.push(_turn('watch', on: false));
      await settle();
      expect(s.agent.requests('session/close'), hasLength(1));
      await s.kernel.stopped;
    });
  });

  group('thincoder host tools', () {
    tearDown(() async {
      HostTools.unregister('browser_click');
      await HostMcpServer.shutdown();
      HostMcpServer.exposedGroups = {'browser'};
    });

    /// A browser tool in the registry, as BrowserTools puts one there.
    void browserTool() => HostTools.register(
      HostTool(
        name: 'browser_click',
        description: 'Clicks an element of a shared tab.',
        inputSchema: const {'type': 'object'},
        kind: ToolKind.browser,
        group: 'browser',
        summary: (input, output) =>
            browserStepSummary('browser_click', input, output),
        run: (input, call) async => 'Clicked.',
      ),
    );

    /// The one server entry a session request carries.
    Map<String, Object?> serverOf(ThincoderMock agent, String method) {
      final params = agent.requests(method).single['params'] as Map;
      final servers = params['mcpServers'] as List;
      expect(servers, hasLength(1));
      return (servers.single as Map).cast<String, Object?>();
    }

    /// The entry as §4.2 has it: this endpoint, and a token of its own.
    void expectServer(Map<String, Object?> server) {
      expect(server['type'], 'http');
      expect(server['name'], 'baocode');
      expect(server['url'], HostMcpServer.url);
      final headers = (server['headers'] as List).cast<Map>();
      expect(headers.single['name'], 'Authorization');
      expect(
        headers.single['value'],
        matches(RegExp(r'^Bearer [A-Za-z0-9_-]{43}$')),
      );
      expect(server['_meta'], {'baocode.dev/trusted': true});
    }

    test('T11: a new, a loaded and a resumed session are given the host '
        "tools' server", () async {
      browserTool();
      final s = _Session(make: () => ThincoderMock(httpMcp: true));
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      expectServer(serverOf(s.agent, 'session/new'));

      // Out of view and back: the same session, resumed.
      s.kernel.release();
      await settle();
      s.kernel.prepare();
      await settle();
      expectServer(serverOf(s.agent, 'session/resume'));

      // A record's session: loaded.
      final t = _Session(
        context: KernelContext(
          cwd: '/project',
          resume: SessionRecord(
            id: '/project|3',
            title: 'From the terminal',
            updatedAt: DateTime.utc(2026, 10, 15),
            cwd: '/project',
          ),
        ),
        make: () => ThincoderMock(httpMcp: true),
      );
      addTearDown(t.dispose);
      t.kernel.prepare();
      await settle();
      expectServer(serverOf(t.agent, 'session/load'));
    });

    test('T12: an agent that does not take MCP servers is sent none, and '
        'the session goes on', () async {
      browserTool();
      final s = await _ready();
      expect(
        (s.agent.requests('session/new').single['params'] as Map)
            .containsKey('mcpServers'),
        isFalse,
      );
      s.send('hi');
      await s.agent.finished.future;
      expect(_prompts(s), ['hi']);
      expect(s.kernel.health.status, KernelHealthStatus.ready);
    });

    test('T13: with no tool to give, no server is sent', () async {
      final s = _Session(make: () => ThincoderMock(httpMcp: true));
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      expect(
        (s.agent.requests('session/new').single['params'] as Map)
            .containsKey('mcpServers'),
        isFalse,
      );
    });

    test('T14: the session over takes its token back', () async {
      browserTool();
      final s = _Session(make: () => ThincoderMock(httpMcp: true));
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      // The token the agent was given, as its request carries it.
      final entry = serverOf(s.agent, 'session/new');
      final token = (entry['headers'] as List)
          .single['value']
          .toString()
          .substring('Bearer '.length);
      final before = HostMcpServer.revocations;
      s.kernel.release();
      await settle();
      expect(HostMcpServer.revocations, before + 1);

      // The test binding would answer 400 to every request of its own.
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      final client = HttpClient();
      try {
        final request = await client.postUrl(Uri.parse(HostMcpServer.url!));
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $token',
        );
        request.write('{"jsonrpc":"2.0","id":1,"method":"tools/list"}');
        final response = await request.close();
        await response.drain<void>();
        expect(response.statusCode, 401);
      } finally {
        client.close(force: true);
      }
    });

    test('T15: a host tool call is the browser card its registry makes it, '
        'and any other tool stays as it was', () async {
      browserTool();
      final s = await _ready();
      s.agent.push(
        _update({
          'sessionUpdate': 'tool_call',
          'toolCallId': 't1',
          'title': 'baocode_browser_click',
          'kind': 'other',
          'status': 'in_progress',
          'rawInput': {'text': 'Sign in'},
        }),
      );
      await settle();
      final card = s.items<ToolCallItem>().single;
      expect(card.kind, ToolKind.browser);
      expect(card.tool, 'browser_click');
      expect(card.target, '“Sign in”');
      expect(card.input, {'text': 'Sign in'});

      // The card keeps the tool's own identity once the call is over, as
      // the Claude face's does (D10).
      s.agent.push(
        _update({
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 't1',
          'status': 'completed',
          'content': [
            {
              'type': 'content',
              'content': {'type': 'text', 'text': 'Clicked.'},
            },
          ],
        }),
      );
      await settle();
      final done = s.items<ToolCallItem>().single;
      expect(done.status, ToolStatus.succeeded);
      expect(done.kind, ToolKind.browser);
      expect(done.tool, 'browser_click');
      expect(done.input, {'text': 'Sign in'});
      expect(done.target, '“Sign in”');

      s.agent.push(
        _update({
          'sessionUpdate': 'tool_call',
          'toolCallId': 't2',
          'title': 'some_mcp_tool',
          'kind': 'other',
          'status': 'in_progress',
          'rawInput': <String, Object?>{},
        }),
      );
      await settle();
      final other = s.items<ToolCallItem>().last;
      expect(other.kind, ToolKind.other);
      expect(other.target, 'some_mcp_tool');
    });
  });

  group('thincoder connection', () {
    test('a request told to wait is not cut off by the connection timeout',
        () async {
      // The agent answers after 90 ms — well past the connection's 50 ms
      // default. Told to wait, the request is still there to take it.
      final frames = <Map<String, Object?>>[];
      final waiting = ThincoderConnection(
        frames.add,
        timeout: const Duration(milliseconds: 50),
      );
      final answer = waiting.request(
        'session/prompt',
        const {'sessionId': '/project|3'},
        ThincoderConnection.noTimeout,
      );
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 90), () {
          waiting.receive({
            'jsonrpc': '2.0',
            'id': frames.single['id'],
            'result': const {'stopReason': 'end_turn'},
          });
        }),
      );
      expect(await answer, {'stopReason': 'end_turn'});

      // The same request with nothing said is on the connection's clock:
      // no answer within its 50 ms is no answer.
      final bounded = ThincoderConnection(
        (_) {},
        timeout: const Duration(milliseconds: 50),
      );
      await expectLater(
        bounded.request('session/prompt', const {'sessionId': '/project|3'}),
        throwsA(
          isA<ThincoderRpcError>().having(
            (error) => error.message,
            'message',
            'session/prompt got no answer',
          ),
        ),
      );
    });
  });

  group('thincoder session ids', () {
    test('are the folder and the slot together, split at the last |', () {
      expect(ThincoderSessionRef.combine('/project', '3'), '/project|3');
      expect(ThincoderSessionRef.split('/project|3'), ('/project', '3'));
      expect(ThincoderSessionRef.cwdOf('/project|3'), '/project');
      expect(ThincoderSessionRef.slotOf('/project|3'), '3');
      expect(ThincoderSessionRef.split(r'C:\Users\me\project|12'), (
        r'C:\Users\me\project',
        '12',
      ));
      expect(ThincoderSessionRef.split('a|b|3'), ('a|b', '3'));
      expect(ThincoderSessionRef.split('3'), isNull);
      expect(ThincoderSessionRef.split('|3'), isNull);
      expect(ThincoderSessionRef.split('/project|'), isNull);
    });
  });

  group('thincoder locator', () {
    tearDown(() {
      ThincoderPathSetting.current = () => null;
      ThincoderLocator.candidatesOverride = null;
    });

    test('compares versions with the one it was checked against', () {
      expect(ThincoderLocator.verifiedVersion, '0.12.74');
      expect(ThincoderLocator.belowVerified('0.12.73'), isTrue);
      expect(ThincoderLocator.belowVerified('0.12.74'), isFalse);
      expect(ThincoderLocator.belowVerified('0.12.75'), isFalse);
      expect(ThincoderLocator.belowVerified('0.9.99'), isTrue);
      expect(ThincoderLocator.belowVerified('1.0.0'), isFalse);
      expect(
        ThincoderLocator.belowVerified(null),
        isFalse,
        reason: 'a version that is not said is not one that is too old',
      );
      expect(ThincoderLocator.parseVersion('thincoder v0.12.74\n'), '0.12.74');
      expect(ThincoderLocator.parseVersion('no version here'), isNull);
    });

    test('says where to look, the PATH first', () {
      if (Platform.isWindows) {
        const environment = {
          'PATH': r'C:\tools;D:\bin',
          'APPDATA': r'C:\Users\me\AppData\Roaming',
        };
        expect(
          ThincoderLocator.candidates(environment),
          contains(r'C:\tools\thincoder.cmd'),
        );
        expect(
          ThincoderLocator.candidates(environment),
          contains(r'D:\bin\thincoder.cmd'),
        );
        expect(
          ThincoderLocator.candidates(environment),
          contains(r'C:\Users\me\AppData\Roaming\npm\thincoder.cmd'),
        );
        return;
      }
      const environment = {'PATH': '/usr/bin:/opt/bin'};
      expect(
        ThincoderLocator.candidates(environment),
        contains('/usr/bin/thincoder'),
      );
      expect(
        ThincoderLocator.candidates(environment),
        contains('/opt/bin/thincoder'),
      );
    });

    test('none installed: how to install one', () async {
      ThincoderLocator.candidatesOverride = (_) => const [];
      await expectLater(
        ThincoderLocator.locate(const {'PATH': ''}),
        throwsA(
          isA<ThincoderUnavailable>()
              .having((error) => error.message, 'message',
                  'thincoder is not installed')
              .having((error) => error.detail, 'detail',
                  contains('npm install -g thincoder'))
              .having((error) => error.detail, 'detail',
                  contains('Node.js 24')),
        ),
      );
    });

    test('a path set that is not there: how to correct it', () async {
      ThincoderPathSetting.current = () => '/nowhere/thincoder';
      await expectLater(
        ThincoderLocator.locate(const {'PATH': ''}),
        throwsA(
          isA<ThincoderUnavailable>().having(
            (error) => error.detail,
            'detail',
            contains('Settings → General → thincoder'),
          ),
        ),
      );
    });

    test('the setting is read as a path, and only as one', () {
      expect(ThincoderPathSetting.settingKey, 'thincoder.path');
      expect(ThincoderPathSetting.parse('  /opt/thincoder  '), '/opt/thincoder');
      expect(ThincoderPathSetting.parse(''), isNull);
      expect(ThincoderPathSetting.parse(null), isNull);
      expect(ThincoderPathSetting.parse(7), isNull);
    });
  });

  group('the editor context on the host side', () {
    /// A chat session over a scripted thincoder agent, and that agent.
    ({ChatSession session, ThincoderMock agent}) chat() {
      final agent = ThincoderMock();
      late final KernelDescriptor descriptor;
      descriptor = KernelDescriptor(
        id: 'thincoder',
        label: 'thincoder',
        icon: Icons.smart_toy_outlined,
        description: '',
        create: (context) => ThincoderKernel(
          descriptor,
          context,
          start: (_) async => agent,
          launch: (cwd) async =>
              ThincoderLaunch(cwd: cwd, executable: '/mock/thincoder'),
        ),
      );
      final session = ChatSession(
        kernel: descriptor,
        kernels: [descriptor],
        historyCount: 0,
        kernelContext: const KernelContext(cwd: '/p'),
      );
      addTearDown(session.dispose);
      return (session: session, agent: agent);
    }

    /// What the agent was asked, in order.
    List<String> promptsOf(ThincoderMock agent) => [
      for (final request in agent.requests('session/prompt'))
        (((request['params'] as Map)['prompt'] as List).single as Map)['text']
            as String,
    ];

    /// The last message the conversation shows.
    UserMessageItem lastSent(ChatSession session) => [
      for (var i = 0; i < session.itemCount; i++)
        if (session.itemAt(i) case final UserMessageItem item) item,
    ].last;

    /// Makes [send] a turn, and waits for it to reach the agent.
    Future<void> sent(
      ChatSession session,
      ThincoderMock agent,
      void Function() send,
    ) async {
      final before = agent.requests('session/prompt').length;
      send();
      for (var i = 0; i < 60; i++) {
        if (agent.requests('session/prompt').length > before) break;
        await pumpEventQueue(times: 1);
      }
      await settle();
      expect(agent.requests('session/prompt'), hasLength(before + 1));
    }

    test('the setting off leaves the context out (T78)', () async {
      final (:session, :agent) = chat();
      final setting = EditorContextSetting.current;
      EditorContextSetting.current = () => false;
      addTearDown(() => EditorContextSetting.current = setting);
      await sent(
        session,
        agent,
        () => session.send(
          const ComposerMessage(text: 'look'),
          editor: () => const OpenEditor(
            '/p/a.dart',
            line: 10,
            selectedLines: (3, 5),
            selectedText: 'x\ny\nz',
          ),
        ),
      );
      expect(promptsOf(agent), ['look']);
      expect(lastSent(session).contexts, isEmpty);
    });

    test('with no file open the message is as it was (T79)', () async {
      final (:session, :agent) = chat();
      await sent(
        session,
        agent,
        () => session.send(
          const ComposerMessage(text: 'hi'),
          editor: () => null,
        ),
      );
      expect(promptsOf(agent), ['hi']);
      expect(lastSent(session).contexts, isEmpty);
    });

    test('a file open with no cursor is its path alone (T79②)', () async {
      final (:session, :agent) = chat();
      await sent(
        session,
        agent,
        () => session.send(
          const ComposerMessage(text: 'look'),
          editor: () => const OpenEditor('/p/a.dart'),
        ),
      );
      final prompt = promptsOf(agent).single;
      expect(
        prompt,
        startsWith(
          'look\n\n<system-reminder>The user has /p/a.dart open in the '
          'editor.',
        ),
      );
      expect(prompt, isNot(contains('cursor on line')));
      expect(prompt, isNot(contains('selected')));
      expect(lastSent(session).contexts.single.name, 'a.dart');
    });

    test('dismissed for a draft, a new editor brings it back (T81)', () async {
      final (:session, :agent) = chat();
      OpenEditor open = const OpenEditor('/p/a.dart', line: 10);
      await sent(
        session,
        agent,
        () => session.send(
          const ComposerMessage(text: 'one'),
          editor: () => open,
          editorContext: false,
        ),
      );
      expect(promptsOf(agent), ['one']);
      expect(lastSent(session).contexts, isEmpty);

      // The editor moves: the next message carries the new context again.
      open = const OpenEditor('/p/a.dart', line: 20);
      await sent(
        session,
        agent,
        () => session.send(
          const ComposerMessage(text: 'two'),
          editor: () => open,
        ),
      );
      expect(promptsOf(agent).last, contains('cursor on line 20'));
      expect(lastSent(session).contexts.single.line, 20);
    });

    test('the setting is on unless off, and its keys are in both ARBs (T82)',
        () {
      expect(EditorContextSetting.settingKey, 'chat.editorContext');
      expect(EditorContextSetting.off, isFalse);
      // Unset, or anything but false: on.
      expect(EditorContextSetting.enabled(null), isTrue);
      expect(EditorContextSetting.enabled(true), isTrue);
      expect(EditorContextSetting.enabled(false), isFalse);

      const keys = [
        'generalSettingsEditorContext',
        'generalSettingsEditorContextDescription',
        'editorContextLine',
        'editorContextLines',
      ];
      for (final name in ['app_en.arb', 'app_zh.arb']) {
        final text = File('lib/l10n/$name').readAsStringSync();
        for (final key in keys) {
          expect(text, contains('"$key"'), reason: '$name: $key');
        }
      }

    });
  });

  group('the files the agent reads and writes (F18)', () {
    /// A temp folder that goes when the test does.
    Directory temp() {
      final dir = Directory.systemTemp.createTempSync('thincoder-fs');
      addTearDown(() => dir.deleteSync(recursive: true));
      return dir;
    }

    /// An open workspace over [dir], its files this machine's own.
    IdeWorkspace spaceOver(Directory dir) {
      final space = IdeWorkspace(dir.path, files: IdeFileService(dir.path));
      addTearDown(space.dispose);
      return space;
    }

    /// A file opened in [space], with [buffer] unsaved when given.
    Future<({String path, IdeDocument doc})> opened(
      IdeWorkspace space, {
      String disk = 'on disk\n',
      String? buffer,
    }) async {
      final path = p.join(space.root, 'a.dart');
      File(path).writeAsStringSync(disk);
      await space.open(path);
      final doc = space.documentOf(path)!;
      if (buffer != null) doc.text = buffer;
      return (path: path, doc: doc);
    }

    /// What the agent wrote under [id]: its answer, waited for (a write to
    /// the disk takes its time).
    Future<Map<String, Object?>> answered(_Session s, Object? id) async {
      for (var i = 0; i < 400; i++) {
        final answer = s.agent.written
            .where((message) => message['id'] == id)
            .firstOrNull;
        if (answer != null) return answer;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      fail('no answer to $id');
    }

    void pushWrite(_Session s, Object? id, String path, String content) =>
        s.agent.push({
          'jsonrpc': '2.0',
          'id': id,
          'method': 'fs/write_text_file',
          'params': {'sessionId': '1', 'path': path, 'content': content},
        });

    void pushRead(_Session s, Object? id, String path) => s.agent.push({
      'jsonrpc': '2.0',
      'id': id,
      'method': 'fs/read_text_file',
      'params': {'sessionId': '1', 'path': path},
    });

    test('T83: a write over unsaved changes is refused, nothing written',
        () async {
      final dir = temp();
      final space = spaceOver(dir);
      final (:path, :doc) = await opened(space, buffer: 'my buffer\n');
      final log = _log();
      final s = _Session(
        context: KernelContext(cwd: dir.path, files: IdeKernelFiles()),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      pushWrite(s, 'fs-1', path, 'the agent\n');
      await settle();

      final answer = await answered(s, 'fs-1');
      expect((answer['error']! as Map)['code'], -32603);
      // The user's buffer and the disk are as they were; nothing says a
      // change was made.
      expect(doc.text, 'my buffer\n');
      expect(doc.savedText, 'on disk\n');
      expect(File(path).readAsStringSync(), 'on disk\n');
      expect(s.events.whereType<FileEdited>(), isEmpty);
      expect(
        s.items<NoticeItem>().where((item) => item.kind == NoticeKind.error),
        hasLength(1),
      );
      expect(_saidTimes(log, 'fs: a write was refused'), 1);
    });

    test('T84: the buffer and the agent text are shown side by side, read-only',
        () async {
      final dir = temp();
      final space = spaceOver(dir);
      final (:path, :doc) = await opened(space, buffer: 'my buffer\n');
      final s = _Session(
        context: KernelContext(cwd: dir.path, files: IdeKernelFiles()),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      pushWrite(s, 'fs-1', path, 'the agent\n');
      await settle();

      final diff = space.documents.singleWhere((doc) => doc.diff != null);
      expect(diff.readOnly, isTrue);
      expect(diff.label, "Agent's change (not applied)");
      expect(diff.text, 'the agent\n');
      expect(diff.diff!.text.value, 'my buffer\n');
      expect(doc.text, 'my buffer\n');
    });

    test('T85: a file not open is written, the disk as the agent said',
        () async {
      final dir = temp();
      final s = _Session(
        context: KernelContext(cwd: dir.path, files: IdeKernelFiles()),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      final path = p.join(dir.path, 'new.dart');
      pushWrite(s, 'fs-1', path, 'made\n');
      await settle();

      expect((await answered(s, 'fs-1'))['result'], <String, Object?>{});
      expect(File(path).readAsStringSync(), 'made\n');
      expect(s.events.whereType<FileEdited>(), hasLength(1));
    });

    test('T86: a path outside the project is refused, said and logged',
        () async {
      final dir = temp();
      final root = Directory(p.join(dir.path, 'project'))..createSync();
      final outside = p.join(dir.path, 'outside', 'x.txt');
      final log = _log();
      final s = _Session(
        context: KernelContext(cwd: root.path, files: IdeKernelFiles()),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      pushWrite(s, 'fs-1', outside, 'nope');
      await settle();

      expect(((await answered(s, 'fs-1'))['error']! as Map)['code'], -32602);
      expect(File(outside).existsSync(), isFalse);
      expect(
        s.items<NoticeItem>().where((item) => item.kind == NoticeKind.error),
        hasLength(1),
      );
      expect(_saidTimes(log, 'fs: refused a path outside the project'), 1);
    });

    test('T87: the kernel declares fs, the catalog does not', () async {
      final s = _Session(
        context: KernelContext(cwd: '/p', files: IdeKernelFiles()),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      expect(
        (s.agent.requests('initialize').single['params']
            as Map)['clientCapabilities'],
        ThincoderFiles.capabilities,
      );
      expect(ThincoderFiles.capabilities, {
        'fs': {'readTextFile': true, 'writeTextFile': true},
      });

      final catalogAgent = ThincoderMock(cwd: '/p');
      final catalog = ThincoderCatalog(connect: (cwd) async => catalogAgent);
      await catalog.sessionsIn('/p');
      expect(
        (catalogAgent.requests('initialize').single['params']
            as Map)['clientCapabilities'],
        <String, Object?>{},
      );
    });

    test('T88: a read is the editor buffer, unsaved changes and all',
        () async {
      final dir = temp();
      final space = spaceOver(dir);
      final (:path, :doc) = await opened(space, buffer: 'my buffer\n');
      final s = _Session(
        context: KernelContext(cwd: dir.path, files: IdeKernelFiles()),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      pushRead(s, 'fs-1', path);
      await settle();

      expect((await answered(s, 'fs-1'))['result'], {'content': 'my buffer\n'});
      expect(doc.text, 'my buffer\n');
    });

    test('T89: a clean open file is written, and its editor follows', () async {
      final dir = temp();
      final space = spaceOver(dir);
      final (:path, :doc) = await opened(space);
      final s = _Session(
        context: KernelContext(cwd: dir.path, files: IdeKernelFiles()),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      pushWrite(s, 'fs-1', path, 'new text\n');
      await settle();

      expect((await answered(s, 'fs-1'))['result'], <String, Object?>{});
      expect(doc.text, 'new text\n');
      expect(doc.savedText, 'new text\n');
      expect(doc.dirty, isFalse);
      expect(File(path).readAsStringSync(), 'new text\n');
      expect(s.events.whereType<FileEdited>(), hasLength(1));
    });

    test('T90: the change is the review surface\'s, with what it was',
        () async {
      final dir = temp();
      final space = spaceOver(dir);
      final (:path, :doc) = await opened(space);
      final s = _Session(
        context: KernelContext(cwd: dir.path, files: IdeKernelFiles()),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      // While a turn runs, the change is that turn's.
      s.agent.hold = Completer<void>();
      s.send('go');
      await settle();
      pushWrite(s, 'fs-1', path, 'new text\n');
      await answered(s, 'fs-1');
      await settle();

      final edited = s.events.whereType<FileEdited>().single;
      expect(edited.change.path, path);
      expect((edited.original! as OriginalText).text, 'on disk\n');
      expect(edited.turnId, 'turn-1');
      expect(doc.text, 'new text\n');

      s.agent.release();
      await settle();
    });

    test('T91: a method that is not one of the two is still -32601', () async {
      final s = _Session(
        context: KernelContext(cwd: '/p', files: IdeKernelFiles()),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      s.agent.push({
        'jsonrpc': '2.0',
        'id': 'fs-1',
        'method': 'fs/something_else',
        'params': const <String, Object?>{},
      });
      await settle();

      expect(((await answered(s, 'fs-1'))['error']! as Map)['code'], -32601);
      expect(s.events.whereType<FileEdited>(), isEmpty);
    });

    test('T92: a file that cannot be read says why, as -32603', () async {
      final s = _Session(
        context: KernelContext(cwd: '/p', files: _BinaryFiles()),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      pushRead(s, 'fs-1', '/p/a.bin');
      await settle();

      final error = (await answered(s, 'fs-1'))['error']! as Map;
      expect(error['code'], -32603);
      expect('${error['message']}', contains('Binary'));
      expect(s.events.whereType<FileEdited>(), isEmpty);
    });
  });

  group('the registered kernel', () {
    test('is named as the terminal\'s, and the scripted one stays out of the '
        'kernels on offer', () {
      // Which of them the app offers first cannot be read back here: the
      // whole suite runs over the scripted kernels and the registry's own
      // list is replaced with them (test/flutter_test_config.dart:39).
      expect(KernelRegistry.thincoder.id, 'thincoder');
      expect(MockKernels.thincoder.id, 'thincoder');
      expect(MockKernels.all, isNot(contains(MockKernels.thincoder)));
    });
  });

  group('the model picked while a turn runs (F21)', () {
    const sonnet = 'anthropic:claude-sonnet-5';

    _Session session({
      List<String>? models,
      bool configError = false,
      bool held = false,
    }) {
      final s = _Session(
        make: () => ThincoderMock(models: models, configError: configError)
          ..hold = held ? Completer<void>() : null,
      );
      addTearDown(s.dispose);
      return s;
    }

    test('a pick waits for the turn, then goes before the next (T100)',
        () async {
      final s = session(models: const [sonnet, 'b'], held: true);
      s.kernel.prepare();
      await settle();
      s.send('go');
      await settle();
      expect(s.transcript.activeTurn, 'turn-1');

      s.kernel.model.select('b');
      expect(s.agent.requests('session/set_config_option'), isEmpty);
      expect(s.kernel.pendingModel, 'b');
      expect(s.kernel.model.selected, sonnet);

      s.agent.release();
      await s.agent.finished.future;
      await settle();

      final writes = s.agent.requests('session/set_config_option');
      expect(writes, hasLength(1));
      expect(writes.single['params'], {
        'sessionId': '1',
        'configId': 'model',
        'value': 'b',
      });
      expect(s.kernel.model.selected, 'b');
      expect(s.kernel.pendingModel, isNull);
    });

    test('the last of two picks while the turn runs wins (T101①)',
        () async {
      final s = session(models: const [sonnet, 'b', 'c'], held: true);
      s.kernel.prepare();
      await settle();
      s.send('go');
      await settle();

      s.kernel.model.select('b');
      s.kernel.model.select('c');
      expect(s.kernel.pendingModel, 'c');
      expect(s.agent.requests('session/set_config_option'), isEmpty);

      s.agent.release();
      await s.agent.finished.future;
      await settle();

      final writes = s.agent.requests('session/set_config_option');
      expect(writes, hasLength(1));
      expect(writes.single['params'], {
        'sessionId': '1',
        'configId': 'model',
        'value': 'c',
      });
      expect(s.kernel.model.selected, 'c');
    });

    test('a pick made while a switch is out goes after its answer (T101②)',
        () async {
      final s = session(models: const [sonnet, 'b', 'c']);
      s.kernel.prepare();
      await settle();

      s.kernel.model.select('b');
      s.kernel.model.select('c');
      // The first write is out; the second waits for its answer.
      expect(s.agent.requests('session/set_config_option'), hasLength(1));
      expect(s.kernel.pendingModel, isNull);

      await settle();
      final writes = s.agent.requests('session/set_config_option');
      expect(writes, hasLength(2));
      expect(writes.first['params'], {
        'sessionId': '1',
        'configId': 'model',
        'value': 'b',
      });
      expect(writes.last['params'], {
        'sessionId': '1',
        'configId': 'model',
        'value': 'c',
      });
      expect(s.kernel.model.selected, 'c');
      expect(s.kernel.pendingModel, isNull);
    });

    test('a switch the agent refuses keeps the model shown and says so '
        '(T102)', () async {
      final s = session(
        models: const [sonnet, 'b'],
        configError: true,
        held: true,
      );
      s.kernel.prepare();
      await settle();
      s.send('go');
      await settle();

      s.kernel.model.select('b');
      s.agent.release();
      await s.agent.finished.future;
      await settle();

      expect(s.kernel.model.selected, sonnet);
      expect(s.kernel.pendingModel, isNull);
      final errors = [
        for (final item in s.items<NoticeItem>())
          if (item.kind == NoticeKind.error) item,
      ];
      expect(errors, hasLength(1));
      expect(errors.single.text, contains('not confirmed'));
      expect(s.kernel.health.status, KernelHealthStatus.ready);
    });

    test('a conversation closed forgets the model waiting (T103①)',
        () async {
      final s = session(models: const [sonnet, 'b'], held: true);
      s.kernel.prepare();
      await settle();
      s.send('go');
      await settle();

      s.kernel.model.select('b');
      expect(s.kernel.pendingModel, 'b');
      s.kernel.dispose();
      expect(s.kernel.pendingModel, isNull);

      s.agent.release();
      await settle();
      expect(s.agent.requests('session/set_config_option'), isEmpty);
    });

    test('a view left while waiting writes nothing at the end (T103②)',
        () async {
      final s = session(models: const [sonnet, 'b'], held: true);
      s.kernel.prepare();
      await settle();
      s.send('go');
      await settle();

      s.kernel.model.select('b');
      expect(s.kernel.pendingModel, 'b');
      s.kernel.release();
      s.agent.release();
      await settle();

      expect(s.kernel.pendingModel, isNull);
      expect(s.agent.requests('session/set_config_option'), isEmpty);
      expect(
        [
          for (final item in s.items<NoticeItem>())
            if (item.kind == NoticeKind.error) item,
        ],
        isEmpty,
      );
    });

    test('the waiting sentence is in both ARB files (T104)', () {
      for (final name in ['app_en.arb', 'app_zh.arb']) {
        final text = File('lib/l10n/$name').readAsStringSync();
        expect(text, contains('"modelsSwitchPending"'), reason: name);
      }
      expect(
        File('lib/l10n/app_zh.arb').readAsStringSync(),
        contains('回合结束后切换到 {model}'),
      );
    });

    test('the model in effect, picked with nothing waiting, writes nothing '
        '(T105)', () async {
      final s = session();
      s.kernel.prepare();
      await settle();
      expect(s.kernel.model.options.map((o) => o.id), [sonnet]);

      s.kernel.model.select(sonnet);
      await settle();

      expect(s.agent.requests('session/set_config_option'), isEmpty);
      expect(s.kernel.pendingModel, isNull);
      expect(s.items<NoticeItem>(), isEmpty);
    });
  });

  group('renaming and reverting (A1)', () {
    Future<_Session> ready({ThincoderMock Function()? make}) async {
      final s = _Session(make: make);
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      return s;
    }

    List<NoticeItem> errors(_Session s) => [
      for (final item in s.items<NoticeItem>()) if (item.kind == NoticeKind.error) item,
    ];

    test('G1: a title given with the session up goes out once (§3.4)',
        () async {
      final s = await ready();
      expect(s.kernel, isA<RenamesSession>());
      expect(s.kernel.sessionId, isNotNull);

      s.kernel.rename('New name');
      await settle();

      final writes = s.agent.requests('session/set_title');
      expect(writes, hasLength(1));
      expect(writes.single['params'], {'sessionId': '1', 'title': 'New name'});
      expect(s.kernel.pendingTitle, isNull);
      expect(errors(s), isEmpty);
    });

    test('G1: a title given before the session is made goes out once it is '
        '(§3.4)', () async {
      final s = _Session();
      addTearDown(s.dispose);
      s.kernel.rename('Named early');
      await settle();
      expect(s.agents, isEmpty);
      expect(s.kernel.pendingTitle, isNull);

      s.kernel.prepare();
      await settle();

      final writes = s.agent.requests('session/set_title');
      expect(writes, hasLength(1));
      expect(writes.single['params'], {'sessionId': '1', 'title': 'Named early'});
      expect(s.kernel.pendingTitle, isNull);
    });

    test('G1c: a title with no connection: said, not dropped (§3.5)', () async {
      final s = await ready();
      s.kernel.release();
      await settle();
      expect(s.kernel.canRevertNow, isFalse);
      s.kernel.rename('Renamed');
      await settle();
      expect(s.agent.requests('session/set_title'), isEmpty);
      expect(errors(s).single.text, contains('not confirmed'));
    });

    test('G1b: a title picked while a turn runs waits for its end, last wins '
        '(§3.5)', () async {
      final s = await ready(
        make: () => ThincoderMock(serialInbound: true)
          ..hold = Completer<void>(),
      );
      s.send('go');
      await settle();
      expect(s.transcript.activeTurn, 'turn-1');

      s.kernel.rename('a');
      s.kernel.rename('b');
      expect(s.agent.requests('session/set_title'), isEmpty);
      expect(s.kernel.pendingTitle, 'b');
      expect(s.kernel.canRevertNow, isFalse);

      s.agent.release();
      await s.agent.finished.future;
      await settle();

      final writes = s.agent.requests('session/set_title');
      expect(writes, hasLength(1));
      expect(writes.single['params'], {'sessionId': '1', 'title': 'b'});
      expect(s.kernel.pendingTitle, isNull);
      expect(s.kernel.canRevertNow, isTrue);
    });

    test('G1b: a title the agent refuses at the turn\'s end says so once '
        '(§3.5)', () async {
      final s = await ready(
        make: () => ThincoderMock(serialInbound: true)
          ..hold = Completer<void>()
          ..titleError = true,
      );
      s.send('go');
      await settle();
      s.kernel.rename('a');
      s.kernel.rename('b');

      s.agent.release();
      await s.agent.finished.future;
      await settle();

      final writes = s.agent.requests('session/set_title');
      expect(writes, hasLength(1));
      expect(writes.single['params'], {'sessionId': '1', 'title': 'b'});
      expect(s.kernel.pendingTitle, isNull);
      expect(errors(s), hasLength(1));
      expect(errors(s).single.text, contains('not confirmed'));
    });

    test('G1b: picked again while a write is out, the last goes after it '
        '(§3.5)', () async {
      final s = await ready();
      s.kernel.rename('a');
      expect(s.agent.requests('session/set_title'), hasLength(1));

      s.kernel.rename('b');
      expect(s.kernel.pendingTitle, 'b');
      await settle();

      final writes = s.agent.requests('session/set_title');
      expect(writes, hasLength(2));
      expect(writes.first['params'], {'sessionId': '1', 'title': 'a'});
      expect(writes.last['params'], {'sessionId': '1', 'title': 'b'});
      expect(s.kernel.pendingTitle, isNull);
    });

    test('G1b: picked while a failing write is out, the last still goes '
        '(§3.5)', () async {
      final s = await ready(
        make: () => ThincoderMock(serialInbound: true)..titleError = true,
      );
      s.kernel.rename('a');
      s.kernel.rename('b');
      await settle();
      expect(s.agent.requests('session/set_title').map((w) => w['params']), [
        {'sessionId': '1', 'title': 'a'},
        {'sessionId': '1', 'title': 'b'},
      ]);
      expect(errors(s), hasLength(1));
      expect(s.kernel.pendingTitle, isNull);
    });

    test('G4: a title the agent refuses is one error, nothing left pending',
        () async {
      final s = await ready(
        make: () => ThincoderMock(serialInbound: true)..titleError = true,
      );
      s.kernel.rename('a');
      await settle();

      expect(s.agent.requests('session/set_title'), hasLength(1));
      expect(s.kernel.pendingTitle, isNull);
      expect(errors(s), hasLength(1));
      expect(errors(s).single.text, contains('not confirmed'));
    });

    test('G5: the plan is asked for with the turn, and carried out with it '
        '(§3.1)', () async {
      final s = await ready(
        make: () => ThincoderMock(serialInbound: true)
          ..revertPlan = const {
            'files': [
              {'path': '/p/a.txt', 'displayPath': 'a.txt', 'action': 'restore'},
              {'path': '/p/b.txt', 'displayPath': 'b.txt', 'action': 'restore'},
              {'path': '/p/c.txt', 'displayPath': 'c.txt', 'action': 'delete'},
            ],
            'skipped': [], 'unrevertable': [],
          },
      );
      final plan = await s.kernel.revertPlan(sinceTurn: 'turn-9');
      expect(s.agent.requests('session/revert'), hasLength(1));
      expect(s.events.whereType<ChangesReverted>(), isEmpty);
      expect(plan.files.map((f) => (f.path, f.displayPath, f.action)), [
        ('/p/a.txt', 'a.txt', RevertAction.restore),
        ('/p/b.txt', 'b.txt', RevertAction.restore),
        ('/p/c.txt', 'c.txt', RevertAction.delete),
      ]);

      final outcome = await s.kernel.applyRevert(sinceTurn: 'turn-9');
      final writes = s.agent.requests('session/revert');
      expect(writes, hasLength(2));
      expect(writes.first['params'],
          {'sessionId': '1', 'sinceTurn': 'turn-9', 'dryRun': true});
      expect(writes.last['params'],
          {'sessionId': '1', 'sinceTurn': 'turn-9', 'dryRun': false});
      expect(outcome.files, hasLength(3));
      expect(s.items<NoticeItem>(), isEmpty); // The summary is the host's (§9).
      expect(s.events.whereType<ChangesReverted>(), hasLength(1));
    });

    test('G6: a file changed since the turn is skipped, the host touching '
        'nothing (D-SG3)', () async {
      final s = await ready(
        make: () => ThincoderMock(serialInbound: true)
          ..revertPlan = const {
            'files': [], 'unrevertable': [],
            'skipped': [
              {'path': '/p/b.txt', 'displayPath': 'b.txt', 'reason': 'changed'},
            ],
          },
      );
      final outcome = await s.kernel.applyRevert(sinceTurn: 'turn-1');

      expect(outcome.skipped, hasLength(1));
      expect((outcome.skipped.single.path, outcome.skipped.single.displayPath),
          ('/p/b.txt', 'b.txt'));
      expect(outcome.skipped.single.reason, 'changed');
      expect(outcome.files, isEmpty);
      expect(s.events.whereType<FileEdited>(), isEmpty);
      expect(s.events.whereType<ChangesReverted>(), isEmpty);
      expect(s.transcript.revertedSeq, -1);
    });

    test('G7: oversize and evicted are listed as unrevertable, files kept',
        () async {
      final s = await ready(
        make: () => ThincoderMock(serialInbound: true)
          ..revertPlan = const {
            'files': [
              {'path': '/p/a.txt', 'displayPath': 'a.txt', 'action': 'restore'},
            ],
            'skipped': [], 'unrevertable': [
              {'path': '/p/c.bin', 'displayPath': 'c.bin', 'reason': 'oversize'},
              {'path': '/p/d.txt', 'displayPath': 'd.txt', 'reason': 'evicted'},
            ],
          },
      );
      final outcome = await s.kernel.applyRevert(sinceTurn: 'turn-1');

      expect(outcome.files.single.action, RevertAction.restore);
      expect(outcome.unrevertable.map((item) => item.reason),
          ['oversize', 'evicted']);
      expect(outcome.unrevertable.map((item) => item.displayPath),
          ['c.bin', 'd.txt']);
    });

    test('G8: a turn the kernel does not know is one error, no revert',
        () async {
      final s = await ready(
        make: () => ThincoderMock(serialInbound: true)..revertUnknown = true,
      );
      await expectLater(s.kernel.revertPlan(sinceTurn: 'nope'),
          throwsA(isA<ThincoderRpcError>()));

      expect(s.agent.requests('session/revert'), hasLength(1));
      expect(errors(s), hasLength(1));
      expect(errors(s).single.text, contains('Could not revert'));
      expect(s.events.whereType<ChangesReverted>(), isEmpty);
    });

    test('G11: a partly successful revert lists what it restored and what '
        'failed (D-SG11)', () async {
      final s = await ready(
        make: () => ThincoderMock(serialInbound: true)
          ..revertApply = const {
            'files': [
              {'path': '/p/a.txt', 'displayPath': 'a.txt', 'action': 'restore'},
            ],
            'skipped': [], 'unrevertable': [],
            'failed': [
              {'path': '/p/b.txt', 'displayPath': 'b.txt', 'error': 'EACCES'},
            ],
          },
      );
      final outcome = await s.kernel.applyRevert(sinceTurn: 'turn-1');

      expect(outcome.files, hasLength(1));
      expect(outcome.files.single.path, '/p/a.txt');
      expect(outcome.failed, hasLength(1));
      expect(outcome.failed.single.path, '/p/b.txt');
      expect(outcome.failed.single.error, 'EACCES');
      expect(s.events.whereType<ChangesReverted>(), hasLength(1));
    });

    test('an automatic turn reverts from the prompt turn it belongs to '
        '(§3.3)', () async {
      final s = await ready();
      s.send('go');
      await s.agent.finished.future;
      await settle();

      s.agent.push(_turn('start'));
      await settle();
      expect(s.transcript.activeTurn, 'auto:1');

      await s.kernel.revertPlan(sinceTurn: 'auto:1');
      expect(
        (s.agent.requests('session/revert').single['params'] as Map)['sinceTurn'],
        'turn-1',
      );

      s.agent.push(_turn('end', ok: true));
      await settle();
    });
  });

  group('rewinding (A2)', () {
    Future<_Session> ready({ThincoderMock Function()? make}) async {
      final s = _Session(make: make);
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      return s;
    }

    List<NoticeItem> errors(_Session s) => [
      for (final item in s.items<NoticeItem>())
        if (item.kind == NoticeKind.error) item,
    ];

    test('T1: a rewind names the turn alone, and the host is cut there '
        '(§3.3)', () async {
      final s = await ready();
      final rewound = await s.kernel.rewind(
          itemId: 't-2', index: 3, turns: 2, lastSeen: 't-3');
      expect(rewound, isTrue);
      final writes = s.agent.requests('session/rewind');
      expect(writes, hasLength(1));
      expect(writes.single['params'], {'sessionId': '1', 'turnId': 't-2'});
      expect(s.agent.requests('session/prompt'), isEmpty);
      expect(s.events.whereType<Rewound>(), hasLength(1));
      expect(errors(s), isEmpty);
    });

    test('T5: a rewind drops what waited behind the cut, unsent (§3.3)',
        () async {
      final s = await ready(
          make: () => ThincoderMock(serialInbound: true)
            ..hold = Completer<void>());
      s.send('go');
      await settle();
      expect(s.transcript.activeTurn, 'turn-1');

      s.send('later', id: 'turn-2'); // A turn runs: it waits its own.
      await settle();
      expect(s.transcript.queued.map((q) => q.$1), ['turn-2']);

      expect(await s.kernel.rewind(itemId: 'turn-1', index: 0, turns: 1),
          isTrue);
      await settle();
      expect(s.transcript.queued, isEmpty); // Dropped, not sent.

      s.agent.release();
      await s.agent.finished.future;
      await settle();

      expect(s.agent.requests('session/prompt'), hasLength(1));
      expect(s.shown, isNot(contains('user: later')));
    });

    test('T2: a turn of another run is turned down, with one notice '
        '(D-SG24)', () async {
      final s = await ready(
          make: () => ThincoderMock(serialInbound: true)..rewindUnknown = true);
      final rewound = await s.kernel.rewind(itemId: 'old', index: 0, turns: 1);
      expect(rewound, isFalse);
      expect(s.agent.requests('session/rewind'), hasLength(1));
      expect(errors(s).single.text, englishLocalizations.rewindNotInThisRun);
      expect(s.agent.requests('session/prompt'), isEmpty);
      expect(s.transcript.length, 1); // The notice alone: nothing moved.
    });

    test('T4: a turn under way is turned down with its own notice (§3.3)',
        () async {
      final s = await ready(
          make: () => ThincoderMock(serialInbound: true)..rewindBusy = true);
      final rewound = await s.kernel.rewind(itemId: 't-1', index: 0, turns: 1);
      expect(rewound, isFalse);
      expect(errors(s).single.text, englishLocalizations.rewindTurnInFlight);
      expect(s.transcript.length, 1);
    });

    test('T3: an edit stops, rewinds, and sends only once it went back',
        () async {
      Future<(ChatSession, _EditKernel)> open() async {
        final kernel = _EditKernel();
        final descriptor = KernelDescriptor(
            id: 'edit', label: 'edit', icon: Icons.smart_toy_outlined,
            description: 'Edits for the test', create: (_) => kernel);
        final session = ChatSession(
            kernel: descriptor, kernels: [descriptor], historyCount: 0);
        addTearDown(session.dispose);
        session.send(const ComposerMessage(text: 'first'));
        await settle();
        return (session, kernel);
      }

      final (rewound, kernel) = await open();
      expect(rewound.canEditMessages, isTrue);
      rewound.editMessage(0, const ComposerMessage(text: 'second'));
      expect(kernel.calls, ['send', 'stop', 'rewind']);
      kernel.rewinding!.complete(true);
      await settle();
      expect(kernel.calls, ['send', 'stop', 'rewind', 'send']);

      final (turnedDown, refused) = await open();
      turnedDown.editMessage(0, const ComposerMessage(text: 'second'));
      expect(refused.calls, ['send', 'stop', 'rewind']);
      refused.rewinding!.complete(false);
      await settle();
      expect(refused.calls, ['send', 'stop', 'rewind']);
    });
  });

  group('responsiveness (F22)', () {
    late Directory logs;

    setUp(() {
      logs = Directory.systemTemp.createTempSync('thincoder-timing');
      EventLog.current = EventLog(logs.path);
    });

    tearDown(() {
      EventLog.current = null;
      if (logs.existsSync()) logs.deleteSync(recursive: true);
    });

    /// What the terminal's log says, the lines with [text].
    List<String> logged(String text) {
      final file = File(p.join(logs.path, 'events.log'));
      if (!file.existsSync()) return const [];
      return [
        for (final line in file.readAsLinesSync())
          if (line.contains(text)) line,
      ];
    }

    /// A session over a kernel whose start waits for [gate] — or fails — as
    /// the wait between a view opening and its agent being there (§25.11).
    (ChatSession, List<ThincoderMock>) slow({
      Completer<void>? gate,
      bool fail = false,
    }) {
      final agents = <ThincoderMock>[];
      late final KernelDescriptor descriptor;
      descriptor = KernelDescriptor(
        id: 'thincoder',
        label: 'thincoder',
        icon: Icons.smart_toy_outlined,
        description: 'the test’s',
        create: (_) => ThincoderKernel(
          descriptor,
          const KernelContext(cwd: '/project'),
          start: (_) async {
            if (fail) {
              throw const ThincoderUnavailable('thincoder is not installed');
            }
            final agent = ThincoderMock(serialInbound: true);
            agents.add(agent);
            if (gate != null) await gate.future;
            return agent;
          },
          launch: (cwd) async =>
              ThincoderLaunch(cwd: cwd, executable: '/mock/thincoder'),
        ),
      );
      final session = ChatSession(
        kernel: descriptor,
        kernels: [descriptor],
        historyCount: 0,
      );
      addTearDown(session.dispose);
      return (session, agents);
    }

    /// A pool of the test's, its processes scripted agents — behind [gate]
    /// where the test wants the start to take its time; put back in `finally`
    /// — that is, [addTearDown].
    ThincoderWarm pool(List<ThincoderMock> agents, {Completer<void>? gate}) {
      final previous = ThincoderWarm.instance;
      addTearDown(() => ThincoderWarm.instance = previous);
      return ThincoderWarm.instance = ThincoderWarm(
        start: (_) async {
          final agent = ThincoderMock(serialInbound: true);
          agents.add(agent);
          if (gate != null) await gate.future;
          return agent;
        },
        launch: (cwd) async =>
            ThincoderLaunch(cwd: cwd, executable: '/mock/thincoder'),
        schedule: (_, _) => _NoTimer(),
      );
    }

    test('T107①: a session being started takes the message, and says so '
        '(§25.3)', () async {
      final gate = Completer<void>();
      final (session, agents) = slow(gate: gate);

      session.attach();
      await settle();
      expect(session.health.status, KernelHealthStatus.starting);
      expect(session.canSend, isTrue);
      expect(logged('timing: open'), hasLength(1));
      expect(logged('timing: input-ready'), hasLength(1));

      session.send(const ComposerMessage(text: 'hi'));
      await settle();
      // Taken, not dropped: the turn is open, nothing written to the agent.
      expect(session.isStreaming, isTrue);
      expect(agents.single.requests('session/prompt'), isEmpty);

      List<ChatItem> items() => [
        for (var i = 0; i < session.itemCount; i++) session.itemAt(i),
      ];
      // The user's own line first, then the wait, said while it lasts.
      expect(items().first, isA<UserMessageItem>());
      final waiting = items().whereType<NoticeItem>().single;
      expect(waiting.kind, NoticeKind.warning);
      expect(waiting.text, 'thincoder is starting…');

      gate.complete();
      await settle();
      expect(session.health.status, KernelHealthStatus.ready);
      expect(agents.single.requests('session/prompt'), hasLength(1));

      // The waiting line went with the start; the user's line stays ahead of
      // the first frame that answered it.
      expect(items().whereType<NoticeItem>(), isEmpty);
      expect(items().first, isA<UserMessageItem>());
      expect(
        items().indexWhere(
          (item) => item is AssistantTextItem || item is ToolCallItem,
        ),
        greaterThan(0),
      );
      expect(logged('timing: warm miss'), hasLength(1));
      expect(logged('timing: session-new'), hasLength(1));
      expect(logged('timing: first-frame'), hasLength(1));
    });

    test('T107②: a start that fails ends the turn, once, and leaves none open '
        '(§25.11)', () async {
      final kernel = ThincoderKernel(
        _descriptor,
        const KernelContext(cwd: '/project'),
        start: (_) async =>
            throw const ThincoderUnavailable('thincoder is not installed'),
        launch: (cwd) async =>
            ThincoderLaunch(cwd: cwd, executable: '/mock/thincoder'),
      );
      final events = <KernelEvent>[];
      final subscription = kernel.events.listen(events.add);
      addTearDown(() {
        unawaited(subscription.cancel());
        kernel.dispose();
      });

      kernel.send(const KernelTurn(id: 'turn-1', text: 'hi'));
      await settle();

      final shown = [
        for (final event in events)
          if (event case ItemUpserted(:final item)) item,
      ];
      expect(
        shown
            .whereType<NoticeItem>()
            .where((item) => item.kind == NoticeKind.error),
        hasLength(1),
      );
      expect(events.whereType<TurnEnded>().single.interrupted, isTrue);
      expect(kernel.health.status, KernelHealthStatus.failed);
      // The waiting line went with the failure: nothing says it still starts.
      expect(
        [
          for (final event in events)
            if (event case ItemRemoved(:final id)) id,
        ],
        contains('thincoder:starting'),
      );
    });

    test('T108: a process made warm is taken over whole — one start, one '
        'handshake (§25.2)', () async {
      final warmed = <ThincoderMock>[];
      final gate = Completer<void>();
      final instance = pool(warmed, gate: gate);
      // As the app opens a project: warmed and not waited for, the session
      // created by the same action opening at once.
      unawaited(instance.warm('/project', files: true));
      final s = _Session(
        context: KernelContext(cwd: '/project', files: _BinaryFiles()),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      // The start under way is waited for, not raced: nothing else was made.
      expect(s.agents, isEmpty);
      gate.complete();
      await settle();

      // No start of its own, and no second handshake: the pool's process is
      // the session's — same folder, same capability bit.
      expect(s.agents, isEmpty);
      expect(warmed, hasLength(1));
      expect(warmed.single.requests('initialize'), hasLength(1));
      expect(warmed.single.requests('session/new'), hasLength(1));
      expect(s.kernel.health.status, KernelHealthStatus.ready);
      expect(s.kernel.sessionId, isNotNull);
      expect(logged('warm: held'), hasLength(1));
      expect(logged('timing: warm hit'), hasLength(1));
      expect(logged('timing: warm miss'), isEmpty);
    });

    test('T108②: a process held for another handshake is not taken (§25.2)',
        () async {
      final warmed = <ThincoderMock>[];
      final instance = pool(warmed);
      await instance.warm('/project', files: true);

      // This kernel has no host files: its key is the other bit.
      final s = _Session();
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      expect(warmed, hasLength(1));
      expect(s.agents, hasLength(1));
      expect(s.kernel.health.status, KernelHealthStatus.ready);
      expect(logged('timing: warm miss'), hasLength(1));
    });

    test('T110: the first content frame is what is read, the state frames are '
        'not (§25.6)', () async {
      final s = _Session(
        make: () => ThincoderMock(
          serialInbound: true,
          turn: const [
            {
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': 'Here.'},
            },
          ],
        )..hold = Completer<void>(),
      );
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();

      s.send('go');
      await settle();
      // The turn is out; the agent held before its first frame.
      s.agent.push(_update({
        'sessionUpdate': 'usage_update',
        'used': 10,
        'size': 100,
      }));
      await settle();
      expect(logged('timing: first-frame'), isEmpty);

      s.agent.release();
      await settle();

      final first = logged('timing: first-frame');
      expect(first, hasLength(1));
      final read = RegExp(r'first-frame (\d+)ms').firstMatch(first.single)!.group(1)!;
      expect(int.parse(read), lessThanOrEqualTo(600));
    });

    test('T111: switching back to a kernel kept warm starts nothing (§25.5)',
        () async {
      final starts = <String, List<ThincoderMock>>{};
      KernelDescriptor describe(String id) {
        late final KernelDescriptor descriptor;
        descriptor = KernelDescriptor(
          id: id,
          label: id,
          icon: Icons.smart_toy_outlined,
          description: 'the test’s',
          create: (_) => ThincoderKernel(
            descriptor,
            const KernelContext(cwd: '/project'),
            start: (_) async {
              final agent = ThincoderMock(serialInbound: true);
              (starts[id] ??= []).add(agent);
              return agent;
            },
            launch: (cwd) async =>
                ThincoderLaunch(cwd: cwd, executable: '/mock/thincoder'),
          ),
        );
        return descriptor;
      }

      final a = describe('a'), b = describe('b');
      final session = ChatSession(kernel: a, kernels: [a, b], historyCount: 0);
      addTearDown(session.dispose);
      session.attach();
      await settle();
      expect(starts['a'], hasLength(1));

      session.setKernel(b);
      await settle();
      expect(starts['b'], hasLength(1));

      session.setKernel(a);
      await settle();

      // Back on a: no new process, no new handshake, no new session.
      expect(starts['a'], hasLength(1));
      expect(starts['a']!.single.requests('initialize'), hasLength(1));
      expect(starts['a']!.single.requests('session/new'), hasLength(1));
      // One line each way (§25.5).
      expect(logged('timing: kernel-switch'), hasLength(2));
    });
  });

  test('T126: a saved config shows in a new session after the restart the '
      'page offers (§27.6)', () async {
    final directory = await Directory.systemTemp.createTemp('thincoder-model');
    addTearDown(() async {
      if (directory.existsSync()) await directory.delete(recursive: true);
    });
    final file = File(p.join(directory.path, 'config.json'));
    final store = ThincoderConfigStore(file: file);

    // The scripted agent reads the file where the CLI would — the offline
    // stand-in for a real one (U14): a session started after a save reports
    // what the save wrote.
    ThincoderMock started() {
      final raw = file.existsSync()
          ? jsonDecode(file.readAsStringSync()) as Map<String, Object?>
          : const <String, Object?>{};
      final model = raw['defaultModel'] as String?;
      return ThincoderMock(
        serialInbound: true,
        currentModel: model,
        models: model == null ? null : [model],
      );
    }

    final s = _Session(make: started);
    addTearDown(s.dispose);
    s.kernel.prepare();
    await settle();

    // Nothing configured for us yet: the agent reports a model of its own,
    // and it is the only candidate.
    expect(s.agents, hasLength(1));
    expect(s.kernel.model.selected, 'anthropic:claude-sonnet-5');
    expect(s.kernel.model.options.map((option) => option.id), [
      'anthropic:claude-sonnet-5',
    ]);

    // The page's save (§27.3): the provider, and the model it starts with.
    final saved = await store.saveProvider(
      name: 'openai',
      baseURL: 'https://api.example.com/v1',
      apiKey: 'sk-test-1',
      model: 'gpt-5',
    );
    expect(saved, isA<ThincoderSaved>());

    // The page's button (§27.6): the kernel's own restart, which
    // `ChatSession.restart` calls (`chat_session.dart:398`) — a new
    // process, a new session, the file read again.
    s.kernel.restart();
    await settle();

    expect(s.agents, hasLength(2));
    expect(s.agents.last.requests('session/new'), hasLength(1));
    final model = s.agents.last.configOptions.firstWhere(
      (option) => option['id'] == 'model',
    );
    expect(model['currentValue'], 'openai:gpt-5');
    expect(model['options'], [
      {'value': 'openai:gpt-5', 'name': 'openai:gpt-5'},
    ]);
    // And what the model pill reads (`thincoder_choices.dart:46-53`): the
    // value and the candidate are the new session's.
    expect(s.kernel.model.selected, 'openai:gpt-5');
    expect(s.kernel.model.options.map((option) => option.id), [
      'openai:gpt-5',
    ]);
  });

  group('the runtime the distribution carries (F23, §26)', () {
    late Directory root;
    late DataDirectory previousData;
    late Map<String, String> environment;

    setUp(() {
      root = Directory.systemTemp.createTempSync('thincoder-runtime');
      EventLog.current = EventLog(p.join(root.path, 'logs'));
      previousData = DataDirectory.current;
      DataDirectory.current = DataDirectory(p.join(root.path, 'data'));
      environment = {'PATH': '', 'HOME': root.path};
      ClaudeEnvironment.use(environment);
    });

    tearDown(() {
      DataDirectory.current = previousData;
      EventLog.current = null;
      ThincoderPathSetting.current = () => null;
      ThincoderLocator.candidatesOverride = null;
      ThincoderLocator.executableDirectoryOverride = null;
      ThincoderLocator.isMacOverride = null;
      ClaudeEnvironment.use(null);
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    /// The runtime a distribution carries, beside [app]; answers the CLI's
    /// entry file.
    String putRuntime(String app) {
      final runtime = p.join(app, 'runtime');
      final entry = File(p.join(runtime, 'thincoder', 'bin', 'thincoder.cjs'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('');
      File(p.join(runtime, 'node', 'node.exe'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('');
      return entry.path;
    }

    /// What the terminal's log says, the lines with [text].
    List<String> logged(String text) {
      final file = File(p.join(root.path, 'logs', 'events.log'));
      if (!file.existsSync()) return const [];
      return [
        for (final line in file.readAsLinesSync())
          if (line.contains(text)) line,
      ];
    }

    /// A kernel whose start records what the locator handed it, a scripted
    /// agent standing in for the process it would have started.
    Future<List<ThincoderLaunch>> started() async {
      final launches = <ThincoderLaunch>[];
      final kernel = ThincoderKernel(
        _descriptor,
        const KernelContext(cwd: '/project'),
        start: (launch) async {
          launches.add(launch);
          return ThincoderMock(serialInbound: true);
        },
      );
      addTearDown(kernel.dispose);
      kernel.prepare();
      await settle();
      return launches;
    }

    test('T113 / T115a: the kernel starts the runtime the app carries, and '
        'the log says so', () async {
      final app = p.join(root.path, 'app');
      Directory(app).createSync(recursive: true);
      final entry = putRuntime(app);
      ThincoderLocator.executableDirectoryOverride = app;
      ThincoderLocator.isMacOverride = false;
      var asked = 0;
      ThincoderLocator.candidatesOverride = (_) {
        asked++;
        return const [];
      };

      final launches = await started();

      expect(launches, hasLength(1));
      expect(p.basename(launches.single.executable), 'node.exe');
      expect(launches.single.arguments, [entry, 'acp']);
      expect(
        launches.single.environment[ThincoderLocator.configDirVariable],
        DataDirectory.current.thincoderDataDir,
      );
      // What Settings → Models (thincoder) resolves its file from, the
      // same environment: the page writes the file the CLI reads.
      expect(
        await ThincoderLocator.environment(),
        equals(launches.single.environment),
      );
      expect(asked, 0, reason: 'the PATH is not looked at');
      expect(logged('launch: builtin'), [contains(entry)]);
    });

    test('T112 / T115b: with no runtime the kernel hands over the environment '
        'it always did', () async {
      final app = p.join(root.path, 'app');
      Directory(app).createSync(recursive: true);
      ThincoderLocator.executableDirectoryOverride = app;
      ThincoderLocator.isMacOverride = false;
      final installed = File(p.join(root.path, 'bin', 'thincoder'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('');
      ThincoderLocator.candidatesOverride = (_) => [installed.path];

      final launches = await started();

      expect(launches, hasLength(1));
      expect(launches.single.executable, installed.path);
      expect(launches.single.environment, equals(environment));
      expect(
        launches.single.environment.containsKey(
          ThincoderLocator.configDirVariable,
        ),
        isFalse,
      );
      expect(logged('launch: path'), [contains(installed.path)]);
    });
  });

  group('a rename the kernel confirms (F25, §28)', () {
    /// A workspace with a thincoder agent opened on a scripted agent: the
    /// thread, the kernel it made, the agents it started and its events.
    ({
      Workspace workspace,
      AgentThread thread,
      ThincoderKernel kernel,
      List<ThincoderMock> agents,
      List<KernelEvent> events,
    })
    open({bool titleError = false}) {
      final events = <KernelEvent>[];
      final agents = <ThincoderMock>[];
      late final KernelDescriptor descriptor;
      late final ThincoderKernel kernel;
      descriptor = KernelDescriptor(
        id: 'thincoder',
        label: 'thincoder',
        icon: Icons.smart_toy_outlined,
        description: 'The agent of the user’s terminal',
        create: (context) {
          kernel = ThincoderKernel(
            descriptor,
            context,
            start: (_) async {
              final agent = ThincoderMock(serialInbound: true)
                ..titleError = titleError;
              agents.add(agent);
              return agent;
            },
            launch: (cwd) async =>
                ThincoderLaunch(cwd: cwd, executable: '/mock/thincoder'),
          );
          kernel.events.listen(events.add);
          return kernel;
        },
      );
      final workspace = Workspace(
        projects: const [Project('project', '/project')],
        kernels: [descriptor],
        preferences: MemoryPreferenceStore(),
        drafts: MemoryPreferenceStore(),
      );
      addTearDown(workspace.dispose);
      final thread = workspace.create(project: workspace.projects.single);
      return (
        workspace: workspace,
        thread: thread,
        kernel: kernel,
        agents: agents,
        events: events,
      );
    }

    List<NoticeItem> errors(AgentThread thread) => [
      for (var i = 0; i < thread.session.itemCount; i++)
        if (thread.session.itemAt(i) case final NoticeItem item
            when item.kind == NoticeKind.error)
          item,
    ];

    test('T131: the agent confirms a rename, and the list follows it '
        '(F25①, §28.3)', () async {
      final s = open();
      s.thread.session.attach();
      await settle();
      expect(s.kernel.renameConfirmed, isTrue);
      expect(s.thread.title, 'New Chat');

      expect(await s.workspace.rename(s.thread, 'A'), isTrue);
      // Not changed ahead of the agent: the answer is what names it (§28.4).
      expect(s.thread.title, 'New Chat');
      await settle();

      final renamed = s.events.whereType<SessionRenamed>().toList();
      expect(renamed, hasLength(1));
      expect(renamed.single.title, 'A');
      expect(s.thread.title, 'A');
      expect(
        s.agents.single.requests('session/set_title').map((r) => r['params']),
        [
          {'sessionId': '1', 'title': 'A'},
        ],
      );
    });

    test('T132: a rename the agent refuses sends no event, and the list keeps '
        'its title (F25②, §28.4)', () async {
      final s = open(titleError: true);
      s.thread.session.attach();
      await settle();

      expect(await s.workspace.rename(s.thread, 'A'), isTrue);
      await settle();

      expect(s.events.whereType<SessionRenamed>(), isEmpty);
      expect(s.thread.session.takeRenamed(), isNull);
      expect(s.thread.title, 'New Chat');
      expect(s.agents.single.requests('session/set_title'), hasLength(1));
      expect(errors(s.thread).single.text, contains('not confirmed'));
    });

    test('T134: the title the host lands back is not asked for again '
        '(F25①, §28.4)', () async {
      // A chat of its own: the host's write-back of the event is the test's.
      final events = <KernelEvent>[];
      final agents = <ThincoderMock>[];
      late final KernelDescriptor descriptor;
      descriptor = KernelDescriptor(
        id: 'thincoder',
        label: 'thincoder',
        icon: Icons.smart_toy_outlined,
        description: 'The agent of the user’s terminal',
        create: (context) {
          final kernel = ThincoderKernel(
            descriptor,
            context,
            start: (_) async {
              final agent = ThincoderMock(serialInbound: true);
              agents.add(agent);
              return agent;
            },
            launch: (cwd) async =>
                ThincoderLaunch(cwd: cwd, executable: '/mock/thincoder'),
          );
          kernel.events.listen(events.add);
          return kernel;
        },
      );
      final session = ChatSession(
        kernel: descriptor,
        kernels: [descriptor],
        historyCount: 0,
      );
      addTearDown(session.dispose);
      session.attach();
      await settle();

      session.rename('A');
      await settle();
      expect(events.whereType<SessionRenamed>(), hasLength(1));
      expect(session.takeRenamed(), 'A');
      expect(agents.single.requests('session/set_title'), hasLength(1));

      // What workspace._sync does with the title it was just told (§28.4).
      session.rename('A');
      await settle();
      expect(agents.single.requests('session/set_title'), hasLength(1));
      expect(events.whereType<SessionRenamed>(), hasLength(1));
    });
  });
}

/// A timer that never fires: the pool's TTL is moved by the test's clock.
class _NoTimer implements Timer {
  @override
  void cancel() {}

  @override
  bool get isActive => false;

  @override
  int get tick => 0;
}

/// The host's files as one that cannot be read at all: a binary file's.
class _BinaryFiles implements KernelFiles {
  @override
  Future<String> readText(String path) async =>
      throw IdeBinaryFileException(path);

  @override
  Future<String?> writeText(String path, String text) async =>
      throw IdeBinaryFileException(path);
}

/// A kernel that only goes back, and in what order (§3.3).
class _EditKernel implements AgentKernel, RewindsConversation {
  /// What it was asked: send, stop, rewind.
  final List<String> calls = [];
  /// What [rewind] waits on, for the test to answer.
  Completer<bool>? rewinding;
  final _events = StreamController<KernelEvent>.broadcast();

  @override
  KernelDescriptor get descriptor => _descriptor;
  @override
  Stream<KernelEvent> get events => _events.stream;
  @override
  KernelHealth get health => const KernelHealth(KernelHealthStatus.ready);
  @override
  String? get sessionId => 's-1';

  @override
  void send(KernelTurn turn) {
    calls.add('send');
    _events.add(ItemUpserted(1, turn.id, UserMessageItem(text: turn.text)));
  }

  @override
  void cancel() => calls.add('stop');

  @override
  Future<bool> rewind({required String itemId, required int index,
      required int turns, String? lastSeen}) {
    calls.add('rewind');
    return (rewinding = Completer<bool>()).future;
  }

  @override
  void answer(String requestId, InteractionAnswer answer) {}
  @override
  void restart() {}
  @override
  void prepare() {}
  @override
  void release() {}
  @override
  void dispose() => unawaited(_events.close());
  @override
  Future<void> get stopped => Future.value();
}
