import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_analytics.dart';

void main() {
  final events = <(String, Map<String, Object>?)>[];

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

  group('kind of bet', () {
    test('classifies from tags with the league, top tags and resolution', () {
      final end = DateTime.now().add(const Duration(hours: 5));
      VenueAnalytics.rememberPolymarket(
        ids: ['tok-yes', 'tok-no', 'cond-1', 'nba-lal-bos-2026-10-21'],
        category: 'sports',
        tags: ['sports', 'nba', 'basketball', 'games', 'lakers', 'celtics'],
        slug: 'nba-lal-bos-2026-10-21',
        endDate: end,
        isLive: true,
      );
      final p = VenueAnalytics.pmKindParams(['missing', 'tok-no']);
      expect(p['market_category'], 'sports');
      expect(p['sports_league'], 'nba');
      expect(p['is_live'], true);
      expect(p['event_tags'], ['nba', 'basketball', 'lakers']);
      expect(p['time_to_resolution_bucket'], '1-24h');
    });

    test('maps tags to the product categories and falls back', () {
      expect(VenueAnalytics.marketCategory('other', ['fed-rates']),
          'economics');
      expect(VenueAnalytics.marketCategory('other', ['pop-culture', 'music']),
          'culture');
      expect(VenueAnalytics.marketCategory('other', ['epl']), 'sports');
      expect(VenueAnalytics.marketCategory('science', []), 'tech');
      expect(VenueAnalytics.marketCategory('politics', ['elections']),
          'politics');
      expect(VenueAnalytics.marketCategory('', []), 'other');
      expect(VenueAnalytics.pmKindParams(['unknown'], fallbackCategory: 'crypto'),
          {'market_category': 'crypto'});
      expect(VenueAnalytics.pmKindParams(['unknown']),
          {'market_category': 'unknown'});
    });

    test('league comes from the slug when tags only say the sport', () {
      expect(
          VenueAnalytics.sportsLeague(
              'sports', ['sports', 'soccer'], 'epl-ars-che-2026-11-02'),
          'epl');
      expect(VenueAnalytics.sportsLeague('sports', ['soccer'], 'x'), 'soccer');
      expect(VenueAnalytics.sportsLeague('sports', [], null), isNull);
    });

    test('resolution buckets', () {
      final now = DateTime(2026, 1, 1);
      String b(Duration d) =>
          VenueAnalytics.resolutionBucket(now.add(d), now: now);
      expect(VenueAnalytics.resolutionBucket(null), 'unknown');
      expect(b(const Duration(minutes: -1)), 'ended');
      expect(b(const Duration(minutes: 30)), '<1h');
      expect(b(const Duration(hours: 3)), '1-24h');
      expect(b(const Duration(days: 3)), '1-7d');
      expect(b(const Duration(days: 20)), '7-30d');
      expect(b(const Duration(days: 90)), '30d+');
    });

    test('an event is remembered under every public id it carries', () {
      const e = PolymarketEvent(
        id: 'ev1',
        slug: 'will-it-rain',
        title: 'Will it rain?',
        volume: 0,
        liquidity: 0,
        category: 'other',
        conditionId: 'cond-x',
        tags: ['weather', 'climate'],
        outcomes: [
          PolymarketOutcome(name: 'Yes', price: 0.5, tokenId: 't1'),
          PolymarketOutcome(
              name: 'No', price: 0.5, tokenId: 't2', noTokenId: 't2n'),
        ],
      );
      VenueAnalytics.rememberPolymarketEvent(e);
      for (final id in ['ev1', 'will-it-rain', 'cond-x', 't1', 't2', 't2n']) {
        expect(VenueAnalytics.knowsPolymarket(id), isTrue, reason: id);
      }
      expect(VenueAnalytics.pmKindParams(['t2n'])['market_category'], 'weather');
      expect(VenueAnalytics.pmKindParams(['t2n']).containsKey('is_live'),
          isFalse);
    });

    test('bet outcome events carry the kind for the market', () {
      VenueAnalytics.rememberPolymarket(
          ids: ['tok-a'], category: 'crypto', tags: ['crypto', 'bitcoin']);
      TrackingService.polymarketBetPlaced(
        marketId: 'tok-a',
        outcome: 'buy',
        amount: 10,
        price: 0.5,
        shares: 20,
        logAffiliateEvent: false,
      );
      final placed = events.singleWhere((e) => e.$1 == 'polymarket_bet_placed');
      expect(placed.$2!['market_category'], 'crypto');
      expect(placed.$2!['event_tags'], ['bitcoin']);
      TrackingService.polymarketPositionSold(
          marketId: 'tok-a', shares: 2, price: 0.4);
      final sold =
          events.singleWhere((e) => e.$1 == 'polymarket_position_sold');
      expect(sold.$2!['market_category'], 'crypto');
    });
  });

  group('kind of trade', () {
    test('asset class and dex by coin, wire coin and kind', () {
      VenueAnalytics.rememberHlMarket(
          coin: 'WHEAT',
          wireCoin: 'unit:WHEAT',
          isSpot: false,
          category: 'commodities',
          dex: 'unit');
      VenueAnalytics.rememberHlMarket(
          coin: 'PURR',
          wireCoin: 'PURR/USDC',
          isSpot: true,
          category: 'crypto',
          dex: '');
      expect(VenueAnalytics.hlAssetParams('WHEAT'),
          {'asset_class': 'commodity', 'dex': 'unit'});
      expect(VenueAnalytics.hlAssetParams('unit:WHEAT'),
          {'asset_class': 'commodity', 'dex': 'unit'});
      expect(VenueAnalytics.hlAssetParams('PURR', kind: 'spot'),
          {'asset_class': 'crypto', 'dex': 'main'});
      expect(VenueAnalytics.hlAssetParams('BTC'),
          {'asset_class': 'crypto', 'dex': 'main'});
      expect(VenueAnalytics.assetClass('stocks'), 'stock');
      expect(VenueAnalytics.assetClass('indices'), 'index');
      expect(VenueAnalytics.assetClass('fx'), 'fx');
    });

    test('an order carries asset class, staged ticket settings and origin',
        () {
      VenueAnalytics.rememberHlMarket(
          coin: 'AAPL',
          wireCoin: 'xyz:AAPL',
          isSpot: false,
          category: 'stocks',
          dex: 'xyz');
      VenueAnalytics.stage('hl', 'AAPL', {
        'entry_source': 'search',
        'slippage_bps': 100,
        'tif': 'gtc',
      });
      TrackingService.hyperliquidOrderPlaced(
        coin: 'AAPL',
        kind: 'perp',
        isBuy: true,
        leverage: 3,
        marginUsd: 50,
        notionalUsd: 150,
        source: 'autofire',
        origin: 'advisor',
      );
      final p = events
          .singleWhere((e) => e.$1 == 'hyperliquid_order_placed')
          .$2!;
      expect(p['asset_class'], 'stock');
      expect(p['dex'], 'xyz');
      expect(p['entry_source'], 'search');
      expect(p['slippage_bps'], 100);
      expect(p['tif'], 'gtc');
      expect(p['source'], 'autofire');
      expect(p['origin'], 'advisor');
      VenueAnalytics.unstage('hl', 'AAPL');
      expect(VenueAnalytics.staged('hl', 'AAPL'), isEmpty);
    });
  });

  group('settings and flows', () {
    test('a setting change is sent once per value per scope', () {
      bool send() => VenueAnalytics.settingChanged('x_setting_changed',
          setting: 'leverage', value: 5, scope: 'a');
      expect(send(), isTrue);
      expect(send(), isFalse);
      expect(
          VenueAnalytics.settingChanged('x_setting_changed',
              setting: 'leverage', value: 5, scope: 'b'),
          isTrue);
      VenueAnalytics.resetSettings('a');
      expect(send(), isTrue);
      expect(events.where((e) => e.$1 == 'x_setting_changed').length, 3);
      expect(events.first.$2, {'setting': 'leverage', 'value': 5});
    });

    test('time in flow buckets and bps', () {
      expect(VenueAnalytics.timeInFlowBucket(const Duration(seconds: 3)),
          '<10s');
      expect(VenueAnalytics.timeInFlowBucket(const Duration(seconds: 20)),
          '10-30s');
      expect(VenueAnalytics.timeInFlowBucket(const Duration(seconds: 90)),
          '30s-2m');
      expect(VenueAnalytics.timeInFlowBucket(const Duration(minutes: 5)),
          '2-10m');
      expect(VenueAnalytics.timeInFlowBucket(const Duration(minutes: 15)),
          '10m+');
      expect(VenueAnalytics.bps(2.5), 250);
    });

    test('a Ledger bet pending confirmation is reported once', () {
      VenueAnalytics.rememberLedgerPendingBet('w1', {'amount': 5.0});
      expect(VenueAnalytics.takeLedgerPendingBet('w1'), {'amount': 5.0});
      expect(VenueAnalytics.takeLedgerPendingBet('w1'), isNull);
    });
  });
}
