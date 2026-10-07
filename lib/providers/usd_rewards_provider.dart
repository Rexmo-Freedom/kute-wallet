// lib/providers/usd_rewards_provider.dart
//
// The dollar Earn screen's reads, recovered from the rewards section of
// the deleted lib/providers/flashnet_provider.dart (commit b7e7c6f8^):
// the Spark identity pubkey every route is keyed on, the client, the
// summary behind the rate hero, and the payout ledger behind Activity.
//
// ONE DELIBERATE CHANGE FROM THE RECOVERED CODE. The old providers
// swallowed every failure into `null`, which the file's own header
// admitted left a screen handling only loading/data spinning forever.
// The Earn screen has to tell a user the rate is UNAVAILABLE rather than
// show a zero or a stale number as if it were real, and it cannot do
// that if a dead service and a slow one look identical. So these let the
// exception through and the screen renders `AsyncValue.error` as
// "unavailable". Nothing here ever substitutes a default rate.

import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart'
    show GetInfoRequest;
import 'package:flutter/widgets.dart' show WidgetsBinding, AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/usd_rewards_model.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/services/api/usd_rewards_api.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

/// The backend capability behind the Dollars Earn tab.
const String kUsdEarnCapability = 'usd.earn';

/// Whether the app may SHOW the dollar rewards programme: the Earn tab,
/// the rate, the payout ledger and the `usd_earn_*` events.
///
/// The rewards themselves accrue at the token level and cannot be
/// switched off from here; this only decides whether the app displays
/// them. The backend ships the capability disabled, so nothing renders
/// until an operator publishes it on. Fail closed: a rate is a promise,
/// so a missing policy (offline, first boot, an older backend that never
/// heard of the id) hides the tab rather than showing a number nobody
/// approved. `allows` already reports both cases as denied.
final usdEarnEnabledProvider = Provider.autoDispose<bool>((ref) =>
    ref.watch(runtimeCapabilitiesProvider).allows(kUsdEarnCapability));

/// Refresh cadence for the rewards surfaces.
///
/// Deliberately unhurried. Every number behind it moves at most once a day
/// (payouts land at 01:00 UTC), so a 60s poll already refreshes far faster
/// than the data changes. A tighter loop would burn battery to re-render an
/// identical screen.
const Duration usdRewardsPollInterval = Duration(seconds: 60);

/// Re-runs the calling provider every [interval] while the app is in the
/// foreground, and stops when nothing is watching.
///
/// The foreground gate matters: a bare `Timer.periodic` keeps ticking after
/// the app is backgrounded (iOS grants minutes of grace, Android longer) and
/// every tick would fan out to network calls for a UI nobody can see.
/// `lifecycleState` is null until the first lifecycle event lands, which is
/// treated as foreground so a cold start still refreshes.
void _pollWhileForeground(Ref<Object?> ref, Duration interval) {
  final timer = Timer.periodic(interval, (_) {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);
}

/// The wallet's Spark identity pubkey: 33 compressed secp256k1 bytes as 66
/// hex chars.
///
/// This is NOT the Spark address. The address (`sp1...` bech32m, from
/// `sparkSelfAddressProvider`) is where funds get sent; this pubkey is the
/// `:pubkey` path segment on every rewards route. Mixing them up produces a
/// 404, not a type error.
///
/// Returns null when the wallet is not connected, which every caller treats
/// as "no data yet" rather than an error, because an Earn screen opened
/// during wallet startup is normal.
final sparkIdentityPubkeyProvider =
    FutureProvider.autoDispose<String?>((ref) async {
  final sdkWrapper = await ref.watch(breezSDKProvider.future);
  final sdk = sdkWrapper.instance;
  if (sdk == null) return null;

  final info = await sdk.getInfo(request: const GetInfoRequest());
  final pubkey = info.identityPubkey;
  return pubkey.isEmpty ? null : pubkey;
});

final usdRewardsApiProvider = Provider<UsdRewardsApi>((ref) => UsdRewardsApi());

/// Pagination arguments for the payout family.
///
/// A value class rather than a record so the family caches correctly.
class RewardsPageParams {
  final int limit;
  final int offset;

  const RewardsPageParams({this.limit = 30, this.offset = 0});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RewardsPageParams &&
          other.limit == limit &&
          other.offset == offset;

  @override
  int get hashCode => Object.hash(limit, offset);
}

/// The payout page every Earn surface shares.
///
/// Watching one instance keeps the hero's "paid to date" line and the
/// Activity list on a single cached request instead of two independent
/// 60 s timers hitting the same endpoint. 90 rows is, for a programme this
/// young, every payout the wallet has ever received — check
/// `PayoutHistoryResponse.hasMore` before calling any sum over it a
/// lifetime total.
const RewardsPageParams earnPayoutPage = RewardsPageParams(limit: 90);

/// `GET /rewards/:pubkey` — the Earn screen's hero.
///
/// Prefer `.estimatedSatsToday` over any locally computed projection: it is
/// the server's own number, so we never have to defend arithmetic we made up.
/// Resolves to null only when there is no wallet yet; a service failure
/// throws so the screen can say the rate is unavailable.
final userRewardsSummaryProvider =
    FutureProvider.autoDispose<UserRewardsSummary?>((ref) async {
  // Belt and braces under the tab gate: with the capability off nothing
  // watches this, and even if something did the API is never asked.
  if (!ref.watch(usdEarnEnabledProvider)) return null;
  _pollWhileForeground(ref, usdRewardsPollInterval);
  final api = ref.watch(usdRewardsApiProvider);
  final pubkey = await ref.watch(sparkIdentityPubkeyProvider.future);
  if (pubkey == null) return null;
  return api.getUserSummary(pubkey);
});

/// `GET /rewards/:pubkey/payouts` — the daily bitcoin payout ledger.
final payoutHistoryProvider = FutureProvider.family
    .autoDispose<PayoutHistoryResponse?, RewardsPageParams>(
        (ref, params) async {
  if (!ref.watch(usdEarnEnabledProvider)) return null;
  _pollWhileForeground(ref, usdRewardsPollInterval);
  final api = ref.watch(usdRewardsApiProvider);
  final pubkey = await ref.watch(sparkIdentityPubkeyProvider.future);
  if (pubkey == null) return null;
  return api.getPayoutHistory(
    pubkey,
    limit: params.limit,
    offset: params.offset,
  );
});
