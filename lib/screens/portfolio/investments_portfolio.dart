// lib/screens/portfolio/investments_portfolio.dart
//
// The Investments tab's third pill, Portfolio (owner decision October
// 2026: it was Positions, and the Portfolio screen was behind the
// balance). Three sections under the pills, switched with the Active |
// Historic pair's small pills ([KutePill]) at the top of the list
// (founder decision 27 October 2026: the Positions section is gone, its
// rows live under their venue in Balances):
//
//   * BALANCES (the "Portfolio" pill, first, the default; lighter since
//     the founder's 28 October 2026 review): the small bare ring beside
//     "Available to invest" with its amount and chevron at the line's
//     end, its split (Hyperliquid, Polymarket, Dollars) opened in place,
//     Move money under that line, then each venue and its 3 largest
//     positions, the Option-B position rows with their taps and sheets,
//     and a quiet "See all  N" that opens the rest (settled ones last) in
//     place (PortfolioBalanceBreakdown in its overview layout,
//     components/balances_overview.dart, the rows from
//     portfolioVenueLists in open_investments_screen.dart);
//   * P&L CHARTS (what is done only, founder decision 28 October 2026: no
//     Active | Historic pair): ONE card, "Profit and loss" with the
//     realised P&L big in the result colour, the chart under it with its
//     range pills, a hairline, then one line per venue with its realised
//     P&L, a line tapped charting that venue alone; the resting orders
//     under the card, each row with its own cancel, one quiet Cancel all
//     link only with orders at both venues (PortfolioStatisticsOverview,
//     portfolio_statistics.dart; the orders from PortfolioOrdersBook,
//     portfolio_orders.dart). No venue on the account: the "No positions
//     yet" empty state;
//   * ACTIVITY: the Investments activity, the one merged list
//     (portfolio_activity.dart), all of it: this is its home now, so no
//     preview and no "See all".
//
// The section is shared state ([portfolioSectionProvider]) kept for the
// session, so the pill comes back where it was left and a link
// (`?tab=orders` lands on P&L charts, where the orders are; the old
// `?tab=positions|portfolio|open` on Balances), a filled order's "View
// positions" (Balances), a placed order's "View orders" or a trade
// notification can open a section from anywhere. Only the section on
// screen is built.
//
// The Portfolio screen (OpenInvestmentsScreen) keeps its own layout for
// the doors that still push it (Home's Predictions card, a venue
// browser's dock standing on its own); nothing on Investments opens it
// any more.
//
// THE PORTFOLIO SCREEN (portfolio_screen.dart, [sharesHeader]): the
// section pills are the home strip (Portfolio | P&L Charts | Activity in
// equal thirds, the picked one the white pill with the hairline and the
// shadow, [_SectionPills]); on the Portfolio section the strip sits under
// the shares card and Move money (BalancesOverview.sectionSwitch, handed
// through the breakdown), on the other two at the top of the list.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart'
    show kuteDockScrollClearance;
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show portfolioVenueLists;
import 'package:kute/screens/portfolio/portfolio_activity.dart';
import 'package:kute/screens/portfolio/portfolio_balance_breakdown.dart';
import 'package:kute/screens/portfolio/portfolio_empty_state.dart';
import 'package:kute/screens/portfolio/portfolio_filters.dart';
import 'package:kute/screens/portfolio/portfolio_orders.dart';
import 'package:kute/screens/portfolio/portfolio_statistics.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart'
    show KutePill, KutePillSize;
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/transactions_builder.dart'
    show buildNoTransactionsFound;

/// The Portfolio pill's sections, in pill order. [key] is the analytics
/// value (`sub` on `analytics_tab_selected`) and the link vocabulary,
/// fixed English. The Positions section is gone (27 October 2026): its
/// `positions` value is no longer sent, Balances' `balances` stands for it.
enum PortfolioSection {
  balances('balances'),
  charts('charts'),
  activity('activity');

  const PortfolioSection(this.key);

  final String key;

  /// The section an Investments link lands on (`/usd?tab=…`), or null
  /// when the link names no Portfolio section (a venue pill, nothing).
  /// The old Positions section and pill, and the old Portfolio pill with
  /// its Open tab, are Balances (where the positions are now); the old
  /// Orders and Statistics tabs are P&L charts (where the chart and the
  /// orders are); the old Activity tab is Activity.
  static PortfolioSection? forLink(String? key) => switch (key) {
        'balances' ||
        'positions' ||
        'portfolio' ||
        'open' =>
          PortfolioSection.balances,
        'orders' || 'statistics' || 'charts' => PortfolioSection.charts,
        'activity' => PortfolioSection.activity,
        _ => null,
      };
}

/// The section on screen, kept for the session (see the file header).
final portfolioSectionProvider =
    StateProvider<PortfolioSection>((_) => PortfolioSection.balances);

/// The Portfolio pill's page: the section pills at the top of the list,
/// the section under them (see the file header). [onSection] is a pill
/// tap; the Investments screen reports it and writes the section.
class InvestmentsPortfolio extends ConsumerWidget {
  const InvestmentsPortfolio(
      {super.key,
      required this.onSection,
      this.sectionPills = true,
      this.sharesHeader = false});

  final ValueChanged<PortfolioSection> onSection;

  /// The Portfolio screen: the shares block (ring and shares) over the
  /// positions instead of Available to invest and Move money.
  final bool sharesHeader;

  /// False inside Investments, where the page's Portfolio pill carries
  /// the section and opens the pick (investments_category_sheet.dart).
  final bool sectionPills;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(portfolioSectionProvider);
    final Widget pills = sectionPills
        ? _SectionPills(selected: section, onPick: onSection)
        : const SizedBox.shrink();
    return KeyedSubtree(
      key: ValueKey('portfolio-section-${section.key}'),
      child: switch (section) {
        PortfolioSection.balances =>
          _Balances(pills: pills, sharesHeader: sharesHeader),
        PortfolioSection.charts => _Charts(pills: pills),
        PortfolioSection.activity => _Activity(pills: pills),
      },
    );
  }
}

/// Portfolio | P&L Charts | Activity: the home strip (KutePillTabs' tab
/// row, the same chrome drawn here so each pill keeps its key): three
/// pills in equal thirds across the width, the picked one the white pill
/// with the hairline border and the shadow, the others transparent.
class _SectionPills extends StatelessWidget {
  const _SectionPills({required this.selected, required this.onPick});

  final PortfolioSection selected;
  final ValueChanged<PortfolioSection> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sections = PortfolioSection.values;
    return SizedBox(
      height: KutePillSize.regular.height.h,
      child: Row(
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) SizedBox(width: 6.w),
            Expanded(
              child: KutePill(
                key: ValueKey('portfolio-section-pill-${sections[i].key}'),
                label: switch (sections[i]) {
                  PortfolioSection.charts => l10n.portfolioSectionPnlCharts,
                  PortfolioSection.balances => l10n.portfolioSectionBalances,
                  PortfolioSection.activity => l10n.activity,
                },
                selected: sections[i] == selected,
                fillWidth: true,
                onTap: () => onPick(sections[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The pills on the lists' 16 gutter, as the first sliver of a section.
Widget _pillsSliver(Widget pills) => SliverPadding(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 0),
      sliver: SliverToBoxAdapter(child: pills),
    );

/// The last row clear of the home indicator or the dock.
Widget _dockClearance(BuildContext context) => SliverToBoxAdapter(
    child: SizedBox(height: 32.h + kuteDockScrollClearance(context)));

/// P&L charts: the one card (the realised figure, the chart, the venue
/// lines), the resting orders under it (see the file header).
class _Charts extends ConsumerWidget {
  const _Charts({required this.pills});

  final Widget pills;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venues = ref.watch(portfolioVenuesProvider);
    if (!venues.any) {
      return CustomScrollView(slivers: [
        _pillsSliver(pills),
        SliverFillRemaining(
            child: PortfolioEmptyState(context.l10n.ledgerNoPositionsYet)),
      ]);
    }
    return PortfolioStatisticsOverview(
      key: const ValueKey('statistics-overview'),
      trading: venues.trading,
      predictions: venues.predictions,
      orders: PortfolioOrdersBook.watch(ref, venues),
      header: Padding(padding: EdgeInsets.only(bottom: 12.h), child: pills),
    );
  }
}

/// Balances: Available to invest with the ring, Move money under it, then
/// each venue's first positions under it (PortfolioBalanceBreakdown in its
/// overview layout, the rows from [portfolioVenueLists]). The Portfolio
/// screen ([sharesHeader]): the shares card, Move money, the section
/// strip under them, then the venues (see the file header).
class _Balances extends ConsumerWidget {
  const _Balances({required this.pills, this.sharesHeader = false});

  final Widget pills;
  final bool sharesHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venues = ref.watch(portfolioVenuesProvider);
    return CustomScrollView(
      key: const ValueKey('portfolio-balances-list'),
      slivers: [
        if (!sharesHeader) _pillsSliver(pills),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16.w, sharesHeader ? 4.h : 12.h, 16.w, 0),
          sliver: SliverToBoxAdapter(
            child: PortfolioBalanceBreakdown(
                trading: venues.trading,
                predictions: venues.predictions,
                overview: true,
                sharesHeader: sharesHeader,
                sectionSwitch: sharesHeader ? pills : null,
                venues: portfolioVenueLists(context, ref, venues)),
          ),
        ),
        _dockClearance(context),
      ],
    );
  }
}

/// Activity: the whole merged list, on Home's day cards; its shimmer
/// rows while the Investing history is on its way; the app's "no
/// transactions" line when there is nothing.
class _Activity extends ConsumerWidget {
  const _Activity({required this.pills});

  final Widget pills;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = watchPortfolioActivity(ref);
    final Widget body;
    if (activity.entries.isNotEmpty || activity.failed) {
      body = PortfolioActivitySliver(
          key: const ValueKey('portfolio-activity-list'),
          entries: activity.entries,
          failed: activity.failed);
    } else if (activity.loading) {
      body = SliverToBoxAdapter(
        child: SkeletonRowList(
            key: const ValueKey('portfolio-activity-loading'),
            count: 3,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 24.h)),
      );
    } else {
      body = SliverToBoxAdapter(child: buildNoTransactionsFound(context));
    }
    return CustomScrollView(slivers: [
      _pillsSliver(pills),
      SliverPadding(padding: EdgeInsets.only(top: 8.h), sliver: body),
      _dockClearance(context),
    ]);
  }
}
