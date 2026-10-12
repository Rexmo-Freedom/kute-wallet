// The Earn view's two pieces of arithmetic, pinned against Flashnet's
// own payout rule (docs.flashnet.xyz/usdb/rewards): payouts are daily at
// 01:00 UTC, and the only forecast the app draws is the venue's own
// daily estimate added once per day.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/usd/components/usd_earn_chart.dart';

void main() {
  group('usdEarnNextPayoutUtc', () {
    test('counts to 01:00 UTC, not midnight', () {
      final now = DateTime.utc(2026, 10, 12, 18, 30);
      expect(usdEarnNextPayoutUtc(now), DateTime.utc(2026, 10, 13, 1));
    });

    test('between midnight and 01:00 the payment is minutes away', () {
      // The day was cut at 00:00; it is paid at 01:00. The old clock
      // pointed a full day ahead here.
      final now = DateTime.utc(2026, 10, 13, 0, 40);
      expect(usdEarnNextPayoutUtc(now), DateTime.utc(2026, 10, 13, 1));
      expect(usdEarnNextPayoutUtc(now).difference(now),
          const Duration(minutes: 20));
    });

    test('at 01:00 exactly the clock already points to tomorrow', () {
      final now = DateTime.utc(2026, 10, 13, 1);
      expect(usdEarnNextPayoutUtc(now), DateTime.utc(2026, 10, 14, 1));
    });

    test('a local time is read as the UTC instant it is', () {
      // 03:30 in Lisbon summer time (UTC+1) is 02:30 UTC.
      final local = DateTime.utc(2026, 10, 12, 2, 30).toLocal();
      expect(usdEarnNextPayoutUtc(local), DateTime.utc(2026, 10, 13, 1));
    });

    test('rolls over month and year ends', () {
      expect(usdEarnNextPayoutUtc(DateTime.utc(2026, 12, 31, 23, 59)),
          DateTime.utc(2027, 1, 1, 1));
    });
  });

  group('usdEarnCountdownLabel', () {
    test('writes hours unpadded and minutes and seconds padded', () {
      expect(
          usdEarnCountdownLabel(
              const Duration(hours: 6, minutes: 12, seconds: 3)),
          '6h 12m 03s');
      expect(usdEarnCountdownLabel(const Duration(hours: 23, seconds: 59)),
          '23h 00m 59s');
    });

    test('never goes negative', () {
      expect(usdEarnCountdownLabel(const Duration(seconds: -5)), '0h 00m 00s');
    });
  });

  group('UsdEarnProjection', () {
    final days = List.generate(7, (i) => DateTime(2026, 10, 6 + i));
    final byDay = <DateTime, num>{
      DateTime(2026, 10, 7): 100,
      DateTime(2026, 10, 9): 250,
    };

    test('adds the estimate once per day from where the line sits', () {
      final p = UsdEarnProjection.from(
          days: days, byDay: byDay, estimateSats: 50, inSats: true);
      // A third of seven days rounds to 2, floored at 3.
      expect(p.projectedDays, 3);
      expect(p.isOn, isTrue);
      expect(p.days.length, 10);
      expect(p.days.sublist(7), [
        DateTime(2026, 10, 13),
        DateTime(2026, 10, 14),
        DateTime(2026, 10, 15),
      ]);
      // Anchored on the last PAID value inside the window (250), never on
      // a sum of the whole ledger.
      expect(p.byDay[DateTime(2026, 10, 13)], 300);
      expect(p.byDay[DateTime(2026, 10, 14)], 350);
      expect(p.byDay[DateTime(2026, 10, 15)], 400);
      // The history itself is untouched.
      expect(p.byDay[DateTime(2026, 10, 7)], 100);
      expect(p.byDay[DateTime(2026, 10, 9)], 250);
    });

    test('reads in BTC when the wallet does', () {
      final p = UsdEarnProjection.from(
          days: days,
          byDay: {DateTime(2026, 10, 9): 0.0000025},
          estimateSats: 50,
          inSats: false);
      expect(p.byDay[DateTime(2026, 10, 13)], closeTo(0.0000030, 1e-12));
    });

    test('the horizon is a third of the window, between 3 and 90 days', () {
      UsdEarnProjection at(int n) => UsdEarnProjection.from(
            days: List.generate(n, (i) => DateTime(2026, 1, 1 + i)),
            byDay: {DateTime(2026, 1, 1): 1},
            estimateSats: 1,
            inSats: true,
          );
      expect(at(7).projectedDays, 3);
      expect(at(30).projectedDays, 10);
      expect(at(90).projectedDays, 30);
      expect(at(400).projectedDays, 90);
    });

    test('draws nothing without an estimate, days or a ledger', () {
      for (final p in [
        UsdEarnProjection.from(
            days: days, byDay: byDay, estimateSats: 0, inSats: true),
        UsdEarnProjection.from(
            days: const [], byDay: byDay, estimateSats: 50, inSats: true),
        UsdEarnProjection.from(
            days: days, byDay: const {}, estimateSats: 50, inSats: true),
      ]) {
        expect(p.projectedDays, 0);
        expect(p.isOn, isFalse);
      }
      final none = UsdEarnProjection.from(
          days: days, byDay: byDay, estimateSats: 0, inSats: true);
      expect(none.days, days);
      expect(none.byDay, byDay);
    });

    test('projects by calendar day so a clock change cannot double up', () {
      // The last Sunday of October: Europe leaves summer time.
      final window = List.generate(3, (i) => DateTime(2026, 10, 23 + i));
      final p = UsdEarnProjection.from(
          days: window,
          byDay: {DateTime(2026, 10, 23): 10},
          estimateSats: 1,
          inSats: true);
      expect(p.days.sublist(3).map((d) => d.day), [26, 27, 28]);
      expect(p.days.sublist(3).toSet().length, 3);
    });
  });
}
