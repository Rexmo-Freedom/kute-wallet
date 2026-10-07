// A held position whose market has ended but is not redeemable yet is
// "awaiting its result": the provider polls every 20 s for it off the
// Predictions surface, so the card turns claimable on its own.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart';

Position _position(
        {required String eventSlug,
        String? endDate,
        bool redeemable = false}) =>
    Position(
        proxyWallet: 'wallet',
        asset: '1',
        conditionId: 'condition',
        size: 4.53,
        avgPrice: 0.66,
        initialValue: 2.99,
        currentValue: 4.53,
        cashPnl: 1.54,
        percentPnl: 51.4,
        totalBought: 2.99,
        realizedPnl: 0,
        percentRealizedPnl: 0,
        curPrice: 1,
        redeemable: redeemable,
        title: 'Bitcoin Up or Down',
        slug: eventSlug,
        eventSlug: eventSlug,
        outcome: 'Up',
        outcomeIndex: 0,
        oppositeOutcome: 'Down',
        oppositeAsset: '2',
        endDate: endDate);

void main() {
  // The round 09:50-09:55 UTC on 5 Oct 2026.
  const round = 'btc-updown-5m-1791193800';
  final roundEnd = DateTime.utc(2026, 10, 5, 9, 55);
  final awaiting = PolymarketTradingNotifier.awaitingResolution;

  test('a short round waits from its own end, read off the slug', () {
    final p = _position(eventSlug: round);
    expect(awaiting(p, roundEnd.subtract(const Duration(seconds: 1))), isFalse);
    expect(awaiting(p, roundEnd.add(const Duration(seconds: 30))), isTrue);
  });

  test('a redeemable position is no longer waiting', () {
    expect(
        awaiting(_position(eventSlug: round, redeemable: true),
            roundEnd.add(const Duration(minutes: 1))),
        isFalse);
  });

  test('another market waits from its end date, for up to 6 hours', () {
    final p =
        _position(eventSlug: 'nfl-sf-den', endDate: '2026-10-05T20:00:00Z');
    final end = DateTime.utc(2026, 10, 5, 20);
    expect(awaiting(p, end.subtract(const Duration(minutes: 1))), isFalse);
    expect(awaiting(p, end.add(const Duration(hours: 1))), isTrue);
    expect(awaiting(p, end.add(const Duration(hours: 7))), isFalse);
  });

  test('no end known: not waiting', () {
    expect(
        awaiting(_position(eventSlug: 'some-market'), DateTime.now()), isFalse);
  });
}
