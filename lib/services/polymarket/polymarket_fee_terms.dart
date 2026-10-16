import 'package:flutter/foundation.dart' show visibleForTesting;
// lib/services/polymarket/polymarket_fee_terms.dart
//
// What a Polymarket order costs on top of its notional.
//
// The venue charges takers a platform fee per share, shares × rate ×
// (p·(1−p))^exponent, with the curve published per market, and charges
// a builder fee as a flat share of notional when an order carries a
// builder code (Kute's does whenever the backend supplies one; an order
// signed with the zero builder pays none). Both are taken from the account in pUSD
// alongside the trade: "the account must have enough pUSD to cover the
// trade and all applicable platform and builder fees". Neither is part of
// the signed maker/taker amounts, so sizing a buy against the balance
// has to add them itself. https://docs.polymarket.com/trading/fees and
// https://docs.polymarket.com/programs/builders/fees
//
// A BUY's platform fee grows as the fill price falls (more shares for the
// same dollars), so the ceiling for a dollar amount is taken at the
// lowest price it can fill at: the best ask. When the live curve cannot
// be read the documented maxima stand in (0.07 rate, 100 bps builder
// taker, 50 bps maker), which only ever over-reserves.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:kute/services/polymarket/builder_code_resolver.dart';
import 'package:kute/services/polymarket/placement_diagnostics.dart';
import 'package:kute/services/polymarket/warm_connections.dart';
import 'package:kute/services/polymarket_backend_service.dart';

class PolymarketFeeTerms {
  const PolymarketFeeTerms({
    required this.rate,
    required this.exponent,
    required this.builderTakerBps,
    required this.builderMakerBps,
    this.live = true,
  });

  /// Documented venue ceilings, used when the market's own curve is
  /// unavailable. A sizing guard (it can only over-reserve), not a Kute
  /// rate: Kute's builder rate is always read from the CLOB for the code
  /// the backend issued.
  static const worstCase = PolymarketFeeTerms(
      rate: 0.07,
      exponent: 1,
      builderTakerBps: 100,
      builderMakerBps: 50,
      live: false);

  /// Platform fee curve: fee = shares × rate × (p·(1−p))^exponent.
  final double rate, exponent;

  /// Builder (Kute) fee as basis points of notional, taker and maker.
  final double builderTakerBps, builderMakerBps;

  /// False when these are the documented maxima rather than a live read.
  final bool live;

  double platformFee(double shares, double price) => shares <= 0 ||
          !price.isFinite ||
          price <= 0 ||
          price >= 1
      ? 0
      : shares * rate * math.pow(price * (1 - price), exponent);

  double builderFee(double shares, double price, {bool taker = true}) =>
      shares <= 0 || price <= 0
          ? 0
          : shares * price * (taker ? builderTakerBps : builderMakerBps) / 10000;

  double totalFee(double shares, double price, {bool taker = true}) =>
      platformFee(shares, price) + builderFee(shares, price, taker: taker);

  /// What a SELL of [shares] at [price] lands in Predictions: the sale's
  /// value less the platform and builder fees the venue takes out of the
  /// proceeds. Never below zero.
  double sellProceeds(double shares, double price, {bool taker = true}) {
    if (shares <= 0 || !price.isFinite || price <= 0) return 0;
    return math.max(
        0, shares * price - totalFee(shares, price, taker: taker));
  }

  /// The most a BUY of [notional] dollars can be charged in fees when it
  /// fills no cheaper than [lowestPrice]. Rounded up to a cent.
  double feeCeilingForNotional(double notional, double lowestPrice,
      {bool taker = true}) {
    if (!notional.isFinite ||
        notional <= 0 ||
        !lowestPrice.isFinite ||
        lowestPrice <= 0 ||
        lowestPrice >= 1) {
      return 0;
    }
    final shares = notional / lowestPrice;
    return (totalFee(shares, lowestPrice, taker: taker) * 100).ceil() / 100;
  }

  /// All-in cost of a BUY of [notional] filling at [lowestPrice] or better.
  double allInCost(double notional, double lowestPrice, {bool taker = true}) =>
      notional + feeCeilingForNotional(notional, lowestPrice, taker: taker);

  /// The largest notional whose all-in cost, plus [reserve], fits
  /// [budget] at [price]. Floored to a cent so the reserve can never come
  /// out short. [reserve] is any fixed headroom the placement check adds
  /// on top of stake and fees (a market buy's rounding cent), so a stake
  /// sized here passes that same check.
  double maxNotionalFor(double budget, double price,
      {bool taker = true, double reserve = 0}) {
    final room = budget - reserve;
    if (!room.isFinite ||
        room <= 0 ||
        !price.isFinite ||
        price <= 0 ||
        price >= 1) {
      return 0;
    }
    final perShare = price +
        rate * math.pow(price * (1 - price), exponent) +
        price * (taker ? builderTakerBps : builderMakerBps) / 10000;
    final notional = room / perShare * price;
    var cents = (notional * 100).floor();
    // The ceiling rounds fees up per order; step down until it fits.
    while (cents > 0 &&
        allInCost(cents / 100, price, taker: taker) + reserve >
            budget + 1e-9) {
      cents--;
    }
    return cents / 100;
  }

  /// Live terms read within the last minute, by token, so the placement
  /// reads what the fee summary already fetched instead of asking the
  /// venue again on the tap.
  static const cacheFor = Duration(minutes: 1);
  static final Map<String, (PolymarketFeeTerms, DateTime)> _cache = {};
  static final Map<String, Future<PolymarketFeeTerms>> _inFlight = {};

  /// Builder rates by code. They change when the operator changes them,
  /// which is rare; five minutes is well inside the policy's own cadence.
  static const builderCacheFor = Duration(minutes: 5);
  static final Map<String, (Map<String, dynamic>, DateTime)> _builderCache =
      {};

  /// A market's fee curve saved on disk is used for this long without
  /// asking the venue (the curve is set per market and rarely changes),
  /// and refreshed in the background once it is older than
  /// [curveRefreshAfter].
  static const curveSavedFor = Duration(hours: 12);
  static const curveRefreshAfter = Duration(hours: 1);

  /// How long the terms wait for a builder code that is not cached yet. A
  /// healthy link answers well inside it; a slow one is not waited on, and
  /// the last saved builder rates (else the documented maxima, one
  /// percent) stand in. The platform curve never depends on it.
  static const builderCodeWait = Duration(milliseconds: 1500);

  static const _boxName = 'polymarket_fee_curves_v1';
  static Future<Box<String>?>? _opening;
  static Box<String>? _open;
  static final Map<String, String> _disk = {};
  static DateTime Function() clock = DateTime.now;

  @visibleForTesting
  static void resetCacheForTest() {
    _cache.clear();
    _builderCache.clear();
    _inFlight.clear();
    _disk.clear();
    _opening = null;
    _open = null;
    clock = DateTime.now;
  }

  /// The saved curves on disk. Opened by [warmUp] (a slip about to open),
  /// never awaited on the read path: what has been loaded into [_disk] by
  /// then is what a fetch sees.
  static Future<Box<String>?> _box() => _opening ??= () async {
        try {
          final box = Hive.isBoxOpen(_boxName)
              ? Hive.box<String>(_boxName)
              : await Hive.openBox<String>(_boxName)
                  .timeout(const Duration(seconds: 5));
          for (final key in box.keys) {
            _disk.putIfAbsent('$key', () => box.get(key) ?? '');
          }
          return _open = box;
        } catch (_) {
          return null; // No Hive (a test) or a damaged box: memory only.
        }
      }();

  /// Opens the saved curves (a slip about to open) and starts the read
  /// for [tokenId] so the tap finds it cached.
  static Future<void> warmUp(String tokenId) async {
    await _box();
    if (tokenId.isEmpty || cached(tokenId) != null) return;
    try {
      await fetch(tokenId);
    } catch (_) {}
  }

  static Map<String, dynamic>? _saved(String key) {
    final raw = _disk[key];
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static void _save(String key, Map<String, Object?> value) {
    final encoded = jsonEncode(value);
    _disk[key] = encoded;
    // Written through only once the box is open (a slip's warm-up); the
    // read path never opens it.
    try {
      unawaited(_open?.put(key, encoded));
    } catch (_) {}
  }

  /// Puts [terms] in the minute cache, as a read would (a slip whose
  /// summary has them, in a test).
  @visibleForTesting
  static void primeCacheForTest(String tokenId, PolymarketFeeTerms terms) {
    _cache[tokenId] = (terms, clock());
  }

  /// The terms read for [tokenId] within the last minute (what the slip
  /// shows), or null: the tap uses these instead of asking again.
  static PolymarketFeeTerms? cached(String tokenId) {
    final held = _cache[tokenId];
    if (held != null && clock().difference(held.$2) <= cacheFor) {
      return held.$1;
    }
    return null;
  }

  /// Reads the market's fee curve and Kute's builder rates from the CLOB.
  /// Throws when any part is missing or malformed; nothing is defaulted.
  /// The market chain (market → curve) and the builder chain (code →
  /// rates) are independent and run side by side; one read per token at
  /// a time, so the slip's summary and a warm-up share a fetch.
  static Future<PolymarketFeeTerms> fetch(String tokenId,
      {http.Client? client}) async {
    final held = cached(tokenId);
    if (held != null) return held;
    final running = _inFlight[tokenId];
    if (running != null) return running;
    final future = _fetch(tokenId, client: client);
    _inFlight[tokenId] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight[tokenId], future)) _inFlight.remove(tokenId);
    }
  }

  static Future<PolymarketFeeTerms> _fetch(String tokenId,
      {http.Client? client}) async {
    final borrowed = client == null ? PolymarketWarmConnections.borrowClob() : null;
    final http.Client c = client ?? borrowed!.client;
    try {
      Future<Map<String, dynamic>> get(String path) async {
        final response = await c
            .get(Uri.parse('https://clob.polymarket.com$path'))
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) {
          throw StateError('Fee unavailable');
        }
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      double number(Object? value) {
        final n = double.tryParse('$value');
        if (n == null || !n.isFinite || n < 0) {
          throw StateError('Invalid fee');
        }
        return n;
      }

      Future<Map> readCurve() async {
        final market =
            await get('/markets-by-token/${Uri.encodeComponent(tokenId)}');
        final condition = market['condition_id'];
        if (condition is! String || condition.isEmpty) {
          throw StateError('Missing market');
        }
        final info =
            await get('/clob-markets/${Uri.encodeComponent(condition)}');
        final fd = info['fd'];
        // A fee-free market (Gamma's feesEnabled false) is served with no
        // `fd` at all; the rest of the record is there. The venue charges
        // it no platform fee, so its curve is zero. Anything else that
        // is not a curve, or a record for another market, stays an error.
        final Map curve;
        if (!info.containsKey('fd') &&
            info['c'] is String &&
            (info['c'] as String).toLowerCase() == condition.toLowerCase()) {
          curve = const {'r': 0, 'e': 1};
        } else if (fd is Map) {
          curve = fd;
        } else {
          throw StateError('Missing fee curve');
        }
        _save(tokenId, {
          'r': number(curve['r']),
          'e': number(curve['e']),
          'at': clock().millisecondsSinceEpoch,
        });
        return curve;
      }

      // The saved curve stands in for the venue's while it is young
      // enough; past an hour it is refreshed behind the answer.
      Future<Map> curve() async {
        final saved = _saved(tokenId);
        final at = saved?['at'];
        if (saved != null && at is int) {
          final age = clock()
              .difference(DateTime.fromMillisecondsSinceEpoch(at));
          if (age <= curveSavedFor) {
            if (age > curveRefreshAfter) {
              unawaited(readCurve().catchError((_) => const {}));
            }
            return {'r': saved['r'], 'e': saved['e']};
          }
        }
        return readCurve();
      }

      Future<Map<String, dynamic>> ratesFor(String code) async {
        // The zero builder (backend unreachable or no code published)
        // carries no attribution, so the venue charges no builder fee.
        if (isZeroBuilderCode(code)) {
          return const {
            'builder_taker_fee_rate_bps': 0,
            'builder_maker_fee_rate_bps': 0,
          };
        }
        final held = _builderCache[code];
        if (held != null && clock().difference(held.$2) <= builderCacheFor) {
          return held.$1;
        }
        final rates =
            await get('/fees/builder-fees/${Uri.encodeComponent(code)}');
        _builderCache[code] = (rates, clock());
        _save('builder', {
          'builder_taker_fee_rate_bps': number(rates['builder_taker_fee_rate_bps']),
          'builder_maker_fee_rate_bps': number(rates['builder_maker_fee_rate_bps']),
        });
        return rates;
      }

      // Never held up by the backend: the cached code when there is one,
      // else a short wait for the refresh, else the last rates saved for
      // Kute's code (the documented maxima before any were).
      Future<Map<String, dynamic>> builderRates() async {
        var code = PolymarketBackendService.cachedBuilderCode;
        if (code == null) {
          await PolymarketBackendService.refreshBuilderCode()
              .timeout(builderCodeWait, onTimeout: () {})
              .catchError((_) {});
          code = PolymarketBackendService.cachedBuilderCode;
          if (code == null) {
            return _saved('builder') ??
                const {
                  'builder_taker_fee_rate_bps': 100,
                  'builder_maker_fee_rate_bps': 50,
                };
          }
        }
        return ratesFor(code);
      }

      final results = await Future.wait([curve(), builderRates()]);
      final fd = results[0];
      final builder = results[1];
      final terms = PolymarketFeeTerms(
        rate: number(fd['r']),
        exponent: number(fd['e']),
        builderTakerBps: number(builder['builder_taker_fee_rate_bps']),
        builderMakerBps: number(builder['builder_maker_fee_rate_bps']),
      );
      // A curve above the documented maxima is not something to size with.
      if (terms.rate > 1 ||
          terms.exponent > 4 ||
          terms.builderTakerBps > 10000 ||
          terms.builderMakerBps > 10000) {
        throw StateError('Invalid fee');
      }
      _cache[tokenId] = (terms, clock());
      return terms;
    } finally {
      if (borrowed != null && !borrowed.borrowed) c.close();
    }
  }

  /// Live terms when the CLOB answers in time, the documented maxima
  /// otherwise. Sizing with the maxima can only over-reserve.
  static Future<PolymarketFeeTerms> fetchOrWorstCase(String tokenId,
      {Duration timeout = const Duration(seconds: 4)}) async {
    final clock = Stopwatch()..start();
    try {
      return await fetch(tokenId).timeout(timeout);
    } catch (e) {
      PolymarketPlacementDiagnostics.stepFailed('fee_terms', e, clock.elapsed);
      return worstCase;
    }
  }
}

/// The market's fee terms, refreshed each minute while watched. Errors
/// surface to the caller; sizing code falls back to the documented maxima.
final polymarketFeeTermsProvider =
    FutureProvider.autoDispose.family<PolymarketFeeTerms, String>(
        (ref, tokenId) async {
  final timer = Timer(const Duration(minutes: 1), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  final client = http.Client();
  ref.onDispose(client.close);
  return PolymarketFeeTerms.fetch(tokenId, client: client);
});
