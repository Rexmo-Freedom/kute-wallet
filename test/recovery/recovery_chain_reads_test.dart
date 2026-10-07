// Recovery reads funds and nonces straight off the two account-zero EOAs on
// Polygon (the onboarding service's RPC fallback) and Arbitrum One (its own
// public list). A hanging, erroring, wrong-chain or malformed endpoint must
// fall through to the next, and a read with no answer must throw: an
// unanswered read can never pass for an empty account. Network fakes only.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/arbitrum_read_rpc.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';

const _owner = '0x14791697260E4c9A71f18484C9f997B308e59325';

http.Response _result(Object? result) => http.Response(
    jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': result}), 200);

/// Endpoints keyed by host: how each answers `eth_chainId`, and what it
/// answers for everything else (null hangs).
class _Net {
  _Net(this.chainIds, this.answers);
  final Map<String, String?> chainIds;
  final Map<String, Object? Function(String method)> answers;
  final asked = <(String, String)>[];

  Future<http.Response> handle(http.Request request) {
    final method = (jsonDecode(request.body) as Map)['method'] as String;
    final host = request.url.host;
    asked.add((host, method));
    if (method == 'eth_chainId') {
      final id = chainIds[host];
      return id == null
          ? Completer<http.Response>().future
          : Future.value(_result(id));
    }
    final answer = answers[host];
    if (answer == null) return Completer<http.Response>().future;
    final value = answer(method);
    if (value is http.Response) return Future.value(value);
    return Future.value(_result(value));
  }

  List<String> hostsAskedFor(String method) => [
        for (final (host, m) in asked)
          if (m == method) host
      ];
}

String _arb(int i) => Uri.parse(ArbitrumReadRpc.endpoints[i]).host;
String _pol(int i) =>
    Uri.parse(PolymarketOnboardingService.polygonReadRpcs[i]).host;

Future<T> _with<T>(_Net net, Future<T> Function() body) =>
    http.runWithClient(body, () => MockClient(net.handle));

void main() {
  setUp(() {
    ArbitrumReadRpc.debugReset();
    ArbitrumReadRpc.requestTimeout = const Duration(milliseconds: 50);
    PolymarketOnboardingService.debugResetPolygonRpcs();
    PolymarketOnboardingService.polygonRpcTimeout =
        const Duration(milliseconds: 50);
  });
  tearDown(() {
    ArbitrumReadRpc.debugReset();
    PolymarketOnboardingService.debugResetPolygonRpcs();
  });

  group('ArbitrumReadRpc', () {
    test('lists distinct endpoints and native Arbitrum USDC', () {
      expect(ArbitrumReadRpc.endpoints.toSet(),
          hasLength(ArbitrumReadRpc.endpoints.length));
      expect(ArbitrumReadRpc.usdcAddress.toLowerCase(),
          '0xaf88d065e77c8cc2239327c5edb3a432268e5831');
    });

    Object? live(String method) => switch (method) {
          'eth_getBalance' => '0x2386f26fc10000',
          'eth_getTransactionCount' => '0x5',
          'eth_call' => '0x${'0' * 58}989680',
          _ => null,
        };

    test('reads balance, nonce and USDC from a live endpoint', () async {
      final net = _Net({_arb(0): '0xa4b1'}, {_arb(0): live});
      final rpc = ArbitrumReadRpc();
      expect(await _with(net, () => rpc.nativeBalance(_owner)),
          BigInt.from(10).pow(16));
      expect(await _with(net, () => rpc.nonce(_owner)), BigInt.from(5));
      expect(
          await _with(
              net,
              () => rpc.erc20Balance(
                  token: ArbitrumReadRpc.usdcAddress, owner: _owner)),
          BigInt.from(10000000));
    });

    test('a hanging or wrong-chain endpoint falls through to the next',
        () async {
      final net = _Net(
        {_arb(0): null, _arb(1): '0x89', _arb(2): '0xa4b1'},
        {_arb(1): live, _arb(2): live},
      );
      expect(await _with(net, () => ArbitrumReadRpc().nonce(_owner)),
          BigInt.from(5));
      // The Polygon endpoint is never asked for the read itself.
      expect(net.hostsAskedFor('eth_getTransactionCount'), [_arb(2)]);
    });

    test('an error or malformed answer is never read as zero', () async {
      final net = _Net({
        for (var i = 0; i < ArbitrumReadRpc.endpoints.length; i++)
          _arb(i): '0xa4b1',
      }, {
        _arb(0): (_) => http.Response('bad gateway', 502),
        _arb(1): (_) => '0x',
        _arb(2): (_) => 'nope',
        _arb(3): (_) => http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'error': {'code': -32005, 'message': 'rate limited'}
            }),
            200),
      });
      final rpc = ArbitrumReadRpc();
      await expectLater(_with(net, () => rpc.nativeBalance(_owner)),
          throwsA(isA<ArbitrumReadException>()));
      await expectLater(
          _with(
              net,
              () => rpc.erc20Balance(
                  token: ArbitrumReadRpc.usdcAddress, owner: _owner)),
          throwsA(isA<ArbitrumReadException>()));
    });

    test('offline throws', () async {
      final net = _Net({}, {});
      await expectLater(_with(net, () => ArbitrumReadRpc().nonce(_owner)),
          throwsA(isA<ArbitrumReadException>()));
    });
  });

  group('Polygon balance and nonce reads', () {
    test('read through the fallback list', () async {
      final net = _Net(
        {_pol(0): null, _pol(1): '0x89'},
        {
          _pol(1): (method) => switch (method) {
                'eth_getBalance' => '0xde0b6b3a7640000',
                'eth_getTransactionCount' => '0x0',
                _ => null,
              },
        },
      );
      final service = PolymarketOnboardingService();
      expect(await _with(net, () => service.readNativeBalanceOrThrow(_owner)),
          BigInt.from(10).pow(18));
      expect(await _with(net, () => service.readNonceOrThrow(_owner)),
          BigInt.zero);
    });

    test('no answer or a malformed one throws', () async {
      final service = PolymarketOnboardingService();
      await expectLater(
          _with(_Net({}, {}), () => service.readNonceOrThrow(_owner)),
          throwsA(isA<PolymarketReadException>()));
      final malformed = _Net({
        for (var i = 0;
            i < PolymarketOnboardingService.polygonReadRpcs.length;
            i++)
          _pol(i): '0x89',
      }, {
        for (var i = 0;
            i < PolymarketOnboardingService.polygonReadRpcs.length;
            i++)
          _pol(i): (_) => '0x',
      });
      await expectLater(
          _with(malformed, () => service.readNativeBalanceOrThrow(_owner)),
          throwsA(isA<PolymarketReadException>()));
    });
  });
}
