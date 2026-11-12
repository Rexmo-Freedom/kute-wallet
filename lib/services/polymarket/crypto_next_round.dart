// lib/services/polymarket/crypto_next_round.dart
//
// Where the Up and Down buttons of a live crypto round card bet: ONLY on
// the NEXT round, never the one in play (founder decision, 12 November
// 2026: late in a round one side is ~98%, and funding takes 20 to 60 s,
// so a bet on the round in play is unfair or lands too late). The card
// keeps the round in play on show (chart, price, target, countdown) as
// context and says the bet is on the next one ("Next · Starts in 02:16");
// its buttons, the slip, the receipt and the position are the next
// round's. Every length the chips offer (5m, 15m, 1h, 4h), the other
// coins' rows included.
//
//   * The next round can be bet once it has REAL prices
//     ([polyNextRoundUp]): Gamma lists it as taking orders, it has not
//     started, and the live feed holds a two-sided book of both its
//     tokens, no wider than Polymarket's own 10¢. Until then the buttons
//     are disabled ("No prices yet" on the line over them), never on the
//     round in play, never Gamma's `outcomePrices`, a REST midpoint or a
//     last trade: those can be old or invented for a round nobody traded.
//
// Measured on 8 November 2026 (read-only, Gamma and CLOB /book): the next
// 5-minute window is listed about a day ahead and quoted 1¢ wide with some
// $400 to $600 inside 2¢ on each side from at least 4:45 before it starts.
//
// Pure Dart: the card and the tests pass the clock and the books in. The
// read of the next window lives in crypto_next_round_provider.dart.

import 'package:kute/models/polymarket_model.dart' show Btc5MinEvent;
import 'package:kute/services/polymarket/crypto_live_odds.dart'
    show cryptoShownUp, cryptoOddsSane;
import 'package:kute/services/polymarket/shown_price.dart'
    show polySpreadIsWide;
import 'package:kute/services/polymarket_clob_websocket.dart'
    show PolymarketLiveBook;

/// Whether Gamma's [event] is the window starting at [start] (UTC epoch
/// seconds), open for orders at [now], both tokens known.
bool polyNextRoundOpen(Btc5MinEvent event,
    {required int start, required DateTime now}) {
  final at = event.windowStartTime;
  if (at == null || at.millisecondsSinceEpoch ~/ 1000 != start) return false;
  if (!event.active || event.closed || !event.acceptingOrders) return false;
  final up = event.upTokenId;
  final down = event.downTokenId;
  if (up == null || up.isEmpty || down == null || down.isEmpty) return false;
  final end = event.endDate;
  return end == null || end.isAfter(now);
}

/// Whether [book] is a real price: orders on both sides, no wider than
/// [polySpreadIsWide]'s 10¢. The caller passes the feed's current snapshot
/// (`PolymarketLiveBooks.snapshot`), so an old book never gets here.
bool polyRoundBookIsReal(PolymarketLiveBook? book) {
  final bid = book?.bestBid;
  final ask = book?.bestAsk;
  if (bid == null || ask == null || bid <= 0 || ask >= 1) return false;
  return ask >= bid && !polySpreadIsWide(bid, ask);
}

/// The next round's live chance of Up, 0..1, when its buttons can bet on
/// it at [now]: [next] is Gamma's read of the round starting at [start]
/// (UTC seconds), open for orders and not started ([polyNextRoundOpen]),
/// and [upBook] and [downBook], the feed's current books of its two
/// tokens, are real prices ([polyRoundBookIsReal]). Null otherwise: the
/// buttons are disabled, never on the round in play.
double? polyNextRoundUp({
  required Btc5MinEvent? next,
  required int start,
  required PolymarketLiveBook? upBook,
  required PolymarketLiveBook? downBook,
  required DateTime now,
}) {
  if (next == null) return null;
  if (now.toUtc().millisecondsSinceEpoch ~/ 1000 >= start) return null;
  if (!polyNextRoundOpen(next, start: start, now: now)) return null;
  if (!polyRoundBookIsReal(upBook) || !polyRoundBookIsReal(downBook)) {
    return null;
  }
  final up = cryptoShownUp(upBook);
  return cryptoOddsSane(up) ? up : null;
}
