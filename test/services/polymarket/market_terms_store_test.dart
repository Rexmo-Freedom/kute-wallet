// The market facts an order is signed with, saved per token: neg-risk
// for good (it never changes), the price increment while it is confirmed
// or the feed would have announced a change. Memory only here (no Hive).
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/market_terms_store.dart';

void main() {
  var now = DateTime(2026, 10, 12, 12);
  setUp(() {
    PolymarketMarketTermsStore.resetForTest();
    PolymarketMarketTermsStore.clock = () => now;
  });

  test('a REST book saves both facts; neg-risk is never overwritten', () {
    PolymarketMarketTermsStore.saveFromBook(parsePolymarketOrderBook({
      'market': 'm',
      'asset_id': 't',
      'tick_size': '0.01',
      'neg_risk': true,
      'asks': [],
      'bids': [],
    }));
    expect(PolymarketMarketTermsStore.read('t')?.negRisk, isTrue);
    expect(PolymarketMarketTermsStore.currentTickSize('t'), '0.01');
    PolymarketMarketTermsStore.save('t', negRisk: false, tickSize: '0.001');
    expect(PolymarketMarketTermsStore.read('t')?.negRisk, isTrue);
    expect(PolymarketMarketTermsStore.read('t')?.tickSize, '0.001');
  });

  test('an increment is current for ten minutes without a feed', () {
    PolymarketMarketTermsStore.save('t', tickSize: '0.01');
    now = now.add(const Duration(minutes: 9));
    expect(PolymarketMarketTermsStore.currentTickSize('t'), '0.01');
    now = now.add(const Duration(minutes: 2));
    expect(PolymarketMarketTermsStore.currentTickSize('t'), isNull);
    expect(PolymarketMarketTermsStore.read('t')?.tickSize, '0.01',
        reason: 'still saved for the next confirmation');
  });

  test('a fine increment with a mid-band price is read again', () {
    PolymarketMarketTermsStore.save('t', tickSize: '0.001');
    expect(PolymarketMarketTermsStore.currentTickSize('t', referencePrice: 0.97),
        '0.001');
    expect(PolymarketMarketTermsStore.currentTickSize('t', referencePrice: 0.50),
        isNull);
    PolymarketMarketTermsStore.save('t', tickSize: '0.01');
    expect(PolymarketMarketTermsStore.currentTickSize('t', referencePrice: 0.50),
        '0.01');
  });

  test('an increment the venue does not quote is not saved', () {
    PolymarketMarketTermsStore.save('t', tickSize: '0.02');
    expect(PolymarketMarketTermsStore.read('t')?.tickSize, isNull);
    expect(PolymarketMarketTermsStore.currentTickSize('t'), isNull);
  });
}
