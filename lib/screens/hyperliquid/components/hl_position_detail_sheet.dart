import 'dart:async';
import 'package:kute/providers/unified_search_provider.dart' show SearchCategory;
import 'package:kute/screens/shared/kute_page_route.dart';
import 'package:kute/screens/shared/kute_share_actions.dart';
import 'package:kute/screens/share/brag/brag_data.dart' show bragHlPosition;
import 'package:kute/screens/share/brag/position_share_card.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/screens/shared/fitted_title.dart';
import 'package:kute/screens/shared/kute_motion.dart' show KuteStillWhenCovered;
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
// lib/screens/hyperliquid/components/hl_position_detail_sheet.dart
//
// The open-position screen of an Investing position, in plain words. Its
// header row is the market sheet's (logo, ticker). The big figure is what
// the position is worth now (the margin plus the live profit or loss,
// [hlCloseValue]), with the unrealised profit or loss under it in the up /
// down colour ("+$0.42 (+3.9%)", the return on what was put in), then one
// quiet line: the side, the size and the market price with its change
// today ("Short · 0.006 ANTH · $2,104 (+0.8% today)"; founder, 2 November
// 2026). Then the sheet's chart, clean, with its pressure bar; two tiles:
// what was put in (the margin; the collateral on cross) with its leverage
// ("2x leverage", "No leverage"), and the liquidation price with how far
// it is ("12% away", coloured as it closes in: HlLiquidationTile); then
// the options as cards, two side by side (kute_action_cards.dart; founder,
// 4 November 2026: "big squares"): "Add margin" on an isolated position
// (the margin sheet, where Remove is a mode), "Protect it", "Advanced
// chart" and "Details". The position size (the notional, size x price,
// with the coin size), entry, leverage, margin mode and funding wait in
// Details, with one line on what the position size is; closing stays
// wallet-scoped.
//
// Close position is the floating bar's primary button (founder, 2
// November 2026: "a floating pill like the others"; kute_bar_context.dart),
// in the red the pinned button had (KuteBarPrimaryStyle.destructive): it
// opens the close ticket, whose own button is the bar while it is up (and
// thinks while the close runs). Once the position this screen saw is gone
// from the account, the bar reads "Position closed" and takes no tap. At
// its right the round Sal button (founder, 4 November 2026: no share pill
// beside the figure, it floats; kute_bar_context.dart, THE TRADE ROW):
// "Brag about it" in profit (the brag card), else Send to a friend (the
// page's Sal sheet; position_share_card.dart). The body scrolls clear of
// the bar; chart-edit mode takes both away with the header.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/screens/home/components/action_pill.dart'
    show greenColor, redColor;
import 'package:kute/screens/hyperliquid/components/close_position_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_adjust_margin_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_isolated_margin.dart';
import 'package:kute/screens/hyperliquid/components/hl_liquidation_distance.dart';
import 'package:kute/screens/hyperliquid/components/hl_tick_price.dart';
import 'package:kute/screens/shared/portfolio_position_card.dart'
    show portfolioCardCaptionStyle;
import 'package:kute/screens/shared/position_rows_card.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart'
    show HlCandleChart, HlChartEditBody;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/theme/app_theme.dart';

/// The "You put in" tile's sub-line: "2x leverage" ("3.5x leverage" when
/// the leverage is not whole: an integer when whole, else one decimal), or
/// "No leverage" at 1x. Display only: the app opens no leveraged position.
String hlLeverageCaption(AppLocalizations l10n, num leverage) {
  if (leverage <= 1) return l10n.hlPositionNoLeverage;
  final whole = leverage == leverage.roundToDouble();
  return l10n.hlPositionLeverage(
      whole ? leverage.round().toString() : leverage.toStringAsFixed(1));
}

// ───────────────────────────── sheet ─────────────────────────────

class HlPositionDetailSheet extends ConsumerStatefulWidget {
  final HlPerpPosition position;

  /// The market descriptor for the position's coin, when resolvable — used
  /// for the wire coin (candle feed), the icon, and threaded to the close
  /// sheet's advanced order types. Optional: the sheet degrades gracefully
  /// to the position's own coin when the universe hasn't loaded it.
  final HlMarket? market;
  final String? ledgerWalletId;

  const HlPositionDetailSheet({
    super.key,
    required this.position,
    this.market,
    this.ledgerWalletId,
  });

  static const routeName = 'hyperliquid-position-detail-sheet';

  /// One position screen per position: opening the one already on screen
  /// (its own entry or liquidation line, a second tap on its card) does
  /// nothing.
  static String openKey(String coin, String? ledgerWalletId) =>
      '$routeName:${ledgerWalletId ?? 'hot'}:$coin';

  static void show(
    BuildContext context, {
    required HlPerpPosition position,
    HlMarket? market,
    String? ledgerWalletId,
  }) {
    final key = openKey(position.coin, ledgerWalletId);
    if (OpenOnce.isOpen(key)) return;
    TrackingService.screenView('hyperliquid_position_detail');
    // Drop active focus (search field) so closing the sheet doesn't
    // re-summon the keyboard — same fix as the market detail sheet.
    FocusManager.instance.primaryFocus?.unfocus();
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(OpenOnce.run(key, () => navigator.push(
      // The detail sheet's rise (kute_page_route.dart): the settle easing
      // with the 0.97 → 1 scale, down on the close easing.
      KuteSheetPageRoute(
        settings: const RouteSettings(name: routeName),
        barrierColor: Colors.black.withValues(alpha: 0.4),
        // Still while the close sheet (or any sheet) covers it, so its tick
        // animations never share the frames of the sheet being scrolled.
        builder: (_) => KuteStillWhenCovered(
          child: HlPositionDetailSheet(
              position: position,
              market: market,
              ledgerWalletId: ledgerWalletId),
        ),
      ),
    )));
  }

  @override
  ConsumerState<HlPositionDetailSheet> createState() =>
      _HlPositionDetailSheetState();
}

class _HlPositionDetailSheetState extends ConsumerState<HlPositionDetailSheet> {
  /// Live-price feed hold — acquired in initState, released exactly once
  /// in dispose (nulled to guard a double dispose). This sheet sits on
  /// the root navigator, so the shell's Trading-tab pause must not
  /// freeze the headline PnL.
  HlLivePricesNotifier? _livePrices;
  /// The chart's edit mode is on: as on the market sheet, the header,
  /// the position and the bar's Close position give way and the chart
  /// takes the whole screen (HlChartEditBody); Done or back brings them
  /// back.
  bool _advancedChart = false;

  /// The account has shown this position live while the screen is open:
  /// its absence after that means it closed (an empty list before it, a
  /// loading account, says nothing).
  bool _seenLive = false;

  /// The chart keeps the editing state, and the body changes shape around
  /// it (scrolling column when reading, the whole screen when editing);
  /// a global key carries that state across the change.
  final GlobalKey _chartHostKey = GlobalKey();
  Timer? _accountRefresh;

  @override
  void initState() {
    super.initState();
    final ledgerId = widget.ledgerWalletId;
    if (ledgerId != null) {
      _accountRefresh = Timer.periodic(const Duration(seconds: 15), (_) {
        if (mounted) ref.invalidate(ledgerHlAccountProvider(ledgerId));
      });
    }
    // acquire() BEFORE watchCoins so the coin subscribes on the revived
    // socket even when the shell already paused the feed.
    _livePrices = ref.read(hyperliquidLivePricesProvider.notifier);
    _livePrices!.acquire();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Live mid for the headline PnL. Additive + idempotent with the
      // Trading screen's own subscription.
      _livePrices?.watchCoins([widget.position.coin]);
      _livePrices?.focus(widget.position.coin);
    });
  }

  @override
  void dispose() {
    _accountRefresh?.cancel();
    _livePrices?.unfocus(widget.position.coin);
    _livePrices?.release();
    _livePrices = null;
    super.dispose();
  }

  /// Freshest market descriptor for this coin — falls back to the threaded
  /// snapshot while the universe loads, then to null (icon/candles still
  /// render off the position's own coin).
  HlMarket? get _market =>
      ref.watch(hyperliquidAccountMarketProvider(widget.position.coin)) ??
      widget.market;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ledgerId = widget.ledgerWalletId;
    List<HlPerpPosition> positions;
    if (ledgerId == null) {
      positions = ref.watch(hyperliquidPerpPositionsProvider);
    } else {
      final identity = ref.watch(ledgerIdentityProvider(ledgerId));
      final account = ref.watch(ledgerHlAccountProvider(ledgerId)).valueOrNull;
      final valid = identity?.walletId == ledgerId &&
          identity?.hasVerifiedEvm == true &&
          account?.walletId == ledgerId &&
          account?.address?.toLowerCase() ==
              identity?.evmAddress?.toLowerCase();
      positions = valid
          ? [
              ...?account?.account?.positions,
              for (final dex in account!.dexAccounts.values) ...dex.positions
            ]
          : [];
    }
    final current =
        positions.where((p) => p.coin == widget.position.coin).firstOrNull;
    if (current != null) _seenLive = true;
    // Gone from the account it was seen in: nothing left to close.
    final closed = _seenLive && current == null;
    final pos = current ?? widget.position;
    final m = _market;

    // Live mark drives the headline PnL/ROE so it matches the position card;
    // fall back to the exchange snapshot when the WS mid hasn't landed.
    final liveMid = ref.watch(hyperliquidLiveMidProvider(pos.coin));
    final markPx = liveMid ??
        (pos.szi.abs() > 0 ? pos.positionValue / pos.szi.abs() : pos.entryPx);
    final pnl = hlLivePnl(pos, liveMid: liveMid);
    // The return on the user's own margin, off the live P&L so it tracks
    // the headline (the Portfolio card's same figure); the exchange's
    // returnOnEquity when there is no margin to divide by.
    final margin = hlPositionMargin(pos);
    final roe = margin > 0 ? pnl / margin : pos.returnOnEquity;
    final positive = pnl >= 0;
    final accent = positive ? greenColor : redColor;
    final pnlText = '${positive ? '+' : '−'}${formatPolyAmount(ref, pnl.abs())}';
    // What the position is worth now: the margin plus the live profit or
    // loss, what closing gives back (the hero figure).
    final worth = hlCloseValue(pos, liveMid: liveMid);
    final liquidation = current != null ? hlLiquidationPrice(pos) : null;
    // Isolated margin can be topped up or taken out (spending wallet
    // only: the Ledger signer has no reviewed path for
    // updateIsolatedMargin), on the very market the position is held on.
    final canAdjustMargin =
        ledgerId == null && current != null && hlCanAdjustMargin(pos, m);
    final editing = _advancedChart && m != null;

    // The page's Sal context: the round Sal button beside Close position
    // opens it (or, in profit, the brag card; positionBarShare). The
    // scope is around the whole page, with the `header` placement so the
    // chart editor, where Close position is away, has no bar at all. A
    // long press on Close position asks Sal with this context.
    final bar = marketBarContext(
      context,
      // As the header names it, the logo drawn as the header draws it.
      title: hlFriendlyName(m?.coin ?? pos.coin) ?? (m?.coin ?? pos.coin),
      ticker: m?.coin ?? pos.coin,
      wireCoin: m?.wireCoin ?? pos.coin,
      coinCategory: m?.category,
      coinIconUrl: m?.iconUrl,
      venue: kMarketLinkInvesting,
      slug: widget.position.coin,
      // The pick: this position's side.
      outcome: pos.isLong ? context.l10n.longLabel : context.l10n.shortLabel,
      position: true,
      category: SearchCategory.perpetuals,
      searchHint: context.l10n.searchInvestmentsHint,
      source: 'trading',
      placement: KuteBarPlacement.header,
      // An open position brags (kute_share_actions.dart).
      brag: current == null
          ? null
          : () => bragHlPosition(ref.read,
              position: pos,
              title: m?.coin ?? pos.coin,
              side: pos.isLong
                  ? context.l10n.longLabel
                  : context.l10n.shortLabel,
              pnl: pnl,
              markPx: markPx,
              wireCoin: m?.wireCoin,
              iconUrl: m?.iconUrl,
              category: m?.category,
              decimalCap: m?.pxDecimalCap),
    );
    return KuteBarContextScope(
      barContext: bar,
      child: Scaffold(
      backgroundColor: context.isDark ? c.gradientBottom : c.background,
      resizeToAvoidBottomInset: false,
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: PlatformSafeArea(
          child: Column(
            children: [
              // ── Header: close, logo and ticker ────────────────────
              // Edit mode hides it: the chart's own slim top bar names
              // the market there, and Done brings the header back.
              if (!editing)
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 4.h),
                  child: Row(
                    children: [
                      const KuteCloseButton(),
                      SizedBox(width: 8.w),
                      // The market sheet's header row: logo and ticker; the
                      // figure is under it.
                      HlCoinIcon(
                          coin: m?.coin ?? pos.coin,
                          wireCoin: m?.wireCoin ?? pos.coin,
                          category: m?.category,
                          iconUrl: m?.iconUrl,
                          size: 32),
                      SizedBox(width: 8.w),
                      Expanded(
                        // Smaller rather than cut, on its one line.
                        child: FittedTitle(
                          m?.coin ?? pos.coin,
                          key: const ValueKey('hl-position-title'),
                          maxLines: 1,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Body ──────────────────────────────────────────────
              // Editing: the market sheet's edit layout, the chart alone
              // on the whole screen, with the entry, liquidation,
              // take-profit and stop lines still on it.
              Expanded(
                child: editing
                    ? HlChartEditBody(chart: _chart(m, fillHeight: true))
                    : SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        // The foot scrolls clear of the floating Close
                        // position (and of the home indicator: the page
                        // runs to the screen's foot on iOS).
                        padding: EdgeInsets.fromLTRB(
                            20.w,
                            0,
                            20.w,
                            kuteBarScrollClearance.h +
                                MediaQuery.paddingOf(context).bottom),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: 10.h),
                            // The hero is what the position is worth now
                            // (the margin plus the live profit or loss,
                            // [hlCloseValue], the Portfolio card's figure;
                            // a tick flashes it and fades), with the
                            // unrealised profit or loss under it in the up
                            // / down colour: "+$0.42 (+3.9%)", the return
                            // on what was put in. Under that, one quiet
                            // line: the side, the size, and the market
                            // price with its change today. Entry, margin,
                            // leverage and funding wait in Details
                            // (founder, 2 November 2026: one big number,
                            // one quiet line).
                            // The row's whole width: the share floats
                            // beside Close position (founder, 4 November
                            // 2026).
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: HlTickPrice(
                                // The hero figure.
                                key: const ValueKey('hl-position-price'),
                                price: worth,
                                text: formatPolyAmount(ref, worth),
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 38.sp,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1.0,
                                  height: 1.1,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: 2.h),
                            // The P&L, amount and return; read aloud with
                            // its word ("Profit … (…)") since the colour
                            // carries it on screen. One fixed-height line,
                            // tabular figures: a tick never moves what is
                            // under it.
                            Semantics(
                              label: (positive
                                  ? context.l10n.hlPositionProfit
                                  : context.l10n.hlPositionLoss)(
                                pnlText,
                                formatHlPct(roe),
                              ),
                              excludeSemantics: true,
                              child: Text(
                                '$pnlText (${formatHlPct(roe)})',
                                key: const ValueKey('hl-position-result'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                strutStyle: StrutStyle(
                                    fontSize: 17.sp,
                                    height: 1.25,
                                    forceStrutHeight: true),
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 17.sp,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                  height: 1.25,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: 6.h),
                            // "Short · 0.006 ANTH · $2,104 (+0.8% today)":
                            // small, secondary, one line that ends in an
                            // ellipsis rather than wrapping; the change
                            // today keeps its colour.
                            Text.rich(
                              TextSpan(children: [
                                TextSpan(text: [
                                  pos.isLong
                                      ? context.l10n.longLabel
                                      : context.l10n.shortLabel,
                                  '${formatHlSize(pos.szi.abs())} '
                                      '${m?.coin ?? pos.coin}',
                                  formatHlPrice(markPx,
                                      decimalCap: m?.pxDecimalCap),
                                ].join(' · ')),
                                if (m != null)
                                  TextSpan(
                                    text: ' (${context.l10n.polyCardMoveToday(
                                        formatHlPct(m.dayChangeAt(markPx)))})',
                                    style: TextStyle(
                                      color: m.dayChangeAt(markPx) >= 0
                                          ? greenColor
                                          : redColor,
                                    ),
                                  ),
                              ]),
                              key: const ValueKey('hl-position-meta'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              strutStyle: StrutStyle(
                                  fontSize: 14.sp,
                                  height: 1.3,
                                  forceStrutHeight: true),
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                            // A thinly traded market still says so.
                            if (m != null && m.isLowLiquidity) ...[
                              SizedBox(height: 8.h),
                              const HlLowLiquidityBadge(),
                            ],
                            SizedBox(height: 20.h),
                            // The market sheet's chart, so both screens read the
                            // same: candle sizes, styles, zoom, history, the
                            // readable opening scale on a thin market, live
                            // updates, the buy / sell pressure bar under the
                            // plot, and the entry, liquidation, take-profit and
                            // stop lines.
                            if (m != null)
                              _chart(m)
                            else
                              const SkeletonLineChart(
                                  height: 380, padding: EdgeInsets.zero),
                            SizedBox(height: 16.h),
                            // Only what matters on the screen, in plain
                            // words: what was put in (with its leverage) and
                            // how far the liquidation is, each on its own
                            // tile; then the option cards.
                            if (current != null) ...[
                              PositionStatTiles(
                                left: PositionStatTile(
                                  key: const ValueKey('hl-position-margin'),
                                  // The margin (an isolated position's, with
                                  // any added since; a cross position's, the
                                  // collateral it ties up). What it is worth
                                  // now is the hero above, so the tile does
                                  // not say it again. Isolated or cross is in
                                  // Details. Under it the position's
                                  // leverage, said only ("2x leverage", "No
                                  // leverage"; founder, 2 November 2026): the
                                  // Liquidation tile's sub-line style, so both
                                  // tiles keep one height.
                                  label: context.l10n.hlPositionYouPutIn,
                                  value: Text(formatPolyAmount(ref, margin),
                                      maxLines: 1,
                                      style: positionTileValueStyle(c)),
                                  caption: Text(
                                    hlLeverageCaption(
                                        context.l10n,
                                        (m?.isSpot ?? false)
                                            ? 1
                                            : pos.leverageValue),
                                    key: const ValueKey(
                                        'hl-position-leverage'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: positionTileCaptionStyle(c),
                                  ),
                                ),
                                right: HlLiquidationTile(
                                  liquidation: liquidation,
                                  mark: markPx,
                                  decimalCap: m?.pxDecimalCap,
                                ),
                              ),
                              SizedBox(height: 12.h),
                            ],
                            // The options, as cards two side by side
                            // (founder, 4 November 2026: "big squares";
                            // kute_action_cards.dart; an odd last one full
                            // width), as on the market
                            // screen and the Predictions screens: add margin
                            // (an isolated position the app can move margin
                            // on), protect it, the chart's editing mode and
                            // Details (what else the position is made of).
                            KuteActionCardGrid(
                              key: const ValueKey('hl-position-options'),
                              cards: [
                                if (current != null && canAdjustMargin)
                                  KuteActionCard.option(
                                    key: const ValueKey('hl-add-margin'),
                                    icon: Icons.add_rounded,
                                    title: context.l10n.hlMarginAdd,
                                    subtitle: context.l10n.optionAddMarginSub,
                                    // Removing is a mode of the same sheet.
                                    onTap: () => HlAdjustMarginSheet.show(
                                        context,
                                        position: pos,
                                        market: m!,
                                        add: true,
                                        source: HlMarginSource.liquidationRow),
                                  ),
                                // The ticket's own protective orders (stop /
                                // take profit, the trailing stop), one tap
                                // away. Needs the market to place them.
                                if (current != null && m != null && !m.isSpot)
                                  KuteActionCard.option(
                                    key: const ValueKey('hl-position-protect'),
                                    icon: Icons.shield_outlined,
                                    title: context.l10n.positionProtectIt,
                                    subtitle: ledgerId == null
                                        ? context.l10n.hlStopLoss
                                        : context.l10n.investingTrailingStop,
                                    onTap: () {
                                      TrackingService.track(
                                          'position_protect_tapped',
                                          params: {
                                            'venue': 'hyperliquid',
                                            'coin': pos.coin,
                                            ...VenueAnalytics.hlAssetParams(
                                                pos.coin),
                                            'side':
                                                pos.isLong ? 'long' : 'short',
                                            'wallet_kind': ledgerId != null
                                                ? 'ledger'
                                                : 'hot',
                                            'target': ledgerId == null
                                                ? 'stop_loss'
                                                : 'trailing_stop',
                                          });
                                      HlClosePositionSheet.showProtect(
                                          context, ref,
                                          position: pos,
                                          market: m,
                                          ledgerWalletId: ledgerId);
                                    },
                                  ),
                                // The chart's editing mode, as on the market
                                // screen.
                                if (m != null)
                                  KuteActionCard.option(
                                    key: const ValueKey('hl-advanced-chart'),
                                    icon: Icons.candlestick_chart_rounded,
                                    title: context.l10n.hlAdvancedChart,
                                    subtitle:
                                        context.l10n.optionAdvancedChartSub,
                                    onTap: () => HlCandleChart.openAdvanced(
                                        _chartHostKey,
                                        source: 'position'),
                                  ),
                                _detailsCard(pos),
                              ],
                            ),
                          ],
                        ),
                      ),
              ),

              // ── Close position: the floating bar's button ─────────
              // THE BAR IS THE BUTTON (kute_bar_context.dart): the same
              // close ticket the pinned red button opened, in its red,
              // with the round Sal button at its right (Brag about it in
              // profit, else Send to a friend). Edit mode drops both so
              // the chart takes the whole screen, as the header goes;
              // Done brings them back.
              KuteBarContextScope(
                active: !editing,
                barContext: KuteBarContext.primary(
                  label: context.l10n.hlClosePosition,
                  onPrimary: () => HlClosePositionSheet.show(
                    context,
                    position: pos,
                    market: m,
                    ledgerWalletId: widget.ledgerWalletId,
                  ),
                  enabled: !closed,
                  disabledLabel: context.l10n.investingPositionClosed,
                  style: KuteBarPrimaryStyle.destructive,
                  category: SearchCategory.perpetuals,
                  searchHint: context.l10n.searchInvestmentsHint,
                  source: 'trading',
                  share: positionBarShare(bar,
                      brag: current != null && pnl >= 0.005),
                ),
                child: const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  /// The market sheet's chart, reading (in the scrolling body) or editing
  /// (filling the screen), under one key so its state carries across.
  Widget _chart(HlMarket m, {bool fillHeight = false}) => HlCandleChart(
        key: _chartHostKey,
        market: m,
        height: 380,
        fillHeight: fillHeight,
        showSignals: true,
        // No change / LIVE row: the header has the price and its change.
        showSummary: false,
        // This IS the position's screen: its entry and liquidation tags
        // do not open it again.
        positionTagOpensPosition: false,
        // Read like the Predictions position's chart outside Advanced.
        positionView: true,
        ledgerWalletId: widget.ledgerWalletId,
        onAdvancedChanged: (on) => setState(() => _advancedChart = on),
      );

  /// "Details": the last option card, opening the shared bottom sheet (as
  /// the market's "About" card does) with the size, entry, leverage,
  /// margin mode and funding rows.
  KuteActionCard _detailsCard(HlPerpPosition pos) {
    return KuteActionCard.option(
      key: const ValueKey('hl-position-details'),
      icon: Icons.receipt_long_rounded,
      title: context.l10n.details,
      subtitle: context.l10n.optionPositionDetailsSub,
      onTap: () {
        TrackingService.track('investing_position_details_opened',
            params: {'coin': pos.coin});
        unawaited(OpenOnce.run(
            'hl-position-details:${widget.ledgerWalletId ?? 'hot'}:${pos.coin}',
            () => showAppBottomSheet<void>(
                  context: context,
                  builder: (_) => _HlPositionDetailsSheet(
                    position: pos,
                    market: _market,
                    ledgerWalletId: widget.ledgerWalletId,
                  ),
                )));
      },
    );
  }
}

/// The sheet behind the "Details" card: the position's size, entry,
/// leverage, margin mode and funding as plain rows (the side, the margin
/// and the liquidation price are on the screen's tiles). The live price is in
/// the screen's header and the return under its value, so neither is
/// written here. A spending-wallet position follows the account while the
/// sheet is open; a Ledger one shows what the screen held when it opened.
class _HlPositionDetailsSheet extends ConsumerWidget {
  final HlPerpPosition position;
  final HlMarket? market;
  final String? ledgerWalletId;

  const _HlPositionDetailsSheet({
    required this.position,
    required this.market,
    required this.ledgerWalletId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final live = ledgerWalletId == null
        ? ref
            .watch(hyperliquidPerpPositionsProvider)
            .where((p) => p.coin == position.coin)
            .firstOrNull
        : null;
    final pos = live ?? position;
    final cap = market?.pxDecimalCap;
    // The live mark, as on the screen behind; the exchange's snapshot
    // until the mid lands.
    final markPx = ref.watch(hyperliquidLiveMidProvider(pos.coin)) ??
        (pos.szi.abs() > 0 ? pos.positionValue / pos.szi.abs() : pos.entryPx);
    return AppBottomSheetContainer(
      maxHeight: 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: l10n.details,
            trailing: const AppBottomSheetCloseButton(),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 24.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  PositionRowsCard(rows: [
                    // The notional (size x the live price) with the coin
                    // size: what the leverage controls, not the user's
                    // money (the line under the rows says so).
                    PositionRow(l10n.chartPositionSize,
                        '${formatPolyAmount(ref, markPx * pos.szi.abs())} · ${formatHlSize(pos.szi.abs())} ${market?.coin ?? pos.coin}'),
                    // "Entry" for both sides: a short's entry is not
                    // something it "sold", and a long's close is a sale.
                    PositionRow(l10n.hlChartEntry,
                        formatHlPrice(pos.entryPx, decimalCap: cap)),
                    PositionRow(l10n.chartLeverage, '${pos.leverageValue}x'),
                    PositionRow(
                        l10n.investingMarginMode,
                        pos.isCross
                            ? l10n.investingCrossMargin
                            : l10n.investingIsolatedMargin),
                    if (pos.fundingSinceOpen != null)
                      PositionRow(
                        pos.fundingSinceOpen! >= 0
                            ? l10n.investingFundingPaid
                            : l10n.investingFundingReceived,
                        formatPolyAmount(ref, pos.fundingSinceOpen!.abs()),
                      ),
                  ]),
                  // What the screen's two figures are, in one quiet line:
                  // the position size is what the leverage controls;
                  // closing gives back the margin plus the profit or loss.
                  SizedBox(height: 12.h),
                  Text(
                    l10n.hlPositionSizeExplain,
                    style: portfolioCardCaptionStyle(context.colors),
                  ),
                  // The last rows scroll clear of the floating bar.
                  const KuteSheetBarSpace(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
