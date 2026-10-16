// lib/services/polymarket/crypto_window_results.dart
//
// How the last few windows of a crypto Up/Down market ended, for the
// compact results strip under the card's chart (polymarket.com shows the
// same row of up/down marks beside its "Past" menu).
//
// Sources, per window, first that answers:
//   1. Gamma: one `GET /events/keyset?slug=…&slug=…` for every window. A resolved
//      window carries `eventMetadata.finalPrice` and `priceToBeat`
//      (Up when the final price is at or above the price to beat, the
//      market's own rule), and its `outcomePrices` turn to "1"/"0".
//   2. For the window that just ended, before Gamma has resolved it
//      (about a minute): polymarket.com's own open and close price
//      (`/api/crypto/crypto-price`, `completed: true`), the numbers its
//      event page shows as "Price to beat" and "Final price".
// A window neither has settled stays pending (null).
//
// Pure Dart apart from the HTTP calls; unit tested in
// test/services/polymarket/crypto_window_results_test.dart.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/polymarket/polymarket_price_source.dart'
    show kCryptoTwapLookbackSeconds;

/// How many past windows the strip shows (polymarket.com shows four).
const int kCryptoRecentResults = 4;

/// One past window: its start (UTC epoch seconds) and whether it went Up
/// (true), Down (false) or is not settled yet (null).
class CryptoWindowResult {
  final int startEpoch;
  final bool? up;
  const CryptoWindowResult(this.startEpoch, this.up);

  @override
  bool operator ==(Object other) =>
      other is CryptoWindowResult &&
      other.startEpoch == startEpoch &&
      other.up == up;

  @override
  int get hashCode => Object.hash(startEpoch, up);

  @override
  String toString() => 'CryptoWindowResult($startEpoch, $up)';
}

/// The slug of the [minutes] window of [asset] starting at [startEpoch].
String cryptoWindowSlugAt(String asset, int minutes, int startEpoch) =>
    '${asset.toLowerCase()}-updown-${minutes}m-$startEpoch';

double? _num(Object? v) {
  final p = v is num ? v.toDouble() : double.tryParse('$v');
  return p != null && p.isFinite ? p : null;
}

/// Up (true) / Down (false) for one Gamma event, null while unresolved.
bool? cryptoOutcomeOfGammaEvent(Map<String, dynamic> event) {
  final meta = event['eventMetadata'];
  if (meta is Map) {
    final last = _num(meta['finalPrice']);
    final open = _num(meta['priceToBeat']);
    if (last != null && open != null && last > 0 && open > 0) {
      return last >= open;
    }
  }
  final markets = event['markets'];
  if (markets is! List || markets.isEmpty || markets.first is! Map) {
    return null;
  }
  final m = markets.first as Map;
  if (m['closed'] != true) return null;
  List<dynamic>? list(Object? v) {
    if (v is List) return v;
    if (v is String) {
      try {
        final d = jsonDecode(v);
        return d is List ? d : null;
      } catch (_) {}
    }
    return null;
  }

  final outcomes = list(m['outcomes']);
  final prices = list(m['outcomePrices']);
  if (outcomes == null || prices == null || outcomes.length != prices.length) {
    return null;
  }
  final upIdx = outcomes.indexWhere((o) => '$o'.toLowerCase() == 'up');
  if (upIdx < 0) return null;
  final p = _num(prices[upIdx]);
  if (p == 1) return true;
  if (p == 0) return false;
  return null;
}

/// The windows of a Gamma `/events/keyset?slug=…` answer (`{"events":
/// [...]}`) by slug, each Up, Down or null. Public for tests.
Map<String, bool?> parseCryptoResultEvents(String body) {
  final out = <String, bool?>{};
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return out;
  }
  final rows = decoded is Map ? decoded['events'] : decoded;
  if (rows is! List) return out;
  for (final e in rows) {
    if (e is! Map<String, dynamic>) continue;
    final slug = e['slug'];
    if (slug is String) out[slug] = cryptoOutcomeOfGammaEvent(e);
  }
  return out;
}

/// Up (true) / Down (false) from a completed `/api/crypto/crypto-price`
/// answer; null while the window is not complete. Public for tests.
bool? parseCryptoPriceOutcome(String body) {
  try {
    final d = jsonDecode(body);
    if (d is! Map || d['completed'] != true) return null;
    final open = _num(d['openPrice']);
    final close = _num(d['closePrice']);
    if (open == null || close == null || open <= 0 || close <= 0) return null;
    return close >= open;
  } catch (_) {
    return null;
  }
}

const Duration _kTimeout = Duration(seconds: 6);

/// The last results read per asset and window length, so the strip keeps
/// its marks across a window rollover while the new read is out.
final Map<String, List<CryptoWindowResult>> _lastRead = {};

String _cacheKey(String asset, int minutes) =>
    '${asset.toUpperCase()}-$minutes';

/// Remembers [results] as the latest for [asset] / [minutes].
void rememberCryptoResults(
    String asset, int minutes, List<CryptoWindowResult> results) {
  if (results.isNotEmpty) _lastRead[_cacheKey(asset, minutes)] = results;
}

/// What the strip shows for the window starting at [currentStart] before
/// its own read lands: the last results read, moved along to end at the
/// window before [currentStart] (a window not read yet is pending). Empty
/// when nothing was read for this market.
List<CryptoWindowResult> carriedCryptoResults(
    String asset, int minutes, int currentStart,
    {int count = kCryptoRecentResults}) {
  final last = _lastRead[_cacheKey(asset, minutes)];
  if (last == null || last.isEmpty) return const [];
  final span = minutes * 60;
  final known = {for (final r in last) r.startEpoch: r.up};
  return [
    for (var k = count; k >= 1; k--)
      CryptoWindowResult(
          currentStart - k * span, known[currentStart - k * span]),
  ];
}

/// Test hook: forget every remembered result.
void debugForgetCryptoResults() => _lastRead.clear();

/// The last [count] windows before the one starting at [currentStart]
/// (UTC epoch seconds), oldest first. Never throws: a window that cannot
/// be read is pending.
Future<List<CryptoWindowResult>> fetchCryptoRecentResults({
  required String asset,
  required int minutes,
  required int currentStart,
  int count = kCryptoRecentResults,
  http.Client? client,
}) async {
  final span = minutes * 60;
  final starts = [for (var k = count; k >= 1; k--) currentStart - k * span];
  final slugs = [for (final s in starts) cryptoWindowSlugAt(asset, minutes, s)];
  var bySlug = <String, bool?>{};
  try {
    final uri = Uri.parse('https://gamma-api.polymarket.com/events/keyset')
        .replace(queryParameters: {'slug': slugs, 'limit': '${slugs.length}'});
    final r = await SharedHttpClient.get(uri,
        kind: HttpCallKind.backgroundRead, timeout: _kTimeout, client: client);
    if (r.statusCode == 200) bySlug = parseCryptoResultEvents(r.body);
  } catch (_) {}
  final results = [
    for (var i = 0; i < starts.length; i++)
      CryptoWindowResult(starts[i], bySlug[slugs[i]]),
  ];
  // The window that just ended settles on polymarket.com's own open and
  // close before Gamma resolves it.
  if (results.isNotEmpty && results.last.up == null) {
    final last = results.last.startEpoch;
    final up = await _closeAgainstOpen(asset, minutes, last, client);
    if (up != null) results[results.length - 1] = CryptoWindowResult(last, up);
  }
  return results;
}

Future<bool?> _closeAgainstOpen(
    String asset, int minutes, int start, http.Client? client) async {
  const variants = {5: 'fiveminute', 15: 'fifteen', 240: 'fourhour'};
  final variant = variants[minutes];
  if (variant == null) return null;
  String iso(int epoch) =>
      '${DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true).toIso8601String().split('.').first}Z';
  try {
    final uri = Uri.parse('https://polymarket.com/api/crypto/crypto-price')
        .replace(queryParameters: {
      'symbol': asset.toUpperCase(),
      'eventStartTime': iso(start),
      'variant': variant,
      'endDate': iso(start + minutes * 60),
      'twapEnabled': 'true',
      'twapLookbackSeconds': '$kCryptoTwapLookbackSeconds',
    });
    final r = await SharedHttpClient.get(uri,
        kind: HttpCallKind.backgroundRead, timeout: _kTimeout, client: client);
    if (r.statusCode != 200) return null;
    return parseCryptoPriceOutcome(r.body);
  } catch (_) {
    return null;
  }
}
