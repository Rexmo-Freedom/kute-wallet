// The Bitcoin Send's conversion line and typed amount follow every currency
// Settings offers, and a typed figure always means what its label says: a
// currency whose rate has not arrived stays out, because a missing rate reads
// as one to one with the dollar.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money2/money2.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart'
    show canonicalDecimalText;
import 'package:kute/screens/shared/send/send_flow_widgets.dart';

class _Rates extends StateNotifier<CurrencyState> implements CurrencyNotifier {
  _Rates(super.state);

  @override
  Future<void> updateRates() async {}
}

/// 1 BTC = $100,000, so 1 sat = $0.001.
const _perUsd = {
  'EUR': '0.92',
  'GBP': '0.78',
  'CHF': '0.88',
  'BRL': '5.4',
  'SEK': '10.5',
  'NOK': '10.8',
  'DKK': '6.9',
  'PLN': '3.9',
  'CZK': '23',
  'HUF': '360',
  'RON': '4.6',
};

CurrencyState _state({Set<String> without = const {}}) => CurrencyState({
      'USD': Fixed.fromInt(100),
      'BTC': Fixed.parse('0.00001', decimalDigits: 16),
      for (final e in _perUsd.entries)
        if (!without.contains(e.key))
          e.key: Fixed.parse(e.value, decimalDigits: 16),
    });

ProviderContainer _container(CurrencyState rates, {String currency = 'USD'}) {
  final container = ProviderContainer(overrides: [
    currencyProvider.overrideWith((_) => _Rates(rates)),
    settingsProvider.overrideWith((_) => SettingsModel(Settings(
          currency: currency,
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: 'Blockstream',
          reviewDone: true,
        ))),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  AppCurrencies.registerCustomCurrencies();
  final rated = _state().hasRate;

  group('sendFiatFlipUnit', () {
    for (final code in kSendFiatUnits) {
      test('follows Settings to $code', () {
        expect(sendFiatFlipUnit(settingsCurrency: code, hasRate: rated), code);
      });
    }

    test('a currency Settings does not offer is dollars', () {
      expect(sendFiatFlipUnit(settingsCurrency: 'JPY', hasRate: (_) => true),
          'USD');
    });

    test('the unit last typed in comes first', () {
      expect(
          sendFiatFlipUnit(
              lastFiat: 'NOK', settingsCurrency: 'SEK', hasRate: rated),
          'NOK');
    });

    test('with no rate yet the line and the keypad stay in dollars', () {
      final noSek = _state(without: {'SEK'}).hasRate;
      expect(sendFiatFlipUnit(settingsCurrency: 'SEK', hasRate: noSek), 'USD');
      expect(
          sendFiatFlipUnit(
              lastFiat: 'SEK', settingsCurrency: 'EUR', hasRate: noSek),
          'EUR');
    });
  });

  test('every unit has its own mark, so no figure reads bare', () {
    for (final code in kSendFiatUnits) {
      expect(sendCurrencyPrefix(code), isNotEmpty, reason: code);
    }
    expect(sendCurrencyPrefix('SEK'), 'kr');
    expect(sendCurrencyPrefix('PLN'), 'zł');
    expect(sendCurrencyPrefix('CZK'), 'Kč');
    expect(sendCurrencyPrefix('HUF'), 'Ft');
    expect(sendCurrencyPrefix('RON'), 'lei');
  });

  group('a typed amount means what it says', () {
    // value in USD = amount / rate; 1 sat = $0.001.
    const cases = {
      'USD': 1234560,
      'SEK': 117577,
      'NOK': 114311,
      'DKK': 178922,
      'PLN': 316554,
      'CZK': 53676,
      'HUF': 3429,
      'RON': 268382,
    };
    cases.forEach((code, sats) {
      test('1234.56 $code is its value in sats, and reads back', () {
        final container = _container(_state());
        final typed = container
            .read(inputToSatsProvider((amount: '1234.56', currency: code)));
        expect(typed, closeTo(sats, 1));

        final shown = canonicalDecimalText(container.read(
            satsToTargetCurrencyProvider((sats: typed, currency: code))));
        expect(double.parse(shown), closeTo(1234.56, 1.0),
            reason: 'the keypad text after a flip back: $shown');
      });
    });

    test('the line for a widened currency converts at its rate', () {
      final container = _container(_state());
      // 100,000 sats = $100 = 1,050 kronor.
      expect(
          container.read(
              satsToTargetCurrencyProvider((sats: 100000, currency: 'SEK'))),
          '1 050,00');
      expect(
          container.read(
              satsToTargetCurrencyProvider((sats: 100000, currency: 'HUF'))),
          '36,000.00');
    });
  });

  group('conversionToFiatProvider', () {
    test('reads in the Settings currency once its rate is there', () {
      final container = _container(_state(), currency: 'SEK');
      expect(container.read(conversionToFiatProvider(100000)), 'kr1 050,00');
    });

    test('reads in dollars until then, never a dollar figure in kronor', () {
      final container =
          _container(_state(without: {'SEK'}), currency: 'SEK');
      expect(container.read(conversionToFiatProvider(100000)), r'$100.00');
    });
  });
}
