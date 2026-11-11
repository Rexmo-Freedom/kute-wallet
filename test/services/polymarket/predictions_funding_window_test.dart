// The reads Confirm makes before it funds a prediction
// (predictions_funding_window.dart): a market that no longer takes orders
// is never funded, a short round that may end first is funded all the
// same, and a slip never opens on a market already over. Nothing here
// moves money: pre-funding was removed (founder decision, 11 November
// 2026), so these rules only run from Confirm.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/polymarket/predictions_funding_window.dart';

void main() {
  group('closing markets (audit P1-5)', () {
    final now = DateTime.utc(2026, 10, 13, 12);

    test('a round that may end before the money lands is funded all the '
        'same (founder, 23 October 2026)', () {
      for (final left in const [
        Duration(seconds: 1),
        Duration(seconds: 30),
        Duration(seconds: 100),
        Duration(minutes: 3),
      ]) {
        expect(
            predictionsFundingBlock(
                market: const PolymarketMarketWindow(
                    acceptingOrders: true, closed: false),
                endAt: now.add(left),
                fastRound: true,
                now: now),
            isNull,
            reason: '$left left');
      }
    });

    test('not taking orders, or a short round past its end: ended', () {
      expect(
          predictionsFundingBlock(
              market: const PolymarketMarketWindow(
                  acceptingOrders: false, closed: false),
              endAt: now.add(const Duration(hours: 2)),
              fastRound: false,
              now: now),
          PredictionsFundingBlock.ended);
      expect(
          predictionsFundingBlock(
              market: const PolymarketMarketWindow(
                  acceptingOrders: true, closed: true),
              endAt: now.add(const Duration(hours: 2)),
              fastRound: false,
              now: now),
          PredictionsFundingBlock.ended);
      expect(
          predictionsFundingBlock(
              endAt: now.subtract(const Duration(seconds: 1)),
              fastRound: true,
              now: now),
          PredictionsFundingBlock.ended);
    });

    test('a longer market past its display end still trades', () {
      expect(
          predictionsFundingBlock(
              market: const PolymarketMarketWindow(
                  acceptingOrders: true, closed: false),
              endAt: now.subtract(const Duration(days: 3)),
              fastRound: false,
              now: now),
          isNull);
    });

    test('a market that could not be read does not block Confirm', () {
      expect(
          predictionsFundingBlock(
              endAt: now.add(const Duration(hours: 1)),
              fastRound: true,
              now: now),
          isNull);
    });

    test('the CLOB end stands in when the slip has none', () {
      expect(
          predictionsFundingBlock(
              market: PolymarketMarketWindow(
                  acceptingOrders: true,
                  closed: false,
                  endAt: now.subtract(const Duration(seconds: 1))),
              fastRound: true,
              now: now),
          PredictionsFundingBlock.ended);
    });
  });

  group('slips on ended markets', () {
    final now = DateTime.utc(2026, 10, 13, 12);

    test('a short round past its end never opens', () {
      expect(
          polymarketSlipEnded(
              slug: 'btc-updown-5m-1760356800',
              question: 'Bitcoin Up or Down',
              endAt: now.subtract(const Duration(seconds: 5)),
              now: now),
          isTrue);
      expect(
          polymarketSlipEnded(
              slug: 'btc-updown-5m-1760356800',
              question: 'Bitcoin Up or Down',
              endAt: now.add(const Duration(minutes: 3)),
              now: now),
          isFalse);
    });

    test('a closed or ended event never opens; a long market past its date does',
        () {
      expect(
          polymarketSlipEnded(
              event: const PolymarketEvent(
                  id: '1',
                  title: 'Final',
                  slug: 'final',
                  volume: 0,
                  liquidity: 0,
                  category: 'sports',
                  conditionId: '',
                  outcomes: [],
                  closed: true),
              now: now),
          isTrue);
      expect(
          polymarketSlipEnded(
              question: 'Who wins the election?',
              endAt: now.subtract(const Duration(days: 10)),
              now: now),
          isFalse);
    });

    test('market kinds (a funded order\'s analytics label only)', () {
      expect(
          fastMarketKind(
              slug: 'eth-updown-15m-1760356800', live: false, now: now),
          FastMarketKind.short);
      expect(fastMarketKind(slug: 'nba-lal-bos', live: true, now: now),
          FastMarketKind.live);
      expect(fastMarketKind(slug: 'nba-lal-bos', live: false, now: now),
          isNull);
    });
  });
}
