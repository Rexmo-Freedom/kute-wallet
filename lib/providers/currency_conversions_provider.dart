import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:money2/money2.dart';
import 'package:kute/helpers/extension.dart';
import 'package:kute/models/coingecko_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/api/api_client.dart';

class CurrencyNotifier extends StateNotifier<CurrencyState> {
  CurrencyNotifier() : super(CurrencyState({'USD': Fixed.fromInt(1)})) {
    _loadFromHive();
  }

  Future<void> _loadFromHive() async {
    final box = await Hive.openBox<String>('currency_rates_v2');
    final Map<String, Fixed> loadedRates = {};

    for (final key in box.keys) {
      final String? rateString = box.get(key);
      if (rateString == null) continue;
      try {
        loadedRates[key.toString()] = Fixed.parse(rateString);
      } catch (_) {
        // A single malformed / locale-corrupted entry must not abort the whole
        // load — that would drop the BTC rate and collapse every fiat to 0.00.
        // Drop the bad entry and keep going.
        try {
          await box.delete(key);
        } catch (_) {/* non-fatal */}
      }
    }

    if (loadedRates.isNotEmpty) {
      state = CurrencyState(loadedRates);
    }
  }

  Future<void> updateRates() async {
    final box = await Hive.openBox<String>('currency_rates_v2');
    // Carry forward the last-known rates so a slow / rate-limited fetch can
    // only ADD fresher numbers — it can never DROP a rate we already had.
    // Previously this started from scratch ({'USD': 1}); when CoinGecko
    // returned 0 (rate-limited) the `if (btcPriceInUsdDouble > 0)` block was
    // skipped and we still published a state with no 'BTC' key. `CurrencyState
    // .convert` then falls back to valuing 1 BTC at ~$1, so the home fiat
    // balance collapsed to "$0.00" for a frame before the next poll restored
    // it — the "value drops to zero then comes back on refresh" bug. USD stays
    // pinned to 1.
    final Map<String, Fixed> newRates = {
      ...state.rates,
      'USD': Fixed.fromInt(1),
    };

    try {
      final symbols = AppCurrencies.apiSymbols;
      final api = ApiClient('https://api.frankfurter.dev');
      final res = await api.get<Map<String, dynamic>>(
        '/v1/latest?base=USD&symbols=$symbols',
        (json) => (json as Map<String, dynamic>)['rates'] as Map<String, dynamic>,
      );

      if (res.isSuccess) {
        res.data!.forEach((currency, rate) {
          final fixedRate = Fixed.fromNum(rate as num, decimalDigits: 16);
          newRates[currency] = fixedRate;
          box.put(currency, fixedRate.toString());
        });
      }

      final coingecko = CoingeckoModel();
      var btcPriceInUsdDouble = await coingecko.getBitcoinPrice(currency: 'usd');

      // CoinGecko's free tier rate-limits aggressively; on a 429 / timeout
      // getBitcoinPrice returns 0, which used to leave rates['BTC'] unwritten —
      // and convert() then values 1 BTC at ~$1, collapsing every fiat figure to
      // ~0.00 until a fetch finally succeeded (sticky, because the missing key
      // is never persisted). Fall back to an independent source (the same
      // Binance ticker the analytics feed uses) so a rate-limited user still
      // gets a BTC rate this pass.
      if (!_isSaneBtcUsd(btcPriceInUsdDouble)) {
        btcPriceInUsdDouble = await _fetchBinanceBtcUsd() ?? btcPriceInUsdDouble;
      }

      // Sane-range guard (was `> 0`): reject a 0 or a transient garbage price
      // (e.g. a sub-dollar chart point) so it can't poison the cache and stick
      // across boots. A rejected price leaves the last-known rate (carried
      // forward into newRates above) intact rather than dropping it.
      if (_isSaneBtcUsd(btcPriceInUsdDouble)) {
        final Fixed btcPriceInUsd = Fixed.fromNum(btcPriceInUsdDouble, decimalDigits: 16);
        final Fixed one = Fixed.fromInt(100);
        final Fixed usdToBtc = one / btcPriceInUsd;

        newRates['BTC'] = usdToBtc;
        box.put('BTC', usdToBtc.toString());

        final Fixed satsRate = usdToBtc * Fixed.fromInt(100000000);
        newRates['SATS'] = satsRate;
        box.put('SATS', satsRate.toString());
      }

      state = CurrencyState(newRates);
    } catch (e) {
      // Silently ignored
    }
  }
}

/// Plausible BTC/USD band. Rejects 0 (rate-limited / failed fetch) and absurd
/// values (a transient sub-dollar or runaway chart point) that would otherwise
/// poison the cached rate and round every fiat balance to 0.00.
bool _isSaneBtcUsd(double p) => p > 1000 && p < 10000000;

/// Independent BTC/USD fallback for when CoinGecko fails / rate-limits. Hits
/// the same Binance venue the live analytics feed uses (a simple REST ticker,
/// no key, generous limits). Best-effort: returns null on any failure or
/// out-of-band value so the caller keeps its last-known rate.
Future<double?> _fetchBinanceBtcUsd() async {
  try {
    final api = ApiClient('https://api.binance.com');
    final res = await api.get<double>(
      '/api/v3/ticker/price?symbol=BTCUSDT',
      (json) =>
          double.tryParse((json as Map<String, dynamic>)['price'] as String? ?? '') ?? 0,
    );
    if (res.isSuccess && _isSaneBtcUsd(res.data!)) return res.data;
  } catch (_) {/* fall through — keep last-known rate */}
  return null;
}

final currencyProvider = StateNotifierProvider<CurrencyNotifier, CurrencyState>((ref) {
  return CurrencyNotifier();
});

/// Returns a Money object representing 1 BTC in the target currency.
final selectedCurrencyProvider = Provider.autoDispose.family<Money, String>((ref, targetCurrencyCode) {
  final currencyState = ref.watch(currencyProvider);
  AppCurrencies.registerCustomCurrencies();

  final targetCurrency = Currencies().find(targetCurrencyCode) ?? AppCurrencies.usd;
  final oneBtc = Money.fromIntWithCurrency(100000000, AppCurrencies.btc);

  return currencyState.convert(oneBtc, targetCurrency);
});

/// Returns a Money object representing 1 USD in the target currency.
final selectedCurrencyProviderFromUSD = Provider.autoDispose.family<Money, String>((ref, targetCurrencyCode) {
  final currencyState = ref.watch(currencyProvider);
  AppCurrencies.registerCustomCurrencies();

  final targetCurrency = Currencies().find(targetCurrencyCode) ?? AppCurrencies.usd;
  final oneUsd = Money.fromIntWithCurrency(100, AppCurrencies.usd);

  return currencyState.convert(oneUsd, targetCurrency);
});

final conversionProvider = Provider.autoDispose.family<String, int>((ref, amountInSats) {
  final settings = ref.watch(settingsProvider);

  // Both branches now go through `toFormattedString` (locale-aware
  // thousands grouping for sats, narrow-space grouping for BTC
  // decimals) AND ₿-prefix the result per BIP-177. The sats branch
  // used to return `Money.minorUnits.toString()` — raw digits like
  // "12345678" with no comma separation — so a BTC receive row in
  // the activity feed lost its commas whenever the user's display
  // setting was sats. Match `_formatBtcSats` in transactions_builder
  // so the live and cache paths produce identical strings.
  switch (settings.btcFormat) {
    case 'sats':
      return '₿${amountInSats.toFormattedString('sats')}';
    case 'BTC':
    default:
      return '₿${amountInSats.toFormattedString('BTC')}';
  }
});

/// Current BTC price in USD (value of 1 BTC). 0 if rates aren't loaded yet.
/// Used to compare a transaction's stored at-the-time USD value against now.
final currentBtcUsdProvider = Provider.autoDispose<double>((ref) {
  try {
    final cs = ref.watch(currencyProvider);
    final btc = Money.fromIntWithCurrency(100000000, AppCurrencies.btc);
    return double.tryParse(cs.convert(btc, AppCurrencies.usd).amount.toString()) ??
        0;
  } catch (_) {
    return 0;
  }
});

/// Formats integer sats to fiat string with symbol (e.g. "$50.25").
final conversionToFiatProvider = Provider.autoDispose.family<String, int>((ref, amountInSats) {
  final settings = ref.watch(settingsProvider);
  final currencyState = ref.watch(currencyProvider);

  final btcMoney = Money.fromIntWithCurrency(amountInSats, AppCurrencies.btc);

  AppCurrencies.registerCustomCurrencies();
  final targetCode = settings.currency;
  final targetCurrency = Currencies().find(targetCode) ?? AppCurrencies.usd;

  final fiatMoney = currencyState.convert(btcMoney, targetCurrency);

  return fiatMoney.format('S#,##0.00');
});

/// Converts sats to a specific target currency (not necessarily the user's settings currency).
/// Used by MAX button and other cases where input currency differs from settings.
final satsToTargetCurrencyProvider = Provider.autoDispose.family<String, ({int sats, String currency})>((ref, args) {
  final currencyState = ref.watch(currencyProvider);
  final btcMoney = Money.fromIntWithCurrency(args.sats, AppCurrencies.btc);

  AppCurrencies.registerCustomCurrencies();
  final targetCurrency = Currencies().find(args.currency) ?? AppCurrencies.usd;
  final fiatMoney = currencyState.convert(btcMoney, targetCurrency);

  return fiatMoney.format('#,##0.00');
});

/// Parses (amount string + currency code) to integer satoshis.
final inputToSatsProvider = Provider.autoDispose.family<int, ({String amount, String currency})>((ref, args) {
  final currencyState = ref.watch(currencyProvider);

  final sourceMoney = _parseInputToMoney(args.amount, args.currency);
  final btcMoney = currencyState.convert(sourceMoney, AppCurrencies.btc);

  return btcMoney.minorUnits.toInt();
});

/// Parses (amount string + currency code) to formatted BTC string (e.g. "0.00500000").
final inputToBtcStringProvider = Provider.autoDispose.family<String, ({String amount, String currency})>((ref, args) {
  final currencyState = ref.watch(currencyProvider);

  final sourceMoney = _parseInputToMoney(args.amount, args.currency);
  final btcMoney = currencyState.convert(sourceMoney, AppCurrencies.btc);

  return btcMoney.format('0.00000000');
});

// Uses Fixed.parse to avoid double precision loss on financial amounts.
Money _parseInputToMoney(String amountStr, String currencyCode) {
  if (amountStr.isEmpty) return Money.fromInt(0, isoCode: 'USD');

  final cleaned = amountStr.replaceAll(',', '.');
  if (double.tryParse(cleaned) == null) return Money.fromInt(0, isoCode: 'USD');
  if (double.tryParse(cleaned) == 0.0) return Money.fromInt(0, isoCode: 'USD');

  AppCurrencies.registerCustomCurrencies();

  if (currencyCode == 'Sats') {
    final sats = int.tryParse(cleaned.split('.').first) ?? 0;
    return Money.fromIntWithCurrency(sats, AppCurrencies.btc);
  } else if (currencyCode == 'BTC') {
    final fixed = Fixed.parse(cleaned, decimalDigits: 8);
    return Money.fromFixed(fixed, isoCode: 'BTC');
  } else {
    final currency = Currencies().find(currencyCode) ?? AppCurrencies.usd;
    final fixed = Fixed.parse(cleaned, decimalDigits: currency.decimalDigits);
    return Money.fromFixed(fixed, isoCode: currency.isoCode);
  }
}

final updateCurrencyProvider = FutureProvider<void>((ref) async {
  final notifier = ref.read(currencyProvider.notifier);
  try {
    await notifier.updateRates();
  } catch (e) {
    ref.read(onlineProvider.notifier).state = false;
  }
});
