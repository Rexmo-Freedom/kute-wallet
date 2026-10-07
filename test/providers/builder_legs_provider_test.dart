// Unit tests for the portfolio Builder's draft-leg state
// (lib/screens/shared/portfolio_builder/builder_legs_provider.dart):
// add/toggle/remove mechanics, total math, outcome/side flips, and the
// USDC-only insufficient-balance gate the review CTA enforces.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/portfolio_builder/builder_legs_provider.dart';

PredictionBuilderLeg predLeg(String slug, {double amount = 0}) =>
    PredictionBuilderLeg(
      slug: slug,
      title: 'Market $slug',
      yesTokenId: 'yes-$slug',
      noTokenId: 'no-$slug',
      yesPrice: 0.6,
      noPrice: 0.4,
      amountUsd: amount,
    );

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  group('PredictionBuilderNotifier', () {
    test('toggle adds then removes the same market', () {
      final n = container.read(builderPredictionLegsProvider.notifier);
      expect(n.toggle(predLeg('a')), isTrue);
      expect(container.read(builderPredictionLegsProvider), hasLength(1));
      expect(n.contains('a'), isTrue);

      // Toggling the same market again removes it.
      expect(n.toggle(predLeg('a')), isFalse);
      expect(container.read(builderPredictionLegsProvider), isEmpty);
    });

    test('setAmount and total math', () {
      final n = container.read(builderPredictionLegsProvider.notifier);
      n.toggle(predLeg('a'));
      n.toggle(predLeg('b'));
      n.setAmount('a', 12.5);
      n.setAmount('b', 7.5);
      expect(container.read(builderPredictionTotalProvider), closeTo(20, 1e-9));

      // Editing one leg only touches that leg.
      n.setAmount('a', 2);
      expect(container.read(builderPredictionTotalProvider), closeTo(9.5, 1e-9));
      final legs = container.read(builderPredictionLegsProvider);
      expect(legs.firstWhere((l) => l.key == 'b').amountUsd, 7.5);
    });

    test('setOutcome flips the side and the leg resolves the right token', () {
      final n = container.read(builderPredictionLegsProvider.notifier);
      n.toggle(predLeg('a'));
      expect(container.read(builderPredictionLegsProvider).first.tokenId,
          'yes-a');
      n.setOutcome('a', 'No');
      final leg = container.read(builderPredictionLegsProvider).first;
      expect(leg.isNo, isTrue);
      expect(leg.tokenId, 'no-a');
      expect(leg.price, 0.4);
    });

    test('remove and removeAll drop only the named legs', () {
      final n = container.read(builderPredictionLegsProvider.notifier);
      n.toggle(predLeg('a'));
      n.toggle(predLeg('b'));
      n.toggle(predLeg('c'));
      n.remove('b');
      expect(container.read(builderPredictionLegsProvider).map((l) => l.key),
          ['a', 'c']);
      // The post-placement cleanup: successful legs leave, failed stay.
      n.removeAll(['c']);
      expect(container.read(builderPredictionLegsProvider).map((l) => l.key),
          ['a']);
    });
  });

  group('TradeBuilderNotifier', () {
    test('perp and spot legs of the same coin are distinct', () {
      final n = container.read(builderTradeLegsProvider.notifier);
      n.toggle(const TradeBuilderLeg(coin: 'BTC', isSpot: false));
      n.toggle(const TradeBuilderLeg(coin: 'BTC', isSpot: true));
      expect(container.read(builderTradeLegsProvider), hasLength(2));
    });

    test('setSide flips perps but never a spot leg (buy-only)', () {
      final n = container.read(builderTradeLegsProvider.notifier);
      n.toggle(const TradeBuilderLeg(coin: 'ETH', isSpot: false));
      n.toggle(const TradeBuilderLeg(coin: 'TSLA', isSpot: true));

      n.setSide('ETH|perp', false);
      n.setSide('TSLA|spot', false);

      final legs = container.read(builderTradeLegsProvider);
      expect(legs.firstWhere((l) => l.coin == 'ETH').isLong, isFalse);
      expect(legs.firstWhere((l) => l.coin == 'TSLA').isLong, isTrue);
    });

    test('total math tracks amount edits', () {
      final n = container.read(builderTradeLegsProvider.notifier);
      n.toggle(const TradeBuilderLeg(coin: 'BTC', isSpot: false));
      n.toggle(const TradeBuilderLeg(coin: 'TSLA', isSpot: true));
      n.setAmount('BTC|perp', 30);
      n.setAmount('TSLA|spot', 12.34);
      expect(container.read(builderTradeTotalProvider), closeTo(42.34, 1e-9));
    });
  });

  group('builderInsufficientBalance', () {
    test('blocks only when the total exceeds the pool balance', () {
      expect(
          builderInsufficientBalance(totalUsd: 50, availableUsd: 100), isFalse);
      expect(
          builderInsufficientBalance(totalUsd: 100, availableUsd: 100), isFalse);
      expect(
          builderInsufficientBalance(totalUsd: 100.01, availableUsd: 100),
          isTrue);
      // Float noise a hair above the balance must not block.
      expect(
          builderInsufficientBalance(
              totalUsd: 100.0000000001, availableUsd: 100),
          isFalse);
      expect(builderInsufficientBalance(totalUsd: 0, availableUsd: 0), isFalse);
    });
  });
}
