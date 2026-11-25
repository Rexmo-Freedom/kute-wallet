// lib/services/polymarket/confirmed_sales.dart
//
// A Predictions sale the venue filled, between the fill and the Data API
// catching up with it. Pure rules, no I/O (the binding lives in
// `PolymarketTradingNotifier`; the P&L side in
// `portfolioPerformanceDisplayProvider`).
//
// Founder, 2026-11-01: bet $4.24 on No (4.99 shares at ~85¢), sold it
// ("Sold · No +$4.14" in Activity), and the Portfolio still listed the
// prediction as open, with a chance bar and more profit than he made,
// until it later went away. The Data API lags the chain by seconds to
// minutes and its reads do not move forward together (one read leaves
// the sold row out, the next still has it at the pre-sale size). The old
// suppression ended on the first read without the row, and was never set
// when the sale had been confirmed by the row disappearing, so the next
// stale read put the pre-sale row back: listed as open, valued at its
// live price, its open P&L counted next to (or instead of) what the sale
// realised.
//
// The rules here:
//
//   * the POSITION: from the fill until [kConfirmedSaleTtl], a row of the
//     sold token is the pre-sale row while it holds more than what the
//     sale left ([PolymarketConfirmedSale.remainingShares]) and no more
//     than what was held before it. Such a row is shrunk to what is left,
//     or dropped when nothing (or only dust) is left. A row larger than
//     the pre-sale holding has new shares in it and stands.
//   * the P&L: the same stale row in the Data API's book of positions is
//     rewritten the same way, and the shares sold leave the open P&L and
//     enter the realised P&L at the venue's own proceeds, never both. A
//     sale the book does not show at all is added as a closed position.
//     Without the venue's proceeds the shares sold count in neither.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;
import 'package:kute/helpers/prediction_results.dart'
    show kPredictionDustShares;
import 'package:kute/models/portfolio_performance.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Position;

/// How long a filled sale outranks the Data API's rows for its token. The
/// sale is on chain when it is recorded (the sell sheet waits for that),
/// so this only bounds how long a lagging read is distrusted.
const Duration kConfirmedSaleTtl = Duration(minutes: 10);

/// Shares within this count as the same size (the API rounds sizes).
const double _kSharesTolerance = 0.01;

@immutable
class PolymarketConfirmedSale {
  const PolymarketConfirmedSale({
    required this.wallet,
    required this.tokenId,
    required this.soldShares,
    required this.heldShares,
    required this.at,
    this.proceedsUsd,
    this.costUsd,
    this.conditionId = '',
    this.title = '',
    this.outcome = '',
    this.slug = '',
    this.eventSlug = '',
    this.icon = '',
  });

  /// The deposit wallet (lowercase) the sale was made from.
  final String wallet;

  /// The outcome token sold (`Position.asset`).
  final String tokenId;

  /// Shares the venue reports sold.
  final double soldShares;

  /// Shares held right before the sale.
  final double heldShares;

  /// USDC the venue reports received for [soldShares]; null when it gave
  /// no figure.
  final double? proceedsUsd;

  /// What the shares sold cost, from the position's entry cost (the venue's
  /// basis); null when unknown.
  final double? costUsd;

  final DateTime at;

  /// The market and the side, as the position named them (empty when
  /// unknown): what a closed record added for the sale carries.
  final String conditionId;
  final String title;
  final String outcome;
  final String slug;
  final String eventSlug;
  final String icon;

  /// What the sale left.
  double get remainingShares => math.max(0.0, heldShares - soldShares);

  /// Nothing worth keeping is left: the position is closed.
  bool get closesPosition => remainingShares < kPredictionDustShares;

  /// The realised P&L of the sale from the venue's figures; null without
  /// them.
  double? get realizedPnlUsd {
    final proceeds = proceedsUsd;
    final cost = costUsd;
    if (proceeds == null || cost == null) return null;
    if (!proceeds.isFinite || !cost.isFinite) return null;
    return proceeds - cost;
  }

  /// [size] is a row from before this sale: more than it left, no more
  /// than was held.
  bool isPreSaleSize(double size) =>
      size > remainingShares + _kSharesTolerance &&
      size <= heldShares + _kSharesTolerance;

  @override
  bool operator ==(Object other) =>
      other is PolymarketConfirmedSale &&
      other.wallet == wallet &&
      other.tokenId == tokenId &&
      other.soldShares == soldShares &&
      other.heldShares == heldShares &&
      other.proceedsUsd == proceedsUsd &&
      other.costUsd == costUsd &&
      other.at == at;

  @override
  int get hashCode => Object.hash(
      wallet, tokenId, soldShares, heldShares, proceedsUsd, costUsd, at);

  @override
  String toString() => 'PolymarketConfirmedSale($tokenId, '
      '$soldShares of $heldShares sh, \$$proceedsUsd)';
}

/// A sale of [soldShares] of [tokenId] out of [heldShares] held. A sale of
/// at least 95% of the holding sells it all (Sell Max rounds 10 shares
/// down to ~9.96; the rest is dust). Null when the sale says nothing
/// usable.
PolymarketConfirmedSale? newConfirmedSale({
  required String wallet,
  required String tokenId,
  required double soldShares,
  required double heldShares,
  required DateTime now,
  double? proceedsUsd,
  double? costUsd,
  String conditionId = '',
  String title = '',
  String outcome = '',
  String slug = '',
  String eventSlug = '',
  String icon = '',
}) {
  if (wallet.isEmpty ||
      tokenId.isEmpty ||
      !soldShares.isFinite ||
      soldShares <= 0) {
    return null;
  }
  var held = heldShares.isFinite && heldShares > 0 ? heldShares : soldShares;
  if (held < soldShares) held = soldShares;
  // Selling (nearly) all: nothing is left, the dust included.
  final sold = soldShares >= held * 0.95 ? held : soldShares;
  return PolymarketConfirmedSale(
    wallet: wallet.toLowerCase(),
    tokenId: tokenId,
    soldShares: sold,
    heldShares: held,
    at: now,
    proceedsUsd: proceedsUsd != null && proceedsUsd.isFinite && proceedsUsd >= 0
        ? proceedsUsd
        : null,
    costUsd: costUsd != null && costUsd.isFinite && costUsd >= 0
        ? costUsd
        : null,
    conditionId: conditionId,
    title: title,
    outcome: outcome,
    slug: slug,
    eventSlug: eventSlug,
    icon: icon,
  );
}

/// [sales] without the expired ones and the ones of another wallet.
List<PolymarketConfirmedSale> liveConfirmedSales(
  Iterable<PolymarketConfirmedSale> sales,
  String? wallet,
  DateTime now,
) {
  final w = wallet?.toLowerCase();
  if (w == null || w.isEmpty) return const [];
  return List.unmodifiable([
    for (final s in sales)
      if (s.wallet == w && now.difference(s.at) <= kConfirmedSaleTtl) s,
  ]);
}

/// The latest live sale of each token among [sales].
Map<String, PolymarketConfirmedSale> _latestByToken(
    Iterable<PolymarketConfirmedSale> sales) {
  final out = <String, PolymarketConfirmedSale>{};
  for (final s in sales) {
    final prev = out[s.tokenId];
    if (prev == null || s.at.isAfter(prev.at)) out[s.tokenId] = s;
  }
  return out;
}

/// [positions] (a Data API read, or the state's list) against the filled
/// [sales] of the same wallet: a pre-sale row of a sold token is shrunk to
/// what the sale left, or dropped when the sale closed the position. Rows
/// of other tokens, and rows the read has already brought in line, are
/// left as they are.
List<Position> applyConfirmedSales(
  List<Position> positions,
  List<PolymarketConfirmedSale> sales,
) {
  if (sales.isEmpty || positions.isEmpty) return positions;
  final byToken = _latestByToken(sales);
  final out = <Position>[];
  var changed = false;
  for (final p in positions) {
    final sale = byToken[p.asset];
    if (sale == null || !p.size.isFinite || !sale.isPreSaleSize(p.size)) {
      out.add(p);
      continue;
    }
    changed = true;
    if (sale.closesPosition) continue;
    out.add(positionWithSize(p, sale.remainingShares));
  }
  return changed ? out : positions;
}

/// [p] with [newSize] shares. The package Position has no copyWith; the
/// value fields scale with the size so the average price, the price and the
/// percentage P&L stay as they were.
Position positionWithSize(Position p, double newSize) {
  final fraction = p.size > 0 ? newSize / p.size : 0.0;
  return Position(
    proxyWallet: p.proxyWallet,
    asset: p.asset,
    conditionId: p.conditionId,
    size: newSize,
    avgPrice: p.avgPrice,
    initialValue: p.initialValue * fraction,
    currentValue: p.currentValue * fraction,
    cashPnl: p.cashPnl * fraction,
    percentPnl: p.percentPnl,
    totalBought: p.totalBought,
    realizedPnl: p.realizedPnl,
    percentRealizedPnl: p.percentRealizedPnl,
    curPrice: p.curPrice,
    redeemable: p.redeemable,
    mergeable: p.mergeable,
    title: p.title,
    slug: p.slug,
    icon: p.icon,
    eventSlug: p.eventSlug,
    outcome: p.outcome,
    outcomeIndex: p.outcomeIndex,
    oppositeOutcome: p.oppositeOutcome,
    oppositeAsset: p.oppositeAsset,
    endDate: p.endDate,
    negativeRisk: p.negativeRisk,
  );
}

/// The Data API's [book] of positions against the filled [sales] (already
/// those of the book's wallet): see the file comment. A book with nothing
/// to change is returned as it is.
PredictionsBook bookWithConfirmedSales(
  PredictionsBook book,
  List<PolymarketConfirmedSale> sales,
) {
  if (sales.isEmpty) return book;
  final byToken = _latestByToken(sales);
  final seen = <String>{};
  final records = <PredictionRecord>[];
  var changed = false;
  for (final r in book.records) {
    final sale = byToken[r.tokenId];
    if (sale != null) seen.add(r.tokenId);
    if (sale == null ||
        !r.open ||
        r.redeemable ||
        !r.size.isFinite ||
        !sale.isPreSaleSize(r.size)) {
      records.add(r);
      continue;
    }
    changed = true;
    records.add(_recordAfterSale(r, sale));
  }
  // A sale the book has no row of (the buy and the sale both newer than
  // the read): its realised P&L, when the venue's figures give it.
  for (final sale in byToken.values) {
    if (seen.contains(sale.tokenId)) continue;
    final realized = sale.realizedPnlUsd;
    if (realized == null) continue;
    changed = true;
    final cost = sale.costUsd!;
    records.add(PredictionRecord(
      tokenId: sale.tokenId,
      conditionId: sale.conditionId.toLowerCase(),
      open: false,
      redeemable: false,
      size: 0,
      totalSize: sale.soldShares,
      avgPrice: sale.soldShares > 0 ? cost / sale.soldShares : 0,
      entryCostUsd: 0,
      currentPrice: 0,
      realizedPnlUsd: realized,
      unrealizedPnlUsd: 0,
      lastEventAt: sale.at.toUtc(),
      title: sale.title,
      slug: sale.slug,
      eventSlug: sale.eventSlug,
      outcome: sale.outcome,
      icon: sale.icon,
    ));
  }
  if (!changed) return book;
  return PredictionsBook(
    records: List.unmodifiable(records),
    complete: book.complete,
    coversFrom: book.coversFrom,
  );
}

/// The pre-sale record [r] after [sale]: the shares sold leave it at their
/// share of its entry cost and realise the venue's proceeds; what is left
/// stays open (closed when nothing, or only dust, is left).
PredictionRecord _recordAfterSale(PredictionRecord r, PolymarketConfirmedSale sale) {
  final remaining = sale.remainingShares;
  final soldHere = r.size - remaining;
  final keep = r.size > 0 ? remaining / r.size : 0.0;
  final soldCost = r.entryCostUsd * (1 - keep);
  final proceeds = sale.proceedsUsd;
  // The proceeds of the shares this row still shows as held (all of them
  // when the row is from before the sale).
  final realizedAdd = proceeds == null || sale.soldShares <= 0
      ? 0.0
      : proceeds * (soldHere / sale.soldShares).clamp(0.0, 1.0) - soldCost;
  final open = remaining >= kPredictionDustShares;
  return PredictionRecord(
    tokenId: r.tokenId,
    conditionId: r.conditionId,
    open: open,
    redeemable: false,
    size: open ? remaining : 0,
    totalSize: r.totalSize,
    avgPrice: r.avgPrice,
    entryCostUsd: open ? r.entryCostUsd * keep : 0,
    currentPrice: r.currentPrice,
    realizedPnlUsd: r.realizedPnlUsd + realizedAdd,
    unrealizedPnlUsd: open ? r.unrealizedPnlUsd * keep : 0,
    firstEntryAt: r.firstEntryAt,
    // Its own time, not the sale's: a closed row the venue already lists
    // for the same sale is newer and stands in its place
    // ([distinctPredictionRecords]), with the venue's own figure.
    lastEventAt: r.lastEventAt,
    title: r.title,
    slug: r.slug,
    eventSlug: r.eventSlug,
    outcome: r.outcome,
    icon: r.icon,
  );
}
