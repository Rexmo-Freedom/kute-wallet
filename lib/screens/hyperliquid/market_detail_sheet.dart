import 'package:kute/screens/shared/fitted_title.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/shared/kute_blur.dart';
import 'package:kute/screens/shared/kute_motion.dart' show KuteStillWhenCovered;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/shared/charts/kute_chart_trade_lines.dart';
import 'package:kute/screens/shared/charts/kute_chart_range_pills.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/hyperliquid/components/open_orders_sheet.dart';
import 'package:kute/services/hyperliquid/hyperliquid_rounding.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_activity_provider.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/screens/shared/ask_sal_chip.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/models/polymarket_model.dart' show PolymarketEvent;
import 'package:kute/providers/hyperliquid_insights_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_pressure_strip.dart';
import 'package:kute/screens/polymarket/components/price_format.dart'
    show formatPolyChance;
import 'package:kute/screens/polymarket/market_detail_sheet.dart'
    show MarketDetailSheet;
import 'package:kute/screens/shared/charts/kute_chart_signals.dart';
import 'package:kute/services/hyperliquid/insights/hl_crowd_match.dart';
import 'package:kute/services/hyperliquid/insights/hl_flow_signals.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
// lib/screens/hyperliquid/market_detail_sheet.dart
//
// Fullscreen market detail for one Hyperliquid market (perp or spot) —
// presented exactly like the Polymarket MarketDetailSheet (slide-up
// PageRouteBuilder, opaque: false, fullscreenDialog) so the two tabs
// share one navigation grammar.
//
// Content: live header (WS mid via HlTickPrice: primary colour, a brief
// green/red flash on a tick),
// HlCandleChart (TradingView model for every style: an interval row
// 1m…1W, the user's pan and zoom, older bars loaded on demand, one global
// style and interval for all markets — fed by WIRE coin, the one mapping
// that must never leak), perp stats row (funding
// with payer direction + annualized, open interest, 24h volume), a live order-book depth
// ladder (hyperliquidOrderbookProvider, WIRE coin again), the user's
// existing position/holding when any, and a pinned Invest CTA into the
// order slip (the other side, Short or Sell, sits beside it as a quiet
// secondary button).
//
// Stock tokens (kHlStockSymbols) carry the honest-labeling disclaimer:
// these are Hyperliquid-listed tokens TRACKING an equity, not the
// exchange-traded share — prices can diverge, and we say so.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/chart_drawing.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/chart_drawings_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_candles_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/screens/home/components/action_pill.dart'
    show greenColor, redColor;
import 'package:kute/screens/hyperliquid/components/hl_position_detail_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_history.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_intervals.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_opening.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_stats.dart';
import 'package:kute/screens/hyperliquid/components/hl_tick_price.dart';
import 'package:kute/screens/hyperliquid/components/hl_watch_star.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/app_card.dart';
import 'package:kute/screens/shared/components/sheet_detail_row.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart'
    show HlTrade;
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/screens/ledger/ledger_actions.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

// ───────────────────────────── sheet ─────────────────────────────

class HlMarketDetailSheet extends ConsumerStatefulWidget {
  final HlMarket market;

  /// When set, the sheet belongs to that Ledger: Invest and Short open the
  /// Ledger order sheet, and the hot wallet's exposure and fills stay out
  /// of the chart and the CTAs. Market data is public and shared.
  final String? ledgerWalletId;

  /// Where the market was opened from (market_list | search | sal |
  /// portfolio | ledger | deep_link …). Analytics only.
  final String source;

  const HlMarketDetailSheet(
      {super.key,
      required this.market,
      this.ledgerWalletId,
      this.source = 'market_list'});

  static const routeName = 'hyperliquid-market-detail-sheet';

  static void show(BuildContext context,
      {required HlMarket market,
      String? ledgerWalletId,
      String source = 'market_list'}) {
    VenueAnalytics.rememberHlMarkets([market]);
    TrackingService.hyperliquidMarketViewed(
      coin: market.coin,
      kind: market.isSpot ? 'spot' : 'perp',
      extra: {
        'entry_source': source,
        'wallet_kind': ledgerWalletId == null ? 'hot' : 'ledger',
      },
    );
    // Drop active focus (search field) so closing the sheet doesn't
    // re-summon the keyboard — same fix as the PM detail sheet.
    FocusManager.instance.primaryFocus?.unfocus();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        settings: const RouteSettings(name: routeName),
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.4),
        fullscreenDialog: true,
        transitionDuration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
        reverseTransitionDuration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
        // Still while the order slip (or any sheet) covers it, so its tick
        // animations never share the frames of the slip being scrolled.
        pageBuilder: (_, __, ___) => KuteStillWhenCovered(
          child: HlMarketDetailSheet(
              market: market, ledgerWalletId: ledgerWalletId, source: source),
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
    );
  }

  @override
  ConsumerState<HlMarketDetailSheet> createState() =>
      _HlMarketDetailSheetState();
}

/// The body of a chart screen while its chart is in edit mode, shared by
/// the market sheet and the open-position screen so both edit the same
/// way: the screen hides its header and bottom bar, and the chart takes
/// the whole body, TradingView style. The plot flexes to whatever the
/// chart's top bar, date axis, panes and hint line leave; the tools sit
/// in a rail beside it. Tight gutters, and only the hint line (no
/// controls) reaches into the home-indicator inset.
///
/// [chart] is the screen's [HlCandleChart] with `fillHeight: true`, under
/// the same key it has while reading, so its state (edit mode, the armed
/// tool, the selection) carries across the change of layout.
class HlChartEditBody extends StatelessWidget {
  final Widget chart;

  const HlChartEditBody({super.key, required this.chart});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(8.w, 4.h, 8.w,
            math.max(8.h, MediaQuery.viewPaddingOf(context).bottom - 14)),
        child: chart,
      );
}

/// The freshest descriptor of the market a sheet was opened on: the
/// markets provider refreshes every 30 s, and [row] (the list row's
/// snapshot) stands in while it loads. Shared by the market sheet and its
/// About sheet, so both read the same live numbers.
HlMarket hlSheetMarket(WidgetRef ref, HlMarket row) {
  // Keyed on kind AND wire identifier, not the displayed symbol: SPCX
  // exists as both a spot token and a perp, and the by-name lookup
  // searches perps first, so tapping the spot row opened a sheet that
  // called itself Leveraged.
  // The builder-dex catalogue keeps 24h volume, funding and open
  // interest from metas cached for minutes; the open sheet takes them
  // live from the venue's activeAssetCtx channel.
  final ctx = ref
      .watch(hyperliquidActiveAssetCtxProvider(row.wireCoin))
      .valueOrNull;
  final live = ref
      .watch(hyperliquidExactMarketProvider(hlExactMarketKey(row)));
  if (live == null) return hlMarketWithLiveCtx(row, ctx);
  // The live descriptor refreshes price/funding, but its `category`
  // defaults to 'crypto' — the direct-from-HL parse can't classify
  // tokenized equities/commodities. Watching it blindly overwrites the
  // richer classification the browse row carried, which drops BOTH the
  // stock/index logo candidate (parqet) AND the category glyph, so a
  // detail whose list row showed the real SPY logo fell back to the
  // letter badge (user report). Graft the row snapshot's category +
  // iconUrl back when the live copy is at its unclassified default.
  if (live.category == 'crypto' && row.category != 'crypto') {
    return hlMarketWithLiveCtx(
        live.copyWith(
          category: row.category,
          iconUrl: live.iconUrl ?? row.iconUrl,
        ),
        ctx);
  }
  return hlMarketWithLiveCtx(live, ctx);
}

class _HlMarketDetailSheetState extends ConsumerState<HlMarketDetailSheet> {
  /// Consolidated "Details" expander gates the dense secondary sections
  /// (stats strip, funding line, stock disclaimer, order book). Closed by
  /// default so the primary view stays focused on the header + chart +
  /// the user's own position + sticky CTAs — mirrors the Polymarket sheet.

  /// Advanced chart mode (drawing tools + indicator toggles) is active:
  /// the chart expands to dominate the screen, the secondary sections
  /// hide and the sticky CTAs go compact. Reported by HlCandleChart.
  bool _advancedChart = false;

  /// The chart host keeps the editing state, and the body changes shape
  /// around it (scrolling column when reading, bounded column when
  /// editing); a global key carries that state across the change.
  final GlobalKey _chartHostKey = GlobalKey();

  /// Live-price feed hold — acquired in initState, released exactly once
  /// in dispose (nulled to guard a double dispose). This sheet sits on
  /// the root navigator (reachable from global search on any tab), so
  /// the shell's Trading-tab pause must not freeze the header price.
  HlLivePricesNotifier? _livePrices;

  @override
  void initState() {
    super.initState();
    // acquire() BEFORE watchCoins so the coin subscribes on the revived
    // socket even when the shell already paused the feed.
    _livePrices = ref.read(hyperliquidLivePricesProvider.notifier);
    _livePrices!.acquire();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Live mid for the header. The Trading screen owns unwatchAll on
      // its dispose; adding here is additive and idempotent. The wire
      // alias keeps spot / HIP-3 markets streaming (allMids keys by
      // wire name, not display name).
      _livePrices?.watchCoins(
        [widget.market.coin],
        wire: {widget.market.coin: widget.market.wireCoin},
      );
      // The market on screen rides the fast best-bid/ask feed; allMids
      // alone refreshes only every few seconds.
      _livePrices?.focus(widget.market.coin, wire: widget.market.wireCoin);
    });
  }

  @override
  void dispose() {
    _livePrices?.unfocus(widget.market.coin);
    _livePrices?.release();
    _livePrices = null;
    super.dispose();
  }

  HlMarket get market => hlSheetMarket(ref, widget.market);

  /// What Sal is told about this screen: public market facts only.
  AdvisorContext _salContext(HlMarket m) => AdvisorContext(
        surface: 'hl_market_detail',
        marketVenue: 'hyperliquid',
        marketId: m.wireCoin,
        marketDisplayName: m.coin,
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = market;
    final isStock = isHlStockMarket(m);

    final liveMid = ref.watch(hyperliquidLiveMidProvider(m.coin));
    final pricesLive =
        ref.watch(hyperliquidLivePricesProvider.select((s) => s.isLive));
    final price = liveMid ?? (m.midPx > 0 ? m.midPx : m.markPx);

    // Existing exposure on this market. A Ledger sheet shows none of the
    // hot wallet's exposure; its positions live on the Ledger tab.
    HlPerpPosition? position;
    double spotHeld = 0;
    if (widget.ledgerWalletId == null) {
      for (final p in ref.watch(hyperliquidPerpPositionsProvider)) {
        // Positions carry the wire coin ('xyz:TSLA'); a builder-dex
        // position never matched the display coin.
        if (!m.isSpot && p.coin == m.wireCoin) {
          position = p;
          break;
        }
      }
      if (m.isSpot) {
        for (final b in ref.watch(hyperliquidSpotBalancesProvider)) {
          if (b.coin == m.coin) {
            spotHeld = b.total;
            break;
          }
        }
      }
    }

    return Scaffold(
      backgroundColor: context.isDark ? c.gradientBottom : c.background,
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: PlatformSafeArea(
          child: Column(
            children: [
              // ── Header ────────────────────────────────────────────
              // Edit mode hides it: the chart's own slim top bar names
              // the market there, and Done brings the header back.
              if (!_advancedChart)
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
                  child: Row(
                    children: [
                      KuteCircleBackButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      SizedBox(width: 8.w),
                      HlCoinIcon(
                        coin: m.coin,
                        wireCoin: m.wireCoin,
                        category: m.category,
                        iconUrl: m.iconUrl,
                        size: 32,
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // The ticker alone: the kind (Own / Leveraged)
                            // is the Instrument row under Stats, so the
                            // header keeps its room for the title.
                            // Smaller rather than cut, on its one line.
                            FittedTitle(
                              m.coin,
                              key: const ValueKey('hl-detail-title'),
                              maxLines: 1,
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 18.sp,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            SizedBox(height: 2.h),
                            // Wrap (not Row) so the price + change + the
                            // optional 'up to Nx' chip NEVER overflow — on a
                            // wide price (e.g. $29,466.50) the leverage chip
                            // flows to a new line instead of clipping. Only
                            // shown when it fits.
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8.w,
                              runSpacing: 2.h,
                              children: [
                                // The primary text colour at rest; a
                                // tick flashes green or red and fades
                                // back, so the price never sits in a
                                // colour that argues with the change.
                                HlTickPrice(
                                  price: price,
                                  text: formatHlPrice(price,
                                      decimalCap: m.pxDecimalCap),
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                // The change of the price shown beside
                                // it, not of a minutes-old snapshot.
                                Text(
                                  formatHlPct(m.dayChangeAt(price)),
                                  style: TextStyle(
                                    color: m.dayChangeAt(price) >= 0
                                        ? greenColor
                                        : redColor,
                                    fontSize: 13.sp,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                // The price feed gave up reconnecting:
                                // say so instead of painting a frozen
                                // number as if it were live.
                                if (!pricesLive)
                                  HlMetaChip(
                                      text: context.l10n.chartPriceDelayed),
                                // A thinly traded market says so, in
                                // the kind badge's own neutral chip. It
                                // sits on this wrapping line, not beside
                                // the badge: the name row has no room
                                // for it and would cut the ticker.
                                if (m.isLowLiquidity)
                                  const HlLowLiquidityBadge(),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // The watchlist star. Sal's one door on this screen
                      // is the question capsule under this header.
                      HlWatchStar(market: m, size: 22, source: 'detail'),
                    ],
                  ),
                ),

              // ── Body ──────────────────────────────────────────────
              Expanded(
                child: LayoutBuilder(builder: (context, bodyCons) {
                  // Bounded chart (540 with Details
                  // collapsed, 300 once it opens) instead of filling the
                  // whole viewport, and capped at 78% of the body so the
                  // pills under it stay on screen on short phones; Details starts below. Advanced mode still grows it to
                  // dominate. HlCandleChart applies .h internally, so the
                  // value is handed over in design units.
                  if (_advancedChart) {
                    // Editing: the chart alone, the whole screen
                    // (HlChartEditBody, shared with the position screen).
                    return HlChartEditBody(
                      chart: HlCandleChart(
                        key: _chartHostKey,
                        market: m,
                        height: 240,
                        fillHeight: true,
                        showSignals: true,
                        ledgerWalletId: widget.ledgerWalletId,
                        onAdvancedChanged: (on) =>
                            setState(() => _advancedChart = on),
                      ),
                    );
                  }
                  final target = 540.h;
                  // Sal's question sits above the chart: leave it its
                  // room so the pills still land on screen.
                  final salRoom =
                      ref.watch(aiEnabledProvider).asData?.value == false
                          ? 0.0
                          : 72.h;
                  final chartHeight = math.min(
                          target, bodyCons.maxHeight * 0.78 - salRoom) /
                      1.h;
                  return SingleChildScrollView(
                    // Drawing on the chart must not scroll the sheet, so
                    // Advanced mode pins the body until it is switched off.
                    physics: _advancedChart
                        ? const NeverScrollableScrollPhysics()
                        : const BouncingScrollPhysics(),
                    // Same 20.w gutter as the Polymarket detail so the chart
                    // sits inside a visible inset instead of edge to edge.
                    // Editing mode has no pinned bar below, so the tool
                    // row at the foot of the chart clears the home
                    // indicator on its own.
                    padding: EdgeInsets.fromLTRB(
                        20.w,
                        10.h,
                        20.w,
                        24.h +
                            (_advancedChart
                                ? MediaQuery.viewPaddingOf(context).bottom
                                : 0)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sal's question for this market, right under the
                        // header's price: the one Sal door on this screen.
                        SalQuestionCapsule(
                          advisorContext: _salContext(m),
                          chipSignals: salSignalsForHlMarket(m),
                          padding: EdgeInsets.only(bottom: 14.h),
                        ),
                        // Bounded chart (see chartHeight above); Advanced
                        // mode expands it (animated inside the chart).
                        HlCandleChart(
                          key: _chartHostKey,
                          market: m,
                          height: chartHeight,
                          showSignals: true,
                          // No change / LIVE row under the pills here.
                          showSummary: false,
                          ledgerWalletId: widget.ledgerWalletId,
                          onAdvancedChanged: (on) =>
                              setState(() => _advancedChart = on),
                        ),
                        SizedBox(height: 20.h),
                        // The user's own exposure stays ABOVE the Details
                        // expander — it's the one thing worth surfacing at a
                        // glance. Its money amounts (PnL / holding value) honour
                        // the Bitcoin denomination setting; the market quote
                        // prices below stay in USD.
                        if (!_advancedChart && position != null) ...[
                          _PositionSummaryCard(
                              position: position, funding: m.funding),
                          SizedBox(height: 16.h),
                        ] else if (!_advancedChart &&
                            m.isSpot &&
                            spotHeld > 0) ...[
                          Container(
                            padding: EdgeInsets.all(14.w),
                            decoration: BoxDecoration(
                              color: c.surface.withValues(alpha: 0.96),
                              borderRadius: BorderRadius.circular(14.r),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.account_balance_wallet_outlined,
                                    color: kHlAccent, size: 18.sp),
                                SizedBox(width: 10.w),
                                Expanded(
                                  child: Text(
                                    '${context.l10n.chartYouHold} ${formatHlSize(spotHeld)} ${m.coin} ≈ ${formatPolyAmount(ref, spotHeld * price)}',
                                    style: TextStyle(
                                      color: c.textPrimary,
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 16.h),
                        ],

                        // About, whose sheet holds the stats and
                        // long-form details, so the chart keeps the
                        // screen.
                        if (!_advancedChart)
                          _buildAboutRow(c, m, isStock, position),
                        SizedBox(height: 16.h),
                      ],
                    ),
                  );
                }),
              ),

              // ── Sticky CTAs ───────────────────────────────────────
              // Blurred backdrop + top border + bottom SafeArea so the
              // buttons clear the home indicator (mirrors PM's sticky bar).
              // Rendered whenever the chart is not being edited, like PM's
              // Yes/No pair: the order slip runs the capability / geo gate
              // on tap and explains when investing is unavailable. Gating
              // the whole bar on the runtime capability here hid it while
              // the policy was still loading or denied, which read as
              // "there is no Invest button". Advanced (editing) mode drops
              // the bar so the chart takes the whole sheet; Done brings it
              // back.
              if (!_advancedChart)
                ClipRect(
                  child: KuteBlur(
                    sigmaX: 18,
                    sigmaY: 18,
                    child: Container(
                      padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 8.h),
                      decoration: BoxDecoration(
                        color: (context.isDark ? c.surface : c.background)
                            .withValues(alpha: 0.55),
                        border: Border(
                          top: BorderSide(color: c.borderSubtle, width: 0.5),
                        ),
                      ),
                      // The inset as seen below PlatformSafeArea, not the
                      // screen's own context above it: Android's
                      // PlatformSafeArea already padded the bottom (so this
                      // reads zero there), iOS leaves it to the bar.
                      // Reading it above the SafeArea added the navigation
                      // bar twice on Android.
                      child: Builder(
                        builder: (context) => Padding(
                          padding: EdgeInsets.only(
                              bottom: math.max(
                                  0.0,
                                  MediaQuery.viewPaddingOf(context).bottom -
                                      8.h)),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildInvestRow(m, spotHeld),
                            ],
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
    );
  }

  /// The pinned Invest row: ONE green door into the order slip (buy /
  /// long, the same marketUp grammar as the Polymarket Yes button), with
  /// the other side demoted to a quiet neutral button beside it so
  /// shorting a perp, or selling a spot token the user holds, stays one
  /// tap away without competing with Invest. The slip has no side toggle
  /// (its side is fixed on open), so that second button is what keeps
  /// Short / Sell reachable.
  ///
  /// The Ledger Investing tab opens this sheet with a wallet pinned, so
  /// the CTA routes through LedgerActions, which hands the SAME order slip
  /// that wallet id: one ticket, signed by the device instead of the hot
  /// account.
  Widget _buildInvestRow(HlMarket m, double spotHeld) {
    final l10n = context.l10n;
    final showOtherSide = !m.isSpot || spotHeld > 0;
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: AppButton(
            text: l10n.hlMarketInvestCta,
            color: AppColors.marketUp,
            compact: _advancedChart,
            onPressed: () => _openOrderSlip(m, isLong: true),
          ),
        ),
        if (showOtherSide) ...[
          SizedBox(width: 10.w),
          Expanded(
            child: AppButton(
              text: m.isSpot ? l10n.sell : l10n.shortLabel,
              variant: m.isSpot
                  ? AppButtonVariant.secondary
                  : AppButtonVariant.primary,
              color: m.isSpot ? null : AppColors.marketDown,
              compact: _advancedChart,
              onPressed: () => _openOrderSlip(m, isLong: false),
            ),
          ),
        ],
      ],
    );
  }

  void _openOrderSlip(HlMarket m, {required bool isLong}) {
    // Coarse params only: the surface, the instrument kind and the side.
    final ledgerWalletId = widget.ledgerWalletId;
    TrackingService.track('hl_invest_cta_tapped', params: {
      'source': 'market_detail',
      'kind': m.isSpot ? 'spot' : 'perp',
      'side': isLong ? 'buy' : 'sell',
      'signer': ledgerWalletId == null ? 'hot' : 'ledger',
    });
    if (ledgerWalletId != null) {
      // Device-approved order on the named Ledger; never the hot slip.
      LedgerActions.placeOrder(context, ref,
          walletId: ledgerWalletId, market: m, isBuy: isLong);
      return;
    }
    HlOrderSlipSheet.show(
      context,
      ref,
      market: m,
      isLong: isLong,
      source: 'market_detail',
      entrySource: widget.source,
    );
  }

  /// "About Bitcoin": the one row under the chart, opening the sheet
  /// with the market's Stats and everything the old Details expander
  /// held.
  Widget _buildAboutRow(AppColorsExtension c, HlMarket m, bool isStock,
      HlPerpPosition? position) {
    final name = hlFriendlyName(m.coin) ?? m.unitAssetName ?? m.coin;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        // Once: a second tap while it slides in does not stack another.
        unawaited(OpenOnce.run(
            'hl-about:${m.wireCoin}',
            () => showAppBottomSheet<void>(
                  context: context,
                  builder: (sheetContext) => _HlAboutSheet(
                    title: sheetContext.l10n.investingAboutMarket(name),
                    market: widget.market,
                    isStock: isStock,
                    position: position,
                  ),
                )));
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14.h),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: c.borderSubtle, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.investingAboutMarket(name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.settingsTitle(context),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: c.textTertiary, size: 22.sp),
          ],
        ),
      ),
    );
  }
}

/// The sheet behind the "About (name)" row: first the market's Stats
/// (label / value pairs in two columns: 24h volume, open interest,
/// funding, maximum leverage, mark, 24h high and low, spread), then what
/// the market is and how it trades right now: the contract rows, the
/// funding payer line and countdown, the stock notice, the order book and
/// the recent trades. Its requests (the 24h candles, the book, the
/// trades) only run while it is open.
class _HlAboutSheet extends ConsumerWidget {
  final String title;

  /// The row snapshot the market sheet was opened on.
  final HlMarket market;
  final bool isStock;
  final HlPerpPosition? position;

  const _HlAboutSheet({
    required this.title,
    required this.market,
    required this.isStock,
    required this.position,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final m = hlSheetMarket(ref, market);
    final position = this.position;
    final l10n = context.l10n;

    // 24h high/low from the fixed 1h × 24h candle window. Spot-pair
    // candles arrive in raw pair units: rescaled onto display units like
    // the chart does.
    double? hi24, lo24;
    final raw = ref
        .watch(hyperliquidLiveCandlesProvider((
          wireCoin: m.wireCoin,
          interval: '1h',
          windowHours: 24,
          exact: false,
        )))
        .valueOrNull
        ?.candles;
    if (raw != null && raw.isNotEmpty) {
      final displayPx = m.midPx > 0 ? m.midPx : m.markPx;
      final scaled = rescaleCandlesToDisplay(raw, displayPx);
      var hi = scaled.first.high, lo = scaled.first.low;
      for (final k in scaled) {
        if (k.high > hi) hi = k.high;
        if (k.low < lo) lo = k.low;
      }
      if (hi > 0 && lo > 0) {
        hi24 = hi;
        lo24 = lo;
      }
    }
    // Top-of-book spread: a narrow select, so only a spread change (not
    // every 250 ms depth tick) rebuilds the sheet.
    final spreadPct = ref.watch(hyperliquidOrderbookProvider(m.wireCoin)
        .select((a) => a.valueOrNull?.spreadPct));
    final stats = [
      ...hlMarketStats(l10n, m),
      if (hi24 != null)
        HlStat(l10n.hl24hHigh, formatHlPrice(hi24, decimalCap: m.pxDecimalCap)),
      if (lo24 != null)
        HlStat(l10n.hl24hLow, formatHlPrice(lo24, decimalCap: m.pxDecimalCap)),
      if (spreadPct != null)
        HlStat(l10n.hlSpread,
            '${spreadPct.toStringAsFixed(spreadPct >= 0.1 ? 2 : 3)}%'),
    ];
    return AppBottomSheetContainer(
      maxHeight: 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: title,
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
                    children: [
                      HlStatsSection(title: l10n.investingStats, stats: stats),
                      SizedBox(height: 12.h),
                      SheetDetailRow(
                        label: context.l10n.chartInstrument,
                        value: hlKindLabel(context.l10n, isSpot: m.isSpot),
                      ),
                      if (position != null) ...[
                        SheetDetailRow(
                            label: context.l10n.chartPositionSize,
                            value:
                                '${formatHlSize(position.szi.abs())} ${m.coin}'),
                        SheetDetailRow(
                            label: context.l10n.chartLeverage,
                            value: '${position.leverageValue}×'),
                        if (position.liquidationPx != null &&
                            position.liquidationPx! > 0)
                          SheetDetailRow(
                              label: context.l10n.chartLiquidationPrice,
                              value: formatHlPrice(position.liquidationPx!,
                                  decimalCap: m.pxDecimalCap)),
                      ],
                      SizedBox(height: 14.h),
                      if (!m.isSpot && m.funding != null) ...[
                        // Who pays whom, and when: funding settles on
                        // the hour.
                        Text(
                          '${m.funding! >= 0 ? context.l10n.hlLongsPayShorts : context.l10n.hlShortsPayLongs} '
                          '${(m.funding!.abs() * 100).toStringAsFixed(4)}%/hr '
                          '(≈ ${(m.funding!.abs() * 24 * 365 * 100).toStringAsFixed(1)}% annualized) · '
                          '${context.l10n.hlFundingIn(60 - DateTime.now().minute)}',
                          style: TextStyle(
                            color: c.textTertiary,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (isStock) ...[
                        SizedBox(height: 12.h),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 12.w, vertical: 10.h),
                          decoration: BoxDecoration(
                            color: c.surfaceLight,
                            borderRadius: BorderRadius.circular(10.r),
                            border: Border.all(color: c.border, width: 0.5),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline_rounded,
                                  color: c.textTertiary, size: 14.sp),
                              SizedBox(width: 8.w),
                              Expanded(
                                child: Text(
                                  m.isSpot
                                      ? '${m.coin} here is a Hyperliquid-listed token tracking the underlying asset; its price can differ from the stock exchange price.'
                                      : '${m.coin} here is a leveraged Hyperliquid contract tracking the underlying asset; its price can differ from the stock exchange price, and it carries leverage, funding and liquidation risk.',
                                  style: TextStyle(
                                    color: c.textSecondary,
                                    fontSize: 12.sp,
                                    height: 1.4,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      SizedBox(height: 16.h),
                      HlOrderBookSection(market: m),
                      SizedBox(height: 16.h),
                      HlRecentTradesSection(market: m),
                    ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── position summary ─────────────────────────

class _PositionSummaryCard extends ConsumerWidget {
  final HlPerpPosition position;

  /// The market's current hourly funding rate, when known: adds the
  /// "next funding" line.
  final double? funding;
  const _PositionSummaryCard({required this.position, this.funding});

  /// "Next funding in 23 min: you pay about $0.12": the countdown to the
  /// top of the hour and what this position pays or receives there at
  /// the current rate. Null when the rate is unknown or zero.
  String? _fundingLine(BuildContext context, WidgetRef ref) {
    final rate = funding;
    if (rate == null || rate == 0 || position.szi == 0) return null;
    final now = DateTime.now();
    final minutes =
        hlNextFundingTime(now).difference(now).inMinutes.clamp(1, 60);
    final estimate = hlFundingEstimate(
      positionValue: position.positionValue,
      isLong: position.isLong,
      rate: rate,
    );
    final time = context.l10n.hlMinutesShort(minutes);
    // The person's own money: the Bitcoin denomination setting applies.
    final amount = estimate.amount < 0.01
        ? '<${formatPolyAmount(ref, 0.01)}'
        : formatPolyAmount(ref, estimate.amount);
    return estimate.pays
        ? context.l10n.hlNextFundingPay(time, amount)
        : context.l10n.hlNextFundingReceive(time, amount);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final pos = position;
    final sideColor = pos.isLong ? greenColor : redColor;
    final liveMid = ref.watch(hyperliquidLiveMidProvider(pos.coin));
    final pnl =
        liveMid != null ? (liveMid - pos.entryPx) * pos.szi : pos.unrealizedPnl;
    final pnlColor = pnl >= 0 ? greenColor : redColor;
    final fundingLine = _fundingLine(context, ref);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        HlPositionDetailSheet.show(
          context,
          position: pos,
          market: ref.read(hyperliquidAccountMarketProvider(pos.coin)),
        );
      },
      child: Container(
        padding: EdgeInsets.all(14.w),
        decoration: AppDecorations.card(context),
        child: Row(
          children: [
            HlSideChip(
                text: pos.isLong
                    ? context.l10n.longLabel
                    : context.l10n.shortLabel,
                color: sideColor),
            SizedBox(width: 8.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.chartYourInvestment,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    '${pos.isLong ? context.l10n.chartBoughtAt : context.l10n.chartSoldAt} ${formatHlPrice(pos.entryPx, decimalCap: ref.watch(hyperliquidAccountMarketProvider(pos.coin))?.pxDecimalCap)}',
                    style: TextStyle(
                      color: c.textTertiary,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (fundingLine != null) ...[
                    SizedBox(height: 2.h),
                    Text(
                      fundingLine,
                      style: TextStyle(
                        color: c.textTertiary,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                RollingNumberText(
                  // The user's PnL is their money — honour the Bitcoin
                  // denomination setting (fiat OR sats/BTC), like Predictions.
                  // The sign stays explicit so gains read `+…`.
                  text:
                      '${pnl >= 0 ? '+' : '−'}${formatPolyAmount(ref, pnl.abs())}',
                  style: TextStyle(
                    color: pnlColor,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  context.l10n.chartManage,
                  style: TextStyle(
                    color: kHlAccent,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── chart ─────────────────────────────

class HlCandleChart extends ConsumerStatefulWidget {
  final HlMarket market;
  final double height;

  /// False keeps the hot wallet's fills and entry line off the chart
  /// (a Ledger sheet shares the market, not the account).
  final bool showOwnActivity;
  final String? ledgerWalletId;

  /// Notifies the host when Advanced mode toggles so it can expand the
  /// chart real estate (hide sections, compact CTAs, grow [height]).
  final ValueChanged<bool>? onAdvancedChanged;

  /// When true the plot flexes to the height the parent leaves after the
  /// fixed rows; the parent must be bounded. [height] is then ignored.
  final bool fillHeight;

  /// The market detail sheet's chart: the thin buy/sell pressure strip
  /// under the plot and the optional market-signal layers (off until
  /// switched on in the Indicators list). False everywhere else, where
  /// the chart is exactly as before.
  final bool showSignals;

  /// Whether tapping the position's entry or liquidation tag opens the
  /// position's screen. False on that screen itself, where the tag would
  /// stack a second copy of it.
  final bool positionTagOpensPosition;

  /// False drops the readout row under the interval pills (the change
  /// over the visible span and the LIVE dot): the Investing market screen,
  /// where the Sal question row takes its place under the chart. The
  /// scrub card still names a scrubbed bar.
  final bool showSummary;

  const HlCandleChart({
    super.key,
    required this.market,
    this.height = 240,
    this.showOwnActivity = true,
    this.ledgerWalletId,
    this.onAdvancedChanged,
    this.fillHeight = false,
    this.showSignals = false,
    this.positionTagOpensPosition = true,
    this.showSummary = true,
  });

  @override
  ConsumerState<HlCandleChart> createState() => _HlCandleChartState();
}

class _HlCandleChartState extends ConsumerState<HlCandleChart> {
  String get _marketKey => hlChartDrawingMarketKey(widget.market);
  ChartPreferencesNotifier get _preferences =>
      ref.read(hlChartPreferencesProvider(_marketKey).notifier);

  /// Style and interval are one global layout for every Hyperliquid
  /// market, like a TradingView layout (see hlChartLayoutProvider).
  HlChartStyle get _style =>
      HlChartStyle.fromName(ref.read(hlChartLayoutProvider).style);

  (IconData, String) _styleLook(HlChartStyle style) => switch (style) {
        HlChartStyle.candles => (
            Icons.candlestick_chart_rounded,
            context.l10n.chartStyleCandles
          ),
        HlChartStyle.hollow => (
            Icons.crop_square_rounded,
            context.l10n.chartStyleHollow
          ),
        HlChartStyle.bars => (
            Icons.bar_chart_rounded,
            context.l10n.chartStyleBars
          ),
        HlChartStyle.heikinAshi => (
            Icons.stacked_bar_chart_rounded,
            context.l10n.chartStyleHeikinAshi
          ),
        HlChartStyle.line => (
            Icons.show_chart_rounded,
            context.l10n.chartStyleLine
          ),
        HlChartStyle.area => (
            Icons.area_chart_rounded,
            context.l10n.chartStyleArea
          ),
        HlChartStyle.baseline => (
            Icons.align_horizontal_center_rounded,
            context.l10n.chartStyleBaseline
          ),
      };

  /// One sheet with every chart style named, instead of two pills that
  /// only knew line and candles.
  Future<void> _pickChartStyle() async {
    HapticFeedback.selectionClick();
    final current = _style;
    final picked = await showAppBottomSheet<HlChartStyle>(
      context: context,
      builder: (sheetContext) => AppBottomSheetContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBottomSheetHeader(
              title: context.l10n.chartStyleTitle,
              trailing: IconButton(
                tooltip:
                    MaterialLocalizations.of(sheetContext).closeButtonTooltip,
                onPressed: () => Navigator.of(sheetContext).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            for (final style in HlChartStyle.values)
              AppBottomSheetListTile(
                title: _styleLook(style).$2,
                icon: _styleLook(style).$1,
                isSelected: style == current,
                onTap: () => Navigator.of(sheetContext).pop(style),
              ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
    if (picked == null || !mounted || picked == current) return;
    // Only how the bars are drawn changes: the interval, the view and the
    // history stay, on this market and every other one.
    ref.read(hlChartLayoutProvider.notifier).setStyle(picked.name);
    VenueAnalytics.settingChanged(
      'chart_type_changed',
      setting: 'chart_style',
      value: picked.name,
      extra: {
        'type': picked.name,
        'coin': widget.market.coin,
        ...VenueAnalytics.hlAssetParams(widget.market.coin),
      },
    );
  }

  /// Interval the live tape is actually painted at (the seed may refine a
  /// sparse market), so history pages match it.
  String? _paintedInterval;

  /// Memoized live tape with older history pages in front of it.
  List<HyperliquidCandle>? _mergeOlder;
  List<HyperliquidCandle>? _mergeLive;
  List<HyperliquidCandle>? _merged;

  /// The interval this sheet OPENS on: the saved one, or a coarser one
  /// when the saved one is too thinly traded on this market to read
  /// (hl_chart_opening.dart). Never saved: the layout stays the user's.
  final HlChartOpening _opening = HlChartOpening();

  HlLiveCandleKey _candleKey(HlCandleInterval iv) => (
        wireCoin: widget.market.wireCoin,
        interval: iv.interval,
        windowHours: hlCandleWindowHours(iv),
        exact: true,
      );

  /// The interval row: one choice for every style and every market.
  /// settingChanged sends only real changes.
  void _selectCandleInterval(HlCandleInterval iv) {
    // A pick in this sheet ends the opening step for good, the saved
    // interval included (the sheet may be showing a coarser one).
    final stepped = _opening.stepped;
    if (stepped || !_opening.settled) setState(_opening.userPicked);
    if (ref.read(hlChartLayoutProvider).interval == iv.interval) {
      if (stepped) HapticFeedback.selectionClick();
      return;
    }
    HapticFeedback.selectionClick();
    ref.read(hlChartLayoutProvider.notifier).setInterval(iv.interval);
    VenueAnalytics.settingChanged(
      'chart_timeframe_changed',
      setting: 'candle_interval',
      value: iv.label,
      extra: {
        'timeframe': iv.label,
        'coin': widget.market.coin,
        ...VenueAnalytics.hlAssetParams(widget.market.coin),
      },
    );
  }

  /// [older] history in front of the [live] tape, cut where the live
  /// tape starts. Memoized on both identities.
  List<HyperliquidCandle> _withHistory(
    List<HyperliquidCandle> older,
    List<HyperliquidCandle> live,
  ) {
    if (older.isEmpty || live.isEmpty) return live;
    if (identical(older, _mergeOlder) && identical(live, _mergeLive)) {
      return _merged!;
    }
    final liveStart = live.first.openTime.millisecondsSinceEpoch;
    var lo = 0, hi = older.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (older[mid].openTime.millisecondsSinceEpoch < liveStart) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    _mergeOlder = older;
    _mergeLive = live;
    _merged = lo == 0
        ? live
        : List.unmodifiable([...older.take(lo), ...live]);
    return _merged!;
  }

  bool _editingNote = false;

  // ── Advanced drawing mode ────────────────────────────────────────
  /// Drawing mode on/off (the "Advanced" pill). Drawings stay VISIBLE
  /// outside the mode; only placing/selecting/editing needs it on.
  bool _drawingMode = false;

  /// The armed tool. Null = select/edit. Stays armed across placements
  /// (standard trading-app behavior) so consecutive tap-drags keep
  /// placing; disarmed only by re-tapping the pill, picking another
  /// tool, tapping Done, or hitting the per-market drawings cap.
  ChartDrawingTool? _armedTool;

  /// ARGB of the armed color; null = the neutral theme default.
  int? _armedColorValue;

  String? _selectedDrawingId;

  /// Last non-empty candle set actually shown. While a newly-picked
  /// timeframe's window is still loading, the chart keeps painting these
  /// instead of flashing a skeleton — and once the new data lands the
  /// line morphs from this shape to the new one (see
  /// HlCandlestickChart.morphKey). Cold start still shows the skeleton.
  List<HyperliquidCandle>? _shownCandles;

  /// The chart, flexed to the remaining height when [HlCandleChart.fillHeight].
  Widget _flexed(Widget chart) =>
      widget.fillHeight ? Expanded(child: chart) : chart;

  /// The chart was panned or pinched past its oldest bar: load one page
  /// of older bars in front of it (HlChartHistory throttles and caches).
  Future<void> _loadMoreHistory() async {
    final shown = _shownCandles;
    final interval = _paintedInterval;
    if (shown == null || shown.isEmpty || interval == null) return;
    final added = await HlChartHistory.loadOlder(
      wireCoin: widget.market.wireCoin,
      interval: interval,
      intervalMinutes: hlIntervalMinutes(interval),
      beforeMs: shown.first.openTime.millisecondsSinceEpoch,
    );
    if (!mounted || added <= 0) return;
    setState(() {});
    TrackingService.track('chart_history_extended', params: {
      'coin': widget.market.coin,
      'interval': interval,
      'bars': added,
    });
  }


  /// Memoized per-market fills, keyed on the provider list's identity.
  /// The sheet rebuilds on every live price tick; re-running the .where()
  /// each build would hand the painter a fresh list identity per tick and
  /// defeat its cheap shouldRepaint.
  List<HlFill>? _fillsForMarket;
  List<HlFill>? _fillsSource;

  /// Memoized trade lines (position + working orders), keyed on the
  /// source list identities so a live tick does not hand the painter a
  /// fresh list and defeat its repaint check.
  List<ChartTradeLine> _tradeLines = const [];
  Object? _tradeLinesKey;
  bool _movingOrder = false;


  @override
  void didUpdateWidget(covariant HlCandleChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (hlChartDrawingMarketKey(oldWidget.market) != _marketKey) {
      _shownCandles = null;
      _fillsSource = null;
      _fillsForMarket = null;
      _armedTool = null;
      _selectedDrawingId = null;
      _paintedInterval = null;
      _opening.reset();
      _mergeOlder = null;
      _mergeLive = null;
      _merged = null;
      _signalsKey = null;
      _signals = ChartSignals.none;
      _signalTargets = const {};
      _flipsSource = null;
      _flips = const [];
    }
  }

  // ─────────────────────── trade lines (orders on the chart) ─────────

  List<ChartTradeLine> _tradeLinesFor(
    HlPerpPosition? position,
    List<HlOpenOrder> orders, {
    required bool editable,
  }) {
    final key = (position, orders, editable, widget.market.wireCoin);
    if (_tradeLinesKey == key) return _tradeLines;
    final cap = widget.market.pxDecimalCap;
    // Every tag on the chart in one format: the decimals the market's
    // price is written with (a far liquidation reads "$1.5", not "$1.486"
    // beside "$7,748.3").
    final reference = widget.market.midPx > 0
        ? widget.market.midPx
        : widget.market.markPx;
    String px(double v) => formatHlPriceLike(v, reference, decimalCap: cap);
    final lines = <ChartTradeLine>[];
    if (position != null && position.entryPx > 0) {
      lines.add(ChartTradeLine(
        id: 'position',
        kind: ChartTradeLineKind.entry,
        price: position.entryPx,
        label: context.l10n.hlChartEntry,
        detail: px(position.entryPx),
        isBuy: position.isLong,
      ));
      final liq = position.liquidationPx;
      if (liq != null && liq.isFinite && liq > 0) {
        lines.add(ChartTradeLine(
          id: 'liq',
          kind: ChartTradeLineKind.liquidation,
          price: liq,
          label: context.l10n.hlChartLiq,
          detail: px(liq),
          isBuy: position.isLong,
        ));
      }
    }
    for (final o in orders) {
      if (o.coin != widget.market.wireCoin && o.coin != widget.market.coin) {
        continue;
      }
      final size = formatHlSize(o.sz);
      if (o.isTrigger) {
        final trigger = o.triggerPx;
        if (trigger == null || trigger <= 0) continue;
        final tpsl = o.tpsl;
        lines.add(ChartTradeLine(
          id: 'order:${o.oid}',
          kind: tpsl == 'tp'
              ? ChartTradeLineKind.takeProfit
              : ChartTradeLineKind.stopLoss,
          price: trigger,
          label: o.isTrailingStop
              ? context.l10n.hlChartTrail
              : tpsl == 'tp'
                  ? 'TP'
                  : tpsl == 'sl'
                      ? 'SL'
                      : context.l10n.hlChartStop,
          detail: o.isPositionTpsl ? px(trigger) : '$size @ ${px(trigger)}',
          isBuy: o.isBuy,
          editable: editable && !o.isTrailingStop && tpsl != null,
        ));
      } else if (o.limitPx > 0) {
        lines.add(ChartTradeLine(
          id: 'order:${o.oid}',
          kind: ChartTradeLineKind.limit,
          price: o.limitPx,
          label: o.isBuy ? context.l10n.buy : context.l10n.sell,
          detail: '$size @ ${px(o.limitPx)}',
          isBuy: o.isBuy,
          editable: editable,
        ));
      }
    }
    _tradeLinesKey = key;
    _tradeLines = lines;
    return lines;
  }

  HlOpenOrder? _orderForLine(String id, List<HlOpenOrder> orders) {
    if (!id.startsWith('order:')) return null;
    final oid = int.tryParse(id.substring(6));
    for (final o in orders) {
      if (o.oid == oid) return o;
    }
    return null;
  }

  List<HlOpenOrder> _hotOrders() =>
      ref.read(hyperliquidTradingProvider).valueOrNull?.openOrders ??
      const <HlOpenOrder>[];

  /// A dragged order line was dropped: confirm the move in the same
  /// words the chart showed, take a fresh approval bound to exactly this
  /// order and price, then let the venue swap the order atomically.
  Future<void> _moveOrder(String id, double rawPx) async {
    if (_movingOrder || widget.ledgerWalletId != null) return;
    final order = _orderForLine(id, _hotOrders());
    if (order == null) return;
    final market = widget.market;
    final double newPx;
    try {
      newPx = double.parse(roundPrice(rawPx,
          szDecimals: market.szDecimals, isSpot: market.isSpot));
    } catch (_) {
      return;
    }
    final oldPx =
        order.isTrigger ? (order.triggerPx ?? order.limitPx) : order.limitPx;
    if ((newPx - oldPx).abs() <= oldPx * 1e-6) return;
    final cap = market.pxDecimalCap;
    final label = order.isTrigger
        ? (order.tpsl == 'tp'
            ? context.l10n.hlTakeProfit
            : context.l10n.hlStopLoss)
        : (order.isBuy ? context.l10n.hlBuyLimit : context.l10n.hlSellLimit);
    _movingOrder = true;
    try {
      final confirmed = await showAppBottomSheet<bool>(
        context: context,
        builder: (sheetContext) => AppBottomSheetContainer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppBottomSheetHeader(
                title: context.l10n.chartMoveOrderTitle,
                subtitle: '$label · ${formatHlSize(order.sz)} ${market.coin}\n'
                    '${formatHlPrice(oldPx, decimalCap: cap)} → ${formatHlPrice(newPx, decimalCap: cap)}',
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8.h),
                child: AppBottomSheetButton(
                  text: context.l10n.chartMoveOrderCta,
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                ),
              ),
              AppBottomSheetTextButton(
                text: context.l10n.cancel,
                onPressed: () => Navigator.of(sheetContext).pop(false),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
      final walletId = pickSpendingWallet(ref.read(settingsProvider))?.id;
      if (walletId == null) return;
      final tpsl = order.isTrigger ? order.tpsl : null;
      final grant = await requireFreshAuthGrant(
        context,
        ref,
        intent: HlIntents.modify(
          walletId: walletId,
          market: market,
          oid: order.oid,
          isLong: order.isBuy,
          size: order.sz,
          px: newPx,
          reduceOnly: order.reduceOnly,
          tif: order.tif,
          tpsl: tpsl,
          isMarket: order.isMarketTrigger,
        ),
        reason: context.l10n.stepUpReasonOrder('${market.coin} · $label'),
        amountUsd: order.sz * newPx,
      );
      if (grant == null || !mounted) return;
      try {
        await ref.read(hyperliquidTradingProvider.notifier).modifyOrder(
            market: market, order: order, newPx: newPx, grant: grant);
        if (!mounted) return;
        HapticFeedback.mediumImpact();
        showMessageSnackBar(
          context: context,
          message: context.l10n
              .chartOrderMoved(formatHlPrice(newPx, decimalCap: cap)),
          error: false,
        );
      } on AuthGrantException catch (e) {
        if (mounted) {
          await handleGrantFailure(context, e, action: SensitiveAction.hlOrder);
        }
      } catch (e) {
        if (!mounted) return;
        showMessageSnackBar(
          context: context,
          message: userErrorCopy(context, e,
              fallback: context.l10n.chartOrderMoveFailed),
          error: true,
        );
      }
    } finally {
      _movingOrder = false;
    }
  }

  /// A tag was tapped: the position opens its own sheet; an order opens
  /// the working-orders list, where it can be cancelled.
  void _onTradeLineTapped(String id, HlPerpPosition? position) {
    if (id == 'position' || id == 'liq') {
      if (position == null || !widget.positionTagOpensPosition) return;
      HlPositionDetailSheet.show(
        context,
        position: position,
        market: widget.market,
        ledgerWalletId: widget.ledgerWalletId,
      );
      return;
    }
    if (widget.ledgerWalletId != null) return;
    unawaited(showHlOpenOrdersSheet(context));
  }

  // ─────────────────────── drawing mode plumbing ───────────────────────

  ChartDrawingsNotifier get _drawingsNotifier => ref.read(
        hlChartDrawingsProvider(hlChartDrawingMarketKey(widget.market))
            .notifier,
      );

  void _toggleDrawingMode() {
    HapticFeedback.selectionClick();
    final entering = !_drawingMode;
    setState(() {
      _drawingMode = entering;
      if (!entering) {
        // Exiting restores normal scrubbing; drawings are already
        // persisted (every mutation writes through).
        _armedTool = null;
        _selectedDrawingId = null;
      }
    });
    if (entering) {
      TrackingService.track(
        'advanced_chart_opened',
        params: {'coin': widget.market.coin},
      );
    }
    widget.onAdvancedChanged?.call(entering);
  }

  void _toggleIndicator(String key) {
    HapticFeedback.selectionClick();
    _preferences.toggleIndicator(key);
    TrackingService.track('indicator_toggled', params: {
      'indicator': key,
      'enabled': ref
          .read(hlChartPreferencesProvider(_marketKey))
          .indicators
          .contains(key),
      'coin': widget.market.coin,
      ...VenueAnalytics.hlAssetParams(widget.market.coin),
    });
  }

  List<(String, String)> get _indicatorChips => [
        ('ma', 'MA 20/50'),
        ('ema', 'EMA 9/21'),
        ('bb', 'BB 20/2'),
        ('vwap', 'VWAP'),
        ('rsi', 'RSI 14'),
        ('macd', 'MACD'),
        ('stoch', 'Stoch 14'),
        ('atr', 'ATR 14'),
        ('vol', context.l10n.chartVolume),
        ('volma', 'Vol MA 20'),
        ('log', context.l10n.chartLogScale),
      ];

  // ─────────────────────── market-signal layers ───────────────────────
  //
  // Optional marks about the market, listed under the indicators and
  // stored with them per market. Every one is off until switched on
  // there, except the pressure strip (on until switched off).

  /// The layers this market can show: (key, title, note). Funding and
  /// open interest exist on perps only; the Predictions layers only where
  /// Predictions is offered, and its levels only for an asset it covers.
  List<(String, String, String)> get _layers {
    if (!widget.showSignals) return const [];
    final l10n = context.l10n;
    final m = widget.market;
    final predictions =
        ref.read(runtimeCapabilitiesProvider).allows('polymarket.browse');
    return [
      (kHlLayerPressureOff, l10n.hlLayerPressure, l10n.hlLayerPressureNote),
      (kHlLayerBigTrades, l10n.hlLayerBigTrades, l10n.hlLayerBigTradesNote),
      if (!m.isSpot) ...[
        (kHlLayerFunding, l10n.hlLayerFunding, l10n.hlLayerFundingNote),
        (kHlLayerOi, l10n.hlLayerOi, l10n.hlLayerOiNote),
      ],
      if (predictions && hlCrowdAssetFor(m) != null)
        (kHlLayerCrowd, l10n.hlLayerCrowd, l10n.hlLayerCrowdNote),
      if (predictions)
        (kHlLayerMacro, l10n.hlLayerMacro, l10n.hlLayerMacroNote),
    ];
  }

  /// A layer is on when its key is stored, except the pressure strip,
  /// whose stored key switches it off.
  static bool _layerOn(Set<String> stored, String key) =>
      key == kHlLayerPressureOff ? !stored.contains(key) : stored.contains(key);

  void _toggleLayer(String key) {
    HapticFeedback.selectionClick();
    final wasOn =
        _layerOn(ref.read(hlChartPreferencesProvider(_marketKey)).indicators, key);
    _preferences.toggleIndicator(key);
    TrackingService.track('indicator_toggled', params: {
      'indicator': key == kHlLayerPressureOff ? 'pressure' : key,
      'enabled': !wasOn,
      'layer': true,
      'coin': widget.market.coin,
      ...VenueAnalytics.hlAssetParams(widget.market.coin),
    });
  }

  /// Funding flips, recomputed when a new history lands.
  Object? _flipsSource;
  List<HlFundingFlip> _flips = const [];

  /// The signals handed to the chart, rebuilt only when an input changes
  /// (the painter repaints on identity), and what a tapped tag opens.
  Object? _signalsKey;
  ChartSignals _signals = ChartSignals.none;
  Map<String, (PolymarketEvent, String)> _signalTargets = const {};

  /// The switched-on layers as one [ChartSignals]. Watches only what the
  /// switched-on layers need, so a chart with none on reads nothing more
  /// than the pressure strip's trade stream.
  ChartSignals _signalsFor(Set<String> stored, double price) {
    if (!widget.showSignals) return ChartSignals.none;
    final m = widget.market;
    final l10n = context.l10n;

    final bigTrades = stored.contains(kHlLayerBigTrades)
        ? ref.watch(hyperliquidTradeFlowProvider(m.wireCoin)
                .select((s) => s.valueOrNull?.bigTrades)) ??
            const <HlBigTrade>[]
        : const <HlBigTrade>[];

    var flips = const <HlFundingFlip>[];
    if (!m.isSpot && stored.contains(kHlLayerFunding)) {
      final history =
          ref.watch(hyperliquidFundingHistoryProvider(m.wireCoin)).valueOrNull;
      if (!identical(history, _flipsSource)) {
        _flipsSource = history;
        _flips = history == null ? const [] : hlFundingFlips(history);
      }
      flips = _flips;
    }

    // Open interest is sampled for as long as the sheet is open, so the
    // signal is ready when its layer is switched on.
    final oi = m.isSpot ? null : ref.watch(hyperliquidOiSignalProvider(m.wireCoin));
    final oiShown = stored.contains(kHlLayerOi) ? oi : null;

    final wantCrowd = stored.contains(kHlLayerCrowd);
    final wantMacro = stored.contains(kHlLayerMacro);
    final crowd = wantCrowd || wantMacro
        ? ref.watch(
            hlCrowdViewProvider(hlCrowdViewKey(hlCrowdAssetFor(m), price)))
        : HlCrowdView.empty;

    final key = (
      bigTrades,
      flips,
      oiShown,
      crowd,
      wantCrowd,
      wantMacro,
      l10n.localeName,
    );
    if (key == _signalsKey) return _signals;
    _signalsKey = key;

    final targets = <String, (PolymarketEvent, String)>{};
    final levels = <ChartSignalLevel>[];
    if (wantCrowd) {
      for (var i = 0; i < crowd.levels.length; i++) {
        final l = crowd.levels[i];
        final id = 'level:$i';
        targets[id] = (l.event, l.kind.name);
        levels.add(ChartSignalLevel(
          id: id,
          price: l.strike,
          label: '${l.kind == HlCrowdKind.reach ? '↑' : '↓'} '
              '${l10n.hlChartCrowdLevel(_crowdPercent(l.chance), _crowdDay(l.day))}',
        ));
      }
    }
    final dates = <ChartSignalDate>[
      for (final f in flips)
        ChartSignalDate(
          timeMs: f.timeMs,
          label: f.longsPay
              ? l10n.hlChartFundingPositive
              : l10n.hlChartFundingNegative,
        ),
    ];
    if (wantMacro) {
      for (var i = 0; i < crowd.dates.length; i++) {
        final d = crowd.dates[i];
        final fed = d.kind == HlMacroKind.fedDecision;
        final id = 'date:$i';
        targets[id] = (d.event, fed ? 'fed_date' : 'inflation_date');
        dates.add(ChartSignalDate(
          timeMs: d.day.millisecondsSinceEpoch,
          label: '${fed ? l10n.hlChartFedDecision : l10n.hlChartUsInflation}'
              ' · ${_crowdDay(d.day)}',
          id: id,
          pinWhenAhead: true,
        ));
      }
    }
    String? caption;
    if (oiShown != null) {
      final pct = formatHlPct(oiShown.change);
      caption = oiShown.rising
          ? l10n.hlChartOiRising(pct, oiShown.minutes)
          : l10n.hlChartOiFalling(pct, oiShown.minutes);
    }
    _signalTargets = targets;
    _signals = ChartSignals(
      levels: levels,
      dates: dates,
      dots: [
        for (final t in bigTrades)
          ChartSignalDot(timeMs: t.timeMs, price: t.price, isBuy: t.isBuy),
      ],
      caption: caption,
    );
    return _signals;
  }

  /// A Predictions chance as Predictions writes it ("36.4%", "<1%").
  static String _crowdPercent(double chance) => formatPolyChance(chance);

  /// The day a Predictions market names, in the app language ("Dec 31").
  String _crowdDay(DateTime day) =>
      DateFormat.MMMd(Localizations.localeOf(context).toString()).format(day);

  /// A Predictions level or macro date was tapped: open its market.
  void _onSignalTapped(String id) {
    final target = _signalTargets[id];
    if (target == null) return;
    TrackingService.track('hl_crowd_market_tapped', params: {
      'coin': widget.market.coin,
      'venue': 'hyperliquid',
      'surface': 'chart',
      'kind': target.$2,
      ...VenueAnalytics.hlAssetParams(widget.market.coin),
    });
    MarketDetailSheet.show(
      context,
      event: target.$1,
      ledgerWalletId: widget.ledgerWalletId,
      source: 'hl_chart',
    );
  }

  /// Indicators sit behind one top-bar button (TradingView's "fx") as a
  /// list that toggles in place, instead of a chip row under the chart.
  Future<void> _pickIndicators() async {
    HapticFeedback.selectionClick();
    await showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) => AppBottomSheetContainer(
        maxHeight: 0.8,
        child: Consumer(
          builder: (context, ref, _) {
            final on =
                ref.watch(hlChartPreferencesProvider(_marketKey)).indicators;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppBottomSheetHeader(
                  title: context.l10n.chartIndicators,
                  trailing: IconButton(
                    tooltip: MaterialLocalizations.of(sheetContext)
                        .closeButtonTooltip,
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.only(bottom: 12.h),
                    children: [
                      for (final (key, label) in _indicatorChips)
                        AppBottomSheetListTile(
                          title: label,
                          subtitle: key == 'vwap'
                              ? context.l10n.chartVwapWindow
                              : null,
                          isSelected: on.contains(key),
                          onTap: () => _toggleIndicator(key),
                        ),
                      // The market-signal layers, in the same list.
                      for (final (key, label, note) in _layers)
                        AppBottomSheetListTile(
                          title: label,
                          subtitle: note,
                          isSelected: _layerOn(on, key),
                          onTap: () => _toggleLayer(key),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _onDrawingPlaced(ChartDrawing drawing) {
    final before = ref
        .read(hlChartDrawingsProvider(hlChartDrawingMarketKey(widget.market)))
        .length;
    if (before >= kMaxDrawingsPerMarket) {
      // At the cap: quietly stop placing — disarm, keep what's drawn.
      // No snackbar; the toolbar pill un-highlighting is the signal.
      if (_armedTool != null) setState(() => _armedTool = null);
      return;
    }
    _drawingsNotifier.add(drawing);
    // No prices in analytics — type + coin only.
    TrackingService.track(
      'drawing_created',
      params: {'type': drawing.tool.name, 'coin': widget.market.coin},
    );
    // One placement per arm (user decision: easy to edit beats fast to
    // spam). The fresh drawing is selected with its handles up, so the
    // very next drag adjusts it rather than dropping another shape;
    // the Tools button re-arms for the next one.
    setState(() {
      _armedTool = null;
      _selectedDrawingId = drawing.id;
    });
  }

  void _armTool(ChartDrawingTool tool) {
    HapticFeedback.selectionClick();
    setState(() {
      _armedTool = _armedTool == tool ? null : tool;
      _selectedDrawingId = null;
    });
  }

  void _pickColor(int? colorValue, String? selectedId) {
    HapticFeedback.selectionClick();
    setState(() => _armedColorValue = colorValue);
    // Recolor the current selection too — the natural expectation when a
    // drawing is highlighted.
    if (selectedId != null) {
      final drawings = ref.read(
        hlChartDrawingsProvider(hlChartDrawingMarketKey(widget.market)),
      );
      for (final d in drawings) {
        if (d.id == selectedId) {
          _drawingsNotifier.update(
            colorValue == null
                ? d.copyWith(clearColor: true)
                : d.copyWith(colorValue: colorValue),
          );
          break;
        }
      }
    }
  }

  /// The rail's tool groups, TradingView style: a group with one tool
  /// arms it on tap; a bigger group opens a flyout naming each tool.
  List<(String, List<ChartDrawingTool>)> get _railGroups => [
        (
          context.l10n.chartToolGroupLines,
          const [
            ChartDrawingTool.trendline,
            ChartDrawingTool.ray,
            ChartDrawingTool.extendedLine,
            ChartDrawingTool.level,
            ChartDrawingTool.horizontalRay,
            ChartDrawingTool.verticalLine,
          ]
        ),
        (
          context.l10n.chartToolFibonacci,
          const [ChartDrawingTool.fibonacci]
        ),
        (
          context.l10n.chartToolGroupShapes,
          const [ChartDrawingTool.rect, ChartDrawingTool.parallelChannel]
        ),
        (
          context.l10n.chartToolGroupPositions,
          const [ChartDrawingTool.longPosition, ChartDrawingTool.shortPosition]
        ),
        (
          context.l10n.chartToolGroupMeasure,
          const [
            ChartDrawingTool.priceRange,
            ChartDrawingTool.dateRange,
            ChartDrawingTool.dateAndPriceRange,
          ]
        ),
        (context.l10n.chartToolGroupNotes, const [ChartDrawingTool.text]),
      ];

  /// The tool each group last armed, so its rail button shows that
  /// tool's icon (TradingView's "last used" behaviour).
  final Map<int, ChartDrawingTool> _lastToolInGroup = {};

  (IconData, String) _toolLook(ChartDrawingTool tool) {
    for (final (t, icon, label) in _drawTools) {
      if (t == tool) return (icon, label);
    }
    return (Icons.draw_rounded, tool.name);
  }

  /// One line under the toolbar that says what the next touch does.
  String _toolbarHint(String? selectedId) {
    final tool = _armedTool;
    if (tool != null) {
      final (_, label) = _toolLook(tool);
      return chartDrawingPointCount(tool) == 1
          ? context.l10n.chartHintTapToPlace(label)
          : context.l10n.chartHintDragToPlace(label);
    }
    if (selectedId != null) return context.l10n.chartHintAdjust;
    return context.l10n.chartHintPickTool;
  }

  /// A group's flyout, opened beside its rail button: every tool with its
  /// name, the armed one ticked. Picking one arms it.
  Future<void> _openToolFlyout(
    BuildContext anchor,
    int group,
    String title,
    List<ChartDrawingTool> tools,
  ) async {
    HapticFeedback.selectionClick();
    final box = anchor.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final c = context.colors;
    final origin = box.localToGlobal(
      Offset(box.size.width + 6, 0),
      ancestor: overlay,
    );
    final picked = await showMenu<ChartDrawingTool>(
      context: context,
      position: RelativeRect.fromRect(
        origin & Size.zero,
        Offset.zero & overlay.size,
      ),
      color: context.isDark ? c.surfaceElevated : Colors.white,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14.r),
        side: BorderSide(color: c.borderSubtle, width: 0.5),
      ),
      items: [
        PopupMenuItem<ChartDrawingTool>(
          enabled: false,
          height: 30,
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 11.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        for (final tool in tools)
          PopupMenuItem<ChartDrawingTool>(
            value: tool,
            height: 44,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _toolLook(tool).$1,
                  size: 18.sp,
                  color:
                      _armedTool == tool ? c.textPrimary : c.textSecondary,
                ),
                SizedBox(width: 12.w),
                Text(
                  _toolLook(tool).$2,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 14.sp,
                    fontWeight: _armedTool == tool
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                if (_armedTool == tool) ...[
                  SizedBox(width: 10.w),
                  Icon(Icons.check_rounded, size: 16.sp, color: c.textPrimary),
                ],
              ],
            ),
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      _lastToolInGroup[group] = picked;
      _armedTool = picked;
      _selectedDrawingId = null;
    });
  }

  List<(ChartDrawingTool, IconData, String)> get _drawTools => [
        (
          ChartDrawingTool.trendline,
          Icons.timeline_rounded,
          context.l10n.chartToolTrendLine,
        ),
        (
          ChartDrawingTool.level,
          Icons.horizontal_rule_rounded,
          context.l10n.chartToolLevel,
        ),
        (
          ChartDrawingTool.ray,
          Icons.north_east_rounded,
          context.l10n.chartToolRay
        ),
        (
          ChartDrawingTool.rect,
          Icons.crop_square_rounded,
          context.l10n.chartToolRectangle,
        ),
        (
          ChartDrawingTool.fibonacci,
          Icons.stacked_line_chart_rounded,
          context.l10n.chartToolFibonacci,
        ),
        (
          ChartDrawingTool.text,
          Icons.text_fields_rounded,
          context.l10n.chartToolText,
        ),
        (
          ChartDrawingTool.horizontalRay,
          Icons.trending_flat_rounded,
          context.l10n.chartToolHorizontalRay,
        ),
        (
          ChartDrawingTool.verticalLine,
          Icons.border_left_rounded,
          context.l10n.chartToolVerticalLine,
        ),
        (
          ChartDrawingTool.extendedLine,
          Icons.line_axis_rounded,
          context.l10n.chartToolExtendedLine,
        ),
        (
          ChartDrawingTool.parallelChannel,
          Icons.drag_handle_rounded,
          context.l10n.chartToolParallelChannel,
        ),
        (
          ChartDrawingTool.longPosition,
          Icons.arrow_circle_up_rounded,
          context.l10n.chartToolLongPosition,
        ),
        (
          ChartDrawingTool.shortPosition,
          Icons.arrow_circle_down_rounded,
          context.l10n.chartToolShortPosition,
        ),
        (
          ChartDrawingTool.priceRange,
          Icons.height_rounded,
          context.l10n.chartToolPriceRange,
        ),
        (
          ChartDrawingTool.dateRange,
          Icons.straighten_rounded,
          context.l10n.chartToolDateRange,
        ),
        (
          ChartDrawingTool.dateAndPriceRange,
          Icons.select_all_rounded,
          context.l10n.chartToolDateAndPriceRange,
        ),
      ];

  Future<void> _editNote(
    ChartDrawingPoint point, {
    ChartDrawing? existing,
  }) async {
    if (_editingNote) return;
    _editingNote = true;
    final marketKey = _marketKey;
    try {
      final text = await showAppBottomSheet<String>(
        context: context,
        builder: (_) => _ChartNoteSheet(initialText: existing?.text ?? ''),
      );
      if (!mounted ||
          _marketKey != marketKey ||
          text == null ||
          text.trim().isEmpty) {
        return;
      }
      final notifier = ref.read(hlChartDrawingsProvider(marketKey).notifier);
      if (existing != null) {
        notifier.update(existing.copyWith(text: text.trim()));
      } else {
        notifier.add(
          ChartDrawing(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            tool: ChartDrawingTool.text,
            points: [point],
            text: text.trim(),
            colorValue: _armedColorValue,
          ),
        );
      }
      TrackingService.track(
        'chart_note_saved',
        params: {'edited': existing != null},
      );
    } finally {
      _editingNote = false;
    }
  }

  // ─────────────────────── edit mode layout (TradingView style) ─────────
  //
  //   [coin  BTC      15m▾  style  fx  undo  redo  Done]   slim top bar
  //   [rail] [            plot, floating context bar  ]
  //   [rail] [                 dates / panes          ]
  //          hint line
  //
  // The tools live in a left rail and the chart settings in one top bar,
  // so the bottom of the sheet is the plot's, not a stack of rows.

  /// One square edit-mode button: a 40 pt target (the floor for these
  /// controls), a tooltip, and a tinted ground while it is on. [more]
  /// adds the corner mark of a rail group that opens a flyout.
  Widget _editIconButton(
    AppColorsExtension c, {
    required IconData icon,
    required String tip,
    required VoidCallback? onTap,
    bool active = false,
    bool more = false,
  }) {
    final color = onTap == null
        ? c.textTertiary.withValues(alpha: 0.4)
        : active
            ? c.textPrimary
            : c.textSecondary;
    return Tooltip(
      message: tip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? c.textPrimary.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 19.sp, color: color),
              if (more)
                Positioned(
                  right: 5,
                  bottom: 5,
                  child: CustomPaint(
                    size: const Size(5, 5),
                    painter: _CornerTickPainter(color),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// A colour choice with a 40 pt target; [current] is the colour of the
  /// selected drawing, or the armed colour when nothing is selected.
  Widget _colorDot(
    AppColorsExtension c,
    int? value,
    String tip,
    String? selectedId,
    int? current,
  ) {
    final color = value == null ? c.textSecondary : Color(value);
    return Tooltip(
      message: tip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _pickColor(value, selectedId),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: current == value
                    ? Border.all(color: c.textPrimary, width: 2)
                    : Border.all(color: c.border, width: 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The interval list behind the top bar's interval button.
  Future<void> _pickInterval(HlCandleInterval current) async {
    HapticFeedback.selectionClick();
    final picked = await showAppBottomSheet<HlCandleInterval>(
      context: context,
      builder: (sheetContext) => AppBottomSheetContainer(
        maxHeight: 0.8,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBottomSheetHeader(
              title: context.l10n.chartInterval,
              trailing: IconButton(
                tooltip:
                    MaterialLocalizations.of(sheetContext).closeButtonTooltip,
                onPressed: () => Navigator.of(sheetContext).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.only(bottom: 12.h),
                children: [
                  for (final iv in kHlCandleIntervals)
                    AppBottomSheetListTile(
                      title: iv.label,
                      isSelected: iv.interval == current.interval,
                      onTap: () => Navigator.of(sheetContext).pop(iv),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _selectCandleInterval(picked);
  }

  /// One undoable step that clears every drawing on this market, after a
  /// confirmation (the undo history only lives while the chart is open).
  Future<void> _removeAllDrawings(int count) async {
    HapticFeedback.selectionClick();
    final confirmed = await showAppBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => AppBottomSheetContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBottomSheetHeader(
              title: context.l10n.chartRemoveAllTitle,
              subtitle: context.l10n.chartRemoveAllBody,
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8.h),
              child: AppBottomSheetButton(
                text: context.l10n.chartRemoveAllCta,
                onPressed: () => Navigator.of(sheetContext).pop(true),
              ),
            ),
            AppBottomSheetTextButton(
              text: context.l10n.cancel,
              onPressed: () => Navigator.of(sheetContext).pop(false),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    _drawingsNotifier.removeAll();
    TrackingService.track('drawing_deleted', params: {
      'via': 'remove_all',
      'count': count,
      'coin': widget.market.coin,
    });
    setState(() => _selectedDrawingId = null);
  }

  /// The slim top bar: the market, the interval and chart-style pickers,
  /// indicators, undo / redo and Done (which leaves edit mode).
  Widget _editTopBar(
    AppColorsExtension c,
    HlCandleInterval candleIv,
    Set<String> indicators,
  ) {
    final m = widget.market;
    final l10n = context.l10n;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          HlCoinIcon(
            coin: m.coin,
            wireCoin: m.wireCoin,
            category: m.category,
            iconUrl: m.iconUrl,
            size: 24,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              m.coin,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 16.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
          Tooltip(
            message: l10n.chartInterval,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(_pickInterval(candleIv)),
              child: Container(
                height: 40,
                padding: EdgeInsets.symmetric(horizontal: 10.w),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.textPrimary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      candleIv.label,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 2.w),
                    Icon(Icons.expand_more_rounded,
                        size: 16.sp, color: c.textTertiary),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: 2.w),
          _editIconButton(
            c,
            icon: _styleLook(_style).$1,
            tip: l10n.chartStyleTitle,
            onTap: _pickChartStyle,
          ),
          _editIconButton(
            c,
            icon: Icons.functions_rounded,
            tip: l10n.chartIndicators,
            active: indicators.isNotEmpty,
            onTap: () => unawaited(_pickIndicators()),
          ),
          _editIconButton(
            c,
            icon: Icons.undo_rounded,
            tip: l10n.chartUndo,
            onTap: !_drawingsNotifier.canUndo
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    _drawingsNotifier.undoLast();
                    TrackingService.track(
                      'drawing_deleted',
                      params: {'via': 'undo', 'coin': widget.market.coin},
                    );
                  },
          ),
          _editIconButton(
            c,
            icon: Icons.redo_rounded,
            tip: l10n.chartRedo,
            onTap: !_drawingsNotifier.canRedo
                ? null
                : () {
                    _drawingsNotifier.redo();
                    TrackingService.track('chart_drawing_redone');
                  },
          ),
          SizedBox(width: 4.w),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleDrawingMode,
            child: SizedBox(
              height: 40,
              child: Center(
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 14.w, vertical: 7),
                  decoration: BoxDecoration(
                    color: context.ctaFill,
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Text(
                    l10n.done,
                    style: TextStyle(
                      color: context.ctaOnColor,
                      fontSize: 13.5.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One rail button per tool group (see [_railGroups]).
  Widget _railGroupButton(
    AppColorsExtension c,
    int index,
    String title,
    List<ChartDrawingTool> tools,
  ) {
    final armed = _armedTool;
    final armedHere = armed != null && tools.contains(armed);
    final shown =
        armedHere ? armed : (_lastToolInGroup[index] ?? tools.first);
    return Builder(
      builder: (anchor) => _editIconButton(
        c,
        icon: _toolLook(shown).$1,
        tip: tools.length == 1 ? _toolLook(shown).$2 : title,
        active: armedHere,
        more: tools.length > 1,
        onTap: tools.length == 1
            ? () => _armTool(tools.first)
            : () => unawaited(_openToolFlyout(anchor, index, title, tools)),
      ),
    );
  }

  /// The left-edge tool rail: select, the tool groups, then the magnet
  /// and remove-all. Scrolls if a short chart cannot fit it.
  Widget _toolRail(
    AppColorsExtension c,
    List<ChartDrawing> drawings,
    bool magnet,
  ) {
    final groups = _railGroups;
    final l10n = context.l10n;
    return Container(
      width: 44,
      decoration: BoxDecoration(
        color: c.textPrimary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          children: [
            _editIconButton(
              c,
              icon: Icons.touch_app_rounded,
              tip: l10n.chartSelectTool,
              active: _armedTool == null,
              onTap: () {
                final armed = _armedTool;
                if (armed != null) _armTool(armed);
              },
            ),
            for (var i = 0; i < groups.length; i++)
              _railGroupButton(c, i, groups[i].$1, groups[i].$2),
            Container(
              width: 24,
              height: 0.5,
              margin: const EdgeInsets.symmetric(vertical: 4),
              color: c.border,
            ),
            _editIconButton(
              c,
              icon: Icons.auto_fix_high_rounded,
              tip: l10n.chartMagnet,
              active: magnet,
              onTap: () {
                HapticFeedback.selectionClick();
                _preferences.toggleMagnet();
                TrackingService.track('chart_magnet_toggled');
              },
            ),
            _editIconButton(
              c,
              icon: Icons.delete_sweep_outlined,
              tip: l10n.chartRemoveAllTitle,
              onTap: drawings.isEmpty
                  ? null
                  : () => unawaited(_removeAllDrawings(drawings.length)),
            ),
          ],
        ),
      ),
    );
  }

  /// The small bar floating over the top of the plot while a tool is
  /// armed (colour for the next drawing, stop) or a drawing is selected
  /// (its colour, edit note, delete).
  Widget _contextBar(
    AppColorsExtension c,
    List<ChartDrawing> drawings,
    String? selectedId,
  ) {
    ChartDrawing? selected;
    for (final d in drawings) {
      if (d.id == selectedId) {
        selected = d;
        break;
      }
    }
    final armed = _armedTool;
    final current = selected != null ? selected.colorValue : _armedColorValue;
    final l10n = context.l10n;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      radius: 12.r,
      color: context.isDark ? c.surfaceElevated : Colors.white,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (armed != null && selected == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(_toolLook(armed).$1,
                  size: 17.sp, color: c.textPrimary),
            ),
          _colorDot(c, null, l10n.chartNeutralColor, selectedId, current),
          _colorDot(c, AppColors.marketUp.toARGB32(), l10n.chartUpColor,
              selectedId, current),
          _colorDot(c, AppColors.marketDown.toARGB32(), l10n.chartDownColor,
              selectedId, current),
          _colorDot(c, AppColors.warning.toARGB32(),
              l10n.chartHighlightColor, selectedId, current),
          if (selected != null && selected.tool == ChartDrawingTool.text)
            _editIconButton(
              c,
              icon: Icons.edit_rounded,
              tip: l10n.chartEditNote,
              onTap: () => unawaited(
                  _editNote(selected!.points.first, existing: selected)),
            ),
          if (selected != null)
            _editIconButton(
              c,
              icon: Icons.delete_outline_rounded,
              tip: l10n.chartDelete,
              onTap: () {
                HapticFeedback.selectionClick();
                _drawingsNotifier.remove(selected!.id);
                TrackingService.track(
                  'drawing_deleted',
                  params: {'via': 'delete', 'coin': widget.market.coin},
                );
                setState(() => _selectedDrawingId = null);
              },
            ),
          if (armed != null)
            _editIconButton(
              c,
              icon: Icons.close_rounded,
              tip: l10n.chartStopDrawing,
              onTap: () => _armTool(armed),
            ),
        ],
      ),
    );
  }

  /// Edit mode: top bar, then the rail beside the chart, then one hint
  /// line. A back gesture leaves edit mode before it leaves the sheet.
  Widget _editLayout(
    AppColorsExtension c,
    Widget chart, {
    required List<ChartDrawing> drawings,
    required String? selectedId,
    required HlCandleInterval candleIv,
    required Set<String> indicators,
    required bool magnet,
  }) {
    final body = Row(
      crossAxisAlignment: widget.fillHeight
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: widget.fillHeight ? null : widget.height.h,
          child: _toolRail(c, drawings, magnet),
        ),
        SizedBox(width: 6.w),
        Expanded(
          child: Stack(
            fit: widget.fillHeight ? StackFit.expand : StackFit.loose,
            children: [
              chart,
              if (_armedTool != null || selectedId != null)
                Positioned(
                  top: 6,
                  left: 0,
                  right: 0,
                  child: Center(child: _contextBar(c, drawings, selectedId)),
                ),
            ],
          ),
        ),
      ],
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _drawingMode) _toggleDrawingMode();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _editTopBar(c, candleIv, indicators),
          SizedBox(height: 6.h),
          _flexed(body),
          Padding(
            padding: EdgeInsets.only(top: 4.h, left: 44 + 6.w),
            child: Text(
              _toolbarHint(selectedId),
              style: TextStyle(color: c.textTertiary, fontSize: 11.5.sp),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// One pill of the timeframe row: the range pill every chart shares.
  Widget _timeframePill(
    AppColorsExtension c, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: EdgeInsets.only(right: 4.w),
      child: KuteRangePill(label: label, selected: selected, onTap: onTap),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final preferences = ref.watch(hlChartPreferencesProvider(_marketKey));
    // One TradingView-style model for every style: the interval sets the
    // bar size, the view is the user's pan and zoom, older bars page in
    // on demand. The style only changes how each bar is drawn.
    final layout = ref.watch(hlChartLayoutProvider);
    final style = HlChartStyle.fromName(layout.style);
    var candleIv = hlCandleInterval(_opening.intervalFor(layout.interval));
    var liveAsync =
        ref.watch(hyperliquidLiveCandlesProvider(_candleKey(candleIv)));
    // Once per open: a tape with too few traded bars steps up to a
    // coarser interval before anything is painted (the skeleton stays up
    // while the next one loads), so a thin market never opens as a flat
    // line. The saved layout is not touched.
    // Only a market the app calls low liquidity is ever stepped: the
    // label and the chart follow one rule (HlMarket.isLowLiquidity).
    _opening.forMarket(lowLiquidity: widget.market.isLowLiquidity);
    while (!_opening.settled) {
      final loaded = liveAsync.valueOrNull;
      if (loaded == null) {
        if (liveAsync.hasError) _opening.settle();
        break;
      }
      if (!_opening.onTapeLoaded(
          saved: layout.interval, candles: loaded.candles)) {
        break;
      }
      candleIv = hlCandleInterval(_opening.intervalFor(layout.interval));
      liveAsync =
          ref.watch(hyperliquidLiveCandlesProvider(_candleKey(candleIv)));
    }
    final state = liveAsync.valueOrNull;
    var candles = state?.candles ?? const <HyperliquidCandle>[];
    final loading = liveAsync.isLoading && candles.isEmpty;
    if (candles.isNotEmpty) {
      final first = candles.first;
      _paintedInterval = hlIntervalOfBar(first.openTime, first.closeTime) ??
          candleIv.interval;
      // Older pages the user panned back to sit in front of the live tape.
      candles = _withHistory(
        HlChartHistory.older(widget.market.wireCoin, _paintedInterval!),
        candles,
      );
    }
    // UNIT GUARD + LIVE FOLD (shared helpers — the pro chart and the
    // position PnL curve use the same ones): first rescale raw spot-pair
    // units onto display units, then fold the current display price into
    // the leading candle so the rightmost bar ticks with the header even
    // when no trade has printed — a thin HIP-3 equity would otherwise
    // freeze between trades. This is what makes the chart feel like the
    // BTC 5-minute one instead of a static snapshot.
    final displayPx = ref
            .watch(hyperliquidLiveMidProvider(widget.market.coin)) ??
        (widget.market.midPx > 0 ? widget.market.midPx : widget.market.markPx);
    // A low-liquidity market keeps its last traded price at the end of
    // the line: its mid is not a print.
    candles = chartCandlesWithLive(
      candles,
      displayPx,
      lowLiquidity: widget.market.isLowLiquidity,
    );

    // The user's OWN fills for this market → buy/sell markers on the chart.
    // HL keys fills by the wire coin (perp) or the base token (spot).
    // Filtered once per fresh provider list, not per rebuild — the painter
    // keys its repaint on the list identity.
    final ledgerId = widget.ledgerWalletId;
    final identity =
        ledgerId == null ? null : ref.watch(ledgerIdentityProvider(ledgerId));
    final ledgerAccount = ledgerId == null
        ? null
        : ref.watch(ledgerHlAccountProvider(ledgerId)).valueOrNull;
    final validLedger = ledgerId != null &&
        identity?.walletId == ledgerId &&
        identity?.hasVerifiedEvm == true &&
        ledgerAccount?.walletId == ledgerId &&
        ledgerAccount?.address?.toLowerCase() ==
            identity?.evmAddress?.toLowerCase();
    final allFills = !widget.showOwnActivity
        ? const <HlFill>[]
        : ledgerId == null
            ? ref.watch(hyperliquidActivityFillsProvider)
            : validLedger
                ? ref.watch(ledgerHlFillsProvider(ledgerId)).valueOrNull ??
                    ledgerAccount?.fills ??
                    const <HlFill>[]
                : const <HlFill>[];
    if (!identical(allFills, _fillsSource)) {
      _fillsSource = allFills;
      _fillsForMarket = allFills
          .where(
            (f) =>
                f.coin == widget.market.wireCoin ||
                f.coin == widget.market.coin,
          )
          .toList(growable: false);
    }
    final myFills = _fillsForMarket ?? const <HlFill>[];

    // The user's OPEN position on this market → entry and liquidation
    // lines, and its working orders → tagged order lines.
    HlPerpPosition? myPosition;
    var entryIsLong = true;
    var openOrders = const <HlOpenOrder>[];
    if (widget.showOwnActivity) {
      openOrders = ledgerId == null
          ? ref.watch(hyperliquidTradingProvider
                  .select((s) => s.valueOrNull?.openOrders)) ??
              const <HlOpenOrder>[]
          : validLedger
              ? ledgerAccount?.openOrders ?? const <HlOpenOrder>[]
              : const <HlOpenOrder>[];
      final positions = ledgerId == null
          ? ref.watch(hyperliquidPerpPositionsProvider)
          : validLedger
              ? <HlPerpPosition>[
                  ...?ledgerAccount?.account?.positions,
                  for (final account in ledgerAccount!.dexAccounts.values)
                    ...account.positions,
                ]
              : const <HlPerpPosition>[];
      for (final p in positions) {
        if (p.coin == widget.market.wireCoin) {
          myPosition = p;
          entryIsLong = p.isLong;
          break;
        }
      }
    }
    final tradeLines = widget.showOwnActivity
        ? _tradeLinesFor(myPosition, openOrders, editable: ledgerId == null)
        : const <ChartTradeLine>[];

    // Keep the previous timeframe's candles up while the new window
    // loads; the chart morphs to the fresh series when it arrives.
    if (!loading && candles.isNotEmpty) {
      _shownCandles = candles;
    }
    final held = _shownCandles;
    final showSkeleton = loading && (held == null || held.isEmpty);
    final displayCandles = loading ? (held ?? candles) : candles;

    // The user's saved drawings for this market — always rendered;
    // editable only in Advanced (drawing) mode. Selection is dropped when
    // its drawing disappears (undo / delete).
    final drawings = ref.watch(
      hlChartDrawingsProvider(hlChartDrawingMarketKey(widget.market)),
    );
    final indicators = preferences.indicators;
    var selectedId = _selectedDrawingId;
    if (selectedId != null && !drawings.any((d) => d.id == selectedId)) {
      selectedId = null;
      _selectedDrawingId = null;
    }

    // The market-signal layers switched on for this market (none by
    // default) and the thin pressure strip under the plot.
    final signals = _signalsFor(indicators, displayPx);
    final showPressure =
        widget.showSignals && !indicators.contains(kHlLayerPressureOff);

    // Candle sizes or ranges, then the chart-type and Advanced buttons.
    final pillRow =
        Row(
          children: [
            // Candle sizes (candle charts) or ranges (line charts) scroll
            // horizontally while the chart-type and Advanced buttons stay
            // pinned on the right.
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final iv in kHlCandleIntervals)
                      _timeframePill(
                        c,
                        label: iv.label,
                        selected: candleIv.interval == iv.interval,
                        onTap: () => _selectCandleInterval(iv),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 6.w),
            // ── Chart style: one button, a named list behind it ────────
            Tooltip(
              message: context.l10n.chartStyleTitle,
              child: GestureDetector(
                onTap: _pickChartStyle,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 7.h),
                  decoration: BoxDecoration(
                    color: c.textPrimary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(9.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_styleLook(_style).$1,
                          size: 16.sp, color: c.textPrimary),
                      SizedBox(width: 4.w),
                      Icon(Icons.expand_more_rounded,
                          size: 14.sp, color: c.textTertiary),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(width: 6.w),
            // ── "Advanced" pill: toggles the drawing tools (trendlines,
            // levels, rays, rectangles) on the chart above. Drawings stay
            // visible when the mode is off.
            Tooltip(
              message: context.l10n.advanced,
              child: GestureDetector(
                onTap: _toggleDrawingMode,
                child: Container(
                  padding: EdgeInsets.all(7.w),
                  decoration: BoxDecoration(
                    color: _drawingMode
                        ? c.textPrimary.withValues(alpha: 0.10)
                        : c.textPrimary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(9.r),
                  ),
                  child: Icon(
                    Icons.draw_rounded,
                    size: 18.sp,
                    color: _drawingMode ? c.textPrimary : c.textTertiary,
                  ),
                ),
              ),
            ),
            // The old fullscreen icon is gone — the Advanced pill above
            // is the ONE mode toggle (exit via the pill or the toolbar's
            // Done button).
          ],
        );

    // The candlestick chart owns its own scrub label + crosshair; we
    // only feed it the live candles and the LIVE flag from the WS.
    final Widget chart = showSkeleton
        ? SkeletonChart(
            // The plot and the readout row it will have (34).
            height: (widget.height + (widget.showSummary ? 34 : 0)).h,
            padding: EdgeInsets.zero,
          )
        : HlCandlestickChart(
            marketKey: hlChartDrawingMarketKey(widget.market),
            candles: displayCandles,
            isLive: state?.isLive ?? false,
            // Plot first; the pills stay attached right under it and
            // the summary row with the LIVE dot sits below them.
            summaryBelow: true,
            // Editing drops the readout row; the top bar names the market.
            // The market screen drops it for good (see showSummary).
            showSummary: widget.showSummary && !_drawingMode,
            footer: _drawingMode
                ? null
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showPressure)
                        HlPressureStrip(wireCoin: widget.market.wireCoin),
                      Padding(
                        padding: EdgeInsets.only(top: 10.h),
                        child: pillRow,
                      ),
                    ],
                  ),
            decimalCap: widget.market.pxDecimalCap,
            height: widget.height,
            fillHeight: widget.fillHeight,
            // The summary is the change over the visible span, named by
            // that span, as on TradingView.
            timeframeLabel: null,
            showVolume: indicators.contains('vol'),
            renderAsLine: false,
            style: style,
            onMoreHistoryWanted: () => unawaited(_loadMoreHistory()),
            onAutoScaleChanged: (auto) => VenueAnalytics.settingChanged(
              'chart_autoscale_toggled',
              setting: 'auto_scale',
              value: auto,
              scope: _marketKey,
              extra: {
                'coin': widget.market.coin,
                ...VenueAnalytics.hlAssetParams(widget.market.coin),
              },
            ),
            indicators: indicators,
            logScale: indicators.contains('log'),
            fills: myFills,
            // The entry rides the trade lines now (with the
            // liquidation and every working order); the painter's own
            // entry line stays off so the two never overlap.
            entryPx: null,
            entryIsLong: entryIsLong,
            tradeLines: tradeLines,
            onTradeLineMoved: ledgerId == null ? _moveOrder : null,
            onTradeLineTapped: (id) => _onTradeLineTapped(id, myPosition),
            signals: signals,
            onSignalTapped: _onSignalTapped,
            // The interval's identity: a new one opens on its newest
            // bars.
            morphKey: 'interval:${candleIv.interval}',
            drawings: drawings,
            drawingMode: _drawingMode,
            armedTool: _armedTool,
            armedColorValue: _armedColorValue,
            magnet: preferences.magnet,
            onTextRequested: (point) => unawaited(_editNote(point)),
            selectedDrawingId: selectedId,
            onDrawingPlaced: _onDrawingPlaced,
            onDrawingSelected: (id) {
              // Selecting from outside Advanced opens Advanced on the
              // tapped drawing; inside it, it is a plain selection.
              final enter = id != null && !_drawingMode;
              setState(() {
                _selectedDrawingId = id;
                if (enter) _drawingMode = true;
              });
              if (enter) widget.onAdvancedChanged?.call(true);
            },
            onDrawingUpdated: (d) => ref
                .read(
                  hlChartDrawingsProvider(
                    hlChartDrawingMarketKey(widget.market),
                  ).notifier,
                )
                .update(d),
          );
    if (_drawingMode) {
      return _editLayout(
        c,
        chart,
        drawings: drawings,
        selectedId: selectedId,
        candleIv: candleIv,
        indicators: indicators,
        magnet: preferences.magnet,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _flexed(chart),
        // The loading skeleton keeps the pills under it; otherwise they
        // ride inside the chart, right under the plot (see footer above).
        if (showSkeleton) ...[
          SizedBox(height: 10.h),
          pillRow,
        ],
      ],
    );
  }
}

/// The small corner triangle on a rail button whose group opens a
/// flyout (TradingView's "more tools here" mark).
class _CornerTickPainter extends CustomPainter {
  const _CornerTickPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CornerTickPainter old) => old.color != color;
}

// ─────────────────────────── order book ───────────────────────────

class HlOrderBookSection extends ConsumerWidget {
  final HlMarket market;
  const HlOrderBookSection({super.key, required this.market});

  static const _levels = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final bookAsync = ref.watch(hyperliquidOrderbookProvider(market.wireCoin));

    return bookAsync.when(
      // Skeleton mimicking the two-column bid/ask ladder while the book
      // first loads: 6 bid bars (left) + 6 ask bars (right).
      loading: () => SizedBox(
        height: 180.h,
        child: KuteSkeleton(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SkeletonBar(90.w, 14.h),
                  const Spacer(),
                  SkeletonBar(56.w, 11.h),
                ],
              ),
              SizedBox(height: 12.h),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final isBid in const [true, false]) ...[
                      if (!isBid) SizedBox(width: 8.w),
                      Expanded(
                        child: Column(
                          children: [
                            for (var i = 0; i < _levels; i++) ...[
                              if (i > 0) SizedBox(height: 6.h),
                              Align(
                                alignment: isBid
                                    ? Alignment.centerLeft
                                    : Alignment.centerRight,
                                child: FractionallySizedBox(
                                  widthFactor: 1.0 - 0.09 * i,
                                  child: SkeletonBar(
                                    double.infinity,
                                    16.h,
                                    radius: 4.r,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      error: (_, __) => Container(
        height: 80.h,
        alignment: Alignment.center,
        child: Text(
          context.l10n.hlOrderBookUnavailable,
          style: TextStyle(color: c.textTertiary, fontSize: 14.sp),
        ),
      ),
      data: (book) {
        final bids = book.bids.take(_levels).toList();
        final asks = book.asks.take(_levels).toList();
        var maxSz = 0.0;
        for (final l in bids) {
          if (l.sz > maxSz) maxSz = l.sz;
        }
        for (final l in asks) {
          if (l.sz > maxSz) maxSz = l.sz;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  context.l10n.hlOrderBook,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (book.isConnected)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6.w,
                        height: 6.w,
                        decoration: const BoxDecoration(
                          color: greenColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 4.w),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            SizedBox(height: 10.h),
            if (bids.isEmpty && asks.isEmpty)
              Container(
                height: 60.h,
                alignment: Alignment.center,
                child: Text(
                  context.l10n.hlEmptyBook,
                  style: TextStyle(color: c.textTertiary, fontSize: 13.sp),
                ),
              )
            else
              // Stacked depth view: asks above (best ask nearest the
              // middle), a spread row, bids below — the exchange-native
              // reading order. RepaintBoundary keeps the 250ms book
              // ticks re-rastering this card only, never the sheet.
              RepaintBoundary(
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                  decoration: BoxDecoration(
                    color: c.surface.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.only(bottom: 6.h),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              context.l10n.hlBookPrice,
                              style: TextStyle(
                                  color: c.textTertiary,
                                  fontSize: 11.sp,
                                  fontWeight: FontWeight.w600),
                            ),
                            Text(
                              context.l10n.hlBookSize,
                              style: TextStyle(
                                  color: c.textTertiary,
                                  fontSize: 11.sp,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      // Asks, worst at the top so the best ask touches
                      // the spread row.
                      for (final l in asks.reversed)
                        _DepthRow(
                          level: l,
                          maxSz: maxSz,
                          isBid: false,
                          decimalCap: market.pxDecimalCap,
                        ),
                      _BookSpreadRow(
                        bestBid: book.bestBid,
                        bestAsk: book.bestAsk,
                        spreadPct: book.spreadPct,
                        decimalCap: market.pxDecimalCap,
                      ),
                      for (final l in bids)
                        _DepthRow(
                          level: l,
                          maxSz: maxSz,
                          isBid: true,
                          decimalCap: market.pxDecimalCap,
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One order-book level: price (side colour), size, and a right-anchored
/// horizontal depth bar proportional to the level's size — a data bar,
/// not a button, so the flat 0.12-alpha market colour fill is correct.
/// Own widget class so live theme changes re-resolve colors per row.
class _DepthRow extends StatelessWidget {
  final HlL2Level level;
  final double maxSz;
  final bool isBid;
  final int decimalCap;

  const _DepthRow({
    required this.level,
    required this.maxSz,
    required this.isBid,
    required this.decimalCap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = isBid ? AppColors.marketUp : AppColors.marketDown;
    return Padding(
      padding: EdgeInsets.only(bottom: 3.h),
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor:
                    maxSz > 0 ? (level.sz / maxSz).clamp(0.04, 1.0) : 0.04,
                child: Container(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(3.r),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 3.h),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formatHlPrice(level.px, decimalCap: decimalCap),
                  style: TextStyle(
                    color: color,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  formatHlSize(level.sz, maxDecimals: 4),
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The spread row between asks and bids. Goes orange past 1% — a wide
/// spread is the one thing a market-order user must notice here.
class _BookSpreadRow extends StatelessWidget {
  final double? bestBid;
  final double? bestAsk;
  final double? spreadPct;
  final int decimalCap;

  const _BookSpreadRow({
    required this.bestBid,
    required this.bestAsk,
    required this.spreadPct,
    required this.decimalCap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pct = spreadPct;
    final b = bestBid, a = bestAsk;
    final abs = (b != null && a != null && a > b) ? a - b : null;
    final wide = pct != null && pct >= 1.0;
    final label = pct == null
        ? context.l10n.hlSpread
        : '${context.l10n.hlSpread}'
            '${abs != null ? ' ${formatHlPrice(abs, decimalCap: decimalCap)}' : ''}'
            ' · ${pct.toStringAsFixed(pct >= 0.1 ? 2 : 3)}%';
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        children: [
          Expanded(child: Divider(height: 1, color: c.borderSubtle)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.w),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (wide)
                  Padding(
                    padding: EdgeInsets.only(right: 4.w),
                    child: Icon(Icons.warning_amber_rounded,
                        color: Colors.orange, size: 12.sp),
                  ),
                Text(
                  label,
                  style: TextStyle(
                    color: wide ? Colors.orange : c.textTertiary,
                    fontSize: 11.5.sp,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: Divider(height: 1, color: c.borderSubtle)),
        ],
      ),
    );
  }
}

/// The streaming trades tape — every match on this market as it prints,
/// newest first, exactly the "orders streaming in" feel of the exchange's
/// own UI. Zero extra network: the tape rides the SAME socket the order
/// book already holds ([hyperliquidRecentTradesProvider] derives from it),
/// and trade frames bypass the book's 250 ms coalescing so each print
/// surfaces the moment it happens.
class HlRecentTradesSection extends ConsumerWidget {
  final HlMarket market;
  const HlRecentTradesSection({super.key, required this.market});

  /// The provider caps the tape at 30 rows (newest first); the list shows
  /// them all inside its own fixed-height scroll so the sheet never grows
  /// per print.
  static const _maxHeight = 236.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final trades = ref.watch(hyperliquidRecentTradesProvider(market.wireCoin));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.hlRecentTrades,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 15.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 10.h),
        // RepaintBoundary: each print re-rasters only this card — the
        // tape streams unthrottled, so this must never repaint the sheet.
        RepaintBoundary(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: c.surface.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: trades.isEmpty
                ? Container(
                    height: 40.h,
                    alignment: Alignment.center,
                    child: Text(
                      context.l10n.hlWaitingNextTrade,
                      style: TextStyle(color: c.textTertiary, fontSize: 13.sp),
                    ),
                  )
                : SizedBox(
                    height: _maxHeight.h,
                    child: ListView.separated(
                      physics: const ClampingScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: trades.length,
                      separatorBuilder: (_, __) => Divider(
                          height: 8.h, thickness: 0.5, color: c.borderSubtle),
                      itemBuilder: (_, i) => _TradeRow(
                        trade: trades[i],
                        decimalCap: market.pxDecimalCap,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _TradeRow extends StatelessWidget {
  final HlTrade trade;
  final int decimalCap;
  const _TradeRow({required this.trade, required this.decimalCap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isBuy = trade.side == 'B';
    final t = DateTime.fromMillisecondsSinceEpoch(trade.time);
    String two(int v) => v.toString().padLeft(2, '0');
    return Row(
      children: [
        SizedBox(
          width: 64.w,
          child: Text(
            '${two(t.hour)}:${two(t.minute)}:${two(t.second)}',
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 11.5.sp,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Expanded(
          child: Text(
            formatHlPrice(trade.px, decimalCap: decimalCap),
            style: TextStyle(
              color: isBuy ? greenColor : redColor,
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Text(
          trade.sz.toStringAsFixed(trade.sz >= 100 ? 0 : 4),
          style: TextStyle(
            color: c.textSecondary,
            fontSize: 12.5.sp,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────── shared bits ─────────────────────────────

/// Bottom trade CTA — a full-colored rounded badge with a left icon disc
/// and the [label] (LONG/SHORT or BUY/SELL), vertically centered. The old
/// price sub-label was dropped: both buttons showed the identical mid
/// price, which was meaningless. Light-mode gets a soft coloured shadow;
/// dark mode stays flat.
// The paired badge CTA now lives in the shared `MarketPairButton`
// (lib/screens/shared/market_pair_button.dart). This sheet uses the
// bare-icon, no-glow configuration (user decision — the disc backplate
// and colored glow read as clutter here).

class _ChartNoteSheet extends StatefulWidget {
  const _ChartNoteSheet({required this.initialText});
  final String initialText;
  @override
  State<_ChartNoteSheet> createState() => _ChartNoteSheetState();
}

class _ChartNoteSheetState extends State<_ChartNoteSheet> {
  late final _text = TextEditingController(text: widget.initialText);
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppBottomSheetContainer(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBottomSheetHeader(title: context.l10n.chartToolText),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: TextField(
                  controller: _text,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 240,
                  decoration:
                      InputDecoration(hintText: context.l10n.chartNoteHint),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(20.w),
                child: AppButton(
                  text: context.l10n.save,
                  onPressed: _text.text.trim().isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_text.text.trim()),
                ),
              ),
            ],
          ),
        ),
      );
}
