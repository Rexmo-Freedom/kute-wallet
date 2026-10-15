// lib/providers/portfolio_rebalance_provider.dart
//
// The Portfolio's Rebalance (founder request, October 2026: "a button to
// rebalance, moves it all to USDB"). Not a money path of its own: one tap
// is one manual pass of the venue sweeper (`VenueSweeper.sweepNow`,
// trigger `manual_rebalance`), the 24 h idle wait set aside and every
// other never-sweep rule kept, through the same rails under the same
// `SweepAuthorization.automatic` (the wallet's own Spark address, an
// unlocked session) with the same `venue_sweep_*` events and Activity
// rows. No Face ID: the money only goes home to the person's own Dollars.
//
// This notifier holds what the Portfolio shows about the tap: the busy
// state while the pass runs, then what each venue did, for the one-line
// notes under the venue rows, and the tap as its steps
// (rebalance_steps.dart): one line per venue whose cash goes home, all at
// once, each completing on its own. The steps are kept with the last tap
// (`portfolio_rebalance_steps_v1`), so they read again after a restart.

import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable, mapEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/rebalance_steps.dart';
import 'package:kute/services/one_balance/sweep_rules.dart'
    show kSweepDustUsd;
import 'package:kute/services/tracking_service.dart';

/// How long the notes a Rebalance left under the venue rows stay up.
const Duration kRebalanceNoteFor = Duration(minutes: 10);

/// How long a submitted move reads "Moving to USDB…" on the tap alone,
/// before the Orchestra row that carries it is listed.
const Duration kRebalanceMovingGrace = Duration(minutes: 2);

@immutable
class PortfolioRebalanceState {
  const PortfolioRebalanceState({
    this.running = false,
    this.outcomes = const <OneBalanceVenue, RebalanceOutcome>{},
    this.at,
    this.steps = MoneyStepGraph.empty,
    this.stepsAt,
  });

  /// The pass is running (the button's busy state).
  final bool running;

  /// What the last tap did at each venue.
  final Map<OneBalanceVenue, RebalanceOutcome> outcomes;

  /// When the last tap's pass finished.
  final DateTime? at;

  /// The last tap as its steps (rebalance_steps.dart): one leg per venue
  /// whose cash goes home, as recorded (the rows bring it up to date
  /// where it is shown).
  final MoneyStepGraph steps;

  /// When the last tap was made (the steps' start).
  final DateTime? stepsAt;

  /// The last tap's outcome for [venue] while its note is still up.
  RebalanceOutcome? outcomeAt(OneBalanceVenue venue, DateTime now) {
    final when = at;
    if (when == null || now.difference(when) > kRebalanceNoteFor) return null;
    return outcomes[venue];
  }

  @override
  bool operator ==(Object other) =>
      other is PortfolioRebalanceState &&
      other.running == running &&
      other.at == at &&
      other.stepsAt == stepsAt &&
      mapEquals(other.outcomes, outcomes) &&
      jsonEncode(other.steps.toJson()) == jsonEncode(steps.toJson());

  @override
  int get hashCode => Object.hash(running, at, stepsAt,
      Object.hashAll(outcomes.entries.map((e) => Object.hash(e.key, e.value))));
}

class PortfolioRebalanceNotifier extends Notifier<PortfolioRebalanceState> {
  @override
  PortfolioRebalanceState build() {
    // The last tap's steps, kept across a restart: the Portfolio follows
    // their rows from there.
    final kept = RebalanceStepsStore.load(DateTime.now());
    return kept == null
        ? const PortfolioRebalanceState()
        : PortfolioRebalanceState(steps: kept.steps, stepsAt: kept.at);
  }

  /// One tap: the amounts are the rows' figures as the person saw them
  /// (`portfolio_rebalance_tapped`, exact). A second tap while the pass
  /// runs does nothing; the sweeper itself never runs two passes at once.
  Future<void> rebalance({
    required double dollarsUsd,
    required double investingUsd,
    required double predictionsUsd,
  }) async {
    if (state.running) return;
    // Every venue with cash a Rebalance can move is on its way home from
    // the tap, all at once.
    final tappedAt = DateTime.now();
    var steps = MoneyStepGraph.empty;
    try {
      steps = RebalanceSteps.planned(ref.read(venueSweeperProvider).movable,
          minUsd: kSweepDustUsd, at: tappedAt);
    } catch (_) {/* the steps never stop the money */}
    RebalanceStepsStore.save(tappedAt, steps);
    state = PortfolioRebalanceState(
        running: true, steps: steps, stepsAt: tappedAt);
    TrackingService.track('portfolio_rebalance_tapped', params: {
      ...TrackingService.exactUsd('dollars_usd', dollarsUsd),
      ...TrackingService.exactUsd('investing_usd', investingUsd),
      ...TrackingService.exactUsd('predictions_usd', predictionsUsd),
    });
    var outcomes = const <OneBalanceVenue, RebalanceOutcome>{};
    try {
      outcomes = await ref.read(venueSweeperProvider.notifier).rebalance();
    } catch (_) {
      // The sweeper reports its own failures (`venue_sweep_failed`) and
      // retries on its backoff; the rows show what stayed.
    } finally {
      final at = DateTime.now();
      try {
        steps = RebalanceSteps.outcomes(steps, outcomes, at: at);
      } catch (_) {}
      RebalanceStepsStore.save(tappedAt, steps);
      state = PortfolioRebalanceState(
          outcomes: outcomes, at: at, steps: steps, stepsAt: tappedAt);
    }
  }
}

final portfolioRebalanceProvider =
    NotifierProvider<PortfolioRebalanceNotifier, PortfolioRebalanceState>(
        PortfolioRebalanceNotifier.new);
