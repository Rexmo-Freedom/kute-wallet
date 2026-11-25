// OrderActivityBinder: today's pending bet and trade mapped onto stages,
// one grace held while anything is in flight and released on every exit
// (done, failed, unconfirmed, vanished, dispose), a re-hold after an expiry,
// and the Riverpod wiring on the two providers.

import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/pending_hyperliquid_order_provider.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/services/platform/background_grace.dart';
import 'package:kute/services/platform/order_activity.dart';
import 'package:kute/services/platform/order_activity_binder.dart';

class _FakeActivity implements OrderActivityPort {
  final log = <String>[];

  @override
  void start(String id,
          {required String title,
          required OrderVenue venue,
          double? amountUsd}) =>
      log.add('start:$id:${venue.name}:$title');

  @override
  void update(String id,
          {required OrderStage stage, required double progress}) =>
      log.add('update:$id:${stage.name}:${(progress * 100).round()}');

  @override
  void end(String id, {required bool success, OrderOutcome? outcome}) =>
      log.add('end:$id:${outcome?.name}');

  @override
  void cancel(String id) => log.add('cancel:$id');
}

/// Counts through the real facade, which is a no-op on the test host.
class _CountingGrace implements BackgroundGracePort {
  int holds = 0;
  int releases = 0;

  @override
  GraceToken hold(String reason) {
    holds++;
    return BackgroundGrace.hold(reason);
  }

  @override
  void release(GraceToken token) {
    releases++;
    BackgroundGrace.release(token);
  }

  @override
  bool isHeld(GraceToken token) => BackgroundGrace.isHeld(token);
}

class _Recorder implements OrderNoticeSink {
  final shown = <OrderNotice>[];
  final dismissed = <int>[];
  @override
  Future<void> show(OrderNotice notice) async => shown.add(notice);
  @override
  Future<void> dismiss(int id) async => dismissed.add(id);
}

PendingBetIntent bet(PendingBetStatus status,
        {PendingBetStage stage = PendingBetStage.submitting,
        PredictionsReadiness? readiness}) =>
    PendingBetIntent(
      tokenId: '111',
      amount: 5,
      slippagePct: 5,
      marketQuestion: 'Will it rain?',
      outcomeName: 'Yes',
      expectedPrice: 0.5,
      status: status,
      stage: stage,
      readiness: readiness,
    );

PendingHlOrderIntent trade(PendingHlOrderStatus status,
        {HlReadiness? readiness}) =>
    PendingHlOrderIntent(
      coin: 'BTC',
      kind: HlMarketKind.perp,
      isLong: true,
      marginUsd: 20,
      leverage: 1,
      slippagePct: 1,
      expectedPx: 60000,
      marketLabel: 'BTC · Perp',
      status: status,
      readiness: readiness,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    BackgroundGrace.debugReset();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    BackgroundGrace.debugReset();
  });

  group('stage map, Predictions', () {
    OrderProgress? map(PendingBetStatus status,
            {PendingBetStage stage = PendingBetStage.submitting,
            PredictionsReadiness? readiness}) =>
        OrderStageMap.polymarket(
            bet(status, stage: stage, readiness: readiness));

    test('nothing before the person commits', () {
      expect(OrderStageMap.polymarket(null), isNull);
      expect(map(PendingBetStatus.awaitingDeposit), isNull);
    });

    test('the money moving, then waiting, in order', () {
      final converting = map(PendingBetStatus.converting)!;
      expect(converting.stage, OrderStage.converting);
      expect(converting.venue, OrderVenue.predictions);
      expect(converting.id, OrderStageMap.predictionsId);
      expect(converting.title, 'Will it rain? · Yes');
      expect(converting.amountUsd, 5);

      final waiting = map(PendingBetStatus.awaitingBalance)!;
      expect(waiting.stage, OrderStage.waitingMoney);
      expect(waiting.progress, greaterThan(converting.progress));
      expect(
          map(PendingBetStatus.awaitingBalance,
                  readiness: PredictionsReadiness.converting)!
              .stage,
          OrderStage.converting);
      expect(
          map(PendingBetStatus.awaitingBalance,
                  readiness: PredictionsReadiness.approving)!
              .stage,
          OrderStage.settingUp);
      expect(
          map(PendingBetStatus.awaitingBalance,
                  readiness: PredictionsReadiness.confirming)!
              .stage,
          OrderStage.confirming);
      expect(
          map(PendingBetStatus.awaitingBalance,
                  readiness: PredictionsReadiness.ready)!
              .stage,
          OrderStage.sending);
    });

    test('a placement walks its stages with rising progress', () {
      final stages = [
        PendingBetStage.submitting,
        PendingBetStage.settingUp,
        PendingBetStage.approving,
        PendingBetStage.delayed,
        PendingBetStage.confirming,
        PendingBetStage.reconciling,
      ];
      final mapped =
          stages.map((s) => map(PendingBetStatus.placing, stage: s)!).toList();
      expect(mapped.map((m) => m.stage), [
        OrderStage.sending,
        OrderStage.settingUp,
        OrderStage.settingUp,
        OrderStage.confirming,
        OrderStage.confirming,
        OrderStage.confirming,
      ]);
      for (var i = 1; i < mapped.length; i++) {
        expect(mapped[i].progress, greaterThan(mapped[i - 1].progress));
      }
      expect(mapped.first.progress,
          greaterThan(map(PendingBetStatus.awaitingBalance)!.progress));
      final confirming = map(PendingBetStatus.awaitingConfirmation)!;
      expect(confirming.stage, OrderStage.confirming);
      expect(confirming.inFlight, isTrue);
      expect(confirming.progress, lessThan(1));
    });

    test('done and failed finish', () {
      expect(map(PendingBetStatus.done)!.outcome, OrderOutcome.placed);
      expect(map(PendingBetStatus.failed)!.outcome, OrderOutcome.failed);
      expect(map(PendingBetStatus.done)!.inFlight, isFalse);
    });
  });

  group('stage map, Investing', () {
    OrderProgress? map(PendingHlOrderStatus status,
            {HlReadiness? readiness}) =>
        OrderStageMap.hyperliquid(trade(status, readiness: readiness));

    test('nothing before the person commits', () {
      expect(OrderStageMap.hyperliquid(null), isNull);
      expect(map(PendingHlOrderStatus.awaitingDeposit), isNull);
    });

    test('waiting, crediting, ready, placing', () {
      final waiting = map(PendingHlOrderStatus.awaitingBalance)!;
      expect(waiting.stage, OrderStage.waitingMoney);
      expect(waiting.venue, OrderVenue.investing);
      expect(waiting.id, OrderStageMap.investingId);
      expect(waiting.title, 'BTC · Perp');
      expect(waiting.amountUsd, 20);
      final crediting = map(PendingHlOrderStatus.awaitingBalance,
          readiness: HlReadiness.crediting)!;
      expect(crediting.stage, OrderStage.confirming);
      final ready = map(PendingHlOrderStatus.awaitingBalance,
          readiness: HlReadiness.ready)!;
      expect(ready.stage, OrderStage.sending);
      final placing = map(PendingHlOrderStatus.placing)!;
      expect(placing.stage, OrderStage.sending);
      expect(placing.progress, greaterThan(ready.progress));
      expect(ready.progress, greaterThan(crediting.progress));
      expect(crediting.progress, greaterThan(waiting.progress));
    });

    test('done, failed and unconfirmed finish, each its own way', () {
      expect(map(PendingHlOrderStatus.done)!.outcome, OrderOutcome.placed);
      expect(map(PendingHlOrderStatus.failed)!.outcome, OrderOutcome.failed);
      expect(map(PendingHlOrderStatus.unconfirmed)!.outcome,
          OrderOutcome.unconfirmed);
    });
  });

  group('binder', () {
    late _FakeActivity activity;
    late _CountingGrace grace;
    late OrderActivityBinder binder;

    setUp(() {
      activity = _FakeActivity();
      grace = _CountingGrace();
      binder = OrderActivityBinder(activity: activity, grace: grace);
    });

    test('an order in flight starts the notice and holds one grace', () {
      binder.polymarket(bet(PendingBetStatus.awaitingDeposit));
      expect(activity.log, isEmpty);
      expect(grace.holds, 0);

      binder.polymarket(bet(PendingBetStatus.awaitingBalance));
      expect(activity.log, [
        'start:predictions:predictions:Will it rain? · Yes',
        'update:predictions:waitingMoney:35',
      ]);
      expect(grace.holds, 1);
      expect(BackgroundGrace.activeCount, 1);
      expect(binder.token, isNotNull);
    });

    test('the same stage again draws nothing; a new one draws once', () {
      binder.polymarket(bet(PendingBetStatus.awaitingBalance));
      binder.polymarket(bet(PendingBetStatus.awaitingBalance));
      expect(activity.log, hasLength(2));
      binder.polymarket(bet(PendingBetStatus.placing));
      expect(activity.log.last, 'update:predictions:sending:80');
      binder.polymarket(
          bet(PendingBetStatus.placing, stage: PendingBetStage.confirming));
      expect(activity.log.last, 'update:predictions:confirming:90');
      expect(grace.holds, 1);
    });

    test('done ends with a success and releases the grace', () {
      binder.polymarket(bet(PendingBetStatus.placing));
      binder.polymarket(bet(PendingBetStatus.done));
      expect(activity.log.last, 'end:predictions:placed');
      expect(grace.releases, 1);
      expect(BackgroundGrace.activeCount, 0);
      expect(binder.token, isNull);
      expect(binder.inFlight, isEmpty);
    });

    test('failed ends with a failure and releases the grace', () {
      binder.hyperliquid(trade(PendingHlOrderStatus.placing));
      binder.hyperliquid(trade(PendingHlOrderStatus.failed));
      expect(activity.log, [
        'start:investing:investing:BTC · Perp',
        'update:investing:sending:80',
        'end:investing:failed',
      ]);
      expect(grace.holds, 1);
      expect(grace.releases, 1);
    });

    test('unconfirmed ends as neither and releases the grace', () {
      binder.hyperliquid(trade(PendingHlOrderStatus.placing));
      binder.hyperliquid(trade(PendingHlOrderStatus.unconfirmed));
      expect(activity.log.last, 'end:investing:unconfirmed');
      expect(grace.releases, 1);
    });

    test('an order that vanishes is cancelled and releases the grace', () {
      binder.polymarket(bet(PendingBetStatus.converting));
      binder.polymarket(null);
      expect(activity.log.last, 'cancel:predictions');
      expect(grace.releases, 1);
      expect(BackgroundGrace.activeCount, 0);
    });

    test('a finished order nobody saw start says nothing', () {
      binder.polymarket(bet(PendingBetStatus.done));
      binder.polymarket(null);
      expect(activity.log, isEmpty);
      expect(grace.holds, 0);
    });

    test('two venues in flight share one grace, released after the last',
        () {
      binder.polymarket(bet(PendingBetStatus.awaitingBalance));
      binder.hyperliquid(trade(PendingHlOrderStatus.awaitingBalance));
      expect(grace.holds, 1);
      expect(binder.inFlight, hasLength(2));
      binder.polymarket(bet(PendingBetStatus.done));
      expect(grace.releases, 0);
      expect(BackgroundGrace.activeCount, 1);
      binder.hyperliquid(trade(PendingHlOrderStatus.done));
      expect(grace.releases, 1);
      expect(BackgroundGrace.activeCount, 0);
    });

    test('after an expiry away, coming back holds again', () {
      binder.polymarket(bet(PendingBetStatus.awaitingBalance));
      final first = binder.token!;
      BackgroundGrace.debugExpire(first);
      expect(BackgroundGrace.isHeld(first), isFalse);
      // Still away: a state change does not start a new task.
      binder.polymarket(bet(PendingBetStatus.placing));
      expect(grace.holds, 1);
      binder.onResumed();
      expect(grace.holds, 2);
      expect(binder.token, isNot(same(first)));
      expect(BackgroundGrace.isHeld(binder.token!), isTrue);
      // A live token is left alone.
      binder.onResumed();
      expect(grace.holds, 2);
      binder.polymarket(bet(PendingBetStatus.done));
      expect(BackgroundGrace.activeCount, 0);
    });

    test('resume with nothing in flight holds nothing', () {
      binder.onResumed();
      expect(grace.holds, 0);
    });

    test('dispose releases the grace and takes every notice down', () {
      binder.polymarket(bet(PendingBetStatus.awaitingBalance));
      binder.hyperliquid(trade(PendingHlOrderStatus.placing));
      binder.dispose();
      expect(activity.log.sublist(activity.log.length - 2),
          containsAll(['cancel:predictions', 'cancel:investing']));
      expect(grace.releases, 1);
      expect(BackgroundGrace.activeCount, 0);
      expect(binder.inFlight, isEmpty);
    });

    test('a hold is never left behind across many lifecycles', () {
      for (var i = 0; i < 5; i++) {
        binder.polymarket(bet(PendingBetStatus.awaitingBalance));
        binder.polymarket(bet(PendingBetStatus.placing));
        binder.polymarket(bet(i.isEven
            ? PendingBetStatus.done
            : PendingBetStatus.failed));
        binder.polymarket(null);
      }
      expect(grace.holds, 5);
      expect(grace.releases, 5);
      expect(BackgroundGrace.activeCount, 0);
    });
  });

  group('Riverpod wiring', () {
    late _Recorder sink;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      OrderActivity.debugReset();
      sink = _Recorder();
      OrderActivity.debugSink = sink;
      OrderActivity.strings =
          () => lookupAppLocalizations(const Locale('en'));
      OrderActivity.isBackgrounded = () => true;
    });
    tearDown(OrderActivity.debugReset);

    test('a bet placed in the background shows its progress and result',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(orderActivityBinderProvider);
      final notifier = container.read(pendingPolymarketBetProvider.notifier);
      notifier.setIntent(bet(PendingBetStatus.awaitingDeposit));
      await pumpEventQueue();
      expect(sink.shown, isEmpty);

      notifier.updateStatus(PendingBetStatus.placing);
      await pumpEventQueue();
      expect(sink.shown.map((n) => n.body),
          ['Will it rain? · Yes', 'Sending your order']);
      expect(BackgroundGrace.activeCount, 1);

      notifier.setStage(PendingBetStage.confirming);
      notifier.updateStatus(PendingBetStatus.done);
      await pumpEventQueue();
      expect(sink.shown.last.title, 'Prediction placed');
      expect(sink.shown.last.outcome, OrderOutcome.placed);
      expect(BackgroundGrace.activeCount, 0);
    });

    test('a trade that finishes is ended once, then cleared quietly',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(orderActivityBinderProvider);
      final notifier =
          container.read(pendingHyperliquidOrderProvider.notifier);
      notifier.setIntent(trade(PendingHlOrderStatus.awaitingBalance));
      await pumpEventQueue();
      expect(sink.shown.last.title, 'Placing your order');
      expect(BackgroundGrace.activeCount, 1);

      // The notifier settles a finished order to null in the same call.
      notifier.updateStatus(PendingHlOrderStatus.done);
      await pumpEventQueue();
      expect(container.read(pendingHyperliquidOrderProvider), isNull);
      expect(sink.shown.last.title, 'Order placed');
      expect(sink.shown.where((n) => n.outcome != null), hasLength(1));
      expect(sink.dismissed, isEmpty);
      expect(BackgroundGrace.activeCount, 0);
    });

    test('disposing the container releases the grace', () async {
      final container = ProviderContainer();
      container.read(orderActivityBinderProvider);
      container
          .read(pendingPolymarketBetProvider.notifier)
          .setIntent(bet(PendingBetStatus.awaitingBalance));
      expect(BackgroundGrace.activeCount, 1);
      container.dispose();
      await pumpEventQueue();
      expect(BackgroundGrace.activeCount, 0);
      expect(sink.dismissed, [OrderActivity.noticeIdFor('predictions')]);
    });
  });
}
