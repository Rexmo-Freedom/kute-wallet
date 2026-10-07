// Predictions setup reads (wallet resolve, deploy check, approval scan) go
// to public Polygon RPCs and fail closed. One hanging, erroring or
// wrong-chain endpoint must fall through to the next; only when every
// endpoint fails does the read throw. Network fakes only.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';

const _wallet = '0x14791697260E4c9A71f18484C9f997B308e59325';
const _token = '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174'; // gitleaks:allow (public USDC.e contract)
const _spender = '0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E';

final _rpcs = PolymarketOnboardingService.polygonReadRpcs;

http.Response _result(Object? result) => http.Response(
    jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': result}), 200);

http.Response _rpcError() => http.Response(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'error': {'code': -32005, 'message': 'upstream overloaded'}
    }),
    200);

/// How one endpoint behaves.
enum _Mode { hang, polygon, wrongChain, serverError, rpcError }

/// Polygon RPCs keyed by host, recording every (host, method) asked.
class _Rpcs {
  _Rpcs(List<_Mode> modes)
      : modes = {
          for (var i = 0; i < _rpcs.length; i++)
            Uri.parse(_rpcs[i]).host: modes[i],
        };

  final Map<String, _Mode> modes;
  final asked = <(String, String)>[];

  Future<http.Response> handle(http.Request request) {
    final method = (jsonDecode(request.body) as Map)['method'] as String;
    asked.add((request.url.host, method));
    final mode = modes[request.url.host]!;
    if (mode == _Mode.hang) return Completer<http.Response>().future;
    // Every live endpoint answers its chain id; the modes below are how
    // it then answers the read itself.
    if (method == 'eth_chainId') {
      return Future.value(_result(mode == _Mode.wrongChain ? '0x1' : '0x89'));
    }
    switch (mode) {
      case _Mode.hang:
        return Completer<http.Response>().future;
      case _Mode.serverError:
        return Future.value(http.Response('bad gateway', 502));
      case _Mode.rpcError:
        return Future.value(_rpcError());
      case _Mode.wrongChain:
        return Future.value(_result('0x'));
      case _Mode.polygon:
        return Future.value(
            _result(method == 'eth_getCode' ? '0x6080' : '0x${'0' * 63}1'));
    }
  }

  List<String> hostsAskedFor(String method) => [
        for (final (host, m) in asked)
          if (m == method) host
      ];
}

String _host(int i) => Uri.parse(_rpcs[i]).host;

Future<T> _with<T>(_Rpcs rpcs, Future<T> Function() body) =>
    http.runWithClient(body, () => MockClient(rpcs.handle));

void main() {
  setUp(() {
    PolymarketOnboardingService.debugResetPolygonRpcs();
    PolymarketOnboardingService.polygonRpcTimeout =
        const Duration(milliseconds: 50);
  });
  tearDown(PolymarketOnboardingService.debugResetPolygonRpcs);

  test('publicnode stays first in the read list', () {
    expect(_rpcs.first, 'https://polygon-bor-rpc.publicnode.com');
    expect(_rpcs.toSet(), hasLength(_rpcs.length));
  });

  test('the first endpoint timing out falls through to the second', () async {
    final rpcs =
        _Rpcs([_Mode.hang, _Mode.polygon, _Mode.polygon, _Mode.polygon]);
    final deployed = await _with(rpcs,
        () => PolymarketOnboardingService().hasContractCodeOrThrow(_wallet));
    expect(deployed, isTrue);
    expect(rpcs.hostsAskedFor('eth_getCode'), [_host(1)]);

    // The hanging endpoint is tried last on the next read, so a scan of
    // many approvals does not pay its timeout on every read.
    rpcs.asked.clear();
    final allowance = await _with(
        rpcs,
        () => PolymarketOnboardingService().readApprovalOrThrow(
            token: _token, owner: _wallet, spender: _spender));
    expect(allowance, BigInt.one);
    expect(rpcs.asked.first.$1, _host(1));
  });

  test('an endpoint on the wrong chain is never asked for the read', () async {
    final rpcs =
        _Rpcs([_Mode.wrongChain, _Mode.polygon, _Mode.polygon, _Mode.polygon]);
    final allowance = await _with(
        rpcs,
        () => PolymarketOnboardingService().readApprovalOrThrow(
            token: _token, owner: _wallet, spender: _spender));
    expect(allowance, BigInt.one);
    expect(rpcs.hostsAskedFor('eth_call'), [_host(1)]);

    // Remembered: the wrong-chain endpoint is not asked again.
    rpcs.asked.clear();
    await _with(rpcs,
        () => PolymarketOnboardingService().hasContractCodeOrThrow(_wallet));
    expect(rpcs.asked.map((a) => a.$1), isNot(contains(_host(0))));
  });

  test('a 5xx or JSON-RPC error falls through to the next endpoint', () async {
    final rpcs =
        _Rpcs([_Mode.serverError, _Mode.rpcError, _Mode.polygon, _Mode.hang]);
    final deployed = await _with(rpcs,
        () => PolymarketOnboardingService().hasContractCodeOrThrow(_wallet));
    expect(deployed, isTrue);
    expect(rpcs.hostsAskedFor('eth_getCode'), [_host(0), _host(1), _host(2)]);
  });

  test('every endpoint failing throws: the read fails closed', () async {
    final rpcs = _Rpcs(
        [_Mode.hang, _Mode.serverError, _Mode.rpcError, _Mode.wrongChain]);
    await expectLater(
      _with(
          rpcs,
          () => PolymarketOnboardingService().readApprovalOrThrow(
              token: _token, owner: _wallet, spender: _spender)),
      throwsA(isA<PolymarketReadException>()),
    );
    // Every endpoint was tried before giving up.
    expect(rpcs.asked.map((a) => a.$1).toSet(),
        {for (var i = 0; i < _rpcs.length; i++) _host(i)});
  });
}
