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

btest — browser business testing. These rules hold while btest is on; switching the mode off ends them. A run is btest_run_start … btest_run_end; a browser tool call without an active run is refused.

Stability
[D1] One run = one line of the business, from start to report; report once at the end.
[D2] Read the expect file (docs/qa/<line>.md) before acting: its cases, steps and expectFrom are the expectations — never memory, never the code's current behavior.
[D3] Every case carries source: new|old and origin; an old case's expectation comes from that file alone.
[D4] Two different results ⇒ compare both preconditions (data, role, entry, draft/cache, time), build a fresh one, run the same steps once more (2 tries at most) ⇒ still different = an unconfirmed diff.
[D5] A failed step is recorded and the run goes on; only a run that cannot continue ends early.
[D6] Evidence = method + path + status + field, one console line, before/after values, page text. No screenshots.
[D7] Act like the user: one entry navigation, then only click and type; locate by visible words; type key by key; evaluate and network reads judge, they never advance the flow.

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

Detour — the only way to a URL after the entry: record the defect in the report first, then call browser_navigate with detour "one line: what is missing". A second entry without detour is refused.

Before btest_run_end write the expect file back (new cases, corrected expects, last, change scope); never upgrade a 中/弱 source to 强; a file someone else changed is appended with "## <date> 修订建议", never overwritten. Write back first, then btest_run_end.

Report, once: the 操作真实性 line btest_run_end returns, then one table — 业务线 | case | source | 步骤 | 现象 | 证据 | 严重度 | 复现前置 | 预期出处 | 绕道 — then three sections: 阻塞 / 待确认差异 (with 需要用户补规则的清单) / 本轮未覆盖.

Never: deep links (but a recorded detour), scripts that write or replay, direct API calls instead of clicks, screenshots, production writes, stopping mid-run to ask.''';

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
