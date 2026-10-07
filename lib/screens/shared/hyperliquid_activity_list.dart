import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart'
    show KuteDockClearance, kuteDockScrollClearance;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/screens/shared/hyperliquid_fill_activity.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/theme/app_theme.dart';

/// Portfolio activity stays bound to its account, even in the root navigator.
class HyperliquidActivityList extends ConsumerWidget {
  const HyperliquidActivityList(
      {super.key,
      required this.fills,
      required this.walletId,
      this.loading = false,
      this.loadFailed = false,
      required this.onRetry,
      this.compareWithSpendingWallet = false,
      this.maxRows = 200});
  final List<HlFill> fills;
  final String? walletId;
  final bool loading, loadFailed, compareWithSpendingWallet;
  final VoidCallback onRetry;
  final int maxRows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final swaps = ref.watch(swapOrdersProvider).where((order) {
      if (walletId == null || order.walletId != walletId) return false;
      return swapActivityFor(order).isInvesting;
    });
    final entries = <({int time, Widget row})>[
      for (final fill in fills)
        (
          time: fill.time,
          row: HyperliquidFillActivityRow(
              fill: fill, compareWithSpendingWallet: compareWithSpendingWallet)
        ),
      for (final order in swaps)
        (
          time: order.timestamp,
          row: buildUnifiedTransactionItem(
              SwapOrderTransaction(
                  id: order.id,
                  timestamp:
                      DateTime.fromMillisecondsSinceEpoch(order.timestamp),
                  details: order,
                  isConfirmed: order.isComplete),
              context,
              ref)
        ),
    ]..sort((a, b) => b.time.compareTo(a.time));
    // Hosted under a Portfolio's dock: the centred state keeps clear of
    // it, the list runs under it with its last row clear.
    if (entries.isEmpty && !loadFailed) {
      return KuteDockClearance(
          child: Center(
              child: loading
                  ? const CircularProgressIndicator.adaptive()
                  : Text(context.l10n.ledgerActivityEmpty,
                      style: TextStyle(color: c.textTertiary))));
    }
    final children = <Widget>[];
    if (loadFailed) {
      children.add(TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(context.l10n.hlActivityRefreshFailedRetry)));
    }
    // Same day cards as Home and the wallets.
    children.addAll(activityDaySections<({int time, Widget row})>(
      entries.take(maxRows).toList(),
      timeOf: (e) => DateTime.fromMillisecondsSinceEpoch(e.time),
      rowOf: (e) => e.row,
    ));
    return ListView(
        padding: EdgeInsets.fromLTRB(
            0, 8.h, 0, 40.h + kuteDockScrollClearance(context)),
        children: children);
  }
}
