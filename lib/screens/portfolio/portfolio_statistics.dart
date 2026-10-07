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
import 'package:kute/screens/portfolio/portfolio_category_donut.dart';
import 'package:kute/screens/portfolio/portfolio_category_drill.dart';
import 'package:kute/screens/polymarket/components/market_card.dart'
    show polyCardFigureStyle;
import 'package:kute/screens/shared/portfolio_position_card.dart'
    show portfolioCardCaptionStyle;
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/hyperliquid/components/hl_isolated_margin.dart'
    show hlCloseValue, hlPositionMargin;
import 'package:kute/services/portfolio/portfolio_categories.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The Statistics tab's two sub-tabs, as the analytics events name them:
/// what is open now, and what is done (all time).
enum StatisticsScope { active, historic }

/// The Portfolio's Statistics tab, for Predictions and Investing, on the
/// spending account and on a Ledger.
///
///   * Two small pills at the top (the app's [KutePill] pair, as the
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
///     pick carries the sub-tab as `scope`.
class PortfolioStatistics extends ConsumerStatefulWidget {
  const PortfolioStatistics({super.key, required this.venue, this.walletId});

  final PortfolioPerformanceVenue venue;
  final String? walletId;

  @override
  ConsumerState<PortfolioStatistics> createState() =>
      _PortfolioStatisticsState();
}

class _PortfolioStatisticsState extends ConsumerState<PortfolioStatistics> {
  StatisticsScope _scope = StatisticsScope.active;

  void _pick(StatisticsScope next) {
    if (next == _scope) return;
    HapticFeedback.selectionClick();
    TrackingService.track('portfolio_tab_changed',
        params: {'tab': 'statistics', 'subtab': next.name});
    setState(() => _scope = next);
  }

  @override
  Widget build(BuildContext context) {
    final venue = widget.venue;
    final walletId = widget.walletId;
    final request =
        PortfolioPerformanceRequest(venue: venue, walletId: walletId);
    final performance = ref.watch(portfolioPerformanceProvider(request));
    return performance.when(
      // The account and session providers this one reads re-emit while the
      // screen is open. Without these the whole tab dropped back to a
      // spinner on every one of those reloads (owner report: "keeps
      // reloading"); the last good figures stay up instead.
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      // The tab runs under the dock (the Portfolio's KuteDockHost): the
      // centred states keep clear of it, the list keeps its last row clear.
      loading: () => const KuteDockClearance(
          child: Center(child: CircularProgressIndicator.adaptive())),
      error: (e, __) => KuteDockClearance(
          child: _PerformanceError(
        venue: venue,
        errorCategory: TrackingService.errorCategory(e),
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

/// The "performance unavailable" state. Its event fires once per mount,
/// not per rebuild of the provider's error.
class _PerformanceError extends StatefulWidget {
  const _PerformanceError({
    required this.venue,
    required this.errorCategory,
    required this.onRetry,
  });
  final PortfolioPerformanceVenue venue;
  final String errorCategory;
  final VoidCallback onRetry;

  @override
  State<_PerformanceError> createState() => _PerformanceErrorState();
}

class _PerformanceErrorState extends State<_PerformanceError> {
  @override
  void initState() {
    super.initState();
    TrackingService.track('portfolio_performance_error_shown', params: {
      'venue': widget.venue.name,
      'error_category': widget.errorCategory,
    });
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
    final c = context.colors;
    final l10n = context.l10n;
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final predictions = venue == PortfolioPerformanceVenue.predictions;
    final request =
        PortfolioPerformanceRequest(venue: venue, walletId: walletId);
    final walletKind = walletId == null ? 'hot' : 'ledger';
    final book = predictions ? data.predictions : null;
    // The Investing figures come from what is already on the device: the
    // account's fills and its open positions (the venue's P&L series
    // carries no realised / open split).
    final trading = predictions ? null : _tradingFigures(ref, walletId);
    String amount(double? value) {
      if (!visible) return '••••••';
      if (value == null) return '—';
      return '${value > 0 ? '+' : value < 0 ? '−' : ''}${formatPolyAmount(ref, value.abs())}';
    }

    String money(double? value) => !visible
        ? '••••••'
        : value == null
            ? '—'
            : formatPolyAmount(ref, value);
    String count(int? value) =>
        value == null ? '—' : NumberFormat.decimalPattern().format(value);
    Color pnlColor(double? value) => !visible || value == null || value == 0
        ? c.textPrimary
        : (value > 0 ? AppColors.marketUp : AppColors.marketDown);
    (String, String, Color) pnlTile(String label, double? value) =>
        (label, amount(value), pnlColor(value));
    (String, String, Color) moneyTile(String label, double? value) =>
        (label, money(value), c.textPrimary);
    (String, String, Color) countTile(String label, int? value) =>
        (label, count(value), c.textPrimary);

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

    final List<Widget> content;
    if (scope == StatisticsScope.active) {
      if (book != null) {
        final live = livePredictionRecords(book);
        content = live.isEmpty
            ? [_EmptyLine(text: l10n.openInvestNoOpenPredictions)]
            : [
                card([
                  _PredictionOpenCategories(
                      request: request, records: live, walletKind: walletKind),
                  _StatTiles(tiles: [
                    pnlTile(l10n.portfolioStatOpen, data.openPnlUsd),
                    moneyTile(l10n.portfolioStatAtStake,
                        live.fold<double>(0, (sum, r) => sum + r.entryCostUsd)),
                    countTile(l10n.accountOpenPositions, live.length),
                  ]),
                ]),
              ];
      } else if (trading != null) {
        final positions = trading.positions;
        final spot = trading.spot;
        final known = positions != null && spot != null;
        content = known && positions.isEmpty && spot.isEmpty
            ? [_EmptyLine(text: l10n.openInvestNoOpenInvestments)]
            : [
                card([
                  if (known)
                    _TradingOpenCategories(
                        positions: positions,
                        spot: spot,
                        walletKind: walletKind,
                        walletId: walletId),
                  _StatTiles(tiles: [
                    pnlTile(l10n.portfolioStatOpen, trading.openPnlUsd),
                    moneyTile(
                        l10n.portfolioStatAtStake,
                        positions?.fold<double>(
                            0, (sum, p) => sum + hlPositionMargin(p))),
                    countTile(l10n.accountOpenPositions,
                        known ? positions.length + spot.length : null),
                  ]),
                ]),
              ];
      } else {
        content = const [];
      }
    } else {
      if (book != null) {
        final stats = book.statsSince(null);
        content = stats != null &&
                stats.count == 0 &&
                (data.realizedPnlUsd ?? 0) == 0
            ? [_EmptyLine(text: l10n.betHistoryEmpty)]
            : [
                card([
                  _PredictionCategories(request: request, book: book),
                  _StatTiles(tiles: [
                    pnlTile(l10n.portfolioStatRealized, data.realizedPnlUsd),
                    moneyTile(
                        l10n.portfolioStatAmountPredicted, stats?.stakedUsd),
                    countTile(l10n.portfolioStatCount, stats?.count),
                  ]),
                ]),
              ];
      } else if (trading != null) {
        final stats = trading.book?.statsSince(null);
        content = stats != null && stats.count == 0
            ? [_EmptyLine(text: l10n.hlNoHistoryYet)]
            : [
                card([
                  if (trading.book != null)
                    _TradingCategories(
                        book: trading.book!,
                        walletKind: walletKind,
                        walletId: walletId),
                  // What closing realised (net of exchange fees), the
                  // notional traded and the fills. A figure the fills do
                  // not reach back to, or one not read yet, is a dash,
                  // never a zero. Funding has no tile: the venue gives it
                  // per trade.
                  _StatTiles(tiles: [
                    pnlTile(l10n.portfolioStatRealized, stats?.realizedUsd),
                    moneyTile(l10n.portfolioStatVolume, stats?.volumeUsd),
                    countTile(l10n.portfolioStatTrades, stats?.count),
                  ]),
                ]),
              ];
      } else {
        content = const [];
      }
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
          16.w, 4.h, 16.w, 32.h + kuteDockScrollClearance(context)),
      children: [
        // Natural width, as the Sent | Received pair; under very large
        // text they share the row rather than overflow it.
        Row(
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
        ),
        SizedBox(height: 12.h),
        ...content,
      ],
    );
  }
}

/// Nothing to show on a sub-tab: one quiet line on the card surface (the
/// Breakdown tab's empty card).
class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('statistics-empty'),
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
      {required this.request, required this.records, required this.walletKind});
  final PortfolioPerformanceRequest request;
  final List<PredictionRecord> records;
  final String walletKind;

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
              centreLabel: context.l10n.portfolioStatsActive,
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
      this.walletId});
  final List<HlPerpPosition> positions;
  final List<HlSpotBalance> spot;
  final String walletKind;
  final String? walletId;

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
        centreLabel: context.l10n.portfolioStatsActive,
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
