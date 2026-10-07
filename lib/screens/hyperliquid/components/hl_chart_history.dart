// lib/screens/hyperliquid/components/hl_chart_history.dart
//
// Older candles for the Hyperliquid detail chart, loaded page by page as
// the user pans (or pinches out) past the oldest bar on screen.
//
// The live candle provider seeds the newest bars and keeps them ticking;
// this pager walks back from there with candleSnapshot's startTime /
// endTime, one page of [HlChartHistory.pageBars] at a time, and keeps
// the pages for the session per (wire coin, interval) so reopening a
// market or switching back to an interval costs nothing.
//
// Rate limits: one request in flight per series, at least
// [HlChartHistory.minGap] between any two requests, and a series stops
// asking once the venue has nothing older (it serves the newest 5000
// candles per interval) or [HlChartHistory.maxBars] are loaded.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:kute/constants/hyperliquid_constants.dart';
import 'package:kute/models/hyperliquid_model.dart';

class _HistorySeries {
  List<HyperliquidCandle> bars = const [];
  bool loading = false;
  bool exhausted = false;
}

class HlChartHistory {
  HlChartHistory._();

  static const int pageBars = 500;
  static const int maxBars = 5000;
  static const Duration minGap = Duration(milliseconds: 1500);

  /// Series kept for the session; the oldest is dropped past this many.
  static const int _maxSeries = 16;

  static final Map<String, _HistorySeries> _series = {};
  static DateTime _lastRequest = DateTime(0);

  static String _key(String wireCoin, String interval) => '$wireCoin|$interval';

  /// Bars loaded before the live seed, ascending. The list identity only
  /// changes when a page lands, so hosts can memoize on it.
  static List<HyperliquidCandle> older(String wireCoin, String interval) =>
      _series[_key(wireCoin, interval)]?.bars ?? const [];

  /// Loads one page of bars that open before [beforeMs]. Returns how many
  /// new bars arrived (0 while throttled, loading, or at the start of the
  /// venue's history).
  static Future<int> loadOlder({
    required String wireCoin,
    required String interval,
    required int intervalMinutes,
    required int beforeMs,
    http.Client? client,
  }) async {
    final key = _key(wireCoin, interval);
    var series = _series.remove(key);
    if (series == null && _series.length >= _maxSeries) {
      _series.remove(_series.keys.first);
    }
    series ??= _HistorySeries();
    _series[key] = series; // most recently used last
    if (series.loading || series.exhausted) return 0;
    final now = DateTime.now();
    if (now.difference(_lastRequest) < minGap) return 0;
    _lastRequest = now;

    final have = series.bars;
    final endMs = (have.isNotEmpty
            ? (have.first.openTime.millisecondsSinceEpoch < beforeMs
                ? have.first.openTime.millisecondsSinceEpoch
                : beforeMs)
            : beforeMs) -
        1;
    final bucketMs = intervalMinutes * 60000;
    series.loading = true;
    try {
      var page = await _fetch(
        client,
        wireCoin: wireCoin,
        interval: interval,
        startMs: endMs - pageBars * bucketMs,
        endMs: endMs,
      );
      // Thin markets only return traded buckets, so a quiet stretch can
      // come back empty with older trades behind it: look once further.
      if (page.isEmpty) {
        page = await _fetch(
          client,
          wireCoin: wireCoin,
          interval: interval,
          startMs: endMs - pageBars * 8 * bucketMs,
          endMs: endMs,
        );
      }
      page = [
        for (final k in page)
          if (k.openTime.millisecondsSinceEpoch <= endMs) k
      ];
      if (page.isEmpty) {
        series.exhausted = true;
        return 0;
      }
      series.bars = List.unmodifiable([...page, ...have]);
      if (series.bars.length >= maxBars) series.exhausted = true;
      return page.length;
    } catch (_) {
      // A failed page is retried on the next pull.
      return 0;
    } finally {
      series.loading = false;
    }
  }

  static Future<List<HyperliquidCandle>> _fetch(
    http.Client? client, {
    required String wireCoin,
    required String interval,
    required int startMs,
    required int endMs,
  }) async {
    const headers = {'content-type': 'application/json'};
    final body = jsonEncode({
      'type': 'candleSnapshot',
      'req': {
        'coin': wireCoin,
        'interval': interval,
        'startTime': startMs,
        'endTime': endMs,
      },
    });
    final request = client != null
        ? client.post(HyperliquidConstants.infoUri, headers: headers, body: body)
        : http.post(HyperliquidConstants.infoUri, headers: headers, body: body);
    final resp = await request.timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw StateError('candleSnapshot ${resp.statusCode}');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! List) return const [];
    final out = <HyperliquidCandle>[];
    for (final raw in decoded) {
      if (raw is! Map<String, dynamic>) continue;
      final t = (raw['t'] as num?)?.toInt();
      final tClose = (raw['T'] as num?)?.toInt();
      if (t == null || tClose == null) continue;
      out.add(HyperliquidCandle(
        openTime: DateTime.fromMillisecondsSinceEpoch(t),
        closeTime: DateTime.fromMillisecondsSinceEpoch(tClose),
        open: double.tryParse(raw['o']?.toString() ?? '') ?? 0,
        high: double.tryParse(raw['h']?.toString() ?? '') ?? 0,
        low: double.tryParse(raw['l']?.toString() ?? '') ?? 0,
        close: double.tryParse(raw['c']?.toString() ?? '') ?? 0,
        volume: double.tryParse(raw['v']?.toString() ?? '') ?? 0,
      ));
    }
    out.sort((a, b) => a.openTime.compareTo(b.openTime));
    return out;
  }
}
