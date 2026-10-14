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
// notes under the venue rows.

import 'package:flutter/foundation.dart' show immutable, mapEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
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
  });

  /// The pass is running (the button's busy state).
  final bool running;

  /// What the last tap did at each venue.
  final Map<OneBalanceVenue, RebalanceOutcome> outcomes;

  /// When the last tap's pass finished.
  final DateTime? at;

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
      mapEquals(other.outcomes, outcomes);

  @override
  int get hashCode => Object.hash(running, at,
      Object.hashAll(outcomes.entries.map((e) => Object.hash(e.key, e.value))));
}

class PortfolioRebalanceNotifier extends Notifier<PortfolioRebalanceState> {
  @override
  PortfolioRebalanceState build() => const PortfolioRebalanceState();

  /// One tap: the amounts are the rows' figures as the person saw them
  /// (`portfolio_rebalance_tapped`, exact). A second tap while the pass
  /// runs does nothing; the sweeper itself never runs two passes at once.
  Future<void> rebalance({
    required double dollarsUsd,
    required double investingUsd,
    required double predictionsUsd,
  }) async {
    if (state.running) return;
    state = const PortfolioRebalanceState(running: true);
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
      state = PortfolioRebalanceState(outcomes: outcomes, at: DateTime.now());
    }
  }
}

final portfolioRebalanceProvider =
    NotifierProvider<PortfolioRebalanceNotifier, PortfolioRebalanceState>(
        PortfolioRebalanceNotifier.new);
