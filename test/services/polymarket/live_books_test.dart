// The market feed's latest book per token (PolymarketLiveBooks): the
// slip quotes and prices an order from it instead of asking the REST API,
// so what it hands out has to be the venue's book as it stands, current
// only while the feed is, and the increment the feed announces has to
// reach the saved market terms.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/market_terms_store.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';

void main() {
  late PolymarketLiveBooks books;
  var now = DateTime(2026, 10, 12, 12);

  setUp(() {
    PolymarketMarketTermsStore.resetForTest();
    books = PolymarketLiveBooks.instance..reset();
    books.clock = () => now;
    PolymarketMarketTermsStore.clock = () => now;
  });

  PolymarketBookMessage book(String asset,
          {List<(String, String)> asks = const [('0.40', '100')],
          List<(String, String)> bids = const [('0.30', '100')]}) =>
      PolymarketBookMessage.fromJson({
        'event_type': 'book',
        'asset_id': asset,
        'market': 'm',
        'asks': [for (final (p, s) in asks) {'price': p, 'size': s}],
        'bids': [for (final (p, s) in bids) {'price': p, 'size': s}],
        'hash': 'h',
      });

  test('a book frame is the snapshot; level changes keep it current', () {
    books.apply(book('t', asks: [('0.40', '100'), ('0.45', '50')]));
    var snap = books.snapshot('t')!;
    expect(snap.bestAsk, 0.40);
    expect(snap.bestBid, 0.30);

    // The 40¢ level is taken out, a new 38¢ ask appears.
    books.apply(polymarketWsMessagesOf(jsonEncode({
      'event_type': 'price_change',
      'asset_id': 't',
      'price_changes': [
        {'asset_id': 't', 'price': '0.40', 'size': '0', 'side': 'SELL'},
        {'asset_id': 't', 'price': '0.38', 'size': '20', 'side': 'SELL'},
      ],
    })).single);
    snap = books.snapshot('t')!;
    expect(snap.bestAsk, 0.38);
    final rest = snap.toOrderBook(tickSize: '0.01', negRisk: false);
    expect(rest.asks.map((l) => l.price), ['0.38', '0.45']);
    expect(rest.asks.first.size, '20.0');
    expect(rest.bids.single.price, '0.3');
    expect((rest.minTickSize, rest.negRisk, rest.assetId),
        ('0.01', false, 't'));
  });

  test('a snapshot with no feed activity for a while is not current', () {
    books.apply(book('t'));
    expect(books.isCurrent('t'), isTrue);
    now = now.add(const Duration(seconds: 4));
    expect(books.isCurrent('t'), isTrue);
    now = now.add(const Duration(seconds: 2));
    expect(books.isCurrent('t'), isFalse);
    expect(books.snapshot('t'), isNull);
    // The last book is still there for a fallback that wants it.
    expect(books.latest('t'), isNotNull);
    // A level change brings it back.
    books.apply(polymarketWsMessagesOf(jsonEncode({
      'event_type': 'price_change',
      'asset_id': 't',
      'price_changes': [
        {'price': '0.41', 'size': '5', 'side': 'SELL'},
      ],
    })).single);
    expect(books.isCurrent('t'), isTrue);
  });

  test('a level change for a token with no book is ignored', () {
    books.apply(polymarketWsMessagesOf(jsonEncode({
      'event_type': 'price_change',
      'asset_id': 'x',
      'price_changes': [
        {'price': '0.41', 'size': '5', 'side': 'SELL'},
      ],
    })).single);
    expect(books.latest('x'), isNull);
  });

  test('a tick-size change updates the saved increment for the token', () {
    PolymarketMarketTermsStore.save('t', negRisk: true, tickSize: '0.01');
    books.apply(polymarketWsMessagesOf(jsonEncode({
      'event_type': 'tick_size_change',
      'asset_id': 't',
      'market': 'm',
      'old_tick_size': '0.01',
      'new_tick_size': '0.001',
    })).single);
    final terms = PolymarketMarketTermsStore.read('t')!;
    expect(terms.tickSize, '0.001');
    expect(terms.negRisk, isTrue);
  });

  test('the saved increment counts as current while the feed is', () {
    PolymarketMarketTermsStore.save('t', tickSize: '0.01');
    books.apply(book('t'));
    expect(PolymarketMarketTermsStore.currentTickSize('t'), '0.01');
    // Well past the confirmation window, but the feed is still live.
    now = now.add(const Duration(minutes: 30));
    expect(PolymarketMarketTermsStore.currentTickSize('t'), isNull);
    books.apply(book('t'));
    expect(PolymarketMarketTermsStore.currentTickSize('t'), '0.01');
  });
}
