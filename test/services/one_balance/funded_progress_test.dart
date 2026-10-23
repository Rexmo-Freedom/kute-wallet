// A funded order's staged progress, whatever funds it (founder, 14 October
// 2026: "regardless of what is happening on the prediction we should
// always show that progress"): Bitcoin, Dollars, the other venue's cash.
// The record starts the moment the person approves, follows the venue's
// autofire to the end, and a stop keeps its failed step with where the
// money is now.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/pending_bet_autofire.dart'
    show autofireRoundClosed;
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/screens/shared/rubber_band_progress.dart';
import 'package:kute/screens/shared/slip_shortfall.dart' show fundedStopLine;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/polymarket/bet_prefund.dart';

const _bet = FundedOrderLabel(
  venue: OneBalanceVenue.predictions,
  orderUsd: 5,
  side: 'Up',
  market: 'Bitcoin Up or Down',
  marketKey: 'tok',
);

const _order = FundedOrderLabel(
  venue: OneBalanceVenue.investing,
  orderUsd: 20,
  side: 'Long',
  market: 'BTC',
  marketKey: 'BTC',
);

PendingBetIntent _intent({DateTime? endAt, String question = 'Bitcoin Up or Down - 5 minutes'}) =>
    PendingBetIntent(
      tokenId: 'tok',
      amount: 5,
      slippagePct: 10,
      marketQuestion: question,
      outcomeName: 'Up',
      expectedPrice: 0.5,
      marketEndAt: endAt,
      fundUsd: 5.2,
      status: PendingBetStatus.awaitingDeposit,
    );

FundedOrderRecord _record(FundedOrderStage stage,
        {FundedOrderLabel label = _bet,
        double addUsd = 0,
        FundedOrderStage? stoppedAt,
        FundedMoneyAt? moneyAt,
        String? reason,
        String? message,
        DateTime? at}) =>
    FundedOrderRecord(
      id: 'fo_1',
      label: label,
      stage: stage,
      createdAt: at ?? DateTime.now(),
      updatedAt: at ?? DateTime.now(),
      addUsd: addUsd,
      stoppedAt: stoppedAt,
      moneyAt: moneyAt,
      reason: reason,
      message: message,
    );

String _money(double usd) => '\$${usd.toStringAsFixed(2)}';

void main() {
  setUp(() => FundedOrdersNotifier.persist = false);
  tearDown(() => FundedOrdersNotifier.persist = true);

  group('the steps a funded order shows', () {
    test('Dollars or the other venue\'s cash: the move, then the bet', () {
      final preparing = FundedProgress(_record(FundedOrderStage.preparing));
      expect(preparing.stepCount, 2);
      expect(preparing.active, 0);
      expect(preparing.failed, isFalse);
      final placing = FundedProgress(_record(FundedOrderStage.placing));
      expect(placing.active, 1);
      final done = FundedProgress(_record(FundedOrderStage.done));
      expect(done.done, isTrue);
      expect(done.active, 2);
    });

    test('with a Bitcoin leg: adding, the move, the bet', () {
      FundedProgress at(FundedOrderStage s) =>
          FundedProgress(_record(s, addUsd: 6));
      expect(at(FundedOrderStage.adding).stepCount, 3);
      expect(at(FundedOrderStage.adding).active, 0);
      expect(at(FundedOrderStage.preparing).active, 1);
      expect(at(FundedOrderStage.placing).active, 2);
    });

    test('the tension rises with every step, fastest at the end', () {
      for (final addUsd in [0.0, 6.0]) {
        final stages = [
          if (addUsd > 0) FundedOrderStage.adding,
          FundedOrderStage.preparing,
          FundedOrderStage.placing,
        ];
        final stretch = [
          for (final s in stages)
            rubberBandStretchFor(
                FundedProgress(_record(s, addUsd: addUsd)).progress),
        ];
        for (var i = 1; i < stretch.length; i++) {
          expect(stretch[i], greaterThan(stretch[i - 1]));
        }
        expect(stretch.last - stretch[stretch.length - 2],
            greaterThan(stretch[1] - stretch[0] - 1e-9));
        expect(FundedProgress(_record(FundedOrderStage.done)).progress, 1);
      }
    });

    test('a stop marks the step it was on as failed', () {
      final stopped = FundedProgress(_record(FundedOrderStage.failed,
          stoppedAt: FundedOrderStage.placing,
          moneyAt: FundedMoneyAt.venue,
          reason: 'price_moved'));
      expect(stopped.failed, isTrue);
      expect(stopped.active, 1);
      final early = FundedProgress(_record(FundedOrderStage.failed,
          stoppedAt: FundedOrderStage.preparing,
          moneyAt: FundedMoneyAt.investments));
      expect(early.active, 0);
    });
  });

  group('the records', () {
    test('a stop keeps where it was, where the money is and what was said',
        () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final orders = c.read(fundedOrdersProvider.notifier);
      final id = orders.start(_bet, stage: FundedOrderStage.preparing);
      orders.setStage(id, FundedOrderStage.placing);
      orders.stop(id,
          stage: FundedOrderStage.failed,
          reason: 'price_moved',
          moneyAt: FundedMoneyAt.venue,
          message: 'moved');
      final r = orders.byId(id)!;
      expect(r.stage, FundedOrderStage.failed);
      expect(r.stoppedAt, FundedOrderStage.placing);
      expect(r.moneyAt, FundedMoneyAt.venue);
      expect(r.message, 'moved');
      // Ended records keep their end.
      orders.stop(id, stage: FundedOrderStage.ready, reason: 'late');
      expect(orders.byId(id)!.reason, 'price_moved');
      final back = FundedOrderRecord.fromJson(r.toJson())!;
      expect(back.stoppedAt, FundedOrderStage.placing);
      expect(back.moneyAt, FundedMoneyAt.venue);
      expect(back.message, 'moved');
      expect(back.cleared, isFalse);
    });

    test('the slip shows a run, a stop until a new try, a placed one briefly',
        () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final orders = c.read(fundedOrdersProvider.notifier);
      FundedProgress? shown() => FundedOrdersNotifier.progressOn(
          c.read(fundedOrdersProvider),
          OneBalanceVenue.predictions,
          'tok',
          DateTime.now());
      final id = orders.start(_bet, stage: FundedOrderStage.preparing);
      expect(shown()!.active, 0);
      // Another market's slip shows nothing.
      expect(
          FundedOrdersNotifier.progressOn(c.read(fundedOrdersProvider),
              OneBalanceVenue.predictions, 'other', DateTime.now()),
          isNull);
      orders.stop(id,
          stage: FundedOrderStage.failed,
          reason: 'market_closed',
          moneyAt: FundedMoneyAt.venue);
      expect(shown()!.failed, isTrue);
      // Long after: gone.
      expect(
          FundedOrdersNotifier.progressOn(
              c.read(fundedOrdersProvider),
              OneBalanceVenue.predictions,
              'tok',
              DateTime.now().add(const Duration(hours: 1))),
          isNull);
      // A new try on the market clears it.
      final next = orders.start(_bet, stage: FundedOrderStage.preparing);
      expect(orders.byId(id)!.cleared, isTrue);
      expect(shown()!.record.id, next);
      orders.setStage(next, FundedOrderStage.done);
      expect(shown()!.done, isTrue);
      expect(
          FundedOrdersNotifier.progressOn(
              c.read(fundedOrdersProvider),
              OneBalanceVenue.predictions,
              'tok',
              DateTime.now().add(const Duration(seconds: 10))),
          isNull);
    });

    test('a stop is cleared by hand (a direct retry)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final orders = c.read(fundedOrdersProvider.notifier);
      final id = orders.start(_bet, stage: FundedOrderStage.placing);
      orders.stop(id, stage: FundedOrderStage.failed, reason: 'placement');
      orders.clearStop(id);
      expect(
          FundedOrdersNotifier.progressOn(c.read(fundedOrdersProvider),
              OneBalanceVenue.predictions, 'tok', DateTime.now()),
          isNull);
    });
  });

  group('the runner follows a Dollars- or venue-funded bet', () {
    late ProviderContainer c;
    late BitcoinFundedOrderRunner runner;
    setUp(() {
      c = ProviderContainer();
      runner = c.read(bitcoinFundedOrderRunnerProvider);
    });
    tearDown(() => c.dispose());

    FundedOrderRecord rec(String id) =>
        c.read(fundedOrdersProvider.notifier).byId(id)!;

    test('approved: the steps start at once, before any money moves', () {
      final id = runner.beginFunded(_bet);
      expect(rec(id).stage, FundedOrderStage.preparing);
      expect(FundedOrdersNotifier.activeOf(
              c.read(fundedOrdersProvider), OneBalanceVenue.predictions)!
          .id, id);
    });

    test('the credit, then the venue refuses for the price: the failed step '
        'and the money in Predictions', () async {
      final pending = c.read(pendingPolymarketBetProvider.notifier);
      pending.setIntent(_intent());
      final id = runner.beginFunded(_bet);
      runner.followFunded(id, rowIds: {'q1'});
      expect(rec(id).venueRowIds, {'q1'});
      pending.updateStatus(PendingBetStatus.awaitingBalance);
      await Future<void>.delayed(Duration.zero);
      expect(rec(id).stage, FundedOrderStage.preparing);
      pending.updateStatus(PendingBetStatus.placing);
      await Future<void>.delayed(Duration.zero);
      expect(rec(id).stage, FundedOrderStage.placing);
      pending.updateStatus(PendingBetStatus.failed,
          errorMessage: 'The price moved', failureCode: 'price_moved');
      await Future<void>.delayed(Duration.zero);
      final r = rec(id);
      expect(r.stage, FundedOrderStage.failed);
      expect(r.stoppedAt, FundedOrderStage.placing);
      expect(r.reason, 'price_moved');
      expect(r.moneyAt, FundedMoneyAt.venue);
      expect(r.message, 'The price moved');
    });

    test('placed: done', () async {
      final pending = c.read(pendingPolymarketBetProvider.notifier);
      pending.setIntent(_intent());
      final id = runner.beginFunded(_bet);
      runner.followFunded(id);
      pending.updateStatus(PendingBetStatus.placing);
      pending.updateStatus(PendingBetStatus.done);
      await Future<void>.delayed(Duration.zero);
      expect(rec(id).stage, FundedOrderStage.done);
    });

    test('refused before the money left: the move step, in Investments', () {
      final id = runner.beginFunded(_bet);
      runner.stopFunded(id, reason: 'venue_refused', message: 'No route');
      final r = rec(id);
      expect(r.stage, FundedOrderStage.failed);
      expect(r.stoppedAt, FundedOrderStage.preparing);
      expect(r.moneyAt, FundedMoneyAt.investments);
    });

    test('declined after all: forgotten', () {
      final id = runner.beginFunded(_bet);
      runner.dropFunded(id);
      expect(c.read(fundedOrdersProvider.notifier).byId(id), isNull);
    });
  });

  group('the line under a stop says what happened and where the money is',
      () {
    final l10n = l10nForLanguage('en');
    test('price moved: in Predictions', () {
      expect(
          fundedStopLine(
              l10n,
              _record(FundedOrderStage.failed,
                  stoppedAt: FundedOrderStage.placing,
                  moneyAt: FundedMoneyAt.venue,
                  reason: 'price_moved',
                  message: 'The price moved to 84¢'),
              _money),
          r'Price moved too fast. Your $5.00 is in Predictions. Tap to try again.');
    });
    test('the round closed first', () {
      expect(
          fundedStopLine(
              l10n,
              _record(FundedOrderStage.failed,
                  stoppedAt: FundedOrderStage.preparing,
                  moneyAt: FundedMoneyAt.venue,
                  reason: 'market_closed'),
              _money),
          r'This round closed before your money arrived. Your $5.00 is in '
          'Predictions. Tap to try again.');
    });
    test('the autofire\'s timeout already says where it is', () {
      expect(
          fundedStopLine(
              l10n,
              _record(FundedOrderStage.failed,
                  stoppedAt: FundedOrderStage.preparing,
                  moneyAt: FundedMoneyAt.venue,
                  reason: 'funds_timeout',
                  message: l10n.betAutofireFundsTimeout),
              _money),
          l10n.betAutofireFundsTimeout);
    });
    test('still in Dollars: in Investments', () {
      expect(
          fundedStopLine(
              l10n,
              _record(FundedOrderStage.failed,
                  stoppedAt: FundedOrderStage.preparing,
                  moneyAt: FundedMoneyAt.investments,
                  reason: 'venue_refused',
                  message: 'No route right now.'),
              _money),
          r'No route right now. Your $5.00 is in Investments. Tap to place.');
    });
    test('an Investing order: in Investing', () {
      expect(
          fundedStopLine(
              l10n,
              _record(FundedOrderStage.failed,
                  label: _order,
                  stoppedAt: FundedOrderStage.placing,
                  moneyAt: FundedMoneyAt.venue,
                  reason: 'placement',
                  message: 'Order rejected.'),
              _money),
          r'Order rejected. Your $20.00 is in Investing. Tap to try again.');
    });
  });

  group('the founder\'s case: a 5-minute round and no Predictions cash', () {
    test('a round that closed while the money was on its way stops at once',
        () {
      final end = DateTime(2026, 10, 14, 12, 5);
      final intent = _intent(endAt: end);
      expect(autofireRoundClosed(intent, now: end.subtract(const Duration(seconds: 1))),
          isFalse);
      expect(autofireRoundClosed(intent, now: end), isTrue);
      // A long market's end date is for display only.
      expect(
          autofireRoundClosed(_intent(endAt: end, question: 'Will it rain?'),
              now: end.add(const Duration(minutes: 1))),
          isFalse);
    });

    test('a 5-minute round is funded from wherever the money is, even when '
        'it may end first (founder, 23 October 2026)', () {
      final now = DateTime(2026, 10, 14, 12);
      for (final left in const [Duration(seconds: 20), Duration(minutes: 4)]) {
        expect(
            predictionsFundingBlock(
                endAt: now.add(left), fastRound: true, now: now),
            isNull);
      }
      // Over already: nothing moves.
      expect(
          predictionsFundingBlock(
              endAt: now.subtract(const Duration(seconds: 1)),
              fastRound: true,
              now: now),
          PredictionsFundingBlock.ended);
    });
  });
}
