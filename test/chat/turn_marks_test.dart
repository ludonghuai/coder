import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_types.dart';

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

/// A kernel over [id]: a descriptor that makes it, and the kernel.
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

/// A session over a kernel a test drives, with no history.
({ChatSession session, _Kernel kernel}) _session() {
  final kernel = _kernelFor('test');
  final session = ChatSession(kernel: kernel.descriptor, historyCount: 0);
  addTearDown(session.dispose);
  return (session: session, kernel: kernel);
}

const _read = ToolCallItem(kind: ToolKind.read, target: 'a.dart');
const _answer = AssistantTextItem('Done.');

void main() {
  test('a turn is marked where it starts, and takes its time at its end', () {
    final (:session, :kernel) = _session();
    kernel
      ..emit(
        ItemUpserted(kernel.nextSeq, 'u1', const UserMessageItem(text: 'Hi')),
      )
      ..emit(TurnStarted(kernel.nextSeq, 'u1'))
      ..emit(ItemUpserted(kernel.nextSeq, 'a1', _read));
    expect(session.turns, [(turnId: 'u1', start: 1, prompt: 0, worked: null)]);
    kernel.emit(
      TurnEnded(kernel.nextSeq, 'u1', worked: const Duration(seconds: 65)),
    );
    expect(session.turns, [
      (turnId: 'u1', start: 1, prompt: 0, worked: const Duration(seconds: 65)),
    ]);
  });

  test('a turn the agent took up has no message', () {
    final (:session, :kernel) = _session();
    kernel.emit(TurnStarted(kernel.nextSeq, 'auto:1', unprompted: true));
    expect(session.turns.single.start, 0);
    expect(session.turns.single.prompt, isNull);
  });

  test('the message that began it is found when it landed first', () {
    final (:session, :kernel) = _session();
    kernel
      ..emit(
        ItemUpserted(kernel.nextSeq, 'u1', const UserMessageItem(text: 'Hi')),
      )
      ..emit(ItemUpserted(kernel.nextSeq, 'a1', _answer))
      ..emit(TurnStarted(kernel.nextSeq, 'u1'));
    expect(session.turns.single.start, 2);
    expect(session.turns.single.prompt, 0);
  });

  test('a stopped turn keeps no time', () {
    final (:session, :kernel) = _session();
    kernel.emit(TurnStarted(kernel.nextSeq, 'u1'));
    kernel.emit(
      TurnEnded(
        kernel.nextSeq,
        'u1',
        interrupted: true,
        worked: const Duration(seconds: 30),
      ),
    );
    expect(session.turns.single.worked, isNull);
  });

  test('earlier history read moves the turns along', () {
    final (:session, :kernel) = _session();
    kernel
      ..emit(
        ItemUpserted(kernel.nextSeq, 'u1', const UserMessageItem(text: 'Hi')),
      )
      ..emit(TurnStarted(kernel.nextSeq, 'u1'));
    kernel.emit(
      HistoryPrepended(kernel.nextSeq, [('old1', _read), ('old2', _answer)]),
    );
    expect(session.turns.single.start, 3);
    expect(session.turns.single.prompt, 2);
  });

  test('a rewind drops the turns it cut away; a late end changes none', () {
    final (:session, :kernel) = _session();
    kernel
      ..emit(
        ItemUpserted(kernel.nextSeq, 'u0', const UserMessageItem(text: 'One')),
      )
      ..emit(TurnStarted(kernel.nextSeq, 'c'))
      ..emit(ItemUpserted(kernel.nextSeq, 'a0', _read))
      ..emit(ItemUpserted(kernel.nextSeq, 'b0', _answer))
      ..emit(
        TurnEnded(kernel.nextSeq, 'c', worked: const Duration(seconds: 10)),
      )
      ..emit(
        ItemUpserted(kernel.nextSeq, 'u1', const UserMessageItem(text: 'Two')),
      )
      ..emit(TurnStarted(kernel.nextSeq, 'a'))
      ..emit(ItemUpserted(kernel.nextSeq, 'a1', _read))
      ..emit(ItemUpserted(kernel.nextSeq, 'b1', _answer))
      ..emit(TurnStarted(kernel.nextSeq, 'auto:1', unprompted: true));
    expect(session.turns.map((turn) => turn.turnId), ['c', 'a', 'auto:1']);
    // Cut in the middle of the second turn: it and the one after it go.
    kernel.emit(Rewound(kernel.nextSeq, index: 5));
    expect(session.turns.map((turn) => turn.turnId), ['c']);
    kernel.emit(
      TurnEnded(kernel.nextSeq, 'auto:1', worked: const Duration(seconds: 9)),
    );
    expect(session.turns.single.worked, const Duration(seconds: 10));
  });

  test('a rewind to the start drops every turn; nothing is thrown', () {
    final (:session, :kernel) = _session();
    kernel
      ..emit(
        ItemUpserted(kernel.nextSeq, 'u0', const UserMessageItem(text: 'Hi')),
      )
      ..emit(TurnStarted(kernel.nextSeq, 'u0'))
      ..emit(ItemUpserted(kernel.nextSeq, 'a0', _read));
    expect(session.turns.single.start, 1);
    // Cut before it: its mark starts past the cut, and nothing is left to
    // straddle it.
    kernel.emit(Rewound(kernel.nextSeq, index: 0));
    expect(session.turns, isEmpty);
  });

  test('a rewind keeps a turn that ended where the cut begins', () {
    final (:session, :kernel) = _session();
    kernel
      ..emit(
        ItemUpserted(kernel.nextSeq, 'u0', const UserMessageItem(text: 'One')),
      )
      ..emit(TurnStarted(kernel.nextSeq, 'c'))
      ..emit(ItemUpserted(kernel.nextSeq, 'a0', _read))
      ..emit(ItemUpserted(kernel.nextSeq, 'b0', _answer))
      ..emit(
        TurnEnded(kernel.nextSeq, 'c', worked: const Duration(seconds: 10)),
      )
      ..emit(
        ItemUpserted(kernel.nextSeq, 'u1', const UserMessageItem(text: 'Two')),
      )
      ..emit(TurnStarted(kernel.nextSeq, 'a'))
      ..emit(ItemUpserted(kernel.nextSeq, 'a1', _read))
      ..emit(TurnStarted(kernel.nextSeq, 'auto:1', unprompted: true));
    // The turns starting at the cut go; the one ending just there stays.
    kernel.emit(Rewound(kernel.nextSeq, index: 4));
    expect(session.turns.map((turn) => turn.turnId), ['c']);
  });

  test('a rewind at the next message keeps the turn before it', () {
    final (:session, :kernel) = _session();
    kernel
      ..emit(
        ItemUpserted(kernel.nextSeq, 'u0', const UserMessageItem(text: 'Hi')),
      )
      ..emit(TurnStarted(kernel.nextSeq, 'u0'))
      ..emit(ItemUpserted(kernel.nextSeq, 'a0', _read))
      ..emit(ItemUpserted(kernel.nextSeq, 'b0', _answer))
      ..emit(
        TurnEnded(kernel.nextSeq, 'u0', worked: const Duration(seconds: 10)),
      )
      // What the agent took up on its own, answered.
      ..emit(TurnStarted(kernel.nextSeq, 'auto:1', unprompted: true))
      ..emit(ItemUpserted(kernel.nextSeq, 'a1', _read))
      ..emit(ItemUpserted(kernel.nextSeq, 'b1', _answer))
      ..emit(
        TurnEnded(
          kernel.nextSeq,
          'auto:1',
          worked: const Duration(seconds: 20),
        ),
      )
      // What the user sends after it, then edits: the cut is its message.
      ..emit(
        ItemUpserted(kernel.nextSeq, 'u1', const UserMessageItem(text: 'Next')),
      )
      ..emit(TurnStarted(kernel.nextSeq, 'u1'));
    expect(session.turns.map((turn) => turn.turnId), ['u0', 'auto:1', 'u1']);
    kernel.emit(Rewound(kernel.nextSeq, index: 5));
    expect(session.turns.map((turn) => turn.turnId), ['u0', 'auto:1']);
  });

  test('another kernel starts the turns anew', () {
    final (:session, :kernel) = _session();
    kernel.emit(TurnStarted(kernel.nextSeq, 'auto:1', unprompted: true));
    expect(session.turns, hasLength(1));
    session.setKernel(_kernelFor('other').descriptor);
    expect(session.turns, isEmpty);
  });
}
