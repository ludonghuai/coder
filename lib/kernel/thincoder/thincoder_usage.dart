part of 'thincoder_events.dart';

// The usage face of the translation (F20, §30): what a `usage_update` carries
// beyond `used` — a request's input, its output, and how much of the input
// the prompt cache served — turned into the desktop's own counts.
//
// The block's parse, the `CacheTokens` it makes, the price lookup and the log
// line a block that does not read gets (§30.5, §15.2) live here and nowhere
// else (§30.6): the events file only accumulates what comes back and says it.

/// The key a request's usage comes under, beside `used` (§30.4):
/// `{"input": 900, "output": 334, "cacheRead": 700}` — one frame, a request.
const _usageKey = 'thincoder.dev/usage';

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
  int? count(Object? value) => switch (value) {
    final num value
        when value.isFinite && value >= 0 && value == value.roundToDouble() =>
      value.toInt(),
    _ => null,
  };
  final input = count(block['input']);
  final output = count(block['output']);
  final cacheRead = count(block['cacheRead']);
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
