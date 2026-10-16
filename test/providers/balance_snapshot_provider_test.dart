// `balance_snapshot`: exact amounts, the one-balance rail figures, once
// per session and per 6 hours.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/balance_snapshot_provider.dart';
import 'package:kute/providers/unified_balances_provider.dart';

BalanceSnapshotInputs _known({
  UnifiedVenueBalances venues = const UnifiedVenueBalances(
      investingKnown: true, predictionsKnown: true),
  double waiting = 0,
  double inFlight = 0,
}) =>
    BalanceSnapshotInputs(
      isSpendingAccount: true,
      bitcoinLoaded: true,
      dollarsKnown: true,
      btcSats: 100000,
      usdPerBtc: 100000,
      dollarsUsd: 42.504,
      venues: venues,
      waitingUsd: waiting,
      inFlightUsd: inFlight,
    );

void main() {
  group('balanceSnapshotParams', () {
    test('null until the core figures are known', () {
      expect(balanceSnapshotParams(BalanceSnapshotInputs.notSpending), isNull);
      expect(
          balanceSnapshotParams(const BalanceSnapshotInputs(
              isSpendingAccount: true, bitcoinLoaded: true, dollarsKnown: true)),
          isNull);
    });

    test('exact amounts, venue fields, waiting and in flight', () {
      final p = balanceSnapshotParams(_known(
        venues: const UnifiedVenueBalances(
          readyInInvestingUsd: 3.2,
          readyInPredictionsUsd: 0.6,
          investedInInvestingUsd: 50,
          investedInPredictionsUsd: 12.5,
          investingKnown: true,
          predictionsKnown: true,
        ),
        waiting: 0.6,
        inFlight: 25.004,
      ))!;
      expect(p['btc_usd'], 100);
      expect(p['dollars_usd'], 42.5);
      expect(p['investing_cash_usd'], 3.2);
      expect(p['predictions_cash_usd'], 0.6);
      expect(p['invested_usd'], 62.5);
      expect(p['waiting_usd'], 0.6);
      expect(p['in_flight_usd'], 25);
      // bitcoin, dollars, investing cash and invested are over $1;
      // predictions cash is not, and the rail figures never count.
      expect(p['buckets_with_money'], 4);
      expect(p['wallet_kind'], 'hot');
      expect(p.keys, isNot(contains('order_ref')));
    });

    test('an unknown venue omits its fields and invested', () {
      final p = balanceSnapshotParams(_known(
        venues: const UnifiedVenueBalances(
            readyInPredictionsUsd: 2, predictionsKnown: true),
      ))!;
      expect(p.containsKey('investing_cash_usd'), isFalse);
      expect(p.containsKey('invested_usd'), isFalse);
      expect(p['predictions_cash_usd'], 2);
      expect(p['waiting_usd'], 0);
      expect(p['in_flight_usd'], 0);
    });
  });

  group('BalanceSnapshotReporter', () {
    test('sends at once when every venue is known, then never again',
        () {
      final sent = <Map<String, Object>>[];
      DateTime? stamp;
      final r = BalanceSnapshotReporter(
        clock: () => DateTime(2026, 10, 12, 12),
        readLastSentAt: () => stamp,
        writeLastSentAt: (at) => stamp = at,
        analyticsDisabled: () => false,
        send: (event, params) {
          expect(event, 'balance_snapshot');
          sent.add(params);
        },
      );
      r.observe(_known());
      r.observe(_known(waiting: 5));
      expect(sent.length, 1);
      expect(r.isDone, isTrue);
      expect(stamp, DateTime(2026, 10, 12, 12));
    });

    test('a snapshot sent under six hours ago is not repeated', () {
      var sends = 0;
      final r = BalanceSnapshotReporter(
        clock: () => DateTime(2026, 10, 12, 12),
        readLastSentAt: () => DateTime(2026, 10, 12, 7),
        writeLastSentAt: (_) {},
        analyticsDisabled: () => false,
        send: (_, __) => sends++,
      );
      r.observe(_known());
      expect(sends, 0);
      expect(r.isDone, isTrue);
    });

    test('an unknown venue waits the grace, then sends what is known', () {
      fakeAsync((async) {
        var sends = 0;
        final r = BalanceSnapshotReporter(
          clock: () => DateTime(2026, 10, 12, 12),
          readLastSentAt: () => null,
          writeLastSentAt: (_) {},
          analyticsDisabled: () => false,
          send: (_, params) {
            sends++;
            expect(params.containsKey('investing_cash_usd'), isFalse);
          },
        );
        r.observe(_known(
            venues: const UnifiedVenueBalances(predictionsKnown: true)));
        async.elapse(const Duration(seconds: 19));
        expect(sends, 0);
        async.elapse(const Duration(seconds: 2));
        expect(sends, 1);
      });
    });

    test('analytics off leaves the slot for a session that can send', () {
      var sends = 0;
      final r = BalanceSnapshotReporter(
        clock: () => DateTime(2026, 10, 12, 12),
        readLastSentAt: () => null,
        writeLastSentAt: (_) {},
        analyticsDisabled: () => true,
        send: (_, __) => sends++,
      );
      r.observe(_known());
      expect(sends, 0);
      expect(r.isDone, isFalse);
    });
  });
}
