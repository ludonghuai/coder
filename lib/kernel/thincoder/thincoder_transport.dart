/// thincoder's side of the adapter (the Adaptee): the messages of
/// `thincoder acp`, one JSON object per line (NDJSON · JSON-RPC 2.0).
abstract interface class ThincoderTransport {
  /// What the agent writes: its responses and `session/update`
  /// notifications, its own requests (`session/request_permission`,
  /// `fs/*`), and last, when the process ends, a [ThincoderExit.type]
  /// message.
  Stream<Map<String, Object?>> get messages;

  /// Writes a request, a response or a notification to its stdin.
  void write(Map<String, Object?> message);

  /// Ends the process.
  void close();

  /// Completes once the process is gone, closed or not.
  Future<void> get exited;
}

/// The message a transport ends with: the agent is gone.
abstract final class ThincoderExit {
  static const type = 'transport_exit';

  /// [executable] is the build run, where the transport knows it.
  static Map<String, Object?> message(
    int code,
    String stderr, {
    String? executable,
  }) => {
    'type': type,
    'code': code,
    'stderr': stderr,
    'executable': ?executable,
  };
}

/// How to start thincoder for one session: where it runs, which build, and
/// the environment it runs in (the login shell's, as the user's terminal
/// has it).
class ThincoderLaunch {
  const ThincoderLaunch({
    required this.cwd,
    required this.executable,
    this.environment = const {},
  });

  /// The project folder the process runs in: the agent's single cwd, and
  /// the sessions it lists are this folder's (`session/new` refuses any
  /// other cwd).
  final String cwd;

  /// The thincoder to run.
  final String executable;

  /// What it runs with.
  final Map<String, String> environment;

  /// The subcommand that serves ACP on stdio.
  static const command = 'acp';

  /// The environment with the variables [added] over it.
  ThincoderLaunch withEnvironment(Map<String, String> added) =>
      ThincoderLaunch(
        cwd: cwd,
        executable: executable,
        environment: {...environment, ...added},
      );
}

/// thincoder could not be started: not installed, not at the path set, or
/// the process refused to start. [message] is for the user; [detail] says
/// more.
class ThincoderUnavailable implements Exception {
  const ThincoderUnavailable(this.message, {this.detail});

  final String message;
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message\n$detail';
}

/// Starts thincoder for a session; throws [ThincoderUnavailable] when it
/// cannot.
typedef ThincoderTransportFactory = Future<ThincoderTransport> Function(
  ThincoderLaunch launch,
);
