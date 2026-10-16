// lib/services/polymarket/fresh_fill.dart
//
// The price a market buy is signed at, from a book read just before it is
// signed: a marketable limit (fill-and-kill) whose worst price is the
// executable ask plus the order's tolerance, on the market's increment,
// never past what the approval covers and never outside the venue's valid
// range (one tick to one minus a tick, i.e. 1¢ to 99¢ on a 1¢ market).
//
// A queued bet funded from Dollars used to be priced from the odds the
// slip showed when it was confirmed, and signed after the money had
// landed, tens of seconds later. On a five-minute round or a game in play
// the book had moved by then, and the order was killed. The autofire now
// reads the book after the credit and prices from it with this.

import 'dart:math' as math;

import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show OrderBook;

/// [price] rounded DOWN to [tick] (a buy's worst price never rounds up
/// past what was approved), then clamped to the venue's valid range:
/// one tick to one minus a tick.
double polymarketWorstPriceOnTick(double price, double tick) {
  if (!tick.isFinite || tick <= 0 || tick >= 1) {
    throw ArgumentError.value(tick, 'tick', 'not a market increment');
  }
  final ticks = (price / tick + 1e-9).floor();
  final maxTicks = ((1 - tick) / tick).round();
  final clamped = ticks.clamp(1, maxTicks);
  return double.parse((clamped * tick).toStringAsFixed(6));
}

/// What a market buy is signed with, read off one book.
class PolymarketFillPrice {
  const PolymarketFillPrice({
    required this.orderPrice,
    required this.quotedPrice,
    required this.bestAsk,
    required this.quote,
  });

  /// The worst price signed: the fresh cap (ask plus tolerance, at least
  /// one tick above it), under the approval, on the increment.
  final double orderPrice;

  /// What the whole stake costs per share in this book (the marginal ask
  /// walked to the stake): the price quoted for the fill.
  final double quotedPrice;

  /// The cheapest ask now.
  final double bestAsk;

  /// The executable quote the price came from (increment, neg-risk, fee
  /// terms), handed to the order so it signs without another read.
  final PolymarketMarketBuyQuote quote;
}

/// Prices a market buy of [amount] on [book] for [tokenId]: the cap at
/// [slippagePct] over the executable ask (`polymarketBuyCap`), never
/// above [approvedMaxPrice] (rounded down to the increment). Throws
/// [PolymarketThinBook] when nothing can fill under the approval: no
/// asks at all, or the best ask already above it ([PolymarketThinBook.
/// retryPrice] then names what a new approval would cover).
PolymarketFillPrice polymarketFillPrice(
  OrderBook book, {
  required String tokenId,
  required double amount,
  required double slippagePct,
  required double approvedMaxPrice,
  PolymarketFeeTerms fees = PolymarketFeeTerms.worstCase,
}) {
  final PolymarketMarketBuyQuote quote;
  try {
    quote = PolymarketMarketBuyQuote.fromBook(book,
        tokenId: tokenId,
        amount: amount,
        slippagePct: slippagePct.clamp(0, 30).toDouble(),
        fees: fees);
  } on StateError {
    // Nothing for sale.
    throw const PolymarketThinBook(fillableUsd: 0);
  }
  final tick = double.parse(quote.tickSize);
  final approved = polymarketWorstPriceOnTick(approvedMaxPrice, tick);
  final orderPrice = polymarketWorstPriceOnTick(
      math.min(quote.maxPrice, approved), tick);
  if (quote.bestAsk > orderPrice + 1e-9) {
    throw PolymarketThinBook(
        fillableUsd: 0,
        price: quote.price,
        limit: approvedMaxPrice,
        retryPrice: quote.maxPrice);
  }
  return PolymarketFillPrice(
    orderPrice: orderPrice,
    quotedPrice: quote.price,
    bestAsk: quote.bestAsk,
    quote: quote,
  );
}
