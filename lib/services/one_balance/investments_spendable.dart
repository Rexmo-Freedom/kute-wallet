// lib/services/one_balance/investments_spendable.dart
//
// "What can Investments spend right now?" for the amount screens that pay
// out of Investments through the venue-cash engine (Buy bitcoin from
// Investments in the Move sheet, the Dollars send): Dollars plus the
// venue cash the engine can reach (venue_cash_source.dart), never the
// positions. The same "Available" the Investments header shows.
//
//  * [investmentsSpendable] is the pure figure: the total on the From row
//    (Dollars + reachable venue cash) and the Max, which is that total
//    less the planned move costs, checked against the engine's own plan
//    ([planDollarsShortfall]) so Max is always an amount it can execute.
//  * The figure is instant: it reads the engine's LAST venue read
//    ([venueCashLastReadProvider], kept for the app's life), else the
//    one-balance picture's venue cash ([venueCashSeedProvider]), else
//    Dollars alone (a cold start). [venueCashRefreshProvider] reads the
//    venues again in the background while a screen shows the figure and
//    the number follows when it changes: no spinner, no loading text.
//
// Nothing here moves money.

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/one_balance_provider.dart'
    show oneBalanceProvider;
import 'package:kute/providers/settings_provider.dart' show settingsProvider;
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/route_minimums.dart'
    show venueFloorUsd;
import 'package:kute/services/one_balance/venue_cash_source.dart';

/// What Investments can spend, split the way the From row needs it.
@immutable
class InvestmentsSpendable {
  const InvestmentsSpendable({
    required this.dollarsUsd,
    required this.venueCashUsd,
    required this.maxUsd,
  });

  /// The spending account's Dollars.
  final double dollarsUsd;

  /// Venue cash the engine can bring into a purchase or a send (each
  /// venue's free cash that clears its route minimum), before costs.
  final double venueCashUsd;

  /// The most an action can ask for: Dollars plus the venue cash net of
  /// the planned move costs, a figure the engine's plan covers.
  final double maxUsd;

  /// Dollars plus reachable venue cash: the From row's figure.
  double get totalUsd => _floorCents(dollarsUsd + venueCashUsd);

  @override
  bool operator ==(Object other) =>
      other is InvestmentsSpendable &&
      other.dollarsUsd == dollarsUsd &&
      other.venueCashUsd == venueCashUsd &&
      other.maxUsd == maxUsd;

  @override
  int get hashCode => Object.hash(dollarsUsd, venueCashUsd, maxUsd);

  @override
  String toString() => 'InvestmentsSpendable(dollars: $dollarsUsd, '
      'venueCash: $venueCashUsd, max: $maxUsd)';
}

double _floorCents(double usd) {
  if (!usd.isFinite || usd <= 0) return 0;
  return ((usd * 100) + 1e-6).floor() / 100;
}

double _ceilCents(double usd) {
  if (!usd.isFinite || usd <= 0) return 0;
  return ((usd * 100) - 1e-6).ceil() / 100;
}

/// Dollars plus the venue cash in [sources] the engine can reach, and the
/// Max the engine's plan covers. Pure.
///
/// A venue counts only when its free cash clears its minimum (plus the
/// route's fixed cost), exactly as [venueCashReachUsd] and
/// [planDollarsShortfall] skip it. Max starts at [venueCashReachUsd] and
/// steps down a cent at a time until [planDollarsShortfall] covers it, so
/// tapping Max never asks for a cent the plan cannot land.
InvestmentsSpendable investmentsSpendable({
  required double dollarsUsd,
  required List<VenueCashCandidate> sources,
}) {
  final dollars = dollarsUsd.isFinite && dollarsUsd > 0 ? dollarsUsd : 0.0;
  var venue = 0.0;
  final seen = <OneBalanceVenue>{};
  for (final s in sources) {
    if (!seen.add(s.venue)) continue;
    final cost = kVenuePullCost[s.venue] ?? (share: 0.02, fixedUsd: 0.30);
    final available = _floorCents(s.availableUsd);
    final minimum = _ceilCents(
        (s.minimumUsd.isFinite && s.minimumUsd > 0 ? s.minimumUsd : 0) +
            cost.fixedUsd);
    if (available <= 0 || available < minimum) continue;
    if (venuePullArrives(available, cost) <= 0) continue;
    venue += available;
  }
  if (venue <= 0) {
    return InvestmentsSpendable(
        dollarsUsd: dollars, venueCashUsd: 0, maxUsd: dollars);
  }
  var max = venueCashReachUsd(dollarsUsd: dollars, sources: sources);
  // The engine's plan has the last word: a cent of rounding in a leg's
  // gross-up must never leave Max one cent out of reach.
  for (var i = 0; i < 100 && max > dollars; i++) {
    final plan = planDollarsShortfall(
        neededUsd: max, dollarsUsd: dollars, sources: sources);
    if (plan.covers) break;
    max = _floorCents(max - 0.01);
  }
  if (max < dollars) max = dollars;
  return InvestmentsSpendable(
      dollarsUsd: dollars, venueCashUsd: _floorCents(venue), maxUsd: max);
}

// ─── Riverpod ──────────────────────────────────────────────────────

/// The engine's last read of the venues' free cash, for the spending
/// wallet it was read for. Kept for the app's life so the next amount
/// screen shows it at once.
typedef VenueCashLastRead = ({
  String? walletId,
  List<VenueCashCandidate> candidates,
});

final venueCashLastReadProvider =
    StateProvider<VenueCashLastRead?>((_) => null);

/// Before the engine has read the venues at all: the one-balance
/// picture's venue cash (the Investments header's Available), each venue
/// at its fixed route floor. Only while that picture is already up: an
/// amount screen never wakes the venues or the sweeper to show a figure.
/// Empty on a cold start.
final venueCashSeedProvider = Provider<List<VenueCashCandidate>>((ref) {
  if (!ref.exists(oneBalanceProvider)) return const [];
  final venueCash = ref.watch(oneBalanceProvider.select((s) => s.venueCash));
  return [
    for (final e in venueCash.entries)
      if (e.value.isFinite && e.value > 0)
        (
          venue: e.key,
          availableUsd: e.value,
          eta: kVenuePullEta[e.key]!,
          minimumUsd: venueFloorUsd(e.key),
        ),
  ];
});

/// Reads the venues again through the engine and keeps the answer in
/// [venueCashLastReadProvider]. Watched by a screen showing
/// [investmentsSpendableProvider]: the figure is already on screen, this
/// only updates it. A failed read keeps the last one.
final venueCashRefreshProvider = FutureProvider.autoDispose<void>((ref) async {
  final walletId = pickSpendingWallet(ref.read(settingsProvider))?.id;
  try {
    final candidates = await ref.read(venueCashPullerProvider).candidates();
    ref.read(venueCashLastReadProvider.notifier).state =
        (walletId: walletId, candidates: List.unmodifiable(candidates));
  } catch (_) {
    // The last read (or the seed) stays on screen.
  }
});

/// What Investments can spend right now, from the last known values:
/// synchronous, never loading.
final investmentsSpendableProvider =
    Provider.autoDispose<InvestmentsSpendable>((ref) {
  final dollars = ref.watch(usdBalanceProvider);
  final walletId = ref.watch(
      settingsProvider.select((s) => pickSpendingWallet(s)?.id));
  final last = ref.watch(venueCashLastReadProvider);
  final sources = last != null && last.walletId == walletId
      ? last.candidates
      : ref.watch(venueCashSeedProvider);
  return investmentsSpendable(dollarsUsd: dollars, sources: sources);
});
