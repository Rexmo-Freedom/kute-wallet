import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/evm_wallet_derivation.dart';

// Public deterministic fixtures. Never fund these wallets.
const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const hardhatPhrase =
    'test test test test test test test test test test test junk';

void main() {
  group('versioned EVM derivation', () {
    test('legacy contract retains the existing key and address', () {
      final wallet = EvmWalletDerivation.deriveWallet(
        mnemonic: phrase,
        version: EvmDerivationVersion.legacySha256,
      );
      expect(wallet.privateKey,
          '0x501291248b5a9ab2c9fba2b1c8f6dfef52cbf8b9bb5b7635a2cd02ddd35fa939');
      expect(wallet.address, '0xAac5482758cD28C38090Dcc2f0A08f09C0F814B2');
      expect(wallet.validate(), isTrue);
    });

    test('standard BIP39 vector uses the Ethereum account zero path', () {
      final wallet = EvmWalletDerivation.deriveWallet(
        mnemonic: phrase,
        version: EvmDerivationVersion.standardBip39,
      );
      expect(wallet.privateKey,
          '0x1ab42cc412b618bdea3a599e3c9bae199ebf030895b039e9db1e30dafb12b727');
      expect(wallet.address, '0x9858EfFD232B4033E47d90003D41EC34EcaEda94');
      expect(wallet.derivationIndex, 0);
      expect(wallet.validate(), isTrue);
    });

    test('standard Hardhat development vectors preserve child indices', () {
      final first = EvmWalletDerivation.deriveWallet(
        mnemonic: hardhatPhrase,
        version: EvmDerivationVersion.standardBip39,
      );
      final second = EvmWalletDerivation.deriveWallet(
        mnemonic: hardhatPhrase,
        version: EvmDerivationVersion.standardBip39,
        index: 1,
      );
      expect(first.privateKey,
          '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80');
      expect(first.address, '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266');
      expect(second.address, '0x70997970C51812dc3A010C7d01b50e0d17dc79C8');
      expect(second.derivationIndex, 1);
    });

    test('canonical English spacing and case preserve standard identity', () {
      final wallet = EvmWalletDerivation.deriveWallet(
        mnemonic: '  ${phrase.toUpperCase().replaceAll(' ', '\n\t')}  ',
        version: EvmDerivationVersion.standardBip39,
      );
      expect(wallet.address, '0x9858EfFD232B4033E47d90003D41EC34EcaEda94');
    });

    for (final version in EvmDerivationVersion.values) {
      test('$version rejects invalid checksum and unsupported indices', () {
        expect(
          () => EvmWalletDerivation.deriveWallet(
            mnemonic: List.filled(12, 'abandon').join(' '),
            version: version,
          ),
          throwsArgumentError,
        );
        for (final index in [-1, 0x80000000]) {
          expect(
            () => EvmWalletDerivation.deriveWallet(
              mnemonic: phrase,
              version: version,
              index: index,
            ),
            throwsArgumentError,
          );
        }
      });
    }
  });

  group('account zero key for the Settings reveal', () {
    test('standard BIP39 vector reveals the key of the known address', () {
      final account = EvmWalletDerivation.accountZeroKey(
        mnemonic: phrase,
        version: EvmDerivationVersion.standardBip39,
      );
      expect(account.address, '0x9858EfFD232B4033E47d90003D41EC34EcaEda94');
      expect(account.privateKey,
          '0x1ab42cc412b618bdea3a599e3c9bae199ebf030895b039e9db1e30dafb12b727');
      expect(account.privateKey, matches(RegExp(r'^0x[0-9a-f]{64}$')));
    });

    test('legacy wallets reveal the key of the account the app uses', () {
      final account = EvmWalletDerivation.accountZeroKey(
        mnemonic: phrase,
        version: EvmDerivationVersion.legacySha256,
      );
      final used = EvmWalletDerivation.deriveWallet(
        mnemonic: phrase,
        version: EvmDerivationVersion.legacySha256,
      );
      expect(account.address, used.address);
      expect(account.address, '0xAac5482758cD28C38090Dcc2f0A08f09C0F814B2');
      expect(account.privateKey,
          '0x501291248b5a9ab2c9fba2b1c8f6dfef52cbf8b9bb5b7635a2cd02ddd35fa939');
    });

    test('an invalid phrase reveals nothing', () {
      expect(
        () => EvmWalletDerivation.accountZeroKey(
          mnemonic: List.filled(12, 'abandon').join(' '),
          version: EvmDerivationVersion.standardBip39,
        ),
        throwsArgumentError,
      );
    });
  });

  group('wallet derivation provenance', () {
    test('updating an existing wallet cannot replace its key contract',
        () async {
      final model = SettingsModel(Settings(
        currency: 'USD',
        language: 'en',
        btcFormat: 'sats',
        backup: false,
        biometricsEnabled: false,
        bitcoinElectrumNode: '',
        nodeType: 'electrum',
        reviewDone: false,
        wallets: [WalletConfig(id: 'historical', name: 'Historical')],
      ));
      addTearDown(model.dispose);
      await expectLater(
        model.updateWalletConfig(WalletConfig(
          id: 'historical',
          name: 'Historical',
          evmDerivationVersion: EvmDerivationVersion.standardBip39,
        )),
        throwsStateError,
      );
    });

    test('all missing historical metadata defaults to legacy', () {
      for (final extras in [
        <String, Object?>{},
        {'isPasskey': true, 'passkeyProvider': 'breez-0.17'},
        {'isRestore': true},
        {'isHardware': true, 'walletType': 'ledger'},
      ]) {
        final wallet = WalletConfig.fromMap({
          'id': 'historical',
          'name': 'Historical',
          ...extras,
        });
        expect(wallet.evmDerivationVersion, EvmDerivationVersion.legacySha256);
      }
    });

    for (final version in EvmDerivationVersion.values) {
      test('$version survives serialization and unrelated config edits', () {
        final wallet = WalletConfig(
          id: 'wallet',
          name: 'Wallet',
          evmDerivationVersion: version,
        );
        final restored = WalletConfig.fromMap(wallet.toMap());
        expect(restored.evmDerivationVersion, version);
        expect(
            restored.copyWith(name: 'Renamed').evmDerivationVersion, version);
        expect(restored.copyWith(backedUp: true).evmDerivationVersion, version);
        expect(restored.copyWith(clearEvmIdentity: true).evmDerivationVersion,
            version);
      });
    }

    test('unknown explicit metadata fails closed without selecting a key', () {
      for (final invalid in ['future-v3', '', 1, false, <String, String>{}]) {
        expect(
          () => WalletConfig.fromMap({
            'id': 'wallet',
            'name': 'Wallet',
            'evmDerivationVersion': invalid,
          }),
          throwsFormatException,
        );
      }
    });
  });
}
