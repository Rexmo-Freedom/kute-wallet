// Autonomous claimer: redeems resolved Polymarket positions the moment
// the trading state marks them redeemable (user decision 2026-09-02,
// reversing the earlier manual-claims-only directive — the "You won!"
// snackbar stays as the announcement, the tap is no longer required).
//
// Same long-lived shape as PendingBetAutoFire: a non-autoDispose
// Provider bootstrapped once by Home, listening to the trading
// provider's ticks for the rest of the session regardless of which
// screen is visible.
//
// Guards the old deleted sweep lacked:
//   - Lock gate mirrors redeemPosition's own check (an unlocked session
//     with the lock overlay down, for passkey wallets too) so a locked
//     session quietly waits instead of throwing on every 3s tick — the
//     claim lands on the first tick after unlock.
//   - Oracle finality lag: Polymarket's Data API flips `redeemable` at
//     resolution but the CTF payout often opens minutes later, and
//     redeemPosition aborts until it does. Failures retry with a
//     doubling backoff (2 min → 30 min cap) instead of giving up.
//   - One claim per tick, serialized by an in-flight flag; the state
//     refresh a successful redeem triggers re-enters for the next one.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/providers/auth_provider.dart'
    show sessionUnlockedProvider;
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/polymarket_combos_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/services/tracking_service.dart';

final claimAutoFireProvider = Provider<ClaimAutoFire>((ref) {
  final svc = ClaimAutoFire(ref);
  ref.onDispose(svc.dispose);
  return svc;
});

class ClaimAutoFire {
  final Ref ref;
  bool _claiming = false;
  final Map<String, DateTime> _nextAttempt = {};
  final Map<String, Duration> _backoff = {};
  late final ProviderSubscription<dynamic> _sub;

  ClaimAutoFire(this.ref) {
    _sub = ref.listen(polymarketTradingProvider, (_, __) {
      _maybeClaim();
    });
    // Settled winning combos (parlays) claim themselves the same way: the
    // combos notifier redeems them through the Router on its refresh.
    // Listening keeps it alive for the session, like this claimer.
    _comboSub = ref.listen(polymarketCombosProvider, (_, __) {});
  }

  late final ProviderSubscription<dynamic> _comboSub;

  void dispose() {
    _sub.close();
    _comboSub.close();
  }

  Future<void> _maybeClaim() async {
    if (_claiming) return;
    final s = ref.read(polymarketTradingProvider).valueOrNull;
    if (s == null) return;
    final redeemables =
        s.openPositions.where((p) => p.redeemable).toList();
    if (redeemables.isEmpty) return;

    // Lock gate — mirror redeemPosition's own rule so we wait instead
    // of throwing. The unlock's next provider tick fires the claim.
    final spending = pickSpendingWallet(ref.read(settingsProvider));
    if (spending == null) return;
    if (!ref.read(sessionUnlockedProvider)) return;

    final now = DateTime.now();
    for (final pos in redeemables) {
      final String id = pos.conditionId;
      if (id.isEmpty) continue;
      final next = _nextAttempt[id];
      if (next != null && now.isBefore(next)) continue;

      _claiming = true;
      // A backoff retry is the same claim, not a new one: initiated and
      // failed are reported on the first attempt for an id only.
      final firstAttempt = !_backoff.containsKey(id);
      try {
        if (firstAttempt) {
          unawaited(VenueAnalytics.ensurePolymarket(
              slug: pos.eventSlug, ids: [id, pos.asset]));
          TrackingService.polymarketRedeemInitiated(
              marketId: id, trigger: 'auto');
        }
        // Success is polymarket_position_redeemed with trigger 'auto' (the
        // old polymarket_auto_claim_fired duplicated it and is gone).
        await ref.read(polymarketTradingProvider.notifier).redeemPosition(
              conditionId: id,
              trigger: 'auto',
              reportFailure: firstAttempt,
            );
        _nextAttempt.remove(id);
        _backoff.remove(id);
      } catch (_) {
        // Most commonly the payout isn't open on-chain yet — schedule
        // a retry instead of treating the position as unclaimable.
        // redeemPosition's own analytics cover the terminal-failure
        // paths.
        final cur = _backoff[id] ?? const Duration(minutes: 2);
        _nextAttempt[id] = DateTime.now().add(cur);
        final doubled = cur * 2;
        _backoff[id] = doubled > const Duration(minutes: 30)
            ? const Duration(minutes: 30)
            : doubled;
      } finally {
        _claiming = false;
      }
      // One redeem per tick — the refresh a claim triggers (or the
      // next poll) re-enters for any remaining positions.
      break;
    }
  }
}
