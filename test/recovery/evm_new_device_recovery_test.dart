import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/evm_derivation_policy.dart';
import 'package:kute/services/secure/recovery_check.dart';

// Public phrase used only for deterministic recovery tests.
const phrase = 'abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon about';
const legacyAddress = '0xAac5482758cD28C38090Dcc2f0A08f09C0F814B2';
const standardAddress = '0x9858EfFD232B4033E47d90003D41EC34EcaEda94';

void main() {
  test('historical SDK passkey config without EVM metadata retains old address',
      () {
    final wallet = WalletConfig.fromMap({
      'id': 'old-device-copy',
      'name': 'Wallet',
      'isPasskey': true,
      'passkeyProvider': 'breez-0.17',
      'passkeyLabel': 'Spending Wallet · 1700000000000',
    });
    expect(wallet.evmDerivationVersion, EvmDerivationVersion.legacySha256);
    expect(
        RecoveryCheck.deriveSync(phrase, version: wallet.evmDerivationVersion),
        legacyAddress);
  });

  test('fresh-device label discovery reconstructs both original EVM identities',
      () {
    for (final entry in {
      'Spending Wallet · 1700000000000': legacyAddress,
      standardEvmPasskeyLabel('Spending Wallet · 1800000000000'):
          standardAddress,
    }.entries) {
      // Matches recover_choice: pass the full discovered label into the
      // passkey derivation and persist its format on the new local wallet.
      final discoveredLabel = entry.key;
      final wallet = WalletConfig(
        id: 'new-local-id',
        name: displayPasskeyLabel(discoveredLabel),
        isPasskey: true,
        isRestore: true,
        passkeyLabel: discoveredLabel,
        passkeyProvider: 'breez-0.17',
        evmDerivationVersion: passkeyEvmDerivationVersion(discoveredLabel),
      );
      final reopened = WalletConfig.fromMap(wallet.toMap());
      expect(reopened.passkeyLabel, discoveredLabel);
      expect(
          RecoveryCheck.deriveSync(phrase,
              version: reopened.evmDerivationVersion),
          entry.value);
    }
  });

  test(
      'the same phrase can recover distinct legacy and standard EVM accounts',
      () {
    final old = RecoveryCheck.deriveSync(phrase,
        version: EvmDerivationVersion.legacySha256);
    final standard = RecoveryCheck.deriveSync(phrase,
        version: EvmDerivationVersion.standardBip39);
    expect(old, legacyAddress);
    expect(standard, standardAddress);
    expect(RecoveryCheck.matches(old, standard), isFalse);
  });

  test('restored standard config retains format after rename and backup', () {
    final imported = WalletConfig(
      id: 'phrase-restore',
      name: 'Restored',
      isRestore: true,
      evmDerivationVersion: EvmDerivationVersion.standardBip39,
      recoveryCheckAddress: standardAddress,
    );
    final reopened = WalletConfig.fromMap(
        imported.copyWith(name: 'Renamed', backedUp: true).toMap());
    expect(
        RecoveryCheck.matches(
          reopened.recoveryCheckAddress!,
          RecoveryCheck.deriveSync(phrase,
              version: reopened.evmDerivationVersion),
        ),
        isTrue);
  });
}
