// The book midpoint of many outcome tokens at once, read from the CLOB's
// batch route (`POST /books`), to seed the live price feed before the
// socket's first `book` frame.
//
// The live feed used to read `GET /book?token_id=` once per token. Opening
// a game with 311 markets subscribed 311 tokens, so the sheet's open fired
// 311 requests (and the socket rotation that followed fired them again for
// every token whose answer had not landed), each on its own connection and
// decoded on the UI isolate: ~620 requests, ~700 KB. One batch request per
// hundred tokens carries the same books (311 tokens: 4 requests, ~74 KB
// compressed), decoded off the UI isolate when large.

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'package:kute/services/polymarket/shown_price.dart';

/// Tokens per batch request.
const int kBookSeedBatch = 100;

const Duration _kTimeout = Duration(seconds: 6);

/// Bodies at least this large are decoded on another isolate.
const int _kOffThreadBytes = 64 * 1024;

/// What the seed learnt of some books: the midpoint of each tight one
/// ([mids]), the tokens whose book is wider than 10¢ ([wide]), and the
/// last trade of those that have traded ([lastTrades]).
typedef ClobBookSeeds = ({
  Map<String, double> mids,
  Set<String> wide,
  Map<String, double> lastTrades,
});

/// The midpoint of each of [tokenIds] whose book has both a bid and an
/// ask no more than 10¢ apart, keyed by token. A token with an empty or
/// wide book, an error or a failed batch is left out (the socket delivers
/// it). [client] is injectable for tests; the zone's client otherwise.
Future<Map<String, double>> fetchClobBookMids(
  Iterable<String> tokenIds, {
  http.Client? client,
}) async =>
    (await fetchClobBookSeeds(tokenIds, client: client, lastTrades: false))
        .mids;

/// [fetchClobBookMids], and the tokens whose book is wider than 10¢ with
/// the last trade of each that has one (one `POST /last-trades-prices`
/// per hundred wide tokens; skipped with [lastTrades] false). Polymarket
/// shows a wide book's last trade, not its midpoint ([polyShownPrice]).
Future<ClobBookSeeds> fetchClobBookSeeds(
  Iterable<String> tokenIds, {
  http.Client? client,
  bool lastTrades = true,
}) async {
  final tokens = tokenIds.where((t) => t.isNotEmpty).toSet().toList();
  if (tokens.isEmpty) {
    return (
      mids: <String, double>{},
      wide: <String>{},
      lastTrades: <String, double>{}
    );
  }
  final batches = [
    for (var i = 0; i < tokens.length; i += kBookSeedBatch)
      tokens.sublist(
          i,
          i + kBookSeedBatch > tokens.length
              ? tokens.length
              : i + kBookSeedBatch),
  ];
  final results = await Future.wait([
    for (final batch in batches) _readBatch(batch, client),
  ]);
  final mids = <String, double>{for (final r in results) ...r.mids};
  final wide = <String>{for (final r in results) ...r.wide};
  final trades = <String, double>{};
  if (lastTrades && wide.isNotEmpty) {
    final list = wide.toList();
    final answers = await Future.wait([
      for (var i = 0; i < list.length; i += kBookSeedBatch)
        _readLastTrades(
            list.sublist(i, (i + kBookSeedBatch).clamp(0, list.length)),
            client),
    ]);
    for (final a in answers) {
      trades.addAll(a);
    }
  }
  return (mids: mids, wide: wide, lastTrades: trades);
}

/// The last trade of each of [tokens] (`POST /last-trades-prices`), by
/// token; a token that has not traded, or a failed request, is left out.
/// The `/books` answer carries a `last_trade_price` too, but it is the
/// market's (a No trade at 99¢ shows on the Yes book), not the token's.
Future<Map<String, double>> _readLastTrades(
    List<String> tokens, http.Client? client) async {
  try {
    final uri = Uri.parse('https://clob.polymarket.com/last-trades-prices');
    final body = jsonEncode([
      for (final t in tokens) {'token_id': t}
    ]);
    const headers = {'Content-Type': 'application/json'};
    final response = await (client != null
            ? client.post(uri, headers: headers, body: body)
            : http.post(uri, headers: headers, body: body))
        .timeout(_kTimeout);
    if (response.statusCode != 200) return const {};
    return parseClobLastTrades(response.body);
  } catch (_) {
    return const {};
  }
}

/// The prices in a `POST /last-trades-prices` answer, by token, each
/// strictly inside (0, 1). Public for tests.
Map<String, double> parseClobLastTrades(String body) {
  final out = <String, double>{};
  final decoded = jsonDecode(body);
  if (decoded is! List) return out;
  for (final row in decoded) {
    if (row is! Map) continue;
    final token = row['token_id']?.toString();
    final p = double.tryParse(row['price']?.toString() ?? '');
    if (token == null || token.isEmpty || p == null) continue;
    if (p > 0 && p < 1) out[token] = p;
  }
  return out;
}

typedef _Batch = ({Map<String, double> mids, Set<String> wide});

const _Batch _kNoBatch = (mids: <String, double>{}, wide: <String>{});

Future<_Batch> _readBatch(List<String> tokens, http.Client? client) async {
  try {
    final uri = Uri.parse('https://clob.polymarket.com/books');
    final body = jsonEncode([
      for (final t in tokens) {'token_id': t}
    ]);
    const headers = {'Content-Type': 'application/json'};
    final response = await (client != null
            ? client.post(uri, headers: headers, body: body)
            : http.post(uri, headers: headers, body: body))
        .timeout(_kTimeout);
    if (response.statusCode != 200) return _kNoBatch;
    final text = response.body;
    return text.length < _kOffThreadBytes
        ? parseClobBookSeeds(text)
        : await Isolate.run(() => parseClobBookSeeds(text));
  } catch (_) {
    return _kNoBatch;
  }
}

/// The midpoints in a `POST /books` answer (a list of books). Public for
/// tests.
Map<String, double> parseClobBookMids(String body) =>
    parseClobBookSeeds(body).mids;

/// The midpoints of the tight books in a `POST /books` answer, and the
/// tokens whose book is wider than 10¢ ([clobBookIsWide]). Public for
/// tests.
({Map<String, double> mids, Set<String> wide}) parseClobBookSeeds(String body) {
  final mids = <String, double>{};
  final wide = <String>{};
  final decoded = jsonDecode(body);
  if (decoded is! List) return (mids: mids, wide: wide);
  for (final book in decoded) {
    if (book is! Map) continue;
    final token = book['asset_id']?.toString();
    if (token == null || token.isEmpty) continue;
    if (clobBookIsWide(book)) {
      wide.add(token);
      continue;
    }
    final mid = clobBookMid(book);
    if (mid != null) mids[token] = mid;
  }
  return (mids: mids, wide: wide);
}

({double? bid, double? ask}) _bestOf(Map book) {
  final bids = book['bids'] as List? ?? const [];
  final asks = book['asks'] as List? ?? const [];
  double? bestBid;
  for (final level in bids.whereType<Map>()) {
    final p = double.tryParse(level['price']?.toString() ?? '');
    if (p != null && p > 0 && (bestBid == null || p > bestBid)) bestBid = p;
  }
  double? bestAsk;
  for (final level in asks.whereType<Map>()) {
    final p = double.tryParse(level['price']?.toString() ?? '');
    if (p != null && p > 0 && (bestAsk == null || p < bestAsk)) bestAsk = p;
  }
  return (bid: bestBid, ask: bestAsk);
}

/// Whether one CLOB book is wider than 10¢ ([polySpreadIsWide]; an empty
/// side counts as 0 or 1). An error is not a book, so never wide.
bool clobBookIsWide(Map book) {
  if (book.containsKey('error')) return false;
  final best = _bestOf(book);
  return polySpreadIsWide(best.bid, best.ask);
}

/// The midpoint of one CLOB book (`/book` or one entry of `/books`): the
/// best bid and the best ask, wherever they sit in the arrays. Null when a
/// side is empty, the book is an error, the spread is wider than 10¢
/// (Polymarket shows the last trade then, [polyShownPrice]), or the mid is
/// not strictly inside (0, 1).
double? clobBookMid(Map book) {
  if (book.containsKey('error')) return null;
  final bids = book['bids'] as List? ?? const [];
  final asks = book['asks'] as List? ?? const [];
  if (bids.isEmpty || asks.isEmpty) return null;
  if (clobBookIsWide(book)) return null;
  // The CLOB returns both sides price-ascending, so the best bid is the
  // last and the best ask the first; scanning for them does not depend
  // on that order.
  var bestBid = -1.0;
  for (final level in bids.whereType<Map>()) {
    final p = double.tryParse(level['price']?.toString() ?? '') ?? -1;
    if (p > bestBid) bestBid = p;
  }
  var bestAsk = double.infinity;
  for (final level in asks.whereType<Map>()) {
    final p =
        double.tryParse(level['price']?.toString() ?? '') ?? double.infinity;
    if (p < bestAsk) bestAsk = p;
  }
  if (bestBid <= 0 || bestAsk <= 0 || !bestAsk.isFinite) return null;
  final mid = (bestBid + bestAsk) / 2.0;
  if (mid <= 0 || mid >= 1) return null;
  return mid;
}
