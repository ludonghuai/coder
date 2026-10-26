import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'package:baocode/chat/chat_feed.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart' show ComposerMessage;
import 'package:baocode/chat/composer/composer_draft.dart';
import 'package:baocode/chat/user_message_style.dart';
import 'package:baocode/chat/widgets/chat_item_view.dart';
import 'package:baocode/chat/widgets/markdown_view.dart';
import 'package:baocode/chat/window_visible.dart';
import 'package:baocode/theme/app_theme.dart';

/// The cases of §8 the visibility gate answers to: hidden, the history is not
/// rebuilt (so no frame is drawn for the words that came in); back, it is
/// rebuilt once, with everything that came in meanwhile.
///
/// The window's state is the test's: [WidgetsBinding.handleAppLifecycleStateChanged]
/// is what the platform calls, and it is what `WindowVisible` reads.
void main() {
  testWidgets('T1 hidden, the history is not rebuilt as the reply streams', (
    tester,
  ) async {
    final (feed, items) = await _mounted(tester);
    _hidden(tester);
    await tester.pump();

    final counter = _countRebuilds();
    final text = StringBuffer('Start. ');
    for (var i = 0; i < 120; i++) {
      text.write('w$i ');
      _stream(feed, items, text.toString());
      await tester.pump(const Duration(milliseconds: 8));
    }

    expect(counter.items, 0, reason: 'no row is rebuilt while hidden');
    expect(counter.markdown, 0, reason: 'nothing is parsed while hidden');
    // Not even a frame was asked for: nothing was drawn at all.
    expect(tester.binding.hasScheduledFrame, isFalse);
    // What shows is what showed before it went out of sight.
    expect(find.textContaining('w119', findRichText: true), findsNothing);
    expect(find.textContaining('Start.', findRichText: true), findsOneWidget);
  });

  testWidgets('T1b hidden, the item taking the status row over is not drawn', (
    tester,
  ) async {
    final (feed, items) = await _mounted(tester, status: true);
    _hidden(tester);
    await tester.pump();
    final counter = _countRebuilds();

    // The turn's first item takes the row's place: the one hand-over a reply
    // makes, and it happens while the window is out of sight.
    items.removeLast();
    items.add(const AssistantTextItem('A step.'));
    feed.notifyListeners();
    await tester.pump(const Duration(milliseconds: 32));
    await tester.pump(const Duration(milliseconds: 400));
    expect(counter.items, 0, reason: 'no row is rebuilt while hidden');

    _shown(tester);
    await tester.pump();
    expect(find.textContaining('A step.', findRichText: true), findsOneWidget);
  });

  testWidgets('T2 back, one rebuild catches up with the whole reply', (
    tester,
  ) async {
    final (feed, items) = await _mounted(tester);
    _hidden(tester);
    await tester.pump();
    final text = StringBuffer('Start. ');
    for (var i = 0; i < 120; i++) {
      text.write('w$i ');
      _stream(feed, items, text.toString());
      await tester.pump(const Duration(milliseconds: 8));
    }

    final counter = _countRebuilds();
    _shown(tester);
    await tester.pump();

    // One build per row on screen: the catch-up is one frame, not one per
    // increment.
    final rows = find.byType(ChatItemView).evaluate().length;
    expect(rows, greaterThan(0));
    expect(counter.items, rows);
    expect(find.textContaining('w119', findRichText: true), findsOneWidget);

    // The list settles its new extent as it lays out, once; after that nothing
    // is left pending from the hidden while — no rebuild per increment.
    await tester.pump(const Duration(milliseconds: 50));
    counter.reset();
    await tester.pump(const Duration(milliseconds: 500));
    expect(counter.items, 0);
    expect(counter.markdown, 0);
  });

  testWidgets('T2a back, still at the bottom', (tester) async {
    final (feed, items) = await _mounted(tester);
    final position = _list(tester).controller!.position;
    expect(position.pixels, position.maxScrollExtent);

    _hidden(tester);
    await tester.pump();
    final text = StringBuffer('Start. ');
    for (var i = 0; i < 120; i++) {
      text.write('w$i ');
      _stream(feed, items, text.toString());
      await tester.pump(const Duration(milliseconds: 8));
    }
    _shown(tester);
    await tester.pump();

    // The words came in below where the list was held: at the bottom, it is
    // still at the bottom, now past them.
    expect(position.pixels, closeTo(position.maxScrollExtent, 1));
    expect(find.textContaining('w119', findRichText: true), findsOneWidget);
  });

  testWidgets('T2b back, mid-history where it was left', (tester) async {
    final (feed, items) = await _mounted(tester, turns: 12);
    final position = _list(tester).controller!.position;
    position.jumpTo(position.maxScrollExtent / 2);
    await tester.pump();
    final before = position.pixels;
    expect(before, greaterThan(0));

    _hidden(tester);
    await tester.pump();
    final text = StringBuffer('Start. ');
    for (var i = 0; i < 120; i++) {
      text.write('w$i ');
      _stream(feed, items, text.toString());
      await tester.pump(const Duration(milliseconds: 8));
    }
    _shown(tester);
    await tester.pump();

    // Not at the bottom, nothing jumps: the same place, within a pixel.
    expect(position.pixels, closeTo(before, 1));
    // And what came in while it was away is there, though below the viewport.
    expect(
      find.textContaining('w119', findRichText: true, skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('T3 hidden, the markdown is not parsed; back, parsed once', (
    tester,
  ) async {
    final (feed, items) = await _mounted(tester);
    _hidden(tester);
    await tester.pump();

    final counter = _countRebuilds();
    final text = StringBuffer('Start. ');
    for (var i = 0; i < 120; i++) {
      text.write('w$i ');
      _stream(feed, items, text.toString());
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(counter.markdown, 0);

    _shown(tester);
    await tester.pump();
    // Each reply on screen is parsed once, from the final text — the same
    // parse a reply written once would get.
    final views = find.byType(MarkdownView).evaluate().length;
    expect(views, greaterThan(0));
    expect(counter.markdown, views);
    expect(
      tester
          .widgetList<MarkdownView>(find.byType(MarkdownView))
          .map((view) => view.data),
      contains(text.toString()),
    );
  });

  testWidgets('T4 hidden from the first frame, nothing is built until back', (
    tester,
  ) async {
    _hidden(tester);
    final (feed, items) = await _mounted(tester);

    final counter = _countRebuilds();
    final text = StringBuffer('Start. ');
    for (var i = 0; i < 120; i++) {
      text.write('w$i ');
      _stream(feed, items, text.toString());
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(counter.items, 0);

    _shown(tester);
    await tester.pump();
    expect(find.textContaining('w119', findRichText: true), findsOneWidget);
  });

  testWidgets('WindowVisible: asked to watch twice, one notice per flip', (
    tester,
  ) async {
    var notices = 0;
    void heard() => notices++;
    // Asked for twice, it watches once: the second ask changes nothing, and a
    // flip is told once.
    WindowVisible.start();
    WindowVisible.start();
    WindowVisible.changed.addListener(heard);
    addTearDown(() {
      WindowVisible.changed.removeListener(heard);
      _shown(tester);
    });

    expect(WindowVisible.isVisible, isTrue);
    _hidden(tester);
    expect(WindowVisible.isVisible, isFalse);
    expect(notices, 1);
    // Still hidden: nothing to tell.
    _hidden(tester);
    expect(notices, 1);
    _shown(tester);
    expect(WindowVisible.isVisible, isTrue);
    expect(notices, 2);
  });
}

/// The app's own reading of the window: hidden as the platform reports it.
void _hidden(WidgetTester tester) =>
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);

void _shown(WidgetTester tester) =>
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

SuperListView _list(WidgetTester tester) =>
    tester.widget<SuperListView>(find.byType(SuperListView));

/// The history, with the live turn's text at the end: [items] last is the
/// streaming one.
Future<(_Feed, List<ChatItem>)> _mounted(
  WidgetTester tester, {
  int turns = 3,
  bool status = false,
}) async {
  // Sticky messages rebuild the shell as rows move (a copy of a message keeps
  // the top): not the words' doing, so the style that leaves it alone.
  UserMessageStyle.current.value = UserMessageStyle.bubble;
  addTearDown(() => UserMessageStyle.current.value = UserMessageStyle.sticky);
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // The window is left as it was found, whatever a case did with it.
  addTearDown(() => _shown(tester));

  final items = <ChatItem>[
    for (var n = 0; n < turns; n++) ...[
      UserMessageItem(text: 'Question $n', worked: const Duration(seconds: 2)),
      AssistantTextItem('Answer $n.'),
    ],
    const UserMessageItem(text: 'Live question'),
    if (status)
      const LiveStatusItem('Thinking…')
    else
      const AssistantTextItem('Start. '),
  ];
  final feed = _Feed(items)..streaming = true;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: ChatHistoryView(feed: feed)),
    ),
  );
  if (status) {
    // The wait's row keeps a clock of its own: a settle would never come.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  } else {
    await tester.pumpAndSettle();
  }
  return (feed, items);
}

/// What the reply has come to: the live text, as the feed tells it.
void _stream(_Feed feed, List<ChatItem> items, String text) {
  items[items.length - 1] = AssistantTextItem(text);
  feed.notifyListeners();
}

/// Counts the rows and the replies built from here on, until the test ends.
_Counter _countRebuilds() {
  final counter = _Counter();
  debugOnRebuildDirtyWidget = (element, _) {
    if (element.widget is ChatItemView) counter.items++;
    if (element.widget is MarkdownView) counter.markdown++;
  };
  addTearDown(() => debugOnRebuildDirtyWidget = null);
  return counter;
}

final class _Counter {
  int items = 0;
  int markdown = 0;

  void reset() {
    items = 0;
    markdown = 0;
  }
}

/// A conversation as the history reads it: items, whether a turn is under way,
/// and a change told by [notifyListeners].
final class _Feed extends ChangeNotifier implements ChatFeed {
  _Feed(this.items);

  List<ChatItem> items;

  @override
  int get itemCount => items.length;

  @override
  ChatItem itemAt(int index) => items[index];

  bool streaming = false;

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
