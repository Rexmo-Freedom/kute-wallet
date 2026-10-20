// lib/services/one_balance/venue_cash_funded_order.dart
//
// An order whose venue is short, funded from Dollars AND the other
// venue's cash, no Bitcoin (founder report 15 October 2026: "i have 5
// dollars in polymarket, 5 in usdb, and it still does not show all the
// steps we have to do, besides it is stuck at preparing order"). The same
// step graph as an order funded from Bitcoin (`bitcoin_funded_order.dart`,
// `fundedOrderGraph`), one line per source, every source started at once
// after the ONE approval. An Investing order:
//
//   leg:predictions   Moving $4.20 from Predictions    straight into the
//                                                      venue when the
//                                                      approval binds it
//   leg:dollars       Moving $6.92 from Dollars        at once, the
//                                                      Dollars already held
//   ready:credit      Crediting to trading balance     from the first money
//                                                      landing
//   place             Opening $10.76 Long BTC          once the venue holds
//                                                      enough (its autofire)
//
// A bet (the bet slip, the same runner): the Investing cash goes straight
// into Predictions by Circle CCTP under the approval (Flashnet offers no
// HyperCore-source route; `HyperCoreMoveRail.withdrawDirect`), the
// readiness is Predictions' own:
//
//   leg:investing     Moving $6.00 from Investing      straight in (CCTP)
//   leg:dollars       Moving $5.00 from Dollars        at once
//   ready:convert     Converting to pUSD               once some money
//   ready:approve     Approving spend                  landed, each only
//   ready:confirm     Confirming balance               when the venue needs it
//   place             Placing $10.00 on Yes            the autofire, once
//                                                      Predictions hold enough
//
// A leg planned straight in that the rail refused before anything moved
// falls back with its real reason ([MoneyFallBack]): Predictions → Dollars,
// then Dollars → the venue for what landed. A leg the approval does not
// bind goes that way from the start. A leg home to Dollars is followed by
// its Orchestra order's status (the landing signal), never by the Dollars
// balance alone; the balance is then asked to catch up
// (`usdBalanceCheckProvider`) and read, bounded, for the move on.
//
// Every wait is bounded: each leg's delivery (`watchLegDelivery`, 12
// minutes), the Dollars catching up (30 seconds), the venue's credit and
// the order (the autofire's own 12 minutes). A stop drops the order and
// cancels its approval; the money stays where it got to (Dollars, the
// venue, or on its way there), and the slip says where.
//
// Analytics: the funnel's own events (`order_funding_*`, the venue's
// autofire reports the end) with `route` and each leg's `ms_leg_*`; the
// puller's `venue_cash_direct_refused` and `*_cash_pulled`. No ids, no
// addresses.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/auth_grant.dart' show AuthGrant;
import 'package:kute/helpers/venue_intents.dart'
    show DirectLegGrants, IntentUnits;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/bitcoin_to_venue_leg.dart'
    show LegDelivery, watchLegDelivery;
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/investments_spendable.dart'
    show VenueCashSnapshot, venueCashSnapshotProvider;
import 'package:kute/services/one_balance/move_steps.dart' show MoveSteps;
import 'package:kute/services/one_balance/multi_source_move.dart'
    show MultiSourceMoveStore;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/slow_move.dart'
    show slowMoveAfter;
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart'
    show VenueMoveResult;
import 'package:kute/services/tracking_service.dart';

/// Queues the order behind its money and moves [fundUsd] from Dollars,
/// the venue holding [readyUsd] for it meanwhile. [fundUsd] 0: queued
/// only, nothing leaves Dollars.
typedef VenueCashQueue = Future<OrderFundingOutcome> Function(
    {required double fundUsd, required double readyUsd});

/// A further move of [usd] from Dollars into the venue under the order's
/// same approval (what a leg brought home to Dollars), the order already
/// queued. [controller] reads Dollars as the chain last saw them.
typedef VenueCashFundMore = Future<OrderFundingOutcome> Function(
    OrderFundingController controller, double usd);

/// What a slip hands the runner once the person approved.
class VenueCashFundedRequest {
  VenueCashFundedRequest({
    required this.venue,
    required this.grant,
    required this.label,
    required this.fundUsd,
    required this.readyUsd,
    required this.plan,
    required this.queue,
    required this.fundMore,
    required this.dropOrder,
    this.moveId,
    this.entrySource,
    this.awaitPlacement,
    this.bindAttempt,
    this.isCurrentAttempt,
  });

  final OneBalanceVenue venue;

  /// The order's one approval (its autofire grant): the order, the most
  /// that may leave Dollars for it, and the other venue's legs straight
  /// in (`VenueLimit.directLegs`).
  final AuthGrant grant;
  final FundedOrderLabel label;

  /// The approved move into the venue (`kFundUsdLimit`).
  final double fundUsd;

  /// The venue's ready cash when the order was approved.
  final double readyUsd;

  /// The plan the approval bound ([VenueCashPuller.plan]): Dollars' share
  /// and every venue leg, run exactly as approved.
  final VenueCashPlan plan;
  final VenueCashQueue queue;
  final VenueCashFundMore fundMore;

  /// Drops the queued order and cancels its approval.
  final void Function() dropOrder;

  /// An earlier try's move record, continued (its legs that went straight
  /// in are not pulled again).
  final String? moveId;
  final String? entrySource;

  /// The step after the money, in place of the venue's own placement
  /// watch (tests).
  final BitcoinPlacementWait? awaitPlacement;
  final bool Function(String runId)? bindAttempt;
  final bool Function()? isCurrentAttempt;
}

/// Step ids this chain adds to [FundedStepId]'s.
abstract final class VenueCashStepId {
  /// A venue leg home to Dollars ("Moving $4.20 from Predictions →
  /// Dollars").
  static String home(OneBalanceVenue venue) => 'leg:${venue.name}>dollars';
}

/// Runs [VenueCashFundedRequest]s. See the file header.
class VenueCashFundedOrderRunner {
  VenueCashFundedOrderRunner(this._ref);

  final Ref _ref;

  /// Test seam: the clock the steps and the leg timings use.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// How long the Dollars reading gets to show what a leg brought home
  /// before the move on reads what it has.
  @visibleForTesting
  static Duration dollarsCatchUp = const Duration(seconds: 30);

  /// The longest a leg's Orchestra order is followed before the order
  /// goes (its money lands wherever it was going, whenever it does).
  @visibleForTesting
  static Duration legMaxWait = const Duration(minutes: 12);

  /// How often the Dollars reading is looked at meanwhile.
  @visibleForTesting
  static Duration dollarsPollEvery = const Duration(milliseconds: 500);

  /// Records the order (its steps show from now) and starts every leg;
  /// returns at once. The run ends placed, stopped or not placed.
  BitcoinFundedRun start(VenueCashFundedRequest r) {
    if (r.isCurrentAttempt?.call() == false) {
      r.grant.revoke();
      return BitcoinFundedRun('', Future.value(BitcoinFundedEnd.notSent));
    }
    final orders = _ref.read(fundedOrdersProvider.notifier);
    final id = orders.start(r.label, stage: FundedOrderStage.preparing);
    if (r.bindAttempt?.call(id) == false) {
      r.grant.revoke();
      orders.remove(id);
      return BitcoinFundedRun(id, Future.value(BitcoinFundedEnd.notSent));
    }
    return BitcoinFundedRun(id, _VenueCashChain(_ref, id, r).run());
  }
}

final venueCashFundedOrderRunnerProvider = Provider<VenueCashFundedOrderRunner>(
    (ref) => VenueCashFundedOrderRunner(ref));

class _VenueCashChain {
  _VenueCashChain(Ref ref, this.id, this.r)
      : _ref = ref,
        _cashSnapshot = ref.read(venueCashSnapshotProvider);

  final Ref _ref;
  final String id;
  final VenueCashFundedRequest r;
  final VenueCashSnapshot _cashSnapshot;

  late final BitcoinLegEnv env = _ref.read(bitcoinLegEnvProvider);
  late final FundedOrdersNotifier orders =
      _ref.read(fundedOrdersProvider.notifier);
  late final VenueCashPuller puller = _ref.read(venueCashPullerProvider);
  late final BitcoinFundedOrderRunner runner =
      _ref.read(bitcoinFundedOrderRunnerProvider);
  final OrderFundingJourney journey = OrderFundingJourney.instance;

  OneBalanceVenue get venue => r.venue;
  VenueCashDestination get destination => venueCashDestinationOf(venue);
  DateTime _now() => VenueCashFundedOrderRunner.clock();

  BitcoinFundedEnd? _end;
  final Completer<BitcoinFundedEnd> _ended = Completer();
  final Completer<void> _stopped = Completer();
  final Completer<void> _credited = Completer();
  final Completer<void> _placeEnded = Completer();
  late final Future<bool> _placement;
  bool _placed = false;
  String? _failedText;
  String? _failedCode;
  String _route = MoneyRoute.direct;

  /// The venue legs, once they went (null: the pull itself failed).
  late final Future<VenueCashPullOutcome?> _pull;

  /// The move record the legs are in, once written.
  final Completer<String?> _moveId = Completer();

  /// What left Dollars for the order so far.
  double _dollarsSent = 0;

  /// What the legs planned straight in are expected to land in the venue.
  double _directArriving = 0;

  /// Whether a move from Dollars went (the move's own step is then the
  /// settlement's, not this chain's to stop).
  bool _dollarsMoved = false;

  static double _cents(double usd) => (usd * 100).roundToDouble() / 100;

  Future<BitcoinFundedEnd> run() {
    unawaited(_go().then((end) {
      if (!_ended.isCompleted) _ended.complete(end);
    }, onError: (Object e) {
      runner.recordError(id, e);
      if (!_ended.isCompleted) {
        _ended.complete(_stop(BitcoinFundedEnd.notSent,
            stage: FundedOrderStage.failed,
            reason: 'not_sent',
            category: TrackingService.errorCategory(e),
            moneyAt: FundedMoneyAt.investments));
      }
    }));
    return _ended.future;
  }

  /// Stops the run: the record says where the money is, the order is
  /// dropped and its approval cancelled; the move's own step (Dollars
  /// going on into the venue) is stopped when nothing left Dollars yet.
  /// The first stop wins; legs already on their way keep landing.
  BitcoinFundedEnd _stop(BitcoinFundedEnd end,
      {required FundedOrderStage stage,
      required String reason,
      String? category,
      OrderFundingStage journeyStage = OrderFundingStage.fund,
      FundedMoneyAt? moneyAt,
      String? message}) {
    final already = _end;
    if (already != null) return already;
    _end = end;
    orders.stop(id,
        stage: stage, reason: reason, moneyAt: moneyAt, message: message);
    if (category != null) journey.failed(venue, journeyStage, category);
    try {
      r.dropOrder();
    } catch (_) {}
    if (!_dollarsMoved) {
      unawaited(_moveId.future.then((moveId) => MoveSteps.record(
          moveId, (g) => MoveSteps.finalStopped(g, reason, at: _now()))));
    }
    if (!_stopped.isCompleted) _stopped.complete();
    if (!_ended.isCompleted) _ended.complete(end);
    return end;
  }

  /// Whether [p] goes straight into the venue: its rail offers the route,
  /// it is not refused lately, and the approval binds it.
  bool _plannedDirect(VenueCashPull p) =>
      puller.directVenues(r.plan, destination).contains(p.venue) &&
      DirectLegGrants.covers(r.grant,
          venue: p.venue.name,
          destination: destination.code,
          amount: IntentUnits.usd(p.usd));

  Future<BitcoinFundedEnd> _go() async {
    final plan = r.plan;
    final share = _cents(math.max(0.0, math.min(plan.dollarsUsd, r.fundUsd)));
    final direct = [
      for (final p in plan.pulls)
        if (_plannedDirect(p)) p,
    ];
    final home = [
      for (final p in plan.pulls)
        if (!direct.contains(p)) p,
    ];
    _route = home.isEmpty ? MoneyRoute.direct : MoneyRoute.viaDollars;
    _directArriving = direct.fold(0.0, (s, p) => s + p.arrivingUsd);
    final legs = <MoneyStep>[
      for (final p in plan.pulls)
        direct.contains(p)
            ? MoneyStep(
                id: FundedStepId.other(p.venue),
                kind: MoneyStepKind.leg,
                from: moneyPlaceOf(p.venue),
                usd: _cents(p.usd),
                route: MoneyRoute.direct)
            : MoneyStep(
                id: VenueCashStepId.home(p.venue),
                kind: MoneyStepKind.leg,
                from: moneyPlaceOf(p.venue),
                to: MoneyPlace.dollars,
                usd: _cents(p.usd),
                route: MoneyRoute.viaDollars),
      if (share >= 0.01)
        MoneyStep(
            id: FundedStepId.dollars,
            kind: MoneyStepKind.leg,
            from: MoneyPlace.dollars,
            usd: share),
      if (home.isNotEmpty)
        MoneyStep(
            id: FundedStepId.dollarsOnward,
            kind: MoneyStepKind.leg,
            from: MoneyPlace.dollars,
            usd: _cents(home.fold(0.0, (s, p) => s + p.arrivingUsd)),
            route: MoneyRoute.viaDollars,
            after: [for (final p in home) VenueCashStepId.home(p.venue)]),
    ];
    // A new try keeps the legs that landed before (done, never run again).
    final carried = [
      for (final s in orders.byId(id)?.steps.steps ?? const <MoneyStep>[])
        if (s.id.startsWith('prev:')) s,
    ];
    final graph = MoneyStepGraph([
      ...carried,
      ...fundedOrderGraph(venue: venue, legs: legs, orderUsd: r.label.orderUsd)
          .steps,
    ]);
    orders.setSteps(id, graph, route: _route);

    journey.start(
      venue,
      orderUsd: r.label.orderUsd,
      fundUsd: r.fundUsd,
      readyUsd: r.readyUsd,
      dollarsUsd: share,
      entrySource: r.entrySource,
      fundingSource: 'venue_cash',
      otherVenueUsed: plan.pulls.isNotEmpty,
      extra: {'legs': plan.pulls.length + (share >= 0.01 ? 1 : 0)},
    );
    journey.setRoute(venue, _route,
        reason: home.isEmpty ? null : 'not_approved_direct');

    // The venue's own placement, followed from now on: it fires the
    // moment the venue holds enough, whatever leg is still landing.
    final wait = r.awaitPlacement ??
        runner.placementWaitFor(venue, fundedRunId: id,
            onFailed: (message, code) {
          _failedText = message;
          _failedCode = code;
        });
    _placement = wait(onCredited: () {
      if (!_credited.isCompleted) _credited.complete();
      orders.setStage(id, FundedOrderStage.placing);
    }).then((placed) {
      _placed = placed;
      return placed;
    }).catchError((Object _) => false);

    // Every venue leg at once, exactly as approved; nothing waits on the
    // Dollars balance here (the legs follow their own orders).
    _pull = puller
        .pullShortfall(
      neededUsd: plan.neededUsd,
      forAction: venueCashForOf(venue),
      destination: destination,
      exclude: venue,
      waitFor: Duration.zero,
      moveId: r.moveId,
      approval: r.grant,
      plan: plan,
      onStarted: (moveId) {
        if (!_moveId.isCompleted) _moveId.complete(moveId);
      },
    )
        .then<VenueCashPullOutcome?>((o) {
      if (!_moveId.isCompleted) _moveId.complete(o.moveId);
      return o;
    }, onError: (Object e) {
      runner.recordError(id, e);
      if (!_moveId.isCompleted) _moveId.complete(null);
      return null;
    });

    // No Dollars of its own to send: the order is queued now, behind the
    // legs (the venue's autofire places it once they landed).
    if (share < 0.01) {
      final queued = await _queue(0, readyUsd: _readyForQueue());
      if (queued is OrderFundingRefused && queued is! OrderFundingUnconfirmed) {
        return _stop(BitcoinFundedEnd.notSent,
            stage: FundedOrderStage.failed,
            reason: 'venue_refused',
            category: queued.reason,
            moneyAt: FundedMoneyAt.investments);
      }
    }

    final steps = MoneyStepRunner(
      graph: graph,
      actionFor: _actionFor,
      onChange: (g) => orders.setSteps(id, g, route: _route),
      clock: _now,
    );
    var settled = await Future.any<MoneyStepGraph?>([
      steps.run(),
      _placeEnded.future.then((_) => null),
    ]);
    settled ??= steps.graph;
    final stopped = _end;
    if (stopped != null) return stopped;
    if (settled.byId(FundedStepId.place)?.status == MoneyStepStatus.done) {
      orders.setStage(id, FundedOrderStage.done);
      return BitcoinFundedEnd.placed;
    }
    // The money reached the venue (or is on its way there): it stays as
    // its cash, available.
    orders.stop(id,
        stage: FundedOrderStage.failed,
        reason: _failedCode ?? 'placement',
        moneyAt: FundedMoneyAt.venue,
        message: _failedText);
    try {
      r.dropOrder();
    } catch (_) {}
    return BitcoinFundedEnd.placementFailed;
  }

  /// What the venue holds for the order once the legs straight in landed:
  /// what the Dollars move is sized against.
  double _readyForQueue() => r.readyUsd + _directArriving;

  Future<OrderFundingOutcome> _queue(double fundUsd,
      {required double readyUsd}) async {
    try {
      return await r.queue(fundUsd: fundUsd, readyUsd: readyUsd);
    } catch (e) {
      runner.recordError(id, e);
      return OrderFundingRefused(TrackingService.errorCategory(e), error: e);
    }
  }

  MoneyStepAction? _actionFor(MoneyStep step) {
    if (step.id == FundedStepId.dollars) return _dollarsShare;
    if (step.id.startsWith(FundedStepId.dollarsOnward)) return _onward;
    for (final v in OneBalanceVenue.values) {
      if (step.id == FundedStepId.other(v)) return _direct;
      if (step.id == VenueCashStepId.home(v) ||
          step.id == '${FundedStepId.other(v)}:via_dollars') {
        return _home;
      }
    }
    switch (step.id) {
      // Predictions: the conversion to pUSD and the spend allowance only
      // when the venue needs them, then its own balance confirmed.
      case FundedStepId.convert:
        return (s, u) => _phase('converting', u, optional: true);
      case FundedStepId.approve:
        return (s, u) => _phase('approving', u, optional: true);
      case FundedStepId.confirm:
        return (s, u) => _phase('confirming', u);
      // Investing: the credit where the order draws from.
      case FundedStepId.credit:
        return (s, u) => _phase('crediting', u);
      case FundedStepId.place:
        return _place;
    }
    return null;
  }

  void _slow() => orders.update(id, (rec) => rec.copyWith(slow: true));

  void _landed(MoneyStep step, String source) {
    final started = step.startedAt;
    if (started == null) return;
    journey.legLanded(venue, source, _now().difference(started).inMilliseconds);
  }

  /// Follows one Orchestra order to delivery. Without a status read (a
  /// test's wallet) it counts as landed once the venue credited the order.
  Future<LegDelivery> _delivery(String Function() legId,
      {void Function()? onExplicitRefund, Duration? estimate}) {
    final statusOf = env.legStatus;
    if (statusOf == null) {
      return Future.any<LegDelivery>([
        _credited.future.then((_) => LegDelivery.delivered),
        _placement.then(
            (placed) => placed ? LegDelivery.delivered : LegDelivery.timedOut),
      ]);
    }
    var refundNotified = false;
    return watchLegDelivery(
        id: legId,
        statusOf: (id) async {
          final status = await statusOf(id);
          if (!refundNotified && status?.trim().toLowerCase() == 'refunded') {
            refundNotified = true;
            onExplicitRefund?.call();
          }
          return status;
        },
        pollEvery: env.legPollEvery,
        maxWait: VenueCashFundedOrderRunner.legMaxWait,
        // Slow past 1.5 times the route's estimate (90 s without one).
        slowAfter: slowMoveAfter(estimate: estimate),
        onSlow: _slow);
  }

  /// The move's row ids name this order; its id follows the background
  /// registration. Returns the id the leg is followed by.
  String Function() _follow(VenueMoveResult move,
      void Function(MoneyStep Function(MoneyStep)) update) {
    orders.addVenueRow(id, move.quoteId);
    if (move.orderId != null) orders.addVenueRow(id, move.orderId!);
    var legId = move.orderId ?? move.quoteId;
    update((s) => s.copyWith(ref: legId));
    final reg = move.registration;
    if (reg != null) {
      unawaited(reg.then((orderId) {
        if (orderId == null || orderId.isEmpty) return;
        legId = orderId;
        orders.addVenueRow(id, orderId);
        update((s) => s.copyWith(ref: orderId));
      }).catchError((Object _) {}));
    }
    return () => legId;
  }

  /// A move from Dollars went: the first is the move's own step (one
  /// Activity row for the whole move).
  void _attach(VenueMoveResult move) {
    if (_dollarsMoved) return;
    _dollarsMoved = true;
    final op = move.operationId ?? move.quoteId;
    unawaited(_moveId.future
        .timeout(const Duration(minutes: 2), onTimeout: () => null)
        .then((moveId) => MultiSourceMoveStore.attachFinal(moveId, op)));
  }

  /// Dollars' own share, at once: the order is queued with it.
  Future<MoneyStepOutcome> _dollarsShare(MoneyStep step,
      void Function(MoneyStep Function(MoneyStep)) update) async {
    final outcome = await _queue(step.usd, readyUsd: _readyForQueue());
    switch (outcome) {
      case OrderFundingFunded(:final move):
        _dollarsSent += move.sentUsd > 0 ? move.sentUsd : step.usd;
        _attach(move);
        if (move.sentUsd > 0) {
          update((s) => s.copyWith(usd: _cents(move.sentUsd)));
        }
        final legId = _follow(move, update);
        switch (await _delivery(legId)) {
          case LegDelivery.delivered:
            _landed(step, 'dollars');
            return MoneyStepDone(ref: legId());
          case LegDelivery.failed:
            // Orchestra sends the dollars back to Dollars.
            _stop(BitcoinFundedEnd.ready,
                stage: FundedOrderStage.ready,
                reason: 'venue_refused',
                category: 'refunded',
                moneyAt: FundedMoneyAt.investments);
            return const MoneyStepFailed('refunded');
          case LegDelivery.timedOut:
            _stop(BitcoinFundedEnd.ready,
                stage: FundedOrderStage.ready,
                reason: 'timeout',
                category: 'timeout',
                moneyAt: FundedMoneyAt.venue);
            return const MoneyStepFailed('timeout');
        }
      case OrderFundingNotNeeded():
        // The venue covers it with what goes straight in: Dollars give
        // nothing, so the move has no step of its own to wait on (set
        // once the legs went, after the puller sized that step).
        unawaited(_pull.then((_) => _moveId.future).then((moveId) =>
            MoveSteps.record(
                moveId,
                (g) => MoveSteps.onward(g, 0,
                    destination: destination,
                    forAction: venueCashForOf(venue)))));
        return const MoneyStepSkipped();
      case OrderFundingUnconfirmed():
        // The rail could not say: the order stays queued and the venue's
        // autofire watches the account.
        _dollarsMoved = true;
        return const MoneyStepDone();
      case OrderFundingRefused(:final reason, :final error):
        if (error != null) runner.recordError(id, error);
        _stop(BitcoinFundedEnd.ready,
            stage: FundedOrderStage.failed,
            reason: 'venue_refused',
            category: reason,
            moneyAt: FundedMoneyAt.investments,
            message: error == null ? null : runner.errorTextFor(error));
        return MoneyStepFailed(reason);
      case OrderFundingNeedsDollars():
        _stop(BitcoinFundedEnd.ready,
            stage: FundedOrderStage.failed,
            reason: 'venue_refused',
            category: 'insufficient_funds',
            moneyAt: FundedMoneyAt.investments);
        return const MoneyStepFailed('insufficient_funds');
    }
  }

  /// [step]'s venue leg among the pulled ones (null: the pull failed or
  /// the run stopped first).
  Future<VenueCashLegOutcome?> _legOf(MoneyStep step) async {
    final pulled = await Future.any<VenueCashPullOutcome?>([
      _pull,
      _stopped.future.then((_) => null),
    ]);
    if (pulled == null) return null;
    for (final l in pulled.legs) {
      if (moneyPlaceOf(l.venue) == step.from) return l;
    }
    return null;
  }

  /// A leg that did not go: its money stays on its venue; the order
  /// cannot be covered, so it goes.
  MoneyStepOutcome _legRefused(VenueCashLegOutcome? leg) {
    final e = leg?.error;
    if (e != null) runner.recordError(id, e);
    final category = e == null
        ? (_end != null ? 'stopped' : 'venue_cash')
        : TrackingService.errorCategory(e);
    _stop(BitcoinFundedEnd.notSent,
        stage: FundedOrderStage.failed,
        reason: 'venue_cash_pending',
        category: category,
        moneyAt:
            _dollarsMoved ? FundedMoneyAt.venue : FundedMoneyAt.investments,
        message: e == null ? null : runner.errorTextFor(e));
    return MoneyStepFailed(category);
  }

  /// A venue leg straight into the venue: done once its order delivered.
  /// Refused before anything moved, it falls back with the reason: home
  /// to Dollars, then on from there.
  Future<MoneyStepOutcome> _direct(MoneyStep step,
      void Function(MoneyStep Function(MoneyStep)) update) async {
    final leg = await _legOf(step);
    if (leg == null || !leg.ok) return _legRefused(leg);
    final source = step.from?.name ?? 'other';
    if (!leg.direct) {
      final reason = leg.fellBackReason ?? 'direct_refused';
      _route = MoneyRoute.viaDollars;
      journey.setRoute(venue, _route, reason: reason);
      final res = leg.result!;
      final homeId = '${step.id}:via_dollars';
      return MoneyStepFellBack(reason, [
        MoneyStep(
            id: homeId,
            kind: MoneyStepKind.leg,
            from: step.from,
            to: MoneyPlace.dollars,
            usd: _cents(leg.sentUsd),
            route: MoneyRoute.viaDollars,
            ref: res.orderId ?? res.quoteId),
        MoneyStep(
            id: '${FundedStepId.dollarsOnward}:$source',
            kind: MoneyStepKind.leg,
            from: MoneyPlace.dollars,
            usd: _cents(leg.arrivingUsd),
            route: MoneyRoute.viaDollars,
            after: [homeId]),
      ]);
    }
    final legId = _follow(leg.result!, update);
    switch (await _delivery(legId, onExplicitRefund: () {
      unawaited(_cashSnapshot.refresh(_ref.read, settledRefs: {
        leg.result!.operationId ?? leg.result!.quoteId,
      }));
    })) {
      case LegDelivery.delivered:
        _landed(step, source);
        unawaited(_cashSnapshot.refresh(_ref.read, settledRefs: {
          leg.result!.operationId ?? leg.result!.quoteId,
        }));
        return MoneyStepDone(ref: legId());
      case LegDelivery.failed:
        // Refunded: the cash goes back to its venue.
        _stop(BitcoinFundedEnd.ready,
            stage: FundedOrderStage.failed,
            reason: 'refunded',
            category: 'refunded',
            moneyAt: FundedMoneyAt.investments);
        return const MoneyStepFailed('refunded');
      case LegDelivery.timedOut:
        // Never placed later at a price nobody saw: the order goes, the
        // money lands in the venue whenever it does.
        _stop(BitcoinFundedEnd.ready,
            stage: FundedOrderStage.ready,
            reason: 'timeout',
            category: 'timeout',
            moneyAt: FundedMoneyAt.venue);
        return const MoneyStepFailed('timeout');
    }
  }

  /// What each venue's leg home landed, for the move on.
  final Map<MoneyPlace, double> _landedHome = {};

  /// A venue leg home to Dollars: done once its Orchestra order says it
  /// delivered (the landing signal; the Dollars balance can lag behind it
  /// by a sync), then Dollars are asked to catch up.
  Future<MoneyStepOutcome> _home(MoneyStep step,
      void Function(MoneyStep Function(MoneyStep)) update) async {
    final leg = await _legOf(step);
    if (leg == null || !leg.ok) return _legRefused(leg);
    final legId = _follow(leg.result!, update);
    final source = step.from?.name ?? 'other';
    final from = switch (step.from) {
      MoneyPlace.predictions => OneBalanceVenue.predictions,
      MoneyPlace.investing => OneBalanceVenue.investing,
      _ => null,
    };
    switch (await _delivery(legId,
        estimate: from == null ? null : kVenuePullEta[from],
        onExplicitRefund: () {
      unawaited(_cashSnapshot.refresh(_ref.read, settledRefs: {
        leg.result!.operationId ?? leg.result!.quoteId,
      }));
    })) {
      case LegDelivery.delivered:
        _landed(step, source);
        unawaited(_cashSnapshot.refresh(_ref.read, settledRefs: {
          leg.result!.operationId ?? leg.result!.quoteId,
        }));
        puller.landedHome(leg.arrivingUsd);
        try {
          env.checkDollars?.call();
        } catch (_) {}
        if (step.from != null) _landedHome[step.from!] = leg.arrivingUsd;
        return MoneyStepDone(ref: legId());
      case LegDelivery.failed:
        _stop(BitcoinFundedEnd.ready,
            stage: FundedOrderStage.failed,
            reason: 'refunded',
            category: 'refunded',
            moneyAt: FundedMoneyAt.investments);
        return const MoneyStepFailed('refunded');
      case LegDelivery.timedOut:
        // It lands in Dollars whenever it does; the order goes.
        _stop(BitcoinFundedEnd.ready,
            stage: FundedOrderStage.ready,
            reason: 'timeout',
            category: 'timeout',
            moneyAt: FundedMoneyAt.investments);
        return const MoneyStepFailed('timeout');
    }
  }

  /// Dollars as the wallet shows them, given at most
  /// [VenueCashFundedOrderRunner.dollarsCatchUp] to show [usd].
  Future<double> _dollarsFor(double usd) async {
    final started = DateTime.now();
    var best = 0.0;
    while (true) {
      try {
        best = math.max(best, env.dollarsNow());
      } catch (_) {}
      if (best + 1e-6 >= usd) return best;
      double? fresh;
      try {
        fresh = await env.freshDollars();
      } catch (_) {
        fresh = null;
      }
      if (fresh != null && fresh > best) best = fresh;
      if (best + 1e-6 >= usd) return best;
      if (DateTime.now().difference(started) >=
          VenueCashFundedOrderRunner.dollarsCatchUp) {
        return best;
      }
      await Future<void>.delayed(VenueCashFundedOrderRunner.dollarsPollEvery);
    }
  }

  /// What came home goes on into the venue, under the same approval: at
  /// most what landed and what the approval has left. Not needed once
  /// the order is placed (the money stays in Dollars).
  Future<MoneyStepOutcome> _onward(MoneyStep step,
      void Function(MoneyStep Function(MoneyStep)) update) async {
    if (_end != null) return const MoneyStepFailed('stopped');
    if (_placed) return const MoneyStepSkipped();
    final landed = step.id == FundedStepId.dollarsOnward
        ? _landedHome.values.fold(0.0, (s, v) => s + v)
        : (_landedHome[MoneyPlace.values
                .where((p) => step.id.endsWith(':${p.name}'))
                .firstOrNull] ??
            step.usd);
    final usd = _cents(math.min(landed > 0 ? landed : step.usd,
        math.max(0.0, r.fundUsd - _dollarsSent)));
    if (usd < 0.01) return const MoneyStepSkipped();
    final dollars = await _dollarsFor(usd);
    if (_end != null) return const MoneyStepFailed('stopped');
    if (_placed) return const MoneyStepSkipped();
    final controller = _ref
        .read(orderFundingControllerProvider)
        .withDollars(() => math.max(env.dollarsNow(), dollars));
    OrderFundingOutcome outcome;
    try {
      outcome = await r.fundMore(controller, usd);
    } catch (e) {
      outcome = OrderFundingRefused(TrackingService.errorCategory(e), error: e);
    }
    switch (outcome) {
      case OrderFundingFunded(:final move):
        _dollarsSent += move.sentUsd > 0 ? move.sentUsd : usd;
        _attach(move);
        update((s) =>
            s.copyWith(usd: _cents(move.sentUsd > 0 ? move.sentUsd : usd)));
        final legId = _follow(move, update);
        switch (await _delivery(legId)) {
          case LegDelivery.delivered:
            _landed(step, 'dollars');
            return MoneyStepDone(ref: legId());
          case LegDelivery.failed:
            _stop(BitcoinFundedEnd.ready,
                stage: FundedOrderStage.ready,
                reason: 'venue_refused',
                category: 'refunded',
                moneyAt: FundedMoneyAt.investments);
            return const MoneyStepFailed('refunded');
          case LegDelivery.timedOut:
            _stop(BitcoinFundedEnd.ready,
                stage: FundedOrderStage.ready,
                reason: 'timeout',
                category: 'timeout',
                moneyAt: FundedMoneyAt.venue);
            return const MoneyStepFailed('timeout');
        }
      case OrderFundingNotNeeded():
        return const MoneyStepSkipped();
      case OrderFundingUnconfirmed():
        return const MoneyStepDone();
      case OrderFundingRefused(:final reason, :final error):
        if (error != null) runner.recordError(id, error);
        // Nothing left Dollars: what came home stays there.
        _stop(BitcoinFundedEnd.ready,
            stage: FundedOrderStage.ready,
            reason: 'venue_refused',
            category: reason,
            moneyAt: FundedMoneyAt.investments);
        return MoneyStepFailed(reason);
      case OrderFundingNeedsDollars():
        _stop(BitcoinFundedEnd.ready,
            stage: FundedOrderStage.ready,
            reason: 'venue_refused',
            category: 'insufficient_funds',
            moneyAt: FundedMoneyAt.investments);
        return const MoneyStepFailed('insufficient_funds');
    }
  }

  Future<MoneyStepOutcome> _phase(
          String phase, void Function(MoneyStep Function(MoneyStep)) update,
          {bool optional = false}) =>
      readinessPhaseStep(
        phase,
        update,
        optional: optional,
        phases: env.readiness?.call(venue),
        credited: _credited.future,
        placement: _placement,
        stopped: _stopped.future,
        failedCode: () => _failedCode,
      );

  Future<MoneyStepOutcome> _place(MoneyStep step,
      void Function(MoneyStep Function(MoneyStep)) update) async {
    final placed = await Future.any<bool>([
      _placement,
      _stopped.future.then((_) => false),
    ]);
    Timer.run(() {
      if (!_placeEnded.isCompleted) _placeEnded.complete();
    });
    if (placed) return const MoneyStepDone();
    return MoneyStepFailed(
        _failedCode ?? (_end != null ? 'stopped' : 'placement'));
  }
}
