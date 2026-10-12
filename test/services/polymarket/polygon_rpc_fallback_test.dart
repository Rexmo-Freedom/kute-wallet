// Predictions setup reads (wallet resolve, deploy check, approval scan) go
// to public Polygon RPCs and fail closed. The endpoints are raced: the
// first is asked at once, the next joins after a short stagger without an
// answer, the first answer wins, and the endpoint that answered is asked
// first next time, across app starts. One hanging, erroring or wrong-chain
// endpoint must never decide the read; only when every endpoint fails does
// the read throw. Network fakes only.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';

const _wallet = '0x14791697260E4c9A71f18484C9f997B308e59325';
const _token = '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174'; // gitleaks:allow (public USDC.e contract)
const _spender = '0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E';

const _known = PolymarketOnboardingService.polygonReadRpcs;
const _unknown = 'https://unlisted.rpc.test';

http.Response _result(Object? result) => http.Response(
    jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': result}), 200);

http.Response _rpcError() => http.Response(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'error': {'code': -32005, 'message': 'upstream overloaded'}
    }),
    200);

/// How one endpoint behaves. `slow` answers Polygon after a delay.
enum _Mode { hang, polygon, slow, wrongChain, serverError, rpcError }

/// Polygon RPCs keyed by host, recording every (host, method) asked.
class _Rpcs {
  _Rpcs(List<String> rpcs, List<_Mode> modes)
      : modes = {
          for (var i = 0; i < rpcs.length; i++) Uri.parse(rpcs[i]).host: modes[i],
        };

  final Map<String, _Mode> modes;
  final asked = <(String, String)>[];
  Duration slowBy = const Duration(milliseconds: 30);

  Future<http.Response> handle(http.Request request) async {
    final method = (jsonDecode(request.body) as Map)['method'] as String;
    asked.add((request.url.host, method));
    final mode = modes[request.url.host]!;
    if (mode == _Mode.hang) return Completer<http.Response>().future;
    // Every live endpoint answers its chain id; the modes below are how
    // it then answers the read itself.
    if (method == 'eth_chainId') {
      return _result(mode == _Mode.wrongChain ? '0x1' : '0x89');
    }
    switch (mode) {
      case _Mode.hang:
        return Completer<http.Response>().future;
      case _Mode.serverError:
        return http.Response('bad gateway', 502);
      case _Mode.rpcError:
        return _rpcError();
      case _Mode.wrongChain:
        return _result('0x');
      case _Mode.slow:
        await Future<void>.delayed(slowBy);
        return _result(method == 'eth_getCode' ? '0x6080' : '0x${'0' * 63}1');
      case _Mode.polygon:
        return _result(method == 'eth_getCode' ? '0x6080' : '0x${'0' * 63}1');
    }
  }

  List<String> hostsAskedFor(String method) => [
        for (final (host, m) in asked)
          if (m == method) host
      ];

  Set<String> hostsAsked() => {for (final (host, _) in asked) host};
}

String _host(String rpc) => Uri.parse(rpc).host;

Future<T> _with<T>(_Rpcs rpcs, Future<T> Function() body) =>
    http.runWithClient(body, () => MockClient(rpcs.handle));

/// Lets every started attempt finish (or time out) so a later read sees
/// the cooldowns the first one earned.
Future<void> _settle() =>
    Future<void>.delayed(PolymarketOnboardingService.polygonRpcTimeout * 2);

void main() {
  List<String>? remembered;
  setUp(() {
    PolymarketOnboardingService.debugResetPolygonRpcs();
    PolymarketOnboardingService.polygonRpcTimeout =
        const Duration(milliseconds: 50);
    PolymarketOnboardingService.polygonRpcStagger =
        const Duration(milliseconds: 10);
    remembered = null;
    PolymarketOnboardingService.loadHealthyRpcs = () async => remembered;
    PolymarketOnboardingService.persistHealthyRpcs =
        (rpcs) async => remembered = rpcs;
  });
  tearDown(PolymarketOnboardingService.debugResetPolygonRpcs);

  test('publicnode stays first in the read list and every listed endpoint '
      'is pre-confirmed as Polygon', () {
    expect(_known.first, 'https://polygon-bor-rpc.publicnode.com');
    expect(_known.toSet(), hasLength(_known.length));
    expect(PolymarketOnboardingService.knownPolygonRpcs, _known.toSet());
  });

  test('the first endpoint timing out is joined by the second, which answers',
      () async {
    final rpcs = _Rpcs(
        _known, [_Mode.hang, _Mode.polygon, _Mode.polygon, _Mode.polygon]);
    final deployed = await _with(rpcs,
        () => PolymarketOnboardingService().hasContractCodeOrThrow(_wallet));
    expect(deployed, isTrue);
    expect(rpcs.hostsAskedFor('eth_getCode'), [_host(_known[0]), _host(_known[1])]);
    // No chain check for a listed endpoint.
    expect(rpcs.hostsAskedFor('eth_chainId'), isEmpty);

    // The endpoint that answered is asked first on the next read, so a
    // scan of many approvals never pays the hanging one's timeout again.
    rpcs.asked.clear();
    final allowance = await _with(
        rpcs,
        () => PolymarketOnboardingService().readApprovalOrThrow(
            token: _token, owner: _wallet, spender: _spender));
    expect(allowance, BigInt.one);
    expect(rpcs.asked.first.$1, _host(_known[1]));
    await _settle();
  });

  test('a slow first endpoint loses the race to a fast second one', () async {
    final rpcs = _Rpcs(
        _known, [_Mode.slow, _Mode.polygon, _Mode.polygon, _Mode.polygon])
      ..slowBy = const Duration(milliseconds: 40);
    final clock = Stopwatch()..start();
    final deployed = await _with(rpcs,
        () => PolymarketOnboardingService().hasContractCodeOrThrow(_wallet));
    expect(deployed, isTrue);
    expect(clock.elapsedMilliseconds, lessThan(40));
    expect(rpcs.hostsAskedFor('eth_getCode'), [_host(_known[0]), _host(_known[1])]);
    await _settle();
  });

  test('a fast first endpoint is the only one asked', () async {
    final rpcs = _Rpcs(
        _known, [_Mode.polygon, _Mode.polygon, _Mode.polygon, _Mode.polygon]);
    await _with(rpcs,
        () => PolymarketOnboardingService().hasContractCodeOrThrow(_wallet));
    expect(rpcs.hostsAskedFor('eth_getCode'), [_host(_known[0])]);
  });

  test('the endpoint that answered is remembered across app starts',
      () async {
    final rpcs = _Rpcs(
        _known, [_Mode.hang, _Mode.hang, _Mode.polygon, _Mode.polygon]);
    await _with(rpcs,
        () => PolymarketOnboardingService().hasContractCodeOrThrow(_wallet));
    expect(remembered?.first, _known[2]);
    await _settle();

    // A new process: only the memory survives, and it is read first.
    PolymarketOnboardingService.debugResetPolygonRpcs();
    PolymarketOnboardingService.polygonRpcTimeout =
        const Duration(milliseconds: 50);
    PolymarketOnboardingService.polygonRpcStagger =
        const Duration(milliseconds: 10);
    PolymarketOnboardingService.loadHealthyRpcs = () async => remembered;
    PolymarketOnboardingService.persistHealthyRpcs =
        (rpcs) async => remembered = rpcs;
    rpcs.asked.clear();
    await _with(rpcs,
        () => PolymarketOnboardingService().hasContractCodeOrThrow(_wallet));
    expect(rpcs.hostsAskedFor('eth_getCode'), [_host(_known[2])]);
  });

  test('an unlisted endpoint is chain-checked and skipped on the wrong chain',
      () async {
    final list = [_unknown, _known[1], _known[2], _known[3]];
    PolymarketOnboardingService.debugReadRpcs = list;
    final rpcs = _Rpcs(
        list, [_Mode.wrongChain, _Mode.polygon, _Mode.polygon, _Mode.polygon]);
    final allowance = await _with(
        rpcs,
        () => PolymarketOnboardingService().readApprovalOrThrow(
            token: _token, owner: _wallet, spender: _spender));
    expect(allowance, BigInt.one);
    expect(rpcs.hostsAskedFor('eth_chainId'), [_host(_unknown)]);
    expect(rpcs.hostsAskedFor('eth_call'), isNot(contains(_host(_unknown))));

    // Remembered: the wrong-chain endpoint is not asked again.
    rpcs.asked.clear();
    await _with(rpcs,
        () => PolymarketOnboardingService().hasContractCodeOrThrow(_wallet));
    expect(rpcs.hostsAsked(), isNot(contains(_host(_unknown))));
  });

  test('a 5xx or JSON-RPC error falls through to the next endpoint', () async {
    final rpcs = _Rpcs(
        _known, [_Mode.serverError, _Mode.rpcError, _Mode.polygon, _Mode.hang]);
    final deployed = await _with(rpcs,
        () => PolymarketOnboardingService().hasContractCodeOrThrow(_wallet));
    expect(deployed, isTrue);
    expect(rpcs.hostsAskedFor('eth_getCode'),
        containsAll([_host(_known[0]), _host(_known[1]), _host(_known[2])]));
    await _settle();
  });

  test('every endpoint failing throws: the read fails closed', () async {
    final rpcs = _Rpcs(
        _known, [_Mode.hang, _Mode.serverError, _Mode.rpcError, _Mode.hang]);
    await expectLater(
      _with(
          rpcs,
          () => PolymarketOnboardingService().readApprovalOrThrow(
              token: _token, owner: _wallet, spender: _spender)),
      throwsA(isA<PolymarketReadException>()),
    );
    // Every endpoint was tried before giving up.
    expect(rpcs.hostsAsked(), {for (final rpc in _known) _host(rpc)});
  });

  test('the receipt poll asks every second for 20 s, then every 2 s', () {
    expect(PolymarketOnboardingService.receiptPollInterval(Duration.zero),
        const Duration(seconds: 1));
    expect(
        PolymarketOnboardingService.receiptPollInterval(
            const Duration(seconds: 19)),
        const Duration(seconds: 1));
    expect(
        PolymarketOnboardingService.receiptPollInterval(
            const Duration(seconds: 20)),
        const Duration(seconds: 2));
  });
}
