import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:baocode/browser/browser_steps.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/host_tools/host_mcp_server.dart';
import 'package:baocode/host_tools/host_tools.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_registry.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/kernel/thincoder/thincoder_options.dart';
import 'package:baocode/kernel/thincoder/thincoder_kernel.dart';
import 'package:baocode/kernel/thincoder/thincoder_locator.dart';
import 'package:baocode/kernel/thincoder/thincoder_mock.dart';
import 'package:baocode/kernel/thincoder/thincoder_protocol.dart';
import 'package:baocode/kernel/thincoder/thincoder_session_ref.dart';
import 'package:baocode/kernel/thincoder/thincoder_transport.dart';
import 'package:baocode/kernel/transcript.dart';
import 'package:baocode/platform/event_log.dart';

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
  }) : _make = make ?? ThincoderMock.new {
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
  }) => kernel.send(
    KernelTurn(id: id, text: text, images: images, notes: notes),
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
      expect(s.kernel, isNot(isA<RewindsConversation>()));
      expect(s.kernel, isNot(isA<RenamesSession>()));
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
          'method': 'fs/read_text_file',
          'params': {'sessionId': '1', 'path': '/project/a.dart'},
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

    test('a turn takes the notes with it, apart from the message', () async {
      final s = _Session();
      addTearDown(s.dispose);
      s.kernel.prepare();
      await settle();
      s.send('look', notes: const ['The user has a.dart open']);
      await s.agent.finished.future;
      await settle();

      final params = s.agent.requests('session/prompt').single['params'] as Map;
      expect((params['prompt'] as List).single, {
        'type': 'text',
        'text': 'look\n\nThe user has a.dart open',
      });
      expect(
        s.items<UserMessageItem>().single.text,
        'look\n\nThe user has a.dart open',
      );
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
}
