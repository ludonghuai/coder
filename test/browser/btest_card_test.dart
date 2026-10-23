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
      for (var i = 1; i <= 8; i++) {
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
      // The label form above is what the card reads: D1 … D8, J1 … J7.
      expect(BtestCard.text, contains('[D8]'));
      expect(BtestCard.text, contains('[P20]'));
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

    test('a chain break sends its why to a read-only subagent, capped (§3.9, §7 #41/#42)', () {
      // The rule's only carrier is the card: the host judges the cause's
      // shape alone (§3.3, check 2), so dropping these sentences would let
      // the behaviour go with nothing failing.
      expect(
        BtestCard.text,
        contains("write it into that break's cause"),
        reason: 'a break’s finding goes into cause',
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
