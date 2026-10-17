// The kernel a new agent starts with: the first of those on offer, and
// the one the user picked, kept between runs. A `kernel` kept by a
// version that offered a single one was nobody's pick, and one no longer
// offered is not there: either way a new agent starts on the first again.
//
// The first of the two kernels here stands for the kernel the app offers
// first (see KernelRegistry): the two scripted ones are enough to pin the
// order down.

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';

/// A workspace on [kernels], one project to start agents in.
Workspace _workspace({
  required List<KernelDescriptor> kernels,
  PreferenceStore? preferences,
}) => Workspace(
  kernels: kernels,
  projects: const [Project('app', '/code/app')],
  preferences: preferences,
);

void main() {
  final kernels = [MockKernels.codex, MockKernels.claudeCode];

  test('a new agent starts on the first of the kernels, and none is kept '
      'as picked', () async {
    final store = MemoryPreferenceStore();
    final workspace = _workspace(kernels: kernels, preferences: store);
    addTearDown(workspace.dispose);
    await workspace.load();
    expect(workspace.preferredKernel.id, 'codex');
    expect(
      workspace.create(project: workspace.projects.first).kernel.id,
      'codex',
    );
    // What is kept is `kernel` alone: an older version's, not a pick.
    expect(store.preferences['kernel'], 'codex');
    expect(store.preferences.containsKey('kernelChosen'), isFalse);
  });

  test('the kernel the user picks is kept, and the next run starts there',
      () async {
    final store = MemoryPreferenceStore();
    final first = _workspace(kernels: kernels, preferences: store);
    await first.load();
    final thread = first.create(project: first.projects.first);
    // As the composer's picker does (see ChatSession.setKernel).
    thread.session.setKernel(kernels.last);
    await pumpEventQueue();
    expect(store.preferences['kernel'], 'claude-code');
    expect(store.preferences['kernelChosen'], isTrue);
    first.dispose();

    final next = _workspace(kernels: kernels, preferences: store);
    addTearDown(next.dispose);
    await next.load();
    expect(next.preferredKernel.id, 'claude-code');
  });

  test('a kernel kept without anyone picking it starts a new agent on the '
      'first again', () async {
    final workspace = _workspace(
      kernels: kernels,
      preferences: MemoryPreferenceStore({'kernel': 'claude-code'}),
    );
    addTearDown(workspace.dispose);
    await workspace.load();
    expect(workspace.preferredKernel.id, 'codex');
  });

  test('a kernel picked but no longer on offer starts a new agent on the '
      'first again', () async {
    final workspace = _workspace(
      kernels: kernels,
      preferences: MemoryPreferenceStore({
        'kernel': 'claude-code-fork',
        'kernelChosen': true,
      }),
    );
    addTearDown(workspace.dispose);
    await workspace.load();
    expect(workspace.preferredKernel.id, 'codex');
  });
}
