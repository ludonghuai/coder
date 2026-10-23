part of '../chat_session.dart';

// The project's paths: how its host spells them, and one path made
// absolute on that host. The class reads both through a delegate each.

/// How the project's paths are spelled: its host's way (POSIX) for a
/// remote one, this machine's otherwise.
p.Context _pathsOf(ChatSession owner) => switch (owner.kernelContext.cwd) {
  final cwd? => RemoteLocation.pathsOf(cwd),
  null => p.context,
};

/// [path] absolute, on the project's host (a remote project's paths are
/// its host's).
String _absoluteOf(ChatSession owner, String path) {
  final cwd = owner.kernelContext.cwd;
  if (cwd == null) return path;
  final paths = RemoteLocation.pathsOf(cwd);
  return paths.isAbsolute(path)
      ? path
      : paths.join(RemoteLocation.pathOf(cwd), path);
}
