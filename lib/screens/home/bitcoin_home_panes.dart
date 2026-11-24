// lib/screens/home/bitcoin_home_panes.dart
//
// THE BITCOIN HOME ON A WIDE WINDOW (kute_layout.dart). The wallet home
// itself is never redesigned (founder's standing rule), so it is drawn
// with its own widgets, only moved:
//
//   * COMPACT: the home, untouched.
//   * MEDIUM: the home in a centred [KuteLayout.columnMaxWidth] column.
//   * EXPANDED: SEPARATED, in the Dollars home's frame (founder, 26
//     November 2026, of a centred single-page Dollars home: "a very
//     iPad-like UI … I like the separated", then "On bitcoin same thing
//     pls"), with the money in the top bar as the fintech desktops have
//     it ("the balance always on the top"): the balance and Purchase /
//     Scan / Receive / Send are the desktop top bar's
//     (desktop_top_bar_money.dart), so the page under it is what you look
//     at ([BitcoinPanesFrame]: centred at [KuteLayout.pageMaxWidth], the
//     page gutters, the top bar's room, [KuteLayout.paneGap] between):
//       - LEFT, the one scroll, the floating bar centred under it
//         ([KuteBarPane]): the home's pill (Activity) at its top left,
//         where the Dollars pills stand; the backup banner, slim, at the
//         top of its list; then the full Bitcoin activity (what "See all"
//         opens on a phone, loading more as it scrolls) in a readable
//         column ([kBitcoinListMaxWidth]), left-aligned.
//       - RIGHT, at [KuteLayout.paneWidth], still, once the wallet has a
//         history: the Goals card (the balance chart and the goals; a
//         Ledger or watch-only wallet's Balance charts). The floating bar
//         stays the search there ([BalanceGoalsNoBar]).
//       - A new wallet: no right column; one empty state (Sal, "No
//         activity yet") close under the pill, centred in the page.
//     Another wallet's tab (WalletBitcoinBody.wide) takes the same frame:
//     its activity on the left, its charts on the right.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/nav_bar_visibility_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/screens/analytics/components/balance_goals.dart'
    show BalanceGoalsNoBar;
import 'package:kute/screens/analytics/components/home_analytics_widget.dart';
import 'package:kute/screens/home/home.dart' show Home;
import 'package:kute/screens/share/pending_share_links.dart';
import 'package:kute/screens/shared/all_activity.dart'
    show ActivityScope, AllActivitySliver, watchAllActivity;
import 'package:kute/screens/shared/kute_bar_context.dart'
    show kuteBarScrollClearance;
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/no_activity_state.dart';
import 'package:kute/screens/shared/transactions_builder.dart'
    show DepositWaitingLine, TransactionList;
import 'package:kute/theme/app_theme.dart';

/// A single column of rows in the left pane: at most this wide,
/// left-aligned (the Dollars lists' rule), never stretched across it.
const double kBitcoinListMaxWidth = 720;

/// The key of the right pane on EXPANDED (the hero), for the frame check.
const Key kBitcoinActionPaneKey = ValueKey('bitcoin-home-action-pane');

/// The Bitcoin home as the form factor wants it (see the file header).
class BitcoinHomePanes extends StatelessWidget {
  const BitcoinHomePanes({super.key});

  @override
  Widget build(BuildContext context) {
    final window = MediaQuery.sizeOf(context).width;
    switch (KuteLayout.forWidth(window)) {
      case KuteFormFactor.compact:
        return const Home();
      case KuteFormFactor.medium:
        return const KuteFormColumn(child: Home());
      case KuteFormFactor.expanded:
        return const Home(panes: true);
    }
  }
}

/// The Dollars page's frame on EXPANDED (usd_account_screen.dart,
/// _InvestmentsPanes), for a Bitcoin surface: the desktop top bar's room,
/// the page centred at [KuteLayout.pageMaxWidth] with [KuteLayout.paneGap]
/// at its sides and between the panes; [left] flexible, the floating bar
/// centred under it ([KuteBarPane]); [right], when there is one, at
/// [KuteLayout.paneWidth], a phone column (its MediaQuery's width the
/// pane's).
class BitcoinPanesFrame extends StatelessWidget {
  const BitcoinPanesFrame({super.key, required this.left, this.right});

  final Widget left;

  /// The side column; null: [left] takes the page's width.
  final Widget? right;

  @override
  Widget build(BuildContext context) => Padding(
        // The desktop top bar's room, which the shell keeps.
        padding: const EdgeInsets.only(top: kuteTopBarHeight),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: KuteLayout.pageMaxWidth),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: KuteLayout.paneGap),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: KuteBarPane(child: left)),
                  if (right != null) ...[
                    const SizedBox(width: KuteLayout.paneGap),
                    SizedBox(
                      width: KuteLayout.paneWidth,
                      child: kuteNarrowMedia(context,
                          width: KuteLayout.paneWidth, child: right!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}

/// A pill row at the top left of a left pane, where the Dollars page
/// draws its own (usd_account_screen.dart): the same insets and width cap.
class BitcoinPaneTop extends StatelessWidget {
  const BitcoinPaneTop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 10.h),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: KuteLayout.paneWidth - 24),
            child: child,
          ),
        ),
      );
}

/// [sliver] at most [kBitcoinListMaxWidth] wide, at the pane's left, with
/// the MediaQuery's width that column's.
class BitcoinListWidthSliver extends StatelessWidget {
  const BitcoinListWidthSliver({super.key, required this.sliver});

  final Widget sliver;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
        builder: (context, constraints) {
          final room = constraints.crossAxisExtent;
          final width = math.min(kBitcoinListMaxWidth, room);
          return SliverPadding(
            padding: EdgeInsets.only(right: room - width),
            sliver: kuteNarrowMedia(context, width: width, child: sliver),
          );
        },
      );
}

/// The room at a left pane's scroll's end: its last rows clear the
/// floating bar under it.
Widget bitcoinPaneEnd(BuildContext context) => SliverToBoxAdapter(
      child: SizedBox(
          height: math.max(
              MediaQuery.paddingOf(context).bottom, kuteBarScrollClearance)),
    );

/// A scroll in a left pane that finds the nav bar hidden (by another
/// page) brings it back, as the Dollars panes do, so its room is never
/// empty.
Widget bitcoinPaneScrollWatch(WidgetRef ref, Widget child) =>
    NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollUpdateNotification && ref.read(navBarHiddenProvider)) {
          ref.read(navBarHiddenProvider.notifier).state = false;
        }
        return false;
      },
      child: child,
    );

/// Whether the Bitcoin home has nothing to list yet, and whether that is
/// the wallet waking up rather than empty: the same sources the activity
/// lists (the spending wallet's bitcoin, or a Ledger or watch-only
/// wallet's own history, as the phone home's Activity tab).
({bool empty, bool waking}) bitcoinHomeHistory(WidgetRef ref,
    {required bool isSavings}) {
  if (isSavings) {
    final empty = !ref.watch(transactionNotifierProvider.select((t) =>
        t.homeTransactionsSorted.any((tx) =>
            tx is! PolymarketTransaction &&
            tx is! PolymarketUsdcReceive &&
            tx is! UsdbTokenTransaction)));
    return (empty: empty, waking: false);
  }
  final activity = watchAllActivity(ref, scope: ActivityScope.bitcoin);
  final empty = activity.curated.entries.isEmpty;
  return (
    empty: empty,
    waking:
        empty && (activity.loading || ref.watch(breezSDKProvider).isLoading),
  );
}

/// The Bitcoin home on EXPANDED (see the file header): the activity on
/// the left, the goals on the right once there is a history.
class BitcoinHomeDesktop extends ConsumerWidget {
  const BitcoinHomeDesktop(
      {super.key, required this.onRefresh, this.banners = const []});

  /// The home's pull-to-refresh ("update everything").
  final RefreshCallback onRefresh;

  /// The home's banners (the backup reminder, the seed notice), at the
  /// top of the left pane's list.
  final List<Widget> banners;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(settingsProvider.select((s) => s.activeWallet));
    final isSavings = (wallet?.isHardware ?? false) ||
        (wallet?.isWatchOnly ?? false) ||
        (wallet?.isExternalAddress ?? false);
    final history = bitcoinHomeHistory(ref, isSavings: isSavings);
    final emptyState = history.empty && !history.waking;
    return BitcoinPanesFrame(
      left: BitcoinActivityPane(
        onRefresh: onRefresh,
        banners: [
          ...banners,
          // A deposit waiting for a lower fee: the home's one quiet line.
          if (!isSavings) const DepositWaitingLine(),
          if (!isSavings) const PendingShareLinksCard(),
        ],
        empty: emptyState,
        list: (controller) => history.waking
            ? const SliverToBoxAdapter(child: SkeletonRowList(count: 3))
            : isSavings
                ? const SliverToBoxAdapter(
                    child: TransactionList(
                        showAll: true, emptyState: NoActivityState()),
                  )
                // What the phone's See all opens, in full.
                : AllActivitySliver(
                    controller: controller,
                    scope: ActivityScope.bitcoin,
                    emptyState: const NoActivityState()),
      ),
      right: history.empty
          ? null
          : BitcoinSideColumn(
              child: HomeAnalyticsWidget(
                surface: 'home',
                showPrice: false,
                balanceGoals: !isSavings,
                padding: EdgeInsets.only(top: 8.h, bottom: 24.h),
              ),
            ),
    );
  }
}

/// The right column of a Bitcoin surface on EXPANDED: [child] (the Goals
/// card, a wallet's charts), still while it fits, its own scroll when the
/// window is too short; it never takes the floating bar
/// ([BalanceGoalsNoBar]).
class BitcoinSideColumn extends StatelessWidget {
  const BitcoinSideColumn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => BalanceGoalsNoBar(
        child: SingleChildScrollView(
          key: kBitcoinActionPaneKey,
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.only(
              bottom: MediaQuery.viewPaddingOf(context).bottom + 16.h),
          child: RepaintBoundary(child: child),
        ),
      );
}

/// The left pane of a Bitcoin surface on EXPANDED: the Activity pill at
/// its top left (where the Dollars pills stand), then one scroll: the
/// [banners], slim, and the [list] in a readable column, or, [empty], the
/// one empty state centred under the pill. Pull-to-refresh is [onRefresh].
class BitcoinActivityPane extends ConsumerStatefulWidget {
  const BitcoinActivityPane({
    super.key,
    required this.onRefresh,
    required this.list,
    required this.empty,
    this.banners = const [],
  });

  final RefreshCallback onRefresh;

  /// The rows, as a sliver, given the pane's scroll (to load more).
  final Widget Function(ScrollController controller) list;
  final bool empty;
  final List<Widget> banners;

  @override
  ConsumerState<BitcoinActivityPane> createState() =>
      _BitcoinActivityPaneState();
}

class _BitcoinActivityPaneState extends ConsumerState<BitcoinActivityPane> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // The phone strip's first pill, named as it names it; on EXPANDED it
    // is the activity itself (no "See all"), the goals standing beside it.
    final pill = KutePillTabs(
      items: [
        KutePillItem(
            label: context.l10n.activity, icon: Icons.receipt_long_rounded),
      ],
      selectedIndex: 0,
      onTap: (_) {},
      size: kutePillSwitchSize,
      // Its own width, as the Dollars pills hug theirs.
      scroll: true,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BitcoinPaneTop(child: pill),
        Expanded(
          child: bitcoinPaneScrollWatch(
            ref,
            RefreshIndicator(
              onRefresh: widget.onRefresh,
              color: c.accent,
              backgroundColor: c.surface,
              child: CustomScrollView(
                controller: _controller,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (widget.banners.isNotEmpty)
                    BitcoinListWidthSliver(
                      sliver: SliverToBoxAdapter(
                        // On the rows' 16 gutter.
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.w),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: widget.banners,
                          ),
                        ),
                      ),
                    ),
                  if (widget.empty)
                    // ONE empty state, centred in the page, close under
                    // the pill like the empty Dollars Overview (Sal's
                    // sprite carries ~20 of air above him).
                    const SliverToBoxAdapter(
                      child: NoActivityState(
                          padding: EdgeInsets.fromLTRB(24, 44, 24, 8)),
                    )
                  else
                    BitcoinListWidthSliver(sliver: widget.list(_controller)),
                  bitcoinPaneEnd(context),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
