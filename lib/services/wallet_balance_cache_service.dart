// lib/services/wallet_balance_cache_service.dart
//
// Persists per-wallet balance snapshots to Hive so the wallet picker
// and home cards never flash "0" on app open or wallet switch. The
// in-memory `walletBalanceCacheProvider` is hydrated from this on
// boot and written-through on every balance update.
//
// Each entry now carries a `lastUpdatedAt` timestamp so consumers
// can tell how stale the cached value is — useful both for surfacing
// "refreshing" hints in the UI and for prioritising sync work on
// resume from background. Hive write failures are surfaced to
// telemetry so we know when the disk path is broken.

import 'dart:convert';

import 'package:hive_ce/hive.dart';

import 'package:kute/models/balance_model.dart';
import 'package:kute/services/tracking_service.dart';

class WalletBalanceCacheService {
  static const _boxName = 'wallet_balance_cache';

  /// In-memory mirror of the on-disk timestamps. The persisted value
  /// shape stays compatible with the old `{onchain, spark, usdb}`
  /// JSON; the timestamp lives alongside in this map (and inside the
  /// JSON for cold-start hydration).
  static final Map<String, DateTime> _lastUpdated = {};

  static Box<String>? get _box {
    try {
      if (!Hive.isBoxOpen(_boxName)) return null;
      return Hive.box<String>(_boxName);
    } catch (_) {
      return null;
    }
  }

  /// Read every persisted balance into a fresh map. Called once on
  /// app start (and by the cache-provider seed) to hydrate the
  /// in-memory state.
  static Map<String, WalletBalance> readAll() {
    final box = _box;
    if (box == null) return const {};
    final out = <String, WalletBalance>{};
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      final entry = _decode(raw);
      if (entry == null) continue;
      final id = key.toString();
      out[id] = entry.balance;
      if (entry.lastUpdated != null) {
        _lastUpdated[id] = entry.lastUpdated!;
      }
    }
    return out;
  }

  /// True when the cached balance for [walletId] is older than
  /// [threshold] (or has no timestamp at all). Drives the
  /// "refreshing" hint and tells the resume sync which wallets need
  /// the most urgent refresh.
  static bool isStale(String walletId,
      {Duration threshold = const Duration(seconds: 30)}) {
    final ts = _lastUpdated[walletId];
    if (ts == null) return true;
    return DateTime.now().difference(ts) >= threshold;
  }

  /// Last successful update timestamp for [walletId], or null if the
  /// wallet has no cached value yet.
  static DateTime? lastUpdatedAt(String walletId) => _lastUpdated[walletId];

  /// Write a single wallet's balance to disk. Hive failures (locked
  /// box, disk full, type adapter issue) are surfaced to telemetry so
  /// we can correlate "balance not updating" reports with persistence
  /// failures in the field.
  static void write(String walletId, WalletBalance balance) {
    final box = _box;
    if (box == null) {
      // Drop wallet_id from the event payload — it's a stable
      // per-wallet correlator that would let BigQuery cluster every
      // event by wallet. The error class alone is enough signal for
      // "balance not updating" reports.
      TrackingService.track('wallet_balance_cache_write_failed',
          params: {'reason': 'box_unavailable'});
      return;
    }
    final now = DateTime.now();
    try {
      box.put(walletId, jsonEncode(_toJson(balance, now)));
      _lastUpdated[walletId] = now;
    } catch (e) {
      TrackingService.track('wallet_balance_cache_write_failed', params: {
        'reason': 'put_threw',
        'error_class': e.runtimeType.toString(),
      });
    }
  }

  /// Drop a single wallet's cached balance — used when the user
  /// deletes a wallet so we don't leak its balance into future
  /// pickers if they later create a wallet that recycles the id.
  static void delete(String walletId) {
    _lastUpdated.remove(walletId);
    final box = _box;
    if (box == null) return;
    try {
      box.delete(walletId);
    } catch (_) {}
  }

  static Map<String, dynamic> _toJson(WalletBalance b, DateTime ts) => {
        'onchain': b.onChainBtcBalance,
        'spark': b.sparkBitcoinbalance,
        'usdb': b.usdbBalance,
        'ts': ts.millisecondsSinceEpoch,
      };

  static _DecodedEntry? _decode(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return null;
      final tsMs = j['ts'];
      return _DecodedEntry(
        balance: WalletBalance(
          onChainBtcBalance: (j['onchain'] as num?)?.toInt() ?? 0,
          sparkBitcoinbalance: (j['spark'] as num?)?.toInt() ?? 0,
          usdbBalance: (j['usdb'] as num?)?.toInt() ?? 0,
        ),
        lastUpdated: tsMs is num
            ? DateTime.fromMillisecondsSinceEpoch(tsMs.toInt())
            : null,
      );
    } catch (_) {
      return null;
    }
  }
}

class _DecodedEntry {
  final WalletBalance balance;
  final DateTime? lastUpdated;
  _DecodedEntry({required this.balance, this.lastUpdated});
}
