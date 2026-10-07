import 'package:kute/models/onchain_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/bitcoin_config_model.dart';

void main() {
  // ---------------------------------------------------------------------------
  // BitcoinConfig — constructor validation
  // ---------------------------------------------------------------------------
  group('BitcoinConfig — constructor validation', () {
    test('throws when both mnemonic and xpub are null', () {
      expect(
        () => BitcoinConfig(
          walletId: 'w1',
          network: Network.bitcoin,
          externalKeychain: KeychainKind.external_,
          internalKeychain: KeychainKind.internal,
          isElectrumBlockchain: true,
          electrumUrl: 'electrum.blockstream.info:700',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('throws with descriptive message when both mnemonic and xpub are null', () {
      expect(
        () => BitcoinConfig(
          walletId: 'w1',
          network: Network.bitcoin,
          externalKeychain: KeychainKind.external_,
          internalKeychain: KeychainKind.internal,
          isElectrumBlockchain: true,
          electrumUrl: 'electrum.blockstream.info:700',
        ),
        throwsA(
          predicate((e) =>
              e is Exception &&
              e.toString().contains('mnemonic') &&
              e.toString().contains('xpub')),
        ),
      );
    });

    test('succeeds when mnemonic is provided', () {
      final config = BitcoinConfig(
        walletId: 'w1',
        mnemonic: 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
        network: Network.bitcoin,
        externalKeychain: KeychainKind.external_,
        internalKeychain: KeychainKind.internal,
        isElectrumBlockchain: true,
        electrumUrl: 'electrum.blockstream.info:700',
      );
      expect(config.mnemonic, isNotNull);
      expect(config.xpub, isNull);
    });

    test('succeeds when xpub is provided', () {
      final config = BitcoinConfig(
        walletId: 'w1',
        xpub: 'xpub6CUGRUonZSQ4TWtTMmzXdrXDtypWKiKrhko4egpiMZbpiaQL2jkwSB1icqYh2cfDfVxdx4df189oLKnC5fSwqPfgyP3hooxujYzAu3fDVmz',
        network: Network.bitcoin,
        externalKeychain: KeychainKind.external_,
        internalKeychain: KeychainKind.internal,
        isElectrumBlockchain: true,
        electrumUrl: 'electrum.blockstream.info:700',
      );
      expect(config.xpub, isNotNull);
      expect(config.mnemonic, isNull);
    });

    test('succeeds when both mnemonic and xpub are provided', () {
      final config = BitcoinConfig(
        walletId: 'w1',
        mnemonic: 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
        xpub: 'xpub6CUGRUonZSQ4TWtTMmzXdrXDtypWKiKrhko4egpiMZbpiaQL2jkwSB1icqYh2cfDfVxdx4df189oLKnC5fSwqPfgyP3hooxujYzAu3fDVmz',
        network: Network.bitcoin,
        externalKeychain: KeychainKind.external_,
        internalKeychain: KeychainKind.internal,
        isElectrumBlockchain: true,
        electrumUrl: 'electrum.blockstream.info:700',
      );
      expect(config.mnemonic, isNotNull);
      expect(config.xpub, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // BitcoinConfig — field storage
  // ---------------------------------------------------------------------------
  group('BitcoinConfig — field storage', () {
    test('stores walletId correctly', () {
      final config = _makeConfig(walletId: 'my-wallet-123');
      expect(config.walletId, 'my-wallet-123');
    });

    test('stores mnemonic correctly', () {
      const mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      final config = _makeConfig(mnemonic: mnemonic);
      expect(config.mnemonic, mnemonic);
    });

    test('stores xpub correctly', () {
      const xpub = 'xpub6CUGRUonZSQ4TWtTMmzXdrXDtypWKiKrhko4egpiMZbpiaQL2jkwSB1icqYh2cfDfVxdx4df189oLKnC5fSwqPfgyP3hooxujYzAu3fDVmz';
      final config = _makeConfigXpub(xpub: xpub);
      expect(config.xpub, xpub);
    });

    test('stores network correctly for mainnet', () {
      final config = _makeConfig(network: Network.bitcoin);
      expect(config.network, Network.bitcoin);
    });

    test('stores network correctly for testnet', () {
      final config = _makeConfig(network: Network.testnet);
      expect(config.network, Network.testnet);
    });

    test('stores network correctly for signet', () {
      final config = _makeConfig(network: Network.signet);
      expect(config.network, Network.signet);
    });

    test('stores network correctly for regtest', () {
      final config = _makeConfig(network: Network.regtest);
      expect(config.network, Network.regtest);
    });

    test('stores externalKeychain correctly', () {
      final config = _makeConfig(externalKeychain: KeychainKind.external_);
      expect(config.externalKeychain, KeychainKind.external_);
    });

    test('stores internalKeychain correctly', () {
      final config = _makeConfig(internalKeychain: KeychainKind.internal);
      expect(config.internalKeychain, KeychainKind.internal);
    });

    test('stores isElectrumBlockchain correctly', () {
      final config = _makeConfig(isElectrumBlockchain: true);
      expect(config.isElectrumBlockchain, isTrue);

      final config2 = _makeConfig(isElectrumBlockchain: false);
      expect(config2.isElectrumBlockchain, isFalse);
    });

    test('stores electrumUrl correctly', () {
      final config = _makeConfig(electrumUrl: 'my-node.example.com:50002');
      expect(config.electrumUrl, 'my-node.example.com:50002');
    });

    test('stores scriptType correctly', () {
      for (final st in ['bip44', 'bip49', 'bip84', 'bip86']) {
        final config = _makeConfigXpub(scriptType: st);
        expect(config.scriptType, st);
      }
    });

    test('scriptType defaults to null', () {
      final config = _makeConfig();
      expect(config.scriptType, isNull);
    });

    test('stores masterFingerprint correctly', () {
      final config = _makeConfigXpub(masterFingerprint: 'aabbccdd');
      expect(config.masterFingerprint, 'aabbccdd');
    });

    test('masterFingerprint defaults to null', () {
      final config = _makeConfig();
      expect(config.masterFingerprint, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // BitcoinConfig — isWatchOnly getter
  // ---------------------------------------------------------------------------
  group('BitcoinConfig — isWatchOnly', () {
    test('isWatchOnly is true when mnemonic is null and xpub is provided', () {
      final config = _makeConfigXpub();
      expect(config.isWatchOnly, isTrue);
    });

    test('isWatchOnly is false when mnemonic is provided', () {
      final config = _makeConfig();
      expect(config.isWatchOnly, isFalse);
    });

    test('isWatchOnly is false when both mnemonic and xpub are provided', () {
      final config = BitcoinConfig(
        walletId: 'w1',
        mnemonic: 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
        xpub: 'xpub6CUGRUonZSQ4TWtTMmzXdrXDtypWKiKrhko4egpiMZbpiaQL2jkwSB1icqYh2cfDfVxdx4df189oLKnC5fSwqPfgyP3hooxujYzAu3fDVmz',
        network: Network.bitcoin,
        externalKeychain: KeychainKind.external_,
        internalKeychain: KeychainKind.internal,
        isElectrumBlockchain: true,
        electrumUrl: 'electrum.blockstream.info:700',
      );
      expect(config.isWatchOnly, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // BitcoinConfig — network selection
  // ---------------------------------------------------------------------------
  group('BitcoinConfig — network selection', () {
    test('all Network enum values can be used', () {
      for (final network in Network.values) {
        final config = _makeConfig(network: network);
        expect(config.network, network);
      }
    });

    test('different networks produce different configs', () {
      final mainnet = _makeConfig(network: Network.bitcoin);
      final testnet = _makeConfig(network: Network.testnet);
      expect(mainnet.network, isNot(equals(testnet.network)));
    });
  });

  // ---------------------------------------------------------------------------
  // BitcoinConfig — default values and optional fields
  // ---------------------------------------------------------------------------
  group('BitcoinConfig — default values and optional fields', () {
    test('mnemonic defaults to null when only xpub is provided', () {
      final config = _makeConfigXpub();
      expect(config.mnemonic, isNull);
    });

    test('xpub defaults to null when only mnemonic is provided', () {
      final config = _makeConfig();
      expect(config.xpub, isNull);
    });

    test('scriptType is optional and defaults to null', () {
      final config = _makeConfig();
      expect(config.scriptType, isNull);
    });

    test('masterFingerprint is optional and defaults to null', () {
      final config = _makeConfig();
      expect(config.masterFingerprint, isNull);
    });

    test('scriptType can be set to any string value', () {
      final config = _makeConfigXpub(scriptType: 'custom');
      expect(config.scriptType, 'custom');
    });

    test('masterFingerprint can be any string', () {
      final config = _makeConfigXpub(masterFingerprint: 'deadbeef');
      expect(config.masterFingerprint, 'deadbeef');
    });
  });

  // ---------------------------------------------------------------------------
  // BitcoinConfig — electrum URL variations
  // ---------------------------------------------------------------------------
  group('BitcoinConfig — electrumUrl', () {
    test('stores plain host:port', () {
      final config = _makeConfig(electrumUrl: 'electrum.blockstream.info:700');
      expect(config.electrumUrl, 'electrum.blockstream.info:700');
    });

    test('stores URL with different ports', () {
      final config = _makeConfig(electrumUrl: 'mynode.local:50002');
      expect(config.electrumUrl, 'mynode.local:50002');
    });

    test('stores localhost URL', () {
      final config = _makeConfig(electrumUrl: '127.0.0.1:50001');
      expect(config.electrumUrl, '127.0.0.1:50001');
    });

    test('stores onion address', () {
      final config = _makeConfig(
        electrumUrl: 'abc123def456.onion:50001',
      );
      expect(config.electrumUrl, 'abc123def456.onion:50001');
    });

    test('stores empty string', () {
      final config = _makeConfig(electrumUrl: '');
      expect(config.electrumUrl, '');
    });
  });

  // ---------------------------------------------------------------------------
  // BitcoinConfigModel — construction
  // ---------------------------------------------------------------------------
  group('BitcoinConfigModel — construction', () {
    test('can be constructed with a mnemonic-based config', () {
      final config = _makeConfig();
      final model = BitcoinConfigModel(config);
      expect(model.config, same(config));
    });

    test('can be constructed with an xpub-based config', () {
      final config = _makeConfigXpub();
      final model = BitcoinConfigModel(config);
      expect(model.config, same(config));
    });

    test('config reference is preserved', () {
      final config = _makeConfig(walletId: 'test-id-123');
      final model = BitcoinConfigModel(config);
      expect(model.config.walletId, 'test-id-123');
    });

    test('config properties are accessible through model', () {
      final config = _makeConfigXpub(
        walletId: 'hw-wallet',
        scriptType: 'bip84',
        masterFingerprint: 'aabbccdd',
      );
      final model = BitcoinConfigModel(config);
      expect(model.config.walletId, 'hw-wallet');
      expect(model.config.scriptType, 'bip84');
      expect(model.config.masterFingerprint, 'aabbccdd');
      expect(model.config.isWatchOnly, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // BitcoinConfig — scriptType values for descriptor selection
  // ---------------------------------------------------------------------------
  group('BitcoinConfig — scriptType for descriptor selection', () {
    test('bip84 scriptType is stored correctly', () {
      final config = _makeConfigXpub(scriptType: 'bip84');
      expect(config.scriptType, 'bip84');
    });

    test('bip49 scriptType is stored correctly', () {
      final config = _makeConfigXpub(scriptType: 'bip49');
      expect(config.scriptType, 'bip49');
    });

    test('bip86 scriptType is stored correctly', () {
      final config = _makeConfigXpub(scriptType: 'bip86');
      expect(config.scriptType, 'bip86');
    });

    test('bip44 scriptType is stored correctly', () {
      final config = _makeConfigXpub(scriptType: 'bip44');
      expect(config.scriptType, 'bip44');
    });

    test('null scriptType falls through to default (bip44) in descriptor logic', () {
      final config = _makeConfigXpub(scriptType: null);
      expect(config.scriptType, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // BitcoinConfig — xpub prefix scenarios
  // ---------------------------------------------------------------------------
  group('BitcoinConfig — xpub key prefixes', () {
    test('zpub prefix stored for native segwit', () {
      final config = _makeConfigXpub(
        xpub: 'zpub6rFR7y4Q2AijBEqTUqiB1AvTEnDcT1uXRd9bmP8sJX6oM7E2qhAhB1JGj1o9wbMQFhvR7ZMVibsU5bXBLYvfR1DNLTfMdm7jV8B6sFiwwt',
      );
      expect(config.xpub!.startsWith('zpub'), isTrue);
    });

    test('ypub prefix stored for nested segwit', () {
      final config = _makeConfigXpub(
        xpub: 'ypub6Ww3ibDFGrJMdDahkE3tX9WK1P7YcDMPNyYHRGBZG1bEF1LCUPqTaBJYkFXCNQ5NqDD5FNjjmPGCrT47gSFwk9fcqxB5JSBFpXfCuJA5VBG',
      );
      expect(config.xpub!.startsWith('ypub'), isTrue);
    });

    test('xpub prefix stored for standard key', () {
      final config = _makeConfigXpub(
        xpub: 'xpub6CUGRUonZSQ4TWtTMmzXdrXDtypWKiKrhko4egpiMZbpiaQL2jkwSB1icqYh2cfDfVxdx4df189oLKnC5fSwqPfgyP3hooxujYzAu3fDVmz',
      );
      expect(config.xpub!.startsWith('xpub'), isTrue);
    });

    test('vpub prefix stored for testnet native segwit', () {
      final config = _makeConfigXpub(
        xpub: 'vpub5SLqN2bLY4WeZGmCW1yATtKPYSJMETbJonxF3V3ohWMHqH3aBgND4PkVBJWBKEBh9Ki3Uo8KBrySFqpTMiQfui9fLRvoB7xXPqjqCRg3Dh2',
        network: Network.testnet,
      );
      expect(config.xpub!.startsWith('vpub'), isTrue);
    });

    test('upub prefix stored for testnet nested segwit', () {
      final config = _makeConfigXpub(
        xpub: 'upub5EXXqsKNMks4hEHDGmpXwgppBqFnJBoGEB7RxHpeKBmMfhGYzJDYJKhLcPXyMTQadFU6gRu56LEqemCiCEPHqRmrVghXCG6y4jswgM5vRoN',
        network: Network.testnet,
      );
      expect(config.xpub!.startsWith('upub'), isTrue);
    });

    test('tpub prefix stored for testnet standard key', () {
      final config = _makeConfigXpub(
        xpub: 'tpubDC49r947KGK52X5rBWS4BLs5m9SRY3pYHnvRrm7HcybZ3BfdEsGFyzCMzayi1u2J6hDoS4v2CALB8fSr2YqagGY3Ce3ocqoEGhwsXuqkNz',
        network: Network.testnet,
      );
      expect(config.xpub!.startsWith('tpub'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // BitcoinConfig — walletId variations
  // ---------------------------------------------------------------------------
  group('BitcoinConfig — walletId', () {
    test('accepts UUID-style walletId', () {
      final config = _makeConfig(walletId: '550e8400-e29b-41d4-a716-446655440000');
      expect(config.walletId, '550e8400-e29b-41d4-a716-446655440000');
    });

    test('accepts numeric walletId', () {
      final config = _makeConfig(walletId: '12345');
      expect(config.walletId, '12345');
    });

    test('accepts empty walletId', () {
      final config = _makeConfig(walletId: '');
      expect(config.walletId, '');
    });

    test('different walletIds produce distinct configs', () {
      final config1 = _makeConfig(walletId: 'wallet-1');
      final config2 = _makeConfig(walletId: 'wallet-2');
      expect(config1.walletId, isNot(equals(config2.walletId)));
    });
  });

  // ---------------------------------------------------------------------------
  // BitcoinConfig — masterFingerprint scenarios
  // ---------------------------------------------------------------------------
  group('BitcoinConfig — masterFingerprint', () {
    test('accepts 8-char hex fingerprint', () {
      final config = _makeConfigXpub(masterFingerprint: 'aabbccdd');
      expect(config.masterFingerprint, 'aabbccdd');
    });

    test('accepts uppercase hex fingerprint', () {
      final config = _makeConfigXpub(masterFingerprint: 'AABBCCDD');
      expect(config.masterFingerprint, 'AABBCCDD');
    });

    test('accepts null fingerprint', () {
      final config = _makeConfigXpub(masterFingerprint: null);
      expect(config.masterFingerprint, isNull);
    });

    test('stores arbitrary string as fingerprint (no validation)', () {
      final config = _makeConfigXpub(masterFingerprint: 'not-hex');
      expect(config.masterFingerprint, 'not-hex');
    });
  });

  // ---------------------------------------------------------------------------
  // BitcoinConfig — keychain kind combinations
  // ---------------------------------------------------------------------------
  group('BitcoinConfig — keychain combinations', () {
    test('standard external/internal keychain setup', () {
      final config = _makeConfig(
        externalKeychain: KeychainKind.external_,
        internalKeychain: KeychainKind.internal,
      );
      expect(config.externalKeychain, KeychainKind.external_);
      expect(config.internalKeychain, KeychainKind.internal);
    });

    test('both keychains can be external', () {
      final config = BitcoinConfig(
        walletId: 'w1',
        mnemonic: 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
        network: Network.bitcoin,
        externalKeychain: KeychainKind.external_,
        internalKeychain: KeychainKind.external_,
        isElectrumBlockchain: true,
        electrumUrl: 'electrum.blockstream.info:700',
      );
      expect(config.externalKeychain, KeychainKind.external_);
      expect(config.internalKeychain, KeychainKind.external_);
    });

    test('both keychains can be internal', () {
      final config = BitcoinConfig(
        walletId: 'w1',
        mnemonic: 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
        network: Network.bitcoin,
        externalKeychain: KeychainKind.internal,
        internalKeychain: KeychainKind.internal,
        isElectrumBlockchain: true,
        electrumUrl: 'electrum.blockstream.info:700',
      );
      expect(config.externalKeychain, KeychainKind.internal);
      expect(config.internalKeychain, KeychainKind.internal);
    });
  });

  // ---------------------------------------------------------------------------
  // BitcoinConfig — multiple configs independence
  // ---------------------------------------------------------------------------
  group('BitcoinConfig — multiple configs are independent', () {
    test('modifying one config does not affect another', () {
      final config1 = _makeConfig(walletId: 'w1', electrumUrl: 'node1:50001');
      final config2 = _makeConfig(walletId: 'w2', electrumUrl: 'node2:50002');
      expect(config1.walletId, 'w1');
      expect(config2.walletId, 'w2');
      expect(config1.electrumUrl, 'node1:50001');
      expect(config2.electrumUrl, 'node2:50002');
    });

    test('mnemonic config and xpub config are independent', () {
      final mnemonicConfig = _makeConfig();
      final xpubConfig = _makeConfigXpub();
      expect(mnemonicConfig.isWatchOnly, isFalse);
      expect(xpubConfig.isWatchOnly, isTrue);
      expect(mnemonicConfig.mnemonic, isNotNull);
      expect(xpubConfig.mnemonic, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // BitcoinConfigModel — multiple models from same config
  // ---------------------------------------------------------------------------
  group('BitcoinConfigModel — multiple models', () {
    test('two models with the same config share the config reference', () {
      final config = _makeConfig();
      final model1 = BitcoinConfigModel(config);
      final model2 = BitcoinConfigModel(config);
      expect(identical(model1.config, model2.config), isTrue);
    });

    test('two models with different configs are independent', () {
      final config1 = _makeConfig(walletId: 'a');
      final config2 = _makeConfig(walletId: 'b');
      final model1 = BitcoinConfigModel(config1);
      final model2 = BitcoinConfigModel(config2);
      expect(model1.config.walletId, 'a');
      expect(model2.config.walletId, 'b');
    });
  });

  // ---------------------------------------------------------------------------
  // BitcoinConfig — watch-only wallet scenarios
  // ---------------------------------------------------------------------------
  group('BitcoinConfig — watch-only wallet scenarios', () {
    test('hardware wallet import is watch-only with fingerprint', () {
      final config = _makeConfigXpub(
        xpub: 'zpub6rFR7y4Q2AijBEqTUqiB1AvTEnDcT1uXRd9bmP8sJX6oM7E2qhAhB1JGj1o9wbMQFhvR7ZMVibsU5bXBLYvfR1DNLTfMdm7jV8B6sFiwwt',
        masterFingerprint: 'aabbccdd',
        scriptType: 'bip84',
      );
      expect(config.isWatchOnly, isTrue);
      expect(config.masterFingerprint, 'aabbccdd');
      expect(config.scriptType, 'bip84');
    });

    test('watch-only with bip86 taproot', () {
      final config = _makeConfigXpub(scriptType: 'bip86');
      expect(config.isWatchOnly, isTrue);
      expect(config.scriptType, 'bip86');
    });

    test('watch-only with bip49 nested segwit', () {
      final config = _makeConfigXpub(scriptType: 'bip49');
      expect(config.isWatchOnly, isTrue);
      expect(config.scriptType, 'bip49');
    });

    test('watch-only with bip44 legacy', () {
      final config = _makeConfigXpub(scriptType: 'bip44');
      expect(config.isWatchOnly, isTrue);
      expect(config.scriptType, 'bip44');
    });

    test('watch-only with no scriptType defaults to bip44 path in descriptor logic', () {
      final config = _makeConfigXpub(scriptType: null);
      expect(config.isWatchOnly, isTrue);
      expect(config.scriptType, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // BitcoinConfig — edge cases
  // ---------------------------------------------------------------------------
  group('BitcoinConfig — edge cases', () {
    test('empty mnemonic string is still considered non-null', () {
      final config = BitcoinConfig(
        walletId: 'w1',
        mnemonic: '',
        network: Network.bitcoin,
        externalKeychain: KeychainKind.external_,
        internalKeychain: KeychainKind.internal,
        isElectrumBlockchain: true,
        electrumUrl: 'electrum.blockstream.info:700',
      );
      // Empty string is not null, so the validation passes
      expect(config.mnemonic, '');
      expect(config.isWatchOnly, isFalse);
    });

    test('empty xpub string is still considered non-null', () {
      final config = BitcoinConfig(
        walletId: 'w1',
        xpub: '',
        network: Network.bitcoin,
        externalKeychain: KeychainKind.external_,
        internalKeychain: KeychainKind.internal,
        isElectrumBlockchain: true,
        electrumUrl: 'electrum.blockstream.info:700',
      );
      expect(config.xpub, '');
      expect(config.isWatchOnly, isTrue);
    });

    test('whitespace-only mnemonic passes null check', () {
      final config = BitcoinConfig(
        walletId: 'w1',
        mnemonic: '   ',
        network: Network.bitcoin,
        externalKeychain: KeychainKind.external_,
        internalKeychain: KeychainKind.internal,
        isElectrumBlockchain: true,
        electrumUrl: 'electrum.blockstream.info:700',
      );
      expect(config.mnemonic, '   ');
    });

    test('very long walletId is accepted', () {
      final longId = 'a' * 1000;
      final config = _makeConfig(walletId: longId);
      expect(config.walletId, longId);
      expect(config.walletId.length, 1000);
    });
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Creates a mnemonic-based BitcoinConfig with sensible defaults.
BitcoinConfig _makeConfig({
  String walletId = 'test-wallet',
  String mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
  Network network = Network.bitcoin,
  KeychainKind externalKeychain = KeychainKind.external_,
  KeychainKind internalKeychain = KeychainKind.internal,
  bool isElectrumBlockchain = true,
  String electrumUrl = 'electrum.blockstream.info:700',
  String? scriptType,
  String? masterFingerprint,
}) {
  return BitcoinConfig(
    walletId: walletId,
    mnemonic: mnemonic,
    network: network,
    externalKeychain: externalKeychain,
    internalKeychain: internalKeychain,
    isElectrumBlockchain: isElectrumBlockchain,
    electrumUrl: electrumUrl,
    scriptType: scriptType,
    masterFingerprint: masterFingerprint,
  );
}

/// Creates an xpub-based (watch-only) BitcoinConfig with sensible defaults.
BitcoinConfig _makeConfigXpub({
  String walletId = 'test-wallet',
  String xpub = 'xpub6CUGRUonZSQ4TWtTMmzXdrXDtypWKiKrhko4egpiMZbpiaQL2jkwSB1icqYh2cfDfVxdx4df189oLKnC5fSwqPfgyP3hooxujYzAu3fDVmz',
  Network network = Network.bitcoin,
  KeychainKind externalKeychain = KeychainKind.external_,
  KeychainKind internalKeychain = KeychainKind.internal,
  bool isElectrumBlockchain = true,
  String electrumUrl = 'electrum.blockstream.info:700',
  String? scriptType,
  String? masterFingerprint,
}) {
  return BitcoinConfig(
    walletId: walletId,
    xpub: xpub,
    network: network,
    externalKeychain: externalKeychain,
    internalKeychain: internalKeychain,
    isElectrumBlockchain: isElectrumBlockchain,
    electrumUrl: electrumUrl,
    scriptType: scriptType,
    masterFingerprint: masterFingerprint,
  );
}
