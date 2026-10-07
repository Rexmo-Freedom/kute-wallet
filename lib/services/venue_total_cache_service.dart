// lib/services/venue_total_cache_service.dart
//
// The last venue total (Predictions, Investing) each wallet's balance
// header showed, persisted in Hive, so the header never falls back to a
// bare dash: while a read is on its way, or after one failed, it shows
// the last known figure, dimmed, until the next sync or pull-to-refresh
// brings a fresh one. Keyed by wallet id and venue, so a Ledger's total
// never stands in for the spending account's. Best effort: a box that
// is not open reads as nothing cached and writes nothing.

import 'package:hive_ce/hive.dart';

class VenueTotalCacheService {
  static const boxName = 'venue_total_cache';

  static Box<double>? get _box {
    try {
      if (!Hive.isBoxOpen(boxName)) return null;
      return Hive.box<double>(boxName);
    } catch (_) {
      return null;
    }
  }

  static String _key(String walletId, String venue) => '$walletId|$venue';

  /// The last total stored for [walletId]'s [venue] ('predictions' or
  /// 'trading'), or null when there is none.
  static double? read(String walletId, String venue) {
    try {
      final value = _box?.get(_key(walletId, venue));
      return value != null && value.isFinite ? value : null;
    } catch (_) {
      return null;
    }
  }

  /// Stores [value] as [walletId]'s last known [venue] total; touches the
  /// disk only when it changed.
  static void write(String walletId, String venue, double value) {
    final box = _box;
    if (box == null || !value.isFinite) return;
    try {
      final key = _key(walletId, venue);
      if (box.get(key) == value) return;
      box.put(key, value);
    } catch (_) {
      // Best effort: the header still shows the fresh figure.
    }
  }

  /// Forgets every venue total of [walletId] (the wallet was deleted).
  static Future<void> deleteWallet(String walletId) async {
    final box = _box;
    if (box == null) return;
    try {
      final keys =
          box.keys.where((k) => k.toString().startsWith('$walletId|')).toList();
      await box.deleteAll(keys);
    } catch (_) {}
  }
}

/// What a venue balance header shows as its total: the fresh figure when
/// there is one (stored as the last known), else the last known one,
/// [stale]. Null [value]: nothing known at all.
class VenueTotal {
  const VenueTotal(this.value, {this.stale = false});
  final double? value;
  final bool stale;
}

/// [fresh] for [walletId]'s [venue] (null: not read yet, or the read
/// failed), falling back to the last known total. A null [walletId] (no
/// wallet resolved yet) neither reads nor writes the cache.
VenueTotal resolveVenueTotal(
    {required String? walletId,
    required String venue,
    required double? fresh}) {
  if (fresh != null && fresh.isFinite) {
    if (walletId != null) VenueTotalCacheService.write(walletId, venue, fresh);
    return VenueTotal(fresh);
  }
  final cached =
      walletId == null ? null : VenueTotalCacheService.read(walletId, venue);
  return VenueTotal(cached, stale: cached != null);
}
