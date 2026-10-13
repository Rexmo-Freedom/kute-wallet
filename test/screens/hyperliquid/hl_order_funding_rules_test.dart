// The slip's funding rules: what of the venue's cash a new order may
// count on, which markets refuse a funded order before money moves, when
// the first order's builder approval waits for the money, and the fresh
// spot-buy transfer.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart'
    show hlSpotBuyPerpTransferUsd;
import 'package:kute/screens/hyperliquid/components/hl_order_funding_rules.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart'
    show HyperliquidInsufficientMarginException;

HlSpotBalance _usdc(double available) =>
    HlSpotBalance(coin: 'USDC', total: available, hold: 0, entryNtl: 0);

void main() {
  group('hlSlipReadyUsd', () {
    test('perp withdrawable plus spot USDC', () {
      expect(hlSlipReadyUsd(withdrawableUsd: 8, spotUsdc: 2), 10);
    });

    test('a queued funded order keeps the money it moved (second order)', () {
      expect(
          hlSlipReadyUsd(
              withdrawableUsd: 20.5, spotUsdc: 0, queuedRequiredUsd: 20.24),
          closeTo(0.26, 1e-9));
      expect(
          hlSlipReadyUsd(withdrawableUsd: 5, spotUsdc: 0, queuedRequiredUsd: 20),
          0);
    });

    test('a sweep carrying the cash home leaves none of it for the order '
        '(close then reopen)', () {
      expect(
          hlSlipReadyUsd(withdrawableUsd: 30, spotUsdc: 1, sweeping: true), 0);
    });
  });

  group('hlFundedMarketBlock', () {
    test('an open-interest-capped perp refuses new exposure before funding',
        () {
      expect(
          hlFundedMarketBlock(
              isSpot: false, reduceOnly: false, oiCapped: true, listed: true),
          'oi_capped');
      // Reduce-only is an exit: never blocked by the cap.
      expect(
          hlFundedMarketBlock(
              isSpot: false, reduceOnly: true, oiCapped: true, listed: true),
          isNull);
    });

    test('a market gone from the list (delisted, halted) takes nothing', () {
      expect(
          hlFundedMarketBlock(
              isSpot: true, reduceOnly: false, oiCapped: false, listed: false),
          'market_unavailable');
      // An unreadable list never blocks: the venue answers at the order.
      expect(
          hlFundedMarketBlock(
              isSpot: false, reduceOnly: false, oiCapped: false, listed: null),
          isNull);
    });
  });

  test('the first order on an unfunded account defers the builder approval',
      () {
    expect(hlDeferBuilderApproval(accountUnfunded: true, shortfallUsd: 10),
        isTrue);
    expect(hlDeferBuilderApproval(accountUnfunded: false, shortfallUsd: 10),
        isFalse);
    expect(hlDeferBuilderApproval(accountUnfunded: true, shortfallUsd: 0),
        isFalse);
  });

  group('hlSpotBuyPerpTransferUsd (from a fresh read)', () {
    test('spot covers it: no transfer', () {
      expect(
          hlSpotBuyPerpTransferUsd(
              usd: 10, spotBalances: [_usdc(12)], perpWithdrawable: 0),
          0);
    });

    test('funded cash credited to perps moves across, to the cent', () {
      // The money a Dollars move just landed: perps hold it, spot does not.
      expect(
          hlSpotBuyPerpTransferUsd(
              usd: 10, spotBalances: [_usdc(0.004)], perpWithdrawable: 10.5),
          10.0);
    });

    test('neither covers it: refused before anything is signed', () {
      expect(
          () => hlSpotBuyPerpTransferUsd(
              usd: 10, spotBalances: const [], perpWithdrawable: 3),
          throwsA(isA<HyperliquidInsufficientMarginException>()));
    });
  });
}
