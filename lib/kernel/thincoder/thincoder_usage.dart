part of 'thincoder_events.dart';

// The usage face of the translation (F20, §30): what a `usage_update` carries
// beyond `used` — a request's input, its output, and how much of the input
// the prompt cache served — turned into the desktop's own counts.
//
// The block's parse, the `CacheTokens` it makes, the price lookup and the log
// line a block that does not read gets (§30.5, §15.2) live here and nowhere
// else (§30.6): the events file only accumulates what comes back and says it.
//
// The same frame's second block (§31.4) is read here too: what the window
// holds, part by part, and the room the compaction line keeps back. No count
// of the desktop's own is added there — the one subtraction is
// `size − threshold`, and even the sum the frame is checked against is the
// CLI's (§31.1 ②).

/// The key a request's usage comes under, beside `used` (§30.4):
/// `{"input": 900, "output": 334, "cacheRead": 700}` — one frame, a request.
const _usageKey = 'thincoder.dev/usage';

/// The key the same frame's context split comes under (§31.4), beside the
/// usage block:
/// `{"segments": [{"name": "system", "tokens": 3100}], "threshold": 95000,
/// "basis": "estimated"}`.
const _contextKey = 'thincoder.dev/context';

/// How far a `usage_update`'s extension block read (§30.5's four rows).
enum _UsageShape {
  /// No block at all: an older CLI's frame, which is every frame until the
  /// extension is on the wire.
  absent,

  /// All three counts: the cache, the cost and the turn's split all follow.
  whole,

  /// Some of the three: what is known is used, what is missing is left out,
  /// the log names it, and no price follows unless all three are there.
  partial,

  /// The block is there and none of its three is a count: nothing is known
  /// of it, so the cache and the cost already known are kept as they are.
  bad,
}

/// A `usage_update`'s extension block as it read (§30.4), and what the
/// desktop's price table made of the request it tells of (§30.1 ⑤).
class _UsageFrame {
  const _UsageFrame(
    this.shape, {
    this.input,
    this.output,
    this.cacheRead,
    this.cache,
    this.cost,
  });

  final _UsageShape shape;

  /// Tokens the request read, the cache's among them.
  final int? input;

  /// Tokens it wrote.
  final int? output;

  /// Of [input], those read from the cache.
  final int? cacheRead;

  /// [input] by what the cache made of it; null where either of the two
  /// counts it needs is not known.
  final CacheTokens? cache;

  /// What the request cost; null where the table has no price for the model
  /// (not 0 — a missing price is not a free one, §30.7), and where a count
  /// the price needs is missing (§30.5 half a block).
  final double? cost;
}

/// A non-negative whole number as the frames carry the counts (§30.4, §31.4):
/// null where the value is not one. One rule for both blocks of a frame — a
/// count is a count wherever it sits, and two readings of the same rule would
/// drift apart.
int? _count(Object? value) => switch (value) {
  final num value
      when value.isFinite && value >= 0 && value == value.roundToDouble() =>
    value.toInt(),
  _ => null,
};

/// The block [update] carries, read and priced: absent, whole, partial or
/// bad (§30.5). A block under the key that does not read in full is named in
/// the log here — it is never dropped in silence (§15.2). A `_meta` that is
/// not a map carries no block under the key, and is read as absent.
_UsageFrame _usageFrameOf(ThincoderEvents owner, Map<String, Object?> update) {
  final meta = update['_meta'];
  if (meta is! Map || !meta.containsKey(_usageKey)) {
    return const _UsageFrame(_UsageShape.absent);
  }
  final block = meta[_usageKey];
  if (block is! Map) {
    return _usageBad('a usage frame with no map under $_usageKey: $block');
  }
  final input = _count(block['input']);
  final output = _count(block['output']);
  final cacheRead = _count(block['cacheRead']);
  if (input == null && output == null && cacheRead == null) {
    return _usageBad(
      'a usage frame with none of input / output / cacheRead a count: $block',
    );
  }
  // The fields the log should name: a field the block does not carry at all,
  // or one it carries and that is not a count — two different things to
  // whoever follows the line into the log, so the line tells them apart.
  final missing = <String>[];
  void noteMissing(String field, int? value) {
    if (value != null) return;
    missing.add(block.containsKey(field) ? '$field (not a count)' : field);
  }
  noteMissing('input', input);
  noteMissing('output', output);
  noteMissing('cacheRead', cacheRead);
  if (missing.isNotEmpty) {
    // Half a block (§30.5): what it carried is used, what it did not is left
    // out, and the log names the field.
    appEvent('thincoder', 'a usage frame without ${missing.join(' / ')}: '
        '$block');
  }
  // Each count is used where it is known and left out where it is not: the
  // cache needs its own two counts, the price needs all three. A block
  // without `cacheRead` is not priced — its whole prompt would count as a
  // miss, a systematic overestimate, and a wrong number is worse than none
  // (§30.1 ⑤, §30.5 half a block). An agent that counts the cache's tokens
  // apart from the prompt's would have `cacheRead` above `input`: the
  // uncached part floors at 0.
  final CacheTokens? cache;
  final double? cost;
  if (input != null && cacheRead != null) {
    final uncached = math.max(0, input - cacheRead);
    cache = CacheTokens(read: cacheRead, uncached: uncached);
    cost = output == null
        ? null
        : _priced(
            owner,
            uncached: uncached,
            output: output,
            cacheRead: cacheRead,
          );
  } else {
    cache = null;
    cost = null;
  }
  return _UsageFrame(
    missing.isEmpty ? _UsageShape.whole : _UsageShape.partial,
    input: input,
    output: output,
    cacheRead: cacheRead,
    cache: cache,
    cost: cost,
  );
}

/// A block that says nothing that reads: said in the log, and no stats of its
/// own — what was known before it stands (§30.5).
_UsageFrame _usageBad(String said) {
  appEvent('thincoder', said);
  return const _UsageFrame(_UsageShape.bad);
}

/// What the request cost by the desktop's table (§30.1 ⑤): the model in
/// effect's price, times the request's tokens. Null where the table has no
/// price for the model, and where its price is in another currency —
/// `costUsd` is dollars, and a yuan price written into it is a wrong number,
/// not an estimate.
///
/// The one lookup the whole adapter does (§30.5): `UsagePrices.of`, keyed
/// `provider:model` as the model choice reports it (§17.3).
double? _priced(
  ThincoderEvents owner, {
  required int uncached,
  required int output,
  required int cacheRead,
}) {
  final model = owner.selected('model');
  if (model == null || model.isEmpty) return null;
  final at = model.indexOf(':');
  final upstream = at <= 0 ? '' : model.substring(0, at);
  final named = at <= 0 ? model : model.substring(at + 1);
  final now = DateTime.now();
  final price = UsagePrices.current.of(upstream, named, at: now);
  if (price == null || price.currency != 'USD') return null;
  return _rounded(
    price.cost(
      UsageCall(
        at: now,
        duration: Duration.zero,
        status: 200,
        provider: upstream,
        model: named,
        input: uncached,
        output: output,
        cacheRead: cacheRead,
        stream: false,
      ),
    ),
  );
}

/// [amount] with the float dust off (a millionth of a dollar): it is a sum
/// of many requests, and only its dollars and cents are ever read.
double _rounded(double amount) => (amount * 1e6).roundToDouble() / 1e6;

/// The context split a frame carries (§31.4), read into the segments the
/// panel draws (§31.5): the CLI's own counts verbatim, then the room the
/// compaction line keeps back.
///
/// Nothing is subtracted here and nothing is made to fit (§31.1 ②): the
/// desktop's one arithmetic is `size − threshold`, and even the sum below is
/// the CLI's own. The producer's counts are estimates while `used` is what
/// the agent measured (or an estimate scaled by a calibration the counts did
/// not get), so the two need not agree. Counts that add up to more than
/// `used` are not trimmed or scaled to fit: the block is dropped whole and
/// the log names it (§31.5), because a share divided by a smaller `used`
/// would be a number the CLI never reported.
///
/// A block that is there and does not read is named in the log, the failing
/// part at a time (§15.2) — one bad item does not throw the good ones away,
/// and the sum is taken over what survived. A block that is not there at all
/// is an older CLI's frame, and says nothing worth a line (§31.4 末行).
///
/// The reserve is the frame's own field, read after that check (§31.5's
/// order): it follows even where not one producer item survived — the parts
/// are unknown, the compaction line is not, and one is a thing to draw.
List<ContextSegment> _contextOf(
  Map<String, Object?> update, {
  required int used,
  required int size,
}) {
  final meta = update['_meta'];
  if (meta is! Map || !meta.containsKey(_contextKey)) return const [];
  final block = meta[_contextKey];
  if (block is! Map) {
    appEvent(
      'thincoder',
      'a usage frame with no map under $_contextKey: $block',
    );
    return const [];
  }
  final listed = block['segments'];
  if (listed is! List) {
    appEvent(
      'thincoder',
      'a context frame whose segments is not a list: $block',
    );
    return const [];
  }
  final segments = <ContextSegment>[];
  for (final item in listed) {
    if (item is! Map) {
      appEvent('thincoder', 'a context segment that is not a map: $item');
      continue;
    }
    final name = item['name'];
    if (name is! String || name.isEmpty) {
      appEvent('thincoder', 'a context segment with no name: $item');
      continue;
    }
    final tokens = _count(item['tokens']);
    if (tokens == null) {
      appEvent(
        'thincoder',
        'a context segment whose tokens is not a count: $item',
      );
      continue;
    }
    // The CLI's count under the CLI's name: the panel knows the parts it
    // draws and shows any other name as it came (§31.5 末段).
    segments.add(ContextSegment(name, tokens));
  }
  final sum = segments.fold(0, (sum, segment) => sum + segment.tokens);
  if (sum > used) {
    final basis = switch (block['basis']) {
      final String basis when basis.isNotEmpty => basis,
      _ => 'not told',
    };
    appEvent(
      'thincoder',
      'a context frame whose segments add up to $sum, more than its used '
      '$used (basis: $basis)',
    );
    return const [];
  }
  // The room the auto-compaction line keeps back (§31.1 ⑤) — the panel's own
  // reserve cell, and its compaction point: `size − threshold`. A line that
  // is missing or outside the window keeps nothing back; not drawn is better
  // than drawn wrong (§31.5).
  final threshold = _count(block['threshold']);
  if (threshold != null && threshold > 0 && threshold < size) {
    segments.add(
      ContextSegment('', size - threshold, kind: ContextKind.buffer),
    );
  }
  return segments;
}
