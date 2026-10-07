// lib/services/hyperliquid/hl_markets_disk_cache.dart
//
// The last market lists Hyperliquid answered, on disk, so the Investing
// list paints at once on the next open while the live lists load. Prices
// in the cached rows are stale by definition; the live rows replace them
// as soon as they arrive.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/hyperliquid_market.dart';

class HlMarketsDiskCache {
  HlMarketsDiskCache._();
  static final instance = HlMarketsDiskCache._();

  static const boxName = 'hyperliquid_markets_cache_v1';

  /// Older than this the snapshot is not worth painting: the universe may
  /// have changed and every price on it is from another day.
  static const maxAge = Duration(days: 3);

  List<HlMarket>? _perps;
  List<HlMarket>? _spots;
  bool _loaded = false;

  List<HlMarket>? get perps => _perps;
  List<HlMarket>? get spots => _spots;

  Box<String>? _box() {
    try {
      return Hive.isBoxOpen(boxName) ? Hive.box<String>(boxName) : null;
    } catch (_) {
      return null;
    }
  }

  /// Reads both lists from disk once; later calls are free.
  void load() {
    if (_loaded) return;
    _loaded = true;
    _perps = _read('perps');
    _spots = _read('spots');
  }

  List<HlMarket>? _read(String key) {
    final box = _box();
    if (box == null) return null;
    try {
      final raw = box.get(key);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final savedAt = DateTime.fromMillisecondsSinceEpoch(
          (decoded['savedAt'] as num?)?.toInt() ?? 0);
      if (DateTime.now().difference(savedAt) > maxAge) return null;
      final rows = decoded['rows'];
      if (rows is! List) return null;
      final out = <HlMarket>[];
      for (final r in rows) {
        if (r is! Map<String, dynamic>) continue;
        final m = HlMarket.fromCacheJson(r);
        if (m != null) out.add(m);
      }
      return out.isEmpty ? null : out;
    } catch (e) {
      if (kDebugMode) debugPrint('[hl-cache] $key unreadable: $e');
      return null;
    }
  }

  /// The venue's reference answers (the builder dex list, the market
  /// annotations) change rarely, and a dex keeps its position for life,
  /// so the last good answer stays usable far longer than a price list.
  static const referenceMaxAge = Duration(days: 30);

  /// The last good raw answer saved under [key], or null.
  String? readReference(String key) {
    final box = _box();
    if (box == null) return null;
    try {
      final raw = box.get('ref_$key');
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final savedAt = DateTime.fromMillisecondsSinceEpoch(
          (decoded['savedAt'] as num?)?.toInt() ?? 0);
      if (DateTime.now().difference(savedAt) > referenceMaxAge) return null;
      final body = decoded['body'];
      return body is String && body.isNotEmpty ? body : null;
    } catch (e) {
      if (kDebugMode) debugPrint('[hl-cache] ref $key unreadable: $e');
      return null;
    }
  }

  /// Keeps [body] (the venue's JSON answer, public data) under [key].
  Future<void> saveReference(String key, String body) async {
    final box = _box();
    if (box == null) return;
    try {
      await box.put(
          'ref_$key',
          jsonEncode({
            'savedAt': DateTime.now().millisecondsSinceEpoch,
            'body': body,
          }));
    } catch (e) {
      if (kDebugMode) debugPrint('[hl-cache] ref $key not saved: $e');
    }
  }

  Future<void> savePerps(List<HlMarket> markets) =>
      _write('perps', markets, (m) => _perps = m);
  Future<void> saveSpots(List<HlMarket> markets) =>
      _write('spots', markets, (m) => _spots = m);

  Future<void> _write(String key, List<HlMarket> markets,
      void Function(List<HlMarket>) remember) async {
    if (markets.isEmpty) return;
    remember(markets);
    final box = _box();
    if (box == null) return;
    try {
      await box.put(
          key,
          jsonEncode({
            'savedAt': DateTime.now().millisecondsSinceEpoch,
            'rows': markets.map((m) => m.toCacheJson()).toList(),
          }));
    } catch (e) {
      if (kDebugMode) debugPrint('[hl-cache] $key not saved: $e');
    }
  }
}
