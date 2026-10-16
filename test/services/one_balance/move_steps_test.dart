// Every move as its step graph (move_steps.dart), one model for all:
// venue ↔ venue (straight there, or through Dollars, then Dollars going
// on), a send (legs home, then the send), the Portfolio's Rebalance (one
// leg per venue, in parallel, each completing on its own), Add to
// Investments from Bitcoin and a purchase paid by Dollars alone (read from
// their row). Records made before the graph map onto steps, and a failed
// leg a Retry covered from another venue never leaves a step waiting.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/move_steps.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/rebalance_steps.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/one_balance/venue_sweeper.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/services/tracking_service.dart';

const _p = OneBalanceVenue.predictions;
const _i = OneBalanceVenue.investing;
final _t0 = DateTime(2026, 10, 15, 12);

MultiSourceMoveLeg _leg(OneBalanceVenue venue,
        {bool ok = true,
        bool direct = false,
        double usd = 10,
        String? op,
        DateTime? at}) =>
    MultiSourceMoveLeg(
      venue: venue,
      usd: usd,
      arrivingUsd: usd * 0.99,
      route: direct ? VenueCashRoute.direct : VenueCashRoute.viaDollars,
      ok: ok,
      at: at ?? _t0,
      operationId: op,
      error: ok ? null : 'network',
    );

MoneyStepStatus _status(MoneyStepGraph g, String id) => g.byId(id)!.status;
List<String> _ids(MoneyStepGraph g) => [for (final s in g.steps) s.id];

MultiSourceMove _move({
  required String forAction,
  required VenueCashDestination destination,
  double total = 20,
  double dollars = 0,
  List<MultiSourceMoveLeg> legs = const [],
  String? finalOp,
}) =>
    MultiSourceMove(
      id: 'msm_${destination.name}',
      forAction: forAction,
      destination: destination,
      totalUsd: total,
      dollarsUsd: dollars,
      createdAt: _t0,
      legs: legs,
      finalOperationId: finalOp,
    );

SwapOrder _row(String id,
        {required String from,
        required String fromNet,
        required String to,
        required String toNet,
        String deposit = '5.00',
        String withdrawal = '4.95',
        String status = 'exchanging',
        String? direction}) =>
    SwapOrder(
      id: id,
      coinFrom: from,
      networkFrom: fromNet,
      coinTo: to,
      networkTo: toNet,
      depositAddress: 'deposit-$id',
      depositAmount: deposit,
      withdrawalAmount: withdrawal,
      status: status,
      timestamp: _t0.millisecondsSinceEpoch,
      withdrawalAddress: 'self',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      operationId: 'op-$id',
      activityDirection: direction,
    );

class _Source implements VenueCashSource, DirectVenueCashSource {
  _Source(this.venue, {this.direct = false, this.available = 500});

  @override
  final OneBalanceVenue venue;
  final double available;
  final bool direct;
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
      direct && destination != VenueCashDestination.dollars;

  @override
  Future<VenueMoveResult> pullTo(VenueCashDestination destination, double usd,
          {required String purpose, required MoveAuthorization auth}) async =>
      VenueMoveResult(
          quoteId: 'q-direct-${venue.name}-${++_n}',
          operationId: 'op-direct-${venue.name}-$_n',
          sentUsd: usd,
          arrivingUsdEstimate: usd * 0.99);
}

AuthGrant _approval(String destination) => AuthGrants.issue(
      SensitiveIntent(
        action: SensitiveAction.pmBet,
        walletId: 'w1',
        venue: IntentVenue.orchestra,
        asset: 'USDB',
        amountMax: IntentUnits.usd(1000),
        limits: {
          VenueLimit.directLegs: DirectLegGrants.limit(
              destination: destination,
              capsUsd: {'investing': 1000, 'predictions': 1000}),
        },
        ttl: const Duration(minutes: 10),
      ),
      method: AuthGrantMethod.biometric,
    );

void main() {
  setUp(() {
    MultiSourceMoveStore.reset();
    DirectRouteRefusals.reset();
    TrackingService.debugTrackObserver = (_, __) {};
  });
  tearDown(() => TrackingService.debugTrackObserver = null);

  group('venue ↔ venue', () {
    test('Investing straight into Predictions: no Dollars step', () {
      final g = MoveSteps.planned(
        destination: VenueCashDestination.predictions,
        forAction: VenueCashFor.predictions,
        legs: const [(venue: _i, usd: 15, direct: true)],
        onwardUsd: 0,
        totalUsd: 15,
        at: _t0,
      );
      expect(_ids(g), ['leg:investing']);
      final leg = g.byId('leg:investing')!;
      expect(leg.from, MoneyPlace.investing);
      expect(leg.to, MoneyPlace.predictions);
      expect(leg.route, MoneyRoute.direct);
      expect(leg.status, MoneyStepStatus.running);
      expect(g.byId(MoveSteps.arriveId), isNull);
    });

    test('Predictions via Dollars, then Dollars go on into Investing', () {
      var g = MoveSteps.planned(
        destination: VenueCashDestination.investing,
        forAction: VenueCashFor.investing,
        legs: const [(venue: _p, usd: 10, direct: false)],
        onwardUsd: 13,
        totalUsd: 13,
        at: _t0,
      );
      expect(_ids(g), ['leg:predictions', 'onward']);
      final onward = g.byId('onward')!;
      expect(onward.from, MoneyPlace.dollars);
      expect(onward.to, MoneyPlace.investing);
      expect(onward.after, ['leg:predictions']);
      expect(onward.status, MoneyStepStatus.waiting);
      expect(g.byId('leg:predictions')!.to, MoneyPlace.dollars);

      // The leg went, the money landed, Dollars went on.
      g = MoveSteps.legRecorded(g, _leg(_p, op: 'op-pm'),
          destination: VenueCashDestination.investing,
          forAction: VenueCashFor.investing);
      expect(g.byId('leg:predictions')!.ref, 'op-pm');
      g = MoveSteps.dollarsLanded(g, at: _t0);
      expect(_status(g, 'leg:predictions'), MoneyStepStatus.done);
      g = MoveSteps.finalSent(g, 'op-dep');
      expect(_status(g, 'onward'), MoneyStepStatus.running);
      expect(g.byId('onward')!.ref, 'op-dep');
    });

    test('the puller records a venue move: direct leg and Dollars onward',
        () async {
      var now = _t0;
      var dollars = 2.0;
      final puller = VenueCashPuller(
        sources: [_Source(_i, direct: true, available: 50)],
        readDollars: () => dollars,
        minimumUsd: (_) async => 1,
        clock: () => now,
        sleep: (d) async => now = now.add(d),
      );
      final outcome = await puller.pullShortfall(
        neededUsd: 20,
        forAction: VenueCashFor.predictions,
        destination: VenueCashDestination.predictions,
        approval: _approval('predictions'),
        waitFor: Duration.zero,
      );
      final g = MultiSourceMoveStore.get(outcome.moveId!)!.steps;
      expect(_ids(g), ['leg:investing', 'onward']);
      expect(g.byId('leg:investing')!.route, MoneyRoute.direct);
      expect(g.byId('leg:investing')!.to, MoneyPlace.predictions);
      expect(g.byId('leg:investing')!.ref, 'op-direct-investing-1');
      // Dollars' own $2 go on into Predictions, waiting on no leg.
      expect(g.byId('onward')!.after, isEmpty);
      expect(g.byId('onward')!.usd, outcome.dollarsNeededUsd);
    });

    test('an old venue record maps its legs and the onward step', () {
      final old = MultiSourceMove.fromJson((_move(
        forAction: VenueCashFor.predictions,
        destination: VenueCashDestination.predictions,
        dollars: 5,
        legs: [_leg(_i, usd: 15, op: 'op-hl')],
        finalOp: 'op-dep',
      ).toJson()))!;
      expect(old.steps.isEmpty, isTrue);
      final g = MoveSteps.of(old);
      expect(_ids(g), ['leg:investing', 'onward']);
      expect(g.byId('leg:investing')!.to, MoneyPlace.dollars);
      expect(g.byId('onward')!.after, ['leg:investing']);
      expect(_status(g, 'onward'), MoneyStepStatus.running);
      expect(g.byId('onward')!.ref, 'op-dep');
    });
  });

  group('send', () {
    test('every leg home to Dollars, then the send after all of them', () {
      final g = MoveSteps.planned(
        destination: VenueCashDestination.dollars,
        forAction: VenueCashFor.send,
        legs: const [
          (venue: _p, usd: 10, direct: false),
          // A direct flag never sends a leg anywhere but Dollars here.
          (venue: _i, usd: 15, direct: true),
        ],
        onwardUsd: 50,
        totalUsd: 50,
        at: _t0,
      );
      expect(_ids(g), ['leg:predictions', 'leg:investing', 'send']);
      expect(g.byId('leg:investing')!.to, MoneyPlace.dollars);
      expect(g.byId('leg:investing')!.route, MoneyRoute.viaDollars);
      final send = g.byId('send')!;
      expect(send.kind, MoneyStepKind.leg);
      expect(send.from, MoneyPlace.dollars);
      expect(send.to, isNull);
      expect(send.usd, 50);
      expect(send.after, ['leg:predictions', 'leg:investing']);
    });

    test('the puller: legs land after the wait, the send is attached',
        () async {
      var now = _t0;
      var dollars = 30.0;
      final puller = VenueCashPuller(
        sources: [_Source(_p, available: 40)],
        readDollars: () => dollars,
        minimumUsd: (_) async => 1,
        clock: () => now,
        sleep: (d) async {
          now = now.add(d);
          dollars = 50; // what came home landed
        },
      );
      final outcome = await puller.pullShortfall(
          neededUsd: 50, forAction: VenueCashFor.send);
      expect(outcome.dollarsCover, isTrue);
      var g = MultiSourceMoveStore.get(outcome.moveId!)!.steps;
      expect(_ids(g), ['leg:predictions', 'send']);
      expect(_status(g, 'leg:predictions'), MoneyStepStatus.done);
      expect(_status(g, 'send'), MoneyStepStatus.waiting);
      expect(g.byId('send')!.usd, 50);

      // The send went: its step follows its operation.
      MultiSourceMoveStore.attachFinal(outcome.moveId, 'op-send');
      g = MultiSourceMoveStore.get(outcome.moveId!)!.steps;
      expect(_status(g, 'send'), MoneyStepStatus.running);
      expect(g.byId('send')!.ref, 'op-send');
    });

    test('an old send record maps its legs and the send', () {
      final old = _move(
        forAction: VenueCashFor.send,
        destination: VenueCashDestination.dollars,
        total: 50,
        dollars: 30,
        legs: [_leg(_p, usd: 20.5, op: 'op-pm')],
      );
      final g = MoveSteps.of(old);
      expect(_ids(g), ['leg:predictions', 'send']);
      expect(g.byId('send')!.usd, 50);
      expect(_status(g, 'send'), MoneyStepStatus.waiting);
      final sent = MoveSteps.of(old.copyWith(finalOperationId: 'op-send'));
      expect(_status(sent, 'send'), MoneyStepStatus.running);
    });
  });

  group('home to Dollars', () {
    test('an old record with no own step maps its legs alone', () {
      final g = MoveSteps.of(_move(
        forAction: VenueCashFor.withdraw,
        destination: VenueCashDestination.dollars,
        legs: [_leg(_p, op: 'op-p'), _leg(_i, op: 'op-i')],
      ));
      expect(_ids(g), ['leg:predictions', 'leg:investing']);
      expect(g.steps.every((s) => s.after.isEmpty), isTrue);
    });
  });

  group('the Rebalance, per venue, in parallel', () {
    MoneyStepGraph sent() => RebalanceSteps.outcomes(
            RebalanceSteps.planned(const {_i: 6.54, _p: 3}, at: _t0), const {
          _i: RebalanceOutcome(RebalanceOutcomeKind.moving,
              usd: 6.54, ref: 'op-i'),
          _p: RebalanceOutcome(RebalanceOutcomeKind.moving,
              usd: 3, ref: 'op-p'),
        });

    SwapOrder home(String op, String network, {String status = 'exchanging'}) =>
        _row('ord-$op',
                from: 'USDC',
                fromNet: network,
                to: 'USDB',
                toNet: 'SPARK',
                status: status)
            .copyWith(operationId: op);

    test('one leg per venue, none waiting on another', () {
      final g = sent();
      expect(_ids(g), ['leg:investing', 'leg:predictions']);
      expect(g.steps.every((s) => s.after.isEmpty), isTrue);
      expect(g.steps.every((s) => s.status == MoneyStepStatus.running), isTrue);
      expect(g.byId('leg:investing')!.to, MoneyPlace.dollars);
      expect(g.byId('leg:investing')!.ref, 'op-i');
    });

    test('Predictions lands first, then Investing', () {
      final g = sent();
      final first = RebalanceSteps.live(g, [
        home('op-p', 'POLYGON', status: 'success'),
        home('op-i', 'HYPERCORE'),
      ]);
      expect(_status(first, 'leg:predictions'), MoneyStepStatus.done);
      expect(_status(first, 'leg:investing'), MoneyStepStatus.running);
      final both = RebalanceSteps.live(g, [
        home('op-p', 'POLYGON', status: 'success'),
        home('op-i', 'HYPERCORE', status: 'success'),
      ]);
      expect(both.allDone, isTrue);
    });

    test('Investing lands first, then Predictions', () {
      final g = sent();
      final first = RebalanceSteps.live(g, [
        home('op-p', 'POLYGON'),
        home('op-i', 'HYPERCORE', status: 'success'),
      ]);
      expect(_status(first, 'leg:investing'), MoneyStepStatus.done);
      expect(_status(first, 'leg:predictions'), MoneyStepStatus.running);
      // A venue whose money the Portfolio saw land is done too.
      final landed = RebalanceSteps.live(
          g, [home('op-i', 'HYPERCORE', status: 'success')],
          landed: {_p});
      expect(landed.allDone, isTrue);
    });

    test('held, below the minimum or not answered: not shown; not now fails',
        () {
      final g = RebalanceSteps.outcomes(
          RebalanceSteps.planned(const {_i: 6.54, _p: 3}, at: _t0), const {
        _i: RebalanceOutcome(RebalanceOutcomeKind.notNow, usd: 6.54),
      });
      expect(_status(g, 'leg:investing'), MoneyStepStatus.failed);
      expect(_status(g, 'leg:predictions'), MoneyStepStatus.skipped);
      final held = RebalanceSteps.outcomes(
          RebalanceSteps.planned(const {_p: 3}, at: _t0), const {
        _p: RebalanceOutcome(RebalanceOutcomeKind.belowMinimum, usd: 3),
        _i: RebalanceOutcome(RebalanceOutcomeKind.moving, usd: 2, ref: 'x'),
      });
      expect(_status(held, 'leg:predictions'), MoneyStepStatus.skipped);
      // A move the tap did not expect is added.
      expect(_status(held, 'leg:investing'), MoneyStepStatus.running);
    });
  });

  group('a single move, from its row', () {
    test('Add to Investments from Bitcoin: Bitcoin → Dollars', () {
      final row = _row('btc-usd',
          from: 'BTC',
          fromNet: 'SPARK',
          to: kOrchestraUsdAssetCode,
          toNet: 'SPARK',
          deposit: '0.00010000',
          withdrawal: '9.87');
      final g = MoveSteps.ofRow(row);
      expect(_ids(g), ['leg:bitcoin']);
      final leg = g.byId('leg:bitcoin')!;
      expect(leg.from, MoneyPlace.bitcoin);
      expect(leg.to, MoneyPlace.dollars);
      expect(leg.usd, 9.87);
      expect(leg.status, MoneyStepStatus.running);
      expect(
          _status(
              MoveSteps.ofRow(row.copyWith(status: 'success')), 'leg:bitcoin'),
          MoneyStepStatus.done);
      expect(
          _status(
              MoveSteps.ofRow(row.copyWith(status: 'failed')), 'leg:bitcoin'),
          MoneyStepStatus.failed);
    });

    test('Bitcoin straight into Predictions or Investing', () {
      final pm = MoveSteps.ofRow(_row('btc-pm',
          from: 'BTC', fromNet: 'SPARK', to: 'USDC.e', toNet: 'POLYGON'));
      expect(pm.byId('leg:bitcoin')!.to, MoneyPlace.predictions);
      final hl = MoveSteps.ofRow(_row('btc-hl',
          from: 'BTC', fromNet: 'SPARK', to: 'USDC', toNet: 'HYPERCORE'));
      expect(hl.byId('leg:bitcoin')!.to, MoneyPlace.investing);
    });

    test('a purchase paid by Dollars alone: the purchase, then the arrival',
        () {
      final row = _row('usd-btc',
          from: kOrchestraUsdAssetCode,
          fromNet: 'SPARK',
          to: 'BTC',
          toNet: 'SPARK',
          deposit: '5.00',
          withdrawal: '0.00005000');
      final g = MoveSteps.ofRow(row);
      expect(_ids(g), ['buy', 'arrive']);
      expect(g.byId('buy')!.usd, 5);
      expect(g.byId('buy')!.kind, MoneyStepKind.buy);
      expect(g.byId('arrive')!.after, ['buy']);
      expect(_status(g, 'buy'), MoneyStepStatus.running);
      expect(_status(g, 'arrive'), MoneyStepStatus.waiting);
      final settled = row.copyWith(status: 'success');
      final counting = MoveSteps.ofRow(settled, counting: true);
      expect(_status(counting, 'buy'), MoneyStepStatus.done);
      expect(_status(counting, 'arrive'), MoneyStepStatus.running);
      expect(MoveSteps.ofRow(settled).allDone, isTrue);
    });

    test('no graph for a send, a receive or a Cash App purchase', () {
      expect(
          MoveSteps.ofRow(_row('send',
                  from: kOrchestraUsdAssetCode,
                  fromNet: 'SPARK',
                  to: 'USDC',
                  toNet: 'POLYGON',
                  direction: 'send'))
              .isEmpty,
          isTrue);
      expect(
          MoveSteps.ofRow(_row('in',
                  from: 'USDC', fromNet: 'ETHEREUM', to: 'BTC', toNet: 'SPARK'))
              .isEmpty,
          isTrue);
    });
  });

  group('a Retry from another venue never leaves a step waiting', () {
    // "Move $20 to Bitcoin": $8 Investing straight to Bitcoin, $12
    // Predictions home to Dollars, which failed; the Retry pulled the
    // remainder from Investing.
    final failedLeg = _leg(_p, ok: false, usd: 12);
    final direct = _leg(_i, direct: true, usd: 8, op: 'op-hl');
    final retry = _leg(_i,
        direct: true,
        usd: 12.2,
        op: 'op-retry',
        at: _t0.add(const Duration(minutes: 3)));

    MultiSourceMove record(List<MultiSourceMoveLeg> legs, MoneyStepGraph g) =>
        MultiSourceMove(
          id: 'msm_retry',
          forAction: VenueCashFor.buyBitcoin,
          destination: VenueCashDestination.bitcoin,
          totalUsd: 20,
          dollarsUsd: 0,
          createdAt: _t0,
          legs: legs,
          steps: g,
        );

    MoneyStepGraph plannedGraph() => MoveSteps.planned(
          destination: VenueCashDestination.bitcoin,
          forAction: VenueCashFor.buyBitcoin,
          legs: const [
            (venue: _i, usd: 8, direct: true),
            (venue: _p, usd: 12, direct: false),
          ],
          onwardUsd: 12.08,
          totalUsd: 20,
          at: _t0,
        );

    test('while the move is partial the failed leg is still owed', () {
      MultiSourceMoveStore.start(record(const [], plannedGraph()));
      MultiSourceMoveStore.addLeg('msm_retry', direct);
      MultiSourceMoveStore.addLeg('msm_retry', failedLeg);
      final move = MultiSourceMoveStore.get('msm_retry')!;
      expect(move.partial, isTrue);
      final g = MoveSteps.of(move);
      expect(_status(g, 'leg:predictions'), MoneyStepStatus.failed);
      expect(g.byId('leg:predictions')!.reason, isNot('replaced'));
      expect(g.byId('buy')!.after, ['leg:predictions']);
    });

    test('once the Retry covered it, nothing waits on the failed leg', () {
      MultiSourceMoveStore.start(record(const [], plannedGraph()));
      MultiSourceMoveStore.addLeg('msm_retry', direct);
      MultiSourceMoveStore.addLeg('msm_retry', failedLeg);
      MultiSourceMoveStore.addLeg('msm_retry', retry);
      final move = MultiSourceMoveStore.get('msm_retry')!;
      expect(move.partial, isFalse);
      final g = move.steps;
      expect(_ids(g), [
        'leg:investing',
        'leg:predictions',
        'leg:investing:2',
        'buy',
        'arrive'
      ]);
      // Kept as failed for the record, waited on by nothing.
      expect(_status(g, 'leg:predictions'), MoneyStepStatus.failed);
      expect(g.byId('leg:predictions')!.reason, MoveSteps.replacedReason);
      expect(g.byId('buy')!.after, isEmpty);
      expect(
          g.byId('arrive')!.after, ['buy', 'leg:investing', 'leg:investing:2']);
    });

    test('a graph stuck by an earlier build is fixed when read', () {
      // As 2.1.2's first graph wrote it: arrive waiting on the failed leg
      // (through buy) after the Retry leg was added.
      var g = plannedGraph();
      for (final l in [direct, failedLeg, retry]) {
        g = MoveSteps.legRecorded(g, l,
            destination: VenueCashDestination.bitcoin,
            forAction: VenueCashFor.buyBitcoin);
      }
      expect(g.byId('buy')!.after, ['leg:predictions']);
      final read = MoveSteps.of(record([direct, failedLeg, retry], g));
      expect(read.byId('buy')!.after, isEmpty);
      expect(read.byId('leg:predictions')!.reason, MoveSteps.replacedReason);
    });

    test('an old record without steps maps a covered Retry the same way', () {
      final g = MoveSteps.of(
          record([direct, failedLeg, retry], MoneyStepGraph.empty));
      expect(g.byId('leg:predictions')!.reason, MoveSteps.replacedReason);
      // Both Investing legs went straight to Bitcoin: nothing left to buy,
      // and the arrival waits on them alone.
      expect(g.byId('buy'), isNull);
      expect(g.byId('arrive')!.after, ['leg:investing', 'leg:investing:2']);
    });
  });

  test('every graph round-trips through the record', () {
    final move = _move(
      forAction: VenueCashFor.send,
      destination: VenueCashDestination.dollars,
      legs: [_leg(_p, op: 'op-p')],
    );
    final g = MoveSteps.of(move);
    final back = MultiSourceMove.fromJson(
        jsonDecode(jsonEncode(move.copyWith(steps: g).toJson())))!;
    expect(jsonEncode(back.steps.toJson()), jsonEncode(g.toJson()));
  });
}
