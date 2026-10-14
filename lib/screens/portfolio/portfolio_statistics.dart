import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart'
    show KuteDockClearance, kuteDockScrollClearance;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
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
import 'package:kute/screens/portfolio/components/portfolio_pnl_chart.dart';
import 'package:kute/screens/portfolio/portfolio_category_donut.dart';
import 'package:kute/screens/portfolio/portfolio_category_drill.dart';
import 'package:kute/screens/portfolio/portfolio_empty_state.dart';
import 'package:kute/screens/portfolio/portfolio_figure_tiles.dart';
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
///     account's P&L (realised plus open) as the headline, the venue's
///     whole P&L history as a line coloured by its change with a dashed
///     baseline at zero, a pinch zooming the time window, a long press
///     scrubbing the header; no range row. The same chart on both
///     sub-tabs. No observations yet, or a P&L that never
///     moved off zero: no chart, never a flat line. Nothing on either
///     sub-tab either: the whole tab is the app's empty state
///     ([NoActivityState]: Sal, the headline, a tagline), nothing else.
///   * Two small pills under it (the app's [KutePill] pair, as the
///     Breakdown tab's Sent | Received), Active first and picked.
///   * Active: what is open now. The donut splits the open positions'
///     value by category (Predictions: a live prediction's shares at the
///     live price; Investing: an open perp's margin plus its profit or
///     loss, the Open tab card's figure, and each spot holding at the
///     mid); the tiles, in one row, are the open P&L, the amount at stake
///     (Predictions: what the open positions cost; Investing: the margin
///     they use) and the open positions. Nothing open: the empty state, compact, and no
///     card (never a card of zeros).
///   * Historic: the all-time donut (amount predicted, volume traded) and
///     the realised P&L, the amount predicted or volume traded and the
///     count. Nothing ever done: the same compact empty state.
///   * A slice picked opens up in the legend's place: what is in it
///     (events, coins), and under each its P&L lines
///     (portfolio_category_drill.dart).
///   * Switching sends `portfolio_tab_changed` with the sub-tab; a slice
///     pick carries the sub-tab as `scope`. The chart's scrub event is
///     portfolio_pnl_chart.dart's.
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

/// The Portfolio screen (open_investments_screen.dart, opened from the
/// Investments balance): Investing and Predictions as one account, said
/// once, from the top down.
///
///   * ONE profit and loss card leads ([PortfolioPnlChart]): one headline,
///     one line over the whole history, pinch to zoom. With both venues'
///     P&L moving, a
///     small All · Investing · Predictions toggle at the top of the card
///     switches the series drawn in the same chart (All: the venues added
///     on the moments either published, [PortfolioPerformance.combine]),
///     and the headline and change with it. A venue whose P&L never moved
///     is not offered (it would draw a flat line); with one left the
///     toggle is gone. A P&L that never moved draws no line, never a
///     flat one. Earn (the dollar rewards programme) is never shown here,
///     whatever the backend's `usd.earn` says (owner decision).
///   * ONE Active | Historic pair under it, and under the pair ONE
///     allocation donut ([_AllocationCard]) by CATEGORY with both venues
///     merged into one set ([CategoryVenue.all]: crypto at either venue is
///     one Crypto slice, Politics and Sports beside Stocks and
///     Commodities). Active: what the account holds now (an Investing
///     holding at what closing it gives back or at the mid, a live
///     prediction at the live price). Historic: everything it ever traded
///     or predicted (the volume traded, the amount predicted), all time.
///     A slice opens up to what is in it at both venues: the positions
///     (Active) or the history rows (Historic). Nothing in it: no donut.
///   * ONE row of figures for the pair, each the venues' added, as small
///     equal tiles side by side (portfolio_figure_tiles.dart, the balance
///     breakdown's tiles): Active the open P&L, the amount at stake and
///     the open positions; Historic the realised P&L, the volume traded
///     and the trades. A sub-tab with nothing on it is the compact empty
///     state, no tiles of zeros.
///   * [footer]: slivers under everything (the screen's Activity).
///   * Never traded (no chart, nothing on either sub-tab): the page is the
///     app's one empty state ([NoActivityState]), or only the [footer]
///     when it has rows ([footerEmpty] false).
///   * A venue the account has not, or whose read failed, is left out.
///     Loading is one spinner until every venue has answered; every venue
///     failing is the retry state (one `portfolio_performance_error_shown`
///     per venue).
///   * Analytics: the chart toggle sends `portfolio_statistics_venue_toggled`
///     {venue}; the pair `portfolio_allocation_view_changed` {view: active
///     | historic}; a slice opened, or closed again,
///     `portfolio_allocation_drilled` {venue: all, level: category | top,
///     category, view}; the chart's scrub event carries the series drawn
///     as `venue` (`all`, `hyperliquid`, `polymarket`).
class PortfolioStatisticsOverview extends ConsumerStatefulWidget {
  const PortfolioStatisticsOverview({
    super.key,
    required this.trading,
    required this.predictions,
    this.footer = const [],
    this.footerEmpty = true,
    this.header,
  });

  /// The venues on the account (portfolio_filters.dart).
  final bool trading;
  final bool predictions;

  /// Over the chart, on the lists' gutter, whatever the figures say (the
  /// Portfolio screen's balance breakdown). A never-traded account shows
  /// it over the one empty state, which fills the rest of the page.
  final Widget? header;

  /// Slivers under the figures (the Portfolio screen's Activity).
  final List<Widget> footer;

  /// The footer has nothing to show: a never-traded account is then the
  /// one empty state.
  final bool footerEmpty;

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

  /// The venue the chart draws; null: All.
  PortfolioPerformanceVenue? _charted;

  /// The category the donut has open; null: none.
  String? _drilled;

  void _pick(StatisticsScope next) {
    if (next == _scope) return;
    HapticFeedback.selectionClick();
    TrackingService.track('portfolio_allocation_view_changed',
        params: {'view': next.name});
    setState(() {
      _scope = next;
      // The donut draws the other view afresh, nothing open.
      _drilled = null;
    });
  }

  void _chart(PortfolioPerformanceVenue? next) {
    if (next == _charted) return;
    HapticFeedback.selectionClick();
    TrackingService.track('portfolio_statistics_venue_toggled',
        params: {'venue': _eventVenue(next)});
    setState(() => _charted = next);
  }

  /// A slice opened ([category]) or closed again (null).
  void _drill(String? category) {
    final previous = _drilled;
    _drilled = category;
    final reported = category ?? previous;
    if (reported == null) return;
    TrackingService.track('portfolio_allocation_drilled', params: {
      'venue': 'all',
      'level': category == null ? 'top' : 'category',
      'category': reported,
      'view': _scope.name,
    });
  }

  /// [top] on the lists' 16 gutter, then the footer, the last row clear
  /// of the home indicator or the dock.
  Widget _page(List<Widget> top) {
    final header = widget.header;
    final all = [if (header != null) header, ...top];
    return CustomScrollView(
      slivers: [
        if (all.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 0),
            sliver: SliverList(delegate: SliverChildListDelegate(all)),
          ),
        ...widget.footer,
        SliverToBoxAdapter(
            child: SizedBox(height: 32.h + kuteDockScrollClearance(context))),
      ],
    );
  }

  /// The one empty state ([empty]) filling the page, under the header
  /// when there is one.
  Widget _emptyPage(Widget empty) {
    final header = widget.header;
    if (header == null) return empty;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 0),
          sliver: SliverToBoxAdapter(child: header),
        ),
        SliverFillRemaining(child: empty),
      ],
    );
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
    // A header keeps the page a scrolling list whatever the figures say.
    final footer = !widget.footerEmpty || widget.header != null;
    // As the venue's own tab: a reload keeps the last figures up.
    if (results.values.any((r) => !r.hasValue && !r.hasError)) {
      const spinner = Center(child: CircularProgressIndicator.adaptive());
      return footer
          ? _page([SizedBox(height: 160.h, child: spinner)])
          : const KuteDockClearance(child: spinner);
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
      final error = _PerformanceError(
        failures: failures,
        onRetry: () {
          for (final venue in failures.keys) {
            TrackingService.track('portfolio_performance_retry_tapped',
                params: {'venue': venue.name});
            ref.invalidate(portfolioPerformanceProvider(
                PortfolioPerformanceRequest(venue: venue)));
          }
        },
      );
      return footer ? _page([error]) : KuteDockClearance(child: error);
    }
    return _OverviewBody(
      venues: [
        for (final v in venues)
          if (data.containsKey(v)) v
      ],
      data: data,
      scope: _scope,
      onScope: _pick,
      onDrill: _drill,
      charted: _charted,
      onChart: _chart,
      footerEmpty: widget.footerEmpty,
      page: _page,
      emptyPage: _emptyPage,
    );
  }
}

class _OverviewBody extends ConsumerWidget {
  const _OverviewBody({
    required this.venues,
    required this.data,
    required this.scope,
    required this.onScope,
    required this.onDrill,
    required this.charted,
    required this.onChart,
    required this.footerEmpty,
    required this.page,
    required this.emptyPage,
  });

  /// The one empty state as the page: alone, or under the header.
  final Widget Function(Widget empty) emptyPage;

  /// The venues read (a venue whose read failed is left out).
  final List<PortfolioPerformanceVenue> venues;
  final Map<PortfolioPerformanceVenue, PortfolioPerformance> data;
  final StatisticsScope scope;
  final ValueChanged<StatisticsScope> onScope;
  final ValueChanged<String?> onDrill;
  final PortfolioPerformanceVenue? charted;
  final ValueChanged<PortfolioPerformanceVenue?> onChart;
  final bool footerEmpty;
  final Widget Function(List<Widget> top) page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final single = venues.length == 1 ? venues.single : null;
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

    // The figures on a sub-tab: the venues' added (the only venue's on a
    // one-venue account).
    _Figures? figuresOn(StatisticsScope on) => single != null
        ? _venueFigures(
            venue: single, data: data[single]!, scope: on, trading: trading)
        : _Figures.sum([
            for (final v in venues)
              _venueFigures(
                  venue: v, data: data[v]!, scope: on, trading: trading)
          ]);
    final figures = figuresOn(scope);

    // Never traded: no chart, nothing on either sub-tab. The page is one
    // empty state (the chart's words), no pills over nothing; or only the
    // footer's rows.
    if (!combined.hasMovement &&
        _Figures.quiet(figures) &&
        _Figures.quiet(figuresOn(_otherScope(scope)))) {
      final text = single == PortfolioPerformanceVenue.predictions
          ? l10n.betHistoryEmpty
          : l10n.hlNoHistoryYet;
      if (!footerEmpty) return page(const []);
      return emptyPage(_PageEmpty(text: text));
    }

    final tiles = [
      if (!_Figures.quiet(figures))
        ..._tilesOf(context, ref, figures!, single, scope),
    ];
    final List<Widget> stats;
    if (tiles.isNotEmpty) {
      stats = [
        _StatTiles(
            key: const ValueKey('statistics-figures'),
            tiles: tiles,
            boxed: true),
      ];
    } else if (figures == null) {
      // Nothing to say.
      stats = const [];
    } else {
      // Nothing on the sub-tab: the empty state, never a card of zeros.
      stats = [_SubTabEmpty(text: _quietText(l10n, single, scope))];
    }

    return page([
      // A P&L that never moved, with something below: no chart, and no
      // second empty state over the figures.
      if (combined.hasMovement) ...[
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
        SizedBox(height: 12.h),
      ],
      _ScopePills(scope: scope, onScope: onScope),
      _AllocationCard(
        venues: venues,
        data: data,
        trading: trading,
        scope: scope,
        onPicked: onDrill,
      ),
      SizedBox(height: 12.h),
      ...stats,
    ]);
  }
}

/// All · Investing · Predictions at the top of the P&L card: the charts'
/// small pills ([KuteRangePill], the card's own selector style), at their
/// natural width.
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

/// The Portfolio's one donut, for the Active | Historic pair: both venues'
/// categories in one set ([CategoryVenue.all]). Active: each open
/// Investing holding at what closing it gives back or at the mid, each
/// live prediction at the live price, the hole saying "Active". Historic:
/// the volume traded and the amount predicted per category, all time
/// (the hole says so); a venue whose history was cut at its read cap adds
/// nothing (the tiles write its dash). A slice opens up to what is in it
/// at both venues, the larger venue's list first, each item's share of
/// the whole slice. A venue not read yet adds nothing until it lands; the
/// predictions' categories still being read: the placeholder. Nothing in
/// it: no card.
class _AllocationCard extends ConsumerWidget {
  const _AllocationCard({
    required this.venues,
    required this.data,
    required this.trading,
    required this.scope,
    required this.onPicked,
  });

  final List<PortfolioPerformanceVenue> venues;
  final Map<PortfolioPerformanceVenue, PortfolioPerformance> data;
  final _TradingParts? trading;
  final StatisticsScope scope;
  final ValueChanged<String?> onPicked;

  /// One card for both views, so the ring morphs between them.
  static const _key = ValueKey('statistics-allocation');

  /// [parts] added per category (a part not known adds nothing).
  static Map<String, double> _merge(List<Map<String, double>?> parts) {
    final out = <String, double>{};
    for (final part in parts) {
      if (part == null) continue;
      for (final MapEntry(:key, :value) in part.entries) {
        out[key] = (out[key] ?? 0) + value;
      }
    }
    return out;
  }

  /// What [values] holds in the slice [inSlice] draws.
  static double _inSlice(
          Map<String, double>? values, bool Function(String) inSlice) =>
      values == null
          ? 0
          : values.entries
              .where((e) => inSlice(e.key))
              .fold<double>(0, (sum, e) => sum + e.value);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final active = scope == StatisticsScope.active;
    final scopeName = scope.name;
    final book = data[PortfolioPerformanceVenue.predictions]?.predictions;
    const request = PortfolioPerformanceRequest(
        venue: PortfolioPerformanceVenue.predictions);
    // Both views' category reads, whichever is on screen, so the pair
    // switches the ring at once (and it morphs) instead of loading.
    final openCategories = book == null
        ? null
        : ref.watch(predictionOpenCategoriesProvider(request));
    final stakes = book == null
        ? null
        : ref.watch(predictionCategoryStakesProvider(request));
    // The same categories the stakes were split by, for the drill-down.
    final stakeCategories = book == null
        ? null
        : ref.watch(predictionCategoriesProvider(request)).valueOrNull;
    Map<String, Object> params(CategorySlice slice) =>
        categoryDrillParams(slice,
            venue: CategoryVenue.all, walletKind: 'hot', scope: scopeName);

    Widget card({
      required Map<String, double> values,
      required String? centreLabel,
      required CategoryDrillBuilder drill,
    }) {
      if (values.values.every((v) => !v.isFinite || v <= 0)) {
        return const SizedBox.shrink();
      }
      return PortfolioCategoryCard(
        key: _key,
        level: scope,
        values: values,
        venue: CategoryVenue.all,
        scope: scopeName,
        centreLabel: centreLabel,
        onPicked: onPicked,
        drill: drill,
      );
    }

    if (active) {
      final livePrices = ref.watch(livePriceProvider.select((s) => s.prices));
      final positions = trading?.positions;
      final spot = trading?.spot;
      final (holdings, byWire) = positions != null && spot != null
          ? _tradingHoldings(ref, positions, spot)
          : (null, const <String, HlMarket>{});
      final tradingValues = holdings == null
          ? null
          : tradingOpenCategoryValues(
              [for (final h in holdings) (h.coin, h.market, h.value)]);
      final live = book == null ? null : livePredictionRecords(book);
      final categories = openCategories;
      // Their markets' categories still being read: the placeholder.
      if (live != null &&
          live.isNotEmpty &&
          categories != null &&
          !categories.hasValue &&
          !categories.hasError) {
        return const PortfolioCategorySkeleton();
      }
      // A read that failed files every prediction under Other.
      final byMarket = categories?.valueOrNull;
      final predictionValues = live == null
          ? null
          : predictionOpenCategoryValues(
              live, byMarket ?? const {}, livePrices);
      return card(
        values: _merge([tradingValues, predictionValues]),
        centreLabel: l10n.portfolioStatsActive,
        drill: (context, slice, inSlice) => _MergedDrill(parts: [
          if (holdings != null)
            (
              _inSlice(tradingValues, inSlice),
              TradingCategoryDrill.active(
                holdings: holdings,
                inSlice: (coin, market) =>
                    inSlice(hlFillCategory(coin, market)),
                marketsByWire: byWire,
                params: params(slice),
                shareOf: slice.value,
              ),
            ),
          if (live != null && byMarket != null)
            (
              _inSlice(predictionValues, inSlice),
              PredictionCategoryDrill(
                records: live,
                categories: byMarket,
                inSlice: inSlice,
                active: true,
                params: params(slice),
                shareOf: slice.value,
              ),
            ),
        ]),
      );
    }

    final tradingBook = trading?.book;
    final markets = ref.watch(hyperliquidAllMarketsProvider);
    final byWire = {for (final m in markets) m.wireCoin: m};
    final tradingVolumes = tradingBook == null
        ? null
        : tradingCategoryVolumes(tradingBook, byWire);
    final categories = stakeCategories;
    if (stakes != null && !stakes.hasValue && !stakes.hasError) {
      return const PortfolioCategorySkeleton();
    }
    final predictionStakes = stakes?.valueOrNull;
    return card(
      values: _merge([tradingVolumes, predictionStakes]),
      centreLabel: null,
      drill: (context, slice, inSlice) => _MergedDrill(parts: [
        if (tradingBook != null && tradingVolumes != null)
          (
            _inSlice(tradingVolumes, inSlice),
            TradingCategoryDrill.historic(
              fills: tradingBook.fills,
              inSlice: (coin, market) => inSlice(hlFillCategory(coin, market)),
              marketsByWire: byWire,
              params: params(slice),
              shareOf: slice.value,
            ),
          ),
        if (book != null && predictionStakes != null && categories != null)
          (
            _inSlice(predictionStakes, inSlice),
            PredictionCategoryDrill(
              records: book.records,
              categories: categories,
              inSlice: inSlice,
              active: false,
              params: params(slice),
              shareOf: slice.value,
            ),
          ),
      ]),
    );
  }
}

/// An opened slice of the merged donut: each venue's list of what is in
/// it, the venue holding more of the slice first; a venue with nothing in
/// it has no list.
class _MergedDrill extends StatelessWidget {
  const _MergedDrill({required this.parts});

  /// Each venue's amount in the slice and its list.
  final List<(double, Widget)> parts;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final part in parts)
        if (part.$1 > 0) part
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    if (shown.length == 1) return shown.single.$2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [for (final part in shown) part.$2],
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
    bool quietOn(StatisticsScope on) => _Figures.quiet(
        _venueFigures(venue: venue, data: data, scope: on, trading: trading));

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
  Widget build(BuildContext context) =>
      PortfolioEmptyState(text, key: const ValueKey('statistics-chart-empty'));
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

/// The figures in ONE low row (founder requests, October 2026), each a
/// caption over its figure, in the balance breakdown's columns
/// (portfolio_figure_tiles.dart): in a card of their own ([boxed], the
/// Portfolio), or as columns inside the card that holds them (a Ledger's
/// Statistics).
class _StatTiles extends StatelessWidget {
  const _StatTiles({super.key, required this.tiles, this.boxed = false});

  /// Label, figure and the figure's colour.
  final List<(String, String, Color)> tiles;

  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final row = PortfolioTileRow(boxed: boxed, children: [
      for (final (label, figure, color) in tiles)
        PortfolioTile(
          children: [
            PortfolioTileStat(
                label: label,
                figure: PortfolioTileFigure(figure, color: color)),
          ],
        ),
    ]);
    if (boxed) return row;
    return Padding(padding: EdgeInsets.all(16.w), child: row);
  }
}

/// The current Predictions figures, rebuilt from the account's positions
/// with their live prices (see [PortfolioPerformance.withLivePredictions]).
PortfolioPerformance _withLivePredictions(
    WidgetRef ref, PortfolioPerformance data) {
  final live = ref.watch(livePriceProvider.select((s) => s.prices));
  return data.withLivePredictions(live);
}
