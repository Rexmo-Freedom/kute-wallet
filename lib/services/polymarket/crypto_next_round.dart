// lib/services/polymarket/crypto_next_round.dart
//
// Where the Up and Down buttons of a live 5-minute crypto card bet
// (founder, 8 November 2026). The card keeps its window on show (chart,
// target, countdown), and partway through the buttons roll to the next
// window by themselves, so nobody buys a 90.5% side for tiny upside, fewer
// fills go bad late in a window and slow funding hurts less:
//
//   * first [kCryptoRoundButtonsStayFor] of a window: this window;
//   * after that: the next window, once it has real prices
//     ([polyNextRoundButtons]: Gamma lists it as taking orders, and the
//     live feed holds a two-sided book of both its tokens, no wider than
//     Polymarket's own 10¢). Until then the buttons stay on this window,
//     to the very end if need be. Never Gamma's `outcomePrices`, a REST
//     midpoint or a last trade: those can be old or invented for a window
//     nobody has traded.
//
// Measured on 8 November 2026 (read-only, Gamma and CLOB /book): the next
// window is listed about a day ahead and quoted 1¢ wide with some $400 to
// $600 inside 2¢ on each side from at least 4:45 before it starts, and the
// one after it too. See the commit's report; the constant is one line.
//
// 15-minute windows do not roll: the two minutes are a 5-minute figure.
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

/// How long into a 5-minute window the buttons stay on it.
const Duration kCryptoRoundButtonsStayFor = Duration(minutes: 2);

/// How long before the buttons may roll the next window is read and its
/// books subscribed, so its prices are there at the moment itself.
const Duration kCryptoNextRoundReadAhead = Duration(seconds: 20);

/// Whether [round] is one whose buttons roll: a 5-minute window.
bool polyRoundButtonsRoll(PolyCryptoRound? round) =>
    round != null && round.window == const Duration(minutes: 5);

/// Whether the next window of [round] is worth reading at [now]: the
/// buttons may roll within [kCryptoNextRoundReadAhead]. Past the window's
/// end too, until the card itself rolls forward.
bool polyNextRoundWanted(PolyCryptoRound? round, DateTime now) =>
    polyRoundButtonsRoll(round) &&
    !now.isBefore(round!.start
        .add(kCryptoRoundButtonsStayFor - kCryptoNextRoundReadAhead));

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

/// What the buttons bet on once they have rolled.
class PolyNextRoundButtons {
  const PolyNextRoundButtons({required this.event, required this.up});

  /// The next window: its slug, title, tokens and times.
  final Btc5MinEvent event;

  /// Its live chance of Up, 0..1.
  final double up;

  DateTime get start => event.windowStartTime!;
}

/// The next window when the buttons of the card showing [round] bet on it
/// at [now]; null when they stay on [round]. [next] is Gamma's read of the
/// next window, [upBook] and [downBook] the feed's current books of its
/// two tokens. Past [round]'s end it still answers (the window has started
/// by then): the card rolls forward within a second or two, onto these
/// same tokens, and the buttons never jump back to a finished window.
PolyNextRoundButtons? polyNextRoundButtons({
  required PolyCryptoRound? round,
  required Btc5MinEvent? next,
  required PolymarketLiveBook? upBook,
  required PolymarketLiveBook? downBook,
  required DateTime now,
}) {
  if (!polyRoundButtonsRoll(round) || next == null) return null;
  if (now.isBefore(round!.start.add(kCryptoRoundButtonsStayFor))) return null;
  if (!polyNextRoundOpen(next,
      start: round.end.millisecondsSinceEpoch ~/ 1000, now: now)) {
    return null;
  }
  if (!polyRoundBookIsReal(upBook) || !polyRoundBookIsReal(downBook)) {
    return null;
  }
  final up = cryptoShownUp(upBook);
  if (!cryptoOddsSane(up)) return null;
  return PolyNextRoundButtons(event: next, up: up!);
}
