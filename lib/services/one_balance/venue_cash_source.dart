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
// Money safety: a pull HOME to the wallet's own Dollars (spark:USDB on
// its own Spark address) runs under [SweepAuthorization.automatic], which
// both rails accept only for that recipient and only while the session
// is unlocked: no tap. That automatic authorization is ONLY for Dollars.
// A leg whose destination is anything else (Bitcoin, the other venue)
// runs only AFTER and UNDER the action's own single approval (the Buy,
// the order, the bet: [ApprovedLegAuthorization]), whose grant binds the
// legs' destination, a cap per venue and the total (`DirectLegGrants`):
// validate, plan the legs ([VenueCashPuller.plan] /
// [VenueCashPuller.directLegLimit]), ONE approval, then the legs, then
// the action. [VenueCashPuller.pullShortfall] refuses such a destination
// without the approval, before anything moves. Investing is never pulled
// from while it holds a cross position or a resting perp order: only the
// rail's sendable cash, and only when nothing on the account can be
// leaning on it. Predictions pulls only cash not reserved by an open BUY
// order.
//
// Routing: an action names where its money is going
// ([VenueCashDestination]). Dollars (a send): every leg comes home to
// Dollars (spark:USDB). Anywhere else, a leg goes STRAIGHT there when its
// venue's rail offers the route and the action's approval covers it,
// always to one of the wallet's own accounts:
//
//  * Investing → Bitcoin: native HyperCore → Spark BTC first; a confirmed
//    unsupported pair alone opens CCTP to the own Spark address.
//    Investing → Predictions the same way: native HyperCore → Polygon
//    USDC.e to the own Predictions account first; a confirmed unsupported
//    pair alone opens CCTP to its own Polymarket standing instruction,
//    with its own label and fee rule (`HyperCoreMoveRail.withdrawDirect`).
//  * Predictions → Bitcoin or Investing: the Predictions cash-out quoted
//    by Orchestra to the destination (polygon:USDC.e → spark:BTC or →
//    hypercore:USDC to the own Investing account)
//    (`PredictionsVenueFunder.sweepTo`).
//
// A refusal before anything moved (the standing terms, the route, the
// quote, a shut gate, the Polymarket wallet not linked yet) brings that
// leg home to Dollars instead (`via_dollars`) and the action takes it on
// from there; a transient refusal is asked once more first, and only a
// definitive one keeps the route off for a while ([DirectRouteRefusals]). Every action with legs is one move
// (multi_source_move.dart): one Activity row, the legs inside it, and
// Retry for a failed remainder.

export 'package:kute/services/one_balance/venue_funder.dart'
    show VenueCashDestination, DirectRouteRefused;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/auth_grant.dart'
    show AuthGrant, AuthGrants, AuthGrantException;
import 'package:kute/helpers/venue_intents.dart'
    show DirectLegGrants, IntentUnits;
import 'package:kute/models/hyperliquid_market.dart'
    show HlOpenOrder, HlPerpPosition;
import 'package:kute/models/orchestra_route_limits.dart'
    show RouteQuoteError, RouteQuoteErrorCode;
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidTradingModelProvider;
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/providers/settings_provider.dart' show settingsProvider;
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/funding/settlement_funding_outcome.dart'
    show SettlementFundingNotStarted, SettlementFundingRefused;
import 'package:kute/services/funding/owned_address_resolver.dart'
    show ProviderReader;
import 'package:kute/services/hyperliquid/cctp_withdrawal.dart'
    show kCctpCoreFeeReserve;
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/investments_spendable.dart'
    show venueCashSnapshotProvider;
import 'package:kute/services/one_balance/money_steps.dart'
    show MoneyStepGraph, MoneyStepStatus;
import 'package:kute/services/one_balance/move_steps.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/predictions_venue_funder.dart'
    show predictionsVenueFunderProvider;
import 'package:kute/services/one_balance/route_minimums.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/one_balance/venue_sweeper.dart'
    show SweepableVenueFunder;
import 'package:kute/services/orchestra/orchestra_quote_gate.dart'
    show OrchestraQuoteFailure;
import 'package:kute/services/orchestra/standing_deposit_store.dart'
    show InvestingWithdrawalDestination;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementFundingUnknown;

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

/// A source whose cash can also go straight to the action's destination
/// (Bitcoin, the other venue) under the action's approval
/// ([ApprovedLegAuthorization]), only ever to one of the wallet's own
/// accounts.
abstract interface class DirectVenueCashSource {
  /// Whether this venue's rail offers a direct route to [destination].
  bool canPullTo(VenueCashDestination destination);

  /// Sends [usd] straight to [destination] under [auth]. Throws
  /// [DirectRouteRefused] when the route was refused before anything
  /// moved (the puller then brings the leg home to Dollars instead);
  /// anything else may have moved and fails the leg.
  Future<VenueMoveResult> pullTo(VenueCashDestination destination, double usd,
      {required String purpose, required MoveAuthorization auth});
}

/// A leg to a destination other than Dollars was asked for without the
/// action's approval: nothing moved.
class VenueLegApprovalRequired implements Exception {
  const VenueLegApprovalRequired();

  @override
  String toString() => 'VenueLegApprovalRequired';
}

/// Direct routes refused lately, per venue and destination: a definitive
/// refusal (the route is not offered, its gate is shut: [sticky]) is not
/// asked again for [ttl]; those legs go through Dollars. A refusal that
/// says nothing about the route itself (a read or the network failed, an
/// address or the destination's terms could not be had this time, an
/// earlier CCTP move still on its way, an amount under the minimum) never
/// keeps the route off: the next action asks again, and a [retryable]
/// one is asked once more at once before the leg goes through Dollars.
abstract final class DirectRouteRefusals {
  /// How long a definitive refusal keeps the route off.
  static const Duration ttl = Duration(minutes: 15);

  /// The clock refusals are stamped and read with (a test seam).
  static DateTime Function() clock = DateTime.now;

  static final Map<String, DateTime> _refused = {};

  static String _key(OneBalanceVenue venue, VenueCashDestination d) =>
      '${venue.name}>${d.name}';

  /// Whether [reason] (a [DirectRouteRefused] reason) says the route
  /// itself is off: no direct route, a shut gate, a pause, a route the
  /// provider does not offer.
  static bool sticky(String? reason) {
    final r = (reason ?? '').toLowerCase();
    return r == 'no_direct_route' ||
        r == 'cctp_paused' ||
        r == 'cctp_capability' ||
        r.contains('route_unavailable') ||
        r.contains('routeunavailable') ||
        r.contains('capability');
  }

  /// Whether [reason] is worth asking once more at once: not the route
  /// itself ([sticky]), not the person's own stop, not an amount or an
  /// earlier move that a second ask cannot change.
  static bool retryable(String? reason) {
    final r = (reason ?? '').toLowerCase();
    if (sticky(r)) return false;
    return !(r == 'user_cancelled' ||
        r.startsWith('settlement_') ||
        // The wallet's own guard refused the route's terms (an account
        // pair, a recipient, a fee cap): a second ask gets the same answer.
        r.startsWith('wallet_guard') ||
        r == 'cctp_in_flight' ||
        r == 'cctp_below_minimum' ||
        r.contains('minimum'));
  }

  static bool isRefused(OneBalanceVenue venue, VenueCashDestination d) {
    final key = _key(venue, d);
    final at = _refused[key];
    if (at == null) return false;
    if (clock().difference(at) >= ttl) {
      _refused.remove(key);
      return false;
    }
    return true;
  }

  static void refuse(OneBalanceVenue venue, VenueCashDestination d) =>
      _refused[_key(venue, d)] = clock();

  /// The direct Bitcoin route into [venue] (`spark:BTC` straight to the
  /// venue's own deposit, an order's Bitcoin leg): same rules, its own key.
  static String _bitcoinKey(OneBalanceVenue venue) => 'bitcoin>${venue.name}';

  static bool isBitcoinRefused(OneBalanceVenue venue) {
    final key = _bitcoinKey(venue);
    final at = _refused[key];
    if (at == null) return false;
    if (clock().difference(at) >= ttl) {
      _refused.remove(key);
      return false;
    }
    return true;
  }

  static void refuseBitcoin(OneBalanceVenue venue) =>
      _refused[_bitcoinKey(venue)] = clock();

  @visibleForTesting
  static void reset() {
    _refused.clear();
    clock = DateTime.now;
  }
}

/// The venue a destination is, if it is one: its own cash is never
/// pulled for it.
OneBalanceVenue? venueOfDestination(VenueCashDestination destination) =>
    switch (destination) {
      VenueCashDestination.predictions => OneBalanceVenue.predictions,
      VenueCashDestination.investing => OneBalanceVenue.investing,
      _ => null,
    };

/// Predictions cash: what [SweepableVenueFunder.idleUsd] calls idle (the
/// cash balance less what open BUY orders reserve; 0 when the orders
/// cannot be read), brought home by its sweep, or straight to Bitcoin or
/// Investing by its direct cash-out.
class PolymarketCashSource implements VenueCashSource, DirectVenueCashSource {
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

  @override
  bool canPullTo(VenueCashDestination destination) =>
      _funder is DirectSweepableVenueFunder &&
      (destination == VenueCashDestination.bitcoin ||
          destination == VenueCashDestination.investing);

  @override
  Future<VenueMoveResult> pullTo(VenueCashDestination destination, double usd,
      {required String purpose, required MoveAuthorization auth}) {
    final funder = _funder;
    if (funder is! DirectSweepableVenueFunder || !canPullTo(destination)) {
      throw const DirectRouteRefused('no_direct_route');
    }
    return (funder as DirectSweepableVenueFunder).sweepTo(
      destination: destination,
      usd: usd,
      auth: auth,
      purpose: purpose,
    );
  }
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

/// Investing's direct door: native-first Bitcoin or Predictions,
/// always to its own destination (`HyperCoreMoveRail.withdrawDirect`).
typedef HlDirectWithdraw = Future<VenueMoveResult> Function(
    InvestingWithdrawalDestination destination,
    double usd,
    String purpose,
    MoveAuthorization auth);

/// Investing cash: the rail's sendable figure (withdrawable perpetuals
/// cash plus unheld spot USDC, never isolated margin or cross
/// collateral), less the HyperCore reserve the CCTP burn keeps back, and
/// nothing at all while a cross position or a resting perp order could
/// lean on it. An unreadable account is 0. With [direct], it also goes
/// straight to Bitcoin or Predictions (native first, CCTP on a refused
/// route).
class HyperliquidCashSource implements VenueCashSource, DirectVenueCashSource {
  HyperliquidCashSource(this._rail, {required this.readGuard, this.direct});

  final HyperliquidMoveRail _rail;

  /// The account's open positions and resting orders, or null when they
  /// cannot be read.
  final Future<HlPullGuardState?> Function() readGuard;

  /// The move straight to its own final destination, or null for none.
  final HlDirectWithdraw? direct;

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

  Future<void> _ensureFree() async {
    // Read again at the moment of the pull: an order placed since the
    // plan turns the account off.
    final guard = await readGuard();
    if (guard == null || !hlPullAllowed(guard)) {
      throw const RouteUnavailable('investing_cash_in_use');
    }
  }

  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) async {
    await _ensureFree();
    return _rail.withdrawToDollars(
      usd: usd,
      auth: SweepAuthorization.automatic,
      purpose: purpose,
    );
  }

  static InvestingWithdrawalDestination? _cctpDestination(
          VenueCashDestination d) =>
      switch (d) {
        VenueCashDestination.bitcoin => InvestingWithdrawalDestination.bitcoin,
        VenueCashDestination.predictions =>
          InvestingWithdrawalDestination.predictions,
        _ => null,
      };

  @override
  bool canPullTo(VenueCashDestination destination) =>
      direct != null && _cctpDestination(destination) != null;

  @override
  Future<VenueMoveResult> pullTo(VenueCashDestination destination, double usd,
      {required String purpose, required MoveAuthorization auth}) async {
    final to = _cctpDestination(destination);
    final send = direct;
    if (to == null || send == null) {
      throw const DirectRouteRefused('no_direct_route');
    }
    await _ensureFree();
    return send(to, usd, purpose, auth);
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
    this.route = VenueCashRoute.viaDollars,
    this.landsIn = VenueCashDestination.dollars,
    this.fellBackReason,
  });

  final VenueCashPull pull;

  /// Why a leg that was to go straight to the destination came home to
  /// Dollars instead (the rail's fixed refusal code); null when it went
  /// the way it was planned.
  final String? fellBackReason;

  /// The rail's answer when the leg was sent.
  final VenueMoveResult? result;

  /// Why the leg did not go; its money stays on its venue.
  final Object? error;

  /// [VenueCashRoute.direct] or [VenueCashRoute.viaDollars].
  final String route;

  /// Where the leg's money lands: the action's destination for a direct
  /// leg, Dollars otherwise.
  final VenueCashDestination landsIn;

  OneBalanceVenue get venue => pull.venue;
  bool get ok => result != null;
  bool get direct => route == VenueCashRoute.direct;

  /// What left the venue (0 for a failed leg).
  double get sentUsd => result?.sentUsd ?? 0;

  /// What the leg is expected to land (0 for a failed leg).
  double get arrivingUsd => ok
      ? (result!.arrivingUsdEstimate > 0
          ? result!.arrivingUsdEstimate
          : pull.arrivingUsd)
      : 0;
}

/// What [VenueCashPuller.pullShortfall] did.
class VenueCashPullOutcome {
  const VenueCashPullOutcome({
    required this.plan,
    required this.legs,
    required this.dollarsCover,
    required this.eta,
    this.destination = VenueCashDestination.dollars,
    this.moveId,
    this.onwardUsd,
    this.alreadyDeliveredUsd = 0,
  });

  final VenueCashPlan plan;

  /// Each venue leg, in plan order.
  final List<VenueCashLegOutcome> legs;

  /// Dollars held what the action takes from them ([onwardUsd]) when the
  /// call returned (after the wait, when one was asked for).
  final bool dollarsCover;

  /// The plan's ETA: how long the slowest leg should take.
  final Duration eta;

  /// Where the action's money is going.
  final VenueCashDestination destination;

  /// The move's record (`MultiSourceMoveStore`), when any leg ran: the
  /// id a Retry and the action's own step are linked by.
  final String? moveId;

  /// What the action still takes from Dollars: the whole amount for a
  /// Dollars destination, otherwise what the direct legs do not deliver.
  final double? onwardUsd;

  /// What earlier attempts of the same move already sent straight to the
  /// destination (a Retry never pulls it again).
  final double alreadyDeliveredUsd;

  /// What left the venues on legs that went.
  double get pulledUsd => legs.fold(0.0, (sum, l) => sum + l.sentUsd);

  /// What successful legs are expected to land.
  double get arrivingUsd => legs.fold(0.0, (sum, l) => sum + l.arrivingUsd);

  /// What legs that went straight to the destination will land there.
  double get directArrivingUsd => legs
      .where((l) => l.ok && l.direct)
      .fold(0.0, (sum, l) => sum + l.arrivingUsd);

  /// What the action takes from Dollars, [plan]'s amount when no figure
  /// was worked out.
  double get dollarsNeededUsd => onwardUsd ?? plan.neededUsd;

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

/// Whether a leg's refusal says its amount is under the route's minimum:
/// the quote's `amount_too_small`, or a rail's own floor
/// (`RouteUnavailable('…below_minimum')`, the CCTP fallback's). Pure.
bool venueLegBelowMinimum(Object error) => switch (error) {
      RouteQuoteError(:final code) =>
        code == RouteQuoteErrorCode.amountTooSmall,
      OrchestraQuoteFailure(:final routeError) =>
        routeError?.code == RouteQuoteErrorCode.amountTooSmall,
      RouteUnavailable(:final reason) =>
        reason?.endsWith('below_minimum') ?? false,
      _ => false,
    };

/// The smallest amount an action sends on from Dollars to a destination
/// other than Dollars (the Orchestra floor plus a margin): Dollars below
/// it are left alone and the venue legs cover the whole amount when they
/// can, so no leg is left too small to go on.
const double kVenueCashOnwardMinimumUsd = 1.0;

/// Plans, pulls in parallel and (optionally) waits for Dollars.
///
/// Calls are serialized: a second call waits for the first to finish
/// and plans again against what is left, so the same venue cash is never
/// pulled twice. Pulls already sent home but not yet seen landing count
/// toward Dollars for [pendingTtl], so a retry right after a stop waits
/// on the money already coming instead of pulling more; legs that went
/// straight to the destination count through the move's record.
class VenueCashPuller {
  VenueCashPuller({
    required List<VenueCashSource> sources,
    required double Function() readDollars,
    required Future<double> Function(OneBalanceVenue venue) minimumUsd,
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleep,
    void Function()? nudge,
    String? Function()? walletId,
    double? Function(OneBalanceVenue venue)? cachedAvailableUsd,
    this.onCashMoved,
    this.onAmountTooSmall,
    this.pollEvery = const Duration(seconds: 3),
    this.nudgeEvery = const Duration(seconds: 20),
    this.pendingTtl = const Duration(minutes: 20),
  })  : _sources = sources,
        _readDollars = readDollars,
        _minimumUsd = minimumUsd,
        _clock = clock ?? DateTime.now,
        _sleep = sleep ?? ((d) => Future<void>.delayed(d)),
        _nudge = nudge,
        _walletId = walletId,
        _cachedAvailableUsd = cachedAvailableUsd;

  final List<VenueCashSource> _sources;
  final double Function() _readDollars;
  final Future<double> Function(OneBalanceVenue venue) _minimumUsd;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _sleep;
  final void Function()? _nudge;
  final String? Function()? _walletId;
  final double? Function(OneBalanceVenue venue)? _cachedAvailableUsd;

  /// Successful sends only, with the source read used before the leg.
  /// A listener never changes the money move's outcome.
  final void Function(VenueCashLegOutcome leg, double? availableBefore)?
      onCashMoved;

  /// A leg home to Dollars of [usd] was refused as under the route's
  /// minimum (the quote's `amount_too_small`, the CCTP fallback's floor):
  /// the real minimum is above it, so the next plan raises that venue's
  /// leg to it or leaves the venue out and the others cover the amount
  /// ([RouteMinimums.noteAmountTooSmall]). Never changes the leg's outcome.
  final void Function(OneBalanceVenue venue, double usd)? onAmountTooSmall;
  final Map<OneBalanceVenue, double> _lastAvailable = {};

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
    for (final read in reads) {
      _lastAvailable[read.venue] = read.availableUsd;
    }
    return reads;
  }

  /// The plan for [neededUsd] against Dollars (plus pulls on their way)
  /// and the venues' free cash right now. Moves nothing.
  ///
  /// For a [destination] other than Dollars, Dollars short of
  /// [kVenueCashOnwardMinimumUsd] are left alone when the venues can cover
  /// the whole amount, so the onward step is never too small to go.
  /// [useDollars] false plans the venues alone (a Retry of a remainder).
  Future<VenueCashPlan> plan({
    required double neededUsd,
    OneBalanceVenue? exclude,
    VenueCashDestination destination = VenueCashDestination.dollars,
    bool useDollars = true,
  }) async {
    final dollars = useDollars ? _readDollars() + pendingUsd : 0.0;
    if (dollars + 0.000001 >= _ceilCents(neededUsd)) {
      return planDollarsShortfall(
          neededUsd: neededUsd, dollarsUsd: dollars, sources: const []);
    }
    final sources = await candidates(exclude: exclude);
    if (destination != VenueCashDestination.dollars &&
        dollars > 0 &&
        dollars < kVenueCashOnwardMinimumUsd) {
      final venuesOnly = planDollarsShortfall(
          neededUsd: neededUsd,
          dollarsUsd: 0,
          sources: sources,
          exclude: exclude);
      if (venuesOnly.covers) return venuesOnly;
    }
    return planDollarsShortfall(
      neededUsd: neededUsd,
      dollarsUsd: dollars,
      sources: sources,
      exclude: exclude,
    );
  }

  /// What the action's one approval binds for [plan]'s legs that would go
  /// straight to [destination] (`VenueLimit.directLegs`): a cap per venue
  /// (the leg's amount) and the total. Null for a Dollars destination or
  /// when no leg can go straight there (they all come home to Dollars
  /// under the automatic authorization). Moves nothing.
  Map<String, Object?>? directLegLimit(
      VenueCashPlan plan, VenueCashDestination destination) {
    if (destination == VenueCashDestination.dollars) return null;
    final caps = <String, double>{};
    for (final p in plan.pulls) {
      final source = _sourceFor(p.venue);
      if (source is DirectVenueCashSource &&
          (source as DirectVenueCashSource).canPullTo(destination) &&
          !DirectRouteRefusals.isRefused(p.venue, destination)) {
        caps[p.venue.name] = p.usd;
      }
    }
    return DirectLegGrants.limit(destination: destination.code, capsUsd: caps);
  }

  /// The venues of [plan] whose legs would go straight to [destination]
  /// under an approval that binds them ([directLegLimit]): the rest come
  /// home to Dollars. Empty for a Dollars destination. Moves nothing.
  Set<OneBalanceVenue> directVenues(
      VenueCashPlan plan, VenueCashDestination destination) {
    final legs = directLegLimit(plan, destination)?['legs'];
    if (legs is! Map) return const {};
    return {
      for (final p in plan.pulls)
        if (legs.containsKey(p.venue.name)) p.venue,
    };
  }

  /// The plan a Retry of [moveId] would run: the failed remainder from
  /// the venues alone, for the approval a Retry to a destination other
  /// than Dollars asks first. Null when there is nothing to retry.
  Future<VenueCashPlan?> planRetry(String moveId) async {
    final move = MultiSourceMoveStore.get(moveId);
    if (move == null || !move.partial) return null;
    if (move.isParallelPurchase) return _parallelRetryPlan(move);
    return plan(
      neededUsd: move.remainingUsd,
      exclude: venueOfDestination(move.destination),
      destination: move.destination,
      useDollars: false,
    );
  }

  VenueCashPlan? _parallelRetryPlan(MultiSourceMove move) {
    final pulls = [
      for (final leg in move.provenUnsentLegs)
        VenueCashPull(
            venue: leg.venue,
            usd: leg.usd,
            arrivingUsd: leg.arrivingUsd,
            eta: _sourceFor(leg.venue)?.estimatedArrival ?? Duration.zero)
    ];
    if (pulls.isEmpty) return null;
    final needed =
        _cents(pulls.fold<double>(0, (sum, leg) => sum + leg.arrivingUsd));
    return VenueCashPlan(
        neededUsd: needed,
        dollarsUsd: 0,
        pulls: pulls,
        covers: true,
        eta: move.legs.isEmpty
            ? Duration.zero
            : pulls.fold<Duration>(
                Duration.zero, (a, b) => a > b.eta ? a : b.eta),
        uncoveredUsd: 0);
  }

  VenueCashSource? _sourceFor(OneBalanceVenue venue) {
    VenueCashSource? source;
    for (final s in _sources) {
      if (s.venue == venue) source = s;
    }
    return source;
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
  /// money stays on its venue). For a [destination] other than Dollars a
  /// leg goes straight there when its venue's rail offers the route
  /// ([DirectVenueCashSource]); a refusal before anything moved brings it
  /// home to Dollars instead (and that route is not asked again this
  /// session). [onPlanned] hears the plan before any leg starts, for the
  /// progress lines, [onStarted] the move's record id once it is written
  /// (before any leg goes; its steps follow the move there), and [onLeg]
  /// each leg as it is sent (or fails). The call then reads Dollars every [pollEvery] until
  /// they hold what the action takes from them
  /// ([VenueCashPullOutcome.onwardUsd]) or the wait runs out; the outcome
  /// says which. [waitFor] null waits [venueCashWaitFor] the plan's ETA;
  /// [Duration.zero] returns once the legs are sent. A plan that does not
  /// cover the amount pulls nothing, and a failed leg skips the wait.
  ///
  /// Every call with legs is one move ([MultiSourceMoveStore]): [moveId]
  /// continues an earlier one (a Retry), whose legs that already went
  /// straight to the destination are not pulled again.
  ///
  /// [approval]: the action's one user approval, given BEFORE this call
  /// and binding [directLegLimit] of the plan. Required whenever a
  /// [destination] other than Dollars needs venue legs: without it
  /// nothing moves ([VenueLegApprovalRequired]; Dollars that already
  /// cover it are only waited on). A leg goes straight to the destination
  /// only while the approval covers it ([ApprovedLegAuthorization]); one
  /// it does not cover comes home to Dollars instead. Legs home to
  /// Dollars run under the automatic authorization.
  Future<VenueCashPullOutcome> pullShortfall({
    required double neededUsd,
    required String forAction,
    VenueCashDestination destination = VenueCashDestination.dollars,
    OneBalanceVenue? exclude,
    Duration? waitFor,
    String? moveId,
    AuthGrant? approval,
    VenueCashPlan? plan,
    bool deferFinishEvent = false,
    void Function(VenueCashPlan plan)? onPlanned,
    void Function(VenueCashLegOutcome leg)? onLeg,
    void Function(String moveId)? onStarted,
  }) {
    final run = _tail.then((_) => _pullShortfall(
          neededUsd: neededUsd,
          forAction: forAction,
          destination: destination,
          exclude: exclude,
          waitFor: waitFor,
          moveId: moveId,
          approval: approval,
          fixedPlan: plan,
          deferFinishEvent: deferFinishEvent,
          onPlanned: onPlanned,
          onLeg: onLeg,
          onStarted: onStarted,
        ));
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Retry on a move a leg failed for: pulls ONLY the failed remainder
  /// from the venues to the move's destination (Dollars, the money
  /// already arrived, are not asked again), as legs of the same move.
  /// Null when there is nothing left to pull or a Retry is running. A
  /// move to a destination other than Dollars needs [approval] (asked
  /// for [planRetry]'s legs first); without it nothing moves.
  Future<VenueCashPullOutcome?> retryMove(String moveId,
      {Duration waitFor = Duration.zero,
      AuthGrant? approval,
      VenueCashPlan? plan}) async {
    final move = MultiSourceMoveStore.get(moveId);
    if (move == null || !move.partial) return null;
    if (move.destination != VenueCashDestination.dollars && approval == null) {
      throw const VenueLegApprovalRequired();
    }
    if (!MultiSourceMoveStore.beginRetry(moveId)) return null;
    try {
      if (move.isParallelPurchase) {
        final safe = _parallelRetryPlan(move);
        if (safe == null) return null;
        final reviewed = plan ?? safe;
        final allowed = {for (final leg in safe.pulls) leg.venue: leg};
        if (reviewed.pulls.isEmpty ||
            reviewed.dollarsUsd != 0 ||
            reviewed.pulls.map((leg) => leg.venue).toSet().length !=
                reviewed.pulls.length ||
            reviewed.pulls.any((leg) => allowed[leg.venue] != leg)) {
          throw const VenueLegApprovalRequired();
        }
        // Persist the loss of no-send proof BEFORE starting native work.
        // A restart must not turn an unresolved retry into a second send.
        final selected =
            reviewed.pulls.map((leg) => MoveSteps.placeOf(leg.venue)).toSet();
        MultiSourceMoveStore.updateSteps(
            moveId,
            (record) => MoneyStepGraph([
                  for (final step in record.steps.steps)
                    MoveSteps.isVenueLeg(step) &&
                            selected.contains(step.from) &&
                            step.status == MoneyStepStatus.failed &&
                            step.ref == null
                        ? step.copyWith(
                            status: MoneyStepStatus.running,
                            reason: 'retry_pending')
                        : step,
                ]));
        // Only proven-stopped source calls are selected. They are disjoint
        // from still-running original legs and need not wait on their tail.
        return await _pullShortfall(
            neededUsd: reviewed.neededUsd,
            forAction: move.forAction,
            destination: move.destination,
            exclude: venueOfDestination(move.destination),
            waitFor: waitFor,
            moveId: moveId,
            useDollars: false,
            remainderOnly: true,
            approval: approval,
            fixedPlan: reviewed);
      }
      final run = _tail.then((_) => _pullShortfall(
            neededUsd: move.remainingUsd,
            forAction: move.forAction,
            destination: move.destination,
            exclude: venueOfDestination(move.destination),
            waitFor: waitFor,
            moveId: moveId,
            useDollars: false,
            remainderOnly: true,
            approval: approval,
          ));
      _tail = run.then((_) {}, onError: (_) {});
      return await run;
    } finally {
      MultiSourceMoveStore.endRetry(moveId);
    }
  }

  Future<VenueCashPullOutcome> _pullShortfall({
    required double neededUsd,
    required String forAction,
    required VenueCashDestination destination,
    OneBalanceVenue? exclude,
    Duration? waitFor,
    String? moveId,
    bool useDollars = true,
    bool remainderOnly = false,
    AuthGrant? approval,
    VenueCashPlan? fixedPlan,
    bool deferFinishEvent = false,
    void Function(VenueCashPlan plan)? onPlanned,
    void Function(VenueCashLegOutcome leg)? onLeg,
    void Function(String moveId)? onStarted,
  }) async {
    final excluded = exclude ?? venueOfDestination(destination);
    // A Retry of the whole action: what earlier legs already sent
    // straight to the destination is not pulled again.
    final earlier = moveId == null ? null : MultiSourceMoveStore.get(moveId);
    final alreadyDirect =
        remainderOnly ? 0.0 : (earlier?.directDeliveredUsd ?? 0.0);
    final needed = math.max(0.0, neededUsd - alreadyDirect);
    // The plan the action's approval bound, when it hands one: its legs
    // run exactly as approved (a fresh plan a cent apart would no longer
    // fit the leg caps and go through Dollars without a word).
    final plan = fixedPlan ??
        await this.plan(
            neededUsd: needed,
            exclude: excluded,
            destination: destination,
            useDollars: useDollars);
    if (!plan.covers) {
      return VenueCashPullOutcome(
          plan: plan,
          legs: const [],
          dollarsCover: false,
          eta: plan.eta,
          destination: destination,
          moveId: moveId,
          alreadyDeliveredUsd: alreadyDirect);
    }
    // No leg to a destination other than Dollars moves before the
    // action's own approval: refused here, before anything moved.
    if (plan.pulls.isNotEmpty &&
        destination != VenueCashDestination.dollars &&
        approval == null) {
      throw const VenueLegApprovalRequired();
    }
    onPlanned?.call(plan);
    final legs = <VenueCashLegOutcome>[];
    String? id = moveId;
    if (plan.pulls.isNotEmpty) {
      id ??= MultiSourceMoveStore.newId();
      String? wallet;
      try {
        wallet = _walletId?.call();
      } catch (_) {}
      MultiSourceMoveStore.start(MultiSourceMove(
        id: id,
        walletId: wallet,
        forAction: forAction,
        destination: destination,
        totalUsd: _cents(neededUsd),
        dollarsUsd: _cents(plan.dollarsUsd),
        createdAt: _clock(),
        // Every move as its steps (move_steps.dart): every leg as it is
        // about to go, then the action's own step (the purchase and the
        // arrival, the send, Dollars going on into the venue). A Retry
        // keeps the move's own graph (start() keeps the record).
        steps: _plannedSteps(plan, destination, approval, neededUsd, forAction),
      ));
      try {
        onStarted?.call(id);
      } catch (_) {/* a listener never stops the move */}
      TrackingService.track('multi_source_move_started', params: {
        'legs': plan.pulls.length + (plan.dollarsUsd > 0 ? 1 : 0),
        'total_usd': plan.neededUsd,
        'destination': forAction,
      });
      final moveKey = id;
      legs.addAll(await Future.wait([
        for (final p in plan.pulls)
          _runLeg(p, forAction, destination, moveKey, approval).then((leg) {
            try {
              onLeg?.call(leg);
            } catch (_) {/* a listener never fails a leg */}
            return leg;
          }),
      ]));
    }
    final failed = legs.where((l) => !l.ok).length;
    // What the action takes from Dollars: the whole amount when Dollars
    // are the destination, else what the direct legs do not bring.
    final direct = legs
        .where((l) => l.ok && l.direct)
        .fold<double>(0, (sum, l) => sum + l.pull.arrivingUsd);
    final onward = destination == VenueCashDestination.dollars
        ? plan.neededUsd
        : (remainderOnly ? 0.0 : _cents(math.max(0, plan.neededUsd - direct)));
    // Every leg went: what the action's own step takes from Dollars.
    if (!remainderOnly && plan.pulls.isNotEmpty) {
      MoveSteps.record(
          id,
          (g) => MoveSteps.onward(g, onward,
              destination: destination, forAction: forAction));
    }
    var cover = remainderOnly || _readDollars() + 0.000001 >= onward;
    final wait = waitFor ?? venueCashWaitFor(plan.eta);
    if (!cover && failed == 0 && wait > Duration.zero) {
      cover = await _waitForDollars(onward, wait);
      // What came home landed: its legs are done.
      if (cover) {
        MoveSteps.record(id, (g) => MoveSteps.dollarsLanded(g, at: _clock()));
      }
    }
    if (cover && !remainderOnly) _pending.clear();
    if (plan.pulls.isNotEmpty && !deferFinishEvent) {
      final delivered = plan.dollarsUsd +
          legs.fold<double>(0, (sum, l) => sum + l.arrivingUsd);
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
        eta: plan.eta,
        destination: destination,
        moveId: id,
        onwardUsd: onward,
        alreadyDeliveredUsd: alreadyDirect);
  }

  Future<VenueCashLegOutcome> _runLeg(
      VenueCashPull p,
      String forAction,
      VenueCashDestination destination,
      String moveId,
      AuthGrant? approval) async {
    var availableBefore = _lastAvailable[p.venue];
    try {
      final cached = _cachedAvailableUsd?.call(p.venue);
      if (cached != null &&
          cached.isFinite &&
          (availableBefore == null || cached < availableBefore)) {
        availableBefore = cached;
      }
    } catch (_) {/* a missing display snapshot never blocks a leg */}
    final source = _sourceFor(p.venue);
    if (source == null) {
      return _recorded(
          moveId,
          VenueCashLegOutcome(
              pull: p, error: const RouteUnavailable('no_source')));
    }
    var route = VenueCashRoute.viaDollars;
    String? fellBack;
    try {
      VenueMoveResult? result;
      if (destination != VenueCashDestination.dollars && approval != null) {
        try {
          AuthGrants.check(approval, approval.boundIntent);
        } on AuthGrantException {
          throw const DirectRouteRefused('settlement_declined');
        }
      }
      final supportsDirect = destination != VenueCashDestination.dollars &&
          source is DirectVenueCashSource &&
          (source as DirectVenueCashSource).canPullTo(destination) &&
          !DirectRouteRefusals.isRefused(p.venue, destination);
      if (supportsDirect &&
          approval != null &&
          !DirectLegGrants.covers(approval,
              venue: p.venue.name,
              destination: destination.code,
              amount: IntentUnits.usd(p.usd))) {
        // A supported route outside the reviewed scope must stop. Sending
        // home automatically here would hide an expired/mismatched approval.
        route = VenueCashRoute.direct;
        throw const DirectRouteRefused('settlement_declined');
      }
      // Straight to the destination only under the action's approval,
      // and only within the leg caps it binds; otherwise home to Dollars
      // (the automatic authorization's one destination).
      if (destination != VenueCashDestination.dollars &&
          approval != null &&
          source is DirectVenueCashSource &&
          (source as DirectVenueCashSource).canPullTo(destination) &&
          !DirectRouteRefusals.isRefused(p.venue, destination) &&
          DirectLegGrants.covers(approval,
              venue: p.venue.name,
              destination: destination.code,
              amount: IntentUnits.usd(p.usd))) {
        route = VenueCashRoute.direct;
        final direct = source as DirectVenueCashSource;
        Future<VenueMoveResult> go() => direct.pullTo(destination, p.usd,
            purpose: kVenueCashPullPurpose,
            auth: ApprovedLegAuthorization(approval));
        try {
          try {
            result = await go();
          } on DirectRouteRefused catch (e) {
            // A refusal that says nothing about the route (a read, the
            // network, the terms this time) is asked once more, while the
            // approval still covers the leg; anything else goes on below.
            if (!DirectRouteRefusals.retryable(e.reason) ||
                !DirectLegGrants.covers(approval,
                    venue: p.venue.name,
                    destination: destination.code,
                    amount: IntentUnits.usd(p.usd))) {
              rethrow;
            }
            _trackDirectRefused(p, destination, e, retrying: true);
            result = await go();
          }
        } on DirectRouteRefused catch (e) {
          // Refused before anything moved: through Dollars instead. Only a
          // refusal of the route itself keeps it off for a while; never
          // this approval not covering the leg (the next action brings its
          // own) nor a transient stop.
          if (_approvalRefusal(e)) {
            rethrow;
          }
          if (DirectRouteRefusals.sticky(e.reason)) {
            DirectRouteRefusals.refuse(p.venue, destination);
          }
          _trackDirectRefused(p, destination, e, retrying: false);
          route = VenueCashRoute.viaDollars;
          fellBack = directRefusalCode(e);
        }
      }
      result ??= await source.pull(p.usd, purpose: kVenueCashPullPurpose);
      final outcome = VenueCashLegOutcome(
        pull: p,
        result: result,
        route: route,
        landsIn: route == VenueCashRoute.direct
            ? destination
            : VenueCashDestination.dollars,
        fellBackReason: fellBack,
      );
      if (route == VenueCashRoute.viaDollars) {
        _pending.add((usd: outcome.arrivingUsd, at: _clock()));
      }
      final params = {
        'amount_usd': _cents(result.sentUsd > 0 ? result.sentUsd : p.usd),
        'for': forAction,
        'route': route,
        'destination': destination.code,
      };
      switch (p.venue) {
        case OneBalanceVenue.investing:
          TrackingService.track('investing_cash_pulled', params: params);
        case OneBalanceVenue.predictions:
          TrackingService.track('predictions_cash_pulled', params: params);
      }
      final recorded = _recorded(moveId, outcome);
      try {
        onCashMoved?.call(recorded, availableBefore);
      } catch (_) {/* a cache listener never fails a sent leg */}
      return recorded;
    } catch (e) {
      if (route == VenueCashRoute.viaDollars && venueLegBelowMinimum(e)) {
        try {
          onAmountTooSmall?.call(p.venue, p.usd);
        } catch (_) {/* a listener never changes the leg */}
      }
      return _recorded(
          moveId, VenueCashLegOutcome(pull: p, error: e, route: route));
    }
  }

  VenueCashLegOutcome _recorded(String moveId, VenueCashLegOutcome leg) {
    final result = leg.result;
    final parallel =
        MultiSourceMoveStore.get(moveId)?.isParallelPurchase == true;
    final knownUnsent = leg.error is DirectRouteRefused ||
        leg.error is SettlementFundingNotStarted;
    final recorded = MultiSourceMoveLeg(
      venue: leg.venue,
      usd: leg.ok ? _cents(leg.sentUsd) : leg.pull.usd,
      arrivingUsd: leg.ok ? _cents(leg.arrivingUsd) : leg.pull.arrivingUsd,
      route: leg.route,
      ok: leg.ok,
      at: _clock(),
      operationId: result?.operationId ??
          (leg.error is SettlementFundingUnknown
              ? (leg.error as SettlementFundingUnknown).operationId
              : null),
      quoteId: result?.quoteId,
      error: leg.ok
          ? null
          : parallel && knownUnsent
              ? 'not_sent'
              : TrackingService.errorCategory(leg.error),
      uncertain: parallel && !leg.ok && !knownUnsent,
      fellBack: leg.fellBackReason,
      stoppedOperationId: leg.error is SettlementFundingRefused
          ? (leg.error as SettlementFundingRefused).operationId
          : null,
    );
    // The leg and its step (on its way, failed, or through Dollars
    // instead: MultiSourceMoveStore.addLeg records both).
    MultiSourceMoveStore.addLeg(moveId, recorded);
    return leg;
  }

  /// A leg that came home to Dollars has landed ([usd]: what it was
  /// counted as on its way): Dollars show it now, so it no longer counts
  /// as on its way (it would be counted twice, or after it moved on).
  void landedHome(double usd) {
    if (!usd.isFinite || usd <= 0) return;
    final i = _pending.indexWhere((p) => (p.usd - usd).abs() < 0.005);
    if (i >= 0) _pending.removeAt(i);
  }

  /// [e]'s fixed code, as the leg's step and the event carry it.
  static String directRefusalCode(DirectRouteRefused e) {
    final r = e.reason ?? '';
    return RegExp(r'^[a-z_]{1,48}$').hasMatch(r)
        ? r
        : TrackingService.errorCategory(r.isEmpty ? 'unknown' : r);
  }

  /// Waits (at most [waitFor]) until Dollars hold [neededUsd]: the move
  /// from Dollars of an action whose venue legs went without the wait
  /// ([pullShortfall]'s `waitFor` zero, while other money was still on
  /// its way to Dollars). [neededUsd] is then the action's own step on
  /// the move's record ([moveId], into [destination] for [forAction]);
  /// covered after a wait, the legs home are done and the pulls on their
  /// way are no longer counted. Never moves anything.
  Future<bool> waitForDollars(
    double neededUsd, {
    String? moveId,
    VenueCashDestination? destination,
    String? forAction,
    Duration waitFor = Duration.zero,
  }) async {
    if (moveId != null && destination != null && forAction != null) {
      MoveSteps.record(
          moveId,
          (g) => MoveSteps.onward(g, _cents(neededUsd),
              destination: destination, forAction: forAction));
    }
    var cover = _readDollars() + 0.000001 >= neededUsd;
    if (!cover && waitFor > Duration.zero) {
      cover = await _waitForDollars(neededUsd, waitFor);
      if (cover) {
        MoveSteps.record(
            moveId, (g) => MoveSteps.dollarsLanded(g, at: _clock()));
      }
    }
    if (cover) _pending.clear();
    return cover;
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

  /// A move's steps for [plan] as its legs are about to go: each leg
  /// straight to [destination] exactly when [_runLeg] would send it there
  /// (the approval covers it), home to Dollars otherwise; then the
  /// action's own step for what the direct legs do not bring (the
  /// purchase, Dollars going on into the venue), or the whole amount for
  /// a send. Moves nothing.
  MoneyStepGraph _plannedSteps(
      VenueCashPlan plan,
      VenueCashDestination destination,
      AuthGrant? approval,
      double totalUsd,
      String forAction) {
    bool direct(VenueCashPull p) {
      final source = _sourceFor(p.venue);
      return destination != VenueCashDestination.dollars &&
          approval != null &&
          source is DirectVenueCashSource &&
          (source as DirectVenueCashSource).canPullTo(destination) &&
          !DirectRouteRefusals.isRefused(p.venue, destination) &&
          DirectLegGrants.covers(approval,
              venue: p.venue.name,
              destination: destination.code,
              amount: IntentUnits.usd(p.usd));
    }

    final legs = [
      for (final p in plan.pulls)
        (venue: p.venue, usd: p.usd, direct: direct(p)),
    ];
    var directUsd = 0.0;
    for (var i = 0; i < legs.length; i++) {
      if (legs[i].direct) directUsd += plan.pulls[i].arrivingUsd;
    }
    return MoveSteps.planned(
      destination: destination,
      forAction: forAction,
      legs: legs,
      onwardUsd: destination == VenueCashDestination.dollars
          ? plan.neededUsd
          : _cents(math.max(0, plan.neededUsd - directUsd)),
      totalUsd: _cents(totalUsd),
      at: _clock(),
    );
  }

  /// `venue_cash_direct_refused`: a leg's direct route was refused before
  /// anything moved, with the rail's fixed reason code (never an error
  /// text), whether it is asked once more ([retrying]) or goes through
  /// Dollars, and whether the refusal keeps the route off for a while.
  static void _trackDirectRefused(VenueCashPull p,
          VenueCashDestination destination, DirectRouteRefused e,
          {required bool retrying}) =>
      TrackingService.track('venue_cash_direct_refused', params: {
        'venue': p.venue.name,
        'destination': destination.code,
        // The rails' reasons are fixed codes (`cctp_in_flight`, an error
        // category); anything else is classified, never sent as text.
        'reason': directRefusalCode(e),
        'retrying': retrying,
        'sticky': DirectRouteRefusals.sticky(e.reason),
        'amount_usd': _cents(p.usd),
      });

  /// A direct leg the rail's approval check refused (the approval lapsed
  /// or did not cover it), not the route itself.
  static bool _approvalRefusal(DirectRouteRefused e) =>
      e.reason == 'settlement_declined' || e.reason == 'user_cancelled';
}

// ─── Riverpod ──────────────────────────────────────────────────────

/// Both venues' cash, Predictions first.
final venueCashSourcesProvider = Provider<List<VenueCashSource>>((ref) {
  final rail = ref.read(hyperliquidMoveRailProvider);
  return [
    PolymarketCashSource(ref.read(predictionsVenueFunderProvider),
        isLive: () => ref.exists(polymarketTradingProvider)),
    HyperliquidCashSource(
      rail,
      readGuard: () => readHyperliquidPullGuard(ref.read),
      direct: rail is HyperCoreMoveRail
          ? (destination, usd, purpose, auth) => rail.withdrawDirect(
              destination: destination, usd: usd, auth: auth, purpose: purpose)
          : null,
    ),
  ];
});

/// The app's puller. Not autoDispose: it remembers pulls on their way.
final venueCashPullerProvider = Provider<VenueCashPuller>((ref) {
  final snapshot = ref.watch(venueCashSnapshotProvider);
  final minimums = ref.read(routeMinimumsProvider);
  return VenueCashPuller(
    sources: ref.read(venueCashSourcesProvider),
    readDollars: () => ref.read(usdBalanceProvider),
    minimumUsd: minimums.minimumUsd,
    nudge: () => BackgroundSyncService().syncNow(),
    walletId: () => pickSpendingWallet(ref.read(settingsProvider))?.id,
    onCashMoved: snapshot.cashMoved,
    onAmountTooSmall: minimums.noteAmountTooSmall,
    cachedAvailableUsd: snapshot.availableUsd,
  );
});

/// How far Dollars plus venue cash reach for an order at [exclude]:
/// Dollars plus the OTHER venues' cash (the target venue's own cash is already counted as
/// what it holds). What the order slips' funding engine
/// (`OrderFundingEngine.decide`) reads as "the rest of Investments".
final venueCashReachExcludingProvider = FutureProvider.autoDispose
    .family<double, OneBalanceVenue>((ref, exclude) async {
  final dollars = ref.watch(usdBalanceProvider);
  try {
    return await ref.read(venueCashPullerProvider).reachUsd(exclude: exclude);
  } catch (_) {
    return dollars;
  }
});
