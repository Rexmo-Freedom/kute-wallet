// lib/services/api_response_cache_service.dart
//
// On-disk cache for the three transaction-history sources whose
// underlying SDKs do NOT already persist their data locally:
//
//   1. Polymarket Activity (Data API).
//   2. Polymarket inbound USDC receives (Polygonscan tokentx API).
//   3. Mempool address transactions (mempool.space) — currently
//      consumed by external-address wallets and the Spark pending-
//      deposits path.
//
// BDK persists its own SQLite for on-chain Bitcoin tx; Breez SDK has
// its own DB for Lightning + Spark + USDB; swap orders and
// Outlogic orders both have existing Hive adapters. Those four don't
// need this layer — restarting the app already shows their txs
// immediately.
//
// What this fixes: cold-start blank tx list for the API-derived
// rows. Without this, every app launch (or iOS process kill) waits
// for live API calls before the home Activity feed has anything to
// render. With this, the cached snapshot is returned synchronously
// at boot and the UI paints immediately; the live fetch replaces
// the cached snapshot when it lands.
//
// Storage: each Hive box stores a JSON-encoded payload keyed by
// either a wallet id or a Safe address. Schema-versioned so future
// shape changes can drop old caches cleanly without crashing.

import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/services/mempool_address_service.dart';
import 'package:kute/services/persistence/hive_schema.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Activity;

class ApiResponseCacheService {
  ApiResponseCacheService._();

  // Schema version — bump when payload shape changes incompatibly,
  // and add a forward migration to [_migrations] covering the prior
  // version. On read, an entry is upgraded forward through the
  // migration chain if possible; if no migration covers the gap
  // (or one throws), the entry is dropped and the next live fetch
  // overwrites it.
  static const int _schemaVersion = 1;

  /// Forward migrations indexed by source version: `_migrations[0]`
  /// handles v1 → v2, `_migrations[1]` handles v2 → v3, etc. Empty
  /// for now since the cache shipped at v1; first incompatible
  /// shape change adds the v1→v2 handler here.
  static const List<HiveMigration> _migrations = <HiveMigration>[];

  static const String _polyActivityBox = 'polymarket_activity_cache';
  static const String _polyUsdcReceivesBox = 'polymarket_usdc_receives_cache';
  static const String _mempoolTxBox = 'mempool_address_tx_cache';

  /// Box names (used by `_initHive` in main.dart to register them at
  /// boot; keep in sync there).
  static const List<String> boxNames = [
    _polyActivityBox,
    _polyUsdcReceivesBox,
    _mempoolTxBox,
  ];

  // ─── Polymarket Activity ──────────────────────────────────────

  /// Cache the user's Polymarket Activity feed by Safe address.
  /// Caller is responsible for normalising the address (lower-cased
  /// hex) — we don't enforce a particular form, just key by what's
  /// passed in.
  static Future<void> writePolymarketActivity(
    String safeAddress,
    List<Activity> activities,
  ) async {
    if (safeAddress.isEmpty) return;
    try {
      final box = Hive.box<String>(_polyActivityBox);
      await box.put(
        safeAddress.toLowerCase(),
        jsonEncode({
          'v': _schemaVersion,
          'savedAt': DateTime.now().millisecondsSinceEpoch,
          'items': activities.map((a) => a.toJson()).toList(),
        }),
      );
    } catch (_) {
      // Persistence failure is non-fatal — UI keeps working from the
      // in-memory live data; we just lose the cold-start hydration
      // for this entry.
    }
  }

  static List<Activity> readPolymarketActivity(String safeAddress) {
    if (safeAddress.isEmpty) return const <Activity>[];
    try {
      final box = Hive.box<String>(_polyActivityBox);
      final raw = box.get(safeAddress.toLowerCase());
      if (raw == null) return const <Activity>[];
      final wrapper = jsonDecode(raw) as Map<String, dynamic>;
      final upgraded = HiveSchema.upgradeOrDrop(
        wrapper,
        currentVersion: _schemaVersion,
        migrations: _migrations,
      );
      if (upgraded == null) return const <Activity>[];
      final items = (upgraded['items'] as List?) ?? const [];
      return items
          .whereType<Map>()
          .map((e) => Activity.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (_) {
      return const <Activity>[];
    }
  }

  // ─── Polymarket USDC Receives ─────────────────────────────────

  static Future<void> writePolymarketUsdcReceives(
    String safeAddress,
    List<PolymarketUsdcReceive> receives,
  ) async {
    if (safeAddress.isEmpty) return;
    try {
      final box = Hive.box<String>(_polyUsdcReceivesBox);
      await box.put(
        safeAddress.toLowerCase(),
        jsonEncode({
          'v': _schemaVersion,
          'savedAt': DateTime.now().millisecondsSinceEpoch,
          'items': receives.map((r) => r.toJson()).toList(),
        }),
      );
    } catch (_) {}
  }

  static List<PolymarketUsdcReceive> readPolymarketUsdcReceives(
      String safeAddress) {
    if (safeAddress.isEmpty) return const <PolymarketUsdcReceive>[];
    try {
      final box = Hive.box<String>(_polyUsdcReceivesBox);
      final raw = box.get(safeAddress.toLowerCase());
      if (raw == null) return const <PolymarketUsdcReceive>[];
      final wrapper = jsonDecode(raw) as Map<String, dynamic>;
      final upgraded = HiveSchema.upgradeOrDrop(
        wrapper,
        currentVersion: _schemaVersion,
        migrations: _migrations,
      );
      if (upgraded == null) return const <PolymarketUsdcReceive>[];
      final items = (upgraded['items'] as List?) ?? const [];
      return items
          .whereType<Map>()
          .map((e) =>
              PolymarketUsdcReceive.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (_) {
      return const <PolymarketUsdcReceive>[];
    }
  }

  // ─── Mempool address transactions ─────────────────────────────

  /// Used both by external-address wallet sync (keyed by walletId)
  /// and by Spark pending-deposit detection (keyed by spark on-chain
  /// address). Caller picks the key.
  static Future<void> writeMempoolTransactions(
    String key,
    List<MempoolTransaction> txs,
  ) async {
    if (key.isEmpty) return;
    try {
      final box = Hive.box<String>(_mempoolTxBox);
      await box.put(
        key,
        jsonEncode({
          'v': _schemaVersion,
          'savedAt': DateTime.now().millisecondsSinceEpoch,
          'items': txs.map((t) => t.toJson()).toList(),
        }),
      );
    } catch (_) {}
  }

  static List<MempoolTransaction> readMempoolTransactions(String key) {
    if (key.isEmpty) return const <MempoolTransaction>[];
    try {
      final box = Hive.box<String>(_mempoolTxBox);
      final raw = box.get(key);
      if (raw == null) return const <MempoolTransaction>[];
      final wrapper = jsonDecode(raw) as Map<String, dynamic>;
      final upgraded = HiveSchema.upgradeOrDrop(
        wrapper,
        currentVersion: _schemaVersion,
        migrations: _migrations,
      );
      if (upgraded == null) return const <MempoolTransaction>[];
      final items = (upgraded['items'] as List?) ?? const [];
      return items
          .whereType<Map>()
          .map((e) => MempoolTransaction.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (_) {
      return const <MempoolTransaction>[];
    }
  }

  // ─── Cleanup on wallet deletion ───────────────────────────────

  /// Wipe all caches keyed by a wallet id. Safe to call on wallet
  /// removal even if no entries exist.
  static Future<void> deleteForWallet(String walletId) async {
    if (walletId.isEmpty) return;
    try {
      await Hive.box<String>(_mempoolTxBox).delete(walletId);
    } catch (_) {}
    // Polymarket caches are keyed by Safe address; if a wallet
    // deletion needs to clean those too, the caller passes the
    // Safe address through `deleteForSafe(...)` separately.
  }

  static Future<void> deleteForSafe(String safeAddress) async {
    if (safeAddress.isEmpty) return;
    final key = safeAddress.toLowerCase();
    try {
      await Hive.box<String>(_polyActivityBox).delete(key);
    } catch (_) {}
    try {
      await Hive.box<String>(_polyUsdcReceivesBox).delete(key);
    } catch (_) {}
  }
}
