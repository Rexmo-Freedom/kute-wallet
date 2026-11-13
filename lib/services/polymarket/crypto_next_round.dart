// lib/services/polymarket/crypto_next_round.dart
//
// Where the Up and Down buttons of a live crypto round card bet (founder,
// 8 November 2026, restored for every length on 12 November 2026: "the
// current bet until some time and then it's the next one"). The card keeps
// the round in play on show (chart, price, target, countdown) all along;
// the buttons:
//
//   * bet THE ROUND IN PLAY until its cutoff ([polyRoundBetCutoff] in
//     crypto_round.dart: two minutes into a five-minute round, then 3, 5
//     and 10 minutes before the end of a 15-minute, hourly and four-hour
//     one), at its live odds ([polyCurrentRoundUp]); the line over them
//     says so ("Now · Ends in 02:16");
//   * then roll to THE NEXT ROUND by themselves ([polyRoundButtonsRolled]):
//     late in a round one side is ~98%, and funding takes 20 to 60 s, so a
//     bet then is unfair or lands too late. The next round is bet once it
//     has REAL prices ([polyNextRoundUp]): Gamma lists it as taking
//     orders, it has not started, and the live feed holds a two-sided book
//     of both its tokens, no wider than Polymarket's own 10¢. Until then
//     the buttons are disabled ("Next · Starts in 01:12 · No prices yet"),
//     never back on the round in play.
//
// The slip, the receipt and the position name the round bet, as before.
// Every length (5m, 15m, 1h, 4h), the other coins' rows included.
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
import 'package:kute/services/polymarket/crypto_round.dart';
import 'package:kute/services/polymarket/shown_price.dart'
    show polySpreadIsWide;
import 'package:kute/services/polymarket_clob_websocket.dart'
    show PolymarketLiveBook;

/// Whether [round] is one whose buttons roll: a round of a length that is
/// bet until a cutoff ([polyRoundBetCutoff]: 5m, 15m, 1h, 4h).
bool polyRoundButtonsRoll(PolyCryptoRound? round) =>
    round != null && polyRoundBetCutoff(round.window.inMinutes) != null;

/// Whether the buttons of a card of [minutes] whose round in play started
/// at [liveStart] (UTC seconds) have rolled to the next round at [now]:
/// the round in play has reached its cutoff ([polyRoundBetCutoff]). A
/// length with no cutoff is on the next round all along.
bool polyRoundButtonsRolled(
    {required int liveStart, required int minutes, required DateTime now}) {
  final cutoff = polyRoundBetCutoff(minutes);
  if (cutoff == null) return true;
  final at = now.toUtc().millisecondsSinceEpoch ~/ 1000;
  return at >= liveStart + minutes * 60 - cutoff.inSeconds;
}

/// The round in play's chance of Up, 0..1, on the buttons before they
/// roll: its live odds ([liveUp], the card's live feed), else Gamma's
/// polled price of [event], as the card always showed it. Null when
/// [event] is not the round that started at [start] (UTC seconds) or
/// takes no orders: the buttons are then disabled.
double? polyCurrentRoundUp({
  required Btc5MinEvent? event,
  required int start,
  required double? liveUp,
}) {
  if (event == null || !event.active || event.closed) return null;
  if (!event.acceptingOrders) return null;
  final up = event.upTokenId;
  final down = event.downTokenId;
  if (up == null || up.isEmpty || down == null || down.isEmpty) return null;
  final from = event.windowStartTime ??
      polyCryptoRoundOf(event.slug, endDate: event.endDate)?.start;
  if (from != null && from.millisecondsSinceEpoch ~/ 1000 != start) {
    return null;
  }
  final chance = liveUp ?? event.upPrice;
  return chance > 0 && chance < 1 ? chance : null;
}

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
