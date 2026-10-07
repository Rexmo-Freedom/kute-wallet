import 'package:flutter_test/flutter_test.dart';
import 'package:money2/money2.dart';
import 'package:kute/models/currency_conversions.dart';

void main() {
  setUpAll(() {
    AppCurrencies.registerCustomCurrencies();
  });

  group('AppCurrencies', () {
    test('supportedFiats contains 12 currencies', () {
      expect(AppCurrencies.supportedFiats.length, 12);
    });

    test('supportedFiats includes USD, EUR, GBP, BRL', () {
      final codes = AppCurrencies.supportedFiats.map((c) => c.isoCode).toList();
      expect(codes, contains('USD'));
      expect(codes, contains('EUR'));
      expect(codes, contains('GBP'));
      expect(codes, contains('BRL'));
    });

    test('BTC currency is defined', () {
      expect(AppCurrencies.btc.isoCode, 'BTC');
    });

    test('SATS currency is defined', () {
      expect(AppCurrencies.sats.isoCode, 'SATS');
    });

    test('apiSymbols excludes USD', () {
      final symbols = AppCurrencies.apiSymbols;
      expect(symbols.contains('USD'), isFalse);
      expect(symbols.contains('EUR'), isTrue);
    });

    test('apiSymbols is comma-separated', () {
      final symbols = AppCurrencies.apiSymbols;
      final parts = symbols.split(',');
      expect(parts.length, 11); // 12 fiats - USD
    });
  });

  group('CurrencyState', () {
    late CurrencyState state;

    setUp(() {
      // Rates are relative to USD. EUR = 0.92 means 1 USD = 0.92 EUR
      state = CurrencyState({
        'EUR': Fixed.fromNum(0.92),
        'GBP': Fixed.fromNum(0.79),
        'BRL': Fixed.fromNum(5.0),
      });
    });

    test('convert USD to EUR with known rate', () {
      final usd100 = Money.fromNum(100.00, isoCode: 'USD');
      final result = state.convert(usd100, AppCurrencies.eur);
      // 100 USD * 0.92 = 92 EUR
      expect(result.currency.isoCode, 'EUR');
      expect(double.parse(result.amount.toString()), closeTo(92.0, 0.1));
    });

    test('convert EUR to USD (reverse direction)', () {
      final eur92 = Money.fromNum(92.0, isoCode: 'EUR');
      final result = state.convert(eur92, AppCurrencies.usd);
      // 92 EUR / 0.92 * 1.0 = 100 USD
      expect(result.currency.isoCode, 'USD');
      expect(double.parse(result.amount.toString()), closeTo(100.0, 0.1));
    });

    test('convert EUR to GBP', () {
      final eur92 = Money.fromNum(92.0, isoCode: 'EUR');
      final result = state.convert(eur92, AppCurrencies.gbp);
      // 92 / 0.92 = 100 USD, 100 * 0.79 = 79 GBP
      expect(result.currency.isoCode, 'GBP');
      expect(double.parse(result.amount.toString()), closeTo(79.0, 0.5));
    });

    test('zero amount converts to zero', () {
      final zero = Money.fromNum(0.0, isoCode: 'USD');
      final result = state.convert(zero, AppCurrencies.eur);
      expect(double.parse(result.amount.toString()), closeTo(0.0, 0.01));
    });

    test('missing currency in rate map defaults to 1:1 with USD', () {
      final usd100 = Money.fromNum(100.0, isoCode: 'USD');
      // CHF not in rate map, defaults to Fixed.fromInt(100) = 1.00
      final result = state.convert(usd100, AppCurrencies.chf);
      expect(result.currency.isoCode, 'CHF');
      // Should treat unknown rate as 1.00
      expect(double.parse(result.amount.toString()), closeTo(100.0, 0.1));
    });

    test('convert same currency returns same amount', () {
      final usd50 = Money.fromNum(50.0, isoCode: 'USD');
      final result = state.convert(usd50, AppCurrencies.usd);
      expect(double.parse(result.amount.toString()), closeTo(50.0, 0.01));
    });
  });

  group('CurrencyState - all supported fiat currencies', () {
    late CurrencyState state;

    // Realistic-ish rates: how many units of fiat per 1 USD
    final Map<String, double> rateValues = {
      'EUR': 0.92,
      'GBP': 0.79,
      'CHF': 0.88,
      'BRL': 5.0,
      'SEK': 10.5,
      'NOK': 10.3,
      'DKK': 6.85,
      'PLN': 4.0,
      'CZK': 22.5,
      'HUF': 355.0,
      'RON': 4.57,
    };

    setUp(() {
      state = CurrencyState(
        rateValues.map((k, v) => MapEntry(k, Fixed.fromNum(v))),
      );
    });

    // USD to each fiat currency
    for (final entry in {
      'EUR': 0.92,
      'GBP': 0.79,
      'CHF': 0.88,
      'BRL': 5.0,
      'SEK': 10.5,
      'NOK': 10.3,
      'DKK': 6.85,
      'PLN': 4.0,
      'CZK': 22.5,
      'HUF': 355.0,
      'RON': 4.57,
    }.entries) {
      test('convert USD to ${entry.key}', () {
        final usd100 = Money.fromNum(100.0, isoCode: 'USD');
        final target = AppCurrencies.supportedFiats
            .firstWhere((c) => c.isoCode == entry.key);
        final result = state.convert(usd100, target);
        expect(result.currency.isoCode, entry.key);
        final resultValue = double.parse(result.amount.toString());
        expect(resultValue, closeTo(100.0 * entry.value, 1.0));
      });
    }

    // Each fiat currency back to USD
    for (final entry in {
      'EUR': 0.92,
      'GBP': 0.79,
      'CHF': 0.88,
      'BRL': 5.0,
      'SEK': 10.5,
      'NOK': 10.3,
      'DKK': 6.85,
      'PLN': 4.0,
      'CZK': 22.5,
      'HUF': 355.0,
      'RON': 4.57,
    }.entries) {
      test('convert ${entry.key} to USD', () {
        final amount = entry.value * 100.0; // equivalent of 100 USD
        final source = Money.fromNum(amount, isoCode: entry.key);
        final result = state.convert(source, AppCurrencies.usd);
        expect(result.currency.isoCode, 'USD');
        final resultValue = double.parse(result.amount.toString());
        expect(resultValue, closeTo(100.0, 1.0));
      });
    }

    test('convert between two non-USD fiats (EUR to BRL)', () {
      final eur46 = Money.fromNum(46.0, isoCode: 'EUR');
      final result = state.convert(eur46, AppCurrencies.brl);
      // 46 EUR / 0.92 = 50 USD, 50 * 5.0 = 250 BRL
      expect(result.currency.isoCode, 'BRL');
      expect(double.parse(result.amount.toString()), closeTo(250.0, 1.0));
    });

    test('convert between two non-USD fiats (GBP to SEK)', () {
      final gbp79 = Money.fromNum(79.0, isoCode: 'GBP');
      final result = state.convert(gbp79, AppCurrencies.sek);
      // 79 GBP / 0.79 = 100 USD, 100 * 10.5 = 1050 SEK
      expect(result.currency.isoCode, 'SEK');
      expect(double.parse(result.amount.toString()), closeTo(1050.0, 5.0));
    });

    test('convert between two non-USD fiats (CZK to HUF)', () {
      final czk225 = Money.fromNum(225.0, isoCode: 'CZK');
      final result = state.convert(czk225, AppCurrencies.huf);
      // 225 CZK / 22.5 = 10 USD, 10 * 355 = 3550 HUF
      expect(result.currency.isoCode, 'HUF');
      expect(double.parse(result.amount.toString()), closeTo(3550.0, 10.0));
    });

    test('convert between two non-USD fiats (PLN to RON)', () {
      final pln40 = Money.fromNum(40.0, isoCode: 'PLN');
      final result = state.convert(pln40, AppCurrencies.ron);
      // 40 PLN / 4.0 = 10 USD, 10 * 4.57 = 45.7 RON
      expect(result.currency.isoCode, 'RON');
      expect(double.parse(result.amount.toString()), closeTo(45.7, 0.5));
    });

    test('convert between two non-USD fiats (DKK to NOK)', () {
      final dkk685 = Money.fromNum(685.0, isoCode: 'DKK');
      final result = state.convert(dkk685, AppCurrencies.nok);
      // 685 DKK / 6.85 = 100 USD, 100 * 10.3 = 1030 NOK
      expect(result.currency.isoCode, 'NOK');
      expect(double.parse(result.amount.toString()), closeTo(1030.0, 5.0));
    });
  });

  group('CurrencyState - BTC conversions', () {
    late CurrencyState state;

    setUp(() {
      // BTC rate: 1 USD = 0.000016 BTC (i.e., 1 BTC ~ 62500 USD)
      // EUR rate: 1 USD = 0.92 EUR
      state = CurrencyState({
        'BTC': Fixed.fromNum(0.000016),
        'EUR': Fixed.fromNum(0.92),
        'GBP': Fixed.fromNum(0.79),
        'BRL': Fixed.fromNum(5.0),
      });
    });

    test('convert USD to BTC', () {
      final usd62500 = Money.fromNum(62500.0, isoCode: 'USD');
      final result = state.convert(usd62500, AppCurrencies.btc);
      expect(result.currency.isoCode, 'BTC');
      final resultValue = double.parse(result.amount.toString());
      expect(resultValue, closeTo(1.0, 0.01));
    });

    test('convert BTC to USD', () {
      final btc1 = Money.fromNum(1.0, isoCode: 'BTC');
      final result = state.convert(btc1, AppCurrencies.usd);
      expect(result.currency.isoCode, 'USD');
      final resultValue = double.parse(result.amount.toString());
      expect(resultValue, closeTo(62500.0, 100.0));
    });

    test('convert small BTC amount to USD', () {
      final btcSmall = Money.fromNum(0.01, isoCode: 'BTC');
      final result = state.convert(btcSmall, AppCurrencies.usd);
      expect(result.currency.isoCode, 'USD');
      final resultValue = double.parse(result.amount.toString());
      expect(resultValue, closeTo(625.0, 10.0));
    });

    test('convert BTC to EUR', () {
      final btc1 = Money.fromNum(1.0, isoCode: 'BTC');
      final result = state.convert(btc1, AppCurrencies.eur);
      expect(result.currency.isoCode, 'EUR');
      final resultValue = double.parse(result.amount.toString());
      // 1 BTC / 0.000016 = 62500 USD, 62500 * 0.92 = 57500 EUR
      expect(resultValue, closeTo(57500.0, 100.0));
    });

    test('convert EUR to BTC', () {
      final eur57500 = Money.fromNum(57500.0, isoCode: 'EUR');
      final result = state.convert(eur57500, AppCurrencies.btc);
      expect(result.currency.isoCode, 'BTC');
      final resultValue = double.parse(result.amount.toString());
      // 57500 / 0.92 = 62500 USD, 62500 * 0.000016 = 1 BTC
      expect(resultValue, closeTo(1.0, 0.05));
    });

    test('convert BTC to BRL', () {
      final btc1 = Money.fromNum(1.0, isoCode: 'BTC');
      final result = state.convert(btc1, AppCurrencies.brl);
      expect(result.currency.isoCode, 'BRL');
      final resultValue = double.parse(result.amount.toString());
      // 1 BTC / 0.000016 = 62500 USD, 62500 * 5.0 = 312500 BRL
      expect(resultValue, closeTo(312500.0, 500.0));
    });

    test('convert BRL to BTC', () {
      final brl312500 = Money.fromNum(312500.0, isoCode: 'BRL');
      final result = state.convert(brl312500, AppCurrencies.btc);
      expect(result.currency.isoCode, 'BTC');
      final resultValue = double.parse(result.amount.toString());
      expect(resultValue, closeTo(1.0, 0.05));
    });

    test('convert zero BTC to USD', () {
      final btcZero = Money.fromNum(0.0, isoCode: 'BTC');
      final result = state.convert(btcZero, AppCurrencies.usd);
      expect(double.parse(result.amount.toString()), closeTo(0.0, 0.01));
    });

    test('convert zero USD to BTC', () {
      final usdZero = Money.fromNum(0.0, isoCode: 'USD');
      final result = state.convert(usdZero, AppCurrencies.btc);
      expect(double.parse(result.amount.toString()), closeTo(0.0, 0.0001));
    });
  });

  group('CurrencyState - zero rates', () {
    test('zero rate for target currency produces zero result', () {
      final state = CurrencyState({
        'EUR': Fixed.fromNum(0.0),
      });
      final usd100 = Money.fromNum(100.0, isoCode: 'USD');
      final result = state.convert(usd100, AppCurrencies.eur);
      expect(double.parse(result.amount.toString()), closeTo(0.0, 0.01));
    });
  });

  group('CurrencyState - negative amounts', () {
    late CurrencyState state;

    setUp(() {
      state = CurrencyState({
        'EUR': Fixed.fromNum(0.92),
        'BTC': Fixed.fromNum(0.000016),
      });
    });

    test('convert negative USD to EUR', () {
      final negUsd = Money.fromNum(-100.0, isoCode: 'USD');
      final result = state.convert(negUsd, AppCurrencies.eur);
      expect(result.currency.isoCode, 'EUR');
      final resultValue = double.parse(result.amount.toString());
      expect(resultValue, closeTo(-92.0, 0.5));
    });

    test('convert negative EUR to USD', () {
      final negEur = Money.fromNum(-92.0, isoCode: 'EUR');
      final result = state.convert(negEur, AppCurrencies.usd);
      expect(result.currency.isoCode, 'USD');
      final resultValue = double.parse(result.amount.toString());
      expect(resultValue, closeTo(-100.0, 0.5));
    });

    test('convert negative BTC to USD', () {
      final negBtc = Money.fromNum(-1.0, isoCode: 'BTC');
      final result = state.convert(negBtc, AppCurrencies.usd);
      expect(result.currency.isoCode, 'USD');
      final resultValue = double.parse(result.amount.toString());
      expect(resultValue, closeTo(-62500.0, 100.0));
    });

    test('convert negative USD to BTC', () {
      final negUsd = Money.fromNum(-62500.0, isoCode: 'USD');
      final result = state.convert(negUsd, AppCurrencies.btc);
      expect(result.currency.isoCode, 'BTC');
      final resultValue = double.parse(result.amount.toString());
      expect(resultValue, closeTo(-1.0, 0.05));
    });
  });

  group('CurrencyState - very large amounts', () {
    late CurrencyState state;

    setUp(() {
      state = CurrencyState({
        'EUR': Fixed.fromNum(0.92),
        'BTC': Fixed.fromNum(0.000016),
        'BRL': Fixed.fromNum(5.0),
      });
    });

    test('convert 1 million USD to EUR', () {
      final usd = Money.fromNum(1000000.0, isoCode: 'USD');
      final result = state.convert(usd, AppCurrencies.eur);
      expect(result.currency.isoCode, 'EUR');
      final resultValue = double.parse(result.amount.toString());
      expect(resultValue, closeTo(920000.0, 100.0));
    });

    test('convert 1 million USD to BRL', () {
      final usd = Money.fromNum(1000000.0, isoCode: 'USD');
      final result = state.convert(usd, AppCurrencies.brl);
      expect(result.currency.isoCode, 'BRL');
      final resultValue = double.parse(result.amount.toString());
      expect(resultValue, closeTo(5000000.0, 100.0));
    });

    test('convert large BTC amount to USD', () {
      final btc21m = Money.fromNum(21000000.0, isoCode: 'BTC');
      final result = state.convert(btc21m, AppCurrencies.usd);
      expect(result.currency.isoCode, 'USD');
      final resultValue = double.parse(result.amount.toString());
      // 21M BTC / 0.000016 = 1.3125 trillion USD
      expect(resultValue, greaterThan(0));
    });

    test('convert large USD amount to BTC', () {
      final usd = Money.fromNum(10000000.0, isoCode: 'USD');
      final result = state.convert(usd, AppCurrencies.btc);
      expect(result.currency.isoCode, 'BTC');
      final resultValue = double.parse(result.amount.toString());
      // 10M USD * 0.000016 = 160 BTC
      expect(resultValue, closeTo(160.0, 5.0));
    });
  });

  group('CurrencyState - precision and rounding', () {
    late CurrencyState state;

    setUp(() {
      state = CurrencyState({
        'EUR': Fixed.fromNum(0.92),
        'GBP': Fixed.fromNum(0.79),
        'BTC': Fixed.fromNum(0.000016),
      });
    });

    test('fractional cent amounts are handled', () {
      final usd = Money.fromNum(1.01, isoCode: 'USD');
      final result = state.convert(usd, AppCurrencies.eur);
      expect(result.currency.isoCode, 'EUR');
      final resultValue = double.parse(result.amount.toString());
      expect(resultValue, closeTo(0.9292, 0.01));
    });

    test('very small fiat amount converts correctly', () {
      final usd = Money.fromNum(0.01, isoCode: 'USD');
      final result = state.convert(usd, AppCurrencies.eur);
      expect(result.currency.isoCode, 'EUR');
      final resultValue = double.parse(result.amount.toString());
      expect(resultValue, closeTo(0.0092, 0.01));
    });

    test('result currency code matches target', () {
      final usd = Money.fromNum(50.0, isoCode: 'USD');
      final resultEur = state.convert(usd, AppCurrencies.eur);
      final resultGbp = state.convert(usd, AppCurrencies.gbp);
      final resultBtc = state.convert(usd, AppCurrencies.btc);
      expect(resultEur.currency.isoCode, 'EUR');
      expect(resultGbp.currency.isoCode, 'GBP');
      expect(resultBtc.currency.isoCode, 'BTC');
    });

    test('round-trip conversion preserves approximate value (USD -> EUR -> USD)', () {
      final original = Money.fromNum(100.0, isoCode: 'USD');
      final inEur = state.convert(original, AppCurrencies.eur);
      final backToUsd = state.convert(inEur, AppCurrencies.usd);
      final resultValue = double.parse(backToUsd.amount.toString());
      expect(resultValue, closeTo(100.0, 1.0));
    });

    test('round-trip conversion preserves approximate value (USD -> BTC -> USD)', () {
      final original = Money.fromNum(1000.0, isoCode: 'USD');
      final inBtc = state.convert(original, AppCurrencies.btc);
      final backToUsd = state.convert(inBtc, AppCurrencies.usd);
      final resultValue = double.parse(backToUsd.amount.toString());
      expect(resultValue, closeTo(1000.0, 50.0));
    });

    test('round-trip conversion preserves approximate value (EUR -> GBP -> EUR)', () {
      final original = Money.fromNum(100.0, isoCode: 'EUR');
      final inGbp = state.convert(original, AppCurrencies.gbp);
      final backToEur = state.convert(inGbp, AppCurrencies.eur);
      final resultValue = double.parse(backToEur.amount.toString());
      expect(resultValue, closeTo(100.0, 2.0));
    });
  });

  group('CurrencyState - edge cases with rate map', () {
    test('empty rate map treats all currencies as 1:1 with USD', () {
      final state = CurrencyState({});
      final usd100 = Money.fromNum(100.0, isoCode: 'USD');
      final result = state.convert(usd100, AppCurrencies.eur);
      expect(double.parse(result.amount.toString()), closeTo(100.0, 0.1));
    });

    test('empty rate map: EUR to GBP is 1:1', () {
      final state = CurrencyState({});
      final eur50 = Money.fromNum(50.0, isoCode: 'EUR');
      final result = state.convert(eur50, AppCurrencies.gbp);
      expect(double.parse(result.amount.toString()), closeTo(50.0, 0.1));
    });

    test('rate of exactly 1.0 means parity with USD', () {
      final state = CurrencyState({
        'EUR': Fixed.fromNum(1.0),
      });
      final usd100 = Money.fromNum(100.0, isoCode: 'USD');
      final result = state.convert(usd100, AppCurrencies.eur);
      expect(double.parse(result.amount.toString()), closeTo(100.0, 0.1));
    });

    test('very small rate (like BTC) does not lose precision entirely', () {
      final state = CurrencyState({
        'BTC': Fixed.fromNum(0.00001),
      });
      final usd1000 = Money.fromNum(1000.0, isoCode: 'USD');
      final result = state.convert(usd1000, AppCurrencies.btc);
      expect(result.currency.isoCode, 'BTC');
      final resultValue = double.parse(result.amount.toString());
      expect(resultValue, closeTo(0.01, 0.005));
    });

    test('very large rate (like HUF) handles correctly', () {
      final state = CurrencyState({
        'HUF': Fixed.fromNum(400.0),
      });
      final usd1 = Money.fromNum(1.0, isoCode: 'USD');
      final result = state.convert(usd1, AppCurrencies.huf);
      expect(result.currency.isoCode, 'HUF');
      final resultValue = double.parse(result.amount.toString());
      expect(resultValue, closeTo(400.0, 1.0));
    });
  });

  group('AppCurrencies - completeness checks', () {
    test('supportedFiats contains all 12 expected currencies', () {
      final codes = AppCurrencies.supportedFiats.map((c) => c.isoCode).toSet();
      expect(codes, containsAll([
        'USD', 'EUR', 'GBP', 'CHF', 'BRL',
        'SEK', 'NOK', 'DKK', 'PLN', 'CZK', 'HUF', 'RON',
      ]));
    });

    test('supportedFiats does not contain BTC', () {
      final codes = AppCurrencies.supportedFiats.map((c) => c.isoCode).toSet();
      expect(codes.contains('BTC'), isFalse);
    });

    test('supportedFiats does not contain SATS', () {
      final codes = AppCurrencies.supportedFiats.map((c) => c.isoCode).toSet();
      expect(codes.contains('SATS'), isFalse);
    });

    test('SATS currency has 0 decimal places', () {
      expect(AppCurrencies.sats.decimalDigits, 0);
    });

    test('SATS currency symbol is lightning bolt', () {
      expect(AppCurrencies.sats.symbol, '\u26A1');
    });

    test('registerCustomCurrencies is idempotent', () {
      AppCurrencies.registerCustomCurrencies();
      AppCurrencies.registerCustomCurrencies();
      // Should not throw; currencies already registered
      expect(Currencies().find('SATS'), isNotNull);
      expect(Currencies().find('BTC'), isNotNull);
    });

    test('apiSymbols does not contain BTC or SATS', () {
      final symbols = AppCurrencies.apiSymbols;
      expect(symbols.contains('BTC'), isFalse);
      expect(symbols.contains('SATS'), isFalse);
    });
  });
}
