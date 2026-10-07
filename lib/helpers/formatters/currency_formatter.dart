import 'package:intl/intl.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:money2/money2.dart';

extension CurrencyFormatting on Currency {
  String formatValue(double amount) {
    final fixed = Fixed.fromNum(amount, decimalDigits: decimalDigits);
    final money = Money.fromFixed(fixed, isoCode: isoCode);
    return money.format('S#0.00');
  }

  String formatFromString(String amount) {
    if (amount.isEmpty) return formatValue(0);
    final fixed = Fixed.parse(amount, decimalDigits: decimalDigits);
    final money = Money.fromFixed(fixed, isoCode: isoCode);
    return money.format('S#0.00');
  }
}

extension SatoshiFormatting on int {
  String toFormattedString(String denomination) {
    final money = Money.fromIntWithCurrency(this, AppCurrencies.btc);
    if (denomination == 'sats') {
      // Locale-aware thousand grouping — `12,345,678` in en/US,
      // `12.345.678` in de/PT, `12'345'678` in fr/CH, etc. `intl`'s
      // `NumberFormat.decimalPattern()` consults `Intl.systemLocale`
      // (which we sync to the user's selected language at app boot).
      // Negative balances are unusual on this surface; the formatter
      // handles the sign placement per locale convention.
      final n = money.minorUnits.toInt();
      return NumberFormat.decimalPattern(Intl.getCurrentLocale()).format(n);
    } else {
      return addBtcDecimalSpaces(money.format('0.00000000'));
    }
  }

  String toRawBtcString() {
    final money = Money.fromIntWithCurrency(this, AppCurrencies.btc);
    return money.format('0.00000000');
  }

  double toDoubleValue(String denomination) {
    if (denomination == 'sats') {
      return toDouble();
    } else {
      return this / 100000000.0;
    }
  }
}

String addBtcDecimalSpaces(String btcStr) {
  final dotIndex = btcStr.indexOf('.');
  if (dotIndex == -1) return btcStr;
  final intPart = btcStr.substring(0, dotIndex + 1);
  final decPart = btcStr.substring(dotIndex + 1);
  if (decPart.length <= 2) return btcStr;
  final buffer = StringBuffer(intPart);
  buffer.write(decPart.substring(0, 2));
  for (var i = 2; i < decPart.length; i++) {
    if ((i - 2) % 3 == 0) buffer.write('\u{2009}');
    buffer.write(decPart[i]);
  }
  return buffer.toString();
}
