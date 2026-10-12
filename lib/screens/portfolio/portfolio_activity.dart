// lib/screens/portfolio/portfolio_activity.dart
//
// The Portfolio's Activity tab: ONE list, everything the spending
// account's investments did, newest first (owner decision October 2026,
// replacing the Investing | Predictions switch over two lists).
//
//   * the venues' own activity: every Hyperliquid fill
//     (HyperliquidFillActivityRow, the Investing list's row) and every
//     prediction placed, sold, won or lost (the Predictions history's
//     rows, results from resolved markets included);
//   * the wallet's deposit and move activity: the dollar ledger exactly
//     as the Dollars activity lists it (assembleActivityRows with
//     onlyUsdb) — Investments deposits, the per-order funding moves, the
//     sweeps back, the dollar sends and receives — plus any venue move
//     that ledger does not carry (an older move paid in bitcoin), so a
//     move is one row here whatever paid for it.
//
// Every row is the widget its own surface draws
// (buildUnifiedTransactionItem, HyperliquidFillActivityRow), on the same
// day cards as Home and the wallets: nothing is restyled, the lists are
// merged and sorted by time. A conversion listed by both the dollar
// ledger and a venue is one row (same order id).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/helpers/swap_activity.dart' show swapActivityFor;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlFill;
import 'package:kute/models/polymarket_model.dart' show ActivityType;
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart'
    show walletTransactionCacheProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/home/components/kute_dock_host.dart'
    show KuteDockClearance, kuteDockScrollClearance;
import 'package:kute/screens/shared/hyperliquid_fill_activity.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/theme/app_theme.dart';

/// One entry of the merged list: a transaction row or a fill, with the
/// time it sorts by.
typedef PortfolioActivityEntry = ({DateTime time, BaseTransaction? tx, HlFill? fill});

/// The merged list, newest first. Pure, so a test can pin what is listed
/// and in what order without a widget tree.
///
/// [dollarRows] is the dollar ledger as the Dollars activity lists it;
/// [swaps] every conversion the wallet knows (venue moves the ledger
/// does not carry are added from it); [bets] the predictions placed,
/// sold, won or lost; [fills] the Investing fills.
List<PortfolioActivityEntry> mergePortfolioActivity({
  required List<BaseTransaction> dollarRows,
  required List<SwapOrderTransaction> swaps,
  required List<PolymarketTransaction> bets,
  required List<HlFill> fills,
}) {
  final listed = <String>{for (final tx in dollarRows) tx.id};
  final entries = <PortfolioActivityEntry>[
    for (final tx in dollarRows) (time: tx.timestamp, tx: tx, fill: null),
    // A venue move the dollar ledger does not carry: paid in bitcoin
    // before one balance. Still a move the Portfolio should show.
    for (final tx in swaps)
      if (!listed.contains(tx.id) && _isVenueMove(tx))
        (time: tx.timestamp, tx: tx, fill: null),
    for (final tx in bets) (time: tx.timestamp, tx: tx, fill: null),
    for (final fill in fills)
      (
        time: DateTime.fromMillisecondsSinceEpoch(fill.time),
        tx: null,
        fill: fill
      ),
  ]..sort((a, b) => b.time.compareTo(a.time));
  return entries;
}

bool _isVenueMove(SwapOrderTransaction tx) {
  final kind = swapActivityFor(tx.details);
  return kind.isInvesting || kind.isPredictions;
}

/// The Activity tab's list for the spending account.
class PortfolioActivityList extends ConsumerWidget {
  const PortfolioActivityList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = context.l10n;
    // The spending account's own history, the slot the Dollars activity
    // and Home read.
    final walletId =
        ref.watch(settingsProvider.select((s) => pickSpendingWallet(s)?.id));
    final txs = ref.watch(walletTransactionCacheProvider
            .select((cache) => walletId == null ? null : cache[walletId])) ??
        Transaction.empty();
    final dollarRows = assembleActivityRows(
      txs.allTransactionsSorted,
      ownAddresses: activityOwnSettleAddresses(ref),
      isHardwareOrWatchOnly: false,
      onlyUsdb: true,
    );
    final bets = <PolymarketTransaction>[
      ...txs.polymarketTransactions.where((t) =>
          t.activityType == ActivityType.trade ||
          t.activityType == ActivityType.redeem),
      // The results the history does not record: a lost prediction is
      // never claimed, so only its resolved market says it lost (and a
      // win shows here until it is claimed).
      ...predictionResultTransactions(ref, txs.polymarketTransactions),
    ];
    final fills = ref.watch(hyperliquidActivityFillsProvider);
    final history = ref.watch(hyperliquidUserFillsProvider);
    final entries = mergePortfolioActivity(
      dollarRows: dollarRows,
      swaps: txs.swapOrderTransactions,
      bets: bets,
      fills: fills,
    );

    // Under the host's dock: the centred states keep clear of it, the
    // list runs under it with its last row clear.
    if (entries.isEmpty && !history.hasError) {
      return KuteDockClearance(
          child: Center(
              child: history.isLoading
                  ? const CircularProgressIndicator.adaptive()
                  : Text(l10n.ledgerActivityEmpty,
                      style: TextStyle(color: c.textTertiary))));
    }
    final children = <Widget>[];
    if (history.hasError) {
      children.add(TextButton.icon(
          onPressed: () => ref.invalidate(hyperliquidUserFillsProvider),
          icon: const Icon(Icons.refresh_rounded),
          label: Text(l10n.hlActivityRefreshFailedRetry)));
    }
    // Same day cards as Home and the wallets.
    children.addAll(activityDaySections<PortfolioActivityEntry>(
      entries,
      timeOf: (e) => e.time,
      rowOf: (e) => e.fill != null
          ? HyperliquidFillActivityRow(
              fill: e.fill!, compareWithSpendingWallet: true)
          : buildUnifiedTransactionItem(e.tx!, context, ref),
    ));
    return ListView(
        padding: EdgeInsets.fromLTRB(
            0, 8.h, 0, 40.h + kuteDockScrollClearance(context)),
        children: children);
  }
}
