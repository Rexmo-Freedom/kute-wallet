// lib/screens/polymarket/components/round_window_label.dart
//
// A 5-minute crypto window's name as the person reads it: "BTC up or down
// · 7:20–7:25", in the app's language and the phone's time zone, on the
// slip, the receipt and the position, so nobody thinks they bought the
// window on the card when the buttons had already rolled to the next one
// (crypto_next_round.dart). Gamma's own title ("Bitcoin Up or Down -
// November 8, 8:35AM-8:40AM ET") stays the market's question everywhere
// the logic and the analytics read it; a row cuts it to "Bitcoin Up or
// Down", which names no window at all. The range never breaks across two
// lines: word joiners hold its en dash to both clocks, in every language,
// and a clock's own space (Bulgarian's "12:00 ч.") does not break, so a long
// name wraps before the range as a whole.

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/services/polymarket/crypto_round.dart';

/// A window's clock time: 24-hour where the locale or the phone reads 24
/// hours ("19:20"), else without its AM or PM ("7:20"): a window is five
/// minutes long and in plain sight of now.
String polyRoundClock(DateTime at,
    {required String locale, bool use24h = false}) {
  final local = at.toLocal();
  final hm = DateFormat.Hm(locale);
  if (use24h) return hm.format(local);
  final isTwelve = (DateFormat.jm(locale).pattern ?? '').contains('a');
  return isTwelve ? DateFormat('h:mm', locale).format(local) : hm.format(local);
}

/// Holds the clocks to the en dash between them. Invisible, and no line
/// breaks at it.
const String kPolyRoundRangeJoin = '\u2060';

/// The name of the 5-minute window with this [slug]; null for anything
/// else.
String? polyRoundWindowName(AppLocalizations l10n, String? slug,
    {bool use24h = false}) {
  if (!polyIsCryptoUpDown5m(slug)) return null;
  final round = polyCryptoRoundOf(slug!)!;
  String clock(DateTime t) =>
      polyRoundClock(t, locale: l10n.localeName, use24h: use24h)
          .replaceAll(' ', '\u00A0');
  return l10n.predictRoundWindow(
      round.asset.toUpperCase(),
      '${clock(round.start)}$kPolyRoundRangeJoin',
      '$kPolyRoundRangeJoin${clock(round.end)}');
}

/// [polyRoundWindowName] with this screen's language and clock.
String? polyRoundWindowNameOf(BuildContext context, String? slug) =>
    polyRoundWindowName(context.l10n, slug,
        use24h: MediaQuery.maybeAlwaysUse24HourFormatOf(context) ?? false);

/// What a screen titles a market by: the window's name for a 5-minute
/// round, else the market's own [question].
String polyShownQuestion(
        BuildContext context, String question, String? slug) =>
    polyRoundWindowNameOf(context, slug) ?? question;
