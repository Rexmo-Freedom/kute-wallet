import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/polymarket_model.dart';

Map<String, Object> event(int index) => {
  'id': '$index', 'slug': 'bitcoin-$index', 'title': 'Bitcoin $index',
  'active': true, 'closed': false, 'liquidity': 5000,
  'markets': [{
    'id': 'market-$index', 'question': 'Will Bitcoin rise?',
    'conditionId': 'condition-$index', 'active': true, 'closed': false,
    'outcomes': '["Yes","No"]', 'outcomePrices': '["0.6","0.4"]',
    'liquidityNum': 5000,
  }],
};

void main() {
  test('typeahead uses one bounded public request and caps provider overflow', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.path, '/public-search');
      expect(request.url.queryParameters['q'], 'btc');
      expect(request.url.queryParameters['limit_per_type'], '30');
      expect(request.url.queryParameters['search_profiles'], 'false');
      return http.Response(jsonEncode({'events': List.generate(100, event)}), 200);
    });
    final model = PolymarketModel(searchClient: client);
    final rows = await model.searchEvents(' btc ');
    expect(calls, 1);
    expect(rows, hasLength(30));
    expect(rows.first.title, 'Bitcoin 0');
    model.dispose();
    expect(await model.searchEvents('eth'), isEmpty);
    expect(calls, 1);
  });

  test('one malformed or closed event does not discard valid matches', () async {
    final model = PolymarketModel(searchClient: MockClient((_) async =>
      http.Response(jsonEncode({'events': [
        {'id': 1, 'markets': 'malformed'},
        {...event(2), 'closed': true}, event(3),
      ]}), 200)));
    final rows = await model.searchEvents('Bitcoin');
    expect(rows.map((row) => row.id), ['3']);
    model.dispose();
  });
}
