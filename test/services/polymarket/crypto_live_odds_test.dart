// The crypto Up/Down card's live Up chance is the book as it stands:
// its midpoint, or its last trade when the spread is wider than 10¢,
// with nothing but broken values filtered out (no smoothing window, no
// band around an earlier price).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/polymarket/crypto_live_odds.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';

void main() {
  late PolymarketLiveBooks books;
  final now = DateTime(2026, 10, 12, 12);

  setUp(() {
    books = PolymarketLiveBooks.instance..reset();
    books.clock = () => now;
  });

  void book(String asset,
      {List<String> bids = const [], List<String> asks = const []}) {
    books.apply(PolymarketBookMessage.fromJson({
      'event_type': 'book',
      'asset_id': asset,
      'market': 'm',
      'bids': [
        for (final p in bids) {'price': p, 'size': '10'}
      ],
      'asks': [
        for (final p in asks) {'price': p, 'size': '10'}
      ],
      'hash': 'h',
    }));
  }

  test('a tight book shows its midpoint', () {
    book('up', bids: ['0.58', '0.59'], asks: ['0.60', '0.70']);
    expect(cryptoShownUp(books.snapshot('up')), closeTo(0.595, 1e-9));
  });

  test('a move far from the last chance shows at once, unbanded', () {
    book('up', bids: ['0.20'], asks: ['0.21']);
    expect(cryptoShownUp(books.snapshot('up')), closeTo(0.205, 1e-9));
    // The book jumps to 80¢: four times the last chance, shown as is.
    books.apply(polymarketWsMessagesOf(jsonEncode({
      'event_type': 'price_change',
      'asset_id': 'up',
      'price_changes': [
        {'asset_id': 'up', 'price': '0.20', 'size': '0', 'side': 'BUY'},
        {'asset_id': 'up', 'price': '0.21', 'size': '0', 'side': 'SELL'},
        {'asset_id': 'up', 'price': '0.80', 'size': '5', 'side': 'BUY'},
        {'asset_id': 'up', 'price': '0.81', 'size': '5', 'side': 'SELL'},
      ],
    })).single);
    expect(cryptoShownUp(books.snapshot('up')), closeTo(0.805, 1e-9));
  });

  test('a wide book shows its last trade, or nothing', () {
    book('up', bids: ['0.30'], asks: ['0.70']);
    expect(cryptoShownUp(books.snapshot('up')), isNull);
    books.apply(PolymarketLastTradePriceMessage.fromJson({
      'event_type': 'last_trade_price',
      'asset_id': 'up',
      'price': '0.44',
    }));
    expect(books.lastTrade('up'), 0.44);
    expect(
        cryptoShownUp(books.snapshot('up'), lastTrade: books.lastTrade('up')),
        0.44);
  });

  test('broken values never show', () {
    expect(cryptoOddsSane(double.nan), isFalse);
    expect(cryptoOddsSane(double.infinity), isFalse);
    expect(cryptoOddsSane(0), isFalse);
    expect(cryptoOddsSane(1), isFalse);
    expect(cryptoOddsSane(null), isFalse);
    expect(cryptoOddsSane(0.5), isTrue);
    expect(cryptoShownUp(null), isNull);
    // An empty book with no trade has nothing to show.
    book('up');
    expect(cryptoShownUp(books.snapshot('up')), isNull);
  });

  group('REST midpoints', () {
    test('one batched POST /midpoints for every token', () async {
      late http.Request seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response('{"a":"0.595","b":"0.405","c":"1"}', 200);
      });
      final mids =
          await fetchClobMidpoints(['a', 'b', 'c', 'a'], client: client);
      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'https://clob.polymarket.com/midpoints');
      expect(jsonDecode(seen.body), [
        {'token_id': 'a'},
        {'token_id': 'b'},
        {'token_id': 'c'},
      ]);
      // 1 is no live chance.
      expect(mids, {'a': 0.595, 'b': 0.405});
    });

    test('a refusal is an error, so the poller backs off', () async {
      final client = MockClient((_) async => http.Response('{}', 429));
      await expectLater(
          fetchClobMidpoints(['a'], client: client), throwsA(anything));
    });

    test('no tokens, no request', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      });
      expect(await fetchClobMidpoints(const [], client: client), isEmpty);
      expect(calls, 0);
    });

    test('a malformed answer parses to nothing', () {
      expect(parseClobMidpoints('nope'), isEmpty);
      expect(parseClobMidpoints('[1,2]'), isEmpty);
      expect(parseClobMidpoints('{"a":"NaN","b":"0.2"}'), {'b': 0.2});
    });
  });
}
