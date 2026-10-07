import 'dart:convert';

import 'package:coingecko_api/coingecko_api.dart';
import 'package:coingecko_api/coingecko_result.dart';
import 'package:coingecko_api/data/market_chart_data.dart';
import 'package:coingecko_api/data/ohlc_info.dart';
import 'package:coingecko_api/sections/coins_section.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/coingecko_model.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------
class MockCoinGeckoApi extends Mock implements CoinGeckoApi {}

class MockCoinsSection extends Mock implements CoinsSection {}

// ---------------------------------------------------------------------------
// Helpers — lightweight wrappers around CoinGeckoResult
// ---------------------------------------------------------------------------

/// Wraps [data] in a successful CoinGeckoResult (isError == false).
CoinGeckoResult<List<MarketChartData>> _successMarketChart(
    List<MarketChartData> data) {
  return CoinGeckoResult(data);
}

/// Returns a CoinGeckoResult whose [isError] is true.
CoinGeckoResult<List<MarketChartData>> _errorMarketChart() {
  return CoinGeckoResult(
    <MarketChartData>[],
    errorCode: 429,
    errorMessage: 'Rate limited',
  );
}

/// Wraps [data] in a successful CoinGeckoResult for OHLC.
CoinGeckoResult<List<OHLCInfo>> _successOHLC(List<OHLCInfo> data) {
  return CoinGeckoResult(data);
}

/// Returns a CoinGeckoResult whose [isError] is true for OHLC.
CoinGeckoResult<List<OHLCInfo>> _errorOHLC() {
  return CoinGeckoResult(
    <OHLCInfo>[],
    errorCode: 500,
    errorMessage: 'Server error',
  );
}

/// Creates a single [MarketChartData] point.
MarketChartData _marketPoint(DateTime date, double price) {
  return MarketChartData(date, price: price);
}

// ---------------------------------------------------------------------------
// Binance — the primary source since the model moved off CoinGecko. Every
// test talks to this fake instead of the network. [respond] maps a request
// to a JSON body; null (the default) answers 500, as an unreachable Binance
// would, which sends the model down its CoinGecko fallback.
// ---------------------------------------------------------------------------
class _Binance {
  Object? Function(Uri url)? respond;
  final requests = <Uri>[];

  late final http.Client client = MockClient((request) async {
    requests.add(request.url);
    final body = respond?.call(request.url);
    return body == null
        ? http.Response('unavailable', 500)
        : http.Response(jsonEncode(body), 200);
  });

  Uri get last => requests.last;
}

/// One Binance kline: [openTime, open, high, low, close, volume, closeTime,
/// quoteVolume, trades, …], prices as strings as Binance sends them.
List<Object> _kline(int openMs, double close, {int? closeMs}) => [
      openMs,
      '${close - 10}',
      '${close + 5}',
      '${close - 15}',
      '$close',
      '12.5',
      closeMs ?? openMs + 299999,
      '1000000',
      10,
      '6',
      '500000',
      '0',
    ];

void main() {
  late MockCoinGeckoApi mockApi;
  late MockCoinsSection mockCoins;
  late _Binance binance;
  late Map<String, double> usdRates;
  late CoingeckoModel model;

  setUpAll(() => registerFallbackValue(DateTime(2025)));

  setUp(() {
    mockApi = MockCoinGeckoApi();
    mockCoins = MockCoinsSection();
    when(() => mockApi.coins).thenReturn(mockCoins);
    binance = _Binance();
    usdRates = {};
    model = CoingeckoModel(
        api: mockApi,
        client: binance.client,
        usdRate: (currency) async => usdRates[currency]);
  });

  void verifyNoCoinGecko() {
    verifyNever(() => mockCoins.getCoinMarketChart(
        id: any(named: 'id'),
        vsCurrency: any(named: 'vsCurrency'),
        days: any(named: 'days')));
    verifyNever(() => mockCoins.getCoinOHLC(
        id: any(named: 'id'),
        vsCurrency: any(named: 'vsCurrency'),
        days: any(named: 'days')));
    verifyNever(() => mockCoins.getCoinMarketChartRanged(
        id: any(named: 'id'),
        vsCurrency: any(named: 'vsCurrency'),
        from: any(named: 'from'),
        to: any(named: 'to')));
  }

  // ─────────────────────────────────────────────
  // Binance pairs
  // ─────────────────────────────────────────────
  group('Binance pairs', () {
    test('currencies Binance quotes read their own BTC pair', () async {
      binance.respond = (url) =>
          {'symbol': url.queryParameters['symbol'], 'price': '64000.50000000'};
      for (final (currency, symbol) in [
        ('usd', 'BTCUSDT'),
        ('EUR', 'BTCEUR'),
        ('gbp', 'BTCGBP'),
        ('brl', 'BTCBRL'),
        ('jpy', 'BTCJPY'),
      ]) {
        expect(await model.getBitcoinPrice(currency: currency), 64000.5,
            reason: currency);
        expect(binance.last.path, '/api/v3/ticker/price');
        expect(binance.last.queryParameters['symbol'], symbol,
            reason: currency);
      }
      verifyNoCoinGecko();
    });

    test('other currencies scale BTCUSDT by the stored USD rate', () async {
      usdRates['CHF'] = 0.8;
      binance.respond = (_) => {'symbol': 'BTCUSDT', 'price': '100000'};
      expect(
          await model.getBitcoinPrice(currency: 'chf'), closeTo(80000, 1e-6));
      expect(binance.last.queryParameters['symbol'], 'BTCUSDT');
      verifyNoCoinGecko();
    });

    test('without a stored rate CoinGecko prices it, never as dollars',
        () async {
      binance.respond = (_) => {'symbol': 'BTCUSDT', 'price': '100000'};
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'sek',
            days: 1,
          )).thenAnswer((_) async => _successMarketChart([
            _marketPoint(DateTime.now(), 1050000.0),
          ]));

      expect(await model.getBitcoinPrice(currency: 'SEK'), 1050000.0);
      expect(binance.requests, isEmpty);
    });
  });

  // ─────────────────────────────────────────────
  // MarketData (simple data class)
  // ─────────────────────────────────────────────
  group('MarketData', () {
    test('stores days and currency', () {
      final md = MarketData(days: 7, currency: 'usd');
      expect(md.days, 7);
      expect(md.currency, 'usd');
    });

    test('stores uppercase currency as-is', () {
      final md = MarketData(days: 30, currency: 'EUR');
      expect(md.currency, 'EUR');
    });

    test('supports zero days', () {
      final md = MarketData(days: 0, currency: 'gbp');
      expect(md.days, 0);
    });

    test('supports large day values', () {
      final md = MarketData(days: 365, currency: 'brl');
      expect(md.days, 365);
    });
  });

  // ─────────────────────────────────────────────
  // CoingeckoModel constructor
  // ─────────────────────────────────────────────
  group('CoingeckoModel constructor', () {
    test('creates default api when none provided', () {
      final defaultModel = CoingeckoModel();
      expect(defaultModel.api, isNotNull);
      expect(defaultModel.api, isA<CoinGeckoApi>());
    });

    test('uses injected api when provided', () {
      expect(model.api, same(mockApi));
    });
  });

  // ─────────────────────────────────────────────
  // getBitcoinPrice
  // ─────────────────────────────────────────────
  group('getBitcoinPrice', () {
    test('reads the Binance ticker without asking CoinGecko', () async {
      binance.respond = (_) => {'symbol': 'BTCUSDT', 'price': '67500.50000000'};
      expect(await model.getBitcoinPrice(), 67500.5);
      expect(binance.last.path, '/api/v3/ticker/price');
      verifyNoCoinGecko();
    });

    test('returns 0.0 when Binance and CoinGecko both fail', () async {
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 1,
          )).thenThrow(Exception('Network error'));
      expect(await model.getBitcoinPrice(), 0.0);
      expect(binance.requests, hasLength(1));
    });

    // Every test below runs with Binance unreachable: CoinGecko answers.
    test('falls back to the last CoinGecko market chart price', () async {
      final now = DateTime.now();
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 1,
          )).thenAnswer((_) async => _successMarketChart([
            _marketPoint(now.subtract(const Duration(hours: 1)), 65000.0),
            _marketPoint(now, 67500.50),
          ]));

      final price = await model.getBitcoinPrice();
      expect(price, 67500.50);
    });

    test('defaults to usd currency', () async {
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 1,
          )).thenAnswer((_) async => _successMarketChart([
            _marketPoint(DateTime.now(), 60000.0),
          ]));

      await model.getBitcoinPrice();

      verify(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 1,
          )).called(1);
    });

    test('converts currency parameter to lowercase', () async {
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'eur',
            days: 1,
          )).thenAnswer((_) async => _successMarketChart([
            _marketPoint(DateTime.now(), 58000.0),
          ]));

      final price = await model.getBitcoinPrice(currency: 'EUR');
      expect(price, 58000.0);
    });

    test('returns 0.0 when API returns error', () async {
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 1,
          )).thenAnswer((_) async => _errorMarketChart());

      final price = await model.getBitcoinPrice();
      expect(price, 0.0);
    });

    test('returns 0.0 when data is empty', () async {
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 1,
          )).thenAnswer((_) async => _successMarketChart([]));

      final price = await model.getBitcoinPrice();
      expect(price, 0.0);
    });

    test('returns 0.0 when API throws exception', () async {
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 1,
          )).thenThrow(Exception('Network error'));

      final price = await model.getBitcoinPrice();
      expect(price, 0.0);
    });

    test('returns single data point price', () async {
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 1,
          )).thenAnswer((_) async => _successMarketChart([
            _marketPoint(DateTime.now(), 42000.0),
          ]));

      final price = await model.getBitcoinPrice();
      expect(price, 42000.0);
    });

    test('returns last price from many data points', () async {
      final now = DateTime.now();
      final points = List.generate(
        24,
        (i) => _marketPoint(
            now.subtract(Duration(hours: 24 - i)), 60000.0 + i * 100),
      );
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 1,
          )).thenAnswer((_) async => _successMarketChart(points));

      final price = await model.getBitcoinPrice();
      expect(price, 60000.0 + 23 * 100); // last point
    });

    test('supports multiple currencies', () async {
      for (final currency in ['eur', 'gbp', 'brl', 'chf', 'sek']) {
        when(() => mockCoins.getCoinMarketChart(
              id: 'bitcoin',
              vsCurrency: currency,
              days: 1,
            )).thenAnswer((_) async => _successMarketChart([
              _marketPoint(DateTime.now(), 50000.0),
            ]));

        final price = await model.getBitcoinPrice(currency: currency);
        expect(price, 50000.0, reason: 'Failed for $currency');
      }
    });

    test('handles zero price', () async {
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 1,
          )).thenAnswer((_) async => _successMarketChart([
            _marketPoint(DateTime.now(), 0.0),
          ]));

      final price = await model.getBitcoinPrice();
      expect(price, 0.0);
    });

    test('handles very large price', () async {
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 1,
          )).thenAnswer((_) async => _successMarketChart([
            _marketPoint(DateTime.now(), 1000000.99),
          ]));

      final price = await model.getBitcoinPrice();
      expect(price, closeTo(1000000.99, 0.01));
    });

    test('handles fractional price', () async {
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 1,
          )).thenAnswer((_) async => _successMarketChart([
            _marketPoint(DateTime.now(), 0.00001234),
          ]));

      final price = await model.getBitcoinPrice();
      expect(price, closeTo(0.00001234, 0.000001));
    });
  });

  // ─────────────────────────────────────────────
  // getBitcoinChangePercentage
  //
  // Binance's 24 hour ticker answers this directly. The CoinGecko 7-day
  // chart computation it replaced is gone, and a failure is 0.0 rather
  // than a CoinGecko call.
  // ─────────────────────────────────────────────
  group('getBitcoinChangePercentage', () {
    test('reads a positive change from the 24 hour ticker', () async {
      binance.respond =
          (_) => {'symbol': 'BTCUSDT', 'priceChangePercent': '3.809'};
      expect(await model.getBitcoinChangePercentage('usd'), 3.809);
      expect(binance.last.path, '/api/v3/ticker/24hr');
      expect(binance.last.queryParameters['symbol'], 'BTCUSDT');
    });

    test('reads a negative change', () async {
      binance.respond =
          (_) => {'symbol': 'BTCUSDT', 'priceChangePercent': '-3.478'};
      expect(await model.getBitcoinChangePercentage('usd'), -3.478);
    });

    test('uses the currency\'s own pair when Binance quotes one', () async {
      binance.respond =
          (_) => {'symbol': 'BTCEUR', 'priceChangePercent': '0.000'};
      expect(await model.getBitcoinChangePercentage('EUR'), 0.0);
      expect(binance.last.queryParameters['symbol'], 'BTCEUR');
    });

    test('a currency without a pair uses BTCUSDT and needs no rate', () async {
      binance.respond =
          (_) => {'symbol': 'BTCUSDT', 'priceChangePercent': '1.5'};
      expect(await model.getBitcoinChangePercentage('sek'), 1.5);
      expect(binance.last.queryParameters['symbol'], 'BTCUSDT');
    });

    test('returns 0.0 when Binance fails, without asking CoinGecko', () async {
      expect(await model.getBitcoinChangePercentage('usd'), 0.0);
      verifyNoCoinGecko();
    });
  });

  // ─────────────────────────────────────────────
  // getBitcoinMarketData
  // ─────────────────────────────────────────────
  group('getBitcoinMarketData', () {
    test('maps klines to close time, close price and quote volume', () async {
      final open = DateTime.utc(2026, 9, 29, 10);
      final close = open.add(const Duration(hours: 1));
      binance.respond = (_) => [
            _kline(open.millisecondsSinceEpoch, 64000,
                closeMs: close.millisecondsSinceEpoch),
          ];
      final result = await model
          .getBitcoinMarketData(MarketData(days: 7, currency: 'usd'));
      expect(result.single.date.toUtc(), close);
      expect(result.single.price, 64000);
      expect(result.single.totalVolume, 1000000);
      verifyNoCoinGecko();
    });

    test('picks an interval and point count the chart can draw', () async {
      binance.respond = (_) => [_kline(0, 64000)];
      for (final (days, interval, limit) in [
        (1, '5m', 289),
        (7, '1h', 169),
        (30, '4h', 181),
        (365, '1d', 366),
      ]) {
        await model
            .getBitcoinMarketData(MarketData(days: days, currency: 'usd'));
        expect(binance.last.path, '/api/v3/klines');
        expect(binance.last.queryParameters['interval'], interval,
            reason: '$days days');
        expect(binance.last.queryParameters['limit'], '$limit',
            reason: '$days days');
      }
    });

    test('scales a pairless currency by the stored USD rate', () async {
      usdRates['CHF'] = 0.8;
      binance.respond = (_) => [_kline(0, 50000)];
      final result = await model
          .getBitcoinMarketData(MarketData(days: 7, currency: 'chf'));
      expect(binance.last.queryParameters['symbol'], 'BTCUSDT');
      expect(result.single.price, closeTo(40000, 1e-6));
      expect(result.single.totalVolume, closeTo(800000, 1e-6));
    });

    // Every test below runs with Binance unreachable: CoinGecko answers.
    test('falls back to the CoinGecko market chart', () async {
      final now = DateTime.now();
      final expectedData = [
        _marketPoint(now.subtract(const Duration(days: 1)), 60000.0),
        _marketPoint(now, 61000.0),
      ];
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 7,
          )).thenAnswer((_) async => _successMarketChart(expectedData));

      final result = await model
          .getBitcoinMarketData(MarketData(days: 7, currency: 'usd'));
      expect(result.length, 2);
    });

    test('converts currency to lowercase', () async {
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'gbp',
            days: 30,
          )).thenAnswer((_) async => _successMarketChart([]));

      await model.getBitcoinMarketData(MarketData(days: 30, currency: 'GBP'));

      verify(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'gbp',
            days: 30,
          )).called(1);
    });

    test('passes correct days parameter', () async {
      for (final days in [1, 7, 30, 90, 365]) {
        when(() => mockCoins.getCoinMarketChart(
              id: 'bitcoin',
              vsCurrency: 'usd',
              days: days,
            )).thenAnswer((_) async => _successMarketChart([]));

        await model
            .getBitcoinMarketData(MarketData(days: days, currency: 'usd'));

        verify(() => mockCoins.getCoinMarketChart(
              id: 'bitcoin',
              vsCurrency: 'usd',
              days: days,
            )).called(1);
      }
    });

    test('throws exception on API failure', () async {
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 7,
          )).thenThrow(Exception('Network timeout'));

      await expectLater(
        () => model.getBitcoinMarketData(MarketData(days: 7, currency: 'usd')),
        throwsA(isA<Exception>()),
      );
    });

    test('returns empty list when API returns empty data', () async {
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 7,
          )).thenAnswer((_) async => _successMarketChart([]));

      final result = await model
          .getBitcoinMarketData(MarketData(days: 7, currency: 'usd'));
      expect(result, isEmpty);
    });

    test('returns large dataset correctly', () async {
      final now = DateTime.now();
      final largeData = List.generate(
        365,
        (i) => _marketPoint(
            now.subtract(Duration(days: 365 - i)), 50000.0 + i * 10),
      );
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 365,
          )).thenAnswer((_) async => _successMarketChart(largeData));

      final result = await model
          .getBitcoinMarketData(MarketData(days: 365, currency: 'usd'));
      expect(result.length, 365);
    });
  });

  // ─────────────────────────────────────────────
  // getBitcoinOHLC
  // ─────────────────────────────────────────────
  group('getBitcoinOHLC', () {
    test('maps klines to open time and scaled OHLC', () async {
      usdRates['CHF'] = 0.5;
      final open = DateTime.utc(2026, 9, 29, 8).millisecondsSinceEpoch;
      binance.respond = (_) => [_kline(open, 60000)];
      final result = await model.getBitcoinOHLC(currency: 'chf', days: 7);
      final candle = result.single;
      expect(candle.timestamp.millisecondsSinceEpoch, open);
      expect(candle.open, closeTo(29995, 1e-6));
      expect(candle.high, closeTo(30002.5, 1e-6));
      expect(candle.low, closeTo(29992.5, 1e-6));
      expect(candle.close, closeTo(30000, 1e-6));
      verifyNoCoinGecko();
    });

    test('30 minute candles up to two days, 4 hour to a month, then daily',
        () async {
      binance.respond = (_) => [_kline(0, 60000)];
      for (final (days, interval, limit) in [
        (1, '30m', 49),
        (2, '30m', 97),
        (7, '4h', 43),
        (30, '4h', 181),
        (90, '1d', 91),
      ]) {
        await model.getBitcoinOHLC(days: days);
        expect(binance.last.queryParameters['interval'], interval,
            reason: '$days days');
        expect(binance.last.queryParameters['limit'], '$limit',
            reason: '$days days');
      }
    });

    // Every test below runs with Binance unreachable: CoinGecko answers.
    test('falls back to CoinGecko OHLC data', () async {
      final ohlcData = [
        OHLCInfo.fromArray([
          DateTime.now().millisecondsSinceEpoch,
          60000.0,
          61000.0,
          59000.0,
          60500.0,
        ]),
      ];
      when(() => mockCoins.getCoinOHLC(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 30,
          )).thenAnswer((_) async => _successOHLC(ohlcData));

      final result = await model.getBitcoinOHLC();
      expect(result.length, 1);
      expect(result.first.open, 60000.0);
      expect(result.first.high, 61000.0);
      expect(result.first.low, 59000.0);
      expect(result.first.close, 60500.0);
    });

    test('defaults to usd currency and 30 days', () async {
      when(() => mockCoins.getCoinOHLC(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 30,
          )).thenAnswer((_) async => _successOHLC([]));

      await model.getBitcoinOHLC();

      verify(() => mockCoins.getCoinOHLC(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 30,
          )).called(1);
    });

    test('uses custom currency and days', () async {
      when(() => mockCoins.getCoinOHLC(
            id: 'bitcoin',
            vsCurrency: 'eur',
            days: 365,
          )).thenAnswer((_) async => _successOHLC([]));

      await model.getBitcoinOHLC(currency: 'EUR', days: 365);

      verify(() => mockCoins.getCoinOHLC(
            id: 'bitcoin',
            vsCurrency: 'eur',
            days: 365,
          )).called(1);
    });

    test('returns empty list on API error', () async {
      when(() => mockCoins.getCoinOHLC(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 30,
          )).thenAnswer((_) async => _errorOHLC());

      final result = await model.getBitcoinOHLC();
      expect(result, isEmpty);
    });

    test('returns empty list on exception', () async {
      when(() => mockCoins.getCoinOHLC(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 30,
          )).thenThrow(Exception('Connection refused'));

      final result = await model.getBitcoinOHLC();
      expect(result, isEmpty);
    });

    test('converts currency to lowercase', () async {
      when(() => mockCoins.getCoinOHLC(
            id: 'bitcoin',
            vsCurrency: 'brl',
            days: 7,
          )).thenAnswer((_) async => _successOHLC([]));

      await model.getBitcoinOHLC(currency: 'BRL', days: 7);

      verify(() => mockCoins.getCoinOHLC(
            id: 'bitcoin',
            vsCurrency: 'brl',
            days: 7,
          )).called(1);
    });

    test('returns multiple OHLC entries', () async {
      final now = DateTime.now();
      final ohlcData = List.generate(
        30,
        (i) => OHLCInfo.fromArray([
          now.subtract(Duration(days: 30 - i)).millisecondsSinceEpoch,
          60000.0 + i * 100,
          61000.0 + i * 100,
          59000.0 + i * 100,
          60500.0 + i * 100,
        ]),
      );
      when(() => mockCoins.getCoinOHLC(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 30,
          )).thenAnswer((_) async => _successOHLC(ohlcData));

      final result = await model.getBitcoinOHLC();
      expect(result.length, 30);
    });
  });

  // ─────────────────────────────────────────────
  // getBitcoinMarketDataRange
  // ─────────────────────────────────────────────
  group('getBitcoinMarketDataRange', () {
    test('the interval follows the span and the range is sent', () async {
      binance.respond = (_) => [_kline(0, 60000)];
      final from = DateTime.utc(2026, 1, 1);
      for (final (span, interval) in [
        (const Duration(hours: 12), '5m'),
        (const Duration(days: 3), '1h'),
        (const Duration(days: 30), '4h'),
        (const Duration(days: 90), '1d'),
      ]) {
        final to = from.add(span);
        await model.getBitcoinMarketDataRange('usd', from, to);
        expect(binance.last.queryParameters['interval'], interval,
            reason: '$span');
        expect(binance.last.queryParameters['startTime'],
            '${from.millisecondsSinceEpoch}');
        expect(binance.last.queryParameters['endTime'],
            '${to.millisecondsSinceEpoch}');
      }
      verifyNoCoinGecko();
    });

    test('daily points are keyed to their own day, finer ones to their close',
        () async {
      final day = DateTime.utc(2026, 9, 1);
      final dayClose = day
          .add(const Duration(days: 1))
          .subtract(const Duration(milliseconds: 1));
      binance.respond = (_) => [
            _kline(day.millisecondsSinceEpoch, 84000,
                closeMs: dayClose.millisecondsSinceEpoch),
          ];
      final daily = await model.getBitcoinMarketDataRange(
          'usd', DateTime.utc(2026, 6, 1), DateTime.utc(2026, 9, 29));
      expect(daily.single.date.toUtc(), day);

      final hourly = await model.getBitcoinMarketDataRange(
          'usd', DateTime.utc(2026, 8, 29), DateTime.utc(2026, 9, 1));
      expect(hourly.single.date.toUtc(), dayClose);
    });

    test('pages through a span longer than one response', () async {
      final from = DateTime.utc(2020, 1, 1);
      final to = DateTime.utc(2026, 1, 1);
      const day = Duration(days: 1);
      binance.respond = (url) {
        final start = int.parse(url.queryParameters['startTime']!);
        final count = start == from.millisecondsSinceEpoch ? 1000 : 3;
        return [
          for (var i = 0; i < count; i++)
            _kline(start + i * day.inMilliseconds, 50000.0 + i),
        ];
      };
      final result = await model.getBitcoinMarketDataRange('usd', from, to);
      expect(result, hasLength(1003));
      expect(binance.requests, hasLength(2));
      expect(binance.requests.last.queryParameters['startTime'],
          '${from.add(day * 1000).millisecondsSinceEpoch}');
    });

    test('an empty Binance answer falls back to CoinGecko', () async {
      binance.respond = (_) => <Object>[];
      final from = DateTime(2025, 1, 1);
      final to = DateTime(2025, 1, 31);
      when(() => mockCoins.getCoinMarketChartRanged(
            id: 'bitcoin',
            vsCurrency: 'usd',
            from: from,
            to: to,
          )).thenAnswer((_) async => _successMarketChart([
            _marketPoint(from, 60000.0),
          ]));
      final result = await model.getBitcoinMarketDataRange('usd', from, to);
      expect(result.single.price, 60000.0);
    });

    // Every test below runs with Binance unreachable: CoinGecko answers.
    test('falls back to CoinGecko ranged market data', () async {
      final from = DateTime(2025, 1, 1);
      final to = DateTime(2025, 1, 31);
      final expectedData = [
        _marketPoint(from, 60000.0),
        _marketPoint(to, 65000.0),
      ];
      when(() => mockCoins.getCoinMarketChartRanged(
            id: 'bitcoin',
            vsCurrency: 'usd',
            from: from,
            to: to,
          )).thenAnswer((_) async => _successMarketChart(expectedData));

      final result = await model.getBitcoinMarketDataRange('usd', from, to);
      expect(result.length, 2);
    });

    test('converts currency to lowercase', () async {
      final from = DateTime(2025, 1, 1);
      final to = DateTime(2025, 6, 1);
      when(() => mockCoins.getCoinMarketChartRanged(
            id: 'bitcoin',
            vsCurrency: 'chf',
            from: from,
            to: to,
          )).thenAnswer((_) async => _successMarketChart([]));

      await model.getBitcoinMarketDataRange('CHF', from, to);

      verify(() => mockCoins.getCoinMarketChartRanged(
            id: 'bitcoin',
            vsCurrency: 'chf',
            from: from,
            to: to,
          )).called(1);
    });

    test('throws exception on API failure', () async {
      final from = DateTime(2025, 1, 1);
      final to = DateTime(2025, 1, 31);
      when(() => mockCoins.getCoinMarketChartRanged(
            id: 'bitcoin',
            vsCurrency: 'usd',
            from: from,
            to: to,
          )).thenThrow(Exception('Server error'));

      await expectLater(
        () => model.getBitcoinMarketDataRange('usd', from, to),
        throwsA(isA<Exception>()),
      );
    });

    test('returns empty list for range with no data', () async {
      final from = DateTime(2009, 1, 1);
      final to = DateTime(2009, 1, 2);
      when(() => mockCoins.getCoinMarketChartRanged(
            id: 'bitcoin',
            vsCurrency: 'usd',
            from: from,
            to: to,
          )).thenAnswer((_) async => _successMarketChart([]));

      final result = await model.getBitcoinMarketDataRange('usd', from, to);
      expect(result, isEmpty);
    });

    test('handles same from and to date', () async {
      final date = DateTime(2025, 6, 15);
      when(() => mockCoins.getCoinMarketChartRanged(
            id: 'bitcoin',
            vsCurrency: 'usd',
            from: date,
            to: date,
          )).thenAnswer((_) async => _successMarketChart([
            _marketPoint(date, 70000.0),
          ]));

      final result = await model.getBitcoinMarketDataRange('usd', date, date);
      expect(result.length, 1);
    });

    test('supports multiple currencies', () async {
      final from = DateTime(2025, 1, 1);
      final to = DateTime(2025, 3, 1);
      for (final currency in ['eur', 'gbp', 'brl', 'sek', 'nok']) {
        when(() => mockCoins.getCoinMarketChartRanged(
              id: 'bitcoin',
              vsCurrency: currency,
              from: from,
              to: to,
            )).thenAnswer((_) async => _successMarketChart([
              _marketPoint(from, 50000.0),
            ]));

        final result =
            await model.getBitcoinMarketDataRange(currency, from, to);
        expect(result.length, 1, reason: 'Failed for $currency');
      }
    });
  });

  // ─────────────────────────────────────────────
  // Error states and edge cases
  // ─────────────────────────────────────────────
  // The groups below all run with Binance unreachable, so they pin the
  // CoinGecko fallback path.
  group('error states', () {
    test('getBitcoinPrice catches all exception types', () async {
      // FormatException
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 1,
          )).thenThrow(const FormatException('bad format'));

      expect(await model.getBitcoinPrice(), 0.0);
    });

    test('getBitcoinPrice handles TypeError', () async {
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 1,
          )).thenThrow(TypeError());

      expect(await model.getBitcoinPrice(), 0.0);
    });

    test('getBitcoinOHLC catches all exception types', () async {
      when(() => mockCoins.getCoinOHLC(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 30,
          )).thenThrow(const FormatException('bad json'));

      final result = await model.getBitcoinOHLC();
      expect(result, isEmpty);
    });

    test('getBitcoinMarketData wraps exception message', () async {
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 7,
          )).thenThrow(Exception('timeout'));

      await expectLater(
        () => model.getBitcoinMarketData(MarketData(days: 7, currency: 'usd')),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Failed to fetch market data'),
          ),
        ),
      );
    });

    test('getBitcoinMarketDataRange wraps exception message', () async {
      final from = DateTime(2025, 1, 1);
      final to = DateTime(2025, 1, 31);
      when(() => mockCoins.getCoinMarketChartRanged(
            id: 'bitcoin',
            vsCurrency: 'usd',
            from: from,
            to: to,
          )).thenThrow(Exception('rate limited'));

      await expectLater(
        () => model.getBitcoinMarketDataRange('usd', from, to),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Failed to fetch market data'),
          ),
        ),
      );
    });
  });

  // ─────────────────────────────────────────────
  // Multiple currency support
  // ─────────────────────────────────────────────
  group('multiple currency support', () {
    test('getBitcoinPrice works with all common fiat currencies', () async {
      final currencies = [
        'usd',
        'eur',
        'gbp',
        'chf',
        'brl',
        'sek',
        'nok',
        'dkk',
        'pln',
        'czk',
        'huf',
        'ron',
      ];
      for (final currency in currencies) {
        when(() => mockCoins.getCoinMarketChart(
              id: 'bitcoin',
              vsCurrency: currency,
              days: 1,
            )).thenAnswer((_) async => _successMarketChart([
              _marketPoint(DateTime.now(), 50000.0),
            ]));

        final price = await model.getBitcoinPrice(currency: currency);
        expect(price, 50000.0, reason: 'Failed for $currency');
      }
    });

    test('case insensitive currency handling across methods', () async {
      // getBitcoinPrice
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 1,
          )).thenAnswer((_) async => _successMarketChart([
            _marketPoint(DateTime.now(), 50000.0),
          ]));
      await model.getBitcoinPrice(currency: 'USD');
      verify(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 1,
          )).called(1);

      // getBitcoinOHLC
      when(() => mockCoins.getCoinOHLC(
            id: 'bitcoin',
            vsCurrency: 'gbp',
            days: 30,
          )).thenAnswer((_) async => _successOHLC([]));
      await model.getBitcoinOHLC(currency: 'GBP');
      verify(() => mockCoins.getCoinOHLC(
            id: 'bitcoin',
            vsCurrency: 'gbp',
            days: 30,
          )).called(1);
    });
  });

  // ─────────────────────────────────────────────
  // Price parsing edge cases
  // ─────────────────────────────────────────────
  group('price parsing edge cases', () {
    test('handles negative price gracefully', () async {
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 1,
          )).thenAnswer((_) async => _successMarketChart([
            _marketPoint(DateTime.now(), -100.0),
          ]));

      final price = await model.getBitcoinPrice();
      expect(price, -100.0);
    });

    test('handles extremely small price', () async {
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 1,
          )).thenAnswer((_) async => _successMarketChart([
            _marketPoint(DateTime.now(), 0.000000001),
          ]));

      final price = await model.getBitcoinPrice();
      expect(price, closeTo(0.000000001, 0.0000000001));
    });

    test('handles extremely large price', () async {
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'usd',
            days: 1,
          )).thenAnswer((_) async => _successMarketChart([
            _marketPoint(DateTime.now(), 999999999.99),
          ]));

      final price = await model.getBitcoinPrice();
      expect(price, closeTo(999999999.99, 0.01));
    });
  });

  // ─────────────────────────────────────────────
  // API call verification
  // ─────────────────────────────────────────────
  group('API call verification', () {
    test('getBitcoinPrice always queries bitcoin id', () async {
      when(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: any(named: 'vsCurrency'),
            days: any(named: 'days'),
          )).thenAnswer((_) async => _successMarketChart([
            _marketPoint(DateTime.now(), 50000.0),
          ]));

      await model.getBitcoinPrice(currency: 'eur');

      verify(() => mockCoins.getCoinMarketChart(
            id: 'bitcoin',
            vsCurrency: 'eur',
            days: 1,
          )).called(1);
    });

    test('getBitcoinOHLC always queries bitcoin id', () async {
      when(() => mockCoins.getCoinOHLC(
            id: 'bitcoin',
            vsCurrency: any(named: 'vsCurrency'),
            days: any(named: 'days'),
          )).thenAnswer((_) async => _successOHLC([]));

      await model.getBitcoinOHLC(currency: 'gbp', days: 90);

      verify(() => mockCoins.getCoinOHLC(
            id: 'bitcoin',
            vsCurrency: 'gbp',
            days: 90,
          )).called(1);
    });

    test('getBitcoinMarketDataRange always queries bitcoin id', () async {
      final from = DateTime(2025, 1, 1);
      final to = DateTime(2025, 6, 1);
      when(() => mockCoins.getCoinMarketChartRanged(
            id: 'bitcoin',
            vsCurrency: any(named: 'vsCurrency'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          )).thenAnswer((_) async => _successMarketChart([]));

      await model.getBitcoinMarketDataRange('brl', from, to);

      verify(() => mockCoins.getCoinMarketChartRanged(
            id: 'bitcoin',
            vsCurrency: 'brl',
            from: from,
            to: to,
          )).called(1);
    });
  });
}
