import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';
import 'package:kute/services/wallet_identity_service.dart';

/// Stand-ins for the hot entry points listed in the Phase 5 plan B12. Each
/// asserts first, like the real entry points will once Phase 3 lands.
class _SpyHotEntryPoints {
  final calls = <HotSigningAction>[];

  void _enter(HotSigningAction action) {
    LedgerOperationScope.assertHotAllowed(action);
    calls.add(action);
  }

  String resolveBip39MnemonicFor(String walletId) {
    _enter(HotSigningAction.bip39MnemonicRead);
    return 'abandon abandon';
  }

  String readMnemonic() {
    _enter(HotSigningAction.authMnemonicRead);
    return 'abandon abandon';
  }

  void hyperliquidWithCredentials() =>
      _enter(HotSigningAction.hyperliquidHotCredentials);

  void polymarketHotCredentials() =>
      _enter(HotSigningAction.polymarketHotCredentials);

  Future<void> executeSparkTransaction() async =>
      _enter(HotSigningAction.sparkTransaction);

  Future<void> executeOnchainTransaction() async =>
      _enter(HotSigningAction.onchainTransaction);

  void bdkSoftwareSign() => _enter(HotSigningAction.bdkSoftwareSign);
}

class _FakeLedgerDevice {
  int signatures = 0;

  Future<String> sign(String payload) async {
    await Future<void>.delayed(Duration.zero);
    signatures++;
    return 'sig:$payload';
  }
}

/// A Ledger funding flow built only from the device, like the Phase 4
/// runners: quote, device signature, broadcast through a public endpoint.
Future<String> _fakeLedgerFundingFlow(_FakeLedgerDevice device) async {
  final signed = await device.sign('psbt');
  await Future<void>.delayed(const Duration(milliseconds: 1));
  return signed;
}

/// A Ledger executor that mistakenly reaches for a hot path.
Future<void> _fakeLedgerExecutorWithHotBug(_SpyHotEntryPoints hot) async {
  await Future<void>.delayed(Duration.zero);
  await hot.executeSparkTransaction();
}

void main() {
  late _SpyHotEntryPoints hot;
  late List<HotSigningAction> blocked;

  setUp(() {
    hot = _SpyHotEntryPoints();
    blocked = [];
    LedgerOperationScope.onBlocked = blocked.add;
  });

  tearDown(() => LedgerOperationScope.onBlocked = null);

  test('Ledger flows run with fakes and record zero hot calls', () async {
    final device = _FakeLedgerDevice();
    final result = await LedgerOperationScope.run(
        'ledger-1', () => _fakeLedgerFundingFlow(device));
    expect(result, 'sig:psbt');
    expect(device.signatures, 1);
    expect(hot.calls, isEmpty);
    expect(blocked, isEmpty);
  });

  test('every hot entry point throws inside the scope and emits', () async {
    final entries = <HotSigningAction, FutureOr<Object?> Function()>{
      HotSigningAction.bip39MnemonicRead: () =>
          hot.resolveBip39MnemonicFor('w'),
      HotSigningAction.authMnemonicRead: hot.readMnemonic,
      HotSigningAction.hyperliquidHotCredentials:
          hot.hyperliquidWithCredentials,
      HotSigningAction.polymarketHotCredentials: hot.polymarketHotCredentials,
      HotSigningAction.sparkTransaction: hot.executeSparkTransaction,
      HotSigningAction.onchainTransaction: hot.executeOnchainTransaction,
      HotSigningAction.bdkSoftwareSign: hot.bdkSoftwareSign,
      HotSigningAction.walletIdentitySign: () =>
          WalletIdentityService.buildAuthChallengeV2('', bodyDigest: ''),
    };
    expect(entries.keys.toSet(), HotSigningAction.values.toSet());

    for (final entry in entries.entries) {
      await expectLater(
        LedgerOperationScope.run('ledger-1', () async => entry.value()),
        throwsA(isA<HotSigningInLedgerScope>()
            .having((e) => e.action, 'action', entry.key)),
      );
    }
    expect(hot.calls, isEmpty);
    expect(blocked, HotSigningAction.values);
  });

  test('the scope follows async gaps, timers and microtasks', () async {
    await LedgerOperationScope.run('ledger-1', () async {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(LedgerOperationScope.currentWalletId, 'ledger-1');

      final timer = Completer<Object?>();
      Timer(Duration.zero, () {
        try {
          hot.bdkSoftwareSign();
          timer.complete(null);
        } catch (e) {
          timer.complete(e);
        }
      });
      expect(await timer.future, isA<HotSigningInLedgerScope>());

      final micro = Completer<Object?>();
      scheduleMicrotask(() {
        try {
          hot.readMnemonic();
          micro.complete(null);
        } catch (e) {
          micro.complete(e);
        }
      });
      expect(await micro.future, isA<HotSigningInLedgerScope>());
    });
    expect(hot.calls, isEmpty);
  });

  test('a buggy executor fails closed', () async {
    await expectLater(
      LedgerOperationScope.run(
          'ledger-1', () => _fakeLedgerExecutorWithHotBug(hot)),
      throwsA(isA<HotSigningInLedgerScope>()),
    );
    expect(hot.calls, isEmpty);
    expect(blocked, [HotSigningAction.sparkTransaction]);
  });

  test('outside the scope hot flows are unchanged', () async {
    expect(LedgerOperationScope.isActive, isFalse);
    expect(hot.readMnemonic(), 'abandon abandon');
    await hot.executeSparkTransaction();
    hot.bdkSoftwareSign();
    expect(hot.calls, [
      HotSigningAction.authMnemonicRead,
      HotSigningAction.sparkTransaction,
      HotSigningAction.bdkSoftwareSign,
    ]);
    expect(blocked, isEmpty);
  });

  test('the scope ends when the body finishes or throws', () async {
    await LedgerOperationScope.run('ledger-1', () async {});
    expect(LedgerOperationScope.isActive, isFalse);
    await expectLater(
      LedgerOperationScope.run<void>(
          'ledger-1', () async => throw StateError('device denied')),
      throwsStateError,
    );
    expect(LedgerOperationScope.isActive, isFalse);
    hot.bdkSoftwareSign();
    expect(hot.calls, [HotSigningAction.bdkSoftwareSign]);
  });

  test('nesting keeps the wallet and refuses a different one', () async {
    await LedgerOperationScope.run('ledger-1', () async {
      await LedgerOperationScope.run('ledger-1', () async {
        expect(LedgerOperationScope.currentWalletId, 'ledger-1');
      });
      await expectLater(
        LedgerOperationScope.run('ledger-2', () async {}),
        throwsStateError,
      );
    });
  });

  test('a throwing reporter never lets the hot call through', () async {
    LedgerOperationScope.onBlocked = (_) => throw Exception('tracking down');
    await expectLater(
      LedgerOperationScope.run('ledger-1', () async => hot.readMnemonic()),
      throwsA(isA<HotSigningInLedgerScope>()),
    );
    expect(hot.calls, isEmpty);
  });

  test('event names are unique snake case with no ids', () {
    final names = HotSigningAction.values.map((a) => a.analyticsName).toList();
    expect(names.toSet().length, names.length);
    for (final name in names) {
      expect(RegExp(r'^[a-z0-9]+(_[a-z0-9]+)*$').hasMatch(name), isTrue,
          reason: name);
    }
  });
}
