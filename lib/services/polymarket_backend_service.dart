import 'package:kute/services/runtime_capabilities_service.dart';
// lib/services/polymarket_backend_service.dart
//
// Non-custodial Polymarket order service.
//
// All requests go directly from the phone to the CLOB (preserves geoblock).
// Builder attribution is part of the signed V2 order. After CLOB acceptance,
// the backend can verify a read-only receipt for accounting; it never places
// the trade or receives the user's L2 secret or wallet signing keys.
//
// We compute HMAC-SHA256 L2 auth ourselves (matching the official py-clob-client)
// because the Dart library has bugs in L2Auth and SignedOrder.toJson().
//
// Verified against: https://github.com/Polymarket/py-clob-client
//   - Secret decoded via base64url (handles '-' and '_' in secrets)
//   - HMAC output encoded via base64url (NOT standard base64)
//   - L2 auth uses 5 headers (NO POLY_NONCE — that's L1 only)
//   - Order body includes 'owner' field (= api key)
//   - Order JSON: salt=int, side="BUY"/"SELL", signatureType=int

import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:kute/services/polymarket/builder_code_resolver.dart';
import 'package:kute/services/polymarket/placement_diagnostics.dart';
import 'package:kute/services/tracking/order_ack_latency.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/polymarket/market_protocol.dart';
import 'package:kute/services/polymarket_order_v2.dart';
import 'package:kute/services/venue_owner_link_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    hide PolymarketConstants;

/// Thrown when the CLOB API returns a 403 geo-restriction.
class GeoBlockException implements Exception {
  @override
  // English on purpose: exception text feeds error categories and logs.
  // Screens map the type to tradingNotAvailableInRegion.
  String toString() => 'Trading is not available in your region.';
}

/// Thrown when the CLOB API returns a 401 (stale/invalid credentials).
class InvalidApiKeyException implements Exception {
  @override
  String toString() => 'Invalid API credentials — refreshing...';
}

/// The venue answered and did not accept this request: a documented
/// refusal, or an HTTP 400 that names an error and no order (see
/// [polymarketHttpRejection]). Transport errors, timeouts, 5xx, duplicate
/// orders and matching delays never use this type.
class PolymarketOrderNotAcceptedException implements Exception {
  const PolymarketOrderNotAcceptedException(this.reason);
  final String reason;

  @override
  String toString() => reason;
}

/// The CLOB's balance refusal. It is documented as the bare sentence, but
/// the venue appends what it counted ("…allowance: the balance is not
/// enough -> balance: 0, order amount: 5000000"); both are the same refusal.
const String kPolymarketBalanceRefusal = 'not enough balance / allowance';

/// Whether [message] is the CLOB's balance refusal, with or without the
/// figures it appends. The order was not accepted.
bool isPolymarketBalanceRefusal(Object? message) {
  if (message is! String ||
      !message.startsWith(kPolymarketBalanceRefusal)) {
    return false;
  }
  final rest = message.substring(kPolymarketBalanceRefusal.length);
  // The detail follows a separator; a longer word is another message.
  return rest.isEmpty || !RegExp(r'^[A-Za-z0-9]').hasMatch(rest);
}

/// Positive proof only: unrecognized CLOB failures remain ambiguous.
/// https://docs.polymarket.com/resources/error-codes#order-processing-errors
///
/// The balance refusal is recognised with its appended figures too: read
/// as ambiguous, the first prediction after a deposit (refused while the
/// venue still counted the old balance) left its order "unaccounted for"
/// and ended on "A previous prediction is still being confirmed".
bool isDefinitivePolymarketOrderRejection(Object? message) =>
    isPolymarketBalanceRefusal(message) ||
    const {
      'Invalid order payload',
      'the order owner has to be the owner of the API KEY',
      'the order signer address has to be the address of the API KEY',
      'invalid post-only order: order crosses book',
      'invalid expiration',
      'order canceled in the CTF exchange contract',
      "order couldn't be fully filled. FOK orders are fully filled or killed.",
      'no orders found to match with FAK order. FAK orders are partially filled or killed if no match is found.',
      'the market is not yet ready to process new orders',
    }.contains(message);

/// The refusal text of a `POST /order` answer that proves the order was
/// not accepted, or null when the answer proves nothing.
///
/// Definitive:
///  - an HTTP 400 carrying a documented refusal (in `error`), with or
///    without the order hash a rejected FAK request can echo;
///  - any other HTTP 400 that carries an error message (`error` or
///    `errorMsg`) and no order id, no accepted status and no success: the
///    CLOB answered and did not take the order. Treating these as
///    ambiguous kept the order journal blocking for 2 to 30 minutes ("A
///    previous prediction is still being confirmed") with nothing for the
///    status check to find. A matching delay is never one of these.
/// Network errors, timeouts, 5xx and every other status stay ambiguous.
String? polymarketHttpRejection(http.Response response) {
  if (response.statusCode != 400) return null;
  try {
    final body = jsonDecode(response.body);
    if (body is! Map) return null;
    final documented = body['error'];
    if (body.keys.every((key) => key == 'error' || key == 'orderID') &&
        // A rejected FAK request can still include its computed order hash.
        // It is not an acknowledgement or evidence of a fill.
        (body['orderID'] == null ||
            (body['orderID'] is String &&
                RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(body['orderID']))) &&
        isDefinitivePolymarketOrderRejection(documented)) {
      return documented as String;
    }
    final message = body['error'] ?? body['errorMsg'];
    if (message is! String || message.trim().isEmpty) return null;
    if (message.toLowerCase().contains('delay')) return null;
    bool blank(Object? value) => value == null || value.toString().isEmpty;
    if (!blank(body['orderID']) ||
        !blank(body['orderId']) ||
        !blank(body['order_id']) ||
        !blank(body['status']) ||
        body['success'] == true) {
      return null;
    }
    final hashes = body['transactionsHashes'];
    if (hashes is List && hashes.isNotEmpty) return null;
    return message;
  } catch (_) {
    return null;
  }
}

@visibleForTesting
bool isDefinitivePolymarketHttpRejection(http.Response response) =>
    polymarketHttpRejection(response) != null;

class PolymarketBackendService {
  final String _apiKey;
  final String _secret;
  final String _passphrase;
  final String _walletAddress;

  static const _clobBaseUrl = 'https://clob.polymarket.com';

  PolymarketBackendService({
    required String apiKey,
    required String secret,
    required String passphrase,
    required String walletAddress,
  })  : _apiKey = apiKey,
        _secret = secret,
        _passphrase = passphrase,
        _walletAddress = walletAddress;

  /// Builds the exact `/order` POST body (as a Map) for a signed order —
  /// the same shape [submitOrder] sends, without POSTing. Used by the
  /// instant pre-sign flow: the backend stores these bytes verbatim and
  /// computes its own fresh L2 HMAC over them at fire time.
  Map<String, dynamic> buildOrderPostBody({
    required SignedOrderV2 signedOrder,
    OrderType orderType = OrderType.gtc,
  }) {
    final orderMap = signedOrder.order.toJson();
    orderMap['signature'] = signedOrder.signature;
    orderMap['expiration'] =
        '0'; // GTC/FOK/FAK wire field; not in V2 typed data.

    // Salt: V2 OrderStructV2 encodes salt as string; CLOB expects int.
    final saltStr = orderMap['salt'].toString();
    orderMap['salt'] = int.tryParse(saltStr) ?? saltStr;

    // Side: V2 OrderStructV2 encodes side as int (0/1); CLOB expects string.
    final sideVal = orderMap['side'];
    if (sideVal is int) {
      orderMap['side'] = sideVal == 0 ? 'BUY' : 'SELL';
    }

    return {
      'deferExec': false,
      'order': orderMap,
      'owner': _apiKey,
      'orderType': orderType.toJson(),
    };
  }

  /// The V2 builder code (bytes32 hex) to sign into an order's `builder`
  /// field for revenue attribution.
  ///
  /// The backend is the only source (see [PolymarketBuilderCodeResolver]);
  /// it is cached per policy revision and session for this app run only.
  /// When the backend is unreachable or answers with no valid code this
  /// returns the zero builder, so trading is never blocked on attribution.
  static final PolymarketBuilderCodeResolver _builderCodes =
      PolymarketBuilderCodeResolver(
    client: () => _client,
    baseUrl: () => dotenv.isInitialized ? dotenv.env['BACKEND'] ?? '' : '',
    revision: () => RuntimeCapabilitiesService.instance.snapshot?.revision,
    session: () => AffiliateService.sessionToken,
    onFailure: (error, elapsed) => PolymarketPlacementDiagnostics.stepFailed(
        'builder_code', error, elapsed),
    // The policy moved on since the app last read it; catch up so the next
    // order can carry the code for the current revision.
    onRevisionMismatch: (_) =>
        unawaited(RuntimeCapabilitiesService.instance.refresh()),
  );

  /// One connection for the builder-code reads. A fresh client per call
  /// pays a new TLS handshake each time, which over a VPN is most of the
  /// five seconds the first attempt allows.
  static http.Client? _builderClient;
  static http.Client get _client => _builderClient ??= http.Client();

  @visibleForTesting
  static void resetBuilderCodeForTest() {
    _builderCodes.reset();
    _builderClient?.close();
    _builderClient = null;
  }

  /// Warms the in-memory code so the order path reads it instantly.
  static Future<void> prefetchBuilderCode() async {
    await getBuilderCode();
  }

  /// The code to sign with now: the backend's, or the zero builder when
  /// there is none to be had. Never throws.
  static Future<String> getBuilderCode() async {
    final resolved = await _builderCodes.resolve();
    if (!resolved.attributed) {
      PolymarketPlacementDiagnostics.note('builder_code', {'source': 'none'});
    }
    return resolved.code;
  }

  /// Compute HMAC-SHA256 signature (matches py-clob-client exactly).
  ///
  /// Message = timestamp + method + path + body
  /// Key    = base64url-decode(secret)
  /// Output = base64url-encode(HMAC-SHA256(key, message))
  String _hmacSignature({
    required String timestamp,
    required String method,
    required String path,
    String? body,
  }) {
    final message = '$timestamp$method$path${body ?? ''}';
    final secretBytes = base64Url.decode(base64Url.normalize(_secret));
    final hmac = Hmac(sha256, secretBytes);
    final digest = hmac.convert(utf8.encode(message));
    // base64url encode — matches Python's base64.urlsafe_b64encode()
    return base64Url.encode(digest.bytes);
  }

  /// Compute the L2 auth bundle for the CLOB WebSocket's user-channel
  /// subscribe payload. Same HMAC contract as REST — the server
  /// expects the `auth` field of the `subscribe` message to carry
  /// {POLY_ADDRESS, POLY_SIGNATURE, POLY_TIMESTAMP, POLY_API_KEY,
  /// POLY_PASSPHRASE}. Method/path are fixed (`GET /ws/user`) per
  /// Polymarket's CLOB spec.
  Map<String, String> userChannelAuthHeaders() {
    return _authHeaders(method: 'GET', path: '/ws/user');
  }

  /// The same 5 L2 headers for another Polymarket gateway that takes CLOB
  /// credentials (the combos Requester API). [path] is the full request
  /// path without host or query; [body] the exact bytes sent.
  Map<String, String> l2Headers({
    required String method,
    required String path,
    String? body,
  }) =>
      _authHeaders(method: method, path: path, body: body);

  /// Generates the 5 L2 auth headers for CLOB requests.
  /// Note: POLY_NONCE is L1-only and NOT included in L2 auth.
  Map<String, String> _authHeaders({
    required String method,
    required String path,
    String? body,
  }) {
    final timestamp =
        (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
    final signature = _hmacSignature(
      timestamp: timestamp,
      method: method,
      path: path,
      body: body,
    );

    return <String, String>{
      'POLY_ADDRESS': _walletAddress,
      'POLY_SIGNATURE': signature,
      'POLY_TIMESTAMP': timestamp,
      'POLY_API_KEY': _apiKey,
      'POLY_PASSPHRASE': _passphrase,
      'Content-Type': 'application/json',
    };
  }

  /// Submit a V2 signed order directly to the Polymarket CLOB.
  ///
  /// No backend proxy on the order path — the app posts straight to
  /// `clob.polymarket.com/order` with the user's L2 auth headers. Builder
  /// attribution lives in the signed order's `builder` field (bytes32),
  /// baked in at signing time.
  Future<Map<String, dynamic>> submitOrder({
    required SignedOrderV2 signedOrder,
    OrderType orderType = OrderType.gtc,
    void Function()? beforePost,
  }) async {
    if (signedOrder.order.side == 0) {
      // Re-check at actual submission, including retry and Ledger call paths.
      // SELL remains independent so the CLOB can permit close-only access.
      // The slip checked moments ago; a policy fetched within the last
      // minute is read, not fetched again, so the post is not held on a
      // second round trip.
      await RuntimeCapabilitiesService.instance.ensureAllowed(
          'polymarket.trade',
          maxAge: const Duration(seconds: 60));
    }
    final accountingIdentity = AffiliateService.revenueIdentity;
    final body = jsonEncode(
        buildOrderPostBody(signedOrder: signedOrder, orderType: orderType));

    try {
      final headers = _authHeaders(
        method: 'POST',
        path: '/order',
        body: body,
      );

      // Debug trace, deliberately credential-free: the old verbose
      // dump printed every L2 header verbatim (POLY_PASSPHRASE and
      // POLY_SIGNATURE included) plus the signed order body — anyone
      // sharing a debug log was sharing their API credentials. What
      // survives is the shape info that was actually useful for
      // diffing against the reference client.
      if (kDebugMode) {
        try {
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          final order = decoded['order'] as Map<String, dynamic>?;
          debugPrint('[pm-order] POST /order '
              'type=${decoded['orderType']} '
              'maker=${order?['maker']} signer=${order?['signer']} '
              'sigType=${order?['signatureType']} side=${order?['side']}');
        } catch (_) {}
      }

      beforePost?.call();
      // POST → CLOB acknowledgement latency (duration + time-in-force
      // kind only; nothing from the order). One event per post.
      final ack = Stopwatch()..start();
      void reportAck(String outcome) {
        if (!ack.isRunning) return;
        ack.stop();
        OrderAckLatency.record(
          venue: 'polymarket',
          orderKind: orderType.name,
          durationMs: ack.elapsedMilliseconds,
          outcome: outcome,
        );
      }

      final http.Response response;
      try {
        response = await http
            .post(Uri.parse('$_clobBaseUrl/order'),
                headers: headers, body: body)
            .timeout(const Duration(seconds: 20));
      } on TimeoutException {
        reportAck('timeout');
        rethrow;
      } catch (_) {
        reportAck('error');
        rethrow;
      }
      reportAck(response.statusCode == 200 ? 'ok' : 'rejected');

      if (kDebugMode) {
        debugPrint(
            '[pm-order] response ${response.statusCode}: ${response.body}');
      }

      // Detect geoblock (403 with "restricted")
      if (response.statusCode == 403 &&
          response.body.toLowerCase().contains('restricted')) {
        throw GeoBlockException();
      }

      // Detect stale/invalid credentials (401)
      if (response.statusCode == 401) {
        throw InvalidApiKeyException();
      }

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        final orderId = (result['orderID'] ?? result['orderId'])?.toString();
        if (result['success'] != false &&
            orderId != null &&
            accountingIdentity != null) {
          unawaited(verifyAcceptedOrder(orderId,
              accountingIdentity: accountingIdentity));
        }
        return result;
      }

      final refusal = polymarketHttpRejection(response);
      if (refusal != null) throw PolymarketOrderNotAcceptedException(refusal);
      throw Exception(
          'Order rejected (${response.statusCode}): ${response.body}');
    } on GeoBlockException {
      rethrow;
    } on InvalidApiKeyException {
      rethrow;
    } on TimeoutException {
      throw Exception('Order submission timed out');
    }
  }

  /// Read-only evidence for revenue attribution after the direct CLOB request.
  /// The ephemeral HMAC authorizes only GET /data/order/{id}; API secrets and
  /// private signing material stay on device. Failure never changes trade success.
  Future<void> verifyAcceptedOrder(String orderId,
      {required String accountingIdentity}) async {
    if (!RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(orderId)) return;
    final backend = dotenv.isInitialized ? dotenv.env['BACKEND'] ?? '' : '';
    if (backend.isEmpty) return;
    // Once this account's ownership is linked, the backend attributes its
    // builder-fee trades itself and no longer needs per-order receipts.
    if (await VenueOwnerLinkService.isPolymarketLinked(_walletAddress)) return;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (AffiliateService.revenueIdentity != accountingIdentity) return;
      try {
        final response = await AffiliateService.sendWithSession(
            'polymarket_order_receipt', (auth) {
          if (AffiliateService.revenueIdentity != accountingIdentity) {
            throw StateError('Accounting identity changed');
          }
          return http
              .post(
                Uri.parse('$backend/api/v1/pm/verify-order'),
                headers: {
                  ..._authHeaders(method: 'GET', path: '/data/order/$orderId'),
                  ...auth
                },
                body: jsonEncode({'orderId': orderId}),
              )
              .timeout(const Duration(seconds: 8));
        });
        if (response.statusCode >= 200 && response.statusCode < 300) return;
        if (response.statusCode >= 400 &&
            response.statusCode < 500 &&
            response.statusCode != 429) {
          return;
        }
      } catch (_) {
        // A receipt can retry; an accepted order must never be submitted twice.
      }
      if (attempt == 0) await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  /// Tell the CLOB to re-read the Safe's on-chain allowance state.
  ///
  /// Required by Polymarket V2 after every `fixMissingApprovals` /
  /// `enableTrading` run: the CLOB caches a Safe's balance + allowance
  /// snapshot and refuses to match orders against stale numbers. Skipping
  /// this is one of the silent reasons a freshly-onboarded Safe still
  /// 400s. Endpoint is documented as a "GET update" (yes, GET on `/update`)
  /// per docs.polymarket.com/trading/deposit-wallets and the V2 reference
  /// client (clob-client-v2 `client.ts updateBalanceAllowance`).
  ///
  /// The CLOB `asset_type` for [assetType] and [tokenId]: CONDITIONAL
  /// becomes CONDITIONAL-V2 for a Protocol V2 position id.
  static String balanceAllowanceAssetType(String assetType, String? tokenId) =>
      assetType == 'CONDITIONAL' && tokenId != null && tokenId.isNotEmpty
          ? PolyMarketProtocol.conditionalAssetType(tokenId)
          : assetType;

  /// [signatureType] should be 3 for POLY_1271 / deposit-wallet trading.
  /// [tokenId] is only set for CONDITIONAL (outcome share) allowances —
  /// COLLATERAL (pUSD) calls omit it. A CONDITIONAL refresh for a Protocol
  /// V2 position is sent as `CONDITIONAL-V2` (PositionManager shares), as
  /// docs.polymarket.com/migrate/polymarket-v2/api-integrations requires.
  Future<void> updateBalanceAllowance({
    required String assetType, // 'COLLATERAL' | 'CONDITIONAL'
    required int signatureType,
    String? tokenId,
  }) async {
    final params = <String, String>{
      'asset_type': balanceAllowanceAssetType(assetType, tokenId),
      'signature_type': signatureType.toString(),
      if (tokenId != null && tokenId.isNotEmpty) 'token_id': tokenId,
    };
    // CRITICAL: HMAC signs the bare path WITHOUT the query string.
    // Polymarket's reference (`clob-client-v2/src/client.ts
    // updateBalanceAllowance`) sets `requestPath: UPDATE_BALANCE_ALLOWANCE`
    // (the path constant alone) when computing L2 headers, then attaches
    // params to the URL separately. Signing with the query embedded
    // returns 401 "Invalid API credentials" — exactly what we were seeing.
    const signedPath = '/balance-allowance/update';
    final urlPath = '$signedPath?${Uri(queryParameters: params).query}';
    try {
      final response = await http
          .get(
            Uri.parse('$_clobBaseUrl$urlPath'),
            headers: _authHeaders(method: 'GET', path: signedPath),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) {
        throw InvalidApiKeyException();
      }
      if (response.statusCode != 200) {
        throw Exception(
            'balance-allowance/update failed (${response.statusCode}): '
            '${response.body}');
      }
    } on TimeoutException {
      throw Exception('balance-allowance/update timed out');
    }
  }

  // HTTP 200 can still contain rejected cancellations (or a partial batch).
  static void _checkCancellation(String body, {String? orderId}) {
    final result = jsonDecode(body) as Map<String, dynamic>;
    final rejected = result['not_canceled'];
    final canceled = result['canceled'];
    if (rejected is! Map ||
        canceled is! List ||
        rejected.isNotEmpty ||
        (orderId != null && !canceled.contains(orderId))) {
      throw StateError(
          'Some orders could not be cancelled. Refresh and retry.');
    }
  }

  /// Cancel a specific order by ID.
  Future<void> cancelOrder(String orderId) async {
    final body = jsonEncode({'orderID': orderId});

    try {
      final response = await http
          .delete(
            Uri.parse('$_clobBaseUrl/order'),
            headers: _authHeaders(
              method: 'DELETE',
              path: '/order',
              body: body,
            ),
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 403 &&
          response.body.toLowerCase().contains('restricted')) {
        throw GeoBlockException();
      }

      if (response.statusCode != 200) {
        throw Exception(
            'Cancel failed (${response.statusCode}): ${response.body}');
      }
      _checkCancellation(response.body, orderId: orderId);
    } on GeoBlockException {
      rethrow;
    } on TimeoutException {
      throw Exception('Cancel order timed out');
    }
  }

  /// Cancel all open orders.
  Future<void> cancelAllOrders() async {
    try {
      final response = await http
          .delete(
            Uri.parse('$_clobBaseUrl/cancel-all'),
            headers: _authHeaders(
              method: 'DELETE',
              path: '/cancel-all',
            ),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 403 &&
          response.body.toLowerCase().contains('restricted')) {
        throw GeoBlockException();
      }

      if (response.statusCode != 200) {
        throw Exception(
            'Cancel all failed (${response.statusCode}): ${response.body}');
      }
      _checkCancellation(response.body);
    } on GeoBlockException {
      rethrow;
    } on TimeoutException {
      throw Exception('Cancel all orders timed out');
    }
  }

  /// Get open orders from the CLOB directly.
  Future<List<Order>> getOpenOrders({String? market}) async =>
      (await getOpenOrderData(market: market)).map(Order.fromJson).toList();

  /// Keeps the authenticated maker address for wallet-scoped collateral checks.
  Future<List<Map<String, dynamic>>> getOpenOrderData({String? market}) async {
    const signedPath = '/data/orders';
    final orders = <Map<String, dynamic>>[];
    final seenCursors = <String>{};
    String? cursor;
    do {
      final params = <String, String>{
        if (market != null) 'market': market,
        if (cursor != null) 'next_cursor': cursor,
      };
      final response = await http
          .get(
            Uri.parse('$_clobBaseUrl$signedPath')
                .replace(queryParameters: params),
            // Sign the bare path, never the pagination query.
            headers: _authHeaders(method: 'GET', path: signedPath),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) throw InvalidApiKeyException();
      if (response.statusCode != 200) {
        throw StateError(
            'Could not load open orders (${response.statusCode}).');
      }
      final decoded = jsonDecode(response.body);
      final List<dynamic> rows;
      if (decoded is List) {
        rows = decoded;
        cursor = null;
      } else {
        final page = decoded as Map<String, dynamic>;
        rows = page['data'] as List<dynamic>;
        cursor = page['next_cursor'] as String?;
      }
      orders.addAll(rows.map((o) => o as Map<String, dynamic>));
      if (cursor == null || cursor.isEmpty || cursor == 'LTE=') break;
      if (!seenCursors.add(cursor)) {
        throw StateError('Open orders returned a repeated page.');
      }
    } while (true);
    return orders;
  }

  Future<Map<String, dynamic>> getCollateralBalanceAllowance() async {
    const path = '/balance-allowance';
    final response = await http
        .get(
          Uri.parse('$_clobBaseUrl$path').replace(queryParameters: {
            'asset_type': 'COLLATERAL',
            'signature_type': '3',
          }),
          headers: _authHeaders(method: 'GET', path: path),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 401) throw InvalidApiKeyException();
    if (response.statusCode != 200) {
      throw StateError('Could not verify Predictions collateral.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// A missing order is not proof that a timed-out submission was rejected.
  Future<Map<String, dynamic>?> getOrderById(String orderId) async {
    if (!RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(orderId)) {
      throw const FormatException('Invalid order ID.');
    }
    final path = '/data/order/$orderId';
    final response = await http
        .get(
          Uri.parse('$_clobBaseUrl$path'),
          headers: _authHeaders(method: 'GET', path: path),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 401) throw InvalidApiKeyException();
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      final body = response.body.replaceAll('\n', ' ');
      throw StateError('Could not verify prediction status '
          '(HTTP ${response.statusCode}: '
          '${body.length > 120 ? body.substring(0, 120) : body}).');
    }
    // The venue answers 200 with a JSON null for an order it never
    // accepted. That is an answer ("no such order"), the same as a 404;
    // casting it used to throw and read as no answer at all.
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// One of this account's trades by id (`GET /data/trades?id=`): its
  /// on-chain status (MATCHED, MINED, CONFIRMED, RETRYING, FAILED) and the
  /// maker orders it matched. Null when the venue does not list it. The L2
  /// signature covers the path only, as the reference client signs it.
  Future<Map<String, dynamic>?> getTradeById(String tradeId) async {
    if (tradeId.isEmpty || tradeId.length > 128) {
      throw const FormatException('Invalid trade ID.');
    }
    const path = '/data/trades';
    final response = await http
        .get(
          Uri.parse('$_clobBaseUrl$path')
              .replace(queryParameters: {'id': tradeId}),
          headers: _authHeaders(method: 'GET', path: path),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 401) throw InvalidApiKeyException();
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw StateError('Could not read the trade (HTTP ${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    final list = decoded is Map ? decoded['data'] : decoded;
    if (list is! List) return null;
    for (final t in list) {
      if (t is Map<String, dynamic> && t['id']?.toString() == tradeId) return t;
    }
    return null;
  }

  // No `/fee-rate` reader: V2 orders carry no feeRateBps (fees are set at
  // match time). The fee schedule the bet slip shows comes from the CLOB
  // market itself — see polymarket/polymarket_fee_terms.dart.
}
