// Venue cash as a Dollars shortfall: the pure planner (Dollars first,
// Predictions before Investing, minimums, the cost gross-up, partial
// cover, exclude), the two sources (Investing refuses while a cross
// position or a resting perp order could lean on its cash), and the
// puller (parallel legs, one failing leaves the others, the bounded wait,
// the analytics).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/one_balance/venue_sweeper.dart'
    show SweepableVenueFunder;
import 'package:kute/services/tracking_service.dart';

import '../../helpers/fake_hyperliquid_move_rail.dart';

const _p = OneBalanceVenue.predictions;
const _i = OneBalanceVenue.investing;

VenueCashCandidate _c(OneBalanceVenue venue, double available,
        {double minimum = 1, Duration? eta}) =>
    (
      venue: venue,
      availableUsd: available,
      eta: eta ?? kVenuePullEta[venue]!,
      minimumUsd: minimum,
    );

HlPerpPosition _position({required bool cross, double szi = 1}) =>
    HlPerpPosition(
      coin: 'BTC',
      szi: szi,
      entryPx: 100000,
      positionValue: 100,
      unrealizedPnl: 0,
      returnOnEquity: 0,
      liquidationPx: null,
      marginUsed: 10,
      leverageType: cross ? 'cross' : 'isolated',
      leverageValue: 10,
      maxLeverage: 40,
    );

HlOpenOrder _order(String coin) => HlOpenOrder(
      coin: coin,
      oid: 1,
      isBuy: true,
      limitPx: 1,
      sz: 1,
      origSz: 1,
      timestamp: 0,
      cloid: null,
      reduceOnly: false,
      orderType: 'Limit',
      isTrigger: false,
      triggerPx: null,
    );

class _Rail extends FakeHyperliquidMoveRail {
  final withdraws = <({double usd, MoveAuthorization auth, String purpose})>[];

  @override
  Future<VenueMoveResult> withdrawToDollars({
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'sweep',
  }) async {
    withdraws.add((usd: usd, auth: auth, purpose: purpose));
    return VenueMoveResult(
        quoteId: 'cctp', sentUsd: usd, arrivingUsdEstimate: usd - 0.2);
  }
}

class _Funder implements SweepableVenueFunder {
  double idle = 0;
  Object? idleError;
  final sweeps = <({double usd, MoveAuthorization auth, String purpose})>[];

  @override
  Future<double> idleUsd() async {
    final e = idleError;
    if (e != null) throw e;
    return idle;
  }

  @override
  Future<VenueMoveResult> sweepToDollars({
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'sweep',
  }) async {
    sweeps.add((usd: usd, auth: auth, purpose: purpose));
    return VenueMoveResult(
        quoteId: 'q', sentUsd: usd, arrivingUsdEstimate: usd * 0.99);
  }

  @override
  Future<VenueMoveResult> fund(
          {required double usd,
          required MoveAuthorization auth,
          String purpose = 'order_funding'}) =>
      throw UnimplementedError();

  @override
  Future<double> minimumUsd() async => 1;

  @override
  Future<VenueMoveQuote> estimate(double usd) => throw UnimplementedError();
}

/// A source the test drives: its pull waits on [gate] when set.
class _Source implements VenueCashSource {
  _Source(this.venue, this.available, {this.error});

  @override
  final OneBalanceVenue venue;
  double available;
  Object? error;
  Completer<void>? gate;
  final pulls = <({double usd, String purpose})>[];
  bool started = false;

  @override
  Duration get estimatedArrival => kVenuePullEta[venue]!;

  @override
  Future<double> availableUsd() async => available;

  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) async {
    started = true;
    pulls.add((usd: usd, purpose: purpose));
    final g = gate;
    if (g != null) await g.future;
    final e = error;
    if (e != null) throw e;
    available -= usd;
    return VenueMoveResult(
        quoteId: 'q-${venue.name}',
        sentUsd: usd,
        arrivingUsdEstimate: usd * 0.99);
  }
}

void main() {
  group('planDollarsShortfall', () {
    test('Dollars that cover the amount pull nothing', () {
      final plan = planDollarsShortfall(
          neededUsd: 40, dollarsUsd: 50, sources: [_c(_p, 100)]);
      expect(plan.covers, isTrue);
      expect(plan.dollarsOnly, isTrue);
      expect(plan.pulls, isEmpty);
      expect(plan.eta, Duration.zero);
      expect(plan.dollarsUsd, 40);
    });

    test('Dollars first, then Predictions before Investing, grossed up', () {
      final plan = planDollarsShortfall(
          neededUsd: 100, dollarsUsd: 50, sources: [_c(_i, 500), _c(_p, 500)]);
      expect(plan.covers, isTrue);
      expect(plan.pulls, hasLength(1));
      final pull = plan.pulls.single;
      expect(pull.venue, _p);
      // 50 / 0.98 = 51.0204… → 51.03, which lands at least 50.
      expect(pull.usd, 51.03);
      expect(pull.arrivingUsd, greaterThanOrEqualTo(50));
      expect(plan.eta, kVenuePullEta[_p]);
      expect(plan.uncoveredUsd, 0);
    });

    test('a venue short of its share gives what it has; the next covers', () {
      final plan = planDollarsShortfall(
          neededUsd: 100,
          dollarsUsd: 50,
          sources: [_c(_p, 20), _c(_i, 500, minimum: 0.91)]);
      expect(plan.covers, isTrue);
      expect(plan.pulls.map((p) => p.venue), [_p, _i]);
      expect(plan.pulls[0].usd, 20);
      // 50 − 19.6 = 30.4; (30.4 + 0.30) / 0.98 = 31.326… → 31.33.
      expect(plan.pulls[1].usd, 31.33);
      expect(plan.arrivingUsd, greaterThanOrEqualTo(50));
      // The slowest leg sets the ETA.
      expect(plan.eta, kVenuePullEta[_i]);
    });

    test('every pull is at least the route minimum', () {
      final plan = planDollarsShortfall(
          neededUsd: 10.2, dollarsUsd: 10, sources: [_c(_p, 50, minimum: 1)]);
      expect(plan.pulls.single.usd, 1.0);
      final hl = planDollarsShortfall(
          neededUsd: 10.2,
          dollarsUsd: 10,
          sources: [_c(_i, 50, minimum: 0.91)]);
      // Investing's floor carries the CCTP allowance so the net clears it.
      expect(hl.pulls.single.usd, 1.21);
    });

    test('a venue whose cash is below its minimum is skipped', () {
      final plan = planDollarsShortfall(
          neededUsd: 12,
          dollarsUsd: 10,
          sources: [_c(_p, 0.5, minimum: 1), _c(_i, 50, minimum: 0.91)]);
      expect(plan.pulls.single.venue, _i);
    });

    test('never more than a venue holds; the rest is uncovered', () {
      final plan = planDollarsShortfall(
          neededUsd: 100, dollarsUsd: 10, sources: [_c(_p, 30), _c(_i, 20)]);
      expect(plan.covers, isFalse);
      expect(plan.pulls.map((p) => p.usd), [30, 20]);
      // 90 − 29.4 − (20 × 0.98 − 0.30) = 41.3.
      expect(plan.uncoveredUsd, 41.3);
    });

    test('exclude leaves the target venue out', () {
      final plan = planDollarsShortfall(
          neededUsd: 20,
          dollarsUsd: 10,
          sources: [_c(_p, 500), _c(_i, 500)],
          exclude: _p);
      expect(plan.pulls.single.venue, _i);
    });

    test('a cost estimate replaces the allowance', () {
      final plan = planDollarsShortfall(
          neededUsd: 20,
          dollarsUsd: 10,
          sources: [_c(_p, 500)],
          costOf: (_) => (share: 0.0, fixedUsd: 0.0));
      expect(plan.pulls.single.usd, 10);
    });

    test('rounds the amount to the cent up', () {
      final plan = planDollarsShortfall(
          neededUsd: 10.001,
          dollarsUsd: 0,
          sources: [_c(_p, 500)],
          costOf: (_) => (share: 0.0, fixedUsd: 0.0));
      expect(plan.neededUsd, 10.01);
      expect(plan.pulls.single.usd, 10.01);
    });

    test('reach is Dollars plus every venue net of its cost', () {
      expect(
          venueCashReachUsd(dollarsUsd: 10, sources: [_c(_p, 50), _c(_i, 0.5)]),
          10 + 49);
      expect(
          venueCashReachUsd(dollarsUsd: 10, sources: [_c(_p, 50)], exclude: _p),
          10);
    });
  });

  group('sources', () {
    test('Investing: the rail sendable less the CCTP reserve', () async {
      final rail = _Rail()..withdrawable = 40;
      final source = HyperliquidCashSource(rail,
          readGuard: () async => (
                positions: const <HlPerpPosition>[],
                openOrders: const <HlOpenOrder>[]
              ));
      expect(source.venue, _i);
      expect(await source.availableUsd(), closeTo(39.94, 1e-9));
    });

    test('Investing refuses with a cross position or a resting perp order',
        () async {
      final rail = _Rail()..withdrawable = 40;
      HlPullGuardState? state = (
        positions: [_position(cross: true)],
        openOrders: const <HlOpenOrder>[]
      );
      final source = HyperliquidCashSource(rail, readGuard: () async => state);
      expect(await source.availableUsd(), 0);
      await expectLater(source.pull(5, purpose: 'cash_pull'),
          throwsA(isA<RouteUnavailable>()));
      expect(rail.withdraws, isEmpty);

      state = (positions: const [], openOrders: [_order('ETH')]);
      expect(await source.availableUsd(), 0);
      await expectLater(source.pull(5, purpose: 'cash_pull'),
          throwsA(isA<RouteUnavailable>()));

      // Isolated positions and spot orders do not lean on the cash.
      state = (
        positions: [_position(cross: false)],
        openOrders: [_order('@107'), _order('PURR/USDC')]
      );
      expect(await source.availableUsd(), closeTo(39.94, 1e-9));

      // An unreadable account is nothing.
      state = null;
      expect(await source.availableUsd(), 0);
    });

    test('Investing pulls home under the automatic sweep authorization',
        () async {
      final rail = _Rail()..withdrawable = 40;
      final source = HyperliquidCashSource(rail,
          readGuard: () async => (
                positions: const <HlPerpPosition>[],
                openOrders: const <HlOpenOrder>[]
              ));
      final result = await source.pull(12.5, purpose: 'cash_pull');
      expect(result.sentUsd, 12.5);
      expect(rail.withdraws.single.usd, 12.5);
      expect(rail.withdraws.single.auth, same(SweepAuthorization.automatic));
      expect(rail.withdraws.single.purpose, 'cash_pull');
    });

    test('hlPullAllowed ignores a flat cross row', () {
      expect(
          hlPullAllowed((
            positions: [_position(cross: true, szi: 0)],
            openOrders: const []
          )),
          isTrue);
    });

    test('Predictions: idle cash, swept home automatically', () async {
      final funder = _Funder()..idle = 25;
      final source = PolymarketCashSource(funder);
      expect(source.venue, _p);
      expect(await source.availableUsd(), 25);
      await source.pull(10, purpose: 'cash_pull');
      expect(funder.sweeps.single.usd, 10);
      expect(funder.sweeps.single.auth, same(SweepAuthorization.automatic));
      expect(funder.sweeps.single.purpose, 'cash_pull');

      funder.idleError = StateError('orders unreadable');
      expect(await source.availableUsd(), 0);
    });
  });

  group('VenueCashPuller', () {
    late List<(String, Map<String, Object>?)> events;
    late DateTime now;
    late double dollars;

    setUp(() {
      events = [];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      now = DateTime(2026, 10, 13, 12);
      dollars = 50;
    });
    tearDown(() => TrackingService.debugTrackObserver = null);

    VenueCashPuller puller(List<VenueCashSource> sources,
            {void Function()? onSleep}) =>
        VenueCashPuller(
          sources: sources,
          readDollars: () => dollars,
          minimumUsd: (_) async => 1,
          clock: () => now,
          sleep: (d) async {
            now = now.add(d);
            onSleep?.call();
          },
        );

    Map<String, Object>? event(String name) =>
        events.where((e) => e.$1 == name).single.$2;

    test('Dollars that cover it: no legs, no events', () async {
      final p = _Source(_p, 100);
      final outcome = await puller([p])
          .pullShortfall(neededUsd: 40, forAction: VenueCashFor.send);
      expect(outcome.dollarsOnly, isTrue);
      expect(outcome.dollarsCover, isTrue);
      expect(p.pulls, isEmpty);
      expect(events, isEmpty);
    });

    test('every leg starts at once, then Dollars are awaited', () async {
      final p = _Source(_p, 20)..gate = Completer<void>();
      final i = _Source(_i, 500)..gate = Completer<void>();
      final run = puller([i, p], onSleep: () => dollars = 100)
          .pullShortfall(neededUsd: 100, forAction: VenueCashFor.buyBitcoin);
      await pumpEventQueue();
      // Both legs are in flight before either finishes.
      expect(p.started, isTrue);
      expect(i.started, isTrue);
      p.gate!.complete();
      i.gate!.complete();
      final outcome = await run;
      expect(outcome.legs.map((l) => l.venue), [_p, _i]);
      expect(outcome.legs.every((l) => l.ok), isTrue);
      expect(outcome.dollarsCover, isTrue);
      expect(p.pulls.single.purpose, kVenueCashPullPurpose);

      expect(event('multi_source_move_started'),
          {'legs': 3, 'total_usd': 100.0, 'destination': 'buy_bitcoin'});
      expect(event('predictions_cash_pulled'),
          {'amount_usd': 20.0, 'for': 'buy_bitcoin'});
      expect(event('investing_cash_pulled'),
          {'amount_usd': 31.33, 'for': 'buy_bitcoin'});
      final finished = event('multi_source_move_finished')!;
      expect(finished['failed_legs'], 0);
      expect(finished['destination'], 'buy_bitcoin');
      expect(finished['landed'], true);
      expect(finished['delivered_usd'] as double, closeTo(100.82, 1e-9));
    });

    test('one leg failing leaves the other; its money stays put', () async {
      final p = _Source(_p, 20);
      final i = _Source(_i, 500, error: const RouteUnavailable('paused'));
      final outcome = await puller([p, i])
          .pullShortfall(neededUsd: 100, forAction: VenueCashFor.send);
      expect(outcome.anyPulled, isTrue);
      expect(outcome.failedLegs.single.venue, _i);
      expect(outcome.failedLegs.single.error, isA<RouteUnavailable>());
      expect(outcome.pulledUsd, 20);
      expect(outcome.dollarsCover, isFalse);
      expect(i.available, 500);
      expect(events.where((e) => e.$1 == 'investing_cash_pulled'), isEmpty);
      expect(event('multi_source_move_finished')!['failed_legs'], 1);
    });

    test('the wait is bounded; a retry waits on the money already coming',
        () async {
      final p = _Source(_p, 100);
      final pull = puller([p]);
      final outcome = await pull.pullShortfall(
          neededUsd: 60,
          forAction: VenueCashFor.send,
          waitFor: const Duration(seconds: 30));
      expect(outcome.dollarsCover, isFalse);
      expect(p.pulls, hasLength(1));
      expect(event('multi_source_move_finished')!['landed'], false);
      expect(pull.pendingUsd, greaterThan(10));

      // Again right away: nothing more is pulled while it is on its way.
      final again = await pull.pullShortfall(
          neededUsd: 60,
          forAction: VenueCashFor.send,
          waitFor: const Duration(seconds: 30));
      expect(again.legs, isEmpty);
      expect(p.pulls, hasLength(1));
    });

    test('a plan that does not cover pulls nothing', () async {
      final p = _Source(_p, 5);
      final outcome = await puller([p])
          .pullShortfall(neededUsd: 100, forAction: VenueCashFor.send);
      expect(outcome.plan.covers, isFalse);
      expect(outcome.legs, isEmpty);
      expect(p.pulls, isEmpty);
      expect(events, isEmpty);
    });

    test('exclude keeps the target venue untouched', () async {
      final p = _Source(_p, 500);
      final i = _Source(_i, 500);
      final outcome = await puller([p, i]).pullShortfall(
          neededUsd: 60,
          forAction: VenueCashFor.predictions,
          exclude: _p,
          waitFor: Duration.zero);
      expect(outcome.legs.single.venue, _i);
      expect(p.pulls, isEmpty);
    });

    test('calls run one after another and re-plan on what is left', () async {
      final p = _Source(_p, 30)..gate = Completer<void>();
      final pull = puller([p]);
      final first = pull.pullShortfall(
          neededUsd: 70, forAction: VenueCashFor.send, waitFor: Duration.zero);
      final second = pull.pullShortfall(
          neededUsd: 70, forAction: VenueCashFor.send, waitFor: Duration.zero);
      await pumpEventQueue();
      expect(p.pulls, hasLength(1));
      p.gate!.complete();
      await first;
      final again = await second;
      // The first pull is on its way and counts: nothing more goes.
      expect(again.legs, isEmpty);
      expect(p.pulls, hasLength(1));
    });
  });
}
