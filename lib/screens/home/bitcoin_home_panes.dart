// lib/screens/home/bitcoin_home_panes.dart
//
// THE BITCOIN HOME ON A WIDE WINDOW (kute_layout.dart). The wallet home
// itself is never redesigned (founder's standing rule), so it is drawn
// exactly as it is, as a phone column:
//
//   * COMPACT: the home, untouched.
//   * MEDIUM: the home in a centred [KuteLayout.columnMaxWidth] column.
//   * EXPANDED: the home as a [KuteLayout.paneWidth] phone column on the
//     left and, beside it, what sits behind a tap from it on a phone: the
//     balance history (the Balance pill's chart, [HomeAnalyticsWidget]
//     with no Activity tab) and the full Bitcoin activity (the list "See
//     all" opens, [AllActivitySliver] in the Bitcoin scope), both their
//     own widgets, under the app's section headers. Each pane scrolls on
//     its own.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/analytics/components/home_analytics_widget.dart';
import 'package:kute/screens/share/pending_share_links.dart';
import 'package:kute/screens/shared/all_activity.dart'
    show ActivityScope, AllActivitySliver;
import 'package:kute/screens/shared/investment_market_browser.dart'
    show InvestmentSectionHeader;
import 'package:kute/screens/shared/kute_bar_context.dart'
    show kuteBarScrollClearance;

/// The widest the side pane grows on a large window; past it the two
/// panes stay together, centred, rather than the lists stretching.
const double _kSidePaneMaxWidth = 760;

/// The room the shell's top nav takes over the panes (the home's own top
/// sliver, home.dart).
double _navClearance() => 64.h;

/// [home] as the form factor wants it (see the file header).
class BitcoinHomePanes extends StatelessWidget {
  const BitcoinHomePanes({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    final window = MediaQuery.sizeOf(context).width;
    switch (KuteLayout.forWidth(window)) {
      case KuteFormFactor.compact:
        return home;
      case KuteFormFactor.medium:
        return KuteFormColumn(child: home);
      case KuteFormFactor.expanded:
        const gap = KuteLayout.paneGap;
        final room = math.min(window, KuteLayout.pageMaxWidth) - 2 * gap;
        final side = math.min(_kSidePaneMaxWidth,
            math.max(0.0, room - KuteLayout.paneWidth - gap));
        return Center(
          child: SizedBox(
            width: KuteLayout.paneWidth + gap + side,
            height: double.infinity,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: KuteLayout.paneWidth,
                  child: kuteNarrowMedia(context,
                      width: KuteLayout.paneWidth, child: home),
                ),
                const SizedBox(width: gap),
                SizedBox(
                  width: side,
                  child: kuteNarrowMedia(context,
                      width: side, child: const _BitcoinSidePane()),
                ),
              ],
            ),
          ),
        );
    }
  }
}

/// The balance history and the full Bitcoin activity, beside the home.
class _BitcoinSidePane extends ConsumerStatefulWidget {
  const _BitcoinSidePane();

  @override
  ConsumerState<_BitcoinSidePane> createState() => _BitcoinSidePaneState();
}

class _BitcoinSidePaneState extends ConsumerState<_BitcoinSidePane> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(settingsProvider.select((s) => s.activeWallet));
    final isSavings = (wallet?.isHardware ?? false) ||
        (wallet?.isWatchOnly ?? false) ||
        (wallet?.isExternalAddress ?? false);
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: _navClearance())),
          SliverToBoxAdapter(
            child: InvestmentSectionHeader(
                label: isSavings
                    ? context.l10n.balance
                    : context.l10n.balanceGoalsTab),
          ),
          // The Balance pill's chart (and, on the spending wallet, its
          // goals), as the home draws it; no Activity tab, so no strip.
          SliverToBoxAdapter(
            child: RepaintBoundary(
              child: HomeAnalyticsWidget(
                surface: 'home',
                showPrice: false,
                balanceGoals: !isSavings,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: InvestmentSectionHeader(label: context.l10n.activity),
          ),
          // What the home's See all opens: its bitcoin, in full.
          const SliverToBoxAdapter(child: PendingShareLinksCard()),
          AllActivitySliver(controller: _scroll, scope: ActivityScope.bitcoin),
          SliverPadding(
              padding: EdgeInsets.only(
                  bottom: 24.h +
                      kuteBarScrollClearance.h +
                      MediaQuery.paddingOf(context).bottom)),
        ],
      ),
    );
  }
}
