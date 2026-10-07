// The state a held Predictions position is in between its market ending
// and its result being claimable.
//
// A market that has ended is not claimable at once. Polymarket first
// resolves it and reports the result to the Conditional Tokens contract on
// Polygon (`reportPayouts`, after which `payoutDenominator > 0`); only then
// does a redeem pay out, and the Data API flags the position `redeemable`
// about then. Measured on 5 Oct 2026: a 5 minute BTC round resolved on
// chain 55 to 88 s after its end (it is settled automatically from its
// price feed); a game's main market 12 to 31 minutes after the final
// whistle, some soccer leagues about 2 hours. In between the position says
// so ("Ended · Result in a few minutes", "You won · Ready to claim soon")
// instead of looking stuck, and turns into the claimable card on its own on
// the next refresh (the trading provider polls faster while a held
// position is in this state).
//
// When Polymarket publishes when a proposed result settles
// (`expected_settlement_time`, resolution_estimate.dart) the caption says
// how long is left instead ("Ended · Result in about 12 min"). Short
// crypto rounds never get one (they settle from their price feed): for a
// 5 or 15 minute Up/Down round, identified by its slug, the caption counts
// from the round's end instead, on its measured settle time (53 to 88 s
// after the end, read on 5 Oct 2026): "about 1 min" for the first 45 s,
// then "under a minute", and the generic "in a few minutes" once 2.5
// minutes have passed without the result.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/live_game.dart';
import 'package:kute/services/polymarket/crypto_round.dart';
import 'package:kute/services/polymarket/resolution_estimate.dart';

/// When the market [conditionId] is expected to settle, read while an
/// ended position shows it and again each minute (a result can be
/// proposed, or proposed again, while the position waits). Null when
/// Polymarket gives no estimate.
final polyExpectedSettlementProvider =
    FutureProvider.autoDispose.family<DateTime?, String>((ref, conditionId) {
  final again = Timer(const Duration(minutes: 1), ref.invalidateSelf);
  ref.onDispose(again.cancel);
  return fetchPolyExpectedSettlement(conditionId);
});

/// The end of the 5 or 15 minute crypto Up/Down round with this slug
/// (`btc-updown-5m-1791199800`, any asset), or null for anything else.
/// These rounds settle on chain from their price feed 53 to 88 s after
/// their end and never carry an expected settlement time.
DateTime? polyShortRoundEnd(String? eventSlug) {
  final round = polyCryptoRoundOf(eventSlug ?? '');
  if (round == null || round.window > const Duration(minutes: 15)) return null;
  return round.end;
}

/// After this much time past a short round's end without its result, the
/// caption stops estimating and says "in a few minutes".
const Duration kPolyShortRoundLate = Duration(seconds: 150);

/// Up to this much past the end the caption says "about 1 min", then
/// "under a minute".
const Duration kPolyShortRoundUnderMinute = Duration(seconds: 45);

/// Whether the caption of a short round ending at [roundEnd] is counting at
/// [now] (and so has to refresh every few seconds).
bool polyShortRoundEstimating(DateTime? roundEnd, DateTime now) {
  if (roundEnd == null) return false;
  final past = now.difference(roundEnd);
  return !past.isNegative && past < kPolyShortRoundLate;
}

/// A tick every 5 s, for a short round's caption while it counts.
final polyAwaitingTickProvider = Provider.autoDispose<DateTime>((ref) {
  final timer = Timer(const Duration(seconds: 5), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return DateTime.now();
});

/// Where an ended, not yet claimable position stands, read off its price.
enum PolyAwaitingResult {
  /// The held side is at ~100%: it won, the payout opens shortly.
  won,

  /// The held side is at ~0%: it lost.
  lost,

  /// Not clear from the price yet.
  pending,
}

/// A 5 or 15 minute round (`btc-updown-5m-1715250300`), whose slug carries
/// its exact window.
bool polyIsShortRound(String? eventSlug) =>
    RegExp(r'-(5|15)m-\d{10}$').hasMatch(eventSlug ?? '');

/// Whether the position's market has stopped (its result is what is left):
/// a short round past its end, a game the feed or Gamma says is over, a
/// market Gamma has closed, or a market that is not a game past its end
/// date. A game's scheduled end alone does not count: games run past it
/// (overtime, a late kickoff), so a game waits for the feed's final or
/// Gamma's flags. Without the event (not read yet) only a short round can
/// tell.
bool polyMarketHasEnded({
  String? eventSlug,
  DateTime? end,
  PolymarketEvent? event,
  PolyLiveGame? live,
  bool isGame = false,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final endPassed = end != null && !end.isAfter(at);
  if (polyIsShortRound(eventSlug) && endPassed) return true;
  if (live?.finished == true) return true;
  if (event == null) return false;
  if (event.ended || event.closed) return true;
  return !isGame && endPassed;
}

/// The awaiting state of a held side worth [price] (0..1) per share.
PolyAwaitingResult polyAwaitingResultFor(double? price) {
  if (price == null) return PolyAwaitingResult.pending;
  if (price >= 0.99) return PolyAwaitingResult.won;
  if (price <= 0.01) return PolyAwaitingResult.lost;
  return PolyAwaitingResult.pending;
}

/// The caption of an ended, not yet claimable position. With [settleAt]
/// (Polymarket's expected settlement time) still ahead it says how long is
/// left: "Result in under a minute", "about N min", or "about N h" past an
/// hour. Without it, or once it has passed, a short round ([shortRound])
/// resolves about a minute and a half after it ends, so it says "in a few
/// minutes"; a game or any other market takes longer (a game typically 15
/// minutes to 2 hours), so it says "soon". A 5 or 15 minute round
/// ([roundEnd], from [polyShortRoundEnd]) without Polymarket's time
/// estimates from its end: "about 1 min", "under a minute" after 45 s, the
/// generic caption after 2.5 minutes.
String polyAwaitingText(AppLocalizations l10n, PolyAwaitingResult result,
    {required bool shortRound,
    DateTime? settleAt,
    DateTime? roundEnd,
    DateTime? now}) {
  final at = now ?? DateTime.now();
  final left = settleAt?.difference(at);
  if ((left == null || left <= Duration.zero) &&
      result != PolyAwaitingResult.lost &&
      polyShortRoundEstimating(roundEnd, at)) {
    final won = result == PolyAwaitingResult.won;
    if (at.difference(roundEnd!) < kPolyShortRoundUnderMinute) {
      return won
          ? l10n.polyAwaitingWonInMinutes(1)
          : l10n.polyAwaitingResultInMinutes(1);
    }
    return won
        ? l10n.polyAwaitingWonUnderMinute
        : l10n.polyAwaitingResultUnderMinute;
  }
  if (left != null &&
      left > Duration.zero &&
      result != PolyAwaitingResult.lost) {
    final won = result == PolyAwaitingResult.won;
    if (left < const Duration(minutes: 1)) {
      return won
          ? l10n.polyAwaitingWonUnderMinute
          : l10n.polyAwaitingResultUnderMinute;
    }
    final minutes = (left.inSeconds / 60).ceil();
    if (minutes < 60) {
      return won
          ? l10n.polyAwaitingWonInMinutes(minutes)
          : l10n.polyAwaitingResultInMinutes(minutes);
    }
    final hours = (left.inMinutes / 60).round();
    return won
        ? l10n.polyAwaitingWonInHours(hours)
        : l10n.polyAwaitingResultInHours(hours);
  }
  return switch (result) {
    PolyAwaitingResult.won =>
      shortRound ? l10n.polyAwaitingWon : l10n.polyAwaitingWonSoon,
    PolyAwaitingResult.lost => l10n.polyAwaitingLost,
    PolyAwaitingResult.pending =>
      shortRound ? l10n.polyAwaitingResult : l10n.polyAwaitingResultSoon,
  };
}
