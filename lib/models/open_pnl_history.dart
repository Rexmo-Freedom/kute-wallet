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
    show
        PortfolioPnlPoint,
        PredictionRecord,
        debugPnlSeriesGrids,
        distinctPredictionRecords;
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

/// A position's realised P&L up to a moment: (when, all it realised so
/// far), oldest first in a list.
typedef OpenPnlRealised = (DateTime, double);

/// One position charted: its stretches ([steps], oldest first, the first
/// one its open; a stretch of 0 is flat), its market's [prices] (oldest
/// first, from before the open where the venue has them) and, on the
/// whole P&L history ([pnlHistoryLegs] and the others), what it realised
/// ([realised]: closes, sells, redeems, fees, each step the running
/// total). The Positions chart's legs realise nothing: they are what is
/// open now.
@immutable
class OpenPnlLeg {
  const OpenPnlLeg({
    required this.key,
    required this.steps,
    required this.prices,
    this.realised = const [],
  }) : assert(steps.length > 0 || realised.length > 0);

  /// The position's key ([openPnlKeyPerp] and the others).
  final String key;
  final List<OpenPnlStep> steps;
  final List<OpenPnlPrice> prices;
  final List<OpenPnlRealised> realised;

  /// When the position was opened (its first stretch, or its first
  /// realised step when it has no stretch charted).
  DateTime get openedAt {
    if (steps.isEmpty) return realised.first.$1;
    if (realised.isEmpty) return steps.first.at;
    final a = steps.first.at, b = realised.first.$1;
    return b.isBefore(a) ? b : a;
  }

  /// Its P&L at [t]: what it had realised by [t], plus 0 before its first
  /// stretch, else the stretch at [t] against the last price at or before
  /// [t] (the stretch's entry when no price is known yet, so the open
  /// itself reads 0).
  double valueAt(DateTime t) {
    final done = realised.isEmpty
        ? 0.0
        : _lastAtOrBefore(realised, t, (r) => r.$1)?.$2 ?? 0.0;
    if (steps.isEmpty || t.isBefore(steps.first.at)) return done;
    final step = _lastAtOrBefore(steps, t, (s) => s.at)!;
    final price = _lastAtOrBefore(prices, t, (p) => p.$1);
    return done + step.pnlAt(price?.$2 ?? step.entry);
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

// ─────────────────────── the whole P&L history ───────────────────────
//
// THE PORTFOLIO'S P&L OVER TIME, DRAWN AS THE POSITIONS CHART IS (founder,
// 6 November 2026: the P&L and Activity heroes "use the same detailed
// engine as the Positions chart"). The account's P&L at a moment t is
// every position's
//
//     realised(t) + quantity(t) × (price(t) − entry(t))
//
// realised(t) stepping at each close, sell, redeem and fee, the second
// term what the position held at t was winning or losing then, from its
// own entry, at its market's prices:
//
//   * a Hyperliquid perp ([hlPerpHistory]): every fill on its coin, oldest
//     first: an increase moves the average entry (the venue's weighted
//     average), a reduction realises (price − entry) on what it closes, a
//     flip closes the one side and opens the other at that fill, and every
//     fill's dollar fee is paid out of the realised; between fills it is
//     marked at the coin's candles. When the fills read do not reach back
//     to the position's own open (the venue keeps the latest fills only),
//     what was held before the first fill read is marked from that fill's
//     price (its moves from there on, never what it made before), and the
//     venue's own P&L under the line carries the rest ([openPnlVenueLeg]),
//     so nothing is counted twice;
//   * a Hyperliquid spot holding: its sells' realised P&L as the venue
//     books it ([hlSpotRealised]; spot fill prices are in raw pair units on
//     some pairs, so they are never priced by hand), and the holding held
//     now as on the Positions chart (its recorded cost);
//   * a prediction: its realised P&L as Polymarket books it (sells and
//     claims, fees included; a resolved one at its payout) at its last
//     event ([polyRealisedLegs]), and the position held now as on the
//     Positions chart;
//   * under them all, each venue's own published P&L ([openPnlVenueLeg]):
//     at every moment the venue published its figure the line is that
//     figure, what the positions charted do not carry held from there.

/// What a Hyperliquid perp's fills say it did ([hlPerpHistory]): its
/// stretches (0 where it was flat) and its realised steps; [assumedEntry]
/// when it was already held before the first fill read (its entry then
/// marked from that fill's price).
typedef HlPerpHistory = ({
  List<OpenPnlStep> steps,
  List<OpenPnlRealised> realised,
  bool assumedEntry,
});

/// A fill's fee is in dollars (USDC, or a USD-pegged quote on the newer
/// perps) and so comes out of the realised; a fee in the bought token (a
/// spot buy) does not.
bool _usdFee(HlFill f) =>
    f.feeToken.isEmpty || f.feeToken.toUpperCase().startsWith('USD');

/// Whether [f] is a spot fill (a pair's wire coin "@107" or "PURR/USDC",
/// or a plain Buy / Sell); a perp's say Open / Close Long / Short.
bool hlFillIsSpot(HlFill f) =>
    f.coin.startsWith('@') ||
    f.coin.contains('/') ||
    f.dir == 'Buy' ||
    f.dir == 'Sell';

/// The whole history of the Hyperliquid perp on [coin] from its [fills]
/// (see the section header): null without a fill on it. [szi] and
/// [entryPx]: the position open now as the venue reports it (null: flat
/// now), which the last stretch is (its entry the venue's own, unless the
/// fills never reached its open).
HlPerpHistory? hlPerpHistory({
  required String coin,
  required Iterable<HlFill> fills,
  double? szi,
  double? entryPx,
}) {
  final mine = fills.where((f) => f.coin == coin && f.sz > 0).toList()
    ..sort((a, b) => a.time.compareTo(b.time));
  if (mine.isEmpty) return null;
  bool flat(double v) => v.abs() <= kOpenPnlFlat;
  bool sameSide(double a, double b) => !flat(a) && !flat(b) && a.sign == b.sign;
  var pos = mine.first.startPosition ?? 0.0;
  var entry = 0.0;
  var assumed = false;
  final steps = <OpenPnlStep>[];
  final realised = <OpenPnlRealised>[];
  var done = 0.0;
  if (!flat(pos)) {
    // Held before the first fill read: marked from its price.
    entry = mine.first.px;
    assumed = true;
  }
  for (final f in mine) {
    var start = f.startPosition ?? pos;
    if ((start - pos).abs() > math.max(kOpenPnlFlat, start.abs() * 1e-6)) {
      // A fill the history does not hold moved it: the venue's own
      // position before this fill stands; a new side's entry is marked
      // here.
      if (!sameSide(start, pos)) {
        entry = f.px;
        if (!flat(start)) assumed = true;
      }
    }
    if (flat(start)) start = 0;
    final end = start + (f.isBuy ? f.sz : -f.sz);
    if (flat(start)) {
      entry = f.px;
    } else if (sameSide(start, end) && end.abs() > start.abs()) {
      entry = (start.abs() * entry + (end.abs() - start.abs()) * f.px) /
          end.abs();
    } else {
      // A reduction, a close or a flip: what it closes is realised.
      final closed =
          sameSide(start, end) ? start.abs() - end.abs() : start.abs();
      done += closed * (f.px - entry) * start.sign;
      if (!flat(end) && !sameSide(start, end)) entry = f.px;
    }
    if (_usdFee(f)) done -= f.fee;
    pos = flat(end) ? 0 : end;
    final at = _local(f.time);
    steps.add(OpenPnlStep(at, pos, pos == 0 ? 0 : entry));
    realised.add((at, done));
  }
  final open = szi != null && !flat(szi);
  final last = steps.removeLast();
  if (open) {
    // The last stretch is the position as the venue reports it now (its
    // own entry, unless the fills never reached its open: then the mark
    // the line started from).
    final sideKept = sameSide(last.qty, szi);
    steps.add(OpenPnlStep(last.at, szi,
        assumed && sideKept ? last.entry : (entryPx ?? last.entry)));
  } else {
    // Flat now, whatever the fills read add up to.
    steps.add(OpenPnlStep(last.at, 0, 0));
  }
  return (
    steps: _merged(steps),
    realised: _mergedRealised(realised),
    assumedEntry: assumed,
  );
}

/// Realised steps sharing a moment kept as the last of them.
List<OpenPnlRealised> _mergedRealised(List<OpenPnlRealised> steps) {
  final out = <OpenPnlRealised>[];
  for (final r in steps) {
    if (out.isNotEmpty && out.last.$1 == r.$1) {
      out[out.length - 1] = r;
    } else {
      out.add(r);
    }
  }
  return out;
}

/// The realised P&L of the spot fills on each pair, as the venue books it
/// (each fill's closedPnl, its dollar fee out of it), by the fill's coin;
/// a pair that never realised anything is left out.
Map<String, List<OpenPnlRealised>> hlSpotRealised(Iterable<HlFill> fills) {
  final byCoin = <String, List<HlFill>>{};
  for (final f in fills) {
    if (f.sz > 0 && hlFillIsSpot(f)) (byCoin[f.coin] ??= []).add(f);
  }
  final out = <String, List<OpenPnlRealised>>{};
  for (final MapEntry(key: coin, value: list) in byCoin.entries) {
    list.sort((a, b) => a.time.compareTo(b.time));
    var done = 0.0;
    final steps = <OpenPnlRealised>[];
    for (final f in list) {
      final moved = f.closedPnl + (_usdFee(f) ? -f.fee : 0.0);
      if (moved == 0 || !moved.isFinite) continue;
      done += moved;
      steps.add((_local(f.time), done));
    }
    if (steps.isNotEmpty) out[coin] = _mergedRealised(steps);
  }
  return out;
}

/// The key of a realised-only leg: a spot pair's sells, a prediction's
/// realised P&L.
String openPnlKeyRealised(String id) => 'realised:$id';

/// Every prediction's realised P&L as Polymarket books it ([records], the
/// Data API's positions): a closed one's result, a resolved one waiting
/// to be claimed at its payout, an open one's sells so far; each as one
/// step at its last event (its first entry when the venue gives no last
/// event). A prediction with nothing realised, or no moment at all, is
/// left out (the live figure the line ends on still counts it).
List<OpenPnlLeg> polyRealisedLegs(List<PredictionRecord> records) => [
      for (final r in distinctPredictionRecords(records))
        if ((r.decidedPnlUsd ?? r.realizedPnlUsd) case final v
            when v != 0 && v.isFinite)
          if ((r.lastEventAt ?? r.firstEntryAt)?.toLocal() case final at?)
            OpenPnlLeg(
              key: openPnlKeyRealised('pm:${r.tokenId}'),
              steps: const [],
              prices: const [],
              realised: [(at, v)],
            ),
    ];

/// THE VENUE'S OWN P&L UNDER THE ENGINE ([points], the venue's published
/// observations, oldest first; [legs] the venue's positions charted): one
/// realised-only leg holding, from each observation on, what the venue
/// counted then that the positions charted do not (the venue's P&L less
/// the legs' sum at that moment). So the line is the venue's own figure at
/// every moment it published one, and the positions' detail between them:
/// what no fill or trade carries (funding, rewards, fees booked apart, a
/// position closed before the fills read, the predictions a cut book does
/// not hold, a closed prediction's swings before it was decided) is in
/// the line at the venue's own moments, never piled onto its last point;
/// before the first fill or trade read the line is the venue's own; with
/// nothing charted at all it IS the venue's line. Observations before the
/// first one off zero, and moves under a millionth, are left out. Null
/// when there is nothing to hold.
OpenPnlLeg? openPnlVenueLeg(
    String key, List<PortfolioPnlPoint> points, List<OpenPnlLeg> legs) {
  final steps = <OpenPnlRealised>[];
  for (final p in points) {
    if (!p.pnlUsd.isFinite) continue;
    final at = p.timestamp.toLocal();
    var rest = p.pnlUsd - openPnlValueAt(legs, at);
    if (rest.abs() < 1e-6) rest = 0;
    if (steps.isEmpty ? rest == 0 : (rest - steps.last.$2).abs() < 1e-6) {
      continue;
    }
    steps.add((at, rest));
  }
  if (steps.isEmpty) return null;
  return OpenPnlLeg(
      key: key, steps: const [], prices: const [], realised: steps);
}


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

/// The positions' P&L added, as the moments it moved: (when, the sum of
/// every leg at that moment), oldest first, up to [now]. A leg moves at
/// its open, at each of its stretches, at each of its prices after its
/// first stretch and at each of its realised steps.
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
    if (leg.steps.isNotEmpty) {
      final held = leg.steps.first.at.microsecondsSinceEpoch;
      for (final p in leg.prices) {
        final us = p.$1.microsecondsSinceEpoch;
        if (us > held && us > open && us <= nowUs) events.add((us, k));
      }
    }
    for (final r in leg.realised) {
      final us = r.$1.microsecondsSinceEpoch;
      if (us > open && us <= nowUs) events.add((us, k));
    }
  }
  events.sort((a, b) => a.$1.compareTo(b.$1));
  final n = legs.length;
  final stepAt = List<int>.filled(n, -1);
  final priceAt = List<int>.filled(n, -1);
  final realAt = List<int>.filled(n, -1);
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
      while (realAt[k] + 1 < leg.realised.length &&
          leg.realised[realAt[k] + 1].$1.microsecondsSinceEpoch <= us) {
        realAt[k]++;
      }
      var v = realAt[k] < 0 ? 0.0 : leg.realised[realAt[k]].$2;
      if (stepAt[k] >= 0) {
        final step = leg.steps[stepAt[k]];
        final price = priceAt[k] < 0 ? step.entry : leg.prices[priceAt[k]].$2;
        v += step.pnlAt(price);
      }
      contrib[k] = v;
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
  return openPnlGrid(
      changes: openPnlChanges(legs, end),
      first: openPnlLeadIn(oldest, end),
      now: end);
}

/// Where a line whose oldest position opened at [oldest] starts: a
/// twelfth of its history before (at least an hour; the Balance charts'
/// lead-in).
DateTime openPnlLeadIn(DateTime oldest, DateTime now) {
  var lead = Duration(
      microseconds:
          (now.difference(oldest).inMicroseconds * kBalanceHistoryLeadIn)
              .round());
  if (lead < kBalanceMinLeadIn) lead = kBalanceMinLeadIn;
  return oldest.subtract(lead);
}

/// [changes] ([openPnlChanges]) laid on the grid from [first] to [now],
/// held at 0 before the first change.
BalanceSeries openPnlGrid({
  required List<(DateTime, double)> changes,
  required DateTime first,
  required DateTime now,
}) {
  debugPnlSeriesGrids++;
  return stepGridSeries(
    first: first,
    now: now,
    opening: 0,
    changes: changes.isEmpty ? [(first, 0.0)] : changes,
    current: changes.isEmpty ? 0.0 : changes.last.$2,
  );
}

/// The points [range] draws of a line ([series], laid from its lead-in by
/// [openPnlGrid] out of [changes]) ending [now]: EVERY RANGE
/// SHOWS ITS OWN REACH (founder, 6 November 2026: "the Positions chart
/// ignores the 1W/1M/3M/1Y/ALL buttons": a line younger than a range drew
/// the same whole line on every range longer than it). A range that
/// reaches back past the line's start is laid again from the range's
/// start, held at 0 before the first position (nothing was open or
/// realised then); ALL is the whole line from its lead-in; a range inside
/// the line is its window ([BalanceSeries.spanFor]). The buckets are the
/// range's own ([kuteTrendWindow]'s rule). With [daily] whether a bucket
/// is a day or more, so a moment is written as a day.
({List<double> values, List<DateTime> times, bool daily}) openPnlRangeWindow({
  required BalanceSeries series,
  required List<(DateTime, double)> changes,
  required DateTime now,
  required BalanceRange range,
}) {
  final back = range.duration;
  var grid = series;
  var span = series.spanFor(range);
  if (back != null && series.length > 0) {
    final from = now.toLocal().subtract(back);
    if (series.times.first.isAfter(from)) {
      grid = openPnlGrid(changes: changes, first: from, now: now.toLocal());
      span = grid.extent;
    }
  }
  final n = grid.length;
  if (n == 0) return (values: const [], times: const [], daily: false);
  final start = (grid.extent - span).ceil().clamp(0, n - 1).toInt();
  final stride = grid.strideFor(span);
  final values = <double>[];
  final times = <DateTime>[];
  for (var i = start; i < n; i++) {
    if (i == start || grid.isDrawn(i, stride)) {
      values.add(grid.values[i]);
      times.add(grid.times[i]);
    }
  }
  return (
    values: values,
    times: times,
    daily: grid.strideFor(span) * grid.cellMinutes >= 1440,
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
