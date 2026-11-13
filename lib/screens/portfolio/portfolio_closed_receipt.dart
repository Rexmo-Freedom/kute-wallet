// lib/screens/portfolio/portfolio_closed_receipt.dart
//
// WHAT A "CLOSED POSITIONS" ROW OPENS (founder, 8 November 2026: "closed
// positions are not clickable in portfolio"; the P&L tab's list,
// portfolio_pnl_section.dart). The row already says what the position made
// or lost, the venue's own figure; the destination is the receipt the
// Activity rows open for that close, and the receipt writes the row's
// figure as its result (`resultUsd`), so the two read the same to the cent.
// Nothing is estimated here: every figure is the venue's, or a sum of the
// venue's.
//
// An Investing row always has one: its order's closing fills, added into
// one fill when there are several ([foldClosedFills]: a market order fills
// at several prices, and any one of them would not be what the row says).
//
// A prediction ([resolveClosedPrediction]) is one row per outcome token,
// and takes the first of:
//
//   1. its result read from the resolved market ([predictionResults]): a
//      loss (never claimed, so never in the history) or a win not claimed
//      yet;
//   2. its claim in the venue's history, unless this token lost (the claim
//      on the market is then the other side's): the Won receipt;
//   3. its sales in the venue's history: the Sold receipt, several added
//      into one;
//   4. older than those reads (each is the venue's newest 100 rows): the
//      result sheet built from the position's own record, only when what
//      it says (the payout less the cost) is the row's figure to the cent;
//   5. the market's page (a sale older than the history, shares merged, a
//      win partly sold before it and older than the history): there is no
//      receipt to show, and no figure to disagree. The row presses only
//      once the event is known; no event slug at all: no destination, and
//      no press state.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/prediction_results.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlFill;
import 'package:kute/models/polymarket_model.dart' show Activity;
import 'package:kute/models/portfolio_performance.dart' show PredictionRecord;
import 'package:kute/models/transactions_model.dart' show PolymarketTransaction;
import 'package:kute/screens/polymarket/market_detail_sheet.dart'
    show MarketDetailSheet;
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyPositionEventProvider;
import 'package:kute/screens/shared/hyperliquid_fill_activity.dart'
    show showClosedFillReceipt;
import 'package:kute/screens/shared/transactions_builder.dart'
    show showClosedPredictionReceipt, showPredictionResultDetails;

/// What a closed row opens (see the file header).
@immutable
sealed class PortfolioClosedDestination {
  const PortfolioClosedDestination();
}

/// The venue record's receipt: a claim, a sale, or the sales added.
class PortfolioClosedVenueReceipt extends PortfolioClosedDestination {
  const PortfolioClosedVenueReceipt(this.tx);
  final PolymarketTransaction tx;
}

/// The result sheet of a prediction held to its resolved market.
class PortfolioClosedResultReceipt extends PortfolioClosedDestination {
  const PortfolioClosedResultReceipt(this.result);
  final PredictionResult result;
}

/// An Investing fill's receipt: the order's closing fills added.
class PortfolioClosedFillReceipt extends PortfolioClosedDestination {
  const PortfolioClosedFillReceipt(this.fill);
  final HlFill fill;
}

/// No receipt: the market's page, once its event is known.
class PortfolioClosedMarketPage extends PortfolioClosedDestination {
  const PortfolioClosedMarketPage(this.eventSlug);
  final String eventSlug;
}

bool _sameCents(double a, double b) => (a * 100).round() == (b * 100).round();

/// Where a prediction's closed row goes, or null when nowhere (see the file
/// header). [resultUsd] is the row's figure; [history] the venue's records
/// of the account; [results] its [predictionResults].
PortfolioClosedDestination? resolveClosedPrediction(
  PredictionRecord record, {
  required double resultUsd,
  required Iterable<PolymarketTransaction> history,
  required Iterable<PredictionResult> results,
}) {
  final token = record.tokenId;
  final market = record.conditionId.toLowerCase();
  if (token.isNotEmpty) {
    for (final r in results) {
      if (r.activity.asset == token) return PortfolioClosedResultReceipt(r);
    }
  }
  final won = record.open
      ? heldPredictionWon(
          redeemable: record.redeemable, curPrice: record.currentPrice)
      : closedPredictionWon(
          totalSize: record.totalSize,
          avgPrice: record.avgPrice,
          realizedPnl: record.realizedPnlUsd,
          curPrice: record.currentPrice);
  bool onMarket(Activity a) =>
      market.isNotEmpty && a.conditionId.toLowerCase() == market;
  final side = record.outcome.trim().toLowerCase();
  // A record names its token, or failing that its market and outcome.
  bool ours(Activity a) {
    final asset = a.asset ?? '';
    if (asset.isNotEmpty && token.isNotEmpty) return asset == token;
    return onMarket(a) && (a.outcome ?? '').trim().toLowerCase() == side;
  }

  final claims = <PolymarketTransaction>[];
  final sales = <PolymarketTransaction>[];
  for (final tx in history) {
    final a = tx.activity;
    final type = a.type.toUpperCase();
    if (type == 'REDEEM') {
      // A redeem may name the winning side alone, or nothing.
      final asset = a.asset ?? '';
      if (a.usdcSize > 0.001 &&
          onMarket(a) &&
          (asset.isEmpty || token.isEmpty || asset == token)) {
        claims.add(tx);
      }
    } else if (type == 'TRADE' &&
        (a.side ?? '').toUpperCase() == 'SELL' &&
        ours(a)) {
      sales.add(tx);
    }
  }
  if (claims.isNotEmpty && won != false) {
    return PortfolioClosedVenueReceipt(_foldRecords(claims, token));
  }
  if (sales.isNotEmpty) {
    return PortfolioClosedVenueReceipt(_foldRecords(sales, token));
  }
  if (won != null) {
    final shares = record.open ? record.size : record.totalSize;
    final stake = record.open ? record.entryCostUsd : record.stakeUsd;
    final payout = won ? shares : 0.0;
    if (shares > 0 && _sameCents(payout - stake, resultUsd)) {
      final at = record.lastEventAt ?? record.firstEntryAt;
      if (at != null) {
        return PortfolioClosedResultReceipt(PredictionResult(
          activity: Activity(
            proxyWallet: '',
            timestamp: at.millisecondsSinceEpoch ~/ 1000,
            conditionId: record.conditionId,
            type: 'REDEEM',
            size: shares,
            usdcSize: payout,
            transactionHash: '',
            asset: token,
            title: record.title,
            slug: record.slug,
            icon: record.icon,
            eventSlug: record.eventSlug,
            outcome: record.outcome,
          ),
          won: won,
          stakeUsd: stake,
          payoutUsd: payout,
        ));
      }
    }
  }
  final slug = record.eventSlug.trim();
  return slug.isEmpty ? null : PortfolioClosedMarketPage(slug);
}

/// [rows] (one kind, a position's sales or claims) as one record: the shares
/// and the dollars added, the average price, dated at the last. Its
/// transaction hash is the one they share, else none (no explorer link says
/// it was all one transaction). One row stands as it is.
PolymarketTransaction _foldRecords(
    List<PolymarketTransaction> rows, String token) {
  if (rows.length == 1) return rows.single;
  final byTime = [...rows]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final last = byTime.last.activity;
  var size = 0.0;
  var usd = 0.0;
  for (final t in byTime) {
    size += t.activity.size;
    usd += t.activity.usdcSize;
  }
  final oneHash = byTime.every((t) => t.txHash == last.transactionHash);
  return PolymarketTransaction(
    id: 'closed_${token}_${last.timestamp}',
    timestamp: byTime.last.timestamp,
    activity: Activity(
      proxyWallet: last.proxyWallet,
      timestamp: last.timestamp,
      conditionId: last.conditionId,
      type: last.type,
      size: size,
      usdcSize: usd,
      transactionHash: oneHash ? last.transactionHash : '',
      price: size > 0 && last.price != null ? usd / size : null,
      asset: last.asset,
      side: last.side,
      outcomeIndex: last.outcomeIndex,
      title: last.title,
      slug: last.slug,
      icon: last.icon,
      eventSlug: last.eventSlug,
      outcome: last.outcome,
    ),
  );
}

/// An order's closing [fills] (not empty) as one fill: the size, the fee and
/// the realised P&L added, the average price, the last fill's time and
/// direction. No fill id (it is several). One fill stands as it is. An
/// order's fills pay their fee in one token; the fee counted is the last
/// fill's token's.
HlFill foldClosedFills(List<HlFill> fills) {
  if (fills.length == 1) return fills.single;
  final byTime = [...fills]..sort((a, b) => a.time.compareTo(b.time));
  final last = byTime.last;
  var size = 0.0;
  var notional = 0.0;
  var fee = 0.0;
  var pnl = 0.0;
  double? builderFee;
  for (final f in byTime) {
    size += f.sz;
    notional += f.px * f.sz;
    pnl += f.closedPnl;
    if (f.feeToken == last.feeToken) fee += f.fee;
    if (f.builderFee case final b?) builderFee = (builderFee ?? 0) + b;
  }
  return HlFill(
    coin: last.coin,
    px: size > 0 ? notional / size : last.px,
    sz: size,
    side: last.side,
    time: last.time,
    closedPnl: pnl,
    // Summed doubles print their noise where a fee is not in dollars.
    fee: double.parse(fee.toStringAsFixed(8)),
    feeToken: last.feeToken,
    oid: last.oid,
    hash: last.hash,
    dir: last.dir,
    cloid: last.cloid,
    builderFee: builderFee,
    startPosition: byTime.first.startPosition,
    liquidated: byTime.any((f) => f.liquidated),
    accountingComplete: byTime.every((f) => f.accountingComplete),
    crossed: last.crossed,
  );
}

/// Opens [destination], whose result is the row's [resultUsd].
void openPortfolioClosedDestination(BuildContext context, WidgetRef ref,
    PortfolioClosedDestination destination,
    {required double resultUsd}) {
  switch (destination) {
    case PortfolioClosedVenueReceipt(:final tx):
      showClosedPredictionReceipt(context, ref, tx, resultUsd: resultUsd);
    case PortfolioClosedResultReceipt(:final result):
      showPredictionResultDetails(context, result, resultUsd: resultUsd);
    case PortfolioClosedFillReceipt(:final fill):
      showClosedFillReceipt(context, fill, resultUsd: resultUsd);
    case PortfolioClosedMarketPage(:final eventSlug):
      final event = ref.read(polyPositionEventProvider(eventSlug));
      if (event == null) return;
      MarketDetailSheet.show(context, event: event, source: 'portfolio_closed');
  }
}
