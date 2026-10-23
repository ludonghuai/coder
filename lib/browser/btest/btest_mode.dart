import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../chat/chat_models.dart' show ToolKind;
import '../../host_tools/host_tools.dart';
import '../../settings/user_settings.dart';
import '../browser_bridge.dart' show BrowserError;
import 'btest_expect_file.dart' show BtestCase;
import 'btest_policy.dart';
import 'btest_run_end.dart';
import 'btest_run_state.dart';

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

  /// Whether the mode was on when its session closed (§9.1, F11).
  static const onKey = 'btest.on';

  /// The traversal the last session picked (§9.1, F11): `chain` / `surface`.
  static const traversalKey = 'btest.traversal';

  /// The write switch the last session picked (§9.1, F11): `readonly` /
  /// `write`.
  static const modeKey = 'btest.mode';

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

  /// Whether btest was on (§9.1, F11): `btest.on` holds a bool, and only
  /// `true` turns the mode on — a string or a number is not one.
  static bool get on => _read(onKey) == true;

  /// The traversal the last session picked (§9.1); null when the key is
  /// missing or holds anything but `chain` / `surface` — the reader then
  /// falls back to the built-in `surface`.
  static BtestTraversal? get traversal => switch (_read(traversalKey)) {
    final String text => BtestTraversal.parse(text),
    _ => null,
  };

  /// The write switch the last session picked (§9.1); null when the key is
  /// missing or holds anything but `readonly` / `write` — the switch then
  /// stays unpicked and `btest.readonly` stands (§9.1「写初始」).
  static bool? get write {
    final face = switch (_read(modeKey)) {
      final String text => BtestFace.parse(text),
      _ => null,
    };
    return face == null ? null : face == BtestFace.write;
  }

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

  /// Keeps [key] as [value] in settings.json; null removes it (what
  /// `update` means, `user_settings.dart:26-27`). A test's [values] takes
  /// the change in place of the file, so a test never writes the machine's
  /// settings. A write that fails is one debugPrint and nothing else: the
  /// session keeps the value it just took, and the next one reads what the
  /// file still holds (§9.1, KD-30 ③).
  static void put(String key, Object? value) {
    if (values case final values?) {
      if (value == null) {
        values.remove(key);
      } else {
        values[key] = value;
      }
      return;
    }
    unawaited(
      SettingsFiles.instance.settings.update(key, value).catchError((
        Object error,
      ) {
        debugPrint('$key not kept: $error');
      }),
    );
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

/// A conversation's btest state (§3.1): whether the mode is on, its run,
/// the two run switches (§9.1), and how many runs it has had.
class BtestState {
  BtestState({this.key = ''});

  /// The key it is kept under (see [BtestMode.keyOf]).
  String key;

  bool _on = false;

  /// Whether the mode is on in this conversation.
  bool get on => _on;

  /// Turns it on or off (§3.1) and keeps it for the next start (§9.1,
  /// F11): on ⇒ `btest.on` written as `true`; off ⇒ the key removed.
  set on(bool value) {
    _on = value;
    BtestSettings.put(BtestSettings.onKey, value ? true : null);
  }

  /// How the next run walks (§9.1): the traversal switch, kept in
  /// `btest.traversal` so the next session reads it back (F11).
  BtestTraversal? _traversal;

  /// Whether the next run may act (§9.1): the write switch, kept in
  /// `btest.mode`. Null until picked — `btest.readonly` then stands.
  bool? _write;

  /// Takes this state's first values from the settings (§9.1, F11): the
  /// three keys written straight into the fields, never through a setter —
  /// opening a conversation writes none of them (§7 #44). A key that is
  /// missing or holds something else falls back: off, the built-in
  /// `surface`, and the write switch left unpicked.
  void fromSettings() {
    _on = BtestSettings.on;
    _traversal = BtestSettings.traversal ?? BtestTraversal.surface;
    _write = BtestSettings.write;
  }

  /// What the traversal switch reads now: its own value, else the built-in
  /// `surface` — what a round did before the switch existed (KD-21).
  BtestTraversal get traversal => _traversal ?? BtestTraversal.surface;

  /// Picks how the next run walks (§9.1): the switch, kept in
  /// `btest.traversal` (§9.1「持久化」). A run under way keeps the traversal
  /// it started with (§9.1: a click only moves the switch).
  set traversal(BtestTraversal value) {
    _traversal = value;
    BtestSettings.put(BtestSettings.traversalKey, value.name);
  }

  /// Whether the write switch reads `允许写` now: its own value, else the
  /// settings' default — read-only unless `btest.readonly` is off.
  bool get write => _write ?? !BtestSettings.readonlyByDefault;

  /// Picks whether the next run may act (§9.1): the switch alone, kept in
  /// `btest.mode` (§9.1「持久化」); a run under way keeps its own.
  set write(bool value) {
    _write = value;
    BtestSettings.put(
      BtestSettings.modeKey,
      value ? BtestFace.write.name : BtestFace.readonly.name,
    );
  }

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
}

/// Where each conversation's btest state lives (§3.1: a host overlay, kept
/// by session — the tool layer and the composer read the same one).
abstract final class BtestMode {
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
    run: btestStartRun,
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
    run: btestEndRun,
  );
}
