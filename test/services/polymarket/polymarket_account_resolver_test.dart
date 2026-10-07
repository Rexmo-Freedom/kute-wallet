import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';

const _eoa = '0x14791697260E4c9A71f18484C9f997B308e59325';
const _uups = '0x1111111111111111111111111111111111111111';
const _beacon = '0x2222222222222222222222222222222222222222';
const _safe = '0x3333333333333333333333333333333333333333';

Position position(String asset) => Position(
      proxyWallet: _safe,
      asset: asset,
      conditionId: '0xc0',
      size: 1,
      avgPrice: 0.5,
      initialValue: 0.5,
      currentValue: 0.6,
      cashPnl: 0,
      percentPnl: 0,
      totalBought: 1,
      realizedPnl: 0,
      percentRealizedPnl: 0,
      curPrice: 0.6,
      title: 'Market',
      slug: 'market',
      eventSlug: 'event',
      outcome: 'Yes',
      outcomeIndex: 0,
      oppositeOutcome: 'No',
      oppositeAsset: '2',
    );

class FakeReads implements PolymarketAccountReads {
  final relayer = <String, bool?>{};

  /// true / false, or an Exception to throw.
  final code = <String, Object>{};
  Object beacon = _beacon;
  Object safe = _safe;
  final positionsBy = <String, Object>{};
  final balances = <String, Object>{};
  final calls = <String>[];

  T _answer<T>(Object value) {
    if (value is Exception) throw value;
    return value as T;
  }

  @override
  String deriveDepositWalletAddress(String eoa) {
    calls.add('derive');
    return _uups;
  }

  @override
  Future<String> predictDepositWallet(String eoa) async {
    calls.add('predict');
    return _answer<String>(beacon);
  }

  @override
  Future<bool?> relayerWalletDeployed(String address) async {
    calls.add('relayer:$address');
    return relayer[address];
  }

  @override
  Future<bool> hasCode(String address) async {
    calls.add('code:$address');
    return _answer<bool>(code[address] ?? false);
  }

  @override
  Future<String> deriveSafeAddress(String eoa) async {
    calls.add('safe');
    return _answer<String>(safe);
  }

  @override
  Future<List<Position>> positions(String address) async {
    calls.add('positions:$address');
    return _answer<List<Position>>(positionsBy[address] ?? <Position>[]);
  }

  @override
  Future<BigInt> erc20Balance(
      {required String token, required String owner}) async {
    calls.add('balance:$token');
    return _answer<BigInt>(balances[token] ?? BigInt.zero);
  }
}

void main() {
  group('resolver', () {
    test('a relayer-registered UUPS deposit wallet wins', () async {
      final reads = FakeReads()..relayer[_uups] = true;
      final account = await PolymarketAccountResolver(reads).resolve(_eoa);
      expect(account.kind, PolymarketAccountKind.depositWallet);
      expect(account.address, _uups);
      expect(account.variant, DepositWalletVariant.uups);
      expect(account.signatureType, 3);
      expect(account.canAct, isTrue);
    });

    test('a deployed UUPS wallet is kept even if the relayer is unknown',
        () async {
      final reads = FakeReads()..code[_uups] = true;
      final account = await PolymarketAccountResolver(reads).resolve(_eoa);
      expect(account.address, _uups);
    });

    test('the beacon wallet is used when deployed', () async {
      final reads = FakeReads()..code[_beacon] = true;
      final account = await PolymarketAccountResolver(reads).resolve(_eoa);
      expect(account.kind, PolymarketAccountKind.depositWallet);
      expect(account.address, _beacon);
      expect(account.variant, DepositWalletVariant.beacon);
    });

    test('a legacy Safe with code is read-only', () async {
      final reads = FakeReads()..code[_safe] = true;
      final account = await PolymarketAccountResolver(reads).resolve(_eoa);
      expect(account.kind, PolymarketAccountKind.legacySafe);
      expect(account.address, _safe);
      expect(account.signatureType, 2);
      expect(account.canAct, isFalse);
    });

    test('a legacy Safe with positions but no code is read-only', () async {
      final reads = FakeReads()..positionsBy[_safe] = [position('1')];
      final account = await PolymarketAccountResolver(reads).resolve(_eoa);
      expect(account.kind, PolymarketAccountKind.legacySafe);
    });

    test('none only when every read succeeded', () async {
      final reads = FakeReads();
      final account = await PolymarketAccountResolver(reads).resolve(_eoa);
      expect(account.kind, PolymarketAccountKind.none);
      expect(account.predictedDepositWallet, _beacon);
      expect(account.address, isNull);
      expect(account.canAct, isFalse);
    });

    test('an RPC failure on the UUPS code check is uncertain, never none',
        () async {
      final reads = FakeReads()..code[_uups] = Exception('rpc down');
      final account = await PolymarketAccountResolver(reads).resolve(_eoa);
      expect(account.kind, PolymarketAccountKind.uncertain);
    });

    test('a failed factory prediction is uncertain', () async {
      final reads = FakeReads()..beacon = Exception('rpc down');
      final account = await PolymarketAccountResolver(reads).resolve(_eoa);
      expect(account.kind, PolymarketAccountKind.uncertain);
    });

    test('a failed Safe positions read is uncertain', () async {
      final reads = FakeReads()..positionsBy[_safe] = Exception('data api');
      final account = await PolymarketAccountResolver(reads).resolve(_eoa);
      expect(account.kind, PolymarketAccountKind.uncertain);
    });

    test('a definitive deposit wallet survives a later failing read', () async {
      final reads = FakeReads()
        ..relayer[_uups] = true
        ..beacon = Exception('never reached');
      final account = await PolymarketAccountResolver(reads).resolve(_eoa);
      expect(account.kind, PolymarketAccountKind.depositWallet);
      expect(reads.calls, isNot(contains('predict')));
    });
  });

  group('strict reads', () {
    String rpc(Object result) =>
        jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': result});

    test('readErc20BalanceOrThrow returns the value or throws', () async {
      final ok = await http.runWithClient(
        () => PolymarketOnboardingService()
            .readErc20BalanceOrThrow(token: _uups, owner: _eoa),
        () =>
            MockClient((_) async => http.Response(rpc('0x${'0' * 62}2a'), 200)),
      );
      expect(ok, BigInt.from(42));

      for (final response in [
        http.Response(
            jsonEncode({
              'error': {'code': -32000}
            }),
            200),
        http.Response('bad gateway', 502),
        http.Response(rpc('0x'), 200),
        http.Response(jsonEncode({'jsonrpc': '2.0'}), 200),
      ]) {
        await expectLater(
          http.runWithClient(
            () => PolymarketOnboardingService()
                .readErc20BalanceOrThrow(token: _uups, owner: _eoa),
            () => MockClient((_) async => response),
          ),
          throwsA(isA<PolymarketReadException>()),
        );
        // The hot fail-soft read keeps returning zero.
        final soft = await http.runWithClient(
          () => PolymarketOnboardingService()
              .readErc20Balance(token: _uups, owner: _eoa),
          () => MockClient((_) async => response),
        );
        expect(soft, BigInt.zero);
      }
    });

    test('approval reads distinguish missing from unknown and invalid bools',
        () async {
      Future<BigInt> read(http.Response response, {bool operator = false}) =>
          http.runWithClient(
              () => PolymarketOnboardingService().readApprovalOrThrow(
                  token: _uups,
                  owner: _eoa,
                  spender: _beacon,
                  operatorApproval: operator),
              () => MockClient((_) async => response));
      expect(await read(http.Response(rpc('0x${'0' * 64}'), 200)), BigInt.zero);
      expect(
          await read(http.Response(rpc('0x${'0' * 63}1'), 200), operator: true),
          BigInt.one);
      for (final response in [
        http.Response('rate limited', 429),
        http.Response(rpc('0x'), 200),
        http.Response(rpc('0x${'x' * 64}'), 200),
        http.Response(
            jsonEncode({
              'error': {'code': -32000}
            }),
            200),
      ]) {
        await expectLater(
            read(response), throwsA(isA<PolymarketReadException>()));
      }
      await expectLater(
          read(http.Response(rpc('0x${'0' * 63}2'), 200), operator: true),
          throwsA(isA<PolymarketReadException>()));
    });

    test('readCtfBalancesBatchOrThrow decodes and rejects short bodies',
        () async {
      String word(int v) => v.toRadixString(16).padLeft(64, '0');
      final ok = await http.runWithClient(
        () => PolymarketOnboardingService()
            .readCtfBalancesBatchOrThrow(positionIds: ['1', '2'], owner: _eoa),
        () => MockClient((_) async => http.Response(
            rpc('0x${word(32)}${word(2)}${word(5)}${word(9)}'), 200)),
      );
      expect(ok, {'1': BigInt.from(5), '2': BigInt.from(9)});

      await expectLater(
        http.runWithClient(
          () => PolymarketOnboardingService().readCtfBalancesBatchOrThrow(
              positionIds: ['1', '2'], owner: _eoa),
          () => MockClient((_) async =>
              http.Response(rpc('0x${word(32)}${word(2)}${word(5)}'), 200)),
        ),
        throwsA(isA<PolymarketReadException>()),
      );
    });

    test('hasContractCodeOrThrow distinguishes empty code from failure',
        () async {
      Future<bool> run(http.Response r) => http.runWithClient(
            () => PolymarketOnboardingService().hasContractCodeOrThrow(_uups),
            () => MockClient((_) async => r),
          );
      expect(await run(http.Response(rpc('0x'), 200)), isFalse);
      expect(await run(http.Response(rpc('0x6080'), 200)), isTrue);
      await expectLater(run(http.Response('down', 500)),
          throwsA(isA<PolymarketReadException>()));
    });

    test('getPositionsOrThrow throws on a failed Data API read', () async {
      final model = PolymarketModel();
      await expectLater(
        model.getPositionsOrThrow(_uups,
            client: MockClient((_) async => http.Response('down', 503))),
        throwsA(isA<http.ClientException>()),
      );
      // Data API v2 envelope; a documented miss is `data: null` or `[]`.
      final empty = await model.getPositionsOrThrow(_uups,
          client: MockClient((_) async => http.Response(
              '{"data":[],"pagination":{"limit":100,"offset":0,'
              '"has_more":false,"next_cursor":null}}',
              200)));
      expect(empty, isEmpty);
      final miss = await model.getPositionsOrThrow(_uups,
          client: MockClient((_) async => http.Response('{"data":null}', 200)));
      expect(miss, isEmpty);
    });
  });
}
