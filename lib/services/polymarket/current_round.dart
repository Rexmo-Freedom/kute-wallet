// lib/services/polymarket/current_round.dart
//
// The round in play of a crypto Up-or-Down series (founder, 23 October
// 2026). A funded bet on a short round can land after the round ended, or
// with the price past what was approved: nothing is placed and the money
// stays as Predictions cash. The slip's Retry then opens the series' round
// in play now, with the same side and stake, for the person to confirm:
// a new round is a new market (its own condition and tokens, a new slug
// every window), so it is resolved from the series, never from the old
// market's id, and never placed by itself.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/polymarket_model.dart'
    show Btc5MinEvent, PolymarketModel;
import 'package:kute/services/polymarket/crypto_round.dart'
    show polyCryptoRoundOf;

/// Reads one window of a series: [asset] as the slug writes it (`btc`),
/// the window's start (UTC seconds, aligned to [minutes]). Null when
/// Polymarket has no such event.
typedef PolyRoundWindowReader = Future<Btc5MinEvent?> Function(
    String asset, int windowStartEpoch, int minutes);

/// Gamma's own event for one window (`<asset>-updown-<minutes>m-<epoch>`).
final polyRoundWindowReaderProvider = Provider<PolyRoundWindowReader>(
  (ref) => (asset, windowStartEpoch, minutes) async {
    final model = PolymarketModel();
    try {
      return await model.getCryptoUpdown5MinEvent(asset,
          targetWindowEpoch: windowStartEpoch, minutes: minutes);
    } finally {
      model.dispose();
    }
  },
);

/// The series of the round [eventSlug] names, when it is one whose every
/// window has its own slug (`btc-updown-5m-1791152100`, 5 or 15 minutes):
/// the asset and the window's length in minutes. Null otherwise (an
/// hourly round, a daily market, anything else).
({String asset, int minutes})? polyRoundSeriesOf(String? eventSlug) {
  if (eventSlug == null || eventSlug.isEmpty) return null;
  final round = polyCryptoRoundOf(eventSlug);
  if (round == null) return null;
  final minutes = round.window.inMinutes;
  if (minutes <= 0 || minutes >= 60) return null;
  return (asset: round.asset, minutes: minutes);
}

/// The round of [eventSlug]'s series in play at [now]: the window that
/// holds [now], else the next one (Polymarket lists a window shortly
/// before it opens). Only an event taking orders with both sides' tokens
/// counts, and never the round [eventSlug] itself. Null when the series
/// is not one ([polyRoundSeriesOf]) or nothing answers.
Future<Btc5MinEvent?> resolveCurrentPolyRound(
  PolyRoundWindowReader read,
  String? eventSlug, {
  DateTime? now,
}) async {
  final series = polyRoundSeriesOf(eventSlug);
  if (series == null) return null;
  final at = (now ?? DateTime.now()).toUtc();
  final span = series.minutes * 60;
  final epoch = at.millisecondsSinceEpoch ~/ 1000;
  final current = (epoch ~/ span) * span;
  final original = eventSlug!.trim().toLowerCase();
  for (final start in [current, current + span]) {
    final slug = '${series.asset}-updown-${series.minutes}m-$start';
    if (slug == original) continue;
    Btc5MinEvent? event;
    try {
      event = await read(series.asset, start, series.minutes);
    } catch (_) {
      event = null;
    }
    if (event == null || event.closed || !event.active) continue;
    if (event.slug.trim().toLowerCase() == original) continue;
    final end = event.endDate;
    if (end != null && !end.isAfter(at)) continue;
    final up = event.upTokenId;
    final down = event.downTokenId;
    if (up == null || up.isEmpty || down == null || down.isEmpty) continue;
    return event;
  }
  return null;
}
