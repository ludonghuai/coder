import 'package:baocode/browser/btest/btest_card.dart';
import 'package:flutter_test/flutter_test.dart';

// The mode card's text and the count that decides its telling (design
// §3.2): one card while the mode is on, one off line after it, and none
// twice.
void main() {
  /// What the conversation would hold after [text] was told.
  List<String> withText(List<String> told, String? text) => [...told, ?text];

  group('the card', () {
    test('carries its marker exactly once', () {
      expect(BtestCard.countIn(BtestCard.text, BtestCard.marker), 1);
      expect(BtestCard.marker, '[btest-mode-card v1]');
    });

    test('never spells the line that ends it', () {
      expect(BtestCard.countIn(BtestCard.text, BtestCard.offMarker), 0);
      expect(BtestCard.countIn(BtestCard.offText, BtestCard.marker), 0);
      expect(BtestCard.countIn(BtestCard.offText, BtestCard.offMarker), 1);
    });

    test('holds every label the content check lists', () {
      for (var i = 1; i <= 9; i++) {
        expect(BtestCard.text, contains('[D$i]'));
      }
      for (var i = 1; i <= 7; i++) {
        expect(BtestCard.text, contains('[J$i]'));
      }
      for (var i = 1; i <= 20; i++) {
        expect(
          BtestCard.text,
          contains('[P${i.toString().padLeft(2, '0')}]'),
          reason: 'problem domain $i',
        );
      }
      for (var i = 1; i <= 3; i++) {
        expect(BtestCard.text, contains('[H$i]'));
      }
      // The label form above is what the card reads: D1 … D9, J1 … J7.
      expect(BtestCard.text, contains('[D8]'));
      expect(BtestCard.text, contains('[D9]'));
      expect(BtestCard.text, contains('[P20]'));
      // 39 labels in all, each exactly once (§6 F2 ②).
      final labels = RegExp(r'\[(?:D\d|J\d|P\d\d|H\d)\]')
          .allMatches(BtestCard.text)
          .map((m) => m[0])
          .toList();
      expect(labels, hasLength(39));
      expect(labels.toSet(), hasLength(39));
    });

    test('the manual hand-off keeps both cases and three bans (§3.11, F12)', () {
      // Case B is the default: the run goes on and the step is recorded.
      expect(BtestCard.text, contains('do NOT stop'));
      expect(BtestCard.text, contains('record it in uncovered'));
      // The why is a datum of the report, not prose: §3.11 fixes it in
      // Chinese (one string for the card, §6 F12 and §7 #47).
      expect(BtestCard.text, contains('why = 需人工上传，本轮未执行'));
      expect(
        BtestCard.text,
        isNot(contains('needs a manual upload, not run this round')),
        reason: 'the old English value is gone (§3.11 取值语种)',
      );
      // Case A stops only when the user asks for it, and the same run carries
      // on after the wait — the wait is not a break.
      expect(
        BtestCard.text,
        contains('Only when the user asks to test this upload feature on its own'),
      );
      expect(
        BtestCard.text,
        contains('请你在这里选文件上传（<业务线> · <本步在做什么>），传完回我「好了」。'),
      );
      expect(
        BtestCard.text,
        contains('bring the page to that step'),
        reason: 'case A brings the page to the upload step (§6 F12 A)',
      );
      expect(
        BtestCard.text,
        contains('and end the turn'),
        reason: 'the stop ends the turn; no tool call follows the sentence',
      );
      expect(
        BtestCard.text,
        contains("then read the attachment list and the record's snapshot"),
        reason: 'after 「好了」 the bound file is read again (§6 F12 A, [P07])',
      );
      expect(
        BtestCard.text,
        contains("wait for the user's 「好了」 in the same conversation"),
      );
      expect(
        BtestCard.text,
        contains('The same runId continues — no new run'),
      );
      expect(
        BtestCard.text,
        contains("case A's wait is not a chain break"),
        reason: 'the hand-off wait never enters chainBreaks (§3.11)',
      );
      // Ban 1 names the browser_upload / file-parameter route (review #91):
      // a file already on disk is no way to stand in for the person.
      expect(BtestCard.text, contains('do not click the file input'));
      expect(BtestCard.text, contains('do not call browser_upload'));
      expect(BtestCard.text, contains('carries a file parameter'));
      expect(
        BtestCard.text,
        contains('a file that already sits in the repository is no exception'),
      );
      expect(
        BtestCard.text,
        contains("a write run's wider action list does not lift this ban"),
      );
      // Bans 2 and 3: no temporary file, no API detour.
      expect(
        BtestCard.text,
        contains('never write a temporary file to fill the gap'),
      );
      expect(
        BtestCard.text,
        contains('never call an API to get around the page'),
      );
    });

    test('carries the traversal discipline, the weight order and the report face (§3.8, §3.9)', () {
      expect(BtestCard.text, contains('chain'));
      expect(BtestCard.text, contains('surface'));
      expect(BtestCard.text, contains('lost on refresh'));
      expect(BtestCard.text, contains('amount reconciliation'));
      expect(BtestCard.text, contains('duplicate submit'));
      expect(BtestCard.text, contains('已修'));
      expect(
        BtestCard.text,
        contains('take the one tied to the higher-weight class'),
        reason: 'a chain round picks its next step by the weights (§3.9)',
      );
      expect(BtestCard.text, contains('traversal=<chain|surface>'));
      expect(
        BtestCard.text,
        contains('# | 业务线 | case | source | 步骤 | 现象 | 证据 | 严重度 | 判定 | '
            '复现前置 | 预期出处 | 绕道 | 建议'),
        reason: '13 columns, the row number and both judgement columns in',
      );
      expect(BtestCard.text, contains('判定'));
      expect(BtestCard.text, contains('建议'));
      expect(BtestCard.text, contains('待研判 · <原因>'));
    });

    test('a chain break is sent at once and never waited on (§3.9, §7 #41/#42)', () {
      // The rule's only carrier is the card: the host judges the cause's
      // shape alone (§3.3, check 2), so dropping these sentences would let
      // the behaviour go with nothing failing.
      expect(
        BtestCard.text,
        contains('the moment a break is recorded, send one and keep walking'),
        reason: 'a break is sent the moment it happens',
      );
      expect(
        BtestCard.text,
        contains('never wait for its answer'),
        reason: 'an answer never blocks the walk',
      );
      expect(
        BtestCard.text,
        contains("goes into that break's cause"),
        reason: 'an answer that arrives before the run ends lands in cause',
      );
      expect(
        BtestCard.text,
        contains('goes into your closing message'),
        reason: 'an answer that arrives after the run ends lands in the report',
      );
      expect(
        BtestCard.text,
        contains('do not reopen the run or block on it'),
        reason: 'a late answer never reopens the run',
      );
      expect(
        BtestCard.text,
        contains('a late answer simply leaves cause absent'),
        reason: 'cause stays optional',
      );
      expect(
        BtestCard.text,
        contains('explore, else plan'),
        reason: 'the read-only fallback',
      );
      expect(BtestCard.text, contains('reason stays one of the four'));
      expect(
        BtestCard.text,
        contains('At most 3 per run'),
        reason: 'the cap',
      );
      expect(BtestCard.text, contains('未查明（达到本轮研判上限）'));
      expect(
        BtestCard.text,
        contains('未查明（<原因>）'),
        reason: 'an unavailable subagent still says why it is unknown',
      );
      expect(
        BtestCard.text,
        contains('not sent to the F8 review'),
        reason: 'one break is not sent twice (F8)',
      );
    });
  });

  group('when a turn is assembled (§3.2)', () {
    test('a fresh mode tells the card, and only once', () {
      expect(BtestCard.forTurn(on: true, transcript: const []), BtestCard.text);
      expect(
        BtestCard.forTurn(on: true, transcript: [BtestCard.text]),
        isNull,
      );
      expect(
        BtestCard.forTurn(on: true, transcript: ['a message', BtestCard.text]),
        isNull,
      );
    });

    test('a mode switched off tells the off line, once', () {
      final told = withText(const [], BtestCard.text);
      final off = BtestCard.forTurn(on: false, transcript: told);
      expect(off, BtestCard.offText);
      expect(
        BtestCard.forTurn(on: false, transcript: withText(told, off)),
        isNull,
      );
      expect(BtestCard.forTurn(on: false, transcript: const []), isNull);
    });

    test('a session resumed with the card in it tells nothing (#11)', () {
      expect(
        BtestCard.forTurn(on: true, transcript: ['restored', BtestCard.text]),
        isNull,
      );
      expect(
        BtestCard.forTurn(on: true, transcript: ['restored']),
        BtestCard.text,
        reason: 'no card in what the session came back with',
      );
    });

    test('back on after a turn told the off line re-tells the card (#22)', () {
      var told = withText(const [], BtestCard.forTurn(on: true, transcript: const []));
      told = withText(told, BtestCard.forTurn(on: false, transcript: told));
      expect(BtestCard.difference(told), 0);
      final again = BtestCard.forTurn(on: true, transcript: told);
      expect(again, BtestCard.text, reason: 'the card went stale');
      told = withText(told, again);
      expect(BtestCard.difference(told), 1);
      expect(BtestCard.countIn(told.join('\n'), BtestCard.marker), 2);
      expect(BtestCard.countIn(told.join('\n'), BtestCard.offMarker), 1);
    });

    test('back on with no turn in between tells nothing (#23)', () {
      var told = withText(const [], BtestCard.forTurn(on: true, transcript: const []));
      expect(BtestCard.forTurn(on: false, transcript: told), BtestCard.offText);
      // Switched back on before that line was ever told: it is dropped.
      final again = BtestCard.forTurn(on: true, transcript: told);
      expect(again, isNull, reason: 'the card never went stale');
      told = withText(told, again);
      expect(BtestCard.countIn(told.join('\n'), BtestCard.offMarker), 0);
      expect(BtestCard.difference(told), 1);
    });

    test('a card told twice reads as two (the count names it)', () {
      expect(
        BtestCard.difference([BtestCard.text, BtestCard.text]),
        2,
      );
    });
  });
}
