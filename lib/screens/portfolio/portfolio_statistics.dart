import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart'
    show KuteDockClearance, kuteDockScrollClearance;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/helpers/hyperliquid_activity.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidAllMarketsProvider, hyperliquidSpotMarketsProvider;
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_activity_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_rewards_provider.dart'
    show earnPayoutPage, payoutHistoryProvider;
import 'package:kute/screens/portfolio/components/portfolio_pnl_chart.dart';
import 'package:kute/screens/portfolio/portfolio_category_donut.dart';
import 'package:kute/screens/portfolio/portfolio_category_drill.dart';
import 'package:kute/screens/portfolio/portfolio_empty_state.dart';
import 'package:kute/screens/polymarket/components/market_card.dart'
    show polyCardFigureStyle;
import 'package:kute/screens/shared/portfolio_position_card.dart'
    show portfolioCardCaptionStyle;
import 'package:kute/screens/shared/charts/kute_chart_format.dart'
    show kuteChangeSign;
import 'package:kute/screens/shared/charts/kute_chart_range_pills.dart'
    show KuteRangePill;
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/no_activity_state.dart';
import 'package:kute/screens/hyperliquid/components/hl_isolated_margin.dart'
    show hlCloseValue, hlPositionMargin;
import 'package:kute/services/portfolio/portfolio_categories.dart';
import 'package:kute/screens/usd/components/usd_balance_tabs.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The Statistics tab's two sub-tabs, as the analytics events name them:
/// what is open now, and what is done (all time).
enum StatisticsScope { active, historic }

/// One venue's Statistics, Predictions or Investing: a Ledger's
/// Statistics tab. The spending account's tab shows both venues as one
/// account ([PortfolioStatisticsOverview]), from the same parts.
///
///   * The profit and loss chart leads ([PortfolioPnlChart]): the
///     account's P&L (realised plus open) as the headline, the change over
///     the range drawn under it, the venue's P&L series as a line coloured
///     by that change with a dashed baseline at the range's start, a long
///     press scrubbing the header, and the 1D … ALL range pills. The same
///     chart on both sub-tabs. No observations yet, or a P&L that never
///     moved off zero: no chart, never a flat line. Nothing on either
///     sub-tab either: the whole tab is the app's empty state
///     ([NoActivityState]: Sal, the headline, a tagline), nothing else.
///   * Two small pills under it (the app's [KutePill] pair, as the
///     Breakdown tab's Sent | Received), Active first and picked.
///   * Active: what is open now. The donut splits the open positions'
///     value by category (Predictions: a live prediction's shares at the
///     live price; Investing: an open perp's margin plus its profit or
///     loss, the Open tab card's figure, and each spot holding at the
///     mid); the tiles are the open P&L, the amount at stake (Predictions:
///     what the open positions cost; Investing: the margin they use) and
///     the open positions. Nothing open: the empty state, compact, and no
///     card (never a card of zeros).
///   * Historic: the all-time donut (amount predicted, volume traded) and
///     the realised P&L, the amount predicted or volume traded and the
///     count. Nothing ever done: the same compact empty state.
///   * A slice picked opens up in the legend's place: what is in it
///     (events, coins), and under each its P&L lines
///     (portfolio_category_drill.dart).
///   * Switching sends `portfolio_tab_changed` with the sub-tab; a slice
///     pick carries the sub-tab as `scope`. The chart's range and scrub
///     events are portfolio_pnl_chart.dart's.
class PortfolioStatistics extends ConsumerStatefulWidget {
  const PortfolioStatistics({super.key, required this.venue, this.walletId});

  final PortfolioPerformanceVenue venue;
  final String? walletId;

  @override
  ConsumerState<PortfolioStatistics> createState() =>
      _PortfolioStatisticsState();
}

/// The sub-tab switch, as the analytics event names it.
void _trackScope(StatisticsScope next) {
  HapticFeedback.selectionClick();
  TrackingService.track('portfolio_tab_changed',
      params: {'tab': 'statistics', 'subtab': next.name});
}

class _PortfolioStatisticsState extends ConsumerState<PortfolioStatistics> {
  StatisticsScope _scope = StatisticsScope.active;

  void _pick(StatisticsScope next) {
    if (next == _scope) return;
    _trackScope(next);
    setState(() => _scope = next);
  }

  @override
  Widget build(BuildContext context) {
    final venue = widget.venue;
    final walletId = widget.walletId;
    final request =
        PortfolioPerformanceRequest(venue: venue, walletId: walletId);
    final performance = ref.watch(portfolioPerformanceProvider(request));
    // The tab runs under the dock (the Portfolio's KuteDockHost): the
    // centred states keep clear of it, the list keeps its last row
    // clear.
    Widget clear(Widget child) => KuteDockClearance(child: child);
    return performance.when(
      // The account and session providers this one reads re-emit while the
      // screen is open. Without these the whole tab dropped back to a
      // spinner on every one of those reloads (owner report: "keeps
      // reloading"); the last good figures stay up instead.
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () =>
          clear(const Center(child: CircularProgressIndicator.adaptive())),
      error: (e, __) => clear(_PerformanceError(
        failures: {venue: TrackingService.errorCategory(e)},
        onRetry: () {
          TrackingService.track('portfolio_performance_retry_tapped',
              params: {'venue': venue.name});
          ref.invalidate(portfolioPerformanceProvider(request));
        },
      )),
      data: (data) => _PerformanceBody(
          venue: venue,
          walletId: walletId,
          scope: _scope,
          onScope: _pick,
          data: request.venue == PortfolioPerformanceVenue.predictions
              ? _withLivePredictions(ref, data)
              : data),
    );
  }
}

/// The spending account's Statistics tab: Investing and Predictions as
/// one account, said once, from the top down.
///
///   * ONE profit and loss card leads ([PortfolioPnlChart]): one headline,
///     one line, one row of range pills. With both venues' P&L moving, a
///     small All · Investing · Predictions toggle at the top of the card
///     switches the series drawn in the same chart (All: the venues added
///     on the moments either published, [PortfolioPerformance.combine]),
///     and the headline and change with it. A venue whose P&L never moved
///     is not offered (it would draw a flat line); with one left the
///     toggle is gone. A P&L that never moved draws no line: Earn's chart
///     takes the lead when the backend allows it (it is the only figure
///     then), else no chart. Nothing on either sub-tab either: the whole
///     tab is the app's empty state ([NoActivityState]), nothing else.
///   * ONE allocation donut under it ([_AllocationCard]): what the account
///     holds now, Investing against Predictions, the total in the hole. A
///     slice or legend row opens that venue in the same ring (its
///     categories, the venue in the hole, a chevron pill back up); a
///     category then opens up as on a venue's own tab. One venue on the
///     account: the ring opens on it, with no way up. Nothing held: no
///     donut.
///   * ONE Active | Historic pair and ONE card of figures under it, for
///     what the donut shows: the account (each figure the venues' added;
///     Earn's paid-to-date one more tile), or the venue opened. A sub-tab
///     with nothing on it is the compact empty state, no card of zeros.
///   * A venue the account has not, or whose read failed, is left out.
///     Loading is one spinner until every venue has answered; every venue
///     failing is the retry state (one `portfolio_performance_error_shown`
///     per venue).
///   * Analytics: the toggle sends `portfolio_statistics_venue_toggled`
///     {venue}, the donut `portfolio_allocation_drilled` {venue, level:
///     venue | top}; the chart's range and scrub events carry the series
///     drawn as `venue` (`all`, `hyperliquid`, `polymarket`).
class PortfolioStatisticsOverview extends ConsumerStatefulWidget {
  const PortfolioStatisticsOverview({
    super.key,
    required this.trading,
    required this.predictions,
    this.earn = false,
  });

  /// The venues on the account (portfolio_filters.dart).
  final bool trading;
  final bool predictions;

  /// Earn allowed by the backend (`usd.earn`).
  final bool earn;

  @override
  ConsumerState<PortfolioStatisticsOverview> createState() =>
      _PortfolioStatisticsOverviewState();
}

/// A venue as the spending account's Statistics events name it; null is
/// the account as a whole.
String _eventVenue(PortfolioPerformanceVenue? venue) => switch (venue) {
      null => 'all',
      PortfolioPerformanceVenue.trading => 'hyperliquid',
      PortfolioPerformanceVenue.predictions => 'polymarket',
    };

class _PortfolioStatisticsOverviewState
    extends ConsumerState<PortfolioStatisticsOverview> {
  StatisticsScope _scope = StatisticsScope.active;

  /// The venue the allocation donut has open; null: the top level.
  PortfolioPerformanceVenue? _opened;

  /// The venue the chart draws; null: All.
  PortfolioPerformanceVenue? _charted;

  void _pick(StatisticsScope next) {
    if (next == _scope) return;
    _trackScope(next);
    setState(() => _scope = next);
  }

  void _chart(PortfolioPerformanceVenue? next) {
    if (next == _charted) return;
    HapticFeedback.selectionClick();
    TrackingService.track('portfolio_statistics_venue_toggled',
        params: {'venue': _eventVenue(next)});
    setState(() => _charted = next);
  }

  void _open(PortfolioPerformanceVenue? next) {
    final venue = next ?? _opened;
    if (next == _opened || venue == null) return;
    TrackingService.track('portfolio_allocation_drilled', params: {
      'venue': _eventVenue(venue),
      'level': next == null ? 'top' : 'venue',
    });
    setState(() => _opened = next);
  }

  @override
  Widget build(BuildContext context) {
    final venues = [
      if (widget.trading) PortfolioPerformanceVenue.trading,
      if (widget.predictions) PortfolioPerformanceVenue.predictions,
    ];
    final results = {
      for (final v in venues)
        v: ref.watch(
            portfolioPerformanceProvider(PortfolioPerformanceRequest(venue: v)))
    };
    // As the venue's own tab: a reload keeps the last figures up.
    if (results.values.any((r) => !r.hasValue && !r.hasError)) {
      return const KuteDockClearance(
          child: Center(child: CircularProgressIndicator.adaptive()));
    }
    final data = <PortfolioPerformanceVenue, PortfolioPerformance>{};
    final failures = <PortfolioPerformanceVenue, String>{};
    for (final MapEntry(key: venue, value: result) in results.entries) {
      if (result.hasError) {
        failures[venue] = TrackingService.errorCategory(result.error!);
      } else {
        data[venue] = venue == PortfolioPerformanceVenue.predictions
            ? _withLivePredictions(ref, result.requireValue)
            : result.requireValue;
      }
    }
    if (data.isEmpty) {
      return KuteDockClearance(
          child: _PerformanceError(
        failures: failures,
        onRetry: () {
          for (final venue in failures.keys) {
            TrackingService.track('portfolio_performance_retry_tapped',
                params: {'venue': venue.name});
            ref.invalidate(portfolioPerformanceProvider(
                PortfolioPerformanceRequest(venue: venue)));
          }
        },
      ));
    }
    return _OverviewBody(
      venues: [
        for (final v in venues)
          if (data.containsKey(v)) v
      ],
      data: data,
      scope: _scope,
      onScope: _pick,
      opened: _opened,
      onOpen: _open,
      charted: _charted,
      onChart: _chart,
      earn: widget.earn,
    );
  }
}

class _OverviewBody extends ConsumerWidget {
  const _OverviewBody({
    required this.venues,
    required this.data,
    required this.scope,
    required this.onScope,
    required this.opened,
    required this.onOpen,
    required this.charted,
    required this.onChart,
    required this.earn,
  });

  /// The venues read (a venue whose read failed is left out).
  final List<PortfolioPerformanceVenue> venues;
  final Map<PortfolioPerformanceVenue, PortfolioPerformance> data;
  final StatisticsScope scope;
  final ValueChanged<StatisticsScope> onScope;
  final PortfolioPerformanceVenue? opened;
  final ValueChanged<PortfolioPerformanceVenue?> onOpen;
  final PortfolioPerformanceVenue? charted;
  final ValueChanged<PortfolioPerformanceVenue?> onChart;
  final bool earn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final single = venues.length == 1 ? venues.single : null;
    // What the donut and the figures under it show: the venue open (the
    // only one, on a one-venue account), or the account.
    final selection = single ?? (venues.contains(opened) ? opened : null);
    final trading = venues.contains(PortfolioPerformanceVenue.trading)
        ? _tradingFigures(ref, null)
        : null;

    // The chart: the account's P&L, or one venue's under the toggle.
    final combined =
        PortfolioPerformance.combine([for (final v in venues) data[v]!]);
    final moving = [
      for (final v in venues)
        if (data[v]!.hasMovement) v
    ];
    final toggled = moving.length > 1 && moving.contains(charted);
    final series = toggled ? charted! : single;

    // The figures for the selection on a sub-tab: a venue's, or the
    // venues' added.
    _Figures? figuresOn(StatisticsScope on) => selection == null
        ? _Figures.sum([
            for (final v in venues)
              _venueFigures(
                  venue: v, data: data[v]!, scope: on, trading: trading)
          ])
        : _venueFigures(
            venue: selection,
            data: data[selection]!,
            scope: on,
            trading: trading);
    final figures = figuresOn(scope);

    // Never traded: no chart, no Earn, nothing on either sub-tab. The page
    // is one empty state (the chart's words), no pills over nothing.
    if (!combined.hasMovement &&
        !earn &&
        _Figures.quiet(figures) &&
        _Figures.quiet(figuresOn(_otherScope(scope)))) {
      return _PageEmpty(
          text: single == PortfolioPerformanceVenue.predictions
              ? l10n.betHistoryEmpty
              : l10n.hlNoHistoryYet);
    }

    final List<Widget> lead;
    if (combined.hasMovement) {
      lead = [
        PortfolioPnlChart(
          venue: series,
          eventVenue: _eventVenue(series),
          data: toggled ? data[charted]! : combined,
          selector: moving.length > 1
              ? _VenueToggle(
                  venues: moving,
                  selected: toggled ? charted : null,
                  onSelected: onChart)
              : null,
        ),
      ];
    } else if (earn) {
      // Nothing moved on the venues: Earn's chart is the only figure.
      lead = const [UsdBalanceTabs()];
    } else {
      // A P&L that never moved, with something below: no chart, and no
      // second empty state over the figures.
      lead = const [];
    }

    // Earn's paid-to-date: one more figure of the account's (its chart
    // leads instead when it is the only one). Earning counts as something
    // on either sub-tab.
    final earnTile =
        earn && combined.hasMovement && (selection == null || single != null)
            ? _earnTile(context, ref, visible)
            : null;
    final tiles = [
      if (!_Figures.quiet(figures))
        ..._tilesOf(context, ref, figures!, selection, scope),
      if (earnTile != null) earnTile,
    ];
    final List<Widget> stats;
    if (tiles.isNotEmpty) {
      stats = [
        Container(
          key: const ValueKey('statistics-figures'),
          clipBehavior: Clip.antiAlias,
          decoration: AppDecorations.card(context),
          child: _StatTiles(tiles: tiles),
        ),
      ];
    } else if (figures == null) {
      // Nothing to say.
      stats = const [];
    } else {
      // Nothing on the sub-tab: the empty state, never a card of zeros.
      stats = [_SubTabEmpty(text: _quietText(l10n, selection, scope))];
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
          16.w, 4.h, 16.w, 32.h + kuteDockScrollClearance(context)),
      children: [
        ...lead,
        _AllocationCard(
          venues: venues,
          data: data,
          trading: trading,
          level: selection,
          single: single != null,
          onOpen: onOpen,
        ),
        SizedBox(height: 12.h),
        _ScopePills(scope: scope, onScope: onScope),
        SizedBox(height: 12.h),
        ...stats,
      ],
    );
  }
}

/// All · Investing · Predictions at the top of the P&L card: the range
/// row's pills (the card's own selector style), at their natural width.
class _VenueToggle extends StatelessWidget {
  const _VenueToggle({
    required this.venues,
    required this.selected,
    required this.onSelected,
  });

  /// The venues offered after All.
  final List<PortfolioPerformanceVenue> venues;

  /// The venue drawn; null: All.
  final PortfolioPerformanceVenue? selected;
  final ValueChanged<PortfolioPerformanceVenue?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget pill(PortfolioPerformanceVenue? venue, String label) =>
        KuteRangePill(
          key: ValueKey('statistics-venue-${_eventVenue(venue)}'),
          label: label,
          selected: venue == selected,
          onTap: () => onSelected(venue),
        );
    return Align(
      alignment: Alignment.centerLeft,
      // Under very large text the row scales down rather than overflow.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            pill(null, l10n.searchFilterAll),
            for (final v in venues) pill(v, _venueName(l10n, v)),
          ],
        ),
      ),
    );
  }
}

/// A venue's name as the app writes it.
String _venueName(AppLocalizations l10n, PortfolioPerformanceVenue venue) =>
    venue == PortfolioPerformanceVenue.predictions
        ? l10n.predictions
        : l10n.trading;

/// The spending account's one donut: what it holds now. The top level
/// splits it by venue (an Investing holding at what closing it gives back
/// or at the mid, a live prediction at the live price), the total in the
/// hole, each venue in the legend (one holding nothing at 0%, so it can
/// still be opened); a slice or row opens the venue in the same ring
/// ([level]): its categories, its name and value in the hole, a chevron
/// pill back up, a category opening up to what is in it. A venue not read
/// yet is left out until it lands. Nothing held: no card (a venue opened
/// from above keeps its empty ring and its way back).
class _AllocationCard extends ConsumerWidget {
  const _AllocationCard({
    required this.venues,
    required this.data,
    required this.trading,
    required this.level,
    required this.single,
    required this.onOpen,
  });

  final List<PortfolioPerformanceVenue> venues;
  final Map<PortfolioPerformanceVenue, PortfolioPerformance> data;
  final _TradingParts? trading;

  /// The venue open; null: the top level.
  final PortfolioPerformanceVenue? level;

  /// The account's only venue: open from the start, no way up.
  final bool single;
  final ValueChanged<PortfolioPerformanceVenue?> onOpen;

  /// One card for every level, so the ring morphs between them.
  static const _key = ValueKey('statistics-allocation');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final livePrices = ref.watch(livePriceProvider.select((s) => s.prices));

    final positions = trading?.positions;
    final spot = trading?.spot;
    final (holdings, byWire) = positions != null && spot != null
        ? _tradingHoldings(ref, positions, spot)
        : (null, const <String, HlMarket>{});
    final book = data[PortfolioPerformanceVenue.predictions]?.predictions;
    final live = book == null ? null : livePredictionRecords(book);
    const request = PortfolioPerformanceRequest(
        venue: PortfolioPerformanceVenue.predictions);
    // Read while the top level shows, so opening Predictions is instant.
    final categories = live == null
        ? null
        : ref.watch(predictionOpenCategoriesProvider(request));

    Map<String, double>? tradingValues() => holdings == null
        ? null
        : tradingOpenCategoryValues(
            [for (final h in holdings) (h.coin, h.market, h.value)]);
    double? valueOf(PortfolioPerformanceVenue venue) {
      final values = switch (venue) {
        PortfolioPerformanceVenue.trading => tradingValues(),
        PortfolioPerformanceVenue.predictions => live == null
            ? null
            : predictionOpenCategoryValues(live, const {}, livePrices),
      };
      return values?.values.fold<double>(0, (sum, v) => sum + v);
    }

    final open = level;
    if (open == null) {
      final known = {
        for (final v in venues)
          if (valueOf(v) case final value?) v: value
      };
      final values = {
        for (final MapEntry(key: v, value: value) in known.entries)
          if (value > 0) v.name: value
      };
      if (values.isEmpty) return const SizedBox.shrink();
      return PortfolioCategoryCard(
        key: _key,
        level: 'top',
        values: values,
        // The venues' names, not a venue's categories.
        venue: CategoryVenue.trading,
        labelOf: (key) =>
            _venueName(l10n, PortfolioPerformanceVenue.values.byName(key)),
        listed: [for (final v in known.keys) v.name],
        centreLabel: l10n.total,
        onOpen: (key) => onOpen(PortfolioPerformanceVenue.values.byName(key)),
      );
    }

    final back = single ? null : () => onOpen(null);
    final scope = StatisticsScope.active.name;
    if (open == PortfolioPerformanceVenue.trading) {
      final values = tradingValues() ?? const <String, double>{};
      if (single && values.isEmpty) return const SizedBox.shrink();
      return PortfolioCategoryCard(
        key: _key,
        level: open,
        values: values,
        venue: CategoryVenue.trading,
        scope: scope,
        centreLabel: l10n.trading,
        onBack: back,
        drill: holdings == null
            ? null
            : (context, slice, inSlice) => TradingCategoryDrill.active(
                  holdings: holdings,
                  inSlice: (coin, market) =>
                      inSlice(hlFillCategory(coin, market)),
                  marketsByWire: byWire,
                  params: categoryDrillParams(slice,
                      venue: CategoryVenue.trading,
                      walletKind: 'hot',
                      scope: scope),
                ),
      );
    }

    final records = live ?? const <PredictionRecord>[];
    // Their markets' categories still being read: the placeholder.
    if (records.isNotEmpty &&
        categories != null &&
        !categories.hasValue &&
        !categories.hasError) {
      return const PortfolioCategorySkeleton();
    }
    // A read that failed files every prediction under Other.
    final byMarket = categories?.valueOrNull;
    final values =
        predictionOpenCategoryValues(records, byMarket ?? const {}, livePrices);
    if (single && values.isEmpty) return const SizedBox.shrink();
    return PortfolioCategoryCard(
      key: _key,
      level: open,
      values: values,
      venue: CategoryVenue.predictions,
      scope: scope,
      centreLabel: l10n.predictions,
      onBack: back,
      drill: byMarket == null
          ? null
          : (context, slice, inSlice) => PredictionCategoryDrill(
                records: records,
                categories: byMarket,
                inSlice: inSlice,
                active: true,
                params: categoryDrillParams(slice,
                    venue: CategoryVenue.predictions,
                    walletKind: 'hot',
                    scope: scope),
              ),
    );
  }
}

/// A sub-tab's figures for a venue, or the venues added: the P&L (open on
/// Active, realised on Historic), the amount (at stake; predicted or
/// traded) and the count (open positions; predictions or trades). Null
/// parts are not known (a dash, never a zero). [empty]: nothing on the
/// sub-tab.
class _Figures {
  const _Figures({required this.empty, this.pnl, this.amount, this.count});

  final bool empty;
  final double? pnl;
  final double? amount;
  final int? count;

  /// Nothing to show on the sub-tab: no figures, nothing on it, or every
  /// figure a zero (a card of zeros says nothing).
  static bool quiet(_Figures? f) =>
      f == null ||
      f.empty ||
      (f.count == 0 && (f.pnl ?? 0) == 0 && (f.amount ?? 0) == 0);

  /// The venues' figures added (a venue with nothing on the sub-tab adds
  /// nothing; a part one venue does not know is not known). Null when no
  /// venue has figures.
  static _Figures? sum(List<_Figures?> parts) {
    final known = parts.whereType<_Figures>().toList();
    if (known.isEmpty) return null;
    final filled = known.where((f) => !f.empty).toList();
    if (filled.isEmpty) return const _Figures(empty: true);
    double? add(double? Function(_Figures) part) {
      var total = 0.0;
      for (final f in filled) {
        final v = part(f);
        if (v == null) return null;
        total += v;
      }
      return total;
    }

    int? count() {
      var total = 0;
      for (final f in filled) {
        final v = f.count;
        if (v == null) return null;
        total += v;
      }
      return total;
    }

    return _Figures(
        empty: false,
        pnl: add((f) => f.pnl),
        amount: add((f) => f.amount),
        count: count());
  }
}

/// The Investing account's parts ([_tradingFigures]).
typedef _TradingParts = ({
  TradingBook? book,
  List<HlPerpPosition>? positions,
  List<HlSpotBalance>? spot,
  double? openPnlUsd,
});

/// [venue]'s figures on [scope]; null when it has none to show (no
/// predictions book, the Investing parts not given).
_Figures? _venueFigures({
  required PortfolioPerformanceVenue venue,
  required PortfolioPerformance data,
  required StatisticsScope scope,
  required _TradingParts? trading,
}) {
  final active = scope == StatisticsScope.active;
  if (venue == PortfolioPerformanceVenue.predictions) {
    final book = data.predictions;
    if (book == null) return null;
    if (active) {
      final live = livePredictionRecords(book);
      return _Figures(
          empty: live.isEmpty,
          pnl: data.openPnlUsd,
          amount: live.fold<double>(0, (sum, r) => sum + r.entryCostUsd),
          count: live.length);
    }
    final stats = book.statsSince(null);
    return _Figures(
        empty: stats != null &&
            stats.count == 0 &&
            (data.realizedPnlUsd ?? 0) == 0,
        pnl: data.realizedPnlUsd,
        amount: stats?.stakedUsd,
        count: stats?.count);
  }
  if (trading == null) return null;
  if (active) {
    final positions = trading.positions;
    final spot = trading.spot;
    final known = positions != null && spot != null;
    return _Figures(
        empty: known && positions.isEmpty && spot.isEmpty,
        pnl: trading.openPnlUsd,
        amount:
            positions?.fold<double>(0, (sum, p) => sum + hlPositionMargin(p)),
        count: known ? positions.length + spot.length : null);
  }
  // What closing realised (net of fees), the notional traded and the
  // fills. A figure the fills do not reach back to, or one not read yet,
  // is a dash, never a zero.
  final stats = trading.book?.statsSince(null);
  return _Figures(
      empty: stats != null && stats.count == 0,
      pnl: stats?.realizedUsd,
      amount: stats?.volumeUsd,
      count: stats?.count);
}

/// The tiles of [figures] for [venue] (null: the account) on [scope].
List<(String, String, Color)> _tilesOf(BuildContext context, WidgetRef ref,
    _Figures figures, PortfolioPerformanceVenue? venue, StatisticsScope scope) {
  final c = context.colors;
  final l10n = context.l10n;
  final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
  final predictions = venue == PortfolioPerformanceVenue.predictions;
  final money = !visible
      ? '••••••'
      : figures.amount == null
          ? '—'
          : formatPolyAmount(ref, figures.amount!);
  final count = figures.count == null
      ? '—'
      : NumberFormat.decimalPattern().format(figures.count);
  return scope == StatisticsScope.active
      ? [
          _pnlTile(
              context, ref, visible, l10n.portfolioStatOpenPnl, figures.pnl),
          (l10n.portfolioStatAtStake, money, c.textPrimary),
          (l10n.accountOpenPositions, count, c.textPrimary),
        ]
      : [
          _pnlTile(
              context, ref, visible, l10n.portfolioStatRealized, figures.pnl),
          (
            predictions
                ? l10n.portfolioStatAmountPredicted
                : l10n.portfolioStatVolume,
            money,
            c.textPrimary
          ),
          (
            predictions ? l10n.portfolioStatCount : l10n.portfolioStatTrades,
            count,
            c.textPrimary
          ),
        ];
}

/// The empty state's headline on a sub-tab with nothing on it, for [venue] (null:
/// the account).
String _quietText(AppLocalizations l10n, PortfolioPerformanceVenue? venue,
    StatisticsScope scope) {
  final predictions = venue == PortfolioPerformanceVenue.predictions;
  return scope == StatisticsScope.active
      ? (predictions
          ? l10n.openInvestNoOpenPredictions
          : l10n.openInvestNoOpenInvestments)
      : (predictions ? l10n.betHistoryEmpty : l10n.hlNoHistoryYet);
}

/// Earn's paid-to-date as a figure: every payout received, in the
/// unit the wallet reads in. Nothing when nothing was paid, the ledger is
/// not read yet, or the page does not hold every payout (it would not be
/// the whole figure).
(String, String, Color)? _earnTile(
    BuildContext context, WidgetRef ref, bool visible) {
  final history = ref.watch(payoutHistoryProvider(earnPayoutPage)).valueOrNull;
  if (history == null || history.hasMore) return null;
  final sats = history.totalPayoutSats;
  if (sats <= 0) return null;
  final label = context.l10n.usdEarnTitle;
  if (!visible) return (label, '••••••', context.colors.textPrimary);
  final btcFormat = ref.watch(settingsProvider.select((s) => s.btcFormat));
  return (
    label,
    '+${sats.toFormattedString(btcFormat)} '
        '${btcFormat == 'sats' ? 'sats' : 'BTC'}',
    AppColors.marketUp,
  );
}

/// A P&L tile: signed and in the up / down colour, as the chart's
/// headline; unknown is a dash, hidden balances the dots.
(String, String, Color) _pnlTile(BuildContext context, WidgetRef ref,
    bool visible, String label, double? value) {
  final c = context.colors;
  if (!visible) return (label, '••••••', c.textPrimary);
  if (value == null) return (label, '—', c.textPrimary);
  return (
    label,
    '${kuteChangeSign(value)}${formatPolyAmount(ref, value.abs())}',
    value > 0
        ? AppColors.marketUp
        : value < 0
            ? AppColors.marketDown
            : c.textPrimary,
  );
}

/// The sub-tab not picked.
StatisticsScope _otherScope(StatisticsScope scope) =>
    scope == StatisticsScope.active
        ? StatisticsScope.historic
        : StatisticsScope.active;

/// The "performance unavailable" state. Its event fires once per mount
/// and venue, not per rebuild of the provider's error.
class _PerformanceError extends StatefulWidget {
  const _PerformanceError({
    required this.failures,
    required this.onRetry,
  });

  /// Each venue whose read failed, with its error category.
  final Map<PortfolioPerformanceVenue, String> failures;
  final VoidCallback onRetry;

  @override
  State<_PerformanceError> createState() => _PerformanceErrorState();
}

class _PerformanceErrorState extends State<_PerformanceError> {
  @override
  void initState() {
    super.initState();
    for (final MapEntry(key: venue, value: category)
        in widget.failures.entries) {
      TrackingService.track('portfolio_performance_error_shown', params: {
        'venue': venue.name,
        'error_category': category,
      });
    }
  }

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(context.l10n.portfolioPerformanceUnavailable,
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 16.sp)),
            SizedBox(height: 16.h),
            AppButton(
              text: context.l10n.retry,
              compact: true,
              variant: AppButtonVariant.secondary,
              onPressed: widget.onRetry,
            ),
          ]),
        ),
      );
}

/// Active | Historic: two small pills at their natural width, as the
/// Breakdown tab's Sent | Received; under very large text they share the
/// row rather than overflow it.
class _ScopePills extends StatelessWidget {
  const _ScopePills({required this.scope, required this.onScope});
  final StatisticsScope scope;
  final ValueChanged<StatisticsScope> onScope;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Flexible(
          child: KutePill(
            key: const ValueKey('statistics-active'),
            label: l10n.portfolioStatsActive,
            selected: scope == StatisticsScope.active,
            onTap: () => onScope(StatisticsScope.active),
          ),
        ),
        SizedBox(width: 6.w),
        Flexible(
          child: KutePill(
            key: const ValueKey('statistics-historic'),
            label: l10n.portfolioStatsHistoric,
            selected: scope == StatisticsScope.historic,
            onTap: () => onScope(StatisticsScope.historic),
          ),
        ),
      ],
    );
  }
}

class _PerformanceBody extends ConsumerWidget {
  const _PerformanceBody({
    required this.venue,
    required this.data,
    required this.scope,
    required this.onScope,
    this.walletId,
  });
  final PortfolioPerformanceVenue venue;
  final PortfolioPerformance data;
  final StatisticsScope scope;
  final ValueChanged<StatisticsScope> onScope;

  /// Null for the spending account; a Ledger wallet's ID otherwise.
  final String? walletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final predictions = venue == PortfolioPerformanceVenue.predictions;
    final trading = predictions ? null : _tradingFigures(ref, walletId);
    bool quietOn(StatisticsScope on) => _Figures.quiet(_venueFigures(
        venue: venue, data: data, scope: on, trading: trading));

    // The chart leads, whatever sub-tab is picked: the account's P&L
    // over time, realised and open together. Nothing published yet, or a
    // P&L that never moved off zero: no chart (never a flat line at
    // zero). With nothing on either sub-tab either, the page is one empty
    // state, no pills over nothing.
    if (!data.hasMovement && quietOn(scope) && quietOn(_otherScope(scope))) {
      return _PageEmpty(
          text: predictions ? l10n.betHistoryEmpty : l10n.hlNoHistoryYet);
    }
    final content = _scopeContent(context, ref,
        venue: venue, data: data, scope: scope, walletId: walletId);
    final lead = [
      if (data.hasMovement) PortfolioPnlChart(venue: venue, data: data)
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(
          16.w, 4.h, 16.w, 32.h + kuteDockScrollClearance(context)),
      children: [
        if (lead.isNotEmpty) ...[...lead, SizedBox(height: 12.h)],
        _ScopePills(scope: scope, onScope: onScope),
        SizedBox(height: 12.h),
        ...content,
      ],
    );
  }
}

/// One venue's sub-tab on a Ledger: its card (the category donut, then
/// the figures under it), or its empty state.
List<Widget> _scopeContent(
  BuildContext context,
  WidgetRef ref, {
  required PortfolioPerformanceVenue venue,
  required PortfolioPerformance data,
  required StatisticsScope scope,
  String? walletId,
}) {
  final l10n = context.l10n;
  final predictions = venue == PortfolioPerformanceVenue.predictions;
  final request = PortfolioPerformanceRequest(venue: venue, walletId: walletId);
  final walletKind = walletId == null ? 'hot' : 'ledger';
  final book = predictions ? data.predictions : null;
  // The Investing figures come from what is already on the device: the
  // account's fills and its open positions (the venue's P&L series
  // carries no realised / open split).
  final trading = predictions ? null : _tradingFigures(ref, walletId);
  final figures =
      _venueFigures(venue: venue, data: data, scope: scope, trading: trading);
  if (figures == null) return const [];
  if (_Figures.quiet(figures)) {
    return [_SubTabEmpty(text: _quietText(l10n, venue, scope))];
  }
  final tiles =
      _StatTiles(tiles: _tilesOf(context, ref, figures, venue, scope));

  // One card on the lists' 16 gutter, the position cards' surface: the
  // kinds of markets the money is (or went) to, then the figures under
  // it. Without categories (history cut, read failed, nothing in them)
  // the card starts with the figures.
  Widget card(List<Widget> children) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: AppDecorations.card(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );

  if (scope == StatisticsScope.active) {
    if (book != null) {
      return [
        card([
          _PredictionOpenCategories(
              request: request,
              records: livePredictionRecords(book),
              walletKind: walletKind,
              centreLabel: l10n.portfolioStatsActive),
          tiles,
        ]),
      ];
    }
    final positions = trading?.positions;
    final spot = trading?.spot;
    return [
      card([
        if (positions != null && spot != null)
          _TradingOpenCategories(
              positions: positions,
              spot: spot,
              walletKind: walletKind,
              walletId: walletId,
              centreLabel: l10n.portfolioStatsActive),
        tiles,
      ]),
    ];
  }

  if (book != null) {
    return [
      card([
        _PredictionCategories(request: request, book: book),
        tiles,
      ]),
    ];
  }
  return [
    card([
      if (trading?.book case final tradingBook?)
        _TradingCategories(
            book: tradingBook, walletKind: walletKind, walletId: walletId),
      tiles,
    ]),
  ];
}

/// Nothing ever done on the account: the whole tab is the app's empty
/// state, as every other empty Portfolio tab ([PortfolioEmptyState]).
class _PageEmpty extends StatelessWidget {
  const _PageEmpty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => PortfolioEmptyState(text,
      key: const ValueKey('statistics-chart-empty'));
}

/// Nothing on a sub-tab: the same empty state, compact, under the pills.
/// No card around it.
class _SubTabEmpty extends StatelessWidget {
  const _SubTabEmpty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => NoActivityState(
      key: const ValueKey('statistics-empty'),
      title: text,
      compact: true,
      cycles: 3);
}

/// The Active Predictions donut: what the live predictions are worth now
/// per category. A placeholder while their markets' categories are read;
/// nothing when that read failed.
class _PredictionOpenCategories extends ConsumerWidget {
  const _PredictionOpenCategories(
      {required this.request,
      required this.records,
      required this.walletKind,
      required this.centreLabel});
  final PortfolioPerformanceRequest request;
  final List<PredictionRecord> records;
  final String walletKind;

  /// The donut's hole: "Active", or the venue's name.
  final String centreLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(predictionOpenCategoriesProvider(request));
    final live = ref.watch(livePriceProvider.select((s) => s.prices));
    return categories.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () => const PortfolioCategorySkeleton(embedded: true),
      error: (_, __) => const SizedBox.shrink(),
      data: (byMarket) => byMarket == null
          ? const SizedBox.shrink()
          : PortfolioCategoryCard(
              key: const ValueKey('category-donut-active'),
              values: predictionOpenCategoryValues(records, byMarket, live),
              venue: CategoryVenue.predictions,
              walletKind: walletKind,
              embedded: true,
              scope: StatisticsScope.active.name,
              centreLabel: centreLabel,
              drill: (context, slice, inSlice) => PredictionCategoryDrill(
                    records: records,
                    categories: byMarket,
                    inSlice: inSlice,
                    active: true,
                    walletId: request.walletId,
                    params: categoryDrillParams(slice,
                        venue: CategoryVenue.predictions,
                        walletKind: walletKind,
                        scope: StatisticsScope.active.name),
                  )),
    );
  }
}

/// The Active Investing donut: each open perp at what closing it gives
/// back (its margin plus its profit or loss, the Open tab card's figure,
/// at the account's last read) and each spot holding at the mid, per
/// category.
class _TradingOpenCategories extends ConsumerWidget {
  const _TradingOpenCategories(
      {required this.positions,
      required this.spot,
      required this.walletKind,
      required this.centreLabel,
      this.walletId});
  final List<HlPerpPosition> positions;
  final List<HlSpotBalance> spot;
  final String walletKind;
  final String? walletId;

  /// The donut's hole: "Active", or the venue's name.
  final String centreLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (holdings, byWire) = _tradingHoldings(ref, positions, spot);
    final values = tradingOpenCategoryValues(
        [for (final h in holdings) (h.coin, h.market, h.value)]);
    return PortfolioCategoryCard(
        key: const ValueKey('category-donut-active'),
        values: values,
        venue: CategoryVenue.trading,
        walletKind: walletKind,
        embedded: true,
        scope: StatisticsScope.active.name,
        centreLabel: centreLabel,
        drill: (context, slice, inSlice) => TradingCategoryDrill.active(
              holdings: holdings,
              inSlice: (coin, market) => inSlice(hlFillCategory(coin, market)),
              marketsByWire: byWire,
              walletId: walletId,
              params: categoryDrillParams(slice,
                  venue: CategoryVenue.trading,
                  walletKind: walletKind,
                  scope: StatisticsScope.active.name),
            ));
  }
}

/// Each open perp at what closing it gives back (its margin plus its
/// profit or loss, the Open tab card's figure) and each spot holding at
/// the mid (one whose market or price is not known yet is left out), with
/// the markets by wire coin.
(List<TradingHolding>, Map<String, HlMarket>) _tradingHoldings(
    WidgetRef ref, List<HlPerpPosition> positions, List<HlSpotBalance> spot) {
  final markets = ref.watch(hyperliquidAllMarketsProvider);
  final byWire = {for (final m in markets) m.wireCoin: m};
  final spotMarkets = ref.watch(hyperliquidSpotMarketsProvider).valueOrNull ??
      const <HlMarket>[];
  return (
    [
      for (final p in positions)
        TradingHolding(
            coin: p.coin,
            market: byWire[p.coin],
            value: hlCloseValue(p),
            position: p),
      for (final balance in spot)
        if (spotMarkets.where((m) => m.coin == balance.coin).firstOrNull
            case final market? when market.midPx > 0)
          TradingHolding(
              coin: market.wireCoin,
              market: market,
              value: balance.total * market.midPx,
              spot: balance),
    ],
    byWire,
  );
}

/// The Historic Predictions donut: the amount predicted per category, all
/// time. A placeholder while the markets' categories are read; nothing
/// when the history was cut, the read failed or nothing was predicted.
class _PredictionCategories extends ConsumerWidget {
  const _PredictionCategories({required this.request, required this.book});
  final PortfolioPerformanceRequest request;
  final PredictionsBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stakes = ref.watch(predictionCategoryStakesProvider(request));
    // The same categories the stakes were split by, for the drill-down.
    final categories =
        ref.watch(predictionCategoriesProvider(request)).valueOrNull;
    final walletKind = request.walletId == null ? 'hot' : 'ledger';
    return stakes.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () => const PortfolioCategorySkeleton(embedded: true),
      error: (_, __) => const SizedBox.shrink(),
      data: (values) => values == null
          ? const SizedBox.shrink()
          : PortfolioCategoryCard(
              key: const ValueKey('category-donut-historic'),
              values: values,
              venue: CategoryVenue.predictions,
              walletKind: walletKind,
              embedded: true,
              scope: StatisticsScope.historic.name,
              drill: categories == null
                  ? null
                  : (context, slice, inSlice) => PredictionCategoryDrill(
                        records: book.records,
                        categories: categories,
                        inSlice: inSlice,
                        active: false,
                        walletId: request.walletId,
                        params: categoryDrillParams(slice,
                            venue: CategoryVenue.predictions,
                            walletKind: walletKind,
                            scope: StatisticsScope.historic.name),
                      )),
    );
  }
}

/// The Historic Investing donut: the volume traded per category, all
/// time, from the fills the tiles read. Nothing when the fills were cut.
class _TradingCategories extends ConsumerWidget {
  const _TradingCategories(
      {required this.book, required this.walletKind, this.walletId});
  final TradingBook book;
  final String walletKind;
  final String? walletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final markets = ref.watch(hyperliquidAllMarketsProvider);
    final byWire = {for (final m in markets) m.wireCoin: m};
    final volumes = tradingCategoryVolumes(book, byWire);
    if (volumes == null) return const SizedBox.shrink();
    return PortfolioCategoryCard(
        key: const ValueKey('category-donut-historic'),
        values: volumes,
        venue: CategoryVenue.trading,
        walletKind: walletKind,
        embedded: true,
        scope: StatisticsScope.historic.name,
        drill: (context, slice, inSlice) => TradingCategoryDrill.historic(
              fills: book.fills,
              inSlice: (coin, market) => inSlice(hlFillCategory(coin, market)),
              marketsByWire: byWire,
              walletId: walletId,
              params: categoryDrillParams(slice,
                  venue: CategoryVenue.trading,
                  walletKind: walletKind,
                  scope: StatisticsScope.historic.name),
            ));
  }
}

/// The Investing account's fills, its open positions and spot holdings
/// (USDC aside, as the Open tab lists them) and what the positions stand
/// at, from the providers the Open and Activity tabs already read. Null
/// parts are not known yet (still loading, or a read that failed), never
/// zero.
_TradingParts _tradingFigures(WidgetRef ref, String? walletId) {
  TradingBook? book;
  List<HlPerpPosition>? positions;
  List<HlSpotBalance>? balances;
  if (walletId == null) {
    // The REST history says whether the list was cut; the merged list
    // adds the executions the socket has seen since.
    final history = ref.watch(hyperliquidUserFillsProvider).valueOrNull;
    if (history != null) {
      book = TradingBook(
          fills: ref.watch(hyperliquidActivityFillsProvider),
          complete: history.length < kHyperliquidUserFillsCap);
    }
    final snapshot = ref.watch(hyperliquidAccountProvider).valueOrNull;
    positions = snapshot?.positions;
    balances = snapshot?.spotBalances;
  } else {
    final fills = ref.watch(ledgerHlFillsProvider(walletId)).valueOrNull;
    if (fills != null) {
      book =
          TradingBook(fills: fills, complete: fills.length < kLedgerHlMaxFills);
    }
    final account = ref.watch(ledgerHlAccountProvider(walletId)).valueOrNull;
    if (account?.account != null) {
      positions = [
        ...account!.account!.positions,
        for (final dex in account.dexAccounts.values) ...dex.positions,
      ];
      balances = account.account!.spotBalances;
    }
  }
  return (
    book: book,
    positions: positions,
    spot: balances
        ?.where((b) => b.coin != 'USDC' && b.total > 0)
        .toList(growable: false),
    openPnlUsd: positions?.fold<double>(0, (sum, p) => sum + p.unrealizedPnl),
  );
}

/// Figures on a card, two to a row: each a caption label over its
/// figure, as on the position cards.
class _StatTiles extends StatelessWidget {
  const _StatTiles({required this.tiles});

  /// Label, figure and the figure's colour.
  final List<(String, String, Color)> tiles;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: LayoutBuilder(builder: (context, constraints) {
        final gap = 12.w;
        final width = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: 16.h,
          children: [
            for (final (label, figure, color) in tiles)
              SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: portfolioCardCaptionStyle(c)),
                    SizedBox(height: 4.h),
                    Text(figure, style: polyCardFigureStyle(color)),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// The current Predictions figures, rebuilt from the account's positions
/// with their live prices (see [PortfolioPerformance.withLivePredictions]).
PortfolioPerformance _withLivePredictions(
    WidgetRef ref, PortfolioPerformance data) {
  final live = ref.watch(livePriceProvider.select((s) => s.prices));
  return data.withLivePredictions(live);
}
