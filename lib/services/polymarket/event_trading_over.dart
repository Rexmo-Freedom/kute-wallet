// Whether trading on a Polymarket event is over, by Gamma's flags alone.
//
// Polymarket keeps a market open until it resolves, so its `endDate` can
// pass while it is still trading: the Brazil presidential "who wins"
// market kept its first-round date while the runoff was weeks away. The
// end date is for display ("Expected 4 Oct") and the "Ending soon" sort,
// never for hiding. A lopsided price (99/1) never means closed either:
// a longshot in an outright is a live, tradable market.

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
/// be traded: not `closed`, and `acceptingOrders` not `false`. A missing
/// `acceptingOrders` means open; the backend feed keeps the field.
bool polyRawMarketTradable(Object? market) {
  if (market is! Map) return false;
  return market['closed'] != true && market['acceptingOrders'] != false;
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
List<dynamic> polyShownRawMarkets(List<dynamic> markets) {
  if (!markets.any(polyRawMarketTradable)) return markets;
  final shown = [
    for (final m in markets)
      if (polyRawMarketTradable(m) || polyRawMarketIsGameWinner(m)) m,
  ];
  return shown.length == markets.length ? markets : shown;
}

/// True for a raw Gamma market that is a game's moneyline (Gamma's
/// `sportsMarketType`): the market a finished game's winner is read from.
bool polyRawMarketIsGameWinner(Object? market) =>
    market is Map && market['sportsMarketType'] == 'moneyline';

/// True when [markets] (raw Gamma markets) is not empty and none of them
/// can be traded; false for an empty list.
bool polyAllRawMarketsClosed(List<dynamic> markets) =>
    markets.isNotEmpty && !markets.any(polyRawMarketTradable);
