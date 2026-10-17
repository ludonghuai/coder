import 'thincoder_transport.dart';

/// No processes on the web.
abstract final class ThincoderProcess {
  static Future<ThincoderTransport> start(ThincoderLaunch launch) async =>
      throw const ThincoderUnavailable(
        'thincoder runs in the desktop app',
        detail: 'The browser cannot start local processes.',
      );

  /// No processes to stop on the web.
  static Future<void> stopAll() async {}

  static Future<void> reapLeftovers() async {}
}
