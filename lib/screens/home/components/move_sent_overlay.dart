// lib/screens/home/components/move_sent_overlay.dart
//
// Confirmation shown after a move between the user's own accounts.
// [note] is the caller's pending line (e.g. that Bitcoin is still
// arriving) and is shown under the message when present.

import 'package:flutter/material.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/services/tracking_service.dart';

void pushMoveSentOverlay({
  required NavigatorState navigator,
  required String amount,
  required String fromWalletName,
  required String toWalletName,
  required String assetIconAsset,
  String? note,
}) {
  TrackingService.screenView('move_sent_overlay');
  pushKuteSuccessOverlay(
    navigator: navigator,
    overlay: MoveSentOverlay(
      amount: amount,
      fromWalletName: fromWalletName,
      toWalletName: toWalletName,
      assetIconAsset: assetIconAsset,
      note: note,
    ),
  );
}

class MoveSentOverlay extends StatelessWidget {
  final String amount;
  final String fromWalletName;
  final String toWalletName;
  final String assetIconAsset;
  final String? note;

  const MoveSentOverlay({
    super.key,
    required this.amount,
    required this.fromWalletName,
    required this.toWalletName,
    required this.assetIconAsset,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return KuteSuccessOverlay(
      headlineLabel: context.l10n.confirmationSentToWallet(toWalletName),
      detail: note,
    );
  }
}
