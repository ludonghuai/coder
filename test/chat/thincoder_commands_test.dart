// What `/` offers in a thincoder session (F26①, §28.5): nothing — the kernel
// has no command source, so the list is empty rather than filled from Claude
// Code's customizations. That is a real empty list, not a made-up one.
// Claude Code's own panel is left as it is (F26②, its cases in
// test/chat/command_details_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_markdown/bao_markdown.dart';

import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/composer/composer_mock_data.dart';
import 'package:baocode/chat/composer/suggestion_menu.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/thincoder/thincoder_kernel.dart';
import 'package:baocode/kernel/thincoder/thincoder_mock.dart';
import 'package:baocode/kernel/thincoder/thincoder_transport.dart';
import 'package:baocode/theme/app_theme.dart';

/// A thincoder kernel's descriptor, its agent a scripted one.
KernelDescriptor thincoder() {
  late final KernelDescriptor descriptor;
  descriptor = KernelDescriptor(
    id: 'thincoder',
    label: 'thincoder',
    icon: Icons.smart_toy_outlined,
    description: 'The agent of the user’s terminal',
    create: (context) => ThincoderKernel(
      descriptor,
      context,
      start: (_) async => ThincoderMock(serialInbound: true),
      launch: (cwd) async =>
          ThincoderLaunch(cwd: cwd, executable: '/mock/thincoder'),
    ),
  );
  return descriptor;
}

Finder composerEditor() => find.descendant(
  of: find.byType(ChatComposer),
  matching: find.byType(MarkdownEditor),
);

/// Types [text] at the end of the composer, as an input method does.
Future<void> typeText(WidgetTester tester, String text) async {
  final state = tester.state<MarkdownEditorState>(composerEditor());
  final controller = state.controller;
  controller.selection = TextSelection.collapsed(offset: controller.length);
  final told = state.currentTextEditingValue!;
  final at = told.selection.extentOffset;
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: told.text.replaceRange(at, at, text),
      selection: TextSelection.collapsed(offset: at + text.length),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('T133: a thincoder session offers no `/` commands (F26①, '
      '§28.5)', (tester) async {
    final descriptor = thincoder();

    // ① The kernel does not declare a command source.
    final kernel = descriptor.create(const KernelContext(cwd: '/project'));
    addTearDown(kernel.dispose);
    expect(kernel, isNot(isA<ProvidesCommands>()));

    // ② So its chat has none to offer.
    final session = ChatSession(
      kernel: descriptor,
      kernels: [descriptor],
      historyCount: 0,
    );
    addTearDown(session.dispose);
    expect(session.commands, isEmpty);

    // ③ And `/` opens the menu with no command in it: there is nothing of
    // the kind to pick.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ChatScreen(session: session),
      ),
    );
    await tester.pump();
    await typeText(tester, '/');
    await tester.pump(const Duration(milliseconds: 300));

    final menu = find.byType(SuggestionMenu);
    expect(menu, findsOneWidget, reason: 'the `/` trigger opens the menu');
    final matches = tester.widget<SuggestionMenu>(menu).matches;
    expect(
      matches.where((match) => match.suggestion.kind == SuggestionKind.command),
      isEmpty,
    );

    // Leaving the view asks the kernel to let go; it does so a tick later, so
    // the tick has to run before the test ends with it pending.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(Duration.zero);
  });
}
