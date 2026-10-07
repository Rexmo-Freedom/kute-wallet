// The Deposit Wallet nonce comes from the relayer's documented
// `GET /v1/account/transactions/params?address=<signer>&type=WALLET`
// (docs: trading/wallets-auth), with the undocumented `/nonce?type=WALLET`
// as the fallback. Bodies are live answers read on 2026-10-07 for one
// signer (both routes gave nonce 47).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';

const _eoa = '0x14791697260E4c9A71f18484C9f997B308e59325';
const _wallet = '0x1111111111111111111111111111111111111111';
const _key = '0123456789012345678901234567890123456789012345678901234567890123';

// Live answers (2026-10-07, signer 0x2faae22a…9d62).
const _liveParams =
    '{"address":"0x64367002e4eda849aaad550517eec3e244ad2d18","nonce":"47"}';
const _liveNonce = '{"nonce":"47"}';

Future<Map<String, dynamic>> _build(
        Future<http.Response> Function(http.Request) handler) =>
    http.runWithClient(
        () => PolymarketOnboardingService().buildDepositWalletBatchRequest(
              eoaAddress: _eoa,
              privateKey: _key,
              walletAddress: _wallet,
              calls: [(target: _wallet, value: BigInt.zero, data: '0x')],
              deadline: 2000000000,
            ),
        () => MockClient(handler));

void main() {
  group('parseRelayerWalletNonce', () {
    test('reads both live answer shapes', () {
      expect(
          PolymarketOnboardingService.parseRelayerWalletNonce(
              jsonDecode(_liveParams)),
          '47');
      expect(
          PolymarketOnboardingService.parseRelayerWalletNonce(
              jsonDecode(_liveNonce)),
          '47');
      expect(PolymarketOnboardingService.parseRelayerWalletNonce({'nonce': 0}),
          '0');
    });

    test('refuses a missing or garbled nonce', () {
      for (final bad in [
        null,
        [],
        {},
        {'nonce': ''},
        {'nonce': null},
        {'nonce': 'abc'},
        {'nonce': '-1'},
        {'nonce': 1.5},
      ]) {
        expect(PolymarketOnboardingService.parseRelayerWalletNonce(bad), isNull,
            reason: '$bad');
      }
    });
  });

  group('deposit wallet nonce read', () {
    test('asks the documented route and signs with its nonce', () async {
      final seen = <Uri>[];
      final body = await _build((request) async {
        seen.add(request.url);
        return http.Response(_liveParams, 200);
      });
      expect(seen, hasLength(1));
      expect(seen.single.host, 'relayer-v2.polymarket.com');
      expect(seen.single.path, '/v1/account/transactions/params');
      expect(seen.single.queryParameters, {'address': _eoa, 'type': 'WALLET'});
      expect(body['nonce'], '47');
      // The batch stays addressed to the wallet the caller named, not the
      // route's own `address`.
      expect((body['depositWalletParams'] as Map)['depositWallet'], _wallet);
    });

    for (final failure in [
      ('a server error', http.Response('down', 503)),
      ('an answer without a nonce', http.Response('{"address":"0x1"}', 200)),
    ]) {
      test('falls back to /nonce on ${failure.$1}', () async {
        final seen = <String>[];
        final body = await _build((request) async {
          seen.add(request.url.path);
          if (request.url.path == '/nonce') {
            expect(request.url.queryParameters,
                {'address': _eoa, 'type': 'WALLET'});
            return http.Response(_liveNonce, 200);
          }
          return failure.$2;
        });
        expect(seen, ['/v1/account/transactions/params', '/nonce']);
        expect(body['nonce'], '47');
      });
    }

    test('throws when neither route answers', () async {
      await expectLater(
          _build((_) async => http.Response('down', 503)), throwsException);
    });
  });
}
