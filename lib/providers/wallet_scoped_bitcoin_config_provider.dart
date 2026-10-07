// lib/providers/wallet_scoped_bitcoin_config_provider.dart
//
// Wallet-keyed counterparts to the legacy `bitcoinConfigProvider` &
// friends. The legacy providers read `settingsProvider.activeWallet`
// and therefore tightly couple every BDK-derived operation to whatever
// page the user is currently parked on in the home carousel — a
// problem when the user wants to derive a hardware wallet's address
// while staying on the spending wallet (e.g. picking that hardware
// wallet inside Send / Receive / Deposit pickers without flipping the
// carousel).
//
// These `family` providers take an explicit `walletId` and do the same
// work scoped to that wallet. The legacy providers in
// `bitcoin_config_provider.dart` are kept as thin shims that forward
// to the family using `settings.activeWalletId` for backward compat.
//
// Spark SDK is intentionally NOT wallet-keyed — Breez Spark is a
// singleton and stays bound to the spending wallet. The family
// providers here only cover the BDK side (descriptors, native sessions,
// wallet restore, address peek). Address derivation for the spending
// wallet still flows through Spark via `addressProvider`; the family
// is the right tool for hardware / watch-only wallets.

import 'dart:async';

import 'package:kute/services/onchain/esplora_fallback.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';
import 'package:kute/services/onchain/native_bitcoin_primitives.dart';
// ignore: unused_import
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as spark;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/bitcoin_config_model.dart';
import 'package:kute/models/bitcoin_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/address_provider.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/passkey_service.dart';

/// Per-wallet `BitcoinConfig`. Mirrors the body of the legacy
/// `bitcoinConfigProvider` but reads the wallet from
/// `settings.wallets` by id instead of `settings.activeWallet`.
final bitcoinConfigForWalletProvider =
    FutureProvider.family<BitcoinConfig, String>((ref, walletId) async {
  final settings = ref.watch(settingsProvider);
  final wallet = settings.wallets.firstWhere(
    (w) => w.id == walletId,
    orElse: () => throw Exception('Wallet not found: $walletId'),
  );

  if (wallet.isExternalAddress) {
    throw Exception('External address wallets do not use BDK');
  }

  String? mnemonic;
  String? xpub;

  if (wallet.isPasskey) {
    // Resolution order replicates 0.15.1: the wallet's own stored
    // label first, then the cached-label fallback — so a legacy wallet
    // resolves the exact PRF salt it was created with.
    final label =
        wallet.passkeyLabel ?? await PasskeyService.getCachedLabel();
    // VINTAGE ROUTING (funds safety): `passkeyProvider == null` marks a
    // pre-2.x wallet whose seed only reconstructs via the app's own PRF
    // pipeline. Routing it through the new SDK's signIn could resolve a
    // DIFFERENT credential on the shared RP and derive descriptors for
    // a wallet that isn't the user's. FAIL CLOSED: a legacy-path error
    // propagates — never fall through to the new derivation.
    final spark.Seed seed = wallet.passkeyProvider == null
        ? await PasskeyService.getLegacySeed(label: label)
        : (await PasskeyService.getWallet(label: label, legacy: false)).seed;
    mnemonic = switch (seed) {
      spark.Seed_Mnemonic(:final mnemonic) => mnemonic,
      // Passkey PRF-derived wallets ship as `Seed_Entropy(bytes)`.
      // Convert to BIP39 via BDK so `BitcoinConfig` downstream gets
      // real words for descriptor build. Earlier code threw on this
      // variant, which left passkey wallets unable to derive their
      // own BTC receive address or sign on-chain sends.
      spark.Seed_Entropy(:final field0) =>
        await NativeBitcoinPrimitives.instance.mnemonicFromEntropy(field0),
    };
  } else {
    // Behind the lock the xpub path is used, and the config builds again
    // once the session unlocks.
    if (!wallet.isWatchOnly) watchSessionUnlock(ref);
    final authModel = ref.read(authModelProvider);
    final read = await authModel.readMnemonic(wallet.id,
        access: SeedAccess.automatic, session: ref.read(seedSessionProvider));
    mnemonic = read is SeedOk ? read.value : null;
    xpub = mnemonic == null
        ? await authModel.getExtendedPublicKey(wallet.id)
        : null;
  }

  if ((mnemonic?.isEmpty ?? true) && (xpub?.isEmpty ?? true)) {
    throw Exception('No valid credentials found for wallet ID: ${wallet.id}');
  }

  Network network = Network.bitcoin;
  if (xpub != null) {
    final lower = xpub.toLowerCase();
    if (lower.startsWith('tpub') ||
        lower.startsWith('vpub') ||
        lower.startsWith('upub')) {
      network = Network.testnet;
    }
  }

  return BitcoinConfig(
    walletId: wallet.id,
    mnemonic: mnemonic,
    xpub: xpub,
    network: network,
    externalKeychain: KeychainKind.external_,
    internalKeychain: KeychainKind.internal,
    isElectrumBlockchain: true,
    // The configured host, or its public twin while the configured one
    // is known to be unreachable (see EsploraFallback).
    electrumUrl: ref
        .watch(esploraFallbackProvider)
        .effectiveUrl(settings.bitcoinElectrumNode),
    scriptType: wallet.scriptType,
    mnemonicScriptType: wallet.walletType == 'bitcoin' ? wallet.scriptType : null,
    masterFingerprint: wallet.masterFingerprint,
    isPasskey: wallet.isPasskey,
  );
});

final createInternalDescriptorForWalletProvider =
    FutureProvider.family<String, String>((ref, walletId) {
  return ref
      .watch(bitcoinConfigForWalletProvider(walletId).future)
      .then((config) => BitcoinConfigModel(config).createInternalDescriptor());
});

final createExternalDescriptorForWalletProvider =
    FutureProvider.family<String, String>((ref, walletId) {
  return ref
      .watch(bitcoinConfigForWalletProvider(walletId).future)
      .then((config) => BitcoinConfigModel(config).createExternalDescriptor());
});

/// The fallback state, watched so a recorded failure rebuilds the configs.
final esploraFallbackProvider =
    ChangeNotifierProvider<EsploraFallback>((_) => EsploraFallback.instance);

final restoreWalletForWalletProvider =
    FutureProvider.family<NativeWalletSession, String>((ref, walletId) {
  return ref
      .watch(bitcoinConfigForWalletProvider(walletId).future)
      .then((config) async {
    final externalDescriptor = await ref
        .watch(createExternalDescriptorForWalletProvider(walletId).future);
    final internalDescriptor = await ref
        .watch(createInternalDescriptorForWalletProvider(walletId).future);
    return BitcoinConfigModel(config)
        .restoreWallet(externalDescriptor, internalDescriptor);
  });
});

/// Per-walletId BitcoinModel. Mirrors `bitcoinModelProvider` but
/// targets the explicit walletId — used by the per-wallet scan API
/// (`BackgroundSyncService.scanBdkScope`) so a hardware wallet can be
/// synced and rendered in its detail screen without flipping
/// `settings.activeWalletId`. The model is cached per id so repeat
/// scans on the same wallet reuse the BDK `Wallet` + `Persister`
/// (SQLite reopen is the dominant cost otherwise).
final bitcoinForWalletProvider =
    FutureProvider.family<Bitcoin, String>((ref, walletId) async {
  final session = await ref.watch(restoreWalletForWalletProvider(walletId).future);
  final config = await ref.read(bitcoinConfigForWalletProvider(walletId).future);
  // Only a successfully persisted full scan sets the firstScanDone flag.
  bool firstScanDone = false;
  for (final w in ref.read(settingsProvider).wallets) {
    if (w.id == walletId) {
      firstScanDone = w.firstScanDone;
      break;
    }
  }
  return Bitcoin(session, config.network,
      needsFullScan: session.needsInitialScan || !firstScanDone,
      electrumUrl: config.electrumUrl);
});

final bitcoinModelForWalletProvider =
    FutureProvider.family<BitcoinModel, String>((ref, walletId) async {
  final bitcoin = await ref.watch(bitcoinForWalletProvider(walletId).future);
  return BitcoinModel(bitcoin);
});

/// In-memory cache for derived BDK addresses, scoped by wallet id.
///
/// Deriving is cheap in itself but needs the wallet's native slot, and
/// that slot is shared with scanning. On a wallet mid scan the Receive
/// screen could sit waiting for a gap, which is why it felt like it
/// never loaded. The address does not move until it is used, and
/// `nextUnusedAddress` is idempotent, so the last answer is safe to
/// show at once while a fresh one is fetched behind it.
///
/// Cleared by app restart, and by [invalidateWalletAddressCache] when a
/// wallet is removed or its descriptors change.
final _bdkAddressCache = <String, ({String address, int index})>{};

/// Returns the next-unused BTC receive address for any wallet in
/// `settings.wallets`, regardless of which wallet is currently active
/// in the carousel. Resolution order:
///   - External-address wallet → stored address from AuthModel
///   - Spending hot wallet (sparkEnabled, non-hardware/watch-only) →
///     `addressProvider.bitcoinAddress` (Spark's own derivation,
///     populated on app start). Only meaningful for the wallet that
///     Spark is bound to (the spending wallet).
///   - BDK hardware / watch-only / non-spark hot wallet → load the
///     BDK wallet via the family providers and `nextUnusedAddress`
///     on the external keychain.
///
/// IMPORTANT: this provider used to call `revealNextAddress` +
/// `persist`, which advances BDK's keychain pointer on every call.
/// Combined with the blanket `ref.invalidate(walletAddressProvider)`
/// on receive-screen mount, that meant each tap of "Receive" burned
/// a fresh derivation index and showed the user a different address.
///
/// `nextUnusedAddress` is idempotent: it returns the next address
/// whose scriptPubKey hasn't been used on-chain yet, and subsequent
/// calls return the SAME address until that scriptPubKey actually
/// receives funds. After a full-scan / Electrum sync it correctly
/// skips past every used scriptPubKey from history, so imported
/// wallets get a clean unused address rather than the most-reused
/// `peekAddress(0)`.
///
/// Native persists revealed keychain state before returning the address.
final walletAddressProvider =
    FutureProvider.family<String, String>((ref, walletId) async {
  final settings = ref.watch(settingsProvider);
  final wallet = settings.wallets.firstWhere(
    (w) => w.id == walletId,
    orElse: () => throw Exception('Wallet not found: $walletId'),
  );

  if (wallet.isExternalAddress) {
    final stored = await AuthModel().getExternalAddress(wallet.id);
    return stored ?? '';
  }

  // Signers are air-gapped; no network address to display.
  if (wallet.isSigner) return '';

  final isSparkSpending = wallet.isSparkWallet;
  if (isSparkSpending) {
    // Spark SDK is bound to the spending wallet at app start and stays
    // bound regardless of which wallet the carousel is currently
    // parked on. So `addressProvider.bitcoinAddress` (or the
    // underlying `getSparkBitcoinAddressProvider`) returns the
    // spending wallet's BTC deposit address whether or not it's the
    // "active" wallet in settings. Earlier this resolver gated on
    // `wallet.id == settings.activeWalletId` and the spending wallet
    // wouldn't match when the user was parked on a hardware wallet —
    // the Move sheet's "savings BTC → spending BTC" path then handed
    // an empty string to the embedded `WatchOnlySigningScreen`, which
    // is what surfaced as the empty "To" row in the Jade Bluetooth
    // sign card. We try the active-wallet `addressProvider` cache
    // first (it's pre-warmed and doesn't burn an SDK round-trip);
    // fall back to a fresh SDK fetch if the active wallet is the
    // hardware one and `addressProvider.bitcoinAddress` therefore
    // points at the hardware's BDK address rather than this
    // spending wallet's Spark deposit address.
    if (wallet.id == settings.activeWalletId) {
      final addr = ref.watch(addressProvider).bitcoinAddress;
      if (addr.isNotEmpty) return addr;
    }
    try {
      final addr = await ref.read(getSparkBitcoinAddressProvider.future);
      if (addr.isNotEmpty) return addr;
    } catch (_) {}
    return '';
  }

  final info = await ref.watch(walletReceiveInfoProvider(walletId).future);
  return info.address;
});

/// Address + derivation index of the next unused receive address for a
/// hardware / watch-only wallet. Hardware verify flows need the
/// derivation index that BDK's `nextUnusedAddress` chose so the device's
/// on-screen verify step displays the SAME address that's on the QR.
///
/// Hardcoding `addressIndex = 0` in the verify call (as `_verifyOnLedger`
/// used to) silently mismatched whenever index 0's scriptPubKey had
/// already been used on-chain — `nextUnusedAddress` would jump to index
/// 1+ but the Ledger kept displaying index 0. Funds-loss-risk bug; this
/// provider is the single source of truth that both the QR and the
/// device-verify request read.
///
/// Returns `(address: '', index: 0)` for non-BDK wallets (Spark
/// spending, external-address only, signer-only) — callers that need
/// derivation info already gate on `wallet.isHardware`.
final walletReceiveInfoProvider = FutureProvider.family<
    ({String address, int index}), String>((ref, walletId) async {
  final settings = ref.watch(settingsProvider);
  final wallet = settings.wallets.firstWhere(
    (w) => w.id == walletId,
    orElse: () => throw Exception('Wallet not found: $walletId'),
  );

  // Non-BDK paths: surface the address only — index is irrelevant
  // because nothing in the verify flow runs against these wallets.
  if (wallet.isExternalAddress) {
    final stored = await AuthModel().getExternalAddress(wallet.id);
    return (address: stored ?? '', index: 0);
  }
  if (wallet.isSigner) return (address: '', index: 0);

  final isSparkSpending = wallet.isSparkWallet;
  if (isSparkSpending) {
    if (wallet.id == settings.activeWalletId) {
      final addr = ref.watch(addressProvider).bitcoinAddress;
      if (addr.isNotEmpty) return (address: addr, index: 0);
    }
    try {
      final addr = await ref.read(getSparkBitcoinAddressProvider.future);
      if (addr.isNotEmpty) return (address: addr, index: 0);
    } catch (_) {}
    return (address: '', index: 0);
  }

  // Show the last known address IMMEDIATELY. Everything below needs the
  // native slot, and on a wallet that is being scanned that wait is what
  // the user experiences as a screen that never loads.
  final cached = _bdkAddressCache[walletId];
  if (cached != null) {
    unawaited(_refreshBdkAddress(ref, walletId));
    return cached;
  }

  final model = await ref.watch(bitcoinModelForWalletProvider(walletId).future);
  // The first open of an imported wallet runs a full Electrum scan that
  // holds the wallet's native slot for minutes, and `_start` rejects any
  // other request with 'busy' while it runs. This provider is not
  // autoDispose, so that rejection used to stay cached and the Receive QR
  // shimmered until restart. Wait for the slot instead, and retry a
  // bounded number of times in case another request claims it first.
  final service = NativeOnchainService.instance;
  const maxAttempts = 5;
  // Each wait is bounded. An unbounded one never returned on a wallet
  // that is scanned regularly: the slot frees, a background scan takes
  // it again, and the address request waits for a gap that never comes.
  // The visible symptom was a Receive QR that shimmered forever after
  // switching away from a syncing wallet and back.
  //
  // On the deadline we simply ask anyway. A slot that really is busy
  // answers `busy`, which is retried below, and after the last attempt
  // the error surfaces so the screen can show it and offer a retry
  // instead of pretending to load.
  const slotWait = Duration(seconds: 4);
  for (var attempt = 1;; attempt++) {
    await service.whenIdle(walletId, timeout: slotWait);
    try {
      final info = await model.getNextUnusedAddress();
      final resolved = (address: info.address.toString(), index: info.index);
      _bdkAddressCache[walletId] = resolved;
      return resolved;
    } on OnchainException catch (error) {
      if (error.code != 'busy' || attempt >= maxAttempts) rethrow;
    }
  }
});

/// Re-derives [walletId]'s address in the background and updates the
/// cache when it moves, so a cached answer never goes stale for long.
/// Failures are silent on purpose: the screen already has an address.
Future<void> _refreshBdkAddress(Ref ref, String walletId) async {
  try {
    final model =
        await ref.read(bitcoinModelForWalletProvider(walletId).future);
    await NativeOnchainService.instance
        .whenIdle(walletId, timeout: const Duration(seconds: 6));
    final info = await model.getNextUnusedAddress();
    final resolved = (address: info.address.toString(), index: info.index);
    if (_bdkAddressCache[walletId] != resolved) {
      _bdkAddressCache[walletId] = resolved;
      ref.invalidateSelf();
    }
  } catch (_) {
    // The cached address stays on screen; nothing to tell the user.
  }
}

/// Picks the first hot (spending) wallet in `settings.wallets`. Used
/// by surfaces that need to operate against the spending wallet
/// regardless of which carousel page the user is currently parked on
/// (backup banner, Spark-only operations, etc.). Returns `null` if
/// the user has no hot wallets at all (rare — onboarding always
/// creates one).
WalletConfig? pickSpendingWallet(Settings settings) {
  for (final w in settings.wallets) {
    if (w.isSparkWallet) {
      return w;
    }
  }
  return null;
}
