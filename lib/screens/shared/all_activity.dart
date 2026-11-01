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
// Curated (founder, 1 November 2026; activity_curation.dart): the
// Bitcoin home shows the newest [kHomeActivityRows] actions, never the
// money moving between the person's own accounts, under one "Today" card
// (In, Out, P&L) when anything happened today ([AllActivityPreview]).
// "See all" opens the Activity screen, which lists everything
// ([AllActivitySliver]), built a page at a time as it scrolls, with each
// funding chain folded into the action it paid for ("Paid from Bitcoin").

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart'
    show formatPolyAmount;
import 'package:kute/helpers/swap_activity.dart'
    show SwapActivityKind, swapActivityFor;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/models/swap_order_model.dart' show SwapOrder;
import 'package:kute/providers/currency_conversions_provider.dart'
    show currentBtcUsdProvider;
import 'package:kute/providers/polymarket_live_prices_provider.dart'
    show livePriceProvider;
import 'package:kute/providers/portfolio_performance_provider.dart'
    show portfolioPerformanceDisplayProvider;
import 'package:kute/screens/portfolio/portfolio_filters.dart'
    show portfolioVenuesProvider;
import 'package:kute/screens/shared/activity_curation.dart';
import 'package:kute/screens/shared/position_rows_card.dart'
    show PositionStatTile, positionTileValueStyle;
import 'package:kute/theme/app_theme.dart';
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
const int kHomeActivityPreviewRows = kHomeActivityRows;

/// Tests and the render harness read swaps' intent without the settlement
/// store; null in the app (swapActivityFor).
@visibleForTesting
SwapActivityKind Function(SwapOrder order)? debugAllActivityClassify;

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
  CuratedActivity curated,
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
    // The conversions into and out of Predictions stay listed: the
    // curation folds them into the bet they paid for, or keeps the one
    // row that names both ends (activity_curation.dart).
    keepVenueMoves: true,
    classify: debugAllActivityClassify ?? swapActivityFor,
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
  final entries =
      mergeAllActivity(walletRows: walletRows, bets: bets, fills: fills);
  return (
    entries: entries,
    curated: curateAllActivity(entries,
        classify: debugAllActivityClassify ?? swapActivityFor),
    loading: history.isLoading,
    failed: history.hasError,
  );
}

/// The note on a row whose funding was folded into it ("Paid from
/// Bitcoin"), or null.
String? activityPaidFromNote(
    AppLocalizations l10n, List<ActivityAccount>? from) {
  if (from == null || from.isEmpty) return null;
  String name(ActivityAccount a) => switch (a) {
        ActivityAccount.bitcoin => l10n.bitcoin,
        ActivityAccount.dollars => l10n.assetDollars,
        ActivityAccount.investing => l10n.trading,
        ActivityAccount.predictions => l10n.predictions,
      };
  return from.length == 1
      ? l10n.activityPaidFrom(name(from.first))
      : l10n.activityPaidFromBoth(name(from[0]), name(from[1]));
}

/// [entries] on the day cards, each row the widget its own surface draws.
/// A waiting deposit is listed under Today, whenever it arrived.
///
/// [curated] says which rows took their funding in (the note on the row).
List<Widget> allActivityDaySections(
    BuildContext context, WidgetRef ref, List<AllActivityEntry> entries,
    {CuratedActivity? curated}) {
  final now = DateTime.now();
  final l10n = context.l10n;
  var index = 0;
  return activityDaySections<AllActivityEntry>(
    entries,
    timeOf: (e) => e.tx != null && isWaitingDeposit(e.tx!) ? now : e.time,
    rowOf: (e) {
      final Widget row = e.fill != null
          ? HyperliquidFillActivityRow(
              fill: e.fill!, compareWithSpendingWallet: true)
          : buildUnifiedTransactionItem(e.tx!, context, ref);
      final note = activityPaidFromNote(l10n, curated?.paidFromOf(e));
      return KuteStaggerIn(
        index: index++,
        child: note == null ? row : ActivityRowNote(note: note, child: row),
      );
    },
  );
}

/// The Bitcoin home's Activity: the "Today" card and the newest [limit]
/// actions of everything the spending account did (no money moving
/// between its own accounts: activity_curation.dart), or [emptyState]
/// when there is nothing yet.
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
    final activity = watchAllActivity(ref);
    final classify = debugAllActivityClassify ?? swapActivityFor;
    final shown =
        homeActivityEntries(activity.curated, limit: limit, classify: classify);
    if (shown.isEmpty) {
      return emptyState ?? buildNoTransactionsFound(context);
    }
    final today = todayActivityFlows(activity.curated.entries,
        now: DateTime.now(),
        btcUsd: ref.watch(currentBtcUsdProvider),
        classify: classify);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (today.any) ActivityTodayCard(flows: today),
        ...allActivityDaySections(context, ref, shown,
            curated: activity.curated),
      ],
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
    final entries = activity.curated.entries;
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
    final sections =
        allActivityDaySections(context, ref, shown, curated: activity.curated);
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


/// Today's profit and loss on Investing and Predictions, in dollars: what
/// each venue's own published P&L moved since local midnight (realised
/// plus the open positions' change; Predictions rebuilt from the live
/// positions as the Portfolio does). Null when neither venue has a figure.
double? watchTodayInvestmentsPnl(WidgetRef ref, {DateTime? now}) {
  final venues = ref.watch(portfolioVenuesProvider);
  final at = now ?? DateTime.now();
  final midnight = DateTime(at.year, at.month, at.day);
  double? total;
  for (final v in [
    if (venues.trading) PortfolioPerformanceVenue.trading,
    if (venues.predictions) PortfolioPerformanceVenue.predictions,
  ]) {
    final data = ref
        .watch(portfolioPerformanceDisplayProvider(
            PortfolioPerformanceRequest(venue: v)))
        .valueOrNull;
    if (data == null) continue;
    final p = v == PortfolioPerformanceVenue.predictions &&
            data.predictions != null
        ? data.withLivePredictions(
            ref.watch(livePriceProvider.select((s) => s.prices)))
        : data;
    final change = todayPnlOf(p, midnight);
    if (change != null) total = (total ?? 0) + change;
  }
  return total;
}

/// What [p] moved since [midnight] (local): its latest observation against
/// the last one at or before midnight (zero for an account younger than
/// the day). Null when it has published nothing today.
double? todayPnlOf(PortfolioPerformance p, DateTime midnight) {
  if (p.points.isEmpty) return null;
  final last = p.points.last;
  final since = last.timestamp.toUtc().difference(midnight.toUtc());
  if (since.isNegative) return null;
  final change = p.rangeView(since).changeUsd;
  return change != null && change.isFinite ? change : null;
}

/// The home Activity's "Today" card: three equal tiles in the position
/// pages' tile style, what came in, what went out, and the venues' P&L
/// (coloured; left out when there is no real figure).
class ActivityTodayCard extends ConsumerWidget {
  const ActivityTodayCard({super.key, required this.flows});

  final TodayActivityFlows flows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = context.l10n;
    final visible =
        ref.watch(settingsProvider.select((s) => s.transactionValuesVisible));
    final pnl = watchTodayInvestmentsPnl(ref);
    String money(double? usd) =>
        !visible ? '••••' : usd == null ? '—' : formatPolyAmount(ref, usd);
    Widget tile(String key, String label, String value, {Color? color}) =>
        Expanded(
          child: PositionStatTile(
            key: ValueKey(key),
            label: label,
            value: Text(value,
                maxLines: 1,
                style: positionTileValueStyle(c, color: color).copyWith(
                    fontSize: 18.sp, letterSpacing: -0.4)),
          ),
        );
    final pnlUp = (pnl ?? 0) >= 0;
    final pnlText = pnl == null
        ? ''
        : !visible
            ? '••••'
            : '${pnl > 0 ? '+' : pnl < 0 ? '−' : ''}${formatPolyAmount(ref, pnl.abs())}';
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 0),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tile('activity-today-in', l10n.activityTodayIn,
                money(flows.inUsd)),
            SizedBox(width: 10.w),
            tile('activity-today-out', l10n.activityTodayOut,
                money(flows.outUsd)),
            if (pnl != null) ...[
              SizedBox(width: 10.w),
              tile('activity-today-pnl', l10n.activityTodayPnl, pnlText,
                  color: !visible || pnl == 0
                      ? null
                      : pnlUp
                          ? AppColors.marketUp
                          : AppColors.marketDown),
            ],
          ],
        ),
      ),
    );
  }
}
