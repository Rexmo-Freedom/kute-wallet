// lib/services/hive_boot.dart
//
// The Hive boxes the app reads at boot, opened in one parallel batch,
// then the stored analytics opt-out applied. Called from
// `_initHive` in lib/main.dart once Hive itself is initialised; the test
// in test/services/hive_boot_test.dart runs exactly this path.

import 'package:hive_ce/hive.dart';
import 'package:kute/services/runtime_policy_snapshot_store.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/tx_fiat_snapshot_service.dart';
import 'package:kute/services/venue_total_cache_service.dart';

/// Opens every startup box and applies the stored analytics opt-out.
/// Requires `Hive.init` (and the adapters) to have run already. Never
/// throws: a corrupt cache-tier box is wiped and reopened, and a failed
/// settings open falls through.
Future<void> openStartupHiveBoxes() async {
  // All box opens run in PARALLEL — they're independent file opens with
  // no data dependencies, and sequential awaits put ~20 × ~40ms of I/O
  // on the cold-start critical path (measured as one of the top splash
  // costs). `_openHiveBoxSafe` still isolates per-box corruption.
  //
  // Box-by-box rationale (kept from the sequential version):
  //  * TxFiatSnapshotService.boxName — at-the-time USD value of txs
  //    (Outlogic / BTC receives+sends / Polymarket) for historical
  //    value + gain/loss vs current price.
  //  * once_flags — once-only milestone flags (first_swap, first_bet…).
  //  * milestones_log — chronological log of unlocked milestones.
  //  * accumulation_addresses — the legacy Orchestra deposit addresses
  //    handed out before standing addresses (AccumulationAddressCache),
  //    read only by background sync's silent sweep for late deposits.
  //  * polymarket_suppressed_positions — recently sold/redeemed
  //    positions stay hidden across restarts while the Data API
  //    catches up (epoch-ms per conditionId).
  //  * polymarket_optimistic_activity — synthetic Sold/Bought entries
  //    injected before the Data API confirms them.
  //  * polymarket_spark_txs — Spark tx ids from bet/claim plumbing,
  //    hidden from the Activity feed.
  //  * polymarket_spark_claim_windows — expected-inbound windows for
  //    Orchestra claim receives.
  //  * polymarket_orchestra_orders — orderIds tagged as bet-flow
  //    plumbing (hidden); user Convert exchanges stay visible.
  //  * polymarket_bet_funding — per-bet funding-currency tag (BTC vs
  //    USDC), read on resolve/sell to route proceeds back.
  //  * polymarket_btc_route_queue — queued USDC.e → BTC routes drained
  //    once the pUSD unwrap settles.
  //  * fee_history — universal fee ledger for the analytics Fees tab.
  //  * wallet_balance_cache — per-wallet balance snapshots so cards
  //    never flash "0" on open.
  //  * polymarket_usdc_cache — last-known Safe USDC.e balance.
  //  * venue_total_cache — last-known Predictions / Investing total per
  //    wallet, so the balance headers never show a bare dash.
  //  * polymarket_activity_cache / polymarket_usdc_receives_cache /
  //    mempool_address_tx_cache — API-response caches so cold start
  //    renders the Activity feed without waiting on live APIs.
  //  * wallet_transaction_cache — per-wallet Transaction snapshots
  //    read synchronously at construction time.
  //  * spark_address_ring — recent Spark deposit addresses (ring, max
  //    5) so pending inbound txs survive address rotation + restarts.
  //  * runtime_policy_cache — the last runtime policy fetched for this
  //    wallet (public metadata, no token), so a boot with a bad link
  //    keeps what the backend last allowed (RuntimeCapabilitiesService).
  //  * settings — pre-opened here (was opened lazily by
  //    initialSettingsProvider on the splash critical path; opening it
  //    in this parallel batch removes that sequential cost — openBox
  //    on an already-open box is a fast no-op there).
  await Future.wait([
    _openHiveBoxSafe<String>('asset_icons'),
    _openHiveBoxSafe<String>(TxFiatSnapshotService.boxName),
    _openHiveBoxSafe<bool>('once_flags'),
    _openHiveBoxSafe('milestones_log'),
    _openHiveBoxSafe<String>('outlogicOrders'),
    _openHiveBoxSafe<String>('accumulation_addresses'),
    _openHiveBoxSafe<String>('usdc_balance_history'),
    _openHiveBoxSafe<String>('polymarket_suppressed_positions'),
    _openHiveBoxSafe<String>('polymarket_optimistic_activity'),
    _openHiveBoxSafe<String>('polymarket_spark_txs'),
    _openHiveBoxSafe<String>('polymarket_spark_claim_windows'),
    _openHiveBoxSafe<String>('orchestra_delivery_spark_txs'),
    _openHiveBoxSafe<String>('polymarket_orchestra_orders'),
    _openHiveBoxSafe<String>('polymarket_bet_funding'),
    _openHiveBoxSafe<String>('polymarket_btc_route_queue'),
    _openHiveBoxSafe<String>('fee_history'),
    _openHiveBoxSafe<String>('wallet_balance_cache'),
    _openHiveBoxSafe<double>('polymarket_usdc_cache'),
    _openHiveBoxSafe<double>(VenueTotalCacheService.boxName),
    _openHiveBoxSafe<String>('polymarket_activity_cache'),
    _openHiveBoxSafe<String>('polymarket_usdc_receives_cache'),
    _openHiveBoxSafe<String>('mempool_address_tx_cache'),
    _openHiveBoxSafe<String>('hyperliquid_markets_cache_v1'),
    _openHiveBoxSafe<String>('hyperliquid_sparklines_v1'),
    _openHiveBoxSafe<String>('polymarket_feed_cache_v1'),
    _openHiveBoxSafe<String>('wallet_transaction_cache'),
    _openHiveBoxSafe<String>('spark_address_ring'),
    _openHiveBoxSafe<String>(HiveRuntimePolicySnapshotStore.boxName),
    // Settings box: plain open, NOT _openHiveBoxSafe — the safe variant
    // deletes a corrupt box from disk, which is right for cache-tier
    // boxes but would silently wipe the WALLET LIST here. A failed open
    // just falls through; initialSettingsProvider retries it and owns
    // the error surface exactly as before.
    Hive.openBox('settings').then((_) {}, onError: (_) {}),
  ]);
  // The analytics opt-out lives in the settings box, so apply it the
  // moment the box is open and before anything can fire an event: `track`
  // checks the mute flag at call time. Synchronous; the SDK opt-out it may
  // trigger is fire-and-forget.
  TrackingService.applyStoredOptOut();
}

Future<void> _openHiveBoxSafe<T>(String name) async {
  try {
    await Hive.openBox<T>(name);
  } catch (e) {
    await Hive.deleteBoxFromDisk(name);
    await Hive.openBox<T>(name);
  }
}
