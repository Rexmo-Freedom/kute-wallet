// The order-funding controller against a fake venue funder: what moves,
// what is refused with nothing moved, when the person is sent to the
// Dollars door, and the journey events each path reports.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/services/funding/settlement_funding_outcome.dart';
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementStopReason, SettlementStopped;
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
  });

  final double routeFee;
  final double minimum;
  Object? error;
  final bool staged;
  final List<double> funded = [];
  final List<MoveAuthorization> auths = [];
  final List<OrderFundingStage> stages = [];
  int estimates = 0;

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
  Future<double> minimumUsd() async => minimum;

  @override
  Future<VenueMoveQuote> estimate(double usd) async {
    estimates++;
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
      expect(j.isRunning(OneBalanceVenue.predictions), isFalse);
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

    test('failed and abandoned need an open run', () {
      final j = OrderFundingJourney.instance;
      j.failed(OneBalanceVenue.investing, OrderFundingStage.order, 'x');
      j.abandoned(OneBalanceVenue.investing);
      expect(events, isEmpty);
    });
  });
}
