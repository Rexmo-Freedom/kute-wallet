// lib/services/one_balance/investing_sweep_rules.dart
//
// Investing's own input to the sweeper's idle rule (founder decision,
// October 2026: "abstract + isolated + 24h"). Investing cash STAYS on
// Hyperliquid: closes, cancels, failed orders, TP/SL fills and funding
// leftovers do not send it home. It is part of the one balance's
// Available, and an order, a Dollars send or the other venue draws on it
// when it needs it. The one exception is an idle account: nothing traded,
// no order activity and no position change for `kVenueIdleSweepAfter`
// (sweep_rules.dart, shared with Predictions), with no open position and
// no resting order — then the sweeper brings the cash home under the
// generic rules (dust and minimum aware, the CCTP or direct route as
// before), its trigger named `investing_idle_24h`.
//
// Unlike Predictions, an OPEN POSITION counts as activity here: a sweep
// is only ever for an account at rest. Never cross collateral (a cross
// position's free cash is its margin buffer) and never money a resting
// perp order fills against (Hyperliquid does not lock margin for a
// resting order; it checks at fill and cancels it, `marginCanceled`, when
// the account no longer covers it).
//
// Kept apart from `sweep_rules.dart` so the generic rules and this one
// merge independently. The activity itself is `VenueActivity`
// (venue_activity.dart), the same persisted tracker Predictions uses.

import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_activity.dart';

/// [VenueSnapshot.lastActivityAt] for Investing: now while a position is
/// open (cross or isolated) or an order rests at the venue, else the last
/// recorded Investing activity. With nothing ever recorded (cash first
/// seen under this rule) the window starts now and is recorded, so a
/// restart does not restart it and nothing is swept on a guess.
DateTime investingLastActivity({
  required bool hasOpenPositions,
  required bool hasRestingOrders,
  required DateTime now,
}) {
  if (hasOpenPositions || hasRestingOrders) {
    VenueActivity.note(OneBalanceVenue.investing);
    return now;
  }
  final last = VenueActivity.last(OneBalanceVenue.investing);
  if (last != null) return last;
  VenueActivity.note(OneBalanceVenue.investing);
  return VenueActivity.last(OneBalanceVenue.investing) ?? now;
}
