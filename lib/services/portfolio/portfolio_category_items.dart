// lib/services/portfolio/portfolio_category_items.dart
//
// What the Statistics donut's drill-down lists once a slice is picked:
// the slice's items (Predictions: events; Investing: coins), largest
// first, and under each the lines its P&L is made of.
//
//   * Predictions: a slice's records grouped by their event (its slug;
//     the market's own slug or condition id when the row named none).
//     Active weighs an event by what its live positions are worth now,
//     Historic by what was put on it, the donut's own figures, so the
//     items of a slice add up to the slice. Each record is a line: an
//     open one with its open P&L, a decided one with its result
//     ([predictionLineResult], the Activity's own rule).
//   * Investing: a slice's holdings (Active) or fills (Historic) grouped
//     by wire coin. Historic lines are the coin's round trips
//     ([tradingRoundTrips]): from flat back to flat, with what closing
//     realised net of fees, so the lines add up to the coin's realised
//     P&L as the tile counts it.

import 'package:kute/helpers/prediction_results.dart'
    show closedPredictionWon, heldPredictionWon, kPredictionDustShares;
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/portfolio_performance.dart';

/// The group a prediction is listed under: its event's slug, else its
/// market's slug, condition id or token.
String predictionEventKey(PredictionRecord r) {
  if (r.eventSlug.isNotEmpty) return r.eventSlug;
  if (r.slug.isNotEmpty) return r.slug;
  if (r.conditionId.isNotEmpty) return r.conditionId;
  return r.tokenId;
}

/// One event of a Predictions slice: its records and the amount that
/// weighs it.
class PredictionEventItem {
  const PredictionEventItem({
    required this.key,
    required this.eventSlug,
    required this.title,
    required this.icon,
    required this.value,
    required this.records,
  });

  /// [predictionEventKey] of its records.
  final String key;

  /// Empty when the rows named no event.
  final String eventSlug;

  /// The first record's market question (the event's own title is read
  /// by its slug where there is one) and its image.
  final String title;
  final String icon;
  final double value;

  /// Largest [amount] first.
  final List<PredictionRecord> records;
}

/// [records] grouped by event, each weighed by the sum of [amount] over
/// its records (an amount that is not a finite positive number counts
/// nothing); events worth nothing are left out. Largest first, ties by
/// title.
List<PredictionEventItem> predictionEventItems(
    Iterable<PredictionRecord> records,
    double Function(PredictionRecord r) amount) {
  final groups = <String, List<PredictionRecord>>{};
  for (final r in records) {
    (groups[predictionEventKey(r)] ??= []).add(r);
  }
  double weight(PredictionRecord r) {
    final v = amount(r);
    return v.isFinite && v > 0 ? v : 0;
  }

  final items = <PredictionEventItem>[];
  for (final e in groups.entries) {
    final value = e.value.fold<double>(0, (sum, r) => sum + weight(r));
    if (value <= 0) continue;
    final sorted = [...e.value]..sort((a, b) => weight(b).compareTo(weight(a)));
    final first = sorted.first;
    items.add(PredictionEventItem(
      key: e.key,
      eventSlug: first.eventSlug,
      title: first.title,
      icon: sorted
          .map((r) => r.icon)
          .firstWhere((i) => i.isNotEmpty, orElse: () => ''),
      value: value,
      records: List.unmodifiable(sorted),
    ));
  }
  items.sort((a, b) {
    final byValue = b.value.compareTo(a.value);
    return byValue != 0 ? byValue : a.title.compareTo(b.title);
  });
  return items;
}

/// How a prediction stands, as its drill-down line says it.
enum PredictionLineResult { open, won, lost, sold }

/// [r]'s result, by the same rule as the Predictions activity's result
/// rows and the Portfolio's resolved positions (prediction_results.dart):
/// a position still held is won or lost once its market resolved
/// (redeemable, priced 1 or 0) and open until then; a closed one is won or
/// lost when it was held to the settled result, and sold when it was left
/// before (sold mid-market, or enough of it to move what it paid). Dust
/// left by a sale is sold, never a result.
PredictionLineResult predictionLineResult(PredictionRecord r) {
  final bool? won;
  if (r.open) {
    won = heldPredictionWon(
        redeemable: r.redeemable, curPrice: r.currentPrice);
    if (won == null) return PredictionLineResult.open;
    if (r.size < kPredictionDustShares) return PredictionLineResult.sold;
  } else {
    won = closedPredictionWon(
      totalSize: r.totalSize,
      avgPrice: r.avgPrice,
      realizedPnl: r.realizedPnlUsd,
      curPrice: r.currentPrice,
    );
    if (won == null) return PredictionLineResult.sold;
  }
  return won ? PredictionLineResult.won : PredictionLineResult.lost;
}

/// What a decided prediction ended at, or what an open one has realised
/// so far: the realised P&L the Historic tile counts.
double predictionLineRealizedUsd(PredictionRecord r) =>
    r.decidedPnlUsd ?? r.realizedPnlUsd;

/// One coin of an Investing slice: the amount that weighs it.
class TradingCoinItem<T> {
  const TradingCoinItem(
      {required this.coin, required this.value, required this.entries});

  /// The wire coin.
  final String coin;
  final double value;

  /// What it is made of: its holdings (Active) or its fills (Historic).
  final List<T> entries;
}

/// [entries] grouped by [coinOf], each weighed by the sum of [amount]
/// (an amount that is not a finite positive number counts nothing);
/// coins worth nothing are left out. Largest first, ties by coin.
List<TradingCoinItem<T>> tradingCoinItems<T>(Iterable<T> entries,
    {required String Function(T e) coinOf,
    required double Function(T e) amount}) {
  final groups = <String, List<T>>{};
  final values = <String, double>{};
  for (final e in entries) {
    final coin = coinOf(e);
    (groups[coin] ??= []).add(e);
    final v = amount(e);
    if (v.isFinite && v > 0) values[coin] = (values[coin] ?? 0) + v;
  }
  final items = [
    for (final e in groups.entries)
      if ((values[e.key] ?? 0) > 0)
        TradingCoinItem<T>(
            coin: e.key,
            value: values[e.key]!,
            entries: List.unmodifiable(e.value)),
  ]..sort((a, b) {
      final byValue = b.value.compareTo(a.value);
      return byValue != 0 ? byValue : a.coin.compareTo(b.coin);
    });
  return items;
}

/// One round trip in a coin: from flat to flat again (or still open).
class TradingRoundTrip {
  const TradingRoundTrip({
    required this.long,
    required this.openedAt,
    required this.closedAt,
    required this.realizedUsd,
    required this.volumeUsd,
    required this.fills,
  });

  /// The side it opened on (a spot holding is long).
  final bool long;

  /// Epoch ms of its first fill, and of the fill that brought it back to
  /// flat; null while it is still open.
  final int openedAt;
  final int? closedAt;

  /// What closing realised, net of every fill's exchange fee.
  final double realizedUsd;

  /// Notional traded (price × size of every fill).
  final double volumeUsd;
  final int fills;

  bool get open => closedAt == null;
}

/// The round trips of one coin's [fills] (any order), newest first. Each
/// fill's position before it (`startPosition`) says where a trip starts
/// and where it is back to flat; a reversal closes the trip and the next
/// fill carries on a new one on the other side. A fill that does not say
/// its position before is a trip of its own. Every fill's realised P&L
/// and fee are in exactly one trip, so the trips add up to the coin's
/// realised P&L.
List<TradingRoundTrip> tradingRoundTrips(Iterable<HlFill> fills) {
  final ordered = fills.toList()
    ..sort((a, b) {
      final byTime = a.time.compareTo(b.time);
      return byTime != 0 ? byTime : a.oid.compareTo(b.oid);
    });
  final trips = <TradingRoundTrip>[];
  bool? long;
  int openedAt = 0;
  var realized = 0.0;
  var volume = 0.0;
  var count = 0;

  void close(int? at) {
    if (count == 0) return;
    trips.add(TradingRoundTrip(
        long: long ?? true,
        openedAt: openedAt,
        closedAt: at,
        realizedUsd: realized,
        volumeUsd: volume,
        fills: count));
    long = null;
    realized = 0;
    volume = 0;
    count = 0;
  }

  for (final f in ordered) {
    final before = f.startPosition;
    final delta = f.isBuy ? f.sz : -f.sz;
    if (count == 0) {
      openedAt = f.time;
      long = before == null || before == 0 ? f.isBuy : before > 0;
    }
    count++;
    realized += f.closedPnl - f.fee;
    volume += f.px * f.sz;
    if (before == null || !before.isFinite) {
      close(f.time);
      continue;
    }
    final after = before + delta;
    final tolerance = 1e-9 + 1e-6 * (before.abs() > f.sz ? before.abs() : f.sz);
    if (after.abs() <= tolerance ||
        (before != 0 && before.sign != after.sign)) {
      close(f.time);
    }
  }
  close(null);
  return trips.reversed.toList(growable: false);
}
