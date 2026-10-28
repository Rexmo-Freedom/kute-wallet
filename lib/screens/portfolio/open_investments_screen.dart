// lib/screens/portfolio/open_investments_screen.dart
//
// The spending account's investments, in two places (owner decision
// October 2026):
//
//   * POSITIONS: everything held now, at both venues, in ONE list — settled results and
//     bets on their way first, then every open position, Predictions
//     (Polymarket, combos included) and Investing (Hyperliquid perps and
//     spot holdings) alike, largest first by what it is worth — and under
//     them the resting orders of both venues under their Orders heading,
//     with one count and one Cancel all (portfolio_orders.dart). Each row
//     is a position row or the order row it always was, with its drill-down and its
//     actions. Nothing held and nothing resting: the Sal empty state ("No
//     positions yet"). The Investments tab's Portfolio pill lists the
//     positions under their venue in its Balances section
//     ([portfolioVenueLists], since 27 October 2026: no Positions section
//     any more) and the orders under their venue on its P&L charts
//     (PortfolioOrdersBook, investments_portfolio.dart);
//     [PortfolioPositions] is the same rows as a page of their own.
//   * THE PORTFOLIO ([OpenInvestmentsScreen]), full screen, opened from
//     Home's Predictions card and a venue browser's dock standing on its
//     own (the Investments balance no longer opens it: its Charts,
//     Balances and Activity are the Portfolio pill's sections now): the
//     app bar with its back over one scrolling page — the balance
//     breakdown with its Rebalance (portfolio_balance_breakdown.dart:
//     Dollars, Investing and Predictions cash), the P&L charts' one card
//     (the realised P&L, the chart and its ranges, one line per venue
//     that picks the series) with the resting orders under it
//     (PortfolioStatisticsOverview, the orders from
//     PortfolioOrdersBook), then Positions (the Positions pill's rows,
//     when anything is held), then
//     the Activity, the one merged list (portfolio_activity.dart), its
//     newest five with Home's "See all" to the whole list. No
//     balance header and no deposit or withdrawal buttons. Never traded
//     and nothing in the Activity: the breakdown over the one Sal empty
//     state.
//
// The Portfolio's old Open / Orders / Activity / Statistics tabs are
// gone: Open and Orders are Positions, Activity and Statistics the
// Portfolio screen. A venue the shell draws no tab for
// (portfolio_filters.dart) has no rows in either.
//
// Each position is a plain list row (founder request October 2026,
// components/position_rows.dart): the market's image or the coin's logo,
// a one-line title over one line of facts, the value with the profit or
// loss under it, hairlines between rows and a quiet "N positions" above
// them. Every row is its own widget class and watches only what it needs,
// so a price tick on one row never repaints the rest of the list. The
// resting orders keep their cards (portfolio_orders.dart).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidAccountMarketProvider, hyperliquidSpotMarketsProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/placing_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show
        PolymarketPosition,
        polymarketActivePositionsProvider,
        polymarketClaimablePositionsProvider;
import 'package:kute/providers/polymarket_combos_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/screens/activity/activity_history_screen.dart'
    show showActivityHistory;
import 'package:kute/screens/home/components/kute_dock_host.dart'
    show kuteDockScrollClearance;
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_isolated_margin.dart';
import 'package:kute/screens/hyperliquid/components/hl_liquidation_distance.dart';
import 'package:kute/screens/hyperliquid/components/hl_portfolio_card.dart';
import 'package:kute/screens/hyperliquid/components/hl_position_detail_sheet.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart'
    show livePriceProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/portfolio/components/balances_overview.dart'
    show BalancesCategory, BalancesPnlText, BalancesVenueList;
import 'package:kute/screens/portfolio/components/position_rows.dart';
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyPortfolioEventsPrefetchProvider;
import 'package:kute/screens/portfolio/portfolio_activity.dart';
import 'package:kute/screens/portfolio/portfolio_balance_breakdown.dart';
import 'package:kute/screens/portfolio/portfolio_empty_state.dart';
import 'package:kute/screens/portfolio/portfolio_filters.dart';
import 'package:kute/screens/portfolio/portfolio_orders.dart';
import 'package:kute/screens/portfolio/portfolio_statistics.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/portfolio_position_card.dart';
import 'package:kute/screens/shared/transactions_builder.dart'
    show kActivityPreviewRows;
import 'package:kute/services/polymarket/combos/combo_models.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// A venue: Investing (Hyperliquid) or Predictions (Polymarket). The venue
/// tabs, their docks and headers are scoped by it; the Portfolio carries
/// both.
enum InvestmentsProduct { trading, predictions }

/// The Portfolio, full screen (see the file header).
class OpenInvestmentsScreen extends ConsumerStatefulWidget {
  /// The door it was opened from, for `portfolio_opened`: home |
  /// dock_investing | dock_predictions (investments_balance, notification
  /// and link before the Portfolio pill took those doors).
  final String source;

  const OpenInvestmentsScreen({super.key, required this.source});

  /// Pushes the Portfolio full screen, over the shell's nav bar and dock,
  /// with the app's standard back.
  static Future<void> show(BuildContext context, {required String source}) =>
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
          builder: (_) => OpenInvestmentsScreen(source: source)));

  @override
  ConsumerState<OpenInvestmentsScreen> createState() =>
      _OpenInvestmentsScreenState();
}

class _OpenInvestmentsScreenState extends ConsumerState<OpenInvestmentsScreen> {
  @override
  void initState() {
    super.initState();
    // Once per mount.
    TrackingService.track('portfolio_opened',
        params: {'source': widget.source});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: const KuteBackButton(),
        title: Text(
          context.l10n.walletPortfolioAction,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 20.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: const SafeArea(
          top: false,
          bottom: false,
          child: Material(color: Colors.transparent, child: _PortfolioPage()),
        ),
      ),
    );
  }
}

/// The Portfolio's one page: the chart, the pair, the donut and the
/// figures (PortfolioStatisticsOverview), then the Activity under its
/// heading. No venue on the account: the Activity alone.
class _PortfolioPage extends ConsumerWidget {
  const _PortfolioPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final venues = ref.watch(portfolioVenuesProvider);
    final activity = watchPortfolioActivity(ref);
    final footer = <Widget>[
      // What is held now, the Positions pill's rows, then the resting
      // orders, above the Activity.
      ...portfolioPositionsSlivers(context, ref, venues),
      if (activity.entries.isNotEmpty || activity.failed) ...[
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          sliver: SliverToBoxAdapter(
            child: _SectionHeader(l10n.activity,
                key: const ValueKey('portfolio-activity-heading')),
          ),
        ),
        // The newest few, as Home previews its own; "See all" opens the
        // Activity screen on the whole list.
        PortfolioActivitySliver(
          entries: activity.entries,
          failed: activity.failed,
          limit: kActivityPreviewRows,
          onSeeAll: () => showActivityHistory(context,
              investments: true, source: 'portfolio'),
        ),
      ] else if (activity.loading)
        SliverToBoxAdapter(
          child: SkeletonRowList(
              key: const ValueKey('portfolio-activity-loading'),
              count: 3,
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 24.h)),
        ),
    ];
    if (!venues.any) {
      if (footer.isEmpty) return PortfolioEmptyState(l10n.hlNoHistoryYet);
      return CustomScrollView(slivers: [
        ...footer,
        SliverToBoxAdapter(
            child: SizedBox(height: 32.h + kuteDockScrollClearance(context))),
      ]);
    }
    return PortfolioStatisticsOverview(
      key: const ValueKey('statistics-overview'),
      trading: venues.trading,
      predictions: venues.predictions,
      orders: PortfolioOrdersBook.watch(ref, venues),
      // The balance's cash, part by part, with Rebalance, above the chart.
      header: PortfolioBalanceBreakdown(
          trading: venues.trading, predictions: venues.predictions),
      footer: footer,
      footerEmpty: footer.isEmpty,
    );
  }
}

// ────────────────────────────── positions ──────────────────────────────

/// Positions as a page of their own: everything held now at both venues
/// in one list, then the resting orders (see the file header). A venue still loading shows shimmer rows; nothing held
/// and nothing resting is the Portfolio empty state
/// ([PortfolioEmptyState]).
class PortfolioPositions extends ConsumerWidget {
  const PortfolioPositions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final venues = ref.watch(portfolioVenuesProvider);
    final book = _PositionsBook.watch(context, ref, venues);
    final orders = book.orders!;

    if (book.held.isEmpty &&
        !book.loading &&
        !book.tradingFailed &&
        orders.isEmpty) {
      if (orders.loading) return const PortfolioOrdersSkeleton();
      return PortfolioEmptyState(l10n.ledgerNoPositionsYet);
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
          16.w, 4.h, 16.w, 32.h + kuteDockScrollClearance(context)),
      children: [
        if (book.held.isNotEmpty)
          PortfolioPositionsCount(count: book.held.length),
        ...portfolioRowsWithHairlines(context, book.held),
        if (book.loading) const _LoadingRows(),
        if (book.tradingFailed) _QuietLine(l10n.openInvestPositionsUnavailable),
        ...book.orderItems(context, ref),
      ],
    );
  }
}

/// Everything Positions lists, in its order: settled results and bets on
/// their way lead, then every open position at both venues together,
/// largest first (ties keep their venue order) ([held]); then the resting
/// orders under their Orders heading ([orderItems]). Shared by the
/// Positions pill and the Portfolio's Positions section, so both list the
/// same rows with the same taps.
class _PositionsBook {
  const _PositionsBook({
    required this.held,
    required this.loading,
    required this.tradingFailed,
    this.orders,
  });

  final List<Widget> held;

  /// A venue still reading with nothing listed yet.
  final bool loading;

  /// The Investing read failed with nothing listed.
  final bool tradingFailed;

  /// The resting orders; null when read without them ([watch]'s
  /// `withOrders`: the Investments tab lists them in their own section).
  final PortfolioOrdersBook? orders;

  static _PositionsBook watch(
      BuildContext context, WidgetRef ref, PortfolioVenues venues,
      {bool withOrders = true}) {
    var trading = const <(double, Widget)>[];
    var tradingLoading = false;
    var tradingFailed = false;
    if (venues.trading) {
      final hlAsync = ref.watch(hyperliquidDisplayTradingProvider);
      trading = _tradingCards(ref, hlAsync.valueOrNull);
      tradingLoading = trading.isEmpty && hlAsync.isLoading;
      tradingFailed = trading.isEmpty && !hlAsync.isLoading && hlAsync.hasError;
    }
    final book = venues.predictions ? _PolyBook.watch(ref) : null;
    final predictionsLoading = book != null &&
        book.isEmpty &&
        ref.watch(polymarketTradingProvider).isLoading;

    final leading = book?.leading() ?? const <Widget>[];
    final open = [...trading, ...?book?.openCards()];
    final ranked = [for (var i = 0; i < open.length; i++) (i, open[i])]
      ..sort((a, b) {
        final byValue = b.$2.$1.compareTo(a.$2.$1);
        return byValue != 0 ? byValue : a.$1.compareTo(b.$1);
      });
    return _PositionsBook(
      held: [...leading, for (final (_, (_, card)) in ranked) card],
      loading: tradingLoading || predictionsLoading,
      tradingFailed: tradingFailed,
      orders: withOrders ? PortfolioOrdersBook.watch(ref, venues) : null,
    );
  }

  /// Nothing held and nothing resting.
  bool get isEmpty => held.isEmpty && (orders?.isEmpty ?? true);

  /// The resting orders under their heading, with the count and one
  /// Cancel all (portfolio_orders.dart).
  List<Widget> orderItems(BuildContext context, WidgetRef ref) =>
      orders == null ? const [] : _orderItems(context, ref, orders!);
}

/// [orders] under their Orders heading, with the count and one Cancel
/// all (portfolio_orders.dart).
List<Widget> _orderItems(
        BuildContext context, WidgetRef ref, PortfolioOrdersBook orders) =>
    orders.items(context, ref,
        header: (trailing) => _SectionHeader(context.l10n.portfolioTabOrders,
            key: const ValueKey('portfolio-orders-heading'),
            trailing: trailing));

/// What is held, as slivers (founder request, October 2026): the
/// Positions pill's rows with the same taps and sheets, under a
/// Positions heading in the Activity heading's style, left out with
/// [heading] false (the Investments tab's Positions section, whose pill
/// already says it). Still reading: shimmer rows. Nothing held once
/// read: no section at all. The resting orders are not here: they are
/// listed under their venue on P&L charts (PortfolioStatisticsOverview).
List<Widget> portfolioPositionsSlivers(
    BuildContext context, WidgetRef ref, PortfolioVenues venues,
    {bool heading = true}) {
  if (!venues.any) return const [];
  final book = _PositionsBook.watch(context, ref, venues, withOrders: false);
  if (book.held.isEmpty && !book.loading) return const [];
  return [
    SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          if (heading)
            _SectionHeader(context.l10n.ledgerPositionsTitle,
                key: const ValueKey('portfolio-positions-heading')),
          if (book.held.isNotEmpty)
            PortfolioPositionsCount(count: book.held.length),
          ...portfolioRowsWithHairlines(context, book.held),
          if (book.loading) const _LoadingRows(),
        ]),
      ),
    ),
  ];
}

/// What the Investments tab's Balances section lists under each venue
/// (founder decision 27 October 2026: the Positions pill is gone, its rows
/// live under their venue): under Predictions the bets on their way, the
/// open positions and combos largest first, then the settled ones in their
/// own row style ([BalancesVenueList.settled]: the card lists them only
/// once its "See all" opens it, founder 28 October 2026); under Investing
/// the perps and spot holdings largest first. Each with the venue's P&L
/// beside its value and shimmer rows while it is still read with nothing
/// listed. The rows, taps and sheets are the Positions list's own; the
/// card shows the first three (components/balances_overview.dart).
Map<BalancesCategory, BalancesVenueList> portfolioVenueLists(
    BuildContext context, WidgetRef ref, PortfolioVenues venues) {
  List<Widget> ranked(List<(double, Widget)> cards) {
    final indexed = [for (var i = 0; i < cards.length; i++) (i, cards[i])]
      ..sort((a, b) {
        final byValue = b.$2.$1.compareTo(a.$2.$1);
        return byValue != 0 ? byValue : a.$1.compareTo(b.$1);
      });
    return [for (final (_, (_, card)) in indexed) card];
  }

  return {
    if (venues.predictions)
      BalancesCategory.predictions: () {
        final book = _PolyBook.watch(ref);
        final loading =
            book.isEmpty && ref.watch(polymarketTradingProvider).isLoading;
        return BalancesVenueList(
          rows: [
            for (final p in book.placing)
              PlacingBetRow(key: ValueKey('placing-${p.placementId}'), bet: p),
            ...ranked(book.openCards()),
          ],
          // Settled: listed once the venue's "See all" opens its card.
          settled: [
            for (final p in book.claimable)
              PolyPositionRow(
                  key: ValueKey('poly-r-${p.tokenId}'), position: p),
            for (final p in book.claimableCombos)
              ComboPositionRow(
                  key: ValueKey('combo-r-${p.conditionId}'), position: p),
          ],
          pnl: book.open.isEmpty
              ? null
              : _PredictionsPnl(
                  key: const ValueKey('portfolio-predictions-pnl'),
                  positions: book.open),
          loading: loading,
        );
      }(),
    if (venues.trading)
      BalancesCategory.investing: () {
        final hlAsync = ref.watch(hyperliquidDisplayTradingProvider);
        final cards = _tradingCards(ref, hlAsync.valueOrNull);
        final state = hlAsync.valueOrNull;
        return BalancesVenueList(
          rows: ranked(cards),
          pnl: cards.isEmpty || state == null
              ? null
              : _InvestingPnl(
                  key: const ValueKey('portfolio-investing-pnl'), state: state),
          loading: cards.isEmpty && hlAsync.isLoading,
        );
      }(),
  };
}

/// The open predictions' P&L at the live price, as their rows read it.
class _PredictionsPnl extends ConsumerWidget {
  const _PredictionsPnl({super.key, required this.positions});

  final List<PolymarketPosition> positions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(settingsProvider.select((s) => s.balanceVisible))) {
      return const SizedBox.shrink();
    }
    final pnl = ref.watch(livePriceProvider.select((s) {
      var sum = 0.0;
      for (final p in positions) {
        final live = s.live ? s.prices[p.tokenId] : null;
        final price = p.isResolved ? p.currentPrice : live ?? p.currentPrice;
        sum += (price - p.avgPrice) * p.size;
      }
      return sum;
    }));
    // What was paid, for the percentage, as each row divides by.
    var cost = 0.0;
    for (final p in positions) {
      if (p.avgPrice > 0 && p.size > 0) cost += p.avgPrice * p.size;
    }
    return BalancesPnlText(
        usd: pnl, costUsd: cost, money: (v) => formatPolyAmount(ref, v));
  }
}

/// The open Investing positions' P&L at the live mid (the perps), and the
/// holdings' against what the venue records as paid, as their rows read
/// it.
class _InvestingPnl extends ConsumerWidget {
  const _InvestingPnl({super.key, required this.state});

  final HyperliquidTradingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(settingsProvider.select((s) => s.balanceVisible))) {
      return const SizedBox.shrink();
    }
    var pnl = 0.0;
    // What was put in, for the percentage, as each row divides by: a
    // perp's margin (hlPositionMargin), a holding's recorded cost.
    var cost = 0.0;
    for (final p in state.positions) {
      pnl +=
          hlLivePnl(p, liveMid: ref.watch(hyperliquidLiveMidProvider(p.coin)));
      final margin = hlPositionMargin(p);
      if (margin.isFinite && margin > 0) cost += margin;
    }
    final spot = state.spotBalances
        .where((b) => b.coin != 'USDC' && b.total > 0 && b.costBasis != null)
        .toList();
    if (spot.isNotEmpty) {
      final markets = ref.watch(hyperliquidSpotMarketsProvider).valueOrNull ??
          const <HlMarket>[];
      for (final b in spot) {
        final mid =
            markets.where((m) => m.coin == b.coin).firstOrNull?.midPx ?? 0;
        if (mid > 0) {
          pnl += b.total * mid - b.costBasis!;
          cost += b.costBasis!;
        }
      }
    }
    return BalancesPnlText(
        usd: pnl, costUsd: cost, money: (v) => formatPolyAmount(ref, v));
  }
}

// ───────────────────────────── predictions ─────────────────────────────

/// The account's Polymarket book as the Portfolio lists it: settled results,
/// bets on their way to the book, open positions and combos.
class _PolyBook {
  final List<PolymarketPosition> open;
  final List<PolymarketPosition> claimable;
  final List<PlacingBet> placing;
  final List<ComboPosition> openCombos;
  final List<ComboPosition> claimableCombos;

  const _PolyBook({
    required this.open,
    required this.claimable,
    required this.placing,
    required this.openCombos,
    required this.claimableCombos,
  });

  static _PolyBook watch(WidgetRef ref) {
    final open = ref.watch(polymarketActivePositionsProvider);
    final claimable = ref.watch(polymarketClaimablePositionsProvider);
    // Every position's event in one read as the screen opens (the rows
    // would otherwise each read their own); see poly_position_events.dart.
    ref.watch(polyPortfolioEventsPrefetchProvider);
    // Combos (parlays) live on the Positions Framework, not in the CLOB
    // positions above; their own provider lists them.
    final combos = ref.watch(polymarketCombosProvider).valueOrNull;
    final placing = ref
        .watch(placingPolymarketBetProvider)
        .where((p) => !open
            .any((o) => o.tokenId == p.tokenId && o.size > p.preExistingShares))
        .toList();
    return _PolyBook(
      open: open,
      claimable: claimable,
      placing: placing,
      openCombos: combos?.open ?? const <ComboPosition>[],
      claimableCombos: combos?.claimable ?? const <ComboPosition>[],
    );
  }

  bool get isEmpty =>
      open.isEmpty &&
      claimable.isEmpty &&
      placing.isEmpty &&
      openCombos.isEmpty &&
      claimableCombos.isEmpty;

  /// What leads Positions: settled results, then bets on their way.
  List<Widget> leading() => [
        for (final p in claimable)
          PolyPositionRow(key: ValueKey('poly-r-${p.tokenId}'), position: p),
        for (final p in claimableCombos)
          ComboPositionRow(
              key: ValueKey('combo-r-${p.conditionId}'), position: p),
        // A bet on its way to the book: the stake is the number, its step
        // the facts.
        for (final p in placing)
          PlacingBetRow(key: ValueKey('placing-${p.placementId}'), bet: p),
      ];

  /// The open positions and combos, each with what it is worth at its
  /// last read price (the order Positions ranks them in; the rows
  /// themselves follow the live price).
  List<(double, Widget)> openCards() => [
        for (final p in open)
          (
            p.size * p.currentPrice,
            PolyPositionRow(key: ValueKey('poly-${p.tokenId}'), position: p)
          ),
        for (final p in openCombos)
          (
            p.estimatedValueUsd,
            ComboPositionRow(
                key: ValueKey('combo-${p.conditionId}'), position: p)
          ),
      ];
}

// ────────────────────────────── investing ──────────────────────────────

/// The Investing rows: open perps, then spot holdings (USDC is cash, not
/// a holding), each with what it is worth at the account's last read (a
/// perp at what closing it gives back, a holding at the mid; one whose
/// market is not known yet at zero), the order Positions ranks them in.
List<(double, Widget)> _tradingCards(
    WidgetRef ref, HyperliquidTradingState? state) {
  final positions = state?.positions ?? const <HlPerpPosition>[];
  final spot = (state?.spotBalances ?? const <HlSpotBalance>[])
      .where((balance) => balance.coin != 'USDC' && balance.total > 0)
      .toList();
  final markets = spot.isEmpty
      ? const <HlMarket>[]
      : ref.watch(hyperliquidSpotMarketsProvider).valueOrNull ??
          const <HlMarket>[];
  double spotValue(HlSpotBalance balance) {
    final mid =
        markets.where((m) => m.coin == balance.coin).firstOrNull?.midPx ?? 0;
    return mid > 0 ? balance.total * mid : 0;
  }

  return [
    for (final p in positions)
      (
        hlCloseValue(p),
        HlPositionRow(key: ValueKey('hl-${p.coin}'), position: p)
      ),
    for (final holding in spot)
      (
        spotValue(holding),
        HlSpotRow(key: ValueKey('hl-spot-${holding.coin}'), balance: holding)
      ),
  ];
}

/// One open Hyperliquid perp as a Ledger's portfolio card (HlPortfolioCard;
/// the spending wallet's Portfolio lists [HlPositionRow]):
/// logo, name over one short line ("Short 1x · Liq 106% away"), and on
/// the right the user's money in it, what closing it now gives back (its
/// margin plus the profit or loss, [hlCloseValue]), with the profit or
/// loss and its return on that margin under it. The notional, the size
/// and the entry are on the position screen. Money and P&L follow the
/// live mid. Tap keeps the position details, where closing is offered.
class HlPortfolioPositionCard extends ConsumerWidget {
  final HlPerpPosition position;
  final String? ledgerWalletId;
  const HlPortfolioPositionCard(
      {super.key, required this.position, this.ledgerWalletId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = position;
    final l10n = context.l10n;
    final mid = ref.watch(hyperliquidLiveMidProvider(p.coin));
    final pnl = hlLivePnl(p, liveMid: mid);
    final margin = hlPositionMargin(p);
    final roe = margin > 0 ? pnl / margin : p.returnOnEquity;
    final descriptor = ref.watch(hyperliquidAccountMarketProvider(p.coin));
    final coin = descriptor?.coin ?? p.coin;

    return HlPortfolioCard(
      coin: coin,
      wireCoin: descriptor?.wireCoin ?? p.coin,
      iconUrl: descriptor?.iconUrl,
      category: descriptor?.category,
      // The asset's own name, as on the Investing list; the ticker when
      // no name is known.
      name: hlFriendlyName(p.coin) ?? descriptor?.unitAssetName ?? coin,
      caption:
          '${p.isLong ? l10n.longLabel : l10n.shortLabel} ${p.leverageValue}x',
      trailing: PortfolioCardValue(
        value: formatPolyAmount(ref, hlCloseValue(p, liveMid: mid)),
        pnl: PortfolioCardValue.pnlText(formatPolyAmount(ref, pnl.abs()), pnl,
            percent: roe * 100),
        up: pnl >= 0,
      ),
      // "· Liq 106% away" ends the caption, the distance in the warning /
      // down colour as the mark closes in.
      liquidation: hlLiquidationPrice(p),
      mark: hlPositionMark(p, liveMid: mid),
      onTap: () {
        HapticFeedback.selectionClick();
        TrackingService.track('open_investments_position_tapped',
            params: {'product': 'trading'});
        HlPositionDetailSheet.show(context,
            position: p, market: descriptor, ledgerWalletId: ledgerWalletId);
      },
    );
  }
}

// ─────────────────────────── shared chrome ───────────────────────────

/// The app's section-header grammar: 22sp w800, tight tracking, with
/// whatever acts on the section at its right end ([trailing]: the orders'
/// count and Cancel all).
class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionHeader(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Text(
      title,
      style: TextStyle(
        color: c.textPrimary,
        fontSize: 22.sp,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
    );
    return Padding(
      padding: EdgeInsets.only(top: 20.h, bottom: 12.h),
      child: trailing == null
          ? text
          : Row(children: [Expanded(child: text), trailing!]),
    );
  }
}

/// Positions still loading: the app's shimmer rows, the rows' shape.
class _LoadingRows extends StatelessWidget {
  const _LoadingRows();

  @override
  Widget build(BuildContext context) =>
      SkeletonRowList(count: 2, padding: EdgeInsets.symmetric(vertical: 8.h));
}

/// One quiet sentence inside a list (a venue that could not be read),
/// left in the flow.
class _QuietLine extends StatelessWidget {
  const _QuietLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 28.h),
        child: Text(text,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w500)),
      );
}
