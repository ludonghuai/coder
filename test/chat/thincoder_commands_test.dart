// What `/` offers in a session, by its kernel's command source (F26, §28.5):
// a thincoder one has none, so no panel opens at all (and none is filled from
// Claude Code's customizations); a Claude Code one has a source, so its panel
// opens as it did before this batch — even with no command in its list yet
// (F26②). The composer's other cases are in test/composer_test.dart and
// test/chat/chat_keys_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_markdown/bao_markdown.dart';

import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/composer/suggestion_menu.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/thincoder/thincoder_kernel.dart';
import 'package:baocode/kernel/thincoder/thincoder_mock.dart';
import 'package:baocode/kernel/thincoder/thincoder_transport.dart';
import 'package:baocode/theme/app_theme.dart';

import '../composer_test.dart' show typeInto;
import '../kernel_test.dart' show FakeCli;

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
    expect(session.hasCommandSource, isFalse);

    // ③ And `/` opens no panel at all: a kernel with no command source has
    // nothing to offer, so the panel stays shut (F26①).
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ChatScreen(session: session),
      ),
    );
    await tester.pump();
    await typeInto(tester, composerEditor(), '/');
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byType(SuggestionMenu),
      findsNothing,
      reason: 'no command to offer: no panel opens',
    );
    // The typed `/` stays the text it was typed as.
    final controller = tester
        .widget<MarkdownEditor>(composerEditor())
        .controller;
    expect(controller.text, '/');

    // A query after the `/` changes nothing: there is still no command to
    // offer, so no panel opens for it either.
    await typeInto(tester, composerEditor(), 'pl');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SuggestionMenu), findsNothing);
    expect(controller.text, '/pl');

    // Leaving the view asks the kernel to let go; it does so a tick later, so
    // the tick has to run before the test ends with it pending.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(Duration.zero);
  });

  testWidgets('T139: a Claude session opens `/` with no command in its list '
      'yet (F26②)', (tester) async {
    // A kernel with a command source, its table empty: the window between the
    // session opening and the handshake's commands arriving.
    final cli = FakeCli(answers: {'initialize': {}});
    late final KernelDescriptor descriptor;
    descriptor = KernelDescriptor(
      id: 'claude-code',
      label: 'Claude Code',
      icon: Icons.auto_awesome_rounded,
      description: '',
      create: (context) =>
          ClaudeCodeKernel(descriptor, context, start: (_) async => cli),
    );
    final kernel = descriptor.create(const KernelContext(cwd: '/project'));
    addTearDown(kernel.dispose);
    expect(kernel, isA<ProvidesCommands>());

    final session = ChatSession(
      kernel: descriptor,
      kernels: [descriptor],
      historyCount: 0,
    );
    addTearDown(session.dispose);
    expect(session.commands, isEmpty);
    expect(session.hasCommandSource, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ChatScreen(session: session),
      ),
    );
    await tester.pump();
    // Still nothing to offer once the kernel has started.
    expect(session.commands, isEmpty);

    // `/` at the message's start opens the panel anyway, with no match to
    // show: as Claude's did before the thincoder rule came in.
    await typeInto(tester, composerEditor(), '/');
    await tester.pump(const Duration(milliseconds: 300));
    final menu = find.byType(SuggestionMenu);
    expect(menu, findsOneWidget);
    expect(tester.widget<SuggestionMenu>(menu).matches, isEmpty);

    // A query matching none keeps it open, the same empty shell.
    await typeInto(tester, composerEditor(), 'pl');
    await tester.pump(const Duration(milliseconds: 300));
    final again = find.byType(SuggestionMenu);
    expect(again, findsOneWidget);
    expect(tester.widget<SuggestionMenu>(again).matches, isEmpty);
    final controller = tester
        .widget<MarkdownEditor>(composerEditor())
        .controller;
    expect(controller.text, '/pl');

    // Leaving the view lets the kernel go, as the thincoder case does.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(Duration.zero);
  });
}
