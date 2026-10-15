// lib/services/one_balance/buy_bitcoin_steps.dart
//
// A Buy bitcoin from Investments (the Move sheet's Investments → Bitcoin)
// as its step graph ([MoneyStepGraph], money_steps.dart). "Move $20 to
// Bitcoin" with $12 in Investing and $5 in Predictions and $3 in Dollars:
//
//   leg:investing   Moving $12.00 from Investing → Bitcoin   (direct)
//   leg:predictions Moving $5.00 from Predictions → Dollars  (via Dollars)
//   buy             Buying $8.00 of Bitcoin   after leg:predictions
//   arrive          Arriving in Bitcoin       after buy, leg:investing
//
// Every leg starts at once and completes on its own; the purchase waits
// only on the legs whose money comes home to Dollars (none: it starts
// right away, Dollars pay it), and the arrival on the purchase and the
// legs that went straight to Bitcoin.
//
// The graph lives on the move's record (`MultiSourceMove.steps`,
// `multi_source_moves_v1`) and follows the events the money code already
// has, never deciding anything itself:
//
//  * planned: the puller's plan, every leg running (they go at once);
//  * a leg recorded (`MultiSourceMoveStore.addLeg`): on its way (its
//    Activity row id as `ref`), failed, or fallen back to Dollars;
//  * what the purchase takes from Dollars once the legs went;
//  * the purchase quoting, sent (its settlement operation), or stopped
//    before anything left Dollars;
//  * the money that came home landing in Dollars (the background
//    purchase's wait ending).
//
// What lands later (a leg's row settling, the purchase's order done, the
// bitcoin counted by the wallet) is read from the Activity rows where the
// graph is shown (buy_bitcoin_steps_view.dart). A record made before the
// graph existed (2.1.2's first builds) maps its legs and purchase onto
// steps when read ([BuyBitcoinSteps.of]).
//
// Local only: venue names, dollar amounts and the ids the wallet's own
// rows already carry. Nothing here is tracked.

import 'dart:math' as math;

import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_funder.dart'
    show VenueCashDestination;

/// One planned leg of a Buy bitcoin: [usd] leaves [venue], straight to
/// Bitcoin when [direct], home to Dollars otherwise.
typedef BuyBitcoinPlannedLeg = ({
  OneBalanceVenue venue,
  double usd,
  bool direct,
});

abstract final class BuyBitcoinSteps {
  static const String buyId = 'buy';
  static const String arriveId = 'arrive';

  /// The `for` of a Buy bitcoin move (`VenueCashFor.buyBitcoin`).
  static const String forAction = 'buy_bitcoin';

  static String legId(OneBalanceVenue venue) => 'leg:${venue.name}';

  static MoneyPlace placeOf(OneBalanceVenue venue) => switch (venue) {
        OneBalanceVenue.predictions => MoneyPlace.predictions,
        OneBalanceVenue.investing => MoneyPlace.investing,
      };

  /// Whether [move] is a Buy bitcoin, the move these steps describe.
  static bool describes(MultiSourceMove move) =>
      move.forAction == forAction &&
      move.destination == VenueCashDestination.bitcoin;

  // ── Building ──────────────────────────────────────────────────────

  /// The graph of a Buy bitcoin about to run [legs] (in plan order),
  /// whose purchase takes [onwardUsd] from Dollars, for [totalUsd] in
  /// all. The legs are running from [at]: they all go at once.
  static MoneyStepGraph planned({
    required List<BuyBitcoinPlannedLeg> legs,
    required double onwardUsd,
    required double totalUsd,
    DateTime? at,
  }) {
    final steps = <MoneyStep>[];
    final used = <String>{};
    for (final l in legs) {
      final id = _freshId(legId(l.venue), used);
      used.add(id);
      steps.add(MoneyStep(
        id: id,
        kind: MoneyStepKind.leg,
        from: placeOf(l.venue),
        to: l.direct ? MoneyPlace.bitcoin : MoneyPlace.dollars,
        usd: _cents(l.usd),
        route: l.direct ? MoneyRoute.direct : MoneyRoute.viaDollars,
        status: MoneyStepStatus.running,
        startedAt: at,
      ));
    }
    if (onwardUsd >= 0.01) steps.add(_buy(onwardUsd));
    steps.add(_arrive(totalUsd));
    return _wire(MoneyStepGraph(steps));
  }

  static MoneyStep _buy(double usd) => MoneyStep(
        id: buyId,
        kind: MoneyStepKind.buy,
        from: MoneyPlace.dollars,
        to: MoneyPlace.bitcoin,
        usd: _cents(usd),
      );

  static MoneyStep _arrive(double usd) => MoneyStep(
        id: arriveId,
        kind: MoneyStepKind.arrive,
        to: MoneyPlace.bitcoin,
        usd: _cents(usd),
      );

  /// The dependencies, from the legs as they stand: the purchase after
  /// every leg home to Dollars, the arrival after the purchase and every
  /// leg straight to Bitcoin. Steps keep their order: legs, purchase,
  /// arrival.
  static MoneyStepGraph _wire(MoneyStepGraph g) {
    final legs = [
      for (final s in g.steps)
        if (s.kind == MoneyStepKind.leg) s,
    ];
    final live = legs.where((s) => s.status != MoneyStepStatus.fellBack);
    final via = [
      for (final s in live)
        if (s.route != MoneyRoute.direct) s.id,
    ];
    final direct = [
      for (final s in live)
        if (s.route == MoneyRoute.direct) s.id,
    ];
    final buy = g.byId(buyId);
    final arrive = g.byId(arriveId);
    return MoneyStepGraph([
      ...legs,
      for (final s in g.steps)
        if (s.kind != MoneyStepKind.leg &&
            s.kind != MoneyStepKind.buy &&
            s.kind != MoneyStepKind.arrive)
          s,
      if (buy != null) buy.copyWith(after: via),
      if (arrive != null)
        arrive.copyWith(after: [if (buy != null) buyId, ...direct]),
    ]);
  }

  static String _freshId(String base, Set<String> used) {
    if (!used.contains(base)) return base;
    var n = 2;
    while (used.contains('$base:$n')) {
      n++;
    }
    return '$base:$n';
  }

  // ── Events ────────────────────────────────────────────────────────

  /// A leg was recorded (`MultiSourceMoveStore.addLeg`): it went (on its
  /// way, its Activity row id as `ref`) or it failed. A leg planned
  /// straight to Bitcoin that went home to Dollars instead falls back
  /// (kept, marked, its replacement right after it); a leg the graph did
  /// not plan (a Retry from another venue) is added. A Retry of a failed
  /// leg runs it again in place.
  static MoneyStepGraph legRecorded(MoneyStepGraph g, MultiSourceMoveLeg leg) {
    final place = placeOf(leg.venue);
    final route = leg.direct ? MoneyRoute.direct : MoneyRoute.viaDollars;
    final ref = leg.operationId ?? leg.quoteId;
    final active = g.steps
        .where((s) =>
            s.kind == MoneyStepKind.leg &&
            s.from == place &&
            s.status != MoneyStepStatus.fellBack)
        .lastOrNull;
    MoneyStep fresh(String id) => MoneyStep(
          id: id,
          kind: MoneyStepKind.leg,
          from: place,
          to: leg.direct ? MoneyPlace.bitcoin : MoneyPlace.dollars,
          usd: _cents(leg.usd),
          route: route,
          status: leg.ok ? MoneyStepStatus.running : MoneyStepStatus.failed,
          startedAt: leg.at,
          endedAt: leg.ok ? null : leg.at,
          reason: leg.ok ? null : (leg.error ?? 'error'),
          ref: ref,
        );
    final used = {for (final s in g.steps) s.id};

    // Not planned, or the venue's earlier leg already landed: a new leg.
    if (active == null || active.status == MoneyStepStatus.done) {
      final added = fresh(_freshId(legId(leg.venue), used));
      return _wire(MoneyStepGraph([...g.steps, added]));
    }
    if (!leg.ok) {
      return _wire(g.update(
          active.id,
          (s) => s.copyWith(
              status: MoneyStepStatus.failed,
              usd: _cents(leg.usd),
              endedAt: leg.at,
              reason: leg.error ?? 'error')));
    }
    if (active.route == MoneyRoute.direct && route == MoneyRoute.viaDollars) {
      // Refused straight to Bitcoin before anything moved: via Dollars.
      final replacement = fresh(_freshId('${active.id}:via_dollars', used));
      var next = g.fallBack(active.id, [replacement],
          reason: 'direct_refused', at: leg.at);
      if (next.byId(buyId) == null) {
        // Everything was to go straight to Bitcoin: now Dollars buy this
        // leg's part (the amount is set once every leg went).
        next = MoneyStepGraph([...next.steps, _buy(leg.arrivingUsd)]);
      }
      return _wire(next);
    }
    if (active.route != route) {
      // The other way round (a Retry under a new approval): the same leg,
      // to where it really goes.
      final moved = fresh(active.id);
      return _wire(MoneyStepGraph([
        for (final s in g.steps) s.id == active.id ? moved : s,
      ]));
    }
    return _wire(g.update(
        active.id,
        (s) => s.copyWith(
            status: MoneyStepStatus.running,
            usd: _cents(leg.usd),
            ref: ref,
            startedAt: s.startedAt ?? leg.at,
            clearEnd: true,
            clearReason: true)));
  }

  /// Every leg went: the purchase takes [usd] from Dollars. Nothing left
  /// to buy (every leg went straight to Bitcoin and Dollars gave nothing):
  /// the purchase is skipped.
  static MoneyStepGraph onward(MoneyStepGraph g, double usd) {
    final buy = g.byId(buyId);
    if (usd < 0.01) {
      if (buy == null || buy.status != MoneyStepStatus.waiting) return g;
      return g.update(
          buyId, (s) => s.copyWith(status: MoneyStepStatus.skipped));
    }
    if (buy == null) {
      return _wire(MoneyStepGraph([...g.steps, _buy(usd)]));
    }
    return g.update(
        buyId,
        (s) => s.copyWith(
            usd: _cents(usd),
            status: s.status == MoneyStepStatus.skipped
                ? MoneyStepStatus.waiting
                : null));
  }

  /// The purchase is asking its quote (nothing has left Dollars yet).
  static MoneyStepGraph buyStarted(MoneyStepGraph g, {DateTime? at}) =>
      g.byId(buyId) == null
          ? g
          : g.update(
              buyId,
              (s) => s.copyWith(
                  status: MoneyStepStatus.running,
                  startedAt: at,
                  clearEnd: true,
                  clearReason: true));

  /// The purchase's dollars were sent: its settlement operation follows
  /// it; it is done once its order is (read from its row).
  static MoneyStepGraph buySent(MoneyStepGraph g, String operationId,
          {DateTime? at}) =>
      g.byId(buyId) == null
          ? g
          : g.update(
              buyId,
              (s) => s.copyWith(
                  status: MoneyStepStatus.running,
                  startedAt: s.startedAt ?? at,
                  ref: operationId,
                  clearEnd: true,
                  clearReason: true));

  /// The purchase stopped before anything left Dollars ([reason], a fixed
  /// code: `needs_approval`, an error category): it waits on the person.
  static MoneyStepGraph buyStopped(MoneyStepGraph g, String reason,
      {DateTime? at}) {
    final buy = g.byId(buyId);
    // Once sent, the settlement owns it: a later stop never undoes that.
    if (buy == null || buy.ref != null) return g;
    return g.update(
        buyId,
        (s) => s.copyWith(
            status: MoneyStepStatus.failed, endedAt: at, reason: reason));
  }

  /// What came home landed: Dollars hold what the purchase takes, so every
  /// leg on its way to Dollars is done.
  static MoneyStepGraph dollarsLanded(MoneyStepGraph g, {DateTime? at}) =>
      MoneyStepGraph([
        for (final s in g.steps)
          s.kind == MoneyStepKind.leg &&
                  s.route != MoneyRoute.direct &&
                  s.status == MoneyStepStatus.running
              ? s.copyWith(status: MoneyStepStatus.done, endedAt: at)
              : s,
      ]);

  // ── Reading a record ──────────────────────────────────────────────

  /// [move]'s graph: the one on its record, or for a record made before
  /// the graph existed, its legs and purchase mapped onto steps
  /// ([fromRecord]). Empty for a move that is not a Buy bitcoin.
  static MoneyStepGraph of(MultiSourceMove move) {
    if (!describes(move)) return MoneyStepGraph.empty;
    return move.steps.isEmpty ? fromRecord(move) : move.steps;
  }

  /// A record without steps: each leg as it was recorded (on its way or
  /// failed), the purchase of what the direct legs did not bring (running
  /// once it was sent), then the arrival.
  static MoneyStepGraph fromRecord(MultiSourceMove move) {
    var g = MoneyStepGraph([_arrive(move.totalUsd)]);
    final legs = [...move.legs]..sort((a, b) => a.at.compareTo(b.at));
    for (final leg in legs) {
      g = legRecorded(g, leg);
    }
    final onwardUsd = math.max(0.0, move.totalUsd - move.directDeliveredUsd);
    g = onward(g, onwardUsd);
    final finalOp = move.finalOperationId;
    if (finalOp != null) {
      if (g.byId(buyId) == null) {
        g = _wire(MoneyStepGraph([...g.steps, _buy(onwardUsd)]));
      }
      g = buySent(g, finalOp);
    }
    return g;
  }

  // ── Recording on the move ─────────────────────────────────────────

  /// Applies [change] to move [moveId]'s graph and saves it, when the
  /// move is a Buy bitcoin. Best effort: a missing move is left alone.
  static void record(
      String? moveId, MoneyStepGraph Function(MoneyStepGraph g) change) {
    if (moveId == null) return;
    MultiSourceMoveStore.updateSteps(moveId, (move) {
      if (!describes(move)) return null;
      return change(of(move));
    });
  }

  static double _cents(double usd) => (usd * 100).round() / 100;
}
