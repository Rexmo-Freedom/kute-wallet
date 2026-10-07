// lib/screens/shared/charts/kute_chart_format.dart
//
// How every chart writes a time and a change: the scrub card's date in
// the app's language ("Oct 5, 2026", "5 de out. de 2026"), its time of
// day on an intraday chart ("Oct 5 14:30"), and the signed change from
// the start of the window on screen ("+$12.30 (+1.2%)"). Figures keep
// the one number format the app writes money and prices in (a point for
// decimals, a comma for thousands), so a change never reads "$278.97
// (+44,8%)". One place, so the balance charts and the venue charts never
// drift apart in format again.

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// The locale the chart's dates are written in: the app's, when its date
/// names are loaded (they are once the app's localizations are), else
/// null (intl's default, English).
String? kuteChartLocale(BuildContext context) {
  final locale = Localizations.maybeLocaleOf(context);
  if (locale == null) return null;
  final name = Intl.canonicalizedLocale(locale.toString());
  if (DateFormat.localeExists(name)) return name;
  if (DateFormat.localeExists(locale.languageCode)) return locale.languageCode;
  return null;
}

/// A day on a daily chart: "Oct 5, 2026", "5 de out. de 2026".
String kuteChartDay(DateTime t, String? locale) =>
    DateFormat.yMMMd(locale).format(t);

/// A moment on an intraday chart: "Oct 5 14:30", "5 de out. 14:30".
String kuteChartDayTime(DateTime t, String? locale) =>
    DateFormat.MMMd(locale).add_Hm().format(t);

/// The time of day alone: "14:30".
String kuteChartClock(DateTime t, String? locale) =>
    DateFormat.Hm(locale).format(t);

/// The sign a change is written with: a plus for a rise, the minus sign
/// for a fall (the one the P&L figures use), nothing for no change.
String kuteChangeSign(double delta) =>
    delta > 0 ? '+' : (delta < 0 ? '−' : '');

/// A signed percent with one decimal, in the app's number format:
/// "+1.2%", "−1,234.5%". A change that rounds to nothing is written
/// "0.0%", never "−0.0%".
String kuteSignedPercent(double percent) {
  final tenths = (percent * 10).round();
  final magnitude = NumberFormat('#,##0.0', 'en_US').format(tenths.abs() / 10);
  return '${kuteChangeSign(tenths.toDouble())}$magnitude%';
}

/// Which way a percent change reads once written with one decimal: 1 up,
/// -1 down, 0 when it rounds to nothing.
int kutePercentDirection(double percent) => (percent * 10).round().sign;

/// The change of a value from the start of the window on screen, as the
/// scrub card writes it: the amount when [magnitude] can write one
/// ("+$12.30"), then the percent of [base] when that means something
/// ("+$12.30 (+1.2%)"). With no amount writer it is the percent alone;
/// with neither (a base of zero) it is null.
String? kuteChangeText({
  required double delta,
  required double base,
  String Function(double magnitude)? magnitude,
  bool percent = true,
}) {
  final amount =
      magnitude == null ? null : '${kuteChangeSign(delta)}${magnitude(delta.abs())}';
  final pct = percent && base != 0 && base.isFinite
      ? kuteSignedPercent(delta / base.abs() * 100)
      : null;
  if (amount != null && pct != null) return '$amount ($pct)';
  return amount ?? pct;
}
