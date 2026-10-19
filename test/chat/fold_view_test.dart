import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_feed.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer_draft.dart';
import 'package:baocode/chat/widgets/fold_line.dart';
import 'package:baocode/chat/widgets/live_selectable_text.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

/// A conversation held in a list, changed by hand.
class _Feed extends ChangeNotifier implements ChatFeed, MarksTurns {
  _Feed(this.items, {this.streaming = false});

  List<ChatItem> items;
  bool streaming;

  /// The turns kept, as a kernel would mark them.
  final List<TurnMark> marks = [];

  void update(List<ChatItem> next, {required bool streaming}) {
    items = next;
    this.streaming = streaming;
    notifyListeners();
  }

  @override
  List<TurnMark> get turns => marks;

  @override
  int get itemCount => items.length;

  @override
  ChatItem itemAt(int index) => items[index];

  @override
  bool get isStreaming => streaming;

  @override
  bool get isUnprompted => false;

  @override
  bool get canEditMessages => false;

  @override
  ({int index, ComposerDraft draft})? get editing => null;

  @override
  set editing(({int index, ComposerDraft draft})? value) {}

  @override
  void editMessage(int index, ComposerMessage message) {}

  @override
  VoidCallback? moveToBackgroundAt(int index) => null;

  @override
  VoidCallback? stopAt(int index) => null;
}

const _edit = CodeDiffItem(
  fileName: 'main.dart',
  directory: 'lib',
  lines: [
    DiffLine(DiffLineType.removed, 3, 'old'),
    DiffLine(DiffLineType.added, 3, 'new'),
  ],
);

/// A turn: a thought, a read and a search (a run), words, an edit, one more
/// read, and its answer.
List<ChatItem> _turn({Duration? worked, String words = 'Found it.'}) => [
  UserMessageItem(text: 'Fix the bug', worked: worked),
  const ThinkingItem(text: 'Where is it?', tokens: 4, seconds: 3),
  const ToolCallItem(kind: ToolKind.read, target: 'a.dart'),
  const TerminalItem(command: 'grep -rn foo lib', output: 'lib/a.dart:1'),
  AssistantTextItem(words),
  _edit,
  const ToolCallItem(kind: ToolKind.read, target: 'b.dart'),
  const AssistantTextItem('Done, fixed.'),
];

Future<void> _pump(WidgetTester tester, ChatFeed feed) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: ChatHistoryView(feed: feed)),
    ),
  );
  await tester.pump();
}

/// Taps [line] and lets what it opens or closes grow or shrink.
Future<void> _toggle(WidgetTester tester, Finder line) async {
  await tester.tap(line);
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Finder _text(String text) => find.textContaining(text, findRichText: true);

void main() {
  testWidgets('a finished turn folds its work before its answer', (
    tester,
  ) async {
    await _pump(tester, _Feed(_turn(worked: const Duration(seconds: 65))));

    expect(_text('Worked for 1m 5s · 1 file +1 -1'), findsOneWidget);
    expect(_text('Done, fixed.'), findsOneWidget);
    expect(_text('Found it.'), findsNothing);
    expect(_text('main.dart'), findsNothing);

    // Open: its words and edit, its run folded on its own.
    await _toggle(tester, find.byType(WorkFoldLine));
    expect(_text('Found it.'), findsOneWidget);
    expect(_text('main.dart'), findsOneWidget);
    expect(_text('b.dart'), findsOneWidget);
    expect(
      _text('Read 1 file, searched 1 pattern · thought 3s'),
      findsOneWidget,
    );
    expect(_text('a.dart'), findsNothing);

    await _toggle(tester, find.byType(StepsFoldLine));
    expect(_text('a.dart'), findsOneWidget);
    expect(_text('grep -rn foo lib'), findsOneWidget);

    await _toggle(tester, find.byType(WorkFoldLine));
    expect(_text('Found it.'), findsNothing);
    expect(_text('a.dart'), findsNothing);
    expect(_text('Done, fixed.'), findsOneWidget);
  });

  testWidgets('a run under way shows the step it is on once it has run a '
      'moment, then folds', (tester) async {
    final feed = _Feed([
      const UserMessageItem(text: 'Fix the bug'),
      const ToolCallItem(kind: ToolKind.read, target: 'a.dart'),
      const ThinkingItem(text: 'Hm.', tokens: 2, seconds: 2),
      const ToolCallItem(
        kind: ToolKind.grep,
        target: 'needle',
        status: ToolStatus.running,
      ),
      const LiveStatusItem('Planning next move', visible: false),
    ], streaming: true);
    await _pump(tester, feed);
    expect(_text('Read 1 file, searched 1 pattern'), findsOneWidget);
    expect(_text('a.dart'), findsNothing);
    // Not in a blink: it might be done before it is seen.
    expect(_text('needle'), findsNothing);
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pump();
    expect(_text('needle'), findsOneWidget);

    // Done: the turn's work folds before its answer.
    feed.update([
      const UserMessageItem(text: 'Fix the bug', worked: Duration(seconds: 9)),
      const ToolCallItem(kind: ToolKind.read, target: 'a.dart'),
      const ThinkingItem(text: 'Hm.', tokens: 2, seconds: 2),
      const ToolCallItem(kind: ToolKind.grep, target: 'needle'),
      const AssistantTextItem('It was the needle.'),
    ], streaming: false);
    await tester.pump();
    expect(_text('Worked for 9s'), findsOneWidget);
    expect(_text('needle'), findsOneWidget, reason: 'in the answer only');
    expect(_text('It was the needle.'), findsOneWidget);
    expect(_text('Read 1 file'), findsNothing);
  });

  testWidgets('a step under way done in a blink never shows; one that '
      'showed stays a moment once done', (tester) async {
    List<ChatItem> turn(ToolStatus last) => [
      const UserMessageItem(text: 'Fix the bug'),
      const ToolCallItem(kind: ToolKind.read, target: 'a.dart'),
      ToolCallItem(kind: ToolKind.grep, target: 'needle', status: last),
      const LiveStatusItem('Planning next move', visible: false),
    ];
    final feed = _Feed(turn(ToolStatus.running), streaming: true);
    await _pump(tester, feed);
    await tester.pump(const Duration(milliseconds: 100));
    feed.update(turn(ToolStatus.succeeded), streaming: true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(_text('needle'), findsNothing);

    // Run again, long enough to show; done, kept, then folded.
    feed.update(turn(ToolStatus.running), streaming: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pump();
    expect(_text('needle'), findsOneWidget);
    feed.update(turn(ToolStatus.succeeded), streaming: true);
    await tester.pump();
    expect(_text('needle'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 701));
    await tester.pump();
    expect(_text('needle'), findsNothing);
  });

  testWidgets('a thought of a blink stays closed; a longer one opens as it '
      'streams', (tester) async {
    List<ChatItem> turn({int? seconds}) => [
      const UserMessageItem(text: 'Fix the bug'),
      ThinkingItem(text: 'Where is the needle', tokens: 4, seconds: seconds),
      const LiveStatusItem('Planning next move', visible: false),
    ];
    final feed = _Feed(turn(), streaming: true);
    // Its words as they stream.
    final words = find.byType(LiveSelectableText);
    await _pump(tester, feed);
    expect(words, findsNothing);
    feed.update(turn(seconds: 0), streaming: true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(words, findsNothing);
    expect(_text('Where is the needle'), findsNothing);

    feed.update([
      ...turn(seconds: 0).take(2),
      ...turn().skip(1),
    ], streaming: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pump(const Duration(milliseconds: 400));
    expect(words, findsOneWidget);
  });

  testWidgets('a step shown on its own stays a moment as a run takes it', (
    tester,
  ) async {
    final feed = _Feed([
      const UserMessageItem(text: 'Fix the bug'),
      const ToolCallItem(kind: ToolKind.read, target: 'a.dart'),
      const LiveStatusItem('Planning next move', visible: false),
    ], streaming: true);
    await _pump(tester, feed);
    expect(_text('a.dart'), findsOneWidget);
    feed.update([
      const UserMessageItem(text: 'Fix the bug'),
      const ToolCallItem(kind: ToolKind.read, target: 'a.dart'),
      const ToolCallItem(kind: ToolKind.read, target: 'b.dart'),
      const LiveStatusItem('Planning next move', visible: false),
    ], streaming: true);
    await tester.pump();
    expect(_text('Read 2 files'), findsOneWidget);
    expect(_text('a.dart'), findsOneWidget, reason: 'not gone in a blink');
    await tester.pump(const Duration(milliseconds: 701));
    await tester.pump();
    expect(_text('a.dart'), findsNothing);
  });

  testWidgets('a turn ending while the user reads above folds once they '
      'are back at the bottom', (tester) async {
    final long = List.filled(60, 'A line of what was found.').join('\n\n');
    final feed = _Feed([
      ..._turn(words: long).take(7),
      const LiveStatusItem('Planning next move', visible: false),
    ], streaming: true);
    await _pump(tester, feed);
    final list = find.byType(SuperListView);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(list));
    for (var i = 0; i < 40; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -200)));
      // The wheel's notch eased out (120 ms).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(_text('Fix the bug'), findsWidgets);

    feed.update(
      _turn(worked: const Duration(seconds: 30), words: long),
      streaming: false,
    );
    await tester.pump();
    expect(_text('Worked for 30s'), findsOneWidget);
    expect(find.byType(StepsFoldLine), findsOneWidget, reason: 'kept open');

    for (var i = 0; i < 80; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 400)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pump();
    expect(_text('Worked for 30s'), findsOneWidget);
    expect(find.byType(StepsFoldLine), findsNothing);
    expect(_text('Done, fixed.'), findsOneWidget);
  });

  testWidgets('copying a fold copies its line', (tester) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _pump(tester, _Feed(_turn(worked: const Duration(seconds: 65))));
    await tester.tap(_text('Done, fixed.'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(
      copied,
      'Fix the bug\nWorked for 1m 5s · 1 file +1 -1\nDone, fixed.',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a turn the agent took up folds its own work, not the last '
      'answer', (tester) async {
    final feed =
        _Feed([..._turn(worked: const Duration(seconds: 65)), ..._reportWork])
          ..marks.addAll([
            _mark('turn', 1, prompt: 0, worked: const Duration(seconds: 65)),
            _mark('auto:1', 8, worked: const Duration(seconds: 20)),
          ]);
    await _pump(tester, feed);
    expect(find.byType(WorkFoldLine), findsNWidgets(2));
    expect(_text('Worked for 1m 5s'), findsOneWidget);
    expect(_text('Worked for 20s'), findsOneWidget);
    expect(_text('Done, fixed.'), findsOneWidget);
    expect(_text('Reported.'), findsOneWidget);
    expect(_text('Found it.'), findsNothing);
  });

  testWidgets('a report arriving leaves the turn before it folded, short or '
      'long a history', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final short = await _reportAfter(tester, 20);
    await tester.pumpWidget(const SizedBox());
    final long = await _reportAfter(tester, 200);
    debugPrint('R13 short=$short');
    debugPrint('R13 long=$long');
    expect(short, long);
    // The turn before shows as it did once the report starts and while it
    // works; both turns stand folded once the report ends.
    expect(short.map((step) => step.split(':')[1]), [
      '1100',
      '1100',
      '1101',
      '1111',
    ]);
  });

  testWidgets('a turn the kernel leaves streaming still folds when the next '
      'starts', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final feed = _Feed([..._reportTurn(0), ..._reportTurn(1)], streaming: true)
      ..marks.addAll([
        _mark('turn0', 1, prompt: 0, worked: const Duration(seconds: 65)),
        _mark('turn1', 5, prompt: 4),
      ]);
    await _pump(tester, feed);
    await tester.pumpAndSettle();
    expect(_text('Worked for 1m 5s'), findsOneWidget);
    // Ended, but the kernel still says it streams: it does not fold yet.
    feed.marks[1] = _mark(
      'turn1',
      5,
      prompt: 4,
      worked: const Duration(minutes: 3),
    );
    feed.notifyListeners();
    await tester.pump();
    expect(_text('Worked for 3m 0s'), findsNothing);
    // The next turn starts: the one before it folds, its answer showing.
    feed.marks.add(_mark('auto:1', feed.items.length));
    feed.notifyListeners();
    await tester.pump();
    expect(_text('Worked for 3m 0s'), findsOneWidget);
    expect(_text('Answer 1.'), findsOneWidget);
    // The report's own turn folds once it ends.
    feed.items.addAll(_reportWork);
    feed.marks[2] = _mark('auto:1', 8, worked: const Duration(seconds: 20));
    feed.streaming = false;
    feed.notifyListeners();
    await tester.pump();
    expect(_text('Worked for 3m 0s'), findsOneWidget);
    expect(_text('Worked for 20s'), findsOneWidget);
    expect(_text('Reported.'), findsOneWidget);
  });
}

/// One turn, as a kernel would mark it.
TurnMark _mark(String id, int start, {int? prompt, Duration? worked}) =>
    (turnId: id, start: start, prompt: prompt, worked: worked);

/// A finished turn of a long history: a message, two steps, its answer.
List<ChatItem> _reportTurn(int n) => [
  UserMessageItem(text: 'Question $n'),
  ToolCallItem(kind: ToolKind.read, target: 'q$n.dart'),
  ToolCallItem(kind: ToolKind.grep, target: 'needle$n'),
  AssistantTextItem('Answer $n.'),
];

/// What the agent does in a turn it took up on its own.
const _reportWork = <ChatItem>[
  ToolCallItem(kind: ToolKind.read, target: 'c.dart'),
  ToolCallItem(kind: ToolKind.grep, target: 'reported'),
  AssistantTextItem('Reported.'),
];

/// A report's turn arriving after [turns] turns already read: what shows of
/// them at each step, to compare a short history with a long one.
Future<List<String>> _reportAfter(WidgetTester tester, int turns) async {
  final feed = _Feed([for (var n = 0; n < turns; n++) ..._reportTurn(n)]);
  for (var n = 0; n < turns; n++) {
    feed.marks.add(
      _mark(
        'turn$n',
        n * 4 + 1,
        prompt: n * 4,
        worked: n == turns - 1
            ? const Duration(minutes: 3)
            : const Duration(seconds: 65),
      ),
    );
  }
  await _pump(tester, feed);
  await tester.pumpAndSettle();
  final seen = <String>[];
  void look(String step) {
    final flags = [
      for (final text in [
        'Worked for 3m 0s',
        'Answer ${turns - 1}.',
        'Worked for 20s',
        'Reported.',
      ])
        _text(text).evaluate().isEmpty ? '0' : '1',
    ].join();
    seen.add('$step:$flags');
  }

  look('read');
  // The agent takes up a report: its turn starts before any item of it.
  feed.marks.add(_mark('auto:1', feed.items.length));
  feed.streaming = true;
  feed.notifyListeners();
  await tester.pump();
  look('started');
  for (final item in _reportWork) {
    feed.items.add(item);
    feed.notifyListeners();
    await tester.pump();
  }
  look('worked');
  final at = feed.marks.length - 1;
  feed.marks[at] = _mark(
    'auto:1',
    feed.marks[at].start,
    worked: const Duration(seconds: 20),
  );
  feed.streaming = false;
  feed.notifyListeners();
  await tester.pump();
  look('ended');
  return seen;
}
