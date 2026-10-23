// Which kernels confirm their own renames (F25③, §28.3): Claude Code does
// not, so its list changes at once, as it always did; thincoder does, with a
// live slot and no release on its way, and not otherwise (§28.4).

import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/mock_claude_code_transport.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/thincoder/thincoder_kernel.dart';
import 'package:baocode/kernel/thincoder/thincoder_mock.dart';
import 'package:baocode/kernel/thincoder/thincoder_transport.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';

/// The kernel's descriptor, as the registry gives it (not made here).
final _thincoder = KernelDescriptor(
  id: 'thincoder',
  label: 'thincoder',
  icon: Icons.smart_toy_outlined,
  description: 'The agent of the user’s terminal',
  create: (_) => throw UnimplementedError('not made here'),
);

/// Waits for what the kernel does next.
Future<void> settle() => pumpEventQueue(times: 60);

void main() {
  test('T135: Claude Code does not confirm its renames, so the list changes '
      'at once (F25③, §28.3)', () async {
    late final KernelDescriptor descriptor;
    descriptor = KernelDescriptor(
      id: 'claude-code',
      label: 'Claude Code',
      icon: Icons.auto_awesome_rounded,
      description: '',
      create: (context) => ClaudeCodeKernel(
        descriptor,
        context,
        start: MockClaudeCodeTransport.start,
      ),
    );

    final claudeKernel = descriptor.create(
      const KernelContext(cwd: '/project'),
    );
    addTearDown(claudeKernel.dispose);
    expect(claudeKernel, isA<RenamesSession>());
    expect(claudeKernel, isNot(isA<ConfirmsRename>()));

    final session = ChatSession(
      kernel: descriptor,
      kernels: [descriptor],
      historyCount: 0,
    );
    addTearDown(session.dispose);
    expect(session.canRename, isTrue);
    expect(session.renameConfirmed, isFalse);

    // The list is changed at once, as before: no event is waited for.
    final workspace = Workspace(
      projects: const [Project('project', '/project')],
      kernels: [descriptor],
      preferences: MemoryPreferenceStore(),
      drafts: MemoryPreferenceStore(),
    );
    addTearDown(workspace.dispose);
    final thread = workspace.create(project: workspace.projects.single);
    unawaited(workspace.rename(thread, 'Login'));
    expect(thread.title, 'Login');
  });

  test('T137: a thincoder rename is confirmed only with a live slot (§28.4)',
      () async {
    final agents = <ThincoderMock>[];
    final kernel = ThincoderKernel(
      _thincoder,
      const KernelContext(cwd: '/project'),
      start: (_) async {
        final agent = ThincoderMock(serialInbound: true);
        agents.add(agent);
        return agent;
      },
      launch: (cwd) async =>
          ThincoderLaunch(cwd: cwd, executable: '/mock/thincoder'),
    );
    addTearDown(kernel.dispose);
    final renamed = <KernelEvent>[];
    final subscription = kernel.events.listen(renamed.add);
    addTearDown(subscription.cancel);

    // ③ Before session/new: the title would wait in `_pendingTitle`, so the
    // host changes the list itself (today's path).
    expect(kernel.renameConfirmed, isFalse);

    // ① A live slot: the write goes out, and comes back confirmed.
    kernel.prepare();
    await settle();
    expect(kernel.sessionId, isNotNull);
    expect(kernel.renameConfirmed, isTrue);
    kernel.rename('Early');
    await settle();
    expect(agents.single.requests('session/set_title'), hasLength(1));
    expect(renamed.whereType<SessionRenamed>(), hasLength(1));
    expect(renamed.whereType<SessionRenamed>().single.title, 'Early');

    // ② Released: the connection goes while the slot stays. Not confirmed —
    // nothing lands, and the host had changed the list itself.
    kernel.release();
    await settle();
    expect(kernel.sessionId, isNotNull);
    expect(kernel.renameConfirmed, isFalse);
    kernel.rename('Late');
    await settle();
    expect(agents.single.requests('session/set_title'), hasLength(1));
    expect(renamed.whereType<SessionRenamed>(), hasLength(1));
  });

  test('T138: a rename deferred by a turn, with the view leaving before the '
      'turn ends, is said not confirmed — not dropped silently (§28.4)',
      () async {
    final agents = <ThincoderMock>[];
    final renamed = <KernelEvent>[];
    late final KernelDescriptor descriptor;
    descriptor = KernelDescriptor(
      id: 'thincoder',
      label: 'thincoder',
      icon: Icons.smart_toy_outlined,
      description: 'The agent of the user’s terminal',
      create: (context) {
        final kernel = ThincoderKernel(
          descriptor,
          context,
          start: (_) async {
            final agent = ThincoderMock(serialInbound: true)
              ..hold = Completer<void>();
            agents.add(agent);
            return agent;
          },
          launch: (cwd) async =>
              ThincoderLaunch(cwd: cwd, executable: '/mock/thincoder'),
        );
        kernel.events.listen(renamed.add);
        return kernel;
      },
    );
    final workspace = Workspace(
      projects: const [Project('project', '/project')],
      kernels: [descriptor],
      preferences: MemoryPreferenceStore(),
      drafts: MemoryPreferenceStore(),
    );
    addTearDown(workspace.dispose);
    final thread = workspace.create(project: workspace.projects.single);
    final session = thread.session;
    session.attach();
    await settle();

    // A turn runs: the rename waits for its end (§28.4), and the list waits
    // with it.
    session.send(const ComposerMessage(text: 'go'));
    await settle();
    expect(thread.title, 'go');
    expect(await workspace.rename(thread, 'A'), isTrue);
    expect(thread.title, 'go');

    // The view leaves before the turn ends: the release is asked for, and
    // the title can no longer be written.
    session.detach();
    await settle();
    agents.single.release(); // The turn ends.
    await settle();

    // Lost, and said: no event, the list keeps its title, one notice.
    expect(renamed.whereType<SessionRenamed>(), isEmpty);
    expect(thread.title, 'go');
    final notices = [
      for (var i = 0; i < session.itemCount; i++)
        if (session.itemAt(i) case final NoticeItem item
            when item.kind == NoticeKind.error)
          item,
    ];
    expect(notices, hasLength(1));
    expect(notices.single.text, contains('not confirmed'));
    expect(notices.single.text, contains('closing'));
  });
}
