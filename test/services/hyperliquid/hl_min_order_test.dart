import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
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
}
