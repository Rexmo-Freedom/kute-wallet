// lib/services/one_balance/order_funding.dart
//
// "The order needs more than the venue holds: move the difference from
// Dollars, wait for the credit, then place it." The slips hand the
// numbers to one controller so Predictions and Investing fund an order
// the same way and report the same stages.
//
// The controller moves the money and returns as soon as Dollars have
// left (`OrderFundingFunded`); the venue's own autofire waits for the
// credit and places the queued order. Nothing is placed from here, and
// nothing leaves Dollars without the venue funder's verified quote.
//
// Money safety: the slip checks Dollars BEFORE asking for the one
// approval, and this controller checks them again right before the
// move. A refusal of any kind before the funder's `fund` resolves means
// nothing left Dollars (`OrderFundingRefused`); the only path on which
// money moved is `OrderFundingFunded`.
//
// Analytics (journey events, exact amounts, refs only via
// `TrackingService.orderRef`): `order_funding_started`,
// `order_funding_step`, `order_funding_submitted`, then exactly one of
// `order_funding_completed` / `order_funding_failed` /
// `order_funding_abandoned` per run, reported by [OrderFundingJourney].
// The move itself keeps the venue's own `polymarket_deposit_*` events
// (purpose `conversion_leg`), so money is counted once.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/services/funding/settlement_funding_outcome.dart'
    show SettlementFundingNotStarted;
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementFundingUnknown, SettlementStopReason, SettlementStopped;
import 'package:kute/services/funding/venue_shortfall.dart';
import 'package:kute/services/one_balance/hyperliquid_venue_funder.dart'
    show hyperliquidVenueFunderProvider;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/predictions_venue_funder.dart'
    show predictionsVenueFunderProvider;
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/runtime_capabilities_service.dart'
    show CapabilityUnavailableException;
import 'package:kute/services/tracking_service.dart';

/// Where a funded order is, for the slip's progress line.
enum OrderFundingStage {
  /// Bitcoin → Dollars on the spending wallet, before the move: an order
  /// short of the whole Investments balance, funded from the person's own
  /// bitcoin under its one approval (`bitcoin_funded_order.dart`).
  bitcoin,

  /// Asking the rail what the move costs.
  quote,

  /// Dollars leaving the spending account.
  fund,

  /// Waiting for the venue to credit the move.
  credit,

  /// Placing the order.
  order,
}

/// How a funding attempt ended.
sealed class OrderFundingOutcome {
  const OrderFundingOutcome();
}

/// Dollars moved; the venue now holds enough for the order.
final class OrderFundingFunded extends OrderFundingOutcome {
  const OrderFundingFunded(this.move);

  final VenueMoveResult move;
}

/// The venue already held enough; nothing moved.
final class OrderFundingNotNeeded extends OrderFundingOutcome {
  const OrderFundingNotNeeded();
}

/// The move was refused (user declined, route unavailable, below the
/// rail's minimum). Nothing left Dollars.
final class OrderFundingRefused extends OrderFundingOutcome {
  const OrderFundingRefused(this.reason, {this.error});

  /// A fixed analytics category (`user_cancelled`, `no_route`, …).
  final String reason;

  /// What the funder threw, for the slip's copy. Null for a refusal the
  /// controller decided itself.
  final Object? error;
}

/// The rail could not tell whether the move left Dollars
/// ([SettlementFundingUnknown]): the money may be on its way. A caller
/// that asked for it ([OrderFundingController.fundAndQueue]'s
/// `keepUnconfirmed`) keeps the order queued and keeps watching the
/// venue, so a retry never funds the same order twice; any landed cash
/// stays at the venue. A [OrderFundingRefused] for callers that do not
/// tell the two apart.
final class OrderFundingUnconfirmed extends OrderFundingRefused {
  const OrderFundingUnconfirmed({super.error}) : super('settlement_unknown');
}

/// Dollars plus the venue together cannot cover the order.
final class OrderFundingNeedsDollars extends OrderFundingOutcome {
  const OrderFundingNeedsDollars(this.shortfallUsd);

  /// What the user has to add to Dollars first.
  final double shortfallUsd;
}

/// What a funded order would move, worked out from the venue's estimate
/// before anything is approved: the slip shows the fee and names the
/// amount on its button, and the approval binds [fundUsd].
class OrderFundingPlan {
  const OrderFundingPlan({
    required this.fundUsd,
    required this.arrivingUsd,
    required this.rule,
    required this.minUsd,
  });

  /// What leaves Dollars: [ShortfallRules.topUp], never under the rail's
  /// minimum.
  final double fundUsd;

  /// What the estimate says lands at the venue for [fundUsd].
  final double arrivingUsd;

  /// `prefill_rule` of the top-up ([ShortfallRules.topUp]).
  final String rule;

  /// The rail's minimum at the time of the estimate.
  final double minUsd;

  /// The move's cost: what leaves less what arrives, to the cent.
  double get feeUsd => _ceilCents(fundUsd - arrivingUsd).clamp(0, fundUsd);

  /// A plan without a live estimate: [ShortfallRules.fallbackRouteFee]
  /// stands in for the route's share until the real one is read.
  factory OrderFundingPlan.fallback({
    required double orderUsd,
    required double requiredUsd,
    required double readyUsd,
    double minUsd = ShortfallRules.minTopUpUsd,
  }) =>
      OrderFundingPlan.from(
        orderUsd: orderUsd,
        requiredUsd: requiredUsd,
        readyUsd: readyUsd,
        routeFee: ShortfallRules.fallbackRouteFee,
        minUsd: minUsd,
      );

  /// The plan for a route keeping [routeFee] of what is sent (the Kute
  /// fee already inside it, as a venue funder's estimate folds it).
  factory OrderFundingPlan.from({
    required double orderUsd,
    required double requiredUsd,
    required double readyUsd,
    required double routeFee,
    double minUsd = ShortfallRules.minTopUpUsd,
  }) {
    final top = ShortfallRules.topUp(
        orderUsd: orderUsd,
        requiredUsd: requiredUsd,
        readyUsd: readyUsd,
        routeFee: routeFee);
    final floor = minUsd.isFinite && minUsd > 0 ? minUsd : 0.0;
    final fund = top.usd < floor ? _ceilCents(floor) : top.usd;
    final keep = routeFee.isFinite && routeFee > 0 && routeFee < 1
        ? 1 - routeFee
        : 1.0;
    return OrderFundingPlan(
      fundUsd: fund,
      arrivingUsd: fund * keep,
      rule: top.rule,
      minUsd: floor,
    );
  }

  /// The plan from the venue's live estimate for the order's own amount:
  /// the route's share is read off what the estimate says arrives, then
  /// the top-up is grossed up by it. Falls back to the fallback share on
  /// an unusable estimate; a failed read throws.
  static Future<OrderFundingPlan> read(
    VenueFunder funder, {
    required double orderUsd,
    required double requiredUsd,
    required double readyUsd,
  }) async {
    final base = orderUsd.isFinite && orderUsd > 0
        ? orderUsd
        : ShortfallRules.minTopUpUsd;
    final estimate = await funder.estimate(base);
    final fee = ShortfallRules.routeFeeFrom(
            sentUsd: base, arrivingUsd: estimate.arrivingUsd) ??
        ShortfallRules.fallbackRouteFee;
    return OrderFundingPlan.from(
      orderUsd: orderUsd,
      requiredUsd: requiredUsd,
      readyUsd: readyUsd,
      routeFee: fee,
      minUsd: estimate.minUsd,
    );
  }

  static double _ceilCents(double usd) =>
      ((usd * 100) - 1e-9).ceilToDouble() / 100;

  @override
  String toString() => 'OrderFundingPlan(fund: $fundUsd, '
      'arriving: $arrivingUsd, rule: $rule, min: $minUsd)';
}

/// What the funding engine decided for one order (founder rule, October
/// 2026). See [OrderFundingEngine.decide].
enum OrderFundingRoute {
  /// The venue's own cash covers the order: place it directly.
  direct,

  /// The venue is short but the person's Investments (Dollars plus the
  /// other venue's spendable cash) cover the move: it is planned inside
  /// the same Confirm and approval, then the order is placed. No extra
  /// step, no "Add $X".
  move,

  /// Even everything in Investments is short of what the order needs:
  /// the existing "Add $X to Investments" door, for [OrderFundingDecision
  /// .addUsd].
  addFunds,
}

/// The engine's answer: the route, and the figures behind it.
@immutable
class OrderFundingDecision {
  const OrderFundingDecision({
    required this.route,
    required this.needUsd,
    required this.haveHereUsd,
    required this.shortfallUsd,
    required this.targetUsd,
    required this.addUsd,
  });

  final OrderFundingRoute route;

  /// What the venue must hold for the order: stake or margin, every fee,
  /// the price tolerance and the venue minimum.
  final double needUsd;

  /// The venue's spendable cash (reserved cash already taken off).
  final double haveHereUsd;

  /// [needUsd] − [haveHereUsd], to the cent; zero when covered.
  final double shortfallUsd;

  /// What the move must LAND at the venue: the shortfall plus the safety
  /// buffer, never under [OrderFundingEngine.floorUsd] or the route's
  /// minimum. Zero on [OrderFundingRoute.direct]. What it sends on top of
  /// that is the route's cost ([HyperliquidVenueFunder.sizeFunding] for
  /// Investing); the extra simply stays at the venue as its cash.
  final double targetUsd;

  /// On [OrderFundingRoute.addFunds], what is missing from Investments as
  /// a whole, to the cent; zero otherwise.
  final double addUsd;

  @override
  String toString() => 'OrderFundingDecision(${route.name}, need: $needUsd, '
      'here: $haveHereUsd, short: $shortfallUsd, target: $targetUsd, '
      'add: $addUsd)';
}

/// The shared funding engine for a venue order (Predictions bets and
/// Investing orders alike). Pure.
///
///   need       = stake/notional + all fees + price tolerance + the venue
///                minimum, worked out by the slip;
///   have here  = the venue's spendable cash, minus what is reserved;
///   shortfall  = need − have here.
///
/// No shortfall: place directly. A shortfall that the person's
/// Investments cover (Dollars plus the other venue's spendable cash, less
/// the move's cost): move it silently inside the same Confirm, then place
/// — the move lands max(shortfall + buffer, route minimum, $1), rounded up
/// to the cent, so the order surely works and the extra stays at the
/// venue. Only when everything in Investments is short does the slip show
/// the existing "Add $X to Investments".
abstract final class OrderFundingEngine {
  /// The share of the shortfall added as a safety buffer for fee and
  /// price drift between the quote and the order.
  static const double bufferShare = 0.02;

  /// The smallest buffer, in dollars.
  static const double bufferMinUsd = 0.25;

  /// No move lands less than this.
  static const double floorUsd = 1.0;

  /// What a move for [shortfallUsd] must land: the shortfall plus the
  /// larger of [bufferShare] of it and [bufferMinUsd], never under
  /// [routeMinimumUsd] or [floorUsd], rounded UP to the cent. Zero for no
  /// shortfall.
  static double targetUsd({
    required double shortfallUsd,
    double routeMinimumUsd = 0,
  }) {
    if (!shortfallUsd.isFinite || shortfallUsd <= 1e-6) return 0;
    final buffer = math.max(shortfallUsd * bufferShare, bufferMinUsd);
    final min = routeMinimumUsd.isFinite && routeMinimumUsd > 0
        ? routeMinimumUsd
        : 0.0;
    return OrderFundingPlan._ceilCents(
        math.max(math.max(shortfallUsd + buffer, min), floorUsd));
  }

  /// The decision for an order needing [needUsd] at a venue holding
  /// [haveHereUsd] spendable, with [investmentsUsd] spendable elsewhere
  /// in Investments (Dollars plus the other venue's spendable cash) and
  /// [moveCostUsd] the route's cost for the move (what is sent on top of
  /// what lands).
  static OrderFundingDecision decide({
    required double needUsd,
    required double haveHereUsd,
    required double investmentsUsd,
    double moveCostUsd = 0,
    double routeMinimumUsd = 0,
  }) {
    double clean(double v) => v.isFinite && v > 0 ? v : 0;
    final need = clean(needUsd);
    final here = clean(haveHereUsd);
    final shortfall =
        ShortfallRules.shortfallUsd(requiredUsd: need, readyUsd: here);
    if (shortfall <= 0) {
      return OrderFundingDecision(
        route: OrderFundingRoute.direct,
        needUsd: need,
        haveHereUsd: here,
        shortfallUsd: 0,
        targetUsd: 0,
        addUsd: 0,
      );
    }
    final target =
        targetUsd(shortfallUsd: shortfall, routeMinimumUsd: routeMinimumUsd);
    final send = target + clean(moveCostUsd);
    final elsewhere = clean(investmentsUsd);
    if (elsewhere + 1e-9 >= send) {
      return OrderFundingDecision(
        route: OrderFundingRoute.move,
        needUsd: need,
        haveHereUsd: here,
        shortfallUsd: shortfall,
        targetUsd: target,
        addUsd: 0,
      );
    }
    return OrderFundingDecision(
      route: OrderFundingRoute.addFunds,
      needUsd: need,
      haveHereUsd: here,
      shortfallUsd: shortfall,
      targetUsd: target,
      addUsd: OrderFundingPlan._ceilCents(send - elsewhere),
    );
  }
}

/// A venue funder that can say where its move is while it runs (quote
/// verified, Dollars leaving), so the slip's line and the latency figures
/// are exact. A plain [VenueFunder] reports only around the whole move.
abstract interface class StagedVenueFunder implements VenueFunder {
  Future<VenueMoveResult> fundStaged({
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'order_funding',
    void Function(OrderFundingStage stage)? onStage,
  });
}

/// Analytics value for a venue.
String orderFundingVenueCode(OneBalanceVenue venue) => switch (venue) {
      OneBalanceVenue.predictions => 'polymarket',
      OneBalanceVenue.investing => 'hyperliquid',
    };

/// Funds an order's shortfall from Dollars and queues the order behind
/// the credit.
class OrderFundingController {
  const OrderFundingController({
    required VenueFunder Function(OneBalanceVenue venue) funderFor,
    required double Function() dollarsUsd,
  })  : _funderFor = funderFor,
        _dollarsUsd = dollarsUsd;

  final VenueFunder Function(OneBalanceVenue venue) _funderFor;
  final double Function() _dollarsUsd;

  /// This controller reading Dollars through [dollarsUsd]: an order funded
  /// from bitcoin passes the fresh balance its dollars landed in, before
  /// the shown balance caught up. The check stays the guard.
  OrderFundingController withDollars(double Function() dollarsUsd) =>
      OrderFundingController(funderFor: _funderFor, dollarsUsd: dollarsUsd);

  /// [orderUsd] is the order's size, [requiredUsd] what the venue must
  /// hold for it (size plus any margin or reservation), [readyUsd] what
  /// the venue holds now. The difference is the move. [onStage] reports
  /// progress for the slip.
  ///
  /// [fundUsd] is the amount the slip already worked out and had approved
  /// ([OrderFundingPlan]); without it the controller reads the venue's
  /// estimate itself. [entrySource] is the surface that queued the order,
  /// for the journey's first event.
  ///
  /// [keepUnconfirmed]: a move the rail could not confirm either way
  /// answers [OrderFundingUnconfirmed] (the run stays open at the credit)
  /// instead of a refusal, for a caller that keeps its order queued and
  /// watched (Investing). Off, it is a refusal as before.
  ///
  /// [continueJourney]: the journey was started earlier for this order
  /// (an order funded from bitcoin starts it at the tap, before its
  /// Bitcoin → Dollars leg), so this move carries on that run instead of
  /// opening a second one.
  ///
  /// Resolves the venue's funder before anything else: a venue without
  /// one (Investing until its funder is bound) throws at once.
  Future<OrderFundingOutcome> fundAndQueue({
    required OneBalanceVenue venue,
    required double orderUsd,
    required double requiredUsd,
    required double readyUsd,
    required MoveAuthorization auth,
    void Function(OrderFundingStage)? onStage,
    double? fundUsd,
    String? entrySource,
    String purpose = 'order_funding',
    bool keepUnconfirmed = false,
    bool continueJourney = false,
  }) {
    final funder = _funderFor(venue);
    return _run(
      funder,
      venue: venue,
      orderUsd: orderUsd,
      requiredUsd: requiredUsd,
      readyUsd: readyUsd,
      auth: auth,
      onStage: onStage,
      fundUsd: fundUsd,
      entrySource: entrySource,
      purpose: purpose,
      keepUnconfirmed: keepUnconfirmed,
      continueJourney: continueJourney,
    );
  }

  Future<OrderFundingOutcome> _run(
    VenueFunder funder, {
    required OneBalanceVenue venue,
    required double orderUsd,
    required double requiredUsd,
    required double readyUsd,
    required MoveAuthorization auth,
    void Function(OrderFundingStage)? onStage,
    double? fundUsd,
    String? entrySource,
    required String purpose,
    bool keepUnconfirmed = false,
    bool continueJourney = false,
  }) async {
    final shortfall =
        ShortfallRules.shortfallUsd(requiredUsd: requiredUsd, readyUsd: readyUsd);
    if (shortfall <= 0) return const OrderFundingNotNeeded();
    final journey = OrderFundingJourney.instance;
    final dollars = _dollarsUsd();
    if (!continueJourney || !journey.isRunning(venue)) {
      journey.start(venue,
          orderUsd: orderUsd,
          fundUsd: fundUsd ?? 0,
          readyUsd: readyUsd,
          dollarsUsd: dollars,
          entrySource: entrySource);
    }

    // Quote: the amount to move, from the venue's estimate unless the slip
    // already had it approved.
    onStage?.call(OrderFundingStage.quote);
    journey.step(venue, OrderFundingStage.quote);
    double fund;
    if (fundUsd != null && fundUsd.isFinite && fundUsd > 0) {
      fund = fundUsd;
    } else {
      try {
        fund = (await OrderFundingPlan.read(funder,
                orderUsd: orderUsd,
                requiredUsd: requiredUsd,
                readyUsd: readyUsd))
            .fundUsd;
      } catch (e) {
        final reason = _refusalReason(e);
        journey.failed(venue, OrderFundingStage.quote, reason);
        return OrderFundingRefused(reason, error: e);
      }
      journey.setFundUsd(venue, fund);
    }
    final minimum = await _minimum(funder);
    if (fund < minimum) fund = minimum;

    // Dollars are checked again right here, the last read before any
    // approval is used: a balance that fell since the slip looked sends
    // the person to the Dollars door, with nothing moved.
    if (!dollars.isFinite || dollars + 1e-9 < fund) {
      journey.failed(venue, OrderFundingStage.quote, 'insufficient_funds');
      return OrderFundingNeedsDollars(
          OrderFundingPlan._ceilCents(fund - (dollars.isFinite ? dollars : 0)));
    }

    onStage?.call(OrderFundingStage.fund);
    journey.step(venue, OrderFundingStage.fund);
    final VenueMoveResult move;
    try {
      move = funder is StagedVenueFunder
          ? await funder.fundStaged(
              usd: fund,
              auth: auth,
              purpose: purpose,
              onStage: (stage) {
                onStage?.call(stage);
                journey.step(venue, stage);
              })
          : await funder.fund(usd: fund, auth: auth, purpose: purpose);
    } catch (e) {
      if (keepUnconfirmed && e is SettlementFundingUnknown) {
        // Maybe sent: the run stays open at the credit, which the venue's
        // autofire closes (placed, or the credit wait running out).
        onStage?.call(OrderFundingStage.credit);
        journey.step(venue, OrderFundingStage.credit);
        return OrderFundingUnconfirmed(error: e);
      }
      final reason = _refusalReason(e);
      journey.failed(venue, OrderFundingStage.fund, reason);
      return OrderFundingRefused(reason, error: e);
    }

    // Dollars have left. The credit is the venue autofire's to wait for.
    onStage?.call(OrderFundingStage.credit);
    journey.funded(venue, move, orderUsd: orderUsd);
    return OrderFundingFunded(move);
  }

  Future<double> _minimum(VenueFunder funder) async {
    try {
      final min = await funder.minimumUsd();
      return min.isFinite && min > 0 ? min : ShortfallRules.minTopUpUsd;
    } catch (_) {
      return ShortfallRules.minTopUpUsd;
    }
  }

  /// The fixed analytics category for a refusal. Every one of these means
  /// nothing left Dollars, except [SettlementFundingUnknown], where the
  /// runner could not tell and the sweeper brings any landed cash home.
  static String _refusalReason(Object e) {
    if (e is SettlementStopped) {
      return switch (e.reason) {
        SettlementStopReason.declined => 'user_cancelled',
        SettlementStopReason.routeUnavailable => 'no_route',
        SettlementStopReason.blockedPending => 'settlement_blocked_pending',
        SettlementStopReason.quoteExpired => 'expired',
        SettlementStopReason.quoteReplaced => 'quote_rejected',
      };
    }
    if (e is RouteUnavailable) return 'no_route';
    if (e is CapabilityUnavailableException) return 'capability';
    if (e is SettlementFundingUnknown) return 'settlement';
    if (e is SettlementFundingNotStarted) return 'settlement';
    return TrackingService.errorCategory(e);
  }
}

/// Investing's funder: `HyperliquidVenueFunder` over whatever rail
/// `hyperliquidMoveRailProvider` binds.
final investingVenueFunderProvider = Provider<VenueFunder>(
    (ref) => ref.watch(hyperliquidVenueFunderProvider));

final orderFundingControllerProvider = Provider<OrderFundingController>(
  (ref) => OrderFundingController(
    funderFor: (venue) => switch (venue) {
      OneBalanceVenue.predictions => ref.read(predictionsVenueFunderProvider),
      OneBalanceVenue.investing => ref.read(investingVenueFunderProvider),
    },
    dollarsUsd: () {
      try {
        return ref.read(usdBalanceProvider);
      } catch (_) {
        return 0;
      }
    },
  ),
);

// ── Journey ────────────────────────────────────────────────────────

class _FundingRun {
  _FundingRun({
    required this.startedAt,
    required this.orderUsd,
    required this.fundUsd,
  });

  final DateTime startedAt;
  final double orderUsd;
  double fundUsd;
  OrderFundingStage stage = OrderFundingStage.quote;

  /// `bitcoin` for an order funded from the person's own bitcoin.
  String? fundingSource;

  /// The Bitcoin leg's sats left, and its dollars landed.
  DateTime? bitcoinSentAt;
  DateTime? bitcoinLandedAt;
  DateTime? quotedAt;
  DateTime? fundedAt;
  DateTime? creditedAt;
  double? arrivingUsd;
}

/// Follows one funded order per venue from the slip's tap to its one
/// outcome, for analytics. It moves nothing: the controller reports the
/// move, the venue's autofire the credit and the order. Exactly one of
/// completed / failed / abandoned per started run; a second start on the
/// same venue abandons the first.
class OrderFundingJourney {
  OrderFundingJourney._();

  static OrderFundingJourney instance = OrderFundingJourney._();

  /// Test seam: the clock every `ms_*` figure is measured on.
  static DateTime Function() clock = DateTime.now;

  final Map<OneBalanceVenue, _FundingRun> _runs = {};

  /// Whether a run is open for [venue].
  bool isRunning(OneBalanceVenue venue) => _runs.containsKey(venue);

  @visibleForTesting
  static void reset() => instance = OrderFundingJourney._();

  void start(
    OneBalanceVenue venue, {
    required double orderUsd,
    required double fundUsd,
    required double readyUsd,
    required double dollarsUsd,
    String? entrySource,
    String? fundingSource,
    Map<String, Object> extra = const {},
  }) {
    if (_runs.containsKey(venue)) abandoned(venue);
    _runs[venue] =
        _FundingRun(startedAt: clock(), orderUsd: orderUsd, fundUsd: fundUsd)
          ..fundingSource = fundingSource;
    TrackingService.track('order_funding_started', params: {
      'venue': orderFundingVenueCode(venue),
      'order_usd': orderUsd,
      'fund_usd': fundUsd,
      'ready_usd': readyUsd,
      'dollars_usd': dollarsUsd,
      'entry_source': entrySource ?? 'unknown',
      'wallet_kind': 'hot',
      if (fundingSource != null) 'funding_source': fundingSource,
      ...extra,
    });
  }

  /// The run's `funding_source`, when it has one.
  String? fundingSourceOf(OneBalanceVenue venue) =>
      _runs[venue]?.fundingSource;

  /// An order funded from bitcoin: its Bitcoin leg's sats left now.
  void bitcoinSent(OneBalanceVenue venue) {
    final run = _runs[venue];
    if (run == null) return;
    run.bitcoinSentAt ??= clock();
    step(venue, OrderFundingStage.bitcoin);
  }

  /// An order funded from bitcoin: its dollars landed now. Returns the
  /// milliseconds from the sats leaving to the dollars landing.
  int? bitcoinLanded(OneBalanceVenue venue) {
    final run = _runs[venue];
    if (run == null) return null;
    run.bitcoinLandedAt ??= clock();
    final sent = run.bitcoinSentAt;
    return sent == null
        ? null
        : run.bitcoinLandedAt!.difference(sent).inMilliseconds;
  }

  void setFundUsd(OneBalanceVenue venue, double fundUsd) {
    _runs[venue]?.fundUsd = fundUsd;
  }

  void step(OneBalanceVenue venue, OrderFundingStage stage) {
    final run = _runs[venue];
    if (run == null) return;
    run.stage = stage;
    if (stage == OrderFundingStage.fund) run.quotedAt ??= clock();
    TrackingService.track('order_funding_step', params: {
      'venue': orderFundingVenueCode(venue),
      'step': stage.name,
      if (run.fundingSource != null) 'funding_source': run.fundingSource!,
    });
  }

  /// Dollars have left for [venue].
  void funded(OneBalanceVenue venue, VenueMoveResult move,
      {required double orderUsd}) {
    final run = _runs[venue];
    if (run == null) return;
    run.fundedAt = clock();
    run.quotedAt ??= run.fundedAt;
    run.stage = OrderFundingStage.credit;
    run.fundUsd = move.sentUsd;
    run.arrivingUsd = move.arrivingUsdEstimate;
    void submitted(String? orderId) {
      TrackingService.track('order_funding_submitted', params: {
        'venue': orderFundingVenueCode(venue),
        'fund_usd': move.sentUsd,
        'amount_usd': orderUsd,
        'quote_id': move.quoteId,
        if (orderId != null && orderId.isNotEmpty) 'order_id': orderId,
      });
    }

    final orderId = move.orderId;
    final registration = move.registration;
    if (orderId != null || registration == null) {
      submitted(orderId);
    } else {
      // Reported once the background registration names the order (or
      // gives up: the quote id alone still joins the row).
      unawaited(registration.then(submitted, onError: (_) => submitted(null)));
    }
  }

  /// The venue credited the move: the order is about to be placed.
  void credited(OneBalanceVenue venue) {
    final run = _runs[venue];
    if (run == null) return;
    run.creditedAt ??= clock();
    step(venue, OrderFundingStage.order);
  }

  void completed(OneBalanceVenue venue,
      {required bool resized, double? amountUsd}) {
    final run = _runs.remove(venue);
    if (run == null) return;
    final now = clock();
    // An order funded from bitcoin quotes its move once the dollars
    // landed: its quote time starts there, the Bitcoin leg has its own.
    final quoteFrom = run.bitcoinLandedAt ?? run.startedAt;
    final quoted = run.quotedAt ?? quoteFrom;
    final funded = run.fundedAt ?? quoted;
    final credited = run.creditedAt ?? funded;
    TrackingService.track('order_funding_completed', params: {
      'venue': orderFundingVenueCode(venue),
      'fund_usd': run.fundUsd,
      'amount_usd': amountUsd ?? run.orderUsd,
      'ms_quote': quoted.difference(quoteFrom).inMilliseconds,
      'ms_fund': funded.difference(quoted).inMilliseconds,
      'ms_credit': credited.difference(funded).inMilliseconds,
      'ms_order': now.difference(credited).inMilliseconds,
      'duration_ms': now.difference(run.startedAt).inMilliseconds,
      'resized': resized,
      if (run.fundingSource != null) 'funding_source': run.fundingSource!,
      ...bitcoinTimings(
        sentAt: run.bitcoinSentAt,
        landedAt: run.bitcoinLandedAt,
        creditedAt: run.creditedAt,
        placedAt: now,
      ),
    });
  }

  void failed(OneBalanceVenue venue, OrderFundingStage stage, String category) {
    final run = _runs.remove(venue);
    if (run == null) return;
    TrackingService.track('order_funding_failed', params: {
      'venue': orderFundingVenueCode(venue),
      'stage': stage.name,
      'error_category': TrackingService.errorCategory(category),
      'duration_ms': clock().difference(run.startedAt).inMilliseconds,
      if (run.fundingSource != null) 'funding_source': run.fundingSource!,
    });
  }

  void abandoned(OneBalanceVenue venue, {OrderFundingStage? stage}) {
    final run = _runs.remove(venue);
    if (run == null) return;
    TrackingService.track('order_funding_abandoned', params: {
      'venue': orderFundingVenueCode(venue),
      'stage': (stage ?? run.stage).name,
      if (run.fundingSource != null) 'funding_source': run.fundingSource!,
    });
  }

  /// The three stage timings of an order funded from bitcoin, in exact
  /// milliseconds: the sats leaving to the dollars landing
  /// (`ms_bitcoin_landed`), the dollars landing to the venue crediting the
  /// move (`ms_venue_credited`), the credit to the order placed
  /// (`ms_placed`). Only the figures whose two ends are known.
  static Map<String, Object> bitcoinTimings({
    DateTime? sentAt,
    DateTime? landedAt,
    DateTime? creditedAt,
    DateTime? placedAt,
  }) {
    int? between(DateTime? a, DateTime? b) => a == null || b == null
        ? null
        : b.difference(a).inMilliseconds.clamp(0, 1 << 31).toInt();
    final landed = between(sentAt, landedAt);
    final credited = between(landedAt, creditedAt);
    final placed = between(creditedAt, placedAt);
    return {
      if (landed != null) 'ms_bitcoin_landed': landed,
      if (credited != null) 'ms_venue_credited': credited,
      if (placed != null) 'ms_placed': placed,
    };
  }
}
