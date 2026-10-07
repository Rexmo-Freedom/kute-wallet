// lib/models/coingecko_model.dart
//
// Bitcoin price history for the Balance and Price charts and the day-by-day
// valuation of bets. The name is historical: the data now comes from
// Binance's public klines, which carry no key and a generous limit, because
// CoinGecko's free tier answered the charts with 429s and they stayed empty.
// CoinGecko remains only as the fallback when Binance is unreachable.
//
// Shapes are the coingecko_api types the charts already consume
// (MarketChartData, OHLCInfo), so nothing downstream changes.
import 'dart:convert';
import 'dart:math' as math;

import 'package:coingecko_api/coingecko_api.dart';
import 'package:coingecko_api/data/market_chart_data.dart';
import 'package:coingecko_api/data/ohlc_info.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;

/// USD → fiat multiplier for currencies Binance has no direct pair for.
typedef UsdRateLookup = Future<double?> Function(String currency);

class CoingeckoModel {
  final CoinGeckoApi api;
  final http.Client _http;
  final UsdRateLookup _usdRate;

  CoingeckoModel({CoinGeckoApi? api, http.Client? client, UsdRateLookup? usdRate})
      : api = api ?? CoinGeckoApi(),
        _http = client ?? http.Client(),
        _usdRate = usdRate ?? _hiveUsdRate;

  static const _binance = 'https://api.binance.com';

  /// Quote assets Binance lists against BTC. Everything else prices off
  /// BTCUSDT times the app's own USD → fiat rate.
  static const _directQuotes = {'USD': 'USDT', 'EUR': 'EUR', 'GBP': 'GBP', 'BRL': 'BRL', 'TRY': 'TRY', 'JPY': 'JPY', 'AUD': 'AUD', 'ZAR': 'ZAR', 'PLN': 'PLN', 'RON': 'RON', 'UAH': 'UAH', 'CZK': 'CZK', 'MXN': 'MXN', 'COP': 'COP'};

  /// The last USD → fiat rate the conversions provider stored.
  static Future<double?> _hiveUsdRate(String currency) async {
    try {
      final box = await Hive.openBox<String>('currency_rates_v2');
      final raw = box.get(currency.toUpperCase());
      final v = raw == null ? null : double.tryParse(raw);
      return v != null && v > 0 ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// The Binance pair for [currency] and the multiplier onto its prices.
  ///
  /// Without a stored USD rate a currency with no direct pair cannot be
  /// priced from BTCUSDT: scaling by 1 would show dollar figures under,
  /// say, a krona label. That throws, so priced reads fall back to
  /// CoinGecko, which quotes every fiat directly. [priced] false is for a
  /// dimensionless read (a percentage change), which BTCUSDT answers as is.
  Future<({String symbol, double scale})> _pair(String currency,
      {bool priced = true}) async {
    final code = currency.toUpperCase();
    final quote = _directQuotes[code];
    if (quote != null) return (symbol: 'BTC$quote', scale: 1.0);
    if (!priced) return (symbol: 'BTCUSDT', scale: 1.0);
    final rate = await _usdRate(code);
    if (rate == null) throw StateError('no USD rate for $code');
    return (symbol: 'BTCUSDT', scale: rate);
  }

  Future<dynamic> _get(String path) async {
    final res = await _http.get(Uri.parse('$_binance$path')).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw http.ClientException('binance $path HTTP ${res.statusCode}');
    return jsonDecode(res.body);
  }

  /// Klines as [openTime, open, high, low, close, volume, closeTime, quoteVolume, …].
  Future<List<List<dynamic>>> _klines(String symbol, String interval, {int? startMs, int? endMs, int limit = 1000}) async {
    final q = StringBuffer('/api/v3/klines?symbol=$symbol&interval=$interval&limit=${math.min(limit, 1000)}');
    if (startMs != null) q.write('&startTime=$startMs');
    if (endMs != null) q.write('&endTime=$endMs');
    final decoded = await _get(q.toString());
    return (decoded as List).whereType<List>().map((k) => k.cast<dynamic>()).toList();
  }

  static double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

  static Duration _intervalLength(String interval) => switch (interval) {
        '5m' => const Duration(minutes: 5),
        '15m' => const Duration(minutes: 15),
        '30m' => const Duration(minutes: 30),
        '1h' => const Duration(hours: 1),
        '4h' => const Duration(hours: 4),
        _ => const Duration(days: 1),
      };

  /// Fetches the current price of Bitcoin. Defaults to 'usd'.
  Future<double> getBitcoinPrice({String currency = 'usd'}) async {
    try {
      final pair = await _pair(currency);
      final decoded = await _get('/api/v3/ticker/price?symbol=${pair.symbol}') as Map<String, dynamic>;
      return _num(decoded['price']) * pair.scale;
    } catch (_) {
      try {
        final marketData = await api.coins.getCoinMarketChart(id: 'bitcoin', vsCurrency: currency.toLowerCase(), days: 1);
        if (marketData.isError || marketData.data.isEmpty) return 0.0;
        return marketData.data.last.price ?? 0;
      } catch (_) {
        return 0.0;
      }
    }
  }

  Future<double> getBitcoinChangePercentage(String currency) async {
    try {
      final pair = await _pair(currency, priced: false);
      final decoded = await _get('/api/v3/ticker/24hr?symbol=${pair.symbol}') as Map<String, dynamic>;
      return _num(decoded['priceChangePercent']);
    } catch (_) {
      return 0.0;
    }
  }

  /// The last [data.days] days at a granularity the chart can draw.
  Future<List<MarketChartData>> getBitcoinMarketData(MarketData data) async {
    final days = data.days;
    final interval = days <= 1 ? '5m' : days <= 7 ? '1h' : days <= 45 ? '4h' : '1d';
    final points = (Duration(days: days).inMinutes / _intervalLength(interval).inMinutes).ceil();
    try {
      final pair = await _pair(data.currency);
      final rows = await _klines(pair.symbol, interval, limit: points + 1);
      return [
        for (final k in rows)
          MarketChartData(DateTime.fromMillisecondsSinceEpoch(_num(k[6]).toInt()), price: _num(k[4]) * pair.scale, totalVolume: _num(k[7]) * pair.scale),
      ];
    } catch (e) {
      try {
        final marketData = await api.coins.getCoinMarketChart(id: 'bitcoin', vsCurrency: data.currency.toLowerCase(), days: days);
        return marketData.data;
      } on Exception catch (e2) {
        throw Exception('Failed to fetch market data: $e ($e2)');
      }
    }
  }

  /// Candles: 30 min up to two days, four hours up to a month, daily beyond.
  Future<List<OHLCInfo>> getBitcoinOHLC({String currency = 'usd', int days = 30}) async {
    final interval = days <= 2 ? '30m' : days <= 30 ? '4h' : '1d';
    final points = (Duration(days: days).inMinutes / _intervalLength(interval).inMinutes).ceil();
    try {
      final pair = await _pair(currency);
      final rows = await _klines(pair.symbol, interval, limit: points + 1);
      return [
        for (final k in rows)
          OHLCInfo.fromArray([_num(k[0]).toInt(), _num(k[1]) * pair.scale, _num(k[2]) * pair.scale, _num(k[3]) * pair.scale, _num(k[4]) * pair.scale]),
      ];
    } catch (_) {
      try {
        final result = await api.coins.getCoinOHLC(id: 'bitcoin', vsCurrency: currency.toLowerCase(), days: days);
        if (result.isError) return [];
        return result.data;
      } catch (_) {
        return [];
      }
    }
  }

  /// Price points between [from] and [to]. Daily closes over long spans, so
  /// a year of history is one request; finer intervals for short spans.
  Future<List<MarketChartData>> getBitcoinMarketDataRange(String currency, DateTime from, DateTime to) async {
    final span = to.difference(from);
    final interval = span.inHours <= 24 ? '5m' : span.inDays <= 7 ? '1h' : span.inDays <= 45 ? '4h' : '1d';
    final step = _intervalLength(interval);
    try {
      final pair = await _pair(currency);
      final out = <MarketChartData>[];
      var cursor = from.millisecondsSinceEpoch;
      final endMs = to.millisecondsSinceEpoch;
      for (var page = 0; page < 5 && cursor < endMs; page++) {
        final rows = await _klines(pair.symbol, interval, startMs: cursor, endMs: endMs);
        if (rows.isEmpty) break;
        for (final k in rows) {
          // Daily points are keyed to the day they open, so a day's close
          // lands on that day rather than the next.
          final at = interval == '1d' ? _num(k[0]).toInt() : _num(k[6]).toInt();
          out.add(MarketChartData(DateTime.fromMillisecondsSinceEpoch(at), price: _num(k[4]) * pair.scale, totalVolume: _num(k[7]) * pair.scale));
        }
        final last = _num(rows.last[0]).toInt();
        cursor = last + step.inMilliseconds;
        if (rows.length < 1000) break;
      }
      if (out.isEmpty) throw http.ClientException('binance range empty');
      return out;
    } catch (e) {
      try {
        final marketData = await api.coins.getCoinMarketChartRanged(id: 'bitcoin', vsCurrency: currency.toLowerCase(), from: from, to: to);
        return marketData.data;
      } catch (e2) {
        throw Exception('Failed to fetch market data: $e ($e2)');
      }
    }
  }
}

class MarketData {
  final int days;
  final String currency;

  MarketData({required this.days, required this.currency});
}
