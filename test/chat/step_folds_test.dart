import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/step_folds.dart';

const _thought = ThinkingItem(text: 'Hm.', tokens: 3, seconds: 4);
const _read = ToolCallItem(kind: ToolKind.read, target: 'a.dart');
const _grep = ToolCallItem(kind: ToolKind.grep, target: 'foo');
const _edit = CodeDiffItem(fileName: 'a.dart', directory: 'lib', lines: []);
const _words = AssistantTextItem('Looking.');
const _answer = AssistantTextItem('Done.');
const _reported = AssistantTextItem('Reported.');
const _planning = LiveStatusItem('Planning', visible: false);

UserMessageItem _prompt([Duration? worked = const Duration(seconds: 65)]) =>
    UserMessageItem(text: 'Fix it', worked: worked);

StepFolds _fold(
  List<ChatItem> items, {
  bool live = false,
  List<TurnMark> turns = const [],
}) => StepFolds.of(items.length, (i) => items[i], live: live, turns: turns);

TurnMark _mark(String id, int start, {int? prompt, Duration? worked}) =>
    (turnId: id, start: start, prompt: prompt, worked: worked);

/// The folds as `kind start-end`, each once, in order.
List<String> _folds(List<ChatItem> items, {bool live = false}) {
  final folds = _fold(items, live: live);
  return {
    for (var i = 0; i < items.length; i++) ...[
      if (folds.workAt(i) case final fold?) 'work ${fold.start}-${fold.end}',
      if (folds.stepsAt(i) case final fold?) 'steps ${fold.start}-${fold.end}',
    ],
  }.toList();
}

void main() {
  group('runs of steps', () {
    test('fold from two calls on, thoughts among them', () {
      expect(_folds([_prompt(null), _thought, _read, _thought, _grep]), [
        'steps 1-5',
      ]);
    });

    test('one call, however many thoughts, stays as it is', () {
      expect(_folds([_prompt(null), _thought, _read, _thought]), isEmpty);
    });

    test('words, edits, subagents and refused calls break a run', () {
      const denied = ToolCallItem(
        kind: ToolKind.read,
        target: 'x',
        status: ToolStatus.denied,
      );
      const agent = AgentItem(description: 'Look around');
      const background = TerminalItem(
        command: 'flutter run',
        output: '',
        background: true,
      );
      for (final breaker in <ChatItem>[
        _words,
        _edit,
        agent,
        denied,
        background,
      ]) {
        expect(
          _folds([_prompt(null), _read, breaker, _grep]),
          isEmpty,
          reason: '${breaker.runtimeType}',
        );
      }
    });
  });

  group('a turn\'s work', () {
    test('folds before its answer once timed', () {
      expect(_folds([_prompt(), _read, _grep, _words, _edit, _answer]), [
        'work 1-5',
        'steps 1-3',
      ]);
    });

    test('not while under way, nor stopped (untimed), nor short', () {
      final items = [_prompt(), _read, _grep, _words, _answer];
      expect(_folds(items, live: true), ['steps 1-3']);
      expect(_folds([_prompt(null), ...items.skip(1)]), ['steps 1-3']);
      expect(_folds([_prompt(), _read, _answer]), isEmpty);
    });

    test('a plan\'s card stands out of it: what came after the last folds', () {
      const sentBack = PlanItem(
        path: '/p/plans/a.md',
        round: 1,
        status: PlanStatus.sentBack,
      );
      const approved = PlanItem(
        path: '/p/plans/a.md',
        round: 2,
        status: PlanStatus.approved,
      );
      expect(
        _folds([
          _prompt(),
          _read,
          _grep,
          sentBack,
          _read,
          approved,
          _edit,
          _read,
          _answer,
        ]),
        ['steps 1-3', 'work 6-8'],
      );
      // Too little after it to fold.
      expect(_folds([_prompt(), _read, _grep, approved, _edit, _answer]), [
        'steps 1-3',
      ]);
    });

    test('not without an answer: an error ends it', () {
      const error = NoticeItem(NoticeKind.error, 'Overloaded');
      expect(_folds([_prompt(), _edit, _words, error]), isEmpty);
    });

    test('its answer is all the words after its last step', () {
      expect(_folds([_prompt(), _edit, _read, _words, _thought, _answer]), [
        'work 1-3',
      ]);
    });

    test('the turn under way is the last sent, not one queued after it', () {
      final items = [
        _prompt(),
        _edit,
        _read,
        _answer,
        _prompt(null),
        _read,
        const UserMessageItem(text: 'Then this', queued: true),
      ];
      expect(_folds(items, live: true), ['work 1-3']);
    });
  });

  group('turns', () {
    final userTurn = <ChatItem>[_prompt(), _read, _grep, _answer];
    final twoTurns = <ChatItem>[...userTurn, _read, _grep, _reported];

    List<TurnMark> twoMarks({Duration? auto = const Duration(seconds: 20)}) => [
      _mark('u1', 1, prompt: 0, worked: const Duration(seconds: 65)),
      _mark('auto:1', 4, worked: auto),
    ];

    List<ChatItem> autoTurn(String answer) => [
      _read,
      _grep,
      AssistantTextItem(answer),
    ];

    List<String> work(List<ChatItem> items, {List<TurnMark> turns = const []}) {
      final folds = _fold(items, turns: turns);
      return {
        for (var i = 0; i < items.length; i++)
          if (folds.workAt(i) case final fold? when fold.start == i)
            '${fold.start}-${fold.end} ${fold.worked?.inSeconds}',
      }.toList();
    }

    test('R1: a turn the agent took up folds only its own work', () {
      final folds = _fold(twoTurns, turns: twoMarks());
      expect(work(twoTurns, turns: twoMarks()), ['1-3 65', '4-6 20']);
      expect(folds.rowAt(3, twoTurns[3], (_) => false).item, isTrue);
      expect(folds.rowAt(6, twoTurns[6], (_) => false).item, isTrue);
      expect(folds.turnEndingAt(6), 4);
    });

    test('R2/R12: a turn with nothing to fold stays whole', () {
      expect(work([...userTurn, _reported], turns: twoMarks()), ['1-3 65']);
      final stopped = _fold(twoTurns, turns: twoMarks(auto: null));
      expect(stopped.workAt(4), isNull);
      expect(stopped.rowAt(6, twoTurns[6], (_) => false).item, isTrue);
    });

    test('R3: turns one after another each fold their own work', () {
      final items = [...userTurn, ...autoTurn('One.'), ...autoTurn('Two.')];
      final turns = [
        _mark('u1', 1, prompt: 0, worked: const Duration(seconds: 65)),
        _mark('auto:1', 4, worked: const Duration(seconds: 11)),
        _mark('auto:2', 7, worked: const Duration(seconds: 22)),
      ];
      expect(work(items, turns: turns), ['1-3 65', '4-6 11', '7-9 22']);
    });

    test('R4: nothing folds under way; both fold once both ended', () {
      final live = [...userTurn, _planning];
      final under = _fold(live, live: true, turns: [_mark('u1', 1, prompt: 0)]);
      expect(under.workAt(1), isNull);
      final mid = _fold(twoTurns, live: true, turns: twoMarks(auto: null));
      expect(mid.workAt(1)?.worked, const Duration(seconds: 65));
      expect(mid.workAt(4), isNull);
    });

    test('R5: two turns at the same place make one window, the later one', () {
      final turns = [
        ...twoMarks(),
        _mark('auto:2', 4, worked: const Duration(seconds: 9)),
      ];
      expect(work(twoTurns, turns: turns), ['1-3 65', '4-6 9']);
    });

    test('R6: without turns, the messages still make the windows', () {
      expect(work(userTurn), ['1-3 65']);
    });

    test('R7: a turn read from an old history ends at the next one', () {
      final turns = [_mark('auto:1', 4, worked: const Duration(seconds: 20))];
      expect(work(twoTurns, turns: turns), ['1-3 65', '4-6 20']);
    });

    test('R10: the message taken up first is its own empty window', () {
      final turns = [
        _mark('u1', 1, prompt: 0, worked: const Duration(seconds: 65)),
      ];
      final folds = _fold(userTurn, turns: turns);
      expect((folds.workAt(0), folds.turnEndingAt(3)), (null, 0));
    });

    test('R11: bad marks are dropped; a mark at the end stands', () {
      final bad = [_mark('bad', -1), ...twoMarks(), _mark('bad2', 99)];
      expect(work(twoTurns, turns: bad), ['1-3 65', '4-6 20']);
      final end = [...twoMarks(), _mark('auto:2', 7)];
      expect(work(twoTurns, turns: end), ['1-3 65', '4-6 20']);
      // Out of order: read from the end, the earlier start stands and the
      // one before it in the list goes.
      final jumbled = [
        _mark('late', 4, worked: const Duration(seconds: 20)),
        _mark('early', 1, prompt: 0, worked: const Duration(seconds: 65)),
      ];
      expect(work(twoTurns, turns: jumbled), ['1-6 65']);
    });
  });

  group('rows', () {
    final items = <ChatItem>[
      _prompt(),
      _thought,
      _read,
      _grep,
      _words,
      _edit,
      _answer,
    ];
    final folds = _fold(items);
    StepRow row(int i, {Set<StepFoldKind> open = const {}}) =>
        folds.rowAt(i, items[i], (fold) => open.contains(fold.kind));

    test('a closed turn shows its line, then its answer', () {
      expect(row(1), (work: folds.workAt(1), steps: null, item: false));
      for (final i in [2, 3, 4, 5]) {
        expect(row(i), (work: null, steps: null, item: false));
      }
      expect(row(6), (work: null, steps: null, item: true));
    });

    test('open, its runs show as their lines until opened too', () {
      const work = {StepFoldKind.work};
      expect(row(1, open: work), (
        work: folds.workAt(1),
        steps: folds.stepsAt(1),
        item: false,
      ));
      expect(row(2, open: work).item, isFalse);
      expect(row(4, open: work).item, isTrue);
      final all = {StepFoldKind.work, StepFoldKind.steps};
      expect(
        [
          for (final i in [1, 2, 3]) row(i, open: all).item,
        ],
        [true, true, true],
      );
    });

    test('a closed run under way shows the step it is on', () {
      const running = ToolCallItem(
        kind: ToolKind.grep,
        target: 'foo',
        status: ToolStatus.running,
      );
      final live = <ChatItem>[
        _prompt(null),
        _read,
        _thought,
        running,
        const LiveStatusItem('Planning next move', visible: false),
      ];
      final folds = _fold(live, live: true);
      bool shown(int i) => folds.rowAt(i, live[i], (_) => false).item;
      expect([for (var i = 1; i < 4; i++) shown(i)], [false, false, true]);
      // Done, it folds with the rest.
      final done = [...live]..[3] = _grep;
      final settled = _fold(done, live: true);
      expect(settled.rowAt(3, done[3], (_) => false).item, isFalse);
    });

    test('pictures made break a run, and show out of a closed turn', () {
      final picture = ToolCallItem(
        kind: ToolKind.image,
        target: 'a fox',
        images: [ImageAttachment(bytes: Uint8List(4), mediaType: 'image/png')],
      );
      final turn = <ChatItem>[
        _prompt(),
        _read,
        _grep,
        picture,
        _read,
        _grep,
        _answer,
      ];
      expect(_folds(turn), ['work 1-6', 'steps 1-3', 'steps 4-6']);
      final folds = _fold(turn);
      bool shown(int i) => folds.rowAt(i, turn[i], (_) => false).item;
      expect(
        [for (var i = 1; i < 7; i++) shown(i)],
        [false, false, true, false, false, true],
      );
      // Not while it is made, nor when it failed.
      for (final status in [ToolStatus.running, ToolStatus.failed]) {
        final other = [...turn]
          ..[3] = ToolCallItem(
            kind: ToolKind.image,
            target: 'a fox',
            status: status,
          );
        expect(_fold(other).rowAt(3, other[3], (_) => false).item, isFalse);
      }
    });
  });

  group('thoughts one after another', () {
    const empty = ThinkingItem(text: '', tokens: 0, seconds: 12);
    const titled = ThinkingItem(
      text: '**Plan**\nFirst.',
      tokens: 5,
      seconds: 3,
    );

    test('show as one, in the first one\'s row', () {
      final items = <ChatItem>[_prompt(null), _read, empty, titled, empty];
      final folds = _fold(items);
      expect(
        [
          for (var i = 1; i < items.length; i++)
            folds.rowAt(i, items[i], (_) => true).item,
        ],
        [true, true, false, false],
      );
      final shown = folds.shownAt(2, items[2]) as ThinkingItem;
      expect(shown.text, '**Plan**\nFirst.');
      expect(shown.seconds, 27);
      expect(shown.tokens, 5);
      // The others are as they are.
      expect(folds.shownAt(1, items[1]), same(_read));
      expect(folds.shownAt(3, items[3]), same(titled));
    });

    test('anything between them keeps them apart', () {
      final items = <ChatItem>[_prompt(null), empty, _read, empty];
      final folds = _fold(items);
      expect(folds.shownAt(1, items[1]), same(empty));
      expect(folds.rowAt(3, items[3], (_) => true).item, isTrue);
    });

    test('streaming while the last is, its time counting from the first', () {
      final now = DateTime(2026, 10, 17, 12);
      final live = ThinkingItem(text: '', tokens: 0, startedAt: now);
      final merged = mergeThoughts([empty, empty, live]);
      expect(merged.streaming, isTrue);
      expect(merged.startedAt, now.subtract(const Duration(seconds: 24)));
    });

    test('a closed run under way shows them as it goes', () {
      final live = ThinkingItem(text: '', tokens: 0, startedAt: DateTime(2026));
      final items = <ChatItem>[
        _prompt(null),
        _read,
        _grep,
        empty,
        live,
        const LiveStatusItem('Planning next move', visible: false),
      ];
      final folds = _fold(items, live: true);
      bool shown(int i) => folds.rowAt(i, items[i], (_) => false).item;
      expect(
        [for (var i = 1; i < 5; i++) shown(i)],
        [false, false, true, false],
      );
    });

    test('a turn ending in them ends at their row', () {
      final items = [_prompt(), _read, empty, empty];
      expect(_fold(items).turnEndingAt(2), 0);
      expect(_fold(items).turnEndingAt(3), isNull);
    });
  });

  test('a run counts what its steps did; commands by their words', () {
    final tally = StepTally([
      _thought,
      _read,
      _thought,
      _grep,
      const TerminalItem(command: "sed -n '1,80p' lib/a.dart", output: ''),
      const TerminalItem(
        command: 'cd /p && grep -rn foo lib 2>/dev/null | head',
        output: '',
      ),
      const TerminalItem(command: 'ls lib', output: ''),
      const TerminalItem(
        command: 'flutter test',
        output: '',
        status: CommandStatus.failed,
      ),
      const ToolCallItem(kind: ToolKind.mcp, target: 'query', label: 'Docs'),
    ]);
    expect(tally.counts, {
      StepAction.read: 2,
      StepAction.search: 2,
      StepAction.list: 1,
      StepAction.run: 1,
      StepAction.use: 1,
    });
    expect(tally.thought, 8);
  });

  test('a command that writes, chains or edits in place runs', () {
    for (final command in [
      "sed -i '' 's/a/b/' lib/a.dart",
      'cat a > b',
      'grep foo lib; rm -rf build',
      'flutter analyze && flutter test',
      'python3 - <<EOF\nprint(1)\nEOF',
    ]) {
      expect(commandAction(command), StepAction.run, reason: command);
    }
  });

  group('turn ends', () {
    test('a finished turn ends at its last item, queued messages aside', () {
      const queued = UserMessageItem(text: 'Next', queued: true);
      final items = [_prompt(), _read, _answer, _prompt(), _read, queued];
      final folds = _fold(items);
      expect(
        [for (var i = 0; i < items.length; i++) folds.turnEndingAt(i)],
        [null, null, 0, null, 3, null],
      );
    });

    test('the turn under way, and one not timed, end nowhere', () {
      final items = [_prompt(null), _answer, _prompt(), _read];
      final folds = _fold(items, live: true);
      expect(folds.turnEndingAt(1), isNull);
      expect(folds.turnEndingAt(3), isNull);
    });
  });

  test("a turn's tokens are what it read and wrote", () {
    expect(
      const TurnUsage(inputTokens: 1200, outputTokens: 300).totalTokens,
      1500,
    );
    expect(const TurnUsage(outputTokens: 300).totalTokens, 300);
    expect(const TurnUsage(costUsd: 0.1).totalTokens, isNull);
  });

  group('extending as items come', () {
    /// What a fold stands for, to compare one with another.
    (StepFoldKind, int, int, Duration?)? key(StepFold? fold) =>
        fold == null ? null : (fold.kind, fold.start, fold.end, fold.worked);

    /// Where a thought is shown: the start of its run, if it runs with
    /// another.
    int shownRow(List<ChatItem> items, int index) {
      if (items[index] is! ThinkingItem) return index;
      var start = index;
      while (start > 0 && items[start - 1] is ThinkingItem) {
        start--;
      }
      var end = index;
      while (end + 1 < items.length && items[end + 1] is ThinkingItem) {
        end++;
      }
      return end > start ? start : index;
    }

    void expectSame(
      StepFolds incremental,
      StepFolds full,
      List<ChatItem> items,
    ) {
      expect(incremental.count, items.length);
      for (var i = 0; i < items.length; i++) {
        expect(incremental.rowOf(i), shownRow(items, i));
        expect(key(incremental.stepsAt(i)), key(full.stepsAt(i)));
        expect(key(incremental.workAt(i)), key(full.workAt(i)));
        expect(incremental.turnEndingAt(i), full.turnEndingAt(i));
        for (final open in <Set<StepFoldKind>>[
          const {},
          const {StepFoldKind.work},
          const {StepFoldKind.steps},
          const {StepFoldKind.work, StepFoldKind.steps},
        ]) {
          final a = incremental.rowAt(i, items[i], open.contains);
          final b = full.rowAt(i, items[i], open.contains);
          expect(key(a.work), key(b.work), reason: 'work at $i');
          expect(key(a.steps), key(b.steps), reason: 'steps at $i');
          expect(a.item, b.item, reason: 'item at $i');
        }
        final a = incremental.shownAt(i, items[i]);
        final b = full.shownAt(i, items[i]);
        switch (a) {
          case ThinkingItem():
            expect((b as ThinkingItem).text, a.text, reason: 'shown at $i');
          default:
            expect(identical(a, b), isTrue, reason: 'shown at $i');
        }
      }
    }

    // A turn's own start must fold just as the message that began it did.
    test('D: turns that mirror the messages change no fold at all', () {
      final turn = <ChatItem>[_prompt(), _read, _grep, _answer];
      final items = [...turn, ...turn];
      final marks = [
        _mark('u1', 1, prompt: 0, worked: const Duration(seconds: 65)),
        _mark('u2', 5, prompt: 4, worked: const Duration(seconds: 65)),
      ];
      expectSame(_fold(items, turns: marks), _fold(items), items);
    });

    final script = <ChatItem>[
      UserMessageItem(text: 'Fix it', worked: const Duration(seconds: 65)),
      const ThinkingItem(text: 'One.', tokens: 1, seconds: 2),
      const ThinkingItem(text: 'Two.', tokens: 1, seconds: 2),
      const ThinkingItem(text: 'Three.', tokens: 1, seconds: 2),
      _read,
      _grep,
      _words,
      _edit,
      _read,
      const PlanItem(path: '/p/plan.md', round: 1, status: PlanStatus.sentBack),
      _read,
      const PlanItem(path: '/p/plan.md', round: 2, status: PlanStatus.approved),
      _read,
      _grep,
      _answer,
      UserMessageItem(text: 'Again', worked: const Duration(seconds: 30)),
      const ThinkingItem(text: 'Again one.', tokens: 1, seconds: 1),
      const ToolCallItem(kind: ToolKind.listDir, target: 'lib'),
      _read,
      _answer,
      const LiveStatusItem('Planning next move', visible: false),
    ];

    test('extend matches of at every index, as the history grows', () {
      final items = <ChatItem>[];
      final growing = {
        for (final live in [false, true]) live: _fold(items, live: live),
      };
      for (final item in script) {
        items.add(item);
        for (final live in [false, true]) {
          final incremental = growing[live]!
            ..extend(items.length, (i) => items[i], live: live);
          expectSame(incremental, _fold(items, live: live), items);
        }
      }
    });

    test('a turn ending recomputes its last turn', () {
      final items = <ChatItem>[_prompt(), _read, _grep, _words, _answer];
      final incremental = _fold(items, live: true)
        ..extend(items.length, (i) => items[i], live: false);
      expectSame(incremental, _fold(items), items);
    });

    test('a turn ending reads again what it changed in place', () {
      final items = <ChatItem>[_prompt(null), _read, _grep, _words, _answer];
      final incremental = _fold(items, live: true);
      // Same count, other items: the prompt takes the time it worked, and
      // the answer takes the status row's place.
      items[0] = _prompt(const Duration(seconds: 9));
      items[4] = const AssistantTextItem('It was the needle.');
      incremental.extend(items.length, (i) => items[i], live: false);
      expectSame(incremental, _fold(items), items);
    });

    test('refreshTail shows the words a merged thought took in', () {
      final items = <ChatItem>[
        _prompt(null),
        const ThinkingItem(text: 'A', tokens: 1, seconds: 1),
        const ThinkingItem(text: 'B', tokens: 1, seconds: 1),
      ];
      final folds = _fold(items);
      expect((folds.shownAt(1, items[1]) as ThinkingItem).text, 'A\n\nB');
      const longer = ThinkingItem(text: 'B more', tokens: 2, seconds: 1);
      items[2] = longer;
      folds.refreshTail(2, longer);
      expect((folds.shownAt(1, items[1]) as ThinkingItem).text, 'A\n\nB more');
      expect(folds.rowOf(2), 1);
    });
  });
}
