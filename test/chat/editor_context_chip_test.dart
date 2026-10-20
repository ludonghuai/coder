import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baocode/chat/chat_feed.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/composer/composer_draft.dart';
import 'package:baocode/chat/editor_context_setting.dart';
import 'package:baocode/chat/open_editor.dart';
import 'package:baocode/chat/widgets/chat_item_view.dart';
import 'package:baocode/chat/widgets/inline_code.dart';
import 'package:baocode/chat/widgets/user_message_bubble.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/codicons.dart';

/// A kernel that keeps what it is sent.
class _RecordingKernel with KernelEventSource implements AgentKernel {
  _RecordingKernel(this.descriptor);

  @override
  final KernelDescriptor descriptor;

  final List<KernelTurn> turns = [];

  @override
  KernelHealth get health => KernelHealth.ready;

  @override
  String? get sessionId => null;

  @override
  void send(KernelTurn turn) => turns.add(turn);

  @override
  void answer(String requestId, InteractionAnswer answer) {}

  @override
  void cancel() {}

  @override
  void restart() {}

  @override
  void prepare() {}

  @override
  void release() {}

  @override
  void dispose() => closeEvents();

  @override
  Future<void> get stopped => Future.value();
}

/// A kernel that takes the editor's context with each message.
class _Kernel extends _RecordingKernel implements AcceptsEditorContext {
  _Kernel(super.descriptor);
}

/// One that takes none of it.
class _PlainKernel extends _RecordingKernel {
  _PlainKernel(super.descriptor);
}

({ChatSession session, _RecordingKernel kernel}) _session({
  bool takesContext = true,
}) {
  late final _RecordingKernel kernel;
  final descriptor = KernelDescriptor(
    id: 'thincoder',
    label: 'thincoder',
    icon: Icons.terminal_rounded,
    description: '',
    create: (_) => kernel,
  );
  kernel = takesContext ? _Kernel(descriptor) : _PlainKernel(descriptor);
  final session = ChatSession(
    kernel: descriptor,
    kernels: [descriptor],
    historyCount: 0,
  );
  addTearDown(session.dispose);
  return (session: session, kernel: kernel);
}

Widget _app(Widget child) => MaterialApp(
  theme: buildAppTheme(),
  localizationsDelegates: const [FlutterQuillLocalizations.delegate],
  home: Scaffold(body: child),
);

QuillController _controller(WidgetTester tester) =>
    tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;

/// A conversation whose messages cannot be edited: they open read only.
class _Feed extends ChangeNotifier implements ChatFeed {
  _Feed(this.items);

  final List<ChatItem> items;

  @override
  int get itemCount => items.length;

  @override
  ChatItem itemAt(int index) => items[index];

  @override
  bool get isStreaming => false;

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

void main() {
  testWidgets('the file open in the editor is a chip below the composer\'s '
      'text area, and × takes it off the draft until the editor moves', (
    tester,
  ) async {
    final (:session, :kernel) = _session();
    OpenEditor open = const OpenEditor(
      '/p/a.dart',
      line: 10,
      selectedLines: (3, 5),
      selectedText: 'x\ny\nz',
    );

    Future<void> pump() async {
      await tester.pumpWidget(
        _app(
          ChatComposer(
            session: session,
            draft: session.draft,
            openEditor: () => open,
          ),
        ),
      );
      await tester.pump();
    }

    await pump();
    expect(find.text('a.dart · lines 3–5'), findsOneWidget);
    expect(find.byIcon(Codicons.close), findsOneWidget);
    // A button a screen reader can reach, not a bare icon.
    final semantics = tester.ensureSemantics();
    try {
      expect(
        tester.getSemantics(find.bySemanticsLabel('Dismiss Editor Context')),
        isSemantics(label: 'Dismiss Editor Context', isButton: true),
      );
    } finally {
      semantics.dispose();
    }

    // Taken off this draft: no chip, and the message carries none of it.
    await tester.tap(find.byIcon(Codicons.close));
    await tester.pump();
    expect(find.text('a.dart · lines 3–5'), findsNothing);
    _controller(tester)
        .replaceText(0, 0, 'one', const TextSelection.collapsed(offset: 3));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    expect(kernel.turns.single.contexts, isEmpty);

    // The editor moves: the chip is back, its line with it.
    open = const OpenEditor('/p/a.dart', line: 20);
    await pump();
    expect(find.text('a.dart · line 20'), findsOneWidget);
    _controller(tester)
        .replaceText(0, 0, 'two', const TextSelection.collapsed(offset: 3));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    expect(kernel.turns.last.contexts.single.line, 20);
  });

  testWidgets('a file open with no cursor is its name alone', (tester) async {
    final session = _session().session;
    await tester.pumpWidget(
      _app(
        ChatComposer(
          session: session,
          draft: session.draft,
          openEditor: () => const OpenEditor('/p/a.dart'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('a.dart'), findsOneWidget);
  });

  testWidgets('a sent message shows the context it carried, read only', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const ChatItemView(
          item: UserMessageItem(
            text: 'look',
            contexts: [
              EditorContext(
                '/p/a.dart',
                line: 10,
                selectedLines: (3, 5),
                selectedText: 'x',
              ),
              EditorContext('/p/b.dart'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('a.dart · lines 3–5'), findsOneWidget);
    expect(find.text('b.dart'), findsOneWidget);
    expect(find.byIcon(Codicons.close), findsNothing);
  });

  testWidgets('with the setting off, no chip and nothing sent', (tester) async {
    final (:session, :kernel) = _session();
    final setting = EditorContextSetting.current;
    EditorContextSetting.current = () => false;
    addTearDown(() => EditorContextSetting.current = setting);
    await tester.pumpWidget(
      _app(
        ChatComposer(
          session: session,
          draft: session.draft,
          openEditor: () => const OpenEditor('/p/a.dart', line: 10),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('a.dart · line 10'), findsNothing);

    _controller(tester)
        .replaceText(0, 0, 'one', const TextSelection.collapsed(offset: 3));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    expect(kernel.turns.single.contexts, isEmpty);
  });

  testWidgets('a kernel that takes no editor context shows no chip', (
    tester,
  ) async {
    final (:session, :kernel) = _session(takesContext: false);
    await tester.pumpWidget(
      _app(
        ChatComposer(
          session: session,
          draft: session.draft,
          openEditor: () => const OpenEditor('/p/a.dart', line: 10),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('a.dart · line 10'), findsNothing);
    expect(find.byIcon(Codicons.close), findsNothing);

    _controller(tester)
        .replaceText(0, 0, 'one', const TextSelection.collapsed(offset: 3));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    expect(kernel.turns.single.contexts, isEmpty);
  });

  testWidgets('a sent message opened shows the context it carried, read only', (
    tester,
  ) async {
    final feed = _Feed(const [
      UserMessageItem(
        text: 'look',
        contexts: [EditorContext('/p/a.dart', line: 10)],
      ),
    ]);
    addTearDown(feed.dispose);
    await tester.pumpWidget(_app(ChatHistoryView(feed: feed)));
    await tester.pumpAndSettle();

    // Opened, where its message cannot be edited: a viewer in its place.
    // The conversation's own copy, not the one stuck to its top.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey(0)),
        matching: find.byType(InlineCodeText),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(UserMessageViewer), findsOneWidget);
    expect(find.text('a.dart · line 10'), findsOneWidget);
    expect(find.byIcon(Codicons.close), findsNothing);
  });
}
