// lib/services/polymarket/combos/combo_models.dart
//
// Wire models for Polymarket Combos (parlays): the Requester API's RFQ
// create / accept / status responses and the Data API v2 combo positions
// and activity rows. Amounts on the RFQ wire are 6-decimal base-unit
// strings and stay BigInt here; the Data API serves USDC doubles.
//
// Sources: docs.polymarket.com/trading/combos/requesters.md and the Data
// API v2 OpenAPI (`ComboPosition`, `ComboLeg`, `ComboActivity`).

import 'package:kute/services/polymarket/combos/combo_math.dart';

enum ComboDirection {
  buy,
  sell;

  String get wire => this == buy ? 'BUY' : 'SELL';
}

/// A non-200 Requester/Builder gateway answer: validation, auth, state,
/// rate limit or a dependency failure. [code] is Polymarket's stable string
/// (`RATE_LIMITED`, `EXPIRED_RFQ`, ...); compare as strings, new codes come.
class ComboRfqException implements Exception {
  const ComboRfqException(this.httpStatus, this.code, [this.message]);
  final int httpStatus;
  final String code;
  final String? message;

  bool get isRateLimited => httpStatus == 429 || code == 'RATE_LIMITED';
  bool get isExpired =>
      code == 'EXPIRED_RFQ' || code == 'QUOTE_MISMATCH' || httpStatus == 409;
  bool get isUnauthenticated => httpStatus == 401;
  bool get isRegionBlocked =>
      httpStatus == 403 && (message ?? '').toLowerCase().contains('restricted');

  @override
  String toString() => 'Combo RFQ $httpStatus $code';
}

/// The quote a market maker won the RFQ with. Every amount is exact, in
/// 6-decimal base units, as the gateway sent it.
class ComboQuote {
  const ComboQuote({
    required this.rfqId,
    required this.quoteId,
    required this.direction,
    required this.expiresAt,
    required this.comboConditionId,
    required this.yesPositionId,
    required this.legPositionIds,
    required this.requestedE6,
    required this.blendedPriceE6,
    required this.makerAmountE6,
    required this.takerAmountE6,
    required this.totalRequiredE6,
    required this.netReceiveE6,
    this.builderCode,
  });

  final String rfqId;
  final String quoteId;
  final ComboDirection direction;

  /// Sign and accept before this instant (gateway `expires_at`, ms).
  final DateTime expiresAt;
  final String comboConditionId;

  /// The combo YES position the order trades (`request.yes_position_id`).
  final String yesPositionId;
  final List<String> legPositionIds;

  /// `requested_size.value_e6` echoed back: the BUY budget (pUSD) or the
  /// SELL size (shares).
  final BigInt requestedE6;
  final BigInt blendedPriceE6;
  final BigInt makerAmountE6;
  final BigInt takerAmountE6;

  /// BUY: pUSD the wallet must hold, fees included (the stake).
  /// SELL: combo shares the wallet must hold.
  final BigInt totalRequiredE6;

  /// BUY: combo shares received. SELL: exact pUSD proceeds after fees.
  final BigInt netReceiveE6;

  /// Builder Gateway only (`builder_code`). Null on the Requester API,
  /// where orders must carry the zero builder.
  final String? builderCode;

  bool get isBuy => direction == ComboDirection.buy;

  /// BUY: what the user pays, fees included.
  double get stakeUsd => e6ToDouble(totalRequiredE6);

  /// BUY: combo shares bought; each pays $1 if every leg wins. The lower
  /// of `taker_amount_e6` (the order) and `net_receive_e6` (what the
  /// gateway says arrives), so the payout is never overstated.
  BigInt get payoutE6 =>
      takerAmountE6 < netReceiveE6 ? takerAmountE6 : netReceiveE6;

  /// BUY: what the combo pays if every leg wins ($1 per share).
  double get payoutUsd => e6ToDouble(payoutE6);

  /// SELL: exact pUSD the user receives.
  double get proceedsUsd => e6ToDouble(netReceiveE6);

  /// BUY: shares bought. SELL: shares sold.
  double get sharesUsd =>
      e6ToDouble(isBuy ? netReceiveE6 : makerAmountE6);

  /// Payout ÷ stake: the "x" the combo pays when every leg wins.
  double get multiplier =>
      comboMultiplier(payoutE6: payoutE6, costE6: totalRequiredE6);

  /// Fees the quote carries: BUY total required above the order's own
  /// collateral; SELL gross collateral above the net proceeds.
  double get feesUsd => e6ToDouble(isBuy
      ? comboBuyFeeE6(
          totalRequiredE6: totalRequiredE6, makerAmountE6: makerAmountE6)
      : comboSellFeeE6(
          takerAmountE6: takerAmountE6, netReceiveE6: netReceiveE6));

  double get blendedPrice => e6ToDouble(blendedPriceE6);

  Duration remaining(DateTime now) {
    final d = expiresAt.difference(now);
    return d.isNegative ? Duration.zero : d;
  }
}

/// What a create returned: a winning quote, or a business outcome with no
/// quote (HTTP 200, `status: FAILED`, e.g. `NO_QUOTES`).
sealed class ComboRfqResult {
  const ComboRfqResult();
}

class ComboQuoted extends ComboRfqResult {
  const ComboQuoted(this.quote);
  final ComboQuote quote;
}

class ComboNoQuote extends ComboRfqResult {
  const ComboNoQuote(this.code);

  /// `NO_QUOTES`, `SIZE_TOO_LARGE`, ... or `FAILED` when none was given.
  final String code;
}

/// Durable RFQ state after acceptance (`GET /requests/{rfq_id}`).
class ComboRfqStatus {
  const ComboRfqStatus({
    required this.rfqId,
    required this.status,
    this.txHash,
    this.errorCode,
  });

  final String rfqId;
  final String status;
  final String? txHash;
  final String? errorCode;

  factory ComboRfqStatus.fromJson(Map<String, dynamic> j) {
    final error = j['error'];
    return ComboRfqStatus(
      rfqId: '${j['rfq_id'] ?? ''}',
      status: '${j['status'] ?? ''}'.toUpperCase(),
      txHash: j['tx_hash'] as String?,
      errorCode: error is Map ? error['code']?.toString() : null,
    );
  }

  /// Confirmed on chain.
  bool get isFilled => status == 'FILLED' || status == 'CONFIRMED';

  /// Ended without a fill: a maker decline (last look), an expired window
  /// or an execution failure.
  bool get isFailed =>
      status == 'FAILED' || status == 'EXPIRED' || status == 'CANCELED';

  bool get isTerminal => isFilled || isFailed;
}

/// One leg of a held combo, as the Data API enriches it.
class ComboLeg {
  const ComboLeg({
    required this.index,
    required this.positionId,
    required this.outcomeIndex,
    required this.outcomeLabel,
    required this.status,
    required this.currentPrice,
    required this.title,
    required this.question,
    this.marketId,
    this.marketSlug,
    this.eventSlug,
    this.eventTitle,
    this.imageUrl,
    this.resolvedAt,
    this.endDate,
  });

  final int index;
  final String positionId;
  final int outcomeIndex;
  final String outcomeLabel;

  /// OPEN / RESOLVED_WIN / RESOLVED_LOSS (and any newer code).
  final String status;

  /// Live price of the leg's outcome; its payout (1, 0 or 0.5 for a void)
  /// once the leg has resolved.
  final double currentPrice;
  final String title;
  final String question;

  /// Gamma market id (not the on-chain condition id).
  final String? marketId;
  final String? marketSlug;
  final String? eventSlug;
  final String? eventTitle;
  final String? imageUrl;
  final DateTime? resolvedAt;
  final String? endDate;

  bool get isOpen => status == 'OPEN' && resolvedAt == null;

  ComboLegOutcome get outcome {
    if (isOpen) return ComboLegOutcome.open;
    if (status == 'RESOLVED_WIN') return ComboLegOutcome.won;
    if (status == 'RESOLVED_LOSS') return ComboLegOutcome.lost;
    // A resolved leg with a fractional payout is a void (50/50).
    if (currentPrice > 0.01 && currentPrice < 0.99) return ComboLegOutcome.void_;
    return currentPrice >= 0.99 ? ComboLegOutcome.won : ComboLegOutcome.lost;
  }

  ComboLegMark get mark => ComboLegMark(
        resolved: !isOpen,
        price: currentPrice,
      );

  factory ComboLeg.fromJson(Map<String, dynamic> j) {
    final market = j['market'] is Map<String, dynamic>
        ? j['market'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final event = market['event'] is Map<String, dynamic>
        ? market['event'] as Map<String, dynamic>
        : const <String, dynamic>{};
    String? opt(dynamic v) {
      final s = v?.toString();
      return s == null || s.isEmpty ? null : s;
    }

    return ComboLeg(
      index: _int(j['leg_index']),
      positionId: '${j['leg_position_id'] ?? ''}',
      outcomeIndex: _int(j['leg_outcome_index']),
      outcomeLabel: '${j['leg_outcome_label'] ?? market['outcome'] ?? ''}',
      status: '${j['leg_status'] ?? 'OPEN'}'.toUpperCase(),
      currentPrice: _num(j['leg_current_price']),
      title: '${market['title'] ?? market['question'] ?? ''}',
      question: '${market['question'] ?? market['title'] ?? ''}',
      marketId: opt(market['market_id']),
      marketSlug: opt(market['slug']),
      eventSlug: opt(event['event_slug']),
      eventTitle: opt(event['event_title']),
      imageUrl: opt(market['icon_url']) ??
          opt(market['image_url']) ??
          opt(event['event_image']),
      resolvedAt: DateTime.tryParse('${j['leg_resolved_at'] ?? ''}'),
      endDate: opt(market['end_date']),
    );
  }
}

enum ComboLegOutcome { open, won, lost, void_ }

/// One combo the wallet holds (`GET /v2/positions/combos`). The Data API
/// has no current-value field: [estimatedValueUsd] multiplies the legs'
/// marks and is labelled an estimate wherever it shows.
class ComboPosition {
  const ComboPosition({
    required this.conditionId,
    required this.positionId,
    required this.outcomeIndex,
    required this.shares,
    required this.entryAvgPrice,
    required this.stakeUsd,
    required this.entryFeesUsd,
    required this.realizedPayoutUsd,
    required this.status,
    required this.redeemable,
    required this.legsTotal,
    required this.legsResolved,
    required this.legsPending,
    required this.legs,
    this.firstEntryAt,
    this.resolvedAt,
    this.updatedAt,
  });

  final String conditionId;

  /// Combo position id (decimal), the ERC-1155 id on the PositionManager.
  final String positionId;

  /// 0 = YES. Kute only ever buys the YES side.
  final int outcomeIndex;
  final double shares;
  final double entryAvgPrice;

  /// Fee-inclusive entry basis (`gross_entry_cost_usdc`): what was paid.
  final double stakeUsd;
  final double entryFeesUsd;
  final double realizedPayoutUsd;

  /// OPEN, REDEEMABLE, PARTIAL, RESOLVED_WIN, RESOLVED_LOSS,
  /// RESOLVED_PARTIAL.
  final String status;
  final bool redeemable;
  final int legsTotal;
  final int legsResolved;
  final int legsPending;
  final List<ComboLeg> legs;
  final DateTime? firstEntryAt;
  final DateTime? resolvedAt;
  final DateTime? updatedAt;

  bool get isYes => outcomeIndex == 0;

  /// Payout if every remaining leg wins: $1 per share, halved by each
  /// voided leg, zero once a leg lost.
  double get potentialPayoutUsd =>
      shares * comboBestCaseFactor([for (final l in legs) l.mark]);

  /// Potential payout ÷ stake.
  double get multiplier =>
      stakeUsd > 0 ? potentialPayoutUsd / stakeUsd : 0;

  /// The settled payout once every leg has resolved, else null. Zero as
  /// soon as one leg lost.
  double? get settledPayoutUsd {
    final f = comboSettlementFactor([for (final l in legs) l.mark]);
    return f == null ? null : shares * f;
  }

  bool get isLost => comboSettlementFactor([for (final l in legs) l.mark]) == 0;

  /// Open: no verdict yet and nothing to claim.
  bool get isOpen => !redeemable && !isLost && settledPayoutUsd == null;

  /// ESTIMATE: shares × product of the legs' marks.
  double get estimatedValueUsd =>
      comboEstimatedValue(shares: shares, legs: [for (final l in legs) l.mark]);

  factory ComboPosition.fromJson(Map<String, dynamic> j) {
    final legs = (j['legs'] is List ? j['legs'] as List : const [])
        .whereType<Map<String, dynamic>>()
        .map(ComboLeg.fromJson)
        .toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return ComboPosition(
      conditionId: '${j['combo_condition_id'] ?? ''}'.toLowerCase(),
      positionId: '${j['combo_position_id'] ?? ''}',
      outcomeIndex: _int(j['outcome_index']),
      shares: _num(j['current_size']),
      entryAvgPrice: _num(j['entry_avg_price_usdc']),
      stakeUsd: _num(j['gross_entry_cost_usdc']),
      entryFeesUsd: _num(j['entry_fees_usdc']),
      realizedPayoutUsd: _num(j['realized_payout_usdc']),
      status: '${j['status'] ?? ''}'.toUpperCase(),
      redeemable: j['redeemable'] == true,
      legsTotal: _int(j['legs_total'], fallback: legs.length),
      legsResolved: _int(j['legs_resolved']),
      legsPending: _int(j['legs_pending']),
      legs: legs,
      firstEntryAt: DateTime.tryParse('${j['first_entry_at'] ?? ''}'),
      resolvedAt: DateTime.tryParse('${j['resolved_at'] ?? ''}'),
      updatedAt: DateTime.tryParse('${j['updated_at'] ?? ''}'),
    );
  }
}

/// One combo lifecycle event (`GET /v2/activity/combos`): SPLIT, MERGE,
/// CONVERT, COMPRESS, WRAP, UNWRAP or REDEEM.
class ComboActivity {
  const ComboActivity({
    required this.type,
    required this.conditionId,
    required this.positionId,
    required this.timestamp,
    required this.legs,
    this.amountUsd,
    this.payoutUsd,
    this.transactionHash,
  });

  final String type;
  final String conditionId;
  final String positionId;
  final DateTime timestamp;
  final List<ComboLeg> legs;
  final double? amountUsd;

  /// REDEEM rows only.
  final double? payoutUsd;
  final String? transactionHash;

  bool get isRedeem => type == 'REDEEM';

  factory ComboActivity.fromJson(Map<String, dynamic> j) => ComboActivity(
        type: '${j['type'] ?? ''}'.toUpperCase(),
        conditionId: '${j['combo_condition_id'] ?? ''}'.toLowerCase(),
        positionId: '${j['combo_position_id'] ?? ''}',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            _int(j['timestamp']) * 1000,
            isUtc: true),
        legs: (j['legs'] is List ? j['legs'] as List : const [])
            .whereType<Map<String, dynamic>>()
            .map(ComboLeg.fromJson)
            .toList(),
        amountUsd: j['amount_usdc'] == null ? null : _num(j['amount_usdc']),
        payoutUsd: j['payout_usdc'] == null ? null : _num(j['payout_usdc']),
        transactionHash: j['transaction_hash'] as String?,
      );
}

double _num(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0.0;

int _int(dynamic v, {int fallback = 0}) =>
    v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? fallback;
