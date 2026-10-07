import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/cash_app_status.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/swap_order_model.dart';

final _closedAt = DateTime.utc(2020, 1, 1, 12);

SwapOrder _row({
  String id = 'ord_1',
  String status = 'pending',
  DateTime? expiresAt,
}) =>
    SwapOrder(
      id: id,
      coinFrom: 'BTC',
      networkFrom: 'LIGHTNING',
      coinTo: 'BTC',
      networkTo: 'SPARK',
      depositAddress: 'lnbc1invoice',
      depositAmount: '0.001',
      withdrawalAmount: '0.00099',
      status: status,
      timestamp: 1000,
      withdrawalAddress: '',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      purchaseSource: 'cashapp',
      purchaseFiatUsd: '55.00',
      expiresAt: (expiresAt ?? _closedAt).millisecondsSinceEpoch,
    );

SwapOrder _inWindow({String id = 'ord_open'}) =>
    _row(id: id, expiresAt: DateTime.now().add(const Duration(days: 1)));

void main() {
  group('closed window cadence', () {
    test('keeps the normal rate through the grace period, then slows down',
        () {
      Duration? interval(Duration since) =>
          cashAppClosedWindowPollInterval(since);
      expect(interval(const Duration(minutes: -5)), Duration.zero);
      expect(interval(Duration.zero), Duration.zero);
      expect(interval(kCashAppPaymentGracePeriod - const Duration(seconds: 1)),
          Duration.zero);
      expect(interval(kCashAppPaymentGracePeriod), const Duration(minutes: 1));
      expect(interval(const Duration(minutes: 59)), const Duration(minutes: 1));
      expect(interval(const Duration(hours: 1)), const Duration(minutes: 10));
      expect(interval(const Duration(hours: 23)), const Duration(minutes: 10));
      expect(interval(const Duration(hours: 24)), const Duration(hours: 1));
      expect(interval(const Duration(days: 13)), const Duration(hours: 1));
      expect(interval(const Duration(days: 14)), isNull);
    });

    test('due times follow the interval, app start, foreground and clock',
        () {
      bool due(Duration sinceClosed, Duration sincePoll,
          {Duration sinceForeground = const Duration(days: 30)}) {
        final now = _closedAt.add(sinceClosed);
        return cashAppClosedWindowPollDue(
          now: now,
          closedAt: _closedAt,
          lastPolledAt: now.subtract(sincePoll),
          foregroundedAt: now.subtract(sinceForeground),
        );
      }

      expect(
          cashAppClosedWindowPollDue(
            now: _closedAt.add(const Duration(days: 40)),
            closedAt: _closedAt,
            lastPolledAt: null,
            foregroundedAt: _closedAt,
          ),
          isTrue);
      expect(due(const Duration(seconds: 30), Duration.zero), isTrue);
      expect(due(const Duration(minutes: 10), const Duration(seconds: 59)),
          isFalse);
      expect(due(const Duration(minutes: 10), const Duration(seconds: 60)),
          isTrue);
      expect(due(const Duration(hours: 2), const Duration(minutes: 9)), isFalse);
      expect(due(const Duration(hours: 2), const Duration(minutes: 10)), isTrue);
      expect(due(const Duration(days: 2), const Duration(minutes: 59)), isFalse);
      expect(due(const Duration(days: 2), const Duration(hours: 1)), isTrue);
      expect(due(const Duration(days: 20), const Duration(days: 5)), isFalse);
      expect(
          due(const Duration(days: 20), const Duration(days: 5),
              sinceForeground: const Duration(minutes: 1)),
          isTrue);
      // The clock moved back past the last check.
      expect(due(const Duration(days: 2), const Duration(hours: -3)), isTrue);
    });
  });

  group('closed window schedule', () {
    test('in-window and paid rows are always due, closed rows follow cadence',
        () {
      var now = _closedAt.add(const Duration(seconds: 30));
      final schedule = CashAppClosedWindowSchedule(now: () => now);
      final closed = _row();
      final paid = _row(id: 'ord_paid', status: 'exchanging');
      final open = _inWindow();
      expect(closed.cashAppWindowClosedAt, _closedAt.millisecondsSinceEpoch);

      for (var i = 0; i < 3; i++) {
        expect(schedule.begin(open), isTrue);
        expect(schedule.begin(paid), isTrue);
        // Inside the grace period every background poll checks.
        expect(schedule.begin(closed), isTrue);
        schedule.recordSuccess(closed.id);
      }

      now = _closedAt.add(const Duration(minutes: 5));
      expect(schedule.begin(closed), isTrue);
      schedule.recordSuccess(closed.id);
      now = now.add(const Duration(seconds: 59));
      expect(schedule.isDue(closed), isFalse);
      expect(schedule.begin(closed), isFalse);
      now = now.add(const Duration(seconds: 1));
      expect(schedule.begin(closed), isTrue);
      schedule.recordSuccess(closed.id);

      now = _closedAt.add(const Duration(hours: 5));
      expect(schedule.begin(closed), isTrue);
      schedule.recordSuccess(closed.id);
      now = now.add(const Duration(minutes: 9));
      expect(schedule.begin(closed), isFalse);
      now = now.add(const Duration(minutes: 1));
      expect(schedule.begin(closed), isTrue);
      schedule.recordSuccess(closed.id);
    });

    test('after 14 days only app start and a return to the foreground check',
        () {
      var now = _closedAt.add(const Duration(days: 20));
      final schedule = CashAppClosedWindowSchedule(now: () => now);
      final legacy = _row();
      expect(schedule.begin(legacy), isTrue);
      schedule.recordSuccess(legacy.id);
      now = now.add(const Duration(days: 3));
      expect(schedule.begin(legacy), isFalse);

      schedule.markForegrounded();
      now = now.add(const Duration(seconds: 1));
      expect(schedule.begin(legacy), isTrue);
      schedule.recordSuccess(legacy.id);
      now = now.add(const Duration(hours: 6));
      expect(schedule.begin(legacy), isFalse);
    });

    test('a failed check is retried once after a minute', () {
      var now = _closedAt.add(const Duration(days: 20));
      final schedule = CashAppClosedWindowSchedule(now: () => now);
      final legacy = _row();
      expect(schedule.begin(legacy), isTrue);
      now = now.add(const Duration(seconds: 59));
      expect(schedule.begin(legacy), isFalse);
      now = now.add(const Duration(seconds: 1));
      expect(schedule.begin(legacy), isTrue);
      now = now.add(const Duration(hours: 5));
      expect(schedule.begin(legacy), isFalse);

      schedule.markForegrounded();
      now = now.add(const Duration(seconds: 1));
      expect(schedule.begin(legacy), isTrue);
      schedule.recordSuccess(legacy.id);
      now = now.add(const Duration(minutes: 5));
      expect(schedule.begin(legacy), isFalse);
    });

    test('a clock moved back never delays a check', () {
      var now = _closedAt.add(const Duration(hours: 5));
      final schedule = CashAppClosedWindowSchedule(now: () => now);
      final closed = _row();
      expect(schedule.begin(closed), isTrue);
      schedule.recordSuccess(closed.id);
      now = now.subtract(const Duration(hours: 1));
      expect(schedule.begin(closed), isTrue);
    });

    test('a row that reopens is always due and starts over when it closes',
        () {
      final now = _closedAt.add(const Duration(hours: 5));
      final schedule = CashAppClosedWindowSchedule(now: () => now);
      final closed = _row();
      expect(schedule.begin(closed), isTrue);
      schedule.recordSuccess(closed.id);
      expect(schedule.begin(closed), isFalse);
      expect(schedule.begin(closed.copyWith(status: 'exchanging')), isTrue);
      expect(schedule.begin(closed), isTrue);
    });

    test('only a due order closed within a day keeps sync running off route',
        () {
      var now = _closedAt.add(const Duration(hours: 3));
      final schedule = CashAppClosedWindowSchedule(now: () => now);
      final closed = _row();
      final older = _row(
          id: 'ord_older',
          expiresAt: _closedAt.subtract(const Duration(days: 2)));
      final open = _inWindow();
      final paid = _row(id: 'ord_paid', status: 'exchanging');

      expect(schedule.anyRecentlyClosedDue([older, open, paid]), isFalse);
      expect(schedule.anyRecentlyClosedDue([closed, older, open]), isTrue);
      expect(schedule.begin(closed), isTrue);
      schedule.recordSuccess(closed.id);
      expect(schedule.anyRecentlyClosedDue([closed, older, open]), isFalse);
      now = now.add(const Duration(minutes: 10));
      expect(schedule.anyRecentlyClosedDue([closed]), isTrue);
      now = _closedAt.add(const Duration(hours: 25));
      expect(schedule.anyRecentlyClosedDue([closed]), isFalse);
    });
  });

  test('Cash App status labels are localized', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final pt = lookupAppLocalizations(const Locale('pt'));
    expect(cashAppStatusLabel(_inWindow(), en), en.awaitingPayment);
    expect(cashAppStatusLabel(_row(), en), 'Payment window ended');
    expect(cashAppStatusLabel(_row(), pt), pt.cashAppPaymentWindowEnded);
    expect(
        cashAppStatusLabel(
            _row(status: 'unfulfilled', expiresAt: DateTime.now().add(
                const Duration(days: 1))),
            en),
        en.cashAppPaymentWindowEnded);
    for (final status in ['exchanging', 'confirmation', 'sending']) {
      expect(cashAppStatusLabel(_row(status: status), en), en.processing);
    }
    expect(cashAppStatusLabel(_row(status: 'quoted'), en), en.pending);
    expect(cashAppStatusLabel(_row(status: 'success'), en), en.completed);
    expect(cashAppStatusLabel(_row(status: 'refunded'), en), en.refunded);
    expect(cashAppStatusLabel(_row(status: 'expired'), en), en.expired);
    expect(cashAppStatusLabel(_row(status: 'overdue'), en), en.refunding);
  });
}
