// The dollar send's Review estimate: a refusal is read for what it is (an
// amount the route will not take, a route that is off, a passing failure)
// and the route's own minimum is read from its limits, so Review never
// shows "route unavailable" as the fee and venue cash never starts home
// for a send its route would refuse.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/orchestra_usd_send_routes.dart';

const _btc = UsdSendDestination(
  assetCode: 'BTC',
  displayName: 'Bitcoin',
  displaySymbol: 'BTC',
  chain: 'bitcoin',
  chainDisplayName: 'Bitcoin',
  decimals: 8,
);

void main() {
  group('usdSendEstimateIssue', () {
    test('an amount the route will not take blocks the send', () {
      expect(
          usdSendEstimateIssue(errorCode: 'amount_too_small', statusCode: 400),
          UsdSendEstimateIssue.belowMinimum);
      expect(
          usdSendEstimateIssue(errorCode: 'amount_too_large', statusCode: 400),
          UsdSendEstimateIssue.aboveMaximum);
      expect(
          usdSendEstimateIssue(
              errorCode: 'amount_exceeds_liquidity', statusCode: 400),
          UsdSendEstimateIssue.liquidity);
      for (final issue in [
        UsdSendEstimateIssue.belowMinimum,
        UsdSendEstimateIssue.aboveMaximum,
        UsdSendEstimateIssue.liquidity,
      ]) {
        expect(issue.blocksSend, isTrue, reason: issue.name);
      }
    });

    test('a route refused or withheld blocks the send', () {
      expect(
          usdSendEstimateIssue(errorCode: 'route_unavailable', statusCode: 400),
          UsdSendEstimateIssue.unavailable);
      expect(
          usdSendEstimateIssue(errorCode: 'unsupported_route', statusCode: 400),
          UsdSendEstimateIssue.unavailable);
      expect(usdSendEstimateIssue(statusCode: 403, policyRefusal: true),
          UsdSendEstimateIssue.restricted);
      expect(UsdSendEstimateIssue.unavailable.blocksSend, isTrue);
      expect(UsdSendEstimateIssue.restricted.blocksSend, isTrue);
    });

    test('no answer, a timeout, a 429 or a 5xx is passing: never a block', () {
      for (final status in [null, 408, 429, 500, 502, 503]) {
        final issue = usdSendEstimateIssue(statusCode: status);
        expect(issue, UsdSendEstimateIssue.transient, reason: '$status');
        expect(issue.blocksSend, isFalse);
      }
    });

    test('another refusal leaves the price unknown and the send to its quote',
        () {
      final issue =
          usdSendEstimateIssue(errorCode: 'bad_request', statusCode: 400);
      expect(issue, UsdSendEstimateIssue.unknown);
      expect(issue.blocksSend, isFalse);
    });
  });

  group('usdSendRouteMinimumUnits', () {
    final key = usdSendRouteKey(_btc);

    test('the send is quoted on the dollar balance to the picked coin', () {
      expect(key.fromChain, 'spark');
      expect(key.fromAsset, 'USDB');
      expect(key.toChain, 'bitcoin');
      expect(key.toAsset, 'BTC');
    });

    test('the largest of the exact-in and order minimums, in base units', () {
      final limits = OrchestraRouteLimits.fromLimitsJson({
        'orderNotionalUsd': {'minCents': 2000},
        'exactIn': {
          'requestAmount': {
            'chain': 'spark',
            'asset': 'USDB',
            'minAmountSmallest': '25000000',
            'minUsdCents': 2400,
          },
        },
      }, key);
      expect(usdSendRouteMinimumUnits(limits), BigInt.from(25000000));
    });

    test('USD cents alone are read as base units (a cent is 10,000)', () {
      final limits = OrchestraRouteLimits.fromLimitsJson({
        'orderNotionalUsd': {'minCents': 1550},
      }, key);
      expect(usdSendRouteMinimumUnits(limits), BigInt.from(15500000));
    });

    test('no limits, or limits that name no minimum: none', () {
      expect(usdSendRouteMinimumUnits(null), isNull);
      final limits = OrchestraRouteLimits.fromLimitsJson({
        'exactIn': {'supported': true},
      }, key);
      expect(usdSendRouteMinimumUnits(limits), isNull);
    });
  });

  test('the route key matches the catalog spelling of USDC.e', () {
    const usdce = UsdSendDestination(
      assetCode: 'USDC.E',
      displayName: 'USDC.e',
      displaySymbol: 'USDC.e',
      chain: 'polygon',
      chainDisplayName: 'Polygon',
      decimals: 6,
    );
    expect(
        usdSendRouteKey(usdce),
        RouteKey(
            fromChain: 'spark',
            fromAsset: 'USDB',
            toChain: 'polygon',
            toAsset: 'USDC.e'));
  });
}
