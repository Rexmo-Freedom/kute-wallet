import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';

WalletConfig _ledger({
  String? evmAddress,
  int? verifiedAt,
  String? fingerprint = 'aabbccdd',
}) =>
    WalletConfig(
      id: 'ledger-1',
      name: 'Ledger',
      sparkEnabled: false,
      isWatchOnly: true,
      isHardware: true,
      walletType: 'ledger',
      scriptType: 'bip84',
      masterFingerprint: fingerprint,
      evmAddress: evmAddress,
      evmDerivationPath: evmAddress == null ? null : "m/44'/60'/0'/0/0",
      evmVerifiedAtMs: verifiedAt,
    );

const _address = '0x14791697260E4c9A71f18484C9f997B308e59325';

void main() {
  test('round trip keeps the EVM identity', () {
    final wallet = _ledger(evmAddress: _address, verifiedAt: 1700000000000);
    final restored = WalletConfig.fromMap(wallet.toMap());
    expect(restored.evmAddress, _address);
    expect(restored.evmDerivationPath, "m/44'/60'/0'/0/0");
    expect(restored.evmVerifiedAtMs, 1700000000000);
    expect(restored.hasVerifiedEvm, isTrue);
    expect(restored.isLedger, isTrue);
  });

  test('an old map with no EVM keys gives nulls (Bitcoin-only Ledger)', () {
    final old = {
      'id': 'ledger-1',
      'name': 'Ledger',
      'sparkEnabled': false,
      'isWatchOnly': true,
      'isHardware': true,
      'walletType': 'ledger',
      'masterFingerprint': 'aabbccdd',
    };
    final wallet = WalletConfig.fromMap(old);
    expect(wallet.evmAddress, isNull);
    expect(wallet.evmDerivationPath, isNull);
    expect(wallet.evmVerifiedAtMs, isNull);
    expect(wallet.isLedger, isTrue);
    expect(wallet.hasVerifiedEvm, isFalse);
  });

  test('toMap only appends the new keys', () {
    final keys = _ledger().toMap().keys.toList();
    expect(keys.sublist(keys.length - 6), [
      'evmAddress',
      'evmDerivationPath',
      'evmVerifiedAtMs',
      'recoveryCheckAddress',
      'evmDerivationVersion',
      'evmFormatCheckPending',
    ]);
    expect(keys.first, 'id');
  });

  test('passkey vintage fields survive untouched', () {
    for (final provider in [null, 'breez-0.17']) {
      final wallet = WalletConfig(
        id: 'spend',
        name: 'Spending Wallet',
        isPasskey: true,
        passkeyLabel: 'label-7',
        passkeyProvider: provider,
      );
      final map = wallet.toMap();
      expect(map.containsKey('passkeyProvider'), isTrue);
      final restored = WalletConfig.fromMap(map);
      expect(restored.passkeyProvider, provider);
      expect(restored.passkeyLabel, 'label-7');
      final copied = restored.copyWith(evmAddress: _address);
      expect(copied.passkeyProvider, provider);
      expect(copied.passkeyLabel, 'label-7');
    }
    // An old passkey map with no passkeyProvider key stays legacy (null).
    final legacy = WalletConfig.fromMap(
        {'id': 'x', 'name': 'x', 'isPasskey': true, 'passkeyLabel': 'L'});
    expect(legacy.passkeyProvider, isNull);
    expect(legacy.passkeyLabel, 'L');
  });

  test('isLedger only for walletType ledger with isHardware', () {
    expect(_ledger().isLedger, isTrue);
    expect(
        WalletConfig(id: 'a', name: 'a', walletType: 'ledger').isLedger, isFalse);
    expect(
        WalletConfig(id: 'b', name: 'b', isHardware: true, walletType: 'jade')
            .isLedger,
        isFalse);
    expect(WalletConfig(id: 'c', name: 'c').isLedger, isFalse);
    // A verified identity on something that is not a Ledger never counts.
    expect(
        WalletConfig(
                id: 'd',
                name: 'd',
                evmAddress: _address,
                evmVerifiedAtMs: 1)
            .hasVerifiedEvm,
        isFalse);
  });

  test('a Ledger is never the spending wallet', () {
    final wallet = _ledger(evmAddress: _address, verifiedAt: 1);
    expect(wallet.isSparkWallet, isFalse);
  });

  test('copyWith keeps or clears the identity', () {
    final wallet = _ledger(evmAddress: _address, verifiedAt: 5);
    expect(wallet.copyWith(name: 'Renamed').evmAddress, _address);
    final cleared = wallet.copyWith(clearEvmIdentity: true);
    expect(cleared.evmAddress, isNull);
    expect(cleared.evmDerivationPath, isNull);
    expect(cleared.evmVerifiedAtMs, isNull);
    expect(cleared.masterFingerprint, 'aabbccdd');
  });
}
