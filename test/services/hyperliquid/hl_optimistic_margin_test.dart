import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/hyperliquid/hl_optimistic_margin.dart';

void main() {
  final t0 = DateTime(2026, 10, 12, 12, 0, 0);

  test('an open fill locks margin and lowers withdrawable at once', () {
    final hold = HlOptimisticMargin.afterOpen(
        withdrawable: 100, totalMarginUsed: 20, marginUsd: 30, at: t0);
    expect(hold.withdrawable, 70);
    expect(hold.totalMarginUsed, 50);
    expect(hold.marginBefore, 20);
  });

  test('withdrawable never goes below zero on an open', () {
    final hold = HlOptimisticMargin.afterOpen(
        withdrawable: 10, totalMarginUsed: 0, marginUsd: 30, at: t0);
    expect(hold.withdrawable, 0);
    expect(hold.totalMarginUsed, 30);
  });

  test('a close fill releases margin and realises the PnL', () {
    final hold = HlOptimisticMargin.afterClose(
        withdrawable: 70,
        totalMarginUsed: 50,
        marginReleasedUsd: 30,
        realizedPnlUsd: -5,
        at: t0);
    expect(hold.withdrawable, 95);
    expect(hold.totalMarginUsed, 20);
  });

  test('the snapshot wins once the venue margin moved off the baseline', () {
    final hold = HlOptimisticMargin.afterOpen(
        withdrawable: 100, totalMarginUsed: 20, marginUsd: 30, at: t0);
    // Stale snapshot: margin still at the pre-fill 20 → keep the hold.
    expect(hold.reconciledBy(20, now: t0.add(const Duration(seconds: 2))),
        isFalse);
    // Venue indexed the fill (any movement counts, even a different size).
    expect(hold.reconciledBy(49.5, now: t0.add(const Duration(seconds: 2))),
        isTrue);
  });

  test('the hold expires after its TTL even if nothing moved', () {
    final hold = HlOptimisticMargin.afterOpen(
        withdrawable: 100, totalMarginUsed: 20, marginUsd: 30, at: t0);
    expect(
        hold.reconciledBy(20,
            now: t0.add(HlOptimisticMargin.ttl + const Duration(seconds: 1))),
        isTrue);
  });
}
