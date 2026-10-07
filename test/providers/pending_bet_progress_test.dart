import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';

void main() {
  PendingBetIntent intent() => const PendingBetIntent(
        tokenId: '111',
        amount: 5,
        slippagePct: 5,
        marketQuestion: 'Will it rain?',
        outcomeName: 'Yes',
        expectedPrice: 0.5,
      );

  test('a placement walks its stages and starts over on the next one', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(pendingPolymarketBetProvider.notifier);
    notifier.setIntent(intent());
    notifier.updateStatus(PendingBetStatus.placing);
    expect(container.read(pendingPolymarketBetProvider)!.stage,
        PendingBetStage.submitting);
    notifier.setStage(PendingBetStage.delayed);
    notifier.setStage(PendingBetStage.confirming);
    final mid = container.read(pendingPolymarketBetProvider)!;
    expect(mid.stage, PendingBetStage.confirming);
    expect(mid.status, PendingBetStatus.placing);
    notifier.updateStatus(PendingBetStatus.failed, errorMessage: 'x');
    notifier.updateStatus(PendingBetStatus.placing);
    expect(container.read(pendingPolymarketBetProvider)!.stage,
        PendingBetStage.submitting);
  });

  test('the venue\'s settlement replaces an echo for different shares', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(pendingPolymarketBetProvider.notifier);
    notifier.setIntent(intent());
    notifier.recordFill({
      'success': true,
      'status': 'matched',
      'makingAmount': '5',
      'takingAmount': '10',
    });
    notifier.recordSettlement(
        filledShares: 4, filledCost: null, orderedShares: 10);
    final got = container.read(pendingPolymarketBetProvider)!;
    expect(got.filledShares, 4);
    expect(got.filledCost, isNull);
    expect(got.orderedShares, 10);
    expect(got.venueAccepted, isTrue);
  });
}
