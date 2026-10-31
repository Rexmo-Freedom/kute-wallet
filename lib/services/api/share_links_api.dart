// lib/services/api/share_links_api.dart
//
// The share-links backend (`/api/v1/share/links`, see
// models/share_link_model.dart for what a link is). Every route takes the
// wallet-session bearer the affiliate routes mint
// (AffiliateService.sendWithSession: a session obtained first when none
// exists, one re-auth and retry on a 401), so a wallet only ever sees
// and pays its own links.
//
// [ShareLinksApi] is the interface the screens and the pay-on-open pass
// read through `shareLinksApiProvider`; tests override the provider with
// a fake. [BackendShareLinksApi] is the real client. It never logs or
// tracks a link id, a URL or a destination.

import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/models/share_link_model.dart';
import 'package:kute/services/http/shared_http_client.dart';

/// A backend answer the client could not use: a non-2xx status or a body
/// in a shape it does not know. [code] is the backend's `error` field
/// when it sent one (`link_not_found`, `link_not_open`, ...).
class ShareLinkApiException implements Exception {
  const ShareLinkApiException(this.status, {this.code});
  final int status;
  final String? code;

  bool get notFound => status == 404;
  bool get conflict => status == 409;

  @override
  String toString() => 'Share link request failed ($status)';
}

abstract class ShareLinksApi {
  Future<CreatedShareLink> create({
    required ShareLinkKind kind,
    required int amountMinor,
    String? marketSlug,
    String? senderLabel,
  });

  Future<ShareLink> read(String id);

  /// Claims [id] for [destination] (a Spark address or BOLT11 invoice of
  /// the claiming wallet). Resolves to the link's status after the claim.
  Future<ShareLinkStatus> claim(String id, {required String destination});

  /// This wallet's links the recipients have claimed and the sender has
  /// not paid yet.
  Future<List<ClaimedShareLink>> claimed();

  Future<void> markPaid(String id, {required String paymentId});

  Future<void> cancel(String id);
}

/// How a request reaches the backend with its session headers. Production
/// is [AffiliateService.sendWithSession]; tests pass a plain sender.
typedef SessionSender = Future<http.Response> Function(
  String route,
  Future<http.Response> Function(Map<String, String> auth) send,
);

class BackendShareLinksApi implements ShareLinksApi {
  BackendShareLinksApi({
    String? baseUrl,
    http.Client? client,
    SessionSender? sessionSender,
  })  : _baseUrl = baseUrl,
        _client = client,
        _sessionSender = sessionSender ?? AffiliateService.sendWithSession;

  final String? _baseUrl;
  final http.Client? _client;
  final SessionSender _sessionSender;

  String get _base =>
      '${_baseUrl ?? dotenv.env['BACKEND'] ?? ''}/api/v1/share/links';

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
  };

  @override
  Future<CreatedShareLink> create({
    required ShareLinkKind kind,
    required int amountMinor,
    String? marketSlug,
    String? senderLabel,
  }) async {
    final body = await _send('POST', '', body: {
      'kind': kind.name,
      'asset': kind.asset,
      'amountMinor': amountMinor,
      if (marketSlug != null && marketSlug.isNotEmpty) 'marketSlug': marketSlug,
      if (senderLabel != null && senderLabel.trim().isNotEmpty)
        'senderLabel': senderLabel.trim(),
    });
    final created = CreatedShareLink.fromJson(body);
    if (created == null) throw const ShareLinkApiException(200);
    return created;
  }

  @override
  Future<ShareLink> read(String id) async {
    final body = await _send('GET', '/${Uri.encodeComponent(id)}');
    final link = ShareLink.fromJson(body);
    if (link == null) throw const ShareLinkApiException(200);
    return link;
  }

  @override
  Future<ShareLinkStatus> claim(String id,
      {required String destination}) async {
    final body = await _send('POST', '/${Uri.encodeComponent(id)}/claim',
        body: {'destination': destination});
    return ShareLinkStatus.parse(body is Map ? body['status'] : null);
  }

  @override
  Future<List<ClaimedShareLink>> claimed() async {
    final body = await _send('GET', '/mine?status=claimed');
    final rows = body is Map ? (body['links'] ?? body['items']) : body;
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (ClaimedShareLink.fromJson(row) case final link?) link,
    ];
  }

  @override
  Future<void> markPaid(String id, {required String paymentId}) async {
    await _send('POST', '/${Uri.encodeComponent(id)}/paid',
        body: {'paymentId': paymentId});
  }

  @override
  Future<void> cancel(String id) async {
    await _send('POST', '/${Uri.encodeComponent(id)}/cancel', body: const {});
  }

  Future<Object?> _send(String method, String suffix,
      {Map<String, Object?>? body}) async {
    final uri = Uri.parse('$_base$suffix');
    final response = await _sessionSender('share_links', (auth) {
      final headers = {..._jsonHeaders, ...auth};
      const kind = HttpCallKind.userAction;
      const timeout = Duration(seconds: 20);
      return method == 'GET'
          ? SharedHttpClient.get(uri,
              headers: headers, kind: kind, timeout: timeout, client: _client)
          : SharedHttpClient.post(uri,
              headers: headers,
              body: jsonEncode(body ?? const {}),
              kind: kind,
              timeout: timeout,
              client: _client);
    });
    Object? decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = null;
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? code;
      if (decoded is Map) {
        final error = decoded['error'];
        code = error is String
            ? error
            : error is Map
                ? error['code']?.toString()
                : decoded['code']?.toString();
      }
      throw ShareLinkApiException(response.statusCode, code: code);
    }
    return decoded;
  }
}

/// The client the app reads through. Tests override it with a fake.
final shareLinksApiProvider = Provider<ShareLinksApi>((ref) {
  return debugShareLinksApi ?? BackendShareLinksApi();
});

/// Test seam for code paths that cannot read a provider (the AppsFlyer
/// hooks). Null uses the backend.
@visibleForTesting
ShareLinksApi? debugShareLinksApi;
