// OrderActivity: what the notifications say on Android (ongoing with
// progress, then a result or a dismissal), what iOS posts (a result only,
// only in the background), and nothing at all elsewhere. Never an amount,
// never an id.

import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/services/platform/order_activity.dart';

class _Recorder implements OrderNoticeSink {
  final shown = <OrderNotice>[];
  final dismissed = <int>[];

  @override
  Future<void> show(OrderNotice notice) async => shown.add(notice);

  @override
  Future<void> dismiss(int id) async => dismissed.add(id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Recorder sink;
  const market = 'Will it rain tomorrow? · Yes';
  const amount = 123.45;

  setUp(() {
    OrderActivity.debugReset();
    sink = _Recorder();
    OrderActivity.debugSink = sink;
    OrderActivity.strings = () => lookupAppLocalizations(const Locale('en'));
    OrderActivity.isBackgrounded = () => false;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    OrderActivity.debugReset();
  });

  Future<void> run(Future<void> Function() body) async {
    await body();
    await pumpEventQueue();
  }

  group('Android', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('start posts an indeterminate ongoing notice for the venue', () async {
      await run(() => OrderActivity.start('predictions',
          title: market, venue: OrderVenue.predictions, amountUsd: amount));
      expect(sink.shown, hasLength(1));
      final n = sink.shown.single;
      expect(n.id, OrderActivity.noticeIdFor('predictions'));
      expect(n.title, 'Placing your prediction');
      expect(n.body, market);
      expect(n.progress, isNull);
      expect(n.ongoing, isTrue);
      expect(n.outcome, isNull);
    });

    test('update redraws the same notice with the stage and the percent',
        () async {
      await run(() async {
        await OrderActivity.start('investing',
            title: 'BTC · Perp', venue: OrderVenue.investing, amountUsd: 50);
        await OrderActivity.update('investing',
            stage: OrderStage.waitingMoney, progress: 0.35);
        await OrderActivity.update('investing',
            stage: OrderStage.sending, progress: 0.8);
      });
      expect(sink.shown, hasLength(3));
      final ids = sink.shown.map((n) => n.id).toSet();
      expect(ids, {OrderActivity.noticeIdFor('investing')});
      expect(sink.shown[1].title, 'Placing your order');
      expect(sink.shown[1].body, 'Waiting for your money to arrive');
      expect(sink.shown[1].detail, 'BTC · Perp');
      expect(sink.shown[1].progress, 35);
      expect(sink.shown[2].body, 'Sending your order');
      expect(sink.shown[2].progress, 80);
      expect(sink.shown.every((n) => n.ongoing), isTrue);
    });

    test('a given line replaces the stage sentence; progress is clamped',
        () async {
      await run(() async {
        await OrderActivity.start('predictions',
            title: market, venue: OrderVenue.predictions);
        await OrderActivity.update('predictions',
            stage: OrderStage.confirming, progress: 1.7, line: 'Almost there');
      });
      expect(sink.shown.last.body, 'Almost there');
      expect(sink.shown.last.progress, 100);
    });

    test('every stage has its own sentence', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final lines = OrderStage.values
          .map((s) => OrderActivity.stageLine(l10n, s))
          .toList();
      expect(lines.toSet(), hasLength(OrderStage.values.length));
      expect(lines, contains('Converting your dollars'));
      expect(lines, contains('Setting up your account'));
      expect(lines, contains('Confirming with the venue'));
    });

    test('end in the background replaces the notice with the result',
        () async {
      await run(() async {
        await OrderActivity.start('predictions',
            title: market, venue: OrderVenue.predictions, amountUsd: amount);
        await OrderActivity.update('predictions',
            stage: OrderStage.sending, progress: 0.8);
        OrderActivity.isBackgrounded = () => true;
        await OrderActivity.end('predictions', success: true);
      });
      expect(sink.dismissed, isEmpty);
      final last = sink.shown.last;
      expect(last.id, sink.shown.first.id);
      expect(last.title, 'Prediction placed');
      expect(last.body, market);
      expect(last.detail, isNull);
      expect(last.ongoing, isFalse);
      expect(last.progress, isNull);
      expect(last.outcome, OrderOutcome.placed);
    });

    test('end in front takes the notice down; the slip says the rest',
        () async {
      await run(() async {
        await OrderActivity.start('predictions',
            title: market, venue: OrderVenue.predictions);
        await OrderActivity.end('predictions', success: true);
      });
      expect(sink.shown, hasLength(1));
      expect(sink.dismissed, [OrderActivity.noticeIdFor('predictions')]);
    });

    test('a failure in the background says to open Kute', () async {
      OrderActivity.isBackgrounded = () => true;
      await run(() async {
        await OrderActivity.start('investing',
            title: 'ETH · Perp', venue: OrderVenue.investing);
        await OrderActivity.end('investing', success: false);
      });
      final last = sink.shown.last;
      expect(last.title, 'Order not placed');
      expect(last.body, 'Open Kute to see what happened.');
      expect(last.detail, 'ETH · Perp');
      expect(last.outcome, OrderOutcome.failed);
    });

    test('an unconfirmed order is neither placed nor failed', () async {
      OrderActivity.isBackgrounded = () => true;
      await run(() async {
        await OrderActivity.start('investing',
            title: 'ETH · Perp', venue: OrderVenue.investing);
        await OrderActivity.end('investing',
            success: false, outcome: OrderOutcome.unconfirmed);
      });
      expect(sink.shown.last.title, 'Not confirmed yet');
      expect(sink.shown.last.outcome, OrderOutcome.unconfirmed);
    });

    test('a prediction that failed has its own title', () async {
      OrderActivity.isBackgrounded = () => true;
      await run(() async {
        await OrderActivity.start('predictions',
            title: market, venue: OrderVenue.predictions);
        await OrderActivity.end('predictions', success: false);
      });
      expect(sink.shown.last.title, 'Prediction not placed');
    });

    test('cancel takes the notice down without a result', () async {
      await run(() async {
        await OrderActivity.start('predictions',
            title: market, venue: OrderVenue.predictions);
        await OrderActivity.cancel('predictions');
      });
      expect(sink.shown, hasLength(1));
      expect(sink.dismissed, [OrderActivity.noticeIdFor('predictions')]);
    });

    test('an end with no start says nothing', () async {
      OrderActivity.isBackgrounded = () => true;
      await run(() => OrderActivity.end('predictions', success: true));
      expect(sink.shown, isEmpty);
    });

    test('no notice ever carries the amount or an id', () async {
      OrderActivity.isBackgrounded = () => true;
      await run(() async {
        await OrderActivity.start('predictions',
            title: market, venue: OrderVenue.predictions, amountUsd: amount);
        await OrderActivity.update('predictions',
            stage: OrderStage.converting, progress: 0.5);
        await OrderActivity.end('predictions', success: true);
      });
      for (final n in sink.shown) {
        final text = '${n.title} ${n.body} ${n.detail ?? ''}';
        expect(text, isNot(contains('123')));
        expect(text, isNot(contains('\$')));
        expect(text, isNot(contains('predictions')));
      }
    });

    test('the two venues keep separate, stable notice ids', () {
      expect(OrderActivity.noticeIdFor('predictions'),
          isNot(OrderActivity.noticeIdFor('investing')));
      expect(OrderActivity.noticeIdFor('predictions'),
          OrderActivity.noticeIdFor('predictions'));
      expect(OrderActivity.noticeIdFor('other:1'),
          isNot(OrderActivity.noticeIdFor('other:2')));
    });
  });

  group('iOS', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);

    test('nothing while placing, nothing when it ends in front', () async {
      await run(() async {
        await OrderActivity.start('predictions',
            title: market, venue: OrderVenue.predictions);
        await OrderActivity.update('predictions',
            stage: OrderStage.sending, progress: 0.8);
        await OrderActivity.end('predictions', success: true);
      });
      expect(sink.shown, isEmpty);
      expect(sink.dismissed, isEmpty);
    });

    test('one result notification when it ends in the background', () async {
      await run(() async {
        await OrderActivity.start('investing',
            title: 'BTC · Perp', venue: OrderVenue.investing, amountUsd: 20);
        await OrderActivity.update('investing',
            stage: OrderStage.sending, progress: 0.8);
        OrderActivity.isBackgrounded = () => true;
        await OrderActivity.end('investing', success: true);
      });
      expect(sink.shown, hasLength(1));
      expect(sink.shown.single.title, 'Order placed');
      expect(sink.shown.single.body, 'BTC · Perp');
      expect(sink.shown.single.ongoing, isFalse);
    });

    test('cancel is silent', () async {
      await run(() async {
        await OrderActivity.start('investing',
            title: 'BTC · Perp', venue: OrderVenue.investing);
        await OrderActivity.cancel('investing');
      });
      expect(sink.shown, isEmpty);
      expect(sink.dismissed, isEmpty);
    });
  });

  group('elsewhere', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      OrderActivity.debugSink = null;
    });

    test('is a no-op that never throws', () async {
      expect(OrderActivity.isSupported, isFalse);
      expect(OrderActivity.local, isNull);
      OrderActivity.isBackgrounded = () => true;
      await run(() async {
        await OrderActivity.start('predictions',
            title: market, venue: OrderVenue.predictions, amountUsd: amount);
        await OrderActivity.update('predictions',
            stage: OrderStage.sending, progress: 0.8);
        await OrderActivity.end('predictions', success: true);
        await OrderActivity.cancel('predictions');
      });
    });
  });

  test('every locale has the notice strings', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = lookupAppLocalizations(locale);
      expect(l10n.orderNoticePlacingPrediction, isNotEmpty, reason: '$locale');
      expect(l10n.orderNoticePlacingOrder, isNotEmpty, reason: '$locale');
      expect(l10n.orderNoticeOpenToSee, isNotEmpty, reason: '$locale');
      expect(l10n.orderNoticeProgressChannel, isNotEmpty, reason: '$locale');
      expect(l10n.orderNoticeResultChannel, isNotEmpty, reason: '$locale');
      for (final stage in OrderStage.values) {
        expect(OrderActivity.stageLine(l10n, stage), isNotEmpty,
            reason: '$locale ${stage.name}');
      }
      for (final venue in OrderVenue.values) {
        for (final outcome in OrderOutcome.values) {
          expect(OrderActivity.resultTitle(l10n, venue, outcome), isNotEmpty,
              reason: '$locale ${venue.name} ${outcome.name}');
        }
      }
    }
    expect(AppLocalizations.supportedLocales, hasLength(23));
  });
}
