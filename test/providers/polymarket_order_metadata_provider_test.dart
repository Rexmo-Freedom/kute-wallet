import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/providers/polymarket_order_metadata_provider.dart';

void main() {
  test('deduplicates conditions and uses the documented batch filter',
      () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      // Keyset list route (`/markets` is being deprecated); its response
      // keys the rows under `markets`.
      expect(request.url.host, 'gamma-api.polymarket.com');
      expect(request.url.path, '/markets/keyset');
      expect(request.url.queryParametersAll['condition_ids'], ['a', 'b']);
      expect(request.url.queryParameters['limit'], '2');
      expect(request.url.queryParameters.containsKey('offset'), isFalse);
      return http.Response(
          jsonEncode({
            'markets': [
              {'conditionId': 'a', 'question': 'Will A win?', 'icon': 'a.svg'},
              {
                'conditionId': 'b',
                'question': 'Will B win?',
                'image': 'b.png'
              },
              {
                'conditionId': 'unrelated',
                'question': 'Wrong market',
                'icon': 'wrong'
              },
            ],
          }),
          200);
    });
    final result = await loadPolymarketOrderMetadata(['a', 'a', ' b ', ''],
        client: client);
    expect(requests, 1);
    expect(result.keys, ['a', 'b']);
    expect(result['a']!.title, 'Will A win?');
    expect(result['a']!.imageUrl, 'a.svg');
    expect(result['b']!.imageUrl, 'b.png');
  });

  test('large portfolios fetch bounded serial batches without per-row fanout',
      () async {
    var inFlight = 0;
    var maxInFlight = 0;
    final sizes = <int>[];
    final client = MockClient((request) async {
      inFlight++;
      if (inFlight > maxInFlight) maxInFlight = inFlight;
      final ids = request.url.queryParametersAll['condition_ids']!;
      sizes.add(ids.length);
      await Future<void>.delayed(Duration.zero);
      inFlight--;
      return http.Response(
          jsonEncode({
            'markets': [
              for (final id in ids)
                {'conditionId': id, 'question': id, 'icon': '$id.svg'},
            ],
          }),
          200);
    });
    final result = await loadPolymarketOrderMetadata(
        List.generate(53, (i) => '$i'),
        client: client);
    expect(sizes, [25, 25, 3]);
    expect(maxInFlight, 1);
    expect(result.length, 53);
  });

  test('a body without the markets envelope is a format error, not identity',
      () async {
    await expectLater(
        loadPolymarketOrderMetadata(['a'],
            client: MockClient((_) async => http.Response(
                jsonEncode([
                  {'conditionId': 'a', 'question': 'bare v1 array'}
                ]),
                200))),
        throwsA(isA<FormatException>()));
  });

  test('empty order set does not request markets', () async {
    final result =
        await loadPolymarketOrderMetadata([], client: MockClient((_) async {
      fail('Empty order set must not request a market feed');
    }));
    expect(result, isEmpty);
  });

  test('failed metadata does not turn an unrelated feed into order identity',
      () async {
    await expectLater(
        loadPolymarketOrderMetadata(['a'],
            client: MockClient((_) async => http.Response('unavailable', 503))),
        throwsA(isA<http.ClientException>()));
  });
}
