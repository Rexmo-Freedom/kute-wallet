import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/passkey_service.dart';

/// A recovery-phrase reminder belongs to the wallet that owns the words.
/// Legacy (pre-2.x) passkey wallets show it while `backedUp` is false (the
/// one-shot 2026-08 migration flips it so their owners write the words
/// down; the reveal derives them the 0.15.1 way). A passkey wallet on the
/// current SDK is backed up once its label is on the relay (creation
/// flips `backedUp` when the publish lands); until then, or while its
/// label is still flagged pending, it is not discoverable on another
/// device and the same reminder shows (see [needsPasskeyLabelPublish]).
/// [pendingLabels] defaults to the pending set held in memory.
bool needsWalletBackup(WalletConfig wallet, {Set<String>? pendingLabels}) =>
    (wallet.isSparkWallet || wallet.isBitcoinSoftware) &&
    (!wallet.backedUp ||
        needsPasskeyLabelPublish(wallet, pendingLabels: pendingLabels));

/// A current-SDK passkey wallet whose label is not confirmed on the relay:
/// still flagged pending, or never marked published. Its reminder runs one
/// passkey confirmation that publishes the label
/// (`PasskeyService.finishLabelBackup`), not the recovery-phrase reveal.
bool needsPasskeyLabelPublish(WalletConfig wallet,
    {Set<String>? pendingLabels}) {
  final label = wallet.passkeyLabel;
  if (!wallet.isPasskey || wallet.passkeyProvider == null || label == null) {
    return false;
  }
  return !wallet.backedUp ||
      (pendingLabels ?? PasskeyService.pendingLabelsNow).contains(label);
}

/// The passkey labels this device has not confirmed as published, kept in
/// step with `PasskeyService.pendingLabels` so the reminder follows them.
final passkeyPendingLabelsProvider = Provider<Set<String>>((ref) {
  final pending = PasskeyService.pendingLabels;
  void changed() => ref.invalidateSelf();
  pending.addListener(changed);
  ref.onDispose(() => pending.removeListener(changed));
  return pending.value;
});

/// The passkey reminder's action. A provider so tests can stand in for the
/// OS ceremony.
final passkeyLabelBackupRunnerProvider = Provider<
    Future<PasskeyLabelBackupResult> Function(String label,
        {required String surface})>((ref) => PasskeyService.finishLabelBackup);

/// Home and its global menu only remind about the spending account.
/// Separate Bitcoin wallets show their reminder on their own detail screen.
final pendingSpendingWalletBackupProvider = Provider<WalletConfig?>((ref) {
  final settings = ref.watch(settingsProvider);
  final pending = ref.watch(passkeyPendingLabelsProvider);
  return settings.wallets
      .where((wallet) =>
          wallet.isSparkWallet &&
          needsWalletBackup(wallet, pendingLabels: pending))
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
