import 'dart:math' as math;

import 'package:kute/services/polymarket/market_terms_store.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/services/polymarket_clob_websocket.dart'
    show PolymarketLiveBooks;
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart';

/// CLOB REST books are not best-price-first. Normalize at the boundary so
/// the SDK's first-entry bestAsk/bestBid getters remain correct.
OrderBook parsePolymarketOrderBook(Map<String, dynamic> json) {
  final book = OrderBook.fromJson({
    ...json,
    'min_tick_size': json['tick_size'] ?? json['min_tick_size'],
  });
  List<OrderSummary> levels(List<OrderSummary> source, {required bool asks}) {
    final result = source
        .where((level) =>
            level.priceNum.isFinite &&
            level.priceNum > 0 &&
            level.priceNum < 1 &&
            level.sizeNum.isFinite &&
            level.sizeNum > 0)
        .toList();
    result.sort((a, b) => asks
        ? a.priceNum.compareTo(b.priceNum)
        : b.priceNum.compareTo(a.priceNum));
    return result;
  }

  return OrderBook(
    market: book.market,
    assetId: book.assetId,
    timestamp: book.timestamp,
    hash: book.hash,
    bids: levels(book.bids, asks: false),
    asks: levels(book.asks, asks: true),
    minTickSize: book.minTickSize,
    minOrderSize: book.minOrderSize,
    negRisk: book.negRisk,
  );
}

/// The book cannot fill the stake within the price cap: [fillableUsd] is
/// what the asks at or under the cap add up to now (zero when nothing is
/// for sale there). At placement [price] is what the whole stake would
/// cost per share now and [limit] the approved cap it moved past. Nothing
/// was bought.
class PolymarketThinBook implements Exception {
  const PolymarketThinBook(
      {required this.fillableUsd, this.price, this.limit, this.retryPrice});
  final double fillableUsd;
  final double? price, limit;

  /// When the price moved past [limit]: the cap a new approval would name
  /// at the price now (polymarketBuyCap), for "Retry at 85¢".
  final double? retryPrice;

  /// Whole cents, rounded down: an amount that does fill.
  double get fillableCents => (fillableUsd * 100 + 1e-6).floorToDouble() / 100;

  @override
  String toString() => 'Not enough liquidity at this price '
      '(fillable \$${fillableCents.toStringAsFixed(2)})';
}

double _onTick(int ticks, double tick) =>
    double.parse((ticks * tick).toStringAsFixed(6));

/// The price cap of a market buy at [ask] with [slippagePct] on a market
/// whose increment is [tick]: `ask × (1 + slippage)` rounded DOWN to the
/// tick, but never less than one tick above the (tick-rounded) ask while
/// slippage is above zero. Between about 4¢ and 20¢ the percentage alone
/// rounds back to the ask itself (12¢ × 1.05 = 12.6¢ → 12¢), so any one-tick
/// move killed the fill-or-kill. The extra room is that single tick and no
/// more, and it never lifts the cap past 0.99. Slippage 0 keeps the exact
/// ask. Never above 1 − tick, never below one tick.
double polymarketBuyCap(
    {required double ask, required double slippagePct, required double tick}) {
  final ceiling = 1 - tick;
  final byPct = _onTick(
      (math.min(ask * (1 + slippagePct / 100), ceiling) / tick + 1e-9).floor(),
      tick);
  var cap = byPct;
  if (slippagePct > 0) {
    final oneTick = _onTick((ask / tick + 1e-9).floor() + 1, tick);
    cap = math.max(byPct, math.min(oneTick, 0.99));
  }
  return math.max(tick, math.min(cap, _onTick((ceiling / tick).round(), tick)));
}

/// The mirror for a market sell at [bid]: `bid × (1 − slippage)` rounded UP
/// to the tick, but at least one tick under the (tick-rounded) bid while
/// slippage is above zero, floored at one tick above 0. Slippage 0 keeps
/// the exact bid.
double polymarketSellFloor(
    {required double bid, required double slippagePct, required double tick}) {
  final bidTicks = (bid / tick - 1e-9).ceil();
  final byPct = (bid * (1 - slippagePct / 100) / tick - 1e-9).ceil();
  var ticks = byPct;
  if (slippagePct > 0) ticks = math.min(byPct, bidTicks - 1);
  return _onTick(math.max(1, ticks), tick);
}

/// A market's increment before its book has been read, for an estimate
/// only: the venue quotes 0.001 under 4¢ and over 96¢, else 0.01.
double polymarketEstimatedTick(double price) =>
    price < 0.04 || price > 0.96 ? 0.001 : 0.01;

/// "85¢" (or "8.5¢" off a whole cent): how the slips name a price cap.
String polymarketCentsLabel(double price) {
  final c = price * 100;
  final whole = (c - c.roundToDouble()).abs() < 1e-6;
  return '${whole ? c.round().toString() : c.toStringAsFixed(1)}¢';
}

/// A market sell stopped before signing: the best bid fell to [price],
/// under the approved floor [limit]. [retryPrice] is the floor a new
/// approval would name now (polymarketSellFloor). Nothing was sold.
class PolymarketSellPriceMoved implements Exception {
  const PolymarketSellPriceMoved(
      {required this.price, required this.limit, required this.retryPrice});
  final double price, limit, retryPrice;

  @override
  String toString() => 'Bid moved under the approved price: no liquidity there';
}

/// The price a market sell is signed at, from the bid read after its
/// approval: the floor at that bid (polymarketSellFloor), never under the
/// approved floor [approvedFloor]. When the bid has fallen under the
/// approved floor nothing is signed: [PolymarketSellPriceMoved] carries
/// the floor a new approval would name. [freshBid] null (unread) keeps the
/// approved floor.
double polymarketSellSendPrice({
  required double approvedFloor,
  required double? freshBid,
  required double slippagePct,
  required double tick,
}) {
  final bid = freshBid;
  if (bid == null || !bid.isFinite || bid <= 0 || bid >= 1) {
    return approvedFloor;
  }
  final fresh =
      polymarketSellFloor(bid: bid, slippagePct: slippagePct, tick: tick);
  if (bid < approvedFloor - 1e-9) {
    throw PolymarketSellPriceMoved(
        price: bid, limit: approvedFloor, retryPrice: fresh);
  }
  return math.max(fresh, approvedFloor);
}

/// The dollars the asks at or under [maxPrice] add up to: what a buy
/// capped there can fill against this book.
double polymarketDepthWithin(OrderBook book, double maxPrice) =>
    polymarketWalkAsks(polymarketLevels(book.asks),
            amountUsd: 0, maxPrice: maxPrice)
        .depthUsd;

/// A book side as (price, size) levels, for [polymarketWalkAsks] and
/// [polymarketWalkBids].
List<(double, double)> polymarketLevels(Iterable<OrderSummary> side) =>
    [for (final l in side) (l.priceNum, l.sizeNum)];

bool _validLevel((double, double) level) {
  final (p, size) = level;
  return p.isFinite && p > 0 && p < 1 && size.isFinite && size > 0;
}

/// What a market buy of [amountUsd] gets from a book's asks: walked
/// cheapest first, taking no level priced over the order's cap. The one
/// walk every buy preview, the quote and the Ledger check share, so what
/// a slip says the stake buys ("Payout if you win": [shares], \$1 each)
/// is what the order sent with that cap fills, never the stake over the
/// mid price.
class PolymarketAskWalk {
  const PolymarketAskWalk({
    required this.amountUsd,
    required this.spentUsd,
    required this.shares,
    required this.depthUsd,
    this.lastPrice,
  });

  /// The stake walked.
  final double amountUsd;

  /// The part of the stake the asks under the cap absorb.
  final double spentUsd;

  /// The shares [spentUsd] buys.
  final double shares;

  /// Every ask at or under the cap, in dollars: what fills there now.
  final double depthUsd;

  /// The dearest level the stake reached (with no cap: the marginal ask;
  /// the dearest level there is when the book cannot absorb it). Null when
  /// nothing is for sale under the cap.
  final double? lastPrice;

  /// Whether the whole stake fills under the cap.
  bool get fills => amountUsd - spentUsd <= 1e-9;

  /// The average price paid per share; null when nothing fills.
  double? get averagePrice => shares > 0 ? spentUsd / shares : null;
}

/// Walks [asks] (any order, invalid levels skipped) for a market buy of
/// [amountUsd] capped at [maxPrice] (1: no cap).
PolymarketAskWalk polymarketWalkAsks(Iterable<(double, double)> asks,
    {required double amountUsd, double maxPrice = 1}) {
  final levels = asks.where(_validLevel).toList()
    ..sort((a, b) => a.$1.compareTo(b.$1));
  var remaining = amountUsd.isFinite && amountUsd > 0 ? amountUsd : 0.0;
  var spent = 0.0, shares = 0.0, depth = 0.0;
  double? last;
  for (final (p, size) in levels) {
    if (p > maxPrice + 1e-9) break;
    final cost = p * size;
    depth += cost;
    if (remaining <= 0) continue;
    last = p;
    if (cost >= remaining) {
      spent += remaining;
      shares += remaining / p;
      remaining = 0;
    } else {
      spent += cost;
      shares += size;
      remaining -= cost;
    }
  }
  return PolymarketAskWalk(
      amountUsd: amountUsd.isFinite && amountUsd > 0 ? amountUsd : 0,
      spentUsd: spent,
      shares: shares,
      depthUsd: depth,
      lastPrice: last);
}

/// What a market sell of [shares] brings walking [bids] (any order)
/// dearest first, taking no level under [minPrice]: [soldShares] of them
/// sell, for [proceedsUsd] before fees. The sell previews' mirror of
/// [polymarketWalkAsks].
({double soldShares, double proceedsUsd}) polymarketWalkBids(
    Iterable<(double, double)> bids,
    {required double shares,
    double minPrice = 0}) {
  final levels = bids.where(_validLevel).toList()
    ..sort((a, b) => b.$1.compareTo(a.$1));
  var remaining = shares.isFinite && shares > 0 ? shares : 0.0;
  var sold = 0.0, proceeds = 0.0;
  for (final (p, size) in levels) {
    if (remaining <= 0 || p < minPrice - 1e-9) break;
    final take = math.min(size, remaining);
    sold += take;
    proceeds += take * p;
    remaining -= take;
  }
  return (soldShares: sold, proceedsUsd: proceeds);
}

/// A public book snapshot prepared before approval. The dollar budget and
/// maximum price are immutable; subsequent fills may execute at better prices.
class PolymarketMarketBuyQuote {
  PolymarketMarketBuyQuote._({
    required this.tokenId,
    required this.amount,
    required this.price,
    required this.bestAsk,
    required this.maxPrice,
    required this.tickSize,
    required this.negRisk,
    required this.fees,
    required this.fillableUsd,
    required this.shares,
  }) : fetchedAt = DateTime.now();

  /// What the asks at or under [maxPrice] add up to: less than [amount]
  /// when the book cannot fill the whole stake within the cap.
  final double fillableUsd;

  /// The shares [amount] buys walking the asks up to [maxPrice]
  /// ([polymarketWalkAsks]): what the bet pays, \$1 each, if it wins.
  final double shares;

  final String tokenId, tickSize;

  /// [price] is the marginal ask reached walking depth for [amount];
  /// [bestAsk] the cheapest level, where a fill costs the most in fees.
  final double amount, price, bestAsk, maxPrice;
  final bool negRisk;
  final DateTime fetchedAt;

  /// Fee terms this quote was prepared with: the market's live curve, or
  /// the documented maxima when it could not be read.
  final PolymarketFeeTerms fees;

  /// The most the venue can charge in fees for this buy: every dollar
  /// filling at the best ask, as a taker, with the builder code attached.
  double get feeCeiling => fees.feeCeilingForNotional(amount, bestAsk);

  /// One cent: the venue's one-dollar floor can need a fraction of a cent
  /// more than a stake that floors to whole-cent shares just under it.
  static const roundingHeadroom = 0.01;

  /// [amount] plus [feeCeiling] plus [roundingHeadroom]: what the account
  /// must hold, and the most the approval covers.
  double get allInMax => amount + feeCeiling + roundingHeadroom;

  factory PolymarketMarketBuyQuote.fromBook(
    OrderBook book, {
    required String tokenId,
    required double amount,
    required double slippagePct,
    PolymarketFeeTerms fees = PolymarketFeeTerms.worstCase,
  }) {
    if (book.assetId != tokenId ||
        !amount.isFinite ||
        amount <= 0 ||
        !slippagePct.isFinite ||
        slippagePct < 0 ||
        slippagePct > 30) {
      throw const FormatException('Invalid market quote');
    }
    final tickSize = book.minTickSize;
    if (!const {'0.1', '0.01', '0.005', '0.0025', '0.001', '0.0001'}
        .contains(tickSize)) {
      throw const FormatException('Unsupported market price increment');
    }
    final asks = book.asks
        .where((level) =>
            level.priceNum.isFinite &&
            level.priceNum > 0 &&
            level.priceNum < 1 &&
            level.sizeNum.isFinite &&
            level.sizeNum > 0)
        .toList()
      ..sort((a, b) => a.priceNum.compareTo(b.priceNum));
    if (asks.isEmpty) {
      throw StateError('No liquidity available for this outcome');
    }
    final levels = polymarketLevels(asks);
    // The marginal ask the stake reaches walking the whole book.
    final price =
        polymarketWalkAsks(levels, amountUsd: amount).lastPrice ??
            asks.first.priceNum;
    final tick = double.parse(tickSize!);
    // The selected slippage rounded down, with one tick of room at least;
    // the approval names exactly this cap.
    final maxPrice = polymarketBuyCap(
        ask: price, slippagePct: slippagePct, tick: tick);
    if (maxPrice < price - 1e-9) {
      throw const FormatException('Price is outside the market limits');
    }
    final capped =
        polymarketWalkAsks(levels, amountUsd: amount, maxPrice: maxPrice);
    return PolymarketMarketBuyQuote._(
        tokenId: tokenId,
        amount: amount,
        price: price,
        bestAsk: asks.first.priceNum,
        maxPrice: maxPrice,
        tickSize: tickSize,
        negRisk: book.negRisk,
        fees: fees,
        fillableUsd: capped.depthUsd,
        shares: capped.shares);
  }

  /// Whether the book fills the whole stake within [maxPrice]: the check
  /// the slip makes before approval ([PolymarketThinBook] otherwise).
  bool get fills => fillableUsd + 1e-6 >= amount;

  /// Whether the increment and neg-risk this quote carries can be signed
  /// with now: read within the last 15 seconds, or still what the market
  /// feed (current for the token, where an increment change would have
  /// arrived) and the saved terms say. A slow approval no longer sends
  /// the placement back to the venue for them.
  bool get hasFreshTerms {
    if (DateTime.now().difference(fetchedAt) < const Duration(seconds: 15)) {
      return true;
    }
    if (!PolymarketLiveBooks.instance.isCurrent(tokenId)) return false;
    return PolymarketMarketTermsStore.currentTickSize(tokenId,
                referencePrice: bestAsk) ==
            tickSize &&
        PolymarketMarketTermsStore.read(tokenId)?.negRisk == negRisk;
  }
}

/// A market buy as the approval covers it, built while the prompt is on
/// screen: the shares for [amount] at the approved [price], the market's
/// increment and neg-risk, and the builder code held then. After the
/// approval only signing and the POST remain; a send-time price other
/// than [price] builds a new plan.
class PolymarketOrderPlan {
  const PolymarketOrderPlan({
    required this.amount,
    required this.price,
    required this.shares,
    required this.tickSize,
    required this.negRisk,
    this.builderCode,
  });

  final double amount, price, shares;
  final String tickSize;
  final bool negRisk;

  /// The code held when the plan was built; null means the order goes out
  /// with the zero builder unless the refresh lands before signing.
  final String? builderCode;

  factory PolymarketOrderPlan.build({
    required double amount,
    required double price,
    required String tickSize,
    required bool negRisk,
    String? builderCode,
  }) =>
      PolymarketOrderPlan(
        amount: amount,
        price: price,
        shares: sharesFor(amount, price),
        tickSize: tickSize,
        negRisk: negRisk,
        builderCode: builderCode,
      );

  /// What the market buy spends: the stake itself, signed to the cent
  /// (PolymarketOrderAmounts.encode's `spendUsd`), or the venue's minimum
  /// when [shares] were bumped up to it. Never the floored [shares] ×
  /// [price], which signed a typed \$5.00 as \$4.99.
  double get spendUsd => math.max(amount, shares * price);

  /// Shares for [amount] at [price], floored to a hundredth; bumped up to
  /// meet the venue's one-dollar floor only within the stake plus the
  /// quote's rounding cent, never into the fee room.
  static double sharesFor(double amount, double price) {
    var shares = ((amount / price) * 100).floorToDouble() / 100;
    if (shares * price < 1.0 && amount >= 1.0) {
      final bumped = (1.0 / price * 100).ceilToDouble() / 100;
      if (bumped * price <=
          amount + PolymarketMarketBuyQuote.roundingHeadroom + 1e-9) {
        shares = bumped;
      }
    }
    return shares;
  }
}
