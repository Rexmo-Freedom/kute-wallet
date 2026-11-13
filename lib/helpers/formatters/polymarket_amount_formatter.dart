// Dollars money is shown in dollars (founder, 8 November 2026: "keep it in
// dollars"): the Dollars home and its tabs, the Portfolio, Investing and
// Predictions, every slip and every activity row of that money. The Settings
// currency never touches it, here or in a typed amount: "10" on a slip is
// $10, and $10 is what reaches the venue. Only Bitcoin's own conversion line
// follows Settings (conversionToFiatProvider).
import 'package:intl/intl.dart';

/// [usdAmount] as dollars, whatever the Settings currency. No rate applies.
String formatDollars(double usdAmount, {int decimalDigits = 2}) =>
    NumberFormat.simpleCurrency(name: 'USD', decimalDigits: decimalDigits)
        .format(usdAmount);
