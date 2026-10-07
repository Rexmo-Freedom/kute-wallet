import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/coingecko_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';

/// Cache for historical BTC prices to avoid repeated API calls.
/// Key: "YYYY-MM-DD", Value: price in USD
final _priceCache = <String, double>{};

/// In-flight guard for [prewarmBtcPriceHistory]. Shared across every
/// caller so the whole app issues at most ONE range request, never one
/// per lookup.
Future<void>? _prewarmFuture;

String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Populate [_priceCache] for ~the last [days] days with a SINGLE CoinGecko
/// range request, so the per-date [historicalBtcPriceProvider] reads that
/// follow are cache hits instead of one API call each.
///
/// Why this exists: valuing each Polymarket bet entry at its day's BTC
/// price means a price lookup per BUY. Doing those as one CoinGecko call
/// per bet bursts the free tier into 429s — which ALSO starves the BTC
/// spot-price request the home balance depends on, so the balance
/// collapses to "€0.00" and every Predictions amount renders ~1e8x too
/// large (a ~$5 leg shown as ₿565,216,000). One bulk fetch avoids that.
Future<void> prewarmBtcPriceHistory({int days = 366}) {
  return _prewarmFuture ??= _doPrewarmBtcPriceHistory(days);
}

Future<void> _doPrewarmBtcPriceHistory(int days) async {
  try {
    final coingecko = CoingeckoModel();
    final to = DateTime.now();
    final from = to.subtract(Duration(days: days));
    final data = await coingecko.getBitcoinMarketDataRange('usd', from, to);
    for (final point in data) {
      final price = point.price;
      if (price != null && price > 0) {
        _priceCache[_dayKey(point.date)] = price;
      }
    }
  } catch (_) {
    // Leave the cache as-is and allow a later retry. The per-date
    // provider still works (one call each) as a slower fallback.
    _prewarmFuture = null;
  }
}

/// Fetches the BTC price in USD for a specific date.
/// Returns the price as a double, or null if it could not be fetched.
final historicalBtcPriceProvider = FutureProvider.autoDispose.family<double?, DateTime>((ref, date) async {
  final dateKey = _dayKey(date);

  // Return cached value if available
  if (_priceCache.containsKey(dateKey)) {
    return _priceCache[dateKey];
  }

  // Today has no daily close yet, and the range endpoint answers a
  // sub-day window with nothing, so every lookup for a position opened
  // today came back null. Today's bitcoin price is the price the app is
  // already showing, so that is what today resolves to. Not cached: it
  // moves until the day ends.
  final now = DateTime.now();
  if (_dayKey(now) == dateKey) {
    final live = ref.read(selectedCurrencyProvider('USD')).toDouble();
    if (live.isFinite && live > 0) return live;
  }

  try {
    final coingecko = CoingeckoModel();
    final from = DateTime(date.year, date.month, date.day);
    final to = from.add(const Duration(days: 1));

    final data = await coingecko.getBitcoinMarketDataRange('usd', from, to);

    if (data.isNotEmpty) {
      final price = data.first.price ?? 0.0;
      _priceCache[dateKey] = price;
      return price;
    }
    return null;
  } catch (e) {
    return null;
  }
});

/// Formats a historical price for display.
/// Given sats amount and the BTC/USD price at that time, returns the fiat value string.
String formatHistoricalValue({
  required int amountSats,
  required double btcPriceUsd,
  required String currencySymbol,
}) {
  final btcAmount = amountSats / 100000000.0;
  final fiatValue = btcAmount * btcPriceUsd;
  return '$currencySymbol${fiatValue.toStringAsFixed(2)}';
}
