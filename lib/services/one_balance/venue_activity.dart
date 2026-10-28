// lib/services/one_balance/venue_activity.dart
//
// When the person last did something at a venue: placed, sold, cancelled
// or claimed (an attempt counts, filled or not), or funded a bet there.
// Persisted in the settings box, so a restart keeps it.
//
// Predictions cash is abstracted like Investing's (founder, 2026-10): it
// stays on the venue after fills, failed or abandoned bets, sells, claims
// and funding leftovers, counted as available, and goes home to Dollars
// only after 24 hours with no activity and no open orders
// (`decideSweep`), or when another action pulls it.

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_ce/hive.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';

abstract final class VenueActivity {
  /// Test seam: the clock activity is stamped with.
  static DateTime Function() clock = DateTime.now;

  /// The settings-box key for [venue]'s last activity.
  static String keyFor(OneBalanceVenue venue) =>
      'venue_last_activity_v1:${venue.name}';

  static final Map<OneBalanceVenue, DateTime> _held = {};

  @visibleForTesting
  static void reset() => _held.clear();

  /// Something happened at [venue] now.
  static void note(OneBalanceVenue venue) {
    final at = clock();
    _held[venue] = at;
    try {
      if (Hive.isBoxOpen('settings')) {
        Hive.box('settings').put(keyFor(venue), at.millisecondsSinceEpoch);
      }
    } catch (_) {/* best-effort: this session still holds it */}
  }

  /// When something last happened at [venue], or null when nothing is
  /// known (cash from before this rule counts as long idle).
  static DateTime? last(OneBalanceVenue venue) {
    final held = _held[venue];
    if (held != null) return held;
    try {
      if (!Hive.isBoxOpen('settings')) return null;
      final ms = Hive.box('settings').get(keyFor(venue));
      if (ms is! int) return null;
      return _held[venue] = DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }
}
