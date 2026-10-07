// lib/providers/polymarket_bet_controller.dart
//
// UI-independent placement engine for Polymarket bets. Extracted from the
// old fullscreen `PendingBetOverlay` so the bet-slip bottom sheet can place
// a bet inline (no separate screen) and render progress from
// `pendingPolymarketBetProvider`'s status.
//
// Funding modes:
//   - 'smart' : use the Predictions (USDC) balance first; swap only the
//               shortfall from Bitcoin. If USDC already covers the bet,
//               places direct (no swap).
//   - 'usdc'  : USDC-only. Places direct off the Safe balance; fails if short.
//   - 'btc'   : Bitcoin-only. Always swaps the FULL bet amount.
//
// The swap path (btc / smart-with-shortfall) hands off to
// `pendingBetAutoFireProvider`, which fires the CLOB order once the
// converted USDC lands. The direct path runs the CLOB order here.
//
// Step-up v2 (Wallet Hardening Phase 1b.4): the caller prompts for
// [PolymarketBetController.reviewIntent] and passes the grant to `place`.
// Market orders use a prepared executable quote under one approval. Each
// definitive no-fill retry stays inside the same amount and price bounds.
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'dart:async';
import 'dart:math';

import 'package:kute/services/success_feedback.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart' show AppLocalizations, l10nForLanguage;
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/placing_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/polymarket/fast_bet_window.dart';
import 'package:kute/services/polymarket/hot_order_guard.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/services/polymarket/placement_timeline.dart';
import 'package:kute/services/polymarket/placement_diagnostics.dart';
import 'package:kute/services/polymarket/placement_waits.dart';
import 'package:kute/services/polymarket/sell_settlement.dart';
import 'package:kute/services/polymarket/send_time_read.dart';
import 'package:kute/helpers/formatters/polymarket_side_labels.dart'
    show polymarketMarketType;
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/services/polymarket_onboarding_service.dart'
    show PolymarketReadException;
import 'package:kute/services/sound_service.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/services/tracking_service.dart';

final polymarketBetControllerProvider =
    Provider<PolymarketBetController>((ref) => PolymarketBetController(ref));

class PolymarketBetController {
  PolymarketBetController(this.ref);
  final Ref ref;

  double get _usdcBalance =>
      ref.read(polymarketTradingProvider).valueOrNull?.usdcBalance ?? 0;

  double _usdcShortfall(double amount) =>
      (amount - _usdcBalance).clamp(0.0, double.infinity);

  /// The account must cover the stake AND the venue's fees: platform fee
  /// per share plus Kute's builder fee on notional, both charged in pUSD
  /// outside the signed amounts. A market buy takes its ceiling from the
  /// prepared quote; a resting limit is bounded as a taker at its own
  /// price, since a crossing limit fills immediately. Before preparation
  /// (no terms yet) the documented maxima stand in, which over-reserves.
  static double allInMax(PendingBetIntent intent) {
    final quote = intent.marketQuote;
    if (!intent.isLimit &&
        quote != null &&
        quote.tokenId == intent.tokenId &&
        quote.amount == intent.amount) {
      return quote.allInMax;
    }
    final terms = intent.feeTerms ?? PolymarketFeeTerms.worstCase;
    final price = intent.isLimit ? _gtcPrice(intent) : intent.expectedPrice;
    return terms.allInCost(intent.amount, price.clamp(0.01, 0.99).toDouble());
  }

  /// The cash a Max stake is sized against: what was spendable at the tap,
  /// never more than the account holds now. Null for a typed stake.
  @visibleForTesting
  static double? maxStakeBudget(double? spendAllBudgetUsd, double balance) {
    if (spendAllBudgetUsd == null) return null;
    final budget = spendAllBudgetUsd < balance ? spendAllBudgetUsd : balance;
    return budget.isFinite && budget > 0 ? budget : null;
  }

  /// Finish one-time setup and read the executable book and the market's
  /// fee terms before approval, so review, balance check and signing all
  /// work from the same numbers.
  Future<PendingBetIntent> prepareIntent(PendingBetIntent intent) async {
    final notifier = ref.read(polymarketTradingProvider.notifier);
    final walletId = notifier.signingWalletId;
    // A first prediction runs the account's one-time setup here, behind
    // "Setting up your Predictions wallet…". It used to be awaited for as
    // long as it took, and a failure ended the slip's spinner with nothing
    // said. Now it is bounded, and either outcome names the setup so the
    // slip can say so and offer a retry; setup that is still running
    // carries on, and the retry joins it.
    final clock = Stopwatch()..start();
    try {
      await notifier.enableTrading().timeout(PolymarketPlacementWaits.setup);
    } on TimeoutException catch (e) {
      PolymarketPlacementDiagnostics.stepFailed('setup', e, clock.elapsed);
      throw const PolymarketSetupIncomplete(timedOut: true);
    } catch (e) {
      PolymarketPlacementDiagnostics.stepFailed('setup', e, clock.elapsed);
      throw PolymarketSetupIncomplete(cause: e);
    }
    PolymarketPlacementTimeline.mark('setup');
    if (walletId == null || notifier.signingWalletId != walletId) {
      throw ReauthRequired(const {DriftField.wallet});
    }
    final terms = await PolymarketFeeTerms.fetchOrWorstCase(intent.tokenId);
    PolymarketPlacementTimeline.mark('fees');
    if (notifier.signingWalletId != walletId) {
      throw ReauthRequired(const {DriftField.wallet});
    }
    if (intent.isLimit) return intent.copyWith(feeTerms: terms);
    final model = PolymarketModel();
    try {
      final clock = Stopwatch()..start();
      final OrderBook book;
      try {
        book = await model
            .getOrderBook(intent.tokenId)
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        PolymarketPlacementDiagnostics.stepFailed(
            'order_book', e, clock.elapsed);
        rethrow;
      }
      if (notifier.signingWalletId != walletId) {
        throw ReauthRequired(const {DriftField.wallet});
      }
      var amount = intent.amount;
      var quote = PolymarketMarketBuyQuote.fromBook(
        book,
        tokenId: intent.tokenId,
        amount: amount,
        slippagePct: intent.slippagePct,
        fees: terms,
      );
      // Max resolves here, where the executable best ask is known: the
      // largest stake whose fee ceiling at that ask plus the rounding
      // cent fits the spendable cash, i.e. exactly what `allInMax` and
      // the placement check will ask the balance to cover.
      final budget = maxStakeBudget(intent.spendAllBudgetUsd, _usdcBalance);
      if (budget != null) {
        final fitted = terms.maxNotionalFor(budget, quote.bestAsk,
            reserve: PolymarketMarketBuyQuote.roundingHeadroom);
        if (fitted > 0 && fitted != amount) {
          amount = fitted;
          quote = PolymarketMarketBuyQuote.fromBook(
            book,
            tokenId: intent.tokenId,
            amount: amount,
            slippagePct: intent.slippagePct,
            fees: terms,
          );
        }
      }
      // The book cannot fill the whole stake within the cap (it thins out
      // near the end of a short market): a Max stake takes what fills. A
      // typed stake is the slip's to refuse with what fills now
      // (PolymarketThinBook); a builder leg still goes out to fill in part.
      final fillable =
          PolymarketThinBook(fillableUsd: quote.fillableUsd).fillableCents;
      if (budget != null && fillable + 1e-6 < amount && fillable >= 1.0) {
        amount = fillable;
        quote = PolymarketMarketBuyQuote.fromBook(
          book,
          tokenId: intent.tokenId,
          amount: amount,
          slippagePct: intent.slippagePct,
          fees: terms,
        );
      }
      return intent.copyWith(
          amount: amount, feeTerms: terms, marketQuote: quote);
    } finally {
      model.dispose();
    }
  }

  // ── The book at send time ───────────────────────────────────────────

  PolymarketSendTimeRead<OrderBook>? _sendBook;
  String? _sendBookToken;

  static Future<OrderBook> _readBook(String tokenId) async {
    final model = PolymarketModel();
    try {
      return await model
          .getOrderBook(tokenId)
          .timeout(const Duration(seconds: 3));
    } finally {
      model.dispose();
    }
  }

  /// Called as the approval opens: reads [intent]'s book (and keeps it at
  /// most a second old) and the account's pUSD while the person approves,
  /// so the order is priced from the book as it is when it is signed and
  /// nothing is awaited after the approval that could have run during it.
  void prefetchForSend(PendingBetIntent intent) {
    _sendBook?.cancel();
    _sendBook = null;
    if (intent.isLimit) return;
    final tokenId = intent.tokenId;
    _sendBookToken = tokenId;
    _sendBook = PolymarketSendTimeRead<OrderBook>(() => _readBook(tokenId),
        maxAge: const Duration(seconds: 1),
        refreshEvery: const Duration(milliseconds: 700))
      ..start();
    ref.read(polymarketTradingProvider.notifier).prefetchOrderReads();
  }

  /// The book for [tokenId] now: the prefetched read when it is at most a
  /// second old, else a new read. Null when it cannot be read in time; the
  /// prepared quote then stands, as before.
  Future<OrderBook?> _sendTimeBook(String tokenId) async {
    final prefetched = _sendBook;
    _sendBook = null;
    final read = prefetched != null && _sendBookToken == tokenId
        ? prefetched
        : PolymarketSendTimeRead<OrderBook>(() => _readBook(tokenId),
            maxAge: Duration.zero);
    if (!identical(read, prefetched)) prefetched?.cancel();
    try {
      return await read.take().timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
    }
  }

  /// The quote the order is signed from: [quote] repriced from the book at
  /// send time with the same rule (polymarketBuyCap, one tick of room at
  /// least). The approval names a maximum price, [approvedPrice]: when the
  /// whole stake still fills at or under it the fresh quote is returned and
  /// the order goes out with no second prompt; when the price moved past
  /// it nothing is signed and [PolymarketThinBook] says where it went,
  /// with the maximum a new approval would name. Falls back to [quote]
  /// when the book cannot be read.
  @visibleForTesting
  static PolymarketMarketBuyQuote sendTimeQuote(
      PolymarketMarketBuyQuote quote, OrderBook? book,
      {required double approvedPrice, required double slippagePct}) {
    if (book == null) return quote;
    final PolymarketMarketBuyQuote fresh;
    try {
      fresh = PolymarketMarketBuyQuote.fromBook(book,
          tokenId: quote.tokenId,
          amount: quote.amount,
          slippagePct: slippagePct,
          fees: quote.fees);
    } on StateError {
      // Nothing for sale now.
      throw const PolymarketThinBook(fillableUsd: 0);
    } on FormatException {
      return quote;
    }
    if (fresh.price > approvedPrice + 1e-9) {
      throw PolymarketThinBook(
          fillableUsd: polymarketDepthWithin(book, approvedPrice),
          price: fresh.price,
          limit: approvedPrice,
          retryPrice: fresh.maxPrice);
    }
    return fresh;
  }

  /// A fresh executable quote for the retry rung (null when the book
  /// cannot be read in time or has nothing for sale), and what the asks
  /// within the approved price add up to (null when unread); the approval
  /// is never widened by it.
  Future<({PolymarketMarketBuyQuote? quote, double? depth})> _requote(
      PendingBetIntent intent,
      PolymarketMarketBuyQuote quote,
      double approvedPrice) async {
    final model = PolymarketModel();
    try {
      // Same allowance as the first quote: the venue is already under
      // load when a fill-or-kill misses, so this is no time to be strict.
      final book = await model
          .getOrderBook(intent.tokenId)
          .timeout(const Duration(seconds: 5));
      final depth = polymarketDepthWithin(book, approvedPrice);
      try {
        return (
          quote: PolymarketMarketBuyQuote.fromBook(book,
              tokenId: intent.tokenId,
              amount: intent.amount,
              slippagePct: intent.slippagePct,
              fees: quote.fees),
          depth: depth,
        );
      } catch (_) {
        return (quote: null, depth: depth);
      }
    } catch (_) {
      return (quote: null, depth: null);
    } finally {
      model.dispose();
    }
  }

  /// A fill-and-kill the venue killed for want of sellers at the cap (not
  /// a balance or any other refusal).
  static bool _isNoMatch(Object e) {
    if (e is! PolymarketOrderNotAcceptedException) return false;
    final m = e.reason.toLowerCase();
    return m.contains('no orders found to match') ||
        m.contains("couldn't be fully filled");
  }

  /// The resting price of a limit bet.
  static double _gtcPrice(PendingBetIntent intent) =>
      intent.limitPrice.clamp(0.01, 0.99).toDouble();

  /// Approve the prepared book price plus the ticket's selected slippage.
  /// The displayed last trade is not an executable ask or an approval cap.
  SensitiveIntent? reviewIntent(PendingBetIntent intent) {
    final walletId =
        ref.read(polymarketTradingProvider.notifier).signingWalletId;
    if (walletId == null || walletId.isEmpty) return null;
    // The approval names the all-in maximum: stake plus the venue's fee
    // ceiling. The signed notional is always at or below it.
    if (intent.isLimit) {
      return PmGrants.betReview(
        walletId: walletId,
        tokenId: intent.tokenId,
        maxCostUsd: allInMax(intent),
        worstPrice: _gtcPrice(intent),
        orderType: OrderType.gtc.name,
      );
    }
    final quote = intent.marketQuote;
    if (quote == null ||
        quote.tokenId != intent.tokenId ||
        quote.amount != intent.amount) {
      return null;
    }
    return PmGrants.betReview(
      walletId: walletId,
      tokenId: intent.tokenId,
      maxCostUsd: quote.allInMax,
      worstPrice: quote.maxPrice,
      orderType: OrderType.fak.name,
    );
  }

  /// A grant failure stopped the placement before that order was signed.
  AuthGrantException _failOnGrant(AuthGrantException e) {
    final l10n = l10nForLanguage(ref.read(settingsProvider).language);
    ref.read(pendingPolymarketBetProvider.notifier).updateStatus(
        PendingBetStatus.failed,
        errorMessage: e is ReauthRequired
            ? l10n.stepUpDetailsChanged
            : l10n.stepUpApprovalExpired);
    return e;
  }

  /// Place the active intent using funding [mode] ('smart' | 'usdc' | 'btc').
  /// Drives `pendingPolymarketBetProvider` status the whole way; the caller
  /// renders progress from that.
  // [mode] is legacy ('smart'|'usdc'|'btc' from old call sites); every
  // placement is USDC-only now, so it is accepted and ignored.
  ///
  /// [successHaptic] is false when the caller shows the shared success
  /// confirmation, which fires the haptic itself as its check completes.
  ///
  /// [grant] (Phase 1b.4) approves [reviewIntent] for the pending intent.
  /// Returns the grant failure when one stopped the placement before that
  /// order was signed, so the caller can show "Review again"; else null.
  ///
  /// [entrySource] is the surface the slip was opened from (feed_card |
  /// search | hot_events | ...), analytics only: it becomes entry_source on
  /// polymarket_bet_placed.
  Future<AuthGrantException?> place(
    String mode, {
    required AuthGrant grant,
    bool successHaptic = true,
    String? entrySource,
  }) async {
    final intent = ref.read(pendingPolymarketBetProvider);
    if (intent == null) {
      grant.revoke();
      return null;
    }

    final tradingState = ref.read(polymarketTradingProvider).valueOrNull;
    final proxyWallet = tradingState?.proxyWalletAddress;
    if (proxyWallet == null || proxyWallet.isEmpty) {
      _trackBetFailed(intent, 'wallet_not_ready', entrySource: entrySource);
      ref.read(pendingPolymarketBetProvider.notifier).updateStatus(
          PendingBetStatus.failed,
          errorMessage: l10nForLanguage(ref.read(settingsProvider).language)
              .receiveUsdcWalletNotReady);
      grant.revoke();
      return null;
    }

    // USDC-only placement (user decision: no more betting straight from
    // Lightning). A bet must be fully covered by the Predictions (USDC)
    // balance, fees included; anything short fails fast with a deposit
    // prompt. The deposit-then-autofire journey still works: the intent
    // stays stored, and once deposited USDC lands the autofire places it.
    if (_usdcShortfall(allInMax(intent)) > 0) {
      _trackBetFailed(intent, 'insufficient_usdc', entrySource: entrySource);
      ref.read(pendingPolymarketBetProvider.notifier).updateStatus(
            PendingBetStatus.failed,
            errorMessage: l10nForLanguage(ref.read(settingsProvider).language)
                .betAddFundsToPredict,
          );
      grant.revoke();
      return null;
    }

    ref
        .read(pendingPolymarketBetProvider.notifier)
        .updateStatus(PendingBetStatus.placing);
    if (intent.isLimit) {
      return _placeOrderGtc(intent, grant,
          successHaptic: successHaptic, entrySource: entrySource);
    }
    return _placeOrder(intent, grant,
        successHaptic: successHaptic, entrySource: entrySource);
  }

  /// The one terminal polymarket_bet_failed per placement attempt. The
  /// provider no longer reports per-rung rejections (a killed FAK rung is
  /// retried and often fills), so this is the only failure event for a bet.
  void _trackBetFailed(PendingBetIntent intent, String reason,
      {String? entrySource, StackTrace? stackTrace}) {
    TrackingService.polymarketBetFailed(
      marketId: intent.tokenId,
      reason: reason,
      side: 'buy',
      orderType: intent.isLimit ? 'limit' : 'market',
      amountUsd: intent.amount,
      walletKind: 'hot',
      entrySource: entrySource ?? intent.entrySource,
      stackTrace: stackTrace,
      extra: {
        'funding_source': 'venue_balance',
        if (intent.isLimit) 'limit_price': intent.limitPrice,
        if (!intent.isLimit)
          'slippage_bps': VenueAnalytics.bps(intent.slippagePct),
      },
    );
  }

  /// Place a resting GTC LIMIT order at the intent's [limitPrice]. No
  /// slippage ladder / immediate fill — the order sits on the book until
  /// matched or cancelled, so we do NOT register a position-placing tile
  /// (it isn't a held position yet). Funding is identical to spot: USDC
  /// (direct) or BTC→USDC swap first (via the autofire), then this places.
  Future<AuthGrantException?> _placeOrderGtc(
      PendingBetIntent intent, AuthGrant grant,
      {bool successHaptic = true, String? entrySource}) async {
    final notifier = ref.read(polymarketTradingProvider.notifier);
    try {
      final price = _gtcPrice(intent);
      // Shares from the user's USD stake at the chosen limit price.
      final shares = ((intent.amount / price) * 100).floorToDouble() / 100;
      if (shares <= 0) {
        throw Exception('Amount too small for this limit price.');
      }
      final placed = await notifier.placeOrder(
        tokenId: intent.tokenId,
        side: OrderSide.buy,
        size: shares,
        negRisk: intent.negRisk,
        price: price,
        orderType: OrderType.gtc,
        marketTitle: intent.marketQuestion,
        marketImage: intent.marketImage,
        marketOutcome: intent.outcomeName,
        marketCategory: intent.marketCategory,
        source: 'usdc_pool',
        entrySource: entrySource,
        grant: grant,
        onStep: _onPlacementStep,
      );
      unawaited(notifier.refresh().catchError((_) {}));
      ref.invalidate(polymarketOpenOrdersProvider);
      // What the order did on arrival: rests whole, bought part of it from
      // sellers already at the price (the rest waits), or bought it all.
      final settlement =
          await _settle(placed, intent, orderedShares: shares, resting: true);
      TrackingService.track('polymarket_limit_order_placed', params: {
        'source': 'usdc_pool',
        'wallet_kind': 'hot',
        ..._settlementParams(settlement),
      });
      if (_endsWithoutFill(intent, settlement, entrySource)) return null;
      final bought = settlement.soldShares;
      if (bought > 0) {
        ref.read(pendingPolymarketBetProvider.notifier).recordSettlement(
            filledShares: bought,
            filledCost: settlement.proceeds,
            orderedShares: shares);
        _showArriving(intent, settlement);
      }
      notifier.refreshAfterSale();
      SoundService.playSuccess();
      // Apple Pay style two-beat success haptic — single choke point for
      // bet placement (covers both the open slip and BTC auto-fire). A
      // fill ends on the shared confirmation, whose entrance fires it.
      if (successHaptic && bought <= 0) moneySuccessFeedback();
      ref
          .read(pendingPolymarketBetProvider.notifier)
          .updateStatus(PendingBetStatus.done);
    } catch (e, st) {
      if (e is AuthGrantException) return _failOnGrant(e);
      if (e is PendingPolymarketOrder) {
        ref
            .read(pendingPolymarketBetProvider.notifier)
            .updateStatus(PendingBetStatus.awaitingConfirmation);
        return null;
      }
      _trackBetFailed(intent, _placementFailureCode(e),
          entrySource: entrySource, stackTrace: st);
      ref.read(pendingPolymarketBetProvider.notifier).updateStatus(
          PendingBetStatus.failed,
          errorMessage: _friendlyPlacementError(e));
    }
    return null;
  }

  /// Direct CLOB placement from funded pUSD, using the prepared book cap.
  Future<AuthGrantException?> _placeOrder(
      PendingBetIntent intent, AuthGrant grant,
      {bool successHaptic = true, String? entrySource}) async {
    final notifier = ref.read(polymarketTradingProvider.notifier);
    // Phase 1b.4: one approval for the whole ladder. Each rung gets a child
    // grant bound to exactly that rung; a rung past the cap re-auths.
    final ladder = PmLadderGrant(grant);
    try {
      final quote = intent.marketQuote;
      if (quote == null ||
          quote.tokenId != intent.tokenId ||
          quote.amount != intent.amount) {
        throw ReauthRequired(const {DriftField.price});
      }
      final approvedPrice =
          (grant.boundIntent.limits[IntentLimit.limitPrice] as num).toDouble();
      var orderPrice = min(quote.maxPrice, approvedPrice);
      // The stake is signed in full. Fees are not a percentage of the
      // balance to shave off (the old 0.97 heuristic under-bought on
      // fee-free markets and still fell short on low-priced crypto
      // outcomes); the venue's ceiling for THIS quote must fit the
      // balance alongside the stake, or the order is not sent.
      if (quote.allInMax > _usdcBalance + 1e-6) {
        throw StateError('Insufficient balance for the stake and fees');
      }
      // The book as it is now, after the approval (read while it was on
      // screen): the cap is computed from it, never above the approval.
      PolymarketPlacementTimeline.trace('approved');
      final book = await _sendTimeBook(intent.tokenId);
      PolymarketPlacementTimeline.trace('send_book');
      final sendQuote = sendTimeQuote(quote, book,
          approvedPrice: approvedPrice, slippagePct: intent.slippagePct);
      orderPrice = min(sendQuote.maxPrice, approvedPrice);
      final effectiveAmount = intent.amount;
      PolymarketPlacementDiagnostics.note('order_plan', {
        'amount': effectiveAmount,
        'orderPrice': orderPrice,
        'approvedPrice': approvedPrice,
        'maxPrice': quote.maxPrice,
        'sendMaxPrice': sendQuote.maxPrice,
        'bestAsk': quote.bestAsk,
        'sendBestAsk': sendQuote.bestAsk,
        'allInMax': quote.allInMax,
        'balance': _usdcBalance,
        'negRisk': quote.negRisk,
      });

      // The Portfolio shows the prediction on its way from here.
      _markPlacing(intent);

      // Submit at the approved maximum: CLOB matches at available better
      // prices. One definitive no-fill may retry, never an unknown result.
      Object? lastErr;
      Map<String, dynamic>? accepted;
      var orderedShares = 0.0;
      for (var i = 0; i < 2; i++) {
        var shares =
            ((effectiveAmount / orderPrice) * 100).floorToDouble() / 100;
        if (shares * orderPrice < 1.0 && effectiveAmount >= 1.0) {
          // The venue's one-dollar floor; the quote's headroom covers the
          // fraction of a cent, and the approval is never exceeded.
          final bumped = (1.0 / orderPrice * 100).ceilToDouble() / 100;
          if (bumped * orderPrice <= quote.allInMax + 1e-9) shares = bumped;
        }

        try {
          final fillResponse = await notifier.placeOrder(
            tokenId: intent.tokenId,
            side: OrderSide.buy,
            size: shares,
            negRisk: sendQuote.negRisk,
            marketQuote: sendQuote,
            price: orderPrice,
            orderType: OrderType.fak,
            marketTitle: intent.marketQuestion,
            marketImage: intent.marketImage,
            marketOutcome: intent.outcomeName,
            marketCategory: intent.marketCategory,
            source: 'usdc_pool',
            entrySource: entrySource,
            grant: ladder.rung(
              walletId: notifier.signingWalletId ?? '',
              tokenId: intent.tokenId,
              isBuy: true,
              size: shares,
              price: orderPrice,
              orderType: OrderType.fak.name,
            ),
            onStep: _onPlacementStep,
          );
          accepted = fillResponse;
          orderedShares = shares;
          PolymarketPlacementDiagnostics.orderOutcome(
              rung: i,
              price: orderPrice,
              shares: shares,
              orderType: OrderType.fak.name,
              response: fillResponse);
          ref
              .read(pendingPolymarketBetProvider.notifier)
              .recordFill(fillResponse);
          PolymarketPlacementTimeline.mark('response');
          lastErr = null;
          break;
        } catch (e) {
          lastErr = e;
          PolymarketPlacementDiagnostics.orderOutcome(
              rung: i,
              price: orderPrice,
              shares: shares,
              orderType: OrderType.fak.name,
              error: e,
              failureCode: _placementFailureCode(e));
          if (e is! PolymarketOrderNotAcceptedException ||
              (i == 1 && !_isNoMatch(e))) {
            rethrow;
          }
          // A killed fill-and-kill means the book moved above the cap
          // between quote and post. The venue's own client re-reads the
          // book for a market order; so does the retry, and it only goes
          // out again if the fresh price is still inside the approval.
          final read = await _requote(intent, quote, approvedPrice);
          final fresh = read.quote;
          if (i == 1 || fresh == null || fresh.price > approvedPrice + 1e-9) {
            PolymarketPlacementDiagnostics.note('requote_outside_approval', {
              'freshPrice': fresh?.price,
              'approvedPrice': approvedPrice,
              'depthWithinApproval': read.depth,
            });
            // Said with the book's own figures: what fills within the
            // approved price now, or where the price went. Any other
            // refusal keeps its own words.
            if (_isNoMatch(e) && read.depth != null) {
              throw PolymarketThinBook(
                  fillableUsd: read.depth!,
                  price: fresh?.price,
                  limit: approvedPrice,
                  retryPrice: fresh?.maxPrice);
            }
            rethrow;
          }
          orderPrice = min(fresh.maxPrice, approvedPrice);
          PolymarketPlacementDiagnostics.note('requote', {
            'price': orderPrice,
            'bestAsk': fresh.bestAsk,
          });
        }
      }
      if (lastErr != null) {
        throw lastErr;
      }

      unawaited(notifier.refresh().catchError((_) {}));
      // Accepted. What it got is read from the venue (the order, then its
      // trades on chain) behind the busy button: "Placing prediction…",
      // the live game's wait, "Matched · confirming", then the receipt.
      final immediateFill =
          ref.read(pendingPolymarketBetProvider)?.filledShares != null;
      final settlement = await _settle(accepted!, intent,
          orderedShares: orderedShares, resting: false);
      if (_endsWithoutFill(intent, settlement, entrySource)) {
        PolymarketPlacementTimeline.finish(
            settlement.result == PmSellResult.unknown ? 'pending' : 'failed',
            reason: _settlementParams(settlement)['fill_outcome'] as String);
        return null;
      }
      ref.read(pendingPolymarketBetProvider.notifier).recordSettlement(
          filledShares: settlement.soldShares,
          // The POST's echo when the order matched at once, else the trades.
          filledCost: settlement.proceeds ??
              (immediateFill
                  ? ref.read(pendingPolymarketBetProvider)?.filledCost
                  : null),
          orderedShares: orderedShares);
      if (!immediateFill && settlement.proceeds != null) {
        // The provider reports a fill the POST echoed; one that matched
        // after the live game's delay is reported here, from the venue's
        // own figures, so it is not missing from the funnel or revenue.
        _trackLateFill(intent, settlement, accepted, entrySource,
            approval: FastBetWindow.approvalParam(grant.method));
      }
      notifier.refreshAfterSale();
      final filled = ref.read(pendingPolymarketBetProvider);
      if (filled?.filledShares == null) {
        ref.invalidate(polymarketOpenOrdersProvider);
        ref
            .read(pendingPolymarketBetProvider.notifier)
            .updateStatus(PendingBetStatus.awaitingConfirmation);
        PolymarketPlacementDiagnostics.note('fill_unconfirmed', {
          'filledShares': filled?.filledShares,
          'filledCost': filled?.filledCost,
        });
        PolymarketPlacementTimeline.finish('pending');
        return null;
      }
      PolymarketPlacementDiagnostics.note('filled', {
        'shares': filled?.filledShares,
        'cost': filled?.filledCost,
      });
      PolymarketPlacementTimeline.finish('filled');

      SoundService.playSuccess();
      // Apple Pay style two-beat success haptic (see note above).
      if (successHaptic) moneySuccessFeedback();

      ref
          .read(pendingPolymarketBetProvider.notifier)
          .updateStatus(PendingBetStatus.done);
      // Separate event name, fired alongside the provider's
      // polymarket_bet_placed for the same fill: dashboards must NOT sum it
      // with polymarket_bet_placed (that would count this bet twice). It
      // exists only to mark the slip → filled completion step.
      TrackingService.track('polymarket_bet_placed_after_convert',
          params: _settlementParams(settlement));

      // The Portfolio card turns from "Placing prediction…" into the
      // bridge until the real position lands.
      _showArriving(intent, settlement);
    } catch (e, st) {
      if (e is AuthGrantException) {
        _clearPlacing();
        return _failOnGrant(e);
      }
      if (e is PendingPolymarketOrder) {
        _clearPlacing();
        ref
            .read(pendingPolymarketBetProvider.notifier)
            .updateStatus(PendingBetStatus.awaitingConfirmation);
        return null;
      }
      final code = _placementFailureCode(e);
      _trackBetFailed(intent, code, entrySource: entrySource, stackTrace: st);
      PolymarketPlacementDiagnostics.note('placement_failed', {
        'failure': code,
        'error': '${e.runtimeType}',
      });
      ref.read(pendingPolymarketBetProvider.notifier).updateStatus(
          PendingBetStatus.failed,
          errorMessage: _friendlyPlacementError(e),
          retryMaxPrice: polymarketRetryPrice(e));
      _clearPlacing(failedMessage: _friendlyPlacementError(e));
      PolymarketPlacementTimeline.finish(
          e is PendingPolymarketOrder ? 'pending' : 'failed', reason: code);
    } finally {
      ladder.close();
    }
    return null;
  }

  // ── Following an accepted order ─────────────────────────────────────

  /// The Portfolio's tile for the market buy in flight, if any.
  String? _placingTile;

  void _markPlacing(PendingBetIntent intent) {
    try {
      final preShares = ref
          .read(polymarketActivePositionsProvider)
          .where((p) => p.tokenId == intent.tokenId)
          .fold<double>(0, (sum, p) => sum + p.size);
      final price = intent.expectedPrice;
      _placingTile = ref.read(placingPolymarketBetProvider.notifier).markPlacing(
            tokenId: intent.tokenId,
            marketQuestion: intent.marketQuestion,
            marketImage: intent.marketImage,
            outcomeName: intent.outcomeName,
            amount: intent.amount,
            shares: price > 0 ? intent.amount / price : 0,
            avgPrice: price,
            preExistingShares: preShares,
            // Covers a live game's delay and the confirmation; the
            // placement always settles the tile before this.
            watchdogDuration: const Duration(seconds: 60),
            stepLabel: _l10n.betPlacingPrediction,
          );
    } catch (_) {}
  }

  /// The tile for a placement that ended without a position: dropped, or
  /// briefly marked failed with [failedMessage].
  void _clearPlacing({String? failedMessage}) {
    final id = _placingTile;
    _placingTile = null;
    if (id == null) return;
    try {
      final tiles = ref.read(placingPolymarketBetProvider.notifier);
      failedMessage == null
          ? tiles.clear(id)
          : tiles.markFailed(id, failedMessage);
    } catch (_) {}
  }

  /// Shares were bought: the Portfolio tile becomes the "Confirmed.
  /// Appearing in your predictions…" bridge until the real position lands
  /// (the Data API shows it ~2-8 s after the match).
  void _showArriving(PendingBetIntent intent, PmSellSettlement settlement) {
    try {
      final tiles = ref.read(placingPolymarketBetProvider.notifier);
      final id = _placingTile ??
          (() {
            final preShares = ref
                .read(polymarketActivePositionsProvider)
                .where((p) => p.tokenId == intent.tokenId)
                .fold<double>(0, (sum, p) => sum + p.size);
            final cost = settlement.proceeds ?? intent.amount;
            final shares = settlement.soldShares;
            return tiles.markPlacing(
              tokenId: intent.tokenId,
              marketQuestion: intent.marketQuestion,
              marketImage: intent.marketImage,
              outcomeName: intent.outcomeName,
              amount: cost,
              shares: shares,
              avgPrice: shares > 0 ? cost / shares : intent.expectedPrice,
              preExistingShares: preShares,
            );
          })();
      _placingTile = null;
      tiles.markSucceeded(id, holdUntilPositionArrives: true);
    } catch (_) {}
  }

  AppLocalizations get _l10n =>
      l10nForLanguage(ref.read(settingsProvider).language);

  /// A self-heal inside the placement, named on the slip's button.
  void _onPlacementStep(String step) {
    ref.read(pendingPolymarketBetProvider.notifier).setStage(step == 'setup'
        ? PendingBetStage.settingUp
        : PendingBetStage.approving);
  }

  /// Follows the accepted order (see sell_settlement.dart) and moves the
  /// slip's button and the Portfolio tile along with it. Read-only.
  Future<PmSellSettlement> _settle(
    Map<String, dynamic> response,
    PendingBetIntent intent, {
    required double orderedShares,
    required bool resting,
  }) {
    final notifier = ref.read(polymarketTradingProvider.notifier);
    final backend = notifier.backendService;
    final pending = ref.read(pendingPolymarketBetProvider.notifier);
    final tiles = ref.read(placingPolymarketBetProvider.notifier);
    final preShares = ref
        .read(polymarketActivePositionsProvider)
        .where((p) => p.tokenId == intent.tokenId)
        .fold<double>(0, (sum, p) => sum + p.size);
    var bought = 0.0;
    var tick = 0;
    // The account showing the new shares also confirms the buy, asked
    // again every other tick rather than on the 5 s refresh.
    Future<bool> positionMoved() async {
      if (bought <= 0) return false;
      if ((tick++).isOdd) {
        notifier.invalidateBalanceCache();
        unawaited(notifier.refresh().catchError((_) {}));
      }
      final held = ref
          .read(polymarketActivePositionsProvider)
          .where((p) => p.tokenId == intent.tokenId)
          .fold<double>(0, (sum, p) => sum + p.size);
      return held >= preShares + bought - 0.01;
    }

    return PmSellSettlementWatcher(
      readOrder: (id) async =>
          backend == null ? null : await backend.getOrderById(id),
      readTrade: backend?.getTradeById,
      positionMoved: positionMoved,
    ).watch(
      response: response,
      tokenId: intent.tokenId,
      offeredShares: orderedShares,
      resting: resting,
      buy: true,
      onStage: (stage, shares) {
        if (stage == PmSellStage.matched) {
          bought = shares;
          pending.setStage(PendingBetStage.confirming);
          final id = _placingTile;
          if (id != null) {
            tiles.advanceStep(id, step: 1, label: _l10n.betMatchedConfirming);
          }
        } else {
          pending.setStage(PendingBetStage.delayed);
        }
      },
    );
  }

  /// Ends a placement the venue accepted that got no shares: the reason on
  /// the slip for one that matched nothing or failed on chain, the honest
  /// result screen for one the venue did not answer for. True when it
  /// ended here. A limit order that rests (or went unanswered) is placed,
  /// not ended.
  bool _endsWithoutFill(PendingBetIntent intent, PmSellSettlement s,
      String? entrySource) {
    final pending = ref.read(pendingPolymarketBetProvider.notifier);
    switch (s.result) {
      case PmSellResult.filled:
      case PmSellResult.partial:
        return false;
      // A market order cannot rest; it reads as unanswered.
      case PmSellResult.resting:
      case PmSellResult.unknown:
        if (intent.isLimit) return false;
        _clearPlacing();
        ref.invalidate(polymarketOpenOrdersProvider);
        pending.updateStatus(PendingBetStatus.awaitingConfirmation);
        return true;
      case PmSellResult.notFilled:
      case PmSellResult.failed:
        final failed = s.result == PmSellResult.failed;
        final message =
            failed ? _l10n.betBuyFailedOnChain : _l10n.betBuyNotMatched;
        TrackingService.polymarketBetFailed(
          marketId: intent.tokenId,
          reason: failed ? 'failed_onchain' : 'not_filled',
          side: 'buy',
          orderType: intent.isLimit ? 'limit' : 'market',
          amountUsd: intent.amount,
          walletKind: 'hot',
          entrySource: entrySource ?? intent.entrySource,
          extra: {
            'funding_source': 'venue_balance',
            ...s.analyticsParams(),
          },
        );
        _clearPlacing(failedMessage: message);
        ref.invalidate(polymarketOpenOrdersProvider);
        pending.updateStatus(PendingBetStatus.failed, errorMessage: message);
        return true;
    }
  }

  /// A market buy that matched after the live game's delay: the provider
  /// only reports fills the POST echoed, so this one is reported here with
  /// the venue's own shares and cost (same event, same order hash).
  void _trackLateFill(PendingBetIntent intent, PmSellSettlement s,
      Map<String, dynamic> response, String? entrySource,
      {required String approval}) {
    final cost = s.proceeds;
    if (cost == null || s.soldShares <= 0) return;
    try {
      TrackingService.polymarketBetPlaced(
        side: 'buy',
        orderType: 'market',
        marketOutcome: intent.outcomeName,
        walletKind: 'hot',
        entrySource: entrySource,
        marketId: intent.tokenId,
        outcome: 'buy',
        amount: cost,
        price: cost / s.soldShares,
        shares: s.soldShares.round(),
        providerOrderId: PmSellSettlementWatcher.orderIdOf(response),
        category: intent.marketCategory,
        marketTitle: intent.marketQuestion,
        source: 'usdc_pool',
        betType: polymarketMarketType(intent.marketQuestion,
            outcome: intent.outcomeName),
        walletCategory: 'spending',
        extra: {...s.analyticsParams(), 'approval': approval},
      );
    } catch (_) {}
  }

  Map<String, Object> _settlementParams(PmSellSettlement s) =>
      s.analyticsParams();

  // Closed vocabulary only: never send raw provider bodies, signatures or
  // wallet addresses to analytics. Exception type alone hid the actual failure.
  String _placementFailureCode(Object error) {
    if (error is PolymarketSetupIncomplete) {
      return error.timedOut ? 'setup_timeout' : 'setup_failed';
    }
    if (error is PolymarketFundsConverting) return 'funds_converting';
    if (error is PolymarketThinBook) return 'liquidity_unavailable';
    if (error is ResolvedPolymarketOrder) return 'previous_order_resolved';
    if (error is PolymarketOrderCheckUnavailable) return 'venue_unreachable';
    if (error is PendingPolymarketOrder) return 'previous_order_unconfirmed';
    if (error is GeoBlockException) return 'region_unavailable';
    if (error is PolymarketReadException) return 'account_read_failed';
    if (error is TimeoutException) return 'request_timeout';
    if (error is InvalidApiKeyException) return 'credentials_invalid';
    final message = error.toString().toLowerCase();
    if (message.contains('fee settings') || message.contains('fee policy')) {
      return 'fee_settings_unavailable';
    }
    if (message.contains('price increment')) return 'market_terms_unavailable';
    if (message.contains('invalid order payload') ||
        message.contains('invalid expiration')) {
      return 'order_format_rejected';
    }
    if (message.contains('market is not yet ready')) return 'market_not_ready';
    if (message.contains('insufficient') || message.contains('balance')) {
      return 'balance_or_allowance';
    }
    if (message.contains('liquidity') ||
        message.contains('no match') ||
        message.contains('fok') ||
        message.contains('fak')) {
      return 'liquidity_unavailable';
    }
    if (message.contains('signature') ||
        message.contains('api key') ||
        message.contains('authentication failed')) {
      return 'approval_unverified';
    }
    if (message.contains('timed out') || message.contains('timeout')) {
      return 'request_timeout';
    }
    if (message.contains('account changed') ||
        message.contains('account is not connected') ||
        message.contains('account is still being prepared')) {
      return 'account_unavailable';
    }
    return 'unclassified';
  }

  String _friendlyPlacementError(Object e) {
    final l10n = l10nForLanguage(ref.read(settingsProvider).language);
    if (e is PolymarketThinBook) return polymarketThinBookMessage(l10n, e);
    return switch (_placementFailureCode(e)) {
      'setup_timeout' => l10n.betSetupSlow,
      'setup_failed' => l10n.betSetupFailed,
      'funds_converting' => l10n.betDepositStillConverting,
      'previous_order_resolved' => l10n.betPreviousOrderChecked,
      'region_unavailable' => l10n.tradingUnavailableRegion,
      'account_read_failed' ||
      'account_unavailable' =>
        l10n.betAccountUnavailable,
      'request_timeout' || 'venue_unreachable' => l10n.betConnectionUnavailable,
      'previous_order_unconfirmed' => l10n.ledgerBetPending,
      'fee_settings_unavailable' => l10n.betFeesUnavailable,
      'market_terms_unavailable' ||
      'market_not_ready' =>
        l10n.betMarketUnavailable,
      'order_format_rejected' => l10n.betOrderFormatRejected,
      'balance_or_allowance' => l10n.betAddFundsToPredict,
      'liquidity_unavailable' => l10n.betBuyLiquidityUnavailable,
      'credentials_invalid' || 'approval_unverified' => l10n.betApprovalRefresh,
      _ => l10n.betActionNotCompleted,
    };
  }
}

/// What the slip says when the book cannot fill the stake: what does fill
/// now when that is at least the venue's \$1 floor, else where the price
/// went past the approved cap, else that nothing is for sale there.
String polymarketThinBookMessage(AppLocalizations l10n, PolymarketThinBook e) {
  final fillable = e.fillableCents;
  if (fillable >= 1.0) {
    return l10n.betBuyFillsUpTo('\$${fillable.toStringAsFixed(2)}');
  }
  final price = e.price, limit = e.limit;
  if (price != null && limit != null && price > limit) {
    return l10n.betBuyPriceMoved(_cents(price), _cents(limit));
  }
  return l10n.betBuyLiquidityUnavailable;
}

/// The maximum a new approval would name after [e] stopped a buy because
/// the price moved past the approved one; null for any other failure.
double? polymarketRetryPrice(Object e) {
  if (e is! PolymarketThinBook) return null;
  final price = e.price, limit = e.limit, retry = e.retryPrice;
  if (price == null || limit == null || retry == null) return null;
  return price > limit + 1e-9 ? retry : null;
}

String _cents(double price) => polymarketCentsLabel(price);
