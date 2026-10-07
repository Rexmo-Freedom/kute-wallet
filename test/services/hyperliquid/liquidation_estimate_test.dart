import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/hyperliquid/liquidation_estimate.dart';

void main() {
  test('maintenance margin is half the initial margin at max leverage', () {
    expect(LiquidationEstimate.maintenanceFraction(50), closeTo(0.01, 1e-12));
    expect(LiquidationEstimate.maintenanceFraction(3), closeTo(1 / 6, 1e-12));
    expect(LiquidationEstimate.maintenanceFraction(0), closeTo(0.5, 1e-12));
  });

  test('an isolated long at 10x on a 50x market liquidates about 9% down',
      () {
    // Notional 1000 at 100, margin 100, maintenance 10 → margin available 90.
    // liq = 100 - 90 / 10 / (1 - 0.01) = 100 - 9.0909 = 90.909
    final liq = LiquidationEstimate.isolated(
        price: 100, size: 10, isLong: true, marginUsd: 100, maxLeverage: 50);
    expect(liq, closeTo(90.909, 0.001));
  });

  test('an isolated short at 10x liquidates about 9% up', () {
    // liq = 100 + 90 / 10 / (1 + 0.01) = 108.911
    final liq = LiquidationEstimate.isolated(
        price: 100, size: 10, isLong: false, marginUsd: 100, maxLeverage: 50);
    expect(liq, closeTo(108.911, 0.001));
  });

  test('a cross position uses the whole account equity', () {
    // Equity 500, other positions need 20, this one needs 10 → 470 available.
    // liq = 100 - 470 / 10 / 0.99 = 52.525
    final liq = LiquidationEstimate.cross(
        price: 100,
        size: 10,
        isLong: true,
        accountValue: 500,
        maintenanceMarginUsed: 20,
        maxLeverage: 50);
    expect(liq, closeTo(52.525, 0.001));
  });

  test('positions the formula cannot describe give no figure', () {
    expect(
        LiquidationEstimate.isolated(
            price: 0, size: 10, isLong: true, marginUsd: 100, maxLeverage: 50),
        isNull);
    // 1x long on a 50x market: margin 1000, maintenance 10 → liq below zero.
    expect(
        LiquidationEstimate.isolated(
            price: 100,
            size: 10,
            isLong: true,
            marginUsd: 1000,
            maxLeverage: 50),
        isNull);
    // Negative margin available would put a long's liquidation above entry.
    expect(
        LiquidationEstimate.cross(
            price: 100,
            size: 10,
            isLong: true,
            accountValue: 5,
            maintenanceMarginUsed: 20,
            maxLeverage: 50),
        isNull);
  });
}
