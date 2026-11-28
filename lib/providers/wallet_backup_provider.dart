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
      (pendingLabels ?? PasskeyService.allPendingLabelsNow).contains(label);
}

/// The passkey labels this device has not confirmed as published, in
/// either passkey home, kept in step with both homes' pending sets so the
/// reminder follows them. With no Kute-home wallet this is exactly the
/// Breez set it always was.
final passkeyPendingLabelsProvider = Provider<Set<String>>((ref) {
  final pending = [
    PasskeyService.pendingLabels,
    PasskeyService.kute.pendingLabels,
  ];
  void changed() => ref.invalidateSelf();
  for (final p in pending) {
    p.addListener(changed);
  }
  ref.onDispose(() {
    for (final p in pending) {
      p.removeListener(changed);
    }
  });
  return PasskeyService.allPendingLabelsNow;
});

/// The passkey reminder's action. A provider so tests can stand in for the
/// OS ceremony. Routed on the marker of the wallet(s) carrying the label:
/// Kute-home wallets publish through Kute's identity, every other passkey
/// wallet through the Breez home exactly as before. A label carried by
/// wallets of both homes, or by a wallet with an unknown marker, runs no
/// ceremony and reports a failure (its reminder stays).
final passkeyLabelBackupRunnerProvider = Provider<
    Future<PasskeyLabelBackupResult> Function(String label,
        {required String surface})>((ref) {
  return (String label, {required String surface}) async {
    var kute = false;
    var other = false;
    for (final w in ref.read(settingsProvider).wallets) {
      if (!w.isPasskey || w.passkeyLabel != label) continue;
      final PasskeyRoute route;
      try {
        route = PasskeyHomes.routeFor(w.passkeyProvider);
      } catch (_) {
        return const PasskeyLabelBackupResult(
            succeeded: false, cancelled: false, republished: 0);
      }
      if (route == PasskeyRoute.kute) {
        kute = true;
      } else {
        other = true;
      }
    }
    if (kute && other) {
      return const PasskeyLabelBackupResult(
          succeeded: false, cancelled: false, republished: 0);
    }
    return kute
        ? PasskeyService.kute.finishLabelBackup(label, surface: surface)
        : PasskeyService.finishLabelBackup(label, surface: surface);
  };
});

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
