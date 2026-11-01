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
//   * no ACTIVITY section any more (founder, 1 November 2026): the
//     activity lives on the Bitcoin home; a `?tab=activity` link goes there
//     (app_router.dart).
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
// section pills are the home strip (Portfolio | P&L Charts in two
// halves, the picked one the white pill with the hairline and the
// shadow, [_SectionPills]); on the Portfolio section the strip sits under
// the shares card and Move money (BalancesOverview.sectionSwitch, handed
// through the breakdown), on P&L Charts at the top of the list. Both
// sections speak one language (founder, 1 November 2026: "the vibes are
// different"): flat on the page background in the 16 gutters, a 13 sp
// sentence-case section title ("Investing · 2", "Profit and loss"), the
// same rows (position_rows.dart: logo 32, title 15 w500, sub 13, figure
// 15 w600 with its change 12 under it, a 14 rhythm), no card.
//
// Empty, both sections draw ONE empty state at one place under the strip
// (founder, 1 November 2026; PortfolioSectionEmpty,
// portfolio_empty_state.dart): the hero Sal at 160, "No open positions"
// or "No P&L yet" and the tagline; switching moves
// nothing but the copy. P&L Charts never opens on a blank frame: what it
// decides on is kept warm under the strip, and a read genuinely still on
// its way is a skeleton of the chart's own size.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidUserFillsProvider;
import 'package:kute/screens/home/components/kute_dock_host.dart'
    show kuteDockScrollClearance;
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show portfolioVenueLists;
import 'package:kute/screens/portfolio/portfolio_balance_breakdown.dart';
import 'package:kute/screens/portfolio/portfolio_empty_state.dart';
import 'package:kute/screens/portfolio/portfolio_filters.dart';
import 'package:kute/screens/portfolio/portfolio_orders.dart';
import 'package:kute/screens/portfolio/portfolio_statistics.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart'
    show KutePill, KutePillSize;

/// The Portfolio pill's sections, in pill order. [key] is the analytics
/// value (`sub` on `analytics_tab_selected`) and the link vocabulary,
/// fixed English. The Positions section is gone (27 October 2026): its
/// `positions` value is no longer sent, Balances' `balances` stands for it.
enum PortfolioSection {
  balances('balances'),
  charts('charts');

  const PortfolioSection(this.key);

  final String key;

  /// The section an Investments link lands on (`/usd?tab=…`), or null
  /// when the link names no Portfolio section (a venue pill, nothing).
  /// The old Positions section and pill, and the old Portfolio pill with
  /// its Open tab, are Balances (where the positions are now); the old
  /// Orders and Statistics tabs are P&L charts (where the chart and the
  /// orders are). The old Activity tab names none: the activity is on
  /// the Bitcoin home now, where app_router.dart sends `?tab=activity`.
  static PortfolioSection? forLink(String? key) => switch (key) {
        'balances' ||
        'positions' ||
        'portfolio' ||
        'open' =>
          PortfolioSection.balances,
        'orders' || 'statistics' || 'charts' => PortfolioSection.charts,
        _ => null,
      };
}

/// The Bitcoin home on its Activity (`?tab=activity`): where the
/// activity lives since it left the Portfolio (founder, 1 November 2026).
const String kHomeActivityLocation = '/home?tab=activity';

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
    if (sharesHeader) {
      // THE PINNED TOP (founder, 31 October 2026: "this part should remain
      // stable in P&L"): one hero instance (the ring, the
      // Invested / Available line, the strip) above every section, the
      // same widget across switches, so nothing jumps; under it the
      // section alone scrolls (the Balances venues, the P&L card, the
      // the orders), with no strip of its own.
      final venues = ref.watch(portfolioVenuesProvider);
      // P&L Charts opens on its final state, never a blank frame: what it
      // decides on is kept warm under the strip whatever section is on
      // screen (the venues' P&L series are, by the ring's all-time P&L;
      // the Investing fills here).
      if (venues.trading) {
        ref.listen(hyperliquidUserFillsProvider, (_, __) {});
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            key: const ValueKey('portfolio-pinned-top'),
            padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 0),
            child: PortfolioBalanceBreakdown(
              trading: venues.trading,
              predictions: venues.predictions,
              overview: true,
              sharesHeader: true,
              heroOnly: true,
              sectionSwitch: pills,
            ),
          ),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey('portfolio-section-${section.key}'),
              child: switch (section) {
                PortfolioSection.balances => const _Balances(
                    pills: SizedBox.shrink(),
                    sharesHeader: true,
                    venuesOnly: true),
                PortfolioSection.charts =>
                  const _Charts(pills: SizedBox.shrink(), showPills: false),
              },
            ),
          ),
        ],
      );
    }
    return KeyedSubtree(
      key: ValueKey('portfolio-section-${section.key}'),
      child: switch (section) {
        PortfolioSection.balances =>
          _Balances(pills: pills, sharesHeader: sharesHeader),
        PortfolioSection.charts => _Charts(pills: pills),
      },
    );
  }
}

/// Portfolio | P&L Charts: the home strip (KutePillTabs' tab
/// row, the same chrome drawn here so each pill keeps its key): three
/// pills in equal halves across the width, the picked one the white pill
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
  const _Charts({required this.pills, this.showPills = true});

  final Widget pills;

  /// False under the Portfolio screen's pinned top, which holds the strip.
  final bool showPills;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venues = ref.watch(portfolioVenuesProvider);
    // Under the Portfolio screen's strip: the sections' one empty state
    // (portfolio_empty_state.dart), where Portfolio puts its own.
    final sectionEmpty = showPills
        ? null
        : PortfolioSectionEmptyPage(
            key: const ValueKey('statistics-chart-empty'),
            title: context.l10n.pnlNoHistoryTitle,
            tagline: PortfolioSectionTagline.pnl);
    if (!venues.any) {
      if (sectionEmpty != null) return sectionEmpty;
      return CustomScrollView(slivers: [
        if (showPills) _pillsSliver(pills),
        SliverFillRemaining(
            child: PortfolioEmptyState(context.l10n.ledgerNoPositionsYet)),
      ]);
    }
    return PortfolioStatisticsOverview(
      key: const ValueKey('statistics-overview'),
      trading: venues.trading,
      predictions: venues.predictions,
      orders: PortfolioOrdersBook.watch(ref, venues),
      sectionEmpty: sectionEmpty,
      header: showPills
          ? Padding(padding: EdgeInsets.only(bottom: 12.h), child: pills)
          : SizedBox(height: 4.h),
    );
  }
}

/// Balances: Available to invest with the ring, Move money under it, then
/// each venue's first positions under it (PortfolioBalanceBreakdown in its
/// overview layout, the rows from [portfolioVenueLists]). The Portfolio
/// screen ([sharesHeader]): the shares card, Move money, the section
/// strip under them, then the venues (see the file header).
class _Balances extends ConsumerWidget {
  const _Balances(
      {required this.pills,
      this.sharesHeader = false,
      this.venuesOnly = false});

  final Widget pills;
  final bool sharesHeader;

  /// Under the Portfolio screen's pinned top: only the venues' positions
  /// (PortfolioBalanceBreakdown.venuesOnly), no hero, no strip.
  final bool venuesOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venues = ref.watch(portfolioVenuesProvider);
    return CustomScrollView(
      key: const ValueKey('portfolio-balances-list'),
      slivers: [
        if (!sharesHeader) _pillsSliver(pills),
        SliverPadding(
          padding:
              EdgeInsets.fromLTRB(16.w, sharesHeader ? 4.h : 12.h, 16.w, 0),
          sliver: SliverToBoxAdapter(
            child: PortfolioBalanceBreakdown(
                trading: venues.trading,
                predictions: venues.predictions,
                overview: true,
                sharesHeader: sharesHeader,
                sectionSwitch: sharesHeader && !venuesOnly ? pills : null,
                venuesOnly: venuesOnly,
                refreshOnOpen: !venuesOnly,
                venues: portfolioVenueLists(context, ref, venues)),
          ),
        ),
        _dockClearance(context),
      ],
    );
  }
}
