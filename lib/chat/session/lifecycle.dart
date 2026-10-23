part of '../chat_session.dart';

// The kernel's connection and the views that mount it: the warm kernels a
// switch keeps, the one it connects to, and how many views show it (a
// view coming back gets a kernel released only when the last one goes).

void _connectOf(ChatSession owner, KernelDescriptor descriptor) {
  final warm = owner._warm.remove(descriptor.id);
  if (warm != null && warm.health.status == KernelHealthStatus.failed) {
    warm.dispose();
    owner._kernel = descriptor.create(owner.kernelContext);
  } else {
    owner._kernel = warm ?? descriptor.create(owner.kernelContext);
  }
  owner._subscription = owner._kernel.events.listen(owner._apply);
}

void _dropWarmOf(ChatSession owner) {
  for (final kernel in owner._warm.values) {
    kernel.dispose();
  }
  owner._warm.clear();
}

/// A view shows the conversation: the kernel gets ready.
void _attachOf(ChatSession owner) {
  owner._views++;
  final opened = Stopwatch()..start(); // A11's first read (§25.6).
  appEvent('thincoder', 'timing: open');
  owner._kernel.prepare();
  owner._startReview();
  if (owner.canSend) appEvent('thincoder', 'timing: input-ready ${opened.elapsedMilliseconds}ms');
}

/// A view no longer shows it. With none left, an idle kernel frees what
/// it holds (a view may come right back, e.g. as the layout changes).
void _detachOf(ChatSession owner) {
  owner._views--;
  scheduleMicrotask(() {
    if (owner._views == 0 && !owner._disposed) owner._kernel.release();
  });
}
