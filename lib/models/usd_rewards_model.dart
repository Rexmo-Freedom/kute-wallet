// lib/models/usd_rewards_model.dart
//
// The dollar rewards programme's wire types, recovered from the rewards
// half of the deleted lib/models/flashnet_model.dart (commit b7e7c6f8^).
// Only the three shapes the Earn screen reads survive the recovery: the
// user summary behind the rate hero, one payout row, and the payout page
// behind Activity. The AMM, liquidity, host-fee, clawback, points and
// leaderboard models stayed deleted — nothing on the new screen reads
// them.
//
// Internal names keep the wire's own spelling ("usdb"); nothing here is
// user facing. The screen renders dollars, USD and $.

import 'dart:convert';

/// Thrown by the rewards client for any non-2xx response.
class RewardsApiException implements Exception {
  final int statusCode;
  final String body;
  const RewardsApiException(this.statusCode, this.body);

  /// The server's human-readable explanation, pulled out of the JSON body.
  /// The rewards API uses `reason`, and the Postgres-level failures we have
  /// seen use `error` / `message`; returns null when the body is not JSON or
  /// carries none.
  String? get reason {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      for (final key in const ['reason', 'error', 'message']) {
        final value = decoded[key];
        if (value is String && value.isNotEmpty) return value;
      }
    } catch (_) {
      // Body was not JSON — nothing to surface.
    }
    return null;
  }

  /// The rewards API answers an excluded / ineligible address with HTTP 400
  /// and a reason string rather than a zero balance. That is a legitimate
  /// state to render, not an error toast.
  bool get isNotEligible => statusCode == 400;

  @override
  String toString() => 'RewardsApiException($statusCode): $body';
}

/// `GET /rewards/:pubkey` — the Earn screen's hero.
class UserRewardsSummary {
  final String pubkey;
  final int usdbBalanceRaw;
  final double usdbBalanceDisplay;
  final int swapSats;
  final int swapCount;
  final int rewardsBracket;
  /// The service's annual rate in percent. Null when it did not report
  /// one: the app never shows a rate the service did not state.
  final double? rewardsPercent;
  final int estimatedSatsToday;

  const UserRewardsSummary({
    required this.pubkey,
    required this.usdbBalanceRaw,
    required this.usdbBalanceDisplay,
    required this.swapSats,
    required this.swapCount,
    required this.rewardsBracket,
    this.rewardsPercent,
    required this.estimatedSatsToday,
  });

  factory UserRewardsSummary.fromJson(Map<String, dynamic> json) {
    final balance = _parseMap(json['usdbBalance']);
    final volume = _parseMap(json['volumeUtcToday']);
    return UserRewardsSummary(
      pubkey: json['pubkey'] as String? ?? '',
      usdbBalanceRaw: _parseInt(balance['raw']),
      usdbBalanceDisplay: _parseDouble(balance['display']),
      swapSats: _parseInt(volume['swapSats']),
      swapCount: _parseInt(volume['swapCount']),
      rewardsBracket: json['rewardsBracket'] as int? ?? 0,
      rewardsPercent: _parseRate(json['rewardsPercent']),
      estimatedSatsToday: _parseInt(json['estimatedSatsToday']),
    );
  }
}

/// One day of the ledger behind `GET /rewards/:pubkey/payouts`.
class RewardPayout {
  final String day;
  final double usdbBalanceDisplay;
  final int rewardsBracket;
  /// The bracket's annual rate, or null when the ledger row omits it.
  final int? annualRewardsBps;

  /// Combined payout for the day, in SATS. Equals
  /// [rewardsPayoutSats] + [endorsementsPayoutSats] when the server sends
  /// the split.
  final int payoutSats;

  /// The holding-reward half of [payoutSats], in SATS.
  final int rewardsPayoutSats;

  /// The delegated-endorsement half of [payoutSats], in SATS. Zero for
  /// anyone who has never been endorsed.
  final int endorsementsPayoutSats;

  /// The day's swap volume that set the bracket, in SATS.
  final int volumeSats;

  final String status;
  final String? txId;
  final String? createdAt;
  final String? paidAt;

  const RewardPayout({
    required this.day,
    required this.usdbBalanceDisplay,
    required this.rewardsBracket,
    this.annualRewardsBps,
    required this.payoutSats,
    this.rewardsPayoutSats = 0,
    this.endorsementsPayoutSats = 0,
    this.volumeSats = 0,
    required this.status,
    this.txId,
    this.createdAt,
    this.paidAt,
  });

  /// True once the sats have actually landed in the wallet.
  /// Case and whitespace tolerant: an exact 'paid' match rendered every
  /// settled payout as pending the moment the server changed its wording.
  bool get isPaid => status.trim().toLowerCase() == 'paid';

  /// The payout day parsed as a date, or null when the server sends junk.
  DateTime? get dayDate => DateTime.tryParse(day);

  /// The bracket's annual rate as a percent (350 bps -> 3.5).
  double? get annualRewardsPercent =>
      annualRewardsBps == null ? null : annualRewardsBps! / 100;

  factory RewardPayout.fromJson(Map<String, dynamic> json) {
    final balance = _parseMap(json['usdbBalance']);
    return RewardPayout(
      day: json['day'] as String? ?? '',
      usdbBalanceDisplay: _parseDouble(balance['display']),
      rewardsBracket: json['rewardsBracket'] as int? ?? 0,
      annualRewardsBps: json['annualRewardsBps'] as int?,
      payoutSats: _parseInt(json['payoutSats']),
      rewardsPayoutSats: _parseInt(json['rewardsPayoutSats']),
      endorsementsPayoutSats: _parseInt(json['endorsementsPayoutSats']),
      volumeSats: _parseVolumeSats(json['volume']),
      status: json['status'] as String? ?? 'pending',
      txId: json['txId'] as String?,
      createdAt: json['createdAt'] as String?,
      paidAt: json['paidAt'] as String?,
    );
  }
}

/// `GET /rewards/:pubkey/payouts?limit=&offset=`
class PayoutHistoryResponse {
  final String pubkey;
  final List<RewardPayout> payouts;
  final int total;
  final int limit;
  final int offset;

  const PayoutHistoryResponse({
    required this.pubkey,
    required this.payouts,
    required this.total,
    this.limit = 0,
    this.offset = 0,
  });

  /// True when the server holds more rows past this page.
  bool get hasMore => offset + payouts.length < total;

  /// Sum of the PAID payouts on this page, in SATS. Pending rows are
  /// excluded on purpose: this is the number a surface labels "paid to
  /// date", and counting a payout the user has not received yet
  /// overstates it.
  int get totalPayoutSats =>
      payouts.where((p) => p.isPaid).fold(0, (sum, p) => sum + p.payoutSats);

  /// Sum of the payouts still awaiting settlement on this page, in SATS.
  int get totalPendingSats =>
      payouts.where((p) => !p.isPaid).fold(0, (sum, p) => sum + p.payoutSats);

  factory PayoutHistoryResponse.fromJson(Map<String, dynamic> json) {
    final items = (json['payouts'] as List? ?? [])
        .map((e) => RewardPayout.fromJson(e as Map<String, dynamic>))
        .toList();
    final pagination = _parseMap(json['pagination']);
    return PayoutHistoryResponse(
      pubkey: json['pubkey'] as String? ?? '',
      payouts: items,
      total: pagination['total'] as int? ?? items.length,
      limit: pagination['limit'] as int? ?? items.length,
      offset: pagination['offset'] as int? ?? 0,
    );
  }
}

// ───────────────────────────── parse helpers ─────────────────────────────

/// Safely reads a nested JSON object.
///
/// `as Map<String, dynamic>?` looks equivalent but throws on a
/// `Map<dynamic, dynamic>`, which is what you get from a hand-built literal
/// or from a decoder that did not preserve the key type. Returns an empty map
/// for anything that is not a map at all, so a shape change upstream degrades
/// to zeros instead of crashing the parse.
Map<String, dynamic> _parseMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v));
  }
  return const <String, dynamic>{};
}

int _parseInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

double _parseDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

/// Reads `swapSats` out of a volume block.
///
/// The rewards API is inconsistent about this: `volumeUtcToday` is an object
/// (`{swapSats, swapCount}`) while a payout row's `volume` has been seen as a
/// bare number. Accepts either shape so one field change upstream cannot zero
/// the UI.
int _parseVolumeSats(dynamic value) {
  if (value is Map<String, dynamic>) return _parseInt(value['swapSats']);
  return _parseInt(value);
}

/// A reported rate in percent, or null when absent or not a finite
/// non-negative number.
double? _parseRate(Object? raw) {
  final value = raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}');
  return value != null && value.isFinite && value >= 0 ? value : null;
}
