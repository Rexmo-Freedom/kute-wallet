// Protocol V2 positions: balances from the PositionManager, results from
// PositionManager.getPayout, claims through the Router.
//
// The chain answers below are the live ones read on 2026-10-07 for the
// resolved V2 canary "polyv2-central-park-rain-2026-10-01" (QA wallet
// 0x8d3f…b84d held 25 YES): balanceOf → 25_000_000, getPayout(YES, 1e6) →
// 0, getPayout(NO, 1e6) → 1_000_000 (Data API /v2/resolutions payouts
// [0, 1000000]); the unresolved canary reverts with 0x28acd6be.
// Network fakes only: nothing is signed for or sent.

import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/services/polymarket/market_protocol.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';

const _owner = '0x8d3f52833636d0918b74426b7f5be855bd51b84d';
const _cond =
    '0x0108d7b09f9cdee65b85ca3e2a352ca1a2000000000000000000000000000000';
const _yes =
    '467936262325854091996365274202848050629178280457241950923657759821494484992';
const _no =
    '467936262325854091996365274202848050629178280457241950923657759821494484993';
const _ctfToken =
    '32338220190071351435772801779725302244575775216413325951443816017994629993401';

String _word(BigInt v) => v.toRadixString(16).padLeft(64, '0');

class _Chain {
  _Chain({this.resolved = true, this.balances = const {}});
  final bool resolved;

  /// Balance by token id; ids not listed hold zero.
  final Map<String, BigInt> balances;
  final calls = <(String to, String data)>[];
  var backendReads = 0;

  Future<http.Response> handle(http.Request request) async {
    if (request.url.host == 'backend.test') {
      backendReads++;
      return http.Response('{}', 404);
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    Map<String, dynamic> ok(String r) =>
        {'jsonrpc': '2.0', 'id': body['id'], 'result': r};
    if (body['method'] == 'eth_chainId') {
      return http.Response(jsonEncode(ok('0x89')), 200);
    }
    final p = (body['params'] as List).first as Map<String, dynamic>;
    final to = (p['to'] as String).toLowerCase();
    final data = (p['data'] as String).substring(2);
    calls.add((to, data));
    final selector = data.substring(0, 8);
    if (selector == '4c619e4c') {
      if (!resolved) {
        return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'error': {
                'code': 3,
                'message': 'execution reverted',
                'data': '0x28acd6be'
              }
            }),
            200);
      }
      final id = BigInt.parse(data.substring(8, 72), radix: 16);
      final noSide = id.isOdd;
      return http.Response(
          jsonEncode(
              ok('0x${_word(noSide ? BigInt.from(1000000) : BigInt.zero)}')),
          200);
    }
    if (selector == '4e1273f4') {
      final n = int.parse(data.substring(8 + 128, 8 + 192), radix: 16);
      final idsStart = 8 + 192 + 64 * n + 64;
      final ids = [
        for (var i = 0; i < n; i++)
          BigInt.parse(
                  data.substring(idsStart + 64 * i, idsStart + 64 * (i + 1)),
                  radix: 16)
              .toString()
      ];
      return http.Response(
          jsonEncode(ok('0x${_word(BigInt.from(32))}${_word(BigInt.from(n))}'
              '${ids.map((id) => _word(balances[id] ?? BigInt.zero)).join()}')),
          200);
    }
    return http.Response('unexpected $selector', 500);
  }
}

void main() {
  setUp(() => dotenv.loadFromString(envString: 'BACKEND=https://backend.test'));

  Future<T> run<T>(
          _Chain chain, Future<T> Function(PolymarketOnboardingService) f) =>
      http.runWithClient(() => f(PolymarketOnboardingService()),
          () => MockClient(chain.handle));

  test('V2 balances come from the PositionManager, CTF ones from CTF',
      () async {
    final chain = _Chain(balances: {
      _yes: BigInt.from(25000000),
      _ctfToken: BigInt.from(7),
    });
    final held = await run(
        chain,
        (s) => s.readCtfBalancesBatch(
            positionIds: [_yes, _ctfToken], owner: _owner));
    expect(held, {_yes: BigInt.from(25000000), _ctfToken: BigInt.from(7)});
    final targets = chain.calls.map((c) => c.$1).toSet();
    expect(targets, {
      PolymarketConstants.comboPositionManagerAddress.toLowerCase(),
      PolymarketConstants.ctfAddress.toLowerCase(),
    });
  });

  test('a resolved V2 condition pays from getPayout, without the CTF route',
      () async {
    final chain = _Chain();
    final c31 = PolyMarketProtocol.v2ConditionId(_cond)!;
    expect(await run(chain, (s) => s.readV2Payouts(c31)), [0.0, 1.0]);
    expect(await run(chain, (s) => s.settledPayout(_cond, 0)), 0.0);
    expect(await run(chain, (s) => s.isConditionFinalized(_cond)), isTrue);
    expect(chain.backendReads, 0);
    expect(
        chain.calls.every((c) =>
            c.$1 ==
            PolymarketConstants.comboPositionManagerAddress.toLowerCase()),
        isTrue);
  });

  test('an unresolved V2 condition is unknown, never a loss', () async {
    final chain = _Chain(resolved: false);
    final c31 = PolyMarketProtocol.v2ConditionId(
        '0x01d83c915cee8a5ec4b4b715d1ac911aa7000000000000000000000000000000')!;
    expect(await run(chain, (s) => s.readV2Payouts(c31)), isNull);
    expect(
        await run(
            chain,
            (s) => s.isConditionFinalized(
                '0x01d83c915cee8a5ec4b4b715d1ac911aa7000000000000000000000000000000')),
        isNull);
  });

  test('a V2 claim redeems each held side through the Router', () async {
    final one = await run(_Chain(balances: {_yes: BigInt.from(25000000)}),
        (s) => s.v2RedeemCalls(positionId: _yes, owner: _owner));
    expect(one, hasLength(1));
    expect(one.single.target, PolymarketConstants.comboRouterAddress);
    expect(
        one.single.data,
        '0xd217a3cc'
        '${_cond.substring(2, 64)}00'
        '${_word(BigInt.zero)}'
        '${_word(BigInt.from(25000000))}');

    final both = await run(
        _Chain(balances: {_yes: BigInt.from(3), _no: BigInt.from(4)}),
        (s) => s.v2RedeemCalls(positionId: _no, owner: _owner));
    expect(both.map((c) => c.data.substring(74, 138)),
        [_word(BigInt.zero), _word(BigInt.one)]);

    final none = await run(
        _Chain(), (s) => s.v2RedeemCalls(positionId: _yes, owner: _owner));
    expect(none, isEmpty);
  });
}
