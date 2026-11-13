// lib/screens/shared/receipt_bar.dart
//
// THE BAR ON A RECEIPT (founder, 1 November 2026): a receipt or detail
// sheet draws no button of its own and no Sal circle. Its one action
// (View on blockchain, View market, Track exchange, Retry) is the
// floating bar's primary button ([ReceiptBarButton]), and Sal is the bar:
// "What happened here?" ([receiptBarContext]), or a long press on the
// receipt's button, opens the Sal sheet already asking about the receipt
// with its public context.

import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/advisor_context.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';

/// What the bar is on a receipt (founder, 31 October 2026: the bar
/// explains the receipt; 1 November 2026: the bar is the ONE way into
/// Sal, no circle on the sheet): "What happened here?", tapping sends the
/// receipt question to Sal with the receipt's public [advisorSurface]
/// (only the surface name ever leaves the device: never an address, id,
/// label, counterparty or amount). On a receipt with its own button
/// ([ReceiptBarButton]) the bar is that button and a long press asks
/// this.
KuteBarContext receiptBarContext(BuildContext context,
        {String? advisorSurface}) =>
    KuteBarContext(
      label: context.l10n.barReceiptLabel,
      sublabel: context.l10n.barAskSalSub,
      clip: 'curious',
      question: context.l10n.barReceiptQuestion,
      source: 'receipt',
      advisorContext: advisorSurface == null
          ? null
          : AdvisorContext(surface: advisorSurface),
    );

/// A receipt's one action (View on blockchain, View market, Track
/// exchange) as THE BAR (founder, 1 November 2026: the sheet's own
/// outlined button sat under the floating bar): the floating bar's
/// primary button with [label] and the handler the drawn button had,
/// off while [onPressed] is null; here only the room that keeps the
/// sheet's last rows scrollable clear of the bar
/// ([kuteBarScrollClearance]). A long press asks Sal about the receipt
/// ([receiptBarContext], held by [TransactionDetailHeader]).
class ReceiptBarButton extends StatelessWidget {
  const ReceiptBarButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.source = 'receipt',
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  /// The `search_opened` source of the bar's long press.
  final String source;

  @override
  Widget build(BuildContext context) => KuteBarContextScope(
        barContext: KuteBarContext.primary(
          label: label,
          onPrimary: onPressed,
          enabled: onPressed != null,
          busy: busy,
          clip: 'idle',
          source: source,
          // Never waits on input: off only while the action runs.
          disabledLabel: null,
        ),
        child: SizedBox(height: kuteBarScrollClearance.h),
      );
}
