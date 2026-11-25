import 'dart:ui' show Color;

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';

/// What a fill did to the position, in [l10n]'s language (English when
/// none is given).
String hlFillAction(HlFill fill, [AppLocalizations? l10n]) {
  final l = l10n ?? l10nForLanguage('en');
  if (fill.liquidated) return l.hlFillLiquidated;
  if (fill.coin.startsWith('@') || fill.coin.contains('/')) {
    return fill.isBuy ? l.hlFillBoughtAsset : l.hlFillSoldAsset;
  }
  final before = fill.startPosition;
  if (before != null &&
      before.isFinite &&
      fill.sz > 0 &&
      (fill.side == 'B' || fill.side == 'A')) {
    final after = before + (fill.isBuy ? fill.sz : -fill.sz);
    if (before == 0) return l.hlFillOpened;
    if (after.abs() < 1e-10) return l.hlFillClosed;
    if (before.sign != after.sign) return l.hlFillReversed;
    return after.abs() > before.abs() ? l.hlFillAdded : l.hlFillReduced;
  }
  final direction = fill.dir.toLowerCase();
  if (direction.contains('close')) return l.hlFillReduced;
  if (direction.contains('open')) return l.hlFillAdded;
  return l.hlFillTradeFilled;
}

/// What a perpetual fill did to the position, in the position's own
/// words: a short that buys is closing, not "buying". [long] is the side
/// of the position concerned: the one it opened, added to or flipped
/// into, or the one it reduced or closed. Null for a spot trade, where
/// bought and sold are the plain truth.
enum HlFillKind {
  opened,
  added,
  reduced,
  closed,
  flipped,
  liquidated,
  bought,
  sold,
}

typedef HlFillEffect = ({HlFillKind kind, bool? long});

HlFillEffect hlFillEffect(HlFill fill) {
  if (fill.coin.startsWith('@') || fill.coin.contains('/')) {
    return (kind: fill.isBuy ? HlFillKind.bought : HlFillKind.sold, long: null);
  }
  final before = fill.startPosition;
  final sized = before != null &&
      before.isFinite &&
      fill.sz > 0 &&
      (fill.side == 'B' || fill.side == 'A');
  if (fill.liquidated) {
    final long = sized && before != 0 ? before > 0 : _dirLong(fill.dir);
    return (kind: HlFillKind.liquidated, long: long);
  }
  if (sized) {
    final after = before + (fill.isBuy ? fill.sz : -fill.sz);
    if (before == 0) return (kind: HlFillKind.opened, long: after > 0);
    if (after.abs() < 1e-10) return (kind: HlFillKind.closed, long: before > 0);
    if (before.sign != after.sign) {
      return (kind: HlFillKind.flipped, long: after > 0);
    }
    return after.abs() > before.abs()
        ? (kind: HlFillKind.added, long: after > 0)
        : (kind: HlFillKind.reduced, long: before > 0);
  }
  final d = fill.dir.trim().toLowerCase();
  if (d.contains('>')) {
    return (kind: HlFillKind.flipped, long: _dirLong(d.split('>').last));
  }
  if (d.startsWith('open')) return (kind: HlFillKind.opened, long: _dirLong(d));
  if (d.startsWith('close')) {
    return (kind: HlFillKind.closed, long: _dirLong(d));
  }
  // Nothing says what it did to a position: a buy reads as going long,
  // a sell as going short, which is what they do to a flat account.
  return (kind: HlFillKind.opened, long: fill.isBuy);
}

/// The side a direction word names; null when it names none.
bool? _dirLong(String dir) {
  final d = dir.toLowerCase();
  if (d.contains('long')) return true;
  if (d.contains('short')) return false;
  return null;
}

/// The colour a fill reads in: [up] for going long, [down] for going
/// short or being liquidated, [neutral] for closing or reducing (a close
/// is neither bullish nor bearish, whichever side it bought or sold on).
/// A spot buy is [up], a spot sale [down].
Color hlFillTone(HlFill fill,
    {required Color up, required Color down, required Color neutral}) {
  final e = hlFillEffect(fill);
  return switch (e.kind) {
    HlFillKind.bought => up,
    HlFillKind.sold => down,
    HlFillKind.liquidated => down,
    HlFillKind.closed || HlFillKind.reduced => neutral,
    HlFillKind.opened ||
    HlFillKind.added ||
    HlFillKind.flipped =>
      (e.long ?? fill.isBuy) ? up : down,
  };
}

/// [hlFillEffect] as a headline with the size: "Closed short 0.008 OAI",
/// "Opened long 0.5 ETH", "Bought 12 HYPE".
String hlFillHeadline(HlFill fill, String size, AppLocalizations l) {
  final e = hlFillEffect(fill);
  final long = e.long ?? fill.isBuy;
  return switch (e.kind) {
    HlFillKind.bought => l.hlChartBoughtSize(size),
    HlFillKind.sold => l.hlChartSoldSize(size),
    HlFillKind.liquidated => l.hlChartLiquidatedSize(size),
    HlFillKind.opened =>
      long ? l.hlChartOpenedLong(size) : l.hlChartOpenedShort(size),
    HlFillKind.added =>
      long ? l.hlChartAddedLong(size) : l.hlChartAddedShort(size),
    HlFillKind.reduced =>
      long ? l.hlChartReducedLong(size) : l.hlChartReducedShort(size),
    HlFillKind.closed =>
      long ? l.hlChartClosedLong(size) : l.hlChartClosedShort(size),
    HlFillKind.flipped =>
      long ? l.hlChartFlippedLong(size) : l.hlChartFlippedShort(size),
  };
}

/// [hlFillHeadline] without the size: the action alone ("Closed long",
/// "Opened short", "Added to short", "Liquidated", "Bought"), in the same
/// translated words. A locale that puts the size first or after a colon
/// ("{size} gekocht", "Vétel: {size}") reads "Gekocht", "Vétel".
String hlFillActionTitle(HlFill fill, AppLocalizations l) {
  var s = hlFillHeadline(fill, '', l).replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.endsWith(':')) s = s.substring(0, s.length - 1).trimRight();
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

/// An order's side in the position's words. A perpetual order that only
/// closes ([reduceOnly]: a take profit, a stop, a close) reads "Close
/// short" for a buy and "Close long" for a sell; one that opens reads
/// "Long" or "Short". A spot order, or one whose purpose is unknown, says
/// Buy or Sell. [coin] is the wire coin ('@142' is spot).
String hlOrderSideLabel(AppLocalizations l,
    {required String coin, required bool isBuy, bool? reduceOnly}) {
  final spot = coin.startsWith('@') || coin.contains('/');
  if (spot || reduceOnly == null) return isBuy ? l.buy : l.sell;
  if (reduceOnly) return l.slipCtaClose(isBuy ? 'short' : 'long');
  return isBuy ? l.longLabel : l.shortLabel;
}

/// One row per fill, never per order: a single order can execute many times.
List<HlFill> mergeHlFills(Iterable<HlFill> history, Iterable<HlFill> live) {
  String key(HlFill f) => f.tradeId != null
      ? '${f.coin}:${f.tradeId}'
      : '${f.coin}:${f.hash}:${f.oid}:${f.time}:${f.side}:${f.sz}:${f.px}:${f.startPosition}';
  final byId = {for (final f in history) key(f): f};
  for (final f in live) {
    byId[key(f)] = f;
  }
  return byId.values.toList()..sort((a, b) => b.time.compareTo(a.time));
}

/// The venue's `userFills` read returns the most recent fills only, this
/// many at most; a list that long may have been cut.
const int kHyperliquidUserFillsCap = 2000;

/// An account's fills, newest or oldest first, as the Statistics tab
/// reads them. [complete] is false when the list was cut at a read cap;
/// [coversFrom] is then the oldest fill it still holds, and statistics
/// reaching back before it are unknown. Mirrors `PredictionsBook`.
class TradingBook {
  const TradingBook({required this.fills, this.complete = true});
  final List<HlFill> fills;
  final bool complete;

  /// The oldest fill held, as a moment; null with no fills.
  DateTime? get coversFrom {
    if (fills.isEmpty) return null;
    var oldest = fills.first.time;
    for (final f in fills) {
      if (f.time < oldest) oldest = f.time;
    }
    return DateTime.fromMillisecondsSinceEpoch(oldest, isUtc: true);
  }

  /// The fills since [since] (all of them when null): how many, their
  /// notional and what closing realised net of exchange fees. Null when
  /// the list does not reach back that far.
  TradingRangeStats? statsSince(DateTime? since) {
    if (!complete) {
      final from = coversFrom;
      if (since == null || from == null || since.isBefore(from)) return null;
    }
    final sinceMs = since?.toUtc().millisecondsSinceEpoch;
    bool inRange(int time) => sinceMs == null || time >= sinceMs;
    var count = 0;
    var volume = 0.0;
    var realized = 0.0;
    for (final f in fills) {
      if (!inRange(f.time)) continue;
      count++;
      volume += f.px * f.sz;
      realized += f.closedPnl - f.fee;
    }
    return TradingRangeStats(
        count: count, volumeUsd: volume, realizedUsd: realized);
  }
}

class TradingRangeStats {
  const TradingRangeStats(
      {required this.count,
      required this.volumeUsd,
      required this.realizedUsd});

  /// Fills, as the Activity tab counts them: one per execution.
  final int count;

  /// Notional traded (price × size of every fill).
  final double volumeUsd;

  /// What closing realised, net of exchange fees. Funding is not in it.
  final double realizedUsd;
}
