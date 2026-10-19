// lib/screens/portfolio/investments_portfolio.dart
//
// The Investments tab's third pill, Portfolio (owner decision October
// 2026: it was Positions, and the Portfolio screen was behind the
// balance). Four sections under the pills, switched with the Active |
// Historic pair's small pills ([KutePill]) at the top of the list:
//
//   * P&L CHARTS (the default): the one P&L chart with its All · Investing ·
//     Predictions toggle, the Active | Historic pair over the allocation
//     donut and its figures (PortfolioStatisticsOverview), then
//     everything held at both venues (portfolioPositionsSlivers, the
//     cards the Positions pill listed), without the orders.
//     No venue on the account: the "No positions yet" empty state;
//   * ORDERS (founder request, October 2026: out of P&L charts): the
//     resting orders at both venues, Investing and Predictions, under
//     their Orders heading with the count and one Cancel all, each row
//     with its own cancel (portfolioOrdersSlivers, portfolio_orders.dart).
//     Nothing resting, or no venue: the "No open orders" empty state;
//   * ACTIVITY: the Investments activity, the one merged list
//     (portfolio_activity.dart), all of it: this is its home now, so no
//     preview and no "See all";
//   * BALANCES (last): the Dollars, Investing and Predictions tiles with
//     Move money under them (PortfolioBalanceBreakdown), moved here from
//     the top of the Portfolio screen.
//
// The section is shared state ([portfolioSectionProvider]) kept for the
// session, so the pill comes back where it was left and a link
// (`?tab=orders` lands on Orders), a filled order's "View positions" or
// a trade notification can open a section from anywhere. Only the
// section on screen is built.
//
// The Portfolio screen (OpenInvestmentsScreen) keeps all of it for the
// doors that still push it (Home's Predictions card, a venue browser's
// dock standing on its own); nothing on Investments opens it any more.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart'
    show kuteDockScrollClearance;
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show portfolioOrdersSlivers, portfolioPositionsSlivers;
import 'package:kute/screens/portfolio/portfolio_activity.dart';
import 'package:kute/screens/portfolio/portfolio_balance_breakdown.dart';
import 'package:kute/screens/portfolio/portfolio_empty_state.dart';
import 'package:kute/screens/portfolio/portfolio_filters.dart';
import 'package:kute/screens/portfolio/portfolio_statistics.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart' show KutePill;
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/transactions_builder.dart'
    show buildNoTransactionsFound;

/// The Portfolio pill's sections, in pill order. [key] is the analytics
/// value (`sub` on `analytics_tab_selected`) and the link vocabulary,
/// fixed English.
enum PortfolioSection {
  charts('charts'),
  orders('orders'),
  activity('activity'),
  balances('balances');

  const PortfolioSection(this.key);

  final String key;

  /// The section an Investments link lands on (`/usd?tab=…`), or null
  /// when the link names no Portfolio section (a venue pill, nothing).
  /// The Positions pill and the old Portfolio pill, with its Open and
  /// Statistics tabs, are Charts (where the chart and the positions are);
  /// the old Orders tab is Orders, the old Activity tab is Activity.
  static PortfolioSection? forLink(String? key) => switch (key) {
        'positions' ||
        'portfolio' ||
        'open' ||
        'statistics' ||
        'charts' =>
          PortfolioSection.charts,
        'orders' => PortfolioSection.orders,
        'balances' => PortfolioSection.balances,
        'activity' => PortfolioSection.activity,
        _ => null,
      };
}

/// The section on screen, kept for the session (see the file header).
final portfolioSectionProvider =
    StateProvider<PortfolioSection>((_) => PortfolioSection.charts);

/// The Portfolio pill's page: the section pills at the top of the list,
/// the section under them (see the file header). [onSection] is a pill
/// tap; the Investments screen reports it and writes the section.
class InvestmentsPortfolio extends ConsumerWidget {
  const InvestmentsPortfolio({super.key, required this.onSection});

  final ValueChanged<PortfolioSection> onSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(portfolioSectionProvider);
    final pills = _SectionPills(selected: section, onPick: onSection);
    return KeyedSubtree(
      key: ValueKey('portfolio-section-${section.key}'),
      child: switch (section) {
        PortfolioSection.charts => _Charts(pills: pills),
        PortfolioSection.orders => _Orders(pills: pills),
        PortfolioSection.balances => _Balances(pills: pills),
        PortfolioSection.activity => _Activity(pills: pills),
      },
    );
  }
}

/// P&L charts | Orders | Activity | Balances: the Active | Historic pair's small pills
/// at their natural width; under very large text they share the row
/// rather than overflow it.
class _SectionPills extends StatelessWidget {
  const _SectionPills({required this.selected, required this.onPick});

  final PortfolioSection selected;
  final ValueChanged<PortfolioSection> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sections = PortfolioSection.values;
    return Row(
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) SizedBox(width: 6.w),
          Flexible(
            child: KutePill(
              key: ValueKey('portfolio-section-pill-${sections[i].key}'),
              label: switch (sections[i]) {
                PortfolioSection.charts => l10n.portfolioSectionPnlCharts,
                PortfolioSection.orders => l10n.portfolioTabOrders,
                PortfolioSection.balances => l10n.portfolioSectionBalances,
                PortfolioSection.activity => l10n.activity,
              },
              selected: sections[i] == selected,
              onTap: () => onPick(sections[i]),
            ),
          ),
        ],
      ],
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

/// Charts: the Portfolio screen's chart, pair and figures, then the
/// positions; the resting orders are [_Orders] (see the file header).
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
    final footer = portfolioPositionsSlivers(context, ref, venues);
    return PortfolioStatisticsOverview(
      key: const ValueKey('statistics-overview'),
      trading: venues.trading,
      predictions: venues.predictions,
      header: Padding(padding: EdgeInsets.only(bottom: 12.h), child: pills),
      footer: footer,
      footerEmpty: footer.isEmpty,
    );
  }
}

/// Orders: the resting orders at both venues with their cancels
/// (portfolioOrdersSlivers); nothing resting, or no venue, the Portfolio
/// empty state.
class _Orders extends ConsumerWidget {
  const _Orders({required this.pills});

  final Widget pills;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venues = ref.watch(portfolioVenuesProvider);
    final orders = portfolioOrdersSlivers(context, ref, venues);
    if (orders.isEmpty) {
      return CustomScrollView(slivers: [
        _pillsSliver(pills),
        SliverFillRemaining(
            child: PortfolioEmptyState(context.l10n.portfolioNoOpenOrders,
                key: const ValueKey('portfolio-orders-empty'))),
      ]);
    }
    return CustomScrollView(
      key: const ValueKey('portfolio-orders-list'),
      slivers: [
        _pillsSliver(pills),
        ...orders,
        _dockClearance(context),
      ],
    );
  }
}

/// Balances: the tiles and Move money (PortfolioBalanceBreakdown).
class _Balances extends ConsumerWidget {
  const _Balances({required this.pills});

  final Widget pills;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venues = ref.watch(portfolioVenuesProvider);
    return CustomScrollView(slivers: [
      _pillsSliver(pills),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
        sliver: SliverToBoxAdapter(
          child: PortfolioBalanceBreakdown(
              trading: venues.trading, predictions: venues.predictions),
        ),
      ),
      _dockClearance(context),
    ]);
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
