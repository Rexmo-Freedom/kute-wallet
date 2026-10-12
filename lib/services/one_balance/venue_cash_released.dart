// lib/services/one_balance/venue_cash_released.dart
//
// "Cash just became idle at a venue." Fired by whatever freed it (a
// position closed, a market resolved, an order cancelled) so the sweeper
// can bring it home at once instead of waiting for its next pass. A
// static broadcast so callers deep in a venue service need no ref.

import 'dart:async';

import 'package:kute/services/one_balance/one_balance_state.dart';

class VenueCashReleased {
  VenueCashReleased._();

  static final StreamController<(OneBalanceVenue, String reason)> _controller =
      StreamController<(OneBalanceVenue, String reason)>.broadcast();

  /// Every release, as (venue, reason). [reason] is a short machine
  /// label (`position_closed`, `market_resolved`, `order_cancelled`)
  /// the sweeper records with the move it makes.
  static Stream<(OneBalanceVenue, String reason)> get stream =>
      _controller.stream;

  static void emit(OneBalanceVenue venue, String reason) {
    _controller.add((venue, reason));
  }
}
