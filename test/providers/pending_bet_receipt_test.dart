import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';

void main() {
  test('receipt retains actual partial fill instead of the requested amount',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(pendingPolymarketBetProvider.notifier);
    notifier.setIntent(const PendingBetIntent(
        tokenId: 'token',
        amount: 10,
        slippagePct: 5,
        marketQuestion: 'Question',
        outcomeName: 'Yes',
        expectedPrice: .5));
    // Only a matched venue reply carries a fill (c087cd5d).
    notifier.recordFill({
      'success': true,
      'status': 'matched',
      'makingAmount': '4.2',
      'takingAmount': '8',
    });
    notifier.updateStatus(PendingBetStatus.done);
    final receipt = container.read(pendingPolymarketBetProvider)!;
    expect(receipt.filledCost, 4.2);
    expect(receipt.filledShares, 8);
    expect(receipt.amount, 10);
  });

  test('a reply that is not matched never records a fill', () {
    for (final status in [null, 'live', 'delayed', 'unmatched', 'failed']) {
      final container = ProviderContainer();
      final notifier = container.read(pendingPolymarketBetProvider.notifier);
      notifier.setIntent(const PendingBetIntent(
          tokenId: 'token',
          amount: 10,
          slippagePct: 5,
          marketQuestion: 'Question',
          outcomeName: 'Yes',
          expectedPrice: .5));
      notifier.recordFill({
        'success': true,
        'status': status,
        'makingAmount': '4.2',
        'takingAmount': '8',
      });
      final receipt = container.read(pendingPolymarketBetProvider)!;
      expect(receipt.filledCost, isNull, reason: '$status');
      expect(receipt.filledShares, isNull, reason: '$status');
      container.dispose();
    }
  });

  test('missing and invalid fills remain unknown, never a fabricated success',
      () {
    for (final value in [null, 'NaN', 'Infinity', '-2', '0', 'invalid']) {
      final container = ProviderContainer();
      final notifier = container.read(pendingPolymarketBetProvider.notifier);
      notifier.setIntent(const PendingBetIntent(
          tokenId: 'token',
          amount: 10,
          slippagePct: 5,
          marketQuestion: 'Question',
          outcomeName: 'Yes',
          expectedPrice: .5));
      notifier.recordFill({
        'success': true,
        'status': 'matched',
        'makingAmount': value,
        'takingAmount': value,
      });
      final receipt = container.read(pendingPolymarketBetProvider)!;
      expect(receipt.filledCost, isNull);
      expect(receipt.filledShares, isNull);
      container.dispose();
    }
  });
}
