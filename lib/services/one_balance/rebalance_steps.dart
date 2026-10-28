// lib/services/one_balance/rebalance_steps.dart
//
// The Portfolio's Rebalance as its step graph ([MoneyStepGraph],
// money_steps.dart), the same model and the same lines as every other
// move: one leg per venue whose cash goes home, all at once, none waiting
// on another, each completing on its own when its row lands in Dollars:
//
//   leg:investing   Moving $12.00 from Investing → Dollars
//   leg:predictions Moving $5.00 from Predictions → Dollars
//
// It follows what the Rebalance already knows, never deciding anything:
// the venues with cash a Rebalance can move at the tap (every leg running:
// the pass sends them together), then what the pass did at each venue
// (`RebalanceOutcome`: sent, with the move's settlement operation as the
// leg's `ref`; held, below the minimum or nothing: not shown; not now:
// it did not move), then each move's Activity row settling.
//
// The last Rebalance's graph is kept in the settings box
// ([RebalanceStepsStore], `portfolio_rebalance_steps_v1`), so the
// Portfolio shows it again after a restart and follows the rows from
// there. Local only: venue names, dollar amounts, the ids the wallet's own
// rows already carry. Nothing here is tracked.

import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/move_steps.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_sweeper.dart'
    show RebalanceOutcome, RebalanceOutcomeKind;
import 'package:kute/services/orchestra/own_spark_arrivals.dart'
    show OwnSparkArrivals;

abstract final class RebalanceSteps {
  /// The order the Portfolio shows the venues in.
  static const List<OneBalanceVenue> order = [
    OneBalanceVenue.investing,
    OneBalanceVenue.predictions,
  ];

  static MoneyStep _leg(OneBalanceVenue venue, double usd, DateTime? at) =>
      MoneyStep(
        id: MoveSteps.legId(venue),
        kind: MoneyStepKind.leg,
        from: MoveSteps.placeOf(venue),
        to: MoneyPlace.dollars,
        usd: _cents(usd),
        route: MoneyRoute.viaDollars,
        status: MoneyStepStatus.running,
        startedAt: at,
      );

  /// The tap: every venue with cash a Rebalance can move ([movable], at
  /// least [minUsd]) is on its way home, all at once.
  static MoneyStepGraph planned(Map<OneBalanceVenue, double> movable,
          {double minUsd = 0.01, DateTime? at}) =>
      MoneyStepGraph([
        for (final v in order)
          if ((movable[v] ?? 0) >= minUsd) _leg(v, movable[v]!, at),
      ]);

  /// What the pass did at each venue: a move sent goes on (what it sent,
  /// its row's settlement operation); one that did not go is failed
  /// ([RebalanceOutcomeKind.notNow]); a venue a rule held, below the
  /// minimum, empty, or whose move was already on its way before the tap
  /// (its tile says so) is not shown, nor one the pass did not answer for.
  /// A move sent from a venue the tap did not expect is added.
  static MoneyStepGraph outcomes(
      MoneyStepGraph g, Map<OneBalanceVenue, RebalanceOutcome> outcomes,
      {DateTime? at}) {
    var out = g;
    for (final v in order) {
      final o = outcomes[v];
      if (o == null) continue;
      final id = MoveSteps.legId(v);
      final step = out.byId(id);
      switch (o.kind) {
        case RebalanceOutcomeKind.moving:
          if (step == null) {
            out = MoneyStepGraph([
              ...out.steps,
              _leg(v, o.usd, at).copyWith(ref: o.ref),
            ]);
          } else {
            out = out.update(
                id,
                (s) => s.copyWith(
                    status: MoneyStepStatus.running,
                    usd: o.usd > 0 ? _cents(o.usd) : null,
                    ref: o.ref));
          }
        case RebalanceOutcomeKind.notNow:
          if (step != null) {
            out = out.update(
                id,
                (s) => s.copyWith(
                    status: MoneyStepStatus.failed,
                    endedAt: at,
                    reason: 'not_now'));
          }
        case RebalanceOutcomeKind.alreadyMoving:
        case RebalanceOutcomeKind.held:
        case RebalanceOutcomeKind.belowMinimum:
        case RebalanceOutcomeKind.nothing:
        case RebalanceOutcomeKind.unknown:
          if (step != null) {
            out = out.update(
                id,
                (s) =>
                    s.copyWith(status: MoneyStepStatus.skipped, endedAt: at));
          }
      }
    }
    // A venue the pass did not answer for: nothing known moved.
    final answered = {
      for (final v in outcomes.keys) MoveSteps.legId(v),
    };
    return MoneyStepGraph([
      for (final s in out.steps)
        s.status == MoneyStepStatus.running && !answered.contains(s.id)
            ? s.copyWith(status: MoneyStepStatus.skipped, endedAt: at)
            : s,
    ]);
  }

  /// Whether [row] is the row of the move [ref] names.
  static bool rowOf(SwapOrder row, String ref) =>
      row.operationId == ref || row.id == ref || row.id == 'cctp-$ref';

  /// [g] brought up to date from [rows]: a leg on its way is done once
  /// its row settled (or the Portfolio saw its venue's money land:
  /// [landed]), failed when its order failed. Never moves a leg back.
  static MoneyStepGraph live(MoneyStepGraph g, List<SwapOrder> rows,
      {Set<OneBalanceVenue> landed = const {}}) {
    var out = g;
    for (final s in g.steps) {
      if (s.status != MoneyStepStatus.running) continue;
      final ref = s.ref;
      final mine = ref == null
          ? const <SwapOrder>[]
          : [
              for (final r in rows)
                if (rowOf(r, ref)) r,
            ];
      final venue =
          order.where((v) => MoveSteps.placeOf(v) == s.from).firstOrNull;
      if (mine.any((r) => r.isComplete) ||
          (venue != null && landed.contains(venue))) {
        out = out.update(s.id, (x) => x.copyWith(status: MoneyStepStatus.done));
      } else if (mine.isNotEmpty &&
          mine.every(
              (r) => OwnSparkArrivals.failedStatuses.contains(r.status))) {
        out = out.update(
            s.id,
            (x) => x.copyWith(
                status: MoneyStepStatus.failed, reason: 'order_failed'));
      }
    }
    return out;
  }

  static double _cents(double usd) => (usd * 100).round() / 100;
}

/// The last Rebalance's graph, in the settings box (best effort: nothing
/// is kept when the box is not open).
abstract final class RebalanceStepsStore {
  static const String key = 'portfolio_rebalance_steps_v1';

  /// How long a kept graph is read back: the rows it follows are stuck
  /// orders after this (`kVenueMoveMaxAge`).
  static const Duration keepFor = Duration(minutes: 30);

  static void save(DateTime at, MoneyStepGraph steps) {
    try {
      if (!Hive.isBoxOpen('settings')) return;
      Hive.box('settings').put(
          key,
          jsonEncode({
            'at': at.millisecondsSinceEpoch,
            'steps': steps.toJson(),
          }));
    } catch (_) {/* best effort */}
  }

  /// The graph kept at [now], with when it started; null when none is
  /// kept or it is older than [keepFor].
  static ({DateTime at, MoneyStepGraph steps})? load(DateTime now) {
    try {
      if (!Hive.isBoxOpen('settings')) return null;
      final raw = Hive.box('settings').get(key);
      if (raw is! String) return null;
      final v = jsonDecode(raw);
      if (v is! Map || v['at'] is! int) return null;
      final at = DateTime.fromMillisecondsSinceEpoch(v['at'] as int);
      if (now.difference(at) > keepFor) return null;
      final steps = MoneyStepGraph.fromJson(v['steps']);
      return steps.isEmpty ? null : (at: at, steps: steps);
    } catch (_) {
      return null;
    }
  }
}
