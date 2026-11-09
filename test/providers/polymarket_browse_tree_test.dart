// The Predictions category tree: the pills and their subcategory rows in
// polymarket.com's order, and where each chip's list is read from.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/polymarket_model.dart';
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
        'instant',
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
        'elections',
        'culture',
        'economy',
        'weather',
        'mentions',
        'art',
      ]);
      // The topics alone, as polymarket.com's nav lists them.
      expect([
        for (final p in PolyPill.values)
          if (p.isTopic) p.key
      ], [
        'politics', 'sports', 'crypto', 'esports', 'finance', 'geopolitics',
        'tech', 'elections', 'culture', 'economy', 'weather', 'mentions',
        'art', //
      ]);
    });

    test('each topic pill lists one Gamma tag', () {
      expect(PolyPill.culture.tagSlugs, ['pop-culture']);
      expect(PolyPill.mentions.tagSlugs, ['mention-markets']);
      expect(PolyPill.elections.tagSlugs, ['elections']);
      // Art is Gamma tag 1422, slug `art` (no related tags: no row).
      expect(PolyPill.art.tagSlugs, ['art']);
      expect(PolyPill.art.relatedTagId, isNull);
      expect(PolyPill.art.defaultSub, 'all');
      expect(PolyPillX.fromKey('art'), PolyPill.art);
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

    // A Gamma `/sports` directory like the live one of 9 November 2026:
    // the six leagues the site pins, leagues of the sports with a league
    // level (soccer by tag 100350, football and combat by code), an
    // esports game, a baseball league.
    Map<String, dynamic> league(String code, String name, String series,
            String tags) =>
        {
          'sport': code,
          'name': name,
          'image': 'https://example.com/$code.png',
          'series': series,
          'tags': tags,
        };
    final directory = [
      league('lal', 'LaLiga', '10193', '1,780,100639,100350'),
      league('epl', 'Premier League', '10188', '1,82,306,100639,100350'),
      league('unl', 'UEFA Nations League', '11446', '1,100639,100350,100816'),
      league('ucl', 'UEFA Champions League', '10204', '1,100977,100639,1234,100350'),
      league('nfl', 'NFL', '12185', '1,450,100639'),
      league('nba', 'NBA', '10345', '1,745,100639'),
      league('cfb', 'College Football', '12756', '1,100351,100639'),
      league('ufc', 'UFC', '38', '1,100639,279'),
      league('ufl', 'UFL', '12553', '1,100639,1186,105925'),
      league('boxing', 'Boxing', '12578', '1,683'),
      league('lol', 'LoL', '10311', '1,64,65,100639'),
      league('kbo', 'KBO', '10370', '1,100639,678'),
      league('atp', 'ATP Tour', '10365', '1,864,100639,101232'),
    ];

    test('Sports: Live, Futures, the pinned leagues, the site sports; no All',
        () {
      final subs = polySportsSubsFromLeagues(directory);
      final keys = [for (final s in subs) s.key];
      // The six the site pins, in its order, by their `/sports` codes.
      expect(keys.take(8), [
        'live', 'futures', 'series:12185', 'series:10345', 'series:12756',
        'series:38', 'series:10204', 'series:11446', //
      ]);
      expect(kPolySportsPinnedLeagues, ['nfl', 'nba', 'cfb', 'ufc', 'ucl', 'unl']);
      // Then the site's sports in its order, then the extras Gamma lists.
      expect(keys.skip(8), kPolySportGroups);
      expect(kPolySiteSports, [
        'soccer', 'tennis', 'cricket', 'basketball', 'football', 'hockey',
        'rugby', 'table-tennis', 'darts', 'volleyball', 'golf', 'mma', //
      ]);
      expect(kPolySportExtras,
          ['baseball', 'handball', 'motorsports', 'cycling', 'chess']);
      expect(keys, isNot(contains('all')));
      // A pinned league is not repeated among the sports; an unpinned
      // league (LaLiga) is not on this row: it is under Soccer.
      expect(keys, isNot(contains('series:10193')));
      // A league carries its logo and name; a sport only when Gamma lists
      // a logo.
      expect(subs[2].label, 'NFL');
      expect(subs[2].imageUrl, 'https://example.com/nfl.png');
      expect(subs[2].route, 'nfl');
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
      // Without the directory the row is still whole: the sports alone.
      expect(
          [for (final s in polySportsSubsFromLeagues(const [])) s.key],
          ['live', 'futures', ...kPolySportGroups]);
      // A directory with only some pinned leagues pins those.
      final some = polySportsSubsFromLeagues([directory[4], directory[0]]);
      expect([for (final s in some) s.key].take(3),
          ['live', 'futures', 'series:12185']);
    });

    test('Sports: the extra sports go by the volume of their leagues', () {
      // Handball's league is the most traded: Handball before Baseball.
      final ranked = [
        league('hbbundesliga', 'Handball Bundesliga', '12557',
            '1,100639,102897,105929'),
        league('kbo', 'KBO', '10370', '1,100639,678'),
      ];
      final keys = [
        for (final s in polySportsSubsFromLeagues(directory, ranked: ranked))
          s.key
      ];
      expect(keys.skip(8 + kPolySiteSports.length),
          ['handball', 'baseball', 'motorsports', 'cycling', 'chess']);
      // Only baseball ranked: it leads the extras; the rest keep their order.
      final baseball = [
        for (final s in polySportsSubsFromLeagues(directory,
            ranked: [ranked[1]]))
          s.key
      ];
      expect(baseball.skip(8 + kPolySiteSports.length),
          ['baseball', 'handball', 'motorsports', 'cycling', 'chess']);
    });

    PolymarketEvent game(String id, String series, double volume24hr) =>
        PolymarketEvent(
          id: id,
          slug: id,
          title: id,
          volume: volume24hr,
          volume24hr: volume24hr,
          liquidity: 0,
          category: 'sports',
          conditionId: id,
          outcomes: const [],
          seriesId: series,
        );

    test('a sport with leagues drills into them: All, then by 24 h volume',
        () {
      expect(polySportHasLeagues('soccer'), isTrue);
      expect(polySportHasLeagues('football'), isTrue);
      expect(polySportHasLeagues('mma'), isTrue);
      expect(polySportHasLeagues('rugby'), isFalse);
      expect(polySportHasLeagues('darts'), isFalse);
      expect(polySportHasLeagues('golf'), isFalse);
      expect(kPolySportLeagueSources.keys, [
        'soccer', 'tennis', 'cricket', 'basketball', 'football', 'hockey',
        'table-tennis', 'volleyball', 'mma', //
      ]);
      // Soccer's leagues carry its tag; esports never count.
      expect(
          [for (final l in polySportLeagues('soccer', directory)) l['sport']],
          ['lal', 'epl', 'unl', 'ucl']);
      // American football and combat have no sport tag on the rows: by code.
      expect(
          [for (final l in polySportLeagues('football', directory)) l['sport']],
          ['nfl', 'cfb', 'ufl']);
      expect([for (final l in polySportLeagues('mma', directory)) l['sport']],
          ['ufc', 'boxing']);
      expect(polySportLeagues('rugby', directory), isEmpty);

      // The league row: the sport first (its chip reads All), then the
      // leagues with trade in the sport's own list, most traded first.
      final subs = polySportLeagueSubs('soccer', directory, [
        game('a', '10188', 100),
        game('b', '10193', 300),
        game('c', '10193', 50),
        game('d', '10204', 200),
        game('e', '12185', 900), // NFL: not a soccer league
        game('f', '10345', 900), // NBA: not a soccer league
      ]);
      expect([for (final s in subs) s.key],
          ['soccer', 'series:10193', 'series:10204', 'series:10188']);
      expect(subs[1].label, 'LaLiga');
      expect(subs[1].imageUrl, 'https://example.com/lal.png');
      expect(subs[1].route, 'lal');
      // The list not landed: the sport alone, the row still drills.
      expect([for (final s in polySportLeagueSubs('soccer', directory, [])) s.key],
          ['soccer']);
      // A sport with no league level: itself alone.
      expect(polySportLeagueSubs('rugby', directory, [game('a', '1', 1)]),
          hasLength(1));
      // Only the first thirty rows rank, so a page landing later never
      // reorders the chips.
      final late = polySportLeagueSubs('soccer', directory, [
        for (var i = 0; i < 30; i++) game('a$i', '10188', 1),
        game('z', '10193', 5000),
      ]);
      expect([for (final s in late) s.key], ['soccer', 'series:10188']);
    });

    test('a league picked elsewhere opens the row it is on', () {
      // LaLiga is under Soccer; NFL is pinned on the Sports row itself
      // (and also under Football), so the Sports row stays.
      expect(polySportOfLeague('series:10193', directory), 'soccer');
      expect(polySportOfLeague('series:12185', directory), isNull);
      expect(polySportOfLeague('series:12553', directory), 'football');
      expect(polySportOfLeague('series:12578', directory), 'mma');
      // A baseball league: Baseball has no league level.
      expect(polySportOfLeague('series:10370', directory), isNull);
      expect(polySportOfLeague('soccer', directory), isNull);
      expect(polySportOfLeague('live', directory), isNull);
      expect(polySportOfLeague('series:10193', const []), isNull);
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
      // Instant is a category of the list, with its own page and no
      // subcategories.
      expect(polyBrowseSelectionFromRouteKey('predictions/instant')!.pill,
          PolyPill.instant);
      expect(PolyPillX.fromKey('instant'), PolyPill.instant);
      final old = polyBrowseSelectionFromRouteKey('predictions/world')!;
      expect(old.pill, PolyPill.geopolitics);
    });

    test('Instant reads no list of its own and is no neighbour to prefetch',
        () {
      expect(
          polyFeedSourceParams(const PolyFeedQuery(pill: PolyPill.instant)),
          isEmpty);
      final around = PolyFeedPrefetch.queriesAround(
        selection: const PolyBrowseSelection(pill: PolyPill.trending),
        pills: const [PolyPill.trending, PolyPill.instant],
        subs: const [],
      );
      expect(around, isEmpty);
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
