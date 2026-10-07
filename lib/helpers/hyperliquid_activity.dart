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
