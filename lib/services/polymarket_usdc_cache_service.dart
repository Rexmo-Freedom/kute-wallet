// lib/services/polymarket_usdc_cache_service.dart
//
// Persists the user's last-known USDC.e balance (Polymarket Safe on
// Polygon) to Hive so it survives app restarts AND `polymarketTrading
// Provider` rebuilds. The trading provider goes through `AsyncLoading`
// every time the active wallet changes — which used to flash $0.00 in
// the wallet picker, send sheet, and home card while the new state
// was being fetched. This cache holds the last good value and the
// display layer reads from it whenever the provider is between fresh
// reads.

import 'package:hive_ce/hive.dart';

class PolymarketUsdcCacheService {
  static const _boxName = 'polymarket_usdc_cache';
  static const _key = 'usdc_balance';

  static Box<double>? get _box {
    try {
      if (!Hive.isBoxOpen(_boxName)) return null;
      return Hive.box<double>(_boxName);
    } catch (_) {
      return null;
    }
  }

  /// Last-known USDC balance in dollars. Returns 0 when nothing is
  /// cached or when the box failed to open (best-effort: never throw).
  static double read() {
    final box = _box;
    if (box == null) return 0;
    try {
      return box.get(_key, defaultValue: 0.0) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Persist [value] as the new last-known balance. Idempotent — the
  /// caller can call this on every successful trading-state read; we
  /// only actually hit disk if the value changed.
  static void write(double value) {
    final box = _box;
    if (box == null) return;
    try {
      final current = box.get(_key, defaultValue: 0.0) ?? 0;
      if (current == value) return;
      box.put(_key, value);
    } catch (_) {
      // Disk full / locked box / etc. The caller's in-memory state
      // is unaffected — caching is best-effort observability.
    }
  }
}
