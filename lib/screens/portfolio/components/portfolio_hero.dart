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
//     positions the Positions section lists; Available as the one balance
//     counts it: Dollars and the venues' spare cash). Nothing open: the
//     Available alone.
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
// Analytics: `portfolio_performance_chart_scrubbed` {venue: all} once per
// scrub gesture, as the P&L chart sent it. Ranges send nothing.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart';
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
    show BalancesFigure, BalancesLiveFigure;
import 'package:kute/screens/portfolio/components/portfolio_pnl_chart.dart'
    show pnlChartRangeProvider, pnlRangeChange, pnlResultColor;
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show portfolioOpenCount;
import 'package:kute/screens/portfolio/portfolio_balance_breakdown.dart'
    show kBreakdownRefreshCap;
import 'package:kute/screens/portfolio/portfolio_filters.dart';
import 'package:kute/screens/shared/charts/kute_chart_format.dart';
import 'package:kute/screens/shared/charts/kute_trend_chart.dart';
import 'package:kute/screens/shared/charts/kute_trend_window.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_total_cache_service.dart'
    show resolveVenueTotal;
import 'package:kute/theme/app_theme.dart';

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
  const PortfolioHero({super.key});

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
        _HeroFigure(refreshing: _refreshing),
        const PortfolioHeroChart(),
        SizedBox(height: 16.h),
        const _HeroLine(),
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

/// "Invested" over the figure (see the file header).
class _HeroFigure extends ConsumerWidget {
  const _HeroFigure({required this.refreshing});

  final bool refreshing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = context.l10n;
    final state = ref.watch(oneBalanceProvider);
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    // The Dollars header's figure (its cache too): both venues read, the
    // figure; else the last one known, sweeping; never read, a dash.
    final display = resolveVenueTotal(
      walletId:
          ref.watch(settingsProvider.select((s) => pickSpendingWallet(s)?.id)),
      venue: kInvestmentsInvestedCacheKey,
      fresh: state.investingKnown && state.predictionsKnown
          ? state.investedUsd
          : null,
    );
    final usd = display.value;
    final text = usd == null
        ? '—'
        : visible
            ? formatPolyFiatForced(ref, usd)
            : '••••••';
    return Semantics(
      container: true,
      label: '${l10n.portfolioInvestedLabel}, $text',
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
                  stale: usd != null && (display.stale || refreshing),
                  usd: usd),
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
  }
}

/// "3 positions · Available $17.64" (see the file header).
class _HeroLine extends ConsumerWidget {
  const _HeroLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = context.l10n;
    final state = ref.watch(oneBalanceProvider);
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final count = portfolioOpenCount(ref, ref.watch(portfolioVenuesProvider));
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
    final usd = cached.value;
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
class PortfolioHeroChart extends ConsumerStatefulWidget {
  const PortfolioHeroChart({super.key, this.now});

  /// The moment the line ends on; now unless a test pins it.
  final DateTime? now;

  @override
  ConsumerState<PortfolioHeroChart> createState() =>
      _PortfolioHeroChartState();
}

class _PortfolioHeroChartState extends ConsumerState<PortfolioHeroChart> {
  /// The point under the finger; null at rest. A notifier, not state: a
  /// scrub frame rebuilds the P&L line alone (the plot draws its own
  /// crosshair).
  final _scrub = ValueNotifier<KuteTrendPoint?>(null);

  @override
  void dispose() {
    _scrub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final venues = ref.watch(portfolioVenuesProvider);
    final range = ref.watch(pnlChartRangeProvider);
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));

    // Each venue's P&L, the predictions at the live prices of the shares
    // held (another market's tick rebuilds nothing).
    var loading = false;
    final known = <PortfolioPerformance>[];
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
      known.add(venue == PortfolioPerformanceVenue.predictions
          ? data.withLivePredictions(ref
              .watch(livePriceProvider.select(
                  (s) => HeldPredictionPrices.of(data.predictions, s.prices)))
              .prices)
          : data);
    }
    if (loading) return const _HeroChartSkeleton();
    // Nothing read (no venue, or every read failed): the figure alone.
    if (known.isEmpty) return SizedBox(height: 4.h);

    final data =
        known.length == 1 ? known.single : PortfolioPerformance.combine(known);
    final series = pnlSeries(data, widget.now ?? DateTime.now());
    final quiet = _quiet(context);
    // Never traded: the figure alone; the sections say it with Sal.
    if (!series.values.any((v) => v != 0)) {
      return SizedBox(
          key: const ValueKey('portfolio-hero-no-history'), height: 4.h);
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

    // The P&L line: over the range, or since its start to the point under
    // the finger.
    Widget change(KuteTrendPoint? point) {
      final scrub =
          point != null && point.index < values.length ? point : null;
      final pnl = pnlRangeChange(values, range, at: scrub?.value) ??
          series.values.last;
      final tail = scrub != null
          ? timeOf(scrub.time ?? times.last)
          : kuteTrendPeriodLabel(l10n, range);
      final color = !visible || pnl == 0 ? c.textPrimary : pnlResultColor(c, pnl);
      return Text.rich(
        TextSpan(children: [
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
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 6.h),
        ValueListenableBuilder<KuteTrendPoint?>(
          valueListenable: _scrub,
          builder: (context, point, _) => change(point),
        ),
        SizedBox(height: 16.h),
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
              params: const {'venue': 'all'}),
          rangeLabels: [for (final r in BalanceRange.values) r.label],
          selectedRange: range.index,
          onRangeSelected: (i) => ref
              .read(pnlChartRangeProvider.notifier)
              .state = BalanceRange.values[i],
        ),
      ],
    );
  }
}

/// The P&L line, the plot and the range row as shapes while the history
/// is on its way, at their own sizes, so nothing moves when it lands.
class _HeroChartSkeleton extends StatelessWidget {
  const _HeroChartSkeleton();

  @override
  Widget build(BuildContext context) => KuteSkeleton(
        key: const ValueKey('portfolio-hero-loading'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 6.h),
            SkeletonBar(150.w, kPortfolioHeroQuiet.sp),
            SizedBox(height: 16.h),
            SkeletonBar(double.infinity, kKuteTrendPlotHeightCompact.h,
                radius: 12.r),
            SizedBox(height: kKuteTrendRangeGap.h),
            SkeletonBar(double.infinity, 28.h, radius: 14.h),
          ],
        ),
      );
}
