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

/// What [HyperliquidVenueFunder.sizeFunding] decided: send [fundUsd],
/// [arrivingUsd] lands (the live estimate at that amount).
class FundingSize {
  const FundingSize({
    required this.fundUsd,
    required this.arrivingUsd,
    required this.minUsd,
  });

  final double fundUsd;
  final double arrivingUsd;

  /// The rail's minimum at the time of the estimate.
  final double minUsd;

  /// What leaves Dollars less what arrives, to the cent.
  double get costUsd {
    final c = fundUsd - arrivingUsd;
    return c.isFinite && c > 0 ? ((c * 100) - 1e-9).ceilToDouble() / 100 : 0;
  }

  /// Whether what arrives covers [neededUsd].
  bool covers(double neededUsd) => arrivingUsd + 1e-6 >= neededUsd;

  @override
  String toString() =>
      'FundingSize(fund: $fundUsd, arriving: $arrivingUsd, min: $minUsd)';
}

class HyperliquidVenueFunder implements VenueFunder {
  HyperliquidVenueFunder(this._rail);

  final HyperliquidMoveRail _rail;

  /// A deposit rate the quote cannot be believed above (the quote guard
  /// refuses anything over 4%; this only keeps the gross-up finite).
  static const double _maxProportionalFee = 0.5;

  /// The most of a move the quote guard lets a declared fee take (400
  /// bps, `OrchestraQuoteBounds.maxFeeBps`): anything a quote keeps
  /// beyond this share is the route's flat cost.
  static const double _maxProportionalRate = 0.04;

  /// How many times [sizeFunding] re-prices its answer before it gives up.
  static const int _sizeRounds = 3;

  /// The ONE sizing of an order's funding on what ARRIVES: what to send
  /// from Dollars so that at least [neededUsd] lands at the venue, read
  /// from the funder's live estimates (flat cost, proportional fee and
  /// the one-time activation of an account Hyperliquid has never seen,
  /// all inside what the estimate says arrives). The first estimate is
  /// priced for [neededUsd] itself; the answer is then priced again at
  /// the amount it would send and topped up by any gap, up to
  /// [_sizeRounds] times. [FundingSize.covers] is false when even that
  /// does not land [neededUsd] (the rail's maximum, a quote that keeps
  /// moving): the caller refuses before anything is approved.
  static Future<FundingSize> sizeFunding(
    VenueFunder funder, {
    required double neededUsd,
  }) async {
    if (!neededUsd.isFinite || neededUsd <= 0) {
      return const FundingSize(fundUsd: 0, arrivingUsd: 0, minUsd: 0);
    }
    final first = await funder.estimate(neededUsd);
    var fund = fundUsdFor(shortfallUsd: neededUsd, quote: first);
    var quote = first;
    for (var round = 0; round < _sizeRounds; round++) {
      quote = await funder.estimate(fund);
      final arriving = quote.arrivingUsd.isFinite ? quote.arrivingUsd : 0.0;
      if (arriving + 1e-6 >= neededUsd) {
        return FundingSize(
            fundUsd: fund, arrivingUsd: arriving, minUsd: quote.minUsd);
      }
      final max = quote.maxUsd.isFinite && quote.maxUsd > 0
          ? quote.maxUsd
          : double.infinity;
      if (fund + 1e-9 >= max) break;
      final next = math.min(max, _ceilCents(fund + (neededUsd - arriving)));
      if (next <= fund) break;
      fund = next;
    }
    return FundingSize(
        fundUsd: fund,
        arrivingUsd: quote.arrivingUsd.isFinite ? quote.arrivingUsd : 0,
        minUsd: quote.minUsd);
  }

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
      // A venue-cash leg is never a deposit from Dollars.
      ApprovedLegAuthorization() =>
        throw const RouteUnavailable('a venue leg never funds from Dollars'),
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
    var fixed = quote.fixedCostUsd.isFinite && quote.fixedCostUsd > 0
        ? quote.fixedCostUsd
        : 0.0;
    // The whole cost of the move as the quote prices it: what it says
    // arrives against the amount it was asked for, or its declared fee,
    // whichever is larger. The HyperCore route's cost is close to flat
    // (about $1.24, plus the one-time activation an account Hyperliquid
    // has never seen pays, which Orchestra prices in when the quote
    // names the account): a rate read off it would under-send small
    // moves and over-send large ones.
    final declared =
        quote.feeUsd.isFinite && quote.feeUsd > 0 ? quote.feeUsd : 0.0;
    final implied = quote.arrivingUsd.isFinite && quote.arrivingUsd > 0
        ? shortfallUsd - quote.arrivingUsd
        : 0.0;
    final total = math.max(declared, implied);
    // A proportional fee is capped by the quote guard
    // ([_maxProportionalRate]); whatever the quote charges beyond that
    // share is flat and is added once, not grossed up.
    var proportional = math.max(0.0, total - fixed);
    final cap = shortfallUsd * _maxProportionalRate;
    if (proportional > cap) {
      fixed += proportional - cap;
      proportional = cap;
    }
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
