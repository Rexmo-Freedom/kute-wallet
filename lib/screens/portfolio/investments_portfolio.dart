// lib/screens/portfolio/investments_portfolio.dart
//
// THE PORTFOLIO SCREEN'S PAGE (portfolio_screen.dart), redone on 4
// November 2026 (founder: "the top chart means nothing, it's super
// confusing … the portfolio screen when users click there must be
// completely overhauled to have a much, much, much better fintech design
// comparable to the rest of the app"). One scroll, top down:
//
//   * THE HERO (components/portfolio_hero.dart): "Invested" over what the
//     open positions are worth now, the P&L over the range picked under
//     it, ONE P&L chart with the app's range row, and "3 positions ·
//     Available $17.64". The allocation ring that adapted to each section
//     is gone; the hero is one instance whatever the section, and reads
//     it (founder, 5 November 2026): on Positions only the positions open
//     now (their P&L now, the chart folded away), on P&L the venue square
//     picked alone (portfolioPnlVenueProvider, dropped when P&L is left);
//   * the section switch, pinned under the app bar once it reaches it
//     ([_StripHeader]): Activity | Positions | P&L (KutePillTabs at the
//     app's switch size, equal thirds, the one white pill sliding);
//   * the section ([PortfolioSection], shared state kept for the
//     session, Activity first and the default):
//       - ACTIVITY (portfolio_activity.dart, PortfolioActivitySection):
//         the bets placed, sold, won or lost and the Investing opens and
//         closes, the newest four as the home's Latest squares, the next
//         two as its Earlier rows, then its "See all";
//       - POSITIONS (the `balances` section, its key kept for links and
//         analytics): the biggest open positions as squares, the rest as
//         the Investing list's rows under their venue
//         (PortfolioBalanceBreakdown.venuesOnly, components/
//         balances_overview.dart);
//       - P&L (the `charts` section): each venue's P&L ("By venue", two
//         big squares side by side, each venue's P&L over the hero's range
//         with its sparkline across the bottom), the all-time stats
//         (realised, unrealised, win rate) as compact tiles in one row,
//         and the resting orders, each row with its own cancel
//         (PortfolioStatisticsOverview without its chart,
//         portfolio_statistics.dart). The chart is the hero's.
//
// Every section starts [kPortfolioSectionEmptyTop] under the strip, its
// empty state the one treatment (Sal, portfolio_empty_state.dart), and
// ends with the bar's clearance inside the scroll. Only the section on
// screen is built; the hero is one instance across switches. A switch
// keeps the top block where it is: a section scrolled past the pin opens
// the next at its top under the pinned strip, and a short section is at
// least the viewport under the strip tall, so the strip never drops.
//
// The section is shared state ([portfolioSectionProvider]) so a link
// (`?tab=orders` lands on P&L, where the orders are; the old
// `?tab=positions|portfolio|open` on Positions), a filled order's "View
// positions", a placed order's "View orders" or a trade notification can
// open a section from anywhere.

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/rendering.dart'
    show RenderSliverToBoxAdapter, SliverGeometry;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidUserFillsProvider;
import 'package:kute/screens/home/components/kute_dock_host.dart'
    show kuteDockScrollClearance;
import 'package:kute/screens/portfolio/components/portfolio_hero.dart';
import 'package:kute/screens/portfolio/components/portfolio_pnl_chart.dart'
    show portfolioPnlVenueProvider;
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show portfolioSquareCount;
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show portfolioOpenRanked, portfolioVenueLists;
import 'package:kute/screens/portfolio/portfolio_activity.dart'
    show PortfolioActivitySection;
import 'package:kute/screens/portfolio/portfolio_balance_breakdown.dart';
import 'package:kute/screens/portfolio/portfolio_empty_state.dart';
import 'package:kute/screens/portfolio/portfolio_filters.dart';
import 'package:kute/screens/portfolio/portfolio_orders.dart';
import 'package:kute/screens/portfolio/portfolio_statistics.dart';
import 'package:kute/screens/shared/kute_bar_context.dart'
    show kuteBarScrollClearance;
import 'package:kute/theme/app_theme.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart'
    show KutePillItem, KutePillTabs, kutePillSwitchSize;

/// The Portfolio screen's sections, in pill order. [key] is the analytics
/// value (`sub` on `analytics_tab_selected`) and the link vocabulary,
/// fixed English: Positions keeps `balances` and P&L keeps `charts`, the
/// names they had when the pills read Portfolio and P&L Charts.
enum PortfolioSection {
  activity('activity'),
  balances('balances'),
  charts('charts');

  const PortfolioSection(this.key);

  final String key;

  /// The section an Investments link lands on (`/usd?tab=…`), or null
  /// when the link names no Portfolio section (a venue pill, nothing).
  /// The old Positions section and pill, and the old Portfolio pill with
  /// its Open tab, are Positions; the old Orders and Statistics tabs are
  /// P&L (where the orders are). `activity` names none: app_router.dart
  /// sends an old `/usd?tab=activity` to the Bitcoin home's Activity.
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

/// The Bitcoin home on its Activity (`?tab=activity`): where an old
/// `/usd?tab=activity` link lands (app_router.dart).
const String kHomeActivityLocation = '/home?tab=activity';

/// The section on screen, kept for the session; Activity to start
/// (founder, 4 November 2026: "an activity row (the first one)").
final portfolioSectionProvider =
    StateProvider<PortfolioSection>((_) => PortfolioSection.activity);

/// The Portfolio screen's page (see the file header). [onSection] is a
/// pill tap; the screen reports it and writes the section.
class InvestmentsPortfolio extends ConsumerWidget {
  const InvestmentsPortfolio({super.key, required this.onSection});

  final ValueChanged<PortfolioSection> onSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(portfolioSectionProvider);
    return _PortfolioPage(
        section: section,
        pills: _SectionPills(selected: section, onPick: onSection));
  }
}

/// The page as one scroll: the hero, the pinned strip, the section (see
/// the file header).
class _PortfolioPage extends ConsumerStatefulWidget {
  const _PortfolioPage({required this.section, required this.pills});

  final PortfolioSection section;
  final Widget pills;

  @override
  ConsumerState<_PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends ConsumerState<_PortfolioPage> {
  final _scroll = ScrollController();
  final _top = GlobalKey();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Where the strip pins: the hero's height.
  double get _pinAt => _top.currentContext?.size?.height ?? 0;

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    // The Investing history is kept warm whatever the section: the
    // Activity lists its fills and P&L decides on them.
    if (ref.watch(portfolioVenuesProvider.select((v) => v.trading))) {
      ref.listen(hyperliquidUserFillsProvider, (_, __) {});
    }
    // A switch keeps the hero where it is; a section scrolled past the
    // pin opens the next at its top, the strip still pinned. Before the
    // new section is built, so it never shows at the old depth. Leaving
    // P&L drops its venue pick: the hero is both venues again.
    ref.listen(portfolioSectionProvider, (prev, next) {
      if (prev == next) return;
      if (next != PortfolioSection.charts) {
        ref.read(portfolioPnlVenueProvider.notifier).state = null;
      }
      if (!_scroll.hasClients) return;
      final pin = _pinAt;
      if (_scroll.offset > pin) _scroll.jumpTo(pin);
    });
    // Watched for the page's life: the pick lasts while the screen is
    // open and goes with it.
    final picked = ref.watch(portfolioPnlVenueProvider);
    final strip = _StripHeader(
      pills: widget.pills,
      background: context.colors.background,
      extent: (_kStripTop + _kStripBottom).h + kutePillSwitchSize.height.h,
    );
    return LayoutBuilder(builder: (context, box) {
      // A short section still fills the viewport under the pinned strip.
      final minSection =
          (box.maxHeight - strip.extent).clamp(0.0, double.infinity);
      return CustomScrollView(
        key: const ValueKey('portfolio-page-scroll'),
        controller: _scroll,
        slivers: [
          _HeroSliver(
            child: Padding(
              key: _top,
              padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 0),
              child: KeyedSubtree(
                key: const ValueKey('portfolio-top'),
                // Section-aware: Positions reads only the positions open
                // now (no chart), P&L the venue square picked.
                child: PortfolioHero(
                  open: section == PortfolioSection.balances,
                  venue: section == PortfolioSection.charts ? picked : null,
                ),
              ),
            ),
          ),
          SliverPersistentHeader(pinned: true, delegate: strip),
          SliverToBoxAdapter(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minSection),
              // The section from the top of that room, never centred in it.
              child: Align(
                alignment: Alignment.topCenter,
                child: KeyedSubtree(
                  key: ValueKey('portfolio-section-${section.key}'),
                  child: switch (section) {
                    PortfolioSection.activity => const _ActivityBox(),
                    PortfolioSection.balances => const _BalancesBox(),
                    PortfolioSection.charts => const _ChartsBox(),
                  },
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// The hero as the page's first sliver, its height kept out of the
/// section's way: the hero folds its chart on Positions and back
/// (components/portfolio_hero.dart), and while it is scrolled out of sight
/// above the pinned strip every change of its height moves the scroll
/// position with it ([SliverGeometry.scrollOffsetCorrection]), so the
/// section under the strip stays exactly where it is. In sight, the hero
/// eases its height and the page under it follows, as any block does.
class _HeroSliver extends SingleChildRenderObjectWidget {
  const _HeroSliver({required Widget super.child});

  @override
  RenderSliverToBoxAdapter createRenderObject(BuildContext context) =>
      _RenderHeroSliver();
}

class _RenderHeroSliver extends RenderSliverToBoxAdapter {
  /// The hero's height at the last layout.
  double? _extent;

  @override
  void performLayout() {
    super.performLayout();
    final box = child;
    if (box == null || !box.hasSize) return;
    final extent = switch (constraints.axis) {
      Axis.vertical => box.size.height,
      Axis.horizontal => box.size.width,
    };
    final before = _extent;
    _extent = extent;
    if (before == null || (extent - before).abs() < precisionErrorTolerance) {
      return;
    }
    // Wholly above the viewport (the strip pinned): keep what is under it
    // still.
    if (constraints.scrollOffset > 0 &&
        constraints.scrollOffset >= before - precisionErrorTolerance) {
      geometry = SliverGeometry(scrollOffsetCorrection: extent - before);
    }
  }
}

/// The strip's room above and below its pills, design units.
const double _kStripTop = 14;
const double _kStripBottom = 4;

/// The Activity | Positions | P&L strip as a pinned sliver header, on the
/// page's own background so the section scrolls under it.
class _StripHeader extends SliverPersistentHeaderDelegate {
  const _StripHeader(
      {required this.pills, required this.background, required this.extent});

  final Widget pills;
  final Color background;
  final double extent;

  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      Container(
        key: const ValueKey('portfolio-strip'),
        color: background,
        padding: EdgeInsets.fromLTRB(16.w, _kStripTop.h, 16.w, _kStripBottom.h),
        alignment: Alignment.topCenter,
        child: pills,
      );

  @override
  bool shouldRebuild(_StripHeader old) =>
      old.pills != pills ||
      old.background != background ||
      old.extent != extent;
}

/// The end of every section: clear of the home indicator and of the bar
/// ([kuteBarScrollClearance], inside the scroll, so the last row can be
/// seen and tapped).
double _portfolioScrollEnd(BuildContext context) =>
    32.h + kuteBarScrollClearance.h + kuteDockScrollClearance(context);

/// Activity: the home's pattern for the investments' actions
/// (PortfolioActivitySection), then the bar's clearance.
class _ActivityBox extends StatelessWidget {
  const _ActivityBox();

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PortfolioActivitySection(),
          SizedBox(height: _portfolioScrollEnd(context)),
        ],
      );
}

/// Positions: the biggest open positions as squares, then the rest under
/// their venues (PortfolioBalanceBreakdown.venuesOnly, no refresh of its
/// own: the hero's read already runs), then the bar's clearance.
class _BalancesBox extends ConsumerWidget {
  const _BalancesBox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venues = ref.watch(portfolioVenuesProvider);
    final ranked = portfolioOpenRanked(ref, venues);
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PortfolioBalanceBreakdown(
              trading: venues.trading,
              predictions: venues.predictions,
              overview: true,
              sharesHeader: true,
              venuesOnly: true,
              refreshOnOpen: false,
              squareIds: ranked
                  .take(portfolioSquareCount(ranked.length))
                  .toList(growable: false),
              venues: portfolioVenueLists(context, ref, venues)),
          SizedBox(height: _portfolioScrollEnd(context)),
        ],
      ),
    );
  }
}

/// P&L: each venue's P&L, the all-time stats and the resting orders
/// (PortfolioStatisticsOverview without its chart: the hero has it), its
/// empty state the sections' one.
class _ChartsBox extends ConsumerWidget {
  const _ChartsBox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venues = ref.watch(portfolioVenuesProvider);
    final sectionEmpty = Padding(
      key: const ValueKey('statistics-chart-empty'),
      padding: EdgeInsets.only(top: kPortfolioSectionEmptyTop.h),
      child: PortfolioSectionEmpty(
          title: context.l10n.pnlNoHistoryTitle,
          tagline: PortfolioSectionTagline.pnl),
    );
    if (!venues.any) return sectionEmpty;
    return PortfolioStatisticsOverview(
      key: const ValueKey('statistics-overview'),
      trading: venues.trading,
      predictions: venues.predictions,
      orders: PortfolioOrdersBook.watch(ref, venues),
      sectionEmpty: sectionEmpty,
      boxed: true,
      chart: false,
      endClearance: _portfolioScrollEnd(context),
    );
  }
}

/// Activity | Positions | P&L: the app's switch row (KutePillTabs at
/// [kutePillSwitchSize]): equal thirds across the width, the one white
/// pill sliding to the picked one. Each pill keeps its key.
class _SectionPills extends StatelessWidget {
  const _SectionPills({required this.selected, required this.onPick});

  final PortfolioSection selected;
  final ValueChanged<PortfolioSection> onPick;

  @override
  Widget build(BuildContext context) {
    final sections = PortfolioSection.values;
    return KutePillTabs(
      horizontalPadding: 0,
      items: [
        for (final s in sections)
          KutePillItem(
            key: ValueKey('portfolio-section-pill-${s.key}'),
            label: portfolioSectionName(context.l10n, s),
          ),
      ],
      selectedIndex: sections.indexOf(selected),
      onTap: (i) => onPick(sections[i]),
    );
  }
}

/// A section's name as its pill writes it.
String portfolioSectionName(AppLocalizations l10n, PortfolioSection s) =>
    switch (s) {
      PortfolioSection.activity => l10n.activity,
      PortfolioSection.balances => l10n.portfolioSectionBalances,
      PortfolioSection.charts => l10n.portfolioSectionPnlCharts,
    };
