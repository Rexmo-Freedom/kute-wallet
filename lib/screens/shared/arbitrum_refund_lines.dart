// lib/screens/shared/arbitrum_refund_lines.dart
//
// The quiet lines Investing shows for USDC returned on Arbitrum
// (arbitrum_refund_watch.dart): "$12.40 returned on Arbitrum", and under a
// refunded balance too small for a Bridge2 deposit the existing "Below the
// minimum to move". Words only, in the places that already carry quiet
// lines (the Investing header's detail, the Portfolio's Investing tile,
// a refunded CCTP move's Activity detail). Nothing when nothing is shown.
//
// No "Move to Investing" action: the wallet's address holds no gas on
// Arbitrum and Kute has no relayer to submit a gasless Bridge2 deposit for
// it (arbitrum_refund_watch.dart).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/arbitrum_refund_provider.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show sendShortAddress;
import 'package:kute/services/hyperliquid/arbitrum_refund_watch.dart';
import 'package:kute/services/orchestra_routes.dart'
    show orchestraChainDisplayName;
import 'package:kute/theme/app_theme.dart';

/// "$12.40 returned on Arbitrum" (and the below-the-minimum note) for
/// [state], or nothing while nothing is shown.
List<String> arbitrumRefundLines(AppLocalizations l10n,
    ArbitrumRefundState state, String Function(double usd) amount) {
  if (!state.shown) return const [];
  return [
    l10n.arbitrumRefundReturned(amount(state.usd)),
    if (state.belowMinimum) l10n.portfolioRebalanceBelowMinimum,
  ];
}

/// What became of an Investing move by CCTP whose Orchestra order was
/// refunded, in its Activity detail: its USDC went back to the wallet's own
/// address on Arbitrum ("Returned to 0x1234…abcd on Arbitrum", the
/// one-time receive's line), with the below-the-minimum note while what is
/// there is too little for a Bridge2 deposit. Nothing for any other row.
class CctpRefundOutcome extends ConsumerWidget {
  const CctpRefundOutcome({super.key, required this.row});

  final SwapOrder row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refund = row.refundAddress.trim();
    if (!isRefundedCctpMoveRow(row) || refund.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final note =
        TextStyle(color: context.colors.textSecondary, fontSize: 14.sp);
    final balance = ref.watch(arbitrumRefundProvider);
    // The balance is read as soon as the row turned refunded.
    ref.listen(arbitrumRefundRowsWatcherProvider, (_, __) {});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 8.h),
        Text(
          l10n.activityReturnedTo(
              sendShortAddress(refund), orchestraChainDisplayName('arbitrum')),
          key: const ValueKey('cctp-move-returned'),
          style: note,
        ),
        if (balance.belowMinimum) ...[
          SizedBox(height: 4.h),
          Text(l10n.portfolioRebalanceBelowMinimum,
              key: const ValueKey('cctp-move-returned-below-minimum'),
              style: note),
        ],
      ],
    );
  }
}
