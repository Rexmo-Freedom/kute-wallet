// lib/services/polymarket/thin_history.dart
//
// The price history of a market almost nobody trades, made drawable.
//
// Polymarket's history of such a market is not a record of trades: with
// an empty or very wide book the price it reports jumps between the two
// sides of the spread (17%, 30%, 17%, 31%, 18% ten minutes apart on a
// market with $152 of volume and a 4%/30% book), which drew as needles
// and combs and read as a broken chart. The CHART's copy of the series is
// cleaned here; the prices used to trade, the live price on a tag and
// every profit-and-loss figure never pass through this file.
//
// Only thin markets ([polyMarketIsThin]). On a liquid market a one-point
// jump that comes straight back is news, and the rule below would remove
// it: of the series recorded on 2026-10-05 it leaves both leaders of the
// Brazil election untouched on every range, but takes a real ten-point
// spike out of "Will the U.S. invade Iran" ($71M traded). And never a
// game being played, where a goal is exactly a jump.
//
// Pure Dart; unit tested on recorded series in
// test/services/polymarket/thin_history_test.dart.

import 'package:kute/models/polymarket_model.dart';

/// A market that has traded less than this in all (US dollars) is thin.
const double kPolyThinVolumeUsd = 5000;

/// Whether a market with [volume] traded in all is thin: its history is
/// mostly quotes, not trades. A volume that is not known is not thin.
bool polyMarketIsThin(double? volume) =>
    volume != null && volume < kPolyThinVolumeUsd;

/// Whether the market behind [tokenId] in [event] is thin: by the
/// outcome's own volume where it has one (each candidate of an election
/// trades on its own), else by the event's (a Yes/No market's is the
/// event's; Gamma leaves the volume keys off a market that has never
/// traded, and an event that traded under the line as a whole has no
/// outcome above it).
bool polyTokenIsThin(PolymarketEvent event, String? tokenId) {
  if (tokenId == null || tokenId.isEmpty) return false;
  for (final o in event.outcomes) {
    if (o.tokenId != tokenId && o.noTokenId != tokenId) continue;
    return polyMarketIsThin(o.volume ?? event.volume);
  }
  return false;
}

/// On a thin market, a live price this far (fifteen points of chance)
/// from the last point of the history is not drawn as a cliff at the end
/// of the line: the line ends at its history and the value tag alone
/// says the live price. A never-traded market's history is its old wide
/// quotes; its live book may be tight and elsewhere.
const double kPolyThinCliff = 0.15;

/// Whether a line's newest point is left where its history ends rather
/// than pinned to [live]: only a thin market's, and only when the live
/// price is [kPolyThinCliff] or more away from [last].
bool polyThinCliff(
    {required bool thin, required double? live, required double? last}) =>
    thin && live != null && last != null && (live - last).abs() >= kPolyThinCliff;

/// A spike departs from the points around it by at least this (eight
/// points of chance)…
const double kPolySpikeMinJump = 0.08;

/// …and by at least this many times the median absolute deviation of the
/// six points either side of it, so a line that really is that jumpy
/// keeps its jumps.
const double kPolySpikeMadFactor = 4.0;

/// How long an excursion can be and still be a spike (points).
const int kPolySpikeMaxPoints = 2;

/// Light smoothing is applied when the line still turns round at more
/// than this share of its points.
const double kPolyCombTurnShare = 1 / 3;

double _median(List<double> values) {
  final v = [...values]..sort();
  final n = v.length;
  if (n == 0) return 0;
  return n.isOdd ? v[n ~/ 2] : (v[n ~/ 2 - 1] + v[n ~/ 2]) / 2;
}

/// [prices] without their spikes. A spike is one or two points in a row
/// ([kPolySpikeMaxPoints]) that
///
///   * all lie on the same side of the point before them,
///   * depart from the point before AND the point after by at least
///     max([kPolySpikeMinJump], [kPolySpikeMadFactor] × the median
///     absolute deviation of the six points either side), and
///   * come back: the point after is within max(2 points, a quarter of
///     the jump) of the point before.
///
/// Its points are put on the straight line between the two around it. A
/// move that stays (a level shift) fails the last test and is kept. The
/// first point, which has nothing before it, is set to the second when it
/// stands that far from the three that follow and they agree; the last
/// point is the latest price and is never touched.
List<double> despikePrices(List<double> prices) {
  final n = prices.length;
  if (n < 4) return prices;
  List<double>? out;
  double at(int i) => out == null ? prices[i] : out[i];

  double threshold(int from, int to) {
    final around = <double>[
      for (var k = from - 6; k < to + 6; k++)
        if (k >= 0 && k < n && (k < from || k >= to)) prices[k],
    ];
    final mid = _median(around);
    final mad = _median([for (final x in around) (x - mid).abs()]);
    final byNoise = kPolySpikeMadFactor * mad;
    return byNoise > kPolySpikeMinJump ? byNoise : kPolySpikeMinJump;
  }

  // The first point.
  final next3 = [prices[1], prices[2], prices[3]];
  final spread3 = next3.reduce((a, b) => a > b ? a : b) -
      next3.reduce((a, b) => a < b ? a : b);
  if ((prices[0] - _median(next3)).abs() >= threshold(0, 1) &&
      spread3 <= 0.02) {
    out = [...prices];
    out[0] = prices[1];
  }

  var i = 1;
  while (i < n - 1) {
    var removed = false;
    for (var length = 1; length <= kPolySpikeMaxPoints; length++) {
      final after = i + length;
      if (after >= n) break;
      final before = at(i - 1), back = prices[after];
      var up = true, down = true;
      var jump = double.infinity, drop = double.infinity;
      for (var k = i; k < after; k++) {
        final d = prices[k] - before;
        if (d <= 0) up = false;
        if (d >= 0) down = false;
        if (d.abs() < jump) jump = d.abs();
        final r = (prices[k] - back).abs();
        if (r < drop) drop = r;
      }
      if (!up && !down) continue;
      final t = threshold(i, after);
      final least = jump < drop ? jump : drop;
      final band = least * 0.25 > 0.02 ? least * 0.25 : 0.02;
      if (jump >= t && drop >= t && (back - before).abs() <= band) {
        out ??= [...prices];
        for (var k = i; k < after; k++) {
          out[k] = before + (back - before) * (k - i + 1) / (length + 1);
        }
        i = after;
        removed = true;
        break;
      }
    }
    if (!removed) i++;
  }
  return out ?? prices;
}

/// The share of [prices]' inner points where the line turns round (a rise
/// followed by a fall or the reverse; flat stretches do not count).
double priceTurnShare(List<double> prices) {
  final n = prices.length;
  if (n < 3) return 0;
  var turns = 0;
  var last = 0.0;
  for (var i = 1; i < n; i++) {
    final d = prices[i] - prices[i - 1];
    if (d == 0) continue;
    if (last != 0 && (d > 0) != (last > 0)) turns++;
    last = d;
  }
  return turns / (n - 2);
}

/// [prices] under a running median of five, when the line is a comb: it
/// turns round at more than [kPolyCombTurnShare] of its points (the price
/// stepping to and fro across a spread bucket after bucket). A median
/// keeps a level shift where it happened and as sharp as it was. The two
/// points at either end are left as they are. Anything else comes back
/// untouched.
List<double> decombPrices(List<double> prices) {
  final n = prices.length;
  if (n < 12 || priceTurnShare(prices) <= kPolyCombTurnShare) return prices;
  final out = [...prices];
  for (var i = 2; i < n - 2; i++) {
    out[i] = _median(prices.sublist(i - 2, i + 3));
  }
  return out;
}

/// A thin market's [points] for its chart: spikes out ([despikePrices]),
/// then the comb, if one is left ([decombPrices]). The same list comes
/// back when nothing changed. Call only for a market that
/// [polyMarketIsThin] and is not a game in play.
List<PolymarketPricePoint> smoothThinHistory(
    List<PolymarketPricePoint> points) {
  if (points.length < 4) return points;
  final raw = [for (final p in points) p.price];
  final clean = decombPrices(despikePrices(raw));
  if (identical(clean, raw)) return points;
  return [
    for (var i = 0; i < points.length; i++)
      clean[i] == raw[i]
          ? points[i]
          : PolymarketPricePoint(
              timestamp: points[i].timestamp, price: clean[i]),
  ];
}
