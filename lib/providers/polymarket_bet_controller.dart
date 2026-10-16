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
import 'dart:convert';
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
import 'package:kute/services/polymarket/bet_prefund.dart'
    show PolymarketMarketWindow;
import 'package:kute/services/polymarket/hot_order_guard.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/market_terms_store.dart';
import 'package:kute/services/polymarket/order_refusal.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/services/polymarket/placement_timeline.dart';
import 'package:kute/services/polymarket/placement_diagnostics.dart';
import 'package:kute/services/polymarket/placement_waits.dart';
import 'package:kute/services/polymarket/sell_settlement.dart';
import 'package:kute/services/polymarket/send_time_read.dart';
import 'package:kute/services/polymarket/warm_connections.dart';
import 'package:kute/services/polymarket_clob_websocket.dart'
    show PolymarketLiveBooks;
import 'package:kute/helpers/formatters/polymarket_side_labels.dart'
    show polymarketMarketType;
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/services/polymarket_onboarding_service.dart'
    show PolymarketReadException;
import 'package:kute/services/sound_service.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/services/tracking_service.dart';

/// Reads a market's trading window (`PolymarketBetController.marketWindow`)
/// before a bet is funded: the slip's closing-market check (audit P1-5).
final polymarketMarketWindowReaderProvider =
    Provider<Future<PolymarketMarketWindow?> Function(String conditionId)>(
        (ref) => PolymarketBetController.marketWindow);

final polymarketBetControllerProvider =
    Provider<PolymarketBetController>((ref) => PolymarketBetController(ref));

class PolymarketBetController {
  PolymarketBetController(this.ref);
  final Ref ref;

  double get _usdcBalance =>
      ref.read(polymarketTradingProvider).valueOrNull?.usdcBalance ?? 0;

  /// What the venue lets a new buy spend: the balance less what resting
  /// BUY orders already reserve against it, the same figure the slip
  /// shows as available. Sizing and the pre-sign check used the whole
  /// balance, so a stake the slip itself said did not fit could be signed
  /// and refused.
  double get _spendableUsdc {
    final state = ref.read(polymarketTradingProvider).valueOrNull;
    if (state == null) return 0;
    return spendableUsdc(state.usdcBalance, state.openOrders);
  }

  /// [cash] less the unfilled part of every resting BUY in [orders]. The
  /// slip sizes a funded bet's move against the same figure.
  static double spendableUsdc(double cash, List<Order> orders) {
    var committed = 0.0;
    for (final order in orders) {
      if (order.side.toUpperCase() != 'BUY') continue;
      final remaining = ((double.tryParse(order.originalSize) ?? 0) -
              (double.tryParse(order.sizeMatched) ?? 0))
          .clamp(0.0, double.infinity);
      committed += remaining * (double.tryParse(order.price) ?? 0);
    }
    return (cash - committed).clamp(0.0, double.infinity);
  }

  // Explicit prefunded bets use the actual pUSD and venue count. The display
  // aggregate may still show the pre-transfer balance (or unconverted USDC.e).
  Future<double> _freshSpendableUsdc() async {
    final notifier = ref.read(polymarketTradingProvider.notifier);
    final generation = notifier.accountGeneration;
    final wallet = notifier.signingWalletId;
    final proxy =
        ref.read(polymarketTradingProvider).valueOrNull?.proxyWalletAddress;
    try {
      final reads = await notifier
          .readBuyReadiness(refreshVenue: true)
          .timeout(const Duration(seconds: 15));
      final current = ref.read(polymarketTradingProvider).valueOrNull;
      if (!identical(notifier, ref.read(polymarketTradingProvider.notifier)) ||
          notifier.accountGeneration != generation ||
          notifier.signingWalletId != wallet ||
          current?.proxyWalletAddress != proxy) {
        throw ReauthRequired(const {DriftField.wallet});
      }
      if (reads == null ||
          !reads.setupDone ||
          reads.venue == null ||
          current == null) {
        return 0;
      }
      return spendableUsdc(
          min(reads.pusd.toDouble(), reads.venue!.balance.toDouble()) / 1e6,
          current.openOrders);
    } on AuthGrantException {
      rethrow;
    } catch (_) {
      return 0;
    }
  }

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
  Future<PendingBetIntent> prepareIntent(PendingBetIntent intent,
      {bool requireFreshCollateral = false}) async {
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
    // The terms the slip is showing (read within the last minute) are the
    // terms; the venue is only asked when nothing is cached.
    final cachedTerms = PolymarketFeeTerms.cached(intent.tokenId);
    PolymarketPlacementTimeline.tag(
        'fees_source', cachedTerms != null ? 'cached' : 'fetched');
    final terms = cachedTerms ??
        await PolymarketFeeTerms.fetchOrWorstCase(intent.tokenId);
    PolymarketPlacementTimeline.mark('fees');
    if (notifier.signingWalletId != walletId) {
      throw ReauthRequired(const {DriftField.wallet});
    }
    if (intent.isLimit) return intent.copyWith(feeTerms: terms);
    {
      final clock = Stopwatch()..start();
      final OrderBook book;
      try {
        book = await readBook(intent.tokenId,
            timeout: const Duration(seconds: 5));
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
      final spendable =
          requireFreshCollateral && intent.spendAllBudgetUsd != null
              ? await _freshSpendableUsdc()
              : _spendableUsdc;
      final budget = maxStakeBudget(intent.spendAllBudgetUsd, spendable);
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
    }
  }

  // ── Warm-up while the slip is open ──────────────────────────────────

  /// Called as a slip opens on [tokenId]: holds a warm connection to the
  /// venue, opens the saved market terms and fee curves, starts the fee
  /// read the slip's summary shares, and refreshes the builder code in
  /// the background. The live book arrives through the market feed the
  /// slip subscribes to. Paired with [releaseSlip].
  void warmSlip({required String tokenId}) {
    PolymarketWarmConnections.acquire();
    unawaited(PolymarketMarketTermsStore.warmUp());
    if (tokenId.isNotEmpty) unawaited(PolymarketFeeTerms.warmUp(tokenId));
    unawaited(PolymarketBackendService.refreshBuilderCode());
  }

  void releaseSlip() => PolymarketWarmConnections.release();

  // ── The book: the feed first, REST when it has nothing current ──────

  /// Where the last book read came from, for the timeline: feed | rest.
  String? _bookSource;

  /// The book for [tokenId] from the market feed when its snapshot is
  /// current and the market's terms (increment, neg-risk) are known; else
  /// null, and the REST book is read.
  static OrderBook? liveBook(String tokenId,
      {Duration maxAge = PolymarketLiveBooks.freshFor}) {
    final snapshot =
        PolymarketLiveBooks.instance.snapshot(tokenId, maxAge: maxAge);
    if (snapshot == null) return null;
    final negRisk = PolymarketMarketTermsStore.read(tokenId)?.negRisk;
    final tick = PolymarketMarketTermsStore.currentTickSize(tokenId,
        referencePrice: snapshot.bestAsk);
    if (negRisk == null || tick == null) return null;
    return snapshot.toOrderBook(tickSize: tick, negRisk: negRisk);
  }

  /// `GET /book` on the warm connection. The book carries the market's
  /// increment and neg-risk, which are saved for the feed's snapshots.
  static Future<OrderBook> restBook(String tokenId,
      {Duration timeout = const Duration(seconds: 5)}) {
    return PolymarketWarmConnections.withClob((c) async {
      final response = await c
          .get(Uri.https(PolymarketWarmConnections.clobHost, '/book',
              {'token_id': tokenId}))
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw Exception('orderbook fetch failed: ${response.statusCode}');
      }
      final book = parsePolymarketOrderBook(
          jsonDecode(response.body) as Map<String, dynamic>);
      PolymarketMarketTermsStore.saveFromBook(book);
      return book;
    });
  }

  /// `GET /markets/{condition_id}` on the warm connection: whether the
  /// market takes orders now, and its end. Null when it cannot be read.
  static Future<PolymarketMarketWindow?> marketWindow(String conditionId,
      {Duration timeout = const Duration(seconds: 4)}) async {
    if (!RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(conditionId)) return null;
    return PolymarketWarmConnections.withClob((c) async {
      final response = await c
          .get(Uri.https(
              PolymarketWarmConnections.clobHost, '/markets/$conditionId'))
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is! Map) return null;
      final accepting = body['accepting_orders'];
      if (accepting is! bool) return null;
      final end = body['end_date_iso'];
      return PolymarketMarketWindow(
        acceptingOrders: accepting,
        closed: body['closed'] == true,
        endAt: end is String ? DateTime.tryParse(end) : null,
      );
    });
  }

  /// The feed's current book, else the REST book within [timeout].
  Future<OrderBook> readBook(String tokenId,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final live = liveBook(tokenId);
    if (live != null) {
      _bookSource = 'feed';
      PolymarketPlacementTimeline.tag('book_source', 'feed');
      return live;
    }
    _bookSource = 'rest';
    PolymarketPlacementTimeline.tag('book_source', 'rest');
    return restBook(tokenId, timeout: timeout);
  }

  @visibleForTesting
  String? get debugBookSource => _bookSource;

  // ── The book at send time ───────────────────────────────────────────

  PolymarketSendTimeRead<OrderBook>? _sendBook;
  String? _sendBookToken;

  /// The order as the approval covers it, built while the prompt is on
  /// screen (see [prefetchForSend]).
  PolymarketOrderPlan? _plan;
  int _planBuilds = 0;

  @visibleForTesting
  PolymarketOrderPlan? get debugPlan => _plan;

  /// Plans built for the placement running now: one when the pre-built
  /// order went out as it was, two when the send-time price differed.
  @visibleForTesting
  int get debugPlanBuilds => _planBuilds;

  /// Called as the approval opens: with the market feed current the
  /// order is priced from its book when the approval returns, so nothing
  /// is read meanwhile; otherwise the REST book is read and kept at most
  /// a second old. The account's pUSD is read either way, and the order
  /// the approval covers (shares at the approved cap, increment, neg-
  /// risk, builder code) is built now, so only signing and the POST
  /// remain after the biometric.
  void prefetchForSend(PendingBetIntent intent) {
    _sendBook?.cancel();
    _sendBook = null;
    _plan = null;
    _planBuilds = 0;
    if (intent.isLimit) return;
    final tokenId = intent.tokenId;
    _sendBookToken = tokenId;
    if (liveBook(tokenId) == null) {
      _sendBook = PolymarketSendTimeRead<OrderBook>(
          () => restBook(tokenId, timeout: const Duration(seconds: 3)),
          maxAge: const Duration(seconds: 1),
          refreshEvery: const Duration(milliseconds: 700))
        ..start();
    }
    ref.read(polymarketTradingProvider.notifier).prefetchOrderReads();
    final quote = intent.marketQuote;
    if (quote != null &&
        quote.tokenId == tokenId &&
        quote.amount == intent.amount) {
      _plan = _buildPlan(intent.amount, quote.maxPrice, quote);
    }
  }

  PolymarketOrderPlan _buildPlan(
      double amount, double price, PolymarketMarketBuyQuote quote) {
    _planBuilds++;
    return PolymarketOrderPlan.build(
      amount: amount,
      price: price,
      tickSize: quote.tickSize,
      negRisk: quote.negRisk,
      builderCode: PolymarketBackendService.cachedBuilderCode,
    );
  }

  /// The plan for [price]: the one built during the approval when the
  /// send-time price is the approved one, else built now.
  PolymarketOrderPlan _planFor(
      double amount, double price, PolymarketMarketBuyQuote quote) {
    final held = _plan;
    if (held != null &&
        held.amount == amount &&
        (held.price - price).abs() < 1e-9 &&
        held.tickSize == quote.tickSize &&
        held.negRisk == quote.negRisk) {
      return held;
    }
    return _plan = _buildPlan(amount, price, quote);
  }

  /// The book for [tokenId] now: the feed's current snapshot, else the
  /// prefetched read when it is at most a second old, else a new read.
  /// Null when it cannot be read in time; the prepared quote then stands.
  Future<OrderBook?> _sendTimeBook(String tokenId) async {
    final live = liveBook(tokenId);
    if (live != null) {
      _sendBook?.cancel();
      _sendBook = null;
      PolymarketPlacementTimeline.tag('send_book_source', 'feed');
      return live;
    }
    PolymarketPlacementTimeline.tag('send_book_source', 'rest');
    final prefetched = _sendBook;
    _sendBook = null;
    final read = prefetched != null && _sendBookToken == tokenId
        ? prefetched
        : PolymarketSendTimeRead<OrderBook>(
            () => restBook(tokenId, timeout: const Duration(seconds: 3)),
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
    try {
      // Same allowance as the first quote: the venue is already under
      // load when a fill-or-kill misses, so this is no time to be strict.
      final book = await readBook(intent.tokenId,
          timeout: const Duration(seconds: 5));
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
    }
  }

  /// A refusal that says the price moved (the fill-and-kill matched
  /// nothing at its cap, or the price was refused): not a balance or any
  /// other refusal.
  static bool _isNoMatch(Object e) =>
      e is PolymarketOrderNotAcceptedException &&
      isPolymarketPriceRefusal(e.reason);

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
  AuthGrantException _failOnGrant(AuthGrantException e,
      {PendingBetIntent? intent, String? entrySource}) {
    if (intent != null) {
      _trackBetFailed(
          intent,
          switch (e) {
            ReauthRequired() => 'approval_details_changed',
            GrantRevoked() => 'approval_revoked',
            GrantExpired() => 'approval_expired',
            GrantConsumed() => 'approval_consumed',
          },
          entrySource: entrySource,
          error: e);
    }
    final l10n = l10nForLanguage(ref.read(settingsProvider).language);
    ref.read(pendingPolymarketBetProvider.notifier).updateStatus(
        PendingBetStatus.failed,
        errorMessage: e is ReauthRequired
            ? l10n.stepUpDetailsChanged
            : l10n.stepUpApprovalExpired);
    PolymarketPlacementTimeline.finish('failed',
        reason: switch (e) {
          ReauthRequired() => 'approval_details_changed',
          GrantRevoked() => 'approval_revoked',
          GrantExpired() => 'approval_expired',
          GrantConsumed() => 'approval_consumed',
        });
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
    bool requireFreshCollateral = false,
  }) async {
    final intent = ref.read(pendingPolymarketBetProvider);
    if (intent == null) {
      grant.revoke();
      PolymarketPlacementTimeline.finish('declined', reason: 'no_intent');
      return null;
    }
    _approval = FastBetWindow.approvalParam(grant.method);
    _orderPrice = null;
    _retried = false;

    final tradingState = ref.read(polymarketTradingProvider).valueOrNull;
    final proxyWallet = tradingState?.proxyWalletAddress;
    if (proxyWallet == null || proxyWallet.isEmpty) {
      _trackBetFailed(intent, 'wallet_not_ready', entrySource: entrySource);
      ref.read(pendingPolymarketBetProvider.notifier).updateStatus(
          PendingBetStatus.failed,
          errorMessage: l10nForLanguage(ref.read(settingsProvider).language)
              .receiveUsdcWalletNotReady);
      grant.revoke();
      PolymarketPlacementTimeline.finish('failed', reason: 'wallet_not_ready');
      return null;
    }

    // USDC-only placement (user decision: no more betting straight from
    // Lightning). A bet must be fully covered by the Predictions (USDC)
    // balance, fees included; anything short fails fast with a deposit
    // prompt. The deposit-then-autofire journey still works: the intent
    // stays stored, and once deposited USDC lands the autofire places it.
    final double spendable;
    try {
      spendable =
          requireFreshCollateral ? await _freshSpendableUsdc() : _spendableUsdc;
    } on AuthGrantException catch (e) {
      grant.revoke();
      return _failOnGrant(e, intent: intent, entrySource: entrySource);
    }
    if (allInMax(intent) > spendable + 1e-6) {
      _trackBetFailed(intent, 'insufficient_usdc', entrySource: entrySource);
      ref.read(pendingPolymarketBetProvider.notifier).updateStatus(
            PendingBetStatus.failed,
            errorMessage: l10nForLanguage(ref.read(settingsProvider).language)
                .betAddFundsToPredict,
          );
      grant.revoke();
      PolymarketPlacementTimeline.finish('failed', reason: 'insufficient_usdc');
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
        spendableUsd: spendable,
        successHaptic: successHaptic,
        entrySource: entrySource);
  }

  /// The one terminal polymarket_bet_failed per placement attempt. The
  /// provider no longer reports per-rung rejections (a killed FAK rung is
  /// retried and often fills), so this is the only failure event for a bet.
  void _trackBetFailed(PendingBetIntent intent, String reason,
      {String? entrySource, StackTrace? stackTrace, Object? error}) {
    final refusal =
        error is PolymarketOrderNotAcceptedException ? error.reason : null;
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
        'stage': polymarketFailureStage(reason, error),
        // Whether a second, re-priced order went out after the first was
        // refused for its price.
        'retried': _retried,
        ...placementContext(intent,
            approval: _approval, orderPrice: _orderPrice),
        // What the order book said when it refused the order: a closed
        // class, and the venue's own words (never typed by anyone) before
        // the figures it appends, hex and numbers taken out. No ids,
        // addresses or order data.
        if (refusal != null) ...polymarketRefusalParams(refusal),
      },
    );
  }

  /// The approval method and the price signed for the placement running
  /// now, for its failure event. Placements on an account never overlap
  /// (the order guard holds it), so one of each is enough.
  String? _approval;
  double? _orderPrice;
  bool _retried = false;
  double? _requotedPrice;

  /// What every placement failure event carries about the order: the
  /// exchange it goes to, its time in force, the market's shape, the
  /// exact prices, the signature type and how it was approved. Exact
  /// amounts and prices are allowed; nothing here identifies the person,
  /// the wallet or the order.
  @visibleForTesting
  static Map<String, Object> placementContext(PendingBetIntent intent,
      {String? approval, double? orderPrice}) {
    final betType = polymarketMarketType(intent.marketQuestion,
        outcome: intent.outcomeName);
    final negRisk = intent.marketQuote?.negRisk ?? intent.negRisk;
    return {
      'venue_market_type': negRisk ? 'neg_risk' : 'standard',
      'venue_order_type': intent.isLimit ? 'GTC' : 'FAK',
      'bet_type': betType,
      'outcome_category': switch (betType) {
        'moneyline' || 'spread' || 'over_under' => 'game',
        _ when negRisk => 'multi',
        _ => 'binary',
      },
      'is_short_round': isShortRound(intent.marketQuestion),
      'expected_price': intent.expectedPrice,
      if (intent.isLimit) 'order_price': intent.limitPrice,
      if (!intent.isLimit && orderPrice != null) 'order_price': orderPrice,
      if (!intent.isLimit && intent.marketQuote != null)
        'max_price': intent.marketQuote!.maxPrice,
      // Hot Predictions orders are POLY_1271 deposit-wallet orders.
      'sig_type': 3,
      if (approval != null) 'approval': approval,
    };
  }

  /// A five- or fifteen-minute round ("Bitcoin Up or Down - October 7,
  /// 5:00PM-5:05PM ET"), from its title: the slip's intent carries no
  /// slug.
  @visibleForTesting
  static bool isShortRound(String question) =>
      RegExp(r'up\s+or\s+down', caseSensitive: false).hasMatch(question) &&
      RegExp(r'\d{1,2}:\d{2}\s*[AP]M\s*[-–]\s*\d{1,2}:\d{2}\s*[AP]M',
              caseSensitive: false)
          .hasMatch(question);

  /// Where a placement ended, as one closed word: the step that failed.
  @visibleForTesting
  static String polymarketFailureStage(String code, Object? error) {
    if (error is PolymarketRefusalOutlivedApproval) return 'grant_expired';
    if (error is PolymarketStaleReservation) return 'balance_check';
    if (error is PolymarketBalanceRefused) return 'self_heal';
    if (error is PolymarketOrderNotAcceptedException) return 'submit';
    if (error is PolymarketThinBook) {
      return error.limit != null || error.fillableUsd > 0 ? 'quote' : 'book';
    }
    return switch (code) {
      'setup_timeout' ||
      'setup_failed' ||
      'wallet_not_ready' ||
      'account_unavailable' ||
      'account_read_failed' =>
        'setup',
      'funds_converting' => 'approvals',
      'insufficient_usdc' || 'balance_or_allowance' => 'balance_check',
      'fee_settings_unavailable' || 'market_terms_unavailable' => 'quote',
      'liquidity_unavailable' => 'book',
      'region_unavailable' => 'geo_blocked',
      'request_timeout' => 'timeout',
      'venue_unreachable' => 'submit',
      'credentials_invalid' || 'approval_unverified' => 'sign',
      'approval_expired' || 'approval_consumed' => 'grant_expired',
      'approval_details_changed' => 'reauth',
      'approval_revoked' => 'user_declined',
      'previous_order_resolved' || 'previous_order_unconfirmed' =>
        'guard_pending',
      'order_format_rejected' || 'market_not_ready' => 'submit',
      _ => 'unknown',
    };
  }

  /// The placement ended without an accepted order and without a failure:
  /// an earlier order still holds the outcome, or this one went out and
  /// its answer proves nothing yet. Reported as declined with its stage.
  void _trackPending(PendingBetIntent intent, PendingPolymarketOrder e) {
    PolymarketPlacementDiagnostics.declined(
      switch (e) {
        PolymarketOrderOutcomeUnknown() => 'outcome_unknown',
        PolymarketOrderCheckUnavailable() => 'venue_unreachable',
        PolymarketOrderInProgress() => 'order_in_progress',
        _ => 'previous_order_unconfirmed',
      },
      error: e,
      stage: e is PolymarketOrderOutcomeUnknown ? 'submit' : 'guard_pending',
      context: placementContext(intent,
          approval: _approval, orderPrice: _orderPrice),
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
      PolymarketPlacementTimeline.mark('response');
      unawaited(notifier.refresh().catchError((_) {}));
      ref.invalidate(polymarketOpenOrdersProvider);
      // What the order did on arrival: rests whole, bought part of it from
      // sellers already at the price (the rest waits), or bought it all.
      final settlement =
          await _settle(placed, intent, orderedShares: shares, resting: true);
      PolymarketPlacementTimeline.mark('settle');
      TrackingService.track('polymarket_limit_order_placed', params: {
        'source': 'usdc_pool',
        'wallet_kind': 'hot',
        ..._settlementParams(settlement),
      });
      if (_endsWithoutFill(intent, settlement, entrySource)) {
        PolymarketPlacementTimeline.finish(
            settlement.result == PmSellResult.unknown ? 'pending' : 'failed',
            reason: _settlementParams(settlement)['fill_outcome'] as String);
        return null;
      }
      final bought = settlement.soldShares;
      if (bought > 0) {
        ref.read(pendingPolymarketBetProvider.notifier).recordSettlement(
            filledShares: bought,
            filledCost: settlement.proceeds,
            orderedShares: shares);
        _showArriving(intent,
            shares: settlement.soldShares, cost: settlement.proceeds);
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
      PolymarketPlacementTimeline.finish(bought > 0 ? 'filled' : 'resting');
    } catch (e, st) {
      if (e is AuthGrantException) {
        return _failOnGrant(e, intent: intent, entrySource: entrySource);
      }
      if (e is PendingPolymarketOrder) {
        _trackPending(intent, e);
        ref
            .read(pendingPolymarketBetProvider.notifier)
            .updateStatus(PendingBetStatus.awaitingConfirmation);
        PolymarketPlacementTimeline.finish('pending',
            reason: _placementFailureCode(e));
        return null;
      }
      final code = _placementFailureCode(e);
      _trackBetFailed(intent, code,
          entrySource: entrySource, stackTrace: st, error: e);
      ref.read(pendingPolymarketBetProvider.notifier).updateStatus(
          PendingBetStatus.failed,
          errorMessage: _friendlyPlacementError(e));
      PolymarketPlacementTimeline.finish('failed', reason: code);
    }
    return null;
  }

  /// Direct CLOB placement from funded pUSD, using the prepared book cap.
  Future<AuthGrantException?> _placeOrder(
      PendingBetIntent intent, AuthGrant grant,
      {required double spendableUsd,
      bool successHaptic = true,
      String? entrySource}) async {
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
      if (quote.allInMax > spendableUsd + 1e-6) {
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
        'spendable': spendableUsd,
        'negRisk': quote.negRisk,
      });

      // The Portfolio shows the prediction on its way from here.
      _markPlacing(intent);

      // Submit at the approved maximum: CLOB matches at available better
      // prices. One definitive no-fill may retry, never an unknown result.
      Object? lastErr;
      Map<String, dynamic>? accepted;
      var orderedShares = 0.0;
      _requotedPrice = null;
      for (var i = 0; i < 2; i++) {
        // The order built during the approval when the price is the
        // approved one (the usual case), else built now for the price
        // the book moved to.
        final plan = _planFor(effectiveAmount, orderPrice, sendQuote);
        final shares = plan.shares;
        PolymarketPlacementDiagnostics.note('order', {
          'prebuilt': identical(plan, _plan) && _planBuilds == 1,
          'builder': plan.builderCode == null ? 'none' : 'attributed',
        });

        _orderPrice = orderPrice;
        _retried = i > 0;
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
            // On polymarket_bet_placed: the tolerance, whether this is the
            // re-priced second order, and the price the book quoted for
            // the stake (next to the fill_price the venue gave).
            analytics: {
              'slippage_bps': VenueAnalytics.bps(intent.slippagePct),
              'retried': i > 0,
              'quoted_price': _requotedPrice ?? sendQuote.price,
            },
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
              negRisk: sendQuote.negRisk,
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
              negRisk: sendQuote.negRisk,
              error: e,
              failureCode: _placementFailureCode(e),
              stage: polymarketFailureStage(_placementFailureCode(e), e));
          // Only a fill-and-kill that matched nothing is worth a second
          // rung at a re-read price. Any other refusal (balance, approval,
          // market state, an unrecognised 400) would only be refused again
          // and run the placement's self-heal a second time.
          if (e is! PolymarketOrderNotAcceptedException || !_isNoMatch(e)) {
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
          _requotedPrice = fresh.price;
          PolymarketPlacementDiagnostics.note('requote', {
            'price': orderPrice,
            'bestAsk': fresh.bestAsk,
          });
        }
      }
      if (lastErr != null) {
        throw lastErr;
      }

      // Accepted. The receipt shows the moment the venue says the order
      // matched (the POST's echo, or the order read for a live game's
      // delay), with the amounts the venue gave; the trade's way on chain
      // is followed behind it and the receipt updated when it lands.
      final immediateFill =
          ref.read(pendingPolymarketBetProvider)?.filledShares != null;
      final matched = Completer<double>();
      final settling = _settle(accepted!, intent,
          orderedShares: orderedShares,
          resting: false,
          onMatched: (shares) {
            if (!matched.isCompleted) matched.complete(shares);
          }).catchError((Object e) {
        // A read that failed outright: no shares proven. Reported as
        // unanswered, the way an unreadable order always was.
        return PmSellSettlement(
            result: PmSellResult.unknown,
            offeredShares: orderedShares,
            soldShares: 0,
            firstStatus: '${accepted!['status'] ?? ''}'.toLowerCase(),
            confirmedBy: 'none',
            timeToMatch: Duration.zero);
      });
      final first = await Future.any<Object>([matched.future, settling]);
      if (first is PmSellSettlement) {
        // Ended without a match first: nothing bought, or the venue did
        // not say in time. The settled result decides, as before.
        final settlement = first;
        PolymarketPlacementTimeline.mark('settle');
        if (_endsWithoutFill(intent, settlement, entrySource)) {
          PolymarketPlacementTimeline.finish(
              settlement.result == PmSellResult.unknown ? 'pending' : 'failed',
              reason: _settlementParams(settlement)['fill_outcome'] as String);
          return null;
        }
        _succeed(intent, grant, accepted, entrySource,
            orderedShares: orderedShares,
            shares: settlement.soldShares,
            cost: settlement.proceeds ??
                (immediateFill
                    ? ref.read(pendingPolymarketBetProvider)?.filledCost
                    : null),
            successHaptic: successHaptic);
        _afterSettlement(intent, settlement, accepted, entrySource,
            orderedShares: orderedShares, immediateFill: immediateFill);
        return null;
      }
      final shares = first as double;
      PolymarketPlacementTimeline.mark('matched');
      _succeed(intent, grant, accepted, entrySource,
          orderedShares: orderedShares,
          shares: shares,
          // The POST's echo when it describes these shares; else the
          // trades say later.
          cost: immediateFill
              ? ref.read(pendingPolymarketBetProvider)?.filledCost
              : null,
          successHaptic: successHaptic);
      unawaited(settling.then((settlement) => _afterSettlement(
          intent, settlement, accepted!, entrySource,
          orderedShares: orderedShares, immediateFill: immediateFill)));
    } catch (e, st) {
      if (e is AuthGrantException) {
        _clearPlacing();
        return _failOnGrant(e, intent: intent, entrySource: entrySource);
      }
      if (e is PendingPolymarketOrder) {
        _clearPlacing();
        _trackPending(intent, e);
        ref
            .read(pendingPolymarketBetProvider.notifier)
            .updateStatus(PendingBetStatus.awaitingConfirmation);
        PolymarketPlacementTimeline.finish('pending',
            reason: _placementFailureCode(e));
        return null;
      }
      final code = _placementFailureCode(e);
      _trackBetFailed(intent, code,
          entrySource: entrySource, stackTrace: st, error: e);
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

  /// The venue said the order matched: the receipt now, with [shares] and
  /// [cost] as the venue gave them (the cost is null until the trades say
  /// it when the POST echoed none), the balance read once at once, and the
  /// timeline sent. Settlement carries on behind it ([_afterSettlement]).
  void _succeed(PendingBetIntent intent, AuthGrant grant,
      Map<String, dynamic> accepted, String? entrySource,
      {required double orderedShares,
      required double shares,
      required double? cost,
      required bool successHaptic}) {
    final notifier = ref.read(polymarketTradingProvider.notifier);
    final pending = ref.read(pendingPolymarketBetProvider.notifier);
    pending.recordSettlement(
        filledShares: shares, filledCost: cost, orderedShares: orderedShares);
    // The matched shares count and their cost leaves the cash at once
    // (a no-op when the POST's echo already recorded this order).
    final orderId =
        (accepted['orderID'] ?? accepted['orderId'] ?? accepted['order_id'])
            ?.toString();
    if (orderId != null && orderId.isNotEmpty) {
      notifier.notePendingFill(
        key: orderId,
        tokenId: intent.tokenId,
        shares: shares,
        costUsd: cost ?? shares * intent.expectedPrice,
      );
    }
    // The cash moved: one targeted read now, not the next 5 s tick.
    unawaited(notifier.refreshBalanceAfterMatch());
    notifier.refreshAfterSale();
    PolymarketPlacementDiagnostics.note('filled', {
      'shares': shares,
      'cost': cost,
    });
    PolymarketPlacementTimeline.finish('filled');

    SoundService.playSuccess();
    // Apple Pay style two-beat success haptic (see note above).
    if (successHaptic) moneySuccessFeedback();

    pending.updateStatus(PendingBetStatus.done);
    // The Portfolio card turns from "Placing prediction…" into the
    // bridge until the real position lands.
    _showArriving(intent, shares: shares, cost: cost);
  }

  /// The settlement of a matched buy, finished behind the receipt: the
  /// venue's final shares and cost replace the echo, a fill that matched
  /// after a live game's delay is reported, and a trade the chain refused
  /// is said on the slip and the Portfolio tile. Never throws.
  void _afterSettlement(PendingBetIntent intent, PmSellSettlement settlement,
      Map<String, dynamic> accepted, String? entrySource,
      {required double orderedShares, required bool immediateFill}) {
    try {
      final pending = ref.read(pendingPolymarketBetProvider.notifier);
      if (settlement.result == PmSellResult.failed) {
        final message = _l10n.betBuyFailedOnChain;
        TrackingService.polymarketBetFailed(
          marketId: intent.tokenId,
          reason: 'failed_onchain',
          side: 'buy',
          orderType: 'market',
          amountUsd: intent.amount,
          walletKind: 'hot',
          entrySource: entrySource ?? intent.entrySource,
          extra: {
            'funding_source': 'venue_balance',
            ...settlement.analyticsParams(),
          },
        );
        _clearPlacing(failedMessage: message);
        ref.invalidate(polymarketOpenOrdersProvider);
        pending.updateStatus(PendingBetStatus.failed, errorMessage: message);
        return;
      }
      if (settlement.soldShares > 0) {
        pending.recordSettlement(
            filledShares: settlement.soldShares,
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
              approval: _approval ?? 'biometric');
        }
      }
      // Separate event name, fired alongside the provider's
      // polymarket_bet_placed for the same fill: dashboards must NOT sum it
      // with polymarket_bet_placed (that would count this bet twice). It
      // exists only to mark the slip → filled completion step, with how
      // the settlement went.
      TrackingService.track('polymarket_bet_placed_after_convert',
          params: _settlementParams(settlement));
      ref.read(polymarketTradingProvider.notifier).refreshAfterSale();
    } catch (_) {
      // The slip is gone (container disposed): nothing left to update.
    }
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
  void _showArriving(PendingBetIntent intent,
      {required double shares, required double? cost}) {
    try {
      final tiles = ref.read(placingPolymarketBetProvider.notifier);
      final id = _placingTile ??
          (() {
            final preShares = ref
                .read(polymarketActivePositionsProvider)
                .where((p) => p.tokenId == intent.tokenId)
                .fold<double>(0, (sum, p) => sum + p.size);
            final cost0 = cost ?? intent.amount;
            return tiles.markPlacing(
              tokenId: intent.tokenId,
              marketQuestion: intent.marketQuestion,
              marketImage: intent.marketImage,
              outcomeName: intent.outcomeName,
              amount: cost0,
              shares: shares,
              avgPrice: shares > 0 ? cost0 / shares : intent.expectedPrice,
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
    void Function(double shares)? onMatched,
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
          onMatched?.call(shares);
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
    if (error is PolymarketStaleReservation) return 'stale_matched_orders';
    if (error is PolymarketBalanceRefused) {
      // An allowance to an address the app does not know is never set
      // from a refusal; nothing about the balance is wrong.
      final spender = polymarketRefusalSpender(error.reason);
      return spender != null && !polymarketPinnedSpenders.containsKey(spender)
          ? 'venue_unknown_spender'
          : 'venue_balance_refused';
    }
    if (error is PolymarketRefusalOutlivedApproval) {
      return isPolymarketBalanceRefusal(error.reason)
          ? 'venue_balance_refused'
          : 'venue_rejected';
    }
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
    // The venue answered and did not take the order, for a reason none of
    // the above names. Nothing was placed; the journal is already settled.
    if (error is PolymarketOrderNotAcceptedException) return 'venue_rejected';
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
      'venue_balance_refused' => l10n.betVenueBalanceRefused,
      'venue_rejected' ||
      'venue_unknown_spender' =>
        l10n.ledgerErrorVenueRejected,
      'stale_matched_orders' => l10n.betVenueSettling,
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
