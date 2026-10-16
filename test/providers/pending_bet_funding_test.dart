// A bet queued behind its own funding leg: what the intent carries, when
// it is too old to fire, and what a market or limit bet is placed for
// when the deposit lands short.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/pending_bet_autofire.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';

void main() {
  PendingBetIntent intent({bool isLimit = false}) => PendingBetIntent(
        tokenId: '111',
        amount: 10,
        slippagePct: 5,
        marketQuestion: 'Will it rain?',
        outcomeName: 'Yes',
        expectedPrice: 0.5,
        isLimit: isLimit,
        limitPrice: isLimit ? 0.5 : 0,
      );

  group('a funded intent', () {
    test('an old same-market attempt cannot bind its graph to a new intent',
        () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final notifier = c.read(pendingPolymarketBetProvider.notifier);
      final old = intent().copyWith(fundUsd: 5, queuedAt: DateTime.utc(2026));
      notifier.setIntent(old);
      final replacement = old.copyWith(amount: 8);
      notifier.setIntent(replacement);
      expect(notifier.bindFundingRun(old, 'old_run'), isFalse);
      expect(
          identical(c.read(pendingPolymarketBetProvider), replacement), isTrue);
      expect(notifier.bindFundingRun(replacement, 'new_run'), isTrue);
      notifier.recordSettlement(
          filledShares: 2, filledCost: 1, orderedShares: 2);
      expect(c.read(pendingPolymarketBetProvider)!.fundedRunId, 'new_run');
    });
    test('keeps its funding through status changes and settlement', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(pendingPolymarketBetProvider.notifier);
      final at = DateTime.utc(2026, 10, 12, 12);
      notifier.setIntent(intent().copyWith(
          status: PendingBetStatus.awaitingBalance, fundUsd: 5.3, queuedAt: at));
      var got = container.read(pendingPolymarketBetProvider)!;
      expect(got.funded, isTrue);
      expect(got.fundUsd, 5.3);
      expect(got.queuedAt, at);
      expect(got.fundQuoteRef, isNull);
      notifier.recordFunding(quoteRef: 'ref_abc');
      notifier.updateStatus(PendingBetStatus.placing);
      notifier.recordSettlement(
          filledShares: 4, filledCost: 2, orderedShares: 10);
      got = container.read(pendingPolymarketBetProvider)!;
      expect(got.fundUsd, 5.3);
      expect(got.fundQuoteRef, 'ref_abc');
      expect(got.queuedAt, at);
      expect(got.status, PendingBetStatus.placing);
      expect(intent().funded, isFalse);
    });

    test('is stale after 30 minutes, never without a queue time', () {
      final at = DateTime.utc(2026, 10, 12, 12);
      final queued = intent().copyWith(fundUsd: 5, queuedAt: at);
      expect(queued.isStale(now: at.add(const Duration(minutes: 29))),
          isFalse);
      expect(queued.isStale(now: at.add(const Duration(minutes: 31))),
          isTrue);
      expect(PendingBetIntent.maxQueuedAge, const Duration(minutes: 30));
      expect(intent().isStale(now: at.add(const Duration(days: 1))), isFalse);
    });
  });

  test('the funds timeout is the existing 12 minutes', () {
    expect(kFundsTimeout, const Duration(minutes: 12));
  });

  group('landedStakeFor', () {
    const terms = PolymarketFeeTerms.worstCase;

    test('a market bet whose deposit covers it is placed as typed', () {
      final r = landedStakeFor(
          amount: 10, balance: 12, feeTerms: terms, price: 0.5, isLimit: false)!;
      expect(r.usd, 10);
      expect(r.resized, isFalse);
    });

    test('a market bet that landed short shrinks to what fits with fees',
        () {
      final r = landedStakeFor(
          amount: 10, balance: 8, feeTerms: terms, price: 0.5, isLimit: false)!;
      expect(r.resized, isTrue);
      expect(r.usd, lessThan(8));
      expect(r.usd, greaterThanOrEqualTo(1));
      expect(terms.allInCost(r.usd, 0.5), lessThanOrEqualTo(8 + 1e-6));
    });

    test('under the venue minimum the bet fails instead', () {
      expect(
          landedStakeFor(
              amount: 10,
              balance: 0.8,
              feeTerms: terms,
              price: 0.5,
              isLimit: false),
          isNull);
      expect(
          landedStakeFor(
              amount: 0, balance: 10, feeTerms: terms, price: 0.5, isLimit: false),
          isNull);
    });

    test('a limit bet never resizes: short is short', () {
      final full = landedStakeFor(
          amount: 10, balance: 10.2, feeTerms: terms, price: 0.5, isLimit: true)!;
      expect(full.usd, 10);
      expect(full.resized, isFalse);
      expect(
          landedStakeFor(
              amount: 10, balance: 9, feeTerms: terms, price: 0.5, isLimit: true),
          isNull);
    });
  });
}
