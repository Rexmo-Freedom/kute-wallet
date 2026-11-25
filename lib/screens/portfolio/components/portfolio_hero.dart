// lib/screens/portfolio/components/portfolio_hero.dart
//
// Dollars money: every figure here reads in dollars, whatever the Settings
// currency; only Bitcoin's conversion follows Settings
// (polymarket_amount_formatter.dart).
//
// THE PORTFOLIO SCREEN'S HERO, one instance over every section (the
// redesign of 7 November 2026 after the Robinhood / Public / Webull /
// Polymarket / Kalshi review; founder: "yes build this"), left-aligned in
// the 16 gutters, top down:
//
//   * the TOTAL the account holds there, 40 sp w700, tabular, rolling in
//     place: what the open positions are worth now plus Available, the
//     Dollars header's own split (InvestmentBalanceHeader
//     .oneBalanceSplitFigures: the same snapshot, the same display cache,
//     to the cent in dollars; never the money its in-flight
//     lines name); the last figure known, dimmed and sweeping
//     ([StaleShimmer]), while a venue is read (again), a dash before
//     anything was ever read; dots with balances hidden. No caption: the
//     number speaks for itself, as on a brokerage's home;
//   * under it the P&L over the range the pills show, in the result
//     colour: "▲ $7.55 (+12.0%) · Past month" (portfolio_pnl_period.dart:
//     the line's end less the range's start, ALL the P&L since the
//     account began), the percent only on a real base
//     ([portfolioPnlPercent]: what was held at the range's start of at
//     least a dollar, under 1000 %), else the amount alone. While a finger
//     scrubs the line it reads "Up $4.10 · Oct 12" / "Down $1.20 · Oct 12"
//     (the P&L since the range's start to the point under the finger; ALL,
//     the P&L then); only that line rebuilds on a scrub frame (a
//     [ValueNotifier], never the section);
//   * ONE chart: the account's P&L over the range from the whole P&L
//     history engine (providers/open_pnl_history_provider.dart), never a
//     value line (money moved in or out would make it jump); its last
//     point the P&L now, so the line's figure IS the hero's.
//     [KuteTrendChart] green or red by the range's result, the split fill
//     and the dotted line at zero, the scrub, the compact plot; "N
//     positions not charted" under it for a position whose line cannot be
//     read; the range row 1W 1M 3M ALL (kPortfolioPnlRanges, fw34's rule:
//     the fixed ranges shorter than the history, then ALL; a pick the line
//     does not offer draws ALL with ALL lit; 1M to start, ALL when 1M is
//     not offered; under a week nothing to pick and no row). The pick is
//     shared with the P&L tab's headline, its "By product" rows and the
//     "Share P&L" card;
//   * one quiet line: "Invested $X · Available $Y", the two adding up to
//     the total above.
//
// THE P&L TAB'S DRILL ([PortfolioHero.venue], portfolioPnlVenueProvider;
// a "By product" row tapped): the line names the venue after its logo
// ("Predictions · ▲ $5.78 · Past month", the amount alone: a percent of
// the whole account's base would mean nothing), the chart is that venue's
// line (the same chart morphing to it on the chip spring), and a small
// "All" chip beside the total puts both venues back, as the picked row
// tapped again does. The total and the line under the chart stay the
// account's.
//
// Never traded (a P&L that never left zero): no P&L line, no chart and no
// range row, the total and the line under it alone. A history still on
// its way: the shapes of the line, the plot and the ranges as a skeleton,
// never a blank frame that then jumps. The venues are read again as the
// screen opens (as their pull to refresh does, capped).
//
// Transitions: the line's words fade out then in (ArrivalSwitcher
// .sequential), the chart folds and unfolds on KuteMotion's settle (300
// ms) and draws in afresh, the figure rolls; all at once under Reduce
// Motion. Every figure is tabular, so a live tick never shifts the line.
//
// Analytics: `portfolio_performance_chart_scrubbed` {venue: all |
// hyperliquid | polymarket, the series drawn} once per scrub gesture; the
// "All" chip sends `portfolio_statistics_venue_toggled` {venue: all}, as
// a row does. Ranges send nothing.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart'
    show hyperliquidTradingProvider;
import 'package:kute/providers/one_balance_provider.dart';
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
    show BalancesFigure, BalancesLiveFigure, kBalancesCentUsd;
import 'package:kute/screens/portfolio/components/portfolio_pnl_chart.dart'
    show
        pnlChartRangeProvider,
        pnlEventVenue,
        pnlRangeChange,
        pnlResultColor,
        portfolioPickPnlVenue;
import 'package:kute/screens/portfolio/components/portfolio_pnl_period.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show InvestmentsProduct;
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
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_total_cache_service.dart'
    show resolveVenueTotal;
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart';

/// The display cache's key for the Invested figure: the Dollars header's
/// own (venue_total_cache_service.dart, resolveInvestmentsDisplay), so the
/// two never disagree while a venue is read again.
const String kInvestmentsInvestedCacheKey = 'investments_invested';

/// The display cache's key for Available.
const String kPortfolioAvailableCacheKey = 'portfolio_available';

/// The hero figure's size, design units.
const double kPortfolioHeroFigure = 40;

/// The hero's line and caption size, design units.
const double kPortfolioHeroQuiet = 13;

/// The hero (see the file header).
class PortfolioHero extends ConsumerStatefulWidget {
  const PortfolioHero({super.key, this.venue});

  /// P&L: the "By product" row picked ([portfolioPnlVenueProvider]); null:
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
        PortfolioHeroChart(venue: widget.venue),
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

/// The hero's Invested and Available (see the file header): the Dollars
/// header's own split, each null before it was ever read (a dash), stale
/// while its last figure known stands in.
typedef PortfolioHeroSplit = ({
  double? investedUsd,
  double? availableUsd,
  bool investedStale,
  bool availableStale,
});

/// [PortfolioHeroSplit] from a build.
PortfolioHeroSplit portfolioHeroSplit(WidgetRef ref) {
  final state = ref.watch(oneBalanceProvider);
  final walletId =
      ref.watch(settingsProvider.select((s) => pickSpendingWallet(s)?.id));
  // Both venues read, the figure; else the last one known, sweeping;
  // never read, a dash.
  final invested = resolveVenueTotal(
    walletId: walletId,
    venue: kInvestmentsInvestedCacheKey,
    fresh: state.investingKnown && state.predictionsKnown
        ? state.investedUsd
        : null,
  );
  final available = resolveVenueTotal(
    walletId: walletId,
    venue: kPortfolioAvailableCacheKey,
    fresh: state.dollarsKnown &&
            state.investingKnown &&
            state.predictionsKnown &&
            !ref.watch(usdBalanceUnknownProvider)
        ? state.availableUsd
        : null,
  );
  // Read once, ever: the Dollars header's own figures (the same split).
  final split = InvestmentBalanceHeader.oneBalanceSplitFigures(ref);
  return (
    investedUsd: invested.value == null ? null : split.investedUsd,
    availableUsd: available.value == null ? null : split.availableUsd,
    investedStale: invested.stale,
    availableStale: available.stale,
  );
}

/// The total: what the open positions are worth plus Available; null
/// while either was never read.
double? portfolioHeroTotal(PortfolioHeroSplit split) {
  final invested = split.investedUsd;
  final available = split.availableUsd;
  if (invested == null || available == null) return null;
  return invested + available;
}

/// The total (see the file header); with a venue picked, the "All" chip
/// beside it.
class _HeroFigure extends ConsumerWidget {
  const _HeroFigure({required this.refreshing, this.venue});

  final bool refreshing;
  final PortfolioPerformanceVenue? venue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = context.l10n;
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final split = portfolioHeroSplit(ref);
    final usd = portfolioHeroTotal(split);
    final stale = split.investedStale || split.availableStale;
    final text = usd == null
        ? '—'
        : visible
            ? formatDollars(usd)
            : '••••••';
    final figure = Semantics(
      container: true,
      label: '${l10n.total}, $text',
      excludeSemantics: true,
      // Scaled down rather than cut on a narrow phone or at a large text
      // size; never animated in size.
      child: FittedBox(
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
    );
    final picked = venue;
    // With a venue picked, "All" at the block's end puts both venues back
    // (the picked row tapped again does too); it fades in and out, and
    // nothing in the block moves for it.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
            child: Align(alignment: Alignment.centerLeft, child: figure)),
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

/// A venue's name as the app writes it.
String _venueName(AppLocalizations l10n, PortfolioPerformanceVenue venue) =>
    venue == PortfolioPerformanceVenue.predictions
        ? l10n.predictions
        : l10n.trading;

/// A venue's logo.
String _venueLogo(PortfolioPerformanceVenue venue) => venueMarkAsset(
    venue == PortfolioPerformanceVenue.predictions
        ? InvestmentsProduct.predictions
        : InvestmentsProduct.trading);

/// "Invested $X · Available $Y" (see the file header): the two adding up
/// to the total above, the account's whatever is picked.
class _HeroLine extends ConsumerWidget {
  const _HeroLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = context.l10n;
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final split = portfolioHeroSplit(ref);
    BalancesFigure figure(double? usd, bool stale) => BalancesFigure(
        usd == null
            ? '—'
            : visible
                ? formatDollars(usd)
                : '••••••',
        stale: usd != null && stale,
        usd: usd);
    final invested = figure(split.investedUsd, split.investedStale);
    final available = figure(split.availableUsd, split.availableStale);
    final quiet = _quiet(context);
    final strong =
        quiet.copyWith(color: c.textPrimary, fontWeight: FontWeight.w600);
    return Semantics(
      container: true,
      label: '${l10n.portfolioInvestedLabel} ${invested.text}, '
          '${l10n.portfolioAvailableLabel} ${available.text}',
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
                Text('${l10n.portfolioInvestedLabel} ',
                    maxLines: 1, style: quiet),
                BalancesLiveFigure(
                  key: const ValueKey('portfolio-hero-invested'),
                  figure: invested,
                  style: strong,
                ),
                Text(' · ', style: quiet),
                Text('${l10n.portfolioAvailableLabel} ',
                    maxLines: 1, style: quiet),
                BalancesLiveFigure(
                  key: const ValueKey('portfolio-hero-available'),
                  figure: available,
                  style: strong,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The P&L line, the chart and the ranges (see the file header), from the
/// period figure ([portfolioPnlPeriod]): only the venues' P&L, the live
/// prices of the predictions held and the range are watched, so a price
/// tick on another market, the one balance moving or a section switch
/// never lays the series again. [venue]: that venue's line alone, the line
/// naming it with its logo.
class PortfolioHeroChart extends ConsumerStatefulWidget {
  const PortfolioHeroChart({super.key, this.now, this.venue});

  /// The moment the venues' own line ends on; now unless a test pins it.
  final DateTime? now;

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

  /// The plot and its ranges as last drawn: what folds away when there is
  /// nothing to chart (without laying the series again).
  Widget? _lastChart;

  @override
  void dispose() {
    _scrub.dispose();
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
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final period =
        portfolioPnlPeriod(ref, venue: widget.venue, now: widget.now);
    switch (period.status) {
      case PortfolioPnlStatus.loading:
        return _layout(
            state: 'loading',
            line: const _HeroLineSkeleton(),
            chart: const _HeroPlotSkeleton());
      case PortfolioPnlStatus.none:
        // Never traded, or nothing read: the total alone.
        return _layout(
            state: 'none',
            line: SizedBox(
                key: const ValueKey('portfolio-hero-no-history'), height: 4.h),
            chart: null);
      case PortfolioPnlStatus.ready:
        break;
    }
    final values = period.values;
    final times = period.times;
    final range = period.range;
    final ranges = period.ranges;
    final picked = period.venue;
    final locale = kuteChartLocale(context);
    String timeOf(DateTime t) {
      final d = period.daily && t.hour == 0 && t.minute == 0
          ? t.subtract(const Duration(minutes: 1))
          : t;
      return period.daily
          ? kuteChartDay(d, locale)
          : kuteChartDayTime(t, locale);
    }

    String money(double v) => formatDollars(v.abs());
    final quiet = _quiet(context);
    // The account's base for the percent: the total now (none with a
    // venue picked, see the file header).
    final total = picked == null ? portfolioHeroTotal(portfolioHeroSplit(ref)) : null;

    // The P&L line: over the range at rest, "Up $4.10 · Oct 12" under the
    // finger; the venue picked named first, after its logo.
    Widget change(KuteTrendPoint? point) {
      final scrub =
          point != null && point.index < values.length ? point : null;
      final raw = scrub != null
          ? pnlRangeChange(values, range, at: scrub.value) ?? period.live
          : period.change;
      // Under a cent is no move.
      final pnl = raw.abs() < kBalancesCentUsd ? 0.0 : raw;
      final color = !visible || pnl == 0 ? c.textPrimary : pnlResultColor(c, pnl);
      final String amount;
      if (!visible) {
        // Hidden: dots alone, nothing to read a direction from.
        amount = '••••••';
      } else if (scrub != null) {
        amount = pnl > 0
            ? l10n.portfolioHeroUp(money(pnl))
            : pnl < 0
                ? l10n.portfolioHeroDown(money(pnl))
                : l10n.chartNoChange;
      } else {
        final percent =
            pnl == 0 ? null : portfolioPnlPercent(pnl, total);
        amount = '${kuteTrendArrow(pnl)}${money(pnl)}'
            '${percent == null ? '' : ' (${kuteSignedPercent(percent)})'}';
      }
      final tail = scrub != null
          ? timeOf(scrub.time ?? times.last)
          : kuteTrendPeriodLabel(l10n, range);
      final text = Text.rich(
        TextSpan(children: [
          if (picked != null)
            TextSpan(
                text: '${_venueName(l10n, picked)} · ',
                style: TextStyle(
                    color: c.textPrimary, fontWeight: FontWeight.w600)),
          TextSpan(
            text: amount,
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
            // The figure's own colour: the range's P&L, green or red.
            lineColor: values.isEmpty
                ? c.textPrimary
                : pnlResultColor(c, period.change),
            zeroSplit: true,
            // The dotted line at zero.
            baseline: 0,
            height: kKuteTrendPlotHeightCompact.h,
            onScrub: (p) => _scrub.value = p,
            // Once per scrub gesture.
            onScrubStart: () => TrackingService.track(
                'portfolio_performance_chart_scrubbed',
                params: {'venue': pnlEventVenue(picked)}),
            rangeLabels: _rangeLabels(ranges),
            selectedRange: ranges.indexOf(range),
            onRangeSelected: (i) =>
                ref.read(pnlChartRangeProvider.notifier).state = ranges[i],
          ),
          if (period.leftOut.isNotEmpty)
            _NotCharted(count: period.leftOut.length),
        ],
      ),
    );
  }
}

/// The range row for [ranges] (shortest first, ALL last): their labels;
/// none with ALL alone (a history under a week: nothing to pick).
List<String>? _rangeLabels(List<BalanceRange> ranges) =>
    ranges.length < 2 ? null : [for (final r in ranges) r.label];

/// "1 position not charted (history unavailable)" under the chart: a
/// position held now whose line could not be read (the figure still
/// counts it).
class _NotCharted extends StatelessWidget {
  const _NotCharted({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: 10.h),
        child: Text(
          context.l10n.portfolioOpenPnlNotCharted(count),
          key: const ValueKey('portfolio-hero-left-out'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
}

/// The chart's room: with nothing to chart (no history) it eases to nothing as it fades, and back once there is
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
