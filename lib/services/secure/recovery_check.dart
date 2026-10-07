import 'dart:isolate';

import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/services/evm_wallet_derivation.dart';

import 'package:kute/models/auth_model.dart';
import 'package:kute/models/settings_model.dart';

/// The public recovery check address matches a re-entered recovery phrase
/// to an existing wallet id without storing anything secret.
///
/// It is the index 0 EVM address for the wallet’s persisted derivation
/// version, with no extra BIP39 passphrase. It is used only for matching:
/// never tracked, logged or sent anywhere.
abstract final class RecoveryCheck {
  static String normalize(String phrase) =>
      phrase.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');

  static String deriveSync(String mnemonic, {
    EvmDerivationVersion version = EvmDerivationVersion.legacySha256,
  }) => EvmWalletDerivation.deriveWallet(
      mnemonic: normalize(mnemonic), version: version, index: 0).address;

  /// Derives off the UI isolate.
  static Future<String> derive(String mnemonic, {
    EvmDerivationVersion version = EvmDerivationVersion.legacySha256,
  }) => Isolate.run(() => deriveSync(mnemonic, version: version));

  static bool matches(String stored, String derived) =>
      stored.toLowerCase() == derived.toLowerCase();

  /// Wallets whose seed Kute stores (not passkey, hardware, watch-only or
  /// external address).
  static bool holdsStoredSeed(WalletConfig wallet) =>
      !wallet.isPasskey &&
      !wallet.isHardware &&
      !wallet.isWatchOnly &&
      !wallet.isExternalAddress;

  /// Stores the address for [walletId] when it has none. Best effort.
  static Future<void> record(
    SettingsModel settings,
    String walletId,
    String mnemonic, {
    Future<String> Function(String mnemonic)? deriveAddress,
  }) async {
    try {
      final wallet = settings.walletById(walletId);
      if (wallet == null) return;
      final address = await (deriveAddress?.call(mnemonic) ??
          derive(mnemonic, version: wallet.evmDerivationVersion));
      await settings.setRecoveryCheckAddress(walletId, address);
    } catch (_) {}
  }

  /// Fills in the address for stored-seed wallets created before it
  /// existed. Runs after an unlock with that [session]; it never triggers
  /// a passkey ceremony and reads nothing while the session is locked.
  static Future<void> backfill({
    required SettingsModel settings,
    required List<WalletConfig> wallets,
    required AuthModel auth,
    required SeedSession session,
    Future<String> Function(String mnemonic)? deriveAddress,
  }) async {
    for (final wallet in wallets) {
      if (!holdsStoredSeed(wallet) || wallet.recoveryCheckAddress != null) {
        continue;
      }
      try {
        final mnemonic = await auth.getMnemonic(wallet.id,
            access: SeedAccess.automatic, session: session);
        if (mnemonic == null) continue;
        await record(settings, wallet.id, mnemonic,
            deriveAddress: deriveAddress);
      } catch (_) {}
    }
  }
}
