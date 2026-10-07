import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/l10n/l10n.dart' show languageNativeNames;
import 'package:kute/services/onchain/native_onchain_service.dart' show OnchainEndpoint;
import 'package:kute/models/settings_model.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/secure_storage.dart' as ss;
import 'package:kute/services/tracking_service.dart';

/// First-boot language: follow the DEVICE locale when we ship a full
/// translation for it (one of [languageNativeNames]), otherwise English.
/// Once the user picks a language in Settings the stored value wins and
/// this default never runs again.
String deviceDefaultLanguage() {
  final device = PlatformDispatcher.instance.locale.languageCode;
  return languageNativeNames.containsKey(device) ? device : 'en';
}

final initialSettingsProvider = FutureProvider<Settings>((ref) async {
  final box = await Hive.openBox('settings');
  const storage = ss.secureStorage;

  // General Settings
  final currency = box.get('currency', defaultValue: 'USD');
  final language = box.get('language', defaultValue: deviceDefaultLanguage());
  final btcFormat = box.get('btcFormat', defaultValue: 'sats');
  final backup = box.get('backup', defaultValue: false);
  final balancePrivacy = box.get('balancePrivacy', defaultValue: 0) as int;
  var bitcoinElectrumNode = box.get('bitcoinElectrumNode',
      defaultValue: OnchainEndpoint.defaultMainnet) as String;
  var nodeType = box.get('nodeType', defaultValue: 'Blockstream') as String;
  // The Blockstream preset moved from its Esplora API to its Electrum
  // server (see OnchainEndpoint.defaultMainnet for why). Installs still
  // on the old preset value follow it; a custom Esplora URL is kept.
  if (bitcoinElectrumNode == 'https://blockstream.info/api' &&
      nodeType == 'Blockstream') {
    bitcoinElectrumNode = OnchainEndpoint.defaultMainnet;
    await box.put('bitcoinElectrumNode', bitcoinElectrumNode);
  }
  // One-shot migration: earlier builds shipped a "Mempool"
  // option that pointed at `mempool.space:50002`, but
  // mempool.space only publishes an Esplora REST API — there's
  // no public clearnet Electrum server on that host. Users who
  // selected it were left permanently offline (sync would
  // refuse to connect every retry). Silently rewrite their
  // stored node to a working default so they don't have to dig
  // through settings to recover.
  // Presets that served self-signed certificates could never connect
  // from the app (the native client validates certificates); anyone on
  // one follows the default.
  const retiredPresets = {
    'mempool.space:50002',
    'electrum.emzy.de:50002',
    'electrum.bitaroo.net:50002',
    'bitcoin.aranguren.org:50002',
    'electrum.qtornado.com:50002',
  };
  if (retiredPresets.contains(bitcoinElectrumNode)) {
    bitcoinElectrumNode = OnchainEndpoint.defaultMainnet;
    nodeType = 'Blockstream';
    await box.put('bitcoinElectrumNode', bitcoinElectrumNode);
    await box.put('nodeType', nodeType);
  }
  final biometricsEnabled = box.get('biometricsEnabled', defaultValue: true);
  final affiliateCode = box.get('affiliateCode');
  // New installs default to 'system' (follow device theme). Existing
  // users keep whatever was previously persisted ('light' / 'dark').
  final themeMode = box.get('themeMode', defaultValue: 'system');

  // Account Status Settings
  final fullAccount = box.get('fullAccount', defaultValue: false);
  final kycCompleted = box.get('kycCompleted', defaultValue: false);
  final country = box.get('country');
  final isPremium = box.get('isPremium', defaultValue: false);
  final simpleMode = box.get('simpleMode', defaultValue: false);
  // Delight / mascot toggles. Defaults: mascot ON (it's the
  // brand's signature), sound OFF (wallets should be silent
  // unless the user opts in).
  final mascotEnabled = box.get('mascotEnabled', defaultValue: true);
  final soundEnabled = box.get('soundEnabled', defaultValue: false);
  final signerEnabled = box.get('signerEnabled', defaultValue: false);
  // Default `bitcoin` per spec — a fresh user thinks in bitcoin
  // first. Toggling to `fiat` flips the hero amount everywhere.
  final mainDenomination =
      box.get('mainDenomination', defaultValue: 'bitcoin') as String;
  // Auto-lock grace before the in-place lock overlay engages on
  // resume. Default 5 minutes (user decision); 0 = immediately.
  final autoLockSeconds = box.get('autoLockSeconds', defaultValue: 300) as int;

  // A secure storage error must not block startup: the splash
  // classifies storage failures and shows the retry screen.
  String? reviewDoneString;
  try {
    reviewDoneString = await storage.read(key: 'reviewDone');
  } catch (_) {}
  final reviewDone = reviewDoneString == 'true';

  // Multi-wallet Settings
  final rawWallets = box.get('wallets', defaultValue: []);
  final persistedActiveWalletId = box.get('activeWalletId') as String?;

  // Parse raw maps into WalletConfig objects
  List<WalletConfig> wallets = [];
  if (rawWallets is List) {
    wallets = rawWallets
        .map((e) {
          if (e is Map) {
            return WalletConfig.fromMap(e);
          }
          return null;
        })
        .whereType<WalletConfig>()
        .toList();
  }

  // One-shot migration (2026-08): LEGACY (pre-2.x, passkeyProvider
  // null) passkey wallets depend on a single OS credential on the
  // shared Breez RP, and a second credential minted later can hide
  // them from passkey recovery. Ask their owners for a paper backup:
  // flip `backedUp` to false ONCE so the existing home banner and
  // verify-words quiz take over (the reveal is already vintage-safe
  // via getLegacySeed). Completing the quiz sets backedUp true again;
  // the guard flag stops this migration from ever re-flipping it.
  final legacyPasskeyBackupFlagged =
      box.get('legacyPasskeyBackupPromptV1', defaultValue: false) as bool;
  if (!legacyPasskeyBackupFlagged) {
    var flipped = false;
    wallets = wallets.map((w) {
      if (w.isPasskey && w.passkeyProvider == null && w.backedUp) {
        flipped = true;
        return w.copyWith(backedUp: false);
      }
      return w;
    }).toList();
    if (flipped) {
      await box.put('wallets', wallets.map((w) => w.toMap()).toList());
      TrackingService.track('legacy_passkey_backup_flagged');
    }
    await box.put('legacyPasskeyBackupPromptV1', true);
  }

  // Boot guard: never start with a cold wallet as active. If the
  // process died inside the wallet detail screen (which transiently
  // swaps active to a hardware/watch-only wallet), the persisted
  // activeWalletId could resurrect that swap on next launch and
  // Home would render the cold wallet instead of spending. Snap
  // back to whichever spending wallet exists so the carousel
  // always opens on the hot wallet.
  String? activeWalletId = persistedActiveWalletId;
  if (persistedActiveWalletId != null) {
    WalletConfig? persistedWallet;
    for (final w in wallets) {
      if (w.id == persistedActiveWalletId) {
        persistedWallet = w;
        break;
      }
    }
    final isCold = persistedWallet != null &&
        (persistedWallet.isBitcoinSoftware ||
            persistedWallet.isHardware ||
            persistedWallet.isWatchOnly ||
            persistedWallet.isExternalAddress ||
            persistedWallet.isSigner);
    if (persistedWallet == null || isCold) {
      // Find the first hot/spending wallet.
      WalletConfig? spending;
      for (final w in wallets) {
        if (w.isSparkWallet) {
          spending = w;
          break;
        }
      }
      activeWalletId = spending?.id ??
          (persistedWallet?.isBitcoinSoftware == true
              ? persistedWallet!.id
              : null);
    }
  }

  return Settings(
    currency: currency,
    language: language,
    btcFormat: btcFormat,
    backup: backup,
    bitcoinElectrumNode: bitcoinElectrumNode,
    nodeType: nodeType,
    balancePrivacy: balancePrivacy,
    biometricsEnabled: biometricsEnabled,
    reviewDone: reviewDone,
    affiliateCode: affiliateCode,
    themeMode: themeMode,
    fullAccount: fullAccount,
    kycCompleted: kycCompleted,
    country: country,
    wallets: wallets,
    activeWalletId: activeWalletId,
    isPremium: isPremium,
    simpleMode: simpleMode,
    mascotEnabled: mascotEnabled,
    soundEnabled: soundEnabled,
    signerEnabled: signerEnabled,
    mainDenomination: mainDenomination,
    autoLockSeconds: autoLockSeconds,
  );
});

final settingsProvider = StateNotifierProvider<SettingsModel, Settings>((ref) {
  final initialSettings = ref.watch(initialSettingsProvider);

  return SettingsModel(
    initialSettings.when(
      data: (settings) => settings,
      loading: () {
        return Settings(
          currency: 'USD',
          language: deviceDefaultLanguage(),
          btcFormat: 'sats',
          backup: false,
          bitcoinElectrumNode: OnchainEndpoint.defaultMainnet,
          nodeType: 'Blockstream',
          balancePrivacy: 1,
          biometricsEnabled: true,
          reviewDone: false,
          fullAccount: false,
          kycCompleted: false,
          country: null,
          wallets: [],
          activeWalletId: null,
          isPremium: false,
        );
      },
      error: (err, stack) {
        return Settings(
          currency: 'USD',
          language: deviceDefaultLanguage(),
          btcFormat: 'sats',
          backup: false,
          bitcoinElectrumNode: OnchainEndpoint.defaultMainnet,
          nodeType: 'Blockstream',
          balancePrivacy: 1,
          biometricsEnabled: true,
          reviewDone: false,
          fullAccount: false,
          kycCompleted: false,
          country: null,
          wallets: [],
          activeWalletId: null,
          isPremium: false,
        );
      },
    ),
  );
});

final onlineProvider = StateProvider<bool>((ref) => true);
