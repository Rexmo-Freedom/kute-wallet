// lib/services/api/usd_rewards_api.dart
//
// Client for the dollar rewards service, recovered from the deleted
// lib/services/api/flashnet_rewards_api.dart (commit b7e7c6f8^) and cut
// down to the two routes the Earn screen reads.
//
//   * Both routes are UNAUTHENTICATED. No bearer token, no challenge /
//     verify dance.
//   * The '/v1' prefix lives in the base URL below, so paths are written
//     '/rewards/...' and never '/v1/rewards/...'.
//   * Errors surface as RewardsApiException. HTTP 400 is not a bug: an
//     excluded or ineligible address answers 400 with a reason string,
//     which `RewardsApiException.isNotEligible` / `.reason` exist to
//     render.
//
// SERVICE STATE, probed 24 September 2026:
//   GET /v1/rewards/:pubkey           200, carries rewardsPercent
//   GET /v1/rewards/:pubkey/payouts   200, carries the daily ledger
//   GET /v1/stats                     500, Postgres error 42883
// `/stats` is protocol-wide social proof the new screen does not render,
// so it is deliberately absent here. Everything the screen needs is on
// the two live routes, and a failure on either surfaces as an error the
// screen renders as "unavailable" rather than as a zero.
//
// The endorsement / points / leaderboard routes stayed deleted. See
// commit b7e7c6f8^ for the notes on what shipping endorsements would
// take (UUIDv7 nonces, canonical-YAML secp256k1 signatures).

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:kute/models/usd_rewards_model.dart';

const _rewardsBaseUrl = 'https://rewards.flashnet.xyz/v1';

class UsdRewardsApi {
  final http.Client _http;

  UsdRewardsApi({http.Client? client}) : _http = client ?? http.Client();

  /// `GET /rewards/:pubkey` — balance, today's volume, bracket, rate and the
  /// server's own estimate of today's sats. Prefer `estimatedSatsToday` over
  /// any locally computed projection: it is the number the programme pays.
  Future<UserRewardsSummary> getUserSummary(String pubkey) async {
    final res = await _getRewards('/rewards/$pubkey');
    return UserRewardsSummary.fromJson(res as Map<String, dynamic>);
  }

  /// `GET /rewards/:pubkey/payouts` — the daily bitcoin payout ledger.
  Future<PayoutHistoryResponse> getPayoutHistory(
    String pubkey, {
    int limit = 30,
    int offset = 0,
  }) async {
    final res = await _getRewards(
        '/rewards/$pubkey/payouts?limit=$limit&offset=$offset');
    return PayoutHistoryResponse.fromJson(res as Map<String, dynamic>);
  }

  Future<dynamic> _getRewards(String path) async {
    final uri = Uri.parse('$_rewardsBaseUrl$path');
    final res = await _http.get(uri, headers: {
      'Content-Type': 'application/json',
    });
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body);
    }
    throw RewardsApiException(res.statusCode, res.body);
  }
}
