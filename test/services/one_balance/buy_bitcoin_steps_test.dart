// A Buy bitcoin from Investments as its step graph: one leg straight to
// Bitcoin, one home to Dollars, Dollars' own part; each leg completes on
// its own, the purchase waits only on the leg through Dollars, a refused
// direct leg falls back through Dollars, the record keeps the graph and a
// record made before it maps onto steps.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/services/one_balance/buy_bitcoin_steps.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/tracking_service.dart';

const _p = OneBalanceVenue.predictions;
const _i = OneBalanceVenue.investing;
final _t0 = DateTime(2026, 10, 15, 12);

MultiSourceMoveLeg _leg(OneBalanceVenue venue,
        {bool ok = true,
        bool direct = true,
        double usd = 12,
        String? op,
        String? error}) =>
    MultiSourceMoveLeg(
      venue: venue,
      usd: usd,
      arrivingUsd: usd * 0.99,
      route: direct ? VenueCashRoute.direct : VenueCashRoute.viaDollars,
      ok: ok,
      at: _t0,
      operationId: op,
      error: ok ? null : (error ?? 'network'),
    );

/// "Move $20 to Bitcoin": $12 Investing straight to Bitcoin, $5
/// Predictions home to Dollars, $3 already in Dollars: Dollars buy $8.
MoneyStepGraph _planned() => BuyBitcoinSteps.planned(
      legs: [
        (venue: _i, usd: 12, direct: true),
        (venue: _p, usd: 5, direct: false),
      ],
      onwardUsd: 8,
      totalUsd: 20,
      at: _t0,
    );

MoneyStepStatus _status(MoneyStepGraph g, String id) => g.byId(id)!.status;

class _Source implements VenueCashSource, DirectVenueCashSource {
  _Source(this.venue,
      {this.direct = false, this.refuse = false, this.available = 500});

  @override
  final OneBalanceVenue venue;
  final double available;
  final bool direct;
  final bool refuse;
  int _n = 0;

  @override
  Future<double> availableUsd() async => available;

  @override
  Duration get estimatedArrival => kVenuePullEta[venue]!;

  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) async =>
      VenueMoveResult(
          quoteId: 'q-${venue.name}-${++_n}',
          operationId: 'op-home-${venue.name}-$_n',
          sentUsd: usd,
          arrivingUsdEstimate: usd * 0.99);

  @override
  bool canPullTo(VenueCashDestination destination) =>
      direct && destination == VenueCashDestination.bitcoin;

  @override
  Future<VenueMoveResult> pullTo(VenueCashDestination destination, double usd,
      {required String purpose, required MoveAuthorization auth}) async {
    if (refuse) throw const DirectRouteRefused('no_direct_route');
    return VenueMoveResult(
        quoteId: 'q-direct-${venue.name}-${++_n}',
        operationId: 'op-direct-${venue.name}-$_n',
        sentUsd: usd,
        arrivingUsdEstimate: usd * 0.99);
  }
}

AuthGrant _approval() => AuthGrants.issue(
      SensitiveIntent(
        action: SensitiveAction.moveTransfer,
        walletId: 'w1',
        venue: IntentVenue.orchestra,
        asset: 'USDB',
        amountMax: IntentUnits.usd(1000),
        limits: {
          VenueLimit.directLegs: DirectLegGrants.limit(
              destination: 'bitcoin',
              capsUsd: {'investing': 1000, 'predictions': 1000}),
        },
        ttl: const Duration(minutes: 10),
      ),
      method: AuthGrantMethod.biometric,
    );

void main() {
  group('the graph of a Buy bitcoin', () {
    test('one leg straight to Bitcoin, one through Dollars, and Dollars', () {
      final g = _planned();
      expect([for (final s in g.steps) s.id],
          ['leg:investing', 'leg:predictions', 'buy', 'arrive']);

      final investing = g.byId('leg:investing')!;
      expect(investing.kind, MoneyStepKind.leg);
      expect(investing.from, MoneyPlace.investing);
      expect(investing.to, MoneyPlace.bitcoin);
      expect(investing.route, MoneyRoute.direct);
      expect(investing.usd, 12);

      final predictions = g.byId('leg:predictions')!;
      expect(predictions.from, MoneyPlace.predictions);
      expect(predictions.to, MoneyPlace.dollars);
      expect(predictions.route, MoneyRoute.viaDollars);
      expect(predictions.usd, 5);

      // Every leg goes at once.
      expect(investing.status, MoneyStepStatus.running);
      expect(predictions.status, MoneyStepStatus.running);

      final buy = g.byId('buy')!;
      expect(buy.kind, MoneyStepKind.buy);
      expect(buy.usd, 8);
      expect(buy.after, ['leg:predictions'],
          reason: 'only the leg whose money comes through Dollars');
      expect(g.canStart(buy), isFalse);

      final arrive = g.byId('arrive')!;
      expect(arrive.after, ['buy', 'leg:investing']);
    });

    test('Dollars alone pay the purchase: it starts right away', () {
      final g = BuyBitcoinSteps.planned(
        legs: [(venue: _i, usd: 12, direct: true)],
        onwardUsd: 8,
        totalUsd: 20,
      );
      expect(g.byId('buy')!.after, isEmpty);
      expect(g.canStart(g.byId('buy')!), isTrue);
    });

    test('every leg straight to Bitcoin: no purchase at all', () {
      final g = BuyBitcoinSteps.planned(
        legs: [(venue: _i, usd: 20.5, direct: true)],
        onwardUsd: 0,
        totalUsd: 20,
      );
      expect(g.byId('buy'), isNull);
      expect(g.byId('arrive')!.after, ['leg:investing']);
    });
  });

  group('statuses follow the events, each leg on its own', () {
    test('legs go, fail, retry and land independently; the buy waits', () {
      var g = _planned();
      // Investing went straight to Bitcoin: on its way, with its row id.
      g = BuyBitcoinSteps.legRecorded(
          g, _leg(_i, usd: 12, op: 'op-direct-investing'));
      expect(_status(g, 'leg:investing'), MoneyStepStatus.running);
      expect(g.byId('leg:investing')!.ref, 'op-direct-investing');
      // Predictions failed: it names itself, Investing is untouched.
      g = BuyBitcoinSteps.legRecorded(
          g, _leg(_p, ok: false, direct: false, usd: 5, error: 'network'));
      expect(_status(g, 'leg:predictions'), MoneyStepStatus.failed);
      expect(g.byId('leg:predictions')!.reason, 'network');
      expect(_status(g, 'leg:investing'), MoneyStepStatus.running);
      expect(g.canStart(g.byId('buy')!), isFalse);

      // Retry: only Predictions runs again, in place.
      g = BuyBitcoinSteps.legRecorded(
          g, _leg(_p, direct: false, usd: 5, op: 'op-home-predictions'));
      expect(_status(g, 'leg:predictions'), MoneyStepStatus.running);
      expect(g.byId('leg:predictions')!.reason, isNull);
      expect(
          [for (final s in g.legs) s.id], ['leg:investing', 'leg:predictions']);

      // The purchase is set to what Dollars take once every leg went.
      g = BuyBitcoinSteps.onward(g, 8.05);
      expect(g.byId('buy')!.usd, 8.05);
      expect(g.canStart(g.byId('buy')!), isFalse,
          reason: 'its money has not landed yet');

      // What came home landed: the leg through Dollars is done, the
      // direct leg still on its way, and the purchase may go.
      g = BuyBitcoinSteps.dollarsLanded(g, at: _t0);
      expect(_status(g, 'leg:predictions'), MoneyStepStatus.done);
      expect(_status(g, 'leg:investing'), MoneyStepStatus.running);
      expect(g.canStart(g.byId('buy')!), isTrue);

      // The purchase: quoting, then sent.
      g = BuyBitcoinSteps.buyStarted(g, at: _t0);
      expect(_status(g, 'buy'), MoneyStepStatus.running);
      g = BuyBitcoinSteps.buySent(g, 'op-buy');
      expect(g.byId('buy')!.ref, 'op-buy');
      // A stop after it was sent never undoes it.
      expect(_status(BuyBitcoinSteps.buyStopped(g, 'needs_approval'), 'buy'),
          MoneyStepStatus.running);
      expect(_status(g, 'arrive'), MoneyStepStatus.waiting);
    });

    test('a purchase stopped before anything left Dollars waits on a tap', () {
      var g = BuyBitcoinSteps.buyStarted(_planned());
      g = BuyBitcoinSteps.buyStopped(g, 'needs_approval');
      expect(_status(g, 'buy'), MoneyStepStatus.failed);
      expect(g.byId('buy')!.reason, 'needs_approval');
      // A fresh approval runs it again.
      expect(_status(BuyBitcoinSteps.buyStarted(g), 'buy'),
          MoneyStepStatus.running);
    });

    test('a direct leg refused goes through Dollars and the buy waits on it',
        () {
      final g = BuyBitcoinSteps.legRecorded(
          _planned(), _leg(_i, direct: false, usd: 12, op: 'op-home'));
      expect(_status(g, 'leg:investing'), MoneyStepStatus.fellBack);
      final via = g.byId('leg:investing:via_dollars')!;
      expect(via.status, MoneyStepStatus.running);
      expect(via.to, MoneyPlace.dollars);
      expect(via.ref, 'op-home');
      expect(g.byId('buy')!.after,
          ['leg:investing:via_dollars', 'leg:predictions']);
      expect(g.byId('arrive')!.after, ['buy']);
    });

    test('a fallback when nothing was to be bought adds the purchase', () {
      final planned = BuyBitcoinSteps.planned(
        legs: [(venue: _i, usd: 20.5, direct: true)],
        onwardUsd: 0,
        totalUsd: 20,
      );
      final g = BuyBitcoinSteps.legRecorded(
          planned, _leg(_i, direct: false, usd: 20.5, op: 'op-home'));
      expect(g.byId('buy')!.after, ['leg:investing:via_dollars']);
      expect(g.byId('arrive')!.after, ['buy']);
      expect([for (final s in g.steps) s.id].last, 'arrive');
    });
  });

  group('the record', () {
    setUp(MultiSourceMoveStore.reset);

    test('keeps the graph in multi_source_moves_v1 and reads it back', () {
      final move = MultiSourceMove(
        id: 'msm_1',
        forAction: VenueCashFor.buyBitcoin,
        destination: VenueCashDestination.bitcoin,
        totalUsd: 20,
        dollarsUsd: 3,
        createdAt: _t0,
        steps: _planned(),
      );
      final json = jsonDecode(jsonEncode(move.toJson())) as Map;
      expect(json['steps'], isA<List>());
      final back = MultiSourceMove.fromJson(json)!;
      expect(jsonEncode(back.steps.toJson()), jsonEncode(_planned().toJson()));
      // A record with no steps writes none (older readers see what they
      // always saw).
      expect(move.copyWith(steps: MoneyStepGraph.empty).toJson(),
          isNot(contains('steps')));
    });

    test('a record made before the graph maps its legs and purchase', () {
      final old = MultiSourceMove.fromJson({
        'id': 'msm_old',
        'for': 'buy_bitcoin',
        'destination': 'bitcoin',
        'totalUsd': 20,
        'dollarsUsd': 3,
        'createdAt': _t0.millisecondsSinceEpoch,
        'legs': [
          _leg(_i, usd: 12, op: 'op-hl').toJson(),
          _leg(_p, direct: false, usd: 5, op: 'op-pm').toJson(),
        ],
      })!;
      expect(old.steps.isEmpty, isTrue);
      final g = BuyBitcoinSteps.of(old);
      expect([for (final s in g.steps) s.id],
          ['leg:investing', 'leg:predictions', 'buy', 'arrive']);
      expect(g.byId('leg:investing')!.route, MoneyRoute.direct);
      expect(g.byId('leg:investing')!.ref, 'op-hl');
      expect(g.byId('leg:predictions')!.to, MoneyPlace.dollars);
      expect(_status(g, 'leg:predictions'), MoneyStepStatus.running);
      // What the direct leg did not bring: 20 - 11.88.
      expect(g.byId('buy')!.usd, 8.12);
      expect(g.byId('buy')!.after, ['leg:predictions']);
      expect(_status(g, 'buy'), MoneyStepStatus.waiting);

      // Its purchase went: running, with its operation.
      final bought = BuyBitcoinSteps.of(old.copyWith(finalOperationId: 'op-b'));
      expect(_status(bought, 'buy'), MoneyStepStatus.running);
      expect(bought.byId('buy')!.ref, 'op-b');

      // A failed leg maps as failed.
      final failed = BuyBitcoinSteps.of(old.copyWith(legs: [
        _leg(_i, usd: 12, op: 'op-hl'),
        _leg(_p, ok: false, direct: false, usd: 5),
      ]));
      expect(_status(failed, 'leg:predictions'), MoneyStepStatus.failed);

      // Any other move has no steps here.
      expect(
          BuyBitcoinSteps.of(MultiSourceMove(
                  id: 'msm_send',
                  forAction: VenueCashFor.send,
                  destination: VenueCashDestination.dollars,
                  totalUsd: 20,
                  dollarsUsd: 0,
                  createdAt: _t0))
              .isEmpty,
          isTrue);
    });

    test('an event on an old record writes its mapped graph', () {
      MultiSourceMoveStore.start(MultiSourceMove(
        id: 'msm_old',
        forAction: VenueCashFor.buyBitcoin,
        destination: VenueCashDestination.bitcoin,
        totalUsd: 20,
        dollarsUsd: 3,
        createdAt: _t0,
        legs: [_leg(_p, direct: false, usd: 5, op: 'op-pm')],
      ));
      BuyBitcoinSteps.record('msm_old', BuyBitcoinSteps.buyStarted);
      final g = MultiSourceMoveStore.get('msm_old')!.steps;
      expect(_status(g, 'leg:predictions'), MoneyStepStatus.running);
      expect(_status(g, 'buy'), MoneyStepStatus.running);
    });
  });

  group('the puller records the graph', () {
    late DateTime now;
    setUp(() {
      now = _t0;
      MultiSourceMoveStore.reset();
      DirectRouteRefusals.reset();
      TrackingService.debugTrackObserver = (_, __) {};
    });
    tearDown(() => TrackingService.debugTrackObserver = null);

    VenueCashPuller puller(List<VenueCashSource> sources, double dollars) =>
        VenueCashPuller(
          sources: sources,
          readDollars: () => dollars,
          minimumUsd: (_) async => 1,
          clock: () => now,
          sleep: (d) async => now = now.add(d),
        );

    test('legs straight to Bitcoin and through Dollars, then the purchase',
        () async {
      String? started;
      // $5 in Predictions, the rest from Investing.
      final outcome = await puller([
        _Source(_p, available: 5),
        _Source(_i, direct: true),
      ], 3)
          .pullShortfall(
        neededUsd: 20,
        forAction: VenueCashFor.buyBitcoin,
        destination: VenueCashDestination.bitcoin,
        approval: _approval(),
        waitFor: Duration.zero,
        onStarted: (id) {
          started = id;
          // Written before any leg goes: every planned leg is running.
          final g = MultiSourceMoveStore.get(id)!.steps;
          expect(g.legs, isNotEmpty);
          expect(
              g.legs.every((s) => s.status == MoneyStepStatus.running), isTrue);
        },
      );
      expect(started, outcome.moveId);
      final g = MultiSourceMoveStore.get(outcome.moveId!)!.steps;
      final legs = {for (final s in g.legs) s.from: s};
      expect(legs[MoneyPlace.predictions]!.route, MoneyRoute.viaDollars);
      expect(legs[MoneyPlace.predictions]!.ref, 'op-home-predictions-1');
      expect(legs[MoneyPlace.investing]!.route, MoneyRoute.direct);
      expect(legs[MoneyPlace.investing]!.ref, 'op-direct-investing-1');
      final buy = g.byId('buy')!;
      expect(buy.after, [legs[MoneyPlace.predictions]!.id]);
      expect(buy.usd, outcome.dollarsNeededUsd);
      expect(g.byId('arrive')!.after, ['buy', legs[MoneyPlace.investing]!.id]);
    });

    test('a refused direct leg falls back on the record', () async {
      final outcome = await puller([_Source(_i, direct: true, refuse: true)], 0)
          .pullShortfall(
        neededUsd: 20,
        forAction: VenueCashFor.buyBitcoin,
        destination: VenueCashDestination.bitcoin,
        approval: _approval(),
        waitFor: Duration.zero,
      );
      final g = MultiSourceMoveStore.get(outcome.moveId!)!.steps;
      expect(_status(g, 'leg:investing'), MoneyStepStatus.fellBack);
      expect(_status(g, 'leg:investing:via_dollars'), MoneyStepStatus.running);
      expect(g.byId('buy')!.after, ['leg:investing:via_dollars']);
      expect(g.byId('buy')!.usd, outcome.dollarsNeededUsd);
    });

    test('a move that is not a Buy bitcoin keeps its own graph', () async {
      // Every move has its steps now (move_steps.dart): a send's legs come
      // home to Dollars, then the send.
      final outcome = await puller([_Source(_p)], 0).pullShortfall(
          neededUsd: 20, forAction: VenueCashFor.send, waitFor: Duration.zero);
      final g = MultiSourceMoveStore.get(outcome.moveId!)!.steps;
      expect([for (final s in g.steps) s.id], ['leg:predictions', 'send']);
      expect(g.byId('send')!.after, ['leg:predictions']);
      expect(g.byId('buy'), isNull);
    });
  });
}
