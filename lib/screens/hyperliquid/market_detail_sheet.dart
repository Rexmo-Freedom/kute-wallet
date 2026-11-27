import 'package:kute/platform/web_image.dart' show WebImagesOn;
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/screens/usd/components/dollars_activity_tab.dart'
    show DollarsActivityTab;
import 'package:kute/screens/shared/kute_side_panel.dart';
import 'package:kute/screens/shared/kute_page_route.dart';
import 'package:kute/screens/shared/fitted_title.dart';
import 'package:kute/providers/unified_search_provider.dart' show SearchCategory;
import 'package:kute/screens/shared/kute_share_actions.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show HlPositionRow, HlSpotRow, PortfolioCardList;
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/screens/shared/charts/kute_chart_core.dart'
    show kKuteMarketChartHeight;
import 'package:kute/screens/shared/kute_motion.dart'
    show KuteStillWhenCovered, kuteReduceMotion, kuteMotion, kArrivalDuration;
import 'package:kute/screens/shared/kute_detail_panes.dart'
    show kuteDetailPaneWidth;
import 'package:kute/screens/shared/kute_desk_market.dart'
    show KuteWheelRelay, kuteMarketFormFactor;
import 'package:kute/screens/shared/kute_desk_trade_buttons.dart';
import 'package:kute/screens/shared/position_rows_card.dart'
    show PositionStatTile, PositionStatTiles, positionTileValueStyle;
import 'package:kute/theme/kute_motion.dart' show KuteMotion;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/shared/charts/kute_chart_trade_lines.dart';
import 'package:kute/screens/shared/charts/kute_trend_chart.dart'
    show KuteChartRangeRow;
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/hyperliquid/components/open_orders_sheet.dart';
import 'package:kute/services/hyperliquid/hyperliquid_rounding.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart'
    show HyperliquidOrderNotPlacedException, HyperliquidOrderUnconfirmedException;
import 'package:kute/services/runtime_capabilities_service.dart'
    show runtimeCapabilitiesProvider;
import 'package:kute/screens/shared/capability_unavailable_sheet.dart'
    show advancedTradingOffered;
import 'package:kute/screens/hyperliquid/components/hl_protect_rules.dart';
import 'package:kute/screens/hyperliquid/components/hl_protection_rows.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_activity_provider.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/models/polymarket_model.dart' show PolymarketEvent;
import 'package:kute/providers/hyperliquid_funding_history_provider.dart';
import 'package:kute/providers/hyperliquid_insights_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_pressure_strip.dart';
import 'package:kute/screens/polymarket/components/price_format.dart'
    show formatPolyChance;
import 'package:kute/screens/polymarket/market_detail_sheet.dart'
    show MarketDetailSheet;
import 'package:kute/screens/shared/charts/kute_chart_signals.dart';
import 'package:kute/services/hyperliquid/insights/hl_crowd_match.dart';
import 'package:kute/services/hyperliquid/insights/hl_flow_signals.dart';
// lib/screens/hyperliquid/market_detail_sheet.dart
//
// Fullscreen market detail for one Hyperliquid market (perp or spot) —
// presented exactly like the Polymarket MarketDetailSheet (slide-up
// PageRouteBuilder, opaque: false, fullscreenDialog) so the two tabs
// share one navigation grammar.
//
// Content: the title row (back, logo, ticker, watchlist star), the live
// price large under it (WS mid via HlTickPrice: primary colour, a brief
// green/red flash on a tick), the whole width its own, and the change
// today under the price,
// HlCandleChart (TradingView model for every style: an interval row
// 1m…1W, the user's pan and zoom, older bars loaded on demand, one global
// style and interval for all markets — fed by WIRE coin, the one mapping
// that must never leak), perp stats row (funding
// with payer direction + annualized, open interest, 24h volume), a live order-book depth
// ladder (hyperliquidOrderbookProvider, WIRE coin again), the user's
// existing position/holding when any. The trade buttons are the floating
// bar (founder, 4 November 2026; kute_bar_context.dart, THE TRADE ROW):
// Invest into the order slip, the other side (Short, or a held spot
// token's Sell) beside it, and the round Sal button that sends the market
// to a friend at the row's end.
//
// Stock tokens (kHlStockSymbols) carry the honest-labeling disclaimer:
// these are Hyperliquid-listed tokens TRACKING an equity, not the
// exchange-traded share — prices can diverge, and we say so.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'package:kute/helpers/hyperliquid_activity.dart' show hlOrderSideLabel;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/chart_drawing.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/chart_drawings_provider.dart';
import 'package:kute/providers/hl_price_lines_provider.dart';
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
import 'package:kute/screens/hyperliquid/components/hl_chart_funding_pane.dart'
    show HlFundingFeed;
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_catalog.dart'
    show kHlFundingKey;
import 'package:kute/screens/hyperliquid/components/hl_drawing_rail.dart';
import 'package:kute/screens/hyperliquid/components/hl_drawing_settings_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_drawing_tools.dart';
import 'package:kute/screens/hyperliquid/components/hl_price_line_cards.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_history.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_intervals.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_interval_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_opening.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_description.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_stats.dart';
import 'package:kute/screens/hyperliquid/components/hl_tick_price.dart';
import 'package:kute/screens/hyperliquid/components/hl_watch_star.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/app_card.dart';
import 'package:kute/screens/shared/components/sheet_detail_row.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart'
    show HlTrade;
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/share/send_pick_session.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
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

  /// SEND MODE (screens/share/send_pick_session.dart): the page opened
  /// from Send's market search. Its ticket runs in send mode (its primary
  /// sends the investment, nothing is placed) and the page says so at the
  /// top; its round Sal button still shares the market. Null: the
  /// ordinary page.
  final SendPickSession? sendPick;

  /// THE DESK (EXPANDED): the page opens with the order ticket already in
  /// its side panel on this side (true Long / Buy, false Short / Sell),
  /// [initialUsd] typed in, counted as a ticket opened from [slipSource]
  /// (Sal's prefill, a claimed pick). Null: the page at rest.
  final bool? initialSide;
  final double? initialUsd;
  final String? slipSource;

  const HlMarketDetailSheet(
      {super.key,
      required this.market,
      this.ledgerWalletId,
      this.source = 'market_list',
      this.sendPick,
      this.initialSide,
      this.initialUsd,
      this.slipSource});

  static const routeName = 'hyperliquid-market-detail-sheet';

  static void show(BuildContext context,
      {required HlMarket market,
      String? ledgerWalletId,
      String source = 'market_list',
      SendPickSession? sendPick,
      bool? initialSide,
      double? initialUsd,
      String? slipSource}) {
    VenueAnalytics.rememberHlMarkets([market]);
    // A ticket opened on the desk's page (Sal's prefill, a claimed pick)
    // counts as the ticket it was, not as a market viewed.
    if (slipSource == null) {
      TrackingService.hyperliquidMarketViewed(
        coin: market.coin,
        kind: market.isSpot ? 'spot' : 'perp',
        extra: {
          'entry_source': source,
          'wallet_kind': ledgerWalletId == null ? 'hot' : 'ledger',
        },
      );
    }
    // Drop active focus (search field) so closing the sheet doesn't
    // re-summon the keyboard — same fix as the PM detail sheet.
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context, rootNavigator: true).push(
      // The detail sheet's rise (kute_page_route.dart): the settle easing
      // with the 0.97 → 1 scale, down on the close easing.
      KuteSheetPageRoute(
        settings: const RouteSettings(name: routeName),
        barrierColor: Colors.black.withValues(alpha: 0.4),
        // Two panes of its own on a wide window.
        form: false,
        // Still while the order slip (or any sheet) covers it, so its tick
        // animations never share the frames of the slip being scrolled.
        builder: (_) => KuteStillWhenCovered(
          child: HlMarketDetailSheet(
              market: market,
              ledgerWalletId: ledgerWalletId,
              source: source,
              sendPick: ledgerWalletId == null ? sendPick : null,
              initialSide: initialSide,
              initialUsd: initialUsd,
              slipSource: slipSource),
        ),
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

class _HlMarketDetailSheetState extends ConsumerState<HlMarketDetailSheet>
    with SingleTickerProviderStateMixin {
  /// Consolidated "Details" expander gates the dense secondary sections
  /// (stats strip, funding line, stock disclaimer, order book). Closed by
  /// default so the primary view stays focused on the header + chart +
  /// the user's own position + the floating trade row — mirrors the
  /// Polymarket sheet.

  /// Advanced chart mode (drawing tools + indicator toggles) is active:
  /// the chart expands to dominate the screen, the secondary sections
  /// hide and the bar's trade row goes away. Reported by HlCandleChart.
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

  // ── THE DESK'S SIDE PANEL (EXPANDED; founder, 25 November 2026: "have
  // a button like Long and Short ... Then clicking Long or Short this
  // side bar appears") ──────────────────────────────────────────────────
  //
  // At rest the page is the position page's shape: the market on the
  // left, a right column of the trade buttons, the Stats as squares and
  // the option cards. Long or Short opens the order ticket as the side
  // panel at the window's right edge, top to bottom, on that side; it
  // takes the column's place and the market reflows to the rest of the
  // window. Its X, Escape and the browser's back close it. The Advanced
  // chart editor does the same from the Long and Short in its header,
  // closed by default.

  /// The side the panel is open on (true Long / Buy), null while closed.
  bool? _panelSide;

  /// The side it last opened on, drawn while it slides away.
  bool _panelShownSide = true;

  /// The amount the panel's ticket opens with (an entry's prefill).
  double? _panelUsd;

  /// Where the panel's ticket was opened from (analytics: the slip's
  /// source).
  String _panelSource = 'market_detail';

  /// 0 at rest, 1 open, on the settle easing.
  late final AnimationController _panel = AnimationController(
      vsync: this, duration: KuteMotion.settleDuration);
  late final CurvedAnimation _panelCurve = CurvedAnimation(
      parent: _panel, curve: KuteMotion.settle, reverseCurve: KuteMotion.settle);

  /// The right column's top, on the price's line: the header's height
  /// (measured) plus the price block's top gutter.
  final GlobalKey _deskHeaderKey = GlobalKey();

  /// The page's left side on a laptop, whose scroll the wheel over the
  /// right column turns.
  final GlobalKey _deskLeftKey = GlobalKey();
  double _deskHeaderHeight = 48;

  /// Opens the panel on [isLong] (a second click on the side it is open
  /// on does nothing; the other side opens a ticket on it). Counted as the
  /// trade row's tap and the ticket's opening are on a phone.
  void _openPanel(bool isLong) {
    final m = market;
    TrackingService.track('hl_invest_cta_tapped', params: {
      'source': 'market_detail',
      'kind': m.isSpot ? 'spot' : 'perp',
      'side': isLong ? 'buy' : 'sell',
      'signer': 'hot',
    });
    if (_panelSide == isLong) return;
    HlOrderSlipSheet.trackOpened(
        market: m,
        isLong: isLong,
        source: 'market_detail',
        entrySource: widget.source);
    setState(() {
      _panelSource = 'market_detail';
      _panelUsd = null;
      _panelSide = isLong;
      _panelShownSide = isLong;
      _ticketGeneration++;
    });
    unawaited(_panel.forward());
  }

  /// Closes the panel back to the page at rest ([instant]: no slide).
  void _closePanel({bool instant = false}) {
    if (_panelSide == null) return;
    setState(() => _panelSide = null);
    if (instant) {
      _panel.value = 0;
    } else {
      unawaited(_panel.reverse());
    }
  }

  /// Escape closes the panel (the editor's own Escape first: a tool in
  /// hand, a drawing selected; a field typing keeps its keys).
  bool _onDeskKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    if (!mounted || _panelSide == null) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    final focused = FocusManager.instance.primaryFocus?.context?.widget;
    if (focused is EditableText) return false;
    if (_advancedChart && HlCandleChart.editorBusy(_chartHostKey)) {
      return false;
    }
    _closePanel();
    return true;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onDeskKey);
    final side = widget.initialSide;
    if (side != null &&
        widget.ledgerWalletId == null &&
        widget.sendPick == null) {
      // Opened with a side chosen: the panel is up from the first frame,
      // counted as the ticket it is.
      _panelSide = side;
      _panelShownSide = side;
      _panelUsd = widget.initialUsd;
      _panelSource = widget.slipSource ?? 'market_detail';
      _panel.value = 1;
      HlOrderSlipSheet.trackOpened(
          market: widget.market,
          isLong: side,
          source: _panelSource,
          entrySource: widget.source);
    }
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
    HardwareKeyboard.instance.removeHandler(_onDeskKey);
    _panelCurve.dispose();
    _panel.dispose();
    _livePrices?.unfocus(widget.market.coin);
    _livePrices?.release();
    _livePrices = null;
    super.dispose();
  }

  HlMarket get market => hlSheetMarket(ref, widget.market);

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

    // The page's Sal context (Send to a friend): the round Sal button at
    // the end of the bar's trade row opens it ([_tradeBar]).
    final bar = marketBarContext(
      context,
      // As the header names it, the logo drawn as the header draws it
      // (the Sal sheet's preview and send cards; founder: never the raw
      // ticker and a letter tile).
      title: hlFriendlyName(widget.market.coin) ?? widget.market.coin,
      ticker: widget.market.coin,
      wireCoin: widget.market.wireCoin,
      coinCategory: widget.market.category,
      coinIconUrl: widget.market.iconUrl,
      venue: kMarketLinkInvesting,
      slug: widget.market.coin,
      price: formatHlPrice(
          widget.market.midPx > 0 ? widget.market.midPx : widget.market.markPx,
          decimalCap: widget.market.pxDecimalCap),
      position: false,
      category: SearchCategory.perpetuals,
      searchHint: context.l10n.searchInvestmentsHint,
      source: 'trading',
    );
    // WIDE LAYOUTS (kute_layout.dart). EXPANDED: two panes, the market on
    // the left (title, price, the chart taller, About's stats beside the
    // order book) and the order ticket open in place on the right with the
    // position under it; the floating trade row is away, the ticket's own
    // button is in the pane. A Ledger page or a page in send mode keeps
    // the trade row and stays one centred column, as on MEDIUM. COMPACT:
    // exactly as before.
    // A browser too narrow for the desk keeps the MEDIUM page.
    final formFactor = kuteMarketFormFactor(context);
    // THE DESK (kute_side_panel.dart): on EXPANDED the hot account's page
    // is the whole window, the market on the left and the ticket as the
    // side panel at the window's right edge; the Advanced chart editor
    // keeps the same panel (foldable from its header).
    final desk = formFactor == KuteFormFactor.expanded &&
        widget.ledgerWalletId == null &&
        widget.sendPick == null;
    final inPlace = desk && !_advancedChart;
    // THE WEB'S DESK (founder, 27 November 2026: the venue's screen
    // design, "not super technical, just screen design and positions"):
    // the figures in the header strip with the price, Advanced chart left
    // of the star, the chart, the account's positions under it, the
    // description last, and the trade buttons and this market's position
    // in the right column: no order book, no recent trades. The native
    // desk (an iPad) is as it was.
    final deskWeb = inPlace && KuteBarPane.webLayout;
    // THE DESK at rest: the live book in the right column, the Stats and
    // the recent trades under the chart (founder, 25 November 2026).
    final deskBook = inPlace && _deskBookShown(m);
    _panel.duration =
        kuteReduceMotion(context) ? Duration.zero : KuteMotion.settleDuration;
    if (inPlace) {
      // The right column starts on the price's line, under the header.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final box =
            _deskHeaderKey.currentContext?.findRenderObject() as RenderBox?;
        if (!mounted || box == null || !box.hasSize) return;
        if ((box.size.height - _deskHeaderHeight).abs() > 0.5) {
          setState(() => _deskHeaderHeight = box.size.height);
        }
      });
    }
    final pageChildren = <Widget>[
              // ── Header ────────────────────────────────────────────
              // Edit mode hides it: the chart's own slim top bar names
              // the market there, and Done brings the header back.
              if (!_advancedChart)
                Padding(
                  key: inPlace ? _deskHeaderKey : null,
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
                  child: Row(
                    children: [
                      KuteCircleBackButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      SizedBox(width: 8.w),
                      // Web: the one remote logo drawn as an `<img>`, the
                      // opened market's own (web_image.dart, WebImagesOn);
                      // none to draw, no box and no gap (hlLogoShown).
                      if (hlLogoShown(
                          m.coin, m.wireCoin, m.iconUrl, m.category)) ...[
                        WebImagesOn(
                          child: HlCoinIcon(
                            coin: m.coin,
                            wireCoin: m.wireCoin,
                            category: m.category,
                            iconUrl: m.iconUrl,
                            size: 32,
                          ),
                        ),
                        SizedBox(width: 8.w),
                      ],
                      Flexible(
                        flex: deskWeb ? 0 : 1,
                        fit: deskWeb ? FlexFit.loose : FlexFit.tight,
                        // The ticker alone: the kind (Own / Leveraged) is
                        // the Instrument row under Stats, so the header
                        // keeps its room for the title. Smaller rather
                        // than cut, on its one line.
                        child: FittedTitle(
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
                      ),
                      if (deskWeb) ...[
                        const SizedBox(width: 20),
                        _deskWebPrice(m, price, pricesLive),
                        const SizedBox(width: 24),
                        Expanded(child: _deskWebStats(m)),
                        // No Advanced chart button: the chart below IS
                        // the advanced chart (founder, 27 November 2026).
                        const SizedBox(width: 16),
                      ],
                      // The watchlist star. Send to a friend is the round
                      // Sal button at the end of the bar's trade row.
                      HlWatchStar(market: m, size: 22, source: 'detail'),
                    ],
                  ),
                ),
              // Send mode says it at the top (send_pick_session.dart).
              if (!_advancedChart && widget.sendPick != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SendPickChip(session: widget.sendPick!),
                  ),
                ),

              // ── The price, large ──────────────────────────────────
              // The figure the screen is about, as on Robinhood and
              // Revolut: the live price over its change today. The chart
              // under it writes no price of its own (its scrub card names
              // a scrubbed bar).
              if (!_advancedChart && !deskWeb)
                Container(
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 0),
                  child: _withAdvancedPill(inPlace, Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Smaller rather than cut on a long price. The
                      // primary text colour at rest; a tick flashes green
                      // or red and fades back, so the price never sits in
                      // a colour that argues with the change. The row's
                      // whole width (founder, 4 November 2026: no Send to
                      // a friend pill beside it; it floats in the bar).
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: HlTickPrice(
                          key: const ValueKey('hl-detail-price'),
                          price: price,
                          text: formatHlPrice(price,
                              decimalCap: m.pxDecimalCap),
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
                      // Wrap (not Row) so the change and the optional
                      // chips never overflow: a chip flows to a new line.
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8.w,
                        runSpacing: 4.h,
                        children: [
                          // The change of the price shown above it, not
                          // of a minutes-old snapshot.
                          Text(
                            formatHlPct(m.dayChangeAt(price)),
                            key: const ValueKey('hl-detail-change'),
                            style: TextStyle(
                              color: m.dayChangeAt(price) >= 0
                                  ? greenColor
                                  : redColor,
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          // The price feed gave up reconnecting: say so
                          // instead of painting a frozen number as if it
                          // were live.
                          if (!pricesLive)
                            HlMetaChip(text: context.l10n.chartPriceDelayed),
                          // A thinly traded market says so, in the kind
                          // badge's own neutral chip.
                          if (m.isLowLiquidity) const HlLowLiquidityBadge(),
                        ],
                      ),
                    ],
                  )),
                ),

              // ── Body ──────────────────────────────────────────────
              Expanded(
                child: Builder(builder: (context) {
                  // The reading chart: the market chart's plot
                  // ([kKuteMarketChartHeight], design units; HlCandleChart
                  // applies .h, as the Predictions charts do) starting 12
                  // under the change line, its interval row right under
                  // it, and the option cards below. Advanced mode grows it
                  // to the whole screen.
                  if (_advancedChart) {
                    // Editing: the chart alone, the whole screen
                    // (HlChartEditBody, shared with the position screen).
                    // The header (and the page's bar context with it) is
                    // away, so the bar is hidden outright here: nothing
                    // over the chart tool.
                    return KuteBarContextScope(
                      barContext: const KuteBarContext.hidden(),
                      child: HlChartEditBody(
                        chart: HlCandleChart(
                          key: _chartHostKey,
                          market: m,
                          height: 240,
                          fillHeight: true,
                          showSignals: true,
                          ledgerWalletId: widget.ledgerWalletId,
                          onAdvancedChanged: _onAdvancedChanged,
                          deskPanelOpen: desk ? _panelSide != null : null,
                          // THE DESK: the editor's own Long and Short, at
                          // its header's right, opening the side panel.
                          deskTradeButtons: desk
                              ? KuteDeskTradeButtons(
                                  key: const ValueKey('hl-editor-trades'),
                                  compact: true,
                                  trades: _deskTrades(m, spotHeld))
                              : null,
                        ),
                      ),
                    );
                  }
                  // In place (EXPANDED) the chart is the hero: the
                  // window's height less the header's and the interval
                  // row's room, at least 420 (founder, 25 November 2026:
                  // "this page make it use the full screen").
                  // On MEDIUM (a tall portrait tablet) it takes 40% of
                  // the height, never less than the phone's.
                  final windowHeight = MediaQuery.sizeOf(context).height;
                  // The plot: the window less the header and the price
                  // over it, the pressure strip and interval row under it
                  // and the bottom gutter (the position page's own rule).
                  final chartHeight = inPlace
                      ? kuteDeskChartHeight(windowHeight, around: 230)
                      : formFactor == KuteFormFactor.compact
                          ? kKuteMarketChartHeight
                          : math.max(kKuteMarketChartHeight,
                              windowHeight * 0.4);
                  return SingleChildScrollView(
                    // Drawing on the chart must not scroll the sheet, so
                    // Advanced mode pins the body until it is switched off.
                    physics: _advancedChart
                        ? const NeverScrollableScrollPhysics()
                        : const BouncingScrollPhysics(),
                    // Same 20.w gutter as the Polymarket detail so the chart
                    // sits inside a visible inset instead of edge to edge.
                    padding: EdgeInsets.fromLTRB(
                        20.w,
                        12.h,
                        20.w,
                        // The foot scrolls clear of the floating trade
                        // row, and of the home indicator: the body runs to
                        // the screen's foot (the inset as seen below
                        // PlatformSafeArea: none on Android, which padded
                        // it already).
                        (inPlace
                                ? KuteLayout.paneGap
                                : kuteBarScrollClearance.h) +
                            MediaQuery.viewPaddingOf(context).bottom),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The web's desk: the advanced chart in place
                        // (founder, 27 November 2026: "implement all the
                        // tools directly on desktop"): its toolbar (the
                        // intervals, the chart type by name, Indicators),
                        // the drawing rail at the left, the plot.
                        if (deskWeb)
                          SizedBox(
                            key: const ValueKey('hl-desk-advanced-chart'),
                            height: chartHeight + 72,
                            child: HlCandleChart(
                              key: _chartHostKey,
                              market: m,
                              height: chartHeight,
                              fillHeight: true,
                              showSignals: true,
                              showSummary: false,
                              ledgerWalletId: widget.ledgerWalletId,
                              inlineEditor: true,
                            ),
                          )
                        else
                        // The market chart's plot (see chartHeight above);
                        // Advanced mode expands it (animated inside the
                        // chart).
                        HlCandleChart(
                          key: _chartHostKey,
                          market: m,
                          height: chartHeight,
                          showSignals: true,
                          // No change / LIVE row under the pills here.
                          showSummary: false,
                          ledgerWalletId: widget.ledgerWalletId,
                          onAdvancedChanged: _onAdvancedChanged,
                        ),
                        SizedBox(height: 20.h),
                        // No "Your investment" card here (founder,
                        // 2026-10-20): the position has its own screen,
                        // and the chart already marks entry and
                        // liquidation.
                        // The options under the chart, as two cards side
                        // by side (founder, 4 November 2026: "big squares",
                        // kute_action_cards.dart), as on the position
                        // screen and the Predictions screens: the chart's
                        // editing mode (drawing tools, indicators) and
                        // About, whose sheet holds the stats and long-form
                        // details, so the chart keeps the screen.
                        // (The "Why is it moving?" row is gone: that
                        // question is the first Ask Sal chip in the bar's
                        // Sal sheet; founder, 31 October 2026.)
                        // In place (EXPANDED) About is on the page: its
                        // stats and long-form details beside the order book
                        // and the recent trades, the Advanced chart card
                        // over them.
                        if (deskWeb) ...[
                          // What the market is (the positions are in the
                          // right column, under the order form).
                          _HlAboutContent(
                            market: widget.market,
                            isStock: isStock,
                            position: position,
                            wide: true,
                            showStats: false,
                            infoOnly: true,
                          ),
                        ] else if (inPlace)
                          // The book in the right column: the Stats and
                          // the recent trades here. No book: the Stats are
                          // the column's squares.
                          _HlAboutContent(
                            market: widget.market,
                            isStock: isStock,
                            position: position,
                            wide: true,
                            showStats: false,
                            bookInColumn: deskBook,
                          )
                        else if (!_advancedChart)
                          KuteActionCardGrid(
                            key: const ValueKey('hl-market-options'),
                            cards: [
                              _advancedCard(),
                              _aboutCard(m, isStock, position),
                            ],
                          ),
                        SizedBox(height: 16.h),
                      ],
                    ),
                  );
                }),
              ),

              // ── The trade row: the floating bar ───────────────────
              // THE BAR IS THE TRADE BUTTONS (founder, 4 November 2026:
              // "On the Invest and Short ... it should be the same";
              // kute_bar_context.dart, THE TRADE ROW): Invest and Short
              // (or Sell) float at the foot with the round Sal button that
              // sends the market to a friend, over the content, which
              // scrolls clear of them. Shown whenever the chart is not
              // being edited: the order slip runs the capability / geo
              // gate on tap and explains when investing is unavailable.
              // The chart editor takes them away (its hidden context
              // above) and Done brings them back.
              // In place (EXPANDED) the ticket in the right pane does the
              // trade row's job: the bar is away.
              // THE DESK at rest: the trade buttons head the right
              // column, so the bar keeps only the round Sal button, under
              // that column (KuteBarPane); with the panel open its ticket
              // holds the button and the bar is away.
              KuteBarContextScope(
                active: !_advancedChart,
                // The web's desk: the column's ticket holds the primary
                // and the round Sal button; the bar is away.
                barContext: deskWeb
                    ? const KuteBarContext.hidden()
                    : inPlace
                    ? (_panelSide == null
                        ? KuteBarContext.trade(
                            trades: const [],
                            share: KuteBarShare(barContext: bar),
                            category: SearchCategory.perpetuals,
                            searchHint: context.l10n.searchInvestmentsHint,
                            source: 'trading',
                          )
                        : const KuteBarContext.hidden())
                    : _tradeBar(m, spotHeld, bar),
                child: const SizedBox.shrink(),
              ),
    ];
    final column = Column(children: pageChildren);
    final Widget page = switch (formFactor) {
      KuteFormFactor.compact => column,
      // The desk: the market from the window's left edge (its own 16 /
      // 20 gutters plus 4: the page's [kuteDeskGutter]), uncapped, and the
      // ticket as the side panel at the right edge, top to bottom. The
      // editor keeps the same panel in the same place (the same ticket,
      // so what is typed survives the switch), its chart to the edge.
      _ when desk => _desk(
          column: column,
          editing: _advancedChart,
          rightColumn: deskWeb
              ? _deskWebColumn(m, position, spotHeld, bar)
              : inPlace
              ? _deskColumn(m, position, spotHeld,
                  bookShown: deskBook, statsShown: true)
              : null,
          panel: () => _ticketPane(m, position, spotHeld, bar),
        ),
      // MEDIUM (and a Ledger or send-mode page on EXPANDED): one centred
      // column; the chart editor takes the page's width.
      _ => Center(
          child: ConstrainedBox(
            // The Advanced chart on EXPANDED takes the whole window.
            constraints: BoxConstraints(
                maxWidth: _advancedChart
                    ? (formFactor == KuteFormFactor.expanded
                        ? double.infinity
                        : KuteLayout.pageMaxWidth)
                    : KuteLayout.columnMaxWidth),
            child: column,
          ),
        ),
    };
    return PopScope(
      // The browser's back (and the header's) closes the desk's side
      // panel first.
      canPop: _panelSide == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _panelSide != null) _closePanel();
      },
      child: Scaffold(
        backgroundColor: context.isDark ? c.gradientBottom : c.background,
        body: Container(
          decoration: AppDecorations.screenGradient(context),
          child: PlatformSafeArea(child: page),
        ),
      ),
    );
  }

  /// The chart's editor opened or closed: the desk's panel is closed by
  /// default inside it, and leaving it returns the page as it was.
  void _onAdvancedChanged(bool on) {
    _closePanel(instant: true);
    setState(() => _advancedChart = on);
  }

  /// THE DESK's trade doors (kute_desk_trade_buttons.dart): Long | Short
  /// on a perp, Buy | Sell on a spot token (Sell where one is held, as the
  /// phone's row offers it), in the up and down colours.
  List<KuteBarTrade> _deskTrades(HlMarket m, double spotHeld) {
    final l10n = context.l10n;
    return [
      KuteBarTrade(
        id: m.isSpot ? 'buy' : 'long',
        label: m.isSpot ? l10n.buy : l10n.longLabel,
        fill: AppColors.marketUp,
        onTap: () => _openPanel(true),
      ),
      if (!m.isSpot || spotHeld > 0)
        KuteBarTrade(
          id: m.isSpot ? 'sell' : 'short',
          label: m.isSpot ? l10n.sell : l10n.shortLabel,
          fill: AppColors.marketDown,
          onTap: () => _openPanel(false),
        ),
    ];
  }

  /// THE DESK on EXPANDED: [column] (the market: the page, or the editor
  /// when [editing]) from the window's left edge, [rightColumn] (the page
  /// at rest) at the right gutter, and the order ticket's side panel
  /// ([panel]) sliding in from the right edge over the column's place
  /// while open, the market reflowing to the rest.
  Widget _desk({
    required Widget column,
    required bool editing,
    required Widget? rightColumn,
    required Widget Function() panel,
  }) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final colWidth = kuteDetailPaneWidth(width - 2 * kuteDeskGutter);
      // How much of the window's right the market leaves: the column and
      // its gutters at rest, the panel and a gutter beside it open. The
      // page's own 20 gutters are inside it (the editor has its own).
      final restReserve =
          editing ? 0.0 : colWidth + kuteWideGap + kuteDeskGutter;
      final openReserve =
          kuteSidePanelWidth + (editing ? 0.0 : kuteDeskGutter);
      final inner = editing ? 0.0 : 20.0;
      return AnimatedBuilder(
        animation: _panelCurve,
        builder: (context, _) {
          final t = _panelCurve.value;
          final reserve = restReserve + (openReserve - restReserve) * t;
          return Stack(
            children: [
              Positioned(
                left: editing ? 0 : kuteDeskGutter - inner,
                top: 0,
                bottom: 0,
                right: math.max(0.0, reserve - inner),
                child: KeyedSubtree(key: _deskLeftKey, child: column),
              ),
              if (rightColumn != null && t < 1)
                Positioned(
                  key: const ValueKey('hl-desk-column'),
                  // From the window's top, on the header's own line
                  // (founder, 25 November 2026: "right bar must be more
                  // towards the top"); the header ends where the column
                  // starts, so nothing sits under it.
                  top: kuteDeskColumnTop,
                  bottom: 0,
                  right: kuteDeskGutter,
                  width: colWidth,
                  child: IgnorePointer(
                    ignoring: t > 0,
                    child: Opacity(
                      opacity: (1 - t * 2).clamp(0.0, 1.0),
                      // The wheel over the column scrolls the page
                      // (kute_desk_market.dart, KuteWheelRelay).
                      child: KuteWheelRelay(
                          target: _deskLeftKey, child: rightColumn),
                    ),
                  ),
                ),
              if (t > 0)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: math.min(width, kuteSidePanelWidth),
                  child: FractionalTranslation(
                    translation: Offset(1 - t, 0),
                    child: panel(),
                  ),
                ),
            ],
          );
        },
      );
    });
  }

  /// Whether the desk's right column holds the live order book (founder,
  /// 25 November 2026: "the order book on the right would look better"):
  /// while it first loads, and whenever it has a level on either side. A
  /// market with no book (an error, both sides empty) keeps the Stats as
  /// the column's squares instead of an empty box. A narrow select: only
  /// that answer changing rebuilds the page, never a 250 ms depth tick.
  bool _deskBookShown(HlMarket m) =>
      ref.watch(hyperliquidOrderbookProvider(m.wireCoin).select((a) {
        if (a.hasError) return false;
        final book = a.valueOrNull;
        if (book == null) return true;
        return book.bids.isNotEmpty || book.asks.isNotEmpty;
      }));

  /// THE DESK's right column at rest: the trade buttons, what is held
  /// here, then the live order book down to the bar's clearance at the
  /// window's foot, as many levels a side as fit ([HlOrderBookSection.fill];
  /// the Stats are under the chart). With no book ([bookShown] false) the
  /// Stats are the column's squares, two across, as before. Advanced chart
  /// is the pill on the price row and everything About opened is on the
  /// page, so no option cards here.
  Widget _deskColumn(HlMarket m, HlPerpPosition? position, double spotHeld,
      {required bool bookShown, bool statsShown = true}) {
    final l10n = context.l10n;
    final c = context.colors;
    HlSpotBalance? holding;
    if (m.isSpot && spotHeld > 0) {
      for (final b in ref.watch(hyperliquidSpotBalancesProvider)) {
        if (b.coin == m.coin) holding = b;
      }
    }
    final Widget? held = position != null
        ? HlPositionRow(
            key: ValueKey('hl-desk-position-${position.coin}'),
            position: position)
        : holding != null
            ? IgnorePointer(
                child: HlSpotRow(
                    key: ValueKey('hl-desk-holding-${holding.coin}'),
                    balance: holding),
              )
            : null;
    final gap = SizedBox(height: kKuteActionCardGap.h);
    final foot =
        kuteBarScrollClearance.h + MediaQuery.viewPaddingOf(context).bottom;
    final head = <Widget>[
      KuteDeskTradeButtons(
        key: const ValueKey('hl-desk-trades'),
        trades: _deskTrades(m, spotHeld),
      ),
      if (held != null) ...[
        gap,
        PortfolioCardList(rows: [held]),
        // Its stops, takes and trailing stops as words (a tap offers the
        // cancel, in the side panel), as on the position page.
        if (position != null && widget.ledgerWalletId == null)
          HlProtectionRows(
            key: const ValueKey('hl-desk-protection'),
            coin: position.coin,
            market: m,
            atSide: (open) => KuteSideFlow.run(open),
            padding: EdgeInsets.only(top: kKuteActionCardGap.h),
          ),
      ],
    ];
    if (bookShown) {
      return KuteBarPane(
        child: LayoutBuilder(builder: (context, constraints) {
          // A window too short for a book of five a side under the
          // buttons: the column scrolls, the book at its five.
          if (constraints.maxHeight < 520) {
            return SingleChildScrollView(
              primary: false,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(bottom: foot),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...head,
                  gap,
                  HlOrderBookSection(
                      key: const ValueKey('hl-desk-book'), market: m),
                ],
              ),
            );
          }
          return Padding(
            padding: EdgeInsets.only(bottom: foot),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...head,
                SizedBox(height: 20.h),
                Expanded(
                  child: HlOrderBookSection(
                      key: const ValueKey('hl-desk-book'),
                      market: m,
                      fill: true),
                ),
              ],
            ),
          );
        }),
      );
    }
    final stats =
        statsShown ? hlAboutStats(ref, l10n, m) : const <HlStat>[];
    Widget tile(HlStat stat) => PositionStatTile(
          key: ValueKey('hl-desk-stat-${stat.label}'),
          label: stat.label,
          value: Text(stat.value,
              maxLines: 1, style: positionTileValueStyle(c)),
        );
    return KuteBarPane(
      child: SingleChildScrollView(
        primary: false,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(bottom: foot),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...head,
            if (stats.isNotEmpty) ...[
              gap,
              // Arriving figures (a day's high and low, the spread) ease
              // the squares to their new height.
              AnimatedSize(
                duration: kuteMotion(context, kArrivalDuration),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: Column(
                  key: const ValueKey('hl-desk-stats'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < stats.length; i += 2) ...[
                      if (i > 0) gap,
                      i + 1 < stats.length
                          ? PositionStatTiles(
                              left: tile(stats[i]), right: tile(stats[i + 1]))
                          : tile(stats[i]),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Bumped after a placed order (or the "OK" of one on its way) in the
  /// in-place ticket: a fresh ticket takes its place.
  int _ticketGeneration = 0;

  /// THE WEB'S DESK right column (founder, 27 November 2026: "why is the
  /// right side so empty?"): the order ticket itself, always there (the
  /// same [HlOrderSlipSheet] as the phone's sheet and the desk's side
  /// panel, its amount typed: [HlOrderSlipSheet.typedAmount]), then what
  /// is held on this market, then the account's open positions (the
  /// Overview's own rows and empty state). No Long / Short doors: the
  /// ticket's own side switch.
  Widget _deskWebColumn(HlMarket m, HlPerpPosition? position,
      double spotHeld, KuteBarContext bar) {
    HlSpotBalance? holding;
    if (m.isSpot && spotHeld > 0) {
      for (final b in ref.watch(hyperliquidSpotBalancesProvider)) {
        if (b.coin == m.coin) holding = b;
      }
    }
    final Widget? held = position != null
        ? HlPositionRow(
            key: ValueKey('hl-desk-position-${position.coin}'),
            position: position)
        : holding != null
            ? IgnorePointer(
                child: HlSpotRow(
                    key: ValueKey('hl-desk-holding-${holding.coin}'),
                    balance: holding),
              )
            : null;
    final gap = SizedBox(height: kKuteActionCardGap.h);
    final foot = KuteLayout.paneGap + MediaQuery.viewPaddingOf(context).bottom;
    return KuteBarPane(
      child: SingleChildScrollView(
        key: const ValueKey('hl-desk-web-column'),
        primary: false,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(bottom: foot),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HlOrderSlipSheet.inPlace(
              key: ValueKey('hl-desk-ticket-$_ticketGeneration'),
              market: m,
              entrySource: widget.source,
              share: KuteBarShare(barContext: bar),
              typedAmount: true,
              // Placed (or the "OK" of an order on its way): a fresh
              // ticket, what is now held showing under it.
              onDone: () {
                if (!mounted) return;
                setState(() => _ticketGeneration++);
              },
            ),
            if (held != null) ...[
              gap,
              PortfolioCardList(rows: [held]),
              if (position != null && widget.ledgerWalletId == null)
                HlProtectionRows(
                  key: const ValueKey('hl-desk-protection'),
                  coin: position.coin,
                  market: m,
                  atSide: (open) => KuteSideFlow.run(open),
                  padding: EdgeInsets.only(top: kKuteActionCardGap.h),
                ),
            ],
            SizedBox(height: 20.h),
            // The account's OTHER positions: this market's is the card
            // above.
            DollarsActivityTab(
                key: const ValueKey('hl-desk-positions'),
                inPane: true,
                pnl: false,
                startInvesting: false,
                exclude: {'hl-${m.coin}', 'hl-spot-${m.coin}'}),
          ],
        ),
      ),
    );
  }

  /// EXPANDED's right pane: the order ticket open in place
  /// ([HlOrderSlipSheet.embedded], the trade row's Invest: the buy side,
  /// Short / Sell its own switch), and under it what the person holds on
  /// this market, as the Portfolio lists it (a position's row opens the
  /// position, where Close is). The pane stays put; the ticket is a
  /// full-height card that fits the room it has (SlipFit.fill).
  Widget _ticketPane(HlMarket m, HlPerpPosition? position, double spotHeld,
      KuteBarContext bar) {
    HlSpotBalance? holding;
    if (m.isSpot && spotHeld > 0) {
      for (final b in ref.watch(hyperliquidSpotBalancesProvider)) {
        if (b.coin == m.coin) holding = b;
      }
    }
    final Widget? held = position != null
        ? HlPositionRow(
            key: ValueKey('hl-pane-position-${position.coin}'),
            position: position)
        : holding != null
            // The holding's row opens this very market: here it only
            // reads.
            ? IgnorePointer(
                child: HlSpotRow(
                    key: ValueKey('hl-pane-holding-${holding.coin}'),
                    balance: holding),
              )
            : null;
    // The ticket IS the side panel (its colour the panel's surface, top
    // to bottom), the position in it over its button
    // (kute_side_panel.dart).
    return KeyedSubtree(
      key: const ValueKey('hl-ticket-pane'),
      child: SlipPanelFooter(
        // In the app's palette (not the ticket's tint): the Portfolio's
        // own card, reading on the side colour as the button does.
        footer: held == null
            ? null
            : Theme(
                data: Theme.of(context),
                child: PortfolioCardList(rows: [held])),
        child: HlOrderSlipSheet.inPlace(
          key: ValueKey('hl-ticket-in-place-$_ticketGeneration'),
          market: m,
          entrySource: widget.source,
          source: _panelSource,
          isLong: _panelShownSide,
          initialUsd: _panelUsd,
          share: KuteBarShare(barContext: bar),
          onClose: _closePanel,
          // Placed (or the "OK" of an order on its way): back to the page,
          // where what is now held shows.
          onDone: () {
            if (!mounted) return;
            _closePanel();
            setState(() => _ticketGeneration++);
          },
        ),
      ),
    );
  }

  /// The bar's trade row (kute_bar_context.dart, THE TRADE ROW): ONE
  /// green door into the order slip (buy / long, the same marketUp
  /// grammar as the Polymarket Yes), twice the width of the other side
  /// beside it, so shorting a perp, or selling a spot token the user
  /// holds, stays one tap away without competing with Invest: Short in
  /// the down colour, a spot Sell in the light pill. The slip has no side
  /// toggle (its side is fixed on open), so that second pill is what keeps
  /// Short / Sell reachable. At the row's end the round Sal button opens
  /// [bar], the page's Send to a friend sheet.
  ///
  /// The Ledger Investing tab opens this sheet with a wallet pinned, so
  /// the trades route through LedgerActions, which hands the SAME order
  /// slip that wallet id: one ticket, signed by the device instead of the
  /// hot account.
  ///
  /// SEND MODE (send_pick_session.dart; founder, 7 November 2026): the
  /// pills say they send, by the side the slip sends ("Send Long", "Send
  /// Short", as its primary reads "Send $50 · Long Bitcoin"), in their
  /// green and red, side by side at even widths; a spot token's Sell is
  /// away (a sale is no investment to send), and so is the round Sal
  /// button: no look-only link while sending.
  KuteBarContext _tradeBar(HlMarket m, double spotHeld, KuteBarContext bar) {
    final l10n = context.l10n;
    final sending = widget.sendPick != null;
    final showOtherSide = sending ? !m.isSpot : !m.isSpot || spotHeld > 0;
    return KuteBarContext.trade(
      trades: [
        KuteBarTrade(
          id: 'invest',
          label: sending
              ? sendPickTradeLabel(l10n, l10n.longLabel)
              : l10n.hlMarketInvestCta,
          fill: AppColors.marketUp,
          flex: sending ? 1 : 2,
          onTap: () => _openOrderSlip(m, isLong: true),
        ),
        if (showOtherSide)
          KuteBarTrade(
            id: m.isSpot ? 'sell' : 'short',
            label: m.isSpot
                ? l10n.sell
                : sending
                    ? sendPickTradeLabel(l10n, l10n.shortLabel)
                    : l10n.shortLabel,
            fill: m.isSpot ? null : AppColors.marketDown,
            onTap: () => _openOrderSlip(m, isLong: false),
          ),
      ],
      share: sending ? null : KuteBarShare(barContext: bar),
      category: SearchCategory.perpetuals,
      searchHint: l10n.searchInvestmentsHint,
      source: 'trading',
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
      sendPick: widget.sendPick,
    );
  }

  /// EXPANDED (founder, 25 November 2026: "the Advanced chart button just
  /// seems put there, should be more prominent"; again the same day: "the
  /// Advanced chart button where it was before"): "Advanced chart" is a
  /// pill on the price row, right-aligned, the app's amount-chip face with
  /// the candles glyph, instead of a card. Elsewhere the price block as it
  /// was (the card stays under the chart).
  Widget _withAdvancedPill(bool inPlace, Widget price) {
    if (!inPlace) return price;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: price),
        const SizedBox(width: 24),
        _advancedPill(),
      ],
    );
  }

  /// The "Advanced chart" pill (see [_withAdvancedPill]); on the web's
  /// desk it sits in the header, left of the star.
  Widget _advancedPill() {
    final c = context.colors;
    final label = context.l10n.hlAdvancedChart;
    // Bigger (founder, 25 November 2026: "advanced chart button should be
    // bigger here also"): the bar's pill size (48 high, fully round), the
    // candles at 20 and the label at the body-strong size. Outlined on
    // the page's surface rather than the dark filled pill: the ticket's
    // primary in the panel is the screen's one dark pill, and two would
    // argue over which is the action.
    return Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('hl-advanced-chart'),
              onTap: () => HlCandleChart.openAdvanced(_chartHostKey),
              borderRadius: BorderRadius.circular(24),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: c.border, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.candlestick_chart_rounded,
                        size: 20, color: c.textPrimary),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
  }

  /// The web desk's header price: the live price over its day change, at
  /// the header's size.
  Widget _deskWebPrice(HlMarket m, double price, bool pricesLive) {
    final c = context.colors;
    final change = m.dayChangeAt(price);
    return Column(
      key: const ValueKey('hl-desk-header-price'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HlTickPrice(
          key: const ValueKey('hl-detail-price'),
          price: price,
          text: formatHlPrice(price, decimalCap: m.pxDecimalCap),
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatHlPct(change),
              key: const ValueKey('hl-detail-change'),
              style: TextStyle(
                color: change >= 0 ? AppColors.marketUp : AppColors.marketDown,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (!pricesLive) ...[
              const SizedBox(width: 6),
              HlMetaChip(text: context.l10n.chartPriceDelayed),
            ],
          ],
        ),
      ],
    );
  }

  /// The web desk's header figures: the market's own Stats as the phone's
  /// About lists them ([hlAboutStats]), less the leverage figure and the
  /// order book's spread; label over value, side by side, scrolling
  /// sideways on a narrow window rather than wrapping.
  Widget _deskWebStats(HlMarket m) {
    final c = context.colors;
    final l10n = context.l10n;
    final stats = deskWebStats(hlAboutStats(ref, l10n, m), l10n);
    return SingleChildScrollView(
      key: const ValueKey('hl-desk-header-stats'),
      scrollDirection: Axis.horizontal,
      primary: false,
      child: Row(
        children: [
          for (final (i, stat) in stats.indexed) ...[
            if (i > 0) const SizedBox(width: 24),
            Column(
              key: ValueKey('hl-desk-header-stat-${stat.label}'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stat.label,
                    maxLines: 1,
                    style: TextStyle(
                        color: c.textTertiary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(stat.value,
                    maxLines: 1,
                    style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// "Advanced chart": the chart's editing mode (drawing tools,
  /// indicators).
  KuteActionCard _advancedCard() => KuteActionCard.option(
        key: const ValueKey('hl-advanced-chart'),
        icon: Icons.candlestick_chart_rounded,
        title: context.l10n.hlAdvancedChart,
        subtitle: context.l10n.optionAdvancedChartSub,
        onTap: () => HlCandleChart.openAdvanced(_chartHostKey),
      );

  /// "About Bitcoin": the option card beside Advanced chart, opening the
  /// sheet with the market's Stats and everything the old Details
  /// expander held.
  KuteActionCard _aboutCard(
      HlMarket m, bool isStock, HlPerpPosition? position) {
    final name = hlFriendlyName(m.coin) ?? m.unitAssetName ?? m.coin;
    return KuteActionCard.option(
      key: const ValueKey('hl-about'),
      icon: Icons.info_outline_rounded,
      title: context.l10n.investingAboutMarket(name),
      subtitle: context.l10n.optionAboutMarketSub,
      onTap: () {
        // The descriptions table is read while the sheet slides in.
        ref.read(hlMarketDescriptionsProvider);
        // THE DESK: at the window's right edge, as every panel the page
        // opens (kute_wide_frames.dart, KuteSideFlow).
        // Once: a second tap while it slides in does not stack another.
        void open() => unawaited(OpenOnce.run(
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
        if (kuteWindowIsExpanded(context)) {
          KuteSideFlow.run(open);
        } else {
          open();
        }
      },
    );
  }
}

/// A market's Stats as the About sheet lists them: [hlMarketStats], then
/// the day's high and low (from the 1h x 24h candles) and the spread, as
/// they land. Shared by the About sheet and the desk's squares.
List<HlStat> hlAboutStats(WidgetRef ref, AppLocalizations l10n, HlMarket m) {
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
    return [
      ...hlMarketStats(l10n, m),
      if (hi24 != null)
        HlStat(l10n.hl24hHigh, formatHlPrice(hi24, decimalCap: m.pxDecimalCap)),
      if (lo24 != null)
        HlStat(l10n.hl24hLow, formatHlPrice(lo24, decimalCap: m.pxDecimalCap)),
      if (spreadPct != null)
        HlStat(l10n.hlSpread,
            '${spreadPct.toStringAsFixed(spreadPct >= 0.1 ? 2 : 3)}%'),
    ];
}

/// The sheet behind the "About (name)" row: first what the market is (its
/// description, [hlMarketDescription], over the venue and kind), then its
/// Stats (label / value pairs in two columns: 24h volume, open interest,
/// funding, maximum leverage, mark, 24h high and low, spread), then how it
/// trades right now: the position rows, the funding payer line and
/// countdown, the stock notice, the order book and the recent trades. Its
/// requests (the 24h candles, the book, the trades) only run while it is
/// open. It scrolls clear of the floating bar.
class _HlAboutContent extends ConsumerWidget {
  /// The row snapshot the market sheet was opened on.
  final HlMarket market;
  final bool isStock;
  final HlPerpPosition? position;

  /// The page's own About (EXPANDED, in place; founder, 25 November
  /// 2026: "data here seems too compressed"): what the market is across
  /// the pane's full width, the Stats as one band of tiles under it, the
  /// funding line and the notice at full width, then the order book and
  /// the recent trades side by side (stacked when the pane is too narrow
  /// for two readable columns). False: the sheet's one column.
  final bool wide;

  /// False leaves the Stats out (the desk shows them as the right
  /// column's squares).
  final bool showStats;

  /// The desk's right column holds the order book (founder, 25 November
  /// 2026: "the order book on the right would look better, instead of all
  /// those numbers, and then those numbers at the bottom"): under what it
  /// is, the Stats as squares beside the recent trades, no book here.
  final bool bookInColumn;

  /// The web desk: what the market is (the description, the venue line,
  /// the funding line, the stock notice) and nothing else; the position
  /// is the right column's, the figures the header's.
  final bool infoOnly;

  const _HlAboutContent({
    required this.market,
    required this.isStock,
    required this.position,
    this.wide = false,
    this.showStats = true,
    this.bookInColumn = false,
    this.infoOnly = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final m = hlSheetMarket(ref, market);
    final position = this.position;
    final l10n = context.l10n;
    // Null for the moment the bundled table is still being read: the
    // description waits rather than flashing the template first.
    final descriptions = ref.watch(hlMarketDescriptionsProvider);
    final description = descriptions.isLoading && !descriptions.hasValue
        ? null
        : hlMarketDescription(
            l10n, m, descriptions.valueOrNull ?? const <String, String>{});

    final stats = showStats ? hlAboutStats(ref, l10n, m) : const <HlStat>[];
    final info = <Widget>[
                      // What it is: the description, then the venue and
                      // the kind (Perp / Spot) on one quiet line.
                      // Wide: prose at a readable measure.
                      ConstrainedBox(
                        key: const ValueKey('hl-about-what-it-is'),
                        constraints: BoxConstraints(
                            maxWidth: wide
                                ? kuteDeskProseMaxWidth
                                : double.infinity),
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (description != null)
                            Text(
                              description,
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 15.sp,
                                height: 1.4,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          SizedBox(height: 6.h),
                          Text(
                            l10n.hlAboutTradedOn(HlDexNames.venueOf(m),
                                hlKindLabel(l10n, isSpot: m.isSpot)),
                            style: TextStyle(
                              color: c.textTertiary,
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      ),
                      if (showStats) ...[
                        SizedBox(height: wide ? 28.h : 20.h),
                        HlStatsSection(
                            title: l10n.investingStats,
                            stats: stats,
                            tiles: wide),
                      ],
                      SizedBox(height: 12.h),
                      if (position != null && !infoOnly)
                        // Wide: the rows at a readable width, never
                        // stretched across the pane.
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                                maxWidth: wide ? 420 : double.infinity),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
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
                            ),
                          ),
                        ),
                      SizedBox(height: 14.h),
                      if (!m.isSpot && m.funding != null) ...[
                        // Who pays whom, and when: funding settles on
                        // the hour.
                        Text(
                          '${formatHlFundingLine(context.l10n, m.funding!)} · '
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
                          constraints: BoxConstraints(
                              maxWidth: wide
                                  ? kuteDeskProseMaxWidth
                                  : double.infinity),
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
    ];
    if (infoOnly) {
      return Column(
        key: const ValueKey('hl-about-info'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: info,
      );
    }
    final book = <Widget>[
      HlOrderBookSection(market: m),
      SizedBox(height: 16.h),
      HlRecentTradesSection(market: m),
    ];
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [...info, SizedBox(height: 16.h), ...book],
      );
    }
    if (bookInColumn) {
      return Column(
        key: const ValueKey('hl-about-in-place'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...info,
          SizedBox(height: 28.h),
          LayoutBuilder(builder: (context, constraints) {
            const gap = KuteLayout.paneGap;
            final statsBlock = _HlDeskStats(
                stats: hlAboutStats(ref, l10n, m),
                title: l10n.investingStats);
            // Two readable columns need about 300 each; narrower, stacked.
            if (constraints.maxWidth < 2 * 300 + gap) {
              return Column(
                key: const ValueKey('hl-about-stats-stacked'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  statsBlock,
                  SizedBox(height: 28.h),
                  HlRecentTradesSection(market: m),
                ],
              );
            }
            return Row(
              key: const ValueKey('hl-about-stats-row'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: statsBlock),
                const SizedBox(width: gap),
                Expanded(child: HlRecentTradesSection(market: m)),
              ],
            );
          }),
        ],
      );
    }
    return Column(
      key: const ValueKey('hl-about-in-place'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...info,
        SizedBox(height: 28.h),
        LayoutBuilder(builder: (context, constraints) {
          // Two readable columns need about 300 each; narrower, stacked.
          const gap = KuteLayout.paneGap;
          if (constraints.maxWidth < 2 * 300 + gap) {
            return Column(
              key: const ValueKey('hl-about-book-stacked'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HlOrderBookSection(market: m),
                SizedBox(height: 28.h),
                HlRecentTradesSection(market: m),
              ],
            );
          }
          return Row(
            key: const ValueKey('hl-about-book-row'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: HlOrderBookSection(market: m)),
              const SizedBox(width: gap),
              Expanded(child: HlRecentTradesSection(market: m)),
            ],
          );
        }),
      ],
    );
  }
}

/// The desk's Stats under the chart: titled as the recent trades beside
/// them are, the stat squares the right column showed (moved, never
/// twice), two across, four across where the half is wide and the count
/// fills its rows; an odd last square takes the row's width, never a
/// lone half.
class _HlDeskStats extends StatelessWidget {
  final List<HlStat> stats;
  final String title;
  const _HlDeskStats({required this.stats, required this.title});

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    Widget tile(HlStat stat) => PositionStatTile(
          key: ValueKey('hl-desk-stat-${stat.label}'),
          label: stat.label,
          value: Text(stat.value,
              maxLines: 1, style: positionTileValueStyle(c)),
        );
    final gap = SizedBox(height: kKuteActionCardGap.h);
    return Column(
      key: const ValueKey('hl-desk-stats'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 15.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 10.h),
        // Arriving figures (a day's high and low, the spread) ease the
        // squares to their new height.
        AnimatedSize(
          duration: kuteMotion(context, kArrivalDuration),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: LayoutBuilder(builder: (context, constraints) {
            final perRow =
                constraints.maxWidth >= 680 && stats.length % 4 == 0 ? 4 : 2;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < stats.length; i += perRow) ...[
                  if (i > 0) gap,
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var j = i;
                            j < math.min(i + perRow, stats.length);
                            j++) ...[
                          if (j > i) SizedBox(width: 10.w),
                          Expanded(child: tile(stats[j])),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          }),
        ),
      ],
    );
  }
}

/// The sheet behind the "About (name)" card: [_HlAboutContent] in one
/// column under its title. It scrolls clear of the floating bar.
class _HlAboutSheet extends StatelessWidget {
  final String title;
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
  Widget build(BuildContext context) {
    return AppBottomSheetContainer(
      maxHeight: 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: title,
            trailing: const AppBottomSheetCloseButton(),
          ),
          Flexible(
            child: SingleChildScrollView(
              // The last trades scroll clear of the floating bar.
              padding:
                  EdgeInsets.fromLTRB(20.w, 4.h, 20.w, kuteBarScrollClearance.h),
              child: _HlAboutContent(
                market: market,
                isStock: isStock,
                position: position,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── position summary ─────────────────────────

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

  /// The open position's screen: outside Advanced the chart reads like
  /// the Predictions position's, with a "Your entry" caption on the entry
  /// line, no liquidation line (its tile is under the chart) and no
  /// volume. Advanced brings everything back.
  final bool positionView;

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
    this.positionView = false,
    this.deskPanelOpen,
    this.deskTradeButtons,
    this.inlineEditor = false,
  });

  /// THE WEB'S DESK (founder, 27 November 2026: "get rid of the Advanced
  /// chart [button], and implement all the tools directly on desktop"):
  /// the chart IS the advanced chart, in place on the market page, from
  /// the first frame and for good: its drawing rail, indicators and chart
  /// types, with one toolbar of its own (the intervals, the chart type by
  /// icon and name, Indicators, undo / redo) instead of the editor's top
  /// bar; no Done, and Escape or the back never leave it. Same
  /// drawings, indicators and type, stored as the advanced chart stores
  /// them. Needs [fillHeight] and a bounded parent.
  final bool inlineEditor;

  /// The editor on an EXPANDED window with the order ticket's side panel
  /// beside it: whether the panel is open now (the back then closes the
  /// panel, not the editor), and the Long and Short at the header's right
  /// that open it (kute_desk_trade_buttons.dart). Null: no panel here (a
  /// Ledger's page).
  final bool? deskPanelOpen;
  final Widget? deskTradeButtons;

  /// Whether the editor under [key] holds Escape itself now (a tool in
  /// hand, a drawing selected).
  static bool editorBusy(GlobalKey key) {
    final state = key.currentState;
    return state is _HlCandleChartState &&
        state._drawingMode &&
        (state._armedTool != null || state._selectedDrawingId != null);
  }

  /// Opens the chart under [key] in Advanced (editing) mode, as its old
  /// pencil did: the host screen's "Advanced chart" row. Nothing while it
  /// is already open. [source] is the host screen for
  /// `advanced_chart_opened` (`market`, `position`).
  static void openAdvanced(GlobalKey key, {String source = 'market'}) {
    final state = key.currentState;
    if (state is _HlCandleChartState && !state._drawingMode) {
      state._toggleDrawingMode(source: source);
    }
  }

  @override
  ConsumerState<HlCandleChart> createState() => _HlCandleChartState();
}

/// Tests: the next Advanced opens as on a fresh launch, the tool rail
/// out.
@visibleForTesting
void debugResetHlChartRail() => _HlCandleChartState._railShownThisSession = true;

class _HlCandleChartState extends ConsumerState<HlCandleChart> {
  String get _marketKey => hlChartDrawingMarketKey(widget.market);
  ChartPreferencesNotifier get _preferences =>
      ref.read(hlChartPreferencesProvider(_marketKey).notifier);

  /// Style and interval are one global layout for every Hyperliquid
  /// market, like a TradingView layout (see hlChartLayoutProvider).
  HlChartStyle get _style =>
      HlChartStyle.fromName(ref.read(hlChartLayoutProvider).style);

  /// The chart button's glyph for [style] (one of HlChartStyle.picker).
  IconData _styleIcon(HlChartStyle style) => hlChartStyleIcon(style);

  /// The Chart sheet (hl_chart_sheet.dart): the chart types and the
  /// indicators, behind the chart's one button (the market chart's and
  /// the Advanced top bar's alike).
  void _openChartSheet() {
    unawaited(showHlChartSheet(
      context,
      market: widget.market,
      marketKey: _marketKey,
      candles: _shownCandles ?? const <HyperliquidCandle>[],
      showYourTrades: widget.showOwnActivity,
      onAddPriceLine: _startPriceLine,
    ));
  }

  /// The Chart sheet's new price line: the Advanced chart, the tool in hand.
  void _startPriceLine() {
    if (!mounted) return;
    if (!_drawingMode) _toggleDrawingMode(source: 'price_line');
    setState(() {
      _armedTool = ChartDrawingTool.priceLine;
      _toolSticky = false;
      _placementPending = false;
      _placedPoints = 0;
      _selectedDrawingId = null;
    });
  }

  /// The Advanced axes' corner "Log" switch.
  void _setLogScale(bool on) {
    _preferences.setLogScale(on);
    VenueAnalytics.settingChanged(
      'chart_log_scale_toggled',
      setting: 'log_scale',
      value: on,
      scope: _marketKey,
      extra: {
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
  /// On from the first frame, for good, as the web desk's inline editor
  /// ([HlCandleChart.inlineEditor]).
  late bool _drawingMode = widget.inlineEditor;

  /// The tool in hand. Null = Cursor (select/edit). One drawing per
  /// pick: after it lands the rail goes back to Cursor, unless the tool
  /// was double-tapped ([_toolSticky]).
  ChartDrawingTool? _armedTool;

  /// TradingView's "stay in drawing mode": a double tap on a rail tool
  /// keeps it in hand after each drawing, until it is tapped again.
  bool _toolSticky = false;
  ChartDrawingTool? _lastRailTool;
  DateTime _lastRailTapAt = DateTime(0);

  /// The first point of a two-point drawing is down (tap-tap placement);
  /// the hint asks for the second.
  bool _placementPending = false;

  /// Anchors of the drawing being placed that are down (the chart's
  /// placement, hl_drawing_placement.dart): the hint's "Point k of n".
  int _placedPoints = 0;

  /// ARGB of the armed color; null = the neutral theme default.
  int? _armedColorValue;

  String? _selectedDrawingId;

  /// Whether the edit mode's tool rail is out. Out on the first
  /// Advanced of a session, so the tools are in sight; after that it
  /// stays as the user last left it, on every chart, until the app
  /// restarts.
  static bool _railShownThisSession = true;
  bool _railShown = _railShownThisSession;

  void _toggleRail() {
    HapticFeedback.selectionClick();
    setState(() => _railShownThisSession = _railShown = !_railShown);
  }

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

  /// The daily candles Pivots read, in display units, kept per read so a
  /// live tick does not recompute the levels.
  List<HyperliquidCandle>? _dailySource;
  List<HyperliquidCandle> _daily = const [];

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
    }
    // A window resized across the web desk's width keeps this chart's
    // state (its key): in place it becomes the editor, and back on a
    // narrow layout the reading chart again.
    if (widget.inlineEditor != oldWidget.inlineEditor) {
      if (widget.inlineEditor) {
        _drawingMode = true;
      } else if (_drawingMode) {
        _drawingMode = false;
        _armedTool = null;
        _selectedDrawingId = null;
      }
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
      // A row only the WebSocket has seen has no type or trigger price
      // yet (orderUpdates carries the basic order only): a stop would be
      // drawn as a movable limit at its 5% guard price. It is drawn once
      // REST says what it is (a read that follows within moments).
      if (!o.detailsKnown) continue;
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
          label: hlOrderSideLabel(context.l10n,
              coin: o.coin, isBuy: o.isBuy, reduceOnly: o.reduceOnly),
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
    // Moving an order is Advanced: a withheld policy says so here, before
    // the confirm sheet and the approval, never after them.
    if (!advancedTradingOffered(
        context, ref.read(runtimeCapabilitiesProvider))) {
      return;
    }
    // What the chart must never send: a row it cannot move (still loading,
    // a trailing stop, a trigger whose kind is unknown).
    try {
      hlCheckModifiable(order, _hotOrders());
    } catch (_) {
      showMessageSnackBar(
          context: context,
          message: context.l10n.chartOrderMoveFailed,
          error: true);
      return;
    }
    final mark =
        ref.read(hyperliquidLiveMidProvider(market.coin)) ??
        (market.midPx > 0 ? market.midPx : market.markPx);
    // A stop or take dropped on the wrong side of the price would fire at
    // once: refused before anything else, the line back where it was.
    if (order.isTrigger && order.tpsl != null) {
      final shifted = order.isMarketTrigger
          ? null
          : order.limitPx + (newPx - (order.triggerPx ?? order.limitPx));
      final issue = hlProtectIssue(
          closeIsBuy: order.isBuy,
          tpsl: order.tpsl!,
          trigger: newPx,
          mark: mark,
          limitPx: shifted);
      final text = hlProtectIssueText(context.l10n, issue);
      if (text != null) {
        HapticFeedback.heavyImpact();
        showMessageSnackBar(context: context, message: text, error: true);
        return;
      }
    }
    // A limit dragged across the price fills now, as a taker: said on the
    // confirm sheet, not blocked.
    final crosses = !order.isTrigger &&
        hlLimitCrossesNow(isBuy: order.isBuy, limitPx: newPx, mark: mark);
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
                    '${formatHlPrice(oldPx, decimalCap: cap)} → ${formatHlPrice(newPx, decimalCap: cap)}'
                    '${crosses ? '\n${context.l10n.hlProtectLimitFillsNow}' : ''}',
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
      } on HyperliquidOrderNotPlacedException {
        // Looked up after an unclear answer: nowhere moved, the order is
        // where it was.
        if (!mounted) return;
        showMessageSnackBar(
            context: context,
            message: context.l10n.chartOrderMoveFailed,
            error: true);
      } on HyperliquidOrderUnconfirmedException {
        // Could not tell: the orders were read again; never invite a
        // second move.
        if (!mounted) return;
        showMessageSnackBar(
            context: context,
            message: context.l10n.investingSubmissionUnknown,
            error: true);
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

  void _toggleDrawingMode({String source = 'market'}) {
    // The web desk's inline editor never leaves the mode.
    if (widget.inlineEditor && _drawingMode) return;
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
        params: {'coin': widget.market.coin, 'source': source},
      );
    }
    widget.onAdvancedChanged?.call(entering);
  }

  // ─────────────────────── market-signal layers ───────────────────────
  //
  // Optional marks about the market, stored with the indicators per
  // market. The Chart sheet no longer lists them (founder, 1 November
  // 2026: only the useful indicators), so a stored one loads as off
  // (ChartPreferencesNotifier.shownIndicators); the pressure strip, on
  // until switched off, stays on.

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
        final arrow = l.kind == HlCrowdKind.reach ? '↑' : '↓';
        levels.add(ChartSignalLevel(
          id: id,
          price: l.strike,
          label: '$arrow '
              '${l10n.hlChartCrowdLevel(_crowdPercent(l.chance), _crowdDay(l.day))}',
          // Where the tag column cannot hold the day: the chance alone.
          shortLabel: '$arrow ${_crowdPercent(l.chance)}',
        ));
      }
    }
    final dates = <ChartSignalDate>[];
    if (wantMacro) {
      for (var i = 0; i < crowd.dates.length; i++) {
        final d = crowd.dates[i];
        final fed = d.kind == HlMacroKind.fedDecision;
        final id = 'date:$i';
        targets[id] = (d.event, fed ? 'fed_date' : 'inflation_date');
        final name = fed ? l10n.hlChartFedDecision : l10n.hlChartUsInflation;
        dates.add(ChartSignalDate(
          timeMs: d.day.millisecondsSinceEpoch,
          label: '$name · ${_crowdDay(d.day)}',
          // Where the band cannot hold the day: the event alone.
          shortLabel: name,
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

  /// The rail's price line placed: stored with the price lines, not among
  /// the drawings. The tool stays in hand after a refusal, for another try.
  void _onPriceLinePlaced(ChartDrawing drawing) {
    final placed = hlPlacePriceLine(
      context,
      ref,
      market: widget.market,
      marketKey: _marketKey,
      level: drawing.points.first.price,
      reference: ref.read(hyperliquidLivePricesProvider).mid(widget.market.coin) ??
          _shownCandles?.lastOrNull?.close,
    );
    if (!placed || (_toolSticky && _armedTool == drawing.tool)) return;
    setState(() {
      _armedTool = null;
      _toolSticky = false;
    });
  }

  void _onDrawingPlaced(ChartDrawing drawing, {String? via}) {
    if (drawing.tool == ChartDrawingTool.priceLine) {
      _onPriceLinePlaced(drawing);
      return;
    }
    final before = ref
        .read(hlChartDrawingsProvider(hlChartDrawingMarketKey(widget.market)))
        .length;
    if (before >= kMaxDrawingsPerMarket) {
      // At the cap: quietly stop placing — disarm, keep what's drawn.
      // No snackbar; the rail going back to Cursor is the signal.
      if (_armedTool != null) setState(() => _armedTool = null);
      return;
    }
    _drawingsNotifier.add(drawing);
    // No prices in analytics — type + coin only.
    TrackingService.track(
      'drawing_created',
      params: {
        'type': drawing.tool.name,
        'coin': widget.market.coin,
        if (via != null) 'via': via,
      },
    );
    if (via == null && _toolSticky && _armedTool == drawing.tool) {
      // A tool kept in hand: the next tap starts the next drawing.
      return;
    }
    // One drawing per pick, like TradingView: the rail goes back to
    // Cursor and the new drawing is selected with its handles and
    // toolbar up, so the next touch adjusts it.
    setState(() {
      _armedTool = null;
      _toolSticky = false;
      _selectedDrawingId = drawing.id;
    });
  }

  /// A rail tool tapped. One tap takes it in hand for one drawing; a
  /// double tap keeps it in hand (shown with a small lock); a tap on the
  /// tool in hand puts it down.
  void _armTool(ChartDrawingTool tool) {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    final second = _lastRailTool == tool &&
        now.difference(_lastRailTapAt) < const Duration(milliseconds: 350);
    _lastRailTool = tool;
    _lastRailTapAt = second ? DateTime(0) : now;
    setState(() {
      if (second) {
        _armedTool = tool;
        _toolSticky = true;
      } else if (_armedTool == tool) {
        _armedTool = null;
        _toolSticky = false;
      } else {
        _armedTool = tool;
        _toolSticky = false;
      }
      _placementPending = false;
      _placedPoints = 0;
      _selectedDrawingId = null;
    });
  }

  /// Back to Cursor (the rail's first button).
  void _toCursor() {
    if (_armedTool == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _armedTool = null;
      _toolSticky = false;
      _placementPending = false;
      _placedPoints = 0;
    });
  }

  /// A group's button tapped (hl_drawing_rail.dart). A group of one tool
  /// is a plain rail tool ([_armTool]). A group of more: a tap takes its
  /// face; on the face already in hand a quick second tap keeps it
  /// (sticky), a tap on a kept tool puts it down, and any other tap
  /// opens the group's fly-out.
  void _tapGroup(HlToolGroup group, ChartDrawingTool face, BuildContext anchor) {
    if (!group.single && _armedTool == face && !_toolSticky) {
      final second = _lastRailTool == face &&
          DateTime.now().difference(_lastRailTapAt) <
              const Duration(milliseconds: 350);
      if (!second) {
        unawaited(_openFlyout(group, anchor));
        return;
      }
    }
    _armTool(face);
  }

  /// [group]'s fly-out from its button: the tool picked is taken in hand
  /// (for one drawing) and becomes the group's face.
  Future<void> _openFlyout(HlToolGroup group, BuildContext anchor) async {
    HapticFeedback.selectionClick();
    final picked = await showHlToolFlyout(
      context,
      anchor: anchor,
      group: group,
      armed: _armedTool,
    );
    if (picked == null || !mounted) return;
    HapticFeedback.selectionClick();
    ref.read(hlDrawingRailFacesProvider.notifier).setFace(group.id.name, picked);
    _lastRailTool = picked;
    _lastRailTapAt = DateTime(0);
    setState(() {
      _armedTool = picked;
      _toolSticky = false;
      _placementPending = false;
      _placedPoints = 0;
      _selectedDrawingId = null;
    });
  }

  /// The selected drawing's settings sheet (hl_drawing_settings_sheet.dart).
  /// Each setting changed is reported once, when it closes, through the
  /// toolbar's own event (its name as the action; never a value).
  Future<void> _openDrawingSettings(ChartDrawing drawing) async {
    HapticFeedback.selectionClick();
    final coin = widget.market.coin;
    await showHlDrawingSettings(
      context,
      marketKey: _marketKey,
      drawingId: drawing.id,
      title: _toolLook(drawing.tool),
      onClosed: (changed) {
        for (final action in changed) {
          TrackingService.track('drawing_edited', params: {
            'type': drawing.tool.name,
            'action': action,
            'coin': coin,
          });
        }
      },
    );
  }

  /// One undoable edit of a drawing from its toolbar.
  void _editDrawing(ChartDrawing next, String action) {
    HapticFeedback.selectionClick();
    _drawingsNotifier.update(next);
    TrackingService.track('drawing_edited', params: {
      'type': next.tool.name,
      'action': action,
      'coin': widget.market.coin,
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

  /// A tool's name, as the rail and the hint say it.
  String _toolLook(ChartDrawingTool tool) => hlToolName(context.l10n, tool);

  /// One line under the plot that says what the next touch does.
  String _toolbarHint(String? selectedId, List<ChartDrawing> drawings) {
    final l10n = context.l10n;
    final tool = _armedTool;
    if (tool != null) {
      final label = _toolLook(tool);
      if (_placementPending) {
        final spec = chartDrawingSpec(tool);
        if (spec.openEnded) {
          return _placedPoints >= spec.points
              ? l10n.chartHintFinishShape
              : l10n.chartHintPointOf(_placedPoints + 1, spec.points);
        }
        // Two anchors keep their words; longer tools count the points.
        if (spec.taps > 2 && _placedPoints > 0) {
          return l10n.chartHintPointOf(_placedPoints + 1, spec.taps);
        }
        return l10n.chartHintTapSecondPoint;
      }
      if (_toolSticky) return l10n.chartHintToolKept(label);
      return chartDrawingPointCount(tool) == 1
          ? l10n.chartHintTapToPlace(label)
          : l10n.chartHintTapFirstPoint(label);
    }
    for (final d in drawings) {
      if (d.id == selectedId) {
        return d.locked ? l10n.chartHintLocked : l10n.chartHintAdjust;
      }
    }
    return l10n.chartHintPickToolKeep;
  }

  /// The rail's overflow: the magnet, and removing every drawing.
  Future<void> _openRailMore(
    BuildContext anchor,
    List<ChartDrawing> drawings,
    bool magnet,
  ) async {
    HapticFeedback.selectionClick();
    final box = anchor.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final c = context.colors;
    final l10n = context.l10n;
    final origin = box.localToGlobal(
      Offset(box.size.width + 6, 0),
      ancestor: overlay,
    );
    final picked = await showMenu<String>(
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
        PopupMenuItem<String>(
          key: const ValueKey('hl-chart-rail-magnet'),
          value: 'magnet',
          height: 46,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  l10n.chartMagnet,
                  maxLines: 2,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(width: 16.w),
              SizedBox(
                width: 18,
                child: magnet
                    ? Icon(Icons.check_rounded,
                        size: 18.sp, color: c.textPrimary)
                    : null,
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          key: const ValueKey('hl-chart-rail-remove-all'),
          value: 'removeAll',
          enabled: drawings.isNotEmpty,
          height: 46,
          child: Text(
            l10n.chartRemoveAllTitle,
            style: TextStyle(
              color: drawings.isEmpty
                  ? c.textTertiary
                  : AppColors.marketDown,
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
    if (picked == null || !mounted) return;
    if (picked == 'magnet') {
      HapticFeedback.selectionClick();
      _preferences.toggleMagnet();
      TrackingService.track('chart_magnet_toggled');
    } else if (picked == 'removeAll') {
      unawaited(_removeAllDrawings(drawings.length));
    }
  }

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
      child: MouseRegion(
        cursor: onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
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
                    painter: HlCornerTickPainter(color),
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  /// The Interval sheet behind the top bar's interval button: the
  /// intervals as square cards (hl_chart_interval_sheet.dart).
  Future<void> _pickInterval(HlCandleInterval current) async {
    HapticFeedback.selectionClick();
    final picked = await showHlIntervalSheet(context, current: current);
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

  /// The editor's header on EXPANDED (founder, 25 November 2026, on the
  /// Advanced chart on a laptop: "even now it looks bad"): Done and the
  /// market (logo, name, live price and its change) at the left; at the
  /// right the market page's own row of interval pills, the chart-style
  /// button, undo and redo, grouped at readable sizes.
  Widget _editTopBarWide(AppColorsExtension c, HlCandleInterval candleIv) {
    final m = widget.market;
    final l10n = context.l10n;
    final mid = ref.watch(hyperliquidLiveMidProvider(m.coin));
    final price = mid ?? (m.midPx > 0 ? m.midPx : m.markPx);
    final change = m.dayChangeAt(price);
    final identity = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hlLogoShown(m.coin, m.wireCoin, m.iconUrl, m.category)) ...[
          HlCoinIcon(
            coin: m.coin,
            wireCoin: m.wireCoin,
            category: m.category,
            iconUrl: m.iconUrl,
            size: 30,
          ),
          const SizedBox(width: 10),
        ],
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            m.coin,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ),
        const SizedBox(width: 14),
        if (price > 0)
          HlTickPrice(
            price: price,
            text: formatHlPrice(price, decimalCap: m.pxDecimalCap),
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        const SizedBox(width: 8),
        Text(
          formatHlPct(change),
          style: TextStyle(
            color: change >= 0 ? greenColor : redColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
    final pills = KuteChartRangeRow(
      key: const ValueKey('hl-chart-edit-interval-row'),
      labels: [for (final iv in kHlCandleIntervals) iv.label],
      selectedIndex: kHlCandleIntervals
          .indexWhere((iv) => iv.interval == candleIv.interval),
      onSelected: (i) => _selectCandleInterval(kHlCandleIntervals[i]),
    );
    return SizedBox(
      key: const ValueKey('hl-chart-edit-top-bar-wide'),
      height: 52,
      // The chart beside the ticket's panel on a small laptop is narrow:
      // the intervals fold into the phone's interval button when their
      // pills would not fit, and the market's name and price step down
      // rather than overflow.
      child: LayoutBuilder(builder: (context, constraints) {
        final roomy = constraints.maxWidth >= 640;
        return Row(
          children: [
            _editDoneButton(c, l10n),
            const SizedBox(width: 16),
            if (roomy)
              identity
            else
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: identity,
                ),
              ),
            const SizedBox(width: 16),
            if (roomy)
              // The intervals take what is left, up to 420, at the right.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, room) => Align(
                    alignment: Alignment.centerRight,
                    child: room.maxWidth >= 280
                        ? ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: pills,
                          )
                        : _intervalButton(c, l10n, candleIv),
                  ),
                ),
              )
            else
              _intervalButton(c, l10n, candleIv),
            const SizedBox(width: 10),
            HlChartSheetButton(
              key: const ValueKey('hl-chart-edit-sheet-button'),
              style: _style,
              onTap: _openChartSheet,
            ),
            const SizedBox(width: 10),
            _undoButton(c, l10n),
            _redoButton(c, l10n),
            // THE DESK: Long and Short, opening the order ticket's side
            // panel beside the chart.
            if (widget.deskTradeButtons case final trades?) ...[
              const SizedBox(width: 12),
              trades,
            ],
          ],
        );
      }),
    );
  }

  /// The interval as one button opening the interval list (the phone's
  /// editor; the desk's when its pills do not fit).
  Widget _intervalButton(AppColorsExtension c, AppLocalizations l10n,
          HlCandleInterval candleIv) =>
      Tooltip(
            message: l10n.chartInterval,
            child: GestureDetector(
              key: const ValueKey('hl-chart-edit-interval-button'),
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
          );

  Widget _undoButton(AppColorsExtension c, AppLocalizations l10n) =>
      _editIconButton(
        c,
        icon: Icons.undo_rounded,
        tip: l10n.chartUndo,
        onTap: !_drawingsNotifier.canUndo ? null : _undo,
      );

  Widget _redoButton(AppColorsExtension c, AppLocalizations l10n) =>
      _editIconButton(
        c,
        icon: Icons.redo_rounded,
        tip: l10n.chartRedo,
        onTap: !_drawingsNotifier.canRedo ? null : _redo,
      );

  void _undo() {
    if (!_drawingsNotifier.canUndo) return;
    HapticFeedback.selectionClick();
    _drawingsNotifier.undoLast();
    TrackingService.track(
      'drawing_deleted',
      params: {'via': 'undo', 'coin': widget.market.coin},
    );
  }

  void _redo() {
    if (!_drawingsNotifier.canRedo) return;
    _drawingsNotifier.redo();
    TrackingService.track('chart_drawing_redone');
  }

  /// The editor's keys (a hardware keyboard): Escape puts the tool in
  /// hand down (or lets the selected drawing go, or leaves), Delete / Backspace
  /// removes the selected drawing (the toolbar's Delete), Cmd/Ctrl+Z
  /// undoes and Shift+Cmd/Ctrl+Z redoes.
  KeyEventResult _onEditKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final command = keys.isMetaPressed || keys.isControlPressed;
    if (command && key == LogicalKeyboardKey.keyZ) {
      keys.isShiftPressed ? _redo() : _undo();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      // The plot drops a placing in hand first (hl_charts.dart); then the
      // tool goes down, the selection goes, and last Escape leaves the
      // editor, as Done does.
      if (_armedTool != null) {
        _toCursor();
      } else if (_selectedDrawingId != null) {
        setState(() => _selectedDrawingId = null);
      } else if (_drawingMode &&
          widget.deskPanelOpen != true &&
          !widget.inlineEditor) {
        // (An open side panel takes this Escape: the page closes it.)
        _toggleDrawingMode();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      final id = _selectedDrawingId;
      if (id == null) return KeyEventResult.ignored;
      _drawingsNotifier.remove(id);
      TrackingService.track(
        'drawing_deleted',
        params: {'via': 'delete', 'coin': widget.market.coin},
      );
      setState(() => _selectedDrawingId = null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// This editor holds Backspace (KuteDeskKeys) now.
  bool _claimsDeskKeys = false;

  final FocusNode _editFocus = FocusNode(debugLabel: 'hl-chart-editor');

  @override
  void dispose() {
    if (_claimsDeskKeys) KuteDeskKeys.editorHoldsSelection = false;
    _editFocus.dispose();
    super.dispose();
  }

  /// The slim top bar: the market, the interval, the chart button (chart
  /// types and indicators), undo / redo and Done (which leaves edit mode).
  Widget _editTopBar(AppColorsExtension c, HlCandleInterval candleIv) {
    if (widget.inlineEditor) return _inlineToolbar(c, candleIv);
    if (KuteLayout.isExpanded(context)) return _editTopBarWide(c, candleIv);
    final m = widget.market;
    final l10n = context.l10n;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          if (hlLogoShown(m.coin, m.wireCoin, m.iconUrl, m.category)) ...[
            HlCoinIcon(
              coin: m.coin,
              wireCoin: m.wireCoin,
              category: m.category,
              iconUrl: m.iconUrl,
              size: 24,
            ),
            SizedBox(width: 8.w),
          ],
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
          _intervalButton(c, l10n, candleIv),
          SizedBox(width: 6.w),
          // The chart's one button, as on the market chart: the chart
          // types and the indicators in one sheet.
          HlChartSheetButton(
            key: const ValueKey('hl-chart-edit-sheet-button'),
            style: _style,
            onTap: _openChartSheet,
          ),
          SizedBox(width: 2.w),
          _undoButton(c, l10n),
          _redoButton(c, l10n),
          SizedBox(width: 4.w),
          _editDoneButton(c, l10n),
        ],
      ),
    );
  }

  /// Done: leaves the editor.
  Widget _editDoneButton(AppColorsExtension c, AppLocalizations l10n) =>
      MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
        key: const ValueKey('hl-chart-edit-done'),
        behavior: HitTestBehavior.opaque,
        onTap: _toggleDrawingMode,
        child: SizedBox(
          height: 40,
          child: Center(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 7),
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
      );

  /// One group's button: its face's glyph, the corner mark when it has
  /// more tools. Keyed by its face's tool (as the flat rail was) inside
  /// a key for the group.
  Widget _railGroup(HlToolGroup group, Map<String, String> faces,
      {bool large = false}) {
    final l10n = context.l10n;
    final face = hlGroupFace(group, faces)!;
    return KeyedSubtree(
      key: ValueKey('hl-chart-rail-group-${group.id.name}'),
      child: Builder(
        builder: (anchor) => HlRailButton(
          key: ValueKey('hl-chart-rail-${face.name}'),
          glyph: hlGlyphForTool(face),
          label: hlToolName(l10n, face),
          large: large,
          selected: _armedTool == face,
          sticky: _armedTool == face && _toolSticky,
          onTap: () => _tapGroup(group, face, anchor),
          onMore: group.single
              ? null
              : () => unawaited(_openFlyout(group, anchor)),
          moreLabel: l10n
              .chartToolGroupShowAll(hlToolGroupName(l10n, group.id)),
        ),
      ),
    );
  }

  /// The left-edge tool rail: tuck away, Cursor, the tool groups, then
  /// the overflow (magnet, remove all). Scrolls if a short chart cannot
  /// fit it.
  Widget _toolRail(
    AppColorsExtension c,
    List<ChartDrawing> drawings,
    bool magnet,
  ) {
    final l10n = context.l10n;
    // EXPANDED: roomier targets (48 a button) for a mouse.
    final wide = KuteLayout.isExpanded(context);
    final faces = ref.watch(hlDrawingRailFacesProvider);
    return Container(
      key: const ValueKey('hl-chart-tool-rail'),
      width: wide ? 52 : 44,
      decoration: BoxDecoration(
        color: c.textPrimary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          children: [
            // Tucks the rail away; the plot takes its width.
            KeyedSubtree(
              key: const ValueKey('hl-chart-rail-hide'),
              child: _editIconButton(
                c,
                icon: Icons.chevron_left_rounded,
                tip: l10n.chartToolsButton,
                onTap: _toggleRail,
              ),
            ),
            HlRailButton(
              key: const ValueKey('hl-chart-rail-cursor'),
              glyph: HlRailGlyph.cursor,
              label: l10n.chartToolCursor,
              large: wide,
              selected: _armedTool == null,
              onTap: _toCursor,
            ),
            // The groups (hl_drawing_rail.dart), each showing its face.
            for (final group in kHlToolGroups)
              if (group.id != HlToolGroupId.cursor && group.tools.isNotEmpty)
                _railGroup(group, faces, large: wide),
            Container(
              width: 24,
              height: 0.5,
              margin: const EdgeInsets.symmetric(vertical: 4),
              color: c.border,
            ),
            Builder(
              builder: (anchor) => HlRailButton(
                key: const ValueKey('hl-chart-rail-more'),
                icon: Icons.more_horiz_rounded,
                label: l10n.chartMoreTools,
                large: wide,
                onTap: () =>
                    unawaited(_openRailMore(anchor, drawings, magnet)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The floating toolbar over the selected drawing (the chart places
  /// it): colour, solid or dashed, extend (trend lines), edit (notes),
  /// lock, duplicate, delete. Every change is one undoable step.
  Widget _drawingToolbar(
    ChartDrawing selected,
    ChartDrawing Function() duplicate,
  ) {
    final l10n = context.l10n;
    return HlDrawingToolbar(
      drawing: selected,
      swatches: hlDrawingSwatches(l10n),
      labels: HlDrawingToolbarLabels(
        color: l10n.chartColor,
        solid: l10n.chartLineSolid,
        dashed: l10n.chartLineDashed,
        extend: l10n.chartExtendLine,
        lock: l10n.chartLock,
        unlock: l10n.chartUnlock,
        duplicate: l10n.chartDuplicate,
        delete: l10n.chartDelete,
        editNote: l10n.chartEditNote,
        settings: l10n.settings,
      ),
      onColor: (value) => _pickColor(value, selected.id),
      onToggleDashed: () =>
          _editDrawing(selected.copyWith(dashed: !selected.dashed), 'style'),
      onToggleExtend: selected.tool == ChartDrawingTool.trendline
          ? () => _editDrawing(
              selected.copyWith(extend: !selected.extend), 'extend')
          : null,
      onToggleLock: () =>
          _editDrawing(selected.copyWith(locked: !selected.locked), 'lock'),
      onDuplicate: () {
        HapticFeedback.selectionClick();
        _onDrawingPlaced(duplicate(), via: 'duplicate');
      },
      onDelete: () {
        HapticFeedback.selectionClick();
        _drawingsNotifier.remove(selected.id);
        TrackingService.track(
          'drawing_deleted',
          params: {'via': 'delete', 'coin': widget.market.coin},
        );
        setState(() => _selectedDrawingId = null);
      },
      onEditNote: selected.tool == ChartDrawingTool.text
          ? () => unawaited(
              _editNote(selected.points.first, existing: selected))
          : null,
      onSettings: chartDrawingSpec(selected.tool).settings.isEmpty
          ? null
          : () => unawaited(_openDrawingSettings(selected)),
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
    required bool magnet,
  }) {
    final railShown = _railShown;
    final wide = KuteLayout.isExpanded(context);
    final body = Row(
      crossAxisAlignment: widget.fillHeight
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: [
        if (railShown) ...[
          SizedBox(
            height: widget.fillHeight ? null : widget.height.h,
            child: _toolRail(c, drawings, magnet),
          ),
          SizedBox(width: 6.w),
        ],
        Expanded(
          child: Stack(
            fit: widget.fillHeight ? StackFit.expand : StackFit.loose,
            children: [
              chart,
              // The rail tucked away: one small tab at the plot's top
              // left brings it back.
              if (!railShown)
                Positioned(
                  top: 6,
                  left: 0,
                  child: AppCard(
                    key: const ValueKey('hl-chart-rail-show'),
                    padding: EdgeInsets.zero,
                    radius: 12.r,
                    color: context.isDark ? c.surfaceElevated : Colors.white,
                    child: _editIconButton(
                      c,
                      icon: Icons.chevron_right_rounded,
                      tip: context.l10n.chartToolsButton,
                      onTap: _toggleRail,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    return PopScope(
      // In place on the web desk the back leaves the page, as ever.
      canPop: widget.inlineEditor,
      onPopInvokedWithResult: (didPop, _) {
        // The desk's side panel open: the back closes it, not the editor.
        if (!didPop && _drawingMode && widget.deskPanelOpen != true) {
          _toggleDrawingMode();
        }
      },
      // The editor's keys (Escape, Delete, Cmd/Ctrl+Z); focused on open,
      // or (in place, beside the order form) on a press in the chart.
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: widget.inlineEditor
            ? (_) {
                if (!_editFocus.hasFocus) _editFocus.requestFocus();
              }
            : null,
        child: Focus(
        focusNode: _editFocus,
        autofocus: !widget.inlineEditor,
        onKeyEvent: _onEditKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _editTopBar(c, candleIv),
            SizedBox(height: wide ? 10 : 6.h),
            _flexed(body),
            // The hint talks about tapping: with a mouse it is away
            // rather than telling a mouse to double-tap.
            ListenableBuilder(
              listenable: RendererBinding.instance.mouseTracker,
              builder: (context, _) =>
                  RendererBinding.instance.mouseTracker.mouseIsConnected
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: EdgeInsets.only(
                              top: 4.h,
                              left: railShown ? (wide ? 52 : 44) + 6.w : 0),
                          child: Text(
                            _toolbarHint(selectedId, drawings),
                            key: const ValueKey('hl-chart-edit-hint'),
                            style: TextStyle(
                                color: c.textTertiary, fontSize: 11.5.sp),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// The web desk's inline editor's toolbar ([HlCandleChart.inlineEditor];
  /// founder, 27 November 2026: "make the option to switch chart type more
  /// clear"): the intervals, then the chart type as a labelled choice (its
  /// icon and its name, opening the types, each with its icon and name,
  /// the current one checked), then Indicators (the Chart sheet's
  /// indicators), undo / redo at the right. The page's header names the
  /// market and its price, so neither is repeated here.
  Widget _inlineToolbar(AppColorsExtension c, HlCandleInterval candleIv) {
    final l10n = context.l10n;
    final style = _style;
    Widget chip({
      required Key key,
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool chevron = false,
    }) =>
        Material(
          key: key,
          color: context.isDark ? c.surfaceElevated : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: c.borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: c.textPrimary),
                    const SizedBox(width: 8),
                    Text(label,
                        style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    if (chevron) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down_rounded,
                          size: 18, color: c.textSecondary),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
    final typeKey = GlobalKey();
    final type = chip(
      key: const ValueKey('hl-chart-inline-type'),
      icon: _styleIcon(style),
      label: hlChartStyleName(l10n, style),
      chevron: true,
      onTap: () => unawaited(_pickInlineStyle(typeKey, style)),
    );
    final indicators = chip(
      key: const ValueKey('hl-chart-inline-indicators'),
      icon: Icons.insights_rounded,
      label: l10n.chartIndicators,
      onTap: _openIndicators,
    );
    final pills = KuteChartRangeRow(
      key: const ValueKey('hl-chart-edit-interval-row'),
      labels: [for (final iv in kHlCandleIntervals) iv.label],
      selectedIndex: kHlCandleIntervals
          .indexWhere((iv) => iv.interval == candleIv.interval),
      onSelected: (i) => _selectCandleInterval(kHlCandleIntervals[i]),
    );
    return SizedBox(
      key: const ValueKey('hl-chart-inline-toolbar'),
      height: 44,
      child: LayoutBuilder(builder: (context, constraints) {
        // The intervals fold into the interval button when the row is
        // short of room (a laptop of about 1100), never the type's name.
        final roomy = constraints.maxWidth >= 760;
        return Row(
          children: [
            if (roomy)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: pills,
              )
            else
              _intervalButton(c, l10n, candleIv),
            const SizedBox(width: 12),
            KeyedSubtree(key: typeKey, child: type),
            const SizedBox(width: 8),
            indicators,
            const Spacer(),
            _undoButton(c, l10n),
            _redoButton(c, l10n),
          ],
        );
      }),
    );
  }

  /// The chart types as a menu under the type's button, each with its icon
  /// and its name, [current] checked. A pick is stored as the Chart sheet
  /// stores it (one layout for every market).
  Future<void> _pickInlineStyle(GlobalKey anchor, HlChartStyle current) async {
    final box = anchor.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final c = context.colors;
    final l10n = context.l10n;
    final topLeft = box.localToGlobal(Offset(0, box.size.height + 4),
        ancestor: overlay);
    final picked = await showMenu<HlChartStyle>(
      context: context,
      position: RelativeRect.fromRect(
          topLeft & const Size(1, 1), Offset.zero & overlay.size),
      color: context.isDark ? c.surfaceElevated : Colors.white,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: [
        for (final s in HlChartStyle.picker)
          PopupMenuItem<HlChartStyle>(
            key: ValueKey('hl-chart-inline-type-${s.name}'),
            value: s,
            child: Row(
              children: [
                Icon(_styleIcon(s), size: 18, color: c.textPrimary),
                const SizedBox(width: 10),
                Text(hlChartStyleName(l10n, s),
                    style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 14,
                        fontWeight:
                            s == current ? FontWeight.w700 : FontWeight.w500)),
                const SizedBox(width: 16),
                if (s == current)
                  Icon(Icons.check_rounded, size: 18, color: c.textPrimary),
              ],
            ),
          ),
      ],
    );
    if (picked == null || !mounted) return;
    hlPickChartStyle(ref, widget.market, picked);
  }

  /// Indicators: the Chart sheet's indicators (the types are the
  /// toolbar's own choice beside it).
  void _openIndicators() {
    unawaited(showHlChartSheet(
      context,
      market: widget.market,
      marketKey: _marketKey,
      candles: _shownCandles ?? const <HyperliquidCandle>[],
      showYourTrades: widget.showOwnActivity,
      onAddPriceLine: _startPriceLine,
      indicatorsOnly: true,
    ));
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
    // The Funding pane: a perp's hourly history, read only while it is on
    // and kept for the session (hyperliquid_funding_history_provider.dart).
    final fundingOn =
        !widget.market.isSpot && indicators.contains(kHlFundingKey);
    final fundingHistory = fundingOn
        ? ref.watch(hlFundingHistoryProvider(widget.market.wireCoin))
        : null;
    // Pivots' real daily candles: read only while Pivots are on.
    final dailySource = indicators.contains('pp')
        ? ref
            .watch(hyperliquidDailyCandlesProvider(widget.market.wireCoin))
            .valueOrNull
        : null;
    if (!identical(dailySource, _dailySource)) {
      _dailySource = dailySource;
      _daily = dailySource == null
          ? const []
          : rescaleCandlesToDisplay(dailySource, displayPx);
    }
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
    // The position screen's clean reading chart (see positionView).
    final positionView = widget.positionView && !_drawingMode;

    // The interval row, then the chart-type button. Advanced (the
    // editing mode) opens from the host screen's "Advanced chart" row.
    final pillRow =
        Row(
          children: [
            // The seven intervals share the width (the home strip's range
            // row, KuteChartRangeRow), so every pill is whole beside the
            // chart-type button pinned on the right.
            Expanded(
              child: KuteChartRangeRow(
                key: const ValueKey('hl-interval-row'),
                labels: [for (final iv in kHlCandleIntervals) iv.label],
                selectedIndex: kHlCandleIntervals
                    .indexWhere((iv) => iv.interval == candleIv.interval),
                onSelected: (i) => _selectCandleInterval(kHlCandleIntervals[i]),
              ),
            ),
            SizedBox(width: 6.w),
            // ── Chart style: one button, a named list behind it ────────
            Tooltip(
              message: context.l10n.chartSheetTitle,
              child: GestureDetector(
                key: const ValueKey('hl-chart-sheet-button'),
                onTap: _openChartSheet,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 7.h),
                  decoration: BoxDecoration(
                    color: c.textPrimary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(9.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_styleIcon(_style),
                          size: 16.sp, color: c.textPrimary),
                      SizedBox(width: 4.w),
                      Icon(Icons.expand_more_rounded,
                          size: 14.sp, color: c.textTertiary),
                    ],
                  ),
                ),
              ),
            ),
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
            showVolume: indicators.contains('vol') && !positionView,
            renderAsLine: false,
            style: style,
            // Baseline: the open position's entry; with none, the first
            // bar on screen.
            baselinePrice: myPosition?.entryPx,
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
            indicatorParams: preferences.params,
            dailyCandles: _daily,
            funding: fundingHistory == null
                ? null
                : HlFundingFeed(
                    points: fundingHistory.points,
                    load: fundingHistory.load,
                    busy: fundingHistory.busy,
                    hourlyNow: widget.market.funding,
                  ),
            onFundingWanted: fundingOn
                ? (from) => ref
                    .read(hlFundingHistoryProvider(widget.market.wireCoin)
                        .notifier)
                    .want(from)
                : null,
            logScale: preferences.logScale,
            onLogScaleChanged: _drawingMode ? _setLogScale : null,
            // The Your trades layer: on until the sheet's square turns it
            // off on this market.
            fills: indicators.contains(kHlLayerMyTradesOff)
                ? const <HlFill>[]
                : myFills,
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
            // The header has the price: outside Advanced the reading
            // chart has no live price pill, line or tag column, its levels
            // inside the plot and the position's lines as captions.
            cleanView: !_drawingMode,
            // The tucked rail's tab sits at the plot's top left.
            legendLeftInset: _drawingMode && !_railShown ? 48 : 0,
            // The editor at the desk: the volume and the indicators in
            // panes with real height, larger axes.
            desk: _drawingMode && KuteLayout.isExpanded(context),
            positionView: positionView,
            // The interval's identity: a new one opens on its newest
            // bars.
            morphKey: 'interval:${candleIv.interval}',
            drawings: drawings,
            priceLines: ref.watch(hlPriceLinesForMarketProvider(_marketKey)),
            onPriceLineTapped: (line) => unawaited(hlConfirmRemovePriceLine(
                context, ref, line,
                decimalCap: widget.market.pxDecimalCap)),
            drawingMode: _drawingMode,
            armedTool: _armedTool,
            armedColorValue: _armedColorValue,
            magnet: preferences.magnet,
            onTextRequested: (point) => unawaited(_editNote(point)),
            selectedDrawingId: selectedId,
            onDrawingPlaced: _onDrawingPlaced,
            drawingToolbarBuilder: _drawingToolbar,
            onPlacementPendingChanged: (pending) {
              if (mounted && pending != _placementPending) {
                setState(() => _placementPending = pending);
              }
            },
            onPlacementPointsChanged: (placed) {
              if (mounted && placed != _placedPoints) {
                setState(() => _placedPoints = placed);
              }
            },
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
    // A selected drawing owns Backspace over the ticket beside it.
    final claims = _drawingMode && selectedId != null;
    if (claims || _claimsDeskKeys) {
      _claimsDeskKeys = claims;
      KuteDeskKeys.editorHoldsSelection = claims;
    }
    if (_drawingMode) {
      return _editLayout(
        c,
        chart,
        drawings: drawings,
        selectedId: selectedId,
        candleIv: candleIv,
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

// ─────────────────────────── order book ───────────────────────────

class HlOrderBookSection extends ConsumerWidget {
  final HlMarket market;
  const HlOrderBookSection({super.key, required this.market, this.fill = false});

  static const _levels = 5;

  /// THE DESK's right column (EXPANDED; founder, 25 November 2026): the
  /// section takes the height it is given, its card running to the foot,
  /// and shows as many levels a side as fit there (never fewer than
  /// five, never more than the feed sends), the spread line in the
  /// middle. False: five a side at their own height.
  final bool fill;

  /// The height of one [_DepthRow] and of the [_BookSpreadRow] in this
  /// context's text: how many levels [fill] fits.
  static ({double row, double spread}) _rowHeights(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    double line(double size) {
      final tp = TextPainter(
        text: TextSpan(
            text: '0',
            style: base.merge(TextStyle(
                fontSize: size,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()]))),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      final h = tp.height;
      tp.dispose();
      return h;
    }

    return (
      row: line(12.sp) + 9.h,
      spread: math.max(line(11.5.sp), 12.sp) + 8.h,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final bookAsync = ref.watch(hyperliquidOrderbookProvider(market.wireCoin));

    return bookAsync.when(
      // Skeleton mimicking the two-column bid/ask ladder while the book
      // first loads: 6 bid bars (left) + 6 ask bars (right).
      loading: () => Align(
        alignment: Alignment.topCenter,
        heightFactor: 1,
        child: SizedBox(
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
        Widget ladder(int levels) {
          final bids = book.bids.take(levels).toList();
          final asks = book.asks.take(levels).toList();
          var maxSz = 0.0;
          for (final l in bids) {
            if (l.sz > maxSz) maxSz = l.sz;
          }
          for (final l in asks) {
            if (l.sz > maxSz) maxSz = l.sz;
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
          );
        }

        final empty = book.bids.isEmpty && book.asks.isEmpty;
        final priceSize = Padding(
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
        );
        final card = empty
            ? Container(
                height: 60.h,
                alignment: Alignment.center,
                child: Text(
                  context.l10n.hlEmptyBook,
                  style: TextStyle(color: c.textTertiary, fontSize: 13.sp),
                ),
              )
            // Stacked depth view: asks above (best ask nearest the
            // middle), a spread row, bids below — the exchange-native
            // reading order. RepaintBoundary keeps the 250ms book
            // ticks re-rastering this card only, never the sheet.
            : RepaintBoundary(
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                  decoration: BoxDecoration(
                    color: c.surface.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: !fill
                      ? Column(children: [priceSize, ladder(_levels)])
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            priceSize,
                            Expanded(
                              child: LayoutBuilder(
                                  builder: (context, constraints) {
                                // As many a side as the card's height
                                // holds, the ladder centred on the spread
                                // (a feed with fewer leaves the room at
                                // the card's ends); short of five, five
                                // that scroll inside the card.
                                final h = _rowHeights(context);
                                final fit = ((constraints.maxHeight -
                                            h.spread) /
                                        (2 * h.row))
                                    .floor();
                                if (fit < _levels) {
                                  return SingleChildScrollView(
                                    primary: false,
                                    child: ladder(_levels),
                                  );
                                }
                                return ClipRect(
                                  child: Center(child: ladder(fit)),
                                );
                              }),
                            ),
                          ],
                        ),
                ),
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
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
            if (fill && !empty) Expanded(child: card) else card,
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

  /// The note's field. Autofocus alone left a click-opened note without
  /// the keyboard on the web (the field never took the browser's focus),
  /// so the field asks for it once the sheet is up as well.
  final FocusNode _focus = FocusNode(debugLabel: 'hl-chart-note');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final route = ModalRoute.of(context)?.animation;
      void take() {
        if (mounted && !_focus.hasPrimaryFocus) _focus.requestFocus();
      }

      if (route == null || route.isCompleted) {
        take();
        return;
      }
      void onStatus(AnimationStatus status) {
        if (!status.isCompleted) return;
        route.removeStatusListener(onStatus);
        take();
      }

      route.addStatusListener(onStatus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
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
                  focusNode: _focus,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 240,
                  decoration:
                      InputDecoration(hintText: context.l10n.chartNoteHint),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              // THE BAR IS THE BUTTON (kute_bar_context.dart): Save is the
              // floating Sal bar's primary action, riding above the
              // keyboard while the note is typed; the sheet keeps clear
              // of it.
              Padding(
                padding: EdgeInsets.all(20.w),
                child: KuteBarContextScope(
                  barContext: KuteBarContext.primary(
                    label: context.l10n.save,
                    onPrimary: () =>
                        Navigator.of(context).pop(_text.text.trim()),
                    enabled: _text.text.trim().isNotEmpty,
                    category: SearchCategory.perpetuals,
                    source: 'chart_note',
                    disabledLabel: context.l10n.barNeedNote,
                  ),
                  child: SizedBox(height: kuteBarScrollClearance.h),
                ),
              ),
            ],
          ),
        ),
      );
}


/// The web desk header's figures: [stats] less the maximum leverage (this
/// app offers no leverage talk) and the spread (an order-book figure).
@visibleForTesting
List<HlStat> deskWebStats(List<HlStat> stats, AppLocalizations l10n) => [
      for (final s in stats)
        if (s.label != l10n.chartMaxLeverage && s.label != l10n.hlSpread) s,
    ];
