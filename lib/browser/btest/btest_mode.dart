import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../chat/chat_models.dart' show ToolKind;
import '../../host_tools/host_tools.dart';
import '../../settings/user_settings.dart';
import '../browser_bridge.dart' show BrowserError;
import 'btest_expect_file.dart';
import 'btest_policy.dart';

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

  /// A test's values, in place of settings.json's.
  @visibleForTesting
  static Map<String, Object?>? values;

  static Set<String> get allowHosts => hostsOf(_read(allowHostsKey));
  static Set<String> get prodHosts => hostsOf(_read(prodHostsKey));

  /// Read-only unless the user turned it off.
  static bool get readonlyByDefault => _read(readonlyKey) != false;

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
    if (value is List)
      for (final host in value)
        if ('$host'.trim().isNotEmpty) '$host'.trim().toLowerCase(),
  };

  /// A text field's line as the list it sets: hosts by comma or space; none
  /// for blank.
  static List<String>? listOf(String text) {
    final hosts = [
      for (final host in text.split(RegExp(r'[,\s]+')))
        if (host.trim().isNotEmpty) host.trim().toLowerCase(),
    ];
    return hosts.isEmpty ? null : hosts;
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
    required this.line,
    required this.repoRoot,
    required this.startUrl,
    required this.env,
    required this.face,
    required this.expectFile,
    required this.expectFileRef,
    required this.commitRange,
    required this.baseline,
    required this.cases,
  });

  final String id;
  final String line;

  /// The business repository's root, absolute.
  final String repoRoot;

  /// Its name, from [repoRoot]'s last segment (§3.3: one source for it).
  String get repo => p.basename(repoRoot);

  /// The one URL this run enters by.
  final String startUrl;
  final BtestEnv env;
  final BtestFace face;

  /// The expect file, absolute; and as the run declared it.
  final String expectFile;
  final String expectFileRef;

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

  /// The report's head line (§3.8), read from the counters — the very one
  /// `btest_run_end` hands back to be pasted.
  String get truthLine => [
    '操作真实性：入口=${declared.length}'
        '（navigate=${_count('browser_navigate')}',
    'open=${_count('browser_open')}',
    if (_count('browser_act') > 0) 'act=${_count('browser_act')}）' else '）',
    'evaluate 写值被拒=$scriptsDenied',
    '文字定位=$wordsTargets',
    'ref/selector 兜底=$fallbackTargets',
    '绕道=${detours.length}',
    if (entriesDenied > 0) '入口被拒=$entriesDenied',
  ].join(' · ');

  int _count(String tool) =>
      declared.where((entry) => entry.tool == tool).length;
}

/// A conversation's btest state (§3.1): whether the mode is on, its run,
/// and how many runs it has had.
class BtestState {
  BtestState({this.key = ''});

  /// The key it is kept under (see [BtestMode.keyOf]).
  String key;

  bool on = false;

  /// The run under way; null between runs.
  BtestRun? run;

  int _runs = 0;

  BtestRun start({
    required String line,
    required String repoRoot,
    required String startUrl,
    required BtestEnv env,
    required BtestFace face,
    required String expectFile,
    required String expectFileRef,
    required String commitRange,
    required String? baseline,
    required List<BtestCase> cases,
  }) {
    final started = BtestRun(
      id: 'run-${++_runs}',
      line: line,
      repoRoot: repoRoot,
      startUrl: startUrl,
      env: env,
      face: face,
      expectFile: expectFile,
      expectFileRef: expectFileRef,
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
      run.entries.add(
        BtestEntry(
          tool: tool,
          url: url,
          detour: BtestPolicy.detourOf(tool, input),
        ),
      );
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
        'its expect file (docs/qa/<line>.md), the one entry URL, dev/test/'
        'prod, read-only or write. Returns the run id, the expect file\'s '
        'case index and its SHA-256 (the write-back baseline). btest refuses '
        'every browser action until a run is started, and one run at a '
        'time.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'line': {
          'type': 'string',
          'description': 'The business line, e.g. "订舱".',
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
          'description': 'Optional: read-only unless the btest settings say '
              'otherwise. env: prod with write is refused (rule A).',
        },
        'expectFile': {
          'type': 'string',
          'description': 'Relative to repoRoot: docs/qa/<line>.md.',
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
        'expectFile',
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
        '(coveredCases, issues, blockers, unconfirmedDiffs, uncovered) and '
        'returns the four mechanical readings — the expect file written '
        'back, the three tail keys there, the coverage reconciled, and the '
        'operation authenticity line the report is headed with. Write the '
        'expect file back BEFORE calling this.',
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
        'uncovered': {'type': 'array', 'items': {'type': 'object'}},
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
    final line = _text(input['line']);
    if (line == null) {
      throw const BrowserError('btest_run_start refused: line is required');
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
    final env = BtestEnv.parse(input['env'] as String?);
    if (env == null) {
      throw BrowserError(
        'btest_run_start refused: env must be dev, test or prod, not '
        '"${input['env']}"',
      );
    }
    final BtestFace face;
    final mode = _text(input['mode']);
    if (mode == null) {
      face = BtestSettings.readonlyByDefault
          ? BtestFace.readonly
          : BtestFace.write;
    } else if (BtestFace.parse(mode) case final parsed?) {
      face = parsed;
    } else {
      throw BrowserError(
        'btest_run_start refused: mode must be readonly or write, not '
        '"$mode"',
      );
    }
    if (env == BtestEnv.prod && face == BtestFace.write) {
      throw const BrowserError(BtestPolicy.ruleA);
    }
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
    final expectFileRef = _text(input['expectFile']);
    if (expectFileRef == null) {
      throw const BrowserError(
        'btest_run_start refused: expectFile is required',
      );
    }
    if (BtestExpect.relativeProblem(expectFileRef) case final problem?) {
      throw BrowserError('btest_run_start refused: $problem');
    }
    final expectFile = BtestExpect.resolve(repoRoot, expectFileRef);
    if (BtestExpect.writableProblem(expectFile) case final problem?) {
      throw BrowserError('btest_run_start refused: $problem');
    }
    // The folder the file goes in may not exist yet (a business repo's
    // docs/qa on its first run). Made here, once, so the run's write-back —
    // and the agent's own file tools — meet a folder rather than a path that
    // cannot be resolved. A folder that cannot be made is a readable refusal.
    try {
      Directory(p.dirname(expectFile)).createSync(recursive: true);
    } on FileSystemException catch (error) {
      throw BrowserError(
        'btest_run_start refused: ${p.dirname(expectFile)} cannot be made '
        '(${error.osError?.message ?? error.message})',
      );
    }
    final commitRange = _text(input['commitRange']);
    if (commitRange == null) {
      throw const BrowserError(
        'btest_run_start refused: commitRange is required',
      );
    }
    final BtestExpect expect;
    try {
      expect = BtestExpect.read(expectFile);
    } on FileSystemException catch (error) {
      throw BrowserError(
        'btest_run_start refused: expectFile "$expectFileRef" cannot be '
        'read: ${error.message.isEmpty ? error.osError : error.message}',
      );
    }
    final run = state.start(
      line: line,
      repoRoot: repoRoot,
      startUrl: startUrl!,
      env: env,
      face: face,
      expectFile: expectFile,
      expectFileRef: expectFileRef,
      commitRange: commitRange,
      baseline: expect.hash,
      cases: expect.cases,
    );
    return [
      'btest ${run.id} started · $line · ${env.name} · ${face.name} · '
          '${run.repo}',
      'expectFile: $expectFileRef (${expect.hash ?? 'absent'})',
      'Case index (${expect.cases.length}):',
      '  ${expect.indexText.replaceAll('\n', '\n  ')}',
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
      '先读 $expectFileRef（case 与 expectFrom 都从文件来），再开始。',
      'Never stop mid-run; close with blockers / unconfirmedDiffs / '
          'uncovered, after writing the file back and before btest_run_end.',
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
      '1. 预期文件写回：expectFile: ${write.label}（${run.expectFileRef}；'
      '基线 ${run.baseline == null ? 'absent' : _short(run.baseline!)}）',
    );
    if (!unreadable && write == BtestWrite.notWritten) {
      warnings.add(
        'expectFile: not written — write it back before btest_run_end '
        '(design §3.4)',
      );
    }

    // 2. The three tail sections' keys.
    final missing = [
      for (final key in ['blockers', 'unconfirmedDiffs', 'uncovered'])
        if (input[key] is! List) key,
    ];
    checks.add(
      '2. 三尾注字段：${missing.isEmpty ? 'blockers / unconfirmedDiffs / '
                'uncovered 都在' : '缺 ${missing.join(' / ')}'}',
    );
    if (missing.isNotEmpty) {
      warnings.add(
        'the payload lacks ${missing.join(', ')} — an empty array is fine, '
        'the key must be there',
      );
    }

    // 3. The coverage, against the index run_start returned.
    final index = {for (final one in run.cases) one.id};
    final covered = [
      for (final id in input['coveredCases'] as List? ?? const []) '$id',
    ];
    final outside = [
      for (final id in covered)
        if (!index.contains(id)) id,
    ];
    final issues = [
      for (final issue in input['issues'] as List? ?? const [])
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
    checks.add(
      '3. 覆盖对账：coveredCases ${covered.length - outside.length}/'
      '${covered.length} 在索引；issues ${issues.length} 条，'
      '${unpointed.isEmpty ? 'caseId 与 expectRef 都在' : '${unpointed.length} 处不合格'}',
    );
    if (outside.isNotEmpty) {
      warnings.add(
        'coveredCases: ${outside.join(', ')} not in the run\'s case index',
      );
    }
    warnings.addAll(unpointed);

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
    checks.add('4. ${run.truthLine}');

    state.end();
    return [
      'btest ${run.id} closed.',
      '收尾检查表（四项机械读数；第 4 项即报告头一行）：',
      ...checks,
      if (warnings.isNotEmpty) ...[
        '',
        for (final warning in warnings) 'warning: $warning',
      ],
      '',
      '报告头：${run.truthLine}',
    ].join('\n');
  }

  static String? _text(Object? value) => switch (value) {
    final String text when text.trim().isNotEmpty => text.trim(),
    _ => null,
  };

  static String _short(String hash) =>
      hash.length <= 12 ? hash : hash.substring(0, 12);
}
