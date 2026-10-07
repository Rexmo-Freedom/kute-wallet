// lib/screens/shared/wallet_removal_step_up.dart
//
// Wallet removal approvals (Wallet Hardening Phase 1b, D-9 and D-15).
//
//   * A wallet that holds recovery words on this phone and is not backed
//     up gets one extra confirmation before the usual final confirmation.
//     "Back up first" sends the user to the backup flow instead.
//   * The final confirmation asks for a fresh biometric or Kute PIN
//     approval bound to the wallet, consumed right before removal.
//
// Events: `wallet_remove_unbacked_confirm{result}` here; the step-up
// events come from `requireFreshAuthGrant`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/screens/shared/custom_alert_dialog.dart';
import 'package:kute/services/tracking_service.dart';

/// Whether removing [wallet] could delete the only copy of its words: it
/// holds recovery words on this phone and is not backed up. Hardware,
/// watch-only and tracked-address wallets hold no words, and passkey
/// wallets on the current SDK are recovered with the passkey (the same
/// rule the backup banner uses).
bool walletRemovalNeedsBackupWarning(WalletConfig wallet) =>
    !wallet.backedUp &&
    !wallet.isHardware &&
    !wallet.isWatchOnly &&
    !wallet.isExternalAddress &&
    (!wallet.isPasskey || wallet.passkeyProvider == null);

enum UnbackedRemovalChoice { removeAnyway, backUpFirst, cancelled }

/// D-15. The extra confirmation for a wallet that is not backed up.
/// Emits `wallet_remove_unbacked_confirm{result}`. The caller opens the
/// backup flow on [UnbackedRemovalChoice.backUpFirst].
Future<UnbackedRemovalChoice> confirmUnbackedWalletRemoval(
  BuildContext context,
) async {
  var choice = UnbackedRemovalChoice.cancelled;
  final l10n = context.l10n;
  // showDialog uses the root navigator, so the buttons pop that one.
  final navigator = Navigator.of(context, rootNavigator: true);
  await showCustomAlertDialog(
    context: context,
    title: l10n.removeWalletNotBackedUpTitle,
    content: l10n.removeWalletNotBackedUpBody,
    buttons: [
      CustomAlertAction(
        text: l10n.removeWalletBackUpFirst,
        onPressed: () {
          choice = UnbackedRemovalChoice.backUpFirst;
          navigator.pop();
        },
      ),
      CustomAlertAction.destructive(
        text: l10n.removeWalletAnyway,
        onPressed: () {
          choice = UnbackedRemovalChoice.removeAnyway;
          navigator.pop();
        },
      ),
      CustomAlertAction.secondary(
        text: l10n.cancel,
        onPressed: () => navigator.pop(),
      ),
    ],
  );
  TrackingService.track('wallet_remove_unbacked_confirm', params: {
    'result': switch (choice) {
      UnbackedRemovalChoice.removeAnyway => 'remove_anyway',
      UnbackedRemovalChoice.backUpFirst => 'back_up_first',
      UnbackedRemovalChoice.cancelled => 'cancelled',
    },
  });
  return choice;
}

/// D-9. Fresh biometric or Kute PIN approval for removing [walletId],
/// consumed at once. Call it right before removing. True only when the
/// user approved.
Future<bool> approveWalletRemoval(
  BuildContext context,
  WidgetRef ref,
  String walletId,
) {
  return approveLocalAction(
    context,
    ref,
    intent: walletRemoveIntent(walletId),
    reason: context.l10n.stepUpReasonRemoveWallet,
  );
}
