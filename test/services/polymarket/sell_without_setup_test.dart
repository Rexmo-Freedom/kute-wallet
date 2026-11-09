// A person could not sell a prediction on 2026-11-08, on a mobile connection
// where 85% of requests to every host timed out. Their first sell reached the
// POST and failed on the network; their second ended in the account's setup
// re-check with no order posted (polymarket_setup_failed and
// polymarket_sell_failed in the same millisecond, error_category "unknown").
// A sell of a position the account holds goes to the order book even when
// that re-check cannot finish, and the failures that did happen are
// classified by what they were.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/placement_waits.dart';
import 'package:kute/services/polymarket_onboarding_service.dart'
    show PolymarketReadException;
import 'package:kute/services/tracking_service.dart';

void main() {
  group('a sell whose setup re-check did not finish', () {
    const readFailedClosed =
        PolymarketReadException('eth_getCode: no Polygon RPC answered');

    test('goes to the venue when the deposit wallet is known', () {
      expect(
          polySellProceedsWithoutSetup(readFailedClosed,
              depositWallet: '0xdeposit'),
          isTrue);
      expect(
          polySellProceedsWithoutSetup(Exception('relayer busy'),
              depositWallet: '0xdeposit'),
          isTrue);
    });

    test('still waits for setup when the deposit wallet is not known', () {
      expect(
          polySellProceedsWithoutSetup(readFailedClosed, depositWallet: null),
          isFalse);
      expect(polySellProceedsWithoutSetup(readFailedClosed, depositWallet: ''),
          isFalse);
    });

    test('still ends on an account that changed under the order', () {
      expect(
          polySellProceedsWithoutSetup(
              StateError('Predictions account changed'),
              depositWallet: '0xdeposit'),
          isFalse);
    });
  });

  group('error categories of the sells that failed', () {
    test('every Polygon RPC failing one read is a network failure', () {
      expect(
          TrackingService.errorCategory(const PolymarketReadException(
              'eth_getCode: no Polygon RPC answered')),
          'network');
      expect(
          TrackingService.errorCategory(
              'PolymarketReadException: eth_call: no Polygon RPC answered'),
          'network');
    });

    test('an order killed for want of bids is no liquidity, not unknown',
        () {
      expect(
          TrackingService.errorCategory(
              "order couldn't be fully filled. FOK orders are fully filled or killed."),
          'no_route');
      expect(
          TrackingService.errorCategory(
              'no orders found to match with FAK order. FAK orders are partially filled or killed if no match is found.'),
          'no_route');
      expect(
          TrackingService.errorCategory(Exception(
              'No bids matched at this price. The book may be thin.')),
          'no_route');
    });
  });
}
