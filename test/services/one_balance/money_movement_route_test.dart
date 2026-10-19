// Move money's pure rules: the twelve routes between the spending
// wallet's own cash accounts, how each one moves (rail, source unit, own
// recipient, settlement accounts), and which stops prove that nothing
// left (a fresh Retry is safe) versus a send whose outcome is unknown
// (the sheet locks and points at Activity).

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/models/orchestra_route_limits.dart'
    show RouteQuoteError, RouteQuoteErrorCode;
import 'package:kute/models/orchestra_routes_model.dart'
    show RouteUnavailableReason;
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/services/funding/owned_address_resolver.dart'
    show checkSettlementAccountPair;
import 'package:kute/services/funding/settlement_funding_outcome.dart';
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/services/funding/spark_hypercore_funding_service.dart';
import 'package:kute/services/hyperliquid/cctp_withdrawal.dart';
import 'package:kute/services/one_balance/money_movement_route.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart'
    show RecipientKind;
import 'package:kute/handlers/response_handlers.dart' show Result;
import 'package:kute/services/funding/settlement_http.dart'
    show SettlementHttpOutcome, classifySettlementResult;
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart'
    show HyperCoreMoveRail;
import 'package:kute/services/orchestra/orchestra_quote_gate.dart'
    show OrchestraQuoteFailure;
import 'package:kute/services/orchestra/standing_deposit_store.dart'
    show InvestingWithdrawalDestination;
import 'package:kute/services/runtime_capabilities_service.dart';

const _b = MoneyMovementAccount.bitcoin;
const _d = MoneyMovementAccount.dollars;
const _i = MoneyMovementAccount.investing;
const _p = MoneyMovementAccount.predictions;

void main() {
  test('twelve routes: four accounts, never the same account at both ends', () {
    expect(MoneyMovementRoute.all, hasLength(12));
    expect(MoneyMovementRoute.all.toSet(), hasLength(12));
    for (final r in MoneyMovementRoute.all) {
      expect(r.from, isNot(r.to));
      expect(r.reversed.reversed, r);
      expect(r.code, '${r.from.name}_to_${r.to.name}');
    }
    expect(const MoneyMovementRoute(_d, _b), const MoneyMovementRoute(_d, _b));
    expect(const MoneyMovementRoute(_d, _b) == const MoneyMovementRoute(_b, _d),
        isFalse);
  });

  test('every route is enabled: each has a safe rail today', () {
    expect(kMoneyMovementDisabledRoutes, isEmpty);
  });

  group('the plan for each pair', () {
    final expected = <MoneyMovementRoute,
        (MoneyMovementRail, SettlementFlow, String, String)>{
      const MoneyMovementRoute(_b, _d): (
        MoneyMovementRail.orchestra,
        SettlementFlow.moveBtcToUsdc,
        'spark_btc',
        'spark_usdb'
      ),
      const MoneyMovementRoute(_b, _i): (
        MoneyMovementRail.orchestra,
        SettlementFlow.sparkToInvestingDirect,
        'spark_btc',
        'hypercore_usdc'
      ),
      const MoneyMovementRoute(_b, _p): (
        MoneyMovementRail.orchestra,
        SettlementFlow.moveBtcToPredictions,
        'spark_btc',
        'polygon_usdc.e'
      ),
      const MoneyMovementRoute(_d, _b): (
        MoneyMovementRail.orchestra,
        SettlementFlow.moveDollarsToBtc,
        'spark_usdb',
        'spark_btc'
      ),
      const MoneyMovementRoute(_d, _i): (
        MoneyMovementRail.orchestra,
        SettlementFlow.sparkToInvestingDirect,
        'spark_usdb',
        'hypercore_usdc'
      ),
      const MoneyMovementRoute(_d, _p): (
        MoneyMovementRail.orchestra,
        SettlementFlow.moveUsdToPredictions,
        'spark_usdb',
        'polygon_usdc.e'
      ),
      const MoneyMovementRoute(_i, _b): (
        MoneyMovementRail.hypercoreNativeThenCctp,
        SettlementFlow.investingToSparkDirect,
        'hypercore_usdc',
        'spark_btc'
      ),
      const MoneyMovementRoute(_i, _d): (
        MoneyMovementRail.hypercoreNativeThenCctp,
        SettlementFlow.investingToSparkUsdDirect,
        'hypercore_usdc',
        'spark_usdb'
      ),
      const MoneyMovementRoute(_i, _p): (
        MoneyMovementRail.hypercoreNativeThenCctp,
        SettlementFlow.investingToPredictionsDirect,
        'hypercore_usdc',
        'polygon_usdc.e'
      ),
      const MoneyMovementRoute(_p, _b): (
        MoneyMovementRail.orchestra,
        SettlementFlow.moveUsdToBtc,
        'polygon_usdc.e',
        'spark_btc'
      ),
      const MoneyMovementRoute(_p, _d): (
        MoneyMovementRail.orchestra,
        SettlementFlow.movePredictionsToDollars,
        'polygon_usdc.e',
        'spark_usdb'
      ),
      const MoneyMovementRoute(_p, _i): (
        MoneyMovementRail.orchestra,
        SettlementFlow.movePredictionsToInvesting,
        'polygon_usdc.e',
        'hypercore_usdc'
      ),
    };

    test('covers all twelve', () {
      expect(expected.keys.toSet(), MoneyMovementRoute.all.toSet());
    });

    for (final entry in expected.entries) {
      final route = entry.key;
      final (rail, flow, from, to) = entry.value;
      test('$route: rail, flow, route and source unit', () {
        final plan = moneyMovementPlanFor(route);
        expect(plan.route, route);
        expect(plan.rail, rail);
        expect(plan.flow, flow);
        expect(plan.quoteRoute.label, '$from>$to');
        // Only a Bitcoin source leaves in satoshis.
        expect(plan.sourceInSats, route.from == _b);
        // A CCTP move has no Orchestra quote to show as its fee.
        expect(plan.orchestraEstimate, rail != MoneyMovementRail.cctp);
        expect(
            plan.railCode,
            switch (rail) {
              MoneyMovementRail.orchestra => 'orchestra',
              MoneyMovementRail.hypercoreNativeThenCctp => 'direct',
              MoneyMovementRail.cctp => 'cctp',
            });
      });

      test('$route: lands in the wallet\'s own account', () {
        final plan = moneyMovementPlanFor(route);
        expect(
            plan.recipient,
            switch (route.to) {
              _b || _d => RecipientKind.ownSpark,
              _i => RecipientKind.ownEvm,
              _p => RecipientKind.ownPmWallet,
            });
        expect(plan.recipient, isNot(RecipientKind.external));
        // No route starts on CCTP: it is only the native routes' fallback.
        expect(plan.rail, isNot(MoneyMovementRail.cctp));
        // The runner's own-account guard accepts the pair on these chains.
        expect(
            () => checkSettlementAccountPair(
                route: plan.quoteRoute,
                source: plan.source,
                destination: plan.destination),
            returnsNormally);
      });
    }
  });

  group('Investing → Predictions', () {
    final plan = moneyMovementPlanFor(const MoneyMovementRoute(_i, _p));

    test('goes native HyperCore first, to the own Predictions account', () {
      expect(plan.rail, MoneyMovementRail.hypercoreNativeThenCctp);
      expect(plan.railCode, 'direct');
      expect(plan.flow, SettlementFlow.investingToPredictionsDirect);
      expect(plan.flow.code, 'investing_to_predictions_direct');
      expect(plan.quoteRoute.label, kHypercoreToPredictionsRoute.label);
      expect(plan.source, SettlementAccountKind.hlHot);
      expect(plan.destination, SettlementAccountKind.pmHot);
      expect(plan.recipient, RecipientKind.ownPmWallet);
      expect(plan.orchestraEstimate, isTrue);
    });

    test('its CCTP fallback runs the same route to the same destination', () {
      const predictions = InvestingWithdrawalDestination.predictions;
      expect(cctpRouteFor(predictions).label, plan.quoteRoute.label,
          reason: 'one approved route label covers both attempts');
      expect(cctpFlowFor(predictions),
          SettlementFlow.investingToPredictionsCctp);
      expect(kHypercoreToPredictionsRoute.toChain, predictions.chain);
      expect(kHypercoreToPredictionsRoute.toAsset, predictions.asset);
    });

    test('only Orchestra refusing the route opens CCTP', () {
      // The catalogue missing the pair, or the quote refusing the route.
      expect(
          HyperCoreMoveRail.opensCctpFallback(const SettlementStopped(
              SettlementStopReason.routeUnavailable,
              routeReason: RouteUnavailableReason.pairMissing)),
          isTrue);
      expect(
          HyperCoreMoveRail.opensCctpFallback(OrchestraQuoteFailure(
              'unsupported_route',
              routeError: RouteQuoteError(
                  RouteQuoteErrorCode.fromCode('unsupported_route')!))),
          isTrue);
      final denial = capabilityDenialFromResponse(403,
          '{"error":"feature_unavailable","capability":"polymarket.deposit",'
          '"reason":"country_blocked"}')!;
      for (final stop in <Object>[
        OrchestraQuoteFailure('unsupported_route', denial: denial),
        const SettlementStopped(SettlementStopReason.declined),
        const SettlementStopped(SettlementStopReason.quoteExpired),
        const SettlementStopped(SettlementStopReason.routeUnavailable,
            routeReason: RouteUnavailableReason.stale),
        const HypercoreFundingUnavailable(
            HypercoreFundingUnavailableReason.paused),
        const OrchestraQuoteFailure('too small',
            routeError: RouteQuoteError(RouteQuoteErrorCode.amountTooSmall)),
        const SettlementFundingUnknown('op', 'lost'),
      ]) {
        expect(HyperCoreMoveRail.opensCctpFallback(stop), isFalse,
            reason: '$stop');
      }
    });
  });

  group('what proves nothing was sent', () {
    bool proves(Object e, {bool started = true}) =>
        moneyMovementProvesNothingSent(e, fundingStarted: started);

    test('an unknown funding outcome never does', () {
      expect(proves(const SettlementFundingUnknown('op', 'lost')), isFalse);
      expect(
          proves(const SettlementFundingUnknown('op', 'lost'), started: false),
          isFalse);
    });

    test('an earlier transfer still unresolved never does', () {
      expect(
          proves(const SettlementStopped(SettlementStopReason.blockedPending),
              started: false),
          isFalse);
    });

    test('a runner stop before broadcasting does', () {
      for (final reason in [
        SettlementStopReason.declined,
        SettlementStopReason.quoteExpired,
        SettlementStopReason.quoteReplaced,
        SettlementStopReason.routeUnavailable,
      ]) {
        expect(proves(SettlementStopped(reason)), isTrue, reason: '$reason');
      }
    });

    test('a funding call that said it never submitted does', () {
      expect(proves(const SettlementFundingRefused('locked')), isTrue);
      expect(proves(const MoneyMovementDetailsChanged()), isTrue);
      expect(const MoneyMovementDetailsChanged(),
          isA<SettlementFundingNotStarted>());
    });

    test('a rail that refused before signing does', () {
      expect(
          proves(const CctpUnavailable(CctpUnavailableReason.paused)), isTrue);
      expect(
          proves(const HypercoreFundingUnavailable(
              HypercoreFundingUnavailableReason.paused)),
          isTrue);
    });

    test('a raw error proves it only before the funding call was reached', () {
      expect(proves(StateError('timeout')), isFalse);
      expect(proves(StateError('timeout'), started: false), isTrue);
    });
  });

  test('failure reasons are fixed categories', () {
    String reason(Object e, {bool started = true}) =>
        moneyMovementFailureReason(e, fundingStarted: started);
    expect(reason(const MoneyMovementDetailsChanged()), 'wallet_changed');
    expect(reason(const SettlementStopped(SettlementStopReason.declined)),
        'approval_declined');
    expect(reason(const GrantExpired()), 'approval_declined');
    expect(
        reason(const SettlementFundingUnknown('op', 'x')), 'unknown_outcome');
    expect(
        reason(const SettlementStopped(SettlementStopReason.routeUnavailable)),
        'route_refused');
    expect(reason(const CctpUnavailable(CctpUnavailableReason.paused)),
        'route_refused');
    expect(reason(StateError('x'), started: false), 'not_sent');
    expect(reason(StateError('x')), 'unknown_outcome');
  });

  group('withheld routes', () {
    test('each route answers to the capabilities its rail checks', () {
      List<String> caps(MoneyMovementAccount a, MoneyMovementAccount b) =>
          moneyMovementPlanFor(MoneyMovementRoute(a, b)).capabilities;
      expect(caps(_d, _i), ['hyperliquid.deposit']);
      expect(caps(_b, _i), ['hyperliquid.deposit']);
      expect(caps(_d, _p), ['polymarket.deposit']);
      expect(caps(_b, _p), ['polymarket.deposit']);
      // A withdrawal never answers to a deposit gate.
      expect(caps(_i, _d), ['hyperliquid.withdraw']);
      expect(caps(_i, _b), ['hyperliquid.withdraw']);
      expect(caps(_p, _d), ['polymarket.withdraw']);
      expect(caps(_p, _b), ['polymarket.withdraw']);
      // Venue to venue: both ends.
      expect(caps(_i, _p), ['hyperliquid.withdraw', 'polymarket.deposit']);
      expect(caps(_p, _i), ['polymarket.withdraw', 'hyperliquid.deposit']);
      // The spending account's own Bitcoin and Dollars: the swap switch.
      expect(caps(_b, _d), ['orchestra.swap']);
      expect(caps(_d, _b), ['orchestra.swap']);
      // The CCTP move checks exactly the same set.
      expect(caps(_i, _p),
          cctpCapabilitiesFor(InvestingWithdrawalDestination.predictions));
    });

    CapabilityDecision allow(String _) =>
        const CapabilityDecision(allowed: true);

    test('the first refused capability is the restriction; offline grace '
        'never restricts', () {
      CapabilityDecision decide(String id) => id == 'polymarket.deposit'
          ? const CapabilityDecision(allowed: false, reason: 'country_blocked')
          : const CapabilityDecision(allowed: true, reason: 'offline_grace');
      final r = moneyMovementRestrictionFor(
          ['hyperliquid.withdraw', 'polymarket.deposit'], decide)!;
      expect(r.capability, 'polymarket.deposit');
      expect(r.region, isTrue);
      expect(r.reason, 'country_blocked');
      expect(moneyMovementRestrictionFor(['hyperliquid.withdraw'], decide),
          isNull);
    });

    test("policy refusals map to restrictions; other stops don't", () {
      const caps = ['hyperliquid.withdraw', 'polymarket.deposit'];
      final denial = capabilityDenialFromResponse(
          403,
          '{"error":"feature_unavailable","capability":"polymarket.deposit",'
          '"reason":"country_blocked","revision":3}')!;
      expect(denial.capability, 'polymarket.deposit');
      expect(denial.decision.regionRestricted, isTrue);

      final fromQuote = moneyMovementRestrictionOf(
          OrchestraQuoteFailure('feature_unavailable', denial: denial),
          capabilities: caps,
          decide: allow)!;
      expect(fromQuote.capability, 'polymarket.deposit');
      expect(fromQuote.region, isTrue);

      final fromCctp = moneyMovementRestrictionOf(
          const CctpUnavailable(CctpUnavailableReason.capability,
              decision: CapabilityDecision(allowed: false, reason: 'disabled')),
          capabilities: caps,
          decide: (id) => id == 'hyperliquid.withdraw'
              ? const CapabilityDecision(allowed: false, reason: 'disabled')
              : const CapabilityDecision(allowed: true))!;
      expect(fromCctp.capability, 'hyperliquid.withdraw');
      expect(fromCctp.region, isFalse);

      final venue = moneyMovementRestrictionOf(
          const ProviderAvailabilityException(ProviderAvailability(
              InvestmentProvider.polymarket,
              ProviderAvailabilityStatus.restricted)),
          capabilities: caps,
          decide: allow)!;
      expect(venue.capability, 'polymarket.deposit');
      expect(venue.region, isTrue);

      for (final other in <Object>[
        const CctpUnavailable(CctpUnavailableReason.feeTermsUnavailable),
        const SettlementStopped(SettlementStopReason.routeUnavailable),
        OrchestraQuoteFailure('route_unavailable'),
        StateError('x'),
      ]) {
        expect(
            moneyMovementRestrictionOf(other,
                capabilities: caps, decide: allow),
            isNull,
            reason: '$other');
      }
    });

    test('only a 403 feature_unavailable body is a policy denial', () {
      expect(
          capabilityDenialFromResponse(400,
              '{"error":"feature_unavailable","capability":"x.y"}'),
          isNull);
      expect(capabilityDenialFromResponse(403, '{"error":"forbidden"}'),
          isNull);
      expect(capabilityDenialFromResponse(403, 'not json'), isNull);
      final withMessage = capabilityDenialFromResponse(403,
          '{"error":"feature_unavailable","capability":"hyperliquid.deposit",'
          '"reason":"disabled","message":"Paused for maintenance."}')!;
      expect(withMessage.decision.message, 'Paused for maintenance.');
    });

    test('a policy refusal is never retried and never opens another rail',
        () {
      final denial = capabilityDenialFromResponse(403,
          '{"error":"feature_unavailable","capability":"hyperliquid.withdraw",'
          '"reason":"disabled"}')!;
      expect(
          classifySettlementResult(Result<Object?>(error: 'x', cause: denial)),
          SettlementHttpOutcome.rejected);
      expect(
          HyperCoreMoveRail.opensCctpFallback(OrchestraQuoteFailure(
              'unsupported_route',
              denial: denial)),
          isFalse);
    });
  });
}
