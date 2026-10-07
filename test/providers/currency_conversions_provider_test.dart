import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:money2/money2.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';

Settings _defaultSettings({String currency = 'USD', String btcFormat = 'sats'}) {
  return Settings(
    currency: currency,
    language: 'en',
    btcFormat: btcFormat,
    backup: false,
    balancePrivacy: 0,
    biometricsEnabled: false,
    bitcoinElectrumNode: 'localhost:50002',
    nodeType: 'Blockstream',
    reviewDone: false,
  );
}

CurrencyState _usdOnlyState() => CurrencyState({'USD': Fixed.fromInt(100)});

/// A minimal StateNotifier for CurrencyState that does not touch Hive.
class FakeCurrencyNotifier extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  FakeCurrencyNotifier(CurrencyState initial) : super(initial);

  @override
  Future<void> updateRates() async {}
}

void main() {
  AppCurrencies.registerCustomCurrencies();

  group('CurrencyState', () {
    test('convert BTC to USD with known rate', () {
      final rates = {
        'USD': Fixed.fromInt(100),
        'BTC': Fixed.parse('0.0000010000000000', decimalDigits: 16),
      };
      final cs = CurrencyState(rates);

      final oneBtc = Money.fromIntWithCurrency(100000000, AppCurrencies.btc);
      final result = cs.convert(oneBtc, AppCurrencies.usd);

      expect(result.currency.isoCode, 'USD');
      expect(result.amount > Fixed.zero, true);
    });

    test('convert USD to USD returns same amount', () {
      final cs = CurrencyState({'USD': Fixed.fromInt(100)});

      final tenUsd = Money.fromIntWithCurrency(1000, AppCurrencies.usd);
      final result = cs.convert(tenUsd, AppCurrencies.usd);

      expect(result.amount, tenUsd.amount);
    });

    test('convert with missing rate defaults to 1:1', () {
      final cs = CurrencyState({'USD': Fixed.fromInt(100)});

      final oneBtc = Money.fromIntWithCurrency(100000000, AppCurrencies.btc);
      final result = cs.convert(oneBtc, AppCurrencies.usd);

      expect(result.currency.isoCode, 'USD');
    });

    test('convert USD to EUR with known rate', () {
      final rates = {
        'USD': Fixed.fromInt(100),
        'EUR': Fixed.parse('0.9200000000000000', decimalDigits: 16),
      };
      final cs = CurrencyState(rates);

      final oneUsd = Money.fromIntWithCurrency(100, AppCurrencies.usd);
      final result = cs.convert(oneUsd, AppCurrencies.eur);

      expect(result.currency.isoCode, 'EUR');
    });

    test('convert zero amount returns zero', () {
      final rates = {
        'USD': Fixed.fromInt(100),
        'BTC': Fixed.parse('0.0000010000000000', decimalDigits: 16),
      };
      final cs = CurrencyState(rates);

      final zero = Money.fromIntWithCurrency(0, AppCurrencies.btc);
      final result = cs.convert(zero, AppCurrencies.usd);

      expect(result.minorUnits.toInt(), 0);
    });
  });

  group('AppCurrencies', () {
    test('registerCustomCurrencies makes SATS findable', () {
      AppCurrencies.registerCustomCurrencies();
      expect(Currencies().find('SATS'), isNotNull);
    });

    test('registerCustomCurrencies makes BTC findable', () {
      AppCurrencies.registerCustomCurrencies();
      expect(Currencies().find('BTC'), isNotNull);
    });

    test('apiSymbols excludes USD', () {
      final symbols = AppCurrencies.apiSymbols;
      expect(symbols.contains('USD'), false);
      expect(symbols.contains('EUR'), true);
    });

    test('supportedFiats contains expected currencies', () {
      expect(AppCurrencies.supportedFiats.length, 12);
      final codes = AppCurrencies.supportedFiats.map((c) => c.isoCode).toList();
      expect(codes, contains('USD'));
      expect(codes, contains('EUR'));
      expect(codes, contains('BRL'));
    });
  });

  group('conversionToFiatProvider', () {
    test('zero sats returns formatted zero', () {
      final container = ProviderContainer(overrides: [
        settingsProvider.overrideWith(
          (ref) => SettingsModel(_defaultSettings()),
        ),
        currencyProvider.overrideWith(
          (ref) => FakeCurrencyNotifier(_usdOnlyState()),
        ),
      ]);
      addTearDown(container.dispose);

      final result = container.read(conversionToFiatProvider(0));
      expect(result.contains('0.00'), true);
    });

    test('non-zero sats produces non-zero fiat string', () {
      final container = ProviderContainer(overrides: [
        settingsProvider.overrideWith(
          (ref) => SettingsModel(_defaultSettings()),
        ),
        currencyProvider.overrideWith(
          (ref) => FakeCurrencyNotifier(_usdOnlyState()),
        ),
      ]);
      addTearDown(container.dispose);

      final result = container.read(conversionToFiatProvider(100000000));
      // 1 BTC with default 1:1 rate should not be "0.00"
      expect(result.contains('0.00') && result.trim().replaceAll(RegExp(r'[^\d.]'), '') == '0.00', false);
    });
  });

  group('inputToSatsProvider', () {
    test('empty string returns 0', () {
      final container = ProviderContainer(overrides: [
        currencyProvider.overrideWith(
          (ref) => FakeCurrencyNotifier(_usdOnlyState()),
        ),
      ]);
      addTearDown(container.dispose);

      final result = container.read(
        inputToSatsProvider((amount: '', currency: 'USD')),
      );
      expect(result, 0);
    });

    test('non-numeric string returns 0', () {
      final container = ProviderContainer(overrides: [
        currencyProvider.overrideWith(
          (ref) => FakeCurrencyNotifier(_usdOnlyState()),
        ),
      ]);
      addTearDown(container.dispose);

      final result = container.read(
        inputToSatsProvider((amount: 'abc', currency: 'USD')),
      );
      expect(result, 0);
    });

    test('Sats input parses as integer sats', () {
      final container = ProviderContainer(overrides: [
        currencyProvider.overrideWith(
          (ref) => FakeCurrencyNotifier(_usdOnlyState()),
        ),
      ]);
      addTearDown(container.dispose);

      final result = container.read(
        inputToSatsProvider((amount: '50000', currency: 'Sats')),
      );
      expect(result, isA<int>());
      expect(result > 0, true);
    });

    test('BTC input of 1.0 returns positive sats', () {
      final container = ProviderContainer(overrides: [
        currencyProvider.overrideWith(
          (ref) => FakeCurrencyNotifier(_usdOnlyState()),
        ),
      ]);
      addTearDown(container.dispose);

      final result = container.read(
        inputToSatsProvider((amount: '1.0', currency: 'BTC')),
      );
      expect(result, isA<int>());
      expect(result > 0, true);
    });

    test('zero amount string returns 0', () {
      final container = ProviderContainer(overrides: [
        currencyProvider.overrideWith(
          (ref) => FakeCurrencyNotifier(_usdOnlyState()),
        ),
      ]);
      addTearDown(container.dispose);

      final result = container.read(
        inputToSatsProvider((amount: '0', currency: 'USD')),
      );
      expect(result, 0);
    });
  });

  group('satsToTargetCurrencyProvider', () {
    test('zero sats returns 0.00', () {
      final container = ProviderContainer(overrides: [
        currencyProvider.overrideWith(
          (ref) => FakeCurrencyNotifier(_usdOnlyState()),
        ),
      ]);
      addTearDown(container.dispose);

      final result = container.read(
        satsToTargetCurrencyProvider((sats: 0, currency: 'USD')),
      );
      expect(result, '0.00');
    });
  });
}
