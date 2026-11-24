// lib/screens/home/bitcoin_home_panes.dart
//
// THE BITCOIN HOME ON A WIDE WINDOW (kute_layout.dart). The wallet home
// itself is never redesigned (founder's standing rule), so it is drawn
// exactly as it is, as a phone column:
//
//   * COMPACT: the home, untouched.
//   * MEDIUM: the home in a centred [KuteLayout.columnMaxWidth] column.
//   * EXPANDED (founder, 25 November 2026: "still not centered. No
//     activity must be in center"): ONE centred page in the home's own
//     scroll. The hero (backup banner, balance, Purchase / Scan / Receive
//     / Send) at phone width, centred at the top ([Home.wideBelow]); its
//     Activity | Goals strip left out ([Home.showActivity]) and, under the
//     hero on the same axis:
//       - nothing yet: the home's one empty state (its Sal and "No
//         activity yet"), centred at phone width; no empty Goals card;
//       - with history: the balance chart (the Goals tab's card,
//         [HomeAnalyticsWidget] with no Activity tab) and the full
//         Bitcoin activity (what "See all" opens, [AllActivitySliver])
//         side by side, two equal columns under the app's section
//         headers, the pair at most [_kPairMaxWidth] and centred.
//     No floating bar of its own on EXPANDED (the search lives in the
//     desktop top bar), so no [KuteBarPane] either.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show BoxParentData, SliverPhysicalParentData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/screens/analytics/components/home_analytics_widget.dart';
import 'package:kute/screens/home/home.dart';
import 'package:kute/screens/share/pending_share_links.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/no_activity_state.dart';
import 'package:kute/screens/shared/transactions_builder.dart'
    show DepositWaitingLine, TransactionList;
import 'package:kute/screens/shared/all_activity.dart'
    show ActivityScope, AllActivitySliver, watchAllActivity;
import 'package:kute/screens/shared/investment_market_browser.dart'
    show InvestmentSectionHeader;
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;

/// The balance chart and the activity side by side: at most this wide
/// together, centred under the hero.
const double _kPairMaxWidth = 960;

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
        return Home(
          showActivity: false,
          wideBelow: (controller) =>
              [_BitcoinHomeBelow(controller: controller)],
        );
    }
  }
}

/// A sliver at phone width ([KuteLayout.paneWidth]), centred in its
/// scroll view, with the MediaQuery's width the phone's (a phone widget
/// inside lays out as it does on a phone). Full width when the view is
/// no wider than a phone.
class KutePhoneWidthSliver extends StatelessWidget {
  const KutePhoneWidthSliver({super.key, required this.sliver});

  final Widget sliver;

  @override
  Widget build(BuildContext context) => _CentredSliver(
        maxWidth: KuteLayout.paneWidth,
        gutter: 0,
        sliver: sliver,
      );
}

/// [sliver] at most [maxWidth] wide (and [gutter] clear of each side),
/// centred, with the MediaQuery narrowed to that width.
class _CentredSliver extends StatelessWidget {
  const _CentredSliver(
      {required this.maxWidth, required this.gutter, required this.sliver});

  final double maxWidth;
  final double gutter;
  final Widget sliver;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
        builder: (context, constraints) {
          final room = constraints.crossAxisExtent;
          final width = math.max(0.0, math.min(maxWidth, room - 2 * gutter));
          return SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: (room - width) / 2),
            sliver: kuteNarrowMedia(context, width: width, child: sliver),
          );
        },
      );
}

/// What sits under the hero on EXPANDED (see the file header).
class _BitcoinHomeBelow extends ConsumerWidget {
  const _BitcoinHomeBelow({required this.controller});

  /// The home's scroll, read to load the next page of activity.
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(settingsProvider.select((s) => s.activeWallet));
    final isSavings = (wallet?.isHardware ?? false) ||
        (wallet?.isWatchOnly ?? false) ||
        (wallet?.isExternalAddress ?? false);

    // Whether there is any history: the same sources the two columns
    // list (the spending wallet's bitcoin, or a Ledger or watch-only
    // wallet's own history, as the phone home's Activity tab).
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

    const gap = KuteLayout.paneGap;
    final bottom = SizedBox(height: 24.h);

    if (empty) {
      // ONE empty state, centred under the hero.
      return KutePhoneWidthSliver(
        sliver: SliverToBoxAdapter(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isSavings) const DepositWaitingLine(),
              if (!isSavings) const PendingShareLinksCard(),
              if (waking)
                const SkeletonRowList(count: 3)
              else
                const NoActivityState(),
              bottom,
            ],
          ),
        ),
      );
    }

    return _CentredSliver(
      maxWidth: _kPairMaxWidth,
      gutter: gap,
      sliver: SliverLayoutBuilder(builder: (context, constraints) {
        final column = (constraints.crossAxisExtent - gap) / 2;
        Widget narrow(Widget sliver) =>
            kuteNarrowMedia(context, width: column, child: sliver);
        return SliverCrossAxisGroup(
          slivers: [
            // The balance chart: the Goals tab's card, as the home draws
            // it, without its Activity tab (so no strip).
            SliverCrossAxisExpanded(
              flex: 1,
              sliver: narrow(SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InvestmentSectionHeader(
                        label: isSavings
                            ? context.l10n.balance
                            : context.l10n.balanceGoalsTab),
                    // Its bar action ("Share my level") under this
                    // column, not across the pair's middle.
                    _ColumnBarPane(
                      child: RepaintBoundary(
                        child: HomeAnalyticsWidget(
                          surface: 'home',
                          showPrice: false,
                          balanceGoals: !isSavings,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
            ),
            const SliverConstrainedCrossAxis(
              maxExtent: gap,
              sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
            // The activity: what the home's See all opens, in full.
            SliverCrossAxisExpanded(
              flex: 1,
              sliver: narrow(SliverMainAxisGroup(slivers: [
                SliverToBoxAdapter(
                  child: InvestmentSectionHeader(label: context.l10n.activity),
                ),
                if (isSavings)
                  const SliverToBoxAdapter(
                    child: TransactionList(
                        showAll: true, emptyState: NoActivityState()),
                  )
                else ...[
                  // A deposit waiting for a lower fee: the home's one
                  // quiet line.
                  const SliverToBoxAdapter(child: DepositWaitingLine()),
                  const SliverToBoxAdapter(child: PendingShareLinksCard()),
                  AllActivitySliver(
                      controller: controller,
                      scope: ActivityScope.bitcoin,
                      emptyState: const NoActivityState()),
                ],
                SliverToBoxAdapter(child: bottom),
              ])),
            ),
          ],
        );
      }),
    );
  }
}

/// [KuteBarPane] for a column inside the home's scroll: the floating bar's
/// contextual action (the Goals card's "Share my level") centres under
/// this column on EXPANDED. Measured like [KuteBarPane], by layout alone
/// (a tab sliding in never moves the bar), but through the scroll's
/// slivers too, whose children carry their offsets as paint offsets.
class _ColumnBarPane extends StatefulWidget {
  const _ColumnBarPane({required this.child});

  final Widget child;

  @override
  State<_ColumnBarPane> createState() => _ColumnBarPaneState();
}

class _ColumnBarPaneState extends State<_ColumnBarPane> {
  final _key = GlobalKey();

  void _report(bool active, Route<dynamic>? route) {
    if (!mounted) return;
    if (!active) {
      if (identical(kuteBarPane.value?.owner, this)) kuteBarPane.value = null;
      return;
    }
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return;
    var left = 0.0;
    RenderObject? node = box;
    while (node != null && node.parent != null) {
      final data = node.parentData;
      if (data is BoxParentData) {
        left += data.offset.dx;
      } else if (data is SliverPhysicalParentData) {
        left += data.paintOffset.dx;
      }
      node = node.parent;
    }
    final span = KuteBarPaneSpan(
        owner: this, route: route, left: left, width: box.size.width);
    if (kuteBarPane.value != span) kuteBarPane.value = span;
  }

  @override
  void dispose() {
    final owner = this;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(kuteBarPane.value?.owner, owner)) kuteBarPane.value = null;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    MediaQuery.sizeOf(context);
    final expanded = KuteLayout.forWidth(kuteWindowWidth(context)) ==
        KuteFormFactor.expanded;
    final shown = TickerMode.valuesOf(context).enabled;
    final route = ModalRoute.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _report(expanded && shown, route));
      return KeyedSubtree(key: _key, child: widget.child);
    });
  }
}
