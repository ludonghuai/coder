import 'thincoder_transport.dart';
import 'thincoder_process_stub.dart'
    if (dart.library.io) 'thincoder_process_io.dart'
    as platform;

/// Starts thincoder as a local process; on the web, where there are no
/// processes, fails saying so.
Future<ThincoderTransport> startThincoderProcess(ThincoderLaunch launch) =>
    platform.ThincoderProcess.start(launch);

/// Ends every thincoder process the app started, and waits for them: for
/// when the app quits.
Future<void> stopThincoderProcesses() => platform.ThincoderProcess.stopAll();

/// Ends the thincoder processes an earlier run of the app left running
/// (a crash, a force quit, a hot restart); none on the web.
Future<void> reapThincoderProcesses() =>
    platform.ThincoderProcess.reapLeftovers();
