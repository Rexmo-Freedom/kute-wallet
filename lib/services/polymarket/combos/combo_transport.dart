// lib/services/polymarket/combos/combo_transport.dart
//
// The one seam between Kute and a Polymarket combo RFQ gateway.
//
// Today combos go through the public Requester API, authenticated with the
// user's own CLOB L2 headers, and that route forbids builder attribution:
// every signed order carries the zero builder, so combos earn Kute no
// builder fee yet. To move to the Builder Gateway once Kute is an approved
// combos builder, add a `BuilderGatewayComboTransport` here that:
//   * points at the builder host with base path `/v1/builder/rfq`;
//   * adds the POLY_BUILDER_* headers to `createRequest` and `accept`
//     (signed by the Kute backend, which holds the builder secret; never
//     sent on `status`);
//   * returns `attributesBuilder = true`, so the order signs the
//     `builder_code` the create response returns.
// Nothing else in the combo flow changes.
//
// Docs: docs.polymarket.com/trading/combos/requesters.md and builders.md.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kute/services/polymarket/combos/combo_models.dart';

/// Signs one request with the user's CLOB L2 headers (POLY_ADDRESS,
/// POLY_API_KEY, POLY_PASSPHRASE, POLY_TIMESTAMP, POLY_SIGNATURE) over
/// `timestamp + METHOD + full path + exact body`.
typedef ComboL2Signer = Map<String, String> Function({
  required String method,
  required String path,
  String? body,
});

/// One raw gateway answer. Bodies stay strings so the caller decodes once.
class ComboHttpResponse {
  const ComboHttpResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;

  Map<String, dynamic> get json {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('combo gateway sent no object');
  }
}

abstract interface class PolymarketComboTransport {
  /// True when orders on this route carry the gateway's `builder_code`
  /// (Builder Gateway). False on the Requester API, which rejects any
  /// non-zero builder with BUILDER_ATTRIBUTION_NOT_ALLOWED.
  bool get attributesBuilder;

  /// Short route name for analytics (`requester` / `builder`).
  String get route;

  /// `POST /requests` with [body], the exact serialized JSON.
  Future<ComboHttpResponse> createRequest(String body);

  /// `POST /requests/{rfqId}/accept` with [body]. Safe to repeat: the
  /// gateway never executes the same acceptance twice.
  Future<ComboHttpResponse> accept(String rfqId, String body);

  /// `GET /requests/{rfqId}`, only meaningful after acceptance (409 before).
  Future<ComboHttpResponse> status(String rfqId);
}

/// The public Requester API, authenticated with the user's own CLOB L2
/// credentials. No builder attribution on this route.
class RequesterComboTransport implements PolymarketComboTransport {
  RequesterComboTransport({
    required ComboL2Signer sign,
    http.Client? client,
    this.host = 'combos-rfq-gateway-requester-api.polymarket.com',
  })  : _sign = sign,
        _client = client ?? http.Client();

  static const String basePath = '/v1/requester/rfq';

  final ComboL2Signer _sign;
  final http.Client _client;
  final String host;

  @override
  bool get attributesBuilder => false;

  @override
  String get route => 'requester';

  Uri _uri(String path) => Uri.https(host, path);

  @override
  Future<ComboHttpResponse> createRequest(String body) async {
    const path = '$basePath/requests';
    final res = await _client
        .post(_uri(path),
            headers: {
              ..._sign(method: 'POST', path: path, body: body),
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: body)
        // The gateway holds the request through the 400 ms competition.
        .timeout(const Duration(seconds: 15));
    return ComboHttpResponse(res.statusCode, res.body);
  }

  @override
  Future<ComboHttpResponse> accept(String rfqId, String body) async {
    final path = '$basePath/requests/${Uri.encodeComponent(rfqId)}/accept';
    final res = await _client
        .post(_uri(path),
            headers: {
              ..._sign(method: 'POST', path: path, body: body),
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: body)
        .timeout(const Duration(seconds: 15));
    return ComboHttpResponse(res.statusCode, res.body);
  }

  @override
  Future<ComboHttpResponse> status(String rfqId) async {
    final path = '$basePath/requests/${Uri.encodeComponent(rfqId)}';
    final res = await _client.get(_uri(path), headers: {
      ..._sign(method: 'GET', path: path),
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 10));
    return ComboHttpResponse(res.statusCode, res.body);
  }
}

/// A non-2xx gateway answer as a [ComboRfqException]. The documented error
/// shape is `{error: "...", code: "..."}`.
ComboRfqException comboRfqError(ComboHttpResponse res) {
  String code = 'HTTP_${res.statusCode}';
  String? message;
  try {
    final decoded = jsonDecode(res.body);
    if (decoded is Map) {
      final c = decoded['code'];
      if (c is String && c.isNotEmpty) code = c;
      final e = decoded['error'];
      if (e is String) message = e;
      if (e is Map) {
        message = e['message']?.toString();
        final ec = e['code'];
        if (ec is String && ec.isNotEmpty) code = ec;
      }
    }
  } catch (_) {
    message = res.body.length > 200 ? res.body.substring(0, 200) : res.body;
  }
  return ComboRfqException(res.statusCode, code, message);
}
