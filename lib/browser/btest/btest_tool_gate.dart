import '../../host_tools/host_tools.dart';
import 'btest_mode.dart';
import 'btest_policy.dart';

// The btest gate every browser tool call passes before it runs (§3.4 /
// §3.7): the operation's rules and the release's, judged by [BtestGate] and
// [BtestPolicy]. What this file adds is only where the hosts a call targets
// come from: the entry URLs its input names, else the page its tab is on —
// which the browser library answers, so the generic host-tool face carries
// no browser special case.

/// The gate a browser tool's call passes, or is refused by.
abstract final class BtestToolGate {
  /// Passes [tool]'s call, or throws its refusal. [tabHost] says what page a
  /// tab is on now (null when the tab or its URL is not known); it is asked
  /// only where the input names no entry URL and carries a tab id.
  static Future<void> check(
    String tool,
    Map<String, Object?> input,
    HostToolCall call, {
    required Future<String?> Function(int tabId) tabHost,
  }) async {
    // The two tools that start and end a run: their own rules, and no run
    // needed — otherwise a run could never start (§3.3).
    if (BtestGate.exempt.contains(tool)) return;
    // A session with btest off passes untouched.
    if (BtestGate.stateOf(call) == null) return;
    final found = await _hostsOf(tool, input, tabHost);
    BtestGate.check(
      tool,
      input,
      call,
      hosts: found.hosts,
      targeted: found.targeted,
    );
  }

  /// The hosts a call targets: the entry urls it goes to, else the tab's
  /// current page (§3.7: the target host is what the allow lists judge).
  static Future<({bool targeted, List<String> hosts})> _hostsOf(
    String tool,
    Map<String, Object?> input,
    Future<String?> Function(int tabId) tabHost,
  ) async {
    final urls = BtestPolicy.entryUrls(tool, input);
    if (urls.isNotEmpty) {
      final hosts = <String>[];
      for (final url in urls) {
        final host = Uri.tryParse(url)?.host;
        if (host != null && host.isNotEmpty) hosts.add(host);
      }
      return (targeted: true, hosts: hosts);
    }
    final tabId = input['tabId'];
    if (tabId is! int) return (targeted: false, hosts: const <String>[]);
    final host = await tabHost(tabId);
    return (targeted: true, hosts: [?host]);
  }
}
