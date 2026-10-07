// The live feed's REST seed reads many books in a few batch requests.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/services/polymarket/book_seed.dart';

Map<String, Object?> _book(String token,
        {List<String> bids = const [], List<String> asks = const []}) =>
    {
      'asset_id': token,
      'bids': [
        for (final p in bids) {'price': p, 'size': '10'}
      ],
      'asks': [
        for (final p in asks) {'price': p, 'size': '10'}
      ],
    };

void main() {
  group('the midpoint of a book', () {
    test('best bid and best ask, wherever they sit', () {
      // Bids ascending (best last), asks ascending (best first).
      expect(
          clobBookMid(_book('a',
              bids: ['0.01', '0.40', '0.44'], asks: ['0.46', '0.60', '0.99'])),
          closeTo(0.45, 1e-9));
    });

    test('an empty side, an error or a mid at an end is none', () {
      expect(clobBookMid(_book('a', asks: ['0.5'])), isNull);
      expect(clobBookMid(_book('a', bids: ['0.5'])), isNull);
      expect(clobBookMid({'error': 'No orderbook exists'}), isNull);
      expect(clobBookMid(_book('a', bids: ['1.0'], asks: ['1.0'])), isNull);
    });
  });

  test(
      'a big game\'s tokens are read in batches of a hundred, not one '
      'request each', () async {
    final tokens = [for (var i = 0; i < 311; i++) 't$i'];
    final batches = <int>[];
    final client = MockClient((req) async {
      expect(req.method, 'POST');
      expect(req.url.toString(), 'https://clob.polymarket.com/books');
      final asked = [
        for (final e in jsonDecode(req.body) as List)
          (e as Map)['token_id'] as String
      ];
      batches.add(asked.length);
      return http.Response(
          jsonEncode([
            for (final t in asked)
              // Every tenth book is empty on one side.
              int.parse(t.substring(1)) % 10 == 0
                  ? _book(t, bids: ['0.30'])
                  : _book(t, bids: ['0.30'], asks: ['0.40'])
          ]),
          200);
    });
    final mids = await fetchClobBookMids(tokens, client: client);
    expect(batches, [100, 100, 100, 11]);
    expect(mids.length, 311 - 32);
    expect(mids['t1'], closeTo(0.35, 1e-9));
    expect(mids.containsKey('t0'), isFalse);
  });

  test('a book wider than 10¢ has no midpoint', () {
    // No bid and one ask at 74¢: Polymarket shows no 37% for it.
    expect(clobBookMid(_book('a', bids: ['0.06'], asks: ['0.78'])), isNull);
    expect(clobBookIsWide(_book('a', asks: ['0.74'])), isTrue);
    expect(clobBookIsWide(_book('a', bids: ['0.06'], asks: ['0.12'])), isFalse);
    expect(clobBookIsWide({'error': 'No orderbook exists'}), isFalse);
    final seeds = parseClobBookSeeds(jsonEncode([
      _book('w', asks: ['0.74']),
      _book('t', bids: ['0.06'], asks: ['0.12']),
    ]));
    expect(seeds.wide, {'w'});
    expect(seeds.mids.keys, ['t']);
  });

  test('the wide books\' last trades are read per token', () async {
    final asked = <String>[];
    final client = MockClient((req) async {
      asked.add(req.url.path);
      if (req.url.path == '/books') {
        return http.Response(
            jsonEncode([
              _book('w1', asks: ['0.75']),
              _book('w2', asks: ['0.74']),
              _book('t', bids: ['0.40'], asks: ['0.44']),
            ]),
            200);
      }
      expect(req.url.path, '/last-trades-prices');
      final tokens = [
        for (final e in jsonDecode(req.body) as List)
          (e as Map)['token_id'] as String
      ];
      expect(tokens.toSet(), {'w1', 'w2'});
      // w2 never traded.
      return http.Response(
          jsonEncode([
            {'token_id': 'w1', 'price': '0.01', 'side': 'SELL'},
            {'token_id': 'w2', 'price': '', 'side': ''},
          ]),
          200);
    });
    final seeds = await fetchClobBookSeeds(['w1', 'w2', 't'], client: client);
    expect(asked, ['/books', '/last-trades-prices']);
    expect(seeds.mids, {'t': closeTo(0.42, 1e-9)});
    expect(seeds.wide, {'w1', 'w2'});
    expect(seeds.lastTrades, {'w1': 0.01});
  });

  test('a failed batch leaves its tokens to the socket', () async {
    final client = MockClient((req) async => http.Response('nope', 500));
    expect(await fetchClobBookMids(['a', 'b'], client: client), isEmpty);
  });

  test('many prices in one copy read as the same prices written one by one',
      () {
    const start = LivePriceState(prices: {'a': 0.1, 'b': 0.2});
    final one = start.copyWithPrice('a', 0.3).copyWithPrice('c', 0.5);
    final many = start.copyWithPrices({'a': 0.3, 'c': 0.5});
    expect(many.prices, one.prices);
    expect(many.previousPrices, one.previousPrices);
    expect(many.live, isTrue);
    expect(many.updatedAtMs.keys.toSet(), {'a', 'c'});
    expect(identical(start.copyWithPrices(const {}), start), isTrue);
  });
}
