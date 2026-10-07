// Shared probability formatters used across the Predictions surfaces
// (cards, detail, board, bet slip, portfolio, Builder, charts). One
// implementation, so every surface writes the same chance the same way.
//
// All Polymarket prices render as PERCENT, never cents. Polymarket
// itself uses ¢ on web because share prices are literally $0.65
// USDC, but the cent framing is unfamiliar to non-crypto users and
// reads as a currency unit (which it isn't here — Kute hides the
// USDC layer entirely). Percent reads as "probability of this
// outcome resolving true" which is what users actually want to know.
//
// A CHANCE ([formatPolyChance]) is written with one decimal at most and
// no trailing ".0": "93.5%", "62%". Under 1% it reads "<1%" and over 99%
// ">99%"; a flat "0%" / "100%" is kept for a settled price only, so a
// 99.55% YES never reads as a certain "100%". The two sides of a
// two-outcome market are written off ONE price ([formatPolyChancePair]):
// the second is what the first one's written figure leaves of 100, so the
// pair always adds up.
//
// Where the figure is read against a scale or is the price about to be
// paid (the chart's tags and crosshair, the bet slip's sides), `fineEnds`
// keeps two decimals under 1% and over 99% ("0.45%", "99.55%"): "<1%"
// there would hide a long shot's whole movement.
//
// A PRICE an order rests at ([formatPolyCents]: limit price, open order
// rows) keeps up to three decimals, because that figure is traded on.

/// The written figure for [price], in hundredths of a percent: 0 and
/// 10000 only for a settled price, a multiple of ten (one decimal) from
/// 1% to 99%, and to the hundredth outside that.
int _chanceHundredths(double price) {
  if (!price.isFinite || price <= 0) return 0;
  if (price >= 1) return 10000;
  final pct = price * 100;
  if (pct < 1 || pct > 99) {
    // Rounding never claims a certainty the price does not have.
    return (pct * 100).round().clamp(1, 9999);
  }
  return (pct * 10).round() * 10;
}

String _chanceFigure(int h, bool fineEnds) {
  if (h <= 0) return '0';
  if (h >= 10000) return '100';
  if (!fineEnds) {
    if (h < 100) return '<1';
    if (h > 9900) return '>99';
  }
  var s = (h / 100).toStringAsFixed(h < 100 || h > 9900 ? 2 : 1);
  s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return s;
}

/// A 0..1 chance as every Predictions surface writes it, without the
/// percent sign ("93.5", "62", "<1", ">99"), for copy that carries its
/// own ("{percent}% chance").
String formatPolyChanceFigure(double price, {bool fineEnds = false}) =>
    _chanceFigure(_chanceHundredths(price), fineEnds);

/// A 0..1 chance as every Predictions surface writes it: one decimal at
/// most, no trailing ".0" ("93.5%", "62%"), "<1%" and ">99%" at the two
/// ends and a flat "0%" / "100%" for a settled price only. [fineEnds]
/// keeps two decimals under 1% and over 99% instead ("0.45%", "99.55%").
String formatPolyChance(double price, {bool fineEnds = false}) =>
    '${formatPolyChanceFigure(price, fineEnds: fineEnds)}%';

/// The two sides of a two-outcome market off the one [price] of the
/// first: the second is what the first's written figure leaves of 100
/// ("62.4%" and "37.6%", "<1%" and ">99%"), so the two always add up.
({String first, String second}) formatPolyChancePair(double price,
    {bool fineEnds = false}) {
  final h = _chanceHundredths(price);
  return (
    first: '${_chanceFigure(h, fineEnds)}%',
    second: '${_chanceFigure(10000 - h, fineEnds)}%',
  );
}

/// A move in chance over a span, in points with its sign: one decimal at
/// most and no trailing ".0" ("+25.9", "−4"); whole points with
/// [whole] (the day's move on a card). Null when it rounds to nothing.
String? formatPolyChanceMove(double? move, {bool whole = false}) {
  if (move == null || !move.isFinite) return null;
  final tenths = whole ? (move * 100).round() * 10 : (move * 1000).round();
  if (tenths == 0) return null;
  return '${tenths > 0 ? '+' : '−'}${formatPolyPoints(tenths.abs() / 10)}';
}

/// A count of percentage points, unsigned: one decimal at most and no
/// trailing ".0" ("4", "25.9").
String formatPolyPoints(double points) {
  final s = points.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// A 0..1 PRICE an order rests at or is placed at, as a percent with up
/// to three decimals, trailing zeros trimmed ("39.5%", "0.45%"). Only for
/// the figures an order is traded on (limit price, open order rows);
/// a chance is written with [formatPolyChance].
String formatPolyCents(double price) {
  // Exact extremes only — a settled market at literally 1.0 / 0.0.
  if (price >= 1.0) return '100%';
  if (price <= 0.0) return '0%';
  final pct = price * 100;
  // Up to 3 decimals, then trim any trailing zeros (and a dangling dot) so
  // "50.000" → "50", "99.550" → "99.55", "0.450" → "0.45".
  var s = pct.toStringAsFixed(3);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
  return '$s%';
}
