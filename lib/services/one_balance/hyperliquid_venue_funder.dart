// lib/services/one_balance/hyperliquid_venue_funder.dart
//
// Investing's door for the one-balance layer: `VenueFunder` over the
// `HyperliquidMoveRail`. The order-funding controller and the sweeper
// talk to this; which rail carries the move (HyperCore via Orchestra) is
// the rail provider's business.
//
// A deposit here is always an ORDER's: the user approved the order once,
// and that grant (the autofire grant the slip stores, extended with the
// dollars allowed to leave for it) is what the rail's step-up hook
// checks before any funds move. A sweep never deposits.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/auth_grant.dart' show AuthGrant, AuthGrants;
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementAuthorizationIntent;
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/venue_funder.dart';

/// Limit key on an order grant: the most that may leave the spending
/// account to fund it, in the dollar token's six-decimal base units. An
/// order approved without it funds nothing.
const String kFundUsdLimit = 'fundUsd';

/// Limit key on an order grant: the venue the funding goes to.
const String kFundVenueLimit = 'fundVenue';

/// [kFundVenueLimit]'s value for Investing.
const String kFundVenueInvesting = 'investing';

/// The dollar token's six-decimal base units for [usd]. Zero for a figure
/// that is not a finite positive number.
BigInt dollarsBaseUnits(double usd) =>
    usd.isFinite && usd > 0 ? BigInt.from((usd * 1e6).round()) : BigInt.zero;

class HyperliquidVenueFunder implements VenueFunder {
  HyperliquidVenueFunder(this._rail);

  final HyperliquidMoveRail _rail;

  /// A deposit rate the quote cannot be believed above (the quote guard
  /// refuses anything over 4%; this only keeps the gross-up finite).
  static const double _maxProportionalFee = 0.5;

  @override
  Future<VenueMoveResult> fund({
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'order_funding',
  }) async {
    final grant = switch (auth) {
      UserGrantAuthorization(:final grant) => grant,
      // Money only ever comes home on its own; a sweep never deposits.
      SweepAuthorization() =>
        throw const RouteUnavailable('a sweep never funds a venue'),
    };
    final units = dollarsBaseUnits(usd);
    if (units <= BigInt.zero) {
      throw ArgumentError.value(usd, 'usd', 'not a positive amount');
    }
    await _rail.ensureGasFloat();
    return _rail.depositDollars(
      usd: usd,
      amountBaseUnits: units,
      purpose: purpose,
      stepUp: (settlement) async => grantCoversMove(grant, settlement),
    );
  }

  @override
  Future<double> idleUsd() => _rail.withdrawableUsd();

  @override
  Future<double> minimumUsd() => _rail.minimumUsd(deposit: true);

  /// The rail's quote with the flat cost folded into [VenueMoveQuote.feeUsd],
  /// so a reader of the fee sees the whole cost of the move.
  /// [VenueMoveQuote.arrivingUsd] is
  /// the rail's own figure, already net of everything, and
  /// [VenueMoveQuote.fixedCostUsd] stays for anyone who needs the split.
  @override
  Future<VenueMoveQuote> estimate(double usd) async {
    final q = await _rail.estimate(usd: usd, deposit: true);
    final fixed = q.fixedCostUsd.isFinite && q.fixedCostUsd > 0
        ? q.fixedCostUsd
        : 0.0;
    final fee = q.feeUsd.isFinite && q.feeUsd > 0 ? q.feeUsd : 0.0;
    return VenueMoveQuote(
      arrivingUsd: q.arrivingUsd,
      feeUsd: fee + fixed,
      fixedCostUsd: fixed,
      minUsd: q.minUsd,
      maxUsd: q.maxUsd,
    );
  }

  /// Fires once per move the venue has credited (the rail's own stream).
  Stream<void> get credited => _rail.credited;

  /// What to send so that at least [shortfallUsd] arrives, from [quote],
  /// an [estimate] priced for [shortfallUsd]: the flat cost added, then
  /// the whole grossed up by the proportional rate, rounded up to the
  /// cent, never under the rail's minimum. Capped at the rail's maximum,
  /// where a market order resizes to what arrives.
  ///
  /// Shortfall $19.00 on a 0.1% route with a $1 flat cost: $20.02.
  static double fundUsdFor({
    required double shortfallUsd,
    required VenueMoveQuote quote,
  }) {
    if (!shortfallUsd.isFinite || shortfallUsd <= 0) return 0;
    final fixed = quote.fixedCostUsd.isFinite && quote.fixedCostUsd > 0
        ? quote.fixedCostUsd
        : 0.0;
    final total = quote.feeUsd.isFinite && quote.feeUsd > 0 ? quote.feeUsd : 0.0;
    final proportional = math.max(0.0, total - fixed);
    var rate = proportional / shortfallUsd;
    if (!rate.isFinite || rate < 0) rate = 0;
    if (rate > _maxProportionalFee) rate = _maxProportionalFee;
    var usd = _ceilCents((shortfallUsd + fixed) / (1 - rate));
    final min = quote.minUsd.isFinite && quote.minUsd > 0 ? quote.minUsd : 0.0;
    if (usd < min) usd = _ceilCents(min);
    if (quote.maxUsd.isFinite && quote.maxUsd > 0 && usd > quote.maxUsd) {
      usd = (quote.maxUsd * 100).floorToDouble() / 100;
    }
    return usd;
  }

  /// Whether the order grant [grant] covers the move the rail is about to
  /// make: live, for the same wallet, approved to fund Investing, and for
  /// at least the amount the settlement sends. The grant is not consumed
  /// here; the order consumes it when it is placed.
  static bool grantCoversMove(
    AuthGrant grant,
    SettlementAuthorizationIntent settlement, {
    DateTime? now,
  }) {
    if (grant.consumed || grant.revoked) return false;
    if (grant.isExpiredAt(now ?? AuthGrants.clock())) return false;
    if (grant.walletId != settlement.walletId) return false;
    final bound = grant.boundIntent;
    if (bound.limits[kFundVenueLimit] != kFundVenueInvesting) return false;
    final approved = switch (bound.limits[kFundUsdLimit]) {
      BigInt v => v,
      int v => BigInt.from(v),
      _ => null,
    };
    if (approved == null || approved <= BigInt.zero) return false;
    if (settlement.amountIn <= BigInt.zero) return false;
    return settlement.amountIn <= approved;
  }

  static double _ceilCents(double usd) =>
      ((usd * 100) - 1e-9).ceilToDouble() / 100;
}

/// Investing's funder, over whatever rail [hyperliquidMoveRailProvider]
/// binds.
final hyperliquidVenueFunderProvider = Provider<VenueFunder>(
    (ref) => HyperliquidVenueFunder(ref.watch(hyperliquidMoveRailProvider)));
