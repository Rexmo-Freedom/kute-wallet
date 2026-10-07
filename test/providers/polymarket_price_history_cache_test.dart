// A chart's history read answers whoever is waiting for it. The chart's
// provider waits on PolyPriceHistoryCache.load whenever the series is not
// in the session cache yet (a cold open, a range picked for the first
// time, a line past the ones a tap prefetches); a read that filled the
// cache but never answered left that chart on its placeholder.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';

String _page(int points) => jsonEncode({
      'data': [
        for (var i = 0; i < points; i++)
          {
            'timestamp': 1791000000 + i * 600,
            'price': 0.4 + i / 1000,
            'resolution_seconds': 600,
          },
      ],
    });

void main() {
  // The model keeps one client for the Data API for the whole process, so
  // both tests answer through this one: `token-b` is the series that
  // cannot be read.
  var requests = 0;
  final client = MockClient((request) async {
    requests++;
    return request.url.queryParameters['token_id'] == 'token-b'
        ? http.Response('unavailable', 503)
        : http.Response(_page(40), 200);
  });
  Future<T> withClient<T>(Future<T> Function() body) =>
      http.runWithClient(body, () => client);

  test('a read answers its caller, and a second caller that joins it',
      () async {
    await withClient(() async {
      final first = PolyPriceHistoryCache.load('token-a', '1d');
      final joined = PolyPriceHistoryCache.load('token-a', '1d');
      final points = await first.timeout(const Duration(seconds: 5));
      expect(points, hasLength(40));
      expect(await joined.timeout(const Duration(seconds: 5)), hasLength(40));
      expect(requests, 1);
      // Kept for the session, and the next read starts afresh.
      expect(PolyPriceHistoryCache.fresh('token-a', '1d'), hasLength(40));
      expect(
        await PolyPriceHistoryCache.load('token-a', '1d')
            .timeout(const Duration(seconds: 5)),
        hasLength(40),
      );
      expect(requests, 2);
    });
  });

  test('a read that fails answers null instead of hanging', () async {
    await withClient(() async {
      expect(
        await PolyPriceHistoryCache.load('token-b', '1d')
            .timeout(const Duration(seconds: 5)),
        isNull,
      );
      expect(PolyPriceHistoryCache.any('token-b', '1d'), isNull);
    });
  });
}
