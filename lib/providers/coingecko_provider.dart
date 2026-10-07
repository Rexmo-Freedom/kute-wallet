// lib/providers/coingecko_provider.dart

import 'dart:math';
import 'package:kute/models/coingecko_model.dart';
import 'package:kute/providers/analytics_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:coingecko_api/data/market_chart_data.dart';
import 'package:coingecko_api/data/ohlc_info.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Provider #1: An AsyncNotifier that acts as a cache for the last year of market data.
// It only refetches from the network when the currency changes or when manually invalidated.
class BitcoinMarketDataNotifier extends AsyncNotifier<List<MarketChartData>> {
  @override
  Future<List<MarketChartData>> build() async {
    final currency = ref.watch(settingsProvider.select((s) => s.currency));
    final coingeckoModel = CoingeckoModel();
    final to = DateTime.now();
    final from = to.subtract(const Duration(days: 365));
    // This network call only happens when the provider is first loaded or invalidated.
    return await coingeckoModel.getBitcoinMarketDataRange(currency, from, to);
  }

  Future<void> refreshData() async {
    ref.invalidateSelf();
    await future;
  }
}

final bitcoinMarketDataProvider = AsyncNotifierProvider<BitcoinMarketDataNotifier, List<MarketChartData>>(
      () => BitcoinMarketDataNotifier(),
);


// Provider #2: A simple provider that filters the cached data from above.
// It watches the date range provider and will re-run its filter whenever the date range changes.
final filteredBitcoinMarketDataProvider = Provider.autoDispose<AsyncValue<List<MarketChartData>>>((ref) {
  final marketDataAsync = ref.watch(bitcoinMarketDataProvider);
  final selectedDays = ref.watch(selectedDaysDateArrayProvider);

  // Pass through loading and error states from the main provider.
  if (marketDataAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (marketDataAsync.hasError) {
    return AsyncValue.error(marketDataAsync.error!, marketDataAsync.stackTrace!);
  }

  final fullData = marketDataAsync.value ?? [];
  if (selectedDays.isEmpty || fullData.isEmpty) {
    return const AsyncValue.data([]);
  }

  final from = selectedDays.first;
  final to = selectedDays.last.add(const Duration(days: 1));

  final filtered = fullData.where((data) {
    return !data.date.isBefore(from) && data.date.isBefore(to);
  }).toList();

  return AsyncValue.data(filtered);
});

// Provider #4: OHLC data fetched with range-appropriate granularity.
// Cached per days value so switching ranges doesn't re-fetch.
final bitcoinOHLCByDaysProvider = FutureProvider.family<List<OHLCInfo>, int>((ref, days) async {
  final currency = ref.watch(settingsProvider.select((s) => s.currency));
  final coingeckoModel = CoingeckoModel();
  return await coingeckoModel.getBitcoinOHLC(currency: currency, days: days);
});

// Last-24-hour BTC market chart at hourly granularity. CoinGecko's
// market-chart endpoint serves 5-minute samples for `days=1`, which we
// downsample lightly when consumed. Used by the home BTC card's
// sparkline + 24h trend chip — separate from the 365-day daily series
// used by the analytics chart.
class BitcoinMarketDataLast24hNotifier extends AsyncNotifier<List<MarketChartData>> {
  @override
  Future<List<MarketChartData>> build() async {
    final currency = ref.watch(settingsProvider.select((s) => s.currency));
    final coingeckoModel = CoingeckoModel();
    return await coingeckoModel.getBitcoinMarketData(
      MarketData(days: 1, currency: currency),
    );
  }

  Future<void> refreshData() async {
    ref.invalidateSelf();
    await future;
  }
}

final bitcoinMarketDataLast24hProvider =
    AsyncNotifierProvider<BitcoinMarketDataLast24hNotifier, List<MarketChartData>>(
  () => BitcoinMarketDataLast24hNotifier(),
);

// Aggregate sub-daily candles (4-hour) into daily candles.
List<OHLCInfo> aggregateToDailyCandles(List<OHLCInfo> data) {
  final Map<DateTime, List<OHLCInfo>> grouped = {};
  for (final d in data) {
    final day = DateTime(d.timestamp.year, d.timestamp.month, d.timestamp.day);
    grouped.putIfAbsent(day, () => []).add(d);
  }

  final sortedDays = grouped.keys.toList()..sort();
  return sortedDays.map((day) {
    final candles = grouped[day]!;
    candles.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return OHLCInfo.fromArray([
      day.millisecondsSinceEpoch,
      candles.first.open,
      candles.map((c) => c.high).reduce(max),
      candles.map((c) => c.low).reduce(min),
      candles.last.close,
    ]);
  }).toList();
}

// Maps a selected range (in days) to the CoinGecko fetch parameter.
int _rangeDaysToFetchDays(int rangeDays) {
  if (rangeDays <= 7) return 7;
  if (rangeDays <= 30) return 30;
  if (rangeDays <= 90) return 90;
  return 365;
}

final filteredBitcoinOHLCProvider = Provider.autoDispose<AsyncValue<List<OHLCInfo>>>((ref) {
  final dateRange = ref.watch(dateTimeSelectProvider);
  final startDate = DateTime.fromMillisecondsSinceEpoch(dateRange.start * 1000);
  final endDate = DateTime.fromMillisecondsSinceEpoch(dateRange.end * 1000);
  final rangeDays = endDate.difference(startDate).inDays;

  final fetchDays = _rangeDaysToFetchDays(rangeDays);
  final ohlcAsync = ref.watch(bitcoinOHLCByDaysProvider(fetchDays));

  if (ohlcAsync.isLoading) return const AsyncValue.loading();
  if (ohlcAsync.hasError) return AsyncValue.error(ohlcAsync.error!, ohlcAsync.stackTrace!);

  var data = ohlcAsync.value ?? [];
  if (data.isEmpty) return const AsyncValue.data([]);

  // For short ranges CoinGecko returns sub-daily candles — aggregate to daily.
  if (fetchDays <= 30) {
    data = aggregateToDailyCandles(data);
  }

  return AsyncValue.data(data);
});
