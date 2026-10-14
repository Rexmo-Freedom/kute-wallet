// "Add $X to Investments" never lies (founder rule: show Add only when the
// TOTAL Investments balance is short, and add exactly what it says). The
// Bitcoin leg converts exactly the X the button names; the rest of the
// order comes from the one-balance planner (Dollars, then the other
// venue's cash, straight into the venue under the order's SAME approval).

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/screens/shared/slip_shortfall.dart'
    show slipDollarsShortfallUsd;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/multi_source_move.dart'
    show MultiSourceMoveStore;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';

const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
final _now = DateTime.utc(2026, 10, 14, 12);

/// Predictions cash that can go straight into the Investing account under
/// the order's approval, as the real rail does: only within the leg caps
/// the approval binds.
class _Predictions implements VenueCashSource, DirectVenueCashSource {
  _Predictions(this.cash);
  double cash;
  final direct = <double>[];
  final home = <double>[];

  @override
  OneBalanceVenue get venue => OneBalanceVenue.predictions;

  @override
  Duration get estimatedArrival => const Duration(minutes: 1);

  @override
  Future<double> availableUsd() async => cash;

  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) async {
    home.add(usd);
    cash -= usd;
    return VenueMoveResult(
        quoteId: 'q_home',
        sentUsd: usd,
        arrivingUsdEstimate:
            venuePullArrives(usd, kVenuePullCost[OneBalanceVenue.predictions]!));
  }

  @override
  bool canPullTo(VenueCashDestination destination) =>
      destination == VenueCashDestination.investing;

  @override
  Future<VenueMoveResult> pullTo(VenueCashDestination destination, double usd,
      {required String purpose, required MoveAuthorization auth}) async {
    final grant = (auth as ApprovedLegAuthorization).grant;
    if (!DirectLegGrants.take(grant,
        venue: venue.name,
        destination: destination.code,
        amount: IntentUnits.usd(usd))) {
      throw const DirectRouteRefused('approval_does_not_cover');
    }
    direct.add(usd);
    cash -= usd;
    return VenueMoveResult(
        quoteId: 'q_direct',
        sentUsd: usd,
        arrivingUsdEstimate:
            venuePullArrives(usd, kVenuePullCost[OneBalanceVenue.predictions]!));
  }
}

void main() {
  setUp(() {
    AuthGrants.clock = () => _now;
    MultiSourceMoveStore.reset();
  });
  tearDown(() => AuthGrants.clock = DateTime.now);

  test("the button's X is the Bitcoin leg's USD target, to the cent", () {
    for (final (fund, have) in [
      (20.0, 13.0),
      (20.03, 12.5),
      (7.77, 0.0),
      (5.3, 4.71), // under the route minimum: the button says $1.00
      (101.234, 3.0),
    ]) {
      final x = BitcoinLegRules.addUsd(fundUsd: fund, investmentsUsd: have);
      final shortfall =
          slipDollarsShortfallUsd(topUpUsd: fund, dollarsUsd: have);
      // The same rounding the Dollars door uses, raised only to the route
      // minimum.
      expect(x, shortfall < 1 ? 1.0 : shortfall, reason: '$fund vs $have');
      final plan = BitcoinLegRules.size(
              dollarsShortUsd: x, usdPerBtc: 60000, availableSats: 100000000)
          .plan!;
      expect(plan.targetUsd, x, reason: '$fund vs $have');
    }
    // Investments cover it: no Add at all.
    expect(BitcoinLegRules.addUsd(fundUsd: 10, investmentsUsd: 10), 0);
  });

  test(
      'an Investing order with cash in Predictions converts only the X shown '
      'and draws the rest from Predictions, under the same approval',
      () async {
    final predictions = _Predictions(10);
    var dollars = 3.0;
    final puller = VenueCashPuller(
      sources: [predictions],
      readDollars: () => dollars,
      minimumUsd: (_) async => 1,
      sleep: (_) async {},
    );
    const fundUsd = 20.0;
    // What the button reads: Dollars plus Predictions' reachable cash.
    final reach = await puller.reachUsd(exclude: OneBalanceVenue.investing);
    expect(reach, greaterThan(dollars));
    expect(reach, lessThan(fundUsd)); // the total is short: "Add" is honest
    final x = BitcoinLegRules.addUsd(fundUsd: fundUsd, investmentsUsd: reach);
    expect(x, slipDollarsShortfallUsd(topUpUsd: fundUsd, dollarsUsd: reach));
    final leg = BitcoinLegRules.size(
            dollarsShortUsd: x, usdPerBtc: 60000, availableSats: 100000000)
        .plan!;
    expect(leg.targetUsd, x);

    // Before the approval: the rest of the order is planned, and the legs
    // straight into Investing are bound into the one approval.
    final other = await planOtherVenueCash(puller,
        venue: OneBalanceVenue.investing,
        fundUsd: fundUsd,
        addUsd: leg.targetUsd,
        dollarsUsd: dollars);
    expect(other.covers, isTrue);
    expect(other.otherUsd, closeTo(fundUsd - dollars - x, 0.011));
    expect(other.directLegs, isNotNull);
    final grant = AuthGrants.issue(
      SensitiveIntent(
        action: SensitiveAction.hlOrder,
        walletId: 'w',
        venue: IntentVenue.hyperliquid,
        destination: 'BTC',
        asset: 'BTC',
        amountMax: IntentUnits.usd(25),
        limits: {
          VenueLimit.directLegs: other.directLegs,
          VenueLimit.fundBtc: BitcoinLegGrants.limit(
              maxSats: leg.maxSats, ownSpark: _ownSpark),
        },
        ttl: AuthGrants.autofireTtl,
      ),
      method: AuthGrantMethod.biometric,
      now: _now,
    );

    // The Bitcoin leg landed exactly X in Dollars.
    dollars += x;
    final queued = <({double fundUsd, double readyUsd, double direct})>[];
    final outcome = await fundRestThenMove(
      puller: puller,
      venue: OneBalanceVenue.investing,
      fundUsd: fundUsd,
      readyUsd: 0,
      needsOtherVenue: other.otherUsd > 0,
      grant: grant,
      queue: ({
        required double fundUsd,
        required double readyUsd,
        required double directArrivingUsd,
        String? moveId,
      }) async {
        queued.add(
            (fundUsd: fundUsd, readyUsd: readyUsd, direct: directArrivingUsd));
        return OrderFundingFunded(VenueMoveResult(
            quoteId: 'q_move', sentUsd: fundUsd, arrivingUsdEstimate: fundUsd));
      },
    );
    expect(outcome, isA<OrderFundingFunded>());
    // Predictions' cash went straight into Investing, under the order's own
    // approval, for the rest of the order only; nothing came home.
    expect(predictions.home, isEmpty);
    expect(predictions.direct, hasLength(1));
    expect(predictions.direct.single, lessThanOrEqualTo(10));
    expect(predictions.direct.single, closeTo(other.otherUsd, 0.5));
    // The move from Dollars is what the direct leg does not bring: the
    // Dollars that were there plus exactly the X the bitcoin added.
    expect(queued, hasLength(1));
    expect(queued.single.fundUsd, lessThanOrEqualTo(dollars + 1e-9));
    expect(queued.single.direct, greaterThan(0));
    expect(queued.single.fundUsd + queued.single.direct,
        closeTo(fundUsd, 0.011));
  });

  test('Dollars and the leg cover it: no other-venue leg at all', () async {
    final predictions = _Predictions(10);
    final puller = VenueCashPuller(
      sources: [predictions],
      readDollars: () => 15,
      minimumUsd: (_) async => 1,
    );
    final other = await planOtherVenueCash(puller,
        venue: OneBalanceVenue.investing,
        fundUsd: 20,
        addUsd: 5,
        dollarsUsd: 15);
    expect(other.otherUsd, 0);
    expect(other.directLegs, isNull);
  });
}
