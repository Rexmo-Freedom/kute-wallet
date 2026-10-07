import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';

Settings _defaultSettings({
  String currency = 'USD',
  String language = 'en',
  String btcFormat = 'sats',
  String themeMode = 'dark',
  List<WalletConfig> wallets = const [],
  String? activeWalletId,
}) {
  return Settings(
    currency: currency,
    language: language,
    btcFormat: btcFormat,
    backup: false,
    balancePrivacy: 0,
    biometricsEnabled: true,
    bitcoinElectrumNode: 'bitcoin-mainnet.blockstream.info:50002',
    nodeType: 'Blockstream',
    reviewDone: false,
    themeMode: themeMode,
    wallets: wallets,
    activeWalletId: activeWalletId,
  );
}

void main() {
  group('Settings model', () {
    test('valid btcFormat values accepted', () {
      for (final fmt in ['BTC', 'mBTC', 'bits', 'sats']) {
        final s = _defaultSettings(btcFormat: fmt);
        expect(s.btcFormat, fmt);
      }
    });

    test('invalid btcFormat throws ArgumentError', () {
      expect(
        () => _defaultSettings(btcFormat: 'invalid'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('copyWith updates currency', () {
      final s = _defaultSettings();
      final updated = s.copyWith(currency: 'EUR');
      expect(updated.currency, 'EUR');
      expect(updated.language, 'en');
    });

    test('copyWith updates language', () {
      final s = _defaultSettings();
      final updated = s.copyWith(language: 'pt');
      expect(updated.language, 'pt');
    });

    test('copyWith updates themeMode', () {
      final s = _defaultSettings();
      final updated = s.copyWith(themeMode: 'light');
      expect(updated.themeMode, 'light');
    });

    test('copyWith preserves all fields', () {
      final s = Settings(
        currency: 'EUR',
        language: 'pt',
        btcFormat: 'BTC',
        backup: true,
        balancePrivacy: 1,
        biometricsEnabled: false,
        bitcoinElectrumNode: 'custom:50002',
        nodeType: 'Custom',
        reviewDone: true,
        themeMode: 'light',
        fullAccount: true,
        kycCompleted: true,
        country: 'BR',
        isPremium: true,
      );
      final updated = s.copyWith(currency: 'GBP');
      expect(updated.language, 'pt');
      expect(updated.btcFormat, 'BTC');
      expect(updated.backup, true);
      expect(updated.balanceVisible, false);
      expect(updated.themeMode, 'light');
      expect(updated.fullAccount, true);
      expect(updated.country, 'BR');
      expect(updated.isPremium, true);
    });

    test('toMap serializes all fields', () {
      final s = _defaultSettings();
      final map = s.toMap();
      expect(map['currency'], 'USD');
      expect(map['language'], 'en');
      expect(map['btcFormat'], 'sats');
      expect(map['themeMode'], 'dark');
      expect(map['wallets'], isA<List>());
    });

    test('activeWallet returns null when no wallets', () {
      final s = _defaultSettings();
      expect(s.activeWallet, isNull);
    });

    test('activeWallet returns null when activeWalletId is null', () {
      final wallet = WalletConfig(id: 'w1', name: 'Test');
      final s = _defaultSettings(wallets: [wallet]);
      expect(s.activeWallet, isNull);
    });

    test('activeWallet returns matching wallet', () {
      final wallet = WalletConfig(id: 'w1', name: 'Test');
      final s = _defaultSettings(wallets: [wallet], activeWalletId: 'w1');
      expect(s.activeWallet, isNotNull);
      expect(s.activeWallet!.id, 'w1');
    });

    test('activeWallet returns null for non-existent id', () {
      final wallet = WalletConfig(id: 'w1', name: 'Test');
      final s = _defaultSettings(wallets: [wallet], activeWalletId: 'w999');
      expect(s.activeWallet, isNull);
    });
  });

  group('WalletConfig', () {
    test('defaults are sensible', () {
      final w = WalletConfig(id: 'abc', name: 'My Wallet');
      expect(w.sparkEnabled, true);
      expect(w.backedUp, false);
      expect(w.isWatchOnly, false);
      expect(w.isHardware, false);
      expect(w.isExternalAddress, false);
      expect(w.walletType, 'Generic Signer');
      expect(w.scriptType, isNull);
      expect(w.masterFingerprint, isNull);
      expect(w.isSigner, false);
      expect(w.isRestore, false);
    });

    test('toMap and fromMap roundtrip', () {
      final original = WalletConfig(
        id: 'w1',
        name: 'Test',
        sparkEnabled: false,
        backedUp: true,
        isWatchOnly: true,
        scriptType: 'bip84',
        masterFingerprint: 'aabbccdd',
      );
      final map = original.toMap();
      final restored = WalletConfig.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.sparkEnabled, original.sparkEnabled);
      expect(restored.backedUp, original.backedUp);
      expect(restored.isWatchOnly, original.isWatchOnly);
      expect(restored.scriptType, original.scriptType);
      expect(restored.masterFingerprint, original.masterFingerprint);
    });

    test('copyWith updates name', () {
      final w = WalletConfig(id: 'w1', name: 'Old');
      final updated = w.copyWith(name: 'New');
      expect(updated.name, 'New');
      expect(updated.id, 'w1');
    });

    test('fromMap handles missing optional fields', () {
      final map = {'id': 'w1', 'name': 'Test'};
      final w = WalletConfig.fromMap(map);
      expect(w.sparkEnabled, true);
      expect(w.scriptType, isNull);
    });
  });

  group('SettingsModel notifier (pure logic)', () {
    test('state is accessible after construction', () {
      final model = SettingsModel(_defaultSettings());
      expect(model.state.currency, 'USD');
      expect(model.state.language, 'en');
    });

    test('state reflects initial settings', () {
      final model = SettingsModel(_defaultSettings(
        currency: 'EUR',
        language: 'pt',
        themeMode: 'light',
      ));
      expect(model.state.currency, 'EUR');
      expect(model.state.language, 'pt');
      expect(model.state.themeMode, 'light');
    });
  });
}
