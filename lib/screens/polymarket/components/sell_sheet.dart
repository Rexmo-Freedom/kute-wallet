import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/screens/shared/capability_block_note.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'dart:math' as math;
import 'package:kute/services/polymarket/hot_order_guard.dart';
import 'package:kute/screens/polymarket/components/fast_bet_scope.dart';
import 'package:kute/services/polymarket/fast_bet_window.dart';
import 'package:kute/services/polymarket/sell_settlement.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart'
    show
        PolymarketSellPriceMoved,
        polymarketCentsLabel,
        polymarketEstimatedTick,
        polymarketSellFloor,
        polymarketSellSendPrice;
import 'package:kute/services/polymarket/polymarket_slippage_defaults.dart';
import 'package:kute/services/polymarket/send_time_read.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart'
    show PolyReceiptArtwork;
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/screens/polymarket/components/polymarket_error_copy.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/trade_receipt.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/screens/shared/polymarket_fee_summary.dart';
// lib/screens/polymarket/components/sell_sheet.dart
//
// Sell shares bottom sheet for Polymarket positions.
// Allows selling partial or full position.

import 'dart:async';

import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart'
    show polymarketFeeTermsProvider;
import 'package:kute/screens/shared/sticky_action_bar.dart';
import 'package:kute/screens/shared/decimal_input_formatter.dart';
import 'package:kute/screens/shared/side_tint_palette.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:kute/services/sound_service.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart';

import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_cost_basis_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/screens/home/home_feature_carousel.dart'
    show checkPolymarketGeoblock;
import 'package:kute/screens/polymarket/components/position_sold_overlay.dart';

import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/polymarket_optimistic_activity_service.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';

// Polymarket brand colors
const Color _kPolyRed = AppColors.marketDown;

class SellSheet extends ConsumerStatefulWidget {
  final PolymarketPosition position;

  /// Surface the sheet was opened from (analytics only).
  final String source;

  const SellSheet(
      {super.key, required this.position, this.source = 'position_detail'});

  /// Route name used to identify the sell route when popping back after a
  /// sell succeeds — mirrors BetSlipSheet.routeName.
  static const routeName = 'polymarket-sell-sheet';

  static void show(BuildContext context,
      {required PolymarketPosition position,
      String source = 'position_detail'}) {
    // A resolved market cannot be sold (the CLOB rejects it as "market
    // does not exist"): it is claimed in one tap where it is shown
    // (PolyClaimButton on the card and the position screen), never here.
    if (position.isResolved) return;
    TrackingService.screenView('prediction_sell_sheet');
    TrackingService.setFlowContext(
        flow: 'polymarket_sell',
        step: 'amount',
        venue: 'polymarket',
        walletKind: 'hot');
    // Exact mirror of `BetSlipSheet.show` — same flags, same options.
    // Earlier we added an outer `Padding(viewInsets.bottom)` wrapper here
    // AND another inside the build's `Container(padding: ...)` — double
    // keyboard inset, which is what overflowed the sheet by 233 px when
    // the numpad opened. The build container alone handles the inset.
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      isDismissible: true,
      // Drag-to-dismiss bypasses PopScope (Flutter gap), so disable it —
      // tap-outside still dismisses and IS gated by the PopScope lock
      // while a sell is in flight (see build()).
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      routeSettings: const RouteSettings(name: routeName),
      builder: (_) => FastBetScope(
        active: polyIsFastBetRound(position.eventSlug),
        child: SellSheet(position: position, source: source),
      ),
    );
  }

  @override
  ConsumerState<SellSheet> createState() => _SellSheetState();
}

class _SellSheetState extends ConsumerState<SellSheet> {
  // Unit-aware amount controller. Mirrors the bet slip's
  // `_amountController` model: the user types in either their fiat
  // (USD/EUR/GBP/…) or BTC (sats/BTC per `btcFormat`), we translate
  // back to USDC via the live BTC rate and divide by `currentPrice`
  // to derive how many shares to offer to the CLOB. `_sharesToSell`
  // is the canonical sell quantity used downstream — only its
  // *source* changes with the toggle.
  late final TextEditingController _amountController;
  double _sharesToSell = 0;
  // Tracks the typed USDC value (proceeds the user wants from the
  // sell). Driven by `_amountController` via `_onAmountChanged`;
  // mirrored to `_sharesToSell` once divided by `currentPrice`.
  double _amountUsdc = 0;
  bool _isSelling = false;

  /// The CTA's label while a sale is in flight once it has moved past
  /// "Selling…" ("Sold · confirming"); null for the plain busy label.
  String? _progressLabel;

  /// The venue held the order for a live game's delay, and the shares have
  /// sold (the trade is on its way on chain). Drive the line over the CTA.
  bool _venueDelayed = false;
  bool _matched = false;

  /// The market's in-play order delay while its game is on (0 otherwise),
  /// read from the CLOB when the ticket opens.
  int _liveDelaySeconds = 0;

  /// Drives the failure notice on the ticket and turns the CTA into the
  /// retry. Cleared by a new attempt or by editing the figure.
  bool _sellFailed = false;
  String? _sellErrorMessage;
  String? _sellErrorDetails;

  /// Spot (immediate market sell) vs Limit (resting GTC sell at [_limitPrice]).
  /// Spot is the existing flow. Limit places a sell order that rests on the
  /// book until the market reaches your price — shown under Open orders.
  bool _isLimitMode = false;

  /// Limit sell price as a probability (0.01–0.99). Seeded from the live
  /// price when the user first switches to Limit.
  double _limitPrice = 0.0;
  /// The slippage picked on Advanced; null while the market's default
  /// applies (wider on a 5- or 15-minute crypto round, see
  /// polymarketDefaultSlippagePct).
  double? _slippageChoice;
  double get _slippagePct => _slippageChoice ?? _marketDefaultSlippage;
  double get _marketDefaultSlippage => polymarketDefaultSlippagePct(
      slug: pos.eventSlug,
      question: pos.marketQuestion,
      endAt: DateTime.tryParse(pos.endDateStr ?? ''));

  /// Set when a market sell stopped because the bid fell under the
  /// approved floor: the floor a new approval would name, for the retry.
  double? _sellRetryPrice;

  /// True while the Advanced route is being pushed, so a double tap on the
  /// row cannot stack two copies of the screen. Mirrors the buy slip.
  bool _openingAdvanced = false;

  /// Real best-bid pulled from the CLOB orderbook. Polymarket shows
  /// users a "current price" derived from last-trade / midprice, but
  /// the *actual* fill price on a thin book can sit far below it —
  /// sometimes by 40×+ on illiquid markets. Surfacing the live bid
  /// here means the estimated payout reflects what the user will
  /// actually receive, not a marketing number. `null` while loading
  /// or when the fetch fails — in those cases we fall back to the
  /// displayed current price and a warning is suppressed.
  double? _liquidityBid;
  Timer? _bidRefreshTimer;

  PolymarketPosition get pos => widget.position;

  // Analytics: flow timing, why it stopped, and whether an order went out.
  final DateTime _openedAt = DateTime.now();
  String _flowStep = 'amount';
  String? _stopReason;
  String? _lastErrorCategory;
  bool _sellSubmitted = false;
  String _amountMethod = 'keypad';

  List<String?> get _kindIds => [pos.tokenId, pos.marketId, pos.eventSlug];

  Map<String, Object> _kindParams() => VenueAnalytics.pmKindParams(_kindIds);

  /// What the person has entered so far (no ref reads: used in dispose).
  Map<String, Object> _sellInputs() {
    final all = _sharesToSell >= pos.size - 0.000001;
    final pct =
        pos.size > 0 ? ((_sharesToSell / pos.size) * 100).round() : 0;
    return {
      'venue': 'polymarket',
      'entry_source': widget.source,
      'wallet_kind': 'hot',
      'side': 'sell',
      ...TrackingService.moneyParams(
          amountUsd: _amountUsdc, asset: 'usdc', amount: _amountUsdc),
      'shares': (_sharesToSell * 1e6).round() / 1e6,
      'sell_scope': all ? 'all' : 'partial',
      'pct_of_position': pct.clamp(0, 100),
      'amount_method': _amountMethod,
      'order_type': _isLimitMode ? 'limit' : 'market',
      if (_isLimitMode && _limitPrice > 0)
        'limit_price': (_limitPrice * 10000).round() / 10000,
      if (!_isLimitMode) 'slippage_bps': VenueAnalytics.bps(_slippagePct),
      'advanced_used': _usesAdvanced,
      'market_outcome': pos.outcome.toLowerCase(),
      if (pos.eventSlug != null) 'market_slug': pos.eventSlug!,
      'position_resolved': pos.isResolved,
    };
  }

  void _trackStep(String step) {
    if (_flowStep == step) return;
    _flowStep = step;
    TrackingService.setFlowStep(step);
    TrackingService.track('polymarket_sell_step', params: {
      'step': step,
      ..._kindParams(),
      ..._sellInputs(),
    });
  }

  void _stopped(String reason, {Object? error}) {
    _stopReason = reason;
    if (error != null) _lastErrorCategory = TrackingService.errorCategory(error);
  }

  /// The person committed to the sale: one event per order sent, and the
  /// ticket's settings staged for polymarket_position_sold / _failed.
  void _trackSubmitted(String tokenId) {
    final inputs = _sellInputs();
    _sellSubmitted = true;
    _flowStep = 'submitted';
    TrackingService.setFlowStep('submitted');
    VenueAnalytics.stage('pm_sell', tokenId, {
      for (final k in const [
        'entry_source', 'sell_scope', 'pct_of_position', 'amount_method',
        'limit_price', 'slippage_bps', 'advanced_used',
      ])
        if (inputs[k] != null) k: inputs[k]!,
    });
    TrackingService.track('polymarket_sell_submitted', params: {
      ..._kindParams(),
      ...inputs,
      'time_in_flow_bucket': VenueAnalytics.timeInFlowBucket(
          DateTime.now().difference(_openedAt)),
    });
  }

  /// negRisk flag for [tokenId], read off the SDK position snapshot —
  /// threaded into placeOrder as the fallback when the CLOB /neg-risk
  /// probe fails (a negRisk sell signed against the plain exchange is
  /// rejected).
  bool _negRiskFor(String tokenId) {
    final sdk =
        ref.read(polymarketTradingProvider).valueOrNull?.openPositions ??
            const [];
    for (final p in sdk) {
      if (p.asset == tokenId) return p.negativeRisk;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    // Once per sheet open. Hot wallet only (Ledger sells use
    // LedgerSellSheet). Positions carry no market category.
    unawaited(VenueAnalytics.ensurePolymarket(
        slug: pos.eventSlug, ids: [pos.tokenId, pos.marketId]));
    TrackingService.polymarketSellInitiated(
      marketId: pos.tokenId ?? pos.marketId,
      walletKind: 'hot',
      extra: {
        'entry_source': widget.source,
        'position_resolved': pos.isResolved,
        if (pos.eventSlug != null) 'market_slug': pos.eventSlug!,
      },
    );
    _amountController = TextEditingController();
    _amountController.addListener(_onAmountChanged);
    // A sports market in play holds marketable orders for a few seconds
    // before matching them; the ticket says so while a sale waits.
    unawaited(pmLiveOrderDelaySeconds(pos.marketId).then((seconds) {
      if (mounted && seconds > 0) setState(() => _liveDelaySeconds = seconds);
    }));
    // Kick the first bid fetch right after the first frame so the
    // estimated payout reflects real liquidity, not the marketing
    // mid-price. Refresh every 20 s while the sheet is open — books
    // move fast on small markets.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshBid();
      _bidRefreshTimer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => _refreshBid(),
      );
    });
  }

  Future<void> _refreshBid() async {
    final tokenId = pos.tokenId;
    if (tokenId == null || tokenId.isEmpty) return;
    final model = PolymarketModel();
    try {
      final book = await model.getOrderBook(tokenId);
      if (!mounted) return;
      final bestBid = book.bestBid;
      if (bestBid == null || bestBid <= 0) {
        setState(() {
          _liquidityBid = null;
        });
        return;
      }
      setState(() {
        _liquidityBid = bestBid;
      });
    } catch (_) {
      // Keep the last quote when the provider is temporarily unavailable.
    } finally {
      model.dispose();
    }
  }

  /// USDC → user's local fiat (USD identity, EUR/GBP/BRL/… via the
  /// CoinGecko FX rate). Used to seed / re-render the input controller
  /// in fiat mode and to back out the user's typed fiat → USDC.
  double _usdcToFiat(double usdc) {
    final settings = ref.read(settingsProvider);
    if (settings.currency == 'USD') return usdc;
    final rate =
        ref.read(selectedCurrencyProviderFromUSD(settings.currency)).toDouble();
    return rate > 0 ? usdc * rate : usdc;
  }

  double _fiatToUsdc(double fiat) {
    final settings = ref.read(settingsProvider);
    if (settings.currency == 'USD') return fiat;
    final rate =
        ref.read(selectedCurrencyProviderFromUSD(settings.currency)).toDouble();
    return rate > 0 ? fiat / rate : fiat;
  }

  /// Recompute `_sharesToSell` from the current `_amountUsdc` and
  /// the live `currentPrice`. Clamped to the position's share count
  /// so the user can't oversell.
  void _recomputeSharesFromUsdc() {
    final livePrices = ref.read(livePriceProvider);
    final lp = pos.tokenId != null ? livePrices.prices[pos.tokenId] : null;
    final currentPrice = lp ?? pos.currentPrice;
    if (currentPrice <= 0) {
      _sharesToSell = 0;
      return;
    }
    final raw = _amountUsdc / currentPrice;
    _sharesToSell = raw.clamp(0.0, pos.size);
  }

  void _onAmountChanged() {
    // Fiat tab — typed value is in user's local fiat.
    final parsed = double.tryParse(_amountController.text) ?? 0.0;
    final usdc = _fiatToUsdc(parsed);
    _amountMethod = 'keypad';
    setState(() {
      // A new figure is a new attempt, so the last failure stops
      // describing it and the CTA goes back to being the Sell button.
      _sellFailed = false;
      _sellErrorMessage = null;
      _sellErrorDetails = null;
      _sellRetryPrice = null;
      _amountUsdc = usdc;
      _recomputeSharesFromUsdc();
    });
  }

  @override
  void dispose() {
    if (!_sellSubmitted) {
      try {
        TrackingService.track('polymarket_sell_abandoned', params: {
          ..._kindParams(),
          ..._sellInputs(),
          'market_id': pos.tokenId ?? pos.marketId,
          'step': _flowStep,
          'reason': _stopReason ?? 'user_closed',
          if (_lastErrorCategory != null)
            'last_error_category': _lastErrorCategory!,
          'time_in_flow_bucket': VenueAnalytics.timeInFlowBucket(
              DateTime.now().difference(_openedAt)),
        });
      } catch (_) {}
    }
    TrackingService.clearFlowContext('polymarket_sell');
    _bidRefreshTimer?.cancel();
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    super.dispose();
  }

  /// A resting limit or custom slippage is Advanced. While the policy
  /// withholds Advanced the page does not open (the tap shows the shared
  /// sheet); if it is withdrawn after a limit was set, the sale cannot
  /// submit until the order is back to a plain market sell.
  bool get _usesAdvanced =>
      _isLimitMode ||
      (_slippageChoice ?? kPolymarketDefaultSlippagePct) !=
          kPolymarketDefaultSlippagePct;

  String? get _advancedBlock => _usesAdvanced
      ? ref.watch(runtimeCapabilitiesProvider).blockReason('trading.advanced')
      : null;

  Future<void> _handleSell() async {
    if (_isSelling) return;
    setState(() {
      _isSelling = true;
      _progressLabel = null;
      _venueDelayed = false;
      _matched = false;
    });
    try {
      if (_usesAdvanced) {
        await RuntimeCapabilitiesService.instance
            .ensureAllowed('trading.advanced');
      }
      await _handleSellInner();
    } on CapabilityUnavailableException catch (e) {
      _stopped('advanced_unavailable', error: e);
      if (mounted)
        showMessageSnackBar(
            context: context, message: e.decision.message, error: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSelling = false;
          _progressLabel = null;
          _venueDelayed = false;
          _matched = false;
        });
      }
    }
  }

  Future<void> _handleSellInner() async {
    // Captured before any awaits so step labels/snackbars stay localizable
    // even after the sheet unmounts mid-flight.
    final l10n = context.l10n;
    TrackingService.track('prediction_sell_cta_tapped', params: {
      'amount_bucket': TrackingService.usdBucket(_amountUsdc),
      'denomination': 'fiat',
    });
    if (_sharesToSell <= 0 || _sharesToSell > pos.size) {
      _stopped(_sharesToSell <= 0 ? 'no_amount' : 'above_position');
      return;
    }

    final tokenId = pos.tokenId;
    if (tokenId == null || tokenId.isEmpty) {
      _stopped('outcome_unavailable');
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.cannotSellTokenUnavailable,
          error: true,
        );
      }
      return;
    }

    // Guard against re-selling a just-sold position from a stale tile —
    // the on-chain balance is already 0, so a second order would only
    // produce "not enough balance / allowance" errors. Silent (no
    // snackbar) — just close the sheet.
    if (ref.read(polymarketTradingProvider.notifier).wasRecentlySold(tokenId)) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }

    // Kute's close permission is independent of new-investment restrictions.
    // The CLOB decides whether this region permits close-only orders; do not
    // apply the buy geoblock to an otherwise permitted market or limit sell.
    if (await checkPolymarketGeoblock(context,
        capability: 'polymarket.close')) {
      _stopped('geoblocked');
      return;
    }
    if (!mounted) return;
    _trackStep('approval');

    setState(() => _isSelling = true);

    // LIMIT SELL: place a resting GTC sell at the user's target price. No
    // ladder / immediate fill — the shares stay escrowed on the book until
    // the market reaches the price. It shows up under Open orders. We do
    // NOT mark the position sold (it's still held until the order fills).
    if (_isLimitMode) {
      try {
        final price = _limitPrice.clamp(0.01, 0.99).toDouble();
        final sellShares = _sharesToSell;
        // Phase 1b.4: approve exactly this resting sell before it is signed.
        final grant = await _approveSell(
          tokenId: tokenId,
          shares: sellShares,
          worstPrice: price,
          orderType: OrderType.gtc,
        );
        if (grant == null) {
          _stopped('signing_declined');
          return;
        }
        _trackSubmitted(tokenId);
        final placed =
            await ref.read(polymarketTradingProvider.notifier).placeOrder(
                  tokenId: tokenId,
                  side: OrderSide.sell,
                  size: sellShares,
                  price: price,
                  negRisk: _negRiskFor(tokenId),
                  orderType: OrderType.gtc,
                  grant: grant,
                  marketTitle: pos.marketQuestion,
                  // Crest-first so the resting order row shows the team crest,
                  // not the generic sports ball baked into marketImage.
                  marketImage: positionCrestImage(ref, pos, listen: false),
                  marketOutcome: pos.outcome,
                );
        ref.invalidate(polymarketOpenOrdersProvider);
        // What the order did on arrival: rests whole, sold part of it
        // against bids already at the price (the rest still for sale), or
        // sold it all. One read of the order says which.
        final settlement = await _watchSale(placed,
            tokenId: tokenId, offered: sellShares, resting: true);
        TrackingService.track('polymarket_limit_sell_placed', params: {
          ..._kindParams(),
          ..._sellInputs(),
          'market_id': tokenId,
          ..._settlementParams(settlement),
        });
        try {
          await _finishSale(settlement,
              response: placed,
              tokenId: tokenId,
              limit: true,
              l10n: l10n,
              limitPrice: price);
        } catch (e, st) {
          TrackingService.recordHandled(TrackingService.errorCategory(e), e, st,
              flow: 'polymarket_sell', stage: 'finish');
        }
      } catch (e) {
        if (e is PendingPolymarketOrder || e is ResolvedPolymarketOrder) {
          await _resolveBlockedSale(resolved: e is ResolvedPolymarketOrder);
        } else if (e is AuthGrantException) {
          await _handleSellGrantFailure(e);
        } else {
          _trackSellFailed(e, 'limit');
          if (mounted) {
            showMessageSnackBar(
              context: context,
              message: polymarketErrorCopy(context, e,
                  positionPrice: pos.currentPrice),
              error: true,
            );
          }
        }
      } finally {
        if (mounted) setState(() => _isSelling = false);
      }
      return;
    }

    // Phase 1b.4: the book is read before the approval, which binds the
    // ladder's lowest price and so needs the best bid.
    final notifier = ref.read(polymarketTradingProvider.notifier);

    // Fetch the best bid from the order book to ensure immediate fill.
    // Add slippage buffer so FOK can sweep through multiple bid levels.
    final livePrices = ref.read(livePriceProvider);
    final lp = pos.tokenId != null ? livePrices.prices[pos.tokenId] : null;
    double bestBid = lp ?? pos.currentPrice;
    double? tick;
    try {
      final model = PolymarketModel();
      final book = await model.getOrderBook(tokenId);
      if (book.bestBid != null && book.bestBid! > 0) {
        bestBid = book.bestBid!;
      }
      tick = double.tryParse(book.minTickSize ?? '');
      model.dispose();
    } catch (_) {
      // Fallback to current price if order book fetch fails
    }
    if (!mounted) return;
    final sellTick = tick != null && tick > 0 && tick < 1
        ? tick
        : polymarketEstimatedTick(bestBid);

    // One rung at the slippage the user chose. The ladder used to add a
    // hidden 30% rung, so the approval bound a floor far below what the
    // sheet showed; like the buy path, what is approved is what was picked.
    final slippageLadder = <double>[_slippagePct];
    final sellShares = _sharesToSell;
    final approvedFloor = _sellRungPrice(bestBid,
        slippageLadder.reduce((a, b) => a > b ? a : b), sellTick);
    // The bid is read again while the approval is on screen (kept at most
    // a second old), so the sale is priced from the book as it is when it
    // is signed.
    final sendBook = PolymarketSendTimeRead<OrderBook>(() async {
      final model = PolymarketModel();
      try {
        return await model
            .getOrderBook(tokenId)
            .timeout(const Duration(seconds: 3));
      } finally {
        model.dispose();
      }
    }, maxAge: const Duration(seconds: 1),
        refreshEvery: const Duration(milliseconds: 700))
      ..start();
    final approval = await _approveSell(
      tokenId: tokenId,
      shares: sellShares,
      worstPrice: approvedFloor,
      orderType: OrderType.fok,
    );
    if (approval == null) {
      sendBook.cancel();
      _stopped('signing_declined');
      if (mounted) setState(() => _isSelling = false);
      return;
    }
    if (!mounted) {
      approval.revoke();
      return;
    }
    _trackSubmitted(tokenId);
    // One approval for the whole ladder: each rung gets a child grant bound
    // to exactly that rung.
    final ladder = PmLadderGrant(approval);
    final walletId = notifier.signingWalletId ?? '';

    // The progress stays on this ticket's CTA until the venue answers:
    // "Selling…", the live game's wait when the venue holds the order,
    // "Sold · confirming" once it matched, then the receipt (or the
    // reason, here on the ticket).
    try {
      // Lower clamp = 0.001 (0.1¢) instead of 0.01 (1¢) so users can
      // exit sub-cent positions at the actual market bid. With a 1¢
      // floor a YES position trading around 0.3¢ would have its
      // sell order priced at 1¢ — far above any real bid — and the
      // FOK would zero-fill, effectively trapping the user out of
      // their shares. We're not in the business of blocking exits.
      // The ladder itself is built above, before the approval.

      // The bid now: under the approved floor nothing is signed and the
      // retry names the new floor; otherwise the floor at this bid, never
      // under the approved one.
      OrderBook? freshBook;
      try {
        freshBook = await sendBook.take().timeout(const Duration(seconds: 3));
      } catch (_) {}
      final freshTick = double.tryParse(freshBook?.minTickSize ?? '');
      final sendTick =
          freshTick != null && freshTick > 0 && freshTick < 1 ? freshTick : sellTick;

      Map<String, dynamic>? response;
      double orderPrice = 0;
      Object? lastErr;
      double readResponseAmount(dynamic raw) {
        if (raw == null) return 0;
        if (raw is num) return raw.toDouble();
        if (raw is String) return double.tryParse(raw) ?? 0;
        return 0;
      }

      for (final slip in slippageLadder) {
        // Lower clamp = 0.001 (0.1¢) instead of 0.01 (1¢) so users can
        // exit sub-cent positions at the actual market bid.
        orderPrice = polymarketSellSendPrice(
                approvedFloor: approvedFloor,
                freshBid: freshBook?.bestBid,
                slippagePct: slip,
                tick: sendTick)
            .clamp(0.001, 0.99)
            .toDouble();
        if (kDebugMode) {
          debugPrint('[sell] placeOrder request: tokenId=$tokenId '
              'shares=$_sharesToSell limit=$orderPrice slippage=$slip%');
        }
        try {
          final attempt = await notifier.placeOrder(
            tokenId: tokenId,
            side: OrderSide.sell,
            size: sellShares,
            price: orderPrice,
            negRisk: _negRiskFor(tokenId),
            orderType: OrderType.fok,
            grant: ladder.rung(
              walletId: walletId,
              tokenId: tokenId,
              isBuy: false,
              size: sellShares,
              price: orderPrice,
              orderType: OrderType.fok.name,
            ),
          );
          if (kDebugMode) debugPrint('[sell] placeOrder response: $attempt');

          final filledSharesPeek = readResponseAmount(
            attempt['makingAmount'] ?? attempt['making_amount'],
          );
          final success = attempt['success'];
          final status = (attempt['status'] as String?)?.toLowerCase() ?? '';
          final orderId =
              (attempt['orderID'] ?? attempt['order_id'] ?? attempt['orderId'])
                  ?.toString();
          // V2 CLOB renamed the response key: new deployments return
          // `transactionsHashes`' successor `tradeIDs`; accept both.
          final txHashes = attempt['transactionsHashes'] ?? attempt['tradeIDs'];
          final hasTxHash = txHashes is List && txHashes.isNotEmpty;
          // The order reached the matching engine and was ACCEPTED if it
          // comes back with success:true, a matched/delayed status, an order
          // id, a tx hash, or any echoed fill amount. `delayed` is NOT a
          // failure — it's a matched order held by the CLOB's matching delay
          // that settles a moment later. Treating any of these as "didn't
          // fill" and re-entering the ladder re-submitted a SECOND order
          // against the now-empty balance, which then errored ("balance 0")
          // and reported the whole sell as failed even though the first
          // order filled — the "said it didn't fill but it did" bug.
          final accepted = success == true ||
              status == 'matched' ||
              status == 'delayed' ||
              (orderId != null && orderId.isNotEmpty) ||
              hasTxHash ||
              filledSharesPeek > 0;
          // Widen the ladder only after a documented refusal proves that
          // this submission was not accepted.
          final hardReject = success == false &&
              isDefinitivePolymarketOrderRejection(attempt['errorMsg']);
          if (!accepted && hardReject) {
            // No bids matched at this slippage — try the next (wider) rung.
            lastErr = Exception(
              (attempt['errorMsg'] as String?) ??
                  'No bids matched at this price. The book may be thin.',
            );
            continue;
          }
          // Accepted — or an ambiguous ack with no explicit rejection. Either
          // way do NOT re-submit (that risks a double-sell against a now-empty
          // balance); the position-clear poll / Data API is the source of
          // truth for whether it actually settled.
          response = attempt;
          break;
        } on AuthGrantException {
          // Past the approved cap, or the approval lapsed: stop the ladder.
          rethrow;
        } catch (e) {
          lastErr = e;
          if (e is! PolymarketOrderNotAcceptedException) rethrow;
        }
      }

      if (response == null) {
        throw lastErr ??
            Exception('No bids matched at this price. The book may be thin. '
                'Try selling a smaller amount or wait for liquidity.');
      }

      // Accepted. What became of it is read from the venue (the order,
      // then its trades on chain), and the Portfolio card says "Selling…"
      // until there is an answer.
      notifier.markPositionSelling(tokenId);
      final PmSellSettlement settlement;
      try {
        settlement = await _watchSale(response,
            tokenId: tokenId, offered: sellShares, resting: false);
      } finally {
        notifier.clearPositionSelling(tokenId);
      }
      // The order is past the point of failing now: anything thrown while
      // showing the result must not read as "Could not sell".
      try {
        await _finishSale(settlement,
            response: response, tokenId: tokenId, limit: false, l10n: l10n);
      } catch (e, st) {
        TrackingService.recordHandled(TrackingService.errorCategory(e), e, st,
            flow: 'polymarket_sell', stage: 'finish');
      }
    } catch (e) {
      if (e is PendingPolymarketOrder || e is ResolvedPolymarketOrder) {
        await _resolveBlockedSale(resolved: e is ResolvedPolymarketOrder);
        return;
      }
      if (e is AuthGrantException) {
        // Nothing was signed for the rung that stopped; back to the sheet.
        if (mounted) setState(() => _isSelling = false);
        await _handleSellGrantFailure(e);
        return;
      }
      // One terminal failure per sale (the provider no longer reports
      // per-rung rejections).
      _trackSellFailed(e, 'market');
      // _sellFailureMessage supersedes the raw _friendlyError here: it
      // adds the honest dust-sell special case (and reads the position
      // price itself) before falling back to the generic mapping.
      final moved = e is PolymarketSellPriceMoved ? e : null;
      final msg = moved != null
          ? l10n.betSellPriceMoved(polymarketCentsLabel(moved.price),
              polymarketCentsLabel(moved.limit))
          : _sellFailureMessage(e);
      // The ticket stays where it is and says what happened. The button
      // stops working and becomes the retry, and the figures are editable
      // again, so a sale that failed on the amount can be fixed in place.
      if (mounted) {
        setState(() {
          _isSelling = false;
          _progressLabel = null;
          _sellFailed = true;
          _sellErrorMessage = msg;
          _sellErrorDetails = errorDetailText(e);
          _sellRetryPrice = moved?.retryPrice;
        });
      }
    } finally {
      ladder.close();
    }
  }

  /// Follows an accepted sell order to its answer (see sell_settlement.dart)
  /// and moves the CTA along with it. Read-only: never re-submits.
  Future<PmSellSettlement> _watchSale(
    Map<String, dynamic> response, {
    required String tokenId,
    required double offered,
    required bool resting,
  }) {
    final notifier = ref.read(polymarketTradingProvider.notifier);
    final backend = notifier.backendService;
    final l10n = context.l10n;
    final originalSize = pos.size;
    var sold = 0.0;
    var tick = 0;
    // Evidence from the account itself, alongside the trades: the row is
    // gone, or its size dropped by roughly what was sold. Asked again
    // every other tick rather than waiting for the 5 s refresh.
    Future<bool> positionMoved() async {
      if (!mounted || sold <= 0) return false;
      if ((tick++).isOdd) {
        notifier.invalidateBalanceCache();
        unawaited(notifier.refresh().catchError((_) {}));
      }
      final match = ref
          .read(polymarketActivePositionsProvider)
          .where((p) => p.tokenId == tokenId)
          .firstOrNull;
      if (match == null || match.size <= 0) return true;
      final expected = (originalSize - sold).clamp(0.0, double.infinity);
      return match.size <= expected + 0.01;
    }

    return PmSellSettlementWatcher(
      readOrder: (id) async =>
          backend == null ? null : await backend.getOrderById(id),
      readTrade: backend?.getTradeById,
      positionMoved: positionMoved,
      // Long enough for the live game's delay, then a margin.
      matchTimeout: Duration(seconds: math.max(12, _liveDelaySeconds + 10)),
    ).watch(
      response: response,
      tokenId: tokenId,
      offeredShares: offered,
      resting: resting,
      cancelled: () => !mounted,
      onStage: (stage, shares) {
        if (stage == PmSellStage.matched) sold = shares;
        if (!mounted) return;
        setState(() {
          if (stage == PmSellStage.delayed) _venueDelayed = true;
          _matched = stage == PmSellStage.matched;
          _progressLabel = _matched ? l10n.betSoldConfirming : null;
        });
      },
    );
  }

  /// The analytics of how a sale ended: exact figures, no ids.
  Map<String, Object> _settlementParams(PmSellSettlement s) => {
        'fill_outcome': switch (s.result) {
          PmSellResult.filled => 'filled',
          PmSellResult.partial => 'partial',
          PmSellResult.resting => 'resting',
          PmSellResult.notFilled => 'not_filled',
          PmSellResult.failed => 'failed_onchain',
          PmSellResult.unknown => 'unknown',
        },
        'order_status': s.firstStatus.isEmpty ? 'none' : s.firstStatus,
        'live_delay': s.delayed,
        'confirmed_by': s.confirmedBy,
        'time_to_match_ms': s.timeToMatch.inMilliseconds,
        if (s.timeToConfirm != null)
          'time_to_confirm_ms': s.timeToConfirm!.inMilliseconds,
        'shares_sold': (s.soldShares * 1e6).round() / 1e6,
        if (s.proceeds != null)
          'proceeds_usd': (s.proceeds! * 100).round() / 100,
      };

  /// Ends the sale on what the venue said: the receipt for shares sold,
  /// the resting order for a limit sell that has not filled, the reason
  /// on this ticket for one that sold nothing.
  Future<void> _finishSale(
    PmSellSettlement s, {
    required Map<String, dynamic> response,
    required String tokenId,
    required bool limit,
    required AppLocalizations l10n,
    double? limitPrice,
  }) async {
    // The ticket cannot be dismissed while a sale is in flight; if it was
    // torn down anyway, the account's own refresh catches up.
    if (!mounted) return;
    final notifier = ref.read(polymarketTradingProvider.notifier);
    switch (s.result) {
      case PmSellResult.unknown:
        if (limit) {
          _showLimitPlaced(limitPrice ?? 0, s.offeredShares, l10n);
          return;
        }
        // Accepted, and the venue did not say in time what became of it.
        // Never fabricate a fill: the honest result screen, as before.
        notifier.invalidateBalanceCache();
        unawaited(notifier.refresh().catchError((_) {}));
        ref.invalidate(polymarketOpenOrdersProvider);
        await _resolveBlockedSale(probe: false);
        return;
      case PmSellResult.resting:
        _showLimitPlaced(limitPrice ?? 0, s.offeredShares, l10n);
        return;
      case PmSellResult.notFilled:
      case PmSellResult.failed:
        _trackSaleNotDone(s, limit ? 'limit' : 'market');
        notifier.invalidateBalanceCache();
        unawaited(notifier.refresh().catchError((_) {}));
        if (limit) ref.invalidate(polymarketOpenOrdersProvider);
        if (mounted) {
          setState(() {
            _isSelling = false;
            _progressLabel = null;
            _matched = false;
            _sellFailed = true;
            _sellErrorMessage = s.result == PmSellResult.failed
                ? l10n.betSaleFailedOnChain
                : l10n.betSaleNotMatched;
            _sellErrorDetails = null;
          });
        }
        return;
      case PmSellResult.filled:
      case PmSellResult.partial:
        break;
    }

    final sold = s.soldShares;
    final proceeds = s.proceeds;
    final avgPrice = s.averagePrice;
    final partialLimit = s.result == PmSellResult.partial;

    // Optimistically inject this sell into the home Activity feed so
    // the user sees a "Sold No · 9.96 shares · $1.39" row immediately,
    // instead of waiting for the Polymarket Data API to index the
    // settlement (which lags by seconds-to-minutes). The CLOB answers
    // with trade ids, not chain hashes, so the row is keyed by its trade
    // id (`clob-trade:<id>`, never shown as a transaction) and
    // self-cleans when the Data API lists the matching fill.
    // Only with the venue's own figures.
    if (proceeds != null && avgPrice != null) {
      try {
        final txHash =
            PolymarketOptimisticActivityService.optimisticTradeKey(response);
        if (txHash != null) {
          final tradingState = ref.read(polymarketTradingProvider).valueOrNull;
          final proxyWallet = tradingState?.proxyWalletAddress ?? '';
          // Look up the on-chain Position to get the conditionId.
          final position = (tradingState?.openPositions ?? const [])
              .where((p) => p.asset == tokenId)
              .firstOrNull;
          PolymarketOptimisticActivityService.record(Activity(
            proxyWallet: proxyWallet,
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            conditionId: position?.conditionId ?? '',
            type: 'TRADE',
            size: sold,
            usdcSize: proceeds,
            transactionHash: txHash,
            price: avgPrice,
            asset: tokenId,
            side: 'SELL',
            outcomeIndex: position?.outcomeIndex,
            title: pos.marketQuestion,
            slug: null,
            icon: pos.marketImage,
            eventSlug: pos.eventSlug,
            outcome: pos.outcome,
          ));
          // Push the optimistic entry into the live transaction state
          // immediately — without this, the home Activity feed only sees
          // the new row on the next background sync (~10-30s), which is
          // exactly the lag we're trying to mask.
          ref
              .read(transactionNotifierProvider.notifier)
              .refreshOptimisticPolymarketActivity();
        }
      } catch (_) {
        // Optimistic activity is a UX nicety — never block the success path.
      }
    }

    final costBeforeSale = ref.read(polymarketCostBasisProvider)[tokenId];
    // Realized P&L = proceeds − cost basis attributable to the shares
    // sold. A real cached cost (the local tracker of USDC actually moved)
    // is preferred over `pos.avgPrice * size`: the API rounds avgPrice to
    // 2 decimals and returns 0.00 on sub-cent positions. A cached cost ≈
    // shares is the old takingAmount-as-cost bug, so it falls back.
    double? pnl;
    if (proceeds != null) {
      final cachedLooksBroken = costBeforeSale != null &&
          pos.size > 0 &&
          (costBeforeSale - pos.size).abs() < 0.001;
      final effectiveCachedCost = cachedLooksBroken ? null : costBeforeSale;
      final fractionSold =
          pos.size > 0 ? (sold / pos.size).clamp(0.0, 1.0) : 0.0;
      final costAttributedToSale = effectiveCachedCost != null
          ? effectiveCachedCost * fractionSold
          : pos.avgPrice * sold;
      pnl = proceeds - costAttributedToSale;
    }

    // Revenue and the funnel only ever carry the venue's figures. A limit
    // sell is reported by polymarket_limit_sell_placed (with its fill),
    // and its provider event comes from the order placement itself, so it
    // is not logged here a second time.
    if (!limit && proceeds != null && avgPrice != null) {
      TrackingService.polymarketPositionSold(
        marketId: pos.tokenId ?? '',
        shares: sold,
        price: avgPrice,
        pnl: pnl,
        // Real order hash from the sell's CLOB response → backend attributes
        // the exact fee_usdc (synthetic fallback inside if null).
        providerOrderId:
            (response['orderID'] ?? response['order_id'])?.toString(),
        orderType: limit ? 'limit' : 'market',
        walletKind: 'hot',
        extra: {
          'sell_scope': sold >= pos.size - 0.000001 ? 'all' : 'partial',
          'pct_of_position': pos.size > 0
              ? ((sold / pos.size) * 100).round().clamp(0, 100)
              : 0,
          ..._settlementParams(s),
          if (_approval != null) 'approval': _approval!,
        },
      );
    }

    // Proceeds land in the Safe as pUSD and stay there (no unwrap, no
    // swap). The card drops (full sale) or shrinks (partial) now that the
    // trade is on chain, and the account is read again right away and
    // while the Data API catches up, instead of on the next slow tick.
    final sellingAll = sold >= pos.size - 0.000001;
    // Mark the token sold so a re-tap on a stale tile can't fire a
    // second order against the now-zero balance (see `_handleSell`). A
    // limit sell that is still partly for sale keeps its shares held.
    if (!partialLimit) notifier.markTokenSold(tokenId);
    notifier.markSoldOptimistically(tokenId: tokenId, sharesSold: sold);
    notifier.refreshAfterSale();
    if (limit) ref.invalidate(polymarketOpenOrdersProvider);

    // Selling the whole position resets the cached cost basis; selling
    // part of it scales the remaining cost so "Invested" tracks what is
    // still in the trade.
    if (sellingAll) {
      unawaited(ref
          .read(polymarketCostBasisProvider.notifier)
          .reset(tokenId)
          .catchError((_) {}));
    } else if (pos.size > 0) {
      final remainingFraction =
          ((pos.size - sold) / pos.size).clamp(0.0, 1.0);
      unawaited(ref
          .read(polymarketCostBasisProvider.notifier)
          .scaleByRemaining(tokenId, remainingFraction)
          .catchError((_) {}));
    }

    if (!mounted) return;
    SoundService.playSuccess();
    // The success haptic fires once, in the receipt overlay's entrance
    // (the shared choke point), not here as well.
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    // Crest-first (read, not watch — one-shot async context): the
    // receipt shows the same team crest as the position surfaces.
    final image = positionCrestImage(ref, pos, listen: false);
    final question = pos.marketQuestion;
    final outcome = pos.outcome;
    // Release the sale FIRST. The ticket traps itself while an order is
    // in flight, and this flag is what arms that trap, so leaving it set
    // refused the hand-off. A direct pop, not maybePop, because this is
    // the flow closing itself rather than the person leaving mid-order.
    setState(() {
      _isSelling = false;
      _progressLabel = null;
    });
    _closeTicket();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!rootNavigator.mounted) return;
      if (partialLimit) {
        // Some of a limit sell filled; the rest is still for sale at the
        // person's price and stays under Open orders.
        final at = avgPrice ?? limitPrice ?? 0;
        pushKuteSuccessOverlay(
          navigator: rootNavigator,
          overlay: KuteConfirmation(
            message: l10n.betLimitSellPartial(
              sold.toStringAsFixed(2),
              s.offeredShares.toStringAsFixed(2),
              _formatPriceCompact(at),
              s.remainingShares.toStringAsFixed(2),
            ),
            detail: l10n.betRestingSellNote,
            onDone: rootNavigator.pop,
            receipt: TradeReceipt(
              leading: PolyReceiptArtwork(url: image),
              title: question,
              subtitle: outcome,
              rows: {
                l10n.betShares: sold.toStringAsFixed(2),
                if (proceeds != null)
                  l10n.betSaleProceeds: '\$${proceeds.toStringAsFixed(2)}',
              },
            ),
          ),
        );
        return;
      }
      pushPositionSoldOverlay(
        navigator: rootNavigator,
        marketQuestion: question,
        marketImage: image,
        outcome: outcome,
        shares: sold,
        proceeds: proceeds,
        pnl: pnl,
        // Matched, and the chain had not shown it within the wait: the
        // sale stands, and the balance follows in a moment.
        note: s.confirmedBy == 'timeout' ? l10n.betSaleSettlingNote : null,
      );
    });
  }

  /// The resting limit sell's confirmation, as it always was.
  void _showLimitPlaced(double price, double shares, AppLocalizations l10n) {
    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    setState(() => _isSelling = false);
    _closeTicket();
    pushKuteSuccessOverlay(
        navigator: navigator,
        overlay: KuteConfirmation(
          message:
              l10n.betLimitSellPlaced('${(price * 100).toStringAsFixed(2)}¢'),
          detail: l10n.betRestingSellNote,
          onDone: navigator.pop,
          receipt: TradeReceipt(
              title: pos.marketQuestion,
              subtitle: pos.outcome,
              rows: {l10n.betShares: shares.toStringAsFixed(2)}),
        ));
  }

  /// A sale the venue accepted that sold nothing (killed at the end of a
  /// live game's delay) or whose trade failed on chain.
  void _trackSaleNotDone(PmSellSettlement s, String orderType) {
    final reason =
        s.result == PmSellResult.failed ? 'failed_onchain' : 'not_filled';
    _lastErrorCategory = reason;
    TrackingService.track('polymarket_sell_failed', params: {
      ..._kindParams(),
      ..._sellInputs(),
      'market_id': pos.tokenId ?? pos.marketId,
      'reason': reason,
      'error_category': reason,
      'order_type': orderType,
      'wallet_kind': 'hot',
      'amount_bucket': TrackingService.usdBucket(_amountUsdc),
      ..._settlementParams(s),
    });
  }

  /// Fixed category only — the raw error can carry order details.
  void _trackSellFailed(Object e, String orderType, [StackTrace? st]) {
    final category = TrackingService.errorCategory(e);
    _lastErrorCategory = category;
    TrackingService.recordHandled(category, e, st,
        flow: 'polymarket_sell', stage: orderType);
    TrackingService.track('polymarket_sell_failed', params: {
      ..._kindParams(),
      ..._sellInputs(),
      'market_id': pos.tokenId ?? pos.marketId,
      'reason': category,
      'error_category': category,
      'order_type': orderType,
      'wallet_kind': 'hot',
      'amount_bucket': TrackingService.usdBucket(_amountUsdc),
    });
  }

  /// Closes the ticket, and the Advanced page if it is still above it,
  /// before a receipt is shown. By route name rather than a plain pop,
  /// the way the bet slip closes itself: it does not care what is on top
  /// and it is not subject to the in-flight trap, which is what refused
  /// the hand-off and left a finished sale sitting under its own receipt.
  void _closeTicket() {
    Navigator.of(context, rootNavigator: true)
        .popUntil((route) => route.settings.name != SellSheet.routeName);
  }

  /// The guard would not let this sale through because an earlier
  /// submission is unaccounted for. Finding out what happened to it is
  /// work, so it happens here, behind the CTA that is still spinning, and
  /// the person only ever sees the answer.
  ///
  /// The screen this ends on is a result, never a progress bar: it is
  /// reached once, after the button has finished, and it carries no
  /// "check its status" button because there is nothing left to ask.
  ///
  /// [probe] is false when the order WAS accepted and only its fill is
  /// unconfirmed: there is no earlier submission to account for, so
  /// asking would answer a question nobody posed.
  Future<void> _resolveBlockedSale(
      {bool resolved = false, bool probe = true}) async {
    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final l10n = context.l10n;
    var read = resolved;
    if (!resolved && probe) {
      // The guard already retries the read itself; these rounds cover a
      // venue that is briefly unreachable rather than one that refuses.
      final notifier = ref.read(polymarketTradingProvider.notifier);
      for (var attempt = 0; attempt < 3 && !read; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
        }
        try {
          await notifier.checkPendingOrder();
          read = true;
        } on ResolvedPolymarketOrder {
          read = true;
        } catch (_) {
          // Still unaccounted for. Try again, then say so.
        }
      }
      TrackingService.track('sell_pending_check_result',
          params: {'read': read});
    }
    if (!mounted) return;
    setState(() => _isSelling = false);
    _closeTicket();
    pushKuteSuccessOverlay(
      navigator: navigator,
      overlay: KuteConfirmation(
        message: read ? l10n.betSaleStatusChecked : l10n.betSalePending,
        detail:
            read ? l10n.betSaleStatusCheckedDetail : l10n.betSalePendingDetail,
        success: read,
        showCloseButton: true,
        buttonText: l10n.done,
        onDone: navigator.pop,
      ),
    );
  }

  /// The limit price of one sell ladder rung. The lower clamp is 0.001
  /// (0.1¢) so sub-cent positions can exit at the real bid.
  /// The lowest price the sell accepts: the slippage rounded up to the
  /// tick, with one tick of room at least (polymarketSellFloor).
  static double _sellRungPrice(double bestBid, double slip, double tick) =>
      polymarketSellFloor(bid: bestBid, slippagePct: slip, tick: tick)
          .clamp(0.001, 0.99)
          .toDouble();

  /// Phase 1b.4. Prompts for selling [shares] of [tokenId] at no less than
  /// [worstPrice]. Null when declined or there is no signing wallet.
  Future<AuthGrant?> _approveSell({
    required String tokenId,
    required double shares,
    required double worstPrice,
    required OrderType orderType,
  }) async {
    final walletId =
        ref.read(polymarketTradingProvider.notifier).signingWalletId;
    if (walletId == null || walletId.isEmpty) {
      unawaited(ref
          .read(polymarketTradingProvider.notifier)
          .enableTrading()
          .catchError((_) {}));
      showMessageSnackBar(
        context: context,
        message: context.l10n.receiveUsdcWalletNotReady,
        error: true,
      );
      return null;
    }
    final grant = await requireFreshAuthGrant(
      context,
      ref,
      intent: PmGrants.sellReview(
        walletId: walletId,
        tokenId: tokenId,
        shares: shares,
        worstPrice: worstPrice,
        orderType: orderType.name,
      ),
      reason: context.l10n.stepUpReasonSell,
      amountUsd: shares * pos.currentPrice,
      fastBet: FastBetRequest(eventSlug: pos.eventSlug, hot: true),
    );
    _approval =
        grant == null ? null : FastBetWindow.approvalParam(grant.method);
    return grant;
  }

  /// How the last sell on this ticket was approved (the `approval` value
  /// of polymarket_position_sold).
  String? _approval;

  /// A grant failure stopped the sell before that order was signed. Drift
  /// shows "Review again" (C8); an expired approval says so.
  Future<void> _handleSellGrantFailure(AuthGrantException e) async {
    if (!mounted) return;
    final l10n = context.l10n;
    await handleGrantFailure(context, e, action: SensitiveAction.pmSell);
    if (e is! ReauthRequired && mounted) {
      showMessageSnackBar(
        context: context,
        message: l10n.stepUpApprovalExpired,
        error: true,
      );
    }
  }

  /// Failure copy with one special case: a no-liquidity reject on a
  /// position that's trading at effectively zero (outcome all but
  /// decided against the holder — e.g. a YES on an eliminated team).
  /// The generic "try a smaller amount or wait for more buyers" is a
  /// lie there: no amount fills against an empty bid side and buyers
  /// aren't coming back. Say what's actually true — the shares can't
  /// be sold, and the position becomes clearable once the market
  /// resolves.
  String _sellFailureMessage(Object e) {
    final s = e.toString().toLowerCase();
    final noLiquidity = s.contains('fok') ||
        s.contains('fully filled') ||
        s.contains('no bids matched');
    final noBuyers = _liquidityBid == null || _liquidityBid! <= 0.01;
    final dustPrice = pos.currentPrice <= 0.02;
    if (noLiquidity && (noBuyers || dustPrice)) {
      return context.l10n.predictDustSellError;
    }
    return polymarketErrorCopy(context, e);
  }

  // ── Spot / Limit (sell) ───────────────────────────────────────────────

  /// Push the Advanced page, the way the buy slip does: a full-screen
  /// dialog route on the ROOT navigator, which is why it keeps the app
  /// palette. The tinted palette is installed by the `SideTintedSubtree`
  /// inside this sheet's own build, so a route pushed from above it never
  /// inherits the red (user decision: only sheets wear the side colour).
  ///
  /// The sheet does not hand the screen its state object — the sell sheet
  /// keeps plain State fields. The screen is seeded with the current
  /// values, the typed amount included, and returns the edited ones,
  /// which are applied here on pop. Its Sell button returns too: the
  /// sale runs from this sheet so there is one selling path and the
  /// progress lands on the CTA the person is already looking at.
  Future<void> _openAdvanced() async {
    if (_openingAdvanced || _isSelling) return;
    // Withheld Advanced opens nothing; the shared sheet says why.
    if (!advancedTradingOffered(
        context, ref.read(runtimeCapabilitiesProvider))) {
      return;
    }
    _openingAdvanced = true;
    FocusManager.instance.primaryFocus?.unfocus();
    HapticFeedback.selectionClick();
    TrackingService.track('sell_sheet_advanced_opened');
    _trackStep('advanced');
    final livePrices = ref.read(livePriceProvider);
    final lp = pos.tokenId != null ? livePrices.prices[pos.tokenId] : null;
    final currentPrice = lp ?? pos.currentPrice;
    try {
      final result = await Navigator.of(context, rootNavigator: true)
          .push<_SellAdvancedResult>(
        MaterialPageRoute(
          fullscreenDialog: true,
          settings: const RouteSettings(name: SellSheet.routeName),
          builder: (_) => _SellAdvancedScreen(
            position: pos,
            currentPrice: currentPrice,
            isLimitMode: _isLimitMode,
            limitPrice: _limitPrice,
            slippagePct: _slippagePct,
            amountText: _amountController.text,
            fiatToUsdc: _fiatToUsdc,
            marketDefaultSlippagePct: _marketDefaultSlippage,
          ),
        ),
      );
      if (!mounted || result == null) return;
      setState(() {
        _isLimitMode = result.isLimitMode;
        _limitPrice = result.limitPrice;
        if (result.slippagePct != _slippagePct) {
          _slippageChoice = result.slippagePct;
        }
      });
      // The page carries the amount too, so whatever it was left on comes
      // back through the controller (which recomputes the shares).
      if (_amountController.text != result.amountText) {
        _amountController.text = result.amountText;
        _amountController.selection = TextSelection.fromPosition(
          TextPosition(offset: result.amountText.length),
        );
      }
      // Its Sell button is the real one: it popped so the sheet's own CTA
      // could carry the progress, and the sale runs from here.
      if (result.submit) _handleSell();
    } finally {
      _openingAdvanced = false;
    }
  }

  /// Re-run the sell after a failure. Drops the notice, so the ticket is
  /// back to a plain sell before the button starts working again. A new
  /// sale is a new approval and a new order; nothing is re-sent.
  void _retrySell() {
    if (!mounted) return;
    setState(() {
      _sellFailed = false;
      _sellRetryPrice = null;
      _sellErrorMessage = null;
      _sellErrorDetails = null;
    });
    _handleSell();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Only rebuild when this position's token price changes.
    final livePrice = ref.watch(livePriceProvider
        .select((s) => pos.tokenId != null ? s.prices[pos.tokenId] : null));
    final currentPrice = livePrice ?? pos.currentPrice;
    final livePnl = (currentPrice - pos.avgPrice) * pos.size;
    final livePnlPct = pos.avgPrice > 0
        ? ((currentPrice - pos.avgPrice) / pos.avgPrice) * 100
        : 0.0;
    final currentValue = pos.size * currentPrice;
    final canSell = _sharesToSell > 0 && _sharesToSell <= pos.size;

    // A sale in flight keeps its ticket until the venue has answered. The
    // progress is carried by the CTA, the controls go inert underneath it,
    // and the sheet cannot be dismissed out from under the order. A limit
    // sell waits too, for the one read that says whether it rested, sold
    // part, or sold it all.
    final activelySelling = _isSelling;

    // While a sale waits on a live game's in-play delay, the line over
    // the CTA says why it is taking a moment.
    final delayNote = activelySelling &&
            !_matched &&
            _liveDelaySeconds > 0 &&
            (_venueDelayed || !_isLimitMode)
        ? context.l10n.polyGameInPlayDelay('$_liveDelaySeconds')
        : null;

    final orderPrice = _isLimitMode ? _limitPrice : currentPrice;

    // Selling is money coming out, so the ticket wears the red side the
    // same way the buy slip wears the outcome's colour: the whole subtree
    // is handed the tinted palette and every child that reads
    // `context.colors` follows without knowing about it.
    //
    // Nothing inside the tinted subtree opens a sheet of its own. The
    // step-up PIN gate, the geoblock wall and the error snackbars are all
    // raised from `State.context`, which sits ABOVE this wrapper, so the
    // theme `showModalBottomSheet` captures for them is the app's real
    // palette rather than translucent ink meant for a red surface.
    const sideColor = AppColors.marketDown;
    final tc = sideTintPalette(c, sideColor);

    final viewInsetBottom = MediaQuery.of(context).viewInsets.bottom;

    final form = Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The sell ticket's side block: what is being sold, what it is
          // worth right now. Inert, so it stays on the quietest step.
          _buildPositionCard(tc, currentValue, livePnl, livePnlPct),
          SizedBox(height: 8.h),
          Text(
            context.l10n.betAvgNowPrice(_formatPriceCompact(pos.avgPrice),
                _formatPriceCompact(currentPrice)),
            style: TextStyle(
              color: tc.textSecondary,
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 22.h),
          // One big typed figure, the share equivalent and the position's
          // value underneath. There is no TextField on this step, so the
          // OS keyboard never opens over the ticket; the pinned keypad
          // below the form is the only way in.
          BigAmountDisplay(
            prefix: polyDisplayLabel(ref),
            amountText: _amountController.text,
            conversionLabel: _sharesToSell > 0
                ? '≈ ${context.l10n.betSharesCount(_sharesToSell.toStringAsFixed(2))}'
                : null,
            availableLabel:
                '${context.l10n.available} ${formatPolyAmount(ref, currentValue)}',
            availableExceeded: _amountUsdc > currentValue,
            // One small Max chip beside the figure, as on the buy slips:
            // it fills the whole position (every share), and brings that
            // back after an edit. Nothing to sell, no chip.
            trailing: pos.size > 0 && currentValue > 0
                ? AmountMaxChip(
                    label: context.l10n.max,
                    semanticLabel: context.l10n.amountUseMaximum,
                    onTap: _isSelling
                        ? null
                        : () {
                            _setSellFraction(1);
                            _amountMethod = 'max';
                            TrackingService.track(
                                'sell_sheet_available_tapped');
                          },
                  )
                : null,
          ),
          SizedBox(height: 24.h),
          // The estimated fee, and nothing else (owner decision): no
          // proceeds line before it and none after it.
          PolymarketFeeSummary(
              tokenId: pos.tokenId,
              shares: _sharesToSell,
              price: orderPrice,
              bitcoinFirst: false,
              limit: _isLimitMode),
          SizedBox(height: 8.h),
          PolySlipAdvancedRow(
            trailingText: _isLimitMode
                ? context.l10n.betSlipLimitAt(
                    '${(_limitPrice * 100).toStringAsFixed(1)}¢')
                : null,
            onTap: _openAdvanced,
          ),
          if (_advancedBlock case final reason?)
            CapabilityBlockNote(reason, padding: EdgeInsets.only(top: 10.h)),
          // A sale that did not go through says so here, on the ticket
          // the person is still looking at, and the CTA underneath
          // becomes the retry the locked panel used to carry.
          if (_sellFailed) ...[
            SizedBox(height: 12.h),
            PolySlipNotice(
              title: context.l10n.betCouldNotSell,
              message:
                  _sellErrorMessage ?? context.l10n.betSharesSafeRetryOrClose,
              details: _sellErrorDetails,
            ),
          ],
          SizedBox(height: 12.h),
        ],
      ),
    );

    return PopScope(
      // An in-flight spot sell cannot be dismissed out from under itself.
      // A limit order pops its own sheet, and a failed sale is terminal,
      // so neither traps anything.
      canPop: !activelySelling,
      child: KeyboardDismissOnTap(
        child: SideTintedSubtree(
          side: sideColor,
          child: Container(
            // Bottom-modal chrome — the buy slip's, to the pixel: the side
            // colour as the fill, rounded-top corners, keyboard inset, max
            // 92% screen height. Sized to content (mainAxisSize.min on the
            // inner Column) so the sheet doesn't stretch to full screen.
            padding: EdgeInsets.only(bottom: viewInsetBottom),
            decoration: BoxDecoration(
              color: sideColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
              border: Border(top: BorderSide(color: tc.border)),
            ),
            child: SafeArea(
              bottom: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (MediaQuery.of(context).size.height * 0.92 -
                          viewInsetBottom)
                      .clamp(0.0, double.infinity),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PolySlipHeader(
                      marketQuestion: pos.marketQuestion,
                      marketImage: pos.marketImage,
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        primary: false,
                        child: IgnorePointer(
                            ignoring: activelySelling, child: form),
                      ),
                    ),
                    // The sheet's only amount input, pinned under the
                    // scrolling form so the figure above it never hides
                    // behind a keyboard.
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.w),
                      child: AmountKeypad(
                        value: _amountController.text,
                        maxDecimals: 2,
                        enabled: !_isSelling,
                        onChanged: (v) => _amountController.text = v,
                      ),
                    ),
                    // The greater of a comfortable gap and the system
                    // inset, never both. See the buy slip's action row.
                    if (delayNote != null)
                      Padding(
                        padding: EdgeInsets.fromLTRB(20.w, 6.h, 20.w, 0),
                        child: Text(
                          delayNote,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: tc.textSecondary,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                          20.w,
                          8.h,
                          20.w,
                          math.max(
                              16.h, MediaQuery.of(context).padding.bottom)),
                      child: PolySlipCta(
                        color: sideColor,
                        isBusy: _isSelling,
                        enabled:
                            canSell && !_isSelling && _advancedBlock == null,
                        onTap: _sellFailed ? _retrySell : _handleSell,
                        // "Selling…" → "Sold · confirming" once it matched.
                        busyLabel:
                            _progressLabel ?? context.l10n.betSellingEllipsis,
                        label: _sellFailed
                            ? (_sellRetryPrice != null
                                ? context.l10n.betRetryAtPrice(
                                    polymarketCentsLabel(_sellRetryPrice!))
                                : context.l10n.retry)
                            : _isLimitMode
                                ? (canSell
                                    ? context.l10n.betPlaceLimitAtPrice(
                                        '${(_limitPrice * 100).toStringAsFixed(1)}¢')
                                    : context.l10n.betPlaceLimit)
                                : (canSell
                                    ? '${context.l10n.sell} · ${formatPolyAmount(ref, _amountUsdc)}'
                                    : context.l10n.sell),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The sell ticket's side block. Mirrors the buy slip's selected-outcome
  /// card: an inert identity panel stating what is being sold and what it
  /// is worth, on the quietest tier of the tinted palette.
  ///
  /// The outcome pill is neutral here on purpose. The sheet's own red
  /// already means "selling", so a second directional fill beside it (a
  /// red NO pill on a red sheet) would both vanish and lie. The gain and
  /// loss line keeps its sign, and reads through `success` / `error`,
  /// which the tinted palette collapses onto the contrast ink.
  Widget _buildPositionCard(AppColorsExtension c, double currentValue,
      double livePnl, double livePnlPct) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  pos.outcome.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  context.l10n.betSharesCount(pos.size.toStringAsFixed(1)),
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatPolyAmount(ref, currentValue),
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                  letterSpacing: -0.3,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              SizedBox(height: 3.h),
              Text(
                '${livePnl >= 0 ? '+' : '-'}${formatPolyAmount(ref, livePnl.abs())} '
                '${livePnlPct >= 0 ? '+' : ''}${livePnlPct.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: livePnl >= 0 ? c.success : c.error,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Set the sell input as a fraction (0..1) of the user's position.
  /// 1.0 → "Max" uses `pos.size` exactly so the FOK ladder gets the
  /// same numbers the old `_sellAll` produced; the 5%-of-`pos.size`
  /// "sellingAll" detection downstream still classifies this as a
  /// full exit. The input field is seeded in the active unit (fiat
  /// or BTC) — mirrors the bet slip's quick-chip behaviour.
  void _setSellFraction(double fraction) {
    final clamped = fraction.clamp(0.0, 1.0);
    final shares = clamped >= 1.0 ? pos.size : pos.size * clamped;
    final livePrices = ref.read(livePriceProvider);
    final lp = pos.tokenId != null ? livePrices.prices[pos.tokenId] : null;
    final currentPrice = lp ?? pos.currentPrice;
    final usdc = shares * currentPrice;
    final String seed;
    {
      final fiat = _usdcToFiat(usdc);
      seed = fiat <= 0
          ? ''
          : (fiat == fiat.roundToDouble()
              ? fiat.toStringAsFixed(0)
              : fiat.toStringAsFixed(2));
    }
    _amountController.text = seed;
    _amountController.selection = TextSelection.fromPosition(
      TextPosition(offset: seed.length),
    );
    setState(() {
      _amountUsdc = usdc;
      _sharesToSell = shares;
    });
    HapticFeedback.selectionClick();
  }

  /// Compact ¢/$ share-price formatter that mirrors
  /// position_detail_sheet's `_formatSharePrice`. Sub-dollar prices
  /// read as cents with one decimal (`9.0¢`), $1+ flips to dollar
  /// formatting. Keeps the summary one-liner readable on sub-cent
  /// positions where two-decimal $ rounds to "$0.00".
  String _formatPriceCompact(double v) {
    if (v >= 1.0) return '\$${v.toStringAsFixed(2)}';
    final cents = v * 100;
    if (cents >= 10) return '${cents.toStringAsFixed(0)}¢';
    return '${cents.toStringAsFixed(1)}¢';
  }
}

/// Segmented slippage chip — dark primary fill when selected (accent
/// tints on chips rejected — solid color / dark primary only), neutral
/// surface + primary text when not. Reuses the same shape + padding as
/// the bet slip's slippage row so muscle memory carries.
class _SlippageChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SlippageChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // On a side-tinted sheet the selected chip inverts — the sheet's ink
    // becomes the fill and the side colour becomes the label — because a
    // dark primary fill reads as a smudge on saturated red.
    final tint = SheetTint.maybeOf(context);
    final selectedFill = tint?.on ?? context.ctaFill;
    final selectedInk = tint?.side ?? context.ctaOnColor;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: selected ? selectedFill : c.surfaceLight,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(
            color: selected ? selectedFill : c.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? selectedInk : c.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// What the Advanced page hands back to the sell sheet when it pops.
/// The sell sheet keeps its order state in plain `State` fields, so the
/// page is seeded with copies and returns copies — nothing is shared.
///
/// [submit] is the page's own Sell action. The page carries the whole
/// ticket, so its primary action has to be the real one; it pops first
/// and the sheet runs the sale, which keeps one selling path rather than
/// a second copy of the ladder living up here.
class _SellAdvancedResult {
  const _SellAdvancedResult({
    required this.isLimitMode,
    required this.limitPrice,
    required this.slippagePct,
    required this.amountText,
    required this.submit,
  });

  final bool isLimitMode;
  final double limitPrice;
  final double slippagePct;
  final String amountText;
  final bool submit;
}

/// The sell ticket's Advanced page, built the way the buy slip's is: the
/// whole ticket on one screen, grouped into sections — what you hold, how
/// much of it you are selling, how the order rests, what it comes to —
/// on the app palette, under a back button and a centred title.
///
/// It used to be a small settings page with an order-type toggle and a
/// slippage row, which is a different thing from the buy slip's Advanced
/// and read as one. The shared pieces now live in `slip_chrome.dart`, so
/// the two pages cannot drift apart again.
///
/// It is pushed as a full-screen dialog on the root navigator, so it sits
/// ABOVE the sheet's `SideTintedSubtree` and keeps the app palette. Only
/// sheets wear the side colour.
class _SellAdvancedScreen extends ConsumerStatefulWidget {
  const _SellAdvancedScreen({
    required this.position,
    required this.currentPrice,
    required this.isLimitMode,
    required this.limitPrice,
    required this.slippagePct,
    required this.amountText,
    required this.fiatToUsdc,
    this.marketDefaultSlippagePct = kPolymarketDefaultSlippagePct,
  });

  final PolymarketPosition position;
  final double currentPrice;
  final bool isLimitMode;
  final double limitPrice;
  final double slippagePct;

  /// The market's own default (wider on a short crypto round): not an
  /// Advanced choice.
  final double marketDefaultSlippagePct;

  /// The figure as the sheet's keypad left it, in the user's currency.
  final String amountText;

  /// The sheet's own conversion, so the page reads the same rate rather
  /// than growing a second copy of it.
  final double Function(double) fiatToUsdc;

  static const slippageOptions = [1.0, 2.0, 5.0, 10.0];

  @override
  ConsumerState<_SellAdvancedScreen> createState() =>
      _SellAdvancedScreenState();
}

class _SellAdvancedScreenState extends ConsumerState<_SellAdvancedScreen> {
  late bool _isLimitMode = widget.isLimitMode;
  late double _limitPrice = widget.limitPrice > 0
      ? widget.limitPrice
      : widget.currentPrice.clamp(0.01, 0.99).toDouble();
  late double _slippagePct = widget.slippagePct;
  late final TextEditingController _amountController =
      TextEditingController(text: widget.amountText);
  bool _detailsOpen = false;

  PolymarketPosition get pos => widget.position;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    super.dispose();
  }

  void _onAmountChanged() => setState(() {});

  /// The typed figure in USDC. The page types in the user's currency and
  /// the order is sized in USDC, exactly as the sheet does.
  double get _amountUsdc =>
      widget.fiatToUsdc(double.tryParse(_amountController.text) ?? 0.0);

  double get _positionValue => pos.size * widget.currentPrice;

  /// Shares the order will offer, clamped to what is actually held.
  double get _sharesToSell {
    if (widget.currentPrice <= 0) return 0;
    return (_amountUsdc / widget.currentPrice).clamp(0.0, pos.size).toDouble();
  }

  bool get _canSell => _sharesToSell > 0 && _sharesToSell <= pos.size;

  /// Mirrors the sheet: the page is always reachable, the sale is not.
  bool get _usesAdvanced =>
      _isLimitMode ||
      (_slippagePct != kPolymarketDefaultSlippagePct &&
          _slippagePct != widget.marketDefaultSlippagePct);

  String? get _advancedBlock => _usesAdvanced
      ? ref.watch(runtimeCapabilitiesProvider).blockReason('trading.advanced')
      : null;

  _SellAdvancedResult _result({required bool submit}) => _SellAdvancedResult(
        isLimitMode: _isLimitMode,
        limitPrice: _limitPrice,
        slippagePct: _slippagePct,
        amountText: _amountController.text,
        submit: submit,
      );

  void _close() {
    TrackingService.track('sell_sheet_advanced_applied', params: {
      'order_type': _isLimitMode ? 'limit' : 'spot',
      'slippage_pct': _slippagePct,
    });
    Navigator.of(context).pop(_result(submit: false));
  }

  /// The page's primary action. It pops first and the sheet underneath
  /// runs the sale, so the ladder, the approval and the fill check stay
  /// where they are and the progress shows on the sheet's own button.
  void _sell() {
    if (!_canSell) return;
    HapticFeedback.mediumImpact();
    TrackingService.track('sell_sheet_advanced_sell_tapped', params: {
      'order_type': _isLimitMode ? 'limit' : 'spot',
    });
    Navigator.of(context).pop(_result(submit: true));
  }

  /// What is being sold, and what the whole holding is worth. Inert: the
  /// page's one editable figure is the amount.
  Widget _positionBlock(AppColorsExtension c) {
    final livePnl = (widget.currentPrice - pos.avgPrice) * pos.size;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                pos.outcome.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                context.l10n.betSharesCount(pos.size.toStringAsFixed(2)),
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 12.w),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatPolyAmount(ref, _positionValue),
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
                letterSpacing: -0.3,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            SizedBox(height: 3.h),
            Text(
              '${livePnl >= 0 ? '+' : '-'}${formatPolyAmount(ref, livePnl.abs())}',
              style: TextStyle(
                color: livePnl >= 0 ? c.success : c.error,
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _orderTypeToggle(AppColorsExtension c) {
    Widget seg(String label, bool isLimit) {
      final selected = _isLimitMode == isLimit;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_isLimitMode == isLimit) return;
            HapticFeedback.selectionClick();
            setState(() {
              _isLimitMode = isLimit;
              if (isLimit && _limitPrice <= 0) {
                _limitPrice = widget.currentPrice.clamp(0.01, 0.99).toDouble();
              }
            });
          },
          child: Container(
            height: 38.h,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? c.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9.r),
              border: selected ? Border.all(color: c.border) : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? c.textPrimary : c.textTertiary,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(3.w),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: c.border),
      ),
      child: Row(children: [
        seg(context.l10n.betOrderTypeSpot, false),
        seg(context.l10n.betOrderTypeLimit, true),
      ]),
    );
  }

  Widget _limitPriceInput(AppColorsExtension c) {
    void bump(double deltaCents) {
      final next =
          (((_limitPrice * 100) + deltaCents).clamp(1.0, 99.0)) / 100.0;
      HapticFeedback.selectionClick();
      setState(() => _limitPrice = next);
    }

    Widget step(IconData icon, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 42.sp,
            height: 36.sp,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: c.border),
            ),
            child: Icon(icon, size: 18.sp, color: c.textPrimary),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              context.l10n.betSellAt,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _limitPrice =
                  widget.currentPrice.clamp(0.01, 0.99).toDouble()),
              behavior: HitTestBehavior.opaque,
              child: Text(
                context.l10n.betMarketPrice(
                    '${(widget.currentPrice * 100).toStringAsFixed(1)}¢'),
                style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                    decoration: TextDecoration.underline,
                    decorationColor: c.textPrimary),
              ),
            ),
          ],
        ),
        SizedBox(height: 8.h),
        Container(
          decoration: BoxDecoration(
            color: c.surfaceLight,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: c.border),
          ),
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
          child: Row(
            children: [
              step(Icons.remove_rounded, () => bump(-1)),
              Expanded(
                child: Center(
                  child: Text(
                    '${(_limitPrice * 100).toStringAsFixed(1)}¢',
                    style: TextStyle(
                      fontSize: 22.sp,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ),
              step(Icons.add_rounded, () => bump(1)),
            ],
          ),
        ),
        SizedBox(height: 6.h),
        Text(
          context.l10n.betLimitRestsOnBook,
          style: TextStyle(fontSize: 12.sp, color: c.textTertiary, height: 1.3),
        ),
      ],
    );
  }

  Widget _slippageRow(AppColorsExtension c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.maxSlippage,
            style: TextStyle(
                color: c.textSecondary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w500)),
        SizedBox(height: 10.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            for (final opt in _SellAdvancedScreen.slippageOptions)
              _SlippageChip(
                label: '${opt.toStringAsFixed(0)}%',
                selected: _slippagePct == opt,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _slippagePct = opt);
                },
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final orderPrice = _isLimitMode ? _limitPrice : widget.currentPrice;
    final sellingAll = _sharesToSell >= pos.size - 0.000001;
    final amountStr = formatPolyAmount(ref, _amountUsdc);

    return PopScope(
      // The page always answers with its edited values, including on a
      // swipe back or the system back button.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_result(submit: false));
      },
      child: KeyboardDismissOnTap(
        child: PolySlipAdvancedScaffold(
          title: l10n.betAdvancedSale,
          onBack: _close,
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey('prediction-advanced-sale-scroll'),
                  physics: const ClampingScrollPhysics(),
                  primary: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: 12.h),
                        Text(pos.marketQuestion,
                            style: TextStyle(
                                fontSize: 20.sp,
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary)),
                        SizedBox(height: 20.h),
                        PolySlipSection(
                          title: l10n.betYourPosition,
                          children: [_positionBlock(c)],
                        ),
                        SizedBox(height: 14.h),
                        PolySlipSection(
                          title: l10n.amount,
                          trailing: Text(
                            '${l10n.available} ${formatPolyAmount(ref, _positionValue)}',
                            textAlign: TextAlign.end,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14.sp, color: c.textSecondary),
                          ),
                          children: [
                            PolySlipAmountField(
                              controller: _amountController,
                              prefix: polyDisplayLabel(ref),
                              inputFormatters: const [
                                DecimalInputFormatter(fractionDigits: 2)
                              ],
                            ),
                            if (_sharesToSell > 0) ...[
                              SizedBox(height: 10.h),
                              Text(
                                sellingAll
                                    ? l10n.betAdvancedSaleSellingAll
                                    : '≈ ${l10n.betSharesCount(_sharesToSell.toStringAsFixed(2))}',
                                style: TextStyle(
                                    fontSize: 14.sp, color: c.textSecondary),
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: 14.h),
                        PolySlipSection(
                          title: l10n.portfolioTabOrders,
                          children: [
                            _orderTypeToggle(c),
                            SizedBox(height: 16.h),
                            if (_isLimitMode)
                              _limitPriceInput(c)
                            else
                              _slippageRow(c),
                          ],
                        ),
                        SizedBox(height: 14.h),
                        PolySlipSection(
                          children: [
                            PolymarketFeeSummary(
                              tokenId: pos.tokenId,
                              shares: _sharesToSell,
                              price: orderPrice,
                              bitcoinFirst: false,
                              limit: _isLimitMode,
                            ),
                          ],
                        ),
                        SizedBox(height: 14.h),
                        PolySlipDetailsGroup(
                          open: _detailsOpen,
                          onToggle: () {
                            HapticFeedback.selectionClick();
                            setState(() => _detailsOpen = !_detailsOpen);
                            TrackingService.track(
                                'sell_sheet_advanced_details_toggled',
                                params: {'open': _detailsOpen});
                          },
                          rows: [
                            PolySlipDetailRow(
                                label: l10n.betSharesToSell,
                                value: _sharesToSell.toStringAsFixed(2)),
                            SizedBox(height: 12.h),
                            PolySlipDetailRow(
                                label: l10n.betPricePerShare,
                                value: formatPolyAmount(ref, orderPrice)),
                            if (_isLimitMode) ...[
                              SizedBox(height: 12.h),
                              PolySlipDetailRow(
                                  label: l10n.betOrderDuration,
                                  value: l10n.betUntilCanceled),
                            ],
                            SizedBox(height: 12.h),
                            // What lands, net of the same fees the
                            // estimate above shows (taken from the sale).
                            PolySlipDetailRow(
                                label: l10n.betProceedsToPredictions,
                                value: switch (pos.tokenId) {
                                  final token? when token.isNotEmpty => ref
                                          .watch(
                                              polymarketFeeTermsProvider(token))
                                          .whenOrNull(
                                              data: (fees) => formatPolyAmount(
                                                  ref,
                                                  fees.sellProceeds(
                                                      _sharesToSell,
                                                      orderPrice))) ??
                                      '—',
                                  _ => '—',
                                }),
                          ],
                        ),
                        SizedBox(height: 16.h),
                      ],
                    ),
                  ),
                ),
              ),
              KuteStickyActionBar(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 16.h),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (_advancedBlock case final reason?)
                      CapabilityBlockNote(reason),
                    PolySlipCta(
                      color: _kPolyRed,
                      isBusy: false,
                      enabled: _canSell && _advancedBlock == null,
                      onTap: _sell,
                      label: _isLimitMode
                          ? (_canSell
                              ? l10n.betPlaceLimitAtPrice(
                                  '${(_limitPrice * 100).toStringAsFixed(1)}¢')
                              : l10n.betPlaceLimit)
                          : (_canSell
                              ? '${l10n.sellNow} · $amountStr'
                              : l10n.sell),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
