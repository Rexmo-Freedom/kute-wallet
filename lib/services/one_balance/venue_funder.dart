// lib/services/one_balance/venue_funder.dart
//
// The contract a venue offers the one-balance layer: "put dollars in me,
// tell me what is idle, tell me what a move costs". Each venue binds it
// to its own rail (Orchestra for Predictions, the HyperCore rail for
// Investing); the order-funding controller and the sweeper only ever
// talk to this interface, so a rail change never reaches them.
//
// P0 ships the types only. The venue implementations follow.

import 'package:kute/helpers/auth_grant.dart' show AuthGrant;

/// What a move of a given size would do, before it is committed to.
class VenueMoveQuote {
  const VenueMoveQuote({
    required this.arrivingUsd,
    required this.feeUsd,
    required this.fixedCostUsd,
    required this.minUsd,
    required this.maxUsd,
  });

  /// What lands at the venue after every cost.
  final double arrivingUsd;

  /// The proportional part of the cost (provider commission, spread).
  final double feeUsd;

  /// The flat part (network/gas), paid whatever the size.
  final double fixedCostUsd;

  /// Smallest and largest move the rail accepts right now, in dollars.
  final double minUsd;
  final double maxUsd;

  @override
  String toString() => 'VenueMoveQuote(arriving: $arrivingUsd, '
      'fee: $feeUsd, fixed: $fixedCostUsd, min: $minUsd, max: $maxUsd)';
}

/// A move the rail has accepted and sent.
class VenueMoveResult {
  const VenueMoveResult({
    required this.quoteId,
    required this.sentUsd,
    required this.arrivingUsdEstimate,
    this.orderId,
    this.registration,
    this.operationId,
  });

  /// The settlement operation that carries the move, when the rail has
  /// one: its Activity rows carry the same id.
  final String? operationId;

  /// The provider quote the send was made against.
  final String quoteId;

  /// The provider order id, or null while registration is still pending.
  final String? orderId;

  /// Set when the rail registered the order in the background: completes
  /// with the order id, or null when it is left to the reconciler. Never
  /// throws.
  final Future<String?>? registration;

  /// What left Dollars.
  final double sentUsd;

  /// What the quote said would arrive.
  final double arrivingUsdEstimate;

  bool get registered => orderId != null;
}

/// Who approved a move. The rail checks the authorization against the
/// verified quote before any funds leave.
sealed class MoveAuthorization {
  const MoveAuthorization();
}

/// The user approved this move through a fresh step-up grant.
final class UserGrantAuthorization extends MoveAuthorization {
  const UserGrantAuthorization(this.grant);

  final AuthGrant grant;
}

/// No user tap: the move was started by the app itself.
///
/// Accepted only when the verified quote's recipient is the wallet's own
/// Spark address and the session is unlocked — the same trust level as
/// auto-claim. Money can only ever come home under it; a rail asked to
/// send anywhere else under a sweep must refuse.
final class SweepAuthorization extends MoveAuthorization {
  const SweepAuthorization._();

  static const SweepAuthorization automatic = SweepAuthorization._();
}

/// A venue's door for the one-balance layer.
abstract interface class VenueFunder {
  /// Moves [usd] from Dollars into the venue. [purpose] is recorded with
  /// the move (`order_funding`, `top_up`, …) so Activity and analytics
  /// can say why it happened.
  Future<VenueMoveResult> fund({
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'order_funding',
  });

  /// Venue cash not committed to anything: what a sweep could bring home.
  Future<double> idleUsd();

  /// Smallest move the venue's rail accepts right now.
  Future<double> minimumUsd();

  /// What moving [usd] in would cost and deliver, without committing.
  Future<VenueMoveQuote> estimate(double usd);
}

/// The rail cannot carry this move right now (paused, unfunded, no
/// route for the asset). Nothing has left Dollars when this is thrown.
class RouteUnavailable implements Exception {
  const RouteUnavailable([this.reason]);

  final String? reason;

  @override
  String toString() =>
      reason == null ? 'RouteUnavailable' : 'RouteUnavailable: $reason';
}

/// A move straight to its final destination (venue cash → Bitcoin, the
/// other venue) was refused before anything moved: the route or its fee
/// terms are not offered, a gate is shut, an own address could not be
/// read. The caller goes through Dollars instead.
class DirectRouteRefused extends RouteUnavailable {
  const DirectRouteRefused([super.reason]);

  @override
  String toString() => 'DirectRouteRefused: $reason';
}

/// Where an action's money is going when venue cash is pulled for it:
/// Dollars (a send, the rest of an order's funding), the wallet's own
/// Bitcoin, or one of the venues. A leg goes straight there when the
/// venue's rail offers the route, through Dollars otherwise.
enum VenueCashDestination {
  dollars,
  bitcoin,
  predictions,
  investing;

  /// Analytics value.
  String get code => name;
}

/// A venue whose cash can go straight to a destination other than
/// Dollars, without a tap: only ever to one of the wallet's own accounts.
abstract interface class DirectSweepableVenueFunder {
  /// Sends [usd] of venue cash straight to [destination]. Throws
  /// [DirectRouteRefused] when the route was refused before anything
  /// moved; anything else may have moved and is rethrown untouched.
  Future<VenueMoveResult> sweepTo({
    required VenueCashDestination destination,
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'cash_pull',
  });
}
