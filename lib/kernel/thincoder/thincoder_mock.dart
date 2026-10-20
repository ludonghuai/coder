import 'dart:async';

import 'thincoder_transport.dart';

/// Plays a session's frames as `thincoder acp` sends them, for tests and
/// demos: the same shapes the agent writes (`bridge.mjs`), answered the
/// way its handlers do (`handlers-session.mjs`, `handlers-slots.mjs`).
///
/// A turn is a script: a list of `session/update` updates sent in order,
/// the tool calls among them asking for approval where the script says so.
/// Not offered in the app (D18).
class ThincoderMock implements ThincoderTransport {
  ThincoderMock({
    this.cwd = '/project',
    this.version = '0.12.74',
    List<Map<String, Object?>>? slots,
    List<Map<String, Object?>>? turn,
    List<Map<String, Object?>>? replay,
    this.authRequired = false,
    this.askPermission = false,
    this.autoApprove,
    this.models,
    this.thinkingLevels,
    this.configError = false,
    this.httpMcp = false,
    this.promptImage = false,
    this.serialInbound = false,
  }) : slots = slots ?? _shelf,
       turn = turn ?? defaultTurn,
       replay = replay ?? defaultReplay;

  /// How the app starts one, as a kernel does.
  static Future<ThincoderTransport> start(ThincoderLaunch launch) async =>
      ThincoderMock(cwd: launch.cwd);

  /// What a scripted session is launched with: none of the machine's own
  /// thincoder is looked for — there is nothing to run, the script is the
  /// agent (D18: not a kernel the app offers).
  static Future<ThincoderLaunch> launch(String cwd) async =>
      ThincoderLaunch(cwd: cwd, executable: 'thincoder');

  final String cwd;
  final String version;

  /// What `session/list` reports.
  final List<Map<String, Object?>> slots;

  /// What a turn sends, in order.
  final List<Map<String, Object?>> turn;

  /// What `session/load` replays before its answer.
  final List<Map<String, Object?>> replay;

  /// Answers the session family with `-32000` (not logged in).
  final bool authRequired;

  /// Whether inbound frames are handled one at a time, each on its own
  /// turn, as a real transport's FIFO does (off: in the caller's stack).
  final bool serialInbound;

  /// Whether the script's tool calls ask the user first.
  bool askPermission;

  /// The auto-approval switch it reports; null: an older CLI's, without it.
  bool? autoApprove;

  /// What `model.options` / `thinkingLevel.options` list; null: today's.
  final List<String>? models;
  final List<String>? thinkingLevels;

  /// Answers config writes with `-32602` (T59 / T60).
  final bool configError;

  /// Answers `session/set_title` with `-32602` (a title refused).
  bool titleError = false;

  /// What `session/revert` answers with: the plan for a `dryRun`, and what
  /// applying does (the plan when none is given).
  Map<String, Object?>? revertPlan;
  Map<String, Object?>? revertApply;

  /// Answers `session/revert` with `-32602` (an unknown turn).
  bool revertUnknown = false;

  /// Says its handshake takes HTTP MCP servers (`mcpCapabilities`), as the
  /// CLI with the forwarding face does.
  final bool httpMcp;

  /// Says its handshake takes pictures as native image blocks (F19); off
  /// like an older CLI, which is today's way.
  final bool promptImage;

  /// Answers `session/prompt` with `-32603`: a turn that failed (T67③).
  bool promptError = false;
  String? _level;

  /// The agent's hand on the turn: not completed, the script waits after
  /// every step, so a cancel or a kill lands mid-turn.
  Completer<void>? hold;

  /// What the kernel wrote, in order.
  final List<Map<String, Object?>> written = [];

  /// What the kernel wrote as requests, by method.
  List<Map<String, Object?>> requests(String method) => [
    for (final message in written)
      if (message['method'] == method) message,
  ];

  final StreamController<Map<String, Object?>> _out =
      StreamController.broadcast();
  final Map<String, Completer<Map<String, Object?>>> _asked = {};

  /// The slots the agent has: the ones on its shelf, and the ones it made.
  late final Set<String> _known = {
    for (final session in slots) '${session['sessionId']}',
  };

  /// The slots deleted, which [slots] no longer lists.
  final Set<String> _deleted = {};

  /// The titles written since, by slot ([slots] stays as given).
  final Map<String, String> _titles = {};
  int _newSlots = 0;
  int _rpc = 0;
  bool _crashed = false;
  bool _cancelled = false;
  bool _closed = false;
  String _slot = '1';
  String _model = 'anthropic:claude-sonnet-5';
  bool _thinking = true;
  String _mode = 'normal';

  /// The turn's answer, waited on by the test (a new one each turn).
  Completer<void> finished = Completer<void>();

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  @override
  void write(Map<String, Object?> message) {
    written.add(message);
    if (!serialInbound) {
      _receive(message);
      return;
    }
    // A real transport reads frames FIFO, one at a time, each handled on a
    // turn of its own: a frame cannot run inside the one before it.
    _inbound.add(message);
    if (_draining) return;
    _draining = true;
    unawaited(_drainInbound());
  }

  final List<Map<String, Object?>> _inbound = [];
  bool _draining = false;

  Future<void> _drainInbound() async {
    while (_inbound.isNotEmpty) {
      final message = _inbound.removeAt(0);
      await Future<void>.delayed(Duration.zero);
      _receive(message);
    }
    _draining = false;
  }

  void _receive(Map<String, Object?> message) {
    final method = message['method'];
    if (method is String) {
      final id = message['id'];
      final params =
          (message['params'] as Map?)?.cast<String, Object?>() ?? const {};
      _handle(method, id, params);
      return;
    }
    final id = message['id'];
    if (id == null) return;
    // The user's answer to our own request.
    _asked.remove('$id')?.complete(message);
  }

  /// Sends a frame of its own, e.g. a notification this adapter does not
  /// know (E4).
  void push(Map<String, Object?> message) => _send(message);

  /// Lets the script's turn go on, where the test holds it.
  void release() {
    final holding = hold;
    if (holding != null && !holding.isCompleted) holding.complete();
  }

  /// The process dies: the exit message, then nothing more.
  void crash({int code = 1, String stderr = 'mock: out of memory'}) {
    if (_crashed || _closed) return;
    _crashed = true;
    _send(ThincoderExit.message(code, stderr, executable: '/mock/thincoder'));
    release();
    _done();
  }

  /// The agent gives up on the approval it is waiting on (its own five
  /// minutes, in a test's instant): the tool is refused and the turn goes
  /// on (T9).
  void timeOutPermission() {
    final waiting = [..._asked.values];
    _asked.clear();
    for (final waiter in waiting) {
      if (!waiter.isCompleted) waiter.complete(const <String, Object?>{});
    }
  }

  @override
  Future<void> get exited => _out.done;

  @override
  void close() {
    if (_crashed || _closed) return;
    _closed = true;
    _send(ThincoderExit.message(0, ''));
    release();
    _done();
  }

  void _done() {
    if (_out.isClosed) return;
    unawaited(_out.close());
    if (!finished.isCompleted) finished.complete();
  }

  void _send(Map<String, Object?> message) {
    if (!_out.isClosed) _out.add(message);
  }

  void _respond(Object? id, Map<String, Object?> result) => _send({
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  });

  void _error(Object? id, int code, String message) => _send({
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  });

  void _update(Map<String, Object?> update) => _send({
    'jsonrpc': '2.0',
    'method': 'session/update',
    'params': {'sessionId': _slot, 'update': update},
  });

  /// A request of the agent's own, answered by the kernel (an approval).
  Future<Map<String, Object?>?> _request(
    String method,
    Map<String, Object?> params,
  ) {
    final id = 'rpc-${++_rpc}';
    final done = Completer<Map<String, Object?>>();
    _asked[id] = done;
    _send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    return done.future;
  }

  void _handle(String method, Object? id, Map<String, Object?> params) {
    switch (method) {
      case 'initialize':
        _respond(id, {
          'protocolVersion': 1,
          'agentCapabilities': {
            if (httpMcp) 'mcpCapabilities': {'http': true, 'sse': true},
            'loadSession': true,
            'promptCapabilities': {
              'image': promptImage,
              'audio': false,
              'embeddedContext': false,
            },
            'sessionCapabilities': {
              'list': <String, Object?>{},
              'resume': <String, Object?>{},
              'delete': <String, Object?>{},
              'close': <String, Object?>{},
            },
          },
          'authMethods': const <Object?>[],
          'agentInfo': {'name': 'thincoder', 'version': version},
        });
      case 'session/new':
        if (authRequired) {
          _error(id, -32000, 'no provider API key configured — set '
              'providers[].apiKey in ~/.thincoder/config.json, or run '
              '"thincoder acp --login"');
          return;
        }
        _slot = '${++_newSlots}';
        _known.add(_slot);
        _respond(id, {'sessionId': _slot, 'configOptions': _options()});
      case 'session/load':
        if (authRequired) {
          _error(id, -32000, 'authRequired');
          return;
        }
        if (!_has('${params['sessionId']}')) {
          _error(id, -32602, 'session ${params['sessionId']} not found '
              '(corrupt or deleted)');
          return;
        }
        _slot = '${params['sessionId']}';
        unawaited(_replay(id));
      case 'session/resume':
        if (authRequired) {
          _error(id, -32000, 'authRequired');
          return;
        }
        if (!_has('${params['sessionId']}')) {
          _error(id, -32602, 'session ${params['sessionId']} not found '
              '(corrupt or deleted)');
          return;
        }
        _slot = '${params['sessionId']}';
        _respond(id, {'configOptions': _options()});
      case 'session/list':
        _respond(id, {
          'sessions': [
            for (final session in slots)
              if (!_deleted.contains('${session['sessionId']}'))
                {
                  'cwd': cwd,
                  ...session,
                  'title': _titles['${session['sessionId']}'] ?? session['title'],
                },
          ],
        });
      case 'session/delete':
        final slot = '${params['sessionId']}';
        if (!_has(slot) || !_deleted.add(slot)) {
          // One that is gone (or never was), as the real handler says
          // (`handlers-slots.mjs:209`).
          _error(id, -32602, 'session $slot not found');
          return;
        }
        _respond(id, const {});
      case 'session/set_title':
        final title = '${params['title'] ?? ''}';
        if (titleError || title.trim().isEmpty || title.length > 80) {
          return _error(id, -32602, 'a title is refused');
        }
        _titles['${params['sessionId']}'] = title;
        _respond(id, const {});
      case 'session/revert':
        if (revertUnknown) return _error(id, -32602, 'unknown turn');
        final answer = switch (params['dryRun'] == true) {
          true => revertPlan,
          false => revertApply ?? revertPlan,
        };
        _respond(id, answer ?? _noRevert);
      case 'session/prompt':
        unawaited(_prompt(id, '${params['sessionId']}'));
      case 'session/cancel':
        _cancelled = true;
        release();
        _respond(id, const {});
      case 'session/close':
        _respond(id, const {});
      case 'session/set_mode':
        _mode = '${params['mode']}';
        _update({'sessionUpdate': 'current_mode_update', 'currentModeId': _mode});
        _respond(id, const {});
      case 'session/set_config_option':
        _configure(id, params);
      default:
        if (id != null) _error(id, -32601, 'Method not found');
    }
  }

  void _configure(Object? id, Map<String, Object?> params) {
    final configId = params['configId'];
    final value = params['value'];
    if (configError) return _error(id, -32602, 'refused: $configId');
    switch (configId) {
      case 'model' when value is String && value.isNotEmpty:
        _model = value;
      case 'thinking' when value is bool:
        _thinking = value;
      case 'thinkingLevel'
          when value is String && thinkingLevels?.contains(value) == true:
        _level = value;
        _thinking = value != 'off';
      case 'autoApprove' when value is bool && autoApprove != null:
        autoApprove = value;
      case 'mode' when value == 'plan' || value == 'normal':
        _mode = '$value';
      default:
        _error(id, -32602, 'unknown configId: $configId');
        return;
    }
    _update({
      'sessionUpdate': 'config_option_update',
      'configOptions': _options(),
    });
    _respond(id, {'configOptions': _options()});
  }

  List<Map<String, Object?>> get configOptions => _options();

  /// What the session reports it offers and has in effect
  /// (`sessionConfigOptions`, `handlers-session.mjs:40-53`).
  List<Map<String, Object?>> _options() => [
    {
      'id': 'model',
      'name': 'Model',
      'type': 'select',
      'currentValue': _model,
      'options': [
        for (final model in models ?? [_model])
          {'value': model, 'name': model},
      ],
    },
    {
      'id': 'thinking',
      'name': 'Thinking',
      'type': 'boolean',
      'currentValue': _thinking,
    },
    if (thinkingLevels case final levels?)
      {
        'id': 'thinkingLevel',
        'name': 'Thinking effort',
        'type': 'select',
        'currentValue': _levelOf(levels),
        'options': [
          for (final level in levels)
            {'value': level, 'name': level == 'off' ? 'Off' : level},
        ],
      },
    {
      'id': 'mode',
      'name': 'Mode',
      'type': 'select',
      'currentValue': _mode,
      'options': const [
        {'value': 'normal', 'name': 'Normal'},
        {'value': 'plan', 'name': 'Plan'},
      ],
    },
    if (autoApprove case final auto?)
      {
        'id': 'autoApprove',
        'name': 'Auto-approve tools',
        'type': 'boolean',
        'currentValue': auto,
      },
  ];

  /// The level in effect: the picked one, else the first (or `off`).
  String? _levelOf(List<String> levels) {
    final on = levels.where((level) => level != 'off').firstOrNull;
    if (!_thinking) return levels.contains('off') ? 'off' : on;
    return _level == 'off' || !levels.contains(_level) ? on : _level;
  }

  /// Whether the agent has the session file [slot] (`session/list` shows
  /// less: one that never had a message does not land a file).
  bool _has(String slot) => _known.contains(slot) && !_deleted.contains(slot);


  Future<void> _replay(Object? id) async {
    for (final update in replay) {
      await _between();
      _update(update);
    }
    _respond(id, {'configOptions': _options()});
  }

  Future<void> _prompt(Object? id, String sessionId) async {
    if (finished.isCompleted) finished = Completer<void>();
    if (promptError) {
      _error(id, -32603, 'the turn failed');
      return finished.complete();
    }
    _slot = sessionId;
    _cancelled = false;
    final denied = <String>{};
    for (final update in turn) {
      await _between();
      if (_cancelled) break;
      if (update['sessionUpdate'] == 'tool_call') {
        _update(update);
        if (askPermission && await _approve(update)) {
          denied.add('${update['toolCallId']}');
          _update({
            'sessionUpdate': 'tool_call_update',
            'toolCallId': update['toolCallId'],
            'status': 'failed',
            'content': [
              {
                'type': 'content',
                'content': {'type': 'text', 'text': 'Denied by the user.'},
              },
            ],
          });
        }
        continue;
      }
      if (update['sessionUpdate'] == 'tool_call_update' &&
          denied.remove('${update['toolCallId']}')) {
        // The denial already said how it ended.
        continue;
      }
      _update(update);
    }
    final cancelled = _cancelled;
    _cancelled = false;
    _respond(id, {'stopReason': cancelled ? 'cancelled' : 'end_turn'});
    if (!finished.isCompleted) finished.complete();
  }

  /// Asks the user, as the agent does: three options, in that order, and
  /// the tool refused unless the answer is one of the two approvals
  /// (`bridge.mjs:50-62`).
  Future<bool> _approve(Map<String, Object?> toolCall) async {
    // The kernel's own short-circuit (`dispatch.mjs:177`): never asked.
    if (autoApprove == true) return false;
    final answer = await _request('session/request_permission', {
      'sessionId': _slot,
      'options': const [
        {'optionId': 'approve_once', 'name': 'Approve once', 'kind': 'allow_once'},
        {
          'optionId': 'approve_always',
          'name': 'Approve for this session',
          'kind': 'allow_always',
        },
        {'optionId': 'reject', 'name': 'Reject', 'kind': 'reject_once'},
      ],
      'toolCall': {
        'toolCallId': '${toolCall['toolCallId']}',
        'title': '${toolCall['title']}',
        'content': const [
          {
            'type': 'content',
            'content': {'type': 'text', 'text': 'Requesting approval to run'},
          },
        ],
      },
    });
    final result = (answer?['result'] as Map?)?.cast<String, Object?>();
    final outcome = (result?['outcome'] as Map?)?.cast<String, Object?>();
    if (outcome?['outcome'] != 'selected') return true;
    final picked = '${outcome?['optionId']}';
    return picked != 'approve_once' && picked != 'approve_always';
  }

  /// The script's pace: a step, then its turn (which the test may hold).
  Future<void> _between() async {
    final holding = hold;
    if (holding == null) return Future<void>.delayed(Duration.zero);
    if (holding.isCompleted) return;
    await holding.future;
  }

  static const _shelf = <Map<String, Object?>>[
    {'sessionId': '3', 'updatedAt': '2026-10-15T09:30:00.000Z', 'title': 'From the terminal'},
  ];

  static const _noRevert = <String, Object?>{
    'files': <Object?>[], 'failed': <Object?>[], 'skipped': <Object?>[],
    'unrevertable': <Object?>[]};

  /// What a turn sends when nothing else is asked for: a thought, some
  /// text, a tool call and its result, the usage, and the rest of the
  /// answer.
  static const defaultTurn = <Map<String, Object?>>[
    {
      'sessionUpdate': 'agent_thought_chunk',
      'content': {'type': 'text', 'text': 'Looking at the project…'},
    },
    {
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': 'Let me read that file.'},
    },
    {
      'sessionUpdate': 'tool_call',
      'toolCallId': 't1',
      'title': 'read',
      'kind': 'read',
      'status': 'in_progress',
      'rawInput': {'path': 'lib/main.dart'},
      'content': [
        {
          'type': 'content',
          'content': {'type': 'text', 'text': '{"path":"lib/main.dart"}'},
        },
      ],
    },
    {
      'sessionUpdate': 'tool_call_update',
      'toolCallId': 't1',
      'status': 'completed',
      'content': [
        {
          'type': 'content',
          'content': {'type': 'text', 'text': 'void main() {}'},
        },
      ],
    },
    {'sessionUpdate': 'usage_update', 'used': 1200, 'size': 200000},
    {
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': 'It does nothing yet.'},
    },
  ];

  /// What a load replays: the user's line, the agent's answer, and a tool
  /// card with its result (ids from the agent's replay sequence).
  static const defaultReplay = <Map<String, Object?>>[
    {
      'sessionUpdate': 'user_message_chunk',
      'content': {'type': 'text', 'text': 'Hello from the terminal'},
    },
    {
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': 'Hi — what would you like to do?'},
    },
    {
      'sessionUpdate': 'tool_call',
      'toolCallId': 't7',
      'title': 'read',
      'kind': 'read',
      'status': 'in_progress',
      'rawInput': {'path': 'lib/main.dart'},
      'content': [
        {
          'type': 'content',
          'content': {'type': 'text', 'text': '{"path":"lib/main.dart"}'},
        },
      ],
    },
    {
      'sessionUpdate': 'tool_call_update',
      'toolCallId': 't7',
      'status': 'completed',
      'content': [
        {
          'type': 'content',
          'content': {'type': 'text', 'text': 'void main() {}'},
        },
      ],
    },
  ];
}

/// A stand-in that sends nothing of its own: a recording's frames are
/// pushed at it, and what the kernel writes is kept — the entry the
/// fixtures are replayed through (`test/fixtures/thincoder/*.ndjson`).
class ThincoderReplay implements ThincoderTransport {
  ThincoderReplay();

  /// What the kernel wrote, in order.
  final List<Map<String, Object?>> written = [];

  final StreamController<Map<String, Object?>> _out =
      StreamController.broadcast();
  final List<Map<String, Object?>> _queue = [];
  final List<Completer<Map<String, Object?>>> _asked = [];
  bool _closed = false;

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  /// Sends a recorded frame to the kernel, as the agent wrote it.
  void push(Map<String, Object?> message) {
    if (!_out.isClosed) _out.add(message);
  }

  /// The next message the kernel writes, waiting for one to come: what a
  /// recording's `client` lines are held against.
  Future<Map<String, Object?>> next() {
    if (_queue.isNotEmpty) return Future.value(_queue.removeAt(0));
    final waiter = Completer<Map<String, Object?>>();
    _asked.add(waiter);
    return waiter.future;
  }

  @override
  void write(Map<String, Object?> message) {
    written.add(message);
    if (_asked.isEmpty) {
      _queue.add(message);
      return;
    }
    _asked.removeAt(0).complete(message);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    if (!_out.isClosed) unawaited(_out.close());
  }

  @override
  Future<void> get exited => _out.done;
}
