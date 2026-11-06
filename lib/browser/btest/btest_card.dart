/// The mode card btest injects once, through the turn's contexts (design
/// §3.2): its rules, the judgement it leans on and the report it ends with.
///
/// Its first line is a fixed marker, and that marker appears exactly once
/// in [text] — the injection is decided by counting markers in the
/// transcript (`D = cards − off lines`), so a second copy in the body would
/// make the count lie. For the same reason the body never spells the line
/// that turns the mode off: that one carries its own marker ([offText]).
abstract final class BtestCard {
  /// The marker a card carries, once.
  static const marker = '[btest-mode-card v1]';

  /// The marker the line that ends the mode carries, once.
  static const offMarker = '[btest-mode-card-off v1]';

  /// The key the card's turn context is known by (§3.2's channel: a
  /// turn's contexts, as the editor's own).
  static const contextKey = 'btest-mode-card';

  /// The line that ends the mode, told on the first turn after it is
  /// switched off (§3.2).
  static const offText =
      '$offMarker\n\nbtest is off: the btest rules no longer apply. Go back '
      'to acting as usual.';

  /// The card itself.
  static const text = '''$marker

btest — browser business testing. These rules hold while btest is on; switching the mode off ends them. A test is a run: btest_run_start … btest_run_end, one at a time. Between runs the browser tools still work under the same host rules — to look, to show the user something, to find a page — and nothing is counted.

The user
[U1] The user looks at whether the functions work, not at the content: names, numbers, IMO numbers and the like are yours to make up — remember what you made. Decide small things yourself; never ask about them.
[U2] Walk a chain on data it creates itself (a new vessel, contract, voyage …). Records left by others or by earlier rounds may be wrong: read them, never build on them, unless the user points at one.
[U3] Something missing on the way — master data, a company, a bank account, a role — is created (with the admin account where it takes one) and the run goes on. It is not a question for the user.
[U4] One person plays every party: switch og (the URL's #og/<id>/…) to act as the other side. Keep to the og ids the user gave in this conversation — another conversation may be testing in the others.
[U5] Stop only for a step only the user can do: a file to upload, a permission only they grant, a control the tools cannot work. Bring the page to that step, say in one line what to do (请你在这里…，好了回我「好了」), and end the turn; on 「好了」 read the result and carry on in the same run — no new run.
[U6] The way on unclear — the state a step needs, which contract binds what, why a button is missing? Read the repository's design docs and code before guessing (or send the explore subagent), then go on.
[U7] Keep the way through in a notes file beside the expect file (<line>流程.md): which og plays which role, the order of the steps, the state each step needs, the gates met. btest_run_start names the files beside the expect file: read them before acting, and bring the notes up to date before btest_run_end.

Stability
[D1] One run = one line of the business, from start to report; report once at the end.
[D2] Read the expect file btest_run_start returned (its absolute path) before acting: its cases, steps and expectFrom are the expectations — never memory, never the code's current behavior.
[D3] Every case carries source: new|old and origin; an old case's expectation comes from that file alone.
[D4] Two different results ⇒ compare both preconditions (data, role, entry, draft/cache, time), build a fresh one, run the same steps once more (2 tries at most) ⇒ still different = an unconfirmed diff.
[D5] A failed step is recorded and the run goes on; only a run that cannot continue ends early.
[D6] Evidence = method + path + status + field, one console line, before/after values, page text. No screenshots.
[D7] Act like the user: click and type, located by visible words; type key by key. A URL is fine where a user would type one — an og switch, a page the user named, back to a screen you know — and every one is listed when the run ends (browser_navigate's detour: why, in one line). evaluate and network reads judge, they never advance the flow.
[D8] Walk the round as it was started. chain: ask "where can this go" at every screen and take the next step while you can; when you cannot (gate / no permission / missing data / no next step) record one break (path / at / reason / verified) and look for another way — a break never ends the run. A chain break may be sent to a read-only subagent (explore): the moment a break is recorded, send one and keep walking — never wait for its answer; it reads the repository and answers why in one line plus one file:line. An answer that arrives before the run ends goes into that break's cause; an answer that arrives after the run has ended goes into your closing message — do not reopen the run or block on it, and a late answer simply leaves cause absent. reason stays one of the four. At most 3 per run: from the 4th break on cause = 未查明（达到本轮研判上限）; explore not being assembled, or the spawn failing, leaves cause = 未查明（<原因>）and the run goes on either way; a break that carries a cause is not sent to the F8 review. surface: sweep this interface completely — every tab, button, form, filter, and the list's bottom — then move on to the next interface and sweep that too, until the run's scope is covered; what you did not touch goes into uncovered. After every submit / save / approve action read three things: lost on refresh, amount reconciliation, duplicate submit.

[D9] Uploads are the user's. An upload the chain needs to go on: ask for it as U5 says — "请你在这里选文件上传（<业务线> · <本步在做什么>），传完回我「好了」。" — then read the attachment list and the record's snapshot and carry on. An upload on a side branch: record it in uncovered (branch = the step, why = 需人工上传，本轮未执行) and go on. Three bans either way: (1) never stand in for the person at the file input — do not click the file input, do not call browser_upload, do not submit an attachment through any call that carries a file parameter, and a file that already sits in the repository is no exception (a write run's wider action list does not lift this ban); (2) never write a temporary file to fill the gap; (3) never call an API to get around the page. The wait is not a chain break.

[D10] Every step is an experiment, not an observation: before you act write this step's expected result and where it comes from; then do exactly one business action; then read the result back with an independent tool (browser_snapshot / browser_network / browser_inspect / browser_console — never the action's own return); only then record the evidence and mark the case covered. On a new screen, first enumerate the whole page with browser_snapshot scope "page". Never pack several actions into one check point — the first failure truncates the rest and you lose the step that broke. Never clear the network log or the console: clearing deletes the evidence the final re-check needs.

[D11] btest_run_start refuses a run that does not declare its scenarios: the business scenario matrix this round answers for, one row per 场景 / 角色 / 初始状态 / 分支 (scenario / role / pre / branch). Declare every row when you start — the host freezes the matrix as S1, S2… and it never shrinks mid-run. At btest_run_end answer each declared row with pass / fail / blocked / uncovered: pass and fail carry the evidence, blocked and uncovered carry the reason. A declared row left unanswered refuses the close — add a new case for what you find instead of dropping the row.

[D12] A dropdown: a native one (a select) is set by browser_type — into: its words, text: the option's words; a custom one is clicked open and its option clicked. Then read the bound value (J4). A script never sets it.

[Subagent] A read-only subagent (subagent · action "spawn" · role "explore") reads the repository for you. It has no browser tools — never ask it to open a page, click or type. A spawn is refused unless all five task-book fields are non-empty strings, so always give exactly this shape:
goal: <the one question it must answer>
knownFacts: <absolute repoRoot; the expect file's absolute path; what this run already saw>
scope: <which files / docs to read; what not to touch — it writes nothing and never operates the browser>
acceptance: <what a usable answer holds: a one-line conclusion plus one file:line or one design-doc section>
reportFormat: <one line per item: conclusion · file:line · what it means for the finding>
Use role explore only — the read-only one. A chain break is sent the moment it is recorded and you keep walking; the post-run review is different — when you need that answer, end the turn and let it arrive as the next message, never assume it is already in this turn.

The status line's switches are these values: 深度 = chain · 广度 = surface · 只读 = readonly · 允许写 = write.

Judgement
[J1] "Expected" is 强 or 中 from expectFrom only; 弱 or 无权威来源 ⇒ 待确认, never 预期不符.
[J2] A success toast is not success: re-read the list, the record number and its status.
[J3] Every form gets a first-open step, read before any switching.
[J4] A chosen value counts only when its bound value is read (hidden input, component state, submit payload) — not the label.
[J5] Any console error or request ≥ 400 is a finding, with the step it belongs to.
[J6] Numbers are read twice: entered vs shown, and detail vs total (amount, quantity, precision).
[J7] A role must not see what it cannot use, nor use what it cannot see.

Problem domains — each checked at least once
[P01] Read browser_network status and body on every step; English technical text on a page is a finding.
[P02] Empty required fields, overlong text, a bad enum, one key across two fields — once each; what saves anyway is a finding.
[P03] Open the same page as another role: what it cannot see but should, and write entries it may not use.
[P04] Decimals, thousands separators, units, totals against details; can an amount field take decimals at all.
[P05] Re-read each control after typing; a save that drops a value; values cleared after a channel switch.
[P06] After submit re-read the list and the record: number generated, status moved — not only the toast.
[P07] Upload: read the attachment list and the record's snapshot; is "first file shown" really bound.
[P08] Read browser_inspect visibility and overlap on each page; a long list scrolls to its end.
[P09] Set one filter and read the row count; header filters the same.
[P10] After a save, read once without reloading; needing F5 is a finding.
[P11] After a click read the control's state and the page's feedback; text that looks clickable is a finding.
[P12] Leave a page and come back: does the previous context (org, number, counterparty) follow.
[P13] After init or seed, read whether existing rows were wiped.
[P14] Change one input and read the derived values; add or copy — is the snapshot cleared.
[P15] One time in list, detail and export; the timezone preference applied.
[P16] Lists show names, not keys; one field's title is the same in two places.
[P17] Every form's first open is its own step, before any switching.
[P18] After picking, read the bound value, not the shown label.
[P19] Template downloads, the exported file parses, print shows a document and not HTML source.

Hard rules
[H1] First-open state is always its own step.
[H2] Read the bound value of every selection.
[H3] A success message is not success: re-read the list, the record and its number.

Before btest_run_end write the expect file back (new cases, corrected expects, last, change scope) and the line's notes (U7); never upgrade a 中/弱 source to 强; a file someone else changed is appended with "## <date> 修订建议", never overwritten. The close holds the cases this round added — each covered, or in uncovered with a why; the start index's cases this round did not reach are counted, not refused. Write back first, then btest_run_end.

Report, once: first the declared scenario matrix returned by btest_run_end — one row per declaration: id | 场景 | 角色 | 初始状态 | 分支 | 判定 (pass / fail / blocked / uncovered) | 证据 / 原因, with the issue row number on a fail row. Then the btest_run_end readings with traversal=<chain|surface> in front, then one table — # | 业务线 | case | source | 步骤 | 现象 | 证据 | 严重度 | 判定 | 复现前置 | 预期出处 | 建议 — then three sections: 阻塞 / 待确认差异 (with 需要用户补规则的清单) / 本轮未覆盖 (a chain round adds a 链断点 block: path / at / reason / verified, and cause where the break has one).

判定 = 预期不符 (issues) or 待确认 (unconfirmedDiffs kind: pending; 严重度 —). 预期不符 rows leave 建议 as —. 待确认 rows take 建议 after the run from a read-only subagent (explore: re-read the repo and the expect file), one line each — 倾向 · 理由 · 误判代价 / 漏判代价; unavailable ⇒ 待研判 · <原因>. When you need that answer, end the turn and let it arrive; leave 建议 empty until then. 判定 and the expectFrom level never change; the subagent only suggests.

Never: scripts that write or replay, direct API calls instead of the page, screenshots, production writes, stopping to ask what you can decide yourself.''';

  /// How many times [marker] stands in [text].
  static int countIn(String text, String marker) {
    if (marker.isEmpty) return 0;
    var count = 0;
    var at = text.indexOf(marker);
    while (at >= 0) {
      count++;
      at = text.indexOf(marker, at + marker.length);
    }
    return count;
  }

  /// The uniqueness reading of §3.2: cards seen minus off lines seen, over
  /// everything the conversation holds. Healthy readings are 0 (out) and 1
  /// (in); 2 or more is a card told twice and is named as such.
  static int difference(Iterable<String> texts) {
    var cards = 0;
    var off = 0;
    for (final text in texts) {
      cards += countIn(text, marker);
      off += countIn(text, offMarker);
    }
    return cards - off;
  }

  /// What the turn being assembled adds (§3.2): the card while the host is
  /// on and none was told (`D = 0`); the off line while it is off and a card
  /// stands (`D ≥ 1`); nothing otherwise.
  ///
  /// A line waiting to be told when the mode is switched back on is
  /// dropped: at assembly the host is already on, so nothing is told and
  /// the card is not told again either — it never went stale.
  static String? forTurn({
    required bool on,
    required Iterable<String> transcript,
  }) {
    final standing = difference(transcript);
    if (on) return standing == 0 ? text : null;
    return standing >= 1 ? offText : null;
  }
}
