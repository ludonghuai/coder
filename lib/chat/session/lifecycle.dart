import '../../kernel/agent_kernel.dart';
import '../../kernel/kernel_types.dart';
import '../../platform/event_log.dart';

// The kernels kept warm across a switch, and the two timings read as the
// session opens and switches (§25.5 / §25.6). The map is the overlay's;
// these are the moves it makes on it.

/// The kernel kept for [descriptor] by [cacheWarmKernel], taken back and
/// out of the map; null when none was kept, and when it failed meanwhile
/// (it is disposed here, so the caller starts a fresh one).
AgentKernel? restoreWarmKernel(
  Map<String, AgentKernel> warm,
  KernelDescriptor descriptor,
) {
  final kernel = warm.remove(descriptor.id);
  if (kernel == null) return null;
  if (kernel.health.status == KernelHealthStatus.failed) {
    kernel.dispose();
    return null;
  }
  return kernel;
}

/// Keeps [kernel] while another runs, so that switching back to it skips
/// its start; true: the caller leaves it to the map rather than disposing
/// it. Before the first message there is no conversation to protect.
bool cacheWarmKernel(Map<String, AgentKernel> warm, AgentKernel kernel) {
  warm[kernel.descriptor.id] = kernel;
  return true;
}

/// Lets go of the kernels kept warm, e.g. once the conversation has
/// started (kernels cannot read each other's sessions) or with the session.
void dropWarmKernels(Map<String, AgentKernel> warm) {
  for (final kernel in warm.values) {
    kernel.dispose();
  }
  warm.clear();
}

/// `timing: kernel-switch` (§25.5), once the kernel switched to is ready:
/// true when the clock was read and can be let go.
bool readKernelSwitch(Stopwatch? clock, AgentKernel kernel) {
  if (clock == null) return false;
  if (kernel.health.status != KernelHealthStatus.ready) return false;
  appEvent('thincoder', 'timing: kernel-switch ${clock.elapsedMilliseconds}ms');
  return true;
}

/// A view opening the conversation (A11's first read, §25.6): its clock
/// starts here, and `timing: open` is written.
Stopwatch startOpenTiming() {
  final opened = Stopwatch()..start();
  appEvent('thincoder', 'timing: open');
  return opened;
}

/// `timing: input-ready` (§25.6): once the conversation shows and it can
/// be sent to.
void readInputReady(Stopwatch opened) =>
    appEvent('thincoder', 'timing: input-ready ${opened.elapsedMilliseconds}ms');
