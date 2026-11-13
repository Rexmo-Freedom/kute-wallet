// The standing order's state machine, its record's round trip, what the
// venues' queued statuses read as, and when a next-round pick may post.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/pending_hyperliquid_order_provider.dart'
    show HlReadiness, PendingHlOrderStatus;
import 'package:kute/providers/pending_polymarket_bet_provider.dart'
    show PendingBetStatus, PredictionsReadiness;
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart'
    show HlOrderResultKind;
import 'package:kute/services/standing_orders/standing_order.dart';

StandingOrder order({
  StandingOrderState state = StandingOrderState.funding,
  DateTime? createdAt,
  String? eventSlug,
}) {
  final at = createdAt ?? DateTime.utc(2026, 11, 9, 12);
  return StandingOrder(
    id: 'so_1',
    walletId: 'w1',
    venue: StandingOrderVenue.predictions,
    marketKey: '111',
    marketTitle: 'Will it rain?',
    sideLabel: 'Yes',
    isBuy: true,
    size: 19.23,
    approvedPrice: 0.52,
    amountUsd: 10,
    orderKind: 'market',
    state: state,
    createdAt: at,
    updatedAt: at,
    fundUsd: 10.3,
    arrivingUsd: 10.1,
    slippagePct: 5,
    eventSlug: eventSlug,
    roundWindow: eventSlug == null ? null : 'next',
    orderHash: '0x${'ab' * 32}',
    negRisk: true,
    attempts: 2,
    movedToPrice: 0.81,
  );
}

void main() {
  group('state machine', () {
    test('funding and funded move on, back never', () {
      const s = StandingOrderState.values;
      expect(StandingOrder.canMove(s[0], StandingOrderState.funded), isTrue);
      expect(StandingOrder.canMove(StandingOrderState.funded, StandingOrderState.funding), isFalse);
      expect(StandingOrder.canMove(StandingOrderState.funding, StandingOrderState.posting), isTrue);
      expect(StandingOrder.canMove(StandingOrderState.funded, StandingOrderState.cancelled), isTrue);
      expect(StandingOrder.canMove(StandingOrderState.funded, StandingOrderState.filled), isFalse);
    });

    test('posting ends posted, filled, failed or waits for the person', () {
      expect(StandingOrder.canMove(StandingOrderState.posting, StandingOrderState.posted), isTrue);
      expect(StandingOrder.canMove(StandingOrderState.posting, StandingOrderState.filled), isTrue);
      expect(StandingOrder.canMove(StandingOrderState.posting, StandingOrderState.failed), isTrue);
      expect(StandingOrder.canMove(StandingOrderState.posting, StandingOrderState.needsApproval), isTrue);
      // Never cancelled once it left for the venue.
      expect(StandingOrder.canMove(StandingOrderState.posting, StandingOrderState.cancelled), isFalse);
      expect(StandingOrder.canMove(StandingOrderState.posted, StandingOrderState.filled), isTrue);
      expect(StandingOrder.canMove(StandingOrderState.posted, StandingOrderState.cancelled), isFalse);
    });

    test('terminal states move nowhere; needsApproval only ends', () {
      for (final from in [StandingOrderState.filled, StandingOrderState.failed, StandingOrderState.cancelled]) {
        for (final to in StandingOrderState.values) {
          expect(StandingOrder.canMove(from, to), isFalse, reason: '$from -> $to');
        }
      }
      expect(StandingOrder.canMove(StandingOrderState.needsApproval, StandingOrderState.cancelled), isTrue);
      expect(StandingOrder.canMove(StandingOrderState.needsApproval, StandingOrderState.failed), isTrue);
      expect(StandingOrder.canMove(StandingOrderState.needsApproval, StandingOrderState.posting), isFalse);
    });

    test('cancellable before posting and while waiting for approval', () {
      expect(order(state: StandingOrderState.funding).canCancel, isTrue);
      expect(order(state: StandingOrderState.funded).canCancel, isTrue);
      expect(order(state: StandingOrderState.needsApproval).canCancel, isTrue);
      expect(order(state: StandingOrderState.posting).canCancel, isFalse);
      expect(order(state: StandingOrderState.posted).canCancel, isFalse);
      expect(order(state: StandingOrderState.filled).isOpen, isFalse);
      expect(order(state: StandingOrderState.needsApproval).isOpen, isTrue);
    });

    test('expires with the approval, 30 minutes after the accept', () {
      final at = DateTime.utc(2026, 11, 9, 12);
      final o = order(createdAt: at);
      expect(kStandingOrderLifetime, const Duration(minutes: 30));
      expect(o.isExpiredAt(at.add(const Duration(minutes: 29))), isFalse);
      expect(o.isExpiredAt(at.add(const Duration(minutes: 30))), isTrue);
    });
  });

  test('the record round-trips through JSON with every public fact', () {
    final o = order(
        state: StandingOrderState.needsApproval,
        eventSlug: 'btc-updown-5m-1791152100');
    final back = StandingOrder.fromJson(o.toJson())!;
    expect(back.id, o.id);
    expect(back.walletId, o.walletId);
    expect(back.venue, o.venue);
    expect(back.state, StandingOrderState.needsApproval);
    expect(back.size, o.size);
    expect(back.approvedPrice, o.approvedPrice);
    expect(back.amountUsd, 10);
    expect(back.fundUsd, 10.3);
    expect(back.arrivingUsd, 10.1);
    expect(back.slippagePct, 5);
    expect(back.eventSlug, o.eventSlug);
    expect(back.roundWindow, 'next');
    expect(back.orderHash, o.orderHash);
    expect(back.negRisk, isTrue);
    expect(back.attempts, 2);
    expect(back.movedToPrice, 0.81);
    expect(back.createdAt, o.createdAt);
    // The fill's own figures round-trip; a record from before them reads
    // none.
    final filled = StandingOrder.fromJson(o
        .copyWith(
            state: StandingOrderState.filled, filledSize: 19.6, filledUsd: 9.8)
        .toJson())!;
    expect(filled.filledSize, 19.6);
    expect(filled.filledUsd, 9.8);
    expect(filled.placedUsd, 9.8);
    expect(back.filledSize, isNull);
    expect(back.filledUsd, isNull);
    // Unreadable rows are skipped, never thrown.
    expect(StandingOrder.fromJson({'v': 99}), isNull);
    expect(StandingOrder.fromJson({'v': 1, 'id': 'x'}), isNull);
  });

  group('what the queued statuses read as', () {
    test('a prediction', () {
      expect(standingStateForBet(null), isNull);
      expect(standingStateForBet(PendingBetStatus.awaitingDeposit), isNull);
      expect(standingStateForBet(PendingBetStatus.awaitingBalance), StandingOrderState.funding);
      expect(
          standingStateForBet(PendingBetStatus.awaitingBalance,
              readiness: PredictionsReadiness.waitingFunds),
          StandingOrderState.funding);
      expect(
          standingStateForBet(PendingBetStatus.awaitingBalance,
              readiness: PredictionsReadiness.converting),
          StandingOrderState.funded);
      expect(
          standingStateForBet(PendingBetStatus.awaitingBalance,
              readiness: PredictionsReadiness.ready),
          StandingOrderState.funded);
      expect(standingStateForBet(PendingBetStatus.placing), StandingOrderState.posting);
      expect(standingStateForBet(PendingBetStatus.done), StandingOrderState.filled);
      expect(standingStateForBet(PendingBetStatus.done, isLimit: true), StandingOrderState.posted);
      expect(standingStateForBet(PendingBetStatus.awaitingConfirmation), StandingOrderState.posted);
      expect(standingStateForBet(PendingBetStatus.failed), StandingOrderState.failed);
    });

    test('an Investing order', () {
      expect(standingStateForHlOrder(null), isNull);
      expect(standingStateForHlOrder(PendingHlOrderStatus.awaitingDeposit), isNull);
      expect(standingStateForHlOrder(PendingHlOrderStatus.awaitingBalance), StandingOrderState.funding);
      expect(
          standingStateForHlOrder(PendingHlOrderStatus.awaitingBalance,
              readiness: HlReadiness.crediting),
          StandingOrderState.funded);
      expect(standingStateForHlOrder(PendingHlOrderStatus.placing), StandingOrderState.posting);
      expect(
          standingStateForHlOrder(PendingHlOrderStatus.done,
              result: HlOrderResultKind.filled),
          StandingOrderState.filled);
      expect(
          standingStateForHlOrder(PendingHlOrderStatus.done,
              result: HlOrderResultKind.resting),
          StandingOrderState.posted);
      expect(standingStateForHlOrder(PendingHlOrderStatus.unconfirmed), StandingOrderState.posted);
      expect(standingStateForHlOrder(PendingHlOrderStatus.failed), StandingOrderState.failed);
    });
  });

  test('a record kept by a build that held a pick back for its round reads '
      'as one that waits for nothing', () {
    // 2.2.0 (111) and earlier wrote `postNotBeforeMs`; the venue takes
    // orders before a round starts, so nothing reads it any more.
    final json = order(eventSlug: 'btc-updown-5m-1791152100').toJson()
      ..['postNotBeforeMs'] = 1791152100 * 1000;
    final back = StandingOrder.fromJson(json)!;
    expect(back.eventSlug, 'btc-updown-5m-1791152100');
    expect(back.toJson().containsKey('postNotBeforeMs'), isFalse);
  });

  test('the re-price bounds are three times within 90 seconds', () {
    expect(kStandingReprices, 3);
    expect(kStandingRepriceWindow, const Duration(seconds: 90));
  });
}
