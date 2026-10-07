import 'package:kute/providers/polymarket_combos_provider.dart';
import 'package:kute/screens/polymarket/components/combo_position_card.dart';
import 'package:kute/services/polymarket/combos/combo_models.dart';
import 'package:kute/screens/polymarket/components/live_token_scope.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/screens/shared/portfolio_position_card.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
// lib/screens/portfolio/open_investments_screen.dart
//
// Everything currently at work, on one screen: the user's open
// Hyperliquid perp positions (Investing) and open Polymarket positions
// (Predictions). Opened from each product's Portfolio shortcut.
//
// Layout: the balance header and the tab strip over the product's
// positions. Each position is the portfolio's card, in the language of
// its product's list card: names on the left, the position's value on
// the right with the profit or loss under it (AppColors.marketUp /
// marketDown), one quiet caption (PolyPositionCard, HlPortfolioCard).
//
// Every card is its own widget class (theme-reading widgets inside
// scrolling lists must be their own classes) and watches only what it
// needs, so a price tick on one card never repaints the rest of the
// list.

import 'package:kute/screens/home/components/kute_dock_host.dart';
import 'package:kute/screens/shared/investment_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/portfolio_tabs.dart';
import 'package:kute/screens/shared/investment_balance_header.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/screens/polymarket/components/position_card.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/screens/portfolio/portfolio_statistics.dart';
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyPortfolioEventsPrefetchProvider;
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/providers/placing_polymarket_bet_provider.dart';
import 'package:kute/screens/polymarket/prediction_history_screen.dart';
import 'package:kute/screens/polymarket/components/open_orders_sheet.dart';
import 'package:kute/screens/hyperliquid/components/open_orders_sheet.dart';
import 'package:kute/screens/hyperliquid/components/fills_history_list.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidAccountMarketProvider, hyperliquidSpotMarketsProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show
        PolymarketPosition,
        polymarketActivePositionsProvider,
        polymarketClaimablePositionsProvider;
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/screens/hyperliquid/components/hl_portfolio_card.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_isolated_margin.dart';
import 'package:kute/screens/hyperliquid/components/hl_liquidation_distance.dart';
import 'package:kute/screens/hyperliquid/components/hl_position_detail_sheet.dart';
import 'package:kute/screens/polymarket/components/position_claim.dart';
import 'package:kute/screens/polymarket/components/position_detail_sheet.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Which pool's open investments the screen shows. Scoped per surface
/// (user decision): Predictions opens only Polymarket positions,
/// Investing only Hyperliquid — never both on one screen.
enum InvestmentsProduct { trading, predictions }

class OpenInvestmentsScreen extends StatelessWidget {
  final InvestmentsProduct product;
  final int initialTab;
  final bool embedded;
  const OpenInvestmentsScreen({
    super.key,
    required this.product,
    this.initialTab = 0,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final tabLabels = <(String, IconData)>[
      (context.l10n.portfolioTabOpen, Icons.account_balance_wallet_outlined),
      (context.l10n.portfolioTabOrders, Icons.receipt_long_outlined),
      (context.l10n.activity, Icons.history_rounded),
      (context.l10n.portfolioTabStatistics, Icons.insights_outlined),
    ];
    final tabs = Padding(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 8.h),
      child: PortfolioTabs(tabs: tabLabels),
    );
    final content = TabBarView(
      children: [
        product == InvestmentsProduct.trading
            ? const _TradingBody()
            : const _PredictionsBody(),
        product == InvestmentsProduct.trading
            ? const HlOpenOrdersSheet(embedded: true)
            : const OpenOrdersSheet(embedded: true),
        product == InvestmentsProduct.trading
            ? const HlFillsHistoryList()
            : const PredictionHistoryScreen(embedded: true),
        PortfolioStatistics(
            venue: product == InvestmentsProduct.trading
                ? PortfolioPerformanceVenue.trading
                : PortfolioPerformanceVenue.predictions),
      ],
    );
    return DefaultTabController(
      length: 4,
      initialIndex: initialTab,
      child: embedded
          ? Material(
              color: Colors.transparent,
              child: Column(children: [tabs, Expanded(child: content)]))
          : Scaffold(
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
                // Home's dock mount (frost band + floating dock).
                child: KuteDockHost(
                  dockBuilder: (onHeightChanged) => InvestmentActionBar(
                      product: product,
                      onHeightChanged: onHeightChanged,
                      onPortfolio: true,
                      searchSource: product == InvestmentsProduct.trading
                          ? 'trading_portfolio'
                          : 'predictions_portfolio'),
                  body: SafeArea(
                      top: false,
                      bottom: false,
                      child: NestedScrollView(
                        headerSliverBuilder: (context, innerBoxIsScrolled) => [
                          SliverToBoxAdapter(
                              child: InvestmentBalanceHeader(
                                  product: product,
                                  showDepositButton: false)),
                          // Pinned: the strip must stay reachable once a
                          // list is a screen deep.
                          PortfolioTabsSliver(tabs: tabLabels),
                        ],
                        // The tabs run to the bottom of the screen, under
                        // the frost band and the dock, as on Home; each
                        // list keeps its last row clear of the dock
                        // (kuteDockScrollClearance).
                        body: content,
                      )),
                ),
              ),
            ),
    );
  }
}

// ───────────────────────────── predictions ─────────────────────────────

class _PredictionsBody extends ConsumerWidget {
  const _PredictionsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(polymarketActivePositionsProvider);
    final claimable = ref.watch(polymarketClaimablePositionsProvider);
    // Every position's event in one read as the screen opens (the cards
    // would otherwise each read their own); see poly_position_events.dart.
    ref.watch(polyPortfolioEventsPrefetchProvider);
    // Combos (parlays) live on the Positions Framework, not in the CLOB
    // positions above; their own provider lists them.
    final combos = ref.watch(polymarketCombosProvider).valueOrNull;
    final openCombos = combos?.open ?? const <ComboPosition>[];
    final claimableCombos = combos?.claimable ?? const <ComboPosition>[];

    final placing = ref
        .watch(placingPolymarketBetProvider)
        .where((p) => !open
            .any((o) => o.tokenId == p.tokenId && o.size > p.preExistingShares))
        .toList();
    if (open.isEmpty &&
        claimable.isEmpty &&
        placing.isEmpty &&
        openCombos.isEmpty &&
        claimableCombos.isEmpty) {
      if (ref.watch(polymarketTradingProvider).isLoading) {
        return const _LoadingCards();
      }
      return const _EmptyState(product: InvestmentsProduct.predictions);
    }

    return ListView(
      // Same top gap as the Investing body, so Open predictions sits
      // right under the tab bar rather than a card's height below it.
      padding: EdgeInsets.fromLTRB(
          16.w, 4.h, 16.w, 32.h + kuteDockScrollClearance(context)),
      children: [
        if (claimable.isNotEmpty || claimableCombos.isNotEmpty) ...[
          _SectionHeader(context.l10n.ledgerPmClaimable),
          for (final p in claimable)
            _PolyPositionCard(
                key: ValueKey('poly-r-${p.tokenId}'), position: p),
          for (final p in claimableCombos)
            ComboPositionCard(
                key: ValueKey('combo-r-${p.conditionId}'), position: p),
        ],
        // A bet on its way to the book: the position card's frame in a
        // pending state. The stake is the number; the state is a caption.
        for (final p in placing)
          PolyTitledCard(
            key: ValueKey('placing-${p.placementId}'),
            title: p.marketQuestion,
            imageUrl: p.marketImage,
            trailing:
                PortfolioCardValue(value: formatPolyAmount(ref, p.amount)),
            line: p.outcomeName,
            footer: [
              p.status == PlacingBetStatus.failed
                  ? context.l10n.openInvestPlacementFailed
                  : p.stepLabel ?? context.l10n.openInvestUpdatingPosition,
            ],
          ),
        if (open.isNotEmpty) ...[
          _SectionHeader(context.l10n.openInvestOpenPredictions),
          for (final p in open)
            _PolyPositionCard(key: ValueKey('poly-${p.tokenId}'), position: p),
        ],
        if (openCombos.isNotEmpty) ...[
          _SectionHeader(context.l10n.combosTitle),
          for (final p in openCombos)
            ComboPositionCard(
                key: ValueKey('combo-${p.conditionId}'), position: p),
        ],
      ],
    );
  }
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

class _TradingBody extends ConsumerWidget {
  const _TradingBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hlAsync = ref.watch(hyperliquidTradingProvider);
    final positions =
        hlAsync.valueOrNull?.positions ?? const <HlPerpPosition>[];

    final spot = (hlAsync.valueOrNull?.spotBalances ?? const <HlSpotBalance>[])
        .where((balance) => balance.coin != 'USDC' && balance.total > 0)
        .toList();
    if (positions.isEmpty && spot.isEmpty) {
      if (hlAsync.isLoading) return const _LoadingCards();
      if (hlAsync.hasError) {
        return KuteDockClearance(
            child: Center(
                child: Text(context.l10n.openInvestPositionsUnavailable)));
      }
      return const _EmptyState(product: InvestmentsProduct.trading);
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16.w, 4.h, 16.w, 32.h + kuteDockScrollClearance(context)),
      children: [
        for (final p in positions)
          HlPortfolioPositionCard(key: ValueKey('hl-${p.coin}'), position: p),
        for (final holding in spot) _SpotPositionCard(balance: holding),
      ],
    );
  }
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

/// Total value + overall PnL for the product, styled like the app's
/// hero numbers but smaller. Rolling digits so live ticks read as
/// movement rather than flicker.
/// The app's section-header grammar: 22sp w800, tight tracking.
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(top: 20.h, bottom: 12.h),
      child: Text(
        title,
        style: TextStyle(
          color: c.textPrimary,
          fontSize: 22.sp,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
    );
  }
}

class _LoadingCards extends StatelessWidget {
  const _LoadingCards();

  @override
  Widget build(BuildContext context) {
    return KuteSkeleton(
      child: ListView(
        padding: EdgeInsets.fromLTRB(16.w, 20.h, 16.w, 32.h),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          SkeletonBar(96.w, 13.h),
          SizedBox(height: 8.h),
          SkeletonBar(160.w, 30.h),
          SizedBox(height: 24.h),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: SkeletonCard(height: 116.h),
            ),
        ],
      ),
    );
  }
}

/// Portfolio emptiness is informational; browsing remains on the product page.
/// One centred sentence, nothing else.
class _EmptyState extends StatelessWidget {
  final InvestmentsProduct product;
  const _EmptyState({required this.product});

  @override
  Widget build(BuildContext context) => KuteDockClearance(
          child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.w),
          child: Text(
              product == InvestmentsProduct.predictions
                  ? context.l10n.openInvestNoOpenPredictions
                  : context.l10n.openInvestNoOpenInvestments,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w500)),
        ),
      ));
}

/// "+$12.34" / "−$5.00" — same minus glyph formatHlPct uses.

/// A spot holding as the portfolio's card: logo, name over "TICKER ·
/// Spot", its value at the live mid with the profit or loss against what
/// the venue records as paid, and the size held (with that cost) as a
/// caption. Tap opens the market.
class _SpotPositionCard extends ConsumerWidget {
  const _SpotPositionCard({required this.balance});
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
      name: hlFriendlyName(balance.coin) ??
          market?.unitAssetName ??
          balance.coin,
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
