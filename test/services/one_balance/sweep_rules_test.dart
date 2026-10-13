// The never-sweep rules as a table: each case is one line of the plan's
// "Never sweep" list, plus the batching and rate-limit rules.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/sweep_rules.dart';

final _now = DateTime(2026, 10, 12, 12);

SweepContext _ctx({
  double minimumUsd = 1,
  bool unlocked = true,
  bool owner = true,
  DateTime? backoffUntil,
  DateTime? lastSweepAt,
  DateTime? heldSince,
  bool eventDriven = false,
  bool flushHeld = false,
}) =>
    SweepContext(
      now: _now,
      minimumUsd: minimumUsd,
      sessionUnlocked: unlocked,
      spendingWalletActive: owner,
      backoffUntil: backoffUntil,
      lastSweepAt: lastSweepAt,
      heldSince: heldSince,
      eventDriven: eventDriven,
      flushHeld: flushHeld,
    );

SweepSkipReason _skip(SweepDecision d) => (d as SweepSkip).reason;

SwapOrder _row({
  required String coinFrom,
  required String networkFrom,
  required String coinTo,
  required String networkTo,
  String status = 'exchanging',
  String? walletId = 'w1',
  String provider = 'Orchestra',
  DateTime? at,
}) =>
    SwapOrder(
      id: 'ord_$coinFrom$networkFrom$coinTo$networkTo$status',
      coinFrom: coinFrom,
      networkFrom: networkFrom,
      coinTo: coinTo,
      networkTo: networkTo,
      depositAddress: 'd',
      depositAmount: '10',
      withdrawalAmount: '9.9',
      status: status,
      timestamp: (at ?? _now).millisecondsSinceEpoch,
      withdrawalAddress: 'r',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: 'f',
      provider: provider,
      walletId: walletId,
    );

void main() {
  group('decideSweep', () {
    test('nothing idle is nothing to do', () {
      expect(
          decideSweep(const VenueSnapshot(idleUsd: 0, sweepableUsd: 0), _ctx()),
          isA<SweepNothing>());
      expect(
          decideSweep(
              const VenueSnapshot(idleUsd: 0.004, sweepableUsd: 0.004), _ctx()),
          isA<SweepNothing>());
    });

    test('a locked session or a non-owner wallet waits', () {
      const s = VenueSnapshot(idleUsd: 20, sweepableUsd: 20);
      expect(_skip(decideSweep(s, _ctx(unlocked: false))),
          SweepSkipReason.locked);
      expect(_skip(decideSweep(s, _ctx(owner: false))), SweepSkipReason.locked);
    });

    test('a backoff still running blocks, an expired one does not', () {
      const s = VenueSnapshot(idleUsd: 20, sweepableUsd: 20);
      expect(
          _skip(decideSweep(
              s, _ctx(backoffUntil: _now.add(const Duration(minutes: 1))))),
          SweepSkipReason.backoff);
      expect(
          decideSweep(s,
              _ctx(backoffUntil: _now.subtract(const Duration(seconds: 1)))),
          isA<SweepNow>());
    });

    test('a deposit or withdrawal still in flight blocks', () {
      const s = VenueSnapshot(idleUsd: 20, sweepableUsd: 20, hasPendingMove: true);
      expect(_skip(decideSweep(s, _ctx())), SweepSkipReason.pendingDeposit);
    });

    test('90 s grace after the last deposit settled', () {
      final fresh = VenueSnapshot(
          idleUsd: 20,
          sweepableUsd: 20,
          lastDepositSettledAt: _now.subtract(const Duration(seconds: 89)));
      expect(_skip(decideSweep(fresh, _ctx())), SweepSkipReason.grace);
      final old = VenueSnapshot(
          idleUsd: 20,
          sweepableUsd: 20,
          lastDepositSettledAt: _now.subtract(const Duration(seconds: 91)));
      expect(decideSweep(old, _ctx()), isA<SweepNow>());
    });

    test('a claim mid-flight blocks before any order rule', () {
      const s = VenueSnapshot(
          idleUsd: 20, sweepableUsd: 20, isClaiming: true, isPlacing: true);
      expect(_skip(decideSweep(s, _ctx())), SweepSkipReason.claiming);
    });

    test('a pending intent, a placing tile or an open TWAP blocks', () {
      for (final s in const [
        VenueSnapshot(idleUsd: 20, sweepableUsd: 20, hasPendingIntent: true),
        VenueSnapshot(idleUsd: 20, sweepableUsd: 20, isPlacing: true),
        VenueSnapshot(idleUsd: 20, sweepableUsd: 20, hasOpenTwap: true),
      ]) {
        expect(_skip(decideSweep(s, _ctx())), SweepSkipReason.openOrders);
      }
    });

    test('only the sweepable part moves; fully reserved cash skips', () {
      final partial = decideSweep(
          const VenueSnapshot(
              idleUsd: 20, sweepableUsd: 12, hasReservations: true),
          _ctx());
      expect((partial as SweepNow).usd, 12);
      expect(
          _skip(decideSweep(
              const VenueSnapshot(
                  idleUsd: 20, sweepableUsd: 0, hasReservations: true),
              _ctx())),
          SweepSkipReason.openOrders);
    });

    test('sweepable never exceeds idle', () {
      final d = decideSweep(
          const VenueSnapshot(idleUsd: 8, sweepableUsd: 50), _ctx());
      expect((d as SweepNow).usd, 8);
    });

    test('a rail with nothing withdrawable and nothing reserved waits', () {
      final d = decideSweep(
          const VenueSnapshot(idleUsd: 20, sweepableUsd: 0), _ctx());
      expect(d, isA<SweepWaiting>());
      expect((d as SweepWaiting).cause, SweepWaitingCause.routeUnavailable);
      expect(d.usd, 20);
    });

    test('below the minimum is dust, never waiting', () {
      final d = decideSweep(
          const VenueSnapshot(idleUsd: 0.6, sweepableUsd: 0.6), _ctx());
      expect((d as SweepDust).usd, 0.6);
      final live = decideSweep(
          const VenueSnapshot(idleUsd: 3, sweepableUsd: 3),
          _ctx(minimumUsd: 4));
      expect((live as SweepDust).usd, 3);
    });

    test('the CCTP reserve left on HyperCore is dust', () {
      final d = decideSweep(
          const VenueSnapshot(idleUsd: 0.06, sweepableUsd: 0.06), _ctx());
      expect((d as SweepDust).usd, 0.06);
    });

    test('dust wins over a backoff, a pending move and a rail not ready', () {
      final now = DateTime(2026, 10, 13, 13);
      expect(
          decideSweep(
              const VenueSnapshot(idleUsd: 0.4, sweepableUsd: 0.4),
              SweepContext(
                  now: now,
                  minimumUsd: 1,
                  backoffUntil: now.add(const Duration(minutes: 5)))),
          isA<SweepDust>());
      expect(
          decideSweep(
              const VenueSnapshot(
                  idleUsd: 0.4, sweepableUsd: 0.4, hasPendingMove: true),
              _ctx()),
          isA<SweepDust>());
      expect(
          (decideSweep(const VenueSnapshot(idleUsd: 0.4, sweepableUsd: 0),
                  _ctx()) as SweepDust)
              .usd,
          0.4);
    });

    test('with reservations only the unreserved cash is dust', () {
      final small = decideSweep(
          const VenueSnapshot(
              idleUsd: 0.8, sweepableUsd: 0.3, hasReservations: true),
          _ctx());
      expect((small as SweepDust).usd, 0.3);
      final reserved = decideSweep(
          const VenueSnapshot(
              idleUsd: 30, sweepableUsd: 0.5, hasReservations: true),
          _ctx());
      expect((reserved as SweepDust).usd, 0.5);
    });

    test('at or above the minimum it still waits as before', () {
      final batching = decideSweep(
          const VenueSnapshot(idleUsd: 1, sweepableUsd: 1), _ctx());
      expect((batching as SweepWaiting).cause, SweepWaitingCause.batching);
      final rail = decideSweep(
          const VenueSnapshot(idleUsd: 1.5, sweepableUsd: 0), _ctx());
      expect((rail as SweepWaiting).cause, SweepWaitingCause.routeUnavailable);
    });

    test('exactly the minimum is not below it', () {
      final d = decideSweep(
          const VenueSnapshot(idleUsd: 6, sweepableUsd: 6),
          _ctx(minimumUsd: 6));
      expect(d, isA<SweepNow>());
    });

    test('at or above \$5 sweeps at once', () {
      expect(
          decideSweep(const VenueSnapshot(idleUsd: 5, sweepableUsd: 5), _ctx()),
          isA<SweepNow>());
    });

    test('between the minimum and \$5 holds up to 10 minutes', () {
      const s = VenueSnapshot(idleUsd: 3, sweepableUsd: 3);
      final hold = decideSweep(s, _ctx());
      expect((hold as SweepWaiting).cause, SweepWaitingCause.batching);
      final stillHeld = decideSweep(
          s, _ctx(heldSince: _now.subtract(const Duration(minutes: 9))));
      expect(stillHeld, isA<SweepWaiting>());
      final due = decideSweep(
          s, _ctx(heldSince: _now.subtract(const Duration(minutes: 10))));
      expect((due as SweepNow).usd, 3);
    });

    test('leaving the foreground flushes a held batch', () {
      final d = decideSweep(const VenueSnapshot(idleUsd: 3, sweepableUsd: 3),
          _ctx(flushHeld: true));
      expect(d, isA<SweepNow>());
    });

    test('one sweep per venue per 10 minutes unless event-driven', () {
      const s = VenueSnapshot(idleUsd: 50, sweepableUsd: 50);
      final recent = _now.subtract(const Duration(minutes: 4));
      final limited = decideSweep(s, _ctx(lastSweepAt: recent));
      expect((limited as SweepWaiting).cause, SweepWaitingCause.batching);
      expect(decideSweep(s, _ctx(lastSweepAt: recent, eventDriven: true)),
          isA<SweepNow>());
      expect(
          decideSweep(
              s, _ctx(lastSweepAt: _now.subtract(const Duration(minutes: 10)))),
          isA<SweepNow>());
    });
  });

  group('row predicates', () {
    test('venue networks and deposit rows', () {
      expect(venueNetworksOf(OneBalanceVenue.predictions), {'POLYGON'});
      expect(venueNetworksOf(OneBalanceVenue.investing), {'HYPERCORE'});
      final pm = _row(
          coinFrom: 'USDB', networkFrom: 'SPARK', coinTo: 'USDC', networkTo: 'POLYGON');
      expect(venueDepositRowOf(pm, walletId: 'w1'), OneBalanceVenue.predictions);
      final hl = _row(
          coinFrom: 'USDB', networkFrom: 'SPARK', coinTo: 'USDC', networkTo: 'HYPERCORE');
      expect(venueDepositRowOf(hl, walletId: 'w1'), OneBalanceVenue.investing);
      expect(venueDepositRowOf(hl, walletId: 'other'), isNull);
      // A receive from a HyperEVM chain is dollars arriving, never a
      // venue move.
      final receive = _row(
          coinFrom: 'USDC', networkFrom: 'HYPEREVM', coinTo: 'USDB', networkTo: 'SPARK');
      expect(venueWithdrawalRowOf(receive, walletId: 'w1'), isNull);
      final btc = _row(
          coinFrom: 'BTC', networkFrom: 'SPARK', coinTo: 'USDB', networkTo: 'SPARK');
      expect(venueDepositRowOf(btc, walletId: 'w1'), isNull);
    });

    test('pending moves carry venue and direction, capped at 30 minutes', () {
      final nowMs = _now.millisecondsSinceEpoch;
      final deposit = _row(
          coinFrom: 'USDB', networkFrom: 'SPARK', coinTo: 'USDC', networkTo: 'POLYGON');
      expect(pendingVenueMoveOf(deposit, walletId: 'w1', nowMs: nowMs),
          (OneBalanceVenue.predictions, InFlightKind.toVenue));
      final sweep = _row(
          coinFrom: 'USDC.e', networkFrom: 'POLYGON', coinTo: 'USDB', networkTo: 'SPARK');
      expect(pendingVenueMoveOf(sweep, walletId: 'w1', nowMs: nowMs),
          (OneBalanceVenue.predictions, InFlightKind.fromVenue));
      final hl = _row(
          coinFrom: 'USDC', networkFrom: 'HYPERCORE', coinTo: 'USDB', networkTo: 'SPARK');
      expect(pendingVenueMoveOf(hl, walletId: 'w1', nowMs: nowMs),
          (OneBalanceVenue.investing, InFlightKind.fromVenue));
      final done = _row(
          coinFrom: 'USDB', networkFrom: 'SPARK', coinTo: 'USDC', networkTo: 'POLYGON',
          status: 'success');
      expect(pendingVenueMoveOf(done, walletId: 'w1', nowMs: nowMs), isNull);
      final stale = _row(
          coinFrom: 'USDB', networkFrom: 'SPARK', coinTo: 'USDC', networkTo: 'POLYGON',
          at: _now.subtract(const Duration(minutes: 31)));
      expect(pendingVenueMoveOf(stale, walletId: 'w1', nowMs: nowMs), isNull);
    });
  });
}
