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
    this.isLimit = false,
    this.limitPrice = 0.0,
    this.negRisk = false,
    this.entrySource,
    this.spendAllBudgetUsd,
  });

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
      isLimit: isLimit,
      limitPrice: limitPrice,
      negRisk: negRisk,
      entrySource: entrySource,
      spendAllBudgetUsd: spendAllBudgetUsd,
    );
  }
}

class PendingPolymarketBetNotifier extends Notifier<PendingBetIntent?> {
  @override
  PendingBetIntent? build() => null;

  void setIntent(PendingBetIntent intent) {
    state = intent;
  }

  void updateStatus(PendingBetStatus status,
      {String? errorMessage, double? retryMaxPrice}) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      status: status,
      errorMessage: errorMessage,
      retryMaxPrice: retryMaxPrice,
      // A new placement starts at the first step again.
      stage: status == PendingBetStatus.placing
          ? PendingBetStage.submitting
          : null,
    );
  }

  /// The submitted placement moved on (see [PendingBetStage]).
  void setStage(PendingBetStage stage) {
    final current = state;
    if (current == null || current.stage == stage) return;
    state = current.copyWith(status: current.status, stage: stage,
        errorMessage: current.errorMessage);
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
      isLimit: current.isLimit,
      limitPrice: current.limitPrice,
      negRisk: current.negRisk,
      entrySource: current.entrySource,
      spendAllBudgetUsd: current.spendAllBudgetUsd,
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
}

final pendingPolymarketBetProvider =
    NotifierProvider<PendingPolymarketBetNotifier, PendingBetIntent?>(
  PendingPolymarketBetNotifier.new,
);
