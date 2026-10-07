import 'package:kute/services/tracking/latency_tracker.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'dart:convert';
import 'dart:math' show Random;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:kute/models/affiliate_model.dart'
    show AffiliateService, WalletSessionUnavailable;
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/handlers/response_handlers.dart';
import 'package:kute/services/debug/settlement_fault_registry.dart';

/// Flashnet Orchestra onramp fiat band, as documented by the venue
/// (docs.flashnet.xyz/orchestra — orchestration limits: $1.00 minimum,
/// $50,000.00 maximum fiat per order). These are the FALLBACK bounds the
/// Cash App buy validates against when the live
/// [OrchestraService.getOnrampLimits] call is unavailable. There is no
/// weekly cap — the old client-side $999/week tracker was never a
/// Flashnet rule and has been removed.
///
/// A technical guard for the amount field, not a Kute business setting:
/// the live band comes from the backend and Flashnet enforces its own.
class OrchestraOnrampLimits {
  final double minFiatUsd;
  final double maxFiatUsd;
  const OrchestraOnrampLimits({
    required this.minFiatUsd,
    required this.maxFiatUsd,
  });

  /// Reads the selected Lightning-funded route, never another asset's band.
  /// Current responses use routes[].limits.fiatUsd; older flat responses are
  /// accepted only when no route catalog is present.
  static OrchestraOnrampLimits? fromResponse(
    Object? response, {
    required String destinationChain,
    required String destinationAsset,
  }) {
    double? number(Object? raw) {
      final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
      return value != null && value.isFinite ? value : null;
    }

    OrchestraOnrampLimits? band(Object? value, {bool current = false}) {
      if (value is! Map || value['supported'] == false) return null;
      final min = current
          ? number(value['min'])
          : number(value['minFiatUsd']) ??
              number(value['minFiatAmountUsd']) ??
              number(value['minUsd']);
      final max = current
          ? number(value['max'])
          : number(value['maxFiatUsd']) ??
              number(value['maxFiatAmountUsd']) ??
              number(value['maxUsd']);
      if (min == null || max == null || min <= 0 || max <= min) return null;
      return OrchestraOnrampLimits(minFiatUsd: min, maxFiatUsd: max);
    }

    bool matches(Object? raw, String expected) =>
        raw is String && raw.trim().toLowerCase() == expected.toLowerCase();
    if (response is! Map) return null;
    final routes = response['routes'];
    if (routes is List) {
      for (final row in routes) {
        if (row is! Map ||
            !matches(row['sourceChain'], 'lightning') ||
            !matches(row['sourceAsset'], 'BTC') ||
            !matches(row['destinationChain'], destinationChain) ||
            !matches(row['destinationAsset'], destinationAsset)) {
          continue;
        }
        final limits = row['limits'];
        return limits is Map ? band(limits['fiatUsd'], current: true) : null;
      }
      return null;
    }
    for (final value in [
      response,
      response['limits'],
      response['onramp'],
      response['fiat'],
      response['data'],
    ]) {
      final parsed = band(value);
      if (parsed != null) return parsed;
    }
    return null;
  }
}

class StandingRequestException implements Exception {
  const StandingRequestException(this.status, this.code);
  final int status;
  final String? code;
  bool get refundDefinitelyRefused =>
      status == 409 && code == 'refund_not_available';
  @override
  String toString() => 'Deposit request could not be completed';
}

class OrchestraService {
  /// [maxAge]: a policy fetched for this session within it is read rather
  /// than fetched again (see [RuntimeCapabilitiesService.ensureAllAllowed]).
  static Future<void> _ensureCapabilities(Iterable<String> capabilities,
      {Duration maxAge = Duration.zero}) async {
    if (await AffiliateService.ensureSession() == null) {
      TrackingService.walletSessionAuth(
          route: 'orchestra', outcome: 'unavailable');
      throw WalletSessionUnavailable(
          AffiliateService.sessionUnavailableMessage());
    }
    await RuntimeCapabilitiesService.instance
        .ensureAllAllowed(capabilities, maxAge: maxAge);
  }

  /// How old a policy a quote may read instead of fetching it again. The
  /// Move sheet fetches the policy when it opens and a run can quote two
  /// or three times (the arrival gross-up, a refresh before send), and
  /// each quote used to wait on its own policy round trip first. The
  /// backend's operation guard checks the same capabilities on every
  /// quote against the live policy, so this only spares the app's own
  /// pre-check a round trip. Same minute the order posts use.
  static const Duration _quotePolicyMaxAge = Duration(seconds: 60);

  static String get _baseUrl => '${dotenv.env['BACKEND']!}/api/v1/orchestra';

  /// Documented onramp fiat minimum (USD per order). See
  /// [OrchestraOnrampLimits].
  static const double onrampMinFiatUsd = 1.0;

  /// Documented onramp fiat maximum (USD per order). See
  /// [OrchestraOnrampLimits].
  static const double onrampMaxFiatUsd = 50000.0;

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
  };

  /// Sends one backend Orchestra request. Every /api/v1/orchestra route
  /// requires the wallet-session bearer (minted at POST /api/v1/affiliate/
  /// auth/wallet), so [send] gets JSON headers plus Authorization, with a
  /// session obtained first when none exists and one re-auth and retry on
  /// a 401. [extra] is fixed before the first attempt, so a retry carries
  /// the same idempotency key. Throws [WalletSessionUnavailable] (localized)
  /// without calling the backend when no session can be obtained.
  static Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> headers) send, {
    Map<String, String> extra = const {},
  }) {
    final base = {..._jsonHeaders, ...extra};
    return AffiliateService.sendWithSession(
        'orchestra', (auth) => send({...base, ...auth}));
  }

  /// Wallet-scoped standing-address calls. The caller's identity fence is
  /// checked again inside session acquisition/401 retry, before dispatch.
  static Future<Map<String, dynamic>> standingRequest({
    required String operation,
    required bool Function() current,
    String? label,
    Map<String, dynamic>? body,
    String? idempotencyKey,
    int offset = 0,
    void Function()? beforeDispatch,
  }) async {
    final (method, suffix) = switch (operation) {
      'destinations' => ('GET', '/destinations'),
      'mine' => ('GET', '/mine'),
      'register' => ('PUT', ''),
      'read' => ('GET', ''),
      'deposits' => ('GET', '/deposits'),
      'enabled' => ('PATCH', '/enabled'),
      'resolve' => ('POST', '/resolve'),
      _ => throw ArgumentError('Unknown standing-address operation'),
    };
    if (operation == 'register') await _ensureCapabilities(['crypto.deposit']);
    final uri = Uri.parse('$_baseUrl/standing-deposit-addresses$suffix')
        .replace(queryParameters: {
      if (label != null) 'label': label,
      if (operation == 'deposits') ...{'limit': '100', 'offset': '$offset'},
    });
    final headers =
        method == 'GET' ? <String, String>{} : _idempotency(idempotencyKey);
    final response = await _send((auth) {
      if (!current()) throw StateError('Receive wallet changed');
      beforeDispatch?.call();
      return switch (method) {
        'GET' => http.get(uri, headers: auth),
        'PUT' => http.put(uri, headers: auth, body: jsonEncode(body)),
        'PATCH' => http.patch(uri, headers: auth, body: jsonEncode(body)),
        _ => http.post(uri, headers: auth, body: jsonEncode(body)),
      }
          .timeout(const Duration(seconds: 20));
    }, extra: headers);
    if (!current()) throw StateError('Receive wallet changed');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? code;
      try {
        final data = jsonDecode(response.body);
        if (data is Map) {
          final error = data['error'];
          code = error is String
              ? error
              : error is Map
                  ? error['code']?.toString()
                  : data['code']?.toString();
        }
      } catch (_) {/* A malformed error cannot prove that nothing happened. */}
      throw StandingRequestException(response.statusCode, code);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid deposit response');
    }
    return decoded;
  }

  static final Random _idempotencyRng = Random.secure();

  /// UUID v4 for Flashnet's X-Idempotency-Key header (no uuid package
  /// in pubspec, so generated locally). One key per user ACTION: a
  /// caller retrying the same operation after a timeout/5xx should
  /// generate a key once, hold it, and pass it on every attempt so
  /// Flashnet dedups instead of double-creating the order. Distinct
  /// operations (a re-quote at a different amount) take fresh keys.
  static String generateIdempotencyKey() {
    final b = List<int>.generate(16, (_) => _idempotencyRng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 variant
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-'
        '${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }

  /// The idempotency header for an order-creating or paying call, resolved
  /// once per call so a 401 retry reuses the key.
  static Map<String, String> _idempotency(String? idempotencyKey) => {
        'X-Idempotency-Key': idempotencyKey ?? generateIdempotencyKey(),
      };

  /// Extract a human-readable message from a JSON error body.
  static String _parseError(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) {
        final error = parsed['error'];
        if (error is Map<String, dynamic>) {
          return error['message'] as String? ?? body;
        }
        if (error is String) return error;
        final message = parsed['message'];
        if (message is String) return message;
      }
    } catch (_) {}
    return body;
  }

  /// Flashnet's public orchestration host. Used ONLY for the public,
  /// credential-free routes catalog when the backend proxy has no
  /// /routes endpoint yet. Order-creating calls (onramp, quote, submit)
  /// always go through the backend — the fn_ server key must never
  /// live in the app.
  static const String _publicBaseUrl = 'https://orchestration.flashnet.xyz';

  // ─── Route Catalog ──────────────────────────────────────────────

  /// Response header carrying when the backend fetched its cached routes
  /// copy from Flashnet (Unix seconds or milliseconds, or ISO-8601).
  static const String catalogFetchedAtHeader = 'x-kute-catalog-fetched-at';

  /// Raw route catalog JSON. Tries the backend proxy first (so the
  /// backend can later cache / filter it), then falls back to
  /// Flashnet's public GET /v2/orchestration/routes (no auth).
  static Future<Result<Map<String, dynamic>>> getRoutesRaw() async {
    final res = await getRoutesWithOrigin();
    final fetch = res.data;
    if (fetch == null) return Result(error: res.error);
    return Result(data: fetch.json);
  }

  /// [getRoutesRaw] plus where the catalog came from, for the money-route
  /// freshness rule (Phase 5 plan B2).
  static Future<Result<OrchestraRoutesFetch>> getRoutesWithOrigin() async {
    Future<(Map<String, dynamic>, Map<String, String>)?> tryGet(
        Future<http.Response> Function() get) async {
      try {
        final res = await get();
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final parsed = jsonDecode(res.body);
          if (parsed is Map<String, dynamic> && parsed['assets'] is List) {
            return (parsed, res.headers);
          }
        }
      } catch (_) {}
      return null;
    }

    Future<http.Response> get(Uri uri, Map<String, String>? headers) =>
        http.get(uri, headers: headers).timeout(const Duration(seconds: 12));

    // Backend proxy gets the wallet-session bearer; the public Flashnet
    // host must NOT see our backend token. Without a session the public
    // catalog is used and the backend is not called.
    final fromBackend =
        await tryGet(() => _send((h) => get(Uri.parse('$_baseUrl/routes'), h)));
    if (fromBackend != null) {
      return Result(
        data: OrchestraRoutesFetch(
          json: fromBackend.$1,
          fromBackend: true,
          upstreamFetchedAt: parseCatalogFetchedAt(fromBackend.$2),
        ),
      );
    }
    final fromPublic = await tryGet(
        () => get(Uri.parse('$_publicBaseUrl/v2/orchestration/routes'), null));
    if (fromPublic != null) {
      return Result(
        data: OrchestraRoutesFetch(json: fromPublic.$1, fromBackend: false),
      );
    }
    return Result(error: 'Route catalog unavailable');
  }

  /// Reads [catalogFetchedAtHeader], or null when absent or unparseable.
  static DateTime? parseCatalogFetchedAt(Map<String, String>? headers) {
    if (headers == null) return null;
    String? raw;
    headers.forEach((k, v) {
      if (k.toLowerCase() == catalogFetchedAtHeader) raw = v.trim();
    });
    final value = raw;
    if (value == null || value.isEmpty) return null;
    final n = int.tryParse(value);
    if (n != null) {
      if (n <= 0) return null;
      final ms = n >= 100000000000 ? n : n * 1000;
      if (ms > 8640000000000000) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return DateTime.tryParse(value)?.toLocal();
  }

  /// Live limits for the directed pair [key] (Phase 5 plan B3): the
  /// backend `/limits` proxy, then Flashnet's public host. Null when
  /// neither answers with a matching route; never throws. Limits are
  /// presentation only, so a null result must not block quoting.
  static Future<OrchestraRouteLimits?> getRouteLimits(
    RouteKey key, {
    http.Client? client,
  }) async {
    final query = {
      'sourceChain': key.fromChain,
      'sourceAsset': key.fromAsset,
      'destinationChain': key.toChain,
      'destinationAsset': key.toAsset,
    };

    Future<OrchestraRouteLimits?> tryGet(Uri uri,
        {Map<String, String>? headers}) async {
      try {
        final res = await (client == null
                ? http.get(uri, headers: headers)
                : client.get(uri, headers: headers))
            .timeout(const Duration(seconds: 10));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return OrchestraRouteLimits.fromResponse(jsonDecode(res.body), key);
        }
      } catch (_) {}
      return null;
    }

    final fromBackend = await tryGet(
        Uri.parse('$_baseUrl/limits').replace(queryParameters: query));
    if (fromBackend != null) return fromBackend;
    return tryGet(Uri.parse('$_publicBaseUrl/v1/orchestration/limits')
        .replace(queryParameters: query));
  }

  /// The [RouteQuoteErrorCode] code in an error body, or null.
  static String? _parseRouteErrorCode(String body) {
    try {
      return parseRouteQuoteErrorCode(jsonDecode(body))?.code;
    } catch (_) {
      return null;
    }
  }

  /// Reliability class of an HTTP status for the quote/submit result
  /// events. `network` is a thrown transport failure (timeout, socket),
  /// `client` a local refusal before any request (no session, capability
  /// denied, missing refund address).
  static String _statusClass(int status) => status >= 500
      ? '5xx'
      : status >= 400
          ? '4xx'
          : status >= 200 && status < 300
              ? '2xx'
              : 'other';

  static String _thrownStatusClass(Object e) =>
      e is WalletSessionUnavailable || e is CapabilityUnavailableException
          ? 'client'
          : 'network';

  /// One reliability event per quote request. Route legs are categorical;
  /// no quote/order ids, addresses or amounts.
  static void _trackQuoteResult({
    required String sourceChain,
    required String sourceAsset,
    required String destinationChain,
    required String destinationAsset,
    required bool ok,
    required String statusClass,
    String? errorCode,
  }) =>
      TrackingService.track('orchestra_quote_result', params: {
        'source_chain': sourceChain,
        'source_asset': sourceAsset,
        'destination_chain': destinationChain,
        'destination_asset': destinationAsset,
        'outcome': ok ? 'ok' : 'error',
        'status_class': statusClass,
        if (errorCode != null) 'error_code': errorCode,
      });

  /// One reliability event per deposit submit. No ids.
  static void _trackSubmitResult({
    required bool ok,
    required String statusClass,
  }) =>
      TrackingService.track('orchestra_submit_result', params: {
        'outcome': ok ? 'ok' : 'error',
        'status_class': statusClass,
      });

  // ─── Buy Flow ───────────────────────────────────────────────────

  /// Live fiat limits for the complete Lightning BTC → destination route.
  /// The public fallback receives the same pair and no wallet credentials.
  /// Omitting the destination preserves the default Spark Bitcoin purchase.
  static Future<Result<OrchestraOnrampLimits>> getOnrampLimits({
    String? destinationChain,
    String? destinationAsset,
  }) async {
    final chain = destinationChain?.trim().toLowerCase() ?? 'spark';
    final asset = destinationAsset ??
        switch (chain) {
          'hypercore' => 'USDC',
          'polygon' => 'USDC.e',
          _ => 'BTC',
        };
    OrchestraOnrampLimits? parse(Object? data) =>
        OrchestraOnrampLimits.fromResponse(data,
            destinationChain: chain, destinationAsset: asset);

    Future<OrchestraOnrampLimits?> tryGet(
        Future<http.Response> Function() get) async {
      try {
        final res = await get();
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return parse(jsonDecode(res.body));
        }
      } catch (_) {}
      return null;
    }

    Future<http.Response> get(Uri uri, Map<String, String>? headers) =>
        http.get(uri, headers: headers).timeout(const Duration(seconds: 10));

    final query = {
      'sourceChain': 'lightning',
      'sourceAsset': 'BTC',
      'destinationChain': chain,
      'destinationAsset': asset,
    };
    // Without a session the public limits are used and the backend is not
    // called.
    final fromBackend = await tryGet(() => _send((h) =>
        get(Uri.parse('$_baseUrl/limits').replace(queryParameters: query), h)));
    if (fromBackend != null) return Result(data: fromBackend);
    final fromPublic = await tryGet(() => get(
        Uri.parse('$_publicBaseUrl/v1/orchestration/limits')
            .replace(queryParameters: query),
        null));
    if (fromPublic != null) return Result(data: fromPublic);
    return Result(error: 'Limits unavailable');
  }

  /// Creates a Lightning-funded onramp order (the Cash App buy flow).
  /// Pass exactly one of [amount] (destination smallest units) or
  /// [amountFiatUsd] (USD string, e.g. '50.00' — Flashnet converts to
  /// sats at request time). The backend proxy signs with the fn_
  /// server key; the app never holds it.
  static Future<Result<OrchestraOnrampResponse>> createOnramp({
    String? sourceChain,
    String? sourceAsset,
    required String destinationChain,
    required String destinationAsset,
    required String recipientAddress,
    String? amount,
    String? amountFiatUsd,
    String? idempotencyKey,
  }) async {
    assert((amount == null) != (amountFiatUsd == null),
        'Pass exactly one of amount / amountFiatUsd');
    try {
      await _ensureCapabilities([
        'onramp.cashapp',
        if (destinationChain == 'hypercore') 'hyperliquid.deposit',
        if (destinationChain == 'polygon' &&
            destinationAsset.toUpperCase() == 'USDC.E')
          'polymarket.deposit',
      ]);
      final body = <String, dynamic>{
        'destinationChain': destinationChain,
        'destinationAsset': destinationAsset,
        'recipientAddress': recipientAddress,
      };
      if (amount != null) body['amount'] = amount;
      if (amountFiatUsd != null) body['amountFiatUsd'] = amountFiatUsd;
      if (sourceChain != null) body['sourceChain'] = sourceChain;
      if (sourceAsset != null) body['sourceAsset'] = sourceAsset;

      final res = await _send(
        (h) => http
            .post(
              Uri.parse('$_baseUrl/onramp'),
              headers: h,
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 15)),
        extra: _idempotency(idempotencyKey),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return Result(
            data: OrchestraOnrampResponse.fromJson(jsonDecode(res.body)));
      }
      return Result(error: _parseError(res.body));
    } catch (e) {
      return Result(error: e.toString());
    }
  }

  static Future<Result<OrchestraEstimate>> getEstimate({
    required String sourceChain,
    required String sourceAsset,
    required String destinationChain,
    required String destinationAsset,
    required String amount,
    bool onramp = false,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/estimate').replace(queryParameters: {
        'sourceChain': sourceChain,
        'sourceAsset': sourceAsset,
        'destinationChain': destinationChain,
        'destinationAsset': destinationAsset,
        'amount': amount,
        // A Cash App order is created through /onramp, which the backend
        // prices at its own rule; the flag asks the estimate for that same
        // rule so the fee shown is the fee charged.
        if (onramp) 'onramp': 'true',
      });
      final res = await _send((h) =>
          http.get(uri, headers: h).timeout(const Duration(seconds: 15)));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return Result(
            data: OrchestraEstimate.fromJson(jsonDecode(res.body),
                headers: res.headers));
      }
      return Result(error: _parseError(res.body));
    } catch (e) {
      return Result(error: e.toString());
    }
  }

  // ─── Quote & Submit (Spark orchestration) ──────────────────────

  /// [refundAddress] is REQUIRED by policy, not by Flashnet: a quote
  /// without one strands funds server-side if the swap fails after the
  /// deposit lands. It must be an address on the SOURCE chain that the
  /// user controls (Spark address for spark-source quotes, the sending
  /// EVM/proxy address for EVM-source quotes). Callers that cannot
  /// resolve one must fail the action BEFORE any funds move — the
  /// empty-string guard here is the backstop for that rule.
  static Future<Result<OrchestraQuote>> createQuote({
    required String sourceChain,
    required String sourceAsset,
    required String destinationChain,
    required String destinationAsset,
    required String amount,
    required String recipientAddress,
    required String refundAddress,
    String? deliveryMode,
    int? slippageBps,
    String? idempotencyKey,
  }) async {
    // Quote request → response round-trip (durations only; route legs
    // are categorical). Started right before the HTTP send so capability
    // checks and client-side rejections are not counted.
    final roundtrip = Stopwatch();
    void report(bool ok, String statusClass, [String? errorCode]) {
      if (roundtrip.isRunning) {
        roundtrip.stop();
        LatencyTracker.record(
          LatencyKeys.quoteRoundtrip,
          roundtrip.elapsedMilliseconds,
          params: {
            'source_chain': sourceChain,
            'source_asset': sourceAsset,
            'destination_chain': destinationChain,
            'destination_asset': destinationAsset,
            'outcome': ok ? 'ok' : 'error',
          },
        );
      }
      _trackQuoteResult(
        sourceChain: sourceChain,
        sourceAsset: sourceAsset,
        destinationChain: destinationChain,
        destinationAsset: destinationAsset,
        ok: ok,
        statusClass: statusClass,
        errorCode: errorCode,
      );
    }

    if (refundAddress.trim().isEmpty) {
      report(false, 'client', 'missing_refund_address');
      // Same generic string the quote callers already surface — no new
      // user copy; the point is refusing to quote refund-less.
      return Result(error: 'Failed to get quote');
    }
    try {
      await _ensureCapabilities(
          orchestraCapabilityRequirements(
              sourceChain: sourceChain,
              sourceAsset: sourceAsset,
              destinationChain: destinationChain,
              destinationAsset: destinationAsset),
          maxAge: _quotePolicyMaxAge);
      final body = <String, dynamic>{
        'sourceChain': sourceChain,
        'sourceAsset': sourceAsset,
        'destinationChain': destinationChain,
        'destinationAsset': destinationAsset,
        'amount': amount,
        'recipientAddress': recipientAddress,
        'refundAddress': refundAddress.trim(),
      };
      if (deliveryMode != null) body['deliveryMode'] = deliveryMode;
      if (slippageBps != null) body['slippageBps'] = slippageBps;

      roundtrip.start();
      final res = await _send(
        (h) => http
            .post(
              Uri.parse('$_baseUrl/quote'),
              headers: h,
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 15)),
        extra: _idempotency(idempotencyKey),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final quote = OrchestraQuote.fromJson(
            SettlementFaults.quoteBody(jsonDecode(res.body)));
        report(true, _statusClass(res.statusCode));
        return Result(
          data: quote,
          statusCode: res.statusCode,
          headers: res.headers,
        );
      }
      final routeErrorCode = _parseRouteErrorCode(res.body);
      report(false, _statusClass(res.statusCode), routeErrorCode);
      return Result(
        error: _parseError(res.body),
        statusCode: res.statusCode,
        headers: res.headers,
        errorCode: routeErrorCode,
      );
    } catch (e) {
      report(false, _thrownStatusClass(e), TrackingService.errorCategory(e));
      return Result(error: e.toString());
    }
  }

  /// Pass the operation's persisted [idempotencyKey] on every retry after a
  /// timeout, 5xx or 429 so the backend and Flashnet deduplicate the
  /// submit. Without one a fresh key is generated once per call, so the
  /// single retry after a 401 re-auth sends the same key and body.
  static Future<Result<OrchestraSubmitResponse>> submitDeposit({
    required String quoteId,
    String? sparkTxHash,
    String? sourceSparkAddress,
    String? txHash, // EVM / Solana / generic chain tx hash
    String? sourceAddress,
    String? bitcoinTxid,
    int? bitcoinVout,
    String? idempotencyKey,
  }) async {
    try {
      final body = <String, dynamic>{
        'quoteId': quoteId,
      };
      if (sparkTxHash != null) body['sparkTxHash'] = sparkTxHash;
      if (sourceSparkAddress != null) {
        body['sourceSparkAddress'] = sourceSparkAddress;
      }
      if (txHash != null) body['txHash'] = txHash;
      if (sourceAddress != null) body['sourceAddress'] = sourceAddress;
      if (bitcoinTxid != null) body['bitcoinTxid'] = bitcoinTxid;
      if (bitcoinVout != null) body['bitcoinVout'] = bitcoinVout;

      final res = await _send(
        (h) => http
            .post(
              Uri.parse('$_baseUrl/submit'),
              headers: h,
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 15)),
        extra: _idempotency(idempotencyKey),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final submitted =
            OrchestraSubmitResponse.fromJson(jsonDecode(res.body));
        _trackSubmitResult(ok: true, statusClass: _statusClass(res.statusCode));
        return Result(
          data: submitted,
          statusCode: res.statusCode,
          headers: res.headers,
        );
      }
      _trackSubmitResult(
          ok: false, statusClass: _statusClass(res.statusCode));
      return Result(
        error: _parseError(res.body),
        statusCode: res.statusCode,
        headers: res.headers,
      );
    } catch (e) {
      _trackSubmitResult(ok: false, statusClass: _thrownStatusClass(e));
      return Result(error: e.toString());
    }
  }

  // ─── Order Status ───────────────────────────────────────────────

  static Future<Result<OrchestraOrder>> getStatus(String orderId) async {
    try {
      if (SettlementFaults.takeStatusFailure()) {
        return Result(error: 'Service unavailable', statusCode: 503);
      }
      // Flashnet accepts id, quoteId, or txHash — pick the right param
      final paramKey = orderId.startsWith('q_')
          ? 'quoteId'
          : orderId.startsWith('ord_')
              ? 'id'
              : 'id'; // fallback
      final uri = Uri.parse('$_baseUrl/status')
          .replace(queryParameters: {paramKey: orderId});
      final res = await _send((h) =>
          http.get(uri, headers: h).timeout(const Duration(seconds: 15)));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        // A quote lookup with no order yet still carries the backend's
        // status, expiry and payment evidence; see
        // OrchestraOrder.orderMissing.
        return Result(
          data: OrchestraOrder.fromJson(
              SettlementFaults.statusBody(orderId, jsonDecode(res.body))),
          statusCode: res.statusCode,
          headers: res.headers,
        );
      }
      return Result(
        error: _parseError(res.body),
        statusCode: res.statusCode,
        headers: res.headers,
      );
    } catch (e) {
      return Result(error: e.toString());
    }
  }

  /// Recipient history is private and uses the owned Spark address, never the
  /// source-chain deposit address. The backend verifies its wallet identity.
  static Future<Result<List<OrchestraOrder>>> getHistory(
      String recipientSparkAddress) async {
    try {
      final uri = Uri.parse('$_baseUrl/history')
          .replace(queryParameters: {'address': recipientSparkAddress});
      final res = await _send((h) =>
          http.get(uri, headers: h).timeout(const Duration(seconds: 15)));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        final rows =
            decoded is Map<String, dynamic> ? decoded['orders'] : decoded;
        if (rows is! List) {
          return Result(
              error: 'Invalid order history response',
              statusCode: res.statusCode,
              headers: res.headers);
        }
        final list = rows
            .map((e) => OrchestraOrder.fromJson(e as Map<String, dynamic>))
            .toList();
        return Result(
            data: list, statusCode: res.statusCode, headers: res.headers);
      }
      return Result(
          error: _parseError(res.body),
          statusCode: res.statusCode,
          headers: res.headers);
    } catch (e) {
      return Result(error: e.toString());
    }
  }

  // ─── Accumulation Addresses ─────────────────────────────────────

  /// [refundAddresses] maps source-chain slug → a refund address the
  /// user controls on that chain (Flashnet's `refundAddresses` field —
  /// targets for generated-order refunds on held deposits). Optional
  /// because receive flows watch for EXTERNAL senders the app holds no
  /// source-chain address for; pass it whenever the depositing wallet
  /// is the user's own (e.g. the Hyperliquid EOA on Arbitrum).
  static Future<Result<OrchestraAccumulationAddress>>
      createAccumulationAddress({
    required String sourceChain,
    required String sourceAsset,
    required String destinationAsset,
    required String recipientSparkAddress,
    String? label,
    Map<String, String>? refundAddresses,
    String? idempotencyKey,
  }) async {
    try {
      // Exactly the operation guard's list for this endpoint.
      await _ensureCapabilities(orchestraReceiveAddressCapabilities(
          sourceChain: sourceChain,
          sourceAsset: sourceAsset,
          destinationAsset: destinationAsset));
      final reviewedRevision =
          RuntimeCapabilitiesService.instance.snapshot?.revision;
      final body = <String, dynamic>{
        'sourceChain': sourceChain,
        'sourceAsset': sourceAsset,
        'destinationAsset': destinationAsset,
        'recipientSparkAddress': recipientSparkAddress,
      };
      if (label != null && label.isNotEmpty) body['label'] = label;
      if (refundAddresses != null && refundAddresses.isNotEmpty) {
        body['refundAddresses'] = refundAddresses;
      }

      final res = await _send(
        (h) => http
            .post(
              Uri.parse('$_baseUrl/accumulation-addresses'),
              headers: h,
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 15)),
        extra: _idempotency(idempotencyKey),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final address =
            OrchestraAccumulationAddress.fromJson(jsonDecode(res.body));
        if (reviewedRevision == null ||
            address.feePolicyRevision != reviewedRevision) {
          return Result(error: 'Deposit terms changed. Please try again.');
        }
        return Result(data: address);
      }
      return Result(error: _parseError(res.body));
    } catch (e) {
      return Result(error: e.toString());
    }
  }

  static Future<Result<List<OrchestraAccumulationAddress>>>
      getAccumulationAddresses() async {
    try {
      final res = await _send((h) => http
          .get(Uri.parse('$_baseUrl/accumulation-addresses'), headers: h)
          .timeout(const Duration(seconds: 15)));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final list = (jsonDecode(res.body) as List<dynamic>)
            .map((e) => OrchestraAccumulationAddress.fromJson(
                e as Map<String, dynamic>))
            .toList();
        return Result(data: list);
      }
      return Result(error: _parseError(res.body));
    } catch (e) {
      return Result(error: e.toString());
    }
  }

  static Future<Result<void>> deleteAccumulationAddress(String id) async {
    try {
      final res = await _send((h) => http
          .delete(
            Uri.parse('$_baseUrl/accumulation-addresses/$id'),
            headers: h,
          )
          .timeout(const Duration(seconds: 15)));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return Result(data: null);
      }
      return Result(error: _parseError(res.body));
    } catch (e) {
      return Result(error: e.toString());
    }
  }

  // ─── Liquidation Addresses ─────────────────────────────────────

  static Future<Result<OrchestraLiquidationAddress>> createLiquidationAddress({
    required String destinationChain,
    required String destinationAsset,
    required String destinationAddress,
    String? label,
  }) async {
    try {
      final body = <String, dynamic>{
        'destinationChain': destinationChain,
        'destinationAsset': destinationAsset,
        'destinationAddress': destinationAddress,
      };
      if (label != null && label.isNotEmpty) body['label'] = label;

      final res = await _send((h) => http
          .post(
            Uri.parse('$_baseUrl/liquidation-addresses'),
            headers: h,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15)));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return Result(
            data: OrchestraLiquidationAddress.fromJson(jsonDecode(res.body)));
      }
      return Result(error: _parseError(res.body));
    } catch (e) {
      return Result(error: e.toString());
    }
  }

  static Future<Result<List<OrchestraLiquidationAddress>>>
      getLiquidationAddresses() async {
    try {
      final res = await _send((h) => http
          .get(Uri.parse('$_baseUrl/liquidation-addresses'), headers: h)
          .timeout(const Duration(seconds: 15)));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final list = (jsonDecode(res.body) as List<dynamic>)
            .map((e) =>
                OrchestraLiquidationAddress.fromJson(e as Map<String, dynamic>))
            .toList();
        return Result(data: list);
      }
      return Result(error: _parseError(res.body));
    } catch (e) {
      return Result(error: e.toString());
    }
  }

  static Future<Result<void>> deleteLiquidationAddress(String id) async {
    try {
      final res = await _send((h) => http
          .delete(
            Uri.parse('$_baseUrl/liquidation-addresses/$id'),
            headers: h,
          )
          .timeout(const Duration(seconds: 15)));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return Result(data: null);
      }
      return Result(error: _parseError(res.body));
    } catch (e) {
      return Result(error: e.toString());
    }
  }

  // ─── Pay Links ──────────────────────────────────────────────────

  static Future<Result<OrchestraPayLink>> createPayLink({
    required String destinationChain,
    required String destinationAsset,
    required String recipientAddress,
    required String amountOut,
    String? label,
  }) async {
    try {
      final body = <String, dynamic>{
        'destinationChain': destinationChain,
        'destinationAsset': destinationAsset,
        'recipientAddress': recipientAddress,
        'amountOut': amountOut,
        'message': (label != null && label.isNotEmpty) ? label : 'Payment',
      };

      final res = await _send((h) => http
          .post(
            Uri.parse('$_baseUrl/pay-links'),
            headers: h,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15)));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return Result(data: OrchestraPayLink.fromJson(jsonDecode(res.body)));
      }
      return Result(error: _parseError(res.body));
    } catch (e) {
      return Result(error: e.toString());
    }
  }

  static Future<Result<List<OrchestraPayLink>>> getPayLinks() async {
    try {
      final res = await _send((h) => http
          .get(Uri.parse('$_baseUrl/pay-links'), headers: h)
          .timeout(const Duration(seconds: 15)));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final list = (jsonDecode(res.body) as List<dynamic>)
            .map((e) => OrchestraPayLink.fromJson(e as Map<String, dynamic>))
            .toList();
        return Result(data: list);
      }
      return Result(error: _parseError(res.body));
    } catch (e) {
      return Result(error: e.toString());
    }
  }

  static Future<Result<void>> deletePayLink(String id) async {
    try {
      final res = await _send((h) => http
          .delete(
            Uri.parse('$_baseUrl/pay-links/$id'),
            headers: h,
          )
          .timeout(const Duration(seconds: 15)));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return Result(data: null);
      }
      return Result(error: _parseError(res.body));
    } catch (e) {
      return Result(error: e.toString());
    }
  }
}

/// A route catalog response and where it came from.
class OrchestraRoutesFetch {
  const OrchestraRoutesFetch({
    required this.json,
    required this.fromBackend,
    this.upstreamFetchedAt,
  });

  final Map<String, dynamic> json;
  final bool fromBackend;

  /// The backend's own fetch time for its cached copy, when sent.
  final DateTime? upstreamFetchedAt;
}
