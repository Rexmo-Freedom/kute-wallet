// Venue cash as a Dollars shortfall: the pure planner (Dollars first,
// Predictions before Investing, minimums, the cost gross-up, partial
// cover, exclude), the two sources (Investing refuses while a cross
// position or a resting perp order could lean on its cash), and the
// puller (parallel legs, one failing leaves the others, the bounded wait,
// the analytics).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
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

/// A source with a direct door: [refuse] refuses it before anything
/// moves, [directError] fails it after.
class _DirectSource extends _Source implements DirectVenueCashSource {
  _DirectSource(super.venue, super.available, {this.to = const {}});

  final Set<VenueCashDestination> to;
  bool refuse = false;

  /// The reason a refusal carries; [refusals] refusals at most, then the
  /// door goes (null: every attempt is refused).
  String refuseReason = 'cctp_fee_terms_unavailable';
  int? refusals;
  Object? directError;
  final directs = <({VenueCashDestination to, double usd})>[];
  final auths = <MoveAuthorization>[];

  @override
  bool canPullTo(VenueCashDestination destination) => to.contains(destination);

  @override
  Future<VenueMoveResult> pullTo(VenueCashDestination destination, double usd,
      {required String purpose, required MoveAuthorization auth}) async {
    directs.add((to: destination, usd: usd));
    auths.add(auth);
    final g = gate;
    if (g != null) await g.future;
    if (refuse) {
      final left = refusals;
      if (left == null || left > 0) {
        if (left != null) refusals = left - 1;
        throw DirectRouteRefused(refuseReason);
      }
    }
    final e = directError;
    if (e != null) throw e;
    available -= usd;
    return VenueMoveResult(
        quoteId: 'q-direct-${venue.name}-${directs.length}',
        operationId: 'op-direct-${venue.name}-${directs.length}',
        sentUsd: usd,
        arrivingUsdEstimate: usd * 0.99);
  }
}

/// A Predictions funder with the direct cash-out.
class _DirectFunder extends _Funder implements DirectSweepableVenueFunder {
  bool refuse = false;
  final direct = <({VenueCashDestination to, double usd})>[];

  @override
  Future<VenueMoveResult> sweepTo({
    required VenueCashDestination destination,
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'cash_pull',
  }) async {
    // Never the automatic authorization: only the action's approval.
    expect(auth, isA<ApprovedLegAuthorization>());
    direct.add((to: destination, usd: usd));
    if (refuse) throw const DirectRouteRefused('route_unavailable');
    return VenueMoveResult(
        quoteId: 'q-pm', sentUsd: usd, arrivingUsdEstimate: usd * 0.99);
  }
}

/// The action's one approval, binding legs to [to] capped per venue.
AuthGrant _approval({
  VenueCashDestination to = VenueCashDestination.bitcoin,
  Map<String, double> caps = const {'investing': 1000, 'predictions': 1000},
  SensitiveAction action = SensitiveAction.moveTransfer,
}) =>
    AuthGrants.issue(
      SensitiveIntent(
        action: action,
        walletId: 'w1',
        venue: IntentVenue.orchestra,
        asset: 'USDB',
        amountMax: IntentUnits.usd(1000),
        limits: {
          VenueLimit.directLegs:
              DirectLegGrants.limit(destination: to.code, capsUsd: caps),
        },
        ttl: const Duration(minutes: 10),
      ),
      method: AuthGrantMethod.biometric,
    );

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
      MultiSourceMoveStore.reset();
      DirectRouteRefusals.reset();
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
          {
            'legs': 3,
            'total_usd': 100.0,
            'destination': 'buy_bitcoin',
            'retry': false,
          });
      // A plain source has no direct door: home to Dollars, then on.
      expect(event('predictions_cash_pulled'), {
        'amount_usd': 20.0,
        'for': 'buy_bitcoin',
        'route': 'via_dollars',
        'destination': 'dollars',
      });
      expect(event('investing_cash_pulled'), {
        'amount_usd': 31.33,
        'for': 'buy_bitcoin',
        'route': 'via_dollars',
        'destination': 'dollars',
      });
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
      // The leg's own stop: a fixed category and the exact amount, no
      // bucket.
      final failed = event('venue_cash_pull_failed')!;
      expect(failed['venue'], 'investing');
      expect(failed['error_category'], isA<String>());
      expect(failed['amount_usd'], outcome.failedLegs.single.pull.usd);
      expect(failed.containsKey('amount_bucket'), isFalse);
    });

    test(
        'a failed leg is heard at once, while another leg is still on its '
        'way', () async {
      final p = _Source(_p, 20, error: const RouteUnavailable('paused'));
      final i = _Source(_i, 500)..gate = Completer<void>();
      final heard = <VenueCashLegOutcome>[];
      final run = puller([p, i]).pullShortfall(
          neededUsd: 100, forAction: VenueCashFor.send, onLeg: heard.add);
      await pumpEventQueue();
      // The screen can stop on it now; the Investing leg is still going.
      expect(heard.single.venue, _p);
      expect(heard.single.ok, isFalse);
      expect(i.started, isTrue);
      i.gate!.complete();
      final outcome = await run;
      expect(heard.map((l) => l.venue), [_p, _i]);
      expect(outcome.failedLegs.single.venue, _p);
      expect(outcome.dollarsCover, isFalse, reason: 'a failed leg: no wait');
    });

    test(
        'a leg refused as under its minimum raises that venue\'s minimum for '
        'the next plan; other refusals do not', () async {
      final tooSmall = <(OneBalanceVenue, double)>[];
      VenueCashPuller withHook(List<VenueCashSource> sources) =>
          VenueCashPuller(
            sources: sources,
            readDollars: () => dollars,
            minimumUsd: (_) async => 1,
            clock: () => now,
            sleep: (d) async => now = now.add(d),
            onAmountTooSmall: (venue, usd) => tooSmall.add((venue, usd)),
          );

      final quoteRefused = _Source(_p, 30,
          error: const RouteQuoteError(RouteQuoteErrorCode.amountTooSmall));
      final floorRefused =
          _Source(_i, 500, error: const RouteUnavailable('cctp_below_minimum'));
      final outcome = await withHook([quoteRefused, floorRefused])
          .pullShortfall(neededUsd: 100, forAction: VenueCashFor.send);
      expect(outcome.failedLegs, hasLength(2));
      expect(tooSmall, [(_p, 30.0), (_i, outcome.plan.pullFrom(_i)!.usd)]);

      tooSmall.clear();
      final paused = _Source(_p, 500, error: const RouteUnavailable('paused'));
      await withHook([paused])
          .pullShortfall(neededUsd: 100, forAction: VenueCashFor.send);
      expect(tooSmall, isEmpty);
    });

    test('venueLegBelowMinimum reads the quote and the rails\' floors', () {
      expect(
          venueLegBelowMinimum(
              const RouteQuoteError(RouteQuoteErrorCode.amountTooSmall)),
          isTrue);
      expect(venueLegBelowMinimum(const RouteUnavailable('cctp_below_minimum')),
          isTrue);
      expect(
          venueLegBelowMinimum(
              const RouteQuoteError(RouteQuoteErrorCode.amountTooLarge)),
          isFalse);
      expect(venueLegBelowMinimum(const RouteUnavailable('route_unavailable')),
          isFalse);
      expect(venueLegBelowMinimum(StateError('x')), isFalse);
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

  group('direct legs', () {
    late List<(String, Map<String, Object>?)> events;
    late DateTime now;
    late double dollars;

    setUp(() {
      events = [];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      now = DateTime(2026, 10, 13, 12);
      dollars = 0;
      MultiSourceMoveStore.reset();
      DirectRouteRefusals.reset();
    });
    tearDown(() => TrackingService.debugTrackObserver = null);

    VenueCashPuller puller(List<VenueCashSource> sources) => VenueCashPuller(
          sources: sources,
          readDollars: () => dollars,
          minimumUsd: (_) async => 1,
          clock: () => now,
          sleep: (d) async => now = now.add(d),
        );

    Map<String, Object>? event(String name) =>
        events.where((e) => e.$1 == name).single.$2;

    test('a leg anywhere but Dollars never moves without the approval',
        () async {
      final i = _DirectSource(_i, 500, to: {
        VenueCashDestination.bitcoin,
        VenueCashDestination.predictions,
      });
      final funder = _DirectFunder()..idle = 100;
      final pm = PolymarketCashSource(funder);
      for (final to in [
        VenueCashDestination.bitcoin,
        VenueCashDestination.predictions,
        VenueCashDestination.investing,
      ]) {
        await expectLater(
            puller([pm, i])
                .pullShortfall(neededUsd: 50, forAction: 'x', destination: to),
            throwsA(isA<VenueLegApprovalRequired>()));
      }
      expect(i.directs, isEmpty);
      expect(i.pulls, isEmpty, reason: 'not even home to Dollars');
      expect(funder.direct, isEmpty);
      expect(funder.sweeps, isEmpty);
      expect(MultiSourceMoveStore.all(), isEmpty);
      expect(events, isEmpty);
    });

    test('Dollars that already cover it need no leg approval', () async {
      dollars = 100;
      final i = _DirectSource(_i, 500, to: {VenueCashDestination.bitcoin});
      final outcome = await puller([i]).pullShortfall(
          neededUsd: 50,
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin);
      expect(outcome.dollarsOnly, isTrue);
      expect(i.directs, isEmpty);
    });

    test('a leg runs under the action\'s approval itself', () async {
      final grant = _approval(caps: {'investing': 60});
      final i = _DirectSource(_i, 500, to: {VenueCashDestination.bitcoin});
      final outcome = await puller([i]).pullShortfall(
          neededUsd: 50,
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin,
          approval: grant);
      expect(outcome.legs.single.route, VenueCashRoute.direct);
      final auth = i.auths.single;
      expect(auth, isA<ApprovedLegAuthorization>());
      expect((auth as ApprovedLegAuthorization).grant, same(grant));
      expect(grant.consumed, isFalse, reason: 'the action consumes it');
    });

    test(
        'a supported direct leg outside approval stops without a Dollars detour',
        () async {
      final i = _DirectSource(_i, 500, to: {VenueCashDestination.bitcoin});
      final small = _approval(caps: {'investing': 5});
      final outcome = await puller([i]).pullShortfall(
          neededUsd: 20,
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin,
          approval: small,
          waitFor: Duration.zero);
      expect(i.directs, isEmpty);
      expect(i.pulls, isEmpty);
      expect(outcome.failedLegs, hasLength(1));
      // Not the route's refusal: the next action may go straight.
      expect(DirectRouteRefusals.isRefused(_i, VenueCashDestination.bitcoin),
          isFalse);

      MultiSourceMoveStore.reset();
      final lapsed = _approval()..revoke();
      await puller([i]).pullShortfall(
          neededUsd: 20,
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin,
          approval: lapsed,
          waitFor: Duration.zero);
      expect(i.directs, isEmpty);
      expect(i.pulls, isEmpty);

      // An approval bound to another destination covers nothing here.
      MultiSourceMoveStore.reset();
      await puller([i]).pullShortfall(
          neededUsd: 20,
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin,
          approval: _approval(to: VenueCashDestination.predictions),
          waitFor: Duration.zero);
      expect(i.directs, isEmpty);
    });

    test('rail approval refusal cannot silently fall back to Dollars',
        () async {
      final source = _DirectSource(_i, 500, to: {VenueCashDestination.bitcoin})
        ..refuse = true
        ..refuseReason = 'settlement_declined';
      final result = await puller([source]).pullShortfall(
          neededUsd: 20,
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin,
          approval: _approval(to: VenueCashDestination.bitcoin),
          waitFor: Duration.zero);
      expect(result.failedLegs, hasLength(1));
      expect(source.directs, hasLength(1));
      expect(source.pulls, isEmpty);
    });

    test('directLegLimit binds only the legs that can go straight there',
        () async {
      dollars = 0;
      final p = _Source(_p, 20);
      final i = _DirectSource(_i, 500, to: {VenueCashDestination.bitcoin});
      final pull = puller([p, i]);
      final plan = await pull.plan(
          neededUsd: 50, destination: VenueCashDestination.bitcoin);
      expect(plan.pulls, hasLength(2));
      final limit = pull.directLegLimit(plan, VenueCashDestination.bitcoin)!;
      final investing = plan.pullFrom(_i)!.usd;
      expect(limit['to'], 'bitcoin');
      expect(
          limit['legs'], {'investing': IntentUnits.usd(investing).toString()});
      expect(limit['total'], IntentUnits.usd(investing).toString());
      expect(pull.directLegLimit(plan, VenueCashDestination.dollars), isNull);
      DirectRouteRefusals.refuse(_i, VenueCashDestination.bitcoin);
      expect(pull.directLegLimit(plan, VenueCashDestination.bitcoin), isNull);
    });

    test('Investing → Bitcoin goes straight there; nothing waits on Dollars',
        () async {
      final i = _DirectSource(_i, 500, to: {VenueCashDestination.bitcoin});
      final pull = puller([i]);
      final outcome = await pull.pullShortfall(
          neededUsd: 50,
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin,
          approval: _approval(to: VenueCashDestination.bitcoin));
      expect(i.directs.single.to, VenueCashDestination.bitcoin);
      expect(i.pulls, isEmpty, reason: 'never home first');
      final leg = outcome.legs.single;
      expect(leg.route, VenueCashRoute.direct);
      expect(leg.landsIn, VenueCashDestination.bitcoin);
      // The direct leg covers it all: nothing is taken from Dollars.
      expect(outcome.onwardUsd, 0);
      expect(outcome.dollarsCover, isTrue);
      expect(pull.pendingUsd, 0, reason: 'nothing is on its way to Dollars');
      expect(event('investing_cash_pulled'), {
        'amount_usd': leg.pull.usd,
        'for': 'buy_bitcoin',
        'route': 'direct',
        'destination': 'bitcoin',
      });
      final move = MultiSourceMoveStore.get(outcome.moveId!)!;
      expect(move.destination, VenueCashDestination.bitcoin);
      expect(move.legs.single.direct, isTrue);
      expect(move.legs.single.operationId, 'op-direct-investing-1');
    });

    test(
        'a route refused outright goes through Dollars and stays off for a '
        'while, then is asked again', () async {
      final i = _DirectSource(_i, 500, to: {VenueCashDestination.bitcoin})
        ..refuse = true
        ..refuseReason = 'cctp_capability';
      DirectRouteRefusals.clock = () => now;
      final pull = puller([i]);
      final outcome = await pull.pullShortfall(
          neededUsd: 20,
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin,
          approval: _approval(to: VenueCashDestination.bitcoin),
          waitFor: Duration.zero);
      expect(i.directs, hasLength(1), reason: 'a shut gate is not retried');
      expect(i.pulls, hasLength(1), reason: 'home to Dollars instead');
      expect(outcome.legs.single.route, VenueCashRoute.viaDollars);
      expect(outcome.legs.single.landsIn, VenueCashDestination.dollars);
      // The Dollars it lands are what the purchase takes on.
      expect(outcome.onwardUsd, 20);
      expect(event('investing_cash_pulled')!['route'], 'via_dollars');
      expect(event('investing_cash_pulled')!['destination'], 'bitcoin');
      expect(event('venue_cash_direct_refused'), {
        'venue': 'investing',
        'destination': 'bitcoin',
        'reason': 'cctp_capability',
        'retrying': false,
        'sticky': true,
        'amount_usd': i.pulls.single.usd,
      });
      expect(DirectRouteRefusals.isRefused(_i, VenueCashDestination.bitcoin),
          isTrue);

      // Within the while: straight through Dollars.
      dollars = 100;
      MultiSourceMoveStore.reset();
      await puller([i]).pullShortfall(
          neededUsd: 150,
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin,
          approval: _approval(to: VenueCashDestination.bitcoin),
          waitFor: Duration.zero);
      expect(i.directs, hasLength(1), reason: 'the refusal is remembered');
      expect(i.pulls, hasLength(2));

      // After it, the route is asked again.
      now = now.add(DirectRouteRefusals.ttl);
      expect(DirectRouteRefusals.isRefused(_i, VenueCashDestination.bitcoin),
          isFalse);
    });

    test(
        'a transient refusal (the terms, a read) is asked once more at once '
        'and never keeps the route off', () async {
      // Refused once, then the door goes: the leg is direct after all.
      final i = _DirectSource(_i, 500, to: {VenueCashDestination.bitcoin})
        ..refuse = true
        ..refusals = 1;
      final outcome = await puller([i]).pullShortfall(
          neededUsd: 20,
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin,
          approval: _approval(to: VenueCashDestination.bitcoin),
          waitFor: Duration.zero);
      expect(i.directs, hasLength(2), reason: 'asked once more');
      expect(i.pulls, isEmpty, reason: 'never home first');
      expect(outcome.legs.single.route, VenueCashRoute.direct);
      expect(event('venue_cash_direct_refused')!['retrying'], isTrue);
      expect(event('investing_cash_pulled')!['route'], 'direct');
      expect(DirectRouteRefusals.isRefused(_i, VenueCashDestination.bitcoin),
          isFalse);

      // Refused both times: through Dollars this once, never remembered.
      events.clear();
      MultiSourceMoveStore.reset();
      final j = _DirectSource(_i, 500, to: {VenueCashDestination.bitcoin})
        ..refuse = true;
      final twice = await puller([j]).pullShortfall(
          neededUsd: 20,
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin,
          approval: _approval(to: VenueCashDestination.bitcoin),
          waitFor: Duration.zero);
      expect(j.directs, hasLength(2));
      expect(j.pulls, hasLength(1));
      expect(twice.legs.single.route, VenueCashRoute.viaDollars);
      expect(event('investing_cash_pulled')!['route'], 'via_dollars');
      expect(DirectRouteRefusals.isRefused(_i, VenueCashDestination.bitcoin),
          isFalse,
          reason: 'the next action asks the direct route again');

      // An earlier CCTP move still on its way: not retried at once, not
      // remembered either.
      MultiSourceMoveStore.reset();
      final k = _DirectSource(_i, 500, to: {VenueCashDestination.bitcoin})
        ..refuse = true
        ..refuseReason = 'cctp_in_flight';
      await puller([k]).pullShortfall(
          neededUsd: 20,
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin,
          approval: _approval(to: VenueCashDestination.bitcoin),
          waitFor: Duration.zero);
      expect(k.directs, hasLength(1));
      expect(DirectRouteRefusals.isRefused(_i, VenueCashDestination.bitcoin),
          isFalse);
    });

    test(
        'Max from Dollars, Predictions and Investing: both venue legs go at '
        'once, straight to Bitcoin under the one approval, none via Dollars',
        () async {
      dollars = 10;
      final p = _DirectSource(_p, 30, to: {VenueCashDestination.bitcoin})
        ..gate = Completer<void>();
      final i = _DirectSource(_i, 40, to: {VenueCashDestination.bitcoin})
        ..gate = Completer<void>();
      final pull = puller([p, i]);
      // Max: Dollars plus every venue net of its cost.
      final max = await pull.reachUsd();
      final plan = await pull.plan(
          neededUsd: max, destination: VenueCashDestination.bitcoin);
      expect(plan.covers, isTrue);
      expect(plan.pulls.map((l) => l.venue), [_p, _i]);
      // The one approval binds both legs, each at its full amount.
      final limit = pull.directLegLimit(plan, VenueCashDestination.bitcoin)!;
      expect(limit['legs'], {
        'predictions': IntentUnits.usd(plan.pullFrom(_p)!.usd).toString(),
        'investing': IntentUnits.usd(plan.pullFrom(_i)!.usd).toString(),
      });
      expect(pull.directVenues(plan, VenueCashDestination.bitcoin), {_p, _i});
      final grant = AuthGrants.issue(
        DirectLegGrants.buyBitcoin(
          walletId: 'w1',
          ownSpark: 'spark1self',
          route: 'spark:USDB>spark:BTC',
          asset: 'USDB',
          totalUsd: max,
          directLegs: limit,
          ttl: AuthGrants.autofireTtl,
        ),
        method: AuthGrantMethod.biometric,
      );
      final sent = <OneBalanceVenue>[];
      final run = pull.pullShortfall(
          neededUsd: max,
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin,
          approval: grant,
          waitFor: Duration.zero,
          onLeg: (leg) => sent.add(leg.venue));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      // Both legs started before either was answered: in parallel.
      expect(p.directs, hasLength(1));
      expect(i.directs, hasLength(1));
      i.gate!.complete();
      p.gate!.complete();
      final outcome = await run;
      expect(
          outcome.legs.every((l) => l.route == VenueCashRoute.direct), isTrue);
      expect(p.pulls, isEmpty);
      expect(i.pulls, isEmpty);
      expect(sent.toSet(), {_p, _i}, reason: 'each leg reported as sent');
      // Dollars take the rest on: what they already hold, at once.
      expect(outcome.onwardUsd, closeTo(10, 0.02));
      expect(outcome.dollarsCover, isTrue);
      expect(DirectLegGrants.takenBy(grant), BigInt.zero,
          reason: 'the fakes take nothing; the rails take within the caps');
      expect(events.where((e) => e.$1 == 'venue_cash_direct_refused'), isEmpty);
    });

    test('a direct leg failing after it started never falls back', () async {
      final i = _DirectSource(_i, 500, to: {VenueCashDestination.bitcoin})
        ..directError = StateError('posted, outcome unknown');
      final outcome = await puller([i]).pullShortfall(
          neededUsd: 20,
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin,
          approval: _approval(to: VenueCashDestination.bitcoin));
      expect(i.pulls, isEmpty, reason: 'no second pull of the same cash');
      expect(outcome.failedLegs.single.route, VenueCashRoute.direct);
      expect(outcome.dollarsCover, isFalse);
    });

    test('Predictions → Investing: its direct cash-out, the venue excluded',
        () async {
      final funder = _DirectFunder()..idle = 100;
      final pm = PolymarketCashSource(funder);
      final i = _DirectSource(_i, 500, to: {VenueCashDestination.bitcoin});
      final outcome = await puller([pm, i]).pullShortfall(
          neededUsd: 30,
          forAction: VenueCashFor.investing,
          destination: VenueCashDestination.investing,
          approval: _approval(to: VenueCashDestination.investing));
      expect(funder.direct.single.to, VenueCashDestination.investing);
      expect(funder.sweeps, isEmpty);
      expect(i.pulls, isEmpty);
      expect(i.directs, isEmpty, reason: 'Investing never funds itself');
      expect(outcome.legs.single.venue, _p);
      expect(outcome.directArrivingUsd, greaterThan(0));
    });

    test('Predictions → Bitcoin refused: the cash-out to Dollars instead',
        () async {
      final funder = _DirectFunder()
        ..idle = 100
        ..refuse = true;
      final outcome = await puller([PolymarketCashSource(funder)])
          .pullShortfall(
              neededUsd: 30,
              forAction: VenueCashFor.buyBitcoin,
              destination: VenueCashDestination.bitcoin,
              approval: _approval(to: VenueCashDestination.bitcoin),
              waitFor: Duration.zero);
      expect(funder.direct.single.to, VenueCashDestination.bitcoin);
      expect(funder.sweeps.single.auth, same(SweepAuthorization.automatic));
      expect(outcome.legs.single.route, VenueCashRoute.viaDollars);
      expect(DirectRouteRefusals.isRefused(_p, VenueCashDestination.bitcoin),
          isTrue);
    });

    test('Dollars below the onward minimum are left alone', () async {
      dollars = 0.5;
      final i = _DirectSource(_i, 500, to: {VenueCashDestination.bitcoin});
      final outcome = await puller([i]).pullShortfall(
          neededUsd: 20,
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin,
          approval: _approval(to: VenueCashDestination.bitcoin));
      expect(outcome.plan.dollarsUsd, 0);
      expect(outcome.onwardUsd, 0);
      // Dollars of the minimum or more are used first, as always.
      dollars = 5;
      MultiSourceMoveStore.reset();
      final more = await puller([i]).pullShortfall(
          neededUsd: 20,
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin,
          approval: _approval(to: VenueCashDestination.bitcoin));
      expect(more.plan.dollarsUsd, 5);
      expect(more.onwardUsd, closeTo(5, 0.01));
    });

    test(
        'Investing → Predictions by CCTP when the bet slip asks, only '
        'under the bet\'s own approval', () async {
      final i = _DirectSource(_i, 500, to: {VenueCashDestination.predictions});
      await expectLater(
          puller([i]).pullShortfall(
              neededUsd: 12,
              forAction: VenueCashFor.predictions,
              destination: VenueCashDestination.predictions),
          throwsA(isA<VenueLegApprovalRequired>()));
      expect(i.directs, isEmpty);
      expect(i.pulls, isEmpty);
      final bet = _approval(
          to: VenueCashDestination.predictions,
          caps: {'investing': 20},
          action: SensitiveAction.pmBet);
      final approved = await puller([i]).pullShortfall(
          neededUsd: 12,
          forAction: VenueCashFor.predictions,
          destination: VenueCashDestination.predictions,
          approval: bet);
      expect((i.auths.single as ApprovedLegAuthorization).grant, same(bet));
      expect(approved.onwardUsd, 0);
      MultiSourceMoveStore.reset();
      i.directs.clear();
      final outcome = await puller([i]).pullShortfall(
          neededUsd: 12,
          forAction: VenueCashFor.predictions,
          destination: VenueCashDestination.predictions,
          approval: _approval(to: VenueCashDestination.predictions));
      expect(i.directs.single.to, VenueCashDestination.predictions);
      expect(outcome.onwardUsd, 0);
    });
  });

  group('one move per action', () {
    late DateTime now;
    late double dollars;
    late List<(String, Map<String, Object>?)> events;

    setUp(() {
      events = [];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      now = DateTime(2026, 10, 13, 12);
      dollars = 10;
      MultiSourceMoveStore.reset();
      DirectRouteRefusals.reset();
    });
    tearDown(() => TrackingService.debugTrackObserver = null);

    VenueCashPuller puller(List<VenueCashSource> sources) => VenueCashPuller(
          sources: sources,
          readDollars: () => dollars,
          minimumUsd: (_) async => 1,
          clock: () => now,
          sleep: (d) async => now = now.add(d),
          walletId: () => 'w1',
        );

    test('the legs are one record: delivered, remaining, linked ids', () async {
      final p = _DirectSource(_p, 20, to: {VenueCashDestination.bitcoin});
      final i = _DirectSource(_i, 500, to: {VenueCashDestination.bitcoin})
        ..directError = const RouteUnavailable('paused');
      final outcome = await puller([p, i]).pullShortfall(
          neededUsd: 50,
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin,
          approval: _approval(to: VenueCashDestination.bitcoin));
      final move = MultiSourceMoveStore.get(outcome.moveId!)!;
      expect(move.walletId, 'w1');
      expect(move.totalUsd, 50);
      expect(move.dollarsUsd, 10);
      expect(move.legs, hasLength(2));
      expect(move.okLegs.single.venue, _p);
      expect(move.failedLegs.single.venue, _i);
      // $10 of Dollars plus what Predictions sent: the rest is left.
      expect(move.deliveredUsd, closeTo(10 + 19.8, 0.01));
      expect(move.remainingUsd, closeTo(50 - 29.8, 0.01));
      expect(move.partial, isTrue);
      expect(move.linkedIds, contains('op-direct-predictions-1'));
      expect(move.linkedIds, contains('cctp-op-direct-predictions-1'));
    });

    test('a Retry after switching wallets never pulls the other wallet',
        () async {
      final p = _DirectSource(_p, 20, to: {VenueCashDestination.bitcoin});
      final i = _DirectSource(_i, 500, to: {VenueCashDestination.bitcoin})
        ..directError = const RouteUnavailable('paused');
      final first = await puller([p, i]).pullShortfall(
          neededUsd: 50,
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin,
          approval: _approval(to: VenueCashDestination.bitcoin));
      expect(MultiSourceMoveStore.get(first.moveId!)!.partial, isTrue);
      final other = VenueCashPuller(
        sources: [p, i],
        readDollars: () => dollars,
        minimumUsd: (_) async => 1,
        clock: () => now,
        sleep: (d) async => now = now.add(d),
        walletId: () => 'w2',
      );
      final before = events.length;
      expect(await other.planRetry(first.moveId!), isNull);
      expect(
          await other.retryMove(first.moveId!,
              approval: _approval(to: VenueCashDestination.bitcoin)),
          isNull);
      // Said once, with a fixed reason: never which wallet.
      final refused =
          events.skip(before).where((e) => e.$1 == 'multi_source_move_retry_refused');
      expect(refused, hasLength(1));
      expect(refused.single.$2,
          {'reason': 'other_wallet', 'destination': 'bitcoin'});
    });

    test('Retry pulls only the failed remainder, never the leg that went',
        () async {
      final p = _DirectSource(_p, 20, to: {VenueCashDestination.bitcoin});
      final i = _DirectSource(_i, 500, to: {VenueCashDestination.bitcoin})
        ..directError = const RouteUnavailable('paused');
      final pull = puller([p, i]);
      final first = await pull.pullShortfall(
          neededUsd: 50,
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin,
          approval: _approval(to: VenueCashDestination.bitcoin));
      final id = first.moveId!;
      final remaining = MultiSourceMoveStore.get(id)!.remainingUsd;
      expect(p.directs, hasLength(1));

      i.directError = null;
      dollars = 0; // Dollars spent elsewhere: Retry uses the venues only.
      final retry = await pull.retryMove(id, approval: _approval());
      expect(retry, isNotNull);
      expect(retry!.moveId, id);
      expect(p.directs, hasLength(1), reason: 'Predictions already sent');
      expect(i.directs.last.usd, greaterThanOrEqualTo(remaining),
          reason: 'only the remainder, grossed up for its cost');
      expect(i.directs.last.usd, lessThan(remaining * 1.05 + 0.31));
      final move = MultiSourceMoveStore.get(id)!;
      expect(move.legs, hasLength(3));
      expect(move.partial, isFalse);
      expect(move.remainingUsd, 0);

      // Nothing left: a second Retry pulls nothing.
      expect(await pull.retryMove(id, approval: _approval()), isNull);
      expect(i.directs, hasLength(2));
    });

    test('two Retry taps at once pull once', () async {
      final p = _DirectSource(_p, 20, to: {VenueCashDestination.bitcoin});
      final i = _DirectSource(_i, 500, to: {VenueCashDestination.bitcoin})
        ..directError = const RouteUnavailable('paused');
      final pull = puller([p, i]);
      final id = (await pull.pullShortfall(
              neededUsd: 50,
              forAction: VenueCashFor.buyBitcoin,
              destination: VenueCashDestination.bitcoin,
              approval: _approval(to: VenueCashDestination.bitcoin)))
          .moveId!;
      i
        ..directError = null
        ..gate = Completer<void>();
      final a = pull.retryMove(id, approval: _approval());
      final b = pull.retryMove(id, approval: _approval());
      expect(await b, isNull, reason: 'one Retry runs at a time');
      i.gate!.complete();
      expect(await a, isNotNull);
      expect(i.directs, hasLength(2));
    });

    test('Retry of the whole action reuses what already went', () async {
      final p = _DirectSource(_p, 20, to: {VenueCashDestination.bitcoin});
      final i = _DirectSource(_i, 500, to: {VenueCashDestination.bitcoin})
        ..directError = const RouteUnavailable('paused');
      final pull = puller([p, i]);
      dollars = 0;
      final first = await pull.pullShortfall(
          neededUsd: 50,
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin,
          approval: _approval(to: VenueCashDestination.bitcoin));
      expect(first.dollarsCover, isFalse);
      i.directError = null;
      // The action's own Retry asks for the whole $50 again, same move.
      final again = await pull.pullShortfall(
          neededUsd: 50,
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin,
          approval: _approval(to: VenueCashDestination.bitcoin),
          moveId: first.moveId);
      expect(again.alreadyDeliveredUsd, closeTo(19.8, 0.01));
      expect(p.directs, hasLength(1), reason: 'no double pull');
      expect(again.plan.neededUsd, closeTo(50 - 19.8, 0.01));
      expect(again.moveId, first.moveId);
      expect(MultiSourceMoveStore.all(), hasLength(1));
    });

    test('the action\'s own step joins the move', () async {
      final p = _Source(_p, 100);
      final outcome = await puller([p]).pullShortfall(
          neededUsd: 30, forAction: VenueCashFor.send, waitFor: Duration.zero);
      MultiSourceMoveStore.attachFinal(outcome.moveId, 'op-send');
      final move = MultiSourceMoveStore.get(outcome.moveId!)!;
      expect(move.finalOperationId, 'op-send');
      expect(move.linkedIds, contains('op-send'));
    });

    test('Retry to Bitcoin never moves without its own approval', () async {
      final p = _DirectSource(_p, 20, to: {VenueCashDestination.bitcoin});
      final i = _DirectSource(_i, 500, to: {VenueCashDestination.bitcoin})
        ..directError = const RouteUnavailable('paused');
      final pull = puller([p, i]);
      final id = (await pull.pullShortfall(
              neededUsd: 50,
              forAction: VenueCashFor.buyBitcoin,
              destination: VenueCashDestination.bitcoin,
              approval: _approval()))
          .moveId!;
      i.directError = null;
      final plan = await pull.planRetry(id);
      expect(plan!.pulls.single.venue, _i);
      await expectLater(
          pull.retryMove(id), throwsA(isA<VenueLegApprovalRequired>()));
      expect(i.directs, hasLength(1), reason: 'only the first, failed leg');
      expect(i.pulls, isEmpty);
    });

    test('retry_tapped carries the remainder only', () {
      trackMultiSourceMoveRetry(20.204);
      expect(events.single.$1, 'multi_source_move_retry_tapped');
      expect(events.single.$2, {'remaining_usd': 20.2});
    });

    test('a record survives its JSON', () {
      final move = MultiSourceMove(
        id: 'msm_1',
        walletId: 'w',
        forAction: 'send',
        destination: VenueCashDestination.dollars,
        totalUsd: 50,
        dollarsUsd: 10,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        legs: [
          MultiSourceMoveLeg(
              venue: _i,
              usd: 41,
              arrivingUsd: 40,
              route: VenueCashRoute.viaDollars,
              ok: false,
              at: DateTime.fromMillisecondsSinceEpoch(2000),
              error: 'route'),
        ],
        finalOperationId: 'op',
      );
      final back = MultiSourceMove.fromJson(move.toJson())!;
      expect(back.toJson(), move.toJson());
      // The action's own step went: nothing is left to retry.
      expect(back.partial, isFalse);
      final stopped = MultiSourceMove.fromJson(
          {...move.toJson()}..remove('finalOperationId'))!;
      expect(stopped.partial, isTrue);
      expect(stopped.remainingUsd, 40);
    });
  });
}
