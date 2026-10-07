// lib/models/hyperliquid_model.dart
//
// Thin client for Hyperliquid's public `info` endpoint. All requests are
// POST to `<apiBase>/info` with a JSON body of `{"type": "<query>"}` — the
// same shape their docs describe. No trading, no auth (trading lives in
// services/hyperliquid/hyperliquid_exchange_service.dart).
//
// Two generations of read methods coexist here on purpose:
//   * legacy rail methods (getTickers/getSpotTickers/getCandles) swallow
//     every failure and return empty — the home rail renders "—" and moves
//     on. Their behavior is frozen; the sparkline callers rely on it.
//   * trading methods (getPerpMarkets/getSpotMarkets/getAccountSnapshot/
//     getOpenOrders/getUserFills/getL2Book) THROW on failure
//     (HyperliquidInfoException for HTTP errors, FormatException for
//     malformed bodies, raw network errors otherwise) so providers can
//     surface real error/retry states instead of rendering an empty
//     account as "you have no positions".

import 'dart:convert';
import 'dart:async';
import 'package:kute/services/revenue/hyperliquid_revenue.dart';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:kute/constants/hyperliquid_constants.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/services/hyperliquid/hl_markets_disk_cache.dart';

/// A non-200 (or structurally empty) response from the `info` endpoint on
/// one of the trading read paths.
class HyperliquidInfoException implements Exception {
  final String message;
  final int? statusCode;

  const HyperliquidInfoException(this.message, {this.statusCode});

  @override
  String toString() =>
      'HyperliquidInfoException(${statusCode ?? '-'}): $message';
}

/// One snapshot of a perp market: mark price, prev-day price (for 24h %),
/// and 24h notional volume.
class HyperliquidTicker {
  final String coin;
  final double markPrice;
  final double prevDayPrice;
  final double dayNotionalVolume;

  const HyperliquidTicker({
    required this.coin,
    required this.markPrice,
    required this.prevDayPrice,
    required this.dayNotionalVolume,
  });

  /// 24h percentage change as a fraction (0.025 == +2.5%). Returns 0 when
  /// the previous price is unavailable so the UI can render "—" safely.
  double get dayChangePct {
    if (prevDayPrice <= 0) return 0;
    return (markPrice - prevDayPrice) / prevDayPrice;
  }
}

/// One OHLC candle from `candleSnapshot`. Only `close` is used by the
/// sparkline today, but the full struct is cheap and keeps us honest if we
/// start drawing real charts later.
class HyperliquidCandle {
  final DateTime openTime;
  final DateTime closeTime;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const HyperliquidCandle({
    required this.openTime,
    required this.closeTime,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });
}

/// UNIT GUARD, shared by every candle consumer (mini chart, pro chart,
/// position PnL curve): HL spot pairs return candles in RAW pair units
/// while the app displays converted prices (UBTC closes ~0.00007 vs a
/// displayed ~110000). When the last close disagrees with [displayPx]
/// by more than 2x, the whole series is rescaled by one uniform factor —
/// shape-preserving, only the axis/labels move. Anything within band is
/// returned untouched. Splicing the display price onto raw closes is the
/// historical bug ("flat line then a rocket at the end") this replaces;
/// never do that instead.
List<HyperliquidCandle> rescaleCandlesToDisplay(
  List<HyperliquidCandle> candles,
  double displayPx,
) {
  if (candles.isEmpty || displayPx <= 0) return candles;
  final last = candles.last.close;
  if (last <= 0) return candles;
  final ratio = displayPx / last;
  if (ratio >= 0.5 && ratio <= 2.0) return candles;
  return candles
      .map((k) => HyperliquidCandle(
            openTime: k.openTime,
            closeTime: k.closeTime,
            open: k.open * ratio,
            high: k.high * ratio,
            low: k.low * ratio,
            close: k.close * ratio,
            volume: k.volume,
          ))
      .toList(growable: false);
}

/// The live-feel counterpart: folds the current display price into the
/// LEADING candle (close follows the price, high/low stretch to include
/// it) so the rightmost bar ticks with the header even when no trade has
/// printed — thin HIP-3 equities would otherwise freeze between trades.
/// Call AFTER [rescaleCandlesToDisplay] so both are in display units.
List<HyperliquidCandle> foldDisplayPxIntoLastCandle(
  List<HyperliquidCandle> candles,
  double displayPx,
) {
  if (candles.isEmpty || displayPx <= 0) return candles;
  final last = candles.last;
  if (last.close == displayPx) return candles;
  // Only fold a price that plausibly belongs to this candle's units —
  // a >2x disagreement means the rescale guard didn't run first.
  if (last.close > 0) {
    final ratio = displayPx / last.close;
    if (ratio < 0.5 || ratio > 2.0) return candles;
  }
  final out = List<HyperliquidCandle>.from(candles);
  out[out.length - 1] = HyperliquidCandle(
    openTime: last.openTime,
    closeTime: last.closeTime,
    open: last.open,
    high: last.high > displayPx ? last.high : displayPx,
    low: last.low < displayPx ? last.low : displayPx,
    close: displayPx,
    volume: last.volume,
  );
  return out;
}

/// The candles a market's chart draws from [candles] and the live display
/// price [displayPx]: rescaled onto display units, then with the live
/// price folded into the leading bar ([foldDisplayPxIntoLastCandle]) so
/// the chart ticks with the header. Not on a low-liquidity market
/// ([lowLiquidity]): with no trades its mid can sit ten percent from the
/// last print, and folding it drew a cliff at the end of every line and a
/// bar as tall as the gap. There the chart ends at the last traded price
/// and the header keeps the mid.
List<HyperliquidCandle> chartCandlesWithLive(
  List<HyperliquidCandle> candles,
  double displayPx, {
  required bool lowLiquidity,
}) {
  final scaled = rescaleCandlesToDisplay(candles, displayPx);
  return lowLiquidity ? scaled : foldDisplayPxIntoLastCandle(scaled, displayPx);
}

/// One builder (HIP-3) perp dex from the `perpDexs` list, with its POSITION
/// in that list preserved. [index] is the dexIndex the HIP-3 asset-id formula
/// (100000 + dexIndex*10000 + indexInMeta) needs; the default (crypto) dex is
/// index 0 (a null entry) and is never represented here.
class HlPerpDex {
  final String name;
  final String fullName;
  final int index;

  const HlPerpDex({
    required this.name,
    required this.fullName,
    required this.index,
  });
}

/// Every perp market the venue answered for, and whether that is all of
/// them. [complete] is false when the builder dex list or a builder dex's
/// markets could not be read and no earlier answer stood in: the list is
/// then short of builder (HIP-3) markets, not a smaller venue.
/// [annotated] is false when the venue's categories could not be read,
/// live or remembered: builder markets then carry no asset class.
class HlPerpCatalogue {
  final List<HlMarket> markets;
  final bool complete;
  final bool annotated;

  /// Names of every builder dex the venue lists, in its order; empty when
  /// the list could not be read. A dex whose markets are all delisted is
  /// here and has no market in [markets].
  final List<String> dexes;

  const HlPerpCatalogue({
    required this.markets,
    required this.complete,
    required this.annotated,
    this.dexes = const [],
  });
}

class HyperliquidModel {
  /// [client] is injectable for tests; null uses the global `http.post`
  /// exactly as before.
  HyperliquidModel({http.Client? client}) : _client = client;

  final http.Client? _client;
  List<String>? _usdcDexNames;
  DateTime? _usdcDexNamesAt;

  static Uri get _infoUri => HyperliquidConstants.infoUri;

  Future<http.Response> _info(Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 15)}) {
    const headers = {'content-type': 'application/json'};
    final encoded = jsonEncode(body);
    final client = _client;
    final request = client != null
        ? client.post(_infoUri, headers: headers, body: encoded)
        : http.post(_infoUri, headers: headers, body: encoded);
    return request.timeout(timeout);
  }

  /// Fetch mark price + prev-day price + 24h volume for every perp in
  /// parallel. Returned as a map keyed by coin so callers can cheaply look
  /// up the subset they render on the home rail.
  Future<Map<String, HyperliquidTicker>> getTickers() async {
    try {
      final resp = await _info({'type': 'metaAndAssetCtxs'});
      if (resp.statusCode != 200) return {};
      final decoded = jsonDecode(resp.body);
      if (decoded is! List || decoded.length < 2) return {};

      final meta = decoded[0] as Map<String, dynamic>;
      final ctxs = decoded[1] as List;
      final universe = (meta['universe'] as List?) ?? const [];

      final out = <String, HyperliquidTicker>{};
      for (var i = 0; i < universe.length && i < ctxs.length; i++) {
        final u = universe[i] as Map<String, dynamic>;
        final c = ctxs[i] as Map<String, dynamic>;
        final name = (u['name'] as String?) ?? '';
        if (name.isEmpty) continue;
        out[name] = HyperliquidTicker(
          coin: name,
          markPrice: double.tryParse(c['markPx']?.toString() ?? '') ?? 0,
          prevDayPrice:
              double.tryParse(c['prevDayPx']?.toString() ?? '') ?? 0,
          dayNotionalVolume:
              double.tryParse(c['dayNtlVlm']?.toString() ?? '') ?? 0,
        );
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Fetch spot tickers keyed by token name (e.g. "AAPL" → ticker). HL's
  /// equity tokens (AAPL, NVDA, TSLA, SPY, ...) and commodity proxies
  /// (GLD, SLV, XAUT0) live on spot rather than perps; the universe is a
  /// list of pairs named `@<index>`, while the token metadata carries the
  /// human-readable symbol. We resolve the pair for each token so callers
  /// can ask for "AAPL" without knowing the pair index.
  ///
  /// `pairNameByToken` on the returned record lets callers turn a token
  /// name into the `@<index>` coin string required by `candleSnapshot`.
  Future<({
    Map<String, HyperliquidTicker> tickers,
    Map<String, String> pairNameByToken,
  })> getSpotTickers() async {
    try {
      final resp = await _info({'type': 'spotMetaAndAssetCtxs'});
      if (resp.statusCode != 200) {
        return (tickers: <String, HyperliquidTicker>{}, pairNameByToken: <String, String>{});
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! List || decoded.length < 2) {
        return (tickers: <String, HyperliquidTicker>{}, pairNameByToken: <String, String>{});
      }

      final meta = decoded[0] as Map<String, dynamic>;
      final ctxs = decoded[1] as List;
      final tokens = (meta['tokens'] as List?) ?? const [];
      final universe = (meta['universe'] as List?) ?? const [];

      // Build index→tokenName map so we can resolve pair.tokens[0] → name.
      final tokenNameByIndex = <int, String>{};
      for (final t in tokens) {
        if (t is! Map<String, dynamic>) continue;
        final idx = (t['index'] as num?)?.toInt();
        final name = (t['name'] as String?) ?? '';
        if (idx != null && name.isNotEmpty) {
          tokenNameByIndex[idx] = name;
        }
      }

      // Contexts name their pair in `coin` and are not in universe
      // order (see HlMarket.parseSpotList); position is the fallback.
      final ctxByCoin = <String, Map<String, dynamic>>{};
      for (final c in ctxs) {
        if (c is! Map<String, dynamic>) continue;
        final coin = c['coin'];
        if (coin is String && coin.isNotEmpty) ctxByCoin[coin] = c;
      }

      final tickers = <String, HyperliquidTicker>{};
      final pairNameByToken = <String, String>{};
      for (var i = 0; i < universe.length; i++) {
        final u = universe[i] as Map<String, dynamic>;
        final pairName = (u['name'] as String?) ?? '';
        final Map<String, dynamic>? c = ctxByCoin.isNotEmpty
            ? ctxByCoin[pairName]
            : (i < ctxs.length ? ctxs[i] as Map<String, dynamic> : null);
        if (c == null) continue;
        final pairTokens = (u['tokens'] as List?) ?? const [];
        if (pairTokens.isEmpty) continue;
        final baseIdx = (pairTokens[0] as num?)?.toInt();
        if (baseIdx == null) continue;
        final baseName = tokenNameByIndex[baseIdx];
        if (baseName == null || baseName.isEmpty) continue;

        tickers[baseName] = HyperliquidTicker(
          coin: baseName,
          markPrice: double.tryParse(c['markPx']?.toString() ?? '') ?? 0,
          prevDayPrice:
              double.tryParse(c['prevDayPx']?.toString() ?? '') ?? 0,
          dayNotionalVolume:
              double.tryParse(c['dayNtlVlm']?.toString() ?? '') ?? 0,
        );
        if (pairName.isNotEmpty) pairNameByToken[baseName] = pairName;
      }
      return (tickers: tickers, pairNameByToken: pairNameByToken);
    } catch (_) {
      return (tickers: <String, HyperliquidTicker>{}, pairNameByToken: <String, String>{});
    }
  }

  /// Short price history for one coin — used to paint the sparkline. The
  /// default window (`interval: 1h`, trailing 24h) gives ~24 points, which
  /// is plenty for a 60×24-ish strip and keeps each request tiny.
  Future<List<HyperliquidCandle>> getCandles({
    required String coin,
    String interval = '1h',
    Duration window = const Duration(hours: 24),
  }) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final start = now - window.inMilliseconds;
      final resp = await _info({
        'type': 'candleSnapshot',
        'req': {
          'coin': coin,
          'interval': interval,
          'startTime': start,
          'endTime': now,
        },
      });
      if (resp.statusCode != 200) return const [];
      final decoded = jsonDecode(resp.body);
      if (decoded is! List) return const [];

      return decoded.map<HyperliquidCandle?>((raw) {
        if (raw is! Map<String, dynamic>) return null;
        return HyperliquidCandle(
          openTime: DateTime.fromMillisecondsSinceEpoch(
              (raw['t'] as num?)?.toInt() ?? 0),
          closeTime: DateTime.fromMillisecondsSinceEpoch(
              (raw['T'] as num?)?.toInt() ?? 0),
          open: double.tryParse(raw['o']?.toString() ?? '') ?? 0,
          high: double.tryParse(raw['h']?.toString() ?? '') ?? 0,
          low: double.tryParse(raw['l']?.toString() ?? '') ?? 0,
          close: double.tryParse(raw['c']?.toString() ?? '') ?? 0,
          volume: double.tryParse(raw['v']?.toString() ?? '') ?? 0,
        );
      }).whereType<HyperliquidCandle>().toList();
    } catch (_) {
      return const [];
    }
  }

  /// Hourly funding rates of one perp over the trailing [window], oldest
  /// first (`fundingHistory`; the venue returns at most 500 entries, about
  /// 20 days). Empty on any failure: the chart's funding markers are an
  /// extra, never a reason to fail.
  Future<List<({int timeMs, double rate})>> getFundingHistory({
    required String coin,
    Duration window = const Duration(days: 20),
  }) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final resp = await _info({
        'type': 'fundingHistory',
        'coin': coin,
        'startTime': now - window.inMilliseconds,
      });
      if (resp.statusCode != 200) return const [];
      final decoded = jsonDecode(resp.body);
      if (decoded is! List) return const [];
      final out = <({int timeMs, double rate})>[];
      for (final raw in decoded) {
        if (raw is! Map<String, dynamic>) continue;
        final time = (raw['time'] as num?)?.toInt();
        final rate = double.tryParse(raw['fundingRate']?.toString() ?? '');
        if (time == null || rate == null) continue;
        out.add((timeMs: time, rate: rate));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  // ──────────────────── trading reads (throwing) ────────────────────
  // Unlike the rail methods above, everything below THROWS on failure —
  // see the header comment for the rationale.

  /// Decoded body of an `info` POST, or throws [HyperliquidInfoException]
  /// on a non-200 status. Network/timeout errors propagate as-is.
  Future<dynamic> _infoOrThrow(Map<String, dynamic> body) async {
    final resp = await _info(body);
    if (resp.statusCode != 200) {
      throw HyperliquidInfoException(
        'info ${body['type']} failed',
        statusCode: resp.statusCode,
      );
    }
    return jsonDecode(resp.body);
  }

  /// Every live perp on the DEFAULT (crypto) dex with trading metadata
  /// (assetId = universe position, szDecimals, maxLeverage, onlyIsolated) +
  /// price context. For the FULL merged universe (default + every builder /
  /// HIP-3 dex) use [getAllPerpMarkets].
  Future<List<HlMarket>> getPerpMarkets() async {
    return HlMarket.parsePerpList(
        await _infoOrThrow({'type': 'metaAndAssetCtxs'}));
  }

  /// The main perp dex only: one meta call plus the annotations, enough to
  /// paint the list while the builder dexes are still answering.
  Future<List<HlMarket>> getCorePerpMarkets() async {
    // Future.wait listens to both at once: a meta failure that lands while
    // the annotations are still in flight is delivered here, not reported
    // as an unhandled async error.
    final results = await Future.wait<dynamic>(
        [_infoOrThrow({'type': 'metaAndAssetCtxs'}), getPerpAnnotations()]);
    return HlMarket.parsePerpList(results[0],
        annotations: results[1] as Map<String, HlPerpAnnotation>);
  }

  // ── builder dex catalogue cache ─────────────────────────────────────
  // The HIP-3 dexes (mkts, km, cash, vntl, xyz, hyna, io, abcd, flx, para…)
  // each cost an `info` call, and the perp list refreshes every 30 s. Firing
  // all of them in one wave on every refresh tripped Hyperliquid's rate limit
  // (HTTP 429) and logged a failure per dex per refresh. Their catalogues
  // barely change, and live prices arrive over the socket, so each dex's
  // meta is kept for [_builderMetaTtl], the wave is spaced out, and a 429
  // pauses builder reads for a growing window while the stale copy serves.
  static final Map<String, ({DateTime at, dynamic decoded})> _builderMeta = {};
  static const Duration _builderMetaTtl = Duration(minutes: 5);
  static DateTime? _builderBackoffUntil;
  static Duration _builderBackoff = const Duration(seconds: 60);
  static Future<HlPerpCatalogue>? _allPerpInFlight;
  static const int _builderBatchSize = 3;
  static const Duration _builderBatchGap = Duration(milliseconds: 250);

  /// Test hook: forget the builder dex cache and any rate-limit pause.
  @visibleForTesting
  static void resetBuilderCache() {
    _builderMeta.clear();
    _builderBackoffUntil = null;
    _builderBackoff = const Duration(seconds: 60);
    _allPerpInFlight = null;
    _reference.clear();
    _referenceRefresh.clear();
  }

  /// Every perp dex. The default dex, annotations and dex list go out
  /// together; builder dex metas come from the cache when fresh, otherwise in
  /// small spaced batches. Concurrent callers share one in-flight load.
  Future<List<HlMarket>> getAllPerpMarkets() =>
      getPerpCatalogue().then((c) => c.markets);

  /// [getAllPerpMarkets] with whether the answer is whole: see
  /// [HlPerpCatalogue].
  Future<HlPerpCatalogue> getPerpCatalogue() {
    final inFlight = _allPerpInFlight;
    if (inFlight != null) return inFlight;
    final run = _loadAllPerpMarkets().whenComplete(() => _allPerpInFlight = null);
    _allPerpInFlight = run;
    return run;
  }

  Future<HlPerpCatalogue> _loadAllPerpMarkets() async {
    // All three go out together; Future.wait listens to each from the start
    // so a failed main meta is thrown from here rather than surfacing as an
    // unhandled async error while the other two are still answering.
    final results = await Future.wait<dynamic>([
      _infoOrThrow({'type': 'metaAndAssetCtxs'}),
      _perpAnnotationsOrNull(),
      _perpDexsOrNull(),
    ]);
    final ann = results[1] as Map<String, HlPerpAnnotation>?;
    final dexes = results[2] as List<HlPerpDex>?;
    final out = HlMarket.parsePerpList(
      results[0],
      annotations: ann,
    );
    final metas = await _builderMetas(dexes ?? const []);
    for (final r in metas) {
      out.addAll(HlMarket.parsePerpList(
        r.decoded,
        dex: r.dex.name,
        dexIndex: r.dex.index,
        annotations: ann,
      ));
    }
    return HlPerpCatalogue(
      markets: out,
      complete: dexes != null && metas.length == dexes.length,
      annotated: ann != null,
      dexes: [for (final d in dexes ?? const <HlPerpDex>[]) d.name],
    );
  }

  /// Builder dex metas: cached copies first, then the stale ones fetched in
  /// batches of [_builderBatchSize] with a short gap. A 429 stops the wave,
  /// starts the backoff and leaves the stale copies (if any) in place.
  Future<List<({HlPerpDex dex, dynamic decoded})>> _builderMetas(
      List<HlPerpDex> dexes) async {
    final now = DateTime.now();
    final results = <({HlPerpDex dex, dynamic decoded})>[];
    final stale = <HlPerpDex>[];
    for (final d in dexes) {
      final hit = _builderMeta[d.name];
      if (hit != null && now.difference(hit.at) < _builderMetaTtl) {
        results.add((dex: d, decoded: hit.decoded));
      } else {
        stale.add(d);
      }
    }
    final paused =
        _builderBackoffUntil != null && now.isBefore(_builderBackoffUntil!);
    if (paused) {
      for (final d in stale) {
        final hit = _builderMeta[d.name];
        if (hit != null) results.add((dex: d, decoded: hit.decoded));
      }
      return results;
    }
    var rateLimited = false;
    for (var start = 0; start < stale.length && !rateLimited; start += _builderBatchSize) {
      if (start > 0) await Future<void>.delayed(_builderBatchGap);
      final batch = stale.skip(start).take(_builderBatchSize);
      final fetched = await Future.wait(batch.map((d) async {
        try {
          final decoded =
              await _infoOrThrow({'type': 'metaAndAssetCtxs', 'dex': d.name});
          _builderMeta[d.name] = (at: DateTime.now(), decoded: decoded);
          return (dex: d, decoded: decoded);
        } on HyperliquidInfoException catch (e) {
          if (e.statusCode == 429) rateLimited = true;
          return null;
        } catch (_) {
          return null;
        }
      }));
      for (var i = 0; i < fetched.length; i++) {
        final r = fetched[i];
        if (r != null) {
          results.add(r);
          continue;
        }
        final d = batch.elementAt(i);
        final hit = _builderMeta[d.name];
        if (hit != null) results.add((dex: d, decoded: hit.decoded));
      }
    }
    if (rateLimited) {
      _builderBackoffUntil = DateTime.now().add(_builderBackoff);
      if (kDebugMode) {
        debugPrint('[hl] builder dex metas rate limited (429); '
            'pausing builder reads for ${_builderBackoff.inSeconds}s');
      }
      if (_builderBackoff < const Duration(minutes: 5)) {
        _builderBackoff *= 2;
      }
      // Anything the wave did not reach still serves from its stale copy.
      final covered = results.map((r) => r.dex.name).toSet();
      for (final d in stale) {
        if (covered.contains(d.name)) continue;
        final hit = _builderMeta[d.name];
        if (hit != null) results.add((dex: d, decoded: hit.decoded));
      }
    } else {
      _builderBackoff = const Duration(seconds: 60);
    }
    return results;
  }

  // ── reference reads: the builder dex list and the annotations ───────
  // One slow or blocked read used to drop every builder (HIP-3) market
  // and every category for the session: a single 15 s wait, no second
  // try, no memory. Each read now gets short attempts with a pause
  // between them, and the last good answer is kept (in memory and on
  // disk, public data) and served whenever the live read fails. With an
  // answer in hand the list never waits on the network: the remembered
  // copy is returned at once and refreshed behind it.
  static const Duration _referenceAttemptTimeout = Duration(seconds: 6);
  static const int _referenceAttempts = 3;
  static const Duration _referenceFreshFor = Duration(minutes: 10);

  /// Pause before the second attempt; the third waits twice as long.
  @visibleForTesting
  static Duration referenceRetryGap = const Duration(milliseconds: 500);

  static final Map<String, ({DateTime at, String body})> _reference = {};
  static final Map<String, Future<void>> _referenceRefresh = {};

  /// Test hook: treat every remembered reference answer as old, so the
  /// next read refreshes it behind the remembered copy.
  @visibleForTesting
  static void ageReferenceForTest() {
    for (final type in _reference.keys.toList()) {
      _reference[type] = (
        at: DateTime.fromMillisecondsSinceEpoch(0),
        body: _reference[type]!.body
      );
    }
  }

  /// The raw JSON answer to the `info` request [type], or null when it
  /// cannot be read and was never read before. [usable] rejects an answer
  /// of the wrong shape so it is neither served nor remembered.
  Future<String?> _referenceBody(
      String type, bool Function(dynamic decoded) usable) async {
    final held = _reference[type];
    if (held != null) {
      if (DateTime.now().difference(held.at) >= _referenceFreshFor) {
        _refreshReference(type, usable);
      }
      return held.body;
    }
    final disk = HlMarketsDiskCache.instance.readReference(type);
    if (disk != null) {
      // From an earlier session: usable now, refreshed behind.
      _reference[type] =
          (at: DateTime.fromMillisecondsSinceEpoch(0), body: disk);
      _refreshReference(type, usable);
      return disk;
    }
    await _refreshReference(type, usable);
    return _reference[type]?.body;
  }

  Future<void> _refreshReference(
      String type, bool Function(dynamic decoded) usable) {
    return _referenceRefresh.putIfAbsent(type, () async {
      try {
        for (var attempt = 0; attempt < _referenceAttempts; attempt++) {
          if (attempt > 0) {
            await Future<void>.delayed(referenceRetryGap * attempt);
          }
          try {
            final resp =
                await _info({'type': type}, timeout: _referenceAttemptTimeout);
            if (resp.statusCode == 200 && usable(jsonDecode(resp.body))) {
              _reference[type] = (at: DateTime.now(), body: resp.body);
              unawaited(
                  HlMarketsDiskCache.instance.saveReference(type, resp.body));
              return;
            }
            if (kDebugMode) {
              debugPrint('[hl] $type attempt ${attempt + 1} answered '
                  '${resp.statusCode}');
            }
            // A rate limit is not helped by asking again at once.
            if (resp.statusCode == 429) return;
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[hl] $type attempt ${attempt + 1} failed: $e');
            }
          }
        }
      } finally {
        _referenceRefresh.remove(type);
      }
    });
  }

  Future<Map<String, HlPerpAnnotation>?> _perpAnnotationsOrNull() async {
    final body = await _referenceBody(
        'perpConciseAnnotations', (d) => d is List);
    if (body == null) return null;
    try {
      return HlPerpAnnotation.parseList(jsonDecode(body));
    } catch (_) {
      return null;
    }
  }

  Future<List<HlPerpDex>?> _perpDexsOrNull() async {
    final body = await _referenceBody('perpDexs', (d) => d is List);
    if (body == null) return null;
    try {
      return _parsePerpDexs(jsonDecode(body));
    } catch (_) {
      return null;
    }
  }

  static List<HlPerpDex> _parsePerpDexs(dynamic decoded) {
    if (decoded is! List) {
      throw const FormatException('unexpected perpDexs shape');
    }
    final out = <HlPerpDex>[];
    for (var i = 0; i < decoded.length; i++) {
      final d = decoded[i];
      if (d is! Map) continue; // index 0 is null → the default dex
      final name = (d['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      out.add(HlPerpDex(
        name: name,
        fullName: (d['fullName'] as String?)?.trim() ?? '',
        index: i,
      ));
    }
    return out;
  }

  /// `perpConciseAnnotations` → [HlPerpAnnotation] keyed by
  /// [HlMarket.annotationKey] ('xyz:TSLA', or the bare symbol for the
  /// default dex): category (normalised), friendly name and keywords. The
  /// wire shape is a list of `[coin, {category, displayName, keywords}]`
  /// pairs. Fail-soft: the last good answer when the live read fails, and
  /// an empty map when there has never been one, so categorization falls
  /// back rather than blocking the catalog.
  Future<Map<String, HlPerpAnnotation>> getPerpAnnotations() async =>
      await _perpAnnotationsOrNull() ?? const {};

  /// `perpDexs` → the builder (HIP-3) perp dexes with their ARRAY POSITIONS
  /// preserved (the dexIndex that drives the HIP-3 asset-id offset). Index 0
  /// of the response is `null` (the default dex) and is skipped. Fail-soft:
  /// the last good answer when the live read fails (a dex keeps its
  /// position for life, so a remembered list can only lack a newer dex),
  /// and an empty list when there has never been one. Anything that signs
  /// or reads an account uses [getPerpDexsStrict].
  Future<List<HlPerpDex>> getPerpDexs() async =>
      await _perpDexsOrNull() ?? const [];

  /// Every USDC-quoted spot pair (FULL universe — no allowlist filtering
  /// here; presentation concerns belong to providers/UI). assetId =
  /// 10000 + pair `index` field; wireCoin is the `@<index>`/canonical pair
  /// name market-data endpoints expect.
  Future<List<HlMarket>> getSpotMarkets() async {
    return HlMarket.parseSpotList(
        await _infoOrThrow({'type': 'spotMetaAndAssetCtxs'}));
  }

  /// Perp clearinghouse summary + open positions + spot balances, fetched
  /// in parallel. Throws if either half fails — a partial snapshot would
  /// silently render as "no positions"/"no balance".
  Future<HlAccountSnapshot> getAccountSnapshot(String address) async {
    final results = await Future.wait([
      _infoOrThrow({'type': 'clearinghouseState', 'user': address}),
      _infoOrThrow({'type': 'spotClearinghouseState', 'user': address}),
    ]);
    final perpState = results[0];
    final spotState = results[1];
    if (perpState is! Map<String, dynamic>) {
      throw const FormatException('unexpected clearinghouseState shape');
    }
    return HlAccountSnapshot.fromJson(
      perpState: perpState,
      spotState: spotState is Map<String, dynamic> ? spotState : null,
    );
  }

  /// Withdrawable USDC on builder DEXs. Collateral identity is read from
  /// each DEX's metadata; a different stablecoin is not interchangeable.
  Future<Map<String, HlAccountSnapshot>> getUsdcDexAccounts(String address) async {
    if (_usdcDexNames == null || _usdcDexNamesAt == null ||
        DateTime.now().difference(_usdcDexNamesAt!) > const Duration(minutes: 5)) {
      final names = <String>[];
      final dexes = await getPerpDexsStrict();
      for (var start = 0; start < dexes.length; start += 8) {
        await Future.wait(dexes.skip(start).take(8).map((dex) async {
          final meta = await _infoOrThrow({'type': 'meta', 'dex': dex.name});
          if (meta is! Map) throw const FormatException('Collateral unavailable');
          if (meta['collateralToken'] == 0) names.add(dex.name);
        }));
      }
      _usdcDexNames = names..sort();
      _usdcDexNamesAt = DateTime.now();
    }
    final names = _usdcDexNames!;
    final result = <String, HlAccountSnapshot>{};
    for (var start = 0; start < names.length; start += 8) {
      await Future.wait(names.skip(start).take(8).map((name) async {
        result[name] = await getDexClearinghouse(address, name);
      }));
    }
    return result;
  }

  /// Portfolio positions span the default and builder perpetual DEXs.
  /// Withdrawable USDC includes builder DEX cash. Execution explicitly moves
  /// the required collateral within the same account before spending it.
  Future<HlAccountSnapshot> getPortfolioSnapshot(String address) async {
    final base = await getAccountSnapshot(address);
    final dexes = await getUsdcDexAccounts(address);
    return HlAccountSnapshot(
        accountValue: base.accountValue + dexes.values.fold<double>(0, (v, s) => v + s.accountValue),
        withdrawable: base.withdrawable + dexes.values.fold<double>(0, (v, s) => v + s.withdrawable),
        totalMarginUsed: base.totalMarginUsed + dexes.values.fold<double>(0, (v, s) => v + s.totalMarginUsed),
        positions: [...base.positions, for (final snapshot in dexes.values) ...snapshot.positions],
        spotBalances: base.spotBalances,
        activeDexes: {
          for (final e in dexes.entries)
            if (e.value.hasActivity) e.key,
        });
  }

  /// Resting orders via `frontendOpenOrders` (carries orderType/trigger
  /// metadata the plain `openOrders` query omits).
  ///
  /// Without `dex` the venue answers for the main perp dex and spot only;
  /// a builder (HIP-3) dex's orders come back only when that dex is named.
  /// So the main read plus one read per builder dex in [dexes] (the ones
  /// the account holds anything on, HlAccountSnapshot.activeDexes), merged
  /// by order id, newest first. Any read failing throws: a partial list
  /// would hide orders the user can still cancel.
  Future<List<HlOpenOrder>> getOpenOrders(String address,
      {Iterable<String> dexes = const []}) async {
    Future<List<HlOpenOrder>> read(String dex) async {
      final decoded = await _infoOrThrow({
        'type': 'frontendOpenOrders',
        'user': address,
        if (dex.isNotEmpty) 'dex': dex,
      });
      if (decoded is! List) {
        throw const FormatException('unexpected frontendOpenOrders shape');
      }
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(HlOpenOrder.fromJson)
          .toList();
    }

    final names = <String>{
      for (final d in dexes)
        if (d.trim().isNotEmpty) d.trim(),
    }.toList()
      ..sort();
    final byOid = <int, HlOpenOrder>{};
    for (final o in await read('')) {
      byOid[o.oid] = o;
    }
    for (var start = 0; start < names.length; start += 4) {
      final batch = await Future.wait(names.skip(start).take(4).map(read));
      for (final list in batch) {
        for (final o in list) {
          byOid[o.oid] = o;
        }
      }
    }
    if (names.isEmpty) return byOid.values.toList();
    return byOid.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// Perps on [dex] ('' = the main dex) that are at their open-interest
  /// cap (`perpsAtOpenInterestCap`), as wire coins ('BTC', 'xyz:TSLA').
  /// While capped, orders that grow a position can be rejected.
  Future<Set<String>> getPerpsAtOpenInterestCap({String dex = ''}) async {
    final decoded = await _infoOrThrow({
      'type': 'perpsAtOpenInterestCap',
      if (dex.isNotEmpty) 'dex': dex,
    });
    if (decoded is! List) {
      throw const FormatException('unexpected perpsAtOpenInterestCap shape');
    }
    return {
      for (final c in decoded)
        if (c is String && c.isNotEmpty)
          dex.isEmpty || c.contains(':') ? c : '$dex:$c',
    };
  }

  /// The user's most recent fills (exchange returns newest-first, capped
  /// at 2000).
  Future<List<HlFill>> getUserFills(String address) async {
    final decoded = await _infoOrThrow({'type': 'userFills', 'user': address});
    if (decoded is! List) {
      throw const FormatException('unexpected userFills shape');
    }
    final fills = decoded
        .whereType<Map<String, dynamic>>()
        .map(HlFill.fromJson)
        .toList();
    unawaited(HyperliquidRevenue.recordFills(address, fills));
    return fills;
  }

  /// Whether [address] has any fill on record. Unlike [getUserFills] it
  /// books nothing (no revenue bookkeeping): recovery uses it to probe an
  /// account before deciding whether to adopt it. Throws on failure.
  Future<bool> hasAnyFill(String address) async {
    final decoded = await _infoOrThrow({'type': 'userFills', 'user': address});
    if (decoded is! List) {
      throw const FormatException('unexpected userFills shape');
    }
    return decoded.isNotEmpty;
  }

  /// Whether [address] has any non-funding ledger update (a deposit,
  /// withdrawal or transfer) since the venue started. Throws on failure.
  Future<bool> hasAnyLedgerUpdate(String address) async {
    final decoded = await _infoOrThrow({
      'type': 'userNonFundingLedgerUpdates',
      'user': address,
      'startTime': 0,
    });
    if (decoded is! List) {
      throw const FormatException('unexpected ledger updates shape');
    }
    return decoded.isNotEmpty;
  }

  /// Signed funding cash for one closed trade. Refuse truncated history and
  /// ambiguous fill/funding boundaries rather than manufacture a net profit.
  Future<double> getTradeFunding(
      String address, String coin, int openedAt, int closedAt) async {
    final decoded = await _infoOrThrow({
      'type': 'userFunding',
      'user': address,
      'startTime': openedAt,
      'endTime': closedAt,
    });
    if (decoded is! List || decoded.length >= 500) {
      throw const FormatException('Funding history incomplete');
    }
    var cash = 0.0;
    for (final entry in decoded) {
      if (entry is! Map || entry['delta'] is! Map || entry['time'] is! int) {
        throw const FormatException('Invalid funding entry');
      }
      final delta = entry['delta'] as Map;
      if (delta['coin'] != coin) continue;
      final time = entry['time'] as int;
      final amount = double.tryParse('${delta['usdc']}'.trim());
      if (delta['type'] != 'funding' ||
          amount == null ||
          !amount.isFinite ||
          time <= openedAt ||
          time >= closedAt) {
        throw const FormatException('Funding cannot be allocated safely');
      }
      cash += amount;
    }
    return cash;
  }

  /// L2 book snapshot. [coinKey] must be the WIRE coin — perp name or
  /// `@<index>`/canonical pair name for spot (HlMarket.wireCoin).
  Future<HlL2Book> getL2Book(String coinKey) async {
    final decoded = await _infoOrThrow({'type': 'l2Book', 'coin': coinKey});
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('unexpected l2Book shape');
    }
    return HlL2Book.fromJson(decoded);
  }

  // ── Wallet-scoped strict reads (Wallet hardening Phase 3, P3.7) ──────
  // Used by the Ledger account providers. Every one THROWS on failure so
  // a failed read is flagged as partial, never rendered as zero.

  /// `perpDexs` like [getPerpDexs], but throws instead of returning empty.
  Future<List<HlPerpDex>> getPerpDexsStrict() async {
    final decoded = await _infoOrThrow({'type': 'perpDexs'});
    if (decoded is! List) {
      throw const FormatException('unexpected perpDexs shape');
    }
    final out = <HlPerpDex>[];
    for (var i = 0; i < decoded.length; i++) {
      final d = decoded[i];
      if (d is! Map) continue; // index 0 is null → the default dex
      final name = (d['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      out.add(HlPerpDex(
        name: name,
        fullName: (d['fullName'] as String?)?.trim() ?? '',
        index: i,
      ));
    }
    return out;
  }

  /// Strict, fresh terms for funding a USDC perp order. Other collateral
  /// cannot be funded with USDC and must never be silently substituted.
  Future<double> getPerpTakerFundingRate(
      String address, HlMarket market) async {
    final results = await Future.wait([
      _infoOrThrow(
          {'type': 'meta', if (market.dex.isNotEmpty) 'dex': market.dex}),
      _infoOrThrow({'type': 'userFees', 'user': address}),
    ]);
    final meta = results[0];
    final fees = results[1];
    if (meta is! Map ||
        fees is! Map ||
        (market.dex.isNotEmpty && meta['collateralToken'] != 0)) {
      throw const FormatException('USDC collateral terms unavailable');
    }
    final universe = meta['universe'];
    if (universe is! List) {
      throw const FormatException('Market terms unavailable');
    }
    final terms = universe
        .whereType<Map>()
        .where((m) =>
            m['name'] == market.wireCoin ||
            (market.dex.isNotEmpty &&
                '${market.dex}:${m['name']}' == market.wireCoin))
        .firstOrNull;
    if (terms == null || terms['isDelisted'] == true) {
      throw const FormatException('Market unavailable');
    }
    final rate = double.tryParse('${fees['userCrossRate']}');
    final discount = double.tryParse('${fees['activeReferralDiscount']}');
    final scale = market.dex.isEmpty
        ? 0.0
        : double.tryParse('${terms['deployerFeeScale']}');
    if (rate == null ||
        !rate.isFinite ||
        rate < 0 ||
        discount == null ||
        !discount.isFinite ||
        discount < 0 ||
        discount > 1 ||
        scale == null ||
        !scale.isFinite ||
        scale < 0 ||
        scale > 3) {
      throw const FormatException('Fee terms unavailable');
    }
    final multiplier = scale < 1 ? scale + 1 : scale * 2;
    final growth = terms['growthMode'] == 'enabled' ? 0.1 : 1.0;
    // Ignore any aligned-collateral discount for this funding reserve;
    // the reserve stays in the same account and is not a quoted fee.
    return rate * (1 - discount) * multiplier * growth;
  }

  /// Perp clearinghouse state on one builder (HIP-3) dex.
  Future<HlAccountSnapshot> getDexClearinghouse(
      String address, String dex) async {
    final decoded = await _infoOrThrow(
        {'type': 'clearinghouseState', 'user': address, 'dex': dex});
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('unexpected clearinghouseState shape');
    }
    return HlAccountSnapshot.fromJson(perpState: decoded);
  }
}
