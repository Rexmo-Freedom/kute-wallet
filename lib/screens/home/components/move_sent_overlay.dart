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

void pushMoveSentOverlay({
  required NavigatorState navigator,
  required String amount,
  required String fromWalletName,
  required String toWalletName,
  String? note,
}) {
  TrackingService.screenView('move_sent_overlay');
  pushKuteSuccessOverlay(
    navigator: navigator,
    overlay: MoveSentOverlay(
      amount: amount,
      fromWalletName: fromWalletName,
      toWalletName: toWalletName,
      note: note,
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
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return KuteConfirmation(
      message: l10n.confirmationSentToWallet(toWalletName),
      amount: amount.isEmpty ? null : amount,
      rows: {l10n.from: fromWalletName},
      detail: note,
      onDone: () => Navigator.of(context).pop(),
    );
  }
}
