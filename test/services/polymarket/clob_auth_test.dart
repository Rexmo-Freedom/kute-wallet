import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:kute/services/polymarket/clob_auth.dart';
import 'package:kute/services/polymarket_order_v2.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey, EthSignature;

// Public synthetic key shared with the existing typed-data fixtures.
final key = EthPrivateKey.fromHex(
    '0x0123456789012345678901234567890101234567890123456789012345678901');
const wallet = '0x5555555555555555555555555555555555555555';
const fixture = {
  'apiKey': 'fixture-key',
  'secret': 'c2VjcmV0',
  'passphrase': 'fixture'
};

void main() {
  test('hot and Ledger L1 auth match the independent Viem EIP-712 vector',
      () async {
    // Generated with viem 2.38.0 privateKeyToAccount.signTypedData, using
    // the official clob-client-v2 src/signing/eip712.ts domain and message.
    const expected =
        '0x3d2995b006433122a7bc730b6595f237d6185a0354e6918bdc47bf54d8468d5824d191ae3d6e4af17ec10fd16335cef851d13415b17571737b9d0e82f37b0d741c';
    final hot = await PolymarketClobAuth.headers(
        credentials: key, address: key.address.hexEip55, timestamp: 1700000000);
    final ledger = await PolymarketClobAuth.headers(
        externalSigner: EvmExternalSigner(
            address: key.address.hexEip55,
            sign: (request) async => key.signToSignature(request.digest)),
        address: key.address.hexEip55,
        timestamp: 1700000000);
    expect(hot, ledger);
    final digest = clobAuthEoaTypedData(
            address: key.address.hexEip55, timestamp: 1700000000, nonce: 0)
        .digest;
    expect(digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        '7b5df0ead64705c36de306fff15a7f5cffa20001691ee0097ffbb3c76ae45597');
    // ECDSA implementations may choose different nonces. Both signatures
    // must recover the same EOA over the independent digest.
    for (final wire in [expected, hot['POLY_SIGNATURE']!]) {
      final hex = wire.substring(2);
      final signature = EthSignature(
          BigInt.parse(hex.substring(0, 64), radix: 16),
          BigInt.parse(hex.substring(64, 128), radix: 16),
          int.parse(hex.substring(128, 130), radix: 16));
      expect(recoverSignerAddress(digest, signature),
          key.address.hexEip55.toLowerCase());
    }
    expect(hot['POLY_ADDRESS'], key.address.hexEip55);
    expect(hot['POLY_NONCE'], '0');
    expect(hot['POLY_TIMESTAMP'], '1700000000');
  });

  test('L1 cannot authenticate a different address using the EOA signer',
      () async {
    await expectLater(
        PolymarketClobAuth.headers(
            credentials: key, address: wallet, timestamp: 1700000000),
        throwsFormatException);
  });

  test('derive preserves the official wire schema without requiring nonce',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/auth/derive-api-key');
      return http.Response(jsonEncode(fixture), 200);
    });
    final result = await PolymarketClobAuth(client: client).deriveOrCreate({});
    expect(result.apiKey, fixture['apiKey']);
  });

  test('missing credentials are created with exactly the same L1 identity',
      () async {
    final methods = <String>[];
    final headers = await PolymarketClobAuth.headers(
        credentials: key, address: key.address.hexEip55, timestamp: 1700000000);
    final client = MockClient((request) async {
      methods.add(request.method);
      expect(request.headers['POLY_ADDRESS'], headers['POLY_ADDRESS']);
      expect(request.headers['POLY_SIGNATURE'], headers['POLY_SIGNATURE']);
      expect(request.headers['POLY_NONCE'], '0');
      return request.method == 'GET'
          ? http.Response('{"error":"not found"}', 400)
          : http.Response(jsonEncode(fixture), 200);
    });
    await PolymarketClobAuth(client: client).deriveOrCreate(headers);
    expect(methods, ['GET', 'POST']);
  });

  for (final malformed in [
    '[]',
    '{}',
    '{"apiKey":"", "secret":"s", "passphrase":"p"}'
  ]) {
    test('malformed success fails without creating another key: $malformed',
        () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response(malformed, 200);
      });
      await expectLater(PolymarketClobAuth(client: client).deriveOrCreate({}),
          throwsFormatException);
      expect(calls, 1);
    });
  }

  test('a lost derive response does not create a different key or identity',
      () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      throw http.ClientException('offline');
    });
    await expectLater(PolymarketClobAuth(client: client).deriveOrCreate({}),
        throwsA(isA<http.ClientException>()));
    expect(calls, 1);
  });

  test('cached credentials retain their explicit binding across restarts', () {
    final owner = key.address.hexEip55;
    expect(
        PolymarketClobAuth.cachedAddress({'authAddress': owner},
            ownerAddress: owner, depositWallet: wallet),
        owner);
    expect(
        PolymarketClobAuth.cachedAddress({'authAddress': wallet},
            ownerAddress: owner, depositWallet: wallet),
        wallet);
    expect(
        PolymarketClobAuth.cachedAddress({},
            ownerAddress: owner, depositWallet: wallet),
        owner);
    expect(
        PolymarketClobAuth.cachedAddress({},
            ownerAddress: owner,
            depositWallet: wallet,
            legacyWalletBinding: true),
        wallet);
    expect(
        PolymarketClobAuth.cachedAddress({'authAddress': '0x${'77' * 20}'},
            ownerAddress: owner, depositWallet: wallet),
        isNull);
    expect(
        PolymarketClobAuth.cachedAddress({'authAddress': 1},
            ownerAddress: owner, depositWallet: wallet),
        isNull);
  });
}
