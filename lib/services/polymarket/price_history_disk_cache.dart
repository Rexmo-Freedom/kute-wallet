// lib/services/polymarket/price_history_disk_cache.dart
//
// The Predictions chart's last history per (token, range), on disk, so a
// market opened again in a later session draws its lines at once while
// the Data API answers (the session cache, PolyPriceHistoryCache, covers
// reopening within the same session). A disk series is only ever drawn as
// a stale one: the read runs as it would anyway and replaces it.
//
// Public market data only: token ids, times and prices. Nothing about the
// person's account is written here.
//
// The box is opened on the first chart, never at launch, and kept small
// ([maxEntries] series, oldest saved dropped first).

import 'dart:async';
import 'dart:convert';

import 'package:hive_ce/hive.dart';

import 'package:kute/models/polymarket_model.dart';

class PolyPriceHistoryDiskCache {
  PolyPriceHistoryDiskCache._();

  static const boxName = 'polymarket_price_history_v1';
  static const int maxEntries = 48;
  static const int _version = 1;

  /// How old a saved series may be and still be drawn while the read
  /// runs: about the range's own span at most, so a stale line never
  /// looks like a different market.
  static Duration maxAgeFor(String interval) => switch (interval) {
        '1h' => const Duration(minutes: 10),
        '6h' => const Duration(minutes: 30),
        '1d' => const Duration(hours: 2),
        '1w' => const Duration(hours: 12),
        _ => const Duration(days: 2), // 1M, ALL
      };

  static Future<Box<String>?>? _opening;

  static Future<Box<String>?> _box() => _opening ??= () async {
        try {
          if (Hive.isBoxOpen(boxName)) return Hive.box<String>(boxName);
          return await Hive.openBox<String>(boxName);
        } catch (_) {
          // No Hive (a test) or a damaged box: no disk cache.
          return null;
        }
      }();

  static String _key(String tokenId, String interval) => '$tokenId|$interval';

  /// Opens the box ahead of the first read (a sheet about to open).
  static void warmUp() => unawaited(_box());

  /// The saved series and when it was saved, or null when there is none
  /// young enough for [interval].
  static Future<({List<PolymarketPricePoint> points, DateTime at})?> read(
      String tokenId, String interval) async {
    try {
      final box = await _box();
      final raw = box?.get(_key(tokenId, interval));
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['v'] != _version) return null;
      final at = DateTime.fromMillisecondsSinceEpoch(
          (decoded['at'] as num?)?.toInt() ?? 0);
      if (DateTime.now().difference(at) > maxAgeFor(interval)) return null;
      final t = decoded['t'], p = decoded['p'];
      if (t is! List || p is! List || t.length != p.length || t.length < 2) {
        return null;
      }
      return (
        points: List<PolymarketPricePoint>.unmodifiable([
          for (var i = 0; i < t.length; i++)
            PolymarketPricePoint(
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                  (t[i] as num).toInt() * 1000),
              price: (p[i] as num).toDouble(),
            ),
        ]),
        at: at,
      );
    } catch (_) {
      return null;
    }
  }

  /// Saves [points] for (token, range); drops the oldest saved past
  /// [maxEntries].
  static Future<void> write(String tokenId, String interval,
      List<PolymarketPricePoint> points) async {
    if (points.length < 2) return;
    try {
      final box = await _box();
      if (box == null) return;
      final key = _key(tokenId, interval);
      await box.put(
          key,
          jsonEncode({
            'v': _version,
            'at': DateTime.now().millisecondsSinceEpoch,
            't': [
              for (final x in points) x.timestamp.millisecondsSinceEpoch ~/ 1000
            ],
            'p': [for (final x in points) x.price],
          }));
      if (box.length > maxEntries) {
        final ages = <String, int>{};
        for (final k in box.keys) {
          final raw = box.get(k);
          final at = raw == null
              ? 0
              : (RegExp(r'"at":(\d+)').firstMatch(raw)?.group(1) ?? '0');
          ages['$k'] = int.tryParse('$at') ?? 0;
        }
        final oldest = ages.keys.toList()
          ..sort((a, b) => ages[a]!.compareTo(ages[b]!));
        await box.deleteAll(oldest.take(box.length - maxEntries));
      }
    } catch (_) {
      // Best effort: the session cache still has it.
    }
  }
}
