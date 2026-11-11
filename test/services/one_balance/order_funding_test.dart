// The order-funding controller against a fake venue funder: what moves,
// what is refused with nothing moved, when the person is sent to the
// Dollars door, and the journey events each path reports.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/services/funding/settlement_funding_outcome.dart';
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementFundingUnknown, SettlementStopReason, SettlementStopped;
import 'package:kute/services/funding/venue_shortfall.dart';
import 'package:kute/services/one_balance/hyperliquid_venue_funder.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/tracking_service.dart';

/// A venue funder the test scripts: the estimate it answers, the move it
/// makes (or the error it throws), and what it was asked to move.
class _Funder implements StagedVenueFunder {
  _Funder({
    this.routeFee = 0.01,
    this.minimum = 1.0,
    this.error,
    this.staged = true,
    this.latency = Duration.zero,
  });

  final double routeFee;
  final double minimum;
  Object? error;
  final bool staged;

  /// How long each estimate and minimum read takes (a round trip).
  final Duration latency;
  final List<double> funded = [];
  final List<MoveAuthorization> auths = [];
  final List<OrderFundingStage> stages = [];
  int estimates = 0;
  int minimumReads = 0;

  @override
  Future<VenueMoveResult> fund({
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'order_funding',
  }) async {
    if (staged) throw StateError('fundStaged expected');
    return _move(usd, auth);
  }

  @override
  Future<VenueMoveResult> fundStaged({
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'order_funding',
    void Function(OrderFundingStage stage)? onStage,
  }) async {
    onStage?.call(OrderFundingStage.fund);
    return _move(usd, auth);
  }

  Future<VenueMoveResult> _move(double usd, MoveAuthorization auth) async {
    auths.add(auth);
    final e = error;
    if (e != null) throw e;
    funded.add(usd);
    return VenueMoveResult(
      quoteId: 'q_test',
      orderId: 'ord_test',
      sentUsd: usd,
      arrivingUsdEstimate: usd * (1 - routeFee),
    );
  }

  @override
  Future<double> idleUsd() async => 0;

  @override
  Future<double> minimumUsd() async {
    minimumReads++;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return minimum;
  }

  @override
  Future<VenueMoveQuote> estimate(double usd) async {
    estimates++;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return VenueMoveQuote(
      arrivingUsd: usd * (1 - routeFee),
      feeUsd: usd * routeFee,
      fixedCostUsd: 0,
      minUsd: minimum,
      maxUsd: double.infinity,
    );
  }
}

class _Refused implements Exception, SettlementFundingNotStarted {}

AuthGrant _grant() => AuthGrants.issue(
      PmGrants.fundedBetReview(
        PmGrants.betReview(
          walletId: 'w',
          tokenId: 't',
          maxCostUsd: 10.2,
          worstPrice: 0.6,
          orderType: 'fak',
        ),
        fundUsd: 5.3,
        venue: IntentVenue.polymarket,
      ),
      method: AuthGrantMethod.biometric,
    );

void main() {
  late List<(String, Map<String, Object>?)> events;

  setUp(() {
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    OrderFundingJourney.reset();
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    OrderFundingJourney.reset();
  });

  test('the route event carries the decision and the exact cost difference',
      () {
    final journey = OrderFundingJourney.instance;
    journey.start(OneBalanceVenue.predictions,
        orderUsd: 5, fundUsd: 5.1, readyUsd: 0, dollarsUsd: 0);
    journey.setRoute(OneBalanceVenue.predictions, 'direct',
        decision: 'within_tolerance', costDiffUsd: 0.0175);
    final p = events
        .singleWhere((e) => e.$1 == 'order_funding_route_selected')
        .$2!;
    expect(p['route'], 'direct');
    expect(p['route_decision'], 'within_tolerance');
    expect(p['route_cost_diff_usd'], 0.0175);
    expect(p.containsKey('route_reason'), isFalse);
  });

  OrderFundingController controller(_Funder funder, {double dollars = 100}) =>
      OrderFundingController(
          funderFor: (_) => funder, dollarsUsd: () => dollars);

  List<String> names() => [for (final e in events) e.$1];

  group('OrderFundingPlan', () {
    test('grosses the shortfall up by the route fee, never under the min',
        () {
      final plan = OrderFundingPlan.from(
          orderUsd: 10, requiredUsd: 10.2, readyUsd: 5, routeFee: 0.01);
      expect(plan.fundUsd, closeTo(10, 1e-9));
      expect(plan.rule, ShortfallRules.ruleOrderAmount);
      expect(plan.feeUsd, closeTo(0.1, 1e-9));
      final tiny = OrderFundingPlan.from(
          orderUsd: 0.5, requiredUsd: 0.5, readyUsd: 0, routeFee: 0, minUsd: 1);
      expect(tiny.fundUsd, 1);
    });

    test('reads the route share off the funder estimate', () async {
      final funder = _Funder(routeFee: 0.02, minimum: 1);
      final plan = await OrderFundingPlan.read(funder,
          orderUsd: 10, requiredUsd: 10.3, readyUsd: 0);
      expect(funder.estimates, 1);
      expect(plan.rule, ShortfallRules.ruleOrderPlusFee);
      expect(plan.fundUsd * 0.98, greaterThanOrEqualTo(10.3 - 1e-6));
      expect(plan.minUsd, 1);
    });
  });

  test('nothing is needed when the venue covers the order', () async {
    final funder = _Funder();
    final outcome = await controller(funder).fundAndQueue(
      venue: OneBalanceVenue.predictions,
      orderUsd: 10,
      requiredUsd: 10.2,
      readyUsd: 12,
      auth: UserGrantAuthorization(_grant()),
    );
    expect(outcome, isA<OrderFundingNotNeeded>());
    expect(funder.funded, isEmpty);
    expect(events, isEmpty);
  });

  test('funds the approved amount, reports the stages and the journey',
      () async {
    final funder = _Funder();
    final stages = <OrderFundingStage>[];
    final outcome = await controller(funder, dollars: 20).fundAndQueue(
      venue: OneBalanceVenue.predictions,
      orderUsd: 10,
      requiredUsd: 10.2,
      readyUsd: 5,
      auth: UserGrantAuthorization(_grant()),
      fundUsd: 5.3,
      entrySource: 'feed_card',
      onStage: stages.add,
    );
    expect(outcome, isA<OrderFundingFunded>());
    expect((outcome as OrderFundingFunded).move.sentUsd, 5.3);
    expect(funder.funded, [5.3]);
    expect(funder.estimates, 0, reason: 'the approved amount is not re-read');
    expect(stages, [
      OrderFundingStage.quote,
      OrderFundingStage.fund,
      OrderFundingStage.fund,
      OrderFundingStage.credit,
    ]);
    expect(names(), [
      'order_funding_started',
      'order_funding_step',
      'order_funding_step',
      'order_funding_step',
      'order_funding_submitted',
    ]);
    final started = events.first.$2!;
    expect(started['venue'], 'polymarket');
    expect(started['order_usd'], 10);
    expect(started['fund_usd'], 5.3);
    expect(started['ready_usd'], 5);
    expect(started['dollars_usd'], 20);
    expect(started['entry_source'], 'feed_card');
    expect(started['wallet_kind'], 'hot');
    final submitted = events.last.$2!;
    expect(submitted['fund_usd'], 5.3);
    expect(submitted['amount_usd'], 10);
    expect(submitted['quote_id'], TrackingService.orderRef('q_test'));
    expect(submitted['order_id'], TrackingService.orderRef('ord_test'));
    expect(OrderFundingJourney.instance.isRunning(OneBalanceVenue.predictions),
        isTrue);
  });

  test('without an approved amount the venue estimate sizes the move',
      () async {
    final funder = _Funder(routeFee: 0.02);
    final outcome = await controller(funder).fundAndQueue(
      venue: OneBalanceVenue.predictions,
      orderUsd: 10,
      requiredUsd: 10.3,
      readyUsd: 0,
      auth: UserGrantAuthorization(_grant()),
    );
    expect(outcome, isA<OrderFundingFunded>());
    expect(funder.estimates, 1);
    expect(funder.funded.single * 0.98, greaterThanOrEqualTo(10.3 - 1e-6));
  });

  test('Dollars short of the move: the Dollars door, nothing moved',
      () async {
    final funder = _Funder();
    final outcome = await controller(funder, dollars: 3).fundAndQueue(
      venue: OneBalanceVenue.predictions,
      orderUsd: 10,
      requiredUsd: 10.2,
      readyUsd: 5,
      auth: UserGrantAuthorization(_grant()),
      fundUsd: 5.3,
    );
    expect(outcome, isA<OrderFundingNeedsDollars>());
    expect((outcome as OrderFundingNeedsDollars).shortfallUsd,
        closeTo(2.3, 1e-9));
    expect(funder.funded, isEmpty);
    expect(names().last, 'order_funding_failed');
    expect(events.last.$2!['stage'], 'quote');
    expect(events.last.$2!['error_category'], 'insufficient_funds');
    expect(OrderFundingJourney.instance.isRunning(OneBalanceVenue.predictions),
        isFalse);
  });

  group('a refusal leaves Dollars untouched', () {
    Future<OrderFundingRefused> refuse(Object error) async {
      final funder = _Funder(error: error);
      final outcome = await controller(funder).fundAndQueue(
        venue: OneBalanceVenue.predictions,
        orderUsd: 10,
        requiredUsd: 10.2,
        readyUsd: 5,
        auth: UserGrantAuthorization(_grant()),
        fundUsd: 5.3,
      );
      expect(funder.funded, isEmpty);
      expect(names().last, 'order_funding_failed');
      expect(events.last.$2!['stage'], 'fund');
      expect(OrderFundingJourney.instance
          .isRunning(OneBalanceVenue.predictions), isFalse);
      return outcome as OrderFundingRefused;
    }

    test('declined approval', () async {
      final r = await refuse(
          const SettlementStopped(SettlementStopReason.declined));
      expect(r.reason, 'user_cancelled');
      expect(events.last.$2!['error_category'], 'user_cancelled');
    });

    test('no route', () async {
      expect((await refuse(const RouteUnavailable('paused'))).reason,
          'no_route');
    });

    test('a funding call that never started', () async {
      expect((await refuse(_Refused())).reason, 'settlement');
    });

    test('anything else is categorised, never the raw text', () async {
      final r = await refuse(StateError('Wallet locked. Please unlock first.'));
      expect(r.reason, isNot(contains('Wallet')));
      expect(r.error, isA<StateError>());
    });
  });

  test('a plain funder is used through fund()', () async {
    final funder = _Funder(staged: false);
    final outcome = await controller(funder).fundAndQueue(
      venue: OneBalanceVenue.predictions,
      orderUsd: 10,
      requiredUsd: 10,
      readyUsd: 0,
      auth: UserGrantAuthorization(_grant()),
      fundUsd: 10,
    );
    expect(outcome, isA<OrderFundingFunded>());
    expect(funder.funded, [10]);
  });

  test('a move under the rail minimum is raised to it', () async {
    final funder = _Funder(minimum: 5);
    await controller(funder).fundAndQueue(
      venue: OneBalanceVenue.predictions,
      orderUsd: 2,
      requiredUsd: 2,
      readyUsd: 0,
      auth: UserGrantAuthorization(_grant()),
      fundUsd: 2,
    );
    expect(funder.funded, [5]);
  });

  test('the estimate and the rail minimum are read together, not in turn',
      () {
    // Each read is one round trip of 300 ms. One after the other the
    // quote stage took 600 ms; together it takes 300 ms.
    fakeAsync((async) {
      final funder =
          _Funder(latency: const Duration(milliseconds: 300), staged: false);
      OrderFundingOutcome? outcome;
      controller(funder)
          .fundAndQueue(
            venue: OneBalanceVenue.predictions,
            orderUsd: 10,
            requiredUsd: 10.2,
            readyUsd: 5,
            auth: UserGrantAuthorization(_grant()),
          )
          .then((o) => outcome = o);
      async.elapse(const Duration(milliseconds: 300));
      expect(outcome, isA<OrderFundingFunded>(),
          reason: 'both answers in one wait');
      expect(funder.estimates, 1);
      expect(funder.minimumReads, 1);
      expect(funder.funded, hasLength(1));
    });
  });

  test('with the amount approved, only the minimum is read (one round trip)',
      () {
    fakeAsync((async) {
      final funder =
          _Funder(latency: const Duration(milliseconds: 300), staged: false);
      OrderFundingOutcome? outcome;
      controller(funder)
          .fundAndQueue(
            venue: OneBalanceVenue.predictions,
            orderUsd: 10,
            requiredUsd: 10.2,
            readyUsd: 5,
            auth: UserGrantAuthorization(_grant()),
            fundUsd: 5.3,
          )
          .then((o) => outcome = o);
      async.elapse(const Duration(milliseconds: 300));
      expect(outcome, isA<OrderFundingFunded>());
      expect(funder.estimates, 0);
      expect(funder.minimumReads, 1);
    });
  });

  test("Investing's funder is the Hyperliquid venue funder", () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(investingVenueFunderProvider),
        isA<HyperliquidVenueFunder>());
    expect(container.read(investingVenueFunderProvider),
        same(container.read(hyperliquidVenueFunderProvider)));
  });

  group('OrderFundingJourney', () {
    test('completed carries every latency figure, once', () {
      var now = DateTime.utc(2026, 10, 12, 12);
      OrderFundingJourney.clock = () => now;
      addTearDown(() => OrderFundingJourney.clock = DateTime.now);
      final j = OrderFundingJourney.instance;
      j.start(OneBalanceVenue.predictions,
          orderUsd: 10, fundUsd: 5, readyUsd: 5, dollarsUsd: 20);
      now = now.add(const Duration(milliseconds: 300));
      j.step(OneBalanceVenue.predictions, OrderFundingStage.fund);
      now = now.add(const Duration(milliseconds: 700));
      j.funded(
          OneBalanceVenue.predictions,
          const VenueMoveResult(
              quoteId: 'q', orderId: 'o', sentUsd: 5, arrivingUsdEstimate: 4.9),
          orderUsd: 10);
      now = now.add(const Duration(seconds: 20));
      j.credited(OneBalanceVenue.predictions);
      now = now.add(const Duration(milliseconds: 500));
      j.completed(OneBalanceVenue.predictions, resized: true, amountUsd: 9.8);
      j.completed(OneBalanceVenue.predictions, resized: false);
      final done =
          events.where((e) => e.$1 == 'order_funding_completed').toList();
      expect(done, hasLength(1));
      final p = done.single.$2!;
      expect(p['ms_quote'], 300);
      expect(p['ms_fund'], 700);
      expect(p['ms_credit'], 20000);
      expect(p['ms_order'], 500);
      expect(p['duration_ms'], 21500);
      expect(p['resized'], isTrue);
      expect(p['fund_usd'], 5);
      expect(p['amount_usd'], 9.8);
      // Where the seconds went, one exact figure per leg.
      expect(p['legs'], {
        'quote': 300,
        'fund': 700,
        'credit': 20000,
        'order': 500,
      });
      expect(j.isRunning(OneBalanceVenue.predictions), isFalse);
    });

    test('legs carries the finer legs a run recorded, and the Bitcoin leg',
        () {
      var now = DateTime.utc(2026, 11, 9, 12);
      OrderFundingJourney.clock = () => now;
      addTearDown(() => OrderFundingJourney.clock = DateTime.now);
      final j = OrderFundingJourney.instance;
      j.start(OneBalanceVenue.predictions,
          orderUsd: 10, fundUsd: 5, readyUsd: 5, dollarsUsd: 20);
      j.bitcoinSent(OneBalanceVenue.predictions);
      now = now.add(const Duration(seconds: 4));
      j.bitcoinLanded(OneBalanceVenue.predictions);
      j.leg(OneBalanceVenue.predictions, OrderFundingLeg.estimate, 210);
      now = now.add(const Duration(milliseconds: 300));
      j.step(OneBalanceVenue.predictions, OrderFundingStage.fund);
      now = now.add(const Duration(milliseconds: 700));
      j.funded(
          OneBalanceVenue.predictions,
          const VenueMoveResult(
              quoteId: 'q', orderId: 'o', sentUsd: 5, arrivingUsdEstimate: 4.9),
          orderUsd: 10);
      j.leg(OneBalanceVenue.predictions, OrderFundingLeg.wrap, 6000);
      j.leg(OneBalanceVenue.predictions, OrderFundingLeg.venueCount, 1000);
      // A leg recorded twice keeps its total.
      j.leg(OneBalanceVenue.predictions, OrderFundingLeg.venueCount, 500);
      now = now.add(const Duration(seconds: 20));
      j.credited(OneBalanceVenue.predictions);
      now = now.add(const Duration(milliseconds: 500));
      j.completed(OneBalanceVenue.predictions, resized: false);
      final p =
          events.singleWhere((e) => e.$1 == 'order_funding_completed').$2!;
      expect(p['legs'], {
        'quote': 300,
        'fund': 700,
        'credit': 20000,
        'order': 500,
        'bitcoin': 4000,
        'estimate': 210,
        'wrap': 6000,
        'venue_count': 1500,
      });
      // The figures the dashboards already read are unchanged.
      expect(p['ms_quote'], 300);
      expect(p['ms_bitcoin_landed'], 4000);
    });

    test('legsBreakdown is shared by both emitters: stages, then extras', () {
      expect(
          OrderFundingJourney.legsBreakdown(
              quoteMs: 120,
              fundMs: 3000,
              creditMs: 24000,
              orderMs: 900,
              extra: {OrderFundingLeg.dexCredit: 2000}),
          {
            'quote': 120,
            'fund': 3000,
            'credit': 24000,
            'order': 900,
            'dex_credit': 2000,
          });
      expect(OrderFundingJourney.legsBreakdown(quoteMs: -5, fundMs: 10),
          {'quote': 0, 'fund': 10});
    });

    test('a second start abandons the first run', () {
      final j = OrderFundingJourney.instance;
      j.start(OneBalanceVenue.predictions,
          orderUsd: 10, fundUsd: 5, readyUsd: 5, dollarsUsd: 20);
      j.step(OneBalanceVenue.predictions, OrderFundingStage.fund);
      j.start(OneBalanceVenue.predictions,
          orderUsd: 12, fundUsd: 7, readyUsd: 5, dollarsUsd: 20);
      final abandoned =
          events.where((e) => e.$1 == 'order_funding_abandoned').toList();
      expect(abandoned, hasLength(1));
      expect(abandoned.single.$2!['stage'], 'fund');
    });

    test('a game in play\'s funded bet reads apart on every event', () {
      final j = OrderFundingJourney.instance;
      j.start(OneBalanceVenue.predictions,
          orderUsd: 3.33,
          fundUsd: 2.6,
          readyUsd: 0.8,
          dollarsUsd: 12.66,
          marketKind: 'live');
      j.step(OneBalanceVenue.predictions, OrderFundingStage.fund);
      j.failed(OneBalanceVenue.predictions, OrderFundingStage.order,
          'price_moved');
      final kinds = {
        for (final e in events.where((e) => e.$1.startsWith('order_funding_')))
          e.$1: e.$2!['market_kind']
      };
      expect(kinds, {
        'order_funding_started': 'live',
        'order_funding_step': 'live',
        'order_funding_failed': 'live',
      });
      // Exact amounts, as given.
      expect(
          events.firstWhere((e) => e.$1 == 'order_funding_started').$2![
              'order_usd'],
          3.33);
    });

    test('failed and abandoned need an open run', () {
      final j = OrderFundingJourney.instance;
      j.failed(OneBalanceVenue.investing, OrderFundingStage.order, 'x');
      j.abandoned(OneBalanceVenue.investing);
      expect(events, isEmpty);
    });
  });

  group('an unconfirmed move (SettlementFundingUnknown)', () {
    test('Investing keeps the run open at the credit and says so', () async {
      final funder =
          _Funder(error: const SettlementFundingUnknown('op', 'timeout'));
      final outcome = await controller(funder).fundAndQueue(
        venue: OneBalanceVenue.investing,
        orderUsd: 10,
        requiredUsd: 10.2,
        readyUsd: 0,
        auth: UserGrantAuthorization(_grant()),
        fundUsd: 11.5,
        keepUnconfirmed: true,
      );
      expect(outcome, isA<OrderFundingUnconfirmed>());
      // A refusal to any caller that does not tell the two apart.
      expect(outcome, isA<OrderFundingRefused>());
      expect(names(), isNot(contains('order_funding_failed')));
      expect(OrderFundingJourney.instance.isRunning(OneBalanceVenue.investing),
          isTrue);
    });

    test('without the opt-in it stays a refusal, as before', () async {
      final funder =
          _Funder(error: const SettlementFundingUnknown('op', 'timeout'));
      final outcome = await controller(funder).fundAndQueue(
        venue: OneBalanceVenue.predictions,
        orderUsd: 10,
        requiredUsd: 10.2,
        readyUsd: 5,
        auth: UserGrantAuthorization(_grant()),
        fundUsd: 5.3,
      );
      expect(outcome, isNot(isA<OrderFundingUnconfirmed>()));
      expect((outcome as OrderFundingRefused).reason, 'settlement');
    });
  });

  test('the approved amount is sent as is, never re-planned', () async {
    final funder = _Funder(routeFee: 0.12);
    await controller(funder).fundAndQueue(
      venue: OneBalanceVenue.investing,
      orderUsd: 10,
      requiredUsd: 10.2,
      readyUsd: 0.5,
      auth: UserGrantAuthorization(_grant()),
      fundUsd: 11.46,
    );
    expect(funder.funded, [11.46]);
    expect(funder.estimates, 0);
  });

  group('OrderFundingEngine (founder rule)', () {
    test('the venue already covers it: place directly', () {
      final d = OrderFundingEngine.decide(
          needUsd: 3.5, haveHereUsd: 4, investmentsUsd: 0);
      expect(d.route, OrderFundingRoute.direct);
      expect(d.targetUsd, 0);
    });

    test("the founder's example: \$6 in all, \$2 here, a \$3.50 bet moves "
        'about \$1.75 silently', () {
      // Dollars + the other venue hold \$4; the venue holds \$2.
      final d = OrderFundingEngine.decide(
          needUsd: 3.5, haveHereUsd: 2, investmentsUsd: 4, moveCostUsd: 0.01);
      expect(d.route, OrderFundingRoute.move);
      expect(d.shortfallUsd, 1.5);
      // \$1.50 + the \$0.25 floor of the buffer: \$1.75, never under \$1.
      expect(d.targetUsd, 1.75);
      expect(d.addUsd, 0);
    });

    test('rounds up to the route minimum and to \$1', () {
      expect(OrderFundingEngine.targetUsd(shortfallUsd: 0.1), 1.0);
      expect(
          OrderFundingEngine.targetUsd(shortfallUsd: 0.5, routeMinimumUsd: 2),
          2.0);
      // 2% of \$100 beats the \$0.25 floor; cents round up.
      expect(OrderFundingEngine.targetUsd(shortfallUsd: 100.001), 102.01);
      expect(OrderFundingEngine.targetUsd(shortfallUsd: 0), 0);
    });

    test('total Investments short: the Add door for exactly the rest', () {
      final d = OrderFundingEngine.decide(
          needUsd: 20, haveHereUsd: 0, investmentsUsd: 5, moveCostUsd: 1.24);
      expect(d.route, OrderFundingRoute.addFunds);
      // \$20 + \$0.40 buffer + \$1.24 route cost − \$5 = \$16.64.
      expect(d.addUsd, 16.64);
    });
  });
}
