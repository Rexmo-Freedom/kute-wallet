// The deposit wallet resolve asks the relayer registry, the legacy wallet's
// code and the factory's prediction at the same time, so it costs one round
// trip instead of three in a row, and a slow relayer never holds the
// balance back. A wallet this app already found on the current variant
// skips the legacy checks altogether. Network fakes only.
import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';

const _eoa = '0x14791697260E4c9A71f18484C9f997B308e59325';
const _beaconWord = '2222222222222222222222222222222222222222';

class _Net {
  _Net({this.relayerHangs = false, this.relayerDeployed = false,
      this.legacyCode = '0x', this.rpcDelay = Duration.zero});

  final bool relayerHangs;
  final bool relayerDeployed;
  final String legacyCode;
  final Duration rpcDelay;
  final calls = <String>[];

  Future<http.Response> handle(http.Request request) async {
    if (request.url.host == 'relayer-v2.polymarket.com') {
      calls.add('relayer');
      if (relayerHangs) return Completer<http.Response>().future;
      return http.Response(jsonEncode({'deployed': relayerDeployed}), 200);
    }
    final rpc = jsonDecode(request.body) as Map<String, dynamic>;
    final method = rpc['method'] as String;
    calls.add(method);
    await Future<void>.delayed(rpcDelay);
    final result = switch (method) {
      'eth_chainId' => '0x89',
      'eth_getCode' => legacyCode,
      'eth_call' => '0x${'0' * 24}$_beaconWord',
      _ => '0x',
    };
    return http.Response(
        jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': result}), 200);
  }
}

Future<T> _with<T>(_Net net, Future<T> Function() body) =>
    http.runWithClient(body, () => MockClient(net.handle));

void main() {
  setUp(() {
    PolymarketOnboardingService.debugResetPolygonRpcs();
    PolymarketOnboardingService.polygonRpcTimeout =
        const Duration(milliseconds: 200);
    PolymarketOnboardingService.polygonRpcStagger =
        const Duration(milliseconds: 50);
    PolymarketOnboardingService.relayerResolveTimeout =
        const Duration(milliseconds: 60);
    PolymarketOnboardingService.loadHealthyRpcs = () async => null;
    PolymarketOnboardingService.persistHealthyRpcs = (_) async {};
  });
  tearDown(() {
    PolymarketOnboardingService.debugResetPolygonRpcs();
    PolymarketOnboardingService.relayerResolveTimeout =
        const Duration(seconds: 4);
  });

  // Timing on the fake clock: a wall-clock bound (one 20 ms round trip
  // under 60 ms) read 62 ms on a loaded machine running the full suite.
  test('the three reads start together and a new wallet gets the factory '
      'address within one round trip', () {
    fakeAsync((async) {
      const roundTrip = Duration(milliseconds: 20);
      final net = _Net(rpcDelay: roundTrip);
      ({String address, bool legacy})? resolved;
      _with(net, () => PolymarketOnboardingService().resolveDepositWallet(_eoa))
          .then((r) => resolved = r);
      async.flushMicrotasks();
      // Three reads, all sent before any answered.
      expect(
          net.calls.take(3).toSet(), {'relayer', 'eth_getCode', 'eth_call'});
      expect(resolved, isNull);
      // One round trip answers both chain reads (the relayer answered at
      // once); three in a row would need 60 ms.
      async.elapse(roundTrip);
      expect(resolved, isNotNull);
      expect(resolved!.legacy, isFalse);
      expect(resolved!.address.toLowerCase(), '0x$_beaconWord');
      // No second endpoint joined: the first answered inside its stagger.
      expect(net.calls, hasLength(3));
    });
  });

  test('a hanging relayer never holds the resolve past its own timeout', () {
    fakeAsync((async) {
      final net = _Net(relayerHangs: true);
      String? address;
      _with(net,
              () => PolymarketOnboardingService()
                  .resolveDepositWalletAddress(_eoa))
          .then((a) => address = a);
      async.elapse(PolymarketOnboardingService.relayerResolveTimeout -
          const Duration(milliseconds: 1));
      expect(address, isNull);
      async.elapse(const Duration(milliseconds: 1));
      expect(address?.toLowerCase(), '0x$_beaconWord');
    });
  });

  test('a legacy wallet registered on the relayer is kept', () async {
    final net = _Net(relayerDeployed: true);
    final resolved = await _with(
        net, () => PolymarketOnboardingService().resolveDepositWallet(_eoa));
    expect(resolved.legacy, isTrue);
    expect(resolved.address,
        PolymarketOnboardingService().deriveDepositWalletAddress(_eoa));
  });

  test('a deployed legacy wallet is kept even when the relayer is silent',
      () async {
    final net = _Net(relayerHangs: true, legacyCode: '0x6080');
    final resolved = await _with(
        net, () => PolymarketOnboardingService().resolveDepositWallet(_eoa));
    expect(resolved.legacy, isTrue);
  });

  test('a wallet already found on the current variant skips the legacy '
      'checks', () async {
    final net = _Net();
    final resolved = await _with(
        net,
        () => PolymarketOnboardingService()
            .resolveDepositWallet(_eoa, skipLegacyChecks: true));
    expect(resolved.legacy, isFalse);
    expect(net.calls, ['eth_call']);
  });
}
