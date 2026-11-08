// lib/screens/usd/components/dollars_activity_tab.dart
//
// Dollars money: every figure here reads in dollars, whatever the Settings
// currency; only Bitcoin's conversion follows Settings
// (polymarket_amount_formatter.dart).
//
// THE DOLLARS OVERVIEW TAB. The file and its classes keep the name
// "activity", as do the `?tab=activity` link and the `activity` analytics
// value (InvestmentsTab.activity); the pill reads Overview (founder, 8
// November 2026), and `?tab=overview` opens it too. The first pill of the
// Dollars switch, Overview · Investing · Predictions, and the one the page
// opens on (usd_account_screen.dart). It began as the Activity screen
// (founder, 4 November 2026: "It must have all the open bets and such … It
// must have the P&L below the 4 squares with the highest predictions and
// Hyperliquid bets."). Top down, in the Bitcoin home's language
// (all_activity.dart) and the Portfolio's (position_rows.dart), nothing new:
//
//   * OPEN POSITIONS: the biggest open positions at both venues together,
//     biggest first ([dollarsActivitySquareIds], the Portfolio's own
//     ranking, portfolioOpenRanked), at most [kDollarsActivitySquares], as
//     the Portfolio's squares (PortfolioRowLayout.square: the logo, the P&L
//     % in colour, the name and the value large), two by two in the home's
//     "Latest" grid (ActivitySquareGrid); an odd last one, one alone
//     included, is one full-width compact card under them, never a lone
//     half square (PortfolioPositionSquares, the no-orphan rule; founder,
//     6 November 2026), as on the Portfolio. Each square IS the position's
//     own row (portfolioVenueLists), so a tap opens the position exactly
//     as the Portfolio's row does. Still reading with nothing listed: the
//     squares' skeletons (PortfolioSquaresSkeleton). Nothing open: nothing
//     here, the map leads the tab;
//   * OPEN P&L under the squares ([DollarsPnlStrip]; founder, 6 November
//     2026: the card is the open positions' P&L): what the positions open
//     now made or lost so far (the Portfolio's Positions rows' P&L added,
//     and its P&L tab's "On open positions" over ALL, at the live prices)
//     in one soft card, compact, over the open positions' P&L since each
//     was opened (the open P&L engine's series, its last point that
//     figure; the split fill, the dashed line at zero, no scrub, no range
//     row). A tap opens the Portfolio on Positions. Nothing open: no card;
//   * THE MARKET MAP ([HlMarketMapCard], hl_market_map.dart; moved here from
//     Investing, founder, 8 November 2026): the treemap of the browse
//     universe, a tile opening its market. Always the whole map: Investing's
//     picked category has no say here. Its skeleton until the builder-dex
//     markets are in.
//
// The newest actions no longer list here (the "Latest" card, gone 8
// November 2026): the full activity is the Portfolio's, which the bar opens.
//
// THE MAP'S DATA ([_OverviewMarketMap]): this tab watches the browse universe
// itself, so the map loads and refreshes with Investing unbuilt. The universe
// and its lists are the one shared set of providers Investing reads (30 s
// timers, one read whoever listens), so a second listener makes no second
// read. Its prices are the one allMids socket: the shell keeps it on under
// this pill (applyShellTabLivePolicy) and off wherever nothing it feeds is on
// screen. Behind another pill or tab the card does no work of its own (see
// HlMarketMapCard).
//
// NOTHING OPEN: the tab shows nothing under the pills (founder, 8 November
// 2026: of the map alone on an empty tab, "maybe we cut it from overview if
// nothing open, then we show nothing there"). No map, no empty state. The
// map hides with the policy too (`hyperliquid.browse`), leaving what is held.
//
// ONE EDGE FOR EVERY BLOCK (founder, 5 November 2026: "different size
// here"): the squares, the P&L card and the map all stand on the page's 16
// gutters, the map's group card bringing its own 16 margin, so it sits
// outside the padding the other two share; the heading sits 12 inside that
// edge, as the Bitcoin home's "Latest" and "Earlier" do.
//
// The bar on this tab is "See full portfolio and activity", which pushes
// the Portfolio screen (usd_account_screen.dart), so there is no See all
// here, and the Overview pill always reads Overview (founder, 5 November
// 2026: "it's on the bottom button").
//
// Analytics: nothing new. A square's tap sends the Portfolio row's own
// `open_investments_position_tapped`; a tile's tap opens the market's sheet,
// whose `hyperliquid_market_viewed` says `market_map` as its entry source.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show
        hyperliquidBrowseUniverseProvider,
        hyperliquidBuilderMarketsMissingProvider,
        hyperliquidPerpMarketsProvider;
import 'package:kute/providers/open_pnl_history_provider.dart'
    show
        OpenPnlChartStatus,
        openPnlChartStatusProvider,
        openPnlHistoryProvider,
        openPnlShownRangeProvider,
        openPnlWindowProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart'
    show kuteDockScrollClearance;
import 'package:kute/screens/hyperliquid/components/hl_market_map.dart'
    show HlMarketMapCard;
import 'package:kute/screens/portfolio/components/balances_overview.dart'
    show BalancesCategory, BalancesVenueList, kBalancesCentUsd;
import 'package:kute/screens/portfolio/components/portfolio_pnl_chart.dart'
    show pnlResultColor;
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show PortfolioPositionSquares, PortfolioSquaresSkeleton;
import 'package:kute/screens/portfolio/investments_portfolio.dart'
    show PortfolioSection;
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show portfolioOpenPnl, portfolioOpenRanked, portfolioVenueLists;
import 'package:kute/screens/portfolio/portfolio_filters.dart'
    show portfolioVenuesProvider;
import 'package:kute/screens/shared/animations/premium_group_container.dart';
import 'package:kute/screens/shared/charts/kute_chart_format.dart'
    show kuteChangeSign;
import 'package:kute/screens/shared/charts/kute_trend_chart.dart';
import 'package:kute/screens/shared/kute_motion.dart' show KutePressable;
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/screens/usd/usd_account_screen.dart'
    show openInvestmentsPortfolio;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The open positions drawn as squares, at most.
const int kDollarsActivitySquares = 4;

/// The compact P&L line's height, design units.
const double kDollarsPnlPlotHeight = 64;

/// The ids of the open positions drawn as squares: the biggest first (the
/// order of [ranked], portfolioOpenRanked), at most
/// [kDollarsActivitySquares]. Pure for the tests.
List<String> dollarsActivitySquareIds(List<String> ranked) =>
    ranked.take(kDollarsActivitySquares).toList(growable: false);

/// The rows of [lists] whose keys are [ids], in [ids]' order; an id with
/// no row (a read still catching up) is skipped, never a hole.
List<Widget> dollarsActivitySquareRows(
    List<String> ids, Iterable<BalancesVenueList> lists) {
  final byKey = <Key, Widget>{
    for (final list in lists)
      for (final row in list.rows)
        if (row.key case final k?) k: row,
  };
  return [
    for (final id in ids)
      if (byKey[ValueKey(id)] case final row?) row,
  ];
}

/// The Overview pill's page (see the file header). One scroll, the nested
/// scroll's inner list, so the Dollars header collapses over it as over the
/// venues' lists.
class DollarsActivityTab extends ConsumerWidget {
  const DollarsActivityTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final venues = ref.watch(portfolioVenuesProvider);
    final ranked =
        venues.any ? portfolioOpenRanked(ref, venues) : const <String>[];
    final lists = venues.any
        ? portfolioVenueLists(context, ref, venues)
        : const <BalancesCategory, BalancesVenueList>{};
    final squares = dollarsActivitySquareRows(
        dollarsActivitySquareIds(ranked), lists.values);
    final loading =
        squares.isEmpty && lists.values.any((list) => list.loading);
    final held = squares.isNotEmpty || loading;

    return CustomScrollView(
      key: const ValueKey('dollars-activity-list'),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              if (held)
                _Heading(l10n.accountOpenPositions,
                    key: const ValueKey('dollars-activity-positions-heading')),
              if (squares.isNotEmpty)
                // Two by two, an odd last one (one alone included) the
                // full-width compact card: never a lone half square (the
                // no-orphan rule).
                PortfolioPositionSquares(
                    key: const ValueKey('dollars-activity-squares'),
                    rows: squares)
              else if (loading)
                const PortfolioSquaresSkeleton(
                    key: ValueKey('dollars-activity-loading')),
              const DollarsPnlStrip(),
            ]),
          ),
        ),
        // Outside the gutters: the group card brings its own 16 margin.
        // Nothing open: no map, nothing (see the file header).
        if (held)
          SliverToBoxAdapter(
            // The P&L card's 12 under what is held.
            child: _OverviewMarketMap(margin: EdgeInsets.only(top: 12.h)),
          ),
        // The last block clear of the dock and the bar over it.
        SliverToBoxAdapter(
          child: SizedBox(height: 24.h + kuteDockScrollClearance(context)),
        ),
      ],
    );
  }
}

/// The market map on this tab (see the file header), hidden when the policy
/// withholds Investing's browsing, as Investing's own list is. Its own widget
/// so the universe's 30 s refresh rebuilds the map alone.
class _OverviewMarketMap extends ConsumerWidget {
  const _OverviewMarketMap({required this.margin});

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canBrowse =
        ref.watch(runtimeCapabilitiesProvider).allows('hyperliquid.browse');
    if (!canBrowse) return const SizedBox.shrink();
    final universe = ref.watch(hyperliquidBrowseUniverseProvider).valueOrNull ??
        const <HlMarket>[];
    final buildersMissing = ref.watch(hyperliquidBuilderMarketsMissingProvider);
    final perps = ref.watch(hyperliquidPerpMarketsProvider.select((read) =>
        (landed: read.valueOrNull != null, failed: read.hasError)));
    // The skeleton until the builder-dex markets (the stocks, indices and
    // commodities) are in. A perp list that could not be read is no wait:
    // this tab has nothing else to fall back on, so what was read is drawn
    // until the next 30 s read lands.
    final waiting = !perps.landed &&
        !perps.failed &&
        !universe.any((m) => m.isHip3);
    return HlMarketMapCard(
      universe: universe,
      margin: margin,
      loading: buildersMissing || waiting,
    );
  }
}

/// A section's title over its block, in the home Activity's heading style
/// ("Latest", all_activity.dart), on the page's 16 gutter plus the cards'
/// 12 inset: every heading on one line, 12 inside the blocks' one edge.
class _Heading extends StatelessWidget {
  const _Heading(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(12.w, 14.h, 12.w, 8.h),
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

/// The OPEN P&L under the squares (see the file header; founder, 6
/// November 2026: the card is the open positions' P&L, "Open P&L"): what
/// the positions open now made or lost so far at both venues, at the live
/// prices (portfolioOpenPnl: the Portfolio's Positions rows' P&L added, its
/// P&L tab's "On open positions" over ALL), signed and rolling in its
/// result colour, over the open positions' P&L since each was opened (the
/// open P&L engine's series,
/// [openPnlWindowProvider] on its range [openPnlShownRangeProvider], its
/// last point the figure with the positions it cannot chart left out) with
/// the split fill and the dashed line at zero, short and still. A tap opens
/// the Portfolio on Positions, where those positions are. Nothing open: no
/// card.
/// The history on its way: the card's skeleton; nothing it can chart: the
/// figure alone.
class DollarsPnlStrip extends ConsumerWidget {
  const DollarsPnlStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venues = ref.watch(portfolioVenuesProvider);
    if (!venues.any) return const SizedBox.shrink();
    final open = portfolioOpenPnl(ref, venues);
    if (open == null) return const SizedBox.shrink();
    final status = ref.watch(openPnlChartStatusProvider);
    if (status == OpenPnlChartStatus.loading) {
      return const _PnlStripSkeleton(key: ValueKey('dollars-pnl-loading'));
    }

    final c = context.colors;
    final l10n = context.l10n;
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    // Under a cent is no move.
    final usd = open.usd.abs() < kBalancesCentUsd ? 0.0 : open.usd;
    final color = !visible ? c.textPrimary : pnlResultColor(c, usd);
    final figure = !visible
        ? '••••••'
        : '${kuteChangeSign(usd)}${formatDollars(usd.abs())}';

    // The open P&L engine's line on its range, its last point the open
    // P&L of what it charts.
    List<double>? values;
    List<DateTime>? times;
    if (status == OpenPnlChartStatus.chart) {
      final window =
          ref.watch(openPnlWindowProvider(ref.watch(openPnlShownRangeProvider)));
      if (window != null && window.values.isNotEmpty) {
        final leftOut = ref.watch(openPnlHistoryProvider
                .select((read) => read.valueOrNull?.leftOut)) ??
            const <String>{};
        values = [...window.values];
        values[values.length - 1] =
            portfolioOpenPnl(ref, venues, leaveOut: leftOut)?.usd ??
                values.last;
        times = window.times;
      }
    }

    return Padding(
      padding: EdgeInsets.only(top: 12.h),
      child: Semantics(
        button: true,
        label: '${l10n.portfolioStatOpenPnl} $figure',
        excludeSemantics: true,
        child: KutePressable(
          child: GestureDetector(
            key: const ValueKey('dollars-pnl-strip'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              openInvestmentsPortfolio(context, PortfolioSection.balances);
            },
            child: DecoratedBox(
              decoration: PremiumGroupContainer.decorationOf(context),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 12.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.portfolioStatOpenPnl,
                            key: const ValueKey('dollars-pnl-label'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            size: 18.sp, color: c.textTertiary),
                      ],
                    ),
                    SizedBox(height: 4.h),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: RollingNumberText(
                          key: const ValueKey('dollars-pnl-figure'),
                          text: figure,
                          style: TextStyle(
                            color: color,
                            fontSize: 24.sp,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            height: 1.1,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    if (values != null) ...[
                      SizedBox(height: 10.h),
                      // Still, no scrub: the card is one tap to Positions.
                      IgnorePointer(
                        child: KuteTrendChart(
                          key: const ValueKey('dollars-pnl-chart'),
                          values: values,
                          times: times,
                          // The figure's own colour, as on Positions.
                          lineColor: !visible
                              ? c.textPrimary
                              : pnlResultColor(c, values.last),
                          zeroSplit: true,
                          baseline: 0,
                          live: false,
                          height: kDollarsPnlPlotHeight.h,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The P&L card's shape while its read is on its way.
class _PnlStripSkeleton extends StatelessWidget {
  const _PnlStripSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: 12.h),
        child: KuteSkeleton(
          child: SkeletonBar(double.infinity,
              (14 + 18 + 4 + 28 + 10 + kDollarsPnlPlotHeight + 12).h,
              radius: PremiumGroupContainer.radius),
        ),
      );
}
