// lib/services/polymarket/crypto_live_odds.dart
//
// The Up chance a crypto Up/Down card shows, read the way polymarket.com
// reads it, with no smoothing:
//
//   1. the market feed's live book for the Up token (PolymarketLiveBooks,
//      kept current by every `book` and `price_change` frame): its
//      midpoint, or its last trade when the spread is wider than 10¢
//      (polyShownPrice), exactly as it stands;
//   2. while the feed has no current book for the token, the CLOB's own
//      midpoint over REST (`POST /midpoints`, one request for every card
//      on screen), every 1.5 s;
//   3. only when neither has answered for a while, the market list's
//      price the card already holds (Gamma `outcomePrices`, refreshed
//      every 10 s).
//
// The general live price feed (LivePriceNotifier) keeps its 60-second
// fresh-midpoint rule and ±25% band for every other market; the crypto
// cards no longer read it for their odds.
//
// Pure Dart apart from the HTTP call; unit tested in
// test/services/polymarket/crypto_live_odds_test.dart.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/polymarket/shown_price.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';

/// Where a card's live Up chance came from.
enum CryptoOddsSource { websocket, rest }

/// One live Up chance for a crypto Up/Down card.
class CryptoLiveOdds {
  /// Chance of Up, 0..1 (Down is `1 - up`).
  final double up;
  final CryptoOddsSource source;

  const CryptoLiveOdds(this.up, this.source);

  @override
  bool operator ==(Object other) =>
      other is CryptoLiveOdds && other.up == up && other.source == source;

  @override
  int get hashCode => Object.hash(up, source);

  @override
  String toString() => 'CryptoLiveOdds($up, ${source.name})';
}

/// How often the REST midpoint is read for tokens the market feed has no
/// current book for.
const Duration kCryptoOddsRestEvery = Duration(milliseconds: 1500);

/// Longest wait between REST reads after failures (1.5 s, 3 s, 6 s): a
/// CLOB that is down is not asked every 1.5 s.
const Duration kCryptoOddsRestMaxBackoff = Duration(seconds: 6);

/// Per-attempt timeout and total deadline of one REST read. The deadline
/// keeps the shared client's background retries inside one poll period,
/// so a slow CLOB never stacks requests.
const Duration kCryptoOddsRestTimeout = Duration(milliseconds: 1200);
const Duration kCryptoOddsRestDeadline = Duration(milliseconds: 1500);

/// How long a live chance stands without being confirmed (by the feed or
/// REST) before the card goes back to the market list's price.
const Duration kCryptoOddsMaxAge = Duration(seconds: 10);

/// The wait before the next REST read after [failures] failed ones in a
/// row.
Duration cryptoOddsRestInterval(int failures) {
  if (failures <= 0) return kCryptoOddsRestEvery;
  final ms = kCryptoOddsRestEvery.inMilliseconds * (1 << failures.clamp(0, 8));
  return ms >= kCryptoOddsRestMaxBackoff.inMilliseconds
      ? kCryptoOddsRestMaxBackoff
      : Duration(milliseconds: ms);
}

/// Whether [p] is a chance a live card may show: a finite number strictly
/// inside (0, 1). 0 and 1 only mean something once a market has resolved,
/// and a resolved window has already rolled to the next one on the card.
bool cryptoOddsSane(double? p) => p != null && p.isFinite && p > 0 && p < 1;

/// The Up chance the live [book] shows, Polymarket's way: its midpoint,
/// or [lastTrade] when the spread is wider than 10¢; null when the book
/// has nothing sane to show.
double? cryptoShownUp(PolymarketLiveBook? book, {double? lastTrade}) {
  if (book == null) return null;
  final bid = book.bestBid;
  final ask = book.bestAsk;
  if (bid == null && ask == null) {
    return cryptoOddsSane(lastTrade) ? lastTrade : null;
  }
  final p = polyShownPrice(bid: bid, ask: ask, lastTrade: lastTrade);
  return cryptoOddsSane(p) ? p : null;
}

/// The midpoints in a `POST /midpoints` answer (`{token: "0.595"}`), by
/// token, sane values only. Public for tests.
Map<String, double> parseClobMidpoints(String body) {
  final out = <String, double>{};
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return out;
  }
  if (decoded is! Map) return out;
  decoded.forEach((k, v) {
    final p = v is num ? v.toDouble() : double.tryParse('$v');
    if (k is String && k.isNotEmpty && cryptoOddsSane(p)) out[k] = p!;
  });
  return out;
}

/// The CLOB midpoint of each of [tokens], in one `POST /midpoints`
/// request through the shared keep-alive client (a background read with a
/// short timeout and deadline). Throws on a transport error or a non-200
/// answer so the caller can back off; a token without a book is left out.
Future<Map<String, double>> fetchClobMidpoints(
  Iterable<String> tokens, {
  http.Client? client,
}) async {
  final list = tokens.where((t) => t.isNotEmpty).toSet().toList();
  if (list.isEmpty) return const {};
  final response = await SharedHttpClient.post(
    Uri.parse('https://clob.polymarket.com/midpoints'),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode([
      for (final t in list) {'token_id': t}
    ]),
    kind: HttpCallKind.backgroundRead,
    timeout: kCryptoOddsRestTimeout,
    deadline: kCryptoOddsRestDeadline,
    client: client,
  );
  if (response.statusCode != 200) {
    throw http.ClientException('midpoints ${response.statusCode}');
  }
  return parseClobMidpoints(response.body);
}
