import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:kute/services/polymarket_order_v2.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show ApiCredentials, EthPrivateKey;

/// The CLOB L1 contract is distinct from POLY_1271 order signing.
/// https://docs.polymarket.com/trading/wallets-auth
/// The EOA signs ClobAuth and authenticates L2 requests, including orders
/// whose maker and signer are a deposit wallet.
class PolymarketClobAuth {
  PolymarketClobAuth({http.Client? client}) : _client = client;
  final http.Client? _client;

  static String? cachedAddress(
    Map<dynamic, dynamic> record, {
    required String ownerAddress,
    String? depositWallet,
    bool legacyWalletBinding = false,
  }) {
    final address = record['authAddress'] ??
        (legacyWalletBinding ? depositWallet : ownerAddress);
    if (address is! String || !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address)) {
      return null;
    }
    final normalized = address.toLowerCase();
    return normalized == ownerAddress.toLowerCase() ||
            normalized == depositWallet?.toLowerCase()
        ? address
        : null;
  }

  static Future<Map<String, String>> headers({
    EthPrivateKey? credentials,
    EvmExternalSigner? externalSigner,
    required String address,
    required int timestamp,
    int nonce = 0,
  }) async {
    final signerAddress =
        credentials?.address.hexEip55 ?? externalSigner?.address;
    if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address) ||
        signerAddress?.toLowerCase() != address.toLowerCase() ||
        timestamp < 0 ||
        nonce < 0) {
      throw const FormatException('Invalid CLOB authentication identity');
    }
    return {
      'POLY_ADDRESS': address,
      'POLY_SIGNATURE': await signClobAuthEoa(
        credentials: credentials,
        externalSigner: externalSigner,
        address: address,
        timestamp: timestamp,
        nonce: nonce,
      ),
      'POLY_TIMESTAMP': timestamp.toString(),
      'POLY_NONCE': nonce.toString(),
    };
  }

  /// Nonce zero is the official SDK default and makes provisioning
  /// repeatable after a lost response without creating a new key each time.
  Future<ApiCredentials> deriveOrCreate(Map<String, String> headers) async {
    final ownedClient = _client == null;
    final client = _client ?? http.Client();
    try {
      final derived = await client
          .get(
            Uri.https('clob.polymarket.com', '/auth/derive-api-key'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));
      if (derived.statusCode == 200) return _parse(derived);
      // A failed lookup may mean no key exists for this nonce. Preserve
      // the reference client's create/derive compatibility, but never
      // fall back to a different signing identity or signature protocol.
      final created = await client
          .post(
            Uri.https('clob.polymarket.com', '/auth/api-key'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));
      if (created.statusCode != 200) {
        throw StateError(
            'CLOB credential creation failed (${created.statusCode})');
      }
      return _parse(created);
    } finally {
      if (ownedClient) client.close();
    }
  }

  static ApiCredentials _parse(http.Response response) {
    final body = jsonDecode(response.body);
    if (body is! Map ||
        !['apiKey', 'secret', 'passphrase'].every(
            (key) => body[key] is String && (body[key] as String).isNotEmpty)) {
      throw const FormatException('Invalid CLOB credential response');
    }
    return ApiCredentials(
      apiKey: body['apiKey'] as String,
      secret: body['secret'] as String,
      passphrase: body['passphrase'] as String,
    );
  }
}
