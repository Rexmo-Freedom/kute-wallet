// lib/screens/home/bitcoin_home_panes.dart
//
// THE BITCOIN HOME ON A WIDE WINDOW (kute_layout.dart). The wallet home
// itself is never redesigned (founder's standing rule), so it is drawn
// with its own widgets, only moved:
//
//   * COMPACT: the home, untouched.
//   * MEDIUM: the home in a centred [KuteLayout.columnMaxWidth] column.
//   * EXPANDED: SEPARATED, exactly like the Dollars home (founder, 26
//     November 2026, of a centred single-page Dollars home: "a very
//     iPad-like UI … I like the separated", then of the Bitcoin home: "On
//     bitcoin same thing pls"). The same frame as the Dollars page
//     ([BitcoinPanesFrame]; usd_account_screen.dart, _InvestmentsPanes):
//     centred at [KuteLayout.pageMaxWidth], the page gutters, the desktop
//     top bar's room, [KuteLayout.paneGap] between the panes, so switching
//     between the two tabs leaves both panes exactly in place.
//       - RIGHT, at [KuteLayout.paneWidth], still: the wallet's hero as on
//         a phone (the backup banner when shown, the balance, Purchase /
//         Scan / Receive / Send), drawn by [Home] ([Home.panes]).
//       - LEFT, the one scroll, the floating bar centred under it
//         ([KuteBarPane]): the home's own pill row (Activity | Goals) at
//         its top left, where the Dollars pills stand, then the pill on
//         screen: the full Bitcoin activity (what "See all" opens on a
//         phone, loading more as it scrolls) or the Goals card (the
//         balance chart and the goals). A list stays a readable column
//         ([kBitcoinListMaxWidth]), left-aligned. A new wallet: one empty
//         state (Sal, "No activity yet") under the pills, centred.
//     Another wallet's tab (WalletBitcoinBody.wide) takes the same frame.

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
import 'package:kute/screens/analytics/components/home_analytics_widget.dart';
import 'package:kute/screens/home/home.dart';
import 'package:kute/screens/share/pending_share_links.dart';
import 'package:kute/screens/shared/all_activity.dart'
    show ActivityScope, AllActivitySliver, watchAllActivity;
import 'package:kute/screens/shared/kute_bar_context.dart'
    show kuteBarScrollClearance;
import 'package:kute/screens/shared/kute_motion.dart' show SelectionFade;
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
/// centred under it ([KuteBarPane]); [right] at [KuteLayout.paneWidth], a
/// phone column (its MediaQuery's width the pane's).
class BitcoinPanesFrame extends StatelessWidget {
  const BitcoinPanesFrame({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

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
                  const SizedBox(width: KuteLayout.paneGap),
                  SizedBox(
                    width: KuteLayout.paneWidth,
                    child: kuteNarrowMedia(context,
                        width: KuteLayout.paneWidth, child: right),
                  ),
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

/// The Bitcoin home's left pane on EXPANDED (see the file header): the
/// home's Activity | Goals pills, then the pill on screen.
class BitcoinHomeLeftPane extends ConsumerStatefulWidget {
  const BitcoinHomeLeftPane({super.key, required this.onRefresh});

  /// The home's pull-to-refresh ("update everything").
  final RefreshCallback onRefresh;

  @override
  ConsumerState<BitcoinHomeLeftPane> createState() =>
      _BitcoinHomeLeftPaneState();
}

class _BitcoinHomeLeftPaneState extends ConsumerState<BitcoinHomeLeftPane> {
  /// 0 the activity, 1 the goals (the phone strip's order).
  int _selected = 0;

  /// The `?tab=activity` request last honoured ([homeActivityRequest]).
  String? _request;

  // One scroll per pill, each keeping its place, as the Dollars pills.
  final _activity = ScrollController();
  final _goals = ScrollController();

  @override
  void dispose() {
    _activity.dispose();
    _goals.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final wallet = ref.watch(settingsProvider.select((s) => s.activeWallet));
    final isSavings = (wallet?.isHardware ?? false) ||
        (wallet?.isWatchOnly ?? false) ||
        (wallet?.isExternalAddress ?? false);

    // `/home?tab=activity` (kHomeActivityLocation) lands on the activity,
    // as it does on a phone.
    final request = homeActivityRequest(context);
    if (request != null && request != _request) {
      _request = request;
      _selected = 0;
    }

    // The phone strip's pills, named as it names them; on EXPANDED the
    // first one simply shows the activity here (no "See all").
    final pills = KutePillTabs(
      items: [
        KutePillItem(label: l10n.activity, icon: Icons.receipt_long_rounded),
        // Goals on the spending wallet, Balance on a Ledger or
        // watch-only wallet.
        isSavings
            ? KutePillItem(label: l10n.balance, icon: Icons.savings_rounded)
            : KutePillItem(
                label: l10n.balanceGoalsTab, icon: Icons.flag_rounded),
      ],
      selectedIndex: _selected,
      onTap: (i) {
        if (i != _selected) setState(() => _selected = i);
      },
      size: kutePillSwitchSize,
    );

    final body = SelectionFade(
      selection: _selected,
      order: _selected,
      child: IndexedStack(
        index: _selected,
        children: [
          TickerMode(
            enabled: _selected == 0,
            child: CustomScrollView(
              controller: _activity,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                _BitcoinActivity(controller: _activity, isSavings: isSavings),
                bitcoinPaneEnd(context),
              ],
            ),
          ),
          TickerMode(
            enabled: _selected == 1,
            child: CustomScrollView(
              controller: _goals,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // The Goals card as the home draws it, without its
                // Activity tab (so no strip of its own on the spending
                // wallet). Its bar action ("Share my level") centres
                // under this pane.
                BitcoinListWidthSliver(
                  sliver: SliverToBoxAdapter(
                    child: RepaintBoundary(
                      child: HomeAnalyticsWidget(
                        surface: 'home',
                        showPrice: false,
                        balanceGoals: !isSavings,
                        padding: EdgeInsets.only(top: 6.h, bottom: 24.h),
                      ),
                    ),
                  ),
                ),
                bitcoinPaneEnd(context),
              ],
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BitcoinPaneTop(child: pills),
        Expanded(
          child: bitcoinPaneScrollWatch(
            ref,
            RefreshIndicator(
              onRefresh: widget.onRefresh,
              color: c.accent,
              backgroundColor: c.surface,
              // The pill on screen's own scroll (the stack keeps the
              // other one mounted, offstage).
              notificationPredicate: (n) => n.depth == 0,
              child: body,
            ),
          ),
        ),
      ],
    );
  }
}

/// The Activity pill on EXPANDED: the full Bitcoin activity in a readable
/// column, or the home's one empty state, centred under the pills.
class _BitcoinActivity extends ConsumerWidget {
  const _BitcoinActivity({required this.controller, required this.isSavings});

  /// The pill's scroll, read to load the next page.
  final ScrollController controller;
  final bool isSavings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Whether there is any history: the same sources the list shows (the
    // spending wallet's bitcoin, or a Ledger or watch-only wallet's own
    // history, as the phone home's Activity tab).
    final bool empty;
    final bool waking;
    if (isSavings) {
      empty = !ref.watch(transactionNotifierProvider.select((t) =>
          t.homeTransactionsSorted.any((tx) =>
              tx is! PolymarketTransaction &&
              tx is! PolymarketUsdcReceive &&
              tx is! UsdbTokenTransaction)));
      waking = false;
    } else {
      final activity = watchAllActivity(ref, scope: ActivityScope.bitcoin);
      empty = activity.curated.entries.isEmpty;
      // The wallet waking up, not empty: the home's shimmer rows.
      waking =
          empty && (activity.loading || ref.watch(breezSDKProvider).isLoading);
    }

    if (empty) {
      return SliverMainAxisGroup(slivers: [
        if (!isSavings)
          const BitcoinListWidthSliver(
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [DepositWaitingLine(), PendingShareLinksCard()],
              ),
            ),
          ),
        if (waking)
          const BitcoinListWidthSliver(
            sliver: SliverToBoxAdapter(child: SkeletonRowList(count: 3)),
          )
        else
          // ONE empty state, centred in the pane, close under the pills
          // like the empty Dollars Overview (Sal's sprite carries ~20 of
          // air above him).
          const SliverToBoxAdapter(
            child: NoActivityState(padding: EdgeInsets.fromLTRB(24, 44, 24, 8)),
          ),
      ]);
    }

    return BitcoinListWidthSliver(
      sliver: SliverMainAxisGroup(slivers: [
        if (isSavings)
          const SliverToBoxAdapter(
            child:
                TransactionList(showAll: true, emptyState: NoActivityState()),
          )
        else ...[
          // A deposit waiting for a lower fee: the home's one quiet line.
          const SliverToBoxAdapter(child: DepositWaitingLine()),
          const SliverToBoxAdapter(child: PendingShareLinksCard()),
          // What the phone's See all opens, in full.
          AllActivitySliver(
              controller: controller,
              scope: ActivityScope.bitcoin,
              emptyState: const NoActivityState()),
        ],
      ]),
    );
  }
}
