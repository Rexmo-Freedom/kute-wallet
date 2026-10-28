// Whether trading on a Polymarket event is over, by Gamma's flags alone.
//
// Polymarket keeps a market open until it resolves, so its `endDate` can
// pass while it is still trading: the Brazil presidential "who wins"
// market kept its first-round date while the runoff was weeks away. The
// end date is for display ("Expected 4 Oct") and the "Ending soon" sort,
// never for hiding. A lopsided price (99/1) never means closed either:
// a longshot in an outright is a live, tradable market.

import 'dart:convert';

import 'package:kute/models/polymarket_model.dart';

/// True when [event] can no longer be bet on: Gamma says `closed`,
/// `active: false` or `ended` (a finished game waiting for its result), or
/// every market in it is `closed` or not accepting orders
/// ([PolymarketEvent.marketsClosed]; a market whose `acceptingOrders` is
/// missing counts as open).
///
/// A game in play ([inPlay]) stays open whatever its markets say: a live
/// game runs past its scheduled end and Gamma may pause its book
/// mid-match, and a blowout price is not a settled market. The three
/// explicit flags still win over [inPlay]; a live game never carries them.
bool polyTradingOver(PolymarketEvent event, {required bool inPlay}) {
  if (event.closed || !event.active || event.ended) return true;
  if (inPlay) return false;
  return event.marketsClosed;
}

/// Whether a raw Gamma market (one entry of an event's `markets`) can still
/// be traded: not a placeholder ([polyRawMarketPlaceholder]), not
/// `closed`, `acceptingOrders` not `false` and its order book not switched
/// off (`enableOrderBook: false`). A missing flag means open; the backend
/// feed keeps `active`, `closed` and `acceptingOrders`.
bool polyRawMarketTradable(Object? market) {
  if (market is! Map || polyRawMarketPlaceholder(market)) return false;
  return market['closed'] != true &&
      market['acceptingOrders'] != false &&
      market['enableOrderBook'] != false;
}

/// A generic name Polymarket gives a seat it has not filled yet: "Person
/// O" … "Person Z", "Candidate B", "Other".
final RegExp _kPlaceholderTitle = RegExp(
    r'^(?:(?:person|candidate|player|team|option)\s+[a-z]{1,2}|other)$',
    caseSensitive: false);

double? _rawNum(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String && v.trim().isNotEmpty) return double.tryParse(v.trim());
  return null;
}

/// The first of a raw market's `outcomePrices` (a JSON string or a list);
/// null when there are none (`null`, missing, empty).
double? _rawFirstPrice(Object? prices) {
  Object? list = prices;
  if (prices is String) {
    try {
      list = jsonDecode(prices);
    } catch (_) {
      return null;
    }
  }
  if (list is! List || list.isEmpty) return null;
  return _rawNum(list.first);
}

/// Whether a raw market has ever had a price: a Yes price above 0, a bid,
/// or a trade.
bool _rawHasPrice(Map market) {
  final first = _rawFirstPrice(market['outcomePrices']);
  final bid = _rawNum(market['bestBid']);
  final last = _rawNum(market['lastTradePrice']);
  return (first != null && first > 0) ||
      (bid != null && bid > 0) ||
      (last != null && last > 0);
}

/// True for a raw Gamma market that is a placeholder rather than a market
/// to list: Polymarket seeds a many-outcome event with seats for outcomes
/// nobody has announced ("Person O" … "Person Z", "Other" on the Brazil
/// presidential election), switched off (`active: false`) with no prices
/// (`outcomePrices: null`, a 0 bid and a 1 ask, no trade), and
/// polymarket.com never shows them. So: switched off or `archived`; or
/// never priced while its `outcomePrices` are null or its name is one of
/// those generic seats. A market that has a price is never a placeholder
/// by its name alone.
bool polyRawMarketPlaceholder(Object? market) {
  if (market is! Map) return false;
  if (market['active'] == false || market['archived'] == true) return true;
  if (_rawHasPrice(market)) return false;
  final noPrices = market.containsKey('outcomePrices') &&
      _rawFirstPrice(market['outcomePrices']) == null;
  final title = '${market['groupItemTitle'] ?? ''}'.trim();
  return noPrices || _kPlaceholderTitle.hasMatch(title);
}

/// The tradable markets of a raw Gamma event's [markets], for the rows an
/// open event shows: finished sub-markets (a first-round question) drop out
/// and the open "who wins" market stays. When none is tradable the whole
/// list comes back, so a resolved event (a held position's detail) still
/// shows its outcomes and its winner.
///
/// A game's closed moneyline stays whatever else is open: Polymarket closes
/// it minutes after the final whistle while a second-half spread may trade
/// for another hour, and the card's chart draws the winner from that
/// closed market (PolyGameLines.settledMoneyline). The game lines never lay
/// a closed market out as a row to bet on, so keeping it hides nothing and
/// bets on nothing.
///
/// Placeholders ([polyRawMarketPlaceholder]) never show, open event or
/// resolved, unless they are all there is.
List<dynamic> polyShownRawMarkets(List<dynamic> markets) {
  final real = [
    for (final m in markets)
      if (!polyRawMarketPlaceholder(m)) m,
  ];
  final pool =
      real.isEmpty || real.length == markets.length ? markets : real;
  if (!pool.any(polyRawMarketTradable)) return pool;
  final shown = [
    for (final m in pool)
      if (polyRawMarketTradable(m) || polyRawMarketIsGameWinner(m)) m,
  ];
  return shown.length == pool.length ? pool : shown;
}

/// The placeholders [polyShownRawMarkets] leaves out of [markets]
/// ([polyRawMarketPlaceholder]), kept so a holding in one still lists
/// ([PolymarketEvent.withHeldOutcomes]). Empty when every market is one.
List<dynamic> polyHiddenPlaceholderMarkets(List<dynamic> markets) {
  final hidden = [
    for (final m in markets)
      if (polyRawMarketPlaceholder(m)) m,
  ];
  return hidden.length == markets.length ? const [] : hidden;
}

/// True for a raw Gamma market that is a game's moneyline (Gamma's
/// `sportsMarketType`): the market a finished game's winner is read from.
bool polyRawMarketIsGameWinner(Object? market) =>
    market is Map && market['sportsMarketType'] == 'moneyline';

/// True when [markets] (raw Gamma markets) is not empty and none of them
/// can be traded; false for an empty list.
bool polyAllRawMarketsClosed(List<dynamic> markets) =>
    markets.isNotEmpty && !markets.any(polyRawMarketTradable);
