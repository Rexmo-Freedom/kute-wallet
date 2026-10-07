// The Predictions funnel joins on the parent event: a view, a slip, a
// bet, a sale and a claim all say which event their market belongs to,
// as public Gamma data (id, slug, title), never anything of the wallet.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_analytics.dart';

PolymarketEvent _event() => const PolymarketEvent(
      id: '52317',
      slug: 'nfl-kc-lv-2026-10-04',
      title: 'Chiefs vs. Raiders',
      volume: 1,
      volume24hr: 1,
      liquidity: 1,
      category: 'sports',
      tags: ['sports', 'nfl'],
      conditionId: 'cond-ml',
      outcomes: [
        PolymarketOutcome(
            name: 'Chiefs vs. Raiders',
            price: 0.62,
            tokenId: 'tok-kc',
            noTokenId: 'tok-lv',
            conditionId: 'cond-ml'),
        PolymarketOutcome(
            name: 'Chiefs vs. Raiders: O/U 44.5',
            price: 0.5,
            tokenId: 'tok-over',
            noTokenId: 'tok-under',
            conditionId: 'cond-ou'),
      ],
    );

void main() {
  final events = <(String, Map<String, Object>?)>[];
  Map<String, Object> last(String name) =>
      events.lastWhere((e) => e.$1 == name).$2!;

  setUp(() {
    VenueAnalytics.debugReset();
    events.clear();
    TrackingService.setDisabled(true);
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    VenueAnalytics.debugReset();
  });

  test('a view names its event: id, slug, title', () {
    final e = _event();
    VenueAnalytics.rememberPolymarketEvent(e);
    TrackingService.polymarketViewed(
      marketId: e.id,
      category: e.category,
      source: 'feed_card',
      eventSlug: e.slug,
      eventTitle: e.title,
    );
    final p = last('polymarket_viewed');
    expect(p['market_id'], '52317');
    expect(p['event_id'], '52317');
    expect(p['event_slug'], 'nfl-kc-lv-2026-10-04');
    expect(p['event_title'], 'Chiefs vs. Raiders');
    expect(p['source'], 'feed_card');
  });

  test('a slip names its event, its market and the side it opened on', () {
    final e = _event();
    VenueAnalytics.rememberPolymarketEvent(e);
    TrackingService.polymarketBetSlipOpened(
      'tok-over',
      source: 'market_detail',
      category: 'sports',
      walletKind: 'hot',
      eventId: e.id,
      eventSlug: e.slug,
      eventTitle: e.title,
      marketTitle: 'Chiefs vs. Raiders: O/U 44.5',
      outcome: 'Over',
    );
    final p = last('polymarket_bet_slip_opened');
    expect(p['market_id'], 'tok-over');
    expect(p['event_id'], '52317');
    expect(p['event_slug'], 'nfl-kc-lv-2026-10-04');
    expect(p['event_title'], 'Chiefs vs. Raiders');
    expect(p['market_title'], 'Chiefs vs. Raiders: O/U 44.5');
    expect(p['outcome'], 'Over');
    expect(p['wallet_kind'], 'hot');
  });

  test('a slip with no event at hand still finds it through its token', () {
    VenueAnalytics.rememberPolymarketEvent(_event());
    TrackingService.polymarketBetSlipOpened('tok-lv',
        marketTitle: 'Chiefs vs. Raiders', outcome: 'Raiders');
    final p = last('polymarket_bet_slip_opened');
    expect(p['event_id'], '52317');
    expect(p['event_slug'], 'nfl-kc-lv-2026-10-04');
    expect(p['event_title'], 'Chiefs vs. Raiders');
  });

  test('a market never seen sends what the caller has and nothing else', () {
    TrackingService.polymarketBetSlipOpened('tok-x',
        eventSlug: 'some-market', outcome: 'Yes');
    final p = last('polymarket_bet_slip_opened');
    expect(p['event_slug'], 'some-market');
    expect(p['outcome'], 'Yes');
    expect(p.containsKey('event_id'), isFalse);
    expect(p.containsKey('event_title'), isFalse);
    expect(p.containsKey('market_title'), isFalse);
  });

  test('an outcome opened as its own screen keeps its parent event', () {
    final e = _event();
    VenueAnalytics.rememberPolymarketEvent(e);
    // The stand-in the sheet builds for one outcome: its id and title are
    // the outcome's, its slug and tokens the parent's.
    const standIn = PolymarketEvent(
      id: '52317-Chiefs vs. Raiders: O/U 44.5',
      slug: 'nfl-kc-lv-2026-10-04',
      title: 'Chiefs vs. Raiders: O/U 44.5',
      volume: 0,
      volume24hr: 0,
      liquidity: 1,
      category: 'sports',
      conditionId: 'cond-ou',
      isSyntheticBinary: true,
      outcomes: [
        PolymarketOutcome(name: 'Yes', price: 0.5, tokenId: 'tok-over'),
        PolymarketOutcome(name: 'No', price: 0.5, tokenId: 'tok-under'),
      ],
    );
    VenueAnalytics.rememberPolymarketEvent(standIn);
    TrackingService.polymarketViewed(
        marketId: standIn.id, eventSlug: standIn.slug);
    final p = last('polymarket_viewed');
    expect(p['market_id'], '52317-Chiefs vs. Raiders: O/U 44.5');
    expect(p['event_id'], '52317');
    expect(p['event_title'], 'Chiefs vs. Raiders');
    // And the parent's own record is not overwritten by the stand-in.
    expect(VenueAnalytics.pmEventParams(['tok-kc'])['event_title'],
        'Chiefs vs. Raiders');
  });

  test('a bet, a sale and a claim carry the event id and slug, no title',
      () {
    VenueAnalytics.rememberPolymarketEvent(_event());
    TrackingService.polymarketBetPlaced(
      marketId: 'tok-kc',
      outcome: 'buy',
      amount: 10,
      price: 0.62,
      shares: 16,
      marketTitle: 'Chiefs vs. Raiders',
      marketSlug: 'nfl-kc-lv-2026-10-04',
      logAffiliateEvent: false,
    );
    final placed = last('polymarket_bet_placed');
    expect(placed['event_id'], '52317');
    expect(placed['event_slug'], 'nfl-kc-lv-2026-10-04');
    expect(placed.containsKey('event_title'), isFalse);
    // What it already sent is unchanged.
    expect(placed['market_id'], 'tok-kc');
    expect(placed['market_slug'], 'nfl-kc-lv-2026-10-04');
    expect(placed['market_title'], 'Chiefs vs. Raiders');

    TrackingService.polymarketPositionSold(
        marketId: 'tok-kc', shares: 2, price: 0.4);
    final sold = last('polymarket_position_sold');
    expect(sold['event_id'], '52317');
    expect(sold['event_slug'], 'nfl-kc-lv-2026-10-04');

    TrackingService.polymarketPositionRedeemed(
        marketId: 'cond-ml', outcome: 'Yes', shares: 2, payout: 2);
    final redeemed = last('polymarket_position_redeemed');
    expect(redeemed['event_id'], '52317');
    expect(redeemed['event_slug'], 'nfl-kc-lv-2026-10-04');
  });

  test('a position from a market never seen says only what it knows', () {
    TrackingService.polymarketPositionSold(
        marketId: 'tok-old', shares: 2, price: 0.4, marketSlug: 'old-market');
    final sold = last('polymarket_position_sold');
    expect(sold['event_slug'], 'old-market');
    expect(sold.containsKey('event_id'), isFalse);
    TrackingService.polymarketPositionRedeemed(
        marketId: 'cond-old', outcome: 'Yes', shares: 2, payout: 2);
    final redeemed = last('polymarket_position_redeemed');
    expect(redeemed.containsKey('event_id'), isFalse);
    expect(redeemed.containsKey('event_slug'), isFalse);
  });

  test('titles are cut at 80 characters', () {
    final long = 'A' * 120;
    expect(VenueAnalytics.title80(long).length, 80);
    TrackingService.polymarketBetSlipOpened('tok-y',
        eventTitle: long, marketTitle: long);
    final p = last('polymarket_bet_slip_opened');
    expect((p['event_title']! as String).length, 80);
    expect((p['market_title']! as String).length, 80);
  });

  test('a card with no Gamma id (a crypto round shell) gives no event id',
      () {
    const shell = PolymarketEvent(
      id: 'btc-updown-5m',
      slug: 'btc-updown-5m',
      title: 'BTC Up or Down 5m',
      volume: 0,
      volume24hr: 0,
      liquidity: 0,
      category: 'crypto',
      conditionId: 'c',
      outcomes: [
        PolymarketOutcome(name: 'Up', price: 0.5, tokenId: 'up'),
        PolymarketOutcome(name: 'Down', price: 0.5, tokenId: 'down'),
      ],
    );
    VenueAnalytics.rememberPolymarketEvent(shell);
    final p = VenueAnalytics.pmEventParams(['up']);
    expect(p.containsKey('event_id'), isFalse);
    expect(p['event_slug'], 'btc-updown-5m');
  });
}
