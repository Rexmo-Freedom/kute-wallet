import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/models/currency_conversions.dart';

void main() {
  setUpAll(() {
    AppCurrencies.registerCustomCurrencies();
  });

  group('CurrencyFormatting', () {
    test('formatValue USD', () {
      final result = AppCurrencies.usd.formatValue(42.5);
      expect(result, contains('42.50'));
    });

    test('formatValue zero', () {
      final result = AppCurrencies.usd.formatValue(0);
      expect(result, contains('0.00'));
    });

    test('formatFromString USD', () {
      final result = AppCurrencies.usd.formatFromString('99.99');
      expect(result, contains('99.99'));
    });

    test('formatFromString empty string returns zero', () {
      final result = AppCurrencies.usd.formatFromString('');
      expect(result, contains('0.00'));
    });

    test('formatValue EUR', () {
      final result = AppCurrencies.eur.formatValue(100.0);
      expect(result, contains('100'));
    });
  });

  group('SatoshiFormatting', () {
    test('toFormattedString sats denomination', () {
      final result = 100000.toFormattedString('sats');
      expect(result, '100,000');
    });

    test('toFormattedString BTC denomination', () {
      final result = 100000000.toFormattedString('BTC');
      expect(result, contains('1.00'));
    });

    test('toFormattedString zero sats', () {
      final result = 0.toFormattedString('sats');
      expect(result, '0');
    });

    test('toFormattedString zero BTC', () {
      final result = 0.toFormattedString('BTC');
      expect(result, contains('0.00'));
    });

    test('toRawBtcString 1 BTC', () {
      final result = 100000000.toRawBtcString();
      expect(result, '1.00000000');
    });

    test('toRawBtcString 0 sats', () {
      final result = 0.toRawBtcString();
      expect(result, '0.00000000');
    });

    test('toRawBtcString small amount', () {
      final result = 1.toRawBtcString();
      expect(result, '0.00000001');
    });

    test('toRawBtcString 21M BTC', () {
      final result = 2100000000000000.toRawBtcString();
      expect(result, '21000000.00000000');
    });

    test('toDoubleValue sats denomination', () {
      expect(50000.toDoubleValue('sats'), 50000.0);
    });

    test('toDoubleValue BTC denomination', () {
      expect(100000000.toDoubleValue('BTC'), 1.0);
    });

    test('toDoubleValue zero', () {
      expect(0.toDoubleValue('sats'), 0.0);
      expect(0.toDoubleValue('BTC'), 0.0);
    });
  });

  group('addBtcDecimalSpaces', () {
    test('adds thin spaces after 2 decimal digits', () {
      final result = addBtcDecimalSpaces('1.00000000');
      // Format: 1.00 000 000 (thin spaces between groups)
      expect(result, contains('1.00'));
      expect(result.length, greaterThan('1.00000000'.length));
    });

    test('no dot returns unchanged', () {
      expect(addBtcDecimalSpaces('123'), '123');
    });

    test('2 or fewer decimals returns unchanged', () {
      expect(addBtcDecimalSpaces('1.00'), '1.00');
      expect(addBtcDecimalSpaces('1.5'), '1.5');
    });

    test('zero BTC', () {
      final result = addBtcDecimalSpaces('0.00000000');
      expect(result, isNotEmpty);
      expect(result.startsWith('0.00'), isTrue);
    });
  });
}
