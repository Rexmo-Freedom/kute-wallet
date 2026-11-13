// lib/services/polymarket/predictions_funding_window.dart
//
// Whether a prediction may be funded at Confirm, and which fast market it
// is on.
//
// Founder decision, 11 November 2026: pre-funding is removed. Money moves
// ONLY after the person accepts (Confirm and the step-up approval), never
// at market open, slip open, or an amount typed, tapped or held. Nothing
// here moves money or asks for an approval: these are the reads Confirm
// makes before it funds a bet (the same for every market, fast or not).
//
// Before any funding the market must still take orders
// ([predictionsFundingBlock]). A round that may end before the money
// lands is funded all the same (founder, 23 October 2026): the standing
// order places the bet only while the round is open and the price inside
// what was approved, else the money stays as Predictions cash and the
// slip's Retry opens the series' round in play.

import 'package:kute/models/polymarket_model.dart' show PolymarketEvent;
import 'package:kute/services/polymarket/event_trading_over.dart'
    show polyTradingOver;
import 'package:kute/services/polymarket/polymarket_slippage_defaults.dart'
    show isPolymarketFastRound;

/// Why a market cannot be funded now.
enum PredictionsFundingBlock {
  /// Closed, not taking orders, or a short round already over.
  ended,
}

/// The CLOB's own word on a market (`GET /markets/{condition_id}`).
class PolymarketMarketWindow {
  const PolymarketMarketWindow({
    required this.acceptingOrders,
    required this.closed,
    this.endAt,
  });

  final bool acceptingOrders;
  final bool closed;
  final DateTime? endAt;
}

/// Whether a bet on this market may be funded now, at Confirm: it takes
/// orders ([market], when read) and, for a short round, has not ended at
/// [now]. [endAt] is the slip's own end (Gamma), else the CLOB's. A round
/// that may end before the money lands is funded all the same: the
/// standing order places nothing once it has (the money stays as
/// Predictions cash).
///
/// A market that could not be read ([market] null) does not block: the
/// order itself is refused by a market that is shut.
///
/// An end already past only blocks a short round: a longer market's end
/// date is for display and it trades until it resolves (see
/// `event_trading_over.dart`), so whether it takes orders decides.
PredictionsFundingBlock? predictionsFundingBlock({
  PolymarketMarketWindow? market,
  DateTime? endAt,
  required bool fastRound,
  DateTime? now,
}) {
  if (market != null && (market.closed || !market.acceptingOrders)) {
    return PredictionsFundingBlock.ended;
  }
  final at = now ?? DateTime.now();
  final end = endAt ?? market?.endAt;
  if (fastRound && end != null && !end.isAfter(at)) {
    return PredictionsFundingBlock.ended;
  }
  return null;
}

/// Whether a slip must not open on this market: its event says it is
/// closed, inactive or ended ([polyTradingOver] by its explicit flags,
/// never a live game's paused book), or it is a short round whose end has
/// passed.
bool polymarketSlipEnded({
  PolymarketEvent? event,
  String? slug,
  String? question,
  DateTime? endAt,
  DateTime? now,
}) {
  if (event != null && polyTradingOver(event, inPlay: true)) return true;
  final at = now ?? DateTime.now();
  return endAt != null &&
      !endAt.isAfter(at) &&
      isPolymarketFastRound(
          slug: slug, question: question, endAt: endAt, now: at);
}

/// The fast markets, named on a funded order's analytics (`market_kind`)
/// so they read apart. A label only: a fast market is funded at Confirm
/// exactly as every other market is.
enum FastMarketKind { short, live }

/// [FastMarketKind.short] for a 5- or 15-minute round, `live` for a game
/// in play ([live]: the venue holds its orders for an in-play delay),
/// else null: the same flags the slippage default and the fast fill read.
FastMarketKind? fastMarketKind({
  String? slug,
  String? question,
  DateTime? endAt,
  required bool live,
  DateTime? now,
}) {
  if (isPolymarketFastRound(
      slug: slug, question: question, endAt: endAt, now: now)) {
    return FastMarketKind.short;
  }
  return live ? FastMarketKind.live : null;
}
