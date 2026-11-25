// lib/screens/portfolio/components/portfolio_pnl_period.dart
//
// Dollars money: every figure here reads in dollars, whatever the Settings
// currency; only Bitcoin's conversion follows Settings
// (polymarket_amount_formatter.dart).
//
// THE PORTFOLIO SCREEN'S ONE PERIOD FIGURE (founder, 7 November 2026,
// the redesign after the Robinhood / Public / Webull / Polymarket / Kalshi
// review: "yes build this"). What the account made or lost over the range
// the hero's pills show, read ONCE here so every place that writes it
// agrees to the cent:
//
//   * the hero's line under the total ("▲ $7.55 (+12%) · Past month") and
//     its chart (components/portfolio_hero.dart);
//   * the P&L tab's headline ("You're up $7.55") and the two rows that add
//     up to it, the "By product" rows (portfolio_pnl_section.dart);
//   * the "Share P&L" card (brag_data.dart, bragPnl).
//
// THE LINE is the whole P&L history engine's (providers/
// open_pnl_history_provider.dart: every position's realised P&L stepping
// at its closes, plus what the positions held then were winning or losing,
// under each venue's own published figures), its last point pinned to the
// P&L now (the venues' own, the predictions at the live prices of the
// shares held). Never a value line: money moved in or out would make it
// jump. While the engine is read: [PortfolioPnlStatus.loading]; nothing it
// can chart: the venues' own published line ([pnlSeries]).
//
// THE RANGES (1W 1M 3M ALL, [kPortfolioPnlRanges]; fw34's rule): the
// fixed ranges shorter than the line's history, then ALL; a pick the line
// does not offer draws ALL with ALL lit, so the line always fills the
// width and no two pills draw the same thing. 1M to start
// (pnlChartRangeProvider), ALL when 1M is not offered.
//
// THE PERCENT ([portfolioPnlPercent]): the change over what the account
// held at the range's start, taken as what it holds now less the change
// (the money moved in the range counted from its start). Written only on
// a base of at least [kPortfolioPnlPercentBaseUsd] and under
// [kPortfolioPnlPercentCap] percent; else the amount alone.
//
// THE SPLIT ([portfolioPnlSplit], the P&L tab's two rows): "On open
// positions" is what the positions open now made over the range (their
// P&L now, the Positions rows' own figures added, portfolioOpenPnl, less
// what they stood at on the range's start, each from its own entry:
// openPnlHistoryProvider; ALL: their P&L since each was opened, the
// Dollars Open P&L card's figure); "From closed positions" is the rest of
// the change: what closing, selling and redeeming made, less what those
// positions already stood at when the range began, with what the venues
// count that no position carries (funding, fees booked apart). The two
// are rounded in the dollars on screen so the rows add up to the
// headline to the cent. Fees and funding are not a row of their own: the
// engine carries the fills' fees inside each position's realised P&L and
// funding only inside the venue's own figure, never apart.
//
// Pure reads from a build ([WidgetRef]): nothing here lays a line (the
// providers do, once per range and venue).

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/open_pnl_history.dart'
    show openPnlRangeShown, openPnlValueAt;
import 'package:kute/providers/open_pnl_history_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart'
    show livePriceProvider;
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/screens/portfolio/components/portfolio_pnl_chart.dart'
    show pnlChartRangeProvider, pnlRangeChange, pnlShownRangeProvider;
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show portfolioOpenPnl;
import 'package:kute/screens/portfolio/portfolio_filters.dart';
import 'package:kute/screens/shared/charts/kute_trend_window.dart'
    show kuteTrendWindow;

/// The ranges the Portfolio screen offers, shortest first, ALL last.
const List<BalanceRange> kPortfolioPnlRanges = kPnlHistoryRanges;

/// The least base a percent is written on (see the file header).
const double kPortfolioPnlPercentBaseUsd = 1;

/// A percent this large or larger is not written (a base too small to
/// mean anything).
const double kPortfolioPnlPercentCap = 1000;

/// What the period's figure is.
enum PortfolioPnlStatus {
  /// A venue's P&L or the engine's line is on its way: the shapes.
  loading,

  /// Nothing to show: no venue read, or a P&L that never left zero.
  none,

  /// A line and its figure.
  ready,
}

/// The P&L over the range the hero shows (see the file header).
@immutable
class PortfolioPnlPeriod {
  const PortfolioPnlPeriod({
    required this.status,
    this.venue,
    this.range = BalanceRange.all,
    this.ranges = kPortfolioPnlRanges,
    this.values = const [],
    this.times = const [],
    this.daily = false,
    this.live = 0,
    this.leftOut = const {},
  });

  final PortfolioPnlStatus status;

  /// The venue drawn alone (picked and read); null: the account.
  final PortfolioPerformanceVenue? venue;

  /// The range drawn (its pill lit).
  final BalanceRange range;

  /// The ranges the row offers, shortest first, ALL last.
  final List<BalanceRange> ranges;

  /// The line over [range], oldest first, its last point [live].
  final List<double> values;
  final List<DateTime> times;

  /// A bucket is a day or more: a moment is written as a day.
  final bool daily;

  /// The P&L now (the line's last point).
  final double live;

  /// Positions held now whose line could not be read.
  final Set<String> leftOut;

  bool get ready => status == PortfolioPnlStatus.ready;

  /// The P&L over [range]: the line's end less its start; ALL, the P&L
  /// since the account began.
  double get change => pnlRangeChange(values, range) ?? live;

  /// When the range starts; null with no line.
  DateTime? get start => times.isEmpty ? null : times.first;
}

/// The P&L over the range for [venue] (null: both venues the account has),
/// as the hero draws it (see the file header). [range] draws that range
/// instead of the hero's own pick (the "By product" rows, the share card:
/// the hero's range on one venue's line); [now] pins the venues' own line
/// in tests.
PortfolioPnlPeriod portfolioPnlPeriod(WidgetRef ref,
    {PortfolioPerformanceVenue? venue, BalanceRange? range, DateTime? now}) {
  final venues = ref.watch(portfolioVenuesProvider);
  final rangePicked = ref.watch(pnlChartRangeProvider);
  var loading = false;
  final known = <PortfolioPerformanceVenue, PortfolioPerformance>{};
  for (final (on, v) in [
    (venues.trading, PortfolioPerformanceVenue.trading),
    (venues.predictions, PortfolioPerformanceVenue.predictions),
  ]) {
    if (!on) continue;
    // Only the venue asked for when one is: another venue's tick
    // rebuilds nothing.
    if (venue != null && v != venue) continue;
    final read = ref.watch(portfolioPerformanceDisplayProvider(
        PortfolioPerformanceRequest(venue: v)));
    final data = read.valueOrNull;
    if (data == null) {
      if (!read.hasError) loading = true;
      continue;
    }
    known[v] = v == PortfolioPerformanceVenue.predictions
        ? data.withLivePredictions(ref
            .watch(livePriceProvider.select(
                (s) => HeldPredictionPrices.of(data.predictions, s.prices)))
            .prices)
        : data;
  }
  if (loading) {
    return const PortfolioPnlPeriod(status: PortfolioPnlStatus.loading);
  }
  if (known.isEmpty) {
    return const PortfolioPnlPeriod(status: PortfolioPnlStatus.none);
  }
  final picked = venue != null && known.containsKey(venue) ? venue : null;
  final data = picked != null
      ? known[picked]!
      : known.length == 1
          ? known.values.single
          : PortfolioPerformance.combine(known.values.toList());
  final live =
      data.totalPnlUsd ?? (data.points.isEmpty ? 0.0 : data.points.last.pnlUsd);
  // Never traded: nothing to show.
  if (live == 0 && !data.points.any((p) => p.pnlUsd != 0)) {
    return PortfolioPnlPeriod(status: PortfolioPnlStatus.none, venue: picked);
  }
  final engineVenue = picked ?? (known.length == 1 ? known.keys.single : null);
  final status = ref.watch(pnlChartStatusProvider(engineVenue));
  if (status == OpenPnlChartStatus.loading) {
    return PortfolioPnlPeriod(
        status: PortfolioPnlStatus.loading, venue: picked, live: live);
  }
  if (status == OpenPnlChartStatus.chart) {
    final ranges = ref.watch(pnlRangesProvider(engineVenue));
    final BalanceRange shown;
    if (range != null) {
      shown = range;
    } else {
      shown = ref.watch(pnlShownRangeProvider(engineVenue));
    }
    final window =
        ref.watch(pnlWindowProvider((range: shown, venue: engineVenue)));
    if (window != null && window.values.isNotEmpty) {
      final values = [...window.values];
      values[values.length - 1] = live;
      return PortfolioPnlPeriod(
        status: PortfolioPnlStatus.ready,
        venue: picked,
        range: shown,
        ranges: ranges,
        values: values,
        times: window.times,
        daily: window.daily,
        live: live,
        leftOut: ref.watch(pnlLeftOutProvider(engineVenue)),
      );
    }
  }
  // Nothing the engine can chart: the venues' own line, every range.
  final shown = range ?? openPnlRangeShown(rangePicked, kPortfolioPnlRanges);
  final series = pnlSeries(data, now ?? DateTime.now());
  final window = kuteTrendWindow(series, series.spanFor(shown));
  return PortfolioPnlPeriod(
    status: PortfolioPnlStatus.ready,
    venue: picked,
    range: shown,
    values: window.values,
    times: window.times,
    // On daily (or coarser) buckets a point at midnight closes the day
    // before; finer buckets say when in the day.
    daily: series.strideFor(series.spanFor(shown)) * series.cellMinutes >=
        1440,
    live: live,
  );
}

/// [change] as a percent of what was held at the range's start, taken as
/// [valueNowUsd] less the change (see the file header); null on a base
/// under [kPortfolioPnlPercentBaseUsd], a percent of
/// [kPortfolioPnlPercentCap] or more, or nothing to divide.
double? portfolioPnlPercent(double change, double? valueNowUsd) {
  if (valueNowUsd == null || !valueNowUsd.isFinite || !change.isFinite) {
    return null;
  }
  final base = valueNowUsd - change;
  if (!(base >= kPortfolioPnlPercentBaseUsd)) return null;
  final percent = change / base * 100;
  if (!percent.isFinite || percent.abs() >= kPortfolioPnlPercentCap) {
    return null;
  }
  return percent;
}

/// The P&L tab's headline and its two rows (see the file header), in US
/// dollars to the cent: [headline]
/// is [PortfolioPnlPeriod.change] rounded so, [open] what the positions
/// open now made over the range, [closed] the rest; [closed] + [open] is
/// [headline] as written.
typedef PortfolioPnlSplit = ({double headline, double closed, double open});

/// [period]'s split (see [PortfolioPnlSplit]); null while it is not ready
/// or while what the open positions stood at on the range's start is not
/// known yet (their history on its way, or unread).
PortfolioPnlSplit? portfolioPnlSplit(WidgetRef ref, PortfolioPnlPeriod period) {
  if (!period.ready) return null;
  final venues = ref.watch(portfolioVenuesProvider);
  final v = period.venue;
  final scope = v == null
      ? venues
      : PortfolioVenues(
          trading: venues.trading && v == PortfolioPerformanceVenue.trading,
          predictions: venues.predictions &&
              v == PortfolioPerformanceVenue.predictions);
  final openNow = portfolioOpenPnl(ref, scope);
  var openStart = 0.0;
  final start = period.start;
  if (openNow != null && period.range != BalanceRange.all && start != null) {
    final legs = ref.watch(openPnlHistoryProvider.select((read) =>
        read.hasValue ? read.requireValue.legs : null));
    if (legs == null) return null;
    bool mine(String key) => v == null
        ? true
        : v == PortfolioPerformanceVenue.predictions
            ? key.startsWith('pm:')
            : !key.startsWith('pm:');
    openStart =
        openPnlValueAt([for (final l in legs) if (mine(l.key)) l], start);
  }
  final open = (openNow?.usd ?? 0) - openStart;
  // Rounded in the dollars on screen, so the rows add up as written.
  int cents(double usd) => usd.isFinite ? (usd * 100).round() : 0;
  final headline = cents(period.change);
  final openCents = cents(open);
  final closedCents = headline - openCents;
  double back(int c) => c / 100;
  return (
    headline: back(headline),
    closed: back(closedCents),
    open: back(openCents),
  );
}
