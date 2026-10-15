// lib/services/one_balance/move_steps.dart
//
// Every move as its step graph ([MoneyStepGraph], money_steps.dart): the
// same model, the same widget and the same words for every way money
// moves between the person's own balances (founder, 15 October 2026:
// "same thing on the moving money same progress things"). Each leg is its
// own line and completes on its own; a step waits only on what it really
// needs.
//
// A multi-source move (`MultiSourceMove`, multi_source_move.dart) keeps
// its graph on its record. By what it is for:
//
//   Buy bitcoin (to Bitcoin):
//     leg:investing   Investing → Bitcoin      (direct)
//     leg:predictions Predictions → Dollars    (via Dollars)
//     buy             Buying $8 of Bitcoin     after the legs via Dollars
//     arrive          Arriving in Bitcoin      after buy + direct legs
//
//   Send (from Dollars, the shortfall from Investments):
//     leg:predictions Predictions → Dollars
//     leg:investing   Investing → Dollars
//     send            Sending $50              after every leg
//
//   Into a venue (Predictions ↔ Investing, an order's money):
//     leg:investing   Investing → Predictions  (direct)
//       or            Investing → Dollars      (via Dollars)
//     onward          Dollars → Predictions    after the legs via Dollars
//
//   Home to Dollars (no step of its own): the legs alone.
//
// The record follows the events the money code already has, never
// deciding anything itself: the puller's plan (every leg running: they
// go at once), each leg recorded (on its way with its Activity row id,
// failed, or fallen back to Dollars), what the action's own step takes
// from Dollars, the money that came home landing, and the action's own
// step quoting, sent (`MultiSourceMoveStore.attachFinal`) or stopped.
// What lands later (a row settling, the bitcoin counted) is read where
// the graph is shown (move_steps_view.dart).
//
// A record made before the graph existed maps its legs and its own step
// onto steps when read ([MoveSteps.of]). A failed leg that a Retry has
// since covered (from another venue: the move is no longer partial) is
// kept as failed for the record but no step waits on it any more
// ([replacedReason]): nothing stays waiting forever.
//
// A single move with no record of its own (Add to Investments from
// Bitcoin, a purchase paid by Dollars alone, a venue's cash going home on
// a Rebalance) is one Activity row; its graph is read from that row
// ([MoveSteps.ofRow]), which the wallet keeps, so a restart reads the
// same lines.
//
// Local only: balance names, dollar amounts and the ids the wallet's own
// rows already carry. Nothing here is tracked.

import 'dart:math' as math;

import 'package:kute/helpers/orchestra_router.dart' show orchestraRowAmount;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_funder.dart'
    show VenueCashDestination;
import 'package:kute/services/orchestra/own_spark_arrivals.dart'
    show OwnSparkArrivals;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;

/// One planned venue leg: [usd] leaves [venue], straight to the move's
/// destination when [direct], home to Dollars otherwise.
typedef MovePlannedLeg = ({
  OneBalanceVenue venue,
  double usd,
  bool direct,
});

abstract final class MoveSteps {
  /// Dollars buying bitcoin (a move to Bitcoin).
  static const String buyId = 'buy';

  /// The bitcoin landing in the wallet (a move to Bitcoin).
  static const String arriveId = 'arrive';

  /// The send itself, from Dollars (a send).
  static const String sendId = 'send';

  /// Dollars' part going on into the venue (a move into a venue).
  static const String onwardId = 'onward';

  /// The action's own step, after the legs: at most one per graph.
  static const Set<String> finalIds = {buyId, sendId, onwardId};

  /// The reason a failed leg carries once a Retry covered it: kept on the
  /// record, waited on by nothing.
  static const String replacedReason = 'replaced';

  /// The `for` of a send (`VenueCashFor.send`).
  static const String sendFor = 'send';

  static String legId(OneBalanceVenue venue) => 'leg:${venue.name}';

  /// Whether [s] is a venue's leg (not the action's own step).
  static bool isVenueLeg(MoneyStep s) =>
      s.kind == MoneyStepKind.leg && s.id.startsWith('leg:');

  static MoneyPlace placeOf(OneBalanceVenue venue) => switch (venue) {
        OneBalanceVenue.predictions => MoneyPlace.predictions,
        OneBalanceVenue.investing => MoneyPlace.investing,
      };

  static MoneyPlace placeOfDestination(VenueCashDestination d) => switch (d) {
        VenueCashDestination.dollars => MoneyPlace.dollars,
        VenueCashDestination.bitcoin => MoneyPlace.bitcoin,
        VenueCashDestination.predictions => MoneyPlace.predictions,
        VenueCashDestination.investing => MoneyPlace.investing,
      };

  /// The id of the action's own step for a move to [destination] for
  /// [forAction]: the send, the purchase, Dollars going on into the
  /// venue; null when the legs are the whole move (home to Dollars).
  static String? finalIdFor(
      VenueCashDestination destination, String forAction) {
    if (forAction == sendFor) return sendId;
    return switch (destination) {
      VenueCashDestination.bitcoin => buyId,
      VenueCashDestination.predictions ||
      VenueCashDestination.investing =>
        onwardId,
      VenueCashDestination.dollars => null,
    };
  }

  /// The action's own step, as [id] names it, taking [usd] from Dollars.
  static MoneyStep finalStep(
          String id, VenueCashDestination destination, double usd) =>
      switch (id) {
        buyId => MoneyStep(
            id: buyId,
            kind: MoneyStepKind.buy,
            from: MoneyPlace.dollars,
            to: MoneyPlace.bitcoin,
            usd: _cents(usd),
          ),
        // Leaves the wallet: no balance of the person's receives it.
        sendId => MoneyStep(
            id: sendId,
            kind: MoneyStepKind.leg,
            from: MoneyPlace.dollars,
            usd: _cents(usd),
            route: MoneyRoute.direct,
          ),
        _ => MoneyStep(
            id: onwardId,
            kind: MoneyStepKind.leg,
            from: MoneyPlace.dollars,
            to: placeOfDestination(destination),
            usd: _cents(usd),
            route: MoneyRoute.direct,
          ),
      };

  static MoneyStep _arrive(double usd) => MoneyStep(
        id: arriveId,
        kind: MoneyStepKind.arrive,
        to: MoneyPlace.bitcoin,
        usd: _cents(usd),
      );

  /// The action's own step in [g], if any.
  static MoneyStep? finalOf(MoneyStepGraph g) =>
      g.steps.where((s) => finalIds.contains(s.id)).firstOrNull;

  // ── Building ──────────────────────────────────────────────────────

  /// The graph of a move to [destination] for [forAction] about to run
  /// [legs] (in plan order), whose own step takes [onwardUsd] from
  /// Dollars, for [totalUsd] in all. The legs are running from [at]: they
  /// all go at once.
  static MoneyStepGraph planned({
    required VenueCashDestination destination,
    required String forAction,
    required List<MovePlannedLeg> legs,
    required double onwardUsd,
    required double totalUsd,
    DateTime? at,
  }) {
    final steps = <MoneyStep>[];
    final used = <String>{};
    final dest = placeOfDestination(destination);
    for (final l in legs) {
      final direct = l.direct && destination != VenueCashDestination.dollars;
      final id = _freshId(legId(l.venue), used);
      used.add(id);
      steps.add(MoneyStep(
        id: id,
        kind: MoneyStepKind.leg,
        from: placeOf(l.venue),
        to: direct ? dest : MoneyPlace.dollars,
        usd: _cents(l.usd),
        route: direct ? MoneyRoute.direct : MoneyRoute.viaDollars,
        status: MoneyStepStatus.running,
        startedAt: at,
      ));
    }
    final fin = finalIdFor(destination, forAction);
    if (fin != null && onwardUsd >= 0.01) {
      steps.add(finalStep(fin, destination, onwardUsd));
    }
    if (destination == VenueCashDestination.bitcoin) {
      steps.add(_arrive(totalUsd));
    }
    return _wire(MoneyStepGraph(steps));
  }

  /// The dependencies, from the legs as they stand: the action's own step
  /// after every leg home to Dollars, the arrival after it and every leg
  /// straight to Bitcoin. A leg that fell back or that a Retry replaced is
  /// waited on by nothing. Steps keep their order: legs, the own step,
  /// the arrival.
  static MoneyStepGraph _wire(MoneyStepGraph g) {
    final legs = [
      for (final s in g.steps)
        if (isVenueLeg(s)) s,
    ];
    final live = legs.where((s) =>
        s.status != MoneyStepStatus.fellBack &&
        !(s.status == MoneyStepStatus.failed && s.reason == replacedReason));
    final via = [
      for (final s in live)
        if (s.route != MoneyRoute.direct) s.id,
    ];
    final direct = [
      for (final s in live)
        if (s.route == MoneyRoute.direct) s.id,
    ];
    final fin = finalOf(g);
    final arrive = g.byId(arriveId);
    return MoneyStepGraph([
      ...legs,
      for (final s in g.steps)
        if (!isVenueLeg(s) && !finalIds.contains(s.id) && s.id != arriveId) s,
      if (fin != null) fin.copyWith(after: via),
      if (arrive != null)
        arrive.copyWith(after: [if (fin != null) fin.id, ...direct]),
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

  /// A leg of a move to [destination] for [forAction] was recorded
  /// (`MultiSourceMoveStore.addLeg`): it went (on its way, its Activity
  /// row id as `ref`) or it failed. A leg planned straight to the
  /// destination that went home to Dollars instead falls back (kept,
  /// marked, its replacement right after it); a leg the graph did not plan
  /// (a Retry from another venue, or from a venue whose leg already went)
  /// is added. A Retry of a failed leg runs it again in place.
  static MoneyStepGraph legRecorded(
    MoneyStepGraph g,
    MultiSourceMoveLeg leg, {
    required VenueCashDestination destination,
    required String forAction,
  }) {
    final place = placeOf(leg.venue);
    final route = leg.direct ? MoneyRoute.direct : MoneyRoute.viaDollars;
    final ref = leg.operationId ?? leg.quoteId;
    final active = g.steps
        .where((s) =>
            isVenueLeg(s) &&
            s.from == place &&
            s.status != MoneyStepStatus.fellBack)
        .lastOrNull;
    MoneyStep fresh(String id) => MoneyStep(
          id: id,
          kind: MoneyStepKind.leg,
          from: place,
          to: leg.direct ? placeOfDestination(destination) : MoneyPlace.dollars,
          usd: _cents(leg.usd),
          route: route,
          status: leg.ok ? MoneyStepStatus.running : MoneyStepStatus.failed,
          startedAt: leg.at,
          endedAt: leg.ok ? null : leg.at,
          reason: leg.ok ? null : (leg.error ?? 'error'),
          ref: ref,
        );
    final used = {for (final s in g.steps) s.id};

    // Not planned, the venue's earlier leg already landed, or it already
    // went as another leg (a Retry from a venue whose first leg is still
    // on its way): a new leg. A failed leg is run again in place.
    if (active == null ||
        active.status == MoneyStepStatus.done ||
        (active.ref != null &&
            active.ref != ref &&
            active.status != MoneyStepStatus.failed)) {
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
      // Refused straight to the destination before anything moved: via
      // Dollars.
      final replacement = fresh(_freshId('${active.id}:via_dollars', used));
      var next = g.fallBack(active.id, [replacement],
          reason: leg.fellBack ?? 'direct_refused', at: leg.at);
      final fin = finalIdFor(destination, forAction);
      if (fin != null && finalOf(next) == null) {
        // Everything was to go straight there: now Dollars carry this
        // leg's part on (the amount is set once every leg went).
        next = MoneyStepGraph(
            [...next.steps, finalStep(fin, destination, leg.arrivingUsd)]);
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

  /// Every leg went: the action's own step takes [usd] from Dollars.
  /// Nothing left for it (every leg went straight to the destination and
  /// Dollars gave nothing): it is skipped. A move with no own step (home
  /// to Dollars) is left alone.
  static MoneyStepGraph onward(
    MoneyStepGraph g,
    double usd, {
    required VenueCashDestination destination,
    required String forAction,
  }) {
    final existing = finalOf(g);
    final id = existing?.id ?? finalIdFor(destination, forAction);
    if (id == null) return g;
    if (usd < 0.01) {
      if (existing == null || existing.status != MoneyStepStatus.waiting) {
        return g;
      }
      return g.update(id, (s) => s.copyWith(status: MoneyStepStatus.skipped));
    }
    if (existing == null) {
      return _wire(
          MoneyStepGraph([...g.steps, finalStep(id, destination, usd)]));
    }
    return g.update(
        id,
        (s) => s.copyWith(
            usd: _cents(usd),
            status: s.status == MoneyStepStatus.skipped
                ? MoneyStepStatus.waiting
                : null));
  }

  /// The action's own step is asking its quote (nothing has left Dollars
  /// yet).
  static MoneyStepGraph finalStarted(MoneyStepGraph g, {DateTime? at}) {
    final fin = finalOf(g);
    if (fin == null) return g;
    return g.update(
        fin.id,
        (s) => s.copyWith(
            status: MoneyStepStatus.running,
            startedAt: at,
            clearEnd: true,
            clearReason: true));
  }

  /// The action's own step went: its settlement operation follows it; it
  /// is done once its row is (read from the row).
  static MoneyStepGraph finalSent(MoneyStepGraph g, String operationId,
      {DateTime? at}) {
    final fin = finalOf(g);
    if (fin == null) return g;
    return g.update(
        fin.id,
        (s) => s.copyWith(
            status: MoneyStepStatus.running,
            startedAt: s.startedAt ?? at,
            ref: operationId,
            clearEnd: true,
            clearReason: true));
  }

  /// The action's own step stopped before anything left Dollars ([reason],
  /// a fixed code: `needs_approval`, an error category): it waits on the
  /// person.
  static MoneyStepGraph finalStopped(MoneyStepGraph g, String reason,
      {DateTime? at}) {
    final fin = finalOf(g);
    // Once sent, the settlement owns it: a later stop never undoes that.
    if (fin == null || fin.ref != null) return g;
    return g.update(
        fin.id,
        (s) => s.copyWith(
            status: MoneyStepStatus.failed, endedAt: at, reason: reason));
  }

  /// What came home landed: Dollars hold what the action's own step
  /// takes, so every leg on its way to Dollars is done.
  static MoneyStepGraph dollarsLanded(MoneyStepGraph g, {DateTime? at}) =>
      MoneyStepGraph([
        for (final s in g.steps)
          isVenueLeg(s) &&
                  s.route != MoneyRoute.direct &&
                  s.status == MoneyStepStatus.running
              ? s.copyWith(status: MoneyStepStatus.done, endedAt: at)
              : s,
      ]);

  /// [g] for [move] as it stands: a failed leg is waited on only while the
  /// move is partial (its Retry is still owed); once a Retry covered the
  /// remainder (from any venue), it is marked [replacedReason] and nothing
  /// waits on it, so the own step and the arrival are never stuck behind
  /// it. Kept as failed, for the record. (A move is never partial again
  /// once covered: only a Retry adds legs, and only to a partial move.)
  static MoneyStepGraph reconcile(MultiSourceMove move, MoneyStepGraph g) {
    if (move.partial) return g;
    var changed = false;
    final out = <MoneyStep>[];
    for (final s in g.steps) {
      if (isVenueLeg(s) &&
          s.status == MoneyStepStatus.failed &&
          s.reason != replacedReason) {
        out.add(s.copyWith(reason: replacedReason));
        changed = true;
        continue;
      }
      out.add(s);
    }
    return changed ? _wire(MoneyStepGraph(out)) : g;
  }

  // ── Reading a record ──────────────────────────────────────────────

  /// [move]'s graph: the one on its record, or for a record made before
  /// the graph existed, its legs and own step mapped onto steps
  /// ([fromRecord]); either way [reconcile]d with the record.
  static MoneyStepGraph of(MultiSourceMove move) =>
      reconcile(move, move.steps.isEmpty ? fromRecord(move) : move.steps);

  /// A record without steps: each leg as it was recorded (on its way or
  /// failed), the action's own step (running once it was sent), then the
  /// arrival for a move to Bitcoin.
  static MoneyStepGraph fromRecord(MultiSourceMove move) {
    final destination = move.destination;
    final forAction = move.forAction;
    var g = MoneyStepGraph([
      if (destination == VenueCashDestination.bitcoin) _arrive(move.totalUsd),
    ]);
    final legs = [...move.legs]..sort((a, b) => a.at.compareTo(b.at));
    for (final leg in legs) {
      g = legRecorded(g, leg, destination: destination, forAction: forAction);
    }
    final fin = finalIdFor(destination, forAction);
    if (fin == null) return g;
    final onwardUsd = destination == VenueCashDestination.dollars
        ? move.totalUsd
        : math.max(0.0, move.totalUsd - move.directDeliveredUsd);
    g = onward(g, onwardUsd, destination: destination, forAction: forAction);
    final finalOp = move.finalOperationId;
    if (finalOp != null) {
      if (finalOf(g) == null) {
        g = _wire(MoneyStepGraph(
            [...g.steps, finalStep(fin, destination, onwardUsd)]));
      }
      g = finalSent(g, finalOp);
    }
    return g;
  }

  // ── Recording on the move ─────────────────────────────────────────

  /// Applies [change] to move [moveId]'s graph and saves it. Best effort:
  /// a missing move is left alone, and the steps never stop the money.
  static void record(
      String? moveId, MoneyStepGraph Function(MoneyStepGraph g) change) {
    if (moveId == null) return;
    MultiSourceMoveStore.updateSteps(moveId, (move) => change(of(move)));
  }

  // ── A single move, from its row ───────────────────────────────────

  /// The balance [coin] on [network] is, when it is one of the person's
  /// own: Bitcoin and Dollars on Spark, Predictions' dollars on Polygon,
  /// Investing's on HyperCore. Null for anything else.
  static MoneyPlace? placeOfAsset(String coin, String network) {
    final c = coin.toUpperCase();
    final n = network.toUpperCase();
    final dollar = c == 'USDC' ||
        c == 'USDC.E' ||
        c == 'PUSD' ||
        c == kOrchestraUsdAssetCode.toUpperCase();
    return switch (n) {
      'SPARK' when c == 'BTC' => MoneyPlace.bitcoin,
      'SPARK' when c == kOrchestraUsdAssetCode.toUpperCase() =>
        MoneyPlace.dollars,
      'POLYGON' when dollar => MoneyPlace.predictions,
      'HYPERCORE' when dollar => MoneyPlace.investing,
      _ => null,
    };
  }

  /// [row]'s graph when it is a move between two of the person's own
  /// balances (an Orchestra order): Dollars buying Bitcoin is the
  /// purchase, then the arrival; anything else one leg ("Moving $5.00
  /// from Bitcoin → Dollars"), then the arrival when Bitcoin receives it.
  /// Its statuses are the row's: running while it is on its way, done
  /// once it settled, failed when its order did; the arrival runs while
  /// the wallet has not counted the bitcoin yet ([counting]). Empty for
  /// any other row (a send, a receive, a Cash App purchase).
  static MoneyStepGraph ofRow(SwapOrder row, {bool counting = false}) {
    if (!row.isOrchestra ||
        row.activityDirection == 'send' ||
        row.isCashAppPurchase) {
      return MoneyStepGraph.empty;
    }
    final from = placeOfAsset(row.coinFrom, row.networkFrom);
    final to = placeOfAsset(row.coinTo, row.networkTo);
    if (from == null || to == null || from == to) return MoneyStepGraph.empty;
    final usd = _cents(from == MoneyPlace.bitcoin
        ? orchestraRowAmount(row.withdrawalAmount, row.coinTo)
        : orchestraRowAmount(row.depositAmount, row.coinFrom));
    final status = row.isComplete
        ? MoneyStepStatus.done
        : OwnSparkArrivals.failedStatuses.contains(row.status)
            ? MoneyStepStatus.failed
            : MoneyStepStatus.running;
    final at = DateTime.fromMillisecondsSinceEpoch(row.timestamp);
    final buys = from == MoneyPlace.dollars && to == MoneyPlace.bitcoin;
    final first = MoneyStep(
      id: buys ? buyId : 'leg:${from.name}',
      kind: buys ? MoneyStepKind.buy : MoneyStepKind.leg,
      from: from,
      to: to,
      usd: usd,
      route: buys ? null : MoneyRoute.direct,
      status: status,
      startedAt: at,
      reason: status == MoneyStepStatus.failed ? 'order_failed' : null,
      ref: row.operationId ?? row.id,
    );
    if (to != MoneyPlace.bitcoin) return MoneyStepGraph([first]);
    return MoneyStepGraph([
      first,
      MoneyStep(
        id: arriveId,
        kind: MoneyStepKind.arrive,
        to: MoneyPlace.bitcoin,
        usd: usd,
        after: [first.id],
        status: status == MoneyStepStatus.done
            ? (counting ? MoneyStepStatus.running : MoneyStepStatus.done)
            : MoneyStepStatus.waiting,
      ),
    ]);
  }

  static double _cents(double usd) => (usd * 100).round() / 100;
}
