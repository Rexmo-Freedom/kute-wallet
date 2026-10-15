// lib/screens/portfolio/portfolio_activity.dart
//
// The Portfolio screen's Activity, at its bottom (it was the Portfolio's
// Activity tab): ONE list, everything the spending account's investments
// did, newest first (owner decision October 2026, replacing the Investing
// | Predictions switch over two lists).
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
//
// The Portfolio builds only the newest five (kActivityPreviewRows, Home's
// preview) with Home's "See all" pill under them when there are more; the
// pill opens the Activity screen in its Investments scope
// (PortfolioActivityList), the whole list (founder request, October 2026:
// the Portfolio was building every row).

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
import 'package:kute/screens/shared/hyperliquid_fill_activity.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart' show KutePill;
import 'package:kute/screens/shared/multi_source_move_activity.dart'
    show multiSourceMoveLegIds;
import 'package:kute/services/one_balance/multi_source_move.dart'
    show multiSourceMovesProvider;
import 'package:kute/services/orchestra/own_spark_arrivals.dart'
    show ownSparkArrivalsProvider;
import 'package:kute/screens/shared/transactions_builder.dart';

/// One entry of the merged list: a transaction row or a fill, with the
/// time it sorts by.
typedef PortfolioActivityEntry = ({
  DateTime time,
  BaseTransaction? tx,
  HlFill? fill
});

/// The merged list, newest first. Pure, so a test can pin what is listed
/// and in what order without a widget tree.
///
/// [dollarRows] is the dollar ledger as the Dollars activity lists it;
/// [swaps] every conversion the wallet knows (venue moves the ledger
/// does not carry are added from it); [bets] the predictions placed,
/// sold, won or lost; [fills] the Investing fills; [movedLegIds] the
/// rows folded into a multi-source move's one row (never listed again).
List<PortfolioActivityEntry> mergePortfolioActivity({
  required List<BaseTransaction> dollarRows,
  required List<SwapOrderTransaction> swaps,
  required List<PolymarketTransaction> bets,
  required List<HlFill> fills,
  Set<String> movedLegIds = const {},
}) {
  // A leg of a multi-source move is inside that move's one row.
  final listed = <String>{for (final tx in dollarRows) tx.id, ...movedLegIds};
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

/// The spending account's merged activity as the Portfolio reads it:
/// the entries newest first, and whether the Investing history is still
/// on its way or failed.
typedef PortfolioActivity = ({
  List<PortfolioActivityEntry> entries,
  bool loading,
  bool failed,
});

/// Watches everything the merged list is made of (see the file header)
/// for the spending account and merges it.
PortfolioActivity watchPortfolioActivity(WidgetRef ref) {
  // The spending account's own history, the slot the Dollars activity
  // and Home read.
  final walletId =
      ref.watch(settingsProvider.select((s) => pickSpendingWallet(s)?.id));
  final txs = ref.watch(walletTransactionCacheProvider
          .select((cache) => walletId == null ? null : cache[walletId])) ??
      Transaction.empty();
  // One row per action that took money from more than one place.
  final moves = [
    for (final m in ref.watch(multiSourceMovesProvider))
      if (m.walletId == null || m.walletId == walletId) m,
  ];
  // A delivery to Spark the balance does not show yet keeps its row
  // pending: rebuild when that changes.
  ref.watch(ownSparkArrivalsProvider);
  final dollarRows = assembleActivityRows(
    txs.allTransactionsSorted,
    ownAddresses: activityOwnSettleAddresses(ref),
    isHardwareOrWatchOnly: false,
    onlyUsdb: true,
    moves: moves,
    walletId: walletId,
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
  return (
    entries: mergePortfolioActivity(
      dollarRows: dollarRows,
      swaps: txs.swapOrderTransactions,
      bets: bets,
      fills: fills,
      movedLegIds: multiSourceMoveLegIds(txs.swapOrderTransactions, moves),
    ),
    loading: history.isLoading,
    failed: history.hasError,
  );
}

/// The Portfolio screen's Activity, at its bottom: [entries] on the same
/// day cards as Home and the wallets, each row the widget its own surface
/// draws; the Investing history's retry first when it [failed].
///
/// With a [limit] (the Portfolio passes [kActivityPreviewRows]) only the
/// newest [limit] entries are built; when there are more, Home's "See
/// all" pill sits under them and calls [onSeeAll]. No [limit] builds
/// every entry (the Activity screen's Investments scope).
class PortfolioActivitySliver extends ConsumerWidget {
  const PortfolioActivitySliver({
    super.key,
    required this.entries,
    this.failed = false,
    this.limit,
    this.onSeeAll,
  });

  final List<PortfolioActivityEntry> entries;
  final bool failed;

  /// How many of the newest [entries] to build; null builds them all.
  final int? limit;

  /// Opens the whole list; its pill shows only when [limit] leaves rows
  /// out.
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cap = limit;
    // [entries] is already newest first: the preview is its head, so the
    // rows past it (and their per-row lookups) are never built.
    final more = cap != null && entries.length > cap;
    final shown = more ? entries.sublist(0, cap) : entries;
    final seeAll = onSeeAll;
    final children = <Widget>[
      if (failed)
        TextButton.icon(
            onPressed: () => ref.invalidate(hyperliquidUserFillsProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.l10n.hlActivityRefreshFailedRetry)),
      // Same day cards as Home and the wallets.
      ...activityDaySections<PortfolioActivityEntry>(
        shown,
        timeOf: (e) => e.time,
        rowOf: (e) => e.fill != null
            ? HyperliquidFillActivityRow(
                fill: e.fill!, compareWithSpendingWallet: true)
            : buildUnifiedTransactionItem(e.tx!, context, ref),
      ),
      // Home's "See all" pill (its Activity pill once selected), as is.
      if (more && seeAll != null)
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
          child: Center(
            child: KutePill(
              key: const ValueKey('portfolio-activity-see-all'),
              label: context.l10n.seeAll,
              icon: Icons.arrow_forward_rounded,
              selected: true,
              link: true,
              onTap: seeAll,
            ),
          ),
        ),
    ];
    return SliverList(delegate: SliverChildListDelegate(children));
  }
}

/// The Portfolio's whole Activity, the Activity screen's Investments
/// scope: every entry the Portfolio previews, the same rows on the same
/// day cards, scrolling.
class PortfolioActivityList extends ConsumerWidget {
  const PortfolioActivityList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = watchPortfolioActivity(ref);
    final Widget body;
    if (activity.entries.isNotEmpty || activity.failed) {
      body = PortfolioActivitySliver(
          entries: activity.entries, failed: activity.failed);
    } else if (activity.loading) {
      body = SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24.h),
          child: const Center(child: CircularProgressIndicator.adaptive()),
        ),
      );
    } else {
      body = SliverToBoxAdapter(child: buildNoTransactionsFound(context));
    }
    return CustomScrollView(slivers: [
      SliverPadding(
          padding: EdgeInsets.only(top: 8.h, bottom: 24.h), sliver: body),
    ]);
  }
}
