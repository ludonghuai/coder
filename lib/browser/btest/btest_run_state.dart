/// One run's lifetime (design §3.3), split out of `btest_mode.dart` by
/// SPLIT-5: what a run declared and the counters its fourth check reads
/// ([BtestRun]), what a call did to it ([BtestRunRecord]), and the call that
/// opens one ([btestStartRun]). The mode's own state stays in `btest_mode`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../host_tools/host_tools.dart';
import '../browser_bridge.dart' show BrowserError;
import 'btest_expect_file.dart';
import 'btest_mode.dart';
import 'btest_policy.dart';
import 'btest_weights.dart';

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

/// What a verdict did to the run under way (§3.3, check 4), as an extension
/// so the call site stays `state.recordAllowed(...)` although the fields
/// live here (SPLIT-5).
extension BtestRunRecord on BtestState {
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
        _countTarget(run, target);
      }
    } else if (decision.target case final target?) {
      _countTarget(run, target);
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
}

/// One allowed call's aim, counted (§3.3, 4-③).
void _countTarget(BtestRun run, BtestTarget target) => switch (target) {
  BtestTarget.words => run.wordsTargets++,
  BtestTarget.fallback => run.fallbackTargets++,
};

/// [value] as a trimmed non-empty string, else null: what the tools read
/// their text inputs with.
String? btestText(Object? value) => switch (value) {
  final String text when text.trim().isNotEmpty => text.trim(),
  _ => null,
};

/// `btest_run_start` (§3.3): checks the call, derives the expect file's
/// path (§3.4), opens the run and returns the six items the model acts on.
/// The tool itself — its schema and description — stays in `btest_mode`.
Future<Object> btestStartRun(
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
  final line = btestText(input['line']) ?? '';
  if (BtestExpect.lineProblem(line) case final problem?) {
    throw BrowserError('btest_run_start refused: $problem');
  }
  final startUrl = btestText(input['startUrl']);
  final uri = startUrl == null ? null : Uri.tryParse(startUrl);
  if (uri == null ||
      !(uri.isScheme('http') || uri.isScheme('https')) ||
      uri.host.isEmpty) {
    throw BrowserError(
      'btest_run_start refused: startUrl must be an absolute http(s) URL, '
      'not "${input['startUrl']}"',
    );
  }
  final env = BtestEnv.parse(btestText(input['env']));
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
  final mode = btestText(input['mode']);
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
  final traversalText = btestText(input['traversal']);
  final explicitTraversal =
      traversalText == null ? null : BtestTraversal.parse(traversalText);
  if (traversalText != null && explicitTraversal == null) {
    throw BrowserError(
      'btest_run_start refused: traversal must be chain or surface, not '
      '"$traversalText"',
    );
  }
  final traversal = explicitTraversal ?? state.traversal;
  final repoRoot = btestText(input['repoRoot']);
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
  final commitRange = btestText(input['commitRange']);
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
