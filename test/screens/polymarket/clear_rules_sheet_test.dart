import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/screens/polymarket/components/clear_rules_sheet.dart';

void main() {
  test('reads the market description from /markets/keyset, closed first',
      () async {
    final seen = <Uri>[];
    final client = MockClient((request) async {
      seen.add(request.url);
      if (request.url.queryParameters['closed'] == 'true') {
        return http.Response(jsonEncode({'markets': <Object>[]}), 200);
      }
      return http.Response(
          jsonEncode({
            'markets': [
              {'conditionId': '0xc1', 'description': '  First 90 minutes only. '}
            ],
          }),
          200);
    });
    final rules = await fetchPolymarketMarketRules('0xc1', client: client);
    expect(rules, 'First 90 minutes only.');
    expect(seen, hasLength(2));
    for (final uri in seen) {
      expect(uri.host, 'gamma-api.polymarket.com');
      expect(uri.path, '/markets/keyset');
      expect(uri.queryParameters['condition_ids'], '0xc1');
    }
    expect(seen.first.queryParameters['closed'], 'true');
    expect(seen.last.queryParameters.containsKey('closed'), isFalse);

    // A resolved market's rules never change: the second read is served
    // from the session cache without a request.
    final again = await fetchPolymarketMarketRules('0xc1',
        client: MockClient((_) async => fail('must not refetch')));
    expect(again, 'First 90 minutes only.');
  });

  test('a market without a description yields null, not an empty string',
      () async {
    final rules = await fetchPolymarketMarketRules('0xc2',
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'markets': [
                {'conditionId': '0xc2', 'description': '   '}
              ]
            }),
            200)));
    expect(rules, isNull);
  });

  test('a failed read yields null', () async {
    final rules = await fetchPolymarketMarketRules('0xc3',
        client: MockClient((_) async => http.Response('down', 503)));
    expect(rules, isNull);
  });
}
