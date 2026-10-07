// When an ended Predictions market is expected to settle, from the Data
// API's market resolution endpoint:
//
//   GET https://data-api.polymarket.com/v2/resolutions?condition=<id>
//   → {"data":[{"condition_id":…,"status":"proposed",…,
//               "expected_settlement_time":"2026-10-05T11:30:58Z",
//               "settlement_time_basis":"managed_proposal_expiration"}]}
//
// `expected_settlement_time` (RFC 3339, UTC) is only there while a
// proposed result waits out its challenge window; it is left out once the
// market is settled, while a proposal is under extended review, and before
// anything is proposed (`"data": []`). Read live on 5 Oct 2026: a game
// market under a proposal carried it; 5 and 15 minute crypto rounds never
// did (they go from no row straight to `resolved` about 53 s after their
// end, settled from their price feed), so their positions keep the
// generic "in a few minutes" caption.

import 'dart:convert';

import 'package:http/http.dart' as http;

const String _kResolutionsUrl = 'https://data-api.polymarket.com/v2/resolutions';

/// The expected settlement time in a `/v2/resolutions` response body, or
/// null when it carries none (no row, settled, extended review, or a
/// malformed body).
DateTime? polyExpectedSettlementOf(Object? decoded) {
  if (decoded is! Map) return null;
  final rows = decoded['data'];
  if (rows is! List) return null;
  for (final row in rows) {
    if (row is! Map) continue;
    final raw = row['expected_settlement_time'];
    if (raw is! String || raw.isEmpty) continue;
    final at = DateTime.tryParse(raw);
    if (at != null) return at.toUtc();
  }
  return null;
}

/// Fetches when [conditionId] is expected to settle. Null when unknown,
/// including any network or API failure: the caller falls back to its
/// generic copy.
Future<DateTime?> fetchPolyExpectedSettlement(
  String conditionId, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 8),
}) async {
  if (conditionId.isEmpty) return null;
  try {
    final uri = Uri.parse(_kResolutionsUrl)
        .replace(queryParameters: {'condition': conditionId});
    final resp = await (client == null ? http.get(uri) : client.get(uri))
        .timeout(timeout);
    if (resp.statusCode != 200) return null;
    return polyExpectedSettlementOf(jsonDecode(resp.body));
  } catch (_) {
    return null;
  }
}
