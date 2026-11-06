// lib/screens/portfolio/components/portfolio_hero.dart
//
// THE PORTFOLIO SCREEN'S HERO (founder, 4 November 2026: "the top chart
// means nothing, it's super confusing … the portfolio screen must be
// completely overhauled to have a much, much, much better fintech design
// comparable to the rest of the app"). The allocation ring is gone; the
// top of the page reads like a brokerage's investing tab (Robinhood,
// Revolut, Trading 212), left-aligned in the 16 gutters, top down:
//
//   * "Invested" (13 sp, textSecondary), the app's own word for this
//     figure: the Dollars header's "Invested" (the one balance's
//     investedUsd, the same display cache), what the open positions are
//     worth now at the live marks, open orders' reserve included;
//   * the figure itself, 40 sp w700, tabular, rolling in place; the last
//     figure known, dimmed and sweeping ([StaleShimmer]), while a venue is
//     read (again), a dash before anything was ever read; dots with
//     balances hidden;
//   * under it the P&L over the range picked, in the result colour: "▲
//     $31.84 · Past month" (the line's end less the range's start, ALL
//     the all-time P&L; [pnlRangeChange]). No percent: no provider gives
//     a base for it, and none is invented. While a finger scrubs, the
//     P&L since the range's start to the point under it and its moment
//     ("▲ $12.10 · Oct 16 14:00"); only that line rebuilds on a scrub
//     frame (a [ValueNotifier], never the section);
//   * ONE chart: the account's P&L (Investing and Predictions added,
//     [PortfolioPerformance.combine], the predictions at the live prices
//     of the shares held only) over the range, [KuteTrendChart] as the
//     Bitcoin and Dollars balance charts draw it (the result colour, the
//     dashed hairline at the range's start, the scrub; the compact 160
//     plot, so the section's first row is in sight) with the P&L split
//     fill around zero, and the app's range row under it (1W 1M 3M 1Y
//     ALL, [pnlChartRangeProvider], kept for the session and shared with
//     the P&L section's venue rows and the "Share P&L" card);
//   * one quiet line: "3 positions · Available $17.64" (the open
//     positions the Positions section lists). Nothing open: the Available
//     alone.
//
// ONE INVESTED AND ONE AVAILABLE ACROSS THE APP (founder, 4 November
// 2026: "Balance wrong in dollars … show invested and available in a good
// way"): the figure and the line's Available are the Dollars header's own
// "Invested $X · Available $Y" (InvestmentBalanceHeader
// .oneBalanceSplitFigures: the same snapshot, the same display cache and
// oneBalanceSplit, to the cent in the currency on screen), so the two
// screens never disagree. Available is Dollars, the venues' spare cash and
// money coming home between the person's own accounts, never the money the
// Dollars header names on its in-flight lines.
//
// Never traded (a P&L that never left zero): no P&L line, no chart and no
// range row, the figure and the line under it alone (the sections say it
// with Sal, never twice). A history still on its way: the
// shapes of the line, the plot and the ranges as a skeleton, never a
// blank frame that then jumps. A history that could not be read: the
// figure alone (the P&L section carries the retry).
//
// The venues are read again as the screen opens (as their pull to
// refresh does, capped), the figures sweeping until they land.
//
// THE HERO READS THE SECTION UNDER IT (founder, 5 November 2026):
//
//   * ACTIVITY: as above, both venues over the range;
//   * POSITIONS ("here show the current positions P&L … only the open
//     ones", [PortfolioHero.open]): the line is what the positions open
//     now made or lost so far, at the live prices, "▲ $0.52 (2.7%) · Open
//     P&L" ([_HeroOpenLine]; the rows' P&L added, the percent of what they
//     cost only where every one has a cost: a prediction its entry, a perp
//     its margin, a holding its recorded cost). Under it THE OPEN
//     POSITIONS' P&L CHART ([_OpenPnlChart]; founder, 6 November 2026:
//     "here I wanted the P&L of the open positions — the graph. Put it
//     back."): what the positions held now made or lost since each was
//     opened, each from its own entry (its fills or trades, its market's
//     prices; models/open_pnl_history.dart, providers/
//     open_pnl_history_provider.dart), 0 before it existed, its last point
//     the line's figure itself. No venue publishes this line, so it is
//     worked out from what they do publish, never the account's P&L and
//     never today's sizes against prices from before a position. The same
//     chart as P&L's (the compact plot, the split fill, the result colour
//     of the figure now), the dashed hairline at zero, and its own range
//     row (1W 1M 3M 1Y ALL, [openPnlShownRangeProvider]: the shortest that
//     covers the oldest position's entry to start, the pick kept for the
//     session). A scrub writes the open P&L at that moment in the line
//     ("▲ $0.40 · Open P&L · Oct 16 14:00"). The chart's shapes while the
//     history is read; a position whose history cannot be read is left
//     out of the line (a quiet "1 position not charted" under it; the
//     figure still counts it); nothing charted: the chart folds away as
//     before;
//   * P&L: both venues over the range, or the venue square picked
//     ([PortfolioHero.venue], portfolioPnlVenueProvider; founder:
//     "selecting here must change the top graph") alone: that venue's
//     Invested (the one balance's investedByVenue; the whole block then
//     reads one thing, never a total over one venue's P&L), its P&L line
//     with its logo and name first ("Predictions · ▼ $10.08 · Past
//     week"), its chart (the same chart morphing to it on the chip
//     spring), its open positions in the line under the chart (Available
//     stays the one balance's), and a small "All" beside the figure that
//     puts both venues back, as the picked square tapped again does.
//
// Transitions: the line's words fade out then in (ArrivalSwitcher
// .sequential, never one over the other), the chart folds and unfolds on
// KuteMotion's settle (300 ms) and draws in afresh, the figure rolls; all
// at once under Reduce Motion. Every figure is tabular, so a live tick
// never shifts the line, and a tick rebuilds the open line alone. The page
// keeps the section under the pinned strip still while the hero's height
// changes out of sight (investments_portfolio.dart).
//
// Analytics: `portfolio_performance_chart_scrubbed` {venue: all |
// hyperliquid | polymarket | open_positions, the series drawn} once per
// scrub gesture, as the P&L chart sent it; the "All" chip sends
// `portfolio_statistics_venue_toggled` {venue: all}, as a square does.
// Ranges send nothing.

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/providers/open_pnl_history_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart'
    show hyperliquidTradingProvider;
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart'
    show livePriceProvider;
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceUnknownProvider;
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/portfolio/components/balances_overview.dart'
    show
        BalancesFigure,
        BalancesLiveFigure,
        BalancesPnlText,
        kBalancesCentUsd;
import 'package:kute/screens/portfolio/components/portfolio_pnl_chart.dart'
    show
        pnlChartRangeProvider,
        pnlEventVenue,
        pnlRangeChange,
        pnlResultColor,
        portfolioPickPnlVenue;
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show InvestmentsProduct, portfolioOpenCount, portfolioOpenPnl;
import 'package:kute/screens/portfolio/portfolio_balance_breakdown.dart'
    show kBreakdownRefreshCap;
import 'package:kute/screens/portfolio/portfolio_filters.dart';
import 'package:kute/screens/shared/investment_balance_header.dart'
    show InvestmentBalanceHeader;
import 'package:kute/screens/shared/charts/kute_chart_format.dart';
import 'package:kute/screens/shared/charts/kute_trend_chart.dart';
import 'package:kute/screens/shared/charts/kute_trend_window.dart';
import 'package:kute/screens/shared/kute_motion.dart'
    show ArrivalSwitcher, kuteMotion;
import 'package:kute/screens/shared/kute_pill_tabs.dart'
    show KutePill, KutePillSize;
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/venue_deposit_button.dart'
    show venueMarkAsset;
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_total_cache_service.dart'
    show resolveVenueTotal;
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart';

/// The display cache's key for the Invested figure: the Dollars header's
/// own (venue_total_cache_service.dart, resolveInvestmentsDisplay), so the
/// two never disagree while a venue is read again.
const String kInvestmentsInvestedCacheKey = 'investments_invested';

/// The hero figure's size, design units.
const double kPortfolioHeroFigure = 40;

/// The hero's line and caption size, design units.
const double kPortfolioHeroQuiet = 13;

/// The hero (see the file header).
class PortfolioHero extends ConsumerStatefulWidget {
  const PortfolioHero({super.key, this.open = false, this.venue});

  /// Positions: only the positions open now, their P&L now and its chart
  /// since each was opened (see the file header).
  final bool open;

  /// P&L: the venue square picked ([portfolioPnlVenueProvider]); null:
  /// both venues.
  final PortfolioPerformanceVenue? venue;

  @override
  ConsumerState<PortfolioHero> createState() => _PortfolioHeroState();
}

class _PortfolioHeroState extends ConsumerState<PortfolioHero> {
  /// The venues' read on open is running: the figure sweeps.
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // Right away, from what the app holds; the fresh read after.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  /// Both venues read again, as their pull-to-refresh does, capped.
  Future<void> _refresh() async {
    final venues = ref.read(portfolioVenuesProvider);
    final runs = <Future<void>>[
      if (venues.predictions && ref.exists(polymarketTradingProvider))
        ref.read(polymarketTradingProvider.notifier).refresh(),
      if (venues.trading && ref.exists(hyperliquidTradingProvider))
        ref.read(hyperliquidTradingProvider.notifier).refresh(),
    ];
    // The venues' cash for the one balance's Available.
    unawaited(ref
        .read(venueSweeperProvider.notifier)
        .preview()
        .then((_) {}, onError: (_) {}));
    if (runs.isEmpty) return;
    setState(() => _refreshing = true);
    try {
      await Future.wait(runs).timeout(kBreakdownRefreshCap);
    } catch (_) {
      // A slow or failed read keeps the last figures; the venues' own
      // polls carry on.
    }
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('portfolio-hero'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 4.h),
        _HeroFigure(refreshing: _refreshing, venue: widget.venue),
        PortfolioHeroChart(open: widget.open, venue: widget.venue),
        SizedBox(height: 16.h),
        _HeroLine(venue: widget.venue),
      ],
    );
  }
}

TextStyle _quiet(BuildContext context) => TextStyle(
      color: context.colors.textSecondary,
      fontSize: kPortfolioHeroQuiet.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.3,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// "Invested" over the figure (see the file header); with a venue picked
/// that venue's own Invested, and the "All" chip beside it.
class _HeroFigure extends ConsumerWidget {
  const _HeroFigure({required this.refreshing, this.venue});

  final bool refreshing;
  final PortfolioPerformanceVenue? venue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = context.l10n;
    final state = ref.watch(oneBalanceProvider);
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final walletId =
        ref.watch(settingsProvider.select((s) => pickSpendingWallet(s)?.id));
    final picked = venue;
    final double? usd;
    final bool stale;
    if (picked == null) {
      // The Dollars header's figure (its cache too): both venues read, the
      // figure; else the last one known, sweeping; never read, a dash.
      final display = resolveVenueTotal(
        walletId: walletId,
        venue: kInvestmentsInvestedCacheKey,
        fresh: state.investingKnown && state.predictionsKnown
            ? state.investedUsd
            : null,
      );
      // Read once, ever: the Dollars header's own figure (the same split,
      // see the file header); never read, a dash.
      final split = InvestmentBalanceHeader.oneBalanceSplitFigures(ref);
      usd = display.value == null ? null : split.investedUsd;
      stale = display.stale;
    } else {
      // The venue's own share of it (the one balance's Invested is the
      // venues' added), its last figure known while it is read again.
      final known = picked == PortfolioPerformanceVenue.trading
          ? state.investingKnown
          : state.predictionsKnown;
      final display = resolveVenueTotal(
        walletId: walletId,
        venue: 'portfolio_invested_${picked.name}',
        fresh: known ? state.investedByVenue[_oneBalanceVenue(picked)] ?? 0 : null,
      );
      usd = display.value;
      stale = display.stale;
    }
    final text = usd == null
        ? '—'
        : visible
            ? formatPolyFiatForced(ref, usd)
            : '••••••';
    final figure = Semantics(
      container: true,
      label: [
        l10n.portfolioInvestedLabel,
        if (picked != null) _venueName(l10n, picked),
        text,
      ].join(', '),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.portfolioInvestedLabel,
              key: const ValueKey('portfolio-hero-caption'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _quiet(context)),
          SizedBox(height: 4.h),
          // Scaled down rather than cut on a narrow phone or at a large
          // text size; never animated in size.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: BalancesLiveFigure(
              key: const ValueKey('portfolio-hero-value'),
              figure: BalancesFigure(text,
                  stale: usd != null && (stale || refreshing), usd: usd),
              style: TextStyle(
                color: c.textPrimary,
                fontSize: kPortfolioHeroFigure.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.2,
                height: 1.1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
    // With a venue picked, "All" at the block's end puts both venues back
    // (the picked square tapped again does too); it fades in and out, and
    // nothing in the block moves for it.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: figure),
        ArrivalSwitcher(
          state: picked != null,
          animateSize: false,
          alignment: Alignment.centerRight,
          child: picked == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: EdgeInsetsDirectional.only(start: 8.w),
                  child: KutePill(
                    key: const ValueKey('portfolio-hero-all'),
                    label: l10n.portfolioPnlAllVenues,
                    icon: Icons.close_rounded,
                    selected: true,
                    link: true,
                    size: KutePillSize.compact,
                    onTap: () => portfolioPickPnlVenue(ref, null),
                  ),
                ),
        ),
      ],
    );
  }
}

/// A P&L venue as the one balance names it.
OneBalanceVenue _oneBalanceVenue(PortfolioPerformanceVenue venue) =>
    venue == PortfolioPerformanceVenue.trading
        ? OneBalanceVenue.investing
        : OneBalanceVenue.predictions;

/// A venue's name as the app writes it.
String _venueName(AppLocalizations l10n, PortfolioPerformanceVenue venue) =>
    venue == PortfolioPerformanceVenue.predictions
        ? l10n.predictions
        : l10n.trading;

/// A venue's logo (the P&L squares').
String _venueLogo(PortfolioPerformanceVenue venue) => venueMarkAsset(
    venue == PortfolioPerformanceVenue.predictions
        ? InvestmentsProduct.predictions
        : InvestmentsProduct.trading);

/// "3 positions · Available $17.64" (see the file header); with a venue
/// picked, that venue's positions (Available is the one balance's, never
/// a venue's).
class _HeroLine extends ConsumerWidget {
  const _HeroLine({this.venue});

  final PortfolioPerformanceVenue? venue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = context.l10n;
    final state = ref.watch(oneBalanceProvider);
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final all = ref.watch(portfolioVenuesProvider);
    final picked = venue;
    final count = portfolioOpenCount(
        ref,
        picked == null
            ? all
            : PortfolioVenues(
                trading:
                    all.trading && picked == PortfolioPerformanceVenue.trading,
                predictions: all.predictions &&
                    picked == PortfolioPerformanceVenue.predictions));
    // Dollars and both venues' cash read: the figure; else the last one
    // known, sweeping; never read, a dash.
    final cached = resolveVenueTotal(
      walletId:
          ref.watch(settingsProvider.select((s) => pickSpendingWallet(s)?.id)),
      venue: 'portfolio_available',
      fresh: state.dollarsKnown &&
              state.investingKnown &&
              state.predictionsKnown &&
              !ref.watch(usdBalanceUnknownProvider)
          ? state.availableUsd
          : null,
    );
    final quiet = _quiet(context);
    // Read once, ever: the Dollars header's own Available (the same split,
    // see the file header); never read, a dash.
    final split = InvestmentBalanceHeader.oneBalanceSplitFigures(ref);
    final usd = cached.value == null ? null : split.availableUsd;
    final available = BalancesFigure(
        usd == null
            ? '—'
            : visible
                ? formatPolyFiatForced(ref, usd)
                : '••••••',
        stale: usd != null && cached.stale,
        usd: usd);
    return Semantics(
      container: true,
      label: [
        if (count > 0) l10n.portfolioPositionsCount(count),
        '${l10n.portfolioAvailableLabel} ${available.text}',
      ].join(', '),
      excludeSemantics: true,
      // One line, scaled down past the width rather than cut; the same
      // height whatever it says.
      child: SizedBox(
        height: MediaQuery.textScalerOf(context).scale(kPortfolioHeroQuiet.sp) *
                1.3 +
            2,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              key: const ValueKey('portfolio-hero-line'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (count > 0) ...[
                  Text(l10n.portfolioPositionsCount(count),
                      key: const ValueKey('portfolio-hero-positions'),
                      maxLines: 1,
                      style: quiet),
                  Text(' · ', style: quiet),
                ],
                Text('${l10n.portfolioAvailableLabel} ',
                    maxLines: 1, style: quiet),
                BalancesLiveFigure(
                  key: const ValueKey('portfolio-hero-available'),
                  figure: available,
                  style: quiet.copyWith(
                      color: c.textPrimary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The P&L line, the chart and the ranges (see the file header). Watches
/// only the venues' P&L, the live prices of the predictions held and the
/// range: a price tick on another market, the one balance moving or a
/// section switch never lays the series again.
///
/// [venue] (P&L, a venue square picked): that venue's series alone, the
/// line naming it with its logo. [open] (Positions): the open positions'
/// P&L now in the line ([_HeroOpenLine]) and their own chart under it
/// ([_OpenPnlChart], see the file header); the venues' reads stay watched
/// so the P&L chart is back at once on another section, but no series of
/// theirs is laid.
class PortfolioHeroChart extends ConsumerStatefulWidget {
  const PortfolioHeroChart(
      {super.key, this.now, this.open = false, this.venue});

  /// The moment the line ends on; now unless a test pins it.
  final DateTime? now;

  /// Positions: only the positions open now.
  final bool open;

  /// The venue drawn alone; null: both.
  final PortfolioPerformanceVenue? venue;

  @override
  ConsumerState<PortfolioHeroChart> createState() =>
      _PortfolioHeroChartState();
}

class _PortfolioHeroChartState extends ConsumerState<PortfolioHeroChart> {
  /// The point under the finger; null at rest. A notifier, not state: a
  /// scrub frame rebuilds the P&L line alone (the plot draws its own
  /// crosshair).
  final _scrub = ValueNotifier<KuteTrendPoint?>(null);

  /// The point under the finger on the Positions chart: its open P&L
  /// and its moment as written; null at rest. Read by the line alone.
  final _openScrub = ValueNotifier<OpenPnlScrub?>(null);

  /// The plot and its ranges as last drawn: what folds away when there is
  /// nothing to chart (without laying the series again).
  Widget? _lastChart;

  @override
  void dispose() {
    _scrub.dispose();
    _openScrub.dispose();
    super.dispose();
  }

  /// The line over the chart ([state] names what it shows, so a change of
  /// what it shows fades the old line out and the new one in, and a scrub
  /// or a new figure updates it in place) and the chart folding under it
  /// ([chart] null: folded).
  Widget _layout(
      {required Object state, required Widget line, required Widget? chart}) {
    if (chart != null) _lastChart = chart;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Words in the same place: the old line out, then the new one in,
        // never one over the other.
        ArrivalSwitcher(state: state, sequential: true, child: line),
        _HeroFold(
          folded: chart == null,
          child: chart ?? _lastChart ?? const SizedBox.shrink(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final venues = ref.watch(portfolioVenuesProvider);
    final range = ref.watch(pnlChartRangeProvider);
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final open = widget.open;

    // Each venue's P&L, the predictions at the live prices of the shares
    // held (another market's tick rebuilds nothing; on Positions, where no
    // series is drawn, none does).
    var loading = false;
    final known = <PortfolioPerformanceVenue, PortfolioPerformance>{};
    for (final (on, venue) in [
      (venues.trading, PortfolioPerformanceVenue.trading),
      (venues.predictions, PortfolioPerformanceVenue.predictions),
    ]) {
      if (!on) continue;
      final read = ref.watch(portfolioPerformanceDisplayProvider(
          PortfolioPerformanceRequest(venue: venue)));
      final data = read.valueOrNull;
      if (data == null) {
        if (!read.hasError) loading = true;
        continue;
      }
      known[venue] = venue == PortfolioPerformanceVenue.predictions && !open
          ? data.withLivePredictions(ref
              .watch(livePriceProvider.select(
                  (s) => HeldPredictionPrices.of(data.predictions, s.prices)))
              .prices)
          : data;
    }
    // Positions: the open positions' P&L now, and its chart since each
    // was opened (its shapes while their history is read; folded with
    // nothing to chart).
    if (open) {
      final status = ref.watch(openPnlChartStatusProvider);
      return _layout(
        state: 'open',
        line: _HeroOpenLine(scrub: _openScrub),
        chart: switch (status) {
          OpenPnlChartStatus.none => null,
          OpenPnlChartStatus.loading => const _HeroPlotSkeleton(),
          OpenPnlChartStatus.chart => _OpenPnlChart(scrub: _openScrub),
        },
      );
    }
    // A finger left on the Positions chart as the section changed: no
    // stale moment when Positions is back (after this frame: the line may
    // still be fading out).
    if (_openScrub.value != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _openScrub.value = null);
    }
    if (loading) {
      return _layout(
          state: 'loading',
          line: const _HeroLineSkeleton(),
          chart: const _HeroPlotSkeleton());
    }
    // Nothing read (no venue, or every read failed): the figure alone.
    if (known.isEmpty) {
      return _layout(state: 'none', line: SizedBox(height: 4.h), chart: null);
    }

    // The venue picked, when its P&L is read; else both.
    final picked = widget.venue != null && known.containsKey(widget.venue)
        ? widget.venue
        : null;
    final data = picked != null
        ? known[picked]!
        : known.length == 1
            ? known.values.single
            : PortfolioPerformance.combine(known.values.toList());
    final series = pnlSeries(data, widget.now ?? DateTime.now());
    final quiet = _quiet(context);
    // Never traded: the figure alone; the sections say it with Sal.
    if (!series.values.any((v) => v != 0)) {
      return _layout(
          state: 'none',
          line: SizedBox(
              key: const ValueKey('portfolio-hero-no-history'), height: 4.h),
          chart: null);
    }

    final shown = kuteTrendWindow(series, series.spanFor(range));
    final values = shown.values;
    final times = shown.times;
    final locale = kuteChartLocale(context);
    // On daily (or coarser) buckets a point at midnight closes the day
    // before; finer buckets say when in the day.
    final daily =
        series.strideFor(series.spanFor(range)) * series.cellMinutes >= 1440;
    String timeOf(DateTime t) {
      final d = daily && t.hour == 0 && t.minute == 0
          ? t.subtract(const Duration(minutes: 1))
          : t;
      return daily ? kuteChartDay(d, locale) : kuteChartDayTime(t, locale);
    }

    String money(double v) =>
        visible ? formatPolyAmount(ref, v.abs()) : '••••••';
    final venueName = picked == null ? null : _venueName(l10n, picked);

    // The P&L line: over the range, or since its start to the point under
    // the finger; the venue picked named first, after its logo.
    Widget change(KuteTrendPoint? point) {
      final scrub =
          point != null && point.index < values.length ? point : null;
      final pnl = pnlRangeChange(values, range, at: scrub?.value) ??
          series.values.last;
      final tail = scrub != null
          ? timeOf(scrub.time ?? times.last)
          : kuteTrendPeriodLabel(l10n, range);
      final color = !visible || pnl == 0 ? c.textPrimary : pnlResultColor(c, pnl);
      final text = Text.rich(
        TextSpan(children: [
          if (venueName != null)
            TextSpan(
                text: '$venueName · ',
                style: TextStyle(
                    color: c.textPrimary, fontWeight: FontWeight.w600)),
          TextSpan(
            // Hidden: dots alone, no arrow to read a direction from.
            text: visible ? '${kuteTrendArrow(pnl)}${money(pnl)}' : money(pnl),
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          TextSpan(text: ' · $tail'),
        ]),
        key: const ValueKey('portfolio-hero-change'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: quiet,
      );
      if (picked == null) return text;
      final logo =
          MediaQuery.textScalerOf(context).scale(kPortfolioHeroQuiet.sp) * 1.15;
      return Row(
        children: [
          SvgPicture.asset(_venueLogo(picked),
              key: const ValueKey('portfolio-hero-venue-logo'),
              width: logo,
              height: logo,
              fit: BoxFit.contain),
          SizedBox(width: 6.w),
          Flexible(child: text),
        ],
      );
    }

    return _layout(
      state: 'range-${picked?.name ?? 'all'}',
      line: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 6.h),
          ValueListenableBuilder<KuteTrendPoint?>(
            valueListenable: _scrub,
            builder: (context, point, _) => change(point),
          ),
        ],
      ),
      chart: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 16.h),
          // One chart whatever is drawn: a venue picked, or both again,
          // morphs the line (KuteMotion's chip spring).
          KuteTrendChart(
            key: const ValueKey('portfolio-hero-chart'),
            values: values,
            times: times,
            lineColor: values.isEmpty
                ? c.textPrimary
                : pnlResultColor(c, values.last - values.first),
            zeroSplit: true,
            height: kKuteTrendPlotHeightCompact.h,
            onScrub: (p) => _scrub.value = p,
            // Once per scrub gesture.
            onScrubStart: () => TrackingService.track(
                'portfolio_performance_chart_scrubbed',
                params: {'venue': pnlEventVenue(picked)}),
            rangeLabels: [for (final r in BalanceRange.values) r.label],
            selectedRange: range.index,
            onRangeSelected: (i) => ref
                .read(pnlChartRangeProvider.notifier)
                .state = BalanceRange.values[i],
          ),
        ],
      ),
    );
  }
}

/// Positions: what the open positions made or lost so far, both venues
/// added, at the live prices (open_investments_screen.dart,
/// [portfolioOpenPnl]: the rows' P&L added): "▲ $0.52 (2.7%) · Open P&L",
/// in the result colour, the percent of what they cost only where every
/// one of them has a cost (a prediction its entry, a perp its margin, a
/// holding its recorded cost). Nothing open: no line. Its own widget, so
/// a tick rebuilds this line alone; tabular figures, so it never jitters.
/// While a finger is on the Positions chart ([scrub]), the open P&L at
/// that moment and the moment: "▲ $0.40 · Open P&L · Oct 16 14:00" (no
/// percent: what they cost then is not what they cost now); only the
/// text rebuilds on a scrub frame.
class _HeroOpenLine extends ConsumerWidget {
  const _HeroOpenLine({this.scrub});

  final ValueListenable<OpenPnlScrub?>? scrub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = context.l10n;
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final pnl = portfolioOpenPnl(ref, ref.watch(portfolioVenuesProvider));
    if (pnl == null) {
      return SizedBox(
          key: const ValueKey('portfolio-hero-open-none'), height: 4.h);
    }
    final quiet = _quiet(context);
    Widget line(OpenPnlScrub? at) {
      // Under a cent is no move.
      final raw = at?.value ?? pnl.usd;
      final usd = raw.abs() < kBalancesCentUsd ? 0.0 : raw;
      final percent = at == null && visible && pnl.costed && usd != 0
          ? BalancesPnlText.percentOf(usd, pnl.costUsd)
          : null;
      final color =
          !visible || usd == 0 ? c.textPrimary : pnlResultColor(c, usd);
      final amount = visible
          ? '${kuteTrendArrow(usd)}${formatPolyAmount(ref, usd.abs())}'
              '${percent == null ? '' : ' ($percent)'}'
          : '••••••';
      return Text.rich(
        TextSpan(children: [
          TextSpan(
            text: amount,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          TextSpan(
              text: ' · ${l10n.portfolioStatOpenPnl}'
                  '${at == null ? '' : ' · ${at.when}'}'),
        ]),
        key: const ValueKey('portfolio-hero-open'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: quiet,
      );
    }

    final scrub = this.scrub;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 6.h),
        if (scrub == null)
          line(null)
        else
          ValueListenableBuilder<OpenPnlScrub?>(
            valueListenable: scrub,
            builder: (context, at, _) => line(at),
          ),
      ],
    );
  }
}

/// A point under the finger on the Positions chart: the open P&L then and
/// its moment as the line writes it.
typedef OpenPnlScrub = ({double value, String when});

/// The open positions' P&L since each was opened (see the file header):
/// the range's points ([openPnlWindowProvider], laid once per range and
/// history), the last one the open P&L now (portfolioOpenPnl, the left-out
/// positions left out, so with all of them charted it IS the line's
/// figure). A tick moves that point alone (the chart repaints, no morph);
/// a scrub frame rebuilds neither this nor the hero.
class _OpenPnlChart extends ConsumerWidget {
  const _OpenPnlChart({required this.scrub});

  final ValueNotifier<OpenPnlScrub?> scrub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = context.l10n;
    final range = ref.watch(openPnlShownRangeProvider);
    final window = ref.watch(openPnlWindowProvider(range));
    final leftOut = ref.watch(openPnlHistoryProvider
            .select((read) => read.valueOrNull?.leftOut)) ??
        const <String>{};
    if (window == null || window.values.isEmpty) {
      return const _HeroPlotSkeleton();
    }
    final now = portfolioOpenPnl(ref, ref.watch(portfolioVenuesProvider),
        leaveOut: leftOut);
    final values = [...window.values];
    if (now != null) values[values.length - 1] = now.usd;
    final times = window.times;
    final locale = kuteChartLocale(context);
    String timeOf(DateTime t) {
      // On daily buckets a point at midnight closes the day before.
      final d = window.daily && t.hour == 0 && t.minute == 0
          ? t.subtract(const Duration(minutes: 1))
          : t;
      return window.daily
          ? kuteChartDay(d, locale)
          : kuteChartDayTime(t, locale);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 16.h),
        KuteTrendChart(
          key: const ValueKey('portfolio-hero-open-chart'),
          values: values,
          times: times,
          // The figure's own colour: green above zero, red below.
          lineColor: pnlResultColor(c, values.last),
          zeroSplit: true,
          baseline: 0,
          height: kKuteTrendPlotHeightCompact.h,
          onScrub: (p) => scrub.value = p == null
              ? null
              : (value: p.value, when: timeOf(p.time ?? times.last)),
          // Once per scrub gesture.
          onScrubStart: () => TrackingService.track(
              'portfolio_performance_chart_scrubbed',
              params: {'venue': 'open_positions'}),
          rangeLabels: [for (final r in BalanceRange.values) r.label],
          selectedRange: range.index,
          onRangeSelected: (i) => ref
              .read(openPnlRangeProvider.notifier)
              .state = BalanceRange.values[i],
        ),
        if (leftOut.isNotEmpty) ...[
          SizedBox(height: 10.h),
          Text(
            l10n.portfolioOpenPnlNotCharted(leftOut.length),
            key: const ValueKey('portfolio-hero-open-left-out'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 12.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

/// The chart's room: with nothing to chart (no history, nothing open on
/// Positions) it eases to nothing as it fades, and back once there is
/// (KuteMotion's settle, 300 ms; at once under Reduce Motion). Clipped only while it moves, so at rest the range
/// pill's shadow is whole; once folded the chart leaves the tree (no
/// taps, nothing read out, nothing painted), and coming back it draws in
/// afresh.
class _HeroFold extends StatelessWidget {
  const _HeroFold({required this.folded, required this.child});

  final bool folded;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(end: folded ? 0 : 1),
        duration: kuteMotion(context, KuteMotion.settleDuration),
        curve: KuteMotion.settle,
        child: child,
        builder: (context, open, child) {
          if (open <= 0) return const SizedBox(width: double.infinity);
          return ClipRect(
            clipBehavior: open < 1 ? Clip.hardEdge : Clip.none,
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: open,
              child: IgnorePointer(
                ignoring: open < 1,
                child: Opacity(opacity: open.clamp(0.0, 1.0), child: child),
              ),
            ),
          );
        },
      );
}

/// The P&L line as a shape while the history is on its way, at its own
/// size, so nothing moves when it lands.
class _HeroLineSkeleton extends StatelessWidget {
  const _HeroLineSkeleton();

  @override
  Widget build(BuildContext context) => KuteSkeleton(
        key: const ValueKey('portfolio-hero-loading'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 6.h),
            SkeletonBar(150.w, kPortfolioHeroQuiet.sp),
          ],
        ),
      );
}

/// The plot and the range row as shapes while the history is on its way.
class _HeroPlotSkeleton extends StatelessWidget {
  const _HeroPlotSkeleton();

  @override
  Widget build(BuildContext context) => KuteSkeleton(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 16.h),
            SkeletonBar(double.infinity, kKuteTrendPlotHeightCompact.h,
                radius: 12.r),
            SizedBox(height: kKuteTrendRangeGap.h),
            SkeletonBar(double.infinity, 28.h, radius: 14.h),
          ],
        ),
      );
}
