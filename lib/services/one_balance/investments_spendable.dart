// lib/services/one_balance/investments_spendable.dart
//
// "What can Investments spend right now?" for the amount screens that pay
// out of Investments through the venue-cash engine (Buy bitcoin from
// Investments in the Move sheet, the Dollars send): Dollars plus the
// venue cash the engine can reach (venue_cash_source.dart), never the
// positions: the part of the Investments header's Available a route
// can carry.
//
//  * [investmentsSpendable] is the pure figure: the total (Dollars +
//    reachable venue cash, before costs) and the Max, which is that total
//    less the planned move costs, checked against the engine's own plan
//    ([planDollarsShortfall]) so Max is always an amount it can execute.
//    The From row and the available line show the Max (founder decision
//    13 October 2026): any amount up to the shown figure goes through.
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
import 'package:kute/services/funding/owned_address_resolver.dart'
    show ProviderReader;

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

  /// Dollars plus reachable venue cash, before costs. The From row shows
  /// [maxUsd], what can actually be spent.
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

/// Pending source debits protect the last-known figure while a move is on
/// its rail. A read started before a debit or terminal outcome cannot put
/// the old source cash back next to the destination's newly arrived cash.
final _venueCashWalletEpochProvider = Provider((ref) {
  final walletId =
      ref.watch(settingsProvider.select((s) => pickSpendingWallet(s)?.id));
  return (walletId: walletId, token: Object());
});

final venueCashSnapshotProvider = Provider<VenueCashSnapshot>((ref) {
  final epoch = ref.watch(_venueCashWalletEpochProvider);
  final snapshot = VenueCashSnapshot(ref, epoch.walletId, epoch.token);
  ref.onDispose(snapshot.dispose);
  return snapshot;
});

class VenueCashSnapshot {
  VenueCashSnapshot(this._ref, this.walletId, this._epoch);

  final Ref _ref;
  final String? walletId;
  final Object _epoch;
  bool _alive = true;
  int _revision = 0;
  final Set<String> _sent = {};
  final Map<OneBalanceVenue, double> _ceilings = {};
  final Map<String, ({OneBalanceVenue venue, Set<String> refs})> _pending = {};
  final Set<String> _settled = {};

  void dispose() => _alive = false;

  bool get _current =>
      _alive &&
      identical(_ref.read(_venueCashWalletEpochProvider).token, _epoch);

  List<VenueCashCandidate> _sources() {
    final last = _ref.read(venueCashLastReadProvider);
    return last != null && last.walletId == walletId
        ? last.candidates
        : _ref.read(venueCashSeedProvider);
  }

  /// The displayed source balance before a new send starts. Capturing it
  /// then avoids subtracting again from a read that already saw the send.
  double? availableUsd(OneBalanceVenue venue) => !_current
      ? null
      : _sources().where((s) => s.venue == venue).firstOrNull?.availableUsd;

  /// The rail accepted this source send. Its local operation/quote key
  /// makes duplicate callbacks harmless; no failed or unknown send debits.
  void cashMoved(VenueCashLegOutcome leg, double? availableBefore) {
    if (!_current || !leg.ok) return;
    final result = leg.result!;
    final key = '${leg.venue.name}:'
        '${result.operationId ?? result.orderId ?? result.quoteId}';
    if (!_sent.add(key)) return;
    final usd = result.sentUsd > 0 ? result.sentUsd : leg.pull.usd;
    if (!usd.isFinite || usd <= 0) return;
    final sources = _sources();
    final previous = sources.where((s) => s.venue == leg.venue).firstOrNull;
    final before = availableBefore ?? previous?.availableUsd ?? usd;
    final priorCeiling = _ceilings[leg.venue] ?? before;
    // A live read may already reflect the send. Cap it by the pre-send
    // remainder rather than subtracting the same send from that read too.
    final ceiling = _floorCents([
      before - usd,
      priorCeiling - usd,
      if (previous != null) previous.availableUsd,
    ].reduce((a, b) => a < b ? a : b));
    _ceilings[leg.venue] = ceiling;
    _pending[key] = (
      venue: leg.venue,
      refs: {
        result.quoteId,
        if (result.orderId case final id?) id,
        if (result.operationId case final id?) id,
      }
    );
    _revision++;
    _publish([
      for (final s in sources)
        if (s.venue == leg.venue)
          (
            venue: s.venue,
            availableUsd: ceiling,
            eta: s.eta,
            minimumUsd: s.minimumUsd
          )
        else
          s,
      if (previous == null)
        (
          venue: leg.venue,
          availableUsd: ceiling,
          eta: kVenuePullEta[leg.venue]!,
          minimumUsd: venueFloorUsd(leg.venue)
        ),
    ]);
  }

  void _publish(List<VenueCashCandidate> candidates) {
    _ref.read(venueCashLastReadProvider.notifier).state =
        (walletId: walletId, candidates: List.unmodifiable(candidates));
  }

  /// [settledRefs] must be proved delivered or refunded by their own
  /// leg, never inferred from an unrelated arrival or a generic failure.
  /// Only a new read requested after that proof can reconcile the debit.
  Future<void> refresh(ProviderReader read,
      {Set<String> settledRefs = const {}}) async {
    if (!_current) return;
    _settled.addAll([
      for (final e in _pending.entries)
        if (e.value.refs.any(settledRefs.contains)) e.key,
    ]);
    final settledAtStart = Set<String>.of(_settled);
    final revision = ++_revision;
    try {
      final candidates = await read(venueCashPullerProvider).candidates();
      if (!_current || revision != _revision) return;
      for (final key in settledAtStart) {
        _pending.remove(key);
        _settled.remove(key);
      }
      // Another accepted move may still be settling at this source. A
      // first leg's proof must never restore the second leg's source cash.
      _ceilings.removeWhere(
          (venue, _) => !_pending.values.any((move) => move.venue == venue));
      _publish([
        for (final s in candidates)
          if (_ceilings[s.venue] case final ceiling?)
            (
              venue: s.venue,
              availableUsd: s.availableUsd < ceiling ? s.availableUsd : ceiling,
              eta: s.eta,
              minimumUsd: s.minimumUsd
            )
          else
            s,
      ]);
    } catch (_) {
      // Keep the last figure and pending debit. A later requested read
      // can reconcile a proved terminal leg; nothing polls globally.
    }
  }
}

/// Refresh once after a source's own delivery/refund, for the wallet the
/// move began on. The scoped snapshot also rejects switch-away-and-back
/// callbacks held by an older provider generation.
Future<void> refreshVenueCashAfterMove(ProviderReader read,
    {required String? walletId,
    required VenueCashSnapshot scope,
    required Set<String> settledRefs}) async {
  final snapshot = read(venueCashSnapshotProvider);
  if (snapshot.walletId != walletId || !identical(snapshot, scope)) return;
  await snapshot.refresh(read, settledRefs: settledRefs);
}

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
  await ref.watch(venueCashSnapshotProvider).refresh(ref.read);
});

/// What Investments can spend right now, from the last known values:
/// synchronous, never loading.
final investmentsSpendableProvider =
    Provider.autoDispose<InvestmentsSpendable>((ref) {
  final dollars = ref.watch(usdBalanceProvider);
  final walletId =
      ref.watch(settingsProvider.select((s) => pickSpendingWallet(s)?.id));
  final last = ref.watch(venueCashLastReadProvider);
  final sources = last != null && last.walletId == walletId
      ? last.candidates
      : ref.watch(venueCashSeedProvider);
  return investmentsSpendable(dollarsUsd: dollars, sources: sources);
});

/// What Investments can spend for an order on [venue] beyond that venue's
/// own cash: Dollars plus the OTHER venues' reachable cash, net of their
/// pull costs (the same last-known values and rules as
/// [investmentsSpendableProvider]). The order slips add their own venue's
/// free cash to it, so their "Available" is the whole spendable
/// Investments, the figure the one-balance planner draws on, never the
/// venue's cash alone. Synchronous, never loading.
final investmentsSpendableExcludingProvider = Provider.autoDispose
    .family<InvestmentsSpendable, OneBalanceVenue>((ref, venue) {
  final dollars = ref.watch(usdBalanceProvider);
  final walletId =
      ref.watch(settingsProvider.select((s) => pickSpendingWallet(s)?.id));
  final last = ref.watch(venueCashLastReadProvider);
  final sources = last != null && last.walletId == walletId
      ? last.candidates
      : ref.watch(venueCashSeedProvider);
  return investmentsSpendable(
    dollarsUsd: dollars,
    sources: [
      for (final s in sources)
        if (s.venue != venue) s,
    ],
  );
});
