// lib/screens/portfolio/investments_portfolio.dart
//
// THE PORTFOLIO SCREEN'S PAGE (portfolio_screen.dart), redesigned on 7
// November 2026 after the Robinhood / Public / Webull / Polymarket /
// Kalshi review (founder: "yes build this"). One scroll, top down:
//
//   * THE HERO (components/portfolio_hero.dart), one instance whatever the
//     section: the total (the open positions' worth plus Available), the
//     P&L over the range picked under it ("▲ $7.55 (+12.0%) · Past
//     month"), ONE P&L chart with its range row (1W 1M 3M ALL), and
//     "Invested $X · Available $Y". On P&L a "By product" row picked
//     draws that venue alone (portfolioPnlVenueProvider, dropped when P&L
//     is left);
//   * the section switch, pinned under the app bar once it reaches it
//     ([_StripHeader]): Positions | P&L | Activity (KutePillTabs at the
//     app's switch size, equal thirds, the one white pill sliding);
//   * the section ([PortfolioSection], shared state kept for the
//     session, Positions first and the default):
//       - POSITIONS (the `balances` section, its key kept for links): the
//         open positions by value under plain "Investing" and
//         "Predictions" headings, each row its value with the P&L since it
//         was opened under it (PortfolioBalanceBreakdown.venuesOnly,
//         components/balances_overview.dart); nothing open: "No open
//         positions" with Browse Investing;
//       - P&L (the `charts` section): "You're up $7.55" over the hero's
//         range, the two rows that add up to it (from closed positions, on
//         open positions), "By product" (Predictions, Investing; a row
//         tapped draws that venue in the hero), the closed positions with
//         their results, and the resting orders, each row with its own
//         cancel (PortfolioStatisticsOverview without its chart,
//         portfolio_statistics.dart, portfolio_pnl_section.dart);
//       - ACTIVITY (portfolio_activity.dart, PortfolioActivitySection):
//         the investments' feed by day with All / Trades / Payouts /
//         Transfers chips. Once Activity is on screen its pill reads "→ See
//         all" and a second tap opens the whole Investments activity (the
//         Bitcoin home's mechanism, [_SectionPills]).
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
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show portfolioVenueLists;
import 'package:kute/screens/portfolio/portfolio_activity.dart'
    show PortfolioActivitySection;
import 'package:kute/screens/activity/activity_history_screen.dart'
    show showActivityHistory;
import 'package:kute/screens/shared/all_activity.dart' show ActivityScope;
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

/// The Portfolio screen's sections, in pill order: Positions, P&L,
/// Activity (founder, 6 November 2026: "Activity should be the last,
/// Positions first"). [key] is the link vocabulary and the widgets' keys,
/// fixed English and unchanged by the order: Positions keeps `balances`
/// and P&L keeps `charts`, the names they had when the pills read
/// Portfolio and P&L Charts. [eventName] is what analytics calls the
/// section (`sub` and `from_sub` on `analytics_tab_selected`): positions,
/// pnl, activity, the sections as the pills name them since the redesign
/// of 7 November 2026.
enum PortfolioSection {
  balances('balances', 'positions'),
  charts('charts', 'pnl'),
  activity('activity', 'activity');

  const PortfolioSection(this.key, this.eventName);

  final String key;
  final String eventName;

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

/// The section on screen, kept for the session; Positions to start
/// (founder, 6 November 2026: "Activity should be the last, Positions
/// first").
final portfolioSectionProvider =
    StateProvider<PortfolioSection>((_) => PortfolioSection.balances);

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
                // One hero over every section; on P&L the "By product" row
                // picked draws that venue alone.
                child: PortfolioHero(
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

/// The Positions | P&L | Activity strip as a pinned sliver header, on the
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

/// Positions: the open positions by value under their venue's heading
/// (PortfolioBalanceBreakdown.venuesOnly, no refresh of its own: the
/// hero's read already runs), then the bar's clearance.
class _BalancesBox extends ConsumerWidget {
  const _BalancesBox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venues = ref.watch(portfolioVenuesProvider);
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
              venues: portfolioVenueLists(context, ref, venues)),
          SizedBox(height: _portfolioScrollEnd(context)),
        ],
      ),
    );
  }
}

/// P&L: the headline over the hero's range and the rows that add up to it,
/// "By product", the closed positions and the resting orders
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

/// Positions | P&L | Activity: the app's switch row (KutePillTabs at
/// [kutePillSwitchSize]): equal thirds across the width, the one white
/// pill sliding to the picked one. Each pill keeps its key.
///
/// ACTIVITY'S SEE ALL (founder, 6 November 2026), the Bitcoin home's own
/// mechanism (home_analytics_widget.dart, activityPillSeesAll): once
/// Activity is the section on screen its pill stops naming it and names
/// what a second tap does, "→ See all" (the arrow, l10n seeAll), and that
/// second tap opens the Activity screen on the Investments activity
/// ([portfolioSeeAllActivity]); on another section it reads Activity
/// again. The section itself has no See all button of its own.
class _SectionPills extends StatelessWidget {
  const _SectionPills({required this.selected, required this.onPick});

  final PortfolioSection selected;
  final ValueChanged<PortfolioSection> onPick;

  @override
  Widget build(BuildContext context) {
    final sections = PortfolioSection.values;
    final seesAll = selected == PortfolioSection.activity;
    return KutePillTabs(
      horizontalPadding: 0,
      items: [
        for (final s in sections)
          if (s == PortfolioSection.activity && seesAll)
            KutePillItem(
              key: ValueKey('portfolio-section-pill-${s.key}'),
              label: context.l10n.seeAll,
              icon: Icons.arrow_forward_rounded,
            )
          else
            KutePillItem(
              key: ValueKey('portfolio-section-pill-${s.key}'),
              label: portfolioSectionName(context.l10n, s),
            ),
      ],
      selectedIndex: sections.indexOf(selected),
      onTap: (i) {
        final tapped = sections[i];
        if (tapped == PortfolioSection.activity && seesAll) {
          portfolioSeeAllActivity(context);
          return;
        }
        onPick(tapped);
      },
    );
  }
}

/// The Activity pill's second tap (see [_SectionPills]): the Activity
/// screen on the Investments activity, as the section's old See all
/// button opened it (`activity_history_opened` {entry_source: portfolio,
/// scope: investments}).
void portfolioSeeAllActivity(BuildContext context) => showActivityHistory(
    context,
    source: 'portfolio',
    scope: ActivityScope.investments);

/// A section's name as its pill writes it.
String portfolioSectionName(AppLocalizations l10n, PortfolioSection s) =>
    switch (s) {
      PortfolioSection.activity => l10n.activity,
      PortfolioSection.balances => l10n.portfolioSectionBalances,
      PortfolioSection.charts => l10n.portfolioSectionPnlCharts,
    };
