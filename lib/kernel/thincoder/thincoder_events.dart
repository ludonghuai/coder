import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../chat/chat_models.dart';
import '../../platform/event_log.dart';
import '../kernel_event.dart';
import '../kernel_types.dart';

/// Where the translation puts what it makes: the kernel, which holds the
/// item space and the sequence numbers.
abstract interface class ThincoderSink {
  void emit(KernelEvent event);

  int get nextSeq;

  void emitInfoChanged();
}

/// What `thincoder acp` reports of a session, turned into the events the
/// host shows (design §3.6): text and thoughts into streaming items, its
/// tools into cards, its usage into what the context holds, and its own
/// word for what it offers into the options the choices read (E3).
///
/// Everything it knows is what the agent last reported — nothing is
/// worked out here, and nothing picked here (D20).
class ThincoderEvents {
  ThincoderEvents(this._sink);

  final ThincoderSink _sink;

  /// What the agent offers and has in effect, as it last reported it.
  List<Map<String, Object?>> options = const [];

  /// The mode the agent last reported; never what was asked for (D20).
  String mode = 'normal';

  /// The context window: the agent's word for it, else what thincoder
  /// falls back to for a model it does not know (128 000).
  int contextWindow = 128000;

  /// Which run of items this is (a turn, or a replay): item ids are
  /// `t<run>.<block>` (what the agent said) and `u<run>.<block>` (what was
  /// replayed of the user's), so they never clash with the agent's own
  /// tool ids (`t1`, `t2`, …).
  int _run = 0;
  int _blocks = 0;

  /// The piece of the conversation streaming now: one run of chunks of one
  /// kind is one item; another kind closes it.
  _Piece? _piece;
  String? _pieceId;
  StringBuffer _pieceText = StringBuffer();
  DateTime? _pieceStarted;

  /// The tools reported, as they showed: an update replaces one.
  final Map<String, ChatItem> _tools = {};

  /// The subagents the agent reported, by their record id (F11): what
  /// their cards show, and the strip's rows while they run.
  final Map<String, AgentItem> _subagents = {};

  /// Whether a subagent is still live (D64): its card is running — queued,
  /// at work, in a turn, or in an approval. The tasks are not the whole of
  /// it: a queued one has a card and no row.
  bool get hasLiveSubagents =>
      _subagents.values.any((card) => card.status == CommandStatus.running);

  /// Those of them at work, as the strip has them: a report replaces the
  /// last whole (the form Claude Code's translator takes).
  final Map<String, KernelTask> _tasks = {};

  /// The states a subagent is still live in: a report of one moves it
  /// (its card, its row). One arriving after its end has been reported is
  /// out of contract (D31); the terminal states and `cancelled` are dealt
  /// with as before.
  static const Set<String> _liveStates = {
    'queued',
    'async',
    'turn',
    'approval',
  };

  /// Those a cancel took off the panel (D24): their reports are over with
  /// them — one coming round again is out of contract whatever it says,
  /// and shows nothing (D31).
  final Set<String> _removed = {};

  /// The subagents' own conversations, their tools, and what was said once.
  final Map<String, _Tape> _tapes = {};
  final Map<String, ({String key, int at})> _childTools = {};
  final Set<String> _dropped = {};

  /// What a subagent writes before its card shows again (D34).
  static const _tapeFlush = 256;
  static const _subagentKey = 'thincoder.dev/subagent';

  /// A run of items starts here: a turn, or a load's replay.
  void begin() {
    closePiece();
    _tapeSaid(seal: true);
    _run++;
    _blocks = 0;
  }

  /// One `session/update`: what the agent says happened.
  void update(Map<String, Object?> update) {
    switch (update['sessionUpdate']) {
      case 'agent_message_chunk':
        _content(update, _Piece.text);
      case 'agent_thought_chunk':
        _content(update, _Piece.thought);
      case 'user_message_chunk':
        // Only in a load's replay (§3.4).
        _content(update, _Piece.user);
      case 'tool_call':
        _toolCall(update);
      case 'tool_call_update':
        _toolUpdate(update);
      case 'usage_update':
        _usage(update);
      case 'config_option_update':
        optionsFrom(update);
      case 'current_mode_update':
        if (reportMode(switch (update['currentModeId']) {
          final String mode when mode.isNotEmpty => mode,
          _ => mode,
        })) {
          _sink.emitInfoChanged();
        }
      case 'session_info_update':
        // A subagent's own signal (F11).
        subagent(update);
      default:
        // An update this adapter does not know: left alone, and said in
        // the terminal's log (E4).
        appEvent(
          'thincoder',
          'ignored session/update: ${update['sessionUpdate']}',
        );
    }
  }

  /// What a session's answer says it offers and has in effect — the start
  /// of a session, a load, a resume, or a `set_config_option`.
  void optionsFrom(Map<String, Object?> reported) {
    final raw = reported['configOptions'];
    if (raw is List) {
      options = [
        for (final option in raw)
          if (option is Map) option.cast<String, Object?>(),
      ];
    }
    if (configOf('mode') case final mode?) {
      if (mode['currentValue'] case final String reported) {
        reportMode(reported);
      }
    }
    // Whether the mode moved, or a model or thinking did: what the choices
    // read has changed, so the host is told (E3/D20 — a model or thinking
    // pick shows here or not at all).
    _sink.emitInfoChanged();
  }

  /// The mode the agent reported: shown as it stands until it says
  /// otherwise. Whether it moved.
  bool reportMode(String mode) {
    if (mode != 'plan' && mode != 'normal') return false;
    if (mode == this.mode) return false;
    this.mode = mode;
    return true;
  }

  /// The config option [id] as reported, or null.
  Map<String, Object?>? configOf(String id) =>
      options.where((option) => option['id'] == id).firstOrNull;

  /// The value in effect of a `select` option [id], or null.
  String? selected(String id) => switch (configOf(id)?['currentValue']) {
    final String value => value,
    _ => null,
  };

  /// [id]'s reported options, as the UI lists them.
  List<KernelOption> optionsOf(String id, IconData Function(String) icon) => [
    for (final option in (configOf(id)?['options'] as List? ?? const []))
      if (option is Map && option['value'] is String)
        KernelOption(
          '${option['value']}',
          '${option['name'] ?? option['value']}',
          icon('${option['value']}'),
          '',
        ),
  ];

  /// Whether the agent thinks before it answers, as it last reported it.
  bool get thinking => switch (configOf('thinking')?['currentValue']) {
    final bool on => on,
    _ => false,
  };

  /// Closes the item streaming now, and shows a subagent's unshown text.
  void closePiece() {
    _tapeSaid();
    final id = _pieceId;
    final piece = _piece;
    if (id == null || piece == null) return;
    switch (piece) {
      case _Piece.thought:
        _sink.emit(
          ItemCompleted(
            _sink.nextSeq,
            id,
            item: _thinking(_pieceText.toString(), _pieceStarted),
          ),
        );
      case _Piece.text || _Piece.user:
        _sink.emit(ItemCompleted(_sink.nextSeq, id));
    }
    _piece = null;
    _pieceId = null;
    _pieceText = StringBuffer();
    _pieceStarted = null;
  }

  void _chunk(Map<String, Object?> update, _Piece piece) {
    final text = contentText(update['content'], join: '');
    if (text == null || text.isEmpty) return;
    if (_piece != piece) _open(piece);
    final id = _pieceId!;
    final offset = _pieceText.length;
    _pieceText.write(text);
    switch (piece) {
      case _Piece.text:
        _sink.emit(TextDelta(_sink.nextSeq, id, offset, text));
      case _Piece.thought:
        _sink.emit(
          TextDelta(_sink.nextSeq, id, offset, text, tokens: _pieceText.length),
        );
      case _Piece.user:
        _sink.emit(
          ItemUpserted(
            _sink.nextSeq,
            id,
            UserMessageItem(text: _pieceText.toString()),
            streaming: true,
          ),
        );
    }
  }

  /// Starts the item [piece] streams into, closing the one before it.
  void _open(_Piece piece) {
    closePiece();
    _blocks++;
    _piece = piece;
    _pieceStarted = DateTime.now();
    _pieceText = StringBuffer();
    _pieceId = switch (piece) {
      _Piece.user => 'u$_run.$_blocks',
      _ => 't$_run.$_blocks',
    };
    switch (piece) {
      case _Piece.text:
        _sink.emit(
          ItemUpserted(
            _sink.nextSeq,
            _pieceId!,
            const AssistantTextItem(''),
            streaming: true,
          ),
        );
      case _Piece.thought:
        _sink.emit(
          ItemUpserted(
            _sink.nextSeq,
            _pieceId!,
            ThinkingItem(text: '', tokens: 0, startedAt: _pieceStarted),
            streaming: true,
          ),
        );
      case _Piece.user:
        break;
    }
  }

  void _toolCall(Map<String, Object?> update) {
    final key = _owner(update);
    if (key == '') return;
    if (key != null) return _toolCallOf(key, update);
    closePiece();
    final id = update['toolCallId'];
    if (id is! String || id.isEmpty) return;
    final title = '${update['title'] ?? ''}';
    final raw =
        (update['rawInput'] as Map?)?.cast<String, Object?>() ?? const {};
    final kind = update['kind'];
    final item = _tool(kind is String ? kind : null, title, raw);
    _tools[id] = item;
    _sink.emit(ItemUpserted(_sink.nextSeq, id, item));
  }

  void _toolUpdate(Map<String, Object?> update) {
    final key = _owner(update);
    if (key == '') return;
    if (key != null) return _toolUpdateOf(key, update);
    final id = update['toolCallId'];
    if (id is! String) return;
    // One whose call was never reported: nothing to replace.
    final previous = _tools[id];
    if (previous == null) return;
    final next = _replaced(previous, update);
    if (next == null) return;
    _tools[id] = next;
    _sink.emit(ItemUpserted(_sink.nextSeq, id, next));
  }

  /// What an update makes of the tool [previous]: null where it changes
  /// nothing (a call still running, or one with no next form).
  ChatItem? _replaced(ChatItem previous, Map<String, Object?> update) {
    final status = '${update['status'] ?? ''}';
    if (status == 'in_progress') return null;
    final failed = status == 'failed';
    final output = contentText(update['content'], join: '\n');
    return switch (previous) {
      TerminalItem(:final command, :final description, :final startedAt) =>
        TerminalItem(
          command: command,
          description: description,
          output: output ?? '',
          status: failed ? CommandStatus.failed : CommandStatus.succeeded,
          startedAt: startedAt,
        ),
      ToolCallItem(
        :final kind,
        :final target,
        :final detail,
        :final path,
        :final results,
        :final label,
      ) =>
        ToolCallItem(
          kind: kind,
          target: target,
          detail: detail,
          path: path,
          results: results,
          label: label,
          status: failed ? ToolStatus.failed : ToolStatus.succeeded,
          output: output,
        ),
      _ => null,
    };
  }

  /// The item an ACP tool is shown as, by its kind (§3.6).
  ChatItem _tool(String? kind, String title, Map<String, Object?> raw) {
    final path = switch (raw['path'] ?? raw['filePath']) {
      final String path when path.isNotEmpty => path,
      _ => null,
    };
    switch (kind) {
      case 'read':
        return ToolCallItem(
          kind: ToolKind.read,
          target: path == null ? title : fileName(path),
          path: path,
          status: ToolStatus.running,
        );
      case 'edit' || 'delete' || 'move':
        return ToolCallItem(
          kind: ToolKind.edit,
          target: path == null ? title : fileName(path),
          path: path,
          status: ToolStatus.running,
        );
      case 'execute':
        return TerminalItem(
          command: '${raw['command'] ?? title}',
          output: '',
          status: CommandStatus.running,
          startedAt: DateTime.now(),
        );
      case 'search':
        return ToolCallItem(
          kind: ToolKind.grep,
          target: '${raw['pattern'] ?? raw['query'] ?? title}',
          status: ToolStatus.running,
        );
      case 'fetch':
        return ToolCallItem(
          kind: ToolKind.web,
          target: title,
          status: ToolStatus.running,
        );
      default:
        return ToolCallItem(
          kind: ToolKind.other,
          label: title,
          target: title,
          status: ToolStatus.running,
        );
    }
  }

  void _usage(Map<String, Object?> update) {
    final used = switch (update['used']) {
      final num used => used.toInt(),
      _ => 0,
    };
    final size = switch (update['size']) {
      final num size when size > 0 => size.toInt(),
      _ => contextWindow,
    };
    contextWindow = size;
    _sink.emit(
      UsageReported(_sink.nextSeq, ContextUsage(window: size, used: used)),
    );
  }

  // --- Subagents --------------------------------------------------------------

  /// A `session_info_update`: a subagent's own signal (F11) — its card in
  /// the conversation, and a row in the strip while it works. Anything
  /// else it carries is left alone, and said in the terminal's log (E4).
  void subagent(Map<String, Object?> update) {
    final meta = update['_meta'];
    final reported = meta is Map ? meta['thincoder.dev/subagent'] : null;
    final report = reported is Map
        ? reported.cast<String, Object?>()
        : const <String, Object?>{};
    final role = report['role'];
    final id = report['id'];
    final state = report['state'];
    if (!_named(role) || id is! int || state is! String || state.isEmpty) {
      appEvent('thincoder', 'a subagent report to leave alone: $reported');
      return;
    }
    // `role#id` is what the agent calls it by (the innermost of the relay's
    // path — D21): the record id here.
    final key = 'subagent:$role#$id';
    _tapeSaid(only: key);
    // One a cancel took off the panel does not come back: whatever a later
    // report of the name says — a state that would open a card afresh
    // among them — is one the contract does not make (D31).
    if (_removed.contains(key)) return;
    var card = _subagents[key];
    // One that is over does not come back to life either: a report that has
    // it still live after its end was reported — the card stood down — is
    // one the contract does not make (D31), and nothing here moves for it.
    final ended = card != null && card.status != CommandStatus.running;
    if (ended && _liveStates.contains(state)) return;
    // First seen, whatever state it comes in: its card opens here, and
    // what streams after it begins a piece of its own (as a tool call).
    card ??= _openCard(key, closeMain: true);
    switch (state) {
      case 'queued':
        // Waiting: the card carries it, the strip is for what runs (D23).
        card = _card(card, switch (report['detail']) {
          final String detail when detail.isNotEmpty => 'queued · $detail',
          _ => 'queued',
        });
        _putSubagent(key, card);
      case 'async':
        // At work: in the strip from here, timed from when it was first
        // seen (D29). What it waited with goes.
        card = _card(card, null);
        _putSubagent(key, card);
        _reportTask(key, card);
      case 'turn' || 'approval':
        // The state line reads with its card and with its row — one that
        // has stopped running is not put back in the strip.
        card = _card(card, _stateLine(state, report) ?? card.activity);
        _putSubagent(key, card);
        if (card.status == CommandStatus.running) _reportTask(key, card);
      case 'settled' || 'stopped' || 'done':
        // Settled is done (D25), stopped is where it stood (D24), and
        // `done` is the agent's archive mark: it stops moving here.
        final status = state == 'stopped'
            ? CommandStatus.failed
            : CommandStatus.succeeded;
        if (card.status == CommandStatus.running) {
          card = _card(card, null, status);
          _putSubagent(key, card);
          _endTask(key, status);
        }
      case 'cancelled':
        // Cancelled while queued: it never ran, so nothing of it is kept
        // (the panel removes the block too); one that ran on goes too —
        // and with the card, reports of it are done with (D31).
        _sink.emit(ItemRemoved(_sink.nextSeq, key));
        _subagents.remove(key);
        _tapes.remove(key);
        _removed.add(key);
        if (_tasks.remove(key) != null) _reportTasks();
      default:
        // A state this adapter does not know (E4): its card is left as it
        // is — running rather than hidden away (D27) — and the log says so.
        appEvent('thincoder', 'a subagent state it does not know: $state');
    }
  }

  /// The process is gone, and the subagents it ran with it: what was still
  /// running is frozen as failed, as Claude Code's `endTasks` does (D30).
  ///
  /// What it ran is over with it, so what it kept goes too — cards, rows,
  /// and the names a cancel took off the panel: the ids start over with
  /// the process, and a `role#id` coming round again is another
  /// subagent's — not a card of this one's to go on writing (D21).
  void endSubagents() {
    // What they wrote shows, ending with them (D34).
    _tapeSaid(seal: true);
    for (final MapEntry(key: key, value: card) in [..._subagents.entries]) {
      if (card.status != CommandStatus.running) continue;
      final done = _card(card, null, CommandStatus.failed);
      _subagents[key] = done;
      _putSubagent(key, done);
    }
    // Every task still running ends with it, whether its card was frozen
    // here or had already stopped saying anything.
    var ended = false;
    for (final MapEntry(key: key, value: task) in [..._tasks.entries]) {
      if (task.status != CommandStatus.running) continue;
      _tasks[key] = task.copyWith(
        status: CommandStatus.failed,
        summary: 'thincoder stopped',
      );
      ended = true;
    }
    if (ended) _reportTasks();
    _subagents.clear();
    _tasks.clear();
    _removed.clear();
    _tapes.clear();
    _childTools.clear();
    _dropped.clear();
  }

  /// The subagent's card as the report has it: [activity] what it is doing
  /// now and where it stopped ([status]), how it went and how long it took
  /// (D29). Its id and conversation stay; D21's five fields have no source.
  AgentItem _card(AgentItem card, String? activity, [CommandStatus? status]) =>
      AgentItem(
        description: card.description,
        id: card.id,
        status: status ?? card.status,
        activity: activity,
        startedAt: card.startedAt,
        duration: status == null
            ? card.duration
            : switch (card.startedAt) {
                final started? => DateTime.now().difference(started),
                _ => null,
              },
        background: card.background,
        children: card.children,
      );

  /// Shows [card] as the subagent's, keeps it, and returns it.
  AgentItem _putSubagent(String key, AgentItem card) {
    _subagents[key] = card;
    _sink.emit(ItemUpserted(_sink.nextSeq, key, card));
    return card;
  }

  /// The subagent's row in the strip (D23): what runs beside the
  /// conversation shows there, timed from when it was first seen (D29).
  void _reportTask(String key, AgentItem card) {
    final before = _tasks[key];
    _tasks[key] = KernelTask(
      id: key,
      description: card.description,
      kind: KernelTaskKind.agent,
      status: CommandStatus.running,
      startedAt: before?.startedAt ?? card.startedAt ?? DateTime.now(),
      summary: card.activity,
      background: true,
    );
    _reportTasks();
  }

  /// The subagent's row once it ends: how it went. It leaves the strip —
  /// only what runs shows — and its card keeps the rest.
  void _endTask(String key, CommandStatus status) {
    if (_tasks[key] case final task?) {
      _tasks[key] = task.copyWith(status: status);
      _reportTasks();
    }
  }

  void _reportTasks() =>
      _sink.emit(TasksReported(_sink.nextSeq, [..._tasks.values]));

  /// What a `turn` or `approval` report reads as: `turn <n>/<maxTurns>`
  /// (the one there where the pair is not whole), `approval · <tool>`
  /// where one is named; null where it says nothing this shows (the last
  /// word then stands — the forms are fixed, D28).
  static String? _stateLine(String state, Map<String, Object?> report) {
    if (state != 'turn') {
      return switch (report['detail']) {
        final String detail when detail.isNotEmpty => 'approval · $detail',
        _ => 'approval',
      };
    }
    if (report['progress'] case final Map progress) {
      final turn = progress['turn'];
      final max = progress['maxTurns'];
      if (turn is num) {
        final n = turn.toInt();
        return max is num ? 'turn $n/${max.toInt()}' : 'turn $n';
      }
    }
    return null;
  }

  /// Whether [value] is a name the report has: a string with something in
  /// it.
  static bool _named(Object? value) => value is String && value.isNotEmpty;

  String? _owner(Map<String, Object?> update) {
    final meta = update['_meta'];
    if (meta is! Map || !meta.containsKey(_subagentKey)) return null;
    final mark = meta[_subagentKey];
    final role = mark is Map ? mark['role'] : null;
    final id = mark is Map ? mark['id'] : null;
    if (!_named(role) || id is! int || id < 0) {
      _said('', 'a subagent frame that names no one: $mark');
      return '';
    }
    return 'subagent:$role#$id';
  }
  void _content(Map<String, Object?> update, _Piece piece) {
    final key = _owner(update);
    if (key == '') return;
    if (key == null) return _chunk(update, piece);
    final text = contentText(update['content'], join: '');
    if (text == null || text.isEmpty || _claimed(key) == null) return;
    final tape = _tapes[key]!;
    if (tape.open != piece) {
      _sealTape(tape);
      tape.open = piece;
      tape.since = DateTime.now();
      tape.text = StringBuffer();
      tape.shown = 0;
    }
    tape.text.write(text);
    if (tape.shown == 0 || tape.text.length - tape.shown >= _tapeFlush) {
      _showTape(key);
    }
  }
  AgentItem? _claimed(String key) {
    if (_removed.contains(key)) return _late(key);
    final card = _subagents[key];
    if (card != null && card.status != CommandStatus.running) {
      return _late(key);
    }
    return card ?? _openCard(key);
  }
  AgentItem? _late(String key) {
    _said(key, 'a subagent frame after its end, left alone: $key');
    return null;
  }
  /// First seen: [closeMain] for a state report (batch 4), not for a frame.
  AgentItem _openCard(String key, {bool closeMain = false}) {
    if (closeMain) closePiece();
    _tapes[key] = _Tape();
    return _putSubagent(
      key,
      AgentItem(
        description: key.substring('subagent:'.length),
        id: key,
        startedAt: DateTime.now(),
        background: true,
      ),
    );
  }
  void _toolCallOf(String key, Map<String, Object?> update) {
    final id = update['toolCallId'];
    if (id is! String || id.isEmpty || _claimed(key) == null) return;
    final title = '${update['title'] ?? ''}', kind = update['kind'];
    final raw =
        (update['rawInput'] as Map?)?.cast<String, Object?>() ?? const {};
    _sealTape(_tapes[key]!);
    _tapes[key]!.items.add(_tool(kind is String ? kind : null, title, raw));
    _childTools[id] = (key: key, at: _tapes[key]!.items.length - 1);
    _showTape(key);
  }
  void _toolUpdateOf(String key, Map<String, Object?> update) {
    final tool = _childTools[update['toolCallId']];
    if (tool == null || tool.key != key) return;
    if (_subagents[key]?.status != CommandStatus.running) {
      _said(key, 'a subagent frame after its end, left alone: $key');
      return;
    }
    final items = _tapes[key]!.items;
    final next = _replaced(items[tool.at], update);
    if (next == null) return;
    items[tool.at] = next;
    _showTape(key);
  }
  void _sealTape(_Tape tape) {
    if (tape.open != null) tape.items.add(_item(tape, done: true));
    tape.open = null;
  }
  /// Shows what the tapes wrote — [only]'s or every one's; [seal] closes
  /// the piece being written (a turn's end, the process's).
  void _tapeSaid({String? only, bool seal = false}) {
    for (final MapEntry(key: key, value: tape) in [..._tapes.entries]) {
      if (only != null && only != key) continue;
      if (tape.open == null) continue;
      if (!seal && tape.shown == tape.text.length) continue;
      if (seal) _sealTape(tape);
      _showTape(key);
    }
  }
  ChatItem _item(_Tape tape, {bool done = false}) {
    final text = tape.text.toString();
    if (tape.open != _Piece.thought) return AssistantTextItem(text);
    if (done) return _thinking(text, tape.since);
    return ThinkingItem(text: text, tokens: text.length, startedAt: tape.since);
  }
  void _showTape(String key) {
    final tape = _tapes[key]!, card = _subagents[key]!;
    tape.shown = tape.text.length;
    final talking = [...tape.items, if (tape.open != null) _item(tape)];
    _putSubagent(key, card.copyWith(children: talking));
  }
  void _said(String key, String said) {
    if (_dropped.add(key)) appEvent('thincoder', said);
  }
  static ThinkingItem _thinking(String text, DateTime? started) =>
      ThinkingItem(
        text: text,
        tokens: text.length,
        seconds: math.max(1, _took(started)),
      );
  static int _took(DateTime? since) =>
      since == null ? 0 : DateTime.now().difference(since).inSeconds;

  /// The text of a content block, or of the blocks of a tool's content:
  /// null when there is none.
  static String? contentText(Object? content, {required String join}) {
    final blocks = switch (content) {
      final List blocks => blocks,
      final Map block => [block],
      _ => const <Object?>[],
    };
    final parts = <String>[];
    for (final block in blocks) {
      if (block is! Map) continue;
      final inner = block['content'] is Map ? block['content'] as Map : block;
      if (inner['type'] == 'text' && inner['text'] is String) {
        parts.add(inner['text'] as String);
      }
    }
    return parts.isEmpty ? null : parts.join(join);
  }

  /// The tool's own words of it (the arguments, and a dangerous command the
  /// agent marked): what the user approves.
  static ApprovalPreview? preview(Object? content) {
    final text = contentText(content, join: '\n');
    return text == null ? null : TextPreview(text);
  }

  /// The name of the file [path] names.
  static String fileName(String path) {
    final at = math.max(path.lastIndexOf('/'), path.lastIndexOf(r'\'));
    return at < 0 ? path : path.substring(at + 1);
  }
}

/// A piece of the conversation the agent streams: a run of chunks of one
/// kind is one item, until another kind or the turn's end closes it.
enum _Piece { text, thought, user }

/// One subagent's own conversation as it streams (F12, §16.2).
class _Tape {
  _Piece? open;
  DateTime? since;
  StringBuffer text = StringBuffer();
  List<ChatItem> items = [];
  int shown = 0;
}
