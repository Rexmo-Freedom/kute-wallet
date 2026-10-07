import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/funding/ledger_cash_app_recipient.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';

const _owner = '0x1111111111111111111111111111111111111111';
const _uups = '0x2222222222222222222222222222222222222222';
const _beacon = '0x3333333333333333333333333333333333333333';
const _safe = '0x4444444444444444444444444444444444444444';
const _other = '0x5555555555555555555555555555555555555555';

class _Reads implements PolymarketAccountReads {
  final deployed = <String>{};
  bool unavailable = false;
  final owners = <String>[];

  @override
  String deriveDepositWalletAddress(String eoa) {
    owners.add(eoa);
    return _uups;
  }

  @override
  Future<String> predictDepositWallet(String eoa) async {
    owners.add(eoa);
    return _beacon;
  }

  @override
  Future<bool?> relayerWalletDeployed(String address) async => false;

  @override
  Future<bool> hasCode(String address) async {
    if (unavailable) throw StateError('Offline');
    return deployed.contains(address);
  }

  @override
  Future<String> deriveSafeAddress(String eoa) async => _safe;

  @override
  Future<List<Position>> positions(String address) async => [];

  @override
  Future<BigInt> erc20Balance({required String token, required String owner}) =>
      throw UnimplementedError();
}

void main() {
  test('existing Ledger deposit accounts need only public reads', () async {
    for (final address in [_uups, _beacon]) {
      final reads = _Reads()..deployed.add(address);
      final result = await ledgerCashAppPredictionsRecipient(
        eoa: _owner,
        reads: reads,
        deploy: (_) async => fail('Existing accounts must not deploy again'),
      );
      expect(result, address);
      expect(reads.owners, everyElement(_owner));
    }
  });

  test('first deposit creates and verifies the selected Ledger account',
      () async {
    for (final address in [_uups, _beacon]) {
      final reads = _Reads();
      var deploys = 0;
      final result = await ledgerCashAppPredictionsRecipient(
        eoa: _owner,
        reads: reads,
        deploy: (owner) async {
          expect(owner, _owner);
          deploys++;
          reads.deployed.add(address);
          return address;
        },
        delay: (_) async {},
      );
      expect(result, address);
      expect(deploys, 1);
      expect(reads.owners, everyElement(_owner));
    }
  });

  test('rejects a deployment response belonging to another account', () async {
    await expectLater(
      ledgerCashAppPredictionsRecipient(
        eoa: _owner,
        reads: _Reads(),
        deploy: (_) async => _other,
        delay: (_) async {},
      ),
      throwsStateError,
    );
  });

  test('a predicted address is insufficient until deployment is confirmed',
      () async {
    await expectLater(
      ledgerCashAppPredictionsRecipient(
        eoa: _owner,
        reads: _Reads(),
        deploy: (_) async => _uups,
        delay: (_) async {},
      ),
      throwsStateError,
    );
  });

  test('legacy accounts and failed reads never silently create a new account',
      () async {
    for (final reads in [
      _Reads()..deployed.add(_safe),
      _Reads()..unavailable = true,
    ]) {
      await expectLater(
        ledgerCashAppPredictionsRecipient(
          eoa: _owner,
          reads: reads,
          deploy: (_) async => fail('Cannot deploy with uncertain ownership'),
        ),
        throwsStateError,
      );
    }
  });

  test('invalid Ledger identity is rejected before deployment', () async {
    final reads = _Reads();
    await expectLater(
      ledgerCashAppPredictionsRecipient(
        eoa: '',
        reads: reads,
        deploy: (_) async => fail('Missing Ledger identity'),
      ),
      throwsStateError,
    );
    expect(reads.owners, isEmpty);
  });
}
