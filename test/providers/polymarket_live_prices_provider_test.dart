import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // LivePriceState — pure data class tests
  // ──────────────────────────────────────────────────────────────────────────
  group('LivePriceState', () {
    test('default state has empty maps', () {
      const state = LivePriceState();
      expect(state.prices, isEmpty);
      expect(state.previousPrices, isEmpty);
    });

    test('copyWithPrice adds first price without previous', () {
      const state = LivePriceState();
      final updated = state.copyWithPrice('token-1', 0.65);
      expect(updated.prices['token-1'], 0.65);
      expect(updated.previousPrices['token-1'], isNull);
    });

    test('copyWithPrice moves current to previous on update', () {
      const state = LivePriceState();
      final first = state.copyWithPrice('token-1', 0.65);
      final second = first.copyWithPrice('token-1', 0.70);
      expect(second.prices['token-1'], 0.70);
      expect(second.previousPrices['token-1'], 0.65);
    });

    test('copyWithPrice tracks multiple tokens independently', () {
      const state = LivePriceState();
      final s1 = state.copyWithPrice('a', 0.30);
      final s2 = s1.copyWithPrice('b', 0.80);
      final s3 = s2.copyWithPrice('a', 0.35);

      expect(s3.prices['a'], 0.35);
      expect(s3.prices['b'], 0.80);
      expect(s3.previousPrices['a'], 0.30);
      expect(s3.previousPrices['b'], isNull); // b was only set once
    });

    test('copyWithPrice chain preserves correct previous prices', () {
      const state = LivePriceState();
      final s1 = state.copyWithPrice('t', 0.10);
      final s2 = s1.copyWithPrice('t', 0.20);
      final s3 = s2.copyWithPrice('t', 0.30);

      // previous should always be the LAST price, not the initial
      expect(s3.prices['t'], 0.30);
      expect(s3.previousPrices['t'], 0.20);
    });

    test('copyWithPrice does not mutate original state', () {
      const state = LivePriceState();
      final updated = state.copyWithPrice('token', 0.5);
      expect(state.prices, isEmpty);
      expect(updated.prices['token'], 0.5);
    });

    test('copyWithPrice with zero price', () {
      const state = LivePriceState();
      final updated = state.copyWithPrice('token', 0.0);
      expect(updated.prices['token'], 0.0);
    });

    test('copyWithPrice with price at 1.0 boundary', () {
      const state = LivePriceState();
      final updated = state.copyWithPrice('token', 1.0);
      expect(updated.prices['token'], 1.0);
    });

    test('copyWithPrice with same price value', () {
      const state = LivePriceState();
      final s1 = state.copyWithPrice('t', 0.50);
      final s2 = s1.copyWithPrice('t', 0.50);
      expect(s2.prices['t'], 0.50);
      expect(s2.previousPrices['t'], 0.50);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // priceDirection — direction detection
  // ──────────────────────────────────────────────────────────────────────────
  group('LivePriceState.priceDirection', () {
    test('returns 0 for unknown token', () {
      const state = LivePriceState();
      expect(state.priceDirection('unknown'), 0);
    });

    test('returns 0 when only current price exists (no previous)', () {
      const state = LivePriceState();
      final updated = state.copyWithPrice('t', 0.5);
      expect(updated.priceDirection('t'), 0);
    });

    test('returns 1 when price went up', () {
      const state = LivePriceState();
      final s1 = state.copyWithPrice('t', 0.40);
      final s2 = s1.copyWithPrice('t', 0.60);
      expect(s2.priceDirection('t'), 1);
    });

    test('returns -1 when price went down', () {
      const state = LivePriceState();
      final s1 = state.copyWithPrice('t', 0.70);
      final s2 = s1.copyWithPrice('t', 0.30);
      expect(s2.priceDirection('t'), -1);
    });

    test('returns 0 when price unchanged', () {
      const state = LivePriceState();
      final s1 = state.copyWithPrice('t', 0.50);
      final s2 = s1.copyWithPrice('t', 0.50);
      expect(s2.priceDirection('t'), 0);
    });

    test('tiny price increase detected', () {
      const state = LivePriceState();
      final s1 = state.copyWithPrice('t', 0.500000);
      final s2 = s1.copyWithPrice('t', 0.500001);
      expect(s2.priceDirection('t'), 1);
    });

    test('tiny price decrease detected', () {
      const state = LivePriceState();
      final s1 = state.copyWithPrice('t', 0.500001);
      final s2 = s1.copyWithPrice('t', 0.500000);
      expect(s2.priceDirection('t'), -1);
    });

    test('direction for one token does not affect another', () {
      const state = LivePriceState();
      final s1 = state.copyWithPrice('a', 0.40);
      final s2 = s1.copyWithPrice('b', 0.80);
      final s3 = s2.copyWithPrice('a', 0.60); // a goes up

      expect(s3.priceDirection('a'), 1);
      expect(s3.priceDirection('b'), 0); // b has no previous
    });

    test('direction updates after each price change', () {
      const state = LivePriceState();
      final s1 = state.copyWithPrice('t', 0.30);
      final s2 = s1.copyWithPrice('t', 0.50); // up
      expect(s2.priceDirection('t'), 1);

      final s3 = s2.copyWithPrice('t', 0.40); // down
      expect(s3.priceDirection('t'), -1);

      final s4 = s3.copyWithPrice('t', 0.40); // same
      expect(s4.priceDirection('t'), 0);
    });

    test('price going from 0 to positive is up', () {
      const state = LivePriceState();
      final s1 = state.copyWithPrice('t', 0.0);
      final s2 = s1.copyWithPrice('t', 0.01);
      expect(s2.priceDirection('t'), 1);
    });

    test('price going from positive to 0 is down', () {
      const state = LivePriceState();
      final s1 = state.copyWithPrice('t', 0.5);
      final s2 = s1.copyWithPrice('t', 0.0);
      expect(s2.priceDirection('t'), -1);
    });

    test('price going to 1.0 from 0.99 is up', () {
      const state = LivePriceState();
      final s1 = state.copyWithPrice('t', 0.99);
      final s2 = s1.copyWithPrice('t', 1.0);
      expect(s2.priceDirection('t'), 1);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Multiple subscriptions state tracking
  // ──────────────────────────────────────────────────────────────────────────
  group('LivePriceState multi-token tracking', () {
    test('ten tokens tracked independently', () {
      var state = const LivePriceState();
      for (int i = 0; i < 10; i++) {
        state = state.copyWithPrice('token-$i', i * 0.1);
      }
      expect(state.prices.length, 10);
      expect(state.prices['token-0'], 0.0);
      expect(state.prices['token-9'], closeTo(0.9, 0.001));
    });

    test('updating one token does not lose others', () {
      var state = const LivePriceState();
      state = state.copyWithPrice('a', 0.1);
      state = state.copyWithPrice('b', 0.2);
      state = state.copyWithPrice('c', 0.3);
      state = state.copyWithPrice('a', 0.15); // update a

      expect(state.prices['a'], 0.15);
      expect(state.prices['b'], 0.2);
      expect(state.prices['c'], 0.3);
      expect(state.previousPrices['a'], 0.1);
    });

    test('empty token ID is a valid key', () {
      var state = const LivePriceState();
      state = state.copyWithPrice('', 0.5);
      expect(state.prices[''], 0.5);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Edge cases
  // ──────────────────────────────────────────────────────────────────────────
  group('LivePriceState edge cases', () {
    test('very large number of rapid updates', () {
      var state = const LivePriceState();
      for (int i = 0; i < 1000; i++) {
        state = state.copyWithPrice('t', i / 1000.0);
      }
      expect(state.prices['t'], closeTo(0.999, 0.001));
      expect(state.previousPrices['t'], closeTo(0.998, 0.001));
    });

    test('negative price is stored (validation happens elsewhere)', () {
      var state = const LivePriceState();
      state = state.copyWithPrice('t', -0.5);
      expect(state.prices['t'], -0.5);
    });

    test('price greater than 1 is stored (validation happens elsewhere)', () {
      var state = const LivePriceState();
      state = state.copyWithPrice('t', 1.5);
      expect(state.prices['t'], 1.5);
    });

    test('constructed with pre-filled prices', () {
      final state = LivePriceState(
        prices: {'a': 0.5, 'b': 0.7},
        previousPrices: {'a': 0.4},
      );
      expect(state.prices.length, 2);
      expect(state.previousPrices.length, 1);
      expect(state.priceDirection('a'), 1);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Price filtering logic (from the notifier — prices < 0 or > 1 are skipped)
  // ──────────────────────────────────────────────────────────────────────────
  group('Price validation logic (inline)', () {
    test('valid prices in 0..1 range pass filter', () {
      final prices = [0.0, 0.01, 0.5, 0.99, 1.0];
      final filtered = prices.where((p) => p >= 0 && p <= 1).toList();
      expect(filtered.length, 5);
    });

    test('negative prices are filtered out', () {
      final prices = [-0.1, -1.0, -0.001];
      final filtered = prices.where((p) => p >= 0 && p <= 1).toList();
      expect(filtered, isEmpty);
    });

    test('prices > 1 are filtered out', () {
      final prices = [1.001, 1.5, 100.0];
      final filtered = prices.where((p) => p >= 0 && p <= 1).toList();
      expect(filtered, isEmpty);
    });

    test('mixed valid and invalid prices', () {
      final prices = [-0.1, 0.0, 0.5, 1.0, 1.1];
      final filtered = prices.where((p) => p >= 0 && p <= 1).toList();
      expect(filtered, [0.0, 0.5, 1.0]);
    });
  });
}
