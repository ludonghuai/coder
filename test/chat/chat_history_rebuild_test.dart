import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:baocode/chat/chat_feed.dart';
import 'package:baocode/chat/chat_column.dart';
import 'package:baocode/chat/chat_find.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer_draft.dart';
import 'package:baocode/chat/side_panel/file_open.dart';
import 'package:baocode/chat/user_message_style.dart';
import 'package:baocode/theme/material_file_icons.dart';
import 'package:baocode/chat/widgets/chat_item_view.dart';
import 'package:baocode/chat/widgets/content_image.dart';
import 'package:baocode/chat/widgets/markdown_view.dart';
import 'package:baocode/chat/widgets/thinking_section.dart';
import 'package:baocode/theme/app_theme.dart';

class _Feed extends ChangeNotifier implements ChatFeed {
  _Feed(this.items);

  List<ChatItem> items;

  /// How often an item was read, and which were: an image collection, like
  /// a full fold, reads every one.
  int reads = 0;
  final Set<int> touched = {};

  bool streaming = false;

  @override
  int get itemCount => items.length;

  @override
  ChatItem itemAt(int index) {
    reads++;
    touched.add(index);
    return items[index];
  }

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

const _rebuiltTypes = [
  'findRow',
  'superList',
  'selection',
  'column',
  'images',
  'scrollbar',
  'item',
  'markdown',
];

String? _rebuiltType(Widget widget) => switch (widget) {
  ChatFindRow() => 'findRow',
  SuperListView() => 'superList',
  SelectionArea() => 'selection',
  ChatColumn() => 'column',
  ChatImages() => 'images',
  ScrollbarTheme() => 'scrollbar',
  ChatItemView() => 'item',
  MarkdownBlocks() => 'markdown',
  _ => null,
};

List<ChatItem> _turn(int n) => [
  UserMessageItem(text: 'Question $n', worked: const Duration(seconds: 65)),
  for (var i = 0; i < 40; i++) ...[
    ToolCallItem(kind: ToolKind.read, target: 't${n}_$i.dart'),
    AssistantTextItem('Turn $n step $i.'),
  ],
  AssistantTextItem('Answer $n.'),
];

/// One replay's readings: the rebuilds of each increment, the item reads,
/// whether the streamed data arrived each time, and the end state.
class _Run {
  _Run({
    required this.counts,
    required this.reads,
    required this.readAll,
    required this.dataOk,
    required this.terminal,
    required this.imagesFirst,
    required this.imagesSecond,
    required this.sameImages,
    required this.itemCount,
  });

  final List<Map<String, int>> counts;
  final List<int> reads;

  /// Frames where a full path read every item (a picture collection, a fold
  /// of the whole history): an increment must not.
  final List<int> readAll;
  final List<bool> dataOk;
  final bool terminal;
  final int imagesFirst;
  final int imagesSecond;
  final bool sameImages;

  /// How many items the conversation held when the pictures were read.
  final int itemCount;
}

Future<_Run> _replay(WidgetTester tester, int turns) async {
  // Sticky messages, as the tests' default, re-evaluate which message sticks
  // as rows move, and that rebuilds the shell once mid-reply. Not the
  // words' doing: the replay runs the style that leaves it alone.
  UserMessageStyle.current.value = UserMessageStyle.bubble;
  addTearDown(() => UserMessageStyle.current.value = UserMessageStyle.sticky);
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  final items = <ChatItem>[
    for (var n = 0; n < turns; n++) ..._turn(n),
    const UserMessageItem(text: 'Live question'),
    const AssistantTextItem('Start. '),
  ];
  final feed = _Feed(items)..streaming = true;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: ChatHistoryView(feed: feed)),
    ),
  );
  await tester.pumpAndSettle();
  expect(
    tester
        .widgetList<MarkdownView>(find.byType(MarkdownView))
        .map((view) => view.data),
    contains('Start. '),
  );

  final counts = <Map<String, int>>[];
  final reads = <int>[];
  final readAll = <int>[];
  final dataOk = <bool>[];
  var tally = <String, int>{};
  debugOnRebuildDirtyWidget = (element, _) {
    if (_rebuiltType(element.widget) case final name?) {
      tally[name] = (tally[name] ?? 0) + 1;
    }
  };
  addTearDown(() => debugOnRebuildDirtyWidget = null);
  final text = StringBuffer('Start. ');
  for (var i = 0; i < 120; i++) {
    tally = {};
    final readsBefore = feed.reads;
    feed.touched.clear();
    text.write('w$i ');
    items[items.length - 1] = AssistantTextItem(text.toString());
    feed.notifyListeners();
    await tester.pump(const Duration(milliseconds: 8));
    counts.add({for (final name in _rebuiltTypes) name: tally[name] ?? 0});
    reads.add(feed.reads - readsBefore);
    readAll.add(feed.touched.length == items.length ? 1 : 0);
    dataOk.add(
      tester
          .widgetList<MarkdownView>(find.byType(MarkdownView))
          .any((view) => view.data == text.toString()),
    );
  }
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();

  final live = tester.widget<MarkdownView>(
    find.byWidgetPredicate(
      (view) => view is MarkdownView && view.data == text.toString(),
    ),
  );
  final blocks = tester.widget<MarkdownBlocks>(
    find.descendant(
      of: find.byWidget(live),
      matching: find.byType(MarkdownBlocks),
    ),
  );
  final once = MarkdownView.document(tags: true)
      .parse(text.toString())
      .map((node) => node.textContent)
      .toList();
  final terminal = listEquals(
    blocks.nodes.map((node) => node.textContent).toList(),
    once,
  );

  final images = tester.widget<ChatImages>(find.byType(ChatImages));
  final beforeFirst = feed.reads;
  final first = images.all();
  final imagesFirst = feed.reads - beforeFirst;
  final beforeSecond = feed.reads;
  final second = images.all();
  final imagesSecond = feed.reads - beforeSecond;
  return _Run(
    counts: counts,
    reads: reads,
    readAll: readAll,
    dataOk: dataOk,
    terminal: terminal,
    imagesFirst: imagesFirst,
    imagesSecond: imagesSecond,
    sameImages: identical(first, second),
    itemCount: items.length,
  );
}

void _summarize(String label, _Run run) {
  for (final name in _rebuiltTypes) {
    final values = [for (final counts in run.counts) counts[name]!];
    final total = values.fold(0, (sum, value) => sum + value);
    final range = values.toSet().length == 1
        ? '${values.first}'
        : '${values.reduce((a, b) => a < b ? a : b)}..'
              '${values.reduce((a, b) => a > b ? a : b)}';
    debugPrint('$label $name total=$total per=$range');
  }
  debugPrint(
    '$label reads=${run.reads.fold(0, (a, b) => a + b)} '
    'per=${run.reads.toSet().length == 1 ? run.reads.first : 'differs'} '
    'readAll=${run.readAll.fold(0, (a, b) => a + b)}',
  );
  debugPrint(
    '$label dataOk=${run.dataOk.every((ok) => ok)} terminal=${run.terminal} '
    'images=${run.imagesFirst}/${run.imagesSecond} same=${run.sameImages}',
  );
}

void main() {
  testWidgets('a long conversation rebuilt builds its shown rows, not the '
      'hundreds folded away', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Long turns: each folds its steps away into one row.
    List<ChatItem> turn(int n) => [
      UserMessageItem(text: 'Question $n', worked: const Duration(seconds: 65)),
      for (var i = 0; i < 40; i++) ...[
        ToolCallItem(kind: ToolKind.read, target: 't${n}_$i.dart'),
        AssistantTextItem('Turn $n step $i.'),
      ],
      AssistantTextItem('Answer $n.'),
    ];
    final feed = _Feed([for (var n = 0; n < 20; n++) ...turn(n)]);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: ChatHistoryView(feed: feed)),
      ),
    );
    await tester.pumpAndSettle();
    final alive = find
        .byType(ChatFindRow, skipOffstage: false)
        .evaluate()
        .length;

    var rebuilt = 0;
    var markdown = 0;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (element.widget is ChatFindRow) rebuilt++;
      if (element.widget is MarkdownBlocks) markdown++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    feed.notifyListeners();
    await tester.pump();

    expect(alive, greaterThan(200));
    expect(rebuilt, lessThan(40));
    // What the shown rows say is as it was: not parsed nor laid out anew.
    expect(markdown, 0);
  });

  testWidgets('a right click on a file the conversation names opens the '
      "file's menu", (tester) async {
    // A desktop's: a right click brings up the selection's menu.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final existence = FileExistence((_) async => true);
    addTearDown(existence.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: FileOpenScope(
            root: '/p',
            onOpen: (_) {},
            existence: existence,
            child: ChatHistoryView(
              feed: _Feed([
                UserMessageItem(text: 'Where is it?'),
                AssistantTextItem('See [the report](out/report.html).'),
              ]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(
      // The link's text, after its icon.
      tester.getCenter(find.byType(FileIcon)) + const Offset(30, 0),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Copy Relative Path'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a word streamed in rebuilds one row, whatever the history', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final short = await _replay(tester, 20);
    // The readings print even when an assertion above fails.
    addTearDown(() => _summarize('F1-20 (teardown)', short));
    await tester.pumpWidget(const SizedBox());
    final long = await _replay(tester, 200);
    addTearDown(() => _summarize('F1-200 (teardown)', long));
    _summarize('F1-20', short);
    _summarize('F1-200', long);
    debugPrint(
      'A2 equal=${_sameCounts(short.counts, long.counts)} '
      'B1 readsEqual=${listEquals(short.reads, long.reads)}',
    );

    // The readings print before the assertions: the red run has numbers.
    for (final run in [short, long]) {
      for (final counts in run.counts) {
        expect(counts['findRow'], 0);
        expect(counts['superList'], 0);
        expect(counts['selection'], 0);
        expect(counts['column'], 0);
        expect(counts['images'], 0);
        expect(counts['scrollbar'], 0);
        expect(counts['item'], 1);
        expect(counts['markdown'], lessThanOrEqualTo(1));
      }
      expect(run.reads, everyElement(run.reads.first));
      expect(run.readAll, everyElement(0));
      expect(run.dataOk, everyElement(isTrue));
      // The words show as they come, the throttle merging some.
      final markdown = run.counts.fold(0, (all, c) => all + c['markdown']!);
      expect(markdown, greaterThanOrEqualTo(5));
      expect(run.terminal, isTrue);
      // Collected once, in full: the first read reads every item.
      expect(run.imagesFirst, greaterThanOrEqualTo(run.itemCount));
      expect(run.imagesSecond, 0);
      expect(run.sameImages, isTrue);
    }
    expect(_sameCounts(short.counts, long.counts), isTrue);
    expect(short.reads, long.reads);
  });

  testWidgets('a thought streamed in rebuilds the row its run shows in', (
    tester,
  ) async {
    UserMessageStyle.current.value = UserMessageStyle.bubble;
    addTearDown(() => UserMessageStyle.current.value = UserMessageStyle.sticky);
    addTearDown(tester.view.reset);
    final items = <ChatItem>[
      const UserMessageItem(text: 'Look'),
      const ThinkingItem(text: 'First.', tokens: 1, seconds: 1),
      const ThinkingItem(text: 'Second.', tokens: 1, seconds: 1),
    ];
    final feed = _Feed(items)..streaming = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: ChatHistoryView(feed: feed)),
      ),
    );
    await tester.pumpAndSettle();
    var rows = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (_rebuiltType(element.widget) == 'item') rows++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    items[2] = const ThinkingItem(
      text: 'Second, longer.',
      tokens: 2,
      seconds: 1,
    );
    feed.notifyListeners();
    await tester.pump(const Duration(milliseconds: 8));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    // The run shows in its first row, which took the new words.
    expect(rows, 1);
    expect(
      tester
          .widgetList<ThinkingSection>(find.byType(ThinkingSection))
          .map((section) => section.text)
          .join('\n'),
      contains('Second, longer.'),
    );
  });
}

/// Whether every increment rebuilt the same as its counterpart.
bool _sameCounts(List<Map<String, int>> a, List<Map<String, int>> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!mapEquals(a[i], b[i])) return false;
  }
  return true;
}
