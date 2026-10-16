// lib/services/one_balance/buy_bitcoin_steps.dart
//
// A Buy bitcoin from Investments (the Move sheet's Investments → Bitcoin)
// as its step graph. "Move $20 to Bitcoin" with $12 in Investing and $5
// in Predictions and $3 in Dollars:
//
//   leg:investing   Moving $12.00 from Investing → Bitcoin   (direct)
//   leg:predictions Moving $5.00 from Predictions → Dollars  (via Dollars)
//   buy             Buying $8.00 of Bitcoin   after leg:predictions
//   arrive          Arriving in Bitcoin       after buy, leg:investing
//
// Every move has its graph now (move_steps.dart, one model for every
// move): this is the Buy bitcoin's view of it, kept for the code that
// names the purchase (the purchase itself, the background finisher) and
// for the tests. Everything here is [MoveSteps] for a move to Bitcoin.

import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/move_steps.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_funder.dart'
    show VenueCashDestination;

/// One planned leg of a Buy bitcoin: [usd] leaves [venue], straight to
/// Bitcoin when [direct], home to Dollars otherwise.
typedef BuyBitcoinPlannedLeg = MovePlannedLeg;

abstract final class BuyBitcoinSteps {
  static const String buyId = MoveSteps.buyId;
  static const String arriveId = MoveSteps.arriveId;

  /// The `for` of a Buy bitcoin move (`VenueCashFor.buyBitcoin`).
  static const String forAction = 'buy_bitcoin';

  static const VenueCashDestination _to = VenueCashDestination.bitcoin;

  static String legId(OneBalanceVenue venue) => MoveSteps.legId(venue);

  static MoneyPlace placeOf(OneBalanceVenue venue) => MoveSteps.placeOf(venue);

  /// Whether [move] is a Buy bitcoin.
  static bool describes(MultiSourceMove move) =>
      move.forAction == forAction && move.destination == _to;

  /// See [MoveSteps.planned].
  static MoneyStepGraph planned({
    required List<BuyBitcoinPlannedLeg> legs,
    required double onwardUsd,
    required double totalUsd,
    DateTime? at,
  }) =>
      MoveSteps.planned(
          destination: _to,
          forAction: forAction,
          legs: legs,
          onwardUsd: onwardUsd,
          totalUsd: totalUsd,
          at: at);

  /// See [MoveSteps.legRecorded].
  static MoneyStepGraph legRecorded(MoneyStepGraph g, MultiSourceMoveLeg leg) =>
      MoveSteps.legRecorded(g, leg, destination: _to, forAction: forAction);

  /// See [MoveSteps.onward].
  static MoneyStepGraph onward(MoneyStepGraph g, double usd) =>
      MoveSteps.onward(g, usd, destination: _to, forAction: forAction);

  /// The purchase is asking its quote (nothing has left Dollars yet).
  static MoneyStepGraph buyStarted(MoneyStepGraph g, {DateTime? at}) =>
      MoveSteps.finalStarted(g, at: at);

  /// The purchase's dollars were sent.
  static MoneyStepGraph buySent(MoneyStepGraph g, String operationId,
          {DateTime? at}) =>
      MoveSteps.finalSent(g, operationId, at: at);

  /// The purchase stopped before anything left Dollars.
  static MoneyStepGraph buyStopped(MoneyStepGraph g, String reason,
          {DateTime? at}) =>
      MoveSteps.finalStopped(g, reason, at: at);

  /// This remainder is below the route minimum; nothing left Dollars.
  static MoneyStepGraph buySkipped(MoneyStepGraph g, {DateTime? at}) {
    final buy = g.byId(buyId);
    if (buy == null || buy.ref != null || buy.status == MoneyStepStatus.skipped) {
      return g;
    }
    var next = g.update(
        buyId,
        (s) => s.copyWith(
            status: MoneyStepStatus.skipped,
            endedAt: at,
            reason: 'below_minimum'));
    final arrival = next.byId(arriveId);
    if (arrival != null) {
      final direct = next.steps
          .any((s) => MoveSteps.isVenueLeg(s) && s.route == MoneyRoute.direct);
      next = next.update(
          arriveId,
          (s) => s.copyWith(
              usd: (s.usd - buy.usd).clamp(0.0, double.infinity),
              status: direct ? s.status : MoneyStepStatus.skipped));
    }
    return next;
  }

  /// What came home landed: every leg on its way to Dollars is done.
  static MoneyStepGraph dollarsLanded(MoneyStepGraph g, {DateTime? at}) =>
      MoveSteps.dollarsLanded(g, at: at);

  /// [move]'s graph ([MoveSteps.of]); empty for a move that is not a Buy
  /// bitcoin.
  static MoneyStepGraph of(MultiSourceMove move) =>
      describes(move) ? MoveSteps.of(move) : MoneyStepGraph.empty;

  /// See [MoveSteps.fromRecord].
  static MoneyStepGraph fromRecord(MultiSourceMove move) =>
      MoveSteps.fromRecord(move);

  /// Applies [change] to move [moveId]'s graph and saves it, when the
  /// move is a Buy bitcoin. Best effort: a missing move is left alone.
  static void record(
      String? moveId, MoneyStepGraph Function(MoneyStepGraph g) change) {
    if (moveId == null) return;
    MultiSourceMoveStore.updateSteps(moveId, (move) {
      if (!describes(move)) return null;
      return change(MoveSteps.of(move));
    });
  }
}
