// The Predictions category tree: the pills and their subcategory rows in
// polymarket.com's order, and where each chip's list is read from.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import '../helpers/runtime_policy_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AffiliateService.debugSessionToken = 'test-session');
  tearDown(() => AffiliateService.debugSessionToken = null);

  Future<RuntimeCapabilitiesService> policy(Set<String> blocked) async {
    final service = runtimePolicyFixture(blocked: blocked);
    addTearDown(service.dispose);
    expect(await service.refresh(), isTrue);
    return service;
  }

  group('pills', () {
    test('one pill per site category, in the site order', () {
      expect([for (final p in PolyPill.values) p.key], [
        'watchlist',
        'trending',
        'breaking',
        'new',
        'live',
        'politics',
        'sports',
        'crypto',
        'esports',
        'finance',
        'geopolitics',
        'tech',
        'culture',
        'economy',
        'weather',
        'mentions',
        'elections',
      ]);
    });

    test('each topic pill lists one Gamma tag', () {
      expect(PolyPill.culture.tagSlugs, ['pop-culture']);
      expect(PolyPill.mentions.tagSlugs, ['mention-markets']);
      expect(PolyPill.elections.tagSlugs, ['elections']);
      expect(PolyPill.finance.tagSlugs, ['finance']);
      expect(PolyPill.economy.tagSlugs, ['economy']);
      expect(PolyPill.geopolitics.tagSlugs, ['geopolitics']);
      for (final p in PolyPill.values) {
        expect(p.tagSlugs.length, lessThanOrEqualTo(1), reason: p.key);
      }
      expect(PolyPill.trending.isTopic, isFalse);
      expect(PolyPill.live.isTopic, isFalse);
    });

    test('related tags feed Politics, Geopolitics, Tech, Culture, Economy',
        () {
      expect({
        for (final p in PolyPill.values)
          if (p.relatedTagId != null) p.key: p.relatedTagId
      }, {
        'politics': 2,
        'geopolitics': 100265,
        'tech': 1401,
        'culture': 596,
        'economy': 100328,
      });
    });

    test('the split pills keep their old route segments', () {
      expect(PolyPillX.fromKey('world'), PolyPill.geopolitics);
      expect(PolyPillX.fromKey('tech-culture'), PolyPill.tech);
      expect(PolyPillX.fromKey('culture'), PolyPill.culture);
      expect(PolyPillX.fromKey('nope'), isNull);
    });

    test('Sports opens on the games in play, the rest on All', () {
      const selection = PolyBrowseSelection(pill: PolyPill.sports);
      expect(selection.sub, 'live');
      expect(selection.subOf(PolyPill.crypto), 'all');
      expect(selection.copyWith(sub: 'soccer').sub, 'soccer');
    });

    test('a withdrawn category takes its pills with it', () async {
      final open = await policy({});
      expect(PolyPill.values.every((p) => polyPillOffered(p, open)), isTrue);
      final noSports = await policy({'polymarket.sports'});
      expect([
        for (final p in PolyPill.values)
          if (!polyPillOffered(p, noSports)) p
      ], [PolyPill.live, PolyPill.sports, PolyPill.esports]);
      final noPolitics = await policy({'polymarket.politics'});
      expect([
        for (final p in PolyPill.values)
          if (!polyPillOffered(p, noPolitics)) p
      ], [PolyPill.politics, PolyPill.elections]);
    });
  });

  group('subcategory rows', () {
    test('Breaking has the site topics in the site order', () {
      expect(kPolyBreakingTopics, [
        'all', 'politics', 'world', 'sports', 'crypto', 'finance', 'tech',
        'culture', //
      ]);
    });

    test('Crypto: windows, sections, then the coins', () {
      final subs = polyCryptoSubsFromCounts(null);
      expect([for (final s in subs) s.key], [
        'all', '5m', '15m', '1h', '4h', 'daily', 'weekly', 'monthly',
        'yearly', 'targets', 'pre-market', 'institutions', 'industry',
        'protocol-metrics', 'bitcoin', 'ethereum', 'solana', 'xrp',
        'dogecoin', 'bnb', 'microstrategy', //
      ]);
      // Coins carry their own names; the others are localised on screen.
      expect(subs.firstWhere((s) => s.key == 'xrp').label, 'XRP');
      expect(subs.firstWhere((s) => s.key == 'targets').label, isNull);
      // The seven coins carry the logo the site shows; nothing else does.
      expect([
        for (final s in subs)
          if (s.imageUrl != null) s.key
      ], [
        'bitcoin', 'ethereum', 'solana', 'xrp', 'dogecoin', 'bnb',
        'microstrategy', //
      ]);
      expect(subs.firstWhere((s) => s.key == 'dogecoin').imageUrl,
          'https://polymarket.com/images/logos/doge.png');
    });

    test('Crypto: the site counts number the chips and drop the empty ones',
        () {
      final subs = polyCryptoSubsFromCounts(const {
        'all': '290',
        'fiveM': '0',
        'fifteenM': '7',
        'targets': '28',
        'protocol-metrics': '0',
        'bitcoin': '38',
        'dogecoin': '0',
      });
      final keys = [for (final s in subs) s.key];
      expect(keys, containsAll(['all', '5m', '15m', 'targets', 'bitcoin']));
      expect(keys, isNot(contains('protocol-metrics')));
      expect(keys, isNot(contains('dogecoin')));
      // A chip the counts do not name stays.
      expect(keys, contains('weekly'));
      expect(subs.firstWhere((s) => s.key == 'targets').count, 28);
    });

    test('Finance and Weather are the site lists', () {
      expect(kPolyFinanceSubs, [
        'all', 'daily', 'weekly', 'monthly', 'stocks', 'earnings',
        'indicies', 'commodities', 'forex', 'privates', 'acquisitions',
        'ipo', 'fed-rates', 'prediction-markets', 'treasuries', 'kpis', //
      ]);
      expect(kPolyWeatherSubs, [
        'all', 'temperature', 'precipitation', 'drought', 'global',
        'tornadoes', 'hurricanes', 'earthquakes', 'volcanoes', 'pandemics', //
      ]);
    });

    test('Sports: Live, Futures, six leagues, then the sports; no All', () {
      Map<String, dynamic> league(int i, {bool esports = false}) => {
            'sport': 'l$i',
            'name': 'League $i',
            'image': 'https://example.com/$i.png',
            'series': '$i',
            'tags': esports ? '1,64,100639' : '1,100639',
          };
      final subs = polySportsSubsFromLeagues([
        league(1),
        league(2, esports: true),
        for (var i = 3; i <= 10; i++) league(i),
      ]);
      final keys = [for (final s in subs) s.key];
      expect(keys.take(8), [
        'live', 'futures', 'series:1', 'series:3', 'series:4', 'series:5',
        'series:6', 'series:7', //
      ]);
      expect(keys.skip(8), kPolySportGroups);
      expect(keys, isNot(contains('all')));
      expect(kPolySportGroups.take(7), [
        'soccer', 'tennis', 'cricket', 'basketball', 'baseball', 'football',
        'hockey', //
      ]);
      // A league carries its logo; a sport only when Gamma lists one.
      expect(subs[2].imageUrl, 'https://example.com/1.png');
      expect(subs.last.imageUrl, isNull);
      final logos = polySportGroupLogos(const [
        {'sport': 'darts', 'image': 'https://example.com/darts.png'},
        {'sport': 'chess', 'image': ''},
        {'sport': 'nfl', 'image': 'https://example.com/nfl.png'},
      ]);
      expect(logos, {'darts': 'https://example.com/darts.png'});
      final withLogos =
          polySportsSubsFromLeagues(const [], groupLogos: logos);
      expect(withLogos.firstWhere((s) => s.key == 'darts').imageUrl,
          'https://example.com/darts.png');
      expect(withLogos.firstWhere((s) => s.key == 'soccer').imageUrl, isNull);
      // Without the league list the row is still whole.
      expect(
          [for (final s in polySportsSubsFromLeagues(const [])) s.key],
          ['live', 'futures', ...kPolySportGroups]);
    });

    test('Esports: All, then the games, the ones in play first', () {
      final idle = polyEsportsSubsFrom();
      expect([for (final s in idle) s.label ?? s.key].take(5),
          ['all', 'LoL', 'CS2', 'Rainbow Six Siege', 'Dota 2']);
      final live = polyEsportsSubsFrom(
        logos: const {'val': 'https://example.com/val.png'},
        live: const {'valorant', 'dota-2'},
      );
      expect([for (final s in live) s.key].take(4),
          ['all', 'dota-2', 'valorant', 'league-of-legends']);
      expect(live.firstWhere((s) => s.key == 'valorant').imageUrl,
          'https://example.com/val.png');
      expect(live.length, kPolyEsportsGames.length + 1);
    });

    test('related tags keep Gamma order and labels, science included',
        () async {
      final subs = polyTopicSubsFromRows(const [
        {'id': 439, 'slug': 'ai', 'label': 'AI', 'activeEventsCount': 290},
        {'id': 74, 'slug': 'science', 'label': 'Science', 'activeEventsCount': 40},
        {'id': 1, 'slug': 'empty', 'label': 'Empty', 'activeEventsCount': 0},
        {'id': 439, 'slug': 'ai', 'label': 'AI', 'activeEventsCount': 290},
        {'id': 101999, 'slug': 'big-tech', 'label': 'Big Tech', 'activeEventsCount': 146},
      ], await policy({}));
      expect([for (final s in subs) s.label], ['AI', 'Science', 'Big Tech']);
      expect(subs[1].key, 'tag:74');
      expect(subs[1].route, 'science');
      expect(subs[1].count, 40);
    });

    test('related tags of a withdrawn category are left out', () async {
      final subs = polyTopicSubsFromRows(const [
        {'id': 5, 'slug': 'oil', 'label': 'Oil', 'activeEventsCount': 51},
        {'id': 6, 'slug': 'elections', 'label': 'Elections', 'activeEventsCount': 9},
      ], await policy({'polymarket.politics'}));
      expect([for (final s in subs) s.label], ['Oil']);
    });
  });

  group('where a chip reads from', () {
    test('every fixed Finance, Weather, Sports and Esports chip is a tag list',
        () {
      for (final sub in kPolyFinanceSubs.skip(1)) {
        expect(polyFixedSubSource(PolyPill.finance, sub), isNotNull,
            reason: sub);
      }
      for (final sub in kPolyWeatherSubs.skip(1)) {
        expect(polyFixedSubSource(PolyPill.weather, sub), isNotNull,
            reason: sub);
      }
      for (final sub in kPolySportGroups) {
        expect(polyFixedSubSource(PolyPill.sports, sub)!.tags, [sub]);
      }
      for (final g in kPolyEsportsGames) {
        expect(polyFixedSubSource(PolyPill.esports, g.slug)!.tags, [g.slug]);
      }
    });

    test('All, Live, Futures and Gamma tags are not fixed tag lists', () {
      expect(polyFixedSubSource(PolyPill.finance, 'all'), isNull);
      expect(polyFixedSubSource(PolyPill.sports, 'live'), isNull);
      expect(polyFixedSubSource(PolyPill.sports, 'futures'), isNull);
      expect(polyFixedSubSource(PolyPill.politics, 'tag:126'), isNull);
      expect(polyFixedSubSource(PolyPill.crypto, '5m'), isNull);
      expect(polyFixedSubSource(PolyPill.mentions, 'all'), isNull);
    });

    test('the site names that are not the tag itself', () {
      expect(polyFixedSubSource(PolyPill.finance, 'indicies')!.tags,
          ['indicies']);
      expect(polyFixedSubSource(PolyPill.finance, 'ipo')!.tags, ['ipos']);
      final daily = polyFixedSubSource(PolyPill.finance, 'daily')!;
      expect(daily.tags, ['daily']);
      expect(daily.require, ['finance']);
      expect(polyFixedSubSource(PolyPill.weather, 'temperature')!.tags,
          ['daily-temperature']);
      expect(polyFixedSubSource(PolyPill.weather, 'tornadoes')!.tags,
          ['tornado', 'tornado-risk']);
      expect(polyFixedSubSource(PolyPill.sports, 'mma')!.tags, ['mma']);
    });

    test('Crypto sections and coins read their tags on crypto events', () {
      final targets = polyFixedSubSource(PolyPill.crypto, 'targets')!;
      expect(targets.tags, ['price-milestone', 'price-comparison']);
      expect(targets.require, ['crypto']);
      for (final sub in ['institutions', 'industry', 'protocol-metrics']) {
        final source = polyFixedSubSource(PolyPill.crypto, sub)!;
        expect(source.tags, isNotEmpty, reason: sub);
        expect(source.require, ['crypto'], reason: sub);
      }
      final btc = polyFixedSubSource(PolyPill.crypto, 'bitcoin')!;
      expect(btc.tags, ['bitcoin']);
      expect(btc.require, ['crypto']);
      expect(polyFixedSubSource(PolyPill.crypto, 'daily')!.tags, ['today']);
    });
  });

  group('routes and cache keys', () {
    test('a fixed chip is kept as is, a Gamma tag by its segment', () {
      expect(
          polyBrowseSelectionFromRouteKey('predictions/finance/stocks')!.sub,
          'stocks');
      expect(polyBrowseSelectionFromRouteKey('predictions/sports/soccer')!.sub,
          'soccer');
      expect(
          polyBrowseSelectionFromRouteKey('predictions/esports/cs2')!.sub,
          'cs2');
      expect(polyBrowseSelectionFromRouteKey('predictions/sports')!.sub,
          'live');
      expect(polyBrowseSelectionFromRouteKey('predictions/tech/science')!.sub,
          'route:science');
      final old = polyBrowseSelectionFromRouteKey('predictions/world')!;
      expect(old.pill, PolyPill.geopolitics);
    });

    test('each list has its own disk cache key', () {
      const a = PolyFeedQuery(pill: PolyPill.finance, sub: 'stocks');
      const b = PolyFeedQuery(pill: PolyPill.weather, sub: 'global');
      const c = PolyFeedQuery(pill: PolyPill.mentions);
      expect(a.cacheKey, 'browse_finance_stocks_all_volume');
      expect(b.cacheKey, 'browse_weather_global_all_volume');
      expect(c.cacheKey, 'browse_mentions_all_all_volume');
    });
  });
}
