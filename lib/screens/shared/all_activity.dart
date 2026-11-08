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
// Scoped (founder, 4 November 2026: "On the Bitcoin activity only show
// bitcoin-related stuff and deposits and withdrawals and such"): every list
// reads the same merged entries through an [ActivityScope].
//
//   * [ActivityScope.bitcoin], the Bitcoin home's Activity and its "See
//     all": bitcoin sends and receives (Lightning, Spark, on-chain, the
//     deposits waiting to be claimed), and money moving into or out of
//     bitcoin: Bitcoin to Dollars and back, Bitcoin into Investing or
//     Predictions, withdrawals home to Bitcoin (a move from Investments
//     included), purchases of bitcoin ([isBitcoinActivity]). Predictions
//     placed, Investing fills and money moving between Dollars and the
//     venues are not listed: they are the Investments' and the Dollars'.
//     Nothing folds into a bet here: a Bitcoin → Predictions deposit that
//     paid for one is the bitcoin that left, listed as itself.
//   * [ActivityScope.investments], for the Portfolio and Dollars screens
//     (built elsewhere): every Investing fill, every prediction placed,
//     sold, won or lost, and every move into or out of Investing or
//     Predictions from anywhere, each funding chain folded into the action
//     it paid for, and dollars arriving from or leaving for outside the
//     wallet ([isInvestmentsActivity], activity_curation.dart).
//   * [ActivityScope.all]: everything (the Activity screen opened from a
//     money move, which may be any of them).
//
// Read it with [watchAllActivity] (`scope:`) in a widget, or filter merged
// entries with [activityInScope]; [AllActivityPreview] and
// [AllActivitySliver] take a scope too.
//
// The Bitcoin home shows the newest [kHomeActivityRows] bitcoin entries:
// the first [kHomeActivityLatest] as square tiles under "Latest", the rest
// as plain rows under "Earlier" ([AllActivityPreview]; no Today card since
// the declutter of 1 November 2026). "See all" opens the Activity screen
// in the same scope ([AllActivitySliver]), built a page at a time as it
// scrolls.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/helpers/cash_app_destination.dart'
    show cashAppDestination;
import 'package:kute/helpers/swap_activity.dart'
    show SwapActivityKind, swapActivityFor;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/swap_order_model.dart' show SwapOrder;
import 'package:kute/services/orchestra_routes.dart'
    show isOrchestraUsdLikeCoin;
import 'package:kute/screens/shared/activity_curation.dart';
import 'package:kute/screens/shared/animations/premium_group_container.dart';
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
import 'package:kute/screens/shared/multi_source_move_activity.dart'
    show MultiSourceMoveTransaction;
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/services/one_balance/multi_source_move.dart'
    show multiSourceMovesProvider;
import 'package:kute/services/one_balance/venue_funder.dart'
    show VenueCashDestination;
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

/// What an Activity list shows of the spending account (see the file
/// header).
enum ActivityScope {
  /// Everything every account did.
  all,

  /// Bitcoin sends and receives, and money moving into or out of bitcoin
  /// ([isBitcoinActivity]): the Bitcoin home's Activity and its See all.
  bitcoin,

  /// The venues' fills, bets and results, money moving into or out of
  /// Investing or Predictions, and dollars arriving from or leaving for
  /// outside the wallet ([isInvestmentsActivity]).
  investments,
}

/// Whether the Bitcoin activity lists [e]: a bitcoin send or receive
/// (Lightning, Spark, on-chain, a deposit waiting to be claimed, a
/// purchase of bitcoin), a conversion with bitcoin at one end that is not
/// a send paid from Dollars ([bitcoinLedgerListsSwap]), or a move from
/// Investments to Bitcoin. Never an Investing fill, a prediction, a
/// Dollars transfer or a move between Dollars and a venue.
bool isBitcoinActivity(
  AllActivityEntry e, {
  SwapActivityKind Function(SwapOrder order) classify = swapActivityFor,
  List<BitcoinReceiveMark> marks = const [],
}) {
  final tx = e.tx;
  return switch (tx) {
    null => false,
    BitcoinTransaction() ||
    SparkTransaction() ||
    SparkUnclaimedDeposit() ||
    SparkPendingDeposit() ||
    MempoolAddressTransaction() ||
    OutlogicTransaction() =>
      true,
    SwapOrderTransaction() =>
      bitcoinLedgerListsSwap(tx.details, classify: classify, marks: marks),
    MultiSourceMoveTransaction() =>
      tx.move.destination == VenueCashDestination.bitcoin,
    _ => false,
  };
}

/// Whether the Investments activity lists [e]: an Investing fill, a
/// prediction placed, sold, won or lost (and the venue's own deposit and
/// withdrawal records), USDC arriving in Predictions, a conversion into or
/// out of Investing or Predictions whatever paid for it (a Cash App
/// purchase into a venue included), a move that took money from or to a
/// venue, or dollars arriving from or leaving for outside the wallet
/// (founder, 8 November 2026: a stablecoin deposit must show here): a
/// receive into Dollars, a send paid from Dollars, a plain dollar transfer.
/// A transfer that is a conversion's leg never gets here: it folds into its
/// conversion's row first (assembleActivityRows).
bool isInvestmentsActivity(
  AllActivityEntry e, {
  SwapActivityKind Function(SwapOrder order) classify = swapActivityFor,
}) {
  if (e.fill != null) return true;
  final tx = e.tx;
  return switch (tx) {
    PolymarketTransaction() ||
    PolymarketUsdcReceive() ||
    UsdbTokenTransaction() =>
      true,
    SwapOrderTransaction() => tx.details.isCashAppPurchase
        ? cashAppDestination(tx.details)?.isVenue ?? false
        : _isVenueKind(classify(tx.details)) ||
            _isOutsideDollars(tx.details, classify(tx.details)),
    MultiSourceMoveTransaction() => tx.move.okLegs.isNotEmpty ||
        tx.move.destination == VenueCashDestination.investing ||
        tx.move.destination == VenueCashDestination.predictions,
    _ => false,
  };
}

bool _isVenueKind(SwapActivityKind kind) =>
    kind.isPredictions || kind.isInvesting;

/// A conversion that brings dollars in from outside the wallet, or pays
/// someone outside from Dollars. Crypto received into Bitcoin stays on the
/// Bitcoin activity.
bool _isOutsideDollars(SwapOrder order, SwapActivityKind kind) =>
    switch (kind) {
      SwapActivityKind.receive => isOrchestraUsdLikeCoin(order.coinTo),
      SwapActivityKind.send => isOrchestraUsdLikeCoin(order.coinFrom),
      _ => false,
    };

/// [entries] in [scope], the order kept.
List<AllActivityEntry> activityInScope(
  List<AllActivityEntry> entries,
  ActivityScope scope, {
  SwapActivityKind Function(SwapOrder order) classify = swapActivityFor,
  List<BitcoinReceiveMark> marks = const [],
}) =>
    switch (scope) {
      ActivityScope.all => entries,
      ActivityScope.bitcoin => [
          for (final e in entries)
            if (isBitcoinActivity(e, classify: classify, marks: marks)) e,
        ],
      ActivityScope.investments => [
          for (final e in entries)
            if (isInvestmentsActivity(e, classify: classify)) e,
        ],
    };

/// The spending account's merged activity: the entries newest first, and
/// whether the Investing history is still on its way or failed.
typedef AllActivity = ({
  List<AllActivityEntry> entries,
  CuratedActivity curated,
  bool loading,
  bool failed,
});

/// Watches everything the merged list is made of (see the file header) for
/// the spending account and merges it, in [scope]. The Bitcoin scope never
/// reads the venues' histories (no fill or bet is listed there).
///
/// [AllActivity.entries] are the scope's entries newest first;
/// [AllActivity.curated] the same with each funding chain folded into the
/// action it paid for (nothing folds in the Bitcoin scope, which lists no
/// action of a venue).
AllActivity watchAllActivity(WidgetRef ref,
    {ActivityScope scope = ActivityScope.all}) {
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
  final marks = ref.watch(bitcoinReceiveMarksProvider);
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
    bitcoinReceiveMarks: marks,
    receivedUsd: activityReceivedUsd(ref),
  );
  final classify = debugAllActivityClassify ?? swapActivityFor;
  if (scope == ActivityScope.bitcoin) {
    final entries = activityInScope(
        mergeAllActivity(walletRows: walletRows), scope,
        classify: classify, marks: marks);
    return (
      entries: entries,
      curated: CuratedActivity(entries: entries),
      loading: false,
      failed: false,
    );
  }
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
  final entries = activityInScope(
      mergeAllActivity(walletRows: walletRows, bets: bets, fills: fills),
      scope,
      classify: classify,
      marks: marks);
  return (
    entries: entries,
    curated: curateAllActivity(entries, classify: classify),
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

/// The Bitcoin home's Activity (founder, 1 November 2026: less clutter,
/// each row one or two things; 4 November 2026: bitcoin only, deposits and
/// withdrawals included): the newest [limit] entries of [scope] (the
/// Bitcoin scope: bitcoin sends and receives, and money moving into or out
/// of bitcoin). Another scope lists its newest actions, never the money
/// moving between the person's own accounts (activity_curation.dart). The
/// first [kHomeActivityLatest] under "Latest" as square tiles two by two
/// (the row's icon, the action, the amount large), the rest under
/// "Earlier" as plain one-line rows on one card. A tap opens the same
/// receipt as the row. [emptyState] when there is nothing yet.
class AllActivityPreview extends ConsumerWidget {
  const AllActivityPreview({
    super.key,
    this.limit = kHomeActivityPreviewRows,
    this.emptyState,
    this.scope = ActivityScope.bitcoin,
  });

  final int limit;
  final Widget? emptyState;
  final ActivityScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = watchAllActivity(ref, scope: scope);
    final classify = debugAllActivityClassify ?? swapActivityFor;
    final shown = scope == ActivityScope.bitcoin
        ? activity.entries.take(limit).toList(growable: false)
        : homeActivityEntries(activity.curated,
            limit: limit, classify: classify);
    if (shown.isEmpty) {
      return emptyState ?? buildNoTransactionsFound(context);
    }
    final l10n = context.l10n;
    final latest = shown.take(kHomeActivityLatest).toList(growable: false);
    final earlier = shown.skip(kHomeActivityLatest).toList(growable: false);
    var index = 0;
    Widget rowOf(AllActivityEntry e) => KuteStaggerIn(
          index: index++,
          child: e.fill != null
              ? HyperliquidFillActivityRow(
                  fill: e.fill!, compareWithSpendingWallet: true)
              : buildUnifiedTransactionItem(e.tx!, context, ref),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HomeActivityHeading(l10n.activityLatest),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: ActivityRowLayout(
            shape: ActivityRowShape.square,
            child: ActivitySquareGrid(
                children: [for (final e in latest) rowOf(e)]),
          ),
        ),
        if (earlier.isNotEmpty) ...[
          _HomeActivityHeading(l10n.activityEarlier),
          ActivityRowLayout(
            shape: ActivityRowShape.plain,
            child: PremiumGroupContainer(
              key: const ValueKey('activity-earlier'),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 4.h),
                child: Column(
                  children: [for (final e in earlier) rowOf(e)],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// "Latest" / "Earlier" over the home's Activity, in the day label's
/// style ([ActivityDaySection]).
class _HomeActivityHeading extends StatelessWidget {
  const _HomeActivityHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(28.w, 14.h, 28.w, 8.h),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      );
}

/// [children] two to a row, 10 apart each way, each half the width less
/// the gap (the home's "Latest" squares).
class ActivitySquareGrid extends StatelessWidget {
  const ActivitySquareGrid(
      {super.key, required this.children, this.equalHeights = false});

  final List<Widget> children;

  /// The squares of a row stretched to the tallest of it, for squares as
  /// tall as what they hold (the Portfolio screen's Positions,
  /// PortfolioPositionSquares.holdings). False: squares of a fixed height.
  final bool equalHeights;

  @override
  Widget build(BuildContext context) {
    final gap = 10.w;
    return LayoutBuilder(builder: (context, box) {
      final side = (box.maxWidth - gap) / 2;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i += 2) ...[
            if (i > 0) SizedBox(height: gap),
            _tall(Row(
              crossAxisAlignment: equalHeights
                  ? CrossAxisAlignment.stretch
                  : CrossAxisAlignment.start,
              children: [
                SizedBox(width: side, child: children[i]),
                if (i + 1 < children.length) ...[
                  SizedBox(width: gap),
                  SizedBox(width: side, child: children[i + 1]),
                ],
              ],
            )),
          ],
        ],
      );
    });
  }

  Widget _tall(Widget row) => equalHeights ? IntrinsicHeight(child: row) : row;
}

/// Every entry of [scope], newest first, as slivers for the Activity
/// screen: built a page of [pageSize] at a time, the next page once the
/// list scrolls near its end (the entries are all known; only their rows
/// wait).
class AllActivitySliver extends ConsumerStatefulWidget {
  const AllActivitySliver({
    super.key,
    required this.controller,
    this.pageSize = 60,
    this.scope = ActivityScope.all,
  });

  /// The screen's scroll controller, read to load the next page.
  final ScrollController controller;
  final int pageSize;
  final ActivityScope scope;

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
    final activity = watchAllActivity(ref, scope: widget.scope);
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
