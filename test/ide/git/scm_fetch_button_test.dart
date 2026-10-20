import 'dart:async';

import 'package:baocode/ide/git/git_repository.dart';
import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

/// The Get button in a repository's header (§12.6): the commits it would
/// pull are counted inside it (user 2026-10-19: not a second arrow beside
/// it); the narrow branch label keeps its own `↓N` (§12.6, W4). The button
/// is disabled while the repository works, and a workspace fetch pulls
/// every repository.
void main() {
  late FakeGit site;
  late FakeGit api;
  late IdeGitRepository siteRepository;
  late IdeGitRepository apiRepository;

  Future<IdeWorkspace> pumpScm(
    WidgetTester tester, {
    double? sidebarWidth,
    String siteStatus = '## main...origin/main [behind 2]\x00',
    String apiStatus = '## dev\x00',
  }) async {
    site = FakeGit(inRoot('site'))..status = siteStatus;
    api = FakeGit(inRoot('api'))..status = apiStatus;
    siteRepository = site.repository();
    apiRepository = api.repository();
    final workspace = await pumpWorkbench(
      tester,
      const {'site/a.txt': '', 'api/b.txt': ''},
      roots: ['site', 'api'],
      gitOf: (root) => root == inRoot('site') ? siteRepository : apiRepository,
      viewState: sidebarWidth == null
          ? null
          : {'sidebarWidth': sidebarWidth},
    );
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
    await tester.pumpAndSettle();
    return workspace;
  }

  Finder header(String folder) =>
      find.byKey(ValueKey('repo:${inRoot(folder)}')).first;

  Finder fetchButton(String folder) => find.descendant(
    of: find.byKey(ValueKey('fetch:${inRoot(folder)}')),
    matching: find.byType(IdeActionButton),
  );

  testWidgets('W1: roomy, the actions are Commit, Get (with 2 inside), '
      'Refresh, ...', (tester) async {
    await pumpScm(tester);
    final row = header('site');
    final actions = tester
        .widgetList<IdeActionButton>(
          find.descendant(of: row, matching: find.byType(IdeActionButton)),
        )
        .toList();
    expect(
      [for (final action in actions) action.icon],
      [Codicons.check, Codicons.repoFetch, Codicons.refresh, Codicons.ellipsis],
    );
    expect(actions[1].tooltip, contains(englishLocalizations.scmFetchAndPull));
    expect(
      actions[1].tooltip,
      contains(englishLocalizations.scmBehindCommits(2)),
    );

    // The count is inside the Get button, not a second arrow beside it.
    final get = fetchButton('site');
    expect(find.descendant(of: get, matching: find.text('2')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('↓2')), findsNothing);
    // And it draws within the button's own box: the width is measured.
    final button = tester.getRect(get);
    final count = tester.getRect(
      find.descendant(of: get, matching: find.text('2')),
    );
    expect(
      count.left >= button.left && count.right <= button.right,
      isTrue,
      reason: 'the count draws within the button: $count inside $button',
    );
    final refresh = tester.getCenter(
      find.descendant(of: row, matching: find.byIcon(Codicons.refresh)),
    );
    expect(tester.getCenter(get).dx, lessThan(refresh.dx));
  });

  testWidgets('W6: a two-digit count stays inside the Get button', (
    tester,
  ) async {
    await pumpScm(tester, siteStatus: '## main...origin/main [behind 12]\x00');
    final get = fetchButton('site');
    final count = find.descendant(of: get, matching: find.text('12'));
    expect(count, findsOneWidget);
    final button = tester.getRect(get);
    final digits = tester.getRect(count);
    expect(
      digits.left >= button.left && digits.right <= button.right,
      isTrue,
      reason: 'the digits draw within the button: $digits inside $button',
    );
  });

  testWidgets('W2: the branch label does not repeat the count (one, in the '
      'button)', (tester) async {
    await pumpScm(tester);
    final texts = tester
        .widgetList<Text>(
          find.descendant(of: header('site'), matching: find.byType(Text)),
        )
        .map((text) => text.data)
        .whereType<String>()
        .toList();
    expect(texts, contains('main'));
    expect(texts.where((text) => text.contains('↓')), isEmpty);
    expect(
      find.descendant(of: fetchButton('site'), matching: find.text('2')),
      findsOneWidget,
    );
  });

  testWidgets('W3: behind 0, the Get button carries no count', (tester) async {
    await pumpScm(tester, siteStatus: '## main...origin/main\x00');
    final get = fetchButton('site');
    expect(get, findsOneWidget);
    expect(
      find.descendant(of: get, matching: find.textContaining('2')),
      findsNothing,
    );
    expect(
      find.descendant(of: header('site'), matching: find.textContaining('↓')),
      findsNothing,
    );
  });

  testWidgets('W4: narrow, the actions are hidden and ↓2 follows the branch', (
    tester,
  ) async {
    await pumpScm(tester, sidebarWidth: 180);
    final row = header('site');
    expect(tester.getSize(row).width, lessThan(220));
    expect(fetchButton('site'), findsNothing);
    expect(
      find.descendant(of: row, matching: find.byIcon(Codicons.repoFetch)),
      findsNothing,
    );
    final badge = find.descendant(of: row, matching: find.text('↓2'));
    expect(badge, findsOneWidget);
    final branch = find.descendant(of: row, matching: find.text('main'));
    expect(branch, findsOneWidget);
    expect(
      tester.getCenter(badge).dx,
      greaterThan(tester.getCenter(branch).dx),
    );
    expect(
      find.descendant(of: row, matching: find.textContaining('↓')),
      findsOneWidget,
    );
  });

  testWidgets('W5: the status bar keeps its own ↓N; the header\'s count is '
      'inside the button', (tester) async {
    await pumpScm(tester);
    expect(find.text('main ↓2'), findsOneWidget);
    expect(
      find.descendant(of: header('site'), matching: find.textContaining('↓')),
      findsNothing,
    );
    expect(
      find.descendant(of: fetchButton('site'), matching: find.text('2')),
      findsOneWidget,
    );
  });

  testWidgets('the workspace ... says Fetch and Pull All Repositories; a '
      'repository\'s Fetch From All Remotes stays a fetch', (tester) async {
    await pumpScm(tester);

    // The Changes pane's `...` runs the whole workspace: fetch and pull.
    // Its actions show on hover, as the pane's do.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    final changes = tester.getCenter(find.text('Changes').first);
    await mouse.addPointer(location: changes);
    await mouse.moveTo(changes);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More Actions...').first);
    await tester.pumpAndSettle();
    expect(find.text('Fetch and Pull All Repositories'), findsOneWidget);
    expect(find.text('Fetch From All Remotes'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // A repository's `...`: this repository's remotes, fetched alone.
    await tester.tap(header('site'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Fetch From All Remotes'), findsOneWidget);
    expect(find.text('Fetch and Pull All Repositories'), findsNothing);
  });

  testWidgets('P9: one repository failing leaves the others pulled, told '
      'with its name', (tester) async {
    final workspace = await pumpScm(
      tester,
      siteStatus: '## main...origin/main [behind 2]\x00',
      apiStatus: '## dev\x00',
    );
    final state = tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));
    expect(state.runCommand('git.fetchAll'), isTrue);
    await tester.pumpAndSettle();

    expect(site.callsTo('fetch'), isNotEmpty);
    expect(site.callsTo('merge'), isNotEmpty);
    expect(api.callsTo('fetch'), isNotEmpty);
    expect(api.callsTo('merge'), isEmpty);
    final messages = [
      for (final notification in workspace.notifications.notifications)
        notification.message,
    ];
    final failed = messages.where((message) => message.startsWith('api:'));
    expect(failed, hasLength(1));
    expect(failed.single, contains('Nothing to pull'));
    expect(messages.where((message) => message.startsWith('site:')), isEmpty);
  });

  testWidgets('P10: while the repository works, the Get button is disabled', (
    tester,
  ) async {
    await pumpScm(tester);
    final gate = Completer<void>();
    site.hold = (arguments) async {
      if (arguments.first == 'add') await gate.future;
    };
    final operating = siteRepository.stageAll();
    await tester.pump();
    expect(
      tester.widget<IdeActionButton>(fetchButton('site')).onPressed,
      isNull,
    );
    gate.complete();
    await operating;
    await tester.pump();
    expect(
      tester.widget<IdeActionButton>(fetchButton('site')).onPressed,
      isNotNull,
    );
  });
}
