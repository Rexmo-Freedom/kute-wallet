// How fast a Predictions list opens: the live lists come from one small
// live read, the league chips wait for the list, a keyset read races the
// Kute feed against Gamma, the lists next to the one on screen are read
// ahead, and a pull-to-refresh reads only the list on screen.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/services/polymarket/market_protocol.dart';
import 'package:kute/services/polymarket/polymarket_feed_cache.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import '../helpers/runtime_policy_fixture.dart';

final _future = DateTime.now().add(const Duration(days: 2)).toIso8601String();

Map<String, dynamic> _event(
  String slug, {
  String? period,
  String? score,
  List<String> tags = const ['sports'],
  String? series,
  String? stream,
  double volume24hr = 0,
  String description = '',
}) =>
    {
      'id': slug,
      'slug': slug,
      'title': '$slug title',
      'active': true,
      'closed': false,
      'live': true,
      'endDate': _future,
      'volume24hr': volume24hr,
      'description': description,
      if (period != null) 'period': period,
      if (score != null) 'score': score,
      if (stream != null) 'resolutionSource': stream,
      if (series != null) 'series': [
        {'id': series}
      ],
      'tags': [
        for (final t in tags) {'slug': t}
      ],
      'markets': [
        {
          'id': 'm-$slug',
          'question': '$slug?',
          'outcomes': '["Yes","No"]',
          'outcomePrices': '["0.5","0.5"]',
          'clobTokenIds': '["y-$slug","n-$slug"]',
          'conditionId': '0x$slug',
          'active': true,
        }
      ],
    };

http.Response _page(List<Map<String, dynamic>> events, {String? next}) =>
    http.Response(
        jsonEncode({'events': events, if (next != null) 'next_cursor': next}),
        200);

/// What `events/keyset?live=true` answers: games in play (esports, a
/// tennis match, LoL), a game Gamma flags live before kickoff, a finished
/// one, and a stream that is not a game.
final _liveRows = [
  _event('cs2-a-b-2026-10-07',
      period: '2/3', score: '8-9|1-0|Bo3', tags: ['sports', 'esports', 'cs2']),
  _event('atp-c-d-2026-10-07',
      period: 'S2', score: '6-7, 3-3', tags: ['sports', 'tennis']),
  _event('lol-e-f-2026-10-07',
      period: '5/5',
      score: '0-0|2-2|Bo5',
      tags: ['sports', 'esports', 'league-of-legends']),
  _event('nfl-g-h-2026-10-07', tags: ['sports', 'nfl']),
  _event('epl-i-j-2026-10-07',
      period: 'FT', score: '2-1', tags: ['sports', 'soccer']),
  _event('trump-speech',
      tags: ['politics'], stream: 'https://www.twitch.tv/somechannel'),
];

const _inPlay = {
  'cs2-a-b-2026-10-07',
  'atp-c-d-2026-10-07',
  'lol-e-f-2026-10-07',
};

const _sportsLive = PolyFeedQuery(pill: PolyPill.sports, sub: 'live');
const _livePill = PolyFeedQuery(pill: PolyPill.live);

void main() {
  late RuntimeCapabilitiesService policy;

  setUp(() async {
    AffiliateService.debugSessionToken = 'test-session';
    dotenv.clean();
    polyForgetLiveRead();
    PolyFeedPrefetch.debugReset();
    PolymarketFeedCache.instance.debugClearMemory();
    policy = runtimePolicyFixture();
    expect(await policy.refresh(), isTrue);
  });

  tearDown(() {
    policy.dispose();
    AffiliateService.debugSessionToken = null;
    dotenv.clean();
    PolyMarketProtocol.debugV2MarketIdsOverride = null;
  });

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      runtimeCapabilitiesProvider.overrideWithValue(policy),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<void> firstRead(ProviderContainer c, PolyFeedQuery q) =>
      c.read(polyBrowseFeedProvider(q).notifier).firstRead;

  group('live lists', () {
    test('one live read gives every game in play, esports included', () async {
      final seen = <Uri>[];
      await http.runWithClient(() async {
        final c = container();
        final sports =
            c.listen(polyBrowseFeedProvider(_sportsLive), (_, __) {});
        final live = c.listen(polyBrowseFeedProvider(_livePill), (_, __) {});
        await firstRead(c, _sportsLive);
        await firstRead(c, _livePill);
        expect({for (final e in sports.read().events) e.slug}, _inPlay);
        expect({for (final e in live.read().events) e.slug}, _inPlay);
        // Livestream and the Esports chips read the same answer.
        expect([for (final e in await readPolyLiveStreams()) e.slug],
            ['trump-speech']);
        final chips = await c.read(polyEsportsSubsProvider.future);
        expect(chips, isNotEmpty);
      }, () => MockClient((request) async {
            if (request.url.path == '/sports') {
              return http.Response('[]', 200);
            }
            seen.add(request.url);
            return _page(_liveRows);
          }));
      expect(seen, hasLength(1));
      expect(seen.single.host, 'gamma-api.polymarket.com');
      expect(seen.single.path, '/events/keyset');
      expect(seen.single.queryParameters,
          {'live': 'true', 'closed': 'false', 'limit': '100'});
    });

    test('a failed live read is not kept', () async {
      var calls = 0;
      await http.runWithClient(() async {
        await expectLater(readPolyLiveGames(), throwsA(anything));
        expect({for (final e in await readPolyLiveGames()) e.slug}, _inPlay);
      }, () => MockClient((_) async {
            calls++;
            return calls == 1 ? http.Response('down', 503) : _page(_liveRows);
          }));
      expect(calls, 2);
    });
  });

  group('league chips', () {
    final directory = [
      for (final s in ['nfl', 'atp', 'cs2', 'mlb'])
        {
          'sport': s,
          'name': s.toUpperCase(),
          'image': 'https://example.com/$s.png',
          'series': 'series-$s',
          'tags': s == 'cs2' ? '1,64' : '1',
        }
    ];

    test('rank from 30 rows, after the list has landed, kept ten minutes',
        () async {
      final ranks = <Uri>[];
      late ProviderContainer c;
      bool? listLoadingAtRank;
      await http.runWithClient(() async {
        c = container();
        // The chips are asked for first, as the bar may build first.
        c.listen(polyLeagueRowsProvider, (_, __) {});
        c.listen(polyBrowseFeedProvider(_sportsLive), (_, __) {});
        await firstRead(c, _sportsLive);
        expect(c.read(polyBrowseFeedProvider(_sportsLive)).loading, isFalse);
        final rows = await _until(c, polyLeagueRowsProvider,
            (List<Map<String, dynamic>> r) => r.isNotEmpty);
        expect([for (final r in rows) r['sport']], ['atp', 'cs2', 'nfl']);
        // Another Sports open within ten minutes reads nothing.
        c.invalidate(polyLeagueRowsProvider);
        await c.read(polyLeagueRowsProvider.future);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }, () => MockClient((request) async {
            final q = request.url.queryParameters;
            if (request.url.path == '/sports') {
              return http.Response(jsonEncode(directory), 200);
            }
            if (q['live'] == 'true') {
              await Future<void>.delayed(const Duration(milliseconds: 150));
              return _page(_liveRows);
            }
            ranks.add(request.url);
            listLoadingAtRank =
                c.read(polyBrowseFeedProvider(_sportsLive)).loading;
            return _page([
              _event('a', series: 'series-atp', volume24hr: 500),
              _event('b', series: 'series-cs2', volume24hr: 300),
              _event('c', series: 'series-nfl', volume24hr: 100),
              _event('d', series: 'series-atp', volume24hr: 10),
            ]);
          }));
      expect(ranks, hasLength(1));
      expect(ranks.single.queryParameters['limit'], '30');
      expect(ranks.single.queryParameters['order'], 'volume24hr');
      expect(listLoadingAtRank, isFalse,
          reason: 'the ranking read starts after the list has landed');
    });

    test('the Live list names a league the ranking does not reach', () {
      final subs = polyLiveLeagueSubs([directory[1]], directory);
      expect([for (final s in subs) s.seriesId],
          ['series-atp', 'series-nfl', 'series-cs2', 'series-mlb']);
      expect(polyRankLeagues(directory, [
        _event('x', series: 'series-mlb', volume24hr: 1),
        _event('y', series: 'unknown', volume24hr: 99),
      ]).map((r) => r['sport']), ['mlb']);
    });
  });

  group('Kute feed and Gamma race', () {
    setUp(() => dotenv.loadFromString(envString: 'BACKEND=https://backend.test'));

    Future<({List<String> ids, List<(String, int)> log, int ms})> race(
      Future<http.Response> Function() feed,
      Future<http.Response> Function() gamma,
    ) async {
      final log = <(String, int)>[];
      final clock = Stopwatch()..start();
      final page = await http.runWithClient(
        () => PolymarketModel.readGammaKeysetPage(
            'events', const {'tag_slug': 'politics'},
            limit: 20),
        () => MockClient((request) async {
          final isFeed = request.url.host == 'backend.test';
          log.add((isFeed ? 'feed' : 'gamma', clock.elapsedMilliseconds));
          if (isFeed) {
            expect(request.url.path, '/api/v1/pm/feed/events');
          } else {
            expect(request.url.path, '/events/keyset');
          }
          return isFeed ? feed() : gamma();
        }),
      );
      return (
        ids: [for (final r in page.rows) '${r['id']}'],
        log: log,
        ms: clock.elapsedMilliseconds,
      );
    }

    test('a quick feed answers alone', () async {
      final r = await race(
        () async => _page([_event('from-feed')]),
        () async => _page([_event('from-gamma')]),
      );
      expect(r.ids, ['from-feed']);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(r.log.map((e) => e.$1), ['feed']);
    });

    test('a slow feed: Gamma starts after the head start and wins', () async {
      final r = await race(
        () async {
          await Future<void>.delayed(const Duration(seconds: 2));
          return _page([_event('from-feed')]);
        },
        () async => _page([_event('from-gamma')]),
      );
      expect(r.ids, ['from-gamma']);
      final gammaAt = r.log.firstWhere((e) => e.$1 == 'gamma').$2;
      expect(gammaAt, greaterThanOrEqualTo(450));
      expect(r.ms, lessThan(1500));
    });

    test('a failed feed: Gamma at once', () async {
      final r = await race(
        () async => http.Response('down', 503),
        () async => _page([_event('from-gamma')]),
      );
      expect(r.ids, ['from-gamma']);
      expect(r.log.firstWhere((e) => e.$1 == 'gamma').$2, lessThan(300));
    });

    test('a feed that never answers is given up after three seconds',
        () async {
      final clock = Stopwatch()..start();
      await expectLater(
        race(
          () => Completer<http.Response>().future,
          () async => http.Response('down', 502),
        ),
        throwsA(isA<http.ClientException>()),
      );
      expect(clock.elapsed, lessThan(const Duration(seconds: 4)));
      expect(clock.elapsed,
          greaterThanOrEqualTo(const Duration(milliseconds: 2900)));
    });

    test('a feed that never answers and a slow Gamma: Gamma wins', () async {
      final r = await race(
        () => Completer<http.Response>().future,
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return _page([_event('from-gamma')]);
        },
      );
      expect(r.ids, ['from-gamma']);
      expect(r.ms, lessThan(1000));
    });
  });

  test('a large events page is parsed off the UI isolate with its V2 switch',
      () async {
    PolyMarketProtocol.debugV2MarketIdsOverride = {'m-big-0'};
    final rows = [
      for (var i = 0; i < 30; i++)
        {
          ..._event('big-$i', description: 'x' * 4000),
          'markets': [
            {
              ...(_event('big-$i')['markets'] as List).first
                  as Map<String, dynamic>,
              'positionIds': ['${i + 1}1', '${i + 1}2'],
            }
          ],
        }
    ];
    final body = jsonEncode({'events': rows});
    expect(body.length, greaterThan(64 * 1024));
    final page = await http.runWithClient(
      () => PolymarketModel.readGammaEventsPage(const {'active': 'true'},
          limit: 30),
      () => MockClient((_) async => http.Response(body, 200)),
    );
    expect(page.events, hasLength(30));
    // The worker read market m-big-0 as V2 (its positionIds), the rest
    // as V1, as the app isolate would.
    expect(page.events.first.outcomes.first.tokenId, '11');
    expect(page.events[1].outcomes.first.tokenId, 'y-big-1');
  });

  group('caching and prefetch', () {
    test('the disk cache holds every pill and the recent chips', () {
      expect(PolymarketFeedCache.maxEventEntries, 48);
      expect(PolymarketFeedCache.maxEventBytes, 4 * 1024 * 1024);
    });

    test('the lists around the one on screen: the pills, then the chips', () {
      final selection = const PolyBrowseSelection(pill: PolyPill.sports);
      final pills = [
        PolyPill.trending,
        PolyPill.live,
        PolyPill.politics,
        PolyPill.sports,
        PolyPill.crypto,
      ];
      final queries = PolyFeedPrefetch.queriesAround(
        selection: selection,
        pills: pills,
        subs: polySportsSubsFromLeagues(const []),
      );
      expect([for (final q in queries) '${q.pill.key}/${q.sub}'], [
        'crypto/all', 'politics/all', 'sports/futures', 'sports/soccer',
        'sports/tennis', //
      ]);
      // The Live pill's chips filter the one list on screen.
      final live = PolyFeedPrefetch.queriesAround(
        selection: const PolyBrowseSelection(pill: PolyPill.live),
        pills: pills,
        subs: const [PolySub('all'), PolySub('series:1')],
      );
      expect([for (final q in live) '${q.pill.key}/${q.sub}'],
          ['politics/all', 'trending/all']);
    });

    test('one read at a time, four per landing, none read twice', () async {
      final tags = <String>[];
      var inFlight = 0;
      var maxInFlight = 0;
      await http.runWithClient(() async {
        final c = container();
        final queries = [
          for (final t in ['politics', 'crypto', 'finance', 'tech', 'culture'])
            PolyFeedQuery(pill: PolyPillX.fromKey(t)!),
        ];
        await PolyFeedPrefetch.run(
            queries, (q) => c.read(polyBrowseFeedProvider(q).notifier));
        expect(tags, ['politics', 'crypto', 'finance', 'tech']);
        // Each stays in memory: opening it paints the rows read.
        expect(c.read(polyBrowseFeedProvider(queries.first)).events,
            isNotEmpty);
        await PolyFeedPrefetch.run(
            queries.take(4).toList(),
            (q) => c.read(polyBrowseFeedProvider(q).notifier));
        expect(tags, hasLength(4));
      }, () => MockClient((request) async {
            inFlight++;
            if (inFlight > maxInFlight) maxInFlight = inFlight;
            tags.add(request.url.queryParameters['tag_slug'] ?? '');
            await Future<void>.delayed(const Duration(milliseconds: 20));
            inFlight--;
            return _page([_event('row-${tags.length}', tags: ['politics'])]);
          }));
      expect(maxInFlight, 1);
    });
  });

  group('pull to refresh', () {
    test('reads the list on screen again, and only it', () async {
      final tags = <String>[];
      await http.runWithClient(() async {
        final c = container();
        const politics = PolyFeedQuery(pill: PolyPill.politics);
        const crypto = PolyFeedQuery(pill: PolyPill.crypto);
        c.listen(polyBrowseFeedProvider(politics), (_, __) {});
        c.listen(polyBrowseFeedProvider(crypto), (_, __) {});
        await firstRead(c, politics);
        await firstRead(c, crypto);
        expect(tags..sort(), ['crypto', 'politics']);
        polyRefreshBrowse(
            query: politics, pill: PolyPill.politics, invalidate: c.invalidate);
        await firstRead(c, politics);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(tags.where((t) => t == 'politics'), hasLength(2));
        expect(tags.where((t) => t == 'crypto'), hasLength(1));
      }, () => MockClient((request) async {
            tags.add(request.url.queryParameters['tag_slug'] ?? '');
            return _page([_event('row', tags: ['politics'])]);
          }));
    });

    test('the Live list reads the live events again', () async {
      var reads = 0;
      await http.runWithClient(() async {
        final c = container();
        c.listen(polyBrowseFeedProvider(_livePill), (_, __) {});
        await firstRead(c, _livePill);
        polyRefreshBrowse(
            query: _livePill, pill: PolyPill.live, invalidate: c.invalidate);
        await firstRead(c, _livePill);
      }, () => MockClient((request) async {
            if (request.url.queryParameters['live'] == 'true') reads++;
            return _page(_liveRows);
          }));
      expect(reads, 2);
    });
  });
}

/// The provider's value once [done] holds for it.
Future<T> _until<T>(ProviderContainer c,
    ProviderListenable<AsyncValue<T>> provider, bool Function(T) done) {
  final out = Completer<T>();
  final sub = c.listen<AsyncValue<T>>(provider, (_, next) {
    final v = next.valueOrNull;
    if (v != null && done(v) && !out.isCompleted) out.complete(v);
  }, fireImmediately: true);
  return out.future
      .timeout(const Duration(seconds: 5))
      .whenComplete(sub.close);
}
