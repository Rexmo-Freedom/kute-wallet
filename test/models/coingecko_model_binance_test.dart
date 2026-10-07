import 'dart:convert';

import 'package:coingecko_api/coingecko_api.dart';
import 'package:coingecko_api/sections/coins_section.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/coingecko_model.dart';
import 'package:mocktail/mocktail.dart';

class _CoinGecko extends Mock implements CoinGeckoApi {}

class _Coins extends Mock implements CoinsSection {}

// The charts read Binance klines now; these pin the mapping and the
// USD-rate scaling for currencies Binance has no pair for.
void main() {
  List<dynamic> kline(int openMs, double close) => [openMs, '${close - 10}', '${close + 5}', '${close - 15}', '$close', '12.5', openMs + 86399999, '1000000', 10, '6', '500000', '0'];

  test('daily range points are keyed to their own day and scaled by the USD rate', () async {
    final urls = <String>[];
    final client = MockClient((req) async {
      urls.add(req.url.toString());
      if (req.url.path.contains('klines')) {
        return http.Response(jsonEncode([kline(DateTime.utc(2026, 9, 1).millisecondsSinceEpoch, 84000), kline(DateTime.utc(2026, 9, 2).millisecondsSinceEpoch, 85000)]), 200);
      }
      return http.Response('{}', 404);
    });
    final model = CoingeckoModel(client: client, usdRate: (c) async => c == 'CHF' ? 0.8 : null);
    final pts = await model.getBitcoinMarketDataRange('chf', DateTime.utc(2026, 8, 1), DateTime.utc(2026, 9, 29));
    expect(urls.single, contains('symbol=BTCUSDT'));
    expect(urls.single, contains('interval=1d'));
    expect(pts.length, 2);
    expect(pts.first.date.toUtc().day, 1);
    expect(pts.first.price, closeTo(84000 * 0.8, 0.01));
  });

  test('euro prices come straight from the BTCEUR pair', () async {
    String? url;
    final client = MockClient((req) async {
      url = req.url.toString();
      return http.Response(jsonEncode([kline(DateTime.utc(2026, 9, 29, 10).millisecondsSinceEpoch, 72000)]), 200);
    });
    final model = CoingeckoModel(client: client, usdRate: (_) async => null);
    final ohlc = await model.getBitcoinOHLC(currency: 'eur', days: 1);
    expect(url, contains('symbol=BTCEUR'));
    expect(url, contains('interval=30m'));
    expect(ohlc.single.close, 72000);
    expect(ohlc.single.high, 72005);
  });

  test('a failing Binance call never throws from the candle reader', () async {
    final client = MockClient((_) async => http.Response('nope', 500));
    // The CoinGecko fallback is down too; neither reaches the network.
    final coins = _Coins();
    when(() => coins.getCoinOHLC(id: 'bitcoin', vsCurrency: 'usd', days: 7))
        .thenThrow(Exception('rate limited'));
    final api = _CoinGecko();
    when(() => api.coins).thenReturn(coins);
    final model =
        CoingeckoModel(api: api, client: client, usdRate: (_) async => null);
    expect(await model.getBitcoinOHLC(currency: 'usd', days: 7), isEmpty);
    verify(() => coins.getCoinOHLC(id: 'bitcoin', vsCurrency: 'usd', days: 7))
        .called(1);
  });
}
