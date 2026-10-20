import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/panels/activity_strip.dart';
import 'package:baocode/chat/panels/interaction_panel.dart';
import 'package:baocode/chat/panels/revert_dialog.dart';
import 'package:baocode/chat/widgets/inline_rename_field.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/l10n/l10n.dart';

/// A kernel that only says what a test tells it to.
class _Kernel with KernelEventSource implements AgentKernel {
  _Kernel(this.descriptor);

  @override
  final KernelDescriptor descriptor;
  @override
  KernelHealth get health => KernelHealth.ready;
  @override
  String? get sessionId => null;
  @override
  void send(KernelTurn turn) {}
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

/// A kernel that plans its reverts (F2), naming its own sessions (F1.3).
class _RevertKernel extends _Kernel
    implements PlansReverts, GeneratesTitles, DefersRename, RenamesSession {
  _RevertKernel(super.descriptor);

  bool idle = true;
  String? pending;
  String? planned;
  String? applied;
  int plans = 0;
  int applies = 0;
  RevertPlan plan = const RevertPlan();
  RevertOutcome outcome = const RevertOutcome();

  @override
  bool get canRevertNow => idle;
  @override
  String? get pendingTitle => pending;
  @override
  Future<RevertPlan> revertPlan({required String sinceTurn}) async {
    planned = sinceTurn;
    plans++;
    return plan;
  }
  @override
  Future<RevertOutcome> applyRevert({required String sinceTurn}) async {
    applied = sinceTurn;
    applies++;
    return outcome;
  }
  @override
  void rename(String title) {}
}

/// A kernel that only undoes the host's way, as Claude Code does (A6).
class _UndoKernel extends _Kernel implements RenamesSession, RevertsChanges {
  _UndoKernel(super.descriptor);
  String? reverted;
  @override
  void revertChanges({required String sinceTurn}) => reverted = sinceTurn;
  @override
  void rename(String title) {}
}

({ChatSession session, K kernel}) _session<K extends _Kernel>(
  K Function(KernelDescriptor) make,
) {
  late K kernel;
  final descriptor = KernelDescriptor(
    id: 'test',
    label: 'test',
    icon: Icons.circle,
    description: '',
    create: (_) => kernel,
  );
  kernel = make(descriptor);
  final session = ChatSession(kernel: descriptor, historyCount: 0);
  addTearDown(session.dispose);
  return (session: session, kernel: kernel);
}

const _file = FileChange(path: '/p/a.txt', added: 1, removed: 1);

void main() {
  test('the revert projection follows the kernel and its idleness (G12)', () async {
    final (:session, :kernel) = _session(_RevertKernel.new);
    expect(session.canPlanRevert, isTrue, reason: 'no pending list needed');
    kernel.idle = false;
    expect(session.canPlanRevert, isFalse, reason: 'a turn under way');
    kernel.idle = true;
    await session.revertPlan('t1');
    expect(kernel.planned, 't1');
    await session.applyRevert('t2');
    expect(kernel.applied, 't2');
    expect(session.pendingTitle, isNull);
    kernel.pending = 'b';
    expect(session.pendingTitle, 'b');
  });

  test('the earliest change still pending starts the revert (G12)', () {
    final (:session, :kernel) = _session(_RevertKernel.new);
    kernel.emit(FileEdited(1, _file, turnId: 't1'));
    kernel.emit(FileEdited(2, _file, turnId: 't2'));
    expect(session.revertTurn, 't1');
  });

  test('a kernel the host undoes itself keeps its old path (G12)', () {
    final (:session, :kernel) = _session(_UndoKernel.new);
    expect(session.canPlanRevert, isFalse);
    expect(session.undoAllChanges, isNull);
    kernel.emit(FileEdited(1, _file, turnId: 't1'));
    session.undoAllChanges?.call();
    expect(kernel.reverted, 't1');
  });

  test('a plan refused writes nothing (G10)', () async {
    final (:session, :kernel) = _session(_RevertKernel.new);
    kernel.plan = const RevertPlan(
      files: [RevertFile('/p/a.txt', RevertAction.restore)],
    );
    var asked = 0;
    final outcome = await revertFiles(
      session,
      't1',
      l10n: englishLocalizations,
      confirm: (_) async {
        asked++;
        return false;
      },
    );
    expect(outcome, isNull);
    expect(asked, 1);
    expect(kernel.plans, 1);
    expect(kernel.applies, 0, reason: 'nothing is written on a cancel');
  });

  test('a turn that starts while the plan stands stops it (G12)', () async {
    final (:session, :kernel) = _session(_RevertKernel.new);
    kernel.plan = const RevertPlan(
      files: [RevertFile('/p/a.txt', RevertAction.restore)],
    );
    var blocked = 0;
    final outcome = await revertFiles(
      session,
      't1',
      l10n: englishLocalizations,
      confirm: (_) async {
        kernel.idle = false;
        return true;
      },
      blocked: () async => blocked++,
    );
    expect(outcome, isNull);
    expect(kernel.plans, 1);
    expect(kernel.applies, 0, reason: 'a turn under way: nothing written');
    expect(blocked, 1);
  });

  test('nothing to revert asks nothing (G12)', () async {
    final (:session, :kernel) = _session(_RevertKernel.new);
    var empty = 0;
    var asked = 0;
    final outcome = await revertFiles(
      session,
      't1',
      l10n: englishLocalizations,
      empty: () async => empty++,
      confirm: (_) async {
        asked++;
        return true;
      },
    );
    expect(outcome, isNull);
    expect(empty, 1);
    expect(asked, 0);
  });

  test('the outcome is counted in the conversation, zero groups left out (G6/G7)', () async {
    final (:session, :kernel) = _session(_RevertKernel.new);
    kernel.plan = const RevertPlan(
      files: [RevertFile('/p/a.txt', RevertAction.restore)],
    );
    kernel.outcome = const RevertOutcome(
      files: [RevertFile('/p/a.txt', RevertAction.restore)],
      skipped: [RevertSkip('/p/b.txt', 'changed')],
      unrevertable: [RevertSkip('/p/c.bin', 'oversize')],
    );
    await revertFiles(
      session,
      't1',
      l10n: englishLocalizations,
      confirm: (_) async => true,
    );
    final notice = session.itemAt(session.itemCount - 1);
    expect(notice, isA<NoticeItem>());
    expect(
      (notice as NoticeItem).text,
      'Reverted 1 file · Skipped 1 file · 1 file cannot be reverted',
    );
  });

  testWidgets('undo all is shown greyed, saying why, while a turn runs (G12)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActivityStrip(
            tasks: const [],
            changes: const [_file],
            onKeep: () {},
            onUndo: null,
            undoTooltip: 'Unavailable while a turn is running',
            canOpenTask: (_) => false,
          ),
        ),
      ),
    );
    final undo = find.widgetWithText(PanelButton, 'Undo all');
    expect(undo, findsOneWidget);
    final button = tester.widget<PanelButton>(undo);
    expect(button.onTap, isNull, reason: 'a turn under way: disabled');
    expect(button.tooltip, 'Unavailable while a turn is running');
  });

  testWidgets('a blank or too long title keeps the field open (G3)', (
    tester,
  ) async {
    var calls = 0;
    String? done;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: InlineRenameField(
                initial: 'Old',
                onDone: (text) {
                  calls++;
                  done = text;
                },
              ),
            ),
          ),
        ),
      ),
    );
    final field = find.byType(TextField);
    await tester.enterText(field, '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(calls, 0);
    expect(find.text('A title is required'), findsOneWidget);
    await tester.enterText(field, 'x' * 81);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(calls, 0);
    expect(find.text('A title is at most 80 characters'), findsOneWidget);
    await tester.enterText(field, 'Fine');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(calls, 1);
    expect(done, 'Fine');
  });
}
