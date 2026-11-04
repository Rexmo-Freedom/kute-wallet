import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart'
    show hlMarketCloseSize;
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart'
    show HyperliquidMinNotionalException;
import 'package:kute/services/hyperliquid/hyperliquid_rounding.dart';

/// The notional the venue checks for the order the slip would send for
/// [amount]: the hot submit path's size (floored at the reference) times
/// the IOC's wire price (slippage through the book).
double _sentNotional({
  required double amount,
  required double px,
  required int szDecimals,
  required int leverage,
  required bool isBuy,
  double slippage = 0.01,
}) {
  final size =
      sizeFromUsd(usd: amount * leverage, px: px, szDecimals: szDecimals);
  final wire = double.parse(slippagePrice(
      referencePx: px,
      isBuy: isBuy,
      slippage: slippage,
      szDecimals: szDecimals,
      isSpot: false));
  return size * wire;
}

double _minFor({
  required double px,
  required int szDecimals,
  required int leverage,
  required bool isBuy,
  double slippage = 0.01,
}) =>
    hlMinOrderAmountUsd(
      referencePx: px,
      checkPx: hlMinCheckPx(
          referencePx: px,
          isBuy: isBuy,
          slippage: slippage,
          szDecimals: szDecimals,
          isSpot: false),
      szDecimals: szDecimals,
      leverage: leverage,
    );

void main() {
  group('the slip minimum clears the venue minimum as sent', () {
    // A coin near two dollars traded in whole units: the owner's short
    // prefilled 10.08 and the order went out at 9.98.
    const px = 2.016;
    const szDecimals = 0;

    test('the old mid-only minimum was refused for a short', () {
      final old = minUsdForFlooredSize(
          px: px, szDecimals: szDecimals, minNotionalUsd: 10);
      expect(old, closeTo(10.08, 1e-9));
      expect(
          _sentNotional(
              amount: old,
              px: px,
              szDecimals: szDecimals,
              leverage: 1,
              isBuy: false),
          lessThan(10));
    });

    for (final isBuy in [false, true]) {
      for (final lev in [1, 3]) {
        test('${isBuy ? 'long' : 'short'} at ${lev}x', () {
          final min = _minFor(
              px: px, szDecimals: szDecimals, leverage: lev, isBuy: isBuy);
          expect(
              _sentNotional(
                  amount: min,
                  px: px,
                  szDecimals: szDecimals,
                  leverage: lev,
                  isBuy: isBuy),
              greaterThanOrEqualTo(10));
          // Still survives the price moving a little against it.
          final moved = isBuy ? px * 1.002 : px * 0.998;
          expect(
              _sentNotional(
                  amount: min,
                  px: moved,
                  szDecimals: szDecimals,
                  leverage: lev,
                  isBuy: isBuy),
              greaterThanOrEqualTo(10));
          // And is not wildly more than it needs: within a step and the
          // buffer of the venue minimum.
          expect(min * lev, lessThan((10 * 1.005 / 0.99 + px) * 1.01 + 0.03));
        });
      }
    }

    test('holds across prices, steps and leverage', () {
      final rnd = math.Random(7);
      for (var i = 0; i < 2000; i++) {
        final szDecimals = rnd.nextInt(6);
        final px = math.pow(10, rnd.nextDouble() * 6 - 1).toDouble();
        // The venue's step must be worth less than a few minimums.
        if (px * math.pow(10, -szDecimals) > 25) continue;
        final lev = 1 + rnd.nextInt(20);
        final isBuy = rnd.nextBool();
        final min =
            _minFor(px: px, szDecimals: szDecimals, leverage: lev, isBuy: isBuy);
        expect(
            _sentNotional(
                amount: min,
                px: px,
                szDecimals: szDecimals,
                leverage: lev,
                isBuy: isBuy),
            greaterThanOrEqualTo(10),
            reason: 'px $px sz $szDecimals ${lev}x buy $isBuy -> $min');
      }
    });
  });

  test('a buy is checked at the reference, a sell at its slippage price', () {
    expect(
        hlMinCheckPx(
            referencePx: 100,
            isBuy: true,
            slippage: 0.01,
            szDecimals: 2,
            isSpot: false),
        100);
    expect(
        hlMinCheckPx(
            referencePx: 100,
            isBuy: false,
            slippage: 0.01,
            szDecimals: 2,
            isSpot: false),
        99);
    expect(
        hlCheckedNotionalUsd(
            amountUsd: 10.08,
            referencePx: 2.016,
            checkPx: 1.9958,
            szDecimals: 0),
        closeTo(9.979, 1e-9));
  });

  test('a flip\'s minimum covers the held position plus a minimum past it',
      () {
    const px = 60000.0;
    const held = 0.01;
    final checkPx = hlMinCheckPx(
        referencePx: px,
        isBuy: false,
        slippage: 0.01,
        szDecimals: 5,
        isSpot: false);
    final min = hlMinOrderAmountUsd(
        referencePx: px, checkPx: checkPx, szDecimals: 5, baseSize: held);
    final size = sizeFromUsd(usd: min, px: px, szDecimals: 5);
    expect((size - held) * checkPx, greaterThanOrEqualTo(10));
    expect(min, lessThan(held * px * 1.005 + 12));
  });

  // OPENAI (io:OAI, a HIP-3 perp) near 1,405.2 a coin. Its step is 0.001
  // (1.40 a step): the founder's $10 and $11 closes were both refused
  // with "minimum is $10", which only a 0.001 step does ($11 clears at a
  // 0.0001 step, and a 0.01 step floors $10 to nothing at all).
  group('a partial close on OPENAI clears the venue minimum', () {
    const px = 1405.2;
    const szDecimals = 3;
    // A long of 0.05 OAI (about $70): the close is a sell.
    const held = 0.05;
    final checkPx = hlMinCheckPx(
        referencePx: px,
        isBuy: false,
        slippage: 0.01,
        szDecimals: szDecimals,
        isSpot: false);
    // What the close sheet hands on for a typed figure: its coin size
    // (six decimals) at the mark.
    double typed(double usd) =>
        double.parse((usd / px).toStringAsFixed(6));

    test('the old floored close of \$10 and \$11 went out under \$10',
        () {
      for (final usd in [10.0, 11.0]) {
        final old = flooredSize(typed(usd), szDecimals);
        expect(old, 0.007, reason: '\$$usd');
        expect(meetsMinNotional(px: checkPx, sz: old), isFalse,
            reason: '\$$usd went out at ${old * checkPx}');
      }
    });

    test('\$10 and \$11 now go out at the first step that clears it', () {
      for (final usd in [10.0, 11.0]) {
        final size = hlPartialCloseSize(
            requestedSz: typed(usd),
            positionSz: held,
            referencePx: px,
            checkPx: checkPx,
            szDecimals: szDecimals);
        expect(size, 0.008, reason: '\$$usd');
        expect(size * checkPx,
            greaterThanOrEqualTo(10 * (1 + hlMinNotionalBuffer)));
        // A whole step: the wire size is exact.
        expect(roundSize(size, szDecimals), '0.008');
        expect(size, lessThan(held));
      }
    });

    test('a close that already clears it is sent as asked', () {
      final size = hlPartialCloseSize(
          requestedSz: typed(30),
          positionSz: held,
          referencePx: px,
          checkPx: checkPx,
          szDecimals: szDecimals);
      expect(size, flooredSize(typed(30), szDecimals));
    });

    test('below the minimum is only floored (the caller refuses it)', () {
      final size = hlPartialCloseSize(
          requestedSz: typed(5),
          positionSz: held,
          referencePx: px,
          checkPx: checkPx,
          szDecimals: szDecimals);
      expect(size, 0.003);
    });

    test('rounding up to the whole position closes it exactly', () {
      // A $12 position: the step that clears $10 at the sell price is
      // the whole of it.
      const small = 0.008;
      expect(
          hlPartialCloseSize(
              requestedSz: typed(10),
              positionSz: small,
              referencePx: px,
              checkPx: checkPx,
              szDecimals: szDecimals),
          small);
    });

    test('holds at a 0.0001 step and for a short (a buy) too', () {
      for (final d in [3, 4]) {
        for (final isBuy in [false, true]) {
          final cpx = hlMinCheckPx(
              referencePx: px,
              isBuy: isBuy,
              slippage: 0.01,
              szDecimals: d,
              isSpot: false);
          for (var usd = 10.0; usd <= 20; usd += 0.37) {
            final size = hlPartialCloseSize(
                requestedSz: usd / px,
                positionSz: 1,
                referencePx: px,
                checkPx: cpx,
                szDecimals: d);
            expect(meetsMinNotional(px: cpx, sz: size), isTrue,
                reason: 'd=$d buy=$isBuy \$$usd');
            // Never more than a step past what was asked, on top of the
            // venue's own pricing.
            expect(size * px,
                lessThan(math.max(usd, 10 * 1.02) + math.pow(10, -d) * px));
          }
        }
      }
    });

    const market = HlMarket(
      coin: 'OAI',
      wireCoin: 'io:OAI',
      assetId: 110000,
      kind: HlMarketKind.perp,
      szDecimals: szDecimals,
      maxLeverage: 20,
      onlyIsolated: false,
      markPx: px,
      midPx: px,
      prevDayPx: px,
      dayNtlVlm: 0,
      dex: 'io',
      isHip3: true,
    );
    const position = HlPerpPosition(
      coin: 'io:OAI',
      szi: held,
      entryPx: 1400,
      positionValue: held * px,
      unrealizedPnl: 0,
      returnOnEquity: 0,
      liquidationPx: 1000,
      marginUsed: 3.5,
      leverageType: 'isolated',
      leverageValue: 20,
      maxLeverage: 20,
      fundingSinceOpen: 0,
    );

    test('the close path sends \$10 at a size the venue takes', () {
      final size = hlMarketCloseSize(
          position: position,
          fraction: typed(10) / held,
          market: market,
          referencePx: px);
      expect(size, 0.008);
      expect(
          hlMarketCloseSize(
              position: position, fraction: 1, market: market, referencePx: px),
          held);
    });

    test('a close asked below the minimum is refused before signing', () {
      expect(
          () => hlMarketCloseSize(
              position: position,
              fraction: typed(5) / held,
              market: market,
              referencePx: px),
          throwsA(isA<HyperliquidMinNotionalException>()
              .having((e) => e.minimumUsd, 'minimumUsd', 10)));
    });
  });
}
