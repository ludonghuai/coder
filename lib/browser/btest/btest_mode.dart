import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../chat/chat_models.dart' show ToolKind;
import '../../host_tools/host_tools.dart';
import '../../settings/user_settings.dart';
import '../browser_bridge.dart' show BrowserError;
import 'btest_expect_file.dart';
import 'btest_policy.dart';
import 'btest_weights.dart';

/// btest's own settings, in settings.json (§4: the settings page's two host
/// lists and the read-only default).
abstract final class BtestSettings {
  /// The hosts a browser action may reach at all; empty refuses every one.
  static const allowHostsKey = 'btest.allowHosts';

  /// The hosts that are production: a write action never reaches one, and
  /// an empty list refuses writes (§3.7 rule B).
  static const prodHostsKey = 'btest.prodHosts';

  /// Whether a run that does not say its mode starts read-only (§9).
  static const readonlyKey = 'btest.readonly';

  /// The folder expect files go in; empty derives it from the session's
  /// workspace root (§3.4).
  static const qaRootKey = 'btest.qaRoot';

  /// A test's values, in place of settings.json's.
  @visibleForTesting
  static Map<String, Object?>? values;

  static Set<String> get allowHosts => hostsOf(_read(allowHostsKey));
  static Set<String> get prodHosts => hostsOf(_read(prodHostsKey));

  /// Read-only unless the user turned it off.
  static bool get readonlyByDefault => _read(readonlyKey) != false;

  /// The configured QA root, trimmed; null when the setting is empty (the
  /// path is then derived, §3.4).
  static String? get qaRoot => switch (_read(qaRootKey)) {
    final String text when text.trim().isNotEmpty => text.trim(),
    _ => null,
  };

  /// The setting [key]'s value, as settings.json keeps it now.
  static Object? _read(String key) {
    if (values case final values?) return values[key];
    try {
      return SettingsFiles.instance.settings[key];
    } on Object {
      // No data folder to read from: nothing is configured, and an empty
      // list refuses rather than allows (fail-closed).
      return null;
    }
  }

  /// A settings.json list of hosts, normalized lower case; anything else is
  /// none.
  static Set<String> hostsOf(Object? value) => {
    if (value is List) for (final host in value) ?_hostOf('$host'),
  };

  /// A text field's line as the list it sets: hosts by comma or space; none
  /// for blank.
  static List<String>? listOf(String text) {
    final hosts = [
      for (final host in text.split(RegExp(r'[,\s]+'))) ?_hostOf(host),
    ];
    return hosts.isEmpty ? null : hosts;
  }

  /// [text] as a host alone: what someone types as a URL
  /// (`https://v2-dev.example.com/`) becomes `v2-dev.example.com`, which is
  /// what the gate compares against (`Uri.host`). Without this a list can look
  /// filled and never match — a prod host would go unprotected, and an allow
  /// list would refuse everything.
  static String? _hostOf(String text) {
    final value = text.trim();
    if (value.isEmpty) return null;
    final asUrl = Uri.tryParse(value.contains('://') ? value : '//$value');
    final host = asUrl?.host.trim().toLowerCase() ?? '';
    if (host.isNotEmpty) return host;
    return value.toLowerCase();
  }
}

/// A recorded detour (§3.6.2): which entry, where to, and the finding it was
/// taken for.
class BtestEntry {
  const BtestEntry({required this.tool, required this.url, this.detour});

  final String tool;
  final String url;
  final String? detour;
}

/// One run of a business line (§3.3): what it declared, the expect file's
/// baseline, and the counters its fourth check reads.
class BtestRun {
  BtestRun({
    required this.id,
    required this.number,
    required this.line,
    required this.repoRoot,
    required this.startUrl,
    required this.env,
    required this.face,
    required this.traversal,
    required this.expectFile,
    required this.qaRoot,
    required this.commitRange,
    required this.baseline,
    required this.cases,
  });

  final String id;

  /// The run's ordinal, as the status line reads it (`run 1`, §9.1): the
  /// tools' `runId` is `run-1`, the line says the number it ends with.
  final String number;

  final String line;

  /// The business repository's root, absolute.
  final String repoRoot;

  /// Its name, from [repoRoot]'s last segment (§3.3: one source for it).
  String get repo => p.basename(repoRoot);

  /// The one URL this run enters by.
  final String startUrl;
  final BtestEnv env;
  final BtestFace face;

  /// The way this round walks its pages (§3.9): down the business chain, or
  /// across each interface of the run's scope in turn — one swept whole
  /// before the next is entered.
  final BtestTraversal traversal;

  /// The expect file, absolute — derived by the host (§3.4): `expectFile`
  /// is this run's name for the file, never an input.
  final String expectFile;

  /// The QA root the run's files live under (§3.4): the weights table is
  /// one per root (§3.9).
  final String qaRoot;

  final String commitRange;

  /// The expect file's SHA-256 as the run started; null when absent — the
  /// write-back baseline (§3.3, item 3).
  final String? baseline;

  /// The run's case index, as the file had it at its start.
  final List<BtestCase> cases;

  /// The entry actions allowed so far, in order (§3.6.2).
  final List<BtestEntry> entries = [];

  /// Entry actions refused (§3.3, 4-①: counted apart).
  int entriesDenied = 0;

  /// Scripts refused for writing (§3.3, 4-②).
  int scriptsDenied = 0;

  /// Requests a script made instead of the form (§3.3, 4-②): replay is
  /// refused in btest, so the allowed count stays 0 — the pair is the
  /// reading, and a non-zero refusal is named.
  int replayAllowed = 0;
  int replayDenied = 0;

  /// Targets aimed at, by how (§3.3, 4-③).
  int wordsTargets = 0;
  int fallbackTargets = 0;

  /// Calls refused by any other gate.
  int denied = 0;

  /// The detours taken, in order (§3.6.2).
  List<BtestEntry> get detours => [
    for (final entry in entries)
      if (entry.detour != null) entry,
  ];

  /// The declared entry alone: 入口 counts it, detours are counted apart
  /// (§3.8's line reads `入口=1 … 绕道=1` with one legal detour).
  List<BtestEntry> get declared => [
    for (final entry in entries)
      if (entry.detour == null) entry,
  ];

  /// The report's head line (§3.8): the round's traversal and mode first,
  /// then the counters read from the run — the very line `btest_run_end`
  /// hands back to be pasted, never self-reported. [noVisibleText] is the
  /// payload's count, reconciled against the fallback count in check 4-③.
  String truthLine({required int noVisibleText}) => [
    'traversal=${traversal.name}',
    'mode=${face.name}',
    '操作真实性：入口=${declared.length}'
        '（navigate=${_count('browser_navigate')}',
    'open=${_count('browser_open')}',
    if (_count('browser_act') > 0) 'act=${_count('browser_act')}',
    '被拒=$entriesDenied）',
    'evaluate 写值被拒=$scriptsDenied',
    'replay 放行=$replayAllowed/被拒=$replayDenied',
    '文字定位=$wordsTargets',
    'ref/selector 兜底=$fallbackTargets',
    '无可见文字=$noVisibleText',
    '绕道=${detours.length}',
  ].join(' · ');

  int _count(String tool) =>
      declared.where((entry) => entry.tool == tool).length;
}

/// A conversation's btest state (§3.1): whether the mode is on, its run,
/// the two run switches (§9.1), and how many runs it has had.
class BtestState {
  BtestState({this.key = ''});

  /// The key it is kept under (see [BtestMode.keyOf]).
  String key;

  bool on = false;

  /// How the next run walks (§9.1): the traversal switch, kept in memory and
  /// never written to the settings. Unset until picked; the built-in
  /// `surface` then stands — the third tier of §3.3's priority.
  BtestTraversal? _traversal;

  /// Whether the next run may act (§9.1): the write switch, memory only.
  /// Unset until picked; `btest.readonly` then stands (true ⇒ read-only).
  bool? _write;

  /// What the traversal switch reads now: its own value, else the built-in
  /// `surface` — what a round did before the switch existed (KD-21).
  BtestTraversal get traversal => _traversal ?? BtestTraversal.surface;

  /// Picks how the next run walks: the switch alone. A run under way keeps
  /// the traversal it started with (§9.1: a click only moves the switch).
  set traversal(BtestTraversal value) => _traversal = value;

  /// Whether the write switch reads `允许写` now: its own value, else the
  /// settings' default — read-only unless `btest.readonly` is off.
  bool get write => _write ?? !BtestSettings.readonlyByDefault;

  /// Picks whether the next run may act: the switch alone; a run under way
  /// keeps its own (§9.1).
  set write(bool value) => _write = value;

  /// Whether the write switch was picked in this session: rule A's text says
  /// where an implied `mode: write` came from — the switch or the setting
  /// (§3.7).
  bool get writePicked => _write != null;

  /// The run under way; null between runs.
  BtestRun? run;

  int _runs = 0;

  BtestRun start({
    required String line,
    required String repoRoot,
    required String startUrl,
    required BtestEnv env,
    required BtestFace face,
    required BtestTraversal traversal,
    required String expectFile,
    required String qaRoot,
    required String commitRange,
    required String? baseline,
    required List<BtestCase> cases,
  }) {
    final n = ++_runs;
    final started = BtestRun(
      id: 'run-$n',
      number: '$n',
      line: line,
      repoRoot: repoRoot,
      startUrl: startUrl,
      env: env,
      face: face,
      traversal: traversal,
      expectFile: expectFile,
      qaRoot: qaRoot,
      commitRange: commitRange,
      baseline: baseline,
      cases: cases,
    );
    return run = started;
  }

  /// Ends the run: a later browser call needs a new one (§3.3).
  void end() => run = null;

  /// Records what a verdict allowed: the entry, and how the call aimed.
  void recordAllowed(
    String tool,
    BtestDecision decision,
    Map<String, Object?> input,
  ) {
    final run = this.run;
    if (run == null) return;
    if (decision.entry case final url?) {
      // The first entry is the declared one: a detour there has no defect to
      // record (§3.6.2), and counting it as one would read 入口=0.
      final first = run.entries.isEmpty;
      run.entries.add(
        BtestEntry(
          tool: tool,
          url: url,
          detour: first ? null : BtestPolicy.detourOf(tool, input),
        ),
      );
    }
    if (tool == 'browser_request' && input['replay'] == true) {
      run.replayAllowed++;
    }
    if (tool == 'browser_act') {
      for (final target in BtestPolicy.actTargets(input)) {
        _count(run, target);
      }
    } else if (decision.target case final target?) {
      _count(run, target);
    }
  }

  /// Records a refusal, by the rule that made it (§3.3, check 4).
  void recordDenied(BtestDecision decision) {
    final run = this.run;
    if (run == null) return;
    run.denied++;
    if (decision.entryDenied) run.entriesDenied++;
    if (decision.evaluateWrite) run.scriptsDenied++;
    if (decision.replayDenied) run.replayDenied++;
  }

  static void _count(BtestRun run, BtestTarget target) => switch (target) {
    BtestTarget.words => run.wordsTargets++,
    BtestTarget.fallback => run.fallbackTargets++,
  };
}

/// Where each conversation's btest state lives (§3.1: a host overlay, kept
/// by session — the tool layer and the composer read the same one).
abstract final class BtestMode {
  /// The session setting that starts a conversation in btest (§3.1: the
  /// map the kernel's mode is kept in, beside it).
  static const settingKey = 'btest';

  /// What a conversation's state is kept under: its folder and the agent's
  /// slot, `cwd|slot` — the slot a host tool call names, or the one a
  /// host-side session id ends with (`<cwd>|<slot>`).
  static String keyOf(String? cwd, String? sessionId) {
    final folder = (cwd ?? '').trim();
    final id = (sessionId ?? '').trim();
    final at = id.lastIndexOf('|');
    final slot = at > 0 && at < id.length - 1 ? id.substring(at + 1) : id;
    return '$folder|$slot';
  }

  static final Map<String, BtestState> _states = {};

  /// How many conversations without an id yet had a state made: each its
  /// own, so two of them never share one (§3.1: by session).
  static int _anonymous = 0;
  static const _anon = '#';

  static bool _isAnonymous(String key) =>
      key.substring(key.lastIndexOf('|') + 1).startsWith(_anon);

  /// The state a call's session is kept under; null when it has none yet.
  static BtestState? find(String? cwd, String? sessionId) {
    final exact = _states[keyOf(cwd, sessionId)];
    if (exact != null) return exact;
    // Before its first message a conversation has no id of its own: its
    // state is the folder's one anonymous one. Two of those cannot be told
    // apart, so neither is taken.
    final folder = '${(cwd ?? '').trim()}|';
    final anonymous = [
      for (final entry in _states.entries)
        if (entry.key.startsWith(folder) && _isAnonymous(entry.key))
          entry.value,
    ];
    return anonymous.length == 1 ? anonymous.single : null;
  }

  /// The state [cwd]'s session keeps, made at its first use: its own, never
  /// one another conversation holds.
  static BtestState of(String? cwd, String? sessionId) {
    final id = (sessionId ?? '').trim();
    final key = id.isEmpty
        ? '${(cwd ?? '').trim()}|$_anon${++_anonymous}'
        : keyOf(cwd, id);
    return _states[key] ??= BtestState(key: key);
  }

  /// Keeps [state] under the session it now is: a conversation gets its id
  /// after its first message, and its state moves with it — the key it had
  /// until then goes, if it is still its own.
  static void bind(BtestState state, {String? cwd, String? sessionId}) {
    final id = (sessionId ?? '').trim();
    if (id.isEmpty) return; // Nothing to bind it to yet.
    final key = keyOf(cwd, id);
    if (state.key == key) {
      _states[key] = state;
      return;
    }
    if (_states[state.key] == state) _states.remove(state.key);
    state.key = key;
    _states[key] = state;
  }

  static void release(BtestState state) {
    if (_states[state.key] == state) _states.remove(state.key);
  }

  /// Whether btest is on in a session, as the kernel's approval hook reads
  /// it (§3.7: it answers for the browser group only while it is).
  static bool onFor(String? cwd, String? sessionId) =>
      find(cwd, sessionId)?.on ?? false;

  /// A test's clean slate.
  @visibleForTesting
  static void reset() => _states.clear();
}

/// The gate every browser tool call passes (§3.4 / §3.7): the judgement is
/// [BtestPolicy]'s, the run's counters are [BtestState]'s.
abstract final class BtestGate {
  /// The two tools that start and end a run: their own rules, and no run
  /// needed — otherwise a run could never start (§3.3).
  static const exempt = {'btest_run_start', 'btest_run_end'};

  /// The session's state while btest is on in it; null when it is not.
  static BtestState? stateOf(HostToolCall call) {
    final state = BtestMode.find(call.cwd, call.sessionId);
    return state != null && state.on ? state : null;
  }

  /// Refuses [tool] when btest's rules say no (§3.7: the op rules first),
  /// and counts what it allowed. [hosts] are the hosts the call targets,
  /// [targeted] whether it targets one at all.
  static void check(
    String tool,
    Map<String, Object?> input,
    HostToolCall call, {
    required List<String> hosts,
    required bool targeted,
  }) {
    final state = stateOf(call);
    if (state == null) return;
    final run = state.run;
    if (run == null) {
      throw BrowserError(
        'btest denied: $tool — no active run: call btest_run_start first '
        '(Settings → Browser → btest)',
      );
    }
    final decision = BtestPolicy.judge(
      tool: tool,
      input: input,
      env: run.env,
      face: run.face,
      startUrl: run.startUrl,
      entries: run.entries.length,
      hosts: hosts,
      targeted: targeted,
      allowHosts: BtestSettings.allowHosts,
      prodHosts: BtestSettings.prodHosts,
    );
    if (!decision.allowed) {
      state.recordDenied(decision);
      throw BrowserError(decision.message!);
    }
    state.recordAllowed(tool, decision, input);
  }
}

/// The two tools a run is opened and closed with (§3.3), in the browser
/// group like the rest — a run's rules are about what they guard.
abstract final class BtestTools {
  static final List<HostTool> all = [_start, _end];

  static final HostTool _start = HostTool(
    name: 'btest_run_start',
    description:
        'Starts one btest run for a business line: the business repository, '
        'the one entry URL, dev/test/prod, read-only or write, and the way '
        'the round walks (traversal: chain dives down the business chain; '
        'surface sweeps one interface completely, then the next, until the '
        "run's scope is covered; surface is the default). The expect "
        'file is derived by the host from the line, the repository and the '
        'QA root, and its absolute path is returned. Returns the run id and '
        'traversal, that path, the case index, the SHA-256 (the write-back '
        'baseline) and the weights table (path, source, effective order). '
        'btest refuses every browser action until a run is started, and one '
        'run at a time.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'line': {
          'type': 'string',
          'description': 'The business line, e.g. "订舱". The expect file is '
              'named after it (<line>.md): a name, not a path.',
        },
        'repoRoot': {
          'type': 'string',
          'description': 'The business repository\'s root, absolute; it must '
              'hold .git.',
        },
        'startUrl': {
          'type': 'string',
          'description': 'The one URL this run enters by: every other page '
              'comes from a click, or a recorded detour.',
        },
        'env': {'type': 'string', 'enum': ['dev', 'test', 'prod']},
        'mode': {
          'type': 'string',
          'enum': ['readonly', 'write'],
          'description': 'Optional: the composer\'s write switch decides '
              'when this is left out (read-only unless btest.readonly is '
              'off). env: prod with write is refused (rule A), implied or '
              'not.',
        },
        'traversal': {
          'type': 'string',
          'enum': ['chain', 'surface'],
          'description': 'Optional: chain walks down the business chain as '
              'far as it goes (a step that cannot go on is a chainBreak, and '
              'the run looks for another way); surface sweeps this interface '
              'completely (tabs, buttons, forms, filters, the list), then '
              'moves on to the next interface and sweeps that too, until the '
              "run's scope is covered — never one interface alone. Left out, "
              'the composer\'s traversal switch decides (surface unless it '
              'was picked).',
        },
        'commitRange': {
          'type': 'string',
          'description': 'The change range this run covers, as '
              'git log --oneline -30 gave it.',
        },
      },
      'required': [
        'line',
        'repoRoot',
        'startUrl',
        'env',
        'commitRange',
      ],
    },
    kind: ToolKind.browser,
    group: 'browser',
    run: _startRun,
  );

  static final HostTool _end = HostTool(
    name: 'btest_run_end',
    description:
        'Closes the run: takes the report as a structured payload '
        '(coveredCases, issues, blockers, unconfirmedDiffs, uncovered; a '
        'chain run also sends chainBreaks, and noVisibleText backs the '
        'fallback reading) and returns the five mechanical readings — the '
        'expect file written back, the tail and break keys there, the '
        'coverage reconciled, the operation authenticity line the report is '
        'headed with, and the weights table. Write the expect file back '
        'BEFORE calling this.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'runId': {'type': 'string'},
        'coveredCases': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'issues': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'caseId': {'type': 'string'},
              'step': {'type': 'string'},
              'symptom': {'type': 'string'},
              'evidence': {
                'type': 'object',
                'properties': {
                  'kind': {'type': 'string'},
                  'readout': {'type': 'string'},
                },
              },
              'severity': {'type': 'string'},
              'pre': {'type': 'string'},
              'expectRef': {'type': 'string'},
              'detour': {'type': 'string'},
            },
          },
        },
        'blockers': {'type': 'array', 'items': {'type': 'object'}},
        'unconfirmedDiffs': {'type': 'array', 'items': {'type': 'object'}},
        'uncovered': {
          'type': 'array',
          'items': {'type': 'object'},
          'description': 'What the round did not reach: on a surface run, '
              'each interface or branch of the run\'s scope it did not sweep '
              '(not each control it skipped), as branch / why.',
        },
        'chainBreaks': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
              'at': {'type': 'string'},
              'reason': {
                'type': 'string',
                'enum': ['门控', '无权限', '数据不足', '没有下一步'],
              },
              'verified': {'type': 'string'},
              'cause': {
                'type': 'string',
                'description': 'Optional: why this step could not go on — '
                    'one line plus one file:line (or a document section), '
                    'from the read-only subagent a chain break is sent to. '
                    'Absent when none was sent; reason stays one of the four.',
              },
            },
          },
        },
        'noVisibleText': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'step': {'type': 'string'},
              'element': {'type': 'string'},
            },
          },
        },
      },
      'required': ['runId', 'coveredCases', 'issues'],
    },
    kind: ToolKind.browser,
    group: 'browser',
    run: _endRun,
  );

  static Future<Object> _startRun(
    Map<String, Object?> input,
    HostToolCall call,
  ) async {
    final state = BtestMode.find(call.cwd, call.sessionId);
    if (state == null || !state.on) {
      throw const BrowserError(
        'btest_run_start refused: btest is not on in this session — switch '
        'the mode to btest in the composer first',
      );
    }
    if (state.run case final active?) {
      throw BrowserError(
        'btest_run_start refused: run ${active.id} is still open — end it '
        'with btest_run_end first (one run at a time)',
      );
    }
    final line = _text(input['line']) ?? '';
    if (BtestExpect.lineProblem(line) case final problem?) {
      throw BrowserError('btest_run_start refused: $problem');
    }
    final startUrl = _text(input['startUrl']);
    final uri = startUrl == null ? null : Uri.tryParse(startUrl);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      throw BrowserError(
        'btest_run_start refused: startUrl must be an absolute http(s) URL, '
        'not "${input['startUrl']}"',
      );
    }
    final env = BtestEnv.parse(_text(input['env']));
    if (env == null) {
      throw BrowserError(
        'btest_run_start refused: env must be dev, test or prod, not '
        '"${input['env']}"',
      );
    }
    // The mode's priority (§3.3, written down): the call's parameter, then
    // the session's write switch, then `btest.readonly` — the switch reads
    // the setting itself when it was never picked. Resolved before rule A,
    // which judges the resolved mode (§3.7): env: prod with an implied
    // write is refused as surely as with the parameter.
    final mode = _text(input['mode']);
    final explicitFace = mode == null ? null : BtestFace.parse(mode);
    if (mode != null && explicitFace == null) {
      throw BrowserError(
        'btest_run_start refused: mode must be readonly or write, not '
        '"$mode"',
      );
    }
    final face =
        explicitFace ?? (state.write ? BtestFace.write : BtestFace.readonly);
    if (env == BtestEnv.prod && face == BtestFace.write) {
      // The refusal names both either way; an implied write also says where
      // it came from (the switch, or the setting behind it).
      final from = explicitFace != null
          ? ''
          : '（mode: write 由${state.writePicked ? '写开关' : '设置'}得来）';
      throw BrowserError('${BtestPolicy.ruleA}$from');
    }
    // The round's traversal (§3.9 / §9.1), same priority: the parameter,
    // then the session's traversal switch, then the built-in `surface` —
    // what a run did before the parameter existed. An illegal value is
    // named; a surface given stays surface.
    final traversalText = _text(input['traversal']);
    final explicitTraversal =
        traversalText == null ? null : BtestTraversal.parse(traversalText);
    if (traversalText != null && explicitTraversal == null) {
      throw BrowserError(
        'btest_run_start refused: traversal must be chain or surface, not '
        '"$traversalText"',
      );
    }
    final traversal = explicitTraversal ?? state.traversal;
    final repoRoot = _text(input['repoRoot']);
    if (repoRoot == null || !p.isAbsolute(repoRoot)) {
      throw BrowserError(
        'btest_run_start refused: repoRoot must be an absolute path, not '
        '"${input['repoRoot']}"',
      );
    }
    if (!Directory(repoRoot).existsSync()) {
      throw BrowserError(
        'btest_run_start refused: repoRoot "$repoRoot" is not a folder',
      );
    }
    final git = p.join(repoRoot, '.git');
    if (!FileSystemEntity.isDirectorySync(git) &&
        !FileSystemEntity.isFileSync(git)) {
      throw BrowserError(
        'btest_run_start refused: repoRoot "$repoRoot" holds no .git — it '
        "must be the business repository's root",
      );
    }
    final commitRange = _text(input['commitRange']);
    if (commitRange == null) {
      throw const BrowserError(
        'btest_run_start refused: commitRange is required',
      );
    }
    // Where the expect file goes (§3.4): the QA root's four branches, then
    // the repository's own folder under it — one workspace, one QA root.
    final qa = BtestQaRoot.resolve(
      repoRoot: repoRoot,
      cwd: call.cwd,
      configured: BtestSettings.qaRoot,
      setting: BtestSettings.qaRootKey,
    );
    if (qa.problem case final problem?) {
      throw BrowserError('btest_run_start refused: $problem');
    }
    final qaRoot = qa.root!;
    final expectFile = qaRoot.fileOf(repoRoot, line);
    // The folder may not exist yet (the QA root's first run). Made here,
    // once, so the run's write-back — and the agent's own file tools — meet
    // a folder rather than a path that cannot be resolved. A folder that
    // cannot be made is a readable refusal naming the root and the error
    // (§3.4 · §7 #28). No repository is initialized: the QA root is a plain
    // folder, never a git one.
    final folder = p.dirname(expectFile);
    try {
      Directory(folder).createSync(recursive: true);
    } on FileSystemException catch (error) {
      throw BrowserError(
        'btest_run_start refused: qaRoot "${qaRoot.root}" — "$folder" '
        'cannot be created (${error.osError?.message ?? error.message})',
      );
    }
    // The weights table (§3.9): one per QA root, built on first sight. The
    // run goes on with the built-in eight when it cannot be read or written
    // — a warning, never a refusal.
    final weights = BtestWeights.ensure(qaRoot.root);
    final BtestExpect expect;
    try {
      expect = BtestExpect.read(expectFile);
    } on FileSystemException catch (error) {
      throw BrowserError(
        'btest_run_start refused: expectFile "$expectFile" cannot be '
        'read: ${error.message.isEmpty ? error.osError : error.message}',
      );
    }
    final run = state.start(
      line: line,
      repoRoot: repoRoot,
      startUrl: startUrl!,
      env: env,
      face: face,
      traversal: traversal,
      expectFile: expectFile,
      qaRoot: qaRoot.root,
      commitRange: commitRange,
      baseline: expect.hash,
      cases: expect.cases,
    );
    final source = '来源=${qaRoot.source.label}';
    final reason = qaRoot.reason == null ? '' : ' · 降级原因=${qaRoot.reason}';
    return [
      '1. btest ${run.id} started · $line · ${env.name} · '
          'traversal=${run.traversal.name} · mode=${run.face.name} · '
          '${run.repo}',
      '2. expectFile（解析后的绝对路径）: $expectFile',
      '   $source$reason',
      '3. Case index (${expect.cases.length}):',
      '  ${expect.indexText.replaceAll('\n', '\n  ')}',
      '4. 内容 hash: ${expect.hash ?? 'absent'}（写回基线）',
      if (expect.absent) ...[
        'The file is absent: create it from this skeleton first, then act.',
        BtestExpect.skeleton(
          line: line,
          repo: run.repo,
          startUrl: startUrl,
          env: env.name,
          commitRange: commitRange,
        ),
      ],
      '5. 纪律：先读 $expectFile（case 与 expectFrom 都从文件来），再开始；'
          '不边走边停，收尾带 blockers / unconfirmedDiffs / uncovered，'
          '写回之后再 btest_run_end。',
      '6. weights（历史缺陷密度表）: ${weights.path} · '
          '来源=${weights.source.label}',
      '   生效序：${weights.orderLine}',
      for (final warning in weights.warnings) 'warning: $warning',
    ].join('\n');
  }

  static Future<Object> _endRun(
    Map<String, Object?> input,
    HostToolCall call,
  ) async {
    final state = BtestMode.find(call.cwd, call.sessionId);
    if (state == null || !state.on) {
      throw const BrowserError(
        'btest_run_end refused: btest is not on in this session',
      );
    }
    final run = state.run;
    if (run == null) {
      throw const BrowserError(
        'btest_run_end refused: no active run in this session',
      );
    }
    final said = _text(input['runId']);
    if (said != null && said != run.id) {
      throw BrowserError(
        'btest_run_end refused: "$said" is not this session\'s run '
        '(${run.id})',
      );
    }

    final checks = <String>[];
    final warnings = <String>[];

    // 1. The expect file, against the baseline run_start took.
    var write = BtestWrite.notWritten;
    var unreadable = false;
    try {
      final now = BtestExpect.read(run.expectFile);
      write = BtestExpect.statusOf(baseline: run.baseline, now: now);
    } on FileSystemException catch (error) {
      unreadable = true;
      warnings.add(
        'expectFile: not written — ${error.message.isEmpty ? error.osError : error.message}',
      );
    }
    checks.add(
      '1. 预期文件写回：expectFile: ${write.label}（${run.expectFile}；'
      '基线 ${run.baseline == null ? 'absent' : _short(run.baseline!)}）',
    );
    if (!unreadable && write == BtestWrite.notWritten) {
      warnings.add(
        'expectFile: not written — write it back before btest_run_end '
        '(design §3.4)',
      );
    }

    // 2. The three tail sections' keys; a chain round's breaks too.
    final missing = [
      for (final key in ['blockers', 'unconfirmedDiffs', 'uncovered'])
        if (input[key] is! List) key,
    ];
    final chain = _chainBreaks(run, input['chainBreaks']);
    checks.add(
      '2. 尾注与断点键：${missing.isEmpty ? 'blockers / unconfirmedDiffs / '
                'uncovered 都在' : '缺 ${missing.join(' / ')}'}${chain.text}',
    );
    if (missing.isNotEmpty) {
      warnings.add(
        'the payload lacks ${missing.join(', ')} — an empty array is fine, '
        'the key must be there',
      );
    }
    warnings.addAll(chain.problems);

    // 3. The coverage, against the index run_start returned.
    final index = {for (final one in run.cases) one.id};
    final coveredInput = input['coveredCases'];
    final covered = [
      if (coveredInput is List)
        for (final id in coveredInput) '$id',
    ];
    final outside = [
      for (final id in covered)
        if (!index.contains(id)) id,
    ];
    final issuesInput = input['issues'];
    if (input.containsKey('issues') && issuesInput is! List) {
      warnings.add(
        'issues is not a list — an empty array is fine, the field must be one',
      );
    }
    final issues = [
      if (issuesInput is List)
        for (final issue in issuesInput)
          if (issue is Map) issue.cast<String, Object?>(),
    ];
    final unpointed = <String>[];
    for (final (i, issue) in issues.indexed) {
      final caseId = _text(issue['caseId']);
      if (caseId == null) {
        unpointed.add('issues[${i + 1}].caseId is empty');
      } else if (!index.contains(caseId)) {
        unpointed.add('issues[${i + 1}].caseId "$caseId" is not in the index');
      }
      if (_text(issue['expectRef']) == null) {
        unpointed.add('issues[${i + 1}].expectRef is empty');
      }
    }
    // The pending items (§3.10): the run never judges them, but each must
    // point at a case and say whether it is a diff or a pending rule.
    final diffsInput = input['unconfirmedDiffs'];
    final diffs = [
      if (diffsInput is List)
        for (final diff in diffsInput)
          if (diff is Map) diff.cast<String, Object?>(),
    ];
    final unconfirmed = <String>[];
    for (final (i, diff) in diffs.indexed) {
      if (_text(diff['caseId']) == null) {
        unconfirmed.add('unconfirmedDiffs[${i + 1}].caseId is empty');
      }
      final kind = _text(diff['kind']);
      if (kind == null || !_diffKinds.contains(kind)) {
        unconfirmed.add(
          'unconfirmedDiffs[${i + 1}].kind must be diff or pending, not '
          '"${kind ?? ''}"',
        );
      }
    }
    checks.add(
      '3. 覆盖对账：coveredCases ${covered.length - outside.length}/'
      '${covered.length} 在索引；issues ${issues.length} 条，'
      '${unpointed.isEmpty ? 'caseId 与 expectRef 都在' : '${unpointed.length} 处不合格'}；'
      'unconfirmedDiffs ${diffs.length} 条，'
      '${unconfirmed.isEmpty ? 'caseId 与 kind 都在' : '${unconfirmed.length} 处不合格'}',
    );
    if (coveredInput is! List) {
      warnings.add(
        'coveredCases is not a list — the field is required (an empty array '
        'is fine)',
      );
    }
    if (outside.isNotEmpty) {
      warnings.add(
        'coveredCases: ${outside.join(', ')} not in the run\'s case index',
      );
    }
    warnings.addAll(unpointed);
    warnings.addAll(unconfirmed);

    // 4. What the run itself counted. 入口 is the declared entry alone; a
    // detour is a legal entry and is read apart (§3.8).
    final declared = run.declared;
    if (declared.isEmpty) {
      warnings.add('入口=0 — the run did not enter by its startUrl '
          '(${run.startUrl})');
    } else if (!BtestPolicy.sameUrl(declared.first.url, run.startUrl)) {
      warnings.add(
        '入口=${declared.first.url} is not the run\'s startUrl '
        '(${run.startUrl})',
      );
    }
    if (run.scriptsDenied > 0) {
      warnings.add(
        'evaluate 写值被拒 ${run.scriptsDenied} 次 — that is the reading of '
        'a script trying to write, not a pass',
      );
    }
    if (run.replayDenied > 0) {
      warnings.add(
        'replay 被拒 ${run.replayDenied} 次 — that is the reading of a script '
        'bypassing the form, not a pass',
      );
    }
    final detoured = [
      for (final issue in issues)
        if (_text(issue['detour']) != null) issue,
    ];
    if (run.detours.length != detoured.length) {
      warnings.add(
        '绕道对账：run 记了 ${run.detours.length} 条，报告绕道行 '
        '${detoured.length} 条（差 ${(run.detours.length - detoured.length).abs()}）',
      );
    }
    // 4-③'s reconcile: the run's fallback count is what the payload's
    // noVisibleText[] and the report's 无可见文字 rows must both read.
    final noVisibleInput = input['noVisibleText'];
    final noVisible = [
      if (noVisibleInput is List) for (final one in noVisibleInput) one,
    ];
    if (run.fallbackTargets != noVisible.length) {
      warnings.add(
        '无可见文字对账：ref/selector 兜底 ${run.fallbackTargets} 次，'
        'noVisibleText 记了 ${noVisible.length} 条'
        '（差 ${(run.fallbackTargets - noVisible.length).abs()}）',
      );
    }
    checks.add('4. ${run.truthLine(noVisibleText: noVisible.length)}');

    // 5. The weights table (§3.9): on disk with its eight classes, and every
    // `已修` marker naming a class the table holds.
    final weights = BtestWeights.check(run.qaRoot);
    final String weightText;
    if (weights.problem case final problem?) {
      weightText = problem;
    } else if (weights.missing.isNotEmpty) {
      weightText = '缺类目 ${weights.missing.join(' / ')}（类目不得删）';
    } else {
      weightText = '${BtestWeights.pathOf(run.qaRoot)} 在盘，八类齐';
    }
    checks.add('5. 权重表：$weightText');
    if (weights.problem case final problem?) {
      warnings.add('权重表：$problem');
    }
    if (weights.missing.isNotEmpty) {
      warnings.add(
        '权重表缺类目 ${weights.missing.join(' / ')} — 类目不得删（§3.9）',
      );
    }
    warnings.addAll(weights.warnings);

    state.end();
    return [
      'btest ${run.id} closed.',
      '收尾检查表（五项机械读数；第 4 项即报告头一行）：',
      ...checks,
      if (warnings.isNotEmpty) ...[
        '',
        for (final warning in warnings) 'warning: $warning',
      ],
      '',
      '报告头：${run.truthLine(noVisibleText: noVisible.length)}',
    ].join('\n');
  }

  /// The kinds an `unconfirmedDiffs` entry may take (§3.3, check 3): a diff
  /// between runs, or a rule the user still has to rule on.
  static const _diffKinds = {'diff', 'pending'};

  /// Check 2's chain half (§3.3): a chain run sends `chainBreaks` (an empty
  /// array is fine), and every break's four fields are filled, its reason one
  /// of the four named ones. `cause` is optional (§3.9): absent when no
  /// subagent was sent, and when it stands it must say something — the host
  /// judges the shape alone, never whether the conclusion is true. A surface
  /// run needs none.
  static ({String text, List<String> problems}) _chainBreaks(
    BtestRun run,
    Object? value,
  ) {
    if (run.traversal != BtestTraversal.chain) {
      return (text: '', problems: const []);
    }
    if (value is! List) {
      return (
        text: '；chainBreaks 缺键（chain 轮必带，可为空数组）',
        problems: const [
          'chainBreaks is missing — a chain run sends the key, even as []',
        ],
      );
    }
    final problems = <String>[];
    for (final (i, one) in value.indexed) {
      final item = one is Map
          ? one.cast<String, Object?>()
          : const <String, Object?>{};
      for (final field in const ['path', 'at', 'reason', 'verified']) {
        if (_text(item[field]) == null) {
          problems.add('chainBreaks[${i + 1}].$field is empty');
        }
      }
      final reason = _text(item['reason']);
      if (reason != null && !BtestPolicy.chainBreakReasons.contains(reason)) {
        problems.add(
          'chainBreaks[${i + 1}].reason "$reason" is not one of '
          '门控 / 无权限 / 数据不足 / 没有下一步',
        );
      }
      // A null is the field left out (nothing was found); a blank or a
      // non-string is a cause that says nothing.
      if (item['cause'] case final cause? when _text(cause) == null) {
        problems.add(
          cause is String
              ? 'chainBreaks[${i + 1}].cause is empty'
              : 'chainBreaks[${i + 1}].cause must be one string',
        );
      }
    }
    return (
      text: '；chainBreaks ${value.length} 条'
          '${problems.isEmpty ? '，四字段齐' : '，${problems.length} 处不合格'}',
      problems: problems,
    );
  }

  static String? _text(Object? value) => switch (value) {
    final String text when text.trim().isNotEmpty => text.trim(),
    _ => null,
  };

  static String _short(String hash) =>
      hash.length <= 12 ? hash : hash.substring(0, 12);
}
