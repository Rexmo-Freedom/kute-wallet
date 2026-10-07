import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/hyperliquid/hypercore_cash.dart';

void main() {
  double fundedCost(double margin, int leverage, double slippagePct) {
    final slip = 1 + slippagePct / 100;
    return margin * slip + margin * leverage * slip * kHlOrderFeeCeiling;
  }

  test('a use-everything order leaves room for slippage and fees', () {
    for (final available in [1.0, 12.3456, 250.0, 9999.99]) {
      for (final leverage in [1, 5, 20]) {
        for (final slippage in [0.0, 1.0, 5.0]) {
          final margin = hypercoreMaxOrderUsd(
              availableUsd: available,
              leverage: leverage,
              slippagePct: slippage);
          expect(fundedCost(margin, leverage, slippage),
              lessThanOrEqualTo(available + 1e-9),
              reason: '$available at ${leverage}x, $slippage%');
          expect(fundedCost(margin + 0.02, leverage, slippage),
              greaterThan(available),
              reason: 'not needlessly small at $available');
        }
      }
    }
  });

  test('never rounds up past the balance', () {
    // 12.3456 printed with two decimals was 12.35, above the balance.
    final margin = hypercoreMaxOrderUsd(availableUsd: 12.3456, slippagePct: 0);
    expect(margin, lessThanOrEqualTo(12.34));
    expect(hypercoreMaxOrderUsd(availableUsd: 0), 0);
    expect(hypercoreMaxOrderUsd(availableUsd: double.nan), 0);
  });
}
