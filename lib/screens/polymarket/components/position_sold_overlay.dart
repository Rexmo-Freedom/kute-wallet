import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
// lib/screens/polymarket/components/position_sold_overlay.dart
//
// Confirmation shown after a position is sold. The sale itself is done
// when this is pushed (the sell sheet waits for the trade to be mined), so
// the check shows straight away. The proceeds are the venue's own figures;
// when it gave none the receipt shows the shares alone. When a
// conversion back to Bitcoin is still running ([conversionFuture]), a
// small pending line says so until it resolves. The conversion runs on
// the trading notifier and keeps going if the user dismisses.

import 'package:flutter/material.dart';
import 'package:kute/screens/shared/trade_receipt.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/services/tracking_service.dart';

void pushPositionSoldOverlay({
  required NavigatorState navigator,
  required String marketQuestion,
  String? marketImage,
  required String outcome,
  required double shares,
  required double? proceeds,
  double? avgSellPrice,
  required double? pnl,
  String? note,
  Future<void>? conversionFuture,
}) {
  pushKuteSuccessOverlay(
    navigator: navigator,
    overlay: PositionSoldOverlay(
      marketQuestion: marketQuestion,
      marketImage: marketImage,
      outcome: outcome,
      shares: shares,
      proceeds: proceeds,
      avgSellPrice: avgSellPrice,
      pnl: pnl,
      note: note,
      conversionFuture: conversionFuture,
    ),
  );
}

class PositionSoldOverlay extends StatefulWidget {
  final String marketQuestion;
  final String? marketImage;
  final String outcome;
  final double shares;
  final double? proceeds;
  final double? avgSellPrice;
  final double? pnl;

  /// A quiet line under the check ("Settling on the network…").
  final String? note;

  /// While unresolved the confirmation shows the pending routing line.
  /// Null means no conversion is in flight.
  final Future<void>? conversionFuture;

  const PositionSoldOverlay({
    super.key,
    required this.marketQuestion,
    this.marketImage,
    required this.outcome,
    required this.shares,
    required this.proceeds,
    this.avgSellPrice,
    required this.pnl,
    this.note,
    this.conversionFuture,
  });

  @override
  State<PositionSoldOverlay> createState() => _PositionSoldOverlayState();
}

class _PositionSoldOverlayState extends State<PositionSoldOverlay> {
  bool _converting = false;

  @override
  void initState() {
    super.initState();
    TrackingService.screenView('prediction_sold_overlay');
    final conversion = widget.conversionFuture;
    if (conversion != null) {
      _converting = true;
      conversion.then((_) {
        if (mounted) setState(() => _converting = false);
      }).catchError((_) {
        // If the conversion fails the proceeds stay safely in the
        // Predictions balance, so drop the pending line regardless.
        if (mounted) setState(() => _converting = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return KuteConfirmation(
      message: context.l10n.betPositionSold,
      showCloseButton: true,
      onDone: () => Navigator.of(context).pop(),
      detail:
          _converting ? context.l10n.betRoutingToBitcoinWallet : widget.note,
      receipt: TradeReceipt(
          leading: PolyReceiptArtwork(url: widget.marketImage),
          title: widget.marketQuestion,
          subtitle: widget.outcome,
          rows: {
            context.l10n.betShares: widget.shares.toStringAsFixed(2),
            if (widget.proceeds case final proceeds?)
              context.l10n.betSaleProceeds: '\$${proceeds.toStringAsFixed(2)}',
            if (widget.pnl case final pnl?)
              context.l10n.betSaleReturn:
                  '≈ ${pnl >= 0 ? '+' : '−'}\$${pnl.abs().toStringAsFixed(2)}',
          }),
    );
  }
}
