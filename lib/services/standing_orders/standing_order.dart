// lib/services/standing_orders/standing_order.dart
//
// A standing order (founder, 9 November 2026): the one durable record of a
// prediction or an Investing order the person ACCEPTED (Face ID) whose
// money is still on its way to the venue. The money move starts only at
// the accept, never at the slip or the market opening; the slip closes at
// once; the order is placed the moment the venue counts the money, at a
// price never worse than the one approved, in one piece (never part now
// and part later), and nothing is kept as a working balance on a venue.
//
// What is durable: the PUBLIC facts here, in Hive per wallet
// (standing_order_store.dart). The signed Polymarket order, or the
// Investing approval, lives in secure storage keyed by the standing
// order's id and is deleted the moment the order is posted, cancelled or
// expired. A restart finds the record, checks the venue by the order's
// hash (`getOrderById`, through `HotPolymarketOrderGuard`) and goes on or
// settles it honestly (standing_orders_provider.dart).
//
// The states:
//
//   funding ─▶ funded ─▶ posting ─▶ posted ─▶ filled
//      │          │         │          └───────▶ failed
//      │          │         └──▶ filled | failed
//      └──┬───────┘
//         └──▶ cancelled (before posting only) | failed
//
// Pure Dart: the pending providers' statuses map onto these states here
// ([standingStateForBet], [standingStateForHlOrder]) and the tests pass
// the clock in.

import 'package:kute/providers/pending_hyperliquid_order_provider.dart'
    show HlReadiness, PendingHlOrderStatus;
import 'package:kute/providers/pending_polymarket_bet_provider.dart'
    show PendingBetStatus, PredictionsReadiness;
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart'
    show HlOrderResultKind;
import 'package:kute/services/polymarket/crypto_round.dart'
    show polyCryptoRoundOf;

/// Which venue the standing order is for.
enum StandingOrderVenue {
  predictions,
  investing;

  /// The analytics value (`venue`), the funding events' own.
  String get analyticsName =>
      this == StandingOrderVenue.predictions ? 'polymarket' : 'hyperliquid';
}

enum StandingOrderState {
  /// Accepted; the money is leaving (or still arriving at) the venue.
  funding,

  /// The venue holds the money; the order is about to be posted (the
  /// book's count, a conversion or an allowance may still be settling).
  funded,

  /// The signed order is with the venue (or on its way); its answer is
  /// not in yet.
  posting,

  /// The venue took the order and holds it (a resting limit, a held
  /// in-play order, or an answer that proved nothing yet).
  posted,

  /// Matched: the position exists.
  filled,

  /// Nothing was placed (or the venue killed it unfilled). The money
  /// stays on the venue, available.
  failed,

  /// Cancelled by the person before posting. The money already moved
  /// stays on the venue, available.
  cancelled,

  /// The price moved past the worst price approved while the money was
  /// moving (founder, 9 November 2026: never buy at a price never
  /// approved): stopped, the money on the venue, and the person is asked
  /// for one tap plus Face ID to place at the new price, or to cancel.
  needsApproval;

  bool get isTerminal =>
      this == StandingOrderState.filled ||
      this == StandingOrderState.failed ||
      this == StandingOrderState.cancelled;
}

/// How many times a prediction whose price moved (inside the approved
/// worst price) is re-priced and posted again, and over how long from
/// the first post. Each re-price is a new signature, taken only once the
/// earlier order is proven not accepted (the order guard's rules).
const int kStandingReprices = 3;
const Duration kStandingRepriceWindow = Duration(seconds: 90);

/// Longest a standing order lives from its accept: the approval's own
/// life (the 30 min autofire grant, `PendingBetIntent.maxQueuedAge`).
/// Past it, it is settled as expired with nothing placed.
const Duration kStandingOrderLifetime = Duration(minutes: 30);

/// The failure codes a standing order settles with, besides the venues'
/// own (`price_moved`, `insufficient_usdc`, ...).
abstract final class StandingOrderFailure {
  static const expired = 'expired';
  static const approvalMissing = 'approval_missing';
  static const notResumable = 'kind_not_resumable';
  static const notFilled = 'not_filled';
}

class StandingOrder {
  const StandingOrder({
    required this.id,
    required this.walletId,
    required this.venue,
    required this.marketKey,
    required this.marketTitle,
    required this.sideLabel,
    required this.isBuy,
    required this.size,
    required this.approvedPrice,
    required this.amountUsd,
    required this.orderKind,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    this.fundUsd = 0,
    this.arrivingUsd = 0,
    this.requiredUsd = 0,
    this.readyUsd = 0,
    this.slippagePct = 0,
    this.leverage = 1,
    this.marketKind,
    this.marketImage,
    this.marketCategory,
    this.eventSlug,
    this.roundWindow,
    this.marketEndAt,
    this.postNotBefore,
    this.orderHash,
    this.negRisk = false,
    this.failureCode,
    this.entrySource,
    this.attempts = 1,
    this.movedToPrice,
    this.filledSize,
    this.filledUsd,
  });

  /// Local id (never tracked).
  final String id;
  final String walletId;
  final StandingOrderVenue venue;

  /// The outcome token (Predictions) or the coin (Investing).
  final String marketKey;
  final String marketTitle;

  /// "Yes", "Up", "Long"...
  final String sideLabel;
  final bool isBuy;

  /// Shares (Predictions) or the margin's notional unit (Investing: the
  /// margin itself, `amountUsd`).
  final double size;

  /// The worst price the person approved: the signed limit of the
  /// Polymarket order, the mid the slip showed for Investing.
  final double approvedPrice;

  /// The stake or margin.
  final double amountUsd;

  /// `market` | `limit` (Predictions FAK/GTC; Investing market/limit).
  final String orderKind;
  final StandingOrderState state;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The funding plan: what left Dollars, what the quote said arrives,
  /// what the venue must hold and what it held at the accept.
  final double fundUsd;
  final double arrivingUsd;
  final double requiredUsd;
  final double readyUsd;
  final double slippagePct;

  /// Investing: 1 for spot.
  final int leverage;

  /// Investing: `perp` | `spot`.
  final String? marketKind;
  final String? marketImage;
  final String? marketCategory;

  /// Predictions: the event's slug and the window the slip opened on
  /// (`current` | `next`) for a 5-minute round.
  final String? eventSlug;
  final String? roundWindow;
  final DateTime? marketEndAt;

  /// The post waits for this moment: a pick for the NEXT 5-minute round
  /// funds ahead and posts once that round opens.
  final DateTime? postNotBefore;

  /// Predictions: the signed order's hash (the id the venue files it
  /// under), computed before any POST. Local only, never tracked or shown.
  final String? orderHash;
  final bool negRisk;

  /// Why it failed, as a fixed code.
  final String? failureCode;
  final String? entrySource;

  /// How many orders were signed for it: one, plus one per re-price.
  final int attempts;

  /// Predictions, [StandingOrderState.needsApproval]: the price now
  /// (0..1), past the approved worst price.
  final double? movedToPrice;

  /// [StandingOrderState.filled]: what the venue filled, as its answer
  /// said: the shares (Predictions) or the coin's size (Investing), and
  /// what they cost in dollars (Investing: the notional, size times the
  /// average fill price). Null when the answer carried none (a fill found
  /// on a restart): the approved figures stand in.
  final double? filledSize;
  final double? filledUsd;

  /// What the position holds in dollars once filled, from the fill's own
  /// figures: the cost of the shares (Predictions), the margin at the
  /// fill (Investing: the notional over the leverage); [amountUsd] while
  /// the fill carried none.
  double get placedUsd {
    final usd = filledUsd;
    if (usd == null || !usd.isFinite || usd <= 0) return amountUsd;
    return venue == StandingOrderVenue.investing && leverage > 1
        ? usd / leverage
        : usd;
  }

  bool get isOpen => !state.isTerminal;

  /// Cancellable only before the order left for the venue (or while it
  /// waits for a new approval).
  bool get canCancel =>
      state == StandingOrderState.funding ||
      state == StandingOrderState.funded ||
      state == StandingOrderState.needsApproval;

  bool isExpiredAt(DateTime now) =>
      !now.difference(createdAt).isNegative &&
      now.difference(createdAt) >= kStandingOrderLifetime;

  /// Whether the post may go out at [now] (the round it is for has
  /// opened, or it never waited for one).
  bool mayPostAt(DateTime now) {
    final at = postNotBefore;
    return at == null || !now.isBefore(at);
  }

  /// Whether [from] may move to [to] (see the file header).
  static bool canMove(StandingOrderState from, StandingOrderState to) {
    if (from == to) return false;
    return switch (from) {
      StandingOrderState.funding => const {
          StandingOrderState.funded,
          StandingOrderState.posting,
          StandingOrderState.failed,
          StandingOrderState.cancelled,
        }.contains(to),
      StandingOrderState.funded => const {
          StandingOrderState.posting,
          StandingOrderState.failed,
          StandingOrderState.cancelled,
        }.contains(to),
      StandingOrderState.posting => const {
          StandingOrderState.posted,
          StandingOrderState.filled,
          StandingOrderState.failed,
          StandingOrderState.needsApproval,
        }.contains(to),
      StandingOrderState.posted => const {
          StandingOrderState.filled,
          StandingOrderState.failed,
        }.contains(to),
      // Approved again (the slip placed it at the new price), cancelled,
      // or given up.
      StandingOrderState.needsApproval => const {
          StandingOrderState.cancelled,
          StandingOrderState.failed,
        }.contains(to),
      StandingOrderState.filled ||
      StandingOrderState.failed ||
      StandingOrderState.cancelled =>
        false,
    };
  }

  StandingOrder copyWith({
    StandingOrderState? state,
    DateTime? updatedAt,
    String? orderHash,
    Object? failureCode = _keep,
    DateTime? postNotBefore,
    int? attempts,
    double? movedToPrice,
    double? approvedPrice,
    double? size,
    double? filledSize,
    double? filledUsd,
  }) =>
      StandingOrder(
        id: id,
        walletId: walletId,
        venue: venue,
        marketKey: marketKey,
        marketTitle: marketTitle,
        sideLabel: sideLabel,
        isBuy: isBuy,
        size: size ?? this.size,
        approvedPrice: approvedPrice ?? this.approvedPrice,
        amountUsd: amountUsd,
        orderKind: orderKind,
        state: state ?? this.state,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        fundUsd: fundUsd,
        arrivingUsd: arrivingUsd,
        requiredUsd: requiredUsd,
        readyUsd: readyUsd,
        slippagePct: slippagePct,
        leverage: leverage,
        marketKind: marketKind,
        marketImage: marketImage,
        marketCategory: marketCategory,
        eventSlug: eventSlug,
        roundWindow: roundWindow,
        marketEndAt: marketEndAt,
        postNotBefore: postNotBefore ?? this.postNotBefore,
        orderHash: orderHash ?? this.orderHash,
        negRisk: negRisk,
        failureCode: identical(failureCode, _keep)
            ? this.failureCode
            : failureCode as String?,
        entrySource: entrySource,
        attempts: attempts ?? this.attempts,
        movedToPrice: movedToPrice ?? this.movedToPrice,
        filledSize: filledSize ?? this.filledSize,
        filledUsd: filledUsd ?? this.filledUsd,
      );

  Map<String, Object?> toJson() => {
        'v': 1,
        'id': id,
        'walletId': walletId,
        'venue': venue.name,
        'marketKey': marketKey,
        'marketTitle': marketTitle,
        'sideLabel': sideLabel,
        'isBuy': isBuy,
        'size': size,
        'approvedPrice': approvedPrice,
        'amountUsd': amountUsd,
        'orderKind': orderKind,
        'state': state.name,
        'createdAtMs': createdAt.toUtc().millisecondsSinceEpoch,
        'updatedAtMs': updatedAt.toUtc().millisecondsSinceEpoch,
        'fundUsd': fundUsd,
        'arrivingUsd': arrivingUsd,
        'requiredUsd': requiredUsd,
        'readyUsd': readyUsd,
        'slippagePct': slippagePct,
        'leverage': leverage,
        'marketKind': marketKind,
        'marketImage': marketImage,
        'marketCategory': marketCategory,
        'eventSlug': eventSlug,
        'roundWindow': roundWindow,
        'marketEndAtMs': marketEndAt?.toUtc().millisecondsSinceEpoch,
        'postNotBeforeMs': postNotBefore?.toUtc().millisecondsSinceEpoch,
        'orderHash': orderHash,
        'negRisk': negRisk,
        'failureCode': failureCode,
        'entrySource': entrySource,
        'attempts': attempts,
        'movedToPrice': movedToPrice,
        'filledSize': filledSize,
        'filledUsd': filledUsd,
      };

  /// Null for a record this version cannot read (never a throw: a stale
  /// row must not stop the others).
  static StandingOrder? fromJson(Map<String, Object?> json) {
    try {
      if (json['v'] != 1) return null;
      double dbl(Object? v, [double fallback = 0]) =>
          v is num ? v.toDouble() : fallback;
      DateTime? at(Object? v) => v is int
          ? DateTime.fromMillisecondsSinceEpoch(v, isUtc: true)
          : null;
      final venue = StandingOrderVenue.values
          .firstWhere((v) => v.name == json['venue']);
      final state =
          StandingOrderState.values.firstWhere((s) => s.name == json['state']);
      return StandingOrder(
        id: json['id'] as String,
        walletId: json['walletId'] as String,
        venue: venue,
        marketKey: json['marketKey'] as String,
        marketTitle: json['marketTitle'] as String? ?? '',
        sideLabel: json['sideLabel'] as String? ?? '',
        isBuy: json['isBuy'] as bool? ?? true,
        size: dbl(json['size']),
        approvedPrice: dbl(json['approvedPrice']),
        amountUsd: dbl(json['amountUsd']),
        orderKind: json['orderKind'] as String? ?? 'market',
        state: state,
        createdAt: at(json['createdAtMs'])!,
        updatedAt: at(json['updatedAtMs']) ?? at(json['createdAtMs'])!,
        fundUsd: dbl(json['fundUsd']),
        arrivingUsd: dbl(json['arrivingUsd']),
        requiredUsd: dbl(json['requiredUsd']),
        readyUsd: dbl(json['readyUsd']),
        slippagePct: dbl(json['slippagePct']),
        leverage: json['leverage'] is int ? json['leverage'] as int : 1,
        marketKind: json['marketKind'] as String?,
        marketImage: json['marketImage'] as String?,
        marketCategory: json['marketCategory'] as String?,
        eventSlug: json['eventSlug'] as String?,
        roundWindow: json['roundWindow'] as String?,
        marketEndAt: at(json['marketEndAtMs']),
        postNotBefore: at(json['postNotBeforeMs']),
        orderHash: json['orderHash'] as String?,
        negRisk: json['negRisk'] as bool? ?? false,
        failureCode: json['failureCode'] as String?,
        entrySource: json['entrySource'] as String?,
        attempts: json['attempts'] is int ? json['attempts'] as int : 1,
        movedToPrice: json['movedToPrice'] is num
            ? (json['movedToPrice'] as num).toDouble()
            : null,
        filledSize: json['filledSize'] is num
            ? (json['filledSize'] as num).toDouble()
            : null,
        filledUsd: json['filledUsd'] is num
            ? (json['filledUsd'] as num).toDouble()
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() =>
      'StandingOrder(${venue.name}, ${state.name}, \$$amountUsd)';
}

const Object _keep = Object();

/// The state a queued prediction's status and readiness read as. Null for
/// a bet not accepted yet (`awaitingDeposit`: the slip is open, nothing
/// moved) or a cleared one.
StandingOrderState? standingStateForBet(
  PendingBetStatus? status, {
  PredictionsReadiness? readiness,
  bool isLimit = false,
}) =>
    switch (status) {
      null || PendingBetStatus.awaitingDeposit => null,
      PendingBetStatus.converting => StandingOrderState.funding,
      PendingBetStatus.awaitingBalance =>
        readiness == null || readiness == PredictionsReadiness.waitingFunds
            ? StandingOrderState.funding
            : StandingOrderState.funded,
      PendingBetStatus.placing => StandingOrderState.posting,
      // A resting limit holds its cash on the book; a market order that
      // ended `done` matched.
      PendingBetStatus.done =>
        isLimit ? StandingOrderState.posted : StandingOrderState.filled,
      PendingBetStatus.awaitingConfirmation => StandingOrderState.posted,
      PendingBetStatus.failed => StandingOrderState.failed,
    };

/// The state a queued Investing order's status, readiness and result
/// read as. Null before the accept or once cleared.
StandingOrderState? standingStateForHlOrder(
  PendingHlOrderStatus? status, {
  HlReadiness? readiness,
  HlOrderResultKind? result,
}) =>
    switch (status) {
      null || PendingHlOrderStatus.awaitingDeposit => null,
      PendingHlOrderStatus.awaitingBalance =>
        readiness == null || readiness == HlReadiness.waitingFunds
            ? StandingOrderState.funding
            : StandingOrderState.funded,
      PendingHlOrderStatus.placing => StandingOrderState.posting,
      PendingHlOrderStatus.done => result == HlOrderResultKind.filled
          ? StandingOrderState.filled
          : StandingOrderState.posted,
      PendingHlOrderStatus.unconfirmed => StandingOrderState.posted,
      PendingHlOrderStatus.failed => StandingOrderState.failed,
    };

/// When a prediction's post may go out at the earliest: the start of the
/// round for a pick on a 5-minute window that has not started at [now]
/// (the Crypto card's buttons on "Next"), else null (post as soon as the
/// money is counted). [window] is the slip's own `roundWindow`; a slug
/// whose round is already in play never waits.
DateTime? standingPostNotBefore({
  String? eventSlug,
  String? window,
  required DateTime now,
}) {
  if (eventSlug == null) return null;
  final round = polyCryptoRoundOf(eventSlug);
  if (round == null) return null;
  if (!round.start.isAfter(now)) return null;
  if (window != null && window != 'next') return null;
  return round.start;
}
