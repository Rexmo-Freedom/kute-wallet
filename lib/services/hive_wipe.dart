// lib/services/hive_wipe.dart
//
// The one list of the app's Hive boxes the device wipe deletes
// (`AuthModel.deleteAuthentication`: the sixth wrong PIN, Forgot PIN,
// Start fresh). Every box a service opens belongs here or in
// [hiveBoxesKeptOnWipe]; test/services/hive_wipe_test.dart scans lib for
// box names and fails on one that is in neither.

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:hive_ce/hive.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/hive_boot.dart';
import 'package:kute/services/venue_analytics.dart';

/// Boxes a wipe keeps, each for a reason:
///  * crash_context — categorical "what the app was doing" snapshot
///    (screen, flow, step names) so a crash around the wipe itself can
///    still be attributed on the next launch; no wallet data.
///  * polymarket_market_terms_v1 / polymarket_fee_curves_v1 — public
///    market terms and fee curves (the same for every user), held open by
///    their stores for the process lifetime; deleting them under a live
///    handle gains nothing and would leave a dead box behind the slip.
const Set<String> hiveBoxesKeptOnWipe = {
  'crash_context',
  'polymarket_market_terms_v1',
  'polymarket_fee_curves_v1',
};

/// Every other box the app writes, wallet data and caches alike. A wipe
/// is a hostile-device measure as much as a reset, so nothing that could
/// show what the wiped wallets held or did survives; public caches go
/// too, so the device is as fresh as a new install.
const List<String> hiveBoxesWipedOnWipe = [
  // Wiped since the first build of the wipe.
  'bitcoin',
  'affiliateCode',
  'breez_prefs',
  'settings',
  'bitcoinTransactions',
  'addresses',
  'provider_event_outbox_v1',
  'hyperliquid_revenue_orders_v1',
  // Orphan: written by a retired build, read by nothing now (also
  // deleted at every start by deleteOrphanedHiveBoxes).
  'arbitrum_refund_reports',
  // Startup boxes (hive_boot.dart).
  'asset_icons',
  'tx_fiat_snapshot',
  'once_flags',
  'milestones_log',
  'outlogicOrders',
  'accumulation_addresses',
  'usdc_balance_history',
  'polymarket_suppressed_positions',
  'polymarket_optimistic_activity',
  'polymarket_spark_txs',
  'polymarket_spark_claim_windows',
  'orchestra_delivery_spark_txs',
  'polymarket_orchestra_orders',
  'polymarket_bet_funding',
  'polymarket_btc_route_queue',
  'fee_history',
  'wallet_balance_cache',
  'polymarket_usdc_cache',
  'venue_total_cache',
  'polymarket_activity_cache',
  'polymarket_usdc_receives_cache',
  'mempool_address_tx_cache',
  'hyperliquid_markets_cache_v1',
  'hyperliquid_sparklines_v1',
  'polymarket_feed_cache_v1',
  'wallet_transaction_cache',
  'spark_address_ring',
  'runtime_policy_cache',
  // Opened on demand.
  'currency_rates_v2',
  'hl_chart_preferences',
  'hl_chart_candle_interval',
  'hl_chart_drawings',
  'trade_results_v1',
  'orchestraRoutesCatalog',
  'hyperliquid_watchlist',
  'hyperliquid_favourites',
  'polymarket_watchlist',
  'sideshiftExchanges',
  'polymarket_combo_pending',
  'polymarket_combo_feed',
  'polymarket_cost_basis',
  'polymarket_account_cache',
  'polymarket_rpc_health',
  'polymarket_builder_code',
  'polymarket_price_history_v1',
  'polymarket_order_submissions',
  'polymarket_withdrawals',
  'mempool_tx_details',
  'settlement_operations',
  'settlement_quarantine',
  'ledger_submitted_actions',
  'ledger_venue_descriptors',
  'ledger_verified_receive_addresses',
  'hyperliquid_trailing_submissions',
  'hyperliquid_twap_submissions',
  'hyperliquid_running_twaps',
  'hyperliquid_account_display_cache',
  'standing_deposits_v1',
  'receive_route_availability_v1',
  'bitcoin_receive_marks_v1',
  'pending_receive_quotes_v1',
  'onetime_refund_addresses_v1',
  'venue_analytics',
];

/// Deletes every box in [hiveBoxesWipedOnWipe] from disk, best-effort:
/// a box that does not exist is skipped by Hive, a failing delete is
/// logged by name only and the next box still goes. Services that hold a
/// box open for the process are told to forget it, and the startup boxes
/// are opened again (empty) so code that expects them open keeps working
/// until the process restarts.
Future<void> wipeHiveBoxes() async {
  for (final name in hiveBoxesWipedOnWipe) {
    try {
      await Hive.deleteBoxFromDisk(name);
    } catch (e) {
      debugPrint('[wipe] hive box $name: ${e.runtimeType}');
    }
  }
  SettlementStore.forgetShared();
  VenueAnalytics.forgetStorage();
  try {
    await openStartupHiveBoxes();
  } catch (e) {
    debugPrint('[wipe] reopen startup boxes: ${e.runtimeType}');
  }
}

/// Boxes a retired build wrote that nothing reads any more. Deleted at
/// every start by [deleteOrphanedHiveBoxes] (idempotent and cheap: three
/// file-existence checks each) so they do not sit on devices for good.
const List<String> orphanedHiveBoxes = ['arbitrum_refund_reports'];

/// Deletes [orphanedHiveBoxes] from disk, best-effort. Called from the
/// Hive boot step; a failure is retried at the next start.
Future<void> deleteOrphanedHiveBoxes() async {
  for (final name in orphanedHiveBoxes) {
    try {
      await Hive.deleteBoxFromDisk(name);
    } catch (e) {
      debugPrint('[boot] orphan hive box $name: ${e.runtimeType}');
    }
  }
}
