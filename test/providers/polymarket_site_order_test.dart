// Every level of the Predictions categories follows polymarket.com's own
// order (founder, 9 November 2026: "please rank categories properly as they
// are in the website"), and Trending is the site's Trending: the views its
// pages read, parsed here from their real shapes.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_site_order.dart';

PolymarketEvent _event(String slug) => PolymarketEvent(
      id: slug,
      slug: slug,
      title: slug,
      volume: 1,
      liquidity: 0,
      category: 'politics',
      conditionId: slug,
      outcomes: const [],
    );

Map<String, dynamic> _row(String code, String series, {String tags = '1'}) =>
    {'sport': code, 'name': code, 'series': series, 'tags': tags};

void main() {
  group('the side list', () {
    test('parses the sidebar of a site view', () {
      final site = PolySiteSports.fromView({
        'sidebar': {
          'sections': [
            {
              'label': 'Leagues',
              'items': [
                {
                  'id': 'soccer',
                  'scope': 'soccer',
                  'count': 848,
                  'children': [
                    {'id': '1', 'scope': 'epl', 'count': 9},
                    {'id': '2', 'scope': 'laliga', 'count': 9},
                  ],
                },
                {'id': '37', 'scope': 'cs2', 'count': 77},
                {'id': 'baseball', 'scope': 'baseball', 'count': 0},
              ],
            }
          ]
        }
      })!;
      expect(site.leagues, {
        'soccer': ['epl', 'laliga']
      });
      expect(site.flat, ['cs2', 'baseball']);
      expect(site.hasMarkets('soccer'), isTrue);
      expect(site.hasMarkets('baseball'), isFalse);
      expect(site.listsLeague('lal'), isTrue, reason: 'scope laliga is code lal');
      expect(site.listsLeague('mlb'), isFalse);
      // The disk's copy comes back the same.
      final again = PolySiteSports.fromRow(site.toRow())!;
      expect(again.leagues, site.leagues);
      expect(again.flat, site.flat);
      expect(again.counts, site.counts);
    });

    test('no sidebar is no list', () {
      expect(PolySiteSports.fromView(const {}), isNull);
      expect(PolySiteSports.fromRow(const {'leagues': 1}), isNull);
    });

    test('Soccer, as the site lists it on the 9 November 2026 snapshot', () {
      final codes = [
        'epl', 'lal', 'bun', 'sea', 'unl', 'es2', 'spl', 'fif', 'ucl', 'el1',
        'ned2', 'lva1', //
      ];
      final directory = [
        // Gamma's own order, which must not matter.
        for (final c in codes.reversed)
          _row(c, c, tags: '1,100639,100350'),
      ];
      final subs = polySportLeagueSubs('soccer', directory, const []);
      expect([for (final s in subs.skip(1)) s.route], codes);
    });

    test('a live list moves the chips, an empty sport falls behind', () {
      const site = PolySiteSports(
        leagues: {
          'soccer': ['ucl', 'epl'],
        },
        flat: ['cbb'],
        counts: {'tennis': 3, 'soccer': 9},
      );
      final directory = [
        _row('epl', 'e', tags: '1,100350'),
        _row('ucl', 'u', tags: '1,100350'),
        _row('cbb', 'c', tags: '1,28'),
        _row('nba', 'n', tags: '1,28'),
        _row('nfl', 'f'),
      ];
      expect(
          [
            for (final s
                in polySportLeagueSubs('soccer', directory, const [], site: site))
              s.route
          ],
          ['soccer', 'ucl', 'epl']);
      // A league listed on its own goes under its sport, after the sport's.
      expect(
          [
            for (final s in polySportLeagueSubs('basketball', directory,
                const [], site: site))
              s.route
          ],
          ['basketball', 'cbb']);
      final row = [
        for (final s in polySportsSubsFromLeagues(directory, site: site)) s.key
      ];
      // NFL and NBA are not on this side list, so not pinned; the sports the
      // list has come first, in the site's order, not this list's.
      expect(row.take(5), ['live', 'futures', 'series:u', 'soccer', 'tennis']);
      expect(row, isNot(contains('series:f')));
    });
  });

  test('the topics: each row in the site\'s order, as of 9 November 2026',
      () {
    List<String?> slugs(String pill) =>
        [for (final r in kPolySiteTopicRowsSnapshot[pill]!) r['slug']];
    expect(slugs('politics').take(5),
        ['trump', 'midterms', 'competitive-races', '2028-election', 'post-election']);
    expect(slugs('geopolitics').take(4), ['iran', 'lebanon', 'oil', 'ukraine']);
    expect(slugs('tech').take(4), ['ai', 'elon-musk', 'app-store', 'spacex']);
    expect(slugs('culture').take(3), ['art', 'music', 'celebrities']);
    expect(slugs('economy').take(3), ['trade-war', 'fed-rates', 'inflation']);
  });

  test('a topic\'s site view reads as rows, All left to the chip', () {
    expect(
        polySiteTopicRows(const {
          'sidebar': {
            'sections': [
              {
                'label': 'Politics',
                'items': [
                  {'id': '2', 'label': 'All', 'count': 2352},
                  {'id': '126', 'scope': 'trump', 'label': 'Trump', 'count': 321},
                  {'id': '514', 'scope': 'congress', 'label': 'Congress', 'count': 44},
                ],
              }
            ]
          }
        }),
        [
          {'id': '126', 'slug': 'trump', 'label': 'Trump', 'activeEventsCount': 321},
          {'id': '514', 'slug': 'congress', 'label': 'Congress', 'activeEventsCount': 44},
        ]);
  });

  test('the fixed rows, as the site\'s code and pages have them', () {
    expect(kPolySportGroups.take(5),
        ['soccer', 'tennis', 'cricket', 'basketball', 'baseball']);
    expect(kPolyBreakingTopics,
        ['all', 'politics', 'world', 'sports', 'crypto', 'finance', 'tech', 'culture']);
    expect(kPolyWeatherSubs.take(4),
        ['all', 'temperature', 'precipitation', 'drought']);
    expect(kPolyFinanceSubs.take(5),
        ['all', 'daily', 'weekly', 'monthly', 'stocks']);
    // The top row: Trending, Breaking, New, Live, then the site's topics.
    expect(
        [for (final p in PolyPill.values) p.key].skip(2), [
      'breaking', 'new', 'live', 'politics', 'sports', 'crypto', 'esports',
      'finance', 'geopolitics', 'tech', 'elections', 'culture', 'economy',
      'weather', 'mentions', 'art', //
    ]);
    expect(
        [for (final s in polyCryptoSubsFromCounts(null)) s.key],
        [
          'all', '5m', '15m', '1h', '4h', 'daily', 'weekly', 'monthly',
          'yearly', 'targets', 'pre-market', 'institutions', 'industry',
          'protocol-metrics', 'bitcoin', 'ethereum', 'solana', 'xrp',
          'dogecoin', 'bnb', 'microstrategy', //
        ]);
  });

  group('Trending is the site\'s', () {
    test('its slugs and cursor out of the home view, and out of a next page',
        () {
      final home = polySiteTrendingPage(const {
        'sections': [
          {'type': 'categories', 'items': []},
          {
            'type': 'feed',
            'events': [
              {'slug': 'who-will-leave'},
              {'slug': 'btc-updown-5m-1794234900'},
              {'slug': 'presidential-election-winner-2028'},
            ],
            'nextCursor': 'abc',
          },
        ]
      });
      expect(home.slugs, [
        'who-will-leave',
        'btc-updown-5m-1794234900',
        'presidential-election-winner-2028'
      ]);
      expect(home.cursor, 'abc');
      final next = polySiteTrendingPage(const {
        'items': [
          {'slug': 'x'}
        ],
        'nextCursor': null,
      });
      expect(next.slugs, ['x']);
      expect(next.cursor, isNull);
    });

    test('the 5-minute rounds stay with Crypto › 5 Min; nothing else leaves',
        () {
      expect(
          polyDropFiveMinute(const [
            'a',
            'btc-updown-5m-1794234900',
            'btc-updown-15m-1794234900',
            'b',
          ]),
          ['a', 'btc-updown-15m-1794234900', 'b']);
    });

    test('the cards land in the site\'s order, whatever Gamma answers', () {
      expect(
          [
            for (final e in polyInSiteOrder(
                const ['c', 'gone', 'a', 'b'], [_event('a'), _event('b'), _event('c')]))
              e.slug
          ],
          ['c', 'a', 'b']);
    });

    test('with the site silent, the most traded keep the list from going '
        'blank', () {
      expect(polyFeedSourceParams(const PolyFeedQuery(pill: PolyPill.trending)),
          [
            {
              'active': 'true',
              'closed': 'false',
              'order': 'volume24hr',
              'ascending': 'false',
            }
          ]);
    });
  });
}
