import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_types.dart';

/// A kernel that only says what a test tells it to.
class _Kernel with KernelEventSource implements AgentKernel {
  _Kernel(this.descriptor);

  @override
  final KernelDescriptor descriptor;

  /// What waits for a turn's end, for a kernel that holds one (T106).
  String? pending;

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

/// The kernel that keeps a model until the turn ends (F21).
class _DeferringKernel extends _Kernel implements DefersModelSwitch {
  _DeferringKernel(super.descriptor);

  @override
  String? get pendingModel => pending;
}

/// A kernel over [defers]: its descriptor makes it, and the kernel.
_Kernel _kernelFor({required bool defers}) {
  late _Kernel kernel;
  final descriptor = KernelDescriptor(
    id: 'test',
    label: 'test',
    icon: Icons.circle,
    description: '',
    create: (_) => kernel,
  );
  kernel = defers ? _DeferringKernel(descriptor) : _Kernel(descriptor);
  return kernel;
}

/// A session over a kernel a test drives, with no history.
({ChatSession session, _Kernel kernel}) _session({bool defers = true}) {
  final kernel = _kernelFor(defers: defers);
  final session = ChatSession(kernel: kernel.descriptor, historyCount: 0);
  addTearDown(session.dispose);
  return (session: session, kernel: kernel);
}

void main() {
  test('the waiting model shows while it waits, and none once it is over '
      '(T106)', () {
    final (:session, :kernel) = _session();
    expect(session.pendingModel, isNull);

    kernel.pending = 'b';
    expect(session.pendingModel, 'b');

    kernel.pending = null;
    expect(session.pendingModel, isNull);
  });

  test('a kernel that does not hold a model has none (T106)', () {
    final (:session, :kernel) = _session(defers: false);
    expect(kernel, isNot(isA<DefersModelSwitch>()));
    expect(session.pendingModel, isNull);
  });
}
