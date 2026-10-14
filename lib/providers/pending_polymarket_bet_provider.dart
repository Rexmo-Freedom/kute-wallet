import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
// lib/providers/pending_polymarket_bet_provider.dart
//
// Holds a Polymarket bet intent while the user tops up USDC. The
// bet_slip_sheet pre-stores the intent when the user hits Buy with an
// insufficient balance; the PendingBetOverlay watches balance and fires the
// order automatically once funds land.

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum PendingBetStatus {
  /// Initial state. User sees the one-tap convert CTA; nothing sent yet.
  awaitingDeposit,

  /// Quote created + Spark BTC payment being sent + Orchestra submit.
  /// Short-lived, driven by the PendingBetOverlay's convert flow.
  converting,

  /// BTC sent (or balance was already partial); waiting for USDC to land on
  /// Polygon.
  awaitingBalance,

  /// Funds arrived; submitting the order to the CLOB.
  placing,

  /// Order submitted successfully. The overlay will transition to
  /// BetPlacedOverlay shortly.
  done,

  /// Submission may have reached the venue; status reads must precede retry.
  awaitingConfirmation,

  /// Order submission (or the preceding swap) failed. The overlay shows a
  /// retry CTA and leaves any already-moved funds in the user's wallet.
  failed,
}

/// How far a submitted placement has got, for the slip's button: the
/// order on its way, a step of one-time account setup the venue asked for,
/// held for a live game's delay, or matched and being confirmed on chain.
enum PendingBetStage { submitting, settingUp, approving, delayed, confirming }

class PendingBetIntent {
  final PolymarketMarketBuyQuote? marketQuote;

  /// Fee terms read during preparation, so a resting limit order can be
  /// sized against the balance with its fees too. Null before preparation.
  final PolymarketFeeTerms? feeTerms;
  final bool venueAccepted;
  final double? filledShares;
  final double? filledCost;

  /// Shares the order asked for, so a part fill can say "2.1 of 4.5".
  final double? orderedShares;

  /// Where a submitted placement is (see [PendingBetStage]).
  final PendingBetStage stage;
  final String tokenId;
  final double amount;
  final double slippagePct;
  final String marketQuestion;
  final String? marketImage;
  final String outcomeName;

  /// Provisional display odds. Market execution and approval use the
  /// executable [marketQuote] prepared before authentication.
  final double expectedPrice;
  final PendingBetStatus status;
  final String? errorMessage;

  /// Set with a failure that stopped because the price moved past the
  /// approved maximum: the maximum a new approval would name now, so the
  /// slip's retry reads "Retry at 85¢". Cleared like [errorMessage].
  final double? retryMaxPrice;

  /// Why a failed bet stopped, as a fixed code (price_moved,
  /// market_closed, funds_timeout, book_unavailable, insufficient_usdc,
  /// approval_expired, ...), for the slip's steps to say what happened
  /// and where the money is. Cleared like [errorMessage].
  final String? failureCode;

  /// When the market closes (resolves). Used to gate fast-finalising
  /// markets ("5-minute bets" like hourly Bitcoin Up/Down) so they
  /// can only be funded from USDC — a BTC→USDC swap would not land
  /// in time before resolution.
  final DateTime? marketEndAt;

  /// Polymarket category (`crypto` | `sports` | `politics` | `science`
  /// | `other`) — propagated to `polymarket_bet_placed` analytics so
  /// we can answer "what kinds of markets do users bet on?". Optional
  /// because not every bet entry point has a PolymarketEvent in scope.
  final String? marketCategory;

  /// LIMIT order (GTC) vs SPOT (FAK, immediate). When true the bet is
  /// placed as a resting GTC order at [limitPrice] instead of a market
  /// fill. Smart funding still applies — the swap (if any) lands the USDC,
  /// then the GTC order is placed and escrows it on the book.
  final bool isLimit;

  /// The limit price (0.01–0.99) for a GTC order. Ignored when [isLimit]
  /// is false.
  final double limitPrice;

  /// The event's Gamma negRisk flag, threaded from the bet slip so the
  /// order signs against the right exchange even when the CLOB probe
  /// fails at placement time.
  final bool negRisk;

  /// Surface that queued the bet (analytics: origin of an autofired bet).
  final String? entrySource;

  /// Set when the stake is "everything I can spend" (the slip's Max): the
  /// spendable cash at the tap. Preparation then re-sizes [amount] to the
  /// largest stake that, with the fee ceiling at the executable best ask
  /// and the rounding cent, fits this budget, the same figures the
  /// placement check uses. Null for a typed stake, which is never changed.
  final double? spendAllBudgetUsd;

  /// One balance: the Dollars moved into Predictions for this bet, or
  /// null for a bet paid from venue cash that was already there. Set
  /// when the bet is queued behind its own funding leg
  /// (`OrderFundingController`); the autofire then fires from
  /// [PendingBetStatus.awaitingBalance] on the deposit's credit, resizes
  /// a market bet to what landed, and fails a limit bet that landed short.
  final double? fundUsd;

  /// Investing cash approved to go straight into Predictions for this bet
  /// (`VenueLimit.directLegs`: a cap per venue and the total), bound into
  /// the same one approval as [fundUsd]. Null when none.
  final Map<String, Object?>? directLegs;

  /// The Bitcoin → Dollars leg approved to top Dollars up before the
  /// funding move (`VenueLimit.fundBtc`), bound into the same one
  /// approval as [fundUsd]. Null when Dollars already covered it.
  final Map<String, Object?>? btcLeg;

  /// The funding leg's quote, as the one-way analytics reference
  /// (`TrackingService.orderRef`), never the raw id.
  final String? fundQuoteRef;

  /// What the venue already held when the funding leg left, and what the
  /// leg's quote said would arrive: the queued bet fires once the venue
  /// holds [fundReadyUsd] plus 99% of [fundArrivingUsd] (the move landed),
  /// not on the venue cash alone, which could already cover part of it.
  final double? fundReadyUsd;
  final double? fundArrivingUsd;

  /// When the bet was queued behind its funding leg. A queued bet older
  /// than [maxQueuedAge] never fires.
  final DateTime? queuedAt;

  /// Longest a queued bet may wait before it is dropped unplaced: the
  /// approval's own life (the 30 min autofire grant).
  static const Duration maxQueuedAge = Duration(minutes: 30);

  const PendingBetIntent({
    this.marketQuote,
    this.feeTerms,
    this.venueAccepted = false,
    this.filledShares,
    this.filledCost,
    this.orderedShares,
    this.stage = PendingBetStage.submitting,
    required this.tokenId,
    required this.amount,
    required this.slippagePct,
    required this.marketQuestion,
    required this.outcomeName,
    required this.expectedPrice,
    this.marketImage,
    this.marketEndAt,
    this.marketCategory,
    this.status = PendingBetStatus.awaitingDeposit,
    this.errorMessage,
    this.retryMaxPrice,
    this.failureCode,
    this.isLimit = false,
    this.limitPrice = 0.0,
    this.negRisk = false,
    this.entrySource,
    this.spendAllBudgetUsd,
    this.fundUsd,
    this.directLegs,
    this.btcLeg,
    this.fundQuoteRef,
    this.fundReadyUsd,
    this.fundArrivingUsd,
    this.queuedAt,
  });

  /// Whether this bet is (or was) funded from Dollars for the order.
  bool get funded => fundUsd != null;

  /// A queued bet past [maxQueuedAge] (counted from [queuedAt]) must not
  /// fire, whatever the balance says now. Never stale without a
  /// [queuedAt].
  bool isStale({DateTime? now}) {
    final at = queuedAt;
    if (at == null) return false;
    return (now ?? DateTime.now()).difference(at) > maxQueuedAge;
  }

  /// True when the market resolves in less than [threshold] (default
  /// 5 min). Used to force USDC-pool funding — a BTC swap roundtrip
  /// can take ~1–3 min on Orchestra and might miss the window.
  bool isShortMarket({Duration threshold = const Duration(minutes: 5)}) {
    final endAt = marketEndAt;
    if (endAt == null) return false;
    return endAt.difference(DateTime.now()) <= threshold;
  }

  PendingBetIntent copyWith({
    double? amount,
    PolymarketMarketBuyQuote? marketQuote,
    PolymarketFeeTerms? feeTerms,
    bool? venueAccepted,
    double? filledShares,
    double? filledCost,
    double? orderedShares,
    PendingBetStage? stage,
    PendingBetStatus? status,
    String? errorMessage,
    double? retryMaxPrice,
    String? failureCode,
    double? fundUsd,
    Object? directLegs = _keep,
    Object? btcLeg = _keep,
    String? fundQuoteRef,
    double? fundReadyUsd,
    double? fundArrivingUsd,
    DateTime? queuedAt,
  }) {
    return PendingBetIntent(
      marketQuote: marketQuote ?? this.marketQuote,
      feeTerms: feeTerms ?? this.feeTerms,
      venueAccepted: venueAccepted ?? this.venueAccepted,
      filledShares: filledShares ?? this.filledShares,
      filledCost: filledCost ?? this.filledCost,
      orderedShares: orderedShares ?? this.orderedShares,
      stage: stage ?? this.stage,
      tokenId: tokenId,
      amount: amount ?? this.amount,
      slippagePct: slippagePct,
      marketQuestion: marketQuestion,
      marketImage: marketImage,
      outcomeName: outcomeName,
      expectedPrice: expectedPrice,
      marketEndAt: marketEndAt,
      marketCategory: marketCategory,
      status: status ?? this.status,
      errorMessage: errorMessage,
      retryMaxPrice: retryMaxPrice,
      failureCode: failureCode,
      isLimit: isLimit,
      limitPrice: limitPrice,
      negRisk: negRisk,
      entrySource: entrySource,
      spendAllBudgetUsd: spendAllBudgetUsd,
      fundUsd: fundUsd ?? this.fundUsd,
      directLegs: identical(directLegs, _keep)
          ? this.directLegs
          : directLegs as Map<String, Object?>?,
      btcLeg: identical(btcLeg, _keep)
          ? this.btcLeg
          : btcLeg as Map<String, Object?>?,
      fundQuoteRef: fundQuoteRef ?? this.fundQuoteRef,
      fundReadyUsd: fundReadyUsd ?? this.fundReadyUsd,
      fundArrivingUsd: fundArrivingUsd ?? this.fundArrivingUsd,
      queuedAt: queuedAt ?? this.queuedAt,
    );
  }
}

/// [PendingBetIntent.copyWith]'s "leave [PendingBetIntent.directLegs] as
/// it is" (null clears it).
const Object _keep = Object();

class PendingPolymarketBetNotifier extends Notifier<PendingBetIntent?> {
  @override
  PendingBetIntent? build() => null;

  void setIntent(PendingBetIntent intent) {
    state = intent;
  }

  void updateStatus(PendingBetStatus status,
      {String? errorMessage, double? retryMaxPrice, String? failureCode}) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      status: status,
      errorMessage: errorMessage,
      retryMaxPrice: retryMaxPrice,
      failureCode: failureCode,
      // A new placement starts at the first step again.
      stage: status == PendingBetStatus.placing
          ? PendingBetStage.submitting
          : null,
    );
  }

  /// The funding leg has left Dollars: keep its quote reference on the
  /// queued bet, whatever status the autofire has moved it to since.
  void recordFunding({required String quoteRef}) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
        status: current.status,
        errorMessage: current.errorMessage,
        retryMaxPrice: current.retryMaxPrice,
        failureCode: current.failureCode,
        fundQuoteRef: quoteRef);
  }

  /// The submitted placement moved on (see [PendingBetStage]).
  void setStage(PendingBetStage stage) {
    final current = state;
    if (current == null || current.stage == stage) return;
    state = current.copyWith(status: current.status, stage: stage,
        errorMessage: current.errorMessage,
        failureCode: current.failureCode);
  }

  /// What the venue reports the order got, once it has matched: shares
  /// and their cost (null when the venue gave no cost), against the
  /// shares it asked for.
  void recordSettlement({
    required double filledShares,
    double? filledCost,
    required double orderedShares,
  }) {
    final current = state;
    if (current == null) return;
    state = PendingBetIntent(
      marketQuote: current.marketQuote,
      feeTerms: current.feeTerms,
      venueAccepted: true,
      filledShares: filledShares,
      // Never keep an echo that described a different number of shares.
      filledCost: filledCost,
      orderedShares: orderedShares,
      stage: current.stage,
      tokenId: current.tokenId,
      amount: current.amount,
      slippagePct: current.slippagePct,
      marketQuestion: current.marketQuestion,
      marketImage: current.marketImage,
      outcomeName: current.outcomeName,
      expectedPrice: current.expectedPrice,
      marketEndAt: current.marketEndAt,
      marketCategory: current.marketCategory,
      status: current.status,
      errorMessage: current.errorMessage,
      failureCode: current.failureCode,
      isLimit: current.isLimit,
      limitPrice: current.limitPrice,
      negRisk: current.negRisk,
      entrySource: current.entrySource,
      spendAllBudgetUsd: current.spendAllBudgetUsd,
      fundUsd: current.fundUsd,
      directLegs: current.directLegs,
      btcLeg: current.btcLeg,
      fundQuoteRef: current.fundQuoteRef,
      fundReadyUsd: current.fundReadyUsd,
      fundArrivingUsd: current.fundArrivingUsd,
      queuedAt: current.queuedAt,
    );
  }

  void recordFill(Map<String, dynamic> response) {
    if (response['success'] == true &&
        const {'matched', 'live', 'delayed', 'unmatched'}
            .contains(response['status']?.toString().toLowerCase())) {
      state = state?.copyWith(venueAccepted: true);
    }
    if (response['status']?.toString().toLowerCase() != 'matched') return;
    double? amount(dynamic value) {
      final n = value is num ? value.toDouble() : double.tryParse('$value');
      return n != null && n.isFinite && n > 0 ? n : null;
    }

    final cost = amount(response['makingAmount'] ?? response['making_amount']);
    final shares =
        amount(response['takingAmount'] ?? response['taking_amount']);
    if (cost == null || shares == null) return;
    state = state?.copyWith(filledCost: cost, filledShares: shares);
  }

  void clear() {
    state = null;
  }

  /// Drops an armed bet: one got ready on a fast market's slip
  /// (`BetPrefund`), still waiting for Confirm (`awaitingDeposit` with a
  /// funding cap). Clearing it drops its approval too (the autofire's
  /// listener). A queued, placing, failed or finished bet is left alone.
  void dropArmed() {
    final current = state;
    if (current != null &&
        current.funded &&
        current.status == PendingBetStatus.awaitingDeposit) {
      state = null;
    }
  }
}

final pendingPolymarketBetProvider =
    NotifierProvider<PendingPolymarketBetNotifier, PendingBetIntent?>(
  PendingPolymarketBetNotifier.new,
);
