// lib/services/polymarket/shown_price.dart
//
// The chance a Predictions list shows for an outcome, by Polymarket's own
// rule: the midpoint of the book, unless the spread is wider than 10¢, in
// which case the last traded price. A wide book that has never traded has
// no chance to show ("—"), and a list puts it last.
//
// Without the rule a book with no bids and one ask at 74¢ read as a 37%
// chance (Gamma's `outcomePrices` count the missing bid as 0, and so did
// the midpoint the live feed took), which is how nearly every exact score
// of a football match showed "37.5%".
//
// Pure Dart; unit tested in test/services/polymarket/shown_price_test.dart.

import 'package:kute/models/polymarket_model.dart';

/// A spread wider than this (10¢) makes the midpoint no price.
const double kPolyWideSpread = 0.10;

/// Whether a book whose best bid is [bid] and best ask [ask] is wider than
/// [kPolyWideSpread]. A side with no orders counts as 0 (bids) or 1
/// (asks), as Polymarket counts it.
bool polySpreadIsWide(double? bid, double? ask) {
  final b = bid != null && bid > 0 ? bid : 0.0;
  final a = ask != null && ask > 0 && ask < 1 ? ask : 1.0;
  return a - b > kPolyWideSpread + 1e-9;
}

/// The price Polymarket shows for a book: its midpoint when the spread is
/// 10¢ or less, else [lastTrade]; null when the book is wide and has never
/// traded. [mid] overrides the midpoint worked out from [bid] and [ask].
double? polyShownPrice(
    {double? bid, double? ask, double? lastTrade, double? mid}) {
  if (!polySpreadIsWide(bid, ask)) {
    final b = bid != null && bid > 0 ? bid : 0.0;
    final a = ask != null && ask > 0 && ask < 1 ? ask : 1.0;
    return mid ?? (a + b) / 2;
  }
  if (lastTrade != null && lastTrade > 0 && lastTrade < 1) return lastTrade;
  return null;
}

double? _num(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String && v.trim().isNotEmpty) return double.tryParse(v.trim());
  return null;
}

/// The Yes chance of one Gamma market, from its `outcomePrices` first
/// price ([gammaPrice]) and its quote (`bestBid`, `bestAsk`, `spread`,
/// `lastTradePrice`). [unpriced] when the book is wide and has never
/// traded; [price] is then Gamma's own figure, kept for the slip's first
/// paint, and no list shows it. A market read without its quote (the Kute
/// feed leaves those keys out) keeps Gamma's figure.
({double price, bool unpriced}) polyGammaShownPrice(
    Map<String, dynamic> market, double gammaPrice) {
  final hasQuote = market.containsKey('bestBid') ||
      market.containsKey('bestAsk') ||
      market.containsKey('spread');
  if (!hasQuote) return (price: gammaPrice, unpriced: false);
  final bid = _num(market['bestBid']);
  final ask = _num(market['bestAsk']);
  final spread = _num(market['spread']);
  final wide = spread != null && bid == null && ask == null
      ? spread > kPolyWideSpread + 1e-9
      : polySpreadIsWide(bid, ask) &&
          (spread == null || spread > kPolyWideSpread + 1e-9);
  if (!wide) return (price: gammaPrice, unpriced: false);
  final last = _num(market['lastTradePrice']);
  if (last != null && last > 0 && last < 1) {
    return (price: last, unpriced: false);
  }
  return (price: gammaPrice, unpriced: true);
}

/// The chance a list shows for [o] at the live feed's [prices]: the live
/// price when the feed has one, none while the feed says its book is wide
/// and untraded ([unpriced], `LivePriceState.unpriced`), else the event's
/// own figure (none for an [o] that is [PolymarketOutcome.unpriced]).
double? polyShownChanceOf(
    Map<String, double> prices, Set<String> unpriced, PolymarketOutcome o) {
  final token = o.tokenId;
  if (token != null && token.isNotEmpty) {
    if (unpriced.contains(token)) return null;
    final live = prices[token];
    if (live != null) return live;
  }
  return o.unpriced ? null : o.price;
}

/// Most likely first; an outcome with no chance to show goes last.
int polyCompareShown(double? a, double? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return b.compareTo(a);
}
