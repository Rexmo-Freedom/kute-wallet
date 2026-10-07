import 'dart:convert';

import 'package:http/http.dart' as http;

import 'jade_rpc.dart';

/// Orchestrates the blind oracle PIN authentication flow between
/// Jade device, this app (relay), and Blockstream's PIN server.
///
/// The app acts as an HTTP relay: Jade produces an encrypted handshake
/// payload, the app forwards it to the PIN server, and relays the server's
/// encrypted response back to Jade. The app never sees the actual PIN.
class JadePinAuth {
  final JadeRpc _rpc;
  final http.Client _httpClient;

  /// Default Blockstream PIN server URL.
  static const String defaultPinServerUrl = 'https://jadepin.blockstream.com';

  JadePinAuth(this._rpc, {http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Execute the full PIN authentication flow.
  ///
  /// 1. Calls `auth_user` on Jade → device shows PIN entry screen
  /// 2. User enters PIN on the Jade device (can take 30+ seconds)
  /// 3. Jade returns handshake data with a URL and encrypted payload
  /// 4. App relays payload to Blockstream PIN server via HTTP POST
  /// 5. PIN server returns encrypted response
  /// 6. App relays response back to Jade
  /// 7. Jade decrypts master key → authenticated
  ///
  /// Returns `true` if authentication succeeded, `false` otherwise.
  /// Throws on network errors or RPC errors.
  Future<bool> authenticate({required String network}) async {
    // Step 1: Call auth_user — Jade shows PIN pad, user enters PIN
    // This call blocks until the user completes PIN entry on the device.
    final authResult = await _rpc.authUser(network: network);

    if (authResult is bool) {
      // Already authenticated (e.g., from a previous session)
      return authResult;
    }

    if (authResult is! Map) {
      return false;
    }

    // Step 2: Process handshake — may require multiple round-trips
    return _processAuthResponse(Map<String, dynamic>.from(authResult));
  }

  /// Process an auth response, handling the HTTP relay protocol.
  ///
  /// Jade's `auth_user` returns an `http_request` containing the URL and
  /// data to POST to the PIN server. The server's response is then relayed
  /// back to Jade as the reply to the next expected message.
  Future<bool> _processAuthResponse(Map<String, dynamic> authResponse) async {
    dynamic result = authResponse;
    while (result is Map && result.containsKey('http_request')) {
      final httpRequest = result['http_request'];
      if (httpRequest is! Map ||
          httpRequest['params'] is! Map ||
          httpRequest['on-reply'] is! String ||
          (httpRequest['on-reply'] as String).isEmpty) {
        throw Exception('Invalid Jade PIN authentication response.');
      }
      final params = httpRequest['params'] as Map;
      final urls = params['urls'];
      var url = defaultPinServerUrl;
      if (urls is List && urls.isNotEmpty) {
        // Avoid a dynamically typed firstWhere/orElse callback: CBOR and
        // typed platform lists can give the closure incompatible return types.
        final candidates = urls.whereType<String>().toList();
        if (candidates.isEmpty) {
          throw Exception('Invalid Jade PIN server address.');
        }
        url = candidates.first;
        for (final candidate in candidates) {
          if (!candidate.contains('.onion')) {
            url = candidate;
            break;
          }
        }
      } else if (urls is Map && urls['url'] is String) {
        url = urls['url'] as String;
      }

      final serverResponse =
          await _callPinServer(url: url, data: params['data']);
      if (serverResponse == null) {
        throw Exception('PIN server returned an empty response. '
            'Check your internet connection or try QR Mode.');
      }

      // call() validates the envelope and returns its result. Each round may
      // contain another HTTP request; only Jade's final boolean is success.
      result = await _rpc.call(httpRequest['on-reply'] as String,
          params: serverResponse, timeout: const Duration(seconds: 30));
    }
    return result == true;
  }

  /// Relay encrypted data without including response bodies in errors.
  Future<Map<String, dynamic>?> _callPinServer({
    required String url,
    required dynamic data,
  }) async {
    final http.Response response;
    try {
      response = await _httpClient
          .post(Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: data is String ? data : jsonEncode(data))
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw Exception('Cannot reach Blockstream PIN server. '
          'Check your internet connection or use QR Mode instead.');
    }
    if (response.statusCode != 200) {
      throw Exception('PIN server could not complete the request.');
    }
    if (response.body.isEmpty) return null;
    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        throw const FormatException();
      }
      return body;
    } catch (_) {
      throw Exception('PIN server returned an invalid response.');
    }
  }

  /// Dispose of the HTTP client.
  void dispose() {
    _httpClient.close();
  }
}
