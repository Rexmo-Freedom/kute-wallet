import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';

/// A recovery-phrase reminder belongs to the wallet that owns the words.
/// Passkey accounts recover through their passkey and never get this prompt.
bool needsWalletBackup(WalletConfig wallet) =>
    (wallet.isSparkWallet || wallet.isBitcoinSoftware) &&
    !wallet.isPasskey &&
    !wallet.backedUp;

/// Home and its global menu only remind about the spending account.
/// Separate Bitcoin wallets show their reminder on their own detail screen.
final pendingSpendingWalletBackupProvider = Provider<WalletConfig?>((ref) {
  final settings = ref.watch(settingsProvider);
  return settings.wallets
      .where((wallet) => wallet.isSparkWallet && needsWalletBackup(wallet))
      .firstOrNull;
});

/// Explicit requests fail closed if that wallet was removed or cannot reveal
/// a seed. An unscoped legacy entry point can only resolve a spending wallet;
/// it must never pick an unrelated Bitcoin wallet from the list.
WalletConfig? resolveBackupWalletTarget(Settings settings, {String? walletId}) {
  if (walletId != null) {
    final wallet =
        settings.wallets.where((wallet) => wallet.id == walletId).firstOrNull;
    return wallet != null && (wallet.isSparkWallet || wallet.isBitcoinSoftware)
        ? wallet
        : null;
  }

  final spendingWallets = settings.wallets
      .where((wallet) => wallet.isSparkWallet && !wallet.isPasskey);
  return spendingWallets.where(needsWalletBackup).firstOrNull ??
      spendingWallets
          .where((wallet) => wallet.id == settings.activeWalletId)
          .firstOrNull ??
      spendingWallets.firstOrNull;
}
