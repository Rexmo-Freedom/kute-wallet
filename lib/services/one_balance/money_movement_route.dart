// lib/services/one_balance/money_movement_route.dart
//
// The Portfolio's "Move money" (founder request, 17 October 2026): the
// person picks one of the spending wallet's own cash accounts to move
// from, another to move to, and an amount. Nothing moves until they
// confirm, and only the account they picked pays.
//
// This file is the pure half of that sheet: the four accounts, the twelve
// routes between them, how each route moves (which rail, in which unit,
// to which of the wallet's own accounts), and the rule that decides
// whether a stopped move proved nothing left (a fresh Retry is safe) or
// may have sent money (the sheet locks and points at Activity).
//
// The sheet (lib/screens/home/components/deposit_sheet.dart) dispatches
// each route to the same rails the single-purpose doors use. Positions
// and the Ledger are never part of this.

import 'package:kute/helpers/auth_grant.dart' show AuthGrantException;
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/models/settlement_operation.dart'
    show SettlementAccountKind, SettlementFlow;
import 'package:kute/services/funding/settlement_funding_outcome.dart'
    show SettlementFundingNotStarted;
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementFundingUnknown, SettlementStopReason, SettlementStopped;
import 'package:kute/services/funding/spark_hypercore_funding_service.dart'
    show HypercoreFundingUnavailable;
import 'package:kute/services/hyperliquid/cctp_withdrawal.dart'
    show CctpUnavailable;
import 'package:kute/services/orchestra/orchestra_quote_guard.dart'
    show RecipientKind;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode, kOrchestraUsdChain;

/// The spending wallet's own cash accounts. Positions are never moved.
enum MoneyMovementAccount { bitcoin, dollars, investing, predictions }

/// From one account to another. Never the same account twice.
class MoneyMovementRoute {
  const MoneyMovementRoute(this.from, this.to) : assert(from != to);

  final MoneyMovementAccount from;
  final MoneyMovementAccount to;

  bool get valid => from != to;
  MoneyMovementRoute get reversed => MoneyMovementRoute(to, from);

  /// Analytics value: `dollars_to_bitcoin`.
  String get code => '${from.name}_to_${to.name}';

  /// Every route the sheet can be asked for: four accounts, distinct ends.
  static final List<MoneyMovementRoute> all = [
    for (final from in MoneyMovementAccount.values)
      for (final to in MoneyMovementAccount.values)
        if (from != to) MoneyMovementRoute(from, to),
  ];

  @override
  bool operator ==(Object other) =>
      other is MoneyMovementRoute && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => code;
}

/// How a route's money travels.
enum MoneyMovementRail {
  /// One Orchestra quote, bound to the wallet's own recipient, paid from
  /// the source account by the settlement runner.
  orchestra,

  /// Native HyperCore → Spark through Orchestra first. Circle CCTP only
  /// when Orchestra refused the route itself before anything was signed
  /// (`HyperCoreMoveRail.opensCctpFallback`).
  hypercoreNativeThenCctp,

  /// Circle CCTP out of HyperCore to the wallet's own standing instruction.
  /// There is no Orchestra quote to price it with.
  cctp,
}

/// What a route moves and where it lands, as the sheet dispatches it.
class MoneyMovementPlan {
  const MoneyMovementPlan({
    required this.route,
    required this.rail,
    required this.sourceInSats,
    required this.quoteRoute,
    required this.source,
    required this.destination,
    required this.recipient,
    required this.flow,
  });

  final MoneyMovementRoute route;
  final MoneyMovementRail rail;

  /// The source leaves in satoshis (Bitcoin); every other source leaves
  /// in its own six-decimal dollar units.
  final bool sourceInSats;

  /// The route the first quote (or the CCTP move) is for: what the fee
  /// estimate prices and what the settlement record names.
  final RouteKey quoteRoute;

  /// The wallet's own accounts at each end (`checkSettlementAccountPair`).
  final SettlementAccountKind source;
  final SettlementAccountKind destination;

  /// The kind of own address the quote's recipient must be.
  final RecipientKind recipient;

  /// The settlement flow the first attempt is recorded under.
  final SettlementFlow flow;

  /// Whether the sheet may show an Orchestra estimate as this route's
  /// fee. A CCTP move has no quote, so no Orchestra estimate stands for it.
  bool get orchestraEstimate => rail != MoneyMovementRail.cctp;

  /// Analytics `route` of the first attempt: `orchestra`, `direct`
  /// (native HyperCore) or `cctp`.
  String get railCode => switch (rail) {
        MoneyMovementRail.orchestra => 'orchestra',
        MoneyMovementRail.hypercoreNativeThenCctp => 'direct',
        MoneyMovementRail.cctp => 'cctp',
      };
}

/// The plan for [route]. Pure; the sheet's dispatch and its fee block
/// follow it, and the tests hold every pair to it.
MoneyMovementPlan moneyMovementPlanFor(MoneyMovementRoute route) {
  (String, String) end(MoneyMovementAccount a) => switch (a) {
        MoneyMovementAccount.bitcoin => ('spark', 'BTC'),
        MoneyMovementAccount.dollars => (
            kOrchestraUsdChain,
            kOrchestraUsdAssetCode
          ),
        MoneyMovementAccount.investing => ('hypercore', 'USDC'),
        MoneyMovementAccount.predictions => ('polygon', 'USDC.e'),
      };
  SettlementAccountKind account(MoneyMovementAccount a) => switch (a) {
        MoneyMovementAccount.bitcoin ||
        MoneyMovementAccount.dollars =>
          SettlementAccountKind.sparkHot,
        MoneyMovementAccount.investing => SettlementAccountKind.hlHot,
        MoneyMovementAccount.predictions => SettlementAccountKind.pmHot,
      };
  RecipientKind recipient(MoneyMovementAccount a) => switch (a) {
        MoneyMovementAccount.bitcoin ||
        MoneyMovementAccount.dollars =>
          RecipientKind.ownSpark,
        MoneyMovementAccount.investing => RecipientKind.ownEvm,
        MoneyMovementAccount.predictions => RecipientKind.ownPmWallet,
      };
  if (!route.valid) {
    throw ArgumentError.value(route, 'route', 'same account');
  }
  final from = end(route.from);
  final to = end(route.to);
  final rail = route.from != MoneyMovementAccount.investing
      ? MoneyMovementRail.orchestra
      : route.to == MoneyMovementAccount.predictions
          ? MoneyMovementRail.cctp
          : MoneyMovementRail.hypercoreNativeThenCctp;
  final flow = switch ((route.from, route.to)) {
    (MoneyMovementAccount.bitcoin, MoneyMovementAccount.dollars) =>
      SettlementFlow.moveBtcToUsdc,
    (MoneyMovementAccount.bitcoin, MoneyMovementAccount.investing) =>
      SettlementFlow.sparkToInvestingDirect,
    (MoneyMovementAccount.bitcoin, MoneyMovementAccount.predictions) =>
      SettlementFlow.moveBtcToPredictions,
    (MoneyMovementAccount.dollars, MoneyMovementAccount.bitcoin) =>
      SettlementFlow.moveDollarsToBtc,
    (MoneyMovementAccount.dollars, MoneyMovementAccount.investing) =>
      SettlementFlow.sparkToInvestingDirect,
    (MoneyMovementAccount.dollars, MoneyMovementAccount.predictions) =>
      SettlementFlow.moveUsdToPredictions,
    (MoneyMovementAccount.investing, MoneyMovementAccount.bitcoin) =>
      SettlementFlow.investingToSparkDirect,
    (MoneyMovementAccount.investing, MoneyMovementAccount.dollars) =>
      SettlementFlow.investingToSparkUsdDirect,
    (MoneyMovementAccount.investing, MoneyMovementAccount.predictions) =>
      SettlementFlow.investingToPredictionsCctp,
    (MoneyMovementAccount.predictions, MoneyMovementAccount.bitcoin) =>
      SettlementFlow.moveUsdToBtc,
    (MoneyMovementAccount.predictions, MoneyMovementAccount.dollars) =>
      SettlementFlow.movePredictionsToDollars,
    (MoneyMovementAccount.predictions, MoneyMovementAccount.investing) =>
      SettlementFlow.movePredictionsToInvesting,
    _ => throw ArgumentError.value(route, 'route', 'same account'),
  };
  return MoneyMovementPlan(
    route: route,
    rail: rail,
    sourceInSats: route.from == MoneyMovementAccount.bitcoin,
    quoteRoute: RouteKey(
        fromChain: from.$1, fromAsset: from.$2, toChain: to.$1, toAsset: to.$2),
    source: account(route.from),
    destination: account(route.to),
    recipient: recipient(route.to),
    flow: flow,
  );
}

/// Routes the picker shows but does not let anyone choose (the picker's
/// existing disabled row), with the analytics reason. Empty: every route
/// has a safe rail today.
const Map<MoneyMovementRoute, String> kMoneyMovementDisabledRoutes = {};

/// The spending wallet, or the route the move was confirmed for, changed
/// while the move was on its way: stopped before anything was sent.
class MoneyMovementDetailsChanged
    implements Exception, SettlementFundingNotStarted {
  const MoneyMovementDetailsChanged();

  @override
  String toString() => 'MoneyMovementDetailsChanged';
}

/// Whether [e] proves the move sent nothing, so a fresh Retry (with a
/// fresh approval) cannot pay twice.
///
/// Proof is explicit: a funding call that said it never submitted
/// ([SettlementFundingNotStarted], `SettlementFundingRefused` included),
/// a runner stop before broadcasting ([SettlementStopped], except
/// `blockedPending`, where an earlier transfer on the route is still
/// unresolved), a rail that refused before signing ([CctpUnavailable],
/// [HypercoreFundingUnavailable]), a declined or lapsed approval, or the
/// sheet's own record that the funding call was never reached
/// ([fundingStarted] false). [SettlementFundingUnknown] never proves it,
/// and neither does a raw error once funding started.
bool moneyMovementProvesNothingSent(Object e, {required bool fundingStarted}) {
  if (e is SettlementFundingUnknown) return false;
  if (e is SettlementStopped) {
    return e.reason != SettlementStopReason.blockedPending;
  }
  if (e is SettlementFundingNotStarted) return true;
  if (e is CctpUnavailable || e is HypercoreFundingUnavailable) return true;
  if (e is AuthGrantException) return true;
  return !fundingStarted;
}

/// The analytics `reason` of a move that stopped: a fixed category, never
/// the error text.
String moneyMovementFailureReason(Object e, {required bool fundingStarted}) {
  if (e is MoneyMovementDetailsChanged) return 'wallet_changed';
  if (e is AuthGrantException ||
      (e is SettlementStopped && e.reason == SettlementStopReason.declined)) {
    return 'approval_declined';
  }
  if (!moneyMovementProvesNothingSent(e, fundingStarted: fundingStarted)) {
    return 'unknown_outcome';
  }
  if (e is CctpUnavailable ||
      e is HypercoreFundingUnavailable ||
      (e is SettlementStopped &&
          e.reason == SettlementStopReason.routeUnavailable)) {
    return 'route_refused';
  }
  return 'not_sent';
}
