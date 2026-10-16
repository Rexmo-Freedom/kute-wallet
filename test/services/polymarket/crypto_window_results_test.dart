// The results strip under a crypto Up/Down card: how the last four
// windows ended, oldest first, read from Gamma in one request, the window
// that just ended settled on polymarket.com's own open and close before
// Gamma resolves it, and carried across a rollover while the new read is
// out.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/polymarket/crypto_window_results.dart';

Map<String, dynamic> _event(String slug,
        {double? finalPrice,
        double? priceToBeat,
        bool closed = false,
        List<String> prices = const ['0.5', '0.5']}) =>
    {
      'slug': slug,
      if (finalPrice != null || priceToBeat != null)
        'eventMetadata': {
          if (finalPrice != null) 'finalPrice': finalPrice,
          if (priceToBeat != null) 'priceToBeat': priceToBeat,
        },
      'markets': [
        {
          'closed': closed,
          'outcomes': jsonEncode(['Up', 'Down']),
          'outcomePrices': jsonEncode(prices),
        }
      ],
    };

void main() {
  setUp(debugForgetCryptoResults);

  group('one window', () {
    test('final price at or above the price to beat is Up', () {
      expect(
          cryptoOutcomeOfGammaEvent(
              _event('a', finalPrice: 100, priceToBeat: 100)),
          isTrue);
      expect(
          cryptoOutcomeOfGammaEvent(
              _event('a', finalPrice: 99.9, priceToBeat: 100)),
          isFalse);
    });

    test('a closed market without prices reads its outcome prices', () {
      expect(
          cryptoOutcomeOfGammaEvent(
              _event('a', closed: true, prices: ['0', '1'])),
          isFalse);
      expect(
          cryptoOutcomeOfGammaEvent(
              _event('a', closed: true, prices: ['1', '0'])),
          isTrue);
    });

    test('an open market, or one with only the price to beat, is pending', () {
      expect(cryptoOutcomeOfGammaEvent(_event('a', priceToBeat: 100)), isNull);
      expect(
          cryptoOutcomeOfGammaEvent(_event('a', prices: ['0.0005', '0.9995'])),
          isNull);
    });

    test('polymarket.com open and close count once complete', () {
      expect(
          parseCryptoPriceOutcome(jsonEncode(
              {'openPrice': 100, 'closePrice': 101, 'completed': true})),
          isTrue);
      expect(
          parseCryptoPriceOutcome(jsonEncode(
              {'openPrice': 100, 'closePrice': 99, 'completed': true})),
          isFalse);
      expect(
          parseCryptoPriceOutcome(jsonEncode(
              {'openPrice': 100, 'closePrice': 99, 'completed': false})),
          isNull);
      expect(parseCryptoPriceOutcome('oops'), isNull);
    });
  });

  test('the last four windows in one Gamma read, oldest first', () async {
    const start = 1791808800;
    final asked = <Uri>[];
    final client = MockClient((req) async {
      asked.add(req.url);
      if (req.url.host == 'gamma-api.polymarket.com') {
        return http.Response(
            jsonEncode({
              'events': [
                _event('btc-updown-5m-${start - 300}', priceToBeat: 2),
                _event('btc-updown-5m-${start - 600}',
                    finalPrice: 2, priceToBeat: 3),
                _event('btc-updown-5m-${start - 900}',
                    finalPrice: 3, priceToBeat: 1),
                _event('btc-updown-5m-${start - 1200}',
                    finalPrice: 1, priceToBeat: 1),
              ]
            }),
            200);
      }
      // The window that just ended, before Gamma resolves it.
      expect(req.url.host, 'polymarket.com');
      expect(req.url.queryParameters['eventStartTime'], '2026-10-12T12:35:00Z');
      return http.Response(
          jsonEncode({'openPrice': 2, 'closePrice': 1.5, 'completed': true}),
          200);
    });
    final results = await fetchCryptoRecentResults(
        asset: 'BTC', minutes: 5, currentStart: start, client: client);
    expect(asked.first.path, '/events/keyset');
    expect(asked.first.queryParametersAll['slug'], [
      for (var k = 4; k >= 1; k--) 'btc-updown-5m-${start - k * 300}',
    ]);
    expect(results, [
      const CryptoWindowResult(start - 1200, true),
      const CryptoWindowResult(start - 900, true),
      const CryptoWindowResult(start - 600, false),
      const CryptoWindowResult(start - 300, false),
    ]);
  });

  test('a failed read leaves every window pending, never throws', () async {
    final client = MockClient((_) async => http.Response('nope', 500));
    final results = await fetchCryptoRecentResults(
        asset: 'ETH', minutes: 5, currentStart: 3000, client: client);
    expect(results.map((r) => r.up), [null, null, null, null]);
    expect(results.map((r) => r.startEpoch), [1800, 2100, 2400, 2700]);
  });

  test('a rollover carries the marks along while the new read is out', () {
    rememberCryptoResults('BTC', 5, const [
      CryptoWindowResult(1800, true),
      CryptoWindowResult(2100, false),
      CryptoWindowResult(2400, true),
      CryptoWindowResult(2700, false),
    ]);
    expect(carriedCryptoResults('BTC', 5, 3300), const [
      CryptoWindowResult(2100, false),
      CryptoWindowResult(2400, true),
      CryptoWindowResult(2700, false),
      CryptoWindowResult(3000, null), // just ended, settling
    ]);
    expect(carriedCryptoResults('ETH', 5, 3300), isEmpty);
  });
}
