// Investment amounts always follow the selected fiat currency. Bitcoin
// comparisons are performance metrics, never an alternative balance mode.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';

String _format(WidgetRef ref, double usd, int digits, bool read) {
  final currency = read
      ? ref.read(settingsProvider).currency
      : ref.watch(settingsProvider).currency;
  final rate = currency == 'USD'
      ? 1.0
      : (read
          ? ref.read(selectedCurrencyProviderFromUSD(currency)).toDouble()
          : ref.watch(selectedCurrencyProviderFromUSD(currency)).toDouble());
  final valid = rate.isFinite && rate > 0;
  return NumberFormat.simpleCurrency(
          name: valid ? currency : 'USD', decimalDigits: digits)
      .format(usd * (valid ? rate : 1));
}

String formatPolyAmount(WidgetRef ref, double usdAmount,
        {int decimalDigits = 2}) =>
    _format(ref, usdAmount, decimalDigits, false);
String formatPolyFiatForced(WidgetRef ref, double usdAmount,
        {int decimalDigits = 2}) =>
    formatPolyAmount(ref, usdAmount, decimalDigits: decimalDigits);

String polyDisplayLabel(WidgetRef ref) =>
    NumberFormat.simpleCurrency(name: ref.read(settingsProvider).currency)
        .currencySymbol;
