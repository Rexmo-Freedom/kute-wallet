// Move money's pure rules: the twelve routes between the spending
// wallet's own cash accounts, how each one moves (rail, source unit, own
// recipient, settlement accounts), and which stops prove that nothing
// left (a fresh Retry is safe) versus a send whose outcome is unknown
// (the sheet locks and points at Activity).

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
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
        MoneyMovementRail.cctp,
        SettlementFlow.investingToPredictionsCctp,
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
        if (plan.rail == MoneyMovementRail.cctp) {
          // CCTP never goes through the settlement pair check: it pays
          // the wallet's own standing instruction (own Predictions
          // address, refund the own Investing account).
          expect(route.from, _i);
          expect(route.to, _p);
          return;
        }
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
}
