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
import 'package:kute/screens/polymarket/components/market_card.dart'
    show polyCardFigureStyle;
import 'package:kute/screens/shared/portfolio_position_card.dart'
    show portfolioCardCaptionStyle;
import 'package:kute/screens/shared/charts/kute_chart_format.dart'
    show kuteChangeSign;
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
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
///     moved off zero: the quiet line in its place, never a flat line.
///   * Two small pills under it (the app's [KutePill] pair, as the
///     Breakdown tab's Sent | Received), Active first and picked.
///   * Active: what is open now. The donut splits the open positions'
///     value by category (Predictions: a live prediction's shares at the
///     live price; Investing: an open perp's margin plus its profit or
///     loss, the Open tab card's figure, and each spot holding at the
///     mid); the tiles are the open P&L, the amount at stake (Predictions:
///     what the open positions cost; Investing: the margin they use) and
///     the open positions. Nothing open: one quiet line.
///   * Historic: the all-time donut (amount predicted, volume traded) and
///     the realised P&L, the amount predicted or volume traded and the
///     count. Nothing ever done: one quiet line.
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
/// one account, said once.
///
///   * ONE profit and loss card leads ([PortfolioPnlChart], venue `all`
///     in its events): the venues' P&L added on the moments either
///     published ([PortfolioPerformance.combine]; a venue with no series
///     adds nothing), one headline, one line, one row of range pills.
///     Under the pills on the same card, with both venues on the account,
///     the breakdown: each venue's P&L, signed and coloured (a venue whose
///     read failed is a dash), then Earn's paid-to-date when it has paid
///     anything. A P&L that never moved draws no line: Earn's chart takes
///     the lead when the backend allows it (it is the only figure then),
///     else the quiet line.
///   * ONE Active | Historic pair under it; each venue's card (donut and
///     tiles) stacked under it, the donut's hole naming the venue. A venue
///     with nothing on the sub-tab has no card; neither has: one quiet
///     line.
///   * A venue the account has not is left out. Loading is one spinner
///     until every venue has answered; every venue failing is the retry
///     state (one `portfolio_performance_error_shown` per venue).
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

class _PortfolioStatisticsOverviewState
    extends ConsumerState<PortfolioStatisticsOverview> {
  StatisticsScope _scope = StatisticsScope.active;

  void _pick(StatisticsScope next) {
    if (next == _scope) return;
    _trackScope(next);
    setState(() => _scope = next);
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
      venues: venues,
      data: data,
      scope: _scope,
      onScope: _pick,
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
    required this.earn,
  });

  final List<PortfolioPerformanceVenue> venues;

  /// The venues read; a venue whose read failed is missing.
  final Map<PortfolioPerformanceVenue, PortfolioPerformance> data;
  final StatisticsScope scope;
  final ValueChanged<StatisticsScope> onScope;
  final bool earn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final both = venues.length > 1;
    final combined = PortfolioPerformance.combine([
      for (final v in venues)
        if (data[v] case final d?) d
    ]);

    final perVenue = [
      for (final v in venues)
        if (data[v] case final d?)
          _scopeContent(context, ref,
              venue: v, data: d, scope: scope, named: both),
    ];
    var content = perVenue.length == 1
        ? perVenue.single
        : () {
            final filled = [
              for (final list in perVenue)
                if (!_isQuiet(list)) list
            ];
            if (filled.isEmpty) {
              return <Widget>[
                _EmptyLine(
                    text: scope == StatisticsScope.active
                        ? l10n.openInvestNoOpenInvestments
                        : l10n.hlNoHistoryYet)
              ];
            }
            return [
              for (var i = 0; i < filled.length; i++) ...[
                if (i > 0) SizedBox(height: 12.h),
                ...filled[i],
              ],
            ];
          }();

    final List<Widget> lead;
    if (combined.hasMovement) {
      final tiles = <(String, String, Color)>[
        if (both)
          for (final v in venues)
            _pnlTile(
                context,
                ref,
                visible,
                v == PortfolioPerformanceVenue.trading
                    ? l10n.trading
                    : l10n.predictions,
                switch (data[v]) {
                  null => null,
                  final d => d.totalPnlUsd ?? d.points.lastOrNull?.pnlUsd ?? 0,
                }),
        if (earn)
          if (_earnTile(context, ref, visible) case final tile?) tile,
      ];
      lead = [
        PortfolioPnlChart(
          venue: both ? null : venues.single,
          data: combined,
          footer: tiles.isEmpty
              ? null
              : _StatTiles(
                  key: const ValueKey('statistics-breakdown'), tiles: tiles),
        ),
      ];
    } else if (earn) {
      // Nothing moved on the venues: Earn's chart is the only figure.
      lead = const [UsdBalanceTabs()];
    } else {
      if (_isQuiet(content)) content = const [];
      lead = [
        _EmptyLine(
            text: venues.length == 1 &&
                    venues.single == PortfolioPerformanceVenue.predictions
                ? l10n.betHistoryEmpty
                : l10n.hlNoHistoryYet,
            tag: 'statistics-chart-empty'),
      ];
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16.w, 4.h, 16.w, 32.h + kuteDockScrollClearance(context)),
      children: [
        ...lead,
        SizedBox(height: 12.h),
        _ScopePills(scope: scope, onScope: onScope),
        SizedBox(height: 12.h),
        ...content,
      ],
    );
  }
}

/// Earn's paid-to-date for the breakdown: every payout received, in the
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

/// A sub-tab's content that is only its quiet line (or nothing).
bool _isQuiet(List<Widget> content) =>
    content.isEmpty || (content.length == 1 && content.single is _EmptyLine);

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
    var content = _scopeContent(context, ref,
        venue: venue, data: data, scope: scope, walletId: walletId);

    // The chart leads, whatever sub-tab is picked: the account's P&L
    // over time, realised and open together. Nothing published yet, or a
    // P&L that never moved off zero: one quiet line in its place (never a
    // flat line at zero), and the sub-tab's own quiet line (the same
    // news) stands down.
    final List<Widget> lead;
    if (data.hasMovement) {
      lead = [PortfolioPnlChart(venue: venue, data: data)];
    } else {
      final text = predictions ? l10n.betHistoryEmpty : l10n.hlNoHistoryYet;
      if (_isQuiet(content)) content = const [];
      lead = [_EmptyLine(text: text, tag: 'statistics-chart-empty')];
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
          16.w, 4.h, 16.w, 32.h + kuteDockScrollClearance(context)),
      children: [
        ...lead,
        SizedBox(height: 12.h),
        _ScopePills(scope: scope, onScope: onScope),
        SizedBox(height: 12.h),
        ...content,
      ],
    );
  }
}

/// One venue's sub-tab: its card (the category donut, then the figures
/// under it), or its quiet line. [named] puts the venue's name in the
/// donut's hole (the spending account's tab stacks both venues' cards).
List<Widget> _scopeContent(
  BuildContext context,
  WidgetRef ref, {
  required PortfolioPerformanceVenue venue,
  required PortfolioPerformance data,
  required StatisticsScope scope,
  String? walletId,
  bool named = false,
}) {
  final c = context.colors;
  final l10n = context.l10n;
  final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
  final predictions = venue == PortfolioPerformanceVenue.predictions;
  final request = PortfolioPerformanceRequest(venue: venue, walletId: walletId);
  final walletKind = walletId == null ? 'hot' : 'ledger';
  final book = predictions ? data.predictions : null;
  final venueName = predictions ? l10n.predictions : l10n.trading;
  // The Investing figures come from what is already on the device: the
  // account's fills and its open positions (the venue's P&L series
  // carries no realised / open split).
  final trading = predictions ? null : _tradingFigures(ref, walletId);
  String money(double? value) => !visible
      ? '••••••'
      : value == null
          ? '—'
          : formatPolyAmount(ref, value);
  String count(int? value) =>
      value == null ? '—' : NumberFormat.decimalPattern().format(value);
  (String, String, Color) moneyTile(String label, double? value) =>
      (label, money(value), c.textPrimary);
  (String, String, Color) countTile(String label, int? value) =>
      (label, count(value), c.textPrimary);
  (String, String, Color) pnlTile(String label, double? value) =>
      _pnlTile(context, ref, visible, label, value);

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
    final centre = named ? venueName : l10n.portfolioStatsActive;
    if (book != null) {
      final live = livePredictionRecords(book);
      return live.isEmpty
          ? [_EmptyLine(text: l10n.openInvestNoOpenPredictions)]
          : [
              card([
                _PredictionOpenCategories(
                    request: request,
                    records: live,
                    walletKind: walletKind,
                    centreLabel: centre),
                _StatTiles(tiles: [
                  pnlTile(l10n.portfolioStatOpenPnl, data.openPnlUsd),
                  moneyTile(l10n.portfolioStatAtStake,
                      live.fold<double>(0, (sum, r) => sum + r.entryCostUsd)),
                  countTile(l10n.accountOpenPositions, live.length),
                ]),
              ]),
            ];
    }
    if (trading != null) {
      final positions = trading.positions;
      final spot = trading.spot;
      final known = positions != null && spot != null;
      return known && positions.isEmpty && spot.isEmpty
          ? [_EmptyLine(text: l10n.openInvestNoOpenInvestments)]
          : [
              card([
                if (known)
                  _TradingOpenCategories(
                      positions: positions,
                      spot: spot,
                      walletKind: walletKind,
                      walletId: walletId,
                      centreLabel: centre),
                _StatTiles(tiles: [
                  pnlTile(l10n.portfolioStatOpenPnl, trading.openPnlUsd),
                  moneyTile(
                      l10n.portfolioStatAtStake,
                      positions?.fold<double>(
                          0, (sum, p) => sum + hlPositionMargin(p))),
                  countTile(l10n.accountOpenPositions,
                      known ? positions.length + spot.length : null),
                ]),
              ]),
            ];
    }
    return const [];
  }

  final centre = named ? venueName : null;
  if (book != null) {
    final stats = book.statsSince(null);
    return stats != null && stats.count == 0 && (data.realizedPnlUsd ?? 0) == 0
        ? [_EmptyLine(text: l10n.betHistoryEmpty)]
        : [
            card([
              _PredictionCategories(
                  request: request, book: book, centreLabel: centre),
              _StatTiles(tiles: [
                pnlTile(l10n.portfolioStatRealized, data.realizedPnlUsd),
                moneyTile(l10n.portfolioStatAmountPredicted, stats?.stakedUsd),
                countTile(l10n.portfolioStatCount, stats?.count),
              ]),
            ]),
          ];
  }
  if (trading != null) {
    final stats = trading.book?.statsSince(null);
    return stats != null && stats.count == 0
        ? [_EmptyLine(text: l10n.hlNoHistoryYet)]
        : [
            card([
              if (trading.book != null)
                _TradingCategories(
                    book: trading.book!,
                    walletKind: walletKind,
                    walletId: walletId,
                    centreLabel: centre),
              // What closing realised (net of fees), the notional traded
              // and the fills. A figure the fills do not reach back to, or
              // one not read yet, is a dash, never a zero.
              _StatTiles(tiles: [
                pnlTile(l10n.portfolioStatRealized, stats?.realizedUsd),
                moneyTile(l10n.portfolioStatVolume, stats?.volumeUsd),
                countTile(l10n.portfolioStatTrades, stats?.count),
              ]),
            ]),
          ];
  }
  return const [];
}

/// Nothing to show on a sub-tab (or nothing to chart yet): one quiet line
/// on the card surface (the Breakdown tab's empty card).
class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text, this.tag = 'statistics-empty'});
  final String text;

  /// The line's key, for the tests: the sub-tab's or the chart's.
  final String tag;

  @override
  Widget build(BuildContext context) => Container(
        key: ValueKey(tag),
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 32.h),
        decoration: AppDecorations.card(context),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.colors.textTertiary,
            fontSize: 13.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
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
    final markets = ref.watch(hyperliquidAllMarketsProvider);
    final byWire = {for (final m in markets) m.wireCoin: m};
    final spotMarkets = ref.watch(hyperliquidSpotMarketsProvider).valueOrNull ??
        const <HlMarket>[];
    final holdings = [
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
    ];
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

/// The Historic Predictions donut: the amount predicted per category, all
/// time. A placeholder while the markets' categories are read; nothing
/// when the history was cut, the read failed or nothing was predicted.
class _PredictionCategories extends ConsumerWidget {
  const _PredictionCategories(
      {required this.request, required this.book, this.centreLabel});
  final PortfolioPerformanceRequest request;
  final PredictionsBook book;

  /// The donut's hole; "All time" when null.
  final String? centreLabel;

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
              centreLabel: centreLabel,
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
      {required this.book,
      required this.walletKind,
      this.walletId,
      this.centreLabel});
  final TradingBook book;
  final String walletKind;
  final String? walletId;

  /// The donut's hole; "All time" when null.
  final String? centreLabel;

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
        centreLabel: centreLabel,
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
({
  TradingBook? book,
  List<HlPerpPosition>? positions,
  List<HlSpotBalance>? spot,
  double? openPnlUsd,
}) _tradingFigures(WidgetRef ref, String? walletId) {
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

/// Figures under the category donut on the same card, two to a row: each
/// a caption label over its figure, as on the position cards.
class _StatTiles extends StatelessWidget {
  const _StatTiles({super.key, required this.tiles});

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
