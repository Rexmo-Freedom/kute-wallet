// lib/screens/portfolio/open_investments_screen.dart
//
// The Portfolio: one screen, the same from every door (the Investments
// tab's Portfolio pill, where it lives embedded; Home's Predictions card,
// the Financial hub, a placed bet or order and a trade notification, which
// push it). Owner decision October 2026: the Portfolio button used to
// open a different screen per tab, so the same button gave different
// results.
//
// Layout: the app bar over the tab strip (Open, Orders, Activity,
// Statistics), no balance header and no deposit or withdrawal buttons
// (the Investments tab carries the one deposit door). NO THIRD ROW on
// any tab (owner decision October 2026): every tab shows both venues,
// with nothing to switch.
//   * Open: positions only (owner decision October 2026: the Wallet
//     section with the account's bitcoin and dollars is gone, the
//     balances live in the hero above): the Investing positions
//     (Hyperliquid perps and spot holdings) and the Predictions positions
//     (Polymarket), each under its plain section name with no total, in
//     one list.
//   * Orders: ONE merged list of both venues' open orders, newest first,
//     each row its venue sheet's own (portfolio_orders.dart).
//   * Activity: ONE merged list (portfolio_activity.dart), the venues'
//     activity and the wallet's deposits and moves sorted by time.
//   * Statistics: Investing and Predictions as ONE account, nothing said
//     twice (PortfolioStatisticsOverview): one P&L chart with an All ·
//     Investing · Predictions toggle, one allocation donut that opens a
//     venue (then a category) in the same ring, then one Active |
//     Historic pair over one card of figures for what the donut shows.
//     Earn (the dollar rewards programme) is shown nowhere, whatever the
//     backend's `usd.earn` says (owner decision).
// A venue the shell draws no tab for (portfolio_filters.dart) has no
// section and no rows here.
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
import 'package:kute/screens/home/components/kute_dock_host.dart';
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
import 'package:kute/screens/portfolio/portfolio_empty_state.dart';
import 'package:kute/screens/portfolio/portfolio_filters.dart';
import 'package:kute/screens/portfolio/portfolio_orders.dart';
import 'package:kute/screens/portfolio/portfolio_statistics.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/portfolio_position_card.dart';
import 'package:kute/screens/shared/portfolio_tabs.dart';
import 'package:kute/services/polymarket/combos/combo_models.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// A venue: Investing (Hyperliquid) or Predictions (Polymarket). The venue
/// tabs, their docks and headers are scoped by it; the Portfolio carries
/// both.
enum InvestmentsProduct { trading, predictions }

class OpenInvestmentsScreen extends ConsumerStatefulWidget {
  /// The door it was opened from, for `portfolio_opened`: dock_investing |
  /// dock_predictions | home | hub | bet_placed | order_placed |
  /// notification.
  final String source;

  /// The tab it opens on (kPortfolioTabKeys order). Every tab shows both
  /// venues, so there is no venue to open on.
  final int initialTab;

  /// Mounted as the Investments tab's Portfolio pill (one balance): the
  /// tab strip over the lists, with no Scaffold, no app bar and no back
  /// button (the pills are the navigation), exactly the Ledger's
  /// embedded portfolio. Pushed from a placed bet, an order or a trade
  /// notification it keeps its own screen.
  final bool embedded;

  const OpenInvestmentsScreen({
    super.key,
    required this.source,
    this.initialTab = 0,
    this.embedded = false,
  });

  @override
  ConsumerState<OpenInvestmentsScreen> createState() =>
      _OpenInvestmentsScreenState();
}

class _OpenInvestmentsScreenState extends ConsumerState<OpenInvestmentsScreen> {
  @override
  void initState() {
    super.initState();
    // Once per mount.
    TrackingService.track('portfolio_opened', params: {
      'source': widget.source,
      'tab': kPortfolioTabKeys[
          widget.initialTab.clamp(0, kPortfolioTabKeys.length - 1)],
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final venues = ref.watch(portfolioVenuesProvider);
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
    // Each list runs to the bottom of the screen and keeps its last row
    // clear of the home indicator, or of the host's dock when embedded
    // (kuteDockScrollClearance).
    final content = TabBarView(
      children: [
        _AllPositions(venues: venues),
        PortfolioOpenOrders(venues: venues),
        const PortfolioActivityList(),
        _StatisticsTab(venues: venues),
      ],
    );
    return DefaultTabController(
      length: 4,
      initialIndex: widget.initialTab,
      child: widget.embedded
          // The same strip and lists under the Investments pills, as the
          // Ledger's embedded portfolio mounts them.
          ? Material(
              color: Colors.transparent,
              child: Column(children: [
                tabs,
                Expanded(child: content),
              ]))
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
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: Column(
                    children: [
                      tabs,
                      Expanded(child: content),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

// ──────────────────────────────── open ────────────────────────────────

/// The Open tab: each venue's positions under its plain name, in one
/// list. A venue with nothing open has no section; nothing open anywhere
/// is the Portfolio empty state ([PortfolioEmptyState]).
class _AllPositions extends ConsumerWidget {
  const _AllPositions({required this.venues});

  final PortfolioVenues venues;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final List<Widget> trading;
    var tradingLoading = false;
    if (venues.trading) {
      final hlAsync = ref.watch(hyperliquidTradingProvider);
      trading = _tradingCards(hlAsync.valueOrNull);
      if (trading.isEmpty && hlAsync.isLoading) {
        tradingLoading = true;
      } else if (trading.isEmpty && hlAsync.hasError) {
        trading.add(_QuietLine(l10n.openInvestPositionsUnavailable));
      }
    } else {
      trading = [];
    }
    final List<Widget> predictions;
    var predictionsLoading = false;
    if (venues.predictions) {
      final book = _PolyBook.watch(ref);
      predictions = book.cards(context, ref);
      predictionsLoading =
          predictions.isEmpty && ref.watch(polymarketTradingProvider).isLoading;
    } else {
      predictions = [];
    }
    final nothingOpen = trading.isEmpty &&
        predictions.isEmpty &&
        !tradingLoading &&
        !predictionsLoading;
    if (nothingOpen) return PortfolioEmptyState(l10n.ledgerNoPositionsYet);

    return ListView(
      padding: EdgeInsets.fromLTRB(
          16.w, 4.h, 16.w, 32.h + kuteDockScrollClearance(context)),
      children: [
        if (trading.isNotEmpty || tradingLoading) ...[
          _SectionHeader(l10n.trading),
          if (tradingLoading) const _LoadingCard() else ...trading,
        ],
        if (predictions.isNotEmpty || predictionsLoading) ...[
          _SectionHeader(l10n.predictions),
          if (predictionsLoading) const _LoadingCard() else ...predictions,
        ],
      ],
    );
  }
}

// ────────────────────────────── statistics ──────────────────────────────

/// Statistics: Investing and Predictions as one account, said once
/// ([PortfolioStatisticsOverview]: one P&L chart with a venue toggle, one
/// allocation donut, one Active | Historic pair over one card of
/// figures). No venue on the account: the empty state.
class _StatisticsTab extends StatelessWidget {
  const _StatisticsTab({required this.venues});

  final PortfolioVenues venues;

  @override
  Widget build(BuildContext context) {
    final v = venues;
    if (!v.any) {
      return PortfolioEmptyState(context.l10n.openInvestNoOpenInvestments);
    }
    return PortfolioStatisticsOverview(
        key: const ValueKey('statistics-overview'),
        trading: v.trading,
        predictions: v.predictions);
  }
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

  /// The cards in order, under the Predictions section's one name: wins
  /// to claim, bets on their way, open positions, combos.
  List<Widget> cards(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return [
      if (claimable.isNotEmpty || claimableCombos.isNotEmpty) ...[
        for (final p in claimable)
          _PolyPositionCard(key: ValueKey('poly-r-${p.tokenId}'), position: p),
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
          trailing: PortfolioCardValue(value: formatPolyAmount(ref, p.amount)),
          line: p.outcomeName,
          footer: [
            p.status == PlacingBetStatus.failed
                ? l10n.openInvestPlacementFailed
                : p.stepLabel ?? l10n.openInvestUpdatingPosition,
          ],
        ),
      for (final p in open)
        _PolyPositionCard(key: ValueKey('poly-${p.tokenId}'), position: p),
      for (final p in openCombos)
        ComboPositionCard(key: ValueKey('combo-${p.conditionId}'), position: p),
    ];
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

/// The Investing cards: open perps, then spot holdings (USDC is cash, not
/// a holding).
List<Widget> _tradingCards(HyperliquidTradingState? state) {
  final positions = state?.positions ?? const <HlPerpPosition>[];
  final spot = (state?.spotBalances ?? const <HlSpotBalance>[])
      .where((balance) => balance.coin != 'USDC' && balance.total > 0);
  return [
    for (final p in positions)
      HlPortfolioPositionCard(key: ValueKey('hl-${p.coin}'), position: p),
    for (final holding in spot)
      _SpotPositionCard(
          key: ValueKey('hl-spot-${holding.coin}'), balance: holding),
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

/// A venue still loading under All: one placeholder card under its name.
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
