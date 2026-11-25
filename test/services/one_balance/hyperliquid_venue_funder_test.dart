// Investing's VenueFunder over the move rail: a deposit rides the rail
// under the order's own grant, a sweep never deposits, the flat cost is
// folded into the fee, and the rail's credit stream reaches the caller.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/models/settlement_operation.dart' show SettlementFlow;
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementAuthorizationIntent;
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/hyperliquid_venue_funder.dart';
import 'package:kute/services/one_balance/venue_funder.dart';

import '../../helpers/fake_hyperliquid_move_rail.dart';

SensitiveIntent _orderIntent({BigInt? fundUsd, String? fundVenue}) =>
    SensitiveIntent(
      action: SensitiveAction.hlOrder,
      walletId: 'w1',
      venue: 'hyperliquid',
      destination: 'BTC',
      asset: 'BTC',
      amountMax: BigInt.from(20000000),
      limits: {
        'side': 'long',
        if (fundUsd != null) kFundUsdLimit: fundUsd,
        if (fundVenue != null) kFundVenueLimit: fundVenue,
      },
    );

SettlementAuthorizationIntent _settlement(BigInt amountIn,
        {String walletId = 'w1'}) =>
    SettlementAuthorizationIntent(
      flow: SettlementFlow.sparkToInvestingDirect,
      walletId: walletId,
      destination: '0xabc|v1',
      routeLabel: 'spark:USDB->hypercore:USDC',
      amountIn: amountIn,
      minReceive: amountIn,
      maxFeeBps: 100,
    );

void main() {
  late FakeHyperliquidMoveRail rail;
  late HyperliquidVenueFunder funder;

  setUp(() {
    rail = FakeHyperliquidMoveRail();
    funder = HyperliquidVenueFunder(rail);
  });

  tearDown(() => rail.creditedController.close());

  group('fund', () {
    test('rides the rail with dollar base units, the purpose and a hook that honours the order grant',
        () async {
      final grant = AuthGrants.issue(
          _orderIntent(
              fundUsd: dollarsBaseUnits(20.02), fundVenue: kFundVenueInvesting),
          method: AuthGrantMethod.pin);
      final result = await funder.fund(
          usd: 20.02, auth: UserGrantAuthorization(grant));
      expect(result.sentUsd, 20.02);
      expect(rail.gasFloatCalls, 1);
      expect(rail.deposits.single.units, BigInt.from(20020000));
      expect(rail.deposits.single.purpose, 'order_funding');
      final hook = rail.lastStepUp!;
      expect(await hook(_settlement(BigInt.from(20020000))), isTrue);
      expect(await hook(_settlement(BigInt.from(20020001))), isFalse,
          reason: 'more than the grant allows to leave');
      expect(await hook(_settlement(BigInt.from(5000000), walletId: 'w2')),
          isFalse, reason: 'another wallet');
      // The grant stays for the order: the hook never consumes it.
      expect(grant.consumed, isFalse);
    });

    test('a sweep never deposits: RouteUnavailable before the rail is asked',
        () async {
      await expectLater(
        funder.fund(usd: 10, auth: SweepAuthorization.automatic),
        throwsA(isA<RouteUnavailable>()),
      );
      expect(rail.deposits, isEmpty);
      expect(rail.gasFloatCalls, 0);
    });

    test('the rail refusing the route reaches the caller as RouteUnavailable',
        () async {
      rail.depositError = const RouteUnavailable('paused');
      final grant = AuthGrants.issue(
          _orderIntent(
              fundUsd: dollarsBaseUnits(10), fundVenue: kFundVenueInvesting),
          method: AuthGrantMethod.pin);
      await expectLater(
        funder.fund(usd: 10, auth: UserGrantAuthorization(grant)),
        throwsA(isA<RouteUnavailable>()),
      );
      expect(rail.deposits, isEmpty);
    });

    test('a grant without funding limits, consumed, revoked or expired covers nothing',
        () async {
      final plain =
          AuthGrants.issue(_orderIntent(), method: AuthGrantMethod.pin);
      expect(
          HyperliquidVenueFunder.grantCoversMove(
              plain, _settlement(BigInt.one)),
          isFalse);
      final wrongVenue = AuthGrants.issue(
          _orderIntent(fundUsd: dollarsBaseUnits(10), fundVenue: 'predictions'),
          method: AuthGrantMethod.pin);
      expect(
          HyperliquidVenueFunder.grantCoversMove(
              wrongVenue, _settlement(BigInt.one)),
          isFalse);
      final funded = AuthGrants.issue(
          _orderIntent(
              fundUsd: dollarsBaseUnits(10), fundVenue: kFundVenueInvesting),
          method: AuthGrantMethod.pin);
      expect(
          HyperliquidVenueFunder.grantCoversMove(
              funded, _settlement(BigInt.from(10000000))),
          isTrue);
      expect(
          HyperliquidVenueFunder.grantCoversMove(
              funded, _settlement(BigInt.from(10000000)),
              now: DateTime.now().add(const Duration(hours: 1))),
          isFalse);
      funded.revoke();
      expect(
          HyperliquidVenueFunder.grantCoversMove(
              funded, _settlement(BigInt.from(10000000))),
          isFalse);
    });
  });

  group('estimate', () {
    test('folds the flat cost into the fee and keeps the rail\'s arrival',
        () async {
      rail.quote = const VenueMoveQuote(
          arrivingUsd: 17.98,
          feeUsd: 0.02,
          fixedCostUsd: 1,
          minUsd: 0.8,
          maxUsd: 107600);
      final q = await funder.estimate(19);
      expect(q.feeUsd, closeTo(1.02, 1e-9));
      expect(q.fixedCostUsd, 1);
      expect(q.arrivingUsd, 17.98);
      expect(q.minUsd, 0.8);
      expect(await funder.minimumUsd(), 0.8);
    });

    test('idle cash is the rail\'s withdrawable', () async {
      rail.withdrawable = 3.5;
      expect(await funder.idleUsd(), 3.5);
    });
  });

  group('fundUsdFor', () {
    test('grosses the shortfall up by the rate and the flat cost, to the cent',
        () {
      // 0.1% of $19 is $0.019; a $1 float on top.
      const quote = VenueMoveQuote(
          arrivingUsd: 17.981,
          feeUsd: 1.019,
          fixedCostUsd: 1,
          minUsd: 0.8,
          maxUsd: 107600);
      final usd =
          HyperliquidVenueFunder.fundUsdFor(shortfallUsd: 19, quote: quote);
      expect(usd, closeTo(20.03, 1e-9));
      // What arrives covers the shortfall: usd × (1 − 0.001) − 1 ≥ 19.
      expect(usd * 0.999 - 1, greaterThanOrEqualTo(19));
    });

    test('a free route sends the shortfall itself, never under the minimum',
        () {
      VenueMoveQuote free(double arriving) => VenueMoveQuote(
          arrivingUsd: arriving,
          feeUsd: 0,
          fixedCostUsd: 0,
          minUsd: 10,
          maxUsd: 100);
      expect(HyperliquidVenueFunder.fundUsdFor(shortfallUsd: 5, quote: free(5)),
          10);
      expect(
          HyperliquidVenueFunder.fundUsdFor(
              shortfallUsd: 50.004, quote: free(50.004)),
          50.01);
      expect(
          HyperliquidVenueFunder.fundUsdFor(shortfallUsd: 0, quote: free(0)),
          0);
    });

    test('is capped at the rail\'s maximum', () {
      const capped = VenueMoveQuote(
          arrivingUsd: 5, feeUsd: 0, fixedCostUsd: 0, minUsd: 1, maxUsd: 40);
      expect(
          HyperliquidVenueFunder.fundUsdFor(shortfallUsd: 50, quote: capped),
          40);
    });
  });

  group('sizing on what arrives (the HyperCore route is near-flat)', () {
    test('a \$10 shortfall on a \$1.24 flat route sends enough to land it',
        () async {
      // Measured: \$10 keeps 87.6%. A rate read off it (12.4%) was refused
      // by the old 4% rule and replaced by 2%, which under-funded.
      final f = _CostFunder(flat: 1.24, rate: 0.0008);
      final size =
          await HyperliquidVenueFunder.sizeFunding(f, neededUsd: 10);
      expect(size.covers(10), isTrue);
      expect(f.arriving(size.fundUsd), greaterThanOrEqualTo(10));
      // Not wildly over.
      expect(size.fundUsd, lessThan(11.4));
      expect(size.costUsd, closeTo(size.fundUsd - size.arrivingUsd, 0.01));
    });

    test('a \$1 shortfall is never under-sent (the old 50% cap did)',
        () async {
      final f = _CostFunder(flat: 1.24, rate: 0.0008);
      final size = await HyperliquidVenueFunder.sizeFunding(f, neededUsd: 1);
      expect(f.arriving(size.fundUsd), greaterThanOrEqualTo(1));
      // fundUsdFor alone, from one estimate, already lands it.
      final one = HyperliquidVenueFunder.fundUsdFor(
          shortfallUsd: 1, quote: await f.estimate(1));
      expect(f.arriving(one), greaterThanOrEqualTo(1));
    });

    test('an account Hyperliquid has never seen pays its activation too',
        () async {
      // Orchestra prices the one-time \$1 activation into what arrives
      // for an account it does not know.
      final f = _CostFunder(flat: 1.24, rate: 0.0008, activation: 1.0);
      final size =
          await HyperliquidVenueFunder.sizeFunding(f, neededUsd: 20);
      expect(f.arriving(size.fundUsd), greaterThanOrEqualTo(20));
      expect(size.fundUsd, greaterThan(22.2));
    });

    test('a route that cannot land it (its maximum) does not cover',
        () async {
      final f = _CostFunder(flat: 1.24, rate: 0, max: 15);
      final size =
          await HyperliquidVenueFunder.sizeFunding(f, neededUsd: 20);
      expect(size.covers(20), isFalse);
      expect(size.fundUsd, 15);
    });
  });

  group('sizing on a fresh first quote (the slip read it already)', () {
    // Every estimate is one Orchestra round trip, 800 ms here.
    const trip = Duration(milliseconds: 800);

    test('without one: the sizing estimate, then the verifying one (1.6 s)',
        () {
      fakeAsync((async) {
        final f = _CostFunder(flat: 1.24, rate: 0.0008, latency: trip);
        FundingSize? size;
        HyperliquidVenueFunder.sizeFunding(f, neededUsd: 10.25)
            .then((s) => size = s);
        async.elapse(trip);
        expect(size, isNull, reason: 'the verifying estimate is still out');
        async.elapse(trip);
        expect(size, isNotNull);
        expect(f.estimates, 2);
        expect(async.elapsed, const Duration(milliseconds: 1600));
        expect(size!.covers(10.25), isTrue);
        expect(f.arriving(size!.fundUsd), greaterThanOrEqualTo(10.25));
      });
    });

    test('with one: only the verifying estimate at the amount sent (0.8 s)',
        () {
      fakeAsync((async) {
        final f = _CostFunder(flat: 1.24, rate: 0.0008, latency: trip);
        // The ticket's own read, moments ago, for the same target.
        final first = f.quoteFor(10.25);
        FundingSize? size;
        HyperliquidVenueFunder.sizeFunding(f, neededUsd: 10.25, first: first)
            .then((s) => size = s);
        async.elapse(trip);
        expect(size, isNotNull);
        expect(f.estimates, 1, reason: 'the sizing round trip is spared');
        expect(async.elapsed, trip);
        // The exact-amount rule holds: what is sent was priced itself.
        expect(f.estimatedFor, [size!.fundUsd]);
        expect(size!.covers(10.25), isTrue);
        expect(f.arriving(size!.fundUsd), greaterThanOrEqualTo(10.25));
        // The same answer as the two-trip sizing.
        final twoTrips = _CostFunder(flat: 1.24, rate: 0.0008);
        FundingSize? plain;
        HyperliquidVenueFunder.sizeFunding(twoTrips, neededUsd: 10.25)
            .then((s) => plain = s);
        async.flushMicrotasks();
        expect(plain!.fundUsd, size!.fundUsd);
      });
    });

    test('a first quote that moved is still caught by the verifying estimate',
        () async {
      // The ticket's quote was read on a cheaper route than the one the
      // accept finds: the verification lands short, the top-up round
      // sizes it right, and the amount sent is still a priced one.
      final cheap = _CostFunder(flat: 0.5, rate: 0);
      final f = _CostFunder(flat: 1.24, rate: 0.0008);
      final size = await HyperliquidVenueFunder.sizeFunding(f,
          neededUsd: 10.25, first: cheap.quoteFor(10.25));
      expect(size.covers(10.25), isTrue);
      expect(f.estimatedFor.last, size.fundUsd);
      expect(f.estimates, 2);
    });

    test('freshFirstQuote: the same target within a minute, else nothing', () {
      final now = DateTime.utc(2026, 11, 9, 12);
      final quote = _CostFunder(flat: 1.24, rate: 0.0008).quoteFor(10.25);
      VenueMoveQuote? fresh({
        double quotedFor = 10.25,
        Duration age = const Duration(seconds: 20),
        VenueMoveQuote? q,
      }) =>
          HyperliquidVenueFunder.freshFirstQuote(
            quote: q ?? quote,
            readAt: now.subtract(age),
            quotedForUsd: quotedFor,
            neededUsd: 10.25,
            now: now,
          );
      expect(fresh(), same(quote));
      expect(fresh(age: const Duration(seconds: 59)), same(quote));
      expect(fresh(age: const Duration(seconds: 60)), isNull,
          reason: 'as old as the rail keeps a route\'s limits: read again');
      expect(fresh(quotedFor: 10.30), isNull,
          reason: 'priced for another target');
      expect(fresh(quotedFor: 10.254), same(quote),
          reason: 'the same target to the cent');
      expect(fresh(age: const Duration(seconds: -5)), isNull);
      expect(
          HyperliquidVenueFunder.freshFirstQuote(
              quote: null,
              readAt: now,
              quotedForUsd: 10.25,
              neededUsd: 10.25,
              now: now),
          isNull);
      expect(HyperliquidVenueFunder.kFirstQuoteFreshFor,
          HyperCoreMoveRail.kLimitsFreshFor);
    });
  });

  test('the credit stream is the rail\'s', () async {
    final seen = <void>[];
    final sub = funder.credited.listen(seen.add);
    rail.creditedController.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(seen, hasLength(1));
    await sub.cancel();
  });

  test('the provider wraps the bound rail', () {
    final container = ProviderContainer(overrides: [
      hyperliquidMoveRailProvider.overrideWithValue(rail),
    ]);
    addTearDown(container.dispose);
    expect(container.read(hyperliquidVenueFunderProvider),
        isA<HyperliquidVenueFunder>());
  });
}

/// A funder whose route keeps [flat] (plus [activation]) and [rate] of
/// what is sent, the way the HyperCore route's live quotes do. Each
/// estimate takes [latency] (one Orchestra round trip) and is counted.
class _CostFunder implements VenueFunder {
  _CostFunder(
      {required this.flat,
      required this.rate,
      this.activation = 0,
      this.max = 1e6,
      this.latency = Duration.zero});
  final double flat;
  final double rate;
  final double activation;
  final double max;
  final Duration latency;

  /// How many estimates were asked, and the amounts they were priced for.
  int estimates = 0;
  final List<double> estimatedFor = [];

  double arriving(double usd) => usd * (1 - rate) - flat - activation;

  /// The quote for [usd] without a round trip (what the ticket holds).
  VenueMoveQuote quoteFor(double usd) => VenueMoveQuote(
      arrivingUsd: arriving(usd),
      feeUsd: usd - arriving(usd),
      fixedCostUsd: 0,
      minUsd: 1,
      maxUsd: max);

  @override
  Future<VenueMoveQuote> estimate(double usd) async {
    estimates++;
    estimatedFor.add(usd);
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return quoteFor(usd);
  }

  @override
  Future<VenueMoveResult> fund(
          {required double usd,
          required MoveAuthorization auth,
          String purpose = 'order_funding'}) =>
      throw UnimplementedError();

  @override
  Future<double> idleUsd() async => 0;

  @override
  Future<double> minimumUsd() async => 1;
}
