import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/services/evm_derivation_policy.dart';
import 'package:kute/services/evm_wallet_derivation.dart';

void main() {
  test('new passkey discovery preserves standard recovery format', () {
    const label = 'Spending Wallet::1700000000000';
    final discovered = standardEvmPasskeyLabel(label);
    expect(passkeyEvmDerivationVersion(discovered),
        EvmDerivationVersion.standardBip39);
    expect(displayPasskeyLabel(discovered), label);
    // The full label, including format, remains the original PRF input.
    expect(discovered, isNot(displayPasskeyLabel(discovered)));
  });

  test('unmarked existing passkey labels retain legacy identity and display', () {
    for (final label in ['', 'Kute', 'Spending Wallet::1700000000000']) {
      expect(passkeyEvmDerivationVersion(label), EvmDerivationVersion.legacySha256);
      expect(displayPasskeyLabel(label), label);
    }
  });

  test('unknown explicit passkey format fails instead of selecting legacy', () {
    expect(() => passkeyEvmDerivationVersion('kute:evm:future:v3:Wallet'),
        throwsFormatException);
  });

  test('same phrase has distinct recoverable identities for each format', () {
    const phrase = 'abandon abandon abandon abandon abandon abandon abandon '
        'abandon abandon abandon abandon about';
    final old = EvmWalletDerivation.deriveWallet(mnemonic: phrase,
        version: passkeyEvmDerivationVersion('old label'));
    final fresh = EvmWalletDerivation.deriveWallet(mnemonic: phrase,
        version: passkeyEvmDerivationVersion(standardEvmPasskeyLabel('new label')));
    expect(old.address, '0xAac5482758cD28C38090Dcc2f0A08f09C0F814B2');
    expect(fresh.address, '0x9858EfFD232B4033E47d90003D41EC34EcaEda94');
  });
}
