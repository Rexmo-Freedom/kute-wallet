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
import 'package:kute/services/tracking_service.dart';

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
    // Five independent providers (checked live on 2026-11-09), so one
    // provider's bad evening never decides a read.
    expect(_known, hasLength(5));
    expect(_known.toSet(), hasLength(_known.length));
    expect({for (final rpc in _known) Uri.parse(rpc).host},
        hasLength(_known.length));
    expect(PolymarketOnboardingService.knownPolygonRpcs, _known.toSet());
  });

  test('the stagger is short, so a slow endpoint does not hold the others '
      'back, and the whole read is bounded', () {
    PolymarketOnboardingService.debugResetPolygonRpcs();
    expect(PolymarketOnboardingService.polygonRpcStagger,
        const Duration(milliseconds: 400));
    expect(PolymarketOnboardingService.polygonRpcTimeout,
        const Duration(seconds: 5));
    expect(PolymarketOnboardingService.polygonRpcTotalTimeout,
        const Duration(seconds: 8));
    // Every endpoint started (stagger × 4) and the last one timing out
    // still ends under the total bound.
    expect(
        PolymarketOnboardingService.polygonRpcStagger * (_known.length - 1) +
            PolymarketOnboardingService.polygonRpcTimeout,
        lessThanOrEqualTo(PolymarketOnboardingService.polygonRpcTotalTimeout));
  });

  test('every endpoint hanging: the read fails closed at the total bound, '
      'not after every timeout in turn', () async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    // Per-attempt timeouts far past the total bound: only the bound can
    // end this read.
    PolymarketOnboardingService.polygonRpcTimeout =
        const Duration(milliseconds: 600);
    PolymarketOnboardingService.polygonRpcTotalTimeout =
        const Duration(milliseconds: 120);
    final rpcs = _Rpcs(_known,
        [_Mode.hang, _Mode.hang, _Mode.hang, _Mode.hang, _Mode.hang]);
    final clock = Stopwatch()..start();
    await expectLater(
      _with(rpcs,
          () => PolymarketOnboardingService().hasContractCodeOrThrow(_wallet)),
      throwsA(isA<PolymarketReadException>()),
    );
    expect(clock.elapsedMilliseconds, lessThan(500));
    final failed = events.where((e) => e.$1 == 'polygon_rpc_read_failed');
    expect(failed.single.$2, {'method': 'eth_getCode', 'endpoints': 5});
    // The attempts time out later and the event is not sent again.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(events.where((e) => e.$1 == 'polygon_rpc_read_failed'), hasLength(1));
  });

  test('an answer after the total bound is not the read, but it is '
      'remembered as the healthy endpoint for the next one', () async {
    PolymarketOnboardingService.polygonRpcTimeout =
        const Duration(milliseconds: 800);
    PolymarketOnboardingService.polygonRpcTotalTimeout =
        const Duration(milliseconds: 100);
    final rpcs = _Rpcs(
        _known, [_Mode.slow, _Mode.hang, _Mode.hang, _Mode.hang, _Mode.hang])
      ..slowBy = const Duration(milliseconds: 300);
    await expectLater(
      _with(rpcs,
          () => PolymarketOnboardingService().hasContractCodeOrThrow(_wallet)),
      throwsA(isA<PolymarketReadException>()),
    );
    expect(remembered, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    expect(remembered?.first, _known[0]);
  });

  test('the first good answer wins while slower endpoints are still out',
      () async {
    final rpcs = _Rpcs(_known,
        [_Mode.slow, _Mode.slow, _Mode.polygon, _Mode.hang, _Mode.hang])
      ..slowBy = const Duration(seconds: 1);
    final clock = Stopwatch()..start();
    final deployed = await _with(rpcs,
        () => PolymarketOnboardingService().hasContractCodeOrThrow(_wallet));
    expect(deployed, isTrue);
    // Two staggers to reach the third endpoint, then its answer.
    expect(clock.elapsedMilliseconds, lessThan(800));
    expect(rpcs.hostsAskedFor('eth_getCode'),
        [_host(_known[0]), _host(_known[1]), _host(_known[2])]);
    await _settle();
  });

  test('the first endpoint timing out is joined by the second, which answers',
      () async {
    final rpcs = _Rpcs(
        _known, [_Mode.hang, _Mode.polygon, _Mode.polygon, _Mode.polygon, _Mode.polygon]);
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
        _known, [_Mode.slow, _Mode.polygon, _Mode.polygon, _Mode.polygon, _Mode.polygon])
      // Far slower than any CI scheduling hiccup, so "answered without
      // waiting for it" can't flip on a busy runner (74 ms seen for a 40 ms
      // bound).
      ..slowBy = const Duration(seconds: 1);
    final clock = Stopwatch()..start();
    final deployed = await _with(rpcs,
        () => PolymarketOnboardingService().hasContractCodeOrThrow(_wallet));
    expect(deployed, isTrue);
    expect(clock.elapsedMilliseconds, lessThan(800));
    expect(rpcs.hostsAskedFor('eth_getCode'), [_host(_known[0]), _host(_known[1])]);
    await _settle();
  });

  test('a fast first endpoint is the only one asked', () async {
    final rpcs = _Rpcs(
        _known, [_Mode.polygon, _Mode.polygon, _Mode.polygon, _Mode.polygon, _Mode.polygon]);
    await _with(rpcs,
        () => PolymarketOnboardingService().hasContractCodeOrThrow(_wallet));
    expect(rpcs.hostsAskedFor('eth_getCode'), [_host(_known[0])]);
  });

  test('the endpoint that answered is remembered across app starts',
      () async {
    final rpcs = _Rpcs(
        _known, [_Mode.hang, _Mode.hang, _Mode.polygon, _Mode.polygon, _Mode.polygon]);
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
        _known, [_Mode.serverError, _Mode.rpcError, _Mode.polygon, _Mode.hang, _Mode.polygon]);
    final deployed = await _with(rpcs,
        () => PolymarketOnboardingService().hasContractCodeOrThrow(_wallet));
    expect(deployed, isTrue);
    expect(rpcs.hostsAskedFor('eth_getCode'),
        containsAll([_host(_known[0]), _host(_known[1]), _host(_known[2])]));
    await _settle();
  });

  test('every endpoint failing throws: the read fails closed', () async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    final rpcs = _Rpcs(
        _known, [_Mode.hang, _Mode.serverError, _Mode.rpcError, _Mode.hang, _Mode.hang]);
    await expectLater(
      _with(
          rpcs,
          () => PolymarketOnboardingService().readApprovalOrThrow(
              token: _token, owner: _wallet, spender: _spender)),
      throwsA(isA<PolymarketReadException>()),
    );
    // Every endpoint was tried before giving up.
    expect(rpcs.hostsAsked(), {for (final rpc in _known) _host(rpc)});
    // The fleet hears about the read itself, with no address in it.
    final failed = events.where((e) => e.$1 == 'polygon_rpc_read_failed');
    expect(failed.single.$2, {'method': 'eth_call', 'endpoints': 5});
  });

  test(
      'a balance that decides a withdrawal throws when every endpoint '
      'fails; the lenient read still answers 0', () async {
    final rpcs = _Rpcs(_known,
        [_Mode.serverError, _Mode.rpcError, _Mode.serverError, _Mode.rpcError, _Mode.serverError]);
    await expectLater(
      _with(
          rpcs,
          () => PolymarketOnboardingService()
              .readErc20BalanceOrThrow(token: _token, owner: _wallet)),
      throwsA(isA<PolymarketReadException>()),
    );
    expect(
        await _with(
            rpcs,
            () => PolymarketOnboardingService()
                .readErc20Balance(token: _token, owner: _wallet)),
        BigInt.zero);
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
