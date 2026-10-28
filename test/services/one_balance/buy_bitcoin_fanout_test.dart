import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/services/one_balance/buy_bitcoin_fanout.dart';
import 'package:kute/services/one_balance/dollars_to_bitcoin_minimum.dart';
import 'package:kute/services/one_balance/dollars_to_bitcoin_purchase.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/move_steps.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/tracking_service.dart';

class _Source implements VenueCashSource, DirectVenueCashSource {
  _Source(this.venue, this.started);
  @override
  final OneBalanceVenue venue;
  final List<String> started;
  final release = Completer<void>();
  Object? error;
  bool fallback = false;
  int homeCalls = 0;
  int directCalls = 0;
  @override
  Duration get estimatedArrival => Duration.zero;
  @override
  Future<double> availableUsd() async => 10;
  @override
  bool canPullTo(VenueCashDestination destination) => true;
  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) async {
    homeCalls++;
    started.add('${venue.name}:home');
    await release.future;
    return VenueMoveResult(
        quoteId: 'home_${venue.name}',
        operationId: 'home_${venue.name}',
        sentUsd: usd,
        arrivingUsdEstimate: usd);
  }

  @override
  Future<VenueMoveResult> pullTo(VenueCashDestination destination, double usd,
      {required String purpose, required MoveAuthorization auth}) async {
    directCalls++;
    if (fallback) throw const DirectRouteRefused('no_direct_route');
    final grant = (auth as ApprovedLegAuthorization).grant;
    expect(
        DirectLegGrants.take(grant,
            venue: venue.name,
            destination: destination.code,
            amount: IntentUnits.usd(usd)),
        isTrue);
    started.add(venue.name);
    await release.future;
    if (error != null) throw error!;
    return VenueMoveResult(
        quoteId: 'q_${venue.name}',
        operationId: 'op_${venue.name}',
        sentUsd: usd,
        arrivingUsdEstimate: usd);
  }
}

void main() {
  const ownSpark = 'spark1self';
  late List<String> started;
  late List<_Source> sources;
  late VenueCashPuller puller;
  late VenueCashPlan plan;
  late List<Map<String, Object>?> finishes;

  AuthGrant grant({String recipient = ownSpark}) => AuthGrants.issue(
      DirectLegGrants.buyBitcoin(
          walletId: 'w1',
          ownSpark: recipient,
          route: kDollarsToBtcRoute.label,
          asset: 'USDB',
          totalUsd: plan.neededUsd,
          directLegs: puller.directLegLimit(plan, VenueCashDestination.bitcoin),
          ttl: AuthGrants.autofireTtl),
      method: AuthGrantMethod.pin);

  Future<void> pay(double usd, AuthGrant approval) async {
    expect(
        await approvedPurchaseStepUp(approval)(SettlementAuthorizationIntent(
          flow: SettlementFlow.moveDollarsToBtc,
          walletId: 'w1',
          destination: '$ownSpark|v1',
          routeLabel: kDollarsToBtcRoute.label,
          amountIn: IntentUnits.usd(usd),
          minReceive: BigInt.one,
          maxFeeBps: 100,
        )),
        isTrue);
  }

  setUp(() {
    finishes = [];
    TrackingService.debugTrackObserver = (event, params) {
      if (event == 'multi_source_move_finished') finishes.add(params);
    };
    MultiSourceMoveStore.reset();
    DirectRouteRefusals.reset();
    started = [];
    sources = [
      for (final venue in OneBalanceVenue.values) _Source(venue, started)
    ];
    puller = VenueCashPuller(
        sources: sources,
        readDollars: () => 10,
        minimumUsd: (_) async => 1,
        walletId: () => 'w1');
    plan = VenueCashPlan(
        neededUsd: 30,
        dollarsUsd: 10,
        pulls: [
          for (final venue in OneBalanceVenue.values)
            VenueCashPull(
                venue: venue, usd: 10, arrivingUsd: 10, eta: Duration.zero)
        ],
        covers: true,
        eta: Duration.zero,
        uncoveredUsd: 0);
  });

  tearDown(() => TrackingService.debugTrackObserver = null);

  test('all three source submissions start before any source settles',
      () async {
    final dollarsRelease = Completer<void>();
    final approval = grant();
    final fanout =
        BitcoinPurchaseFanout(buy: (usd, child, id, onFunding) async {
      started.add('dollars');
      expect(child.boundIntent.amountMax, IntentUnits.usd(10));
      expect(child.boundIntent.limits[VenueLimit.directLegs], isNull);
      await pay(usd, child);
      onFunding();
      await dollarsRelease.future;
      return DollarsToBitcoinSent(
          sentUsd: usd, registered: true, operationId: 'initial');
    });
    final work = fanout.start(
        puller: puller,
        plan: plan,
        approval: approval,
        walletId: 'w1',
        ownSpark: ownSpark,
        moveId: 'move');
    await pumpEventQueue();
    expect(started.toSet(), {'dollars', 'investing', 'predictions'});
    expect(approval.consumed, isTrue);
    expect(finishes, isEmpty,
        reason: 'cannot claim Dollars while it is unsent');
    expect(MultiSourceMoveStore.get('move')!.initialDollarsOperationId, isNull);
    dollarsRelease.complete();
    for (final source in sources) {
      source.release.complete();
    }
    final result = await work;
    expect(result.dollarsEnd, ParallelDollarsEnd.submitted);
    expect(finishes, hasLength(1));
    expect(finishes.single!['dollars_usd'], 10);
    expect(result.grant.expiresAt.isAfter(approval.expiresAt), isFalse);
    expect(result.pull.dollarsNeededUsd, 0);
    expect(
        sources.every((s) => s.directCalls == 1 && s.homeCalls == 0), isTrue);
    final record = MultiSourceMoveStore.get('move')!;
    expect(record.initialDollarsOperationId, 'initial');
    expect(MultiSourceMove.fromJson(record.toJson())!.parallelPurchase, isTrue);
    expect(record.finalOperationId, isNull);
    expect(record.linkedIds, contains('initial'));
    expect(record.spentUsd, 30);
    expect(record.remainingUsd, 0);
    expect(
        MultiSourceMove.fromJson(record.toJson())!.initialDollarsSentUsd, 10);
  });

  test('failed Dollars does not stop either venue and is safely retryable',
      () async {
    final fanout = BitcoinPurchaseFanout(buy: (_, __, ___, ____) async {
      started.add('dollars');
      throw StateError('quote rejected before funding');
    });
    final work = fanout.start(
        puller: puller,
        plan: plan,
        approval: grant(),
        walletId: 'w1',
        ownSpark: ownSpark,
        moveId: 'move');
    await pumpEventQueue();
    expect(started.toSet(), {'dollars', 'investing', 'predictions'});
    for (final source in sources) {
      source.release.complete();
    }
    final result = await work;
    final record = MultiSourceMoveStore.get('move')!;
    expect(result.dollarsEnd, ParallelDollarsEnd.notSent);
    expect(finishes, hasLength(1));
    expect(finishes.single!['dollars_usd'], 0);
    expect(finishes.single!['delivered_usd'], 20);
    expect(finishes.single!['failed_legs'], 1);
    expect(initialDollarsRetryable(record), isTrue);
    expect(record.spentUsd, 20);
    expect(record.deliveredUsd, 20);
    expect(record.remainingUsd, 10);
  });

  test('ambiguous initial funding is never offered as a new send', () async {
    final fanout = BitcoinPurchaseFanout(buy: (_, __, ___, onFunding) async {
      onFunding();
      throw StateError('native result unknown');
    });
    final work = fanout.start(
        puller: puller,
        plan: plan,
        approval: grant(),
        walletId: 'w1',
        ownSpark: ownSpark,
        moveId: 'move');
    for (final source in sources) {
      source.release.complete();
    }
    final result = await work;
    final record = MultiSourceMoveStore.get('move')!;
    expect(result.dollarsEnd, ParallelDollarsEnd.unknown);
    expect(initialDollarsRetryable(record), isFalse);
    expect(record.steps.byId(MoveSteps.initialDollarsId)?.reason,
        'outcome_unknown');
    expect(record.initialDollarsOperationId, isNull);
  });

  test('a venue failure cannot block initial Dollars or hide its actual order',
      () async {
    sources.first.error = const DirectRouteRefused('settlement_declined');
    final fanout =
        BitcoinPurchaseFanout(buy: (usd, child, id, onFunding) async {
      await pay(usd, child);
      onFunding();
      return DollarsToBitcoinSent(
          sentUsd: usd, registered: true, operationId: 'initial');
    });
    final work = fanout.start(
        puller: puller,
        plan: plan,
        approval: grant(),
        walletId: 'w1',
        ownSpark: ownSpark,
        moveId: 'move');
    for (final source in sources) {
      source.release.complete();
    }
    final result = await work;
    final record = MultiSourceMoveStore.get('move')!;
    expect(result.pull.failedLegs, hasLength(1));
    expect(record.initialDollarsOperationId, 'initial');
    expect(record.remainingUsd, 10);
    expect(record.spentUsd, 20);
  });

  test(
      'true direct refusal only buys venue fallback, not initial Dollars twice',
      () async {
    sources.first.fallback = true;
    final fanout =
        BitcoinPurchaseFanout(buy: (usd, child, id, onFunding) async {
      await pay(usd, child);
      onFunding();
      return DollarsToBitcoinSent(
          sentUsd: usd, registered: true, operationId: 'initial');
    });
    final work = fanout.start(
        puller: puller,
        plan: plan,
        approval: grant(),
        walletId: 'w1',
        ownSpark: ownSpark,
        moveId: 'move');
    for (final source in sources) {
      source.release.complete();
    }
    final result = await work;
    expect(result.pull.dollarsNeededUsd, 10);
    expect(result.grant.boundIntent.amountMax, IntentUnits.usd(10));
    expect(result.grant.boundIntent.limits[VenueLimit.directLegs], isNull);
    expect(DirectLegGrants.coversPurchase(result.grant, walletId: 'w1',
        recipient: ownSpark, routeLabel: kDollarsToBtcRoute.label,
        amountIn: IntentUnits.usd(11)), isFalse);
    await pay(10, result.grant);
    expect(DirectLegGrants.coversPurchase(result.grant, walletId: 'w1',
        recipient: ownSpark, routeLabel: kDollarsToBtcRoute.label,
        amountIn: IntentUnits.usd(10)), isFalse);
    final record = MultiSourceMoveStore.get('move')!;
    expect(record.steps.byId(MoveSteps.buyId)?.usd, 10);
    expect(record.initialDollarsSentUsd, 10);
    expect(sources.first.homeCalls, 1);
  });

  test('initial dust stays Dollars and does not block the venue submissions',
      () async {
    plan = VenueCashPlan(
        neededUsd: 20.42,
        dollarsUsd: .42,
        pulls: plan.pulls,
        covers: true,
        eta: Duration.zero,
        uncoveredUsd: 0);
    final fanout = BitcoinPurchaseFanout(buy: (_, __, ___, ____) async {
      throw const DollarsToBitcoinBelowMinimum();
    });
    final work = fanout.start(
        puller: puller,
        plan: plan,
        approval: grant(),
        walletId: 'w1',
        ownSpark: ownSpark,
        moveId: 'move');
    for (final source in sources) {
      source.release.complete();
    }
    final result = await work;
    final record = MultiSourceMoveStore.get('move')!;
    expect(result.dollarsEnd, ParallelDollarsEnd.skipped);
    expect(record.spentUsd, 20);
    expect(record.steps.byId(MoveSteps.arriveId)?.usd, 20);
    expect(record.steps.byId(MoveSteps.initialDollarsId)?.status,
        MoneyStepStatus.skipped);
    expect(initialDollarsRetryable(record), isFalse);
  });

  test('known failed source retries without touching held original source',
      () async {
    final failed = sources.first;
    final held = sources.last;
    failed.error = const DirectRouteRefused('settlement_declined');
    final fanout =
        BitcoinPurchaseFanout(buy: (usd, child, id, onFunding) async {
      await pay(usd, child);
      onFunding();
      return DollarsToBitcoinSent(
          sentUsd: usd, registered: true, operationId: 'initial');
    });
    final original = fanout.start(
        puller: puller,
        plan: plan,
        approval: grant(),
        walletId: 'w1',
        ownSpark: ownSpark,
        moveId: 'move');
    await pumpEventQueue();
    failed.release.complete();
    await pumpEventQueue();
    final before = MultiSourceMoveStore.get('move')!;
    expect(before.remainingUsd, 10,
        reason: 'held original source is not retry money');
    final retryPlan = (await puller.planRetry('move'))!;
    expect(retryPlan.pulls.map((leg) => leg.venue), [failed.venue]);
    failed.error = null;
    final approval = AuthGrants.issue(
        DirectLegGrants.retry(
            walletId: 'w1',
            destination: 'bitcoin',
            totalUsd: retryPlan.neededUsd,
            directLegs: puller.directLegLimit(
                retryPlan, VenueCashDestination.bitcoin)!),
        method: AuthGrantMethod.pin);
    final retried =
        await puller.retryMove('move', approval: approval, plan: retryPlan);
    expect(retried!.failedLegs, isEmpty);
    expect(held.release.isCompleted, isFalse,
        reason: 'retry did not wait on or repeat the held leg');
    expect(failed.directCalls, 2);
    expect(held.directCalls, 1);
    expect(held.homeCalls, 0);
    held.release.complete();
    await original;
    expect(MultiSourceMoveStore.get('move')!.remainingUsd, 0);
  });

  test('ambiguous venue error and held source expose no retry allocation',
      () async {
    sources.first.error = StateError('native result unknown');
    final fanout =
        BitcoinPurchaseFanout(buy: (usd, child, id, onFunding) async {
      await pay(usd, child);
      onFunding();
      return DollarsToBitcoinSent(
          sentUsd: usd, registered: true, operationId: 'initial');
    });
    final original = fanout.start(
        puller: puller,
        plan: plan,
        approval: grant(),
        walletId: 'w1',
        ownSpark: ownSpark,
        moveId: 'move');
    await pumpEventQueue();
    sources.first.release.complete();
    await pumpEventQueue();
    final record = MultiSourceMoveStore.get('move')!;
    expect(record.remainingUsd, 0);
    expect(await puller.planRetry('move'), isNull);
    expect(record.legs.single.uncertain, isTrue);
    final step = record.steps.byId(MoveSteps.legId(sources.first.venue));
    expect(step!.status, MoneyStepStatus.running);
    expect(step.reason, 'outcome_unknown');
    sources.last.release.complete();
    await original;
  });

  test('two venues with no Dollars also use safe parallel retry proof',
      () async {
    plan = VenueCashPlan(
        neededUsd: 20,
        dollarsUsd: 0,
        pulls: plan.pulls,
        covers: true,
        eta: Duration.zero,
        uncoveredUsd: 0);
    final fanout = BitcoinPurchaseFanout(
        buy: (_, __, ___, ____) async =>
            throw StateError('no Dollars source exists'));
    final original = fanout.start(
        puller: puller,
        plan: plan,
        approval: grant(),
        walletId: 'w1',
        ownSpark: ownSpark,
        moveId: 'move');
    await pumpEventQueue();
    expect(started.toSet(), {'investing', 'predictions'});
    final record = MultiSourceMoveStore.get('move')!;
    expect(record.parallelPurchase, isTrue);
    expect(record.hasParallelDollars, isFalse);
    expect(record.remainingUsd, 0);
    sources.first.error = StateError('native result unknown');
    for (final source in sources) {
      source.release.complete();
    }
    await original;
    expect(MultiSourceMoveStore.get('move')!.spentUsd, 10,
        reason: 'unknown source is not an accepted payment');
  });

  test('wrong reviewed recipient is rejected before any source starts',
      () async {
    final fanout = BitcoinPurchaseFanout(
        buy: (_, __, ___, ____) async => throw StateError('must not run'));
    await expectLater(
        fanout.start(
            puller: puller,
            plan: plan,
            approval: grant(recipient: 'another'),
            walletId: 'w1',
            ownSpark: ownSpark),
        throwsA(isA<AuthGrantException>()));
    expect(started, isEmpty);
  });
}
