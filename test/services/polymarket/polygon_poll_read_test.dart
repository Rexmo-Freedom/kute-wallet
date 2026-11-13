// The funded bet's chain watch reads light: one endpoint at a time, never
// raced, its two balanceOf calls one after the other, 3 s each; on an
// error, a 429 or a timeout the next configured endpoint, and a failure is
// an exception (counted, backed off), never a zero balance. Network fakes
// only.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';

const _wallet = '0x14791697260E4c9A71f18484C9f997B308e59325';
const _pusd = '0x1111111111111111111111111111111111111111';
const _usdce = '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174'; // gitleaks:allow (public USDC.e contract)
const _rpcs = PolymarketOnboardingService.polygonReadRpcs;

String _word(int v) => '0x${v.toRadixString(16).padLeft(64, '0')}';

enum _Mode { ok, tooMany, hang, rpcError }

void main() {
  setUp(() {
    PolymarketOnboardingService.debugResetPolygonRpcs();
    PolymarketOnboardingService.loadHealthyRpcs = () async => null;
    PolymarketOnboardingService.persistHealthyRpcs = (_) async {};
  });
  tearDown(PolymarketOnboardingService.debugResetPolygonRpcs);

  Future<T> run<T>(Map<String, _Mode> modes, List<(String, String)> asked,
      Future<T> Function() body,
      {void Function(int inFlight)? onFlight}) {
    var inFlight = 0;
    return http.runWithClient(body, () => MockClient((request) async {
          final json = jsonDecode(request.body) as Map;
          final to = ((json['params'] as List).first as Map)['to'] as String;
          asked.add((request.url.toString(), to));
          inFlight++;
          onFlight?.call(inFlight);
          try {
            switch (modes[request.url.toString()] ?? _Mode.ok) {
              case _Mode.hang:
                await Future<void>.delayed(const Duration(seconds: 1));
                return http.Response('{}', 200);
              case _Mode.tooMany:
                return http.Response('rate limited', 429);
              case _Mode.rpcError:
                return http.Response(
                    jsonEncode({
                      'jsonrpc': '2.0',
                      'id': 1,
                      'error': {'code': -32005, 'message': 'overloaded'}
                    }),
                    200);
              case _Mode.ok:
                return http.Response(
                    jsonEncode({
                      'jsonrpc': '2.0',
                      'id': 1,
                      'result': _word(to == _pusd ? 2940000 : 5060000)
                    }),
                    200);
            }
          } finally {
            inFlight--;
          }
        }));
  }

  test('one endpoint, the two balances one after the other, its index',
      () async {
    final asked = <(String, String)>[];
    var most = 0;
    final read = await run({}, asked, () {
      return PolymarketOnboardingService()
          .readBalancesForPoll(tokens: const [_pusd, _usdce], owner: _wallet);
    }, onFlight: (n) => most = n > most ? n : most);
    expect(read.balances, [BigInt.from(2940000), BigInt.from(5060000)]);
    expect(read.endpoint, 0);
    expect(read.errors, 0);
    expect(asked, [(_rpcs[0], _pusd), (_rpcs[0], _usdce)]);
    expect(most, 1);
  });

  test('a 429 moves to the next configured endpoint; the next read starts '
      'there', () async {
    final asked = <(String, String)>[];
    final modes = {_rpcs[0]: _Mode.tooMany};
    final read = await run(modes, asked, () {
      return PolymarketOnboardingService()
          .readBalancesForPoll(tokens: const [_pusd, _usdce], owner: _wallet);
    });
    expect(read.endpoint, 1);
    expect(read.errors, 1);
    expect(asked.map((a) => a.$1), [_rpcs[0], _rpcs[1], _rpcs[1]]);
    asked.clear();
    final again = await run({}, asked, () {
      return PolymarketOnboardingService()
          .readBalancesForPoll(tokens: const [_pusd, _usdce], owner: _wallet);
    });
    // The endpoint that answered goes first now; the one that refused waits
    // out its cooldown at the back.
    expect(again.endpoint, 1);
  });

  test('a per-call timeout is a failure of that endpoint, then the next',
      () async {
    final asked = <(String, String)>[];
    final read = await run({_rpcs[0]: _Mode.hang}, asked, () {
      return PolymarketOnboardingService().readBalancesForPoll(
          tokens: const [_pusd, _usdce],
          owner: _wallet,
          perCallTimeout: const Duration(milliseconds: 50));
    });
    expect(read.endpoint, 1);
    expect(read.errors, 1);
  });

  test('no endpoint answers: an exception with the attempts, never zeros',
      () async {
    final asked = <(String, String)>[];
    final modes = {_rpcs[0]: _Mode.rpcError, _rpcs[1]: _Mode.tooMany};
    await expectLater(
        run(modes, asked, () {
          return PolymarketOnboardingService().readBalancesForPoll(
              tokens: const [_pusd, _usdce], owner: _wallet);
        }),
        throwsA(isA<PolygonPollReadFailed>()
            .having((e) => e.attempts, 'attempts', 2)));
    // Two endpoints at most per read, one request each here.
    expect(asked.map((a) => a.$1), [_rpcs[0], _rpcs[1]]);
  });
}
