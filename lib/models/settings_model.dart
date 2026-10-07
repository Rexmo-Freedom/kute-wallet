import 'package:kute/services/orchestra/standing_deposit_store.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';
import 'package:kute/services/orchestra/pending_receive_quote_cache.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure_storage.dart';
import 'package:kute/services/hardware/ledger/ledger_venue_descriptor_store.dart'
    show wipeLedgerWalletLocalData;
import 'package:hive_ce/hive.dart';
import 'package:kute/services/venue_total_cache_service.dart';
import 'package:path_provider/path_provider.dart';

class WalletConfig {
  final String id;
  final String name;
  final bool sparkEnabled;
  final bool backedUp;
  final bool isWatchOnly;
  final bool isHardware;
  final bool isExternalAddress;
  final String walletType;
  final String? scriptType; // e.g. 'bip84', 'bip86', 'bip49', 'bip44'
  final String? masterFingerprint; // 8-char hex, e.g. 'aabbccdd'
  final bool
      isSigner; // true = this device acts as an air-gapped hardware wallet
  final bool
      isRestore; // true = wallet was restored from seed (affects LN address recovery)
  final bool
      hasPassphrase; // BIP39 passphrase — never stored, entered every time
  final bool isPasskey; // true = wallet secured by passkey, no mnemonic stored
  /// Per-wallet PRF label fed into `Passkey.getWallet(label: …)`. The
  /// Breez SDK derives seed = f(passkey_PRF, label) deterministically,
  /// so two wallets backed by the same passkey MUST carry distinct
  /// labels — otherwise the "second" wallet just re-imports the first.
  /// Null = legacy single-wallet user where the singleton "Default"
  /// label was used at create time; `resolveBip39MnemonicFor` falls
  /// back to that for backward compat.
  final String? passkeyLabel;

  /// Which passkey stack derived this wallet's seed — the VINTAGE tag
  /// every seed-resolution site routes on:
  ///   * null → LEGACY passkey wallet (pre-2.x, breez-sdk 0.15.1 era).
  ///     Its seed derives via the app's own PRF service
  ///     (`PasskeyPrfService`, pinned credential + cached PRF bytes) —
  ///     see `PasskeyService.getLegacySeed`. Persisted wallets from old
  ///     builds have no `passkeyProvider` key, so they land here
  ///     automatically.
  ///   * 'breez-0.17' → created/restored through the 0.17.1
  ///     `PasskeyClient` (register/signIn); seed resolution goes through
  ///     the new SDK path (with credential pinning).
  /// The two paths can resolve DIFFERENT credentials on the shared RP
  /// (all Kute credentials are named 'kute-wallet-user'), so routing a
  /// legacy wallet through the new path derives a different, fund-losing
  /// seed. Only meaningful when `isPasskey` is true.
  final String? passkeyProvider;

  /// True → this wallet's secret material (mnemonic / xpub /
  /// external address) is mirrored into `syncedSecureStorage` and
  /// participates in iCloud Keychain sync. False → local-only.
  /// Default false — Phase C migration flips this to true per wallet
  /// after writing the synced payload.
  final bool cloudBackedUp;

  /// True once this wallet has completed its one-time first full
  /// on-chain scan (Electrum). Until then the next sync runs a FULL
  /// scan to discover all history regardless of birth height; after, every
  /// sync is incremental. Persisted so a cold start before the first scan
  /// finished still triggers a full scan rather than an incremental
  /// against an empty DB (which would show a wrong balance). Only
  /// meaningful for hardware/watch-only (xpub) wallets.
  final bool firstScanDone;

  // ── Ledger Ethereum identity (Wallet hardening Phase 3, B7) ──────────
  // Public data only, all nullable. Written only by
  // `LedgerPairingService.verifyEthereumIdentity` after the user confirmed
  // the address on the device and the Bitcoin fingerprint matched before
  // and after. An old Ledger wallet has none of these keys and stays a
  // Bitcoin-only Ledger.

  /// EIP-55 checksummed address the Ledger displayed and the user approved.
  final String? evmAddress;

  /// BIP32 path of [evmAddress]; `m/44'/60'/0'/0/0` (O5).
  final String? evmDerivationPath;

  /// Epoch ms of the successful on-device verification.
  final int? evmVerifiedAtMs;

  /// Public index 0 EVM address of this wallet's recovery phrase, used only
  /// to match a re-entered phrase to this wallet id (`RecoveryCheck`).
  final String? recoveryCheckAddress;

  /// Immutable phrase-to-EVM-key contract. Missing historical metadata stays
  /// legacy; changing this on an existing wallet would select a new account.
  final EvmDerivationVersion evmDerivationVersion;

  /// True when a phrase recovery could not finish checking whether the
  /// phrase's legacy EVM account holds venue funds (offline, timeout) and
  /// fell back to [EvmDerivationVersion.standardBip39]. The next unlock
  /// retries the check (`RecoveryEvmFormat.retryPending`) and clears it.
  final bool evmFormatCheckPending;

  WalletConfig({
    required this.id,
    required this.name,
    this.sparkEnabled = true,
    this.backedUp = false,
    this.isWatchOnly = false,
    this.isHardware = false,
    this.isExternalAddress = false,
    this.walletType = 'Generic Signer',
    this.scriptType,
    this.masterFingerprint,
    this.isSigner = false,
    this.isRestore = false,
    this.hasPassphrase = false,
    this.isPasskey = false,
    this.passkeyLabel,
    this.passkeyProvider,
    this.cloudBackedUp = false,
    this.firstScanDone = false,
    this.evmAddress,
    this.evmDerivationPath,
    this.evmVerifiedAtMs,
    this.recoveryCheckAddress,
    this.evmDerivationVersion = EvmDerivationVersion.legacySha256,
    this.evmFormatCheckPending = false,
  });

  /// The one spending account backed by the Spark SDK.
  bool get isSparkWallet =>
      sparkEnabled &&
      !isHardware &&
      !isWatchOnly &&
      !isExternalAddress &&
      !isSigner;

  /// An ordinary on-chain wallet whose mnemonic signs locally through BDK.
  bool get isBitcoinSoftware =>
      !sparkEnabled &&
      !isHardware &&
      !isWatchOnly &&
      !isExternalAddress &&
      !isSigner;

  bool get usesBdk => !isSparkWallet && !isExternalAddress && !isSigner;

  /// A Ledger hardware wallet (persisted as `walletType: 'ledger'`).
  bool get isLedger => isHardware && walletType == 'ledger';

  /// A Ledger whose Ethereum address was verified on the device.
  bool get hasVerifiedEvm =>
      isLedger && evmAddress != null && evmVerifiedAtMs != null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'sparkEnabled': sparkEnabled,
      'backedUp': backedUp,
      'isWatchOnly': isWatchOnly,
      'isHardware': isHardware,
      'isExternalAddress': isExternalAddress,
      'walletType': walletType,
      'scriptType': scriptType,
      'masterFingerprint': masterFingerprint,
      'isSigner': isSigner,
      'isRestore': isRestore,
      'hasPassphrase': hasPassphrase,
      'isPasskey': isPasskey,
      'passkeyLabel': passkeyLabel,
      'passkeyProvider': passkeyProvider,
      'cloudBackedUp': cloudBackedUp,
      'firstScanDone': firstScanDone,
      'evmAddress': evmAddress,
      'evmDerivationPath': evmDerivationPath,
      'evmVerifiedAtMs': evmVerifiedAtMs,
      'recoveryCheckAddress': recoveryCheckAddress,
      'evmDerivationVersion': evmDerivationVersion.storageValue,
      'evmFormatCheckPending': evmFormatCheckPending,
    };
  }

  factory WalletConfig.fromMap(Map<dynamic, dynamic> map) {
    return WalletConfig(
      id: map['id'] as String,
      name: map['name'] as String,
      sparkEnabled: map['sparkEnabled'] ?? true,
      backedUp: map['backedUp'] ?? false,
      isWatchOnly: map['isWatchOnly'] ?? false,
      isHardware: map['isHardware'] ?? false,
      isExternalAddress: map['isExternalAddress'] ?? false,
      walletType: map['walletType'] ?? 'Generic Signer',
      scriptType: map['scriptType'],
      masterFingerprint: map['masterFingerprint'],
      isSigner: map['isSigner'] ?? false,
      isRestore: map['isRestore'] ?? false,
      hasPassphrase: map['hasPassphrase'] ?? false,
      isPasskey: map['isPasskey'] ?? false,
      passkeyLabel: map['passkeyLabel'] as String?,
      // Absent key (any wallet persisted before this field) → null →
      // legacy vintage. That default IS the fund-safety property: an
      // old wallet must never silently upgrade itself to the new
      // derivation path.
      passkeyProvider: map['passkeyProvider'] as String?,
      cloudBackedUp: map['cloudBackedUp'] ?? false,
      // Legacy wallets — persisted before this field existed — have NO
      // 'firstScanDone' key, and they were already fully synced under the
      // old path. Default the ABSENT key to true so they go straight to
      // incremental instead of auto-running a heavy (potentially
      // ANR-inducing) full re-scan when their detail screen opens. Any
      // wallet created after this change always writes the key explicitly
      // (false until its first scan completes), so a genuinely-new wallet
      // still full-scans once, and the crash-before-persist retry (key
      // present = false, DB exists) still re-runs the full scan.
      firstScanDone: map['firstScanDone'] ?? true,
      // Absent keys (every wallet persisted before Phase 3) are null: a
      // Bitcoin-only Ledger, or not a Ledger at all.
      evmAddress: map['evmAddress'] as String?,
      evmDerivationPath: map['evmDerivationPath'] as String?,
      evmVerifiedAtMs: (map['evmVerifiedAtMs'] as num?)?.toInt(),
      recoveryCheckAddress: map['recoveryCheckAddress'] as String?,
      evmDerivationVersion:
          EvmDerivationVersion.fromStorage(map['evmDerivationVersion']),
      evmFormatCheckPending: map['evmFormatCheckPending'] == true,
    );
  }

  WalletConfig copyWith({
    String? name,
    bool? sparkEnabled,
    bool? backedUp,
    bool? isWatchOnly,
    bool? isHardware,
    bool? isExternalAddress,
    String? walletType,
    String? scriptType,
    String? masterFingerprint,
    bool? isSigner,
    bool? isRestore,
    bool? hasPassphrase,
    bool? isPasskey,
    String? passkeyLabel,
    String? passkeyProvider,
    bool? cloudBackedUp,
    bool? firstScanDone,
    String? evmAddress,
    String? evmDerivationPath,
    int? evmVerifiedAtMs,
    bool clearEvmIdentity = false,
    String? recoveryCheckAddress,
    bool? evmFormatCheckPending,
  }) {
    return WalletConfig(
      id: id,
      name: name ?? this.name,
      sparkEnabled: sparkEnabled ?? this.sparkEnabled,
      backedUp: backedUp ?? this.backedUp,
      isWatchOnly: isWatchOnly ?? this.isWatchOnly,
      isHardware: isHardware ?? this.isHardware,
      isExternalAddress: isExternalAddress ?? this.isExternalAddress,
      walletType: walletType ?? this.walletType,
      scriptType: scriptType ?? this.scriptType,
      masterFingerprint: masterFingerprint ?? this.masterFingerprint,
      isSigner: isSigner ?? this.isSigner,
      isRestore: isRestore ?? this.isRestore,
      hasPassphrase: hasPassphrase ?? this.hasPassphrase,
      isPasskey: isPasskey ?? this.isPasskey,
      passkeyLabel: passkeyLabel ?? this.passkeyLabel,
      passkeyProvider: passkeyProvider ?? this.passkeyProvider,
      cloudBackedUp: cloudBackedUp ?? this.cloudBackedUp,
      firstScanDone: firstScanDone ?? this.firstScanDone,
      evmAddress: clearEvmIdentity ? null : (evmAddress ?? this.evmAddress),
      evmDerivationPath: clearEvmIdentity
          ? null
          : (evmDerivationPath ?? this.evmDerivationPath),
      evmVerifiedAtMs:
          clearEvmIdentity ? null : (evmVerifiedAtMs ?? this.evmVerifiedAtMs),
      recoveryCheckAddress: recoveryCheckAddress ?? this.recoveryCheckAddress,
      evmDerivationVersion: evmDerivationVersion,
      evmFormatCheckPending:
          evmFormatCheckPending ?? this.evmFormatCheckPending,
    );
  }
}

class Settings {
  final String currency;
  final String language;
  late final String btcFormat;

  /// Home balance privacy cycle, toggled by tapping the headline
  /// balance:
  ///   0 = everything visible
  ///   1 = headline balance hidden (transaction rows still show values)
  ///   2 = headline balance hidden AND transaction values masked
  final int balancePrivacy;

  /// True when the headline balance figures should render. Hidden at
  /// privacy levels 1 and 2. Kept as a getter so the ~20 read sites
  /// that predate the 3-state cycle keep working unchanged.
  bool get balanceVisible => balancePrivacy == 0;

  /// True when individual transaction rows may show their amounts.
  /// Masked only at the deepest privacy level (2).
  bool get transactionValuesVisible => balancePrivacy < 2;

  final bool backup;
  final bool biometricsEnabled;
  final String bitcoinElectrumNode;
  final String nodeType;
  final bool reviewDone;
  final String? affiliateCode;

  // Appearance
  final String themeMode; // 'system' (default), 'dark', 'light'

  // Account Status
  final bool fullAccount;
  final bool kycCompleted;
  final String? country;

  // Account
  final bool isPremium;

  // Simple Mode
  final bool simpleMode;

  // Multi-wallet Settings
  final List<WalletConfig> wallets;
  final String? activeWalletId;

  // ─── Delight / mascot toggles (Phase A8) ────────────────────────
  /// True → the Kute dog mascot renders. False → mascot is hidden
  /// everywhere it reads `kuteStateProvider` (loading overlay, empty
  /// state, and other explicit-state uses still render — only the
  /// global-state perch hides). Default ON because the mascot is the
  /// brand's signature; opt-out for users who find it distracting.
  final bool mascotEnabled;

  /// True → soft chimes play on receive + prediction win. Default
  /// OFF — wallets should be silent by default; the user opts in.
  final bool soundEnabled;

  /// LEGACY (feature removed): the old "signer mode" toggle. The
  /// air-gapped Kute Signer feature is gone; this flag and any
  /// isSigner wallets stay persisted only so existing Hive data
  /// keeps deserializing. Nothing reads this to change behavior.
  final bool signerEnabled;

  /// Single source of truth for "do I think in Bitcoin or in fiat?"
  /// — flips the HERO amount across every balance / activity / chip
  /// surface in the app (home wallet cards, portfolio total,
  /// Polymarket header chip, transaction rows). The secondary line
  /// always shows the other denomination.
  ///
  /// Values: `'bitcoin'` (default) → BTC native is hero, fiat below.
  /// `'fiat'` → fiat hero, BTC native below.
  ///
  /// Replaces the per-surface "is this card BTC-first or fiat-first?"
  /// guesswork that produced inconsistencies (Predictions showing
  /// only sats, Portfolio showing only fiat, etc.). `currency` still
  /// picks which fiat (USD / EUR / …) and `btcFormat` still picks
  /// sats vs BTC; this toggle picks which of the two is the hero.
  final String mainDenomination;

  /// Auto-lock grace: how long the app may sit in the background before
  /// the in-place lock overlay engages on resume. Values: 0 (lock
  /// immediately), 60, or 300 seconds. Default 300 (5 minutes — the
  /// Monzo/PSD2 ceiling; safe because money-moving actions always
  /// require fresh auth regardless of the grace). Cold start always
  /// locks regardless: the unlocked session is memory-only.
  final int autoLockSeconds;

  Settings({
    required this.currency,
    required this.language,
    required String btcFormat,
    required this.backup,
    this.balancePrivacy = 0,
    required this.biometricsEnabled,
    required this.bitcoinElectrumNode,
    required this.nodeType,
    required this.reviewDone,
    this.affiliateCode,
    this.themeMode = 'system',
    this.fullAccount = false,
    this.kycCompleted = false,
    this.country,
    this.wallets = const [],
    this.activeWalletId,
    this.isPremium = false,
    this.simpleMode = false,
    this.mascotEnabled = true,
    this.soundEnabled = false,
    this.signerEnabled = false,
    this.mainDenomination = 'bitcoin',
    this.autoLockSeconds = 300,
  }) : btcFormat = (['BTC', 'mBTC', 'bits', 'sats'].contains(btcFormat))
            ? btcFormat
            : throw ArgumentError('Invalid btcFormat');

  WalletConfig? get activeWallet {
    if (activeWalletId == null || wallets.isEmpty) return null;
    try {
      return wallets.firstWhere((w) => w.id == activeWalletId);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'currency': currency,
      'language': language,
      'btcFormat': btcFormat,
      'balancePrivacy': balancePrivacy,
      'backup': backup,
      'biometricsEnabled': biometricsEnabled,
      'bitcoinElectrumNode': bitcoinElectrumNode,
      'nodeType': nodeType,
      'reviewDone': reviewDone,
      'affiliateCode': affiliateCode,
      'themeMode': themeMode,
      'fullAccount': fullAccount,
      'kycCompleted': kycCompleted,
      'country': country,
      'wallets': wallets.map((x) => x.toMap()).toList(),
      'activeWalletId': activeWalletId,
      'isPremium': isPremium,
      'simpleMode': simpleMode,
      'mascotEnabled': mascotEnabled,
      'soundEnabled': soundEnabled,
      'signerEnabled': signerEnabled,
      'mainDenomination': mainDenomination,
      'autoLockSeconds': autoLockSeconds,
    };
  }

  Settings copyWith({
    String? currency,
    String? language,
    String? btcFormat,
    int? balancePrivacy,
    bool? backup,
    bool? biometricsEnabled,
    String? bitcoinElectrumNode,
    String? nodeType,
    bool? reviewDone,
    String? affiliateCode,
    String? themeMode,
    bool? fullAccount,
    bool? kycCompleted,
    String? country,
    List<WalletConfig>? wallets,
    String? activeWalletId,
    bool? isPremium,
    bool? simpleMode,
    bool? mascotEnabled,
    bool? soundEnabled,
    bool? signerEnabled,
    String? mainDenomination,
    int? autoLockSeconds,
  }) {
    return Settings(
      currency: currency ?? this.currency,
      language: language ?? this.language,
      btcFormat: btcFormat ?? this.btcFormat,
      balancePrivacy: balancePrivacy ?? this.balancePrivacy,
      backup: backup ?? this.backup,
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      bitcoinElectrumNode: bitcoinElectrumNode ?? this.bitcoinElectrumNode,
      nodeType: nodeType ?? this.nodeType,
      reviewDone: reviewDone ?? this.reviewDone,
      affiliateCode: affiliateCode ?? this.affiliateCode,
      themeMode: themeMode ?? this.themeMode,
      fullAccount: fullAccount ?? this.fullAccount,
      kycCompleted: kycCompleted ?? this.kycCompleted,
      country: country ?? this.country,
      wallets: wallets ?? this.wallets,
      activeWalletId: activeWalletId ?? this.activeWalletId,
      isPremium: isPremium ?? this.isPremium,
      simpleMode: simpleMode ?? this.simpleMode,
      mascotEnabled: mascotEnabled ?? this.mascotEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      signerEnabled: signerEnabled ?? this.signerEnabled,
      mainDenomination: mainDenomination ?? this.mainDenomination,
      autoLockSeconds: autoLockSeconds ?? this.autoLockSeconds,
    );
  }
}

class SettingsModel extends StateNotifier<Settings> {
  SettingsModel(super.state);

  WalletConfig? walletById(String id) =>
      state.wallets.where((wallet) => wallet.id == id).firstOrNull;

  final _secureStorage = secureStorage;

  Future<void> addWallet(WalletConfig newWallet) async {
    final box = await Hive.openBox('settings');
    final List<WalletConfig> updatedList = [...state.wallets, newWallet];
    final walletsMap = updatedList.map((w) => w.toMap()).toList();
    await box.put('wallets', walletsMap);

    // Auto-select if it's the first one or logic dictates
    if (state.activeWalletId == null) {
      await setActiveWallet(newWallet.id);
    }

    state = state.copyWith(wallets: updatedList);
  }

  Future<void> removeWallet(String walletId) async {
    // Guard: never delete the last wallet
    if (state.wallets.length <= 1) {
      throw Exception(
          "Cannot delete the last wallet. You must have at least one wallet.");
    }

    // Guard: never delete the last Spark (hot) wallet
    final walletToDelete = state.wallets.firstWhere(
      (w) => w.id == walletId,
      orElse: () => throw Exception("Wallet not found"),
    );
    final isSparkWallet = walletToDelete.isSparkWallet;
    if (isSparkWallet) {
      final sparkCount = state.wallets.where((w) => w.isSparkWallet).length;
      if (sparkCount <= 1) {
        throw Exception("Cannot delete the last Spark wallet.");
      }
    }

    // Release the native owner before deleting a wallet the user removed.
    await NativeOnchainService.instance.retireWallet(walletId);

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final dbFile = File('${appDocDir.path}/bdk_wallet_$walletId.sqlite');
      if (await dbFile.exists()) await dbFile.delete();

      final breezDir = Directory('${appDocDir.path}/breez_$walletId');
      if (await breezDir.exists()) await breezDir.delete(recursive: true);
    } catch (e) {
      // Silently ignored
    }

    await AuthModel().deleteWalletMnemonic(walletId);

    // Clean up Polymarket credentials and proxy wallet
    await SecretStores.local
        .deleteLocalOnly(key: 'pm_api_credentials_$walletId');
    await SecretStores.local.deleteLocalOnly(key: 'pm_proxy_wallet_$walletId');

    // Ledger venue descriptors and submitted-action records (Phase 3).
    await wipeLedgerWalletLocalData(walletId);

    // Per-wallet Hive entries scattered across other services. A
    // forgotten wallet must leave nothing behind that would rehydrate
    // on re-import of a recycled id. Each block is best-effort —
    // missing box / not-open is fine, we just skip it.
    await _wipePerWalletHiveData(walletId);
    await PendingReceiveQuoteCache.deleteForWallet(walletId);
    await StandingDepositStore.deleteWallet(walletId);

    final box = await Hive.openBox('settings');
    final updatedList = state.wallets.where((w) => w.id != walletId).toList();
    final walletsMap = updatedList.map((w) => w.toMap()).toList();
    await box.put('wallets', walletsMap);

    String? newActiveId = state.activeWalletId;
    if (state.activeWalletId == walletId) {
      newActiveId = updatedList.isNotEmpty ? updatedList.first.id : null;
      await box.put('activeWalletId', newActiveId);
    }

    state = state.copyWith(wallets: updatedList, activeWalletId: newActiveId);
  }

  /// Per-wallet Hive cleanup. Called from [removeWallet]. Each box is
  /// best-effort — a missing/closed box is fine, we silently skip it.
  /// Centralised here so adding a new per-wallet store is a one-line
  /// addition with the right naming convention, and the forget-key
  /// flow doesn't drift behind new persistence sites.
  Future<void> _wipePerWalletHiveData(String walletId) async {
    // `addresses` box — caches the wallet's deposit address + index.
    try {
      final addresses = await Hive.openBox('addresses');
      await addresses.delete('bitcoinIndex_$walletId');
      await addresses.delete('bitcoinAddress_$walletId');
    } catch (_) {}

    // `breez_prefs` box — Lightning address registration metadata.
    try {
      final prefs = await Hive.openBox('breez_prefs');
      await prefs.delete('ln_address_$walletId');
      await prefs.delete('ln_username_$walletId');
      await prefs.delete('ln_bech32_$walletId');
      await prefs.delete('is_webhook_registered_$walletId');
    } catch (_) {}

    // `mempool_address_tx_cache` box — external-address tx snapshots.
    try {
      if (Hive.isBoxOpen('mempool_address_tx_cache')) {
        await Hive.box<String>('mempool_address_tx_cache').delete(walletId);
      }
    } catch (_) {}

    // `fee_history` box — per-entry fee log. Entries store walletId
    // in their JSON body, so we scan and drop everything matching.
    try {
      if (Hive.isBoxOpen('fee_history')) {
        final box = Hive.box<String>('fee_history');
        final toDelete = <dynamic>[];
        for (final key in box.keys) {
          final raw = box.get(key);
          if (raw == null) continue;
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map && decoded['walletId'] == walletId) {
              toDelete.add(key);
            }
          } catch (_) {}
        }
        if (toDelete.isNotEmpty) {
          await box.deleteAll(toDelete);
        }
      }
    } catch (_) {}

    // `once_flags` box — analytics "first X" milestones. Wipe ALL
    // flags on any wallet delete: a re-import (even of the same seed)
    // should produce a fresh activation cohort. Device-scoped, not
    // wallet-scoped — there's no clean per-wallet partition here.
    try {
      if (Hive.isBoxOpen('once_flags')) {
        await Hive.box<bool>('once_flags').clear();
      }
    } catch (_) {}
    // `milestones_log` box — chronological log of unlocked milestones
    // (Phase A5). Same wipe semantics as once_flags.
    try {
      if (Hive.isBoxOpen('milestones_log')) {
        await Hive.box('milestones_log').clear();
      }
    } catch (_) {}

    // `wallet_balance_cache` box — persistent per-wallet balance
    // snapshot (Spark BTC + on-chain BTC). Critical: without
    // this delete, the Portfolio total keeps summing the deleted
    // wallet's last-seen balance on every cold start since
    // `WalletBalanceCacheService` rehydrates the whole box into the
    // Riverpod `walletBalanceCacheProvider` at boot. The user's "my
    // portfolio includes wallets I deleted" bug lived here.
    try {
      if (Hive.isBoxOpen('wallet_balance_cache')) {
        await Hive.box<String>('wallet_balance_cache').delete(walletId);
      }
    } catch (_) {}

    // `venue_total_cache` box — the wallet's last Predictions and
    // Investing totals; a deleted wallet's must not outlive it.
    await VenueTotalCacheService.deleteWallet(walletId);

    // `wallet_transaction_cache` box — per-wallet `Transaction`
    // snapshot used by the activity feed. Same rehydrate-on-boot
    // story as the balance cache: a deleted wallet's stale tx list
    // would otherwise reappear on the next launch.
    try {
      if (Hive.isBoxOpen('wallet_transaction_cache')) {
        await Hive.box<String>('wallet_transaction_cache').delete(walletId);
      }
    } catch (_) {}
  }

  Future<void> renameWallet(String walletId, String newName) async {
    final wallet = state.wallets.firstWhere((w) => w.id == walletId,
        orElse: () => throw Exception("Wallet not found"));

    final updatedWallet = wallet.copyWith(name: newName);
    await updateWalletConfig(updatedWallet);
  }

  Future<void> updateWalletConfig(WalletConfig config) async {
    for (final wallet in state.wallets) {
      if (wallet.id == config.id &&
          wallet.evmDerivationVersion != config.evmDerivationVersion) {
        throw StateError('An existing wallet cannot change EVM derivation');
      }
    }
    await _replaceWallet(config);
  }

  Future<void> _replaceWallet(WalletConfig config) async {
    final box = await Hive.openBox('settings');
    final updatedList = state.wallets.map((w) {
      return w.id == config.id ? config : w;
    }).toList();
    final walletsMap = updatedList.map((w) => w.toMap()).toList();
    await box.put('wallets', walletsMap);
    state = state.copyWith(wallets: updatedList);
  }

  /// Marks the recovery EVM format check for [walletId] as settled. A
  /// missing wallet or one with nothing pending is left as is.
  Future<void> clearEvmFormatCheckPending(String walletId) async {
    final wallet = walletById(walletId);
    if (wallet == null || !wallet.evmFormatCheckPending) return;
    await updateWalletConfig(wallet.copyWith(evmFormatCheckPending: false));
  }

  /// The one sanctioned EVM format change. A phrase recovery whose venue
  /// check did not finish fell back to the standard format; the retry found
  /// funds or history only on the legacy account, and none on the standard
  /// one, so the wallet moves to the legacy format with its recovery check
  /// address re-derived for it. Refuses (returns false) for anything else:
  /// a wallet without a pending check, not on the standard format, or not
  /// a stored-seed wallet.
  Future<bool> adoptLegacyEvmAfterRecoveryCheck(
    String walletId, {
    required String recoveryCheckAddress,
  }) async {
    final wallet = walletById(walletId);
    if (wallet == null ||
        !wallet.evmFormatCheckPending ||
        wallet.evmDerivationVersion != EvmDerivationVersion.standardBip39 ||
        wallet.isPasskey ||
        wallet.isHardware ||
        wallet.isWatchOnly ||
        wallet.isExternalAddress) {
      return false;
    }
    await _replaceWallet(WalletConfig.fromMap({
      ...wallet.toMap(),
      'evmDerivationVersion': EvmDerivationVersion.legacySha256.storageValue,
      'recoveryCheckAddress': recoveryCheckAddress,
      'evmFormatCheckPending': false,
    }));
    return true;
  }

  /// Stores a Ledger's device-verified Ethereum identity. Only
  /// `LedgerPairingService` calls this, after a successful verification;
  /// refuses anything that is not a Ledger.
  Future<void> setLedgerEvmIdentity(
    String walletId, {
    required String evmAddress,
    required String evmDerivationPath,
    required int verifiedAtMs,
  }) async {
    final wallet = state.wallets.firstWhere((w) => w.id == walletId,
        orElse: () => throw Exception("Wallet not found"));
    if (!wallet.isLedger) {
      throw StateError('Only a Ledger wallet can hold a verified EVM identity');
    }
    await updateWalletConfig(wallet.copyWith(
      evmAddress: evmAddress,
      evmDerivationPath: evmDerivationPath,
      evmVerifiedAtMs: verifiedAtMs,
    ));
  }

  /// Stores the recovery check address for a wallet that has none. A
  /// missing wallet or an existing address is left as is.
  Future<void> setRecoveryCheckAddress(String walletId, String address) async {
    final wallet = state.wallets.where((w) => w.id == walletId).firstOrNull;
    if (wallet == null || wallet.recoveryCheckAddress != null) return;
    await updateWalletConfig(wallet.copyWith(recoveryCheckAddress: address));
  }

  Future<void> setWalletBackedUp(String walletId, bool backedUp) async {
    final wallet = state.wallets.firstWhere((w) => w.id == walletId,
        orElse: () => throw Exception("Wallet not found"));
    final updatedWallet = wallet.copyWith(backedUp: backedUp);
    await updateWalletConfig(updatedWallet);
  }

  /// Persist that [walletId] has finished its one-time first full
  /// on-chain scan, so every later sync goes incremental. Called from
  /// the sync path the moment a full scan succeeds. Safe no-op if the
  /// wallet is gone or already marked (avoids throwing inside the
  /// sync success path).
  Future<void> setFirstScanDone(String walletId) async {
    WalletConfig? wallet;
    for (final w in state.wallets) {
      if (w.id == walletId) {
        wallet = w;
        break;
      }
    }
    if (wallet == null || wallet.firstScanDone) return;
    await updateWalletConfig(wallet.copyWith(firstScanDone: true));
  }

  Future<void> setActiveWallet(String walletId) async {
    // Update in-memory state synchronously first so that callers like
    // BackgroundSyncService.restart() immediately see the new wallet,
    // even when this Future is not awaited.
    state = state.copyWith(activeWalletId: walletId);
    final box = await Hive.openBox('settings');
    await box.put('activeWalletId', walletId);
  }

  Future<void> setThemeMode(String mode) async {
    final box = await Hive.openBox('settings');
    await box.put('themeMode', mode);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setCurrency(String newCurrency) async {
    final box = await Hive.openBox('settings');
    await box.put('currency', newCurrency);
    state = state.copyWith(currency: newCurrency);
  }

  Future<void> setLanguage(String newLanguage) async {
    final box = await Hive.openBox('settings');
    await box.put('language', newLanguage);
    state = state.copyWith(language: newLanguage);
  }

  Future<void> setBtcFormat(String newBtcFormat) async {
    final box = await Hive.openBox('settings');
    await box.put('btcFormat', newBtcFormat);
    state = state.copyWith(btcFormat: newBtcFormat);
  }

  /// Flip the global hero-amount denomination. `'bitcoin'` →
  /// BTC native is the hero across every balance / chip / row,
  /// fiat sits below as secondary. `'fiat'` → reversed: fiat is
  /// the hero, BTC native sits below. Any other value is rejected.
  Future<void> setMainDenomination(String newDenomination) async {
    if (newDenomination != 'bitcoin' && newDenomination != 'fiat') return;
    final box = await Hive.openBox('settings');
    await box.put('mainDenomination', newDenomination);
    state = state.copyWith(mainDenomination: newDenomination);
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    final box = await Hive.openBox('settings');
    await box.put('biometricsEnabled', enabled);
    state = state.copyWith(biometricsEnabled: enabled);
  }

  /// Persist the auto-lock grace. Only 0 (immediately), 60 (1 minute)
  /// or 300 (5 minutes) are accepted so a malformed write can't poison
  /// the relock policy.
  Future<void> setAutoLockSeconds(int seconds) async {
    if (seconds != 0 && seconds != 60 && seconds != 300) return;
    final box = await Hive.openBox('settings');
    await box.put('autoLockSeconds', seconds);
    state = state.copyWith(autoLockSeconds: seconds);
  }

  Future<void> setBitcoinElectrumNode(String newElectrumNode) async {
    if (newElectrumNode == state.bitcoinElectrumNode) return;
    await NativeOnchainService.instance.closeAll(afterClose: () async {
      final box = await Hive.openBox('settings');
      await box.put('bitcoinElectrumNode', newElectrumNode);
      state = state.copyWith(bitcoinElectrumNode: newElectrumNode);
    });
  }

  Future<void> setNodeType(String newNodeType) async {
    final box = await Hive.openBox('settings');
    await box.put('nodeType', newNodeType);
    state = state.copyWith(nodeType: newNodeType);
  }

  /// Set an explicit privacy level (0/1/2). Persisted so the choice
  /// survives app restarts.
  Future<void> setBalancePrivacy(int level) async {
    final clamped = level % 3;
    final box = await Hive.openBox('settings');
    await box.put('balancePrivacy', clamped);
    state = state.copyWith(balancePrivacy: clamped);
  }

  /// Advance the home balance privacy cycle by one step:
  /// 0 (all visible) → 1 (balance hidden) → 2 (balance + tx values
  /// hidden) → back to 0. Called when the user taps the headline
  /// balance.
  Future<void> cycleBalancePrivacy() async {
    await setBalancePrivacy(state.balancePrivacy + 1);
  }

  /// Compatibility shim for older call sites: reveal (level 0) or
  /// hide the balance (level 1).
  Future<void> setBalanceVisible(bool balanceVisible) async {
    await setBalancePrivacy(balanceVisible ? 0 : 1);
  }

  Future<void> setMascotEnabled(bool enabled) async {
    final box = await Hive.openBox('settings');
    await box.put('mascotEnabled', enabled);
    state = state.copyWith(mascotEnabled: enabled);
  }

  Future<void> setSoundEnabled(bool enabled) async {
    final box = await Hive.openBox('settings');
    await box.put('soundEnabled', enabled);
    state = state.copyWith(soundEnabled: enabled);
  }

  Future<void> setSignerEnabled(bool enabled) async {
    final box = await Hive.openBox('settings');
    await box.put('signerEnabled', enabled);
    state = state.copyWith(signerEnabled: enabled);
  }

  Future<void> setReviewDone(bool hasBeenReviewed) async {
    await _secureStorage.write(
      key: 'reviewDone',
      value: hasBeenReviewed.toString(),
    );
    state = state.copyWith(reviewDone: hasBeenReviewed);
  }

  Future<void> setAffiliateCode(String code) async {
    final box = await Hive.openBox('settings');
    await box.put('affiliateCode', code);
    state = state.copyWith(affiliateCode: code);
  }

  Future<void> setFullAccount(bool enabled) async {
    final box = await Hive.openBox('settings');
    await box.put('fullAccount', enabled);
    state = state.copyWith(fullAccount: enabled);
  }

  Future<void> setKycCompleted(bool completed) async {
    final box = await Hive.openBox('settings');
    await box.put('kycCompleted', completed);
    state = state.copyWith(kycCompleted: completed);
  }

  Future<void> setCountry(String countryCode) async {
    final box = await Hive.openBox('settings');
    await box.put('country', countryCode);
    state = state.copyWith(country: countryCode);
  }

  Future<void> setPremium(bool premium) async {
    final box = await Hive.openBox('settings');
    await box.put('isPremium', premium);
    state = state.copyWith(isPremium: premium);
  }

  Future<void> setSimpleMode(bool enabled) async {
    final box = await Hive.openBox('settings');
    await box.put('simpleMode', enabled);
    state = state.copyWith(simpleMode: enabled);
  }
}
