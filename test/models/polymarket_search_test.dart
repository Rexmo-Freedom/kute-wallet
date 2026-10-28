// The venue search: one bounded Gamma page, most traded first, open
// markets only inside an open event, and a localized name searched in
// English too.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/polymarket_model.dart';

Map<String, Object> market(int index, {double? volumeNum, bool closed = false,
        bool? acceptingOrders}) =>
    {
      'id': 'market-$index',
      'question': 'Will Bitcoin rise $index?',
      'conditionId': 'condition-$index',
      'active': true,
      'closed': closed,
      if (acceptingOrders != null) 'acceptingOrders': acceptingOrders,
      'outcomes': '["Yes","No"]',
      'outcomePrices': '["0.6","0.4"]',
      'liquidityNum': 5000,
      if (volumeNum != null) 'volumeNum': volumeNum,
    };

Map<String, Object> event(int index,
        {double? volumeNum, double? volume, List<Map<String, Object>>? markets}) =>
    {
      'id': '$index',
      'slug': 'bitcoin-$index',
      'title': 'Bitcoin $index',
      'active': true,
      'closed': false,
      'liquidity': 5000,
      if (volume != null) 'volume': volume,
      'markets': markets ?? [market(index, volumeNum: volumeNum)],
    };

http.Response page(List<Map<String, Object>> events) =>
    http.Response(jsonEncode({'events': events}), 200);

void main() {
  test('typeahead uses one bounded public request and caps provider overflow',
      () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.path, '/public-search');
      expect(request.url.queryParameters['q'], 'btc');
      expect(request.url.queryParameters['limit_per_type'], '50');
      expect(request.url.queryParameters['events_status'], 'active');
      expect(request.url.queryParameters['keep_closed_markets'], '0');
      expect(request.url.queryParameters['search_profiles'], 'false');
      expect(request.url.queryParameters['search_tags'], 'false');
      expect(request.url.queryParameters['sort'], 'relevance');
      return page(List.generate(100, (i) => event(i, volumeNum: 1)));
    });
    final model = PolymarketModel(searchClient: client);
    final rows = await model.searchEvents(' btc ');
    expect(calls, 1);
    expect(rows, hasLength(50));
    expect(rows.first.title, 'Bitcoin 0');
    model.dispose();
    expect(await model.searchEvents('eth'), isEmpty);
    expect(calls, 1);
  });

  test('one malformed or closed event does not discard valid matches',
      () async {
    final model = PolymarketModel(
        searchClient: MockClient((_) async => page([
              {'id': 1, 'markets': 'malformed'},
              {...event(2), 'closed': true},
              event(3),
            ])));
    final rows = await model.searchEvents('Bitcoin');
    expect(rows.map((row) => row.id), ['3']);
    model.dispose();
  });

  test('most traded first, Gamma order for ties, no title re-ranking',
      () async {
    final model = PolymarketModel(
        searchClient: MockClient((_) async => page([
              {...event(1, volumeNum: 10), 'title': 'Bitcoin above 100k?'},
              {...event(2, volumeNum: 500), 'title': 'Will Saylor buy more?'},
              {...event(3, volumeNum: 10), 'title': 'Bitcoin ETF flows'},
              {...event(4, volumeNum: 90), 'title': 'Bitcoin dominance'},
            ])));
    final rows = await model.searchEvents('bitcoin');
    expect(rows.map((r) => r.id), ['2', '4', '1', '3']);
    model.dispose();
  });

  test("the event's volume stands in when its markets carry none", () async {
    final model = PolymarketModel(
        searchClient: MockClient((_) async => page([
              event(1, volumeNum: 100),
              event(2, volume: 2500),
              event(3, volume: 7, markets: [
                market(31, volumeNum: 40),
                market(32),
              ]),
            ])));
    final rows = await model.searchEvents('bitcoin');
    expect(rows.map((r) => r.id), ['2', '1', '3']);
    expect(rows[0].volume, 2500);
    expect(rows[2].volume, 40);
    model.dispose();
  });

  test('an open event shows only its tradable markets; all closed is noted',
      () async {
    final model = PolymarketModel(
        searchClient: MockClient((_) async => page([
              event(1, markets: [
                market(11, closed: true, acceptingOrders: false),
                market(12, acceptingOrders: true),
                market(13),
              ]),
              event(2, markets: [
                market(21, closed: true, acceptingOrders: false),
                market(22, acceptingOrders: false),
              ]),
            ])));
    final rows = await model.searchEvents('bitcoin');
    final open = rows.singleWhere((r) => r.id == '1');
    expect(open.outcomes.map((o) => o.name),
        ['Will Bitcoin rise 12?', 'Will Bitcoin rise 13?']);
    expect(open.marketsClosed, isFalse);
    final done = rows.singleWhere((r) => r.id == '2');
    expect(done.marketsClosed, isTrue);
    expect(done.outcomes, hasLength(2));
    model.dispose();
  });

  test('a localized name is searched in English too, merged once each',
      () async {
    final queries = <String>[];
    final model = PolymarketModel(searchClient: MockClient((request) async {
      final q = request.url.queryParameters['q']!;
      queries.add(q);
      if (q == 'brasil') {
        return page([
          {...event(1, volumeNum: 50), 'title': 'Copa do Brasil: Champion'},
          {...event(2, volumeNum: 5), 'title': 'CR Brasil vs. Londrina'},
        ]);
      }
      return page([
        {...event(3, volumeNum: 9000), 'title': 'Brazil Presidential Election'},
        {...event(1, volumeNum: 50), 'title': 'Copa do Brasil: Champion'},
      ]);
    }));
    final rows = await model.searchEvents('brasil');
    expect(queries.toSet(), {'brasil', 'brazil'});
    expect(rows.map((r) => r.id), ['3', '1', '2']);
    model.dispose();
  });

  test('a result is the Politics card: candidates by name, with their '
      'portraits, no placeholder seats', () async {
    // As public-search sends the Brazil event: per-market `image`, no
    // `groupItemImage`, the seats switched off with no prices.
    Map<String, Object?> candidate(String name, double yes,
            {bool closed = false}) =>
        {
          'id': name,
          'question': 'Will $name win the 2026 Brazilian presidential election?',
          'groupItemTitle': name,
          'conditionId': 'cond-$name',
          'active': true,
          'closed': closed,
          'acceptingOrders': !closed,
          'outcomes': '["Yes","No"]',
          'outcomePrices': '["$yes","${1 - yes}"]',
          'bestBid': closed ? null : yes - 0.005,
          'bestAsk': closed ? 0.001 : yes + 0.005,
          'lastTradePrice': closed ? 0.001 : yes,
          'clobTokenIds': '["y-$name","n-$name"]',
          'volumeNum': 1e6,
          'image': 'https://example.com/${name.length}.jpg',
        };
    Map<String, Object?> seat(String name) => {
          'id': name,
          'question': 'Will $name win?',
          'groupItemTitle': name,
          'active': false,
          'closed': false,
          'acceptingOrders': true,
          'outcomes': '["Yes","No"]',
          'outcomePrices': null,
          'bestBid': 0,
          'bestAsk': 1,
          'lastTradePrice': 0,
          'clobTokenIds': '["y-$name","n-$name"]',
          'image': 'https://example.com/flag-br.png',
        };
    final model = PolymarketModel(
        searchClient: MockClient((_) async => http.Response.bytes(
            utf8.encode(jsonEncode({
              'events': [
                {
                  'id': '45915',
                  'slug': 'brazil-presidential-election',
                  'title': 'Brazil Presidential Election',
                  'image': 'https://example.com/brazil.png',
                  'active': true,
                  'closed': false,
                  'negRisk': true,
                  'tags': [
                    {'id': '2', 'slug': 'politics', 'label': 'Politics'}
                  ],
                  'markets': [
                    candidate('Tarcisio de Freitas', 0, closed: true),
                    candidate('Luiz Inácio Lula da Silva', 0.215),
                    candidate('Flávio Bolsonaro', 0.7885),
                    seat('Person O'),
                    seat('Person P'),
                    seat('Other'),
                  ],
                },
              ],
            })),
            200)));
    final e = (await model.searchEvents('bolsonaro')).single;
    model.dispose();
    expect(e.outcomes.map((o) => o.name),
        ['Luiz Inácio Lula da Silva', 'Flávio Bolsonaro']);
    expect(e.outcomes.map((o) => o.imageUrl), [
      'https://example.com/25.jpg', // Lula's portrait
      'https://example.com/16.jpg', // Flávio's
    ]);
    // Both sides of each candidate, for its Yes / No slip.
    expect(e.outcomes.every((o) => o.hasYesNo && o.conditionId != null),
        isTrue);
    // The card's icon is the leading candidate's face, as in Politics.
    expect(e.displayIconUrl, 'https://example.com/16.jpg');
    expect(e.category, 'politics');
    expect(e.negRisk, isTrue);
    // Read as the category list reads the same event.
    final listed = PolymarketModel().parseEventsRaw([
      {
        'id': '45915',
        'slug': 'brazil-presidential-election',
        'title': 'Brazil Presidential Election',
        'active': true,
        'closed': false,
        'markets': [
          candidate('Luiz Inácio Lula da Silva', 0.215),
          candidate('Flávio Bolsonaro', 0.7885),
        ],
      },
    ]).single;
    expect(e.outcomes.map((o) => (o.name, o.price, o.imageUrl, o.tokenId)),
        listed.outcomes.map((o) => (o.name, o.price, o.imageUrl, o.tokenId)));
  });
}
