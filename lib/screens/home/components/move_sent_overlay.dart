// lib/screens/home/components/move_sent_overlay.dart
//
// Result sheet shown after a move between the user's own accounts: the
// amount as the hero, where it came from as a row, and [note], the
// caller's pending line (a conversion still running, a transfer still
// registering), under it.

import 'package:flutter/material.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/services/tracking_service.dart';

/// [swapped]: the move came from Swap, the two-way screen between the
/// person's own Bitcoin and Dollars, and reads "Swapped to …".
void pushMoveSentOverlay({
  required NavigatorState navigator,
  required String amount,
  required String fromWalletName,
  required String toWalletName,
  String? note,
  bool swapped = false,
}) {
  TrackingService.screenView('move_sent_overlay');
  pushKuteSuccessOverlay(
    navigator: navigator,
    overlay: MoveSentOverlay(
      amount: amount,
      fromWalletName: fromWalletName,
      toWalletName: toWalletName,
      note: note,
      swapped: swapped,
    ),
  );
}

class MoveSentOverlay extends StatelessWidget {
  final String amount;
  final String fromWalletName;
  final String toWalletName;
  final String? note;

  const MoveSentOverlay({
    super.key,
    required this.amount,
    required this.fromWalletName,
    required this.toWalletName,
    this.note,
    this.swapped = false,
  });

  /// Swap's own word for it ("Swapped to Dollars"; founder, 7 November
  /// 2026, the screen is "Swap").
  final bool swapped;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return KuteConfirmation(
      // The person's own money moved between their accounts: "Moved to
      // Dollars", never "Bought" (founder, 7 November 2026).
      message: swapped
          ? l10n.confirmationSwappedToWallet(toWalletName)
          : l10n.confirmationMovedToWallet(toWalletName),
      amount: amount.isEmpty ? null : amount,
      rows: {l10n.from: fromWalletName},
      detail: note,
      onDone: () => Navigator.of(context).pop(),
    );
  }
}
