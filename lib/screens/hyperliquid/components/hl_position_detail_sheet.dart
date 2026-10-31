import 'dart:async';
import 'package:kute/providers/unified_search_provider.dart' show SearchCategory;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/kute_share_actions.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/screens/shared/fitted_title.dart';
import 'package:kute/screens/shared/kute_blur.dart';
import 'package:kute/screens/shared/kute_motion.dart' show KuteStillWhenCovered;
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
// lib/screens/hyperliquid/components/hl_position_detail_sheet.dart
//
// The open-position screen of an Investing position, in plain words. It
// reads like the market sheet of the same market: its header row (logo,
// ticker), the live price as the big figure with its change today ("Low
// liquidity" on a thin market) and the sheet's chart, clean, with its
// pressure bar. Under the price, what is the user's: the side and the
// leverage ("Long · 5x") and the profit or loss with the return on what
// was put in ("Profit +$1,000.00 (+15.6%)"). Then two tiles: what was put
// in (the margin; the collateral on cross) with what it is worth now (the
// margin plus the profit or loss, the Portfolio card's own figure,
// [hlCloseValue]), and the liquidation price with how far it is ("12%
// away", coloured as it closes in: HlLiquidationTile); then plain rows:
// "Add margin" on an isolated position (the margin sheet, where Remove is
// a mode), "Protect it" and "Details". The position size (the notional,
// size x price, with the coin size), entry, leverage, margin mode and
// funding wait in Details, with one line on what the position size is;
// closing stays wallet-scoped.

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
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/market_pair_button.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/theme/app_theme.dart';

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
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(OpenOnce.run(key, () => navigator.push(
      PageRouteBuilder(
        settings: const RouteSettings(name: routeName),
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.4),
        fullscreenDialog: true,
        transitionDuration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
        reverseTransitionDuration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
        // Still while the close sheet (or any sheet) covers it, so its tick
        // animations never share the frames of the sheet being scrolled.
        pageBuilder: (_, __, ___) => KuteStillWhenCovered(
          child: HlPositionDetailSheet(
              position: position,
              market: market,
              ledgerWalletId: ledgerWalletId),
        ),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: animation.drive(
              Tween(begin: const Offset(0, 1), end: Offset.zero)
                  .chain(CurveTween(curve: Curves.easeOutCubic)),
            ),
            child: child,
          );
        },
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
  /// the position and the Close bar give way and the chart takes the
  /// whole screen (HlChartEditBody); Done or back brings them back.
  bool _advancedChart = false;

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
    final liquidation = current != null ? hlLiquidationPrice(pos) : null;
    // Isolated margin can be topped up or taken out (spending wallet
    // only: the Ledger signer has no reviewed path for
    // updateIsolatedMargin), on the very market the position is held on.
    final canAdjustMargin =
        ledgerId == null && current != null && hlCanAdjustMargin(pos, m);
    final editing = _advancedChart && m != null;

    // The bar reads "Share with your friends" while this page is up, in
    // chart-edit mode too (the scope is around the whole page).
    return KuteBarContextScope(
      barContext: marketBarContext(
        context,
        title: widget.position.coin,
        path: '/investing/${widget.position.coin}',
        code: ref.read(settingsProvider).affiliateCode,
        position: true,
        category: SearchCategory.perpetuals,
        searchHint: context.l10n.searchInvestmentsHint,
        source: 'trading',
        prompts: [
          context.l10n.salPromptTakeProfit,
          context.l10n.salPromptRisk,
        ],
      ),
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
                      // price is the big figure under it. No Sal on a
                      // position: its rows say what is at risk and how to
                      // protect it.
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
                        // Room for the bar over the foot.
                        padding: EdgeInsets.fromLTRB(20.w, 0, 20.w,
                            28.h + AppBottomSheetContainer.barRoom.h),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: 10.h),
                            // The price now, large, as on the market screen
                            // (a tick flashes and fades), with its change
                            // today; then the position in plain words: its
                            // side and leverage, and the profit or loss with
                            // the return on what was put in.
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: HlTickPrice(
                                key: const ValueKey('hl-position-price'),
                                price: markPx,
                                text: formatHlPrice(markPx,
                                    decimalCap: m?.pxDecimalCap),
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
                            SizedBox(height: 4.h),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8.w,
                              runSpacing: 4.h,
                              children: [
                                if (m != null)
                                  Text(
                                    context.l10n.polyCardMoveToday(
                                        formatHlPct(m.dayChangeAt(markPx))),
                                    key: const ValueKey('hl-position-change'),
                                    style: TextStyle(
                                      color: m.dayChangeAt(markPx) >= 0
                                          ? greenColor
                                          : redColor,
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                                if (m != null && m.isLowLiquidity)
                                  const HlLowLiquidityBadge(),
                              ],
                            ),
                            SizedBox(height: 14.h),
                            // "Long · 5x" in the side's colour (a spot
                            // holding has no leverage: the side alone),
                            // then "Profit +$1,000.00 (+15.6%)" or
                            // "Loss −$500.00 (−7.8%)" in the up / down
                            // colour.
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 10.w,
                              runSpacing: 6.h,
                              children: [
                                HlSideChip(
                                  key: const ValueKey('hl-position-side'),
                                  text: [
                                    pos.isLong
                                        ? context.l10n.longLabel
                                        : context.l10n.shortLabel,
                                    if (!(m?.isSpot ?? false) &&
                                        pos.leverageValue > 0)
                                      '${pos.leverageValue}x',
                                  ].join(' · '),
                                  color: pos.isLong ? greenColor : redColor,
                                ),
                                Text(
                                  (positive
                                      ? context.l10n.hlPositionProfit
                                      : context.l10n.hlPositionLoss)(
                                    '${positive ? '+' : '−'}${formatPolyAmount(ref, pnl.abs())}',
                                    formatHlPct(roe),
                                  ),
                                  key: const ValueKey('hl-position-result'),
                                  style: TextStyle(
                                    color: accent,
                                    fontSize: 15.sp,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.2,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ],
                            ),
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
                            // words: what was put in (with what it is worth
                            // now) and how far the liquidation is, each on
                            // its own tile; then plain rows to
                            // add margin (an isolated position the app can
                            // move margin on), to protect it, and Details
                            // (what else the position is made of).
                            if (current != null) ...[
                              PositionStatTiles(
                                left: PositionStatTile(
                                  key: const ValueKey('hl-position-margin'),
                                  // The margin (an isolated position's, with
                                  // any added since; a cross position's, the
                                  // collateral it ties up), and under it
                                  // what closing now gives back: the margin
                                  // plus the profit or loss, the Portfolio
                                  // card's figure. Isolated or cross is in
                                  // Details.
                                  label: context.l10n.hlPositionYouPutIn,
                                  value: Text(formatPolyAmount(ref, margin),
                                      maxLines: 1,
                                      style: positionTileValueStyle(c)),
                                  caption: Text(
                                      context.l10n.hlPositionWorthNow(
                                          formatPolyAmount(
                                              ref,
                                              hlCloseValue(pos,
                                                  liveMid: liveMid))),
                                      key: const ValueKey(
                                          'hl-position-worth'),
                                      maxLines: 1,
                                      style: positionTileCaptionStyle(c)),
                                ),
                                right: HlLiquidationTile(
                                  liquidation: liquidation,
                                  mark: markPx,
                                  decimalCap: m?.pxDecimalCap,
                                ),
                              ),
                              SizedBox(height: 12.h),
                              if (canAdjustMargin)
                                PositionLinkRow(
                                  key: const ValueKey('hl-add-margin'),
                                  label: context.l10n.hlMarginAdd,
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
                              if (m != null && !m.isSpot)
                                PositionLinkRow(
                                  key: const ValueKey('hl-position-protect'),
                                  label: context.l10n.positionProtectIt,
                                  value: ledgerId == null
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
                            ],
                            // The chart's editing mode, as on the market
                            // screen: one row, above Details, with no icon
                            // like the rows around it.
                            if (m != null)
                              PositionLinkRow(
                                key: const ValueKey('hl-advanced-chart'),
                                label: context.l10n.hlAdvancedChart,
                                onTap: () => HlCandleChart.openAdvanced(
                                    _chartHostKey,
                                    source: 'position'),
                              ),
                            _buildDetailsRow(c, pos),
                          ],
                        ),
                      ),
              ),

              // ── Sticky "Close position" bar ───────────────────────
              // Edit mode drops it so the chart takes the whole screen,
              // as the market sheet drops Invest; Done brings it back.
              if (!editing)
                ClipRect(
                  child: KuteBlur(
                    sigmaX: 18,
                    sigmaY: 18,
                    child: Container(
                      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
                      decoration: BoxDecoration(
                        color: (context.isDark ? c.surface : c.background)
                            .withValues(alpha: 0.55),
                        border: Border(
                          top: BorderSide(color: c.borderSubtle, width: 0.5),
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        child: SizedBox(
                          width: double.infinity,
                          child: MarketPairButton(
                            label: context.l10n.hlClosePosition,
                            color: AppColors.marketDown,
                            icon: Icons.close_rounded,
                            iconDisc: true,
                            glow: true,
                            onTap: () {
                              HlClosePositionSheet.show(
                                context,
                                position: pos,
                                market: m,
                                ledgerWalletId: widget.ledgerWalletId,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
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

  /// "Details": one row under the position, opening the shared bottom
  /// sheet (as the market's "About" row does) with the size, entry,
  /// leverage, margin mode and funding rows.
  Widget _buildDetailsRow(AppColorsExtension c, HlPerpPosition pos) {
    return PositionLinkRow(
      label: context.l10n.details,
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

/// The sheet behind the "Details" row: the position's size, entry,
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
            trailing: IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
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
                    PositionRow(
                        pos.isLong ? l10n.chartBoughtAt : l10n.chartSoldAt,
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width "Close position" CTA — the only action on this sheet. Styled
/// like the market detail's CLOSE POSITION button (red, icon disc, bold
/// label).
// The Close badge now renders via the shared MarketPairButton
// (disc icon + light-mode glow configuration).
