// lib/screens/portfolio/open_investments_screen.dart
//
// The spending account's investments, in two places (owner decision
// October 2026):
//
//   * POSITIONS ([PortfolioPositions]), the Investments tab's third pill:
//     everything held now, at both venues, in ONE list — wins to claim and
//     bets on their way first, then every open position, Predictions
//     (Polymarket, combos included) and Investing (Hyperliquid perps and
//     spot holdings) alike, largest first by what it is worth — and under
//     them the resting orders of both venues under their Orders heading,
//     with one count and one Cancel all (portfolio_orders.dart). Each row
//     is the card or order row it always was, with its drill-down and its
//     actions. Nothing held and nothing resting: the Sal empty state ("No
//     positions yet").
//   * THE PORTFOLIO ([OpenInvestmentsScreen]), full screen, opened from
//     the Investments balance (and Home's Predictions card, a venue
//     browser's dock, a link to the old Activity or Statistics tab): the
//     app bar with its back over one scrolling page — the balance
//     breakdown with its Rebalance (portfolio_balance_breakdown.dart:
//     Dollars, Investing and Predictions cash), the one P&L chart with its
//     All · Investing · Predictions toggle, the Active | Historic pair
//     over one allocation donut by category with both venues merged, the
//     figures for the pair (PortfolioStatisticsOverview), then Positions
//     (the Positions pill's rows, when anything is held or resting), then
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
// Each position is the portfolio's card, in the language of its product's
// list card: names on the left, the position's value on the right with
// the profit or loss under it (AppColors.marketUp / marketDown), one quiet
// caption (PolyPositionCard, HlPortfolioCard). Every card is its own
// widget class (theme-reading widgets inside scrolling lists must be their
// own classes) and watches only what it needs, so a price tick on one card
// never repaints the rest of the list.

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
import 'package:kute/providers/polymarket_live_prices_provider.dart';
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
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/screens/polymarket/components/combo_position_card.dart';
import 'package:kute/screens/polymarket/components/live_token_scope.dart';
import 'package:kute/screens/polymarket/components/position_card.dart';
import 'package:kute/screens/polymarket/components/position_claim.dart';
import 'package:kute/screens/polymarket/components/position_detail_sheet.dart';
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
  /// The door it was opened from, for `portfolio_opened`:
  /// investments_balance | home | dock_investing | dock_predictions |
  /// notification | link.
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
      // What is held now, the Positions pill's rows, above the Activity.
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
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24.h),
            child: const Center(child: CircularProgressIndicator.adaptive()),
          ),
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
      // The balance's cash, part by part, with Rebalance, above the chart.
      header: PortfolioBalanceBreakdown(
          trading: venues.trading, predictions: venues.predictions),
      footer: footer,
      footerEmpty: footer.isEmpty,
    );
  }
}

// ────────────────────────────── positions ──────────────────────────────

/// Positions, the Investments tab's third pill: everything held now at
/// both venues in one list, then the resting orders (see the file
/// header). A venue still loading holds one placeholder card; nothing held
/// and nothing resting is the Portfolio empty state
/// ([PortfolioEmptyState]).
class PortfolioPositions extends ConsumerWidget {
  const PortfolioPositions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final venues = ref.watch(portfolioVenuesProvider);
    final book = _PositionsBook.watch(context, ref, venues);
    final orders = book.orders;

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
        ...book.held,
        if (book.loading) const _LoadingCard(),
        if (book.tradingFailed) _QuietLine(l10n.openInvestPositionsUnavailable),
        ...book.orderItems(context, ref),
      ],
    );
  }
}

/// Everything Positions lists, in its order: wins to claim and bets on
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
    required this.orders,
  });

  final List<Widget> held;

  /// A venue still reading with nothing listed yet.
  final bool loading;

  /// The Investing read failed with nothing listed.
  final bool tradingFailed;
  final PortfolioOrdersBook orders;

  static _PositionsBook watch(
      BuildContext context, WidgetRef ref, PortfolioVenues venues) {
    var trading = const <(double, Widget)>[];
    var tradingLoading = false;
    var tradingFailed = false;
    if (venues.trading) {
      final hlAsync = ref.watch(hyperliquidTradingProvider);
      trading = _tradingCards(ref, hlAsync.valueOrNull);
      tradingLoading = trading.isEmpty && hlAsync.isLoading;
      tradingFailed = trading.isEmpty && !hlAsync.isLoading && hlAsync.hasError;
    }
    final book = venues.predictions ? _PolyBook.watch(ref) : null;
    final predictionsLoading = book != null &&
        book.isEmpty &&
        ref.watch(polymarketTradingProvider).isLoading;

    final leading = book?.leading(context, ref) ?? const <Widget>[];
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
      orders: PortfolioOrdersBook.watch(ref, venues),
    );
  }

  /// Nothing held and nothing resting.
  bool get isEmpty => held.isEmpty && orders.isEmpty;

  /// The resting orders under their heading, with the count and one
  /// Cancel all (portfolio_orders.dart).
  List<Widget> orderItems(BuildContext context, WidgetRef ref) =>
      orders.items(context, ref,
          header: (trailing) => _SectionHeader(context.l10n.portfolioTabOrders,
              key: const ValueKey('portfolio-orders-heading'),
              trailing: trailing));
}

/// The Portfolio's Positions section, above its Activity (founder
/// request, October 2026): the Positions pill's rows, the same cards and
/// order rows with the same taps and sheets, under a Positions heading in
/// the Activity heading's style. Nothing held and nothing resting (or
/// still reading): no section at all.
List<Widget> portfolioPositionsSlivers(
    BuildContext context, WidgetRef ref, PortfolioVenues venues) {
  if (!venues.any) return const [];
  final book = _PositionsBook.watch(context, ref, venues);
  if (book.isEmpty) return const [];
  return [
    SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          if (book.held.isNotEmpty) ...[
            _SectionHeader(context.l10n.ledgerPositionsTitle,
                key: const ValueKey('portfolio-positions-heading')),
            ...book.held,
          ],
          ...book.orderItems(context, ref),
        ]),
      ),
    ),
  ];
}

// ───────────────────────────── predictions ─────────────────────────────

/// The account's Polymarket book as the Portfolio lists it: wins to claim,
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
    // Every position's event in one read as the screen opens (the cards
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

  /// What leads Positions: wins to claim, then bets on their way.
  List<Widget> leading(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return [
      for (final p in claimable)
        _PolyPositionCard(key: ValueKey('poly-r-${p.tokenId}'), position: p),
      for (final p in claimableCombos)
        ComboPositionCard(
            key: ValueKey('combo-r-${p.conditionId}'), position: p),
      // A bet on its way to the book: the position card's frame in a
      // pending state. The stake is the number; the state is a caption.
      for (final p in placing)
        PolyTitledCard(
          key: ValueKey('placing-${p.placementId}'),
          title: p.marketQuestion,
          imageUrl: p.marketImage,
          trailing: PortfolioCardValue(value: formatPolyAmount(ref, p.amount)),
          line: p.outcomeName,
          footer: [
            p.status == PlacingBetStatus.failed
                ? l10n.openInvestPlacementFailed
                : p.stepLabel ?? l10n.openInvestUpdatingPosition,
          ],
        ),
    ];
  }

  /// The open positions and combos, each with what it is worth at its
  /// last read price (the order Positions ranks them in; the cards
  /// themselves follow the live price).
  List<(double, Widget)> openCards() => [
        for (final p in open)
          (
            p.size * p.currentPrice,
            _PolyPositionCard(key: ValueKey('poly-${p.tokenId}'), position: p)
          ),
        for (final p in openCombos)
          (
            p.estimatedValueUsd,
            ComboPositionCard(
                key: ValueKey('combo-${p.conditionId}'), position: p)
          ),
      ];
}

/// One Polymarket position as the portfolio's card (PolyPositionCard):
/// a game's two teams or the market's image and title, the position in
/// one line, its value with the profit or loss under it. The value
/// follows the held outcome's live price. Tap keeps the existing
/// destination (the open-position screen); a win to claim carries its
/// "Claim $4.53" button, which claims in one tap.
class _PolyPositionCard extends ConsumerWidget {
  final PolymarketPosition position;
  const _PolyPositionCard({super.key, required this.position});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = position;
    final live = ref.watch(
        livePriceProvider.select((s) => s.live ? s.prices[p.tokenId] : null));
    final price = p.isResolved ? p.currentPrice : live ?? p.currentPrice;
    final value = p.size * price;
    // A sale of this position the venue accepted and has not settled yet.
    final selling = p.tokenId != null &&
        ref.watch(polymarketTradingProvider.select((s) =>
            s.valueOrNull?.pendingSaleTokens.contains(p.tokenId) ?? false));
    final pnl = (price - p.avgPrice) * p.size;
    final pnlPercent = p.avgPrice > 0 ? (price / p.avgPrice - 1) * 100 : 0.0;

    return LiveTokenScope(
        tokens: [if (!p.isResolved && p.tokenId != null) p.tokenId!],
        keepAlive: true,
        child: PolyPositionCard(
          question: p.marketQuestion,
          imageUrl: p.marketImage,
          outcome: p.outcome,
          shares: p.size,
          avgPrice: p.avgPrice,
          value: value,
          pnl: pnl,
          pnlPercent: pnlPercent,
          eventSlug: p.eventSlug,
          end: polyPositionEnd(p),
          conditionId: p.marketId,
          resolved: p.isResolved,
          claimable: p.won == true,
          status: selling ? context.l10n.betSellingEllipsis : null,
          // A win is claimed from the card in one tap (no review page),
          // ending on the claim confirmation.
          action: p.isResolved && p.won == true
              ? PolyClaimButton(
                  position: p, surface: 'portfolio_card', compact: true)
              : null,
          onTap: () {
            HapticFeedback.selectionClick();
            TrackingService.track('open_investments_position_tapped',
                params: {'product': 'predictions'});
            PositionDetailSheet.show(context, position: p);
          },
        ));
  }
}

// ────────────────────────────── investing ──────────────────────────────

/// The Investing cards: open perps, then spot holdings (USDC is cash, not
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
        HlPortfolioPositionCard(key: ValueKey('hl-${p.coin}'), position: p)
      ),
    for (final holding in spot)
      (
        spotValue(holding),
        _SpotPositionCard(
            key: ValueKey('hl-spot-${holding.coin}'), balance: holding)
      ),
  ];
}

/// One open Hyperliquid perp as the portfolio's card (HlPortfolioCard):
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

/// A spot holding as the portfolio's card: logo, name over "TICKER ·
/// Spot", its value at the live mid with the profit or loss against what
/// the venue records as paid, and the size held (with that cost) as a
/// caption. Tap opens the market.
class _SpotPositionCard extends ConsumerWidget {
  const _SpotPositionCard({super.key, required this.balance});
  final HlSpotBalance balance;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final markets = ref.watch(hyperliquidSpotMarketsProvider).valueOrNull ??
        const <HlMarket>[];
    HlMarket? market;
    for (final item in markets) {
      if (item.coin == balance.coin) {
        market = item;
        break;
      }
    }
    final value = market != null && market.midPx > 0
        ? balance.total * market.midPx
        : null;
    // Cost and P&L from what the venue records as paid (entryNtl); a
    // balance with no cost on record (a transfer in) shows neither.
    final cost = balance.costBasis;
    final pnl = cost != null && value != null ? value - cost : null;
    return HlPortfolioCard(
      coin: balance.coin,
      wireCoin: market?.wireCoin,
      iconUrl: market?.iconUrl,
      category: market?.category,
      name:
          hlFriendlyName(balance.coin) ?? market?.unitAssetName ?? balance.coin,
      caption: '${balance.coin} · ${l10n.investingSpot}',
      trailing: PortfolioCardValue(
        value: value == null ? '—' : formatPolyAmount(ref, value),
        pnl: pnl == null
            ? null
            : PortfolioCardValue.pnlText(formatPolyAmount(ref, pnl.abs()), pnl,
                percent: cost != null && cost > 0 ? pnl / cost * 100 : null),
        up: (pnl ?? 0) >= 0,
      ),
      footer: [
        [
          l10n.openInvestHeld(formatHlSize(balance.total)),
          if (cost != null && pnl != null)
            '${l10n.betReceiptCost} ${formatPolyAmount(ref, cost)}',
        ].join(' · '),
      ],
      onTap: market == null
          ? null
          : () => HlMarketDetailSheet.show(context, market: market!),
    );
  }
}

/// A venue still loading: one placeholder card.
class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => KuteSkeleton(
        child: Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: SkeletonCard(height: 116.h),
        ),
      );
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
