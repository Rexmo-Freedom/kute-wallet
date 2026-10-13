// lib/services/one_balance/venue_cash_source.dart
//
// "Dollars don't cover it: take the rest from venue cash." Venue cash
// stays at the venues (Predictions on Polymarket, Investing on
// Hyperliquid) and the sweeper brings it home only after it has been idle
// for a day, so an action that needs more dollars than Dollars hold uses
// Dollars first and pulls ONLY the shortfall from the venues.
//
//  * [planDollarsShortfall] is the pure planner: Dollars first, then the
//    shortfall from the venues fastest first (Predictions → Dollars rides
//    Orchestra and lands in about a minute; Investing → Dollars falls to
//    Circle CCTP and takes minutes), each pull at least the route's
//    minimum, never more than the venue's free cash, grossed up so what
//    lands in Dollars covers what is missing.
//  * [VenueCashSource] is one venue's free cash and its door home:
//    [PolymarketCashSource] over the Predictions funder's sweep,
//    [HyperliquidCashSource] over the Investing move rail.
//  * [VenueCashPuller] plans, runs every venue leg AT ONCE (in parallel),
//    reports each leg's outcome (a failed leg leaves its money on its
//    venue, still available) and can wait, bounded, for Dollars to reach
//    the amount the action needs.
//
// Money safety: every pull is a move HOME, to the wallet's own Spark
// address, under [SweepAuthorization.automatic], which both rails accept
// only for that recipient and only while the session is unlocked. So the
// action's own single approval (the send, the purchase, the order) stays
// the only prompt. Investing is never pulled from while it holds a cross
// position or a resting perp order: only the rail's sendable cash, and
// only when nothing on the account can be leaning on it. Predictions
// pulls only cash not reserved by an open BUY order.
//
// Routing today: every leg comes home to Dollars (spark:USDB) and the
// action continues from Dollars.
// TODO(one-balance): direct legs. Orchestra offers polygon:USDC(.e) →
// spark:BTC and → hypercore:USDC, and arbitrum:USDC (the CCTP exit) →
// spark:BTC / polygon:USDC(.e); the backend accepts the Investing
// withdrawal standing address for spark:USDB only until the
// `cctp-any-destination` change lands. Each direct leg needs its own
// settlement flow, quote-guard recipient kind and reconciler wiring.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/hyperliquid_market.dart'
    show HlOpenOrder, HlPerpPosition;
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidTradingModelProvider;
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/funding/owned_address_resolver.dart'
    show ProviderReader;
import 'package:kute/services/hyperliquid/cctp_withdrawal.dart'
    show kCctpCoreFeeReserve;
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/predictions_venue_funder.dart'
    show predictionsVenueFunderProvider;
import 'package:kute/services/one_balance/route_minimums.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/one_balance/venue_sweeper.dart'
    show SweepableVenueFunder;
import 'package:kute/services/tracking_service.dart';

// ─── Actions ───────────────────────────────────────────────────────

/// The `for` values the pull events carry: what the pulled cash is for.
abstract final class VenueCashFor {
  static const String send = 'send';
  static const String buyBitcoin = 'buy_bitcoin';
  static const String predictions = 'predictions';
  static const String investing = 'investing';
  static const String withdraw = 'withdraw';
}

/// The `purpose` every pull is recorded with by the venue rails (their
/// withdraw funnels and quote tags).
const String kVenueCashPullPurpose = 'cash_pull';

// ─── Costs and timing ──────────────────────────────────────────────

/// What a pull of X keeps on the way home: `X * share + fixedUsd`.
typedef VenuePullCost = ({double share, double fixedUsd});

/// The allowance a pull is grossed up by when the rail offers no
/// estimate of its own. Conservative on purpose: whatever is not spent
/// lands in Dollars too.
///
/// Predictions → Dollars is one Orchestra order (observed near 1%, the
/// quote guard refuses above 4%). Investing → Dollars is a CCTP burn: the
/// forwarding fee comes off the amount, then the Orchestra order.
const Map<OneBalanceVenue, VenuePullCost> kVenuePullCost = {
  OneBalanceVenue.predictions: (share: 0.02, fixedUsd: 0.0),
  OneBalanceVenue.investing: (share: 0.02, fixedUsd: 0.30),
};

/// How long a pull takes to land in Dollars, by venue.
const Map<OneBalanceVenue, Duration> kVenuePullEta = {
  OneBalanceVenue.predictions: Duration(minutes: 1),
  OneBalanceVenue.investing: Duration(minutes: 5),
};

/// The longest an action waits on a pull before it stops honestly.
const Duration kVenueCashMaxWait = Duration(minutes: 8);

/// The wait an action gives a plan: its ETA plus two minutes of slack,
/// never more than [kVenueCashMaxWait].
Duration venueCashWaitFor(Duration eta) {
  final wait = eta + const Duration(minutes: 2);
  return wait > kVenueCashMaxWait ? kVenueCashMaxWait : wait;
}

/// Venues fastest and cheapest first: Predictions, then Investing.
const List<OneBalanceVenue> kVenuePullOrder = [
  OneBalanceVenue.predictions,
  OneBalanceVenue.investing,
];

double _ceilCents(double usd) {
  if (!usd.isFinite || usd <= 0) return 0;
  // A hair under the cent (float noise) is that cent, not the next one.
  return ((usd * 100) - 1e-6).ceil() / 100;
}

double _floorCents(double usd) {
  if (!usd.isFinite || usd <= 0) return 0;
  return ((usd * 100) + 1e-6).floor() / 100;
}

/// What lands in Dollars for a pull of [pullUsd] under [cost].
double venuePullArrives(double pullUsd, VenuePullCost cost) =>
    math.max(0, pullUsd * (1 - cost.share) - cost.fixedUsd);

/// The pull that lands at least [arriveUsd] under [cost], to the cent up.
double venuePullFor(double arriveUsd, VenuePullCost cost) =>
    _ceilCents((arriveUsd + cost.fixedUsd) / (1 - cost.share));

// ─── The plan ──────────────────────────────────────────────────────

/// One venue's side of the plan, as [planDollarsShortfall] reads it.
typedef VenueCashCandidate = ({
  OneBalanceVenue venue,
  double availableUsd,
  Duration eta,
  double minimumUsd,
});

/// One leg: [usd] leaves [venue], about [arrivingUsd] lands in Dollars.
class VenueCashPull {
  const VenueCashPull({
    required this.venue,
    required this.usd,
    required this.arrivingUsd,
    required this.eta,
  });

  final OneBalanceVenue venue;

  /// What leaves the venue, in dollars, to the cent.
  final double usd;

  /// What the plan expects to land in Dollars for it.
  final double arrivingUsd;

  final Duration eta;

  @override
  bool operator ==(Object other) =>
      other is VenueCashPull &&
      other.venue == venue &&
      other.usd == usd &&
      other.arrivingUsd == arrivingUsd &&
      other.eta == eta;

  @override
  int get hashCode => Object.hash(venue, usd, arrivingUsd, eta);

  @override
  String toString() => 'VenueCashPull(${venue.name}, $usd → $arrivingUsd)';
}

/// What [planDollarsShortfall] decided.
class VenueCashPlan {
  const VenueCashPlan({
    required this.neededUsd,
    required this.dollarsUsd,
    required this.pulls,
    required this.covers,
    required this.eta,
    required this.uncoveredUsd,
  });

  /// The action's amount, to the cent up.
  final double neededUsd;

  /// What Dollars hold toward it (never more than [neededUsd]).
  final double dollarsUsd;

  /// The venue legs, in the order they were chosen.
  final List<VenueCashPull> pulls;

  /// Dollars plus what the legs land reach [neededUsd].
  final bool covers;

  /// When the slowest leg should have landed (zero with no legs).
  final Duration eta;

  /// What is still missing after every leg, to the cent up (0 if
  /// [covers]).
  final double uncoveredUsd;

  /// Dollars alone cover the action.
  bool get dollarsOnly => pulls.isEmpty && covers;

  /// What leaves the venues in all.
  double get pulledUsd => pulls.fold(0.0, (sum, p) => sum + p.usd);

  /// What the legs are expected to land in Dollars in all.
  double get arrivingUsd => pulls.fold(0.0, (sum, p) => sum + p.arrivingUsd);

  /// The pull from [venue], or null.
  VenueCashPull? pullFrom(OneBalanceVenue venue) {
    for (final p in pulls) {
      if (p.venue == venue) return p;
    }
    return null;
  }

  @override
  String toString() => 'VenueCashPlan(needed: $neededUsd, dollars: '
      '$dollarsUsd, pulls: $pulls, covers: $covers, eta: $eta, '
      'uncovered: $uncoveredUsd)';
}

/// Dollars first, then the shortfall from [sources] fastest first.
///
/// Each venue leg is grossed up by [costOf] (default [kVenuePullCost]) so
/// what lands covers its share, is at least the venue's minimum (plus the
/// route's fixed cost, so the net still clears the floor) and never more
/// than the venue's available cash; a venue whose cash is below that is
/// skipped. A leg that cannot take its whole share takes what it has, to
/// the cent down, and the next venue covers the rest. [exclude] leaves a
/// venue out (the venue an order is being funded into).
///
/// Order: by ETA, ties in [kVenuePullOrder] (Predictions, then
/// Investing). Pure.
VenueCashPlan planDollarsShortfall({
  required double neededUsd,
  required double dollarsUsd,
  required List<VenueCashCandidate> sources,
  OneBalanceVenue? exclude,
  VenuePullCost Function(OneBalanceVenue venue)? costOf,
}) {
  final needed = _ceilCents(neededUsd);
  final dollars = dollarsUsd.isFinite && dollarsUsd > 0 ? dollarsUsd : 0.0;
  if (dollars + 0.000001 >= needed) {
    return VenueCashPlan(
      neededUsd: needed,
      dollarsUsd: needed,
      pulls: const [],
      covers: true,
      eta: Duration.zero,
      uncoveredUsd: 0,
    );
  }
  final cost = costOf ??
      (OneBalanceVenue v) => kVenuePullCost[v] ?? (share: 0.02, fixedUsd: 0.30);
  final ordered = [
    for (final s in sources)
      if (s.venue != exclude) s,
  ]..sort((a, b) {
      final byEta = a.eta.compareTo(b.eta);
      if (byEta != 0) return byEta;
      return kVenuePullOrder
          .indexOf(a.venue)
          .compareTo(kVenuePullOrder.indexOf(b.venue));
    });

  var remaining = needed - dollars;
  final pulls = <VenueCashPull>[];
  final used = <OneBalanceVenue>{};
  for (final source in ordered) {
    if (remaining <= 0.000001) break;
    if (used.contains(source.venue)) continue;
    final c = cost(source.venue);
    final available = _floorCents(source.availableUsd);
    final minimum = source.minimumUsd.isFinite && source.minimumUsd > 0
        ? _ceilCents(source.minimumUsd + c.fixedUsd)
        : _ceilCents(c.fixedUsd);
    if (available <= 0 || available < minimum) continue;
    var pull = math.max(venuePullFor(remaining, c), minimum);
    if (pull > available) pull = available;
    final arrives = venuePullArrives(pull, c);
    if (arrives <= 0) continue;
    used.add(source.venue);
    pulls.add(VenueCashPull(
      venue: source.venue,
      usd: pull,
      arrivingUsd: arrives,
      eta: source.eta,
    ));
    remaining -= arrives;
  }
  final covers = remaining <= 0.000001;
  var eta = Duration.zero;
  for (final p in pulls) {
    if (p.eta > eta) eta = p.eta;
  }
  return VenueCashPlan(
    neededUsd: needed,
    dollarsUsd: dollars,
    pulls: List.unmodifiable(pulls),
    covers: covers,
    eta: eta,
    uncoveredUsd: covers ? 0 : _ceilCents(remaining),
  );
}

/// How far Dollars plus venue cash reach: the most an action can ask for
/// with every venue pulled in full (net of the pull cost). Pure.
double venueCashReachUsd({
  required double dollarsUsd,
  required List<VenueCashCandidate> sources,
  OneBalanceVenue? exclude,
  VenuePullCost Function(OneBalanceVenue venue)? costOf,
}) {
  final cost = costOf ??
      (OneBalanceVenue v) => kVenuePullCost[v] ?? (share: 0.02, fixedUsd: 0.30);
  var reach = dollarsUsd.isFinite && dollarsUsd > 0 ? dollarsUsd : 0.0;
  final seen = <OneBalanceVenue>{};
  for (final s in sources) {
    if (s.venue == exclude || !seen.add(s.venue)) continue;
    final c = cost(s.venue);
    final available = _floorCents(s.availableUsd);
    final minimum = _ceilCents(
        (s.minimumUsd.isFinite && s.minimumUsd > 0 ? s.minimumUsd : 0) +
            c.fixedUsd);
    if (available <= 0 || available < minimum) continue;
    reach += venuePullArrives(available, c);
  }
  return _floorCents(reach);
}

// ─── Sources ───────────────────────────────────────────────────────

/// One venue's free cash and its door home to Dollars.
abstract interface class VenueCashSource {
  OneBalanceVenue get venue;

  /// Cash the venue can send home right now without touching anything
  /// an open position or a resting order leans on. 0 when unknown.
  Future<double> availableUsd();

  /// About how long a pull takes to land in Dollars.
  Duration get estimatedArrival;

  /// Sends [usd] home to Dollars under [SweepAuthorization.automatic].
  /// Throws (nothing moved) when the rail refuses.
  Future<VenueMoveResult> pull(double usd, {required String purpose});
}

/// Predictions cash: what [SweepableVenueFunder.idleUsd] calls idle (the
/// cash balance less what open BUY orders reserve; 0 when the orders
/// cannot be read), brought home by its sweep.
class PolymarketCashSource implements VenueCashSource {
  PolymarketCashSource(this._funder, {bool Function()? isLive})
      : _isLive = isLive;

  final SweepableVenueFunder _funder;

  /// Whether the Predictions account is already up (the sweeper keeps it
  /// warm in the app). A read never starts it: an amount screen asking
  /// how far venue cash reaches must not boot the venue.
  final bool Function()? _isLive;

  @override
  OneBalanceVenue get venue => OneBalanceVenue.predictions;

  @override
  Duration get estimatedArrival => kVenuePullEta[OneBalanceVenue.predictions]!;

  @override
  Future<double> availableUsd() async {
    if (_isLive != null && !_isLive()) return 0;
    try {
      final usd = await _funder.idleUsd();
      return usd.isFinite && usd > 0 ? usd : 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) =>
      _funder.sweepToDollars(
        usd: usd,
        auth: SweepAuthorization.automatic,
        purpose: purpose,
      );
}

/// What the Investing account has open, for [HyperliquidCashSource].
typedef HlPullGuardState = ({
  List<HlPerpPosition> positions,
  List<HlOpenOrder> openOrders,
});

/// Whether [order] is a perpetuals order (spot orders name `@123` or a
/// `BASE/QUOTE` pair).
bool hlOrderIsPerp(HlOpenOrder order) =>
    !order.coin.startsWith('@') && !order.coin.contains('/');

/// Whether the Investing account may be pulled from: no open cross
/// position and no resting perp order. Pure.
bool hlPullAllowed(HlPullGuardState state) {
  for (final p in state.positions) {
    if (p.szi != 0 && p.isCross) return false;
  }
  for (final o in state.openOrders) {
    if (hlOrderIsPerp(o)) return false;
  }
  return true;
}

/// Investing cash: the rail's sendable figure (withdrawable perpetuals
/// cash plus unheld spot USDC, never isolated margin or cross
/// collateral), less the HyperCore reserve the CCTP burn keeps back, and
/// nothing at all while a cross position or a resting perp order could
/// lean on it. An unreadable account is 0.
class HyperliquidCashSource implements VenueCashSource {
  HyperliquidCashSource(this._rail, {required this.readGuard});

  final HyperliquidMoveRail _rail;

  /// The account's open positions and resting orders, or null when they
  /// cannot be read.
  final Future<HlPullGuardState?> Function() readGuard;

  @override
  OneBalanceVenue get venue => OneBalanceVenue.investing;

  @override
  Duration get estimatedArrival => kVenuePullEta[OneBalanceVenue.investing]!;

  @override
  Future<double> availableUsd() async {
    try {
      final guard = await readGuard();
      if (guard == null || !hlPullAllowed(guard)) return 0;
      final sendable = await _rail.withdrawableUsd();
      if (!sendable.isFinite || sendable <= 0) return 0;
      final usd = sendable - kCctpCoreFeeReserve.toDouble() / 1e8;
      return usd > 0 ? usd : 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) async {
    // Read again at the moment of the pull: an order placed since the
    // plan turns the account off.
    final guard = await readGuard();
    if (guard == null || !hlPullAllowed(guard)) {
      throw const RouteUnavailable('investing_cash_in_use');
    }
    return _rail.withdrawToDollars(
      usd: usd,
      auth: SweepAuthorization.automatic,
      purpose: purpose,
    );
  }
}

/// The live guard read for the spending wallet's Investing account: the
/// portfolio snapshot (every perp dex) and its resting orders.
Future<HlPullGuardState?> readHyperliquidPullGuard(ProviderReader read) async {
  try {
    final address = await read(hyperliquidAddressProvider.future);
    if (address == null || address.isEmpty) return null;
    final model = read(hyperliquidTradingModelProvider);
    final snapshot = await model
        .getPortfolioSnapshot(address)
        .timeout(const Duration(seconds: 10));
    final orders = await model
        .getOpenOrders(address, dexes: snapshot.activeDexes)
        .timeout(const Duration(seconds: 10));
    return (positions: snapshot.positions, openOrders: orders);
  } catch (_) {
    return null;
  }
}

// ─── The puller ────────────────────────────────────────────────────

/// One venue leg's outcome.
class VenueCashLegOutcome {
  const VenueCashLegOutcome({
    required this.pull,
    this.result,
    this.error,
  });

  final VenueCashPull pull;

  /// The rail's answer when the leg was sent.
  final VenueMoveResult? result;

  /// Why the leg did not go; its money stays on its venue.
  final Object? error;

  OneBalanceVenue get venue => pull.venue;
  bool get ok => result != null;

  /// What left the venue (0 for a failed leg).
  double get sentUsd => result?.sentUsd ?? 0;
}

/// What [VenueCashPuller.pullShortfall] did.
class VenueCashPullOutcome {
  const VenueCashPullOutcome({
    required this.plan,
    required this.legs,
    required this.dollarsCover,
    required this.eta,
  });

  final VenueCashPlan plan;

  /// Each venue leg, in plan order.
  final List<VenueCashLegOutcome> legs;

  /// Dollars held the needed amount when the call returned (after the
  /// wait, when one was asked for).
  final bool dollarsCover;

  /// The plan's ETA: how long the slowest leg should take.
  final Duration eta;

  /// What left the venues on legs that went.
  double get pulledUsd => legs.fold(0.0, (sum, l) => sum + l.sentUsd);

  /// What successful legs are expected to land.
  double get arrivingUsd => legs.fold(
      0.0,
      (sum, l) =>
          sum +
          (l.ok
              ? (l.result!.arrivingUsdEstimate > 0
                  ? l.result!.arrivingUsdEstimate
                  : l.pull.arrivingUsd)
              : 0));

  /// Legs that did not go.
  List<VenueCashLegOutcome> get failedLegs => [
        for (final l in legs)
          if (!l.ok) l
      ];

  /// Some money is on its way home.
  bool get anyPulled => legs.any((l) => l.ok);

  /// Nothing to pull: Dollars already covered the amount.
  bool get dollarsOnly => legs.isEmpty && plan.covers;
}

/// Plans, pulls in parallel and (optionally) waits for Dollars.
///
/// Calls are serialized: a second call waits for the first to finish
/// and plans again against what is left, so the same venue cash is never
/// pulled twice. Pulls already sent but not yet seen landing count
/// toward Dollars for [pendingTtl], so a retry right after a stop waits
/// on the money already coming instead of pulling more.
class VenueCashPuller {
  VenueCashPuller({
    required List<VenueCashSource> sources,
    required double Function() readDollars,
    required Future<double> Function(OneBalanceVenue venue) minimumUsd,
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleep,
    void Function()? nudge,
    this.pollEvery = const Duration(seconds: 3),
    this.nudgeEvery = const Duration(seconds: 20),
    this.pendingTtl = const Duration(minutes: 20),
  })  : _sources = sources,
        _readDollars = readDollars,
        _minimumUsd = minimumUsd,
        _clock = clock ?? DateTime.now,
        _sleep = sleep ?? ((d) => Future<void>.delayed(d)),
        _nudge = nudge;

  final List<VenueCashSource> _sources;
  final double Function() _readDollars;
  final Future<double> Function(OneBalanceVenue venue) _minimumUsd;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _sleep;
  final void Function()? _nudge;

  /// How often the wait reads Dollars.
  final Duration pollEvery;

  /// How often the wait asks the wallet to sync.
  final Duration nudgeEvery;

  /// How long a sent pull counts as on its way.
  final Duration pendingTtl;

  final List<({double usd, DateTime at})> _pending = [];
  Future<void> _tail = Future<void>.value();

  /// Sent pulls still counted as on their way to Dollars.
  double get pendingUsd {
    final now = _clock();
    _pending.removeWhere((p) => now.difference(p.at) >= pendingTtl);
    return _pending.fold(0.0, (sum, p) => sum + p.usd);
  }

  /// Every source's free cash and minimum, read in parallel.
  Future<List<VenueCashCandidate>> candidates(
      {OneBalanceVenue? exclude}) async {
    final reads = await Future.wait([
      for (final s in _sources)
        if (s.venue != exclude)
          () async {
            final available = await s.availableUsd();
            double minimum;
            try {
              minimum = await _minimumUsd(s.venue);
            } catch (_) {
              minimum = venueFloorUsd(s.venue);
            }
            return (
              venue: s.venue,
              availableUsd: available,
              eta: s.estimatedArrival,
              minimumUsd: minimum,
            );
          }(),
    ]);
    return reads;
  }

  /// The plan for [neededUsd] against Dollars (plus pulls on their way)
  /// and the venues' free cash right now. Moves nothing.
  Future<VenueCashPlan> plan(
      {required double neededUsd, OneBalanceVenue? exclude}) async {
    final dollars = _readDollars();
    final pending = pendingUsd;
    if (dollars + pending + 0.000001 >= _ceilCents(neededUsd)) {
      return planDollarsShortfall(
          neededUsd: neededUsd,
          dollarsUsd: dollars + pending,
          sources: const []);
    }
    return planDollarsShortfall(
      neededUsd: neededUsd,
      dollarsUsd: dollars + pending,
      sources: await candidates(exclude: exclude),
      exclude: exclude,
    );
  }

  /// The most an action can ask for: Dollars plus every venue's free
  /// cash net of the pull cost.
  Future<double> reachUsd({OneBalanceVenue? exclude}) async =>
      venueCashReachUsd(
        dollarsUsd: _readDollars() + pendingUsd,
        sources: await candidates(exclude: exclude),
        exclude: exclude,
      );

  /// Uses Dollars first and pulls only the shortfall from venue cash.
  ///
  /// Every leg starts at once; one failing does not stop the others (its
  /// money stays on its venue). [onPlanned] hears the plan before any leg
  /// starts, for the progress lines. The call then reads Dollars every
  /// [pollEvery] until they reach [neededUsd] or the wait runs out; the
  /// outcome says which. [waitFor] null waits [venueCashWaitFor] the
  /// plan's ETA; [Duration.zero] returns once the legs are sent. A plan
  /// that does not cover the amount pulls nothing, and a failed leg
  /// skips the wait.
  Future<VenueCashPullOutcome> pullShortfall({
    required double neededUsd,
    required String forAction,
    OneBalanceVenue? exclude,
    Duration? waitFor,
    void Function(VenueCashPlan plan)? onPlanned,
  }) {
    final run = _tail.then((_) => _pullShortfall(
          neededUsd: neededUsd,
          forAction: forAction,
          exclude: exclude,
          waitFor: waitFor,
          onPlanned: onPlanned,
        ));
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<VenueCashPullOutcome> _pullShortfall({
    required double neededUsd,
    required String forAction,
    OneBalanceVenue? exclude,
    Duration? waitFor,
    void Function(VenueCashPlan plan)? onPlanned,
  }) async {
    final plan = await this.plan(neededUsd: neededUsd, exclude: exclude);
    if (!plan.covers) {
      return VenueCashPullOutcome(
          plan: plan, legs: const [], dollarsCover: false, eta: plan.eta);
    }
    onPlanned?.call(plan);
    final legs = <VenueCashLegOutcome>[];
    if (plan.pulls.isNotEmpty) {
      TrackingService.track('multi_source_move_started', params: {
        'legs': plan.pulls.length + (plan.dollarsUsd > 0 ? 1 : 0),
        'total_usd': plan.neededUsd,
        'destination': forAction,
      });
      legs.addAll(await Future.wait([
        for (final p in plan.pulls) _runLeg(p, forAction),
      ]));
    }
    final failed = legs.where((l) => !l.ok).length;
    var cover = _readDollars() + 0.000001 >= plan.neededUsd;
    final wait = waitFor ?? venueCashWaitFor(plan.eta);
    if (!cover && failed == 0 && wait > Duration.zero) {
      cover = await _waitForDollars(plan.neededUsd, wait);
    }
    if (cover) _pending.clear();
    if (plan.pulls.isNotEmpty) {
      final delivered = plan.dollarsUsd +
          legs.fold<double>(
              0,
              (sum, l) =>
                  sum +
                  (l.ok
                      ? (l.result!.arrivingUsdEstimate > 0
                          ? l.result!.arrivingUsdEstimate
                          : l.pull.arrivingUsd)
                      : 0));
      TrackingService.track('multi_source_move_finished', params: {
        'delivered_usd': _cents(delivered),
        'failed_legs': failed,
        'destination': forAction,
        'landed': cover,
      });
    }
    return VenueCashPullOutcome(
        plan: plan,
        legs: List.unmodifiable(legs),
        dollarsCover: cover,
        eta: plan.eta);
  }

  Future<VenueCashLegOutcome> _runLeg(VenueCashPull p, String forAction) async {
    VenueCashSource? source;
    for (final s in _sources) {
      if (s.venue == p.venue) source = s;
    }
    if (source == null) {
      return VenueCashLegOutcome(
          pull: p, error: const RouteUnavailable('no_source'));
    }
    try {
      final result = await source.pull(p.usd, purpose: kVenueCashPullPurpose);
      final arriving = result.arrivingUsdEstimate > 0
          ? result.arrivingUsdEstimate
          : p.arrivingUsd;
      _pending.add((usd: arriving, at: _clock()));
      final amount = _cents(result.sentUsd > 0 ? result.sentUsd : p.usd);
      switch (p.venue) {
        case OneBalanceVenue.investing:
          TrackingService.track('investing_cash_pulled',
              params: {'amount_usd': amount, 'for': forAction});
        case OneBalanceVenue.predictions:
          TrackingService.track('predictions_cash_pulled',
              params: {'amount_usd': amount, 'for': forAction});
      }
      return VenueCashLegOutcome(pull: p, result: result);
    } catch (e) {
      return VenueCashLegOutcome(pull: p, error: e);
    }
  }

  Future<bool> _waitForDollars(double neededUsd, Duration waitFor) async {
    final start = _clock();
    var lastNudge = start;
    while (true) {
      if (_readDollars() + 0.000001 >= neededUsd) return true;
      final now = _clock();
      if (now.difference(start) >= waitFor) return false;
      if (now.difference(lastNudge) >= nudgeEvery) {
        lastNudge = now;
        try {
          _nudge?.call();
        } catch (_) {}
      }
      await _sleep(pollEvery);
    }
  }

  static double _cents(double usd) => (usd * 100).round() / 100;
}

// ─── Riverpod ──────────────────────────────────────────────────────

/// Both venues' cash, Predictions first.
final venueCashSourcesProvider = Provider<List<VenueCashSource>>((ref) => [
      PolymarketCashSource(ref.read(predictionsVenueFunderProvider),
          isLive: () => ref.exists(polymarketTradingProvider)),
      HyperliquidCashSource(
        ref.read(hyperliquidMoveRailProvider),
        readGuard: () => readHyperliquidPullGuard(ref.read),
      ),
    ]);

/// The app's puller. Not autoDispose: it remembers pulls on their way.
final venueCashPullerProvider = Provider<VenueCashPuller>((ref) {
  final minimums = ref.read(routeMinimumsProvider);
  return VenueCashPuller(
    sources: ref.read(venueCashSourcesProvider),
    readDollars: () => ref.read(usdBalanceProvider),
    minimumUsd: minimums.minimumUsd,
    nudge: () => BackgroundSyncService().syncNow(),
  );
});

/// How far Dollars plus venue cash reach right now, for an amount
/// screen's ceiling. Refreshed when Dollars change; 0-venue fallback on
/// any failure is Dollars alone.
final venueCashReachProvider = FutureProvider.autoDispose<double>((ref) async {
  final dollars = ref.watch(usdBalanceProvider);
  try {
    return await ref.read(venueCashPullerProvider).reachUsd();
  } catch (_) {
    return dollars;
  }
});

/// [venueCashReachProvider] for an order at [exclude]: Dollars plus the
/// OTHER venues' cash (the target venue's own cash is already counted as
/// what it holds). What the order slips' funding engine
/// (`OrderFundingEngine.decide`) reads as "the rest of Investments".
final venueCashReachExcludingProvider =
    FutureProvider.autoDispose.family<double, OneBalanceVenue>(
        (ref, exclude) async {
  final dollars = ref.watch(usdBalanceProvider);
  try {
    return await ref.read(venueCashPullerProvider).reachUsd(exclude: exclude);
  } catch (_) {
    return dollars;
  }
});
