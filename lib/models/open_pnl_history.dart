// lib/models/open_pnl_history.dart
//
// THE OPEN POSITIONS' P&L OVER TIME (founder, 6 November 2026, on the
// Portfolio's Positions hero: "here I wanted the P&L of the open
// positions — the graph. Put it back."). What the positions held NOW made
// or lost since each was opened, at the prices of each moment: never the
// account's P&L (realised and open together) and never today's sizes
// against prices from before a position existed.
//
// Each open position is a LEG ([OpenPnlLeg]): the stretches it was held
// in ([OpenPnlStep]: from a moment, the quantity held, signed so a short
// is negative, and its average entry) and its market's prices. Its P&L at
// a moment t is
//
//     quantity(t) × (price(t) − entry(t))
//
// (a short's quantity is negative, so a falling price is its gain), 0
// before it was opened. The stretches come from the venue's own records:
//
//   * a Hyperliquid perp ([hlPerpOpenSteps]): its fills (`userFills`,
//     each with the position before it), from the fill that opened the
//     position held now (the last one that took it from flat, or from the
//     other side) on; an increase moves the average entry (the venue's own
//     weighted average), a reduction keeps it; the last stretch is the
//     position as the venue reports it now (size, entry). Without that
//     opening fill (no fills read, or the position older than the fills
//     the venue keeps) the open is unknown and the position is not
//     charted;
//   * a Hyperliquid spot holding ([hlSpotOpenSteps]): its buys and sells
//     from the first buy of the holding held now; the average cost is the
//     venue's recorded cost over the holding today on every stretch (the
//     spot fills' prices are in the pair's raw units on some pairs, so
//     they are not used);
//   * a Polymarket position ([polyOpenSteps]): its trades from the first
//     buy after the holding was last empty, the average price moving on
//     each buy; the last stretch is the position as the Data API reports
//     it now (shares, average price). Without its trades, its first entry
//     with today's shares and average price throughout (the
//     approximation the position screen's journey line draws too).
//
// The legs are added on every moment any of them moves ([openPnlChanges])
// and laid on the Balance charts' grid ([openPnlSeries], the P&L chart's
// lead-in and buckets), from a short lead-in before the oldest position
// was opened to now. The chart pins its last point to the live figure.
//
// Pure: nothing here reads a provider or the network.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlFill;
import 'package:kute/models/hyperliquid_model.dart' show HyperliquidCandle;
import 'package:kute/models/portfolio_performance.dart'
    show debugPnlSeriesGrids;
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Activity;

/// Under this many units a position is flat (a fill's rounding).
const double kOpenPnlFlat = 1e-9;

/// One stretch of an open position: from [at], [qty] held (signed: a short
/// is negative) at the average entry [entry].
@immutable
class OpenPnlStep {
  const OpenPnlStep(this.at, this.qty, this.entry);

  final DateTime at;
  final double qty;
  final double entry;

  /// The P&L of this stretch at [price].
  double pnlAt(double price) => qty * (price - entry);

  @override
  bool operator ==(Object other) =>
      other is OpenPnlStep &&
      other.at == at &&
      other.qty == qty &&
      other.entry == entry;

  @override
  int get hashCode => Object.hash(at, qty, entry);

  @override
  String toString() => 'OpenPnlStep($at, $qty @ $entry)';
}

/// A price at a moment, oldest first in a list.
typedef OpenPnlPrice = (DateTime, double);

/// One open position charted: its stretches ([steps], oldest first, the
/// first one its open) and its market's [prices] (oldest first, from
/// before the open where the venue has them).
@immutable
class OpenPnlLeg {
  const OpenPnlLeg(
      {required this.key, required this.steps, required this.prices})
      : assert(steps.length > 0);

  /// The position's key ([openPnlKeyPerp] and the others).
  final String key;
  final List<OpenPnlStep> steps;
  final List<OpenPnlPrice> prices;

  /// When the position held now was opened.
  DateTime get openedAt => steps.first.at;

  /// Its P&L at [t]: 0 before it was opened; else the stretch at [t]
  /// against the last price at or before [t] (the stretch's entry when no
  /// price is known yet, so the open itself reads 0).
  double valueAt(DateTime t) {
    if (t.isBefore(openedAt)) return 0;
    final step = _lastAtOrBefore(steps, t, (s) => s.at)!;
    final price = _lastAtOrBefore(prices, t, (p) => p.$1);
    return step.pnlAt(price?.$2 ?? step.entry);
  }
}

T? _lastAtOrBefore<T>(List<T> list, DateTime t, DateTime Function(T) at) {
  var lo = 0, hi = list.length - 1, found = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (!at(list[mid]).isAfter(t)) {
      found = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return found < 0 ? null : list[found];
}

/// The key of a Hyperliquid perp's leg.
String openPnlKeyPerp(String coin) => 'perp:$coin';

/// The key of a Hyperliquid spot holding's leg.
String openPnlKeySpot(String coin) => 'spot:$coin';

/// The key of a Polymarket position's leg.
String openPnlKeyPrediction(
        {required String? tokenId,
        required String marketId,
        required String outcome}) =>
    'pm:${tokenId ?? '$marketId/$outcome'}';

/// Stretches sharing a moment kept as the last of them (one order filled
/// in parts at once).
List<OpenPnlStep> _merged(List<OpenPnlStep> steps) {
  final out = <OpenPnlStep>[];
  for (final s in steps) {
    if (out.isNotEmpty && out.last.at == s.at) {
      out[out.length - 1] = s;
    } else {
      out.add(s);
    }
  }
  return out;
}

/// The stretches of the Hyperliquid perp on [coin] held now ([szi] signed,
/// [entryPx] the venue's average entry) from its [fills] (see the file
/// header). Null when the fills do not reach the fill that opened it.
List<OpenPnlStep>? hlPerpOpenSteps({
  required String coin,
  required double szi,
  required double entryPx,
  required Iterable<HlFill> fills,
}) {
  if (szi.abs() <= kOpenPnlFlat) return null;
  final mine = fills.where((f) => f.coin == coin && f.sz > 0).toList()
    ..sort((a, b) => a.time.compareTo(b.time));
  if (mine.isEmpty) return null;
  final side = szi.sign;
  // The position before and after each fill: the venue's own
  // startPosition where it gives one, else what the fills before it
  // added up to.
  final before = <double>[];
  final after = <double>[];
  var running = 0.0;
  for (final f in mine) {
    final start = f.startPosition ?? running;
    final end = start + (f.isBuy ? f.sz : -f.sz);
    before.add(start);
    after.add(end);
    running = end;
  }
  bool onSide(double v) => v.abs() > kOpenPnlFlat && v.sign == side;
  // The opening fill: the last one that took the position from flat (or
  // the other side) to this side.
  var open = -1;
  for (var i = mine.length - 1; i >= 0; i--) {
    if (onSide(after[i]) && !onSide(before[i])) {
      open = i;
      break;
    }
  }
  if (open < 0) return null;
  final steps = <OpenPnlStep>[];
  var qty = after[open];
  var entry = mine[open].px;
  steps.add(OpenPnlStep(_local(mine[open].time), qty, entry));
  for (var i = open + 1; i < mine.length; i++) {
    final f = mine[i];
    final from = before[i];
    final to = after[i];
    if (!onSide(to)) {
      // Flat or flipped after the open: these fills are not the position
      // held now (the venue's records disagree); not charted.
      return null;
    }
    if (to.abs() > from.abs()) {
      // An increase: the venue's weighted average entry.
      entry = (from.abs() * entry + (to.abs() - from.abs()) * f.px) / to.abs();
    }
    qty = to;
    steps.add(OpenPnlStep(_local(f.time), qty, entry));
  }
  // The last stretch is the position as the venue reports it now.
  final last = steps.removeLast();
  steps.add(OpenPnlStep(last.at, szi, entryPx));
  return _merged(steps);
}

/// The stretches of the spot holding held now ([total] units at the
/// average cost [avgCost], the venue's recorded cost over [total]) from
/// its [fills] on any of [coins] (the pair's wire coin and the token's
/// name: the venue keys spot fills either way). Null when the fills do
/// not reach its first buy.
List<OpenPnlStep>? hlSpotOpenSteps({
  required Set<String> coins,
  required double total,
  required double avgCost,
  required Iterable<HlFill> fills,
}) {
  if (total <= kOpenPnlFlat) return null;
  final mine = fills.where((f) => coins.contains(f.coin) && f.sz > 0).toList()
    ..sort((a, b) => a.time.compareTo(b.time));
  if (mine.isEmpty) return null;
  var held = 0.0;
  // Null while the holding was already held before the fills read (its
  // first buy unknown) until it is next empty.
  List<OpenPnlStep>? steps = <OpenPnlStep>[];
  for (final f in mine) {
    final start = f.startPosition ?? held;
    held = math.max(0, start + (f.isBuy ? f.sz : -f.sz));
    if (held <= kOpenPnlFlat) {
      steps = [];
      continue;
    }
    if (steps != null && steps.isEmpty && start > kOpenPnlFlat) steps = null;
    steps?.add(OpenPnlStep(_local(f.time), held, avgCost));
  }
  if (steps == null || steps.isEmpty) return null;
  final last = steps.removeLast();
  steps.add(OpenPnlStep(last.at, total, avgCost));
  return _merged(steps);
}

/// The stretches of the Polymarket position on [tokenId] held now ([size]
/// shares at the average price [avgPrice]) from the account's trade
/// history [activities]: from the first buy after the holding was last
/// empty. Null when the history has no such buy.
List<OpenPnlStep>? polyOpenSteps({
  required String tokenId,
  required double size,
  required double avgPrice,
  required Iterable<Activity> activities,
}) {
  if (tokenId.isEmpty || size <= kOpenPnlFlat) return null;
  final trades = activities
      .where((a) =>
          a.asset == tokenId &&
          a.size > 0 &&
          const {'BUY', 'SELL'}.contains((a.side ?? '').toUpperCase()))
      .toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  var shares = 0.0;
  var cost = 0.0;
  var steps = <OpenPnlStep>[];
  for (final t in trades) {
    final at = t.timestampDate.toLocal();
    final buy = (t.side ?? '').toUpperCase() == 'BUY';
    if (buy) {
      if (shares <= 1e-6) {
        shares = 0;
        cost = 0;
        steps = [];
      }
      final price = t.price ??
          (t.size > 0 && t.usdcSize > 0 ? t.usdcSize / t.size : avgPrice);
      shares += t.size;
      cost += t.size * price;
    } else {
      if (steps.isEmpty) continue;
      final entry = shares > 0 ? cost / shares : 0.0;
      shares = math.max(0, shares - t.size);
      cost = entry * shares;
      if (shares <= 1e-6) {
        steps = [];
        continue;
      }
    }
    steps.add(OpenPnlStep(at, shares, shares > 0 ? cost / shares : avgPrice));
  }
  if (steps.isEmpty) return null;
  // A history that does not add up to the shares held now is missing
  // trades (bought before the history the API keeps, or moved in): its
  // first buy is not the holding's.
  if ((shares - size).abs() > math.max(0.01, size * 0.02)) return null;
  final last = steps.removeLast();
  steps.add(OpenPnlStep(last.at, size, avgPrice));
  return _merged(steps);
}

DateTime _local(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

/// A Hyperliquid candle read as prices: the first candle's open at its
/// open, then each close at its close (the candle still running at
/// [now]), oldest first.
List<OpenPnlPrice> openPnlCandlePrices(
    List<HyperliquidCandle> candles, DateTime now) {
  final sorted = [...candles]
    ..sort((a, b) => a.openTime.compareTo(b.openTime));
  final out = <OpenPnlPrice>[];
  for (final k in sorted) {
    if (!(k.close > 0) || !k.close.isFinite) continue;
    if (out.isEmpty && k.open > 0 && k.open.isFinite) {
      out.add((k.openTime.toLocal(), k.open));
    }
    final at = k.closeTime.isAfter(now) ? now : k.closeTime;
    final local = at.toLocal();
    if (out.isNotEmpty && !local.isAfter(out.last.$1)) {
      out[out.length - 1] = (out.last.$1, k.close);
    } else {
      out.add((local, k.close));
    }
  }
  return out;
}

/// A coarse price history with a finer recent one laid over its end: the
/// [coarse] points before the first [fine] one, then [fine].
List<OpenPnlPrice> openPnlMergePrices(
    List<OpenPnlPrice> coarse, List<OpenPnlPrice> fine) {
  if (fine.isEmpty) return coarse;
  if (coarse.isEmpty) return fine;
  final from = fine.first.$1;
  return [
    for (final p in coarse)
      if (p.$1.isBefore(from)) p,
    ...fine,
  ];
}

/// The candles a Hyperliquid leg opened [age] ago reads: the finest
/// interval that keeps the history to a few hundred bars (a quarter hour
/// under three days, an hour under a month, a day beyond), and past a
/// month the last eight days hourly as well, so a week on screen keeps its
/// hours. Each as (interval, how far back), the first the whole history.
List<(String, Duration)> openPnlCandlePlan(Duration age) {
  if (age <= const Duration(days: 3)) {
    return [('15m', age + const Duration(hours: 1))];
  }
  if (age <= const Duration(days: 30)) {
    return [('1h', age + const Duration(hours: 2))];
  }
  return [
    ('1d', age + const Duration(days: 2)),
    ('1h', const Duration(days: 8)),
  ];
}

/// The open positions' P&L added, as the moments it moved: (when, the sum
/// of every leg at that moment), oldest first, up to [now]. A leg moves
/// at its open, at each of its stretches and at each of its prices after
/// the open.
List<(DateTime, double)> openPnlChanges(List<OpenPnlLeg> legs, DateTime now) {
  final nowUs = now.microsecondsSinceEpoch;
  final events = <(int, int)>[];
  for (var k = 0; k < legs.length; k++) {
    final leg = legs[k];
    final open = leg.openedAt.microsecondsSinceEpoch;
    if (open > nowUs) continue;
    events.add((open, k));
    for (final s in leg.steps) {
      final us = s.at.microsecondsSinceEpoch;
      if (us > open && us <= nowUs) events.add((us, k));
    }
    for (final p in leg.prices) {
      final us = p.$1.microsecondsSinceEpoch;
      if (us > open && us <= nowUs) events.add((us, k));
    }
  }
  events.sort((a, b) => a.$1.compareTo(b.$1));
  final n = legs.length;
  final stepAt = List<int>.filled(n, -1);
  final priceAt = List<int>.filled(n, -1);
  final contrib = List<double>.filled(n, 0);
  final out = <(DateTime, double)>[];
  var i = 0;
  while (i < events.length) {
    final us = events[i].$1;
    while (i < events.length && events[i].$1 == us) {
      final k = events[i].$2;
      final leg = legs[k];
      while (stepAt[k] + 1 < leg.steps.length &&
          leg.steps[stepAt[k] + 1].at.microsecondsSinceEpoch <= us) {
        stepAt[k]++;
      }
      while (priceAt[k] + 1 < leg.prices.length &&
          leg.prices[priceAt[k] + 1].$1.microsecondsSinceEpoch <= us) {
        priceAt[k]++;
      }
      final step = leg.steps[math.max(0, stepAt[k])];
      final price = priceAt[k] < 0 ? step.entry : leg.prices[priceAt[k]].$2;
      contrib[k] = step.pnlAt(price);
      i++;
    }
    // Added afresh at each moment, so no rounding builds up.
    var sum = 0.0;
    for (final v in contrib) {
      sum += v;
    }
    out.add((DateTime.fromMicrosecondsSinceEpoch(us), sum));
  }
  return out;
}

/// The open positions' P&L at [t] ([OpenPnlLeg.valueAt] added).
double openPnlValueAt(List<OpenPnlLeg> legs, DateTime t) {
  var sum = 0.0;
  for (final l in legs) {
    sum += l.valueAt(t);
  }
  return sum;
}

/// When the oldest of [legs] was opened, never after [now]; null with
/// none.
DateTime? openPnlOldest(List<OpenPnlLeg> legs, DateTime now) {
  DateTime? oldest;
  for (final l in legs) {
    if (oldest == null || l.openedAt.isBefore(oldest)) oldest = l.openedAt;
  }
  if (oldest != null && oldest.isAfter(now)) return now;
  return oldest;
}

/// The chart's line: [openPnlChanges] laid on the Balance charts' grid
/// ([stepGridSeries], the same ranges, buckets and pinch limits as the P&L
/// chart's [BalanceSeries]) from a short lead-in (a twelfth of the
/// history, at least an hour) before the oldest open, held at 0, to
/// [now]; each grid point the sum at the last moment at or before it. The
/// last point is the sum at [now] (the chart puts the live figure there).
/// Null with no legs.
BalanceSeries? openPnlSeries(List<OpenPnlLeg> legs, DateTime now) {
  final end = now.toLocal();
  final oldest = openPnlOldest(legs, end);
  if (oldest == null) return null;
  debugPnlSeriesGrids++;
  var lead = Duration(
      microseconds:
          (end.difference(oldest).inMicroseconds * kBalanceHistoryLeadIn)
              .round());
  if (lead < kBalanceMinLeadIn) lead = kBalanceMinLeadIn;
  final first = oldest.subtract(lead);
  final changes = openPnlChanges(legs, end);
  return stepGridSeries(
    first: first,
    now: end,
    opening: 0,
    changes: changes.isEmpty ? [(first, 0.0)] : changes,
    current: changes.isEmpty ? 0.0 : changes.last.$2,
  );
}

/// The range the chart opens on: the shortest whose reach covers the
/// oldest open position's entry ([oldestOpen]), ALL past a year.
BalanceRange openPnlDefaultRange(DateTime oldestOpen, DateTime now) {
  final age = now.difference(oldestOpen);
  for (final r in BalanceRange.values) {
    final d = r.duration;
    if (d == null || age <= d) return r;
  }
  return BalanceRange.all;
}
