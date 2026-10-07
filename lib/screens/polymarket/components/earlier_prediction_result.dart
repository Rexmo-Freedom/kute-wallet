// The answer the slip gives when a prediction could not be sent because an
// earlier one on the account was still unaccounted for, and the way to ask
// again from that screen.
//
// It used to say "A previous prediction is still being confirmed. Check
// its status before placing another." with nothing on the screen that
// checks it, cut off after two lines, and the next tap got the same
// screen. Now the result carries a "Check prediction status" button that
// runs the same read-only check (the order journal against the venue) and
// shows what it found. Nothing here signs or sends an order.

import 'package:flutter/material.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/services/polymarket/hot_order_guard.dart';

/// What a check of the earlier prediction found: the line to show, and
/// whether the venue's answer settled it ([read]).
typedef EarlierPredictionCheck = ({String message, bool read});

/// Reads the earlier submission for [tokenId] against the venue (never
/// sends anything) and says what came of it.
Future<EarlierPredictionCheck> checkEarlierPrediction(
  PolymarketTradingNotifier notifier,
  String? tokenId,
  AppLocalizations l10n,
) async {
  try {
    await notifier.checkPendingOrder(tokenId: tokenId);
    return (message: l10n.betPreviousOrderChecked, read: true);
  } on ResolvedPolymarketOrder {
    return (message: l10n.betPreviousOrderChecked, read: true);
  } on PolymarketOrderCheckUnavailable {
    // The venue never answered. The earlier row keeps protecting the
    // account, but the person hears about the connection.
    return (message: l10n.betConnectionUnavailable, read: false);
  } on PolymarketOrderInProgress {
    // Still being placed in this app: not an unknown submission.
    return (message: l10n.betPreviousStillPlacing, read: false);
  } catch (_) {
    // Keep uncertain submissions protected.
    return (message: l10n.ledgerBetPending, read: false);
  }
}

/// The shared confirmation screen with the check's answer. While the
/// answer is not settled it offers the check again.
class EarlierPredictionResult extends StatefulWidget {
  const EarlierPredictionResult({
    super.key,
    required this.message,
    required this.success,
    required this.onDone,
    required this.recheck,
  });

  final String message;
  final bool success;
  final VoidCallback onDone;
  final Future<EarlierPredictionCheck> Function() recheck;

  @override
  State<EarlierPredictionResult> createState() =>
      _EarlierPredictionResultState();
}

class _EarlierPredictionResultState extends State<EarlierPredictionResult> {
  late String _message = widget.message;
  late bool _success = widget.success;
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    final result = await widget.recheck();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _message = result.message;
      _success = result.read;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return KuteConfirmation(
      message: _message,
      success: _success,
      showCloseButton: true,
      buttonText: l10n.done,
      onDone: widget.onDone,
      secondaryButtonText: _success
          ? null
          : (_checking ? l10n.loading : l10n.ledgerBetCheckStatus),
      onSecondary: _success ? null : _check,
    );
  }
}
