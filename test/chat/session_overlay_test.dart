import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baocode/browser/btest/btest_mode.dart';
import 'package:baocode/browser/btest/btest_policy.dart';
import 'package:baocode/browser/btest/btest_run_state.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/chat_session_overlay.dart';
import 'package:baocode/chat/editor_context.dart';
import 'package:baocode/chat/open_editor.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/transcript.dart';

// The host ⇄ overlay contract (design §29.1–§29.3): what the host opens to
// an overlay, in which order it calls it, and that it reads nothing back
// from it but the contract. A fake overlay plays the app's own and a
// recording kernel plays the agent's, so what is asserted is the seam, not
// btest or the turn marks (those have their own tests).

/// A kernel that only says what a test tells it to.
class _Kernel with KernelEventSource implements AgentKernel {
  _Kernel(this.descriptor);

  @override
  final KernelDescriptor descriptor;

  @override
  KernelHealth get health => KernelHealth.ready;
  @override
  String? get sessionId => null;

  final List<KernelTurn> turns = [];
  int prepares = 0;
  int releases = 0;
  bool disposed = false;

  @override
  void send(KernelTurn turn) => turns.add(turn);
  @override
  void answer(String requestId, InteractionAnswer answer) {}
  @override
  void cancel() {}
  @override
  void restart() {}
  @override
  void prepare() => prepares++;
  @override
  void release() => releases++;
  @override
  void dispose() => disposed = true;
  @override
  Future<void> get stopped => Future.value();
}

/// A kernel kept for [id] by its descriptor, and the kernel itself.
_Kernel _kernelFor(String id) {
  late _Kernel kernel;
  final descriptor = KernelDescriptor(
    id: id,
    label: id,
    icon: Icons.circle,
    description: '',
    create: (_) => kernel,
  );
  return kernel = _Kernel(descriptor);
}

/// The app's overlay, played by a test: every contract member records that
/// it was called, and the ones with an answer give what the test set.
class _FakeOverlay implements ChatSessionOverlay {
  final List<String> calls = [];
  final List<ChatItem> items = [];
  final List<TurnMark> turns = [];
  bool btestOn = false;

  /// What [restoreKernel] gives back: a kernel the host must then use.
  AgentKernel? restored;

  /// What [cacheKernel] answers: whether the host leaves the kernel to it.
  bool keep = false;

  /// What [beforeSend] adds to the turn.
  String? addsNote;

  @override
  BtestRun? get btestRun => null;
  @override
  BtestTraversal get btestTraversal => BtestTraversal.surface;
  @override
  bool get btestWrite => false;
  @override
  void setBtest(bool on) => calls.add('setBtest:$on');
  @override
  void setBtestTraversal(BtestTraversal value) {}
  @override
  void setBtestWrite(bool value) {}

  @override
  void addNotice(NoticeItem notice) {
    calls.add('addNotice');
    items.add(notice);
  }

  @override
  KernelChoice? wrapModes(KernelChoice? base) {
    calls.add('wrapModes');
    return base;
  }

  @override
  void onEventBefore(ChatSessionOverlayHost host, KernelEvent event) =>
      calls.add('before:${event.runtimeType}');

  @override
  void onEventAfter(
    ChatSessionOverlayHost host,
    KernelEvent event, {
    required bool changed,
    required bool sessionChanged,
  }) => calls.add('after:${event.runtimeType}:$changed/$sessionChanged');

  @override
  void onAttach(ChatSessionOverlayHost host) => calls.add('attach');

  @override
  void onDetach(ChatSessionOverlayHost host) => calls.add('detach');

  @override
  void onKernelChanging(ChatSessionOverlayHost host, KernelDescriptor next) =>
      calls.add('changing:${next.id}');

  @override
  bool cacheKernel(AgentKernel kernel) {
    calls.add('cache:${kernel.descriptor.id}');
    return keep;
  }

  @override
  AgentKernel? restoreKernel(KernelDescriptor descriptor) {
    calls.add('restore:${descriptor.id}');
    return restored;
  }

  @override
  void onKernelChanged(ChatSessionOverlayHost host) =>
      calls.add('changed');

  @override
  KernelTurn beforeSend(
    ChatSessionOverlayHost host,
    KernelTurn turn,
    OpenEditor? editor,
  ) {
    calls.add('beforeSend');
    final note = addsNote;
    if (note == null) return turn;
    return KernelTurn(
      id: turn.id,
      text: turn.text,
      mentions: turn.mentions,
      images: turn.images,
      contexts: [
        ...turn.contexts,
        TextContext(key: 'fake', name: 'fake', text: note),
      ],
      now: turn.now,
      notes: turn.notes,
    );
  }

  @override
  void onDispose(ChatSessionOverlayHost host) => calls.add('dispose');
}

void main() {
  ({ChatSession session, _Kernel kernel, _FakeOverlay overlay}) sessionWith(
    _FakeOverlay overlay, {
    KernelDescriptor? kernel,
    List<KernelDescriptor>? kernels,
  }) {
    final made = _kernelFor('a');
    final session = ChatSession(
      kernel: kernel ?? made.descriptor,
      kernels: kernels,
      historyCount: 0,
      overlay: overlay,
    );
    addTearDown(session.dispose);
    return (session: session, kernel: made, overlay: overlay);
  }

  test('the host calls the overlay around a transcript change, never for an '
      'event it does not show', () {
    final overlay = _FakeOverlay();
    final (:session, :kernel, overlay: _) = sessionWith(overlay);
    overlay.calls.clear();

    kernel.emit(
      ItemUpserted(1, 'u1', const UserMessageItem(text: 'Hi')),
    );
    expect(overlay.calls, ['before:ItemUpserted', 'after:ItemUpserted:true/true']);

    overlay.calls.clear();
    kernel.emitInfoChanged();
    expect(overlay.calls, [
      'before:KernelInfoChanged',
      'after:KernelInfoChanged:false/true',
    ]);

    // Not shown: the rename and the review's own event reach no hook.
    overlay.calls.clear();
    kernel
      ..emit(SessionRenamed(3, 'Other'))
      ..emit(FilesMayHaveChanged(4));
    expect(overlay.calls, isEmpty);

    // A stale event changes nothing, so neither hook's answer says it did.
    overlay.calls.clear();
    kernel.emit(ItemUpserted(1, 'u1', const UserMessageItem(text: 'again')));
    expect(overlay.calls, [
      'before:ItemUpserted',
      'after:ItemUpserted:false/false',
    ]);
  });

  test('what the overlay adds to the conversation is what the host shows', () {
    final overlay = _FakeOverlay();
    final (:session, kernel: _, overlay: _) = sessionWith(overlay);
    session.addNotice(const NoticeItem(NoticeKind.info, 'noticed'));
    expect(session.itemCount, 1);
    expect(session.itemAt(0), isA<NoticeItem>());
  });

  test('the host builds the turn, the overlay completes it, the kernel gets '
      'the completed one', () {
    final overlay = _FakeOverlay()..addsNote = 'from the overlay';
    final (:session, :kernel, overlay: _) = sessionWith(overlay);
    session.send(const ComposerMessage(text: 'go'));
    expect(overlay.calls, contains('beforeSend'));
    final turn = kernel.turns.single;
    expect(turn.text, 'go');
    expect([for (final c in turn.contexts) c.note], ['from the overlay']);
  });

  test('a switch asks the overlay first, then takes the kernel it gives back',
      () {
    final overlay = _FakeOverlay()..keep = true;
    final a = _kernelFor('a');
    final b = _kernelFor('b');
    final session = ChatSession(
      kernel: a.descriptor,
      kernels: [a.descriptor, b.descriptor],
      historyCount: 0,
      overlay: overlay,
    );
    addTearDown(session.dispose);
    overlay.calls.clear();
    // The overlay keeps b from an earlier visit: the switch back uses it.
    overlay.restored = b;

    session.setKernel(b.descriptor);

    expect(overlay.calls, ['changing:b', 'cache:a', 'restore:b', 'changed']);
    expect(session.agentKernel, same(b));
    expect(a.disposed, isFalse, reason: 'kept warm: the overlay said so');
    expect(b.prepares, 0, reason: 'no view is showing');
  });

  test('a kernel the overlay does not keep is disposed by the host', () {
    final overlay = _FakeOverlay()..keep = false;
    final a = _kernelFor('a');
    final b = _kernelFor('b');
    final session = ChatSession(
      kernel: a.descriptor,
      kernels: [a.descriptor, b.descriptor],
      historyCount: 0,
      overlay: overlay,
    );
    addTearDown(session.dispose);
    session.setKernel(b.descriptor);
    expect(a.disposed, isTrue);
  });

  test('a switch with a view showing prepares the new kernel there', () {
    final overlay = _FakeOverlay();
    final a = _kernelFor('a');
    final b = _kernelFor('b');
    final session = ChatSession(
      kernel: a.descriptor,
      kernels: [a.descriptor, b.descriptor],
      historyCount: 0,
      overlay: overlay,
    );
    addTearDown(session.dispose);
    session.attach();
    expect(a.prepares, 1);
    session.setKernel(b.descriptor);
    expect(b.prepares, 1, reason: 'the view never went away');
  });

  test('attach and detach reach the overlay around the host s own work', () {
    final overlay = _FakeOverlay();
    final (:session, :kernel, overlay: _) = sessionWith(overlay);
    overlay.calls.clear();
    session.attach();
    expect(kernel.prepares, 1);
    expect(overlay.calls, ['attach']);
    session.detach();
    expect(overlay.calls, ['attach', 'detach']);
  });

  test('the overlay is let go before the kernel it read', () {
    final overlay = _FakeOverlay();
    final made = _kernelFor('a');
    final session = ChatSession(
      kernel: made.descriptor,
      historyCount: 0,
      overlay: overlay,
    );
    overlay.calls.clear();
    session.dispose();
    expect(overlay.calls, ['dispose']);
    expect(made.disposed, isTrue);
  });

  test('a revert facet the kernel does not declare throws, never falls back',
      () async {
    final (:session, kernel: _, overlay: _) = sessionWith(_FakeOverlay());
    expect(session.plansReverts, isFalse);
    await expectLater(
      session.revertPlan('t1'),
      throwsA(isA<UnsupportedError>()),
    );
    await expectLater(
      session.applyRevert('t1'),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('the app s own overlay keeps btest under its session, and lets it go '
      'with the session', () {
    BtestMode.reset();
    addTearDown(BtestMode.reset);
    final made = _kernelFor('a');
    final session = ChatSession(kernel: made.descriptor, historyCount: 0);
    session.setBtest(true);
    expect(session.btestOn, isTrue);
    expect(BtestMode.find(null, null), isNotNull, reason: 'bound before an id');
    session.dispose();
    expect(
      BtestMode.find(null, null),
      isNull,
      reason: 'the overlay released its state with the session',
    );
  });
}
