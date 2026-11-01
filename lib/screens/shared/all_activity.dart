// lib/screens/shared/all_activity.dart
//
// Everything the spending account did, in one list (founder, 1 November
// 2026: the Portfolio's Activity goes away and the Bitcoin home's Activity
// shows it all):
//
//   * the wallet's own rows from every account at once: bitcoin sends and
//     receives, the Dollars ledger (deposits, withdrawals, sends, receives),
//     every conversion and venue move, each one row with its legs folded in
//     (assembleActivityRows with allAccounts: a withdrawal home is never
//     listed beside the Spark receives that delivered it);
//   * the venues' own activity: every Hyperliquid fill (opens and closes,
//     HyperliquidFillActivityRow) and every prediction placed, sold, won or
//     lost, results from resolved markets included.
//
// Merged by time, newest first, a deposit waiting on the person leading
// under Today (the one row that needs a tap). Every row is the widget its
// own surface draws, on the same day cards as before: nothing restyled.
//
// The Bitcoin home previews the newest [kHomeActivityPreviewRows]
// ([AllActivityPreview]); "See all" opens the Activity screen, which lists
// them all ([AllActivitySliver]), built a page at a time as it scrolls.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:kute/screens/shared/kute_motion.dart' show KuteStaggerIn;
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/services/one_balance/multi_source_move.dart'
    show multiSourceMovesProvider;
import 'package:kute/services/orchestra/bitcoin_receive_marks.dart';
import 'package:kute/services/orchestra/own_spark_arrivals.dart'
    show ownSparkArrivalsProvider;

/// Rows the Bitcoin home's Activity shows before "See all".
const int kHomeActivityPreviewRows = 8;

/// One entry of the merged list: a transaction row or a fill, with the
/// time it sorts by.
typedef AllActivityEntry = ({DateTime time, BaseTransaction? tx, HlFill? fill});

/// The merged list, newest first, waiting deposits leading. Pure, so a test
/// can pin what is listed and in what order without a widget tree.
///
/// [walletRows] are the wallet's rows from every account
/// (assembleActivityRows with allAccounts); [bets] the predictions placed,
/// sold, won or lost; [fills] the Investing fills. A bet already among the
/// wallet rows (same id) is listed once.
List<AllActivityEntry> mergeAllActivity({
  required List<BaseTransaction> walletRows,
  List<PolymarketTransaction> bets = const [],
  List<HlFill> fills = const [],
}) {
  final listed = <String>{for (final tx in walletRows) tx.id};
  final entries = <AllActivityEntry>[
    for (final tx in walletRows) (time: tx.timestamp, tx: tx, fill: null),
    for (final tx in bets)
      if (listed.add(tx.id)) (time: tx.timestamp, tx: tx, fill: null),
    for (final fill in fills)
      (
        time: DateTime.fromMillisecondsSinceEpoch(fill.time),
        tx: null,
        fill: fill
      ),
  ]..sort((a, b) => b.time.compareTo(a.time));
  bool waiting(AllActivityEntry e) => e.tx != null && isWaitingDeposit(e.tx!);
  if (!entries.any(waiting)) return entries;
  return [...entries.where(waiting), ...entries.where((e) => !waiting(e))];
}

/// The spending account's merged activity: the entries newest first, and
/// whether the Investing history is still on its way or failed.
typedef AllActivity = ({
  List<AllActivityEntry> entries,
  bool loading,
  bool failed,
});

/// Watches everything the merged list is made of (see the file header) for
/// the spending account and merges it.
AllActivity watchAllActivity(WidgetRef ref) {
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
  final walletRows = assembleActivityRows(
    txs.allTransactionsSorted,
    ownAddresses: activityOwnSettleAddresses(ref),
    isHardwareOrWatchOnly: false,
    onlyUsdb: false,
    allAccounts: true,
    moves: moves,
    walletId: walletId,
    // A move over with nothing delivered has no row; its legs show.
    dissolved: moves.isEmpty ? null : watchMultiSourceMovesDissolved(ref),
    bitcoinReceiveMarks: ref.watch(bitcoinReceiveMarksProvider),
  );
  final bets = <PolymarketTransaction>[
    ...txs.polymarketTransactions.where((t) =>
        t.activityType == ActivityType.trade ||
        t.activityType == ActivityType.redeem),
    // The results the history does not record: a lost prediction is never
    // claimed, so only its resolved market says it lost (and a win shows
    // here until it is claimed).
    ...predictionResultTransactions(ref, txs.polymarketTransactions),
  ];
  final fills = ref.watch(hyperliquidActivityFillsProvider);
  final history = ref.watch(hyperliquidUserFillsProvider);
  return (
    entries:
        mergeAllActivity(walletRows: walletRows, bets: bets, fills: fills),
    loading: history.isLoading,
    failed: history.hasError,
  );
}

/// [entries] on the day cards, each row the widget its own surface draws.
/// A waiting deposit is listed under Today, whenever it arrived.
List<Widget> allActivityDaySections(
    BuildContext context, WidgetRef ref, List<AllActivityEntry> entries) {
  final now = DateTime.now();
  var index = 0;
  return activityDaySections<AllActivityEntry>(
    entries,
    timeOf: (e) => e.tx != null && isWaitingDeposit(e.tx!) ? now : e.time,
    rowOf: (e) => KuteStaggerIn(
      index: index++,
      child: e.fill != null
          ? HyperliquidFillActivityRow(
              fill: e.fill!, compareWithSpendingWallet: true)
          : buildUnifiedTransactionItem(e.tx!, context, ref),
    ),
  );
}

/// The Bitcoin home's Activity: the newest [limit] entries of everything
/// the spending account did, or [emptyState] when there is nothing yet.
class AllActivityPreview extends ConsumerWidget {
  const AllActivityPreview({
    super.key,
    this.limit = kHomeActivityPreviewRows,
    this.emptyState,
  });

  final int limit;
  final Widget? emptyState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = watchAllActivity(ref).entries;
    if (entries.isEmpty) {
      return emptyState ?? buildNoTransactionsFound(context);
    }
    final shown =
        entries.length > limit ? entries.sublist(0, limit) : entries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: allActivityDaySections(context, ref, shown),
    );
  }
}

/// Every entry, newest first, as slivers for the Activity screen: built a
/// page of [pageSize] at a time, the next page once the list scrolls near
/// its end (the entries are all known; only their rows wait).
class AllActivitySliver extends ConsumerStatefulWidget {
  const AllActivitySliver({
    super.key,
    required this.controller,
    this.pageSize = 60,
  });

  /// The screen's scroll controller, read to load the next page.
  final ScrollController controller;
  final int pageSize;

  @override
  ConsumerState<AllActivitySliver> createState() => _AllActivitySliverState();
}

class _AllActivitySliverState extends ConsumerState<AllActivitySliver> {
  late int _limit = widget.pageSize;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant AllActivitySliver old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final c = widget.controller;
    if (!c.hasClients || _limit >= _total) return;
    if (c.position.extentAfter < 800) {
      setState(() => _limit += widget.pageSize);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activity = watchAllActivity(ref);
    final entries = activity.entries;
    _total = entries.length;
    // A page that does not fill the screen loads the next one at once.
    if (_limit < _total) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onScroll();
      });
    }
    if (entries.isEmpty) {
      if (activity.loading) {
        return const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator.adaptive()),
          ),
        );
      }
      return SliverToBoxAdapter(child: buildNoTransactionsFound(context));
    }
    final shown =
        entries.length > _limit ? entries.sublist(0, _limit) : entries;
    final sections = allActivityDaySections(context, ref, shown);
    final children = <Widget>[
      if (activity.failed)
        TextButton.icon(
            onPressed: () => ref.invalidate(hyperliquidUserFillsProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.l10n.hlActivityRefreshFailedRetry)),
      ...sections,
    ];
    return SliverList.builder(
      itemCount: children.length,
      itemBuilder: (_, i) => children[i],
    );
  }
}
