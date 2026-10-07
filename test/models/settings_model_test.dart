import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';

void main() {
  Settings _makeSettings({
    String currency = 'USD',
    String language = 'en',
    String btcFormat = 'sats',
    bool backup = false,
    int balancePrivacy = 0,
    bool biometricsEnabled = false,
    String bitcoinElectrumNode = 'ssl://electrum.blockstream.info:700',
    String nodeType = 'electrum',
    bool reviewDone = false,
    List<WalletConfig> wallets = const [],
    String? activeWalletId,
  }) {
    return Settings(
      currency: currency,
      language: language,
      btcFormat: btcFormat,
      backup: backup,
      balancePrivacy: balancePrivacy,
      biometricsEnabled: biometricsEnabled,
      bitcoinElectrumNode: bitcoinElectrumNode,
      nodeType: nodeType,
      reviewDone: reviewDone,
      wallets: wallets,
      activeWalletId: activeWalletId,
    );
  }

  group('WalletConfig', () {
    test('toMap and fromMap round-trip', () {
      // 'Coldcard' is a legacy walletType from before Coldcard
      // support was removed. Stored wallets with retired types must
      // keep round-tripping unchanged, so keep this value here.
      final config = WalletConfig(
        id: 'w1',
        name: 'Main Wallet',
        sparkEnabled: true,
        backedUp: true,
        isWatchOnly: false,
        isHardware: true,
        isExternalAddress: false,
        walletType: 'Coldcard',
        scriptType: 'bip84',
        masterFingerprint: 'aabbccdd',
        isSigner: false,
        isRestore: true,
      );
      final map = config.toMap();
      final restored = WalletConfig.fromMap(map);
      expect(restored.id, 'w1');
      expect(restored.name, 'Main Wallet');
      expect(restored.sparkEnabled, isTrue);
      expect(restored.backedUp, isTrue);
      expect(restored.isHardware, isTrue);
      expect(restored.walletType, 'Coldcard');
      expect(restored.scriptType, 'bip84');
      expect(restored.masterFingerprint, 'aabbccdd');
      expect(restored.isRestore, isTrue);
    });

    test('fromMap defaults', () {
      final config = WalletConfig.fromMap({'id': 'w2', 'name': 'Test'});
      expect(config.sparkEnabled, isTrue);
      expect(config.backedUp, isFalse);
      expect(config.isWatchOnly, isFalse);
      expect(config.isHardware, isFalse);
      expect(config.isExternalAddress, isFalse);
      expect(config.walletType, 'Generic Signer');
      expect(config.scriptType, isNull);
      expect(config.masterFingerprint, isNull);
      expect(config.isSigner, isFalse);
      expect(config.isRestore, isFalse);
    });

    test('copyWith overrides specific fields', () {
      final config = WalletConfig(id: 'w3', name: 'Original');
      final copy = config.copyWith(name: 'Renamed', backedUp: true);
      expect(copy.id, 'w3');
      expect(copy.name, 'Renamed');
      expect(copy.backedUp, isTrue);
      expect(copy.sparkEnabled, isTrue); // default preserved
    });

    test('copyWith preserves id', () {
      final config = WalletConfig(id: 'w4', name: 'Test');
      final copy = config.copyWith(name: 'New');
      expect(copy.id, 'w4');
    });
  });

  group('Settings', () {
    test('valid btcFormat values accepted', () {
      for (final fmt in ['BTC', 'mBTC', 'bits', 'sats']) {
        final s = _makeSettings(btcFormat: fmt);
        expect(s.btcFormat, fmt);
      }
    });

    test('invalid btcFormat throws ArgumentError', () {
      expect(
        () => _makeSettings(btcFormat: 'invalid'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('toMap includes all fields', () {
      final s = _makeSettings(
        currency: 'EUR',
        language: 'pt',
        btcFormat: 'BTC',
      );
      final map = s.toMap();
      expect(map['currency'], 'EUR');
      expect(map['language'], 'pt');
      expect(map['btcFormat'], 'BTC');
      expect(map['balancePrivacy'], 0);
      expect(map['backup'], isFalse);
      expect(map['themeMode'], 'system');
      expect(map['wallets'], isA<List>());
    });

    test('copyWith overrides specific fields', () {
      final s = _makeSettings();
      final copy = s.copyWith(currency: 'BRL', language: 'pt');
      expect(copy.currency, 'BRL');
      expect(copy.language, 'pt');
      expect(copy.btcFormat, 'sats'); // preserved
    });

    test('copyWith with invalid btcFormat throws', () {
      final s = _makeSettings();
      expect(
        () => s.copyWith(btcFormat: 'bad'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('activeWallet returns matching wallet', () {
      final w = WalletConfig(id: 'w1', name: 'Main');
      final s = _makeSettings(wallets: [w], activeWalletId: 'w1');
      expect(s.activeWallet, isNotNull);
      expect(s.activeWallet!.id, 'w1');
    });

    test('activeWallet returns null when no wallets', () {
      final s = _makeSettings(activeWalletId: 'w1');
      expect(s.activeWallet, isNull);
    });

    test('activeWallet returns null when activeWalletId is null', () {
      final w = WalletConfig(id: 'w1', name: 'Main');
      final s = _makeSettings(wallets: [w]);
      expect(s.activeWallet, isNull);
    });

    test('activeWallet returns null when id not found', () {
      final w = WalletConfig(id: 'w1', name: 'Main');
      final s = _makeSettings(wallets: [w], activeWalletId: 'nonexistent');
      expect(s.activeWallet, isNull);
    });

    test('default themeMode is system', () {
      final s = _makeSettings();
      expect(s.themeMode, 'system');
    });

    test('default isPremium is false', () {
      final s = _makeSettings();
      expect(s.isPremium, isFalse);
    });

    test('toMap serializes wallets', () {
      final w = WalletConfig(id: 'w1', name: 'Test');
      final s = _makeSettings(wallets: [w]);
      final map = s.toMap();
      expect((map['wallets'] as List).length, 1);
      expect((map['wallets'] as List)[0]['id'], 'w1');
    });
  });

  // ---------------------------------------------------------------------------
  // WalletConfig — extended tests
  // ---------------------------------------------------------------------------
  group('WalletConfig — constructor defaults', () {
    test('constructor applies correct defaults', () {
      final config = WalletConfig(id: 'abc', name: 'My Wallet');
      expect(config.id, 'abc');
      expect(config.name, 'My Wallet');
      expect(config.sparkEnabled, isTrue);
      expect(config.backedUp, isFalse);
      expect(config.isWatchOnly, isFalse);
      expect(config.isHardware, isFalse);
      expect(config.isExternalAddress, isFalse);
      expect(config.walletType, 'Generic Signer');
      expect(config.scriptType, isNull);
      expect(config.masterFingerprint, isNull);
      expect(config.isSigner, isFalse);
      expect(config.isRestore, isFalse);
      expect(config.hasPassphrase, isFalse);
    });

    test('constructor accepts all explicit values', () {
      final config = WalletConfig(
        id: 'x1',
        name: 'Full',
        sparkEnabled: false,
        backedUp: true,
        isWatchOnly: true,
        isHardware: true,
        isExternalAddress: true,
        walletType: 'Ledger',
        scriptType: 'bip86',
        masterFingerprint: '11223344',
        isSigner: true,
        isRestore: true,
        hasPassphrase: true,
      );
      expect(config.sparkEnabled, isFalse);
      expect(config.backedUp, isTrue);
      expect(config.isWatchOnly, isTrue);
      expect(config.isHardware, isTrue);
      expect(config.isExternalAddress, isTrue);
      expect(config.walletType, 'Ledger');
      expect(config.scriptType, 'bip86');
      expect(config.masterFingerprint, '11223344');
      expect(config.isSigner, isTrue);
      expect(config.isRestore, isTrue);
      expect(config.hasPassphrase, isTrue);
    });
  });

  group('WalletConfig — toMap completeness', () {
    test('toMap includes hasPassphrase field', () {
      final config = WalletConfig(id: 'p1', name: 'Pass', hasPassphrase: true);
      final map = config.toMap();
      expect(map['hasPassphrase'], isTrue);
    });

    test('toMap includes null optional fields', () {
      final config = WalletConfig(id: 'n1', name: 'Nulls');
      final map = config.toMap();
      expect(map.containsKey('scriptType'), isTrue);
      expect(map['scriptType'], isNull);
      expect(map.containsKey('masterFingerprint'), isTrue);
      expect(map['masterFingerprint'], isNull);
    });

    test('toMap contains exactly the expected keys', () {
      final config = WalletConfig(id: 'k1', name: 'Keys');
      final map = config.toMap();
      final expectedKeys = {
        'id',
        'name',
        'sparkEnabled',
        'backedUp',
        'isWatchOnly',
        'isHardware',
        'isExternalAddress',
        'walletType',
        'scriptType',
        'masterFingerprint',
        'isSigner',
        'isRestore',
        'hasPassphrase',
        'isPasskey',
        'passkeyLabel',
        'passkeyProvider',
        'cloudBackedUp',
        'firstScanDone',
        // Ledger Ethereum identity (Wallet hardening Phase 3, B7).
        'evmAddress',
        'evmDerivationPath',
        'evmVerifiedAtMs',
        'recoveryCheckAddress',
        'evmDerivationVersion',
        'evmFormatCheckPending',
      };
      expect(map.keys.toSet(), expectedKeys);
    });
  });

  group('WalletConfig — fromMap edge cases', () {
    test('fromMap with hasPassphrase missing defaults to false', () {
      final config = WalletConfig.fromMap({'id': 'h1', 'name': 'NoPass'});
      expect(config.hasPassphrase, isFalse);
    });

    test('fromMap with hasPassphrase true', () {
      final config = WalletConfig.fromMap({
        'id': 'h2',
        'name': 'WithPass',
        'hasPassphrase': true,
      });
      expect(config.hasPassphrase, isTrue);
    });

    test('fromMap round-trip preserves all fields including hasPassphrase', () {
      final original = WalletConfig(
        id: 'rt1',
        name: 'RoundTrip',
        sparkEnabled: false,
        backedUp: true,
        isWatchOnly: true,
        isHardware: false,
        isExternalAddress: true,
        walletType: 'Trezor',
        scriptType: 'bip49',
        masterFingerprint: 'deadbeef',
        isSigner: true,
        isRestore: false,
        hasPassphrase: true,
      );
      final restored = WalletConfig.fromMap(original.toMap());
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.sparkEnabled, original.sparkEnabled);
      expect(restored.backedUp, original.backedUp);
      expect(restored.isWatchOnly, original.isWatchOnly);
      expect(restored.isHardware, original.isHardware);
      expect(restored.isExternalAddress, original.isExternalAddress);
      expect(restored.walletType, original.walletType);
      expect(restored.scriptType, original.scriptType);
      expect(restored.masterFingerprint, original.masterFingerprint);
      expect(restored.isSigner, original.isSigner);
      expect(restored.isRestore, original.isRestore);
      expect(restored.hasPassphrase, original.hasPassphrase);
    });

    test('fromMap accepts Map<dynamic, dynamic> keys (Hive compatibility)', () {
      final dynamicMap = <dynamic, dynamic>{
        'id': 'dyn1',
        'name': 'Dynamic',
        'sparkEnabled': false,
        'walletType': 'BitBox',
      };
      final config = WalletConfig.fromMap(dynamicMap);
      expect(config.id, 'dyn1');
      expect(config.sparkEnabled, isFalse);
      expect(config.walletType, 'BitBox');
    });
  });

  group('WalletConfig — copyWith extended', () {
    test('copyWith overrides every mutable field individually', () {
      final base = WalletConfig(id: 'cw1', name: 'Base');

      expect(base.copyWith(sparkEnabled: false).sparkEnabled, isFalse);
      expect(base.copyWith(backedUp: true).backedUp, isTrue);
      expect(base.copyWith(isWatchOnly: true).isWatchOnly, isTrue);
      expect(base.copyWith(isHardware: true).isHardware, isTrue);
      expect(base.copyWith(isExternalAddress: true).isExternalAddress, isTrue);
      expect(base.copyWith(walletType: 'Jade').walletType, 'Jade');
      expect(base.copyWith(scriptType: 'bip44').scriptType, 'bip44');
      expect(
        base.copyWith(masterFingerprint: 'ff00ff00').masterFingerprint,
        'ff00ff00',
      );
      expect(base.copyWith(isSigner: true).isSigner, isTrue);
      expect(base.copyWith(isRestore: true).isRestore, isTrue);
      expect(base.copyWith(hasPassphrase: true).hasPassphrase, isTrue);
    });

    test('copyWith with no arguments returns equivalent object', () {
      final base = WalletConfig(
        id: 'cw2',
        name: 'Same',
        scriptType: 'bip84',
        masterFingerprint: 'aabb',
      );
      final copy = base.copyWith();
      expect(copy.id, base.id);
      expect(copy.name, base.name);
      expect(copy.scriptType, base.scriptType);
      expect(copy.masterFingerprint, base.masterFingerprint);
    });
  });

  // ---------------------------------------------------------------------------
  // Settings — extended tests
  // ---------------------------------------------------------------------------
  group('Settings — all default values', () {
    test('default values for optional fields', () {
      final s = _makeSettings();
      expect(s.themeMode, 'system');
      expect(s.fullAccount, isFalse);
      expect(s.kycCompleted, isFalse);
      expect(s.country, isNull);
      expect(s.wallets, isEmpty);
      expect(s.activeWalletId, isNull);
      expect(s.isPremium, isFalse);
      expect(s.affiliateCode, isNull);
    });
  });

  group('Settings — btcFormat validation', () {
    test('empty string btcFormat throws ArgumentError', () {
      expect(
        () => _makeSettings(btcFormat: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('case-sensitive btcFormat rejects lowercase btc', () {
      expect(
        () => _makeSettings(btcFormat: 'btc'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('case-sensitive btcFormat rejects SATS', () {
      expect(
        () => _makeSettings(btcFormat: 'SATS'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('btcFormat rejects Satoshis', () {
      expect(
        () => _makeSettings(btcFormat: 'Satoshis'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('btcFormat rejects numeric string', () {
      expect(
        () => _makeSettings(btcFormat: '100'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Settings — toMap completeness', () {
    test('toMap contains exactly the expected keys', () {
      final s = _makeSettings();
      final map = s.toMap();
      final expectedKeys = {
        'currency',
        'language',
        'btcFormat',
        'balancePrivacy',
        'backup',
        'biometricsEnabled',
        'bitcoinElectrumNode',
        'nodeType',
        'reviewDone',
        'affiliateCode',
        'themeMode',
        'fullAccount',
        'kycCompleted',
        'country',
        'wallets',
        'activeWalletId',
        'isPremium',
        'simpleMode',
        'mascotEnabled',
        'soundEnabled',
        'signerEnabled',
        'mainDenomination',
        'autoLockSeconds',
      };
      expect(map.keys.toSet(), expectedKeys);
    });

    test('toMap serializes all non-default field values', () {
      final wallet = WalletConfig(id: 'tw1', name: 'TestW');
      final s = Settings(
        currency: 'GBP',
        language: 'fr',
        btcFormat: 'mBTC',
        backup: true,
        balancePrivacy: 1,
        biometricsEnabled: true,
        bitcoinElectrumNode: 'ssl://my-node:50002',
        nodeType: 'custom',
        reviewDone: true,
        affiliateCode: 'REF123',
        themeMode: 'light',
        fullAccount: true,
        kycCompleted: true,
        country: 'US',
        wallets: [wallet],
        activeWalletId: 'tw1',
        isPremium: true,
      );
      final map = s.toMap();
      expect(map['currency'], 'GBP');
      expect(map['language'], 'fr');
      expect(map['btcFormat'], 'mBTC');
      expect(map['backup'], isTrue);
      expect(map['balancePrivacy'], 1);
      expect(map['biometricsEnabled'], isTrue);
      expect(map['bitcoinElectrumNode'], 'ssl://my-node:50002');
      expect(map['nodeType'], 'custom');
      expect(map['reviewDone'], isTrue);
      expect(map['affiliateCode'], 'REF123');
      expect(map['themeMode'], 'light');
      expect(map['fullAccount'], isTrue);
      expect(map['kycCompleted'], isTrue);
      expect(map['country'], 'US');
      expect(map['isPremium'], isTrue);
      expect(map['activeWalletId'], 'tw1');
      expect((map['wallets'] as List).length, 1);
    });

    test('toMap serializes null optional fields', () {
      final s = _makeSettings();
      final map = s.toMap();
      expect(map['affiliateCode'], isNull);
      expect(map['country'], isNull);
      expect(map['activeWalletId'], isNull);
    });
  });

  group('Settings — copyWith extended', () {
    test('copyWith overrides every field individually', () {
      final base = _makeSettings();

      expect(base.copyWith(currency: 'JPY').currency, 'JPY');
      expect(base.copyWith(language: 'ja').language, 'ja');
      expect(base.copyWith(btcFormat: 'BTC').btcFormat, 'BTC');
      expect(base.copyWith(balancePrivacy: 1).balanceVisible, isFalse);
      expect(base.copyWith(backup: true).backup, isTrue);
      expect(base.copyWith(biometricsEnabled: true).biometricsEnabled, isTrue);
      expect(
        base
            .copyWith(bitcoinElectrumNode: 'ssl://other:50002')
            .bitcoinElectrumNode,
        'ssl://other:50002',
      );
      expect(base.copyWith(nodeType: 'bitcoin-core').nodeType, 'bitcoin-core');
      expect(base.copyWith(reviewDone: true).reviewDone, isTrue);
      expect(
        base.copyWith(affiliateCode: 'XYZ').affiliateCode,
        'XYZ',
      );
      expect(base.copyWith(themeMode: 'light').themeMode, 'light');
      expect(base.copyWith(fullAccount: true).fullAccount, isTrue);
      expect(base.copyWith(kycCompleted: true).kycCompleted, isTrue);
      expect(base.copyWith(country: 'BR').country, 'BR');
      expect(base.copyWith(isPremium: true).isPremium, isTrue);
      expect(
        base.copyWith(activeWalletId: 'new-id').activeWalletId,
        'new-id',
      );
    });

    test('copyWith with wallets replaces the list entirely', () {
      final w1 = WalletConfig(id: 'a', name: 'A');
      final w2 = WalletConfig(id: 'b', name: 'B');
      final s = _makeSettings(wallets: [w1]);
      final copy = s.copyWith(wallets: [w2]);
      expect(copy.wallets.length, 1);
      expect(copy.wallets.first.id, 'b');
    });

    test('copyWith preserves all other fields when one changes', () {
      final w = WalletConfig(id: 'p1', name: 'Preserved');
      final s = Settings(
        currency: 'CHF',
        language: 'de',
        btcFormat: 'bits',
        backup: true,
        balancePrivacy: 1,
        biometricsEnabled: true,
        bitcoinElectrumNode: 'ssl://node:50002',
        nodeType: 'custom',
        reviewDone: true,
        affiliateCode: 'AFF',
        themeMode: 'light',
        fullAccount: true,
        kycCompleted: true,
        country: 'CH',
        wallets: [w],
        activeWalletId: 'p1',
        isPremium: true,
      );
      final copy = s.copyWith(currency: 'USD');
      expect(copy.currency, 'USD');
      // Every other field preserved
      expect(copy.language, 'de');
      expect(copy.btcFormat, 'bits');
      expect(copy.backup, isTrue);
      expect(copy.balanceVisible, isFalse);
      expect(copy.biometricsEnabled, isTrue);
      expect(copy.bitcoinElectrumNode, 'ssl://node:50002');
      expect(copy.nodeType, 'custom');
      expect(copy.reviewDone, isTrue);
      expect(copy.affiliateCode, 'AFF');
      expect(copy.themeMode, 'light');
      expect(copy.fullAccount, isTrue);
      expect(copy.kycCompleted, isTrue);
      expect(copy.country, 'CH');
      expect(copy.wallets.length, 1);
      expect(copy.activeWalletId, 'p1');
      expect(copy.isPremium, isTrue);
    });
  });

  group('Settings — theme settings', () {
    test('themeMode can be set to light', () {
      final s = Settings(
        currency: 'USD',
        language: 'en',
        btcFormat: 'sats',
        backup: false,
        balancePrivacy: 0,
        biometricsEnabled: false,
        bitcoinElectrumNode: 'ssl://electrum.blockstream.info:700',
        nodeType: 'electrum',
        reviewDone: false,
        themeMode: 'light',
      );
      expect(s.themeMode, 'light');
    });

    test('themeMode survives copyWith', () {
      final s = _makeSettings();
      expect(s.themeMode, 'system');
      final copy = s.copyWith(themeMode: 'dark');
      expect(copy.themeMode, 'dark');
      // original unchanged
      expect(s.themeMode, 'system');
    });

    test('themeMode serialized in toMap', () {
      final s = Settings(
        currency: 'USD',
        language: 'en',
        btcFormat: 'sats',
        backup: false,
        balancePrivacy: 0,
        biometricsEnabled: false,
        bitcoinElectrumNode: 'node',
        nodeType: 'electrum',
        reviewDone: false,
        themeMode: 'light',
      );
      expect(s.toMap()['themeMode'], 'light');
    });
  });

  group('Settings — currency format settings', () {
    test('different currencies are stored correctly', () {
      for (final curr in ['USD', 'EUR', 'GBP', 'BRL', 'JPY', 'CHF']) {
        final s = _makeSettings(currency: curr);
        expect(s.currency, curr);
        expect(s.toMap()['currency'], curr);
      }
    });

    test('btcFormat values round-trip through toMap', () {
      for (final fmt in ['BTC', 'mBTC', 'bits', 'sats']) {
        final s = _makeSettings(btcFormat: fmt);
        expect(s.toMap()['btcFormat'], fmt);
      }
    });
  });

  group('Settings — account status fields', () {
    test('fullAccount defaults to false', () {
      final s = _makeSettings();
      expect(s.fullAccount, isFalse);
    });

    test('kycCompleted defaults to false', () {
      final s = _makeSettings();
      expect(s.kycCompleted, isFalse);
    });

    test('country defaults to null', () {
      final s = _makeSettings();
      expect(s.country, isNull);
    });

    test('account status fields can be set via constructor', () {
      final s = Settings(
        currency: 'USD',
        language: 'en',
        btcFormat: 'sats',
        backup: false,
        balancePrivacy: 0,
        biometricsEnabled: false,
        bitcoinElectrumNode: 'node',
        nodeType: 'electrum',
        reviewDone: false,
        fullAccount: true,
        kycCompleted: true,
        country: 'DE',
      );
      expect(s.fullAccount, isTrue);
      expect(s.kycCompleted, isTrue);
      expect(s.country, 'DE');
    });

    test('account status fields serialize in toMap', () {
      final s = Settings(
        currency: 'USD',
        language: 'en',
        btcFormat: 'sats',
        backup: false,
        balancePrivacy: 0,
        biometricsEnabled: false,
        bitcoinElectrumNode: 'node',
        nodeType: 'electrum',
        reviewDone: false,
        fullAccount: true,
        kycCompleted: true,
        country: 'PT',
        isPremium: true,
      );
      final map = s.toMap();
      expect(map['fullAccount'], isTrue);
      expect(map['kycCompleted'], isTrue);
      expect(map['country'], 'PT');
      expect(map['isPremium'], isTrue);
    });
  });

  group('Settings — activeWallet edge cases', () {
    test('activeWallet with multiple wallets returns the correct one', () {
      final w1 = WalletConfig(id: 'a', name: 'A');
      final w2 = WalletConfig(id: 'b', name: 'B');
      final w3 = WalletConfig(id: 'c', name: 'C');
      final s = _makeSettings(wallets: [w1, w2, w3], activeWalletId: 'b');
      expect(s.activeWallet, isNotNull);
      expect(s.activeWallet!.id, 'b');
      expect(s.activeWallet!.name, 'B');
    });

    test('activeWallet with duplicate ids returns the first match', () {
      final w1 = WalletConfig(id: 'dup', name: 'First');
      final w2 = WalletConfig(id: 'dup', name: 'Second');
      final s = _makeSettings(wallets: [w1, w2], activeWalletId: 'dup');
      expect(s.activeWallet, isNotNull);
      expect(s.activeWallet!.name, 'First');
    });

    test('activeWallet is null when wallets list is empty and id is null', () {
      final s = _makeSettings();
      expect(s.activeWallet, isNull);
    });
  });

  group('Settings — toMap with multiple wallets', () {
    test('toMap serializes multiple wallets correctly', () {
      final w1 = WalletConfig(id: 'w1', name: 'Wallet 1', scriptType: 'bip84');
      final w2 = WalletConfig(
        id: 'w2',
        name: 'Wallet 2',
        isHardware: true,
        walletType: 'Ledger',
      );
      final s = _makeSettings(wallets: [w1, w2], activeWalletId: 'w1');
      final map = s.toMap();
      final walletsList = map['wallets'] as List;
      expect(walletsList.length, 2);
      expect(walletsList[0]['id'], 'w1');
      expect(walletsList[0]['scriptType'], 'bip84');
      expect(walletsList[1]['id'], 'w2');
      expect(walletsList[1]['isHardware'], isTrue);
      expect(walletsList[1]['walletType'], 'Ledger');
      expect(map['activeWalletId'], 'w1');
    });

    test('toMap serializes empty wallets list', () {
      final s = _makeSettings();
      final map = s.toMap();
      expect(map['wallets'], isEmpty);
    });
  });

  group('Settings — immutability checks', () {
    test('copyWith returns a new instance', () {
      final s = _makeSettings();
      final copy = s.copyWith(currency: 'EUR');
      expect(identical(s, copy), isFalse);
      expect(s.currency, 'USD');
      expect(copy.currency, 'EUR');
    });

    test('modifying copied wallets list does not affect original', () {
      final w = WalletConfig(id: 'im1', name: 'Immutable');
      final s = _makeSettings(wallets: [w]);
      final copy = s.copyWith(
        wallets: [...s.wallets, WalletConfig(id: 'im2', name: 'New')],
      );
      expect(s.wallets.length, 1);
      expect(copy.wallets.length, 2);
    });
  });

  group('WalletConfig — scriptType values', () {
    test('all known scriptType values can be set', () {
      for (final st in ['bip44', 'bip49', 'bip84', 'bip86']) {
        final config = WalletConfig(id: 'st', name: 'Script', scriptType: st);
        expect(config.scriptType, st);
        final restored = WalletConfig.fromMap(config.toMap());
        expect(restored.scriptType, st);
      }
    });
  });

  group('WalletConfig — wallet type combinations', () {
    test('watch-only wallet config', () {
      final config = WalletConfig(
        id: 'wo1',
        name: 'Watch Only',
        isWatchOnly: true,
        isHardware: false,
        isSigner: false,
      );
      expect(config.isWatchOnly, isTrue);
      expect(config.isHardware, isFalse);
      expect(config.isSigner, isFalse);
    });

    test('hardware wallet config', () {
      final config = WalletConfig(
        id: 'hw1',
        name: 'Hardware',
        isWatchOnly: false,
        isHardware: true,
        walletType: 'Ledger',
        masterFingerprint: 'aabbccdd',
      );
      expect(config.isHardware, isTrue);
      expect(config.walletType, 'Ledger');
      expect(config.masterFingerprint, 'aabbccdd');
    });

    test('signer wallet config', () {
      final config = WalletConfig(
        id: 'sg1',
        name: 'Signer',
        isSigner: true,
        isHardware: false,
        isWatchOnly: false,
      );
      expect(config.isSigner, isTrue);
    });

    test('restored wallet with passphrase', () {
      final config = WalletConfig(
        id: 'rp1',
        name: 'Restored',
        isRestore: true,
        hasPassphrase: true,
      );
      expect(config.isRestore, isTrue);
      expect(config.hasPassphrase, isTrue);
    });
  });
}
