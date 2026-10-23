/// What btest lets a browser tool call do (design §3.6 / §3.7): the entry
/// rules, the script that may not write, the tool face of a read-only run,
/// and the domain / production gates. Pure judgements — the counters live
/// in btest_mode.dart, and the wiring in browser_tools.dart.
library;

/// Where a run says it works: the authority over writes (design §3.7).
enum BtestEnv {
  dev,
  test,
  prod;

  static BtestEnv? parse(String? value) => switch (value?.trim()) {
    'dev' => BtestEnv.dev,
    'test' => BtestEnv.test,
    'prod' => BtestEnv.prod,
    _ => null,
  };
}

/// What a run may do: read only, or act too (§3.3's `mode`).
enum BtestFace {
  readonly,
  write;

  static BtestFace? parse(String? value) => switch (value?.trim()) {
    'readonly' => BtestFace.readonly,
    'write' => BtestFace.write,
    _ => null,
  };
}

/// How a call aims at its element (§3.3, check 4-③): by the words it shows,
/// or by a ref / selector where there are none.
enum BtestTarget { words, fallback }

/// One call's verdict: allowed, or refused with the text the agent reads.
class BtestDecision {
  const BtestDecision.allow({this.entry, this.target})
    : message = null,
      evaluateWrite = false,
      entryDenied = false;

  const BtestDecision.deny(
    this.message, {
    this.entry,
    this.target,
    this.evaluateWrite = false,
    this.entryDenied = false,
  });

  /// Why it is refused; null when allowed.
  final String? message;

  /// The URL this call enters, when it is an entry action (§3.6.2).
  final String? entry;

  /// How it aims, for the target reading (4-③); null when it aims at none.
  final BtestTarget? target;

  /// Refused for a script that writes (§3.6.3, rule 1): counted, 4-②.
  final bool evaluateWrite;

  /// Refused as an entry action (§3.6.2): counted on its own.
  final bool entryDenied;

  bool get allowed => message == null;
}

abstract final class BtestPolicy {
  /// The tools a read-only run lets through, by tool (§3.6.4) — everything
  /// else is a write action. `browser_evaluate` is judged apart: only with
  /// `readOnly: true` (§3.6.3, rule 2).
  static const readonlyTools = {
    'browser_tabs',
    'browser_open',
    'browser_navigate',
    'browser_snapshot',
    'browser_inspect',
    'browser_network',
    'browser_console',
    'browser_request',
    'browser_watch',
    'browser_history',
    'browser_sources',
    'browser_scroll',
    'browser_close',
    'browser_performance',
    'browser_coverage',
    'browser_memory',
    'browser_screenshot',
  };

  /// The pages a call goes to without a click (§3.6.2): `browser_navigate`'s
  /// url, `browser_open`'s, and each navigate step of `browser_act` — the
  /// three ways to a deep link, judged as one rule (KD-17).
  static List<String> entryUrls(String tool, Map<String, Object?> input) {
    switch (tool) {
      case 'browser_navigate' || 'browser_open':
        final url = input['url'];
        return url is String && url.trim().isNotEmpty ? [url.trim()] : const [];
      case 'browser_act':
        return [
          for (final step in _steps(input))
            if (step['action'] == 'navigate')
              if (step['url'] case final String url when url.trim().isNotEmpty)
                url.trim(),
        ];
      default:
        return const [];
    }
  }

  /// The defect a call brings to justify an entry after the first (§3.6.2):
  /// `browser_navigate`'s own parameter — its value is already the recorded
  /// finding's one line.
  static String? detourOf(String tool, Map<String, Object?> input) {
    if (tool != 'browser_navigate') return null;
    final detour = input['detour'];
    return detour is String && detour.trim().isNotEmpty ? detour.trim() : null;
  }

  /// How `browser_click` / `browser_type` aim (§3.3, 4-③): their words
  /// (`text`, or the field's `into`) first; a ref or selector as fallback.
  static BtestTarget? targetOf(String tool, Map<String, Object?> input) =>
      switch (tool) {
        'browser_click' => _aim(input, words: input['text']),
        'browser_type' => _aim(input, words: input['into']),
        _ => null,
      };

  /// The targets one `browser_act` call aims at, in order — its click and
  /// type steps, each by its own parameters (§3.3, 4-③).
  static List<BtestTarget> actTargets(Map<String, Object?> input) => [
    for (final step in _steps(input))
      ?switch (step['action']) {
        'click' => _aim(step, words: step['text']),
        'type' => _aim(step, words: step['into']),
        _ => null,
      },
  ];

  static BtestTarget? _aim(Map<String, Object?> step, {required Object? words}) {
    if (words is String && words.trim().isNotEmpty) return BtestTarget.words;
    final ref = step['ref'];
    final selector = step['selector'];
    if (ref is int ||
        (selector is String && selector.trim().isNotEmpty)) {
      return BtestTarget.fallback;
    }
    return null;
  }

  /// The forms a script may not take in btest (§3.6.3, rule 1), named for
  /// the refusal: field assignments, requests of its own, storage and
  /// events, and a script clicking or submitting instead of the user.
  static final _writeForms = <(String, RegExp)>[
    (
      'a field assignment',
      RegExp(
        r'\.\s*(value|checked|selectedIndex|innerHTML|outerHTML|textContent|'
        r'innerText)\s*=(?!=)',
      ),
    ),
    ('fetch(', RegExp(r'\bfetch\s*\(')),
    ('XMLHttpRequest', RegExp('XMLHttpRequest')),
    ('document.cookie =', RegExp(r'document\s*\.\s*cookie\s*=')),
    ('localStorage.setItem', RegExp(r'localStorage\s*\.\s*setItem')),
    ('sessionStorage.setItem', RegExp(r'sessionStorage\s*\.\s*setItem')),
    ('dispatchEvent(', RegExp(r'dispatchEvent\s*\(')),
    ('click()', RegExp(r'\.\s*click\s*\(')),
    ('submit()', RegExp(r'\.\s*submit\s*\(')),
  ];

  /// The write form [expression] takes, or null when it only reads.
  static String? writeFormOf(String expression) {
    for (final (name, pattern) in _writeForms) {
      if (pattern.hasMatch(expression)) return name;
    }
    return null;
  }

  /// Whether [tool] only reads (§3.6.4): `browser_evaluate` when it declares
  /// `readOnly: true`, the read-only face's tools; every other tool writes.
  static bool isReadonly(String tool, Map<String, Object?> input) =>
      switch (tool) {
        'browser_evaluate' => input['readOnly'] == true,
        _ => readonlyTools.contains(tool),
      };

  /// Whether a call [hosts] stands for enters [startUrl] (§3.6.2: compared
  /// without a trailing slash).
  static bool sameUrl(String a, String b) =>
      _trimUrl(a) == _trimUrl(b);

  static String _trimUrl(String url) =>
      url.trim().replaceFirst(RegExp(r'/+$'), '');

  /// The verdict for one browser tool call, the operation rules before the
  /// release's (§3.7: 前置拒绝 run first).
  static BtestDecision judge({
    required String tool,
    required Map<String, Object?> input,
    required BtestEnv env,
    required BtestFace face,
    required String startUrl,
    required int entries,
    required List<String> hosts,
    required bool targeted,
    required Set<String> allowHosts,
    required Set<String> prodHosts,
  }) {
    final urls = entryUrls(tool, input);
    final entry = urls.isEmpty ? null : urls.first;
    final target = targetOf(tool, input);
    final host = hosts.isEmpty ? null : hosts.first;

    // §3.6.2 — a browser_act whose steps come from a file cannot be judged
    // here (the file is read at the tool, after this gate): refused rather
    // than let through, since its navigate steps would skip the entry rule
    // and the destination host's checks.
    if (tool == 'browser_act' &&
        input['file'] is String &&
        '${input['file']}'.trim().isNotEmpty &&
        _steps(input).isEmpty) {
      return BtestDecision.deny(
        _deny(
          tool,
          host,
          'the steps of a file cannot be judged — pass them inline in '
              'btest',
        ),
      );
    }

    // A url given and blank is not an entry the gate can judge: the tool
    // would still navigate by it.
    if (tool == 'browser_navigate' && input['url'] is String) {
      final url = input['url']! as String;
      if (url.trim().isEmpty) {
        return BtestDecision.deny(
          _deny(
            tool,
            null,
            'the url is empty: give a URL, or back / forward / reload',
          ),
          entryDenied: true,
        );
      }
    }

    // §3.6.3, rule 1 — every face: a script reads, never writes.
    if (tool == 'browser_evaluate') {
      final form = writeFormOf('${input['expression'] ?? ''}');
      if (form != null) {
        return BtestDecision.deny(
          _deny(
            tool,
            host,
            'btest may not write values from a script ($form)',
          ),
          evaluateWrite: true,
          target: target,
        );
      }
    }

    // §3.6.2 — one entry, the run's startUrl; after it, a detour only.
    if (entry != null) {
      if (entries == 0) {
        if (!sameUrl(entry, startUrl)) {
          return BtestDecision.deny(
            _deny(
              tool,
              host,
              "the entry must be the run's startUrl $startUrl",
            ),
            entry: entry,
            entryDenied: true,
          );
        }
      } else if (detourOf(tool, input) == null) {
        return BtestDecision.deny(
          _deny(
            tool,
            host,
            'record the defect first, then take the detour — a second entry '
                'needs browser_navigate with detour "one line: what is '
                'missing"',
          ),
          entry: entry,
          entryDenied: true,
        );
      }
    }

    // §3.6.3, rule 3 — replay is the script making the request.
    if (tool == 'browser_request' && input['replay'] == true) {
      return BtestDecision.deny(
        _deny(tool, host, 'replay is refused in btest: it bypasses the form'),
      );
    }

    // §3.7, release 3 — a host the user allowed; unknown hosts refuse too.
    if (targeted && hosts.isEmpty) {
      return BtestDecision.deny(
        _deny(tool, null, 'the target host is unknown (the tab shows no '
            'http(s) page)'),
      );
    }
    for (final one in hosts) {
      if (allowHosts.contains(one)) continue;
      return BtestDecision.deny(
        _deny(
          tool,
          one,
          allowHosts.isEmpty
              ? 'btest.allowHosts is empty, so every browser action is '
                    'refused'
              : 'host is not in btest.allowHosts',
        ),
      );
    }

    // §3.7, release 4 — read-only, or a write with both production gates.
    final readonly = isReadonly(tool, input);
    if (face == BtestFace.readonly && !readonly) {
      return BtestDecision.deny(
        _deny(
          tool,
          host,
          tool == 'browser_evaluate'
              ? 'mode: readonly needs readOnly: true (a script that only '
                    'reads)'
              : 'mode: readonly refuses write actions',
        ),
        target: target,
      );
    }
    if (!readonly) {
      if (env == BtestEnv.prod) {
        return BtestDecision.deny(
          _deny(tool, host, 'rule B: env: prod refuses write actions'),
          target: target,
        );
      }
      if (prodHosts.isEmpty) {
        return BtestDecision.deny(
          _deny(
            tool,
            host,
            'rule B: btest.prodHosts is empty, so write actions are refused',
          ),
          target: target,
        );
      }
      for (final one in hosts) {
        if (prodHosts.contains(one)) {
          return BtestDecision.deny(
            _deny(
              tool,
              one,
              'rule B: this is a production host — env and prodHosts '
                  'conflict, and the stricter one decides',
            ),
            target: target,
          );
        }
      }
    }

    return BtestDecision.allow(entry: entry, target: target);
  }

  /// Rule A's refusal (design §3.7): [`env: prod`] and [`mode: write`] never
  /// start a run — the boundary is the authorization's, not a domain's.
  static const ruleA = 'btest_run_start refused: env: prod with mode: write '
      '— btest does not write in production (rule A); start it read-only, '
      'or on dev/test';

  /// The refusal's one line (§3.7): the action, the host it was aimed at,
  /// the rule, and where the lists are set.
  static String _deny(String action, String? host, String rule) =>
      'btest denied: $action'
      '${host == null || host.isEmpty ? '' : ' on $host'}'
      ' — $rule (Settings → Browser → btest)';

  static Iterable<Map<String, Object?>> _steps(Map<String, Object?> input) => [
    for (final step in input['steps'] as List? ?? const [])
      if (step is Map) step.cast<String, Object?>(),
  ];
}
