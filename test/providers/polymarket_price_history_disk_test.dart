// A chart opened again in a later session draws the series that session
// saved while the history read runs, and the read then replaces it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/services/polymarket/price_history_disk_cache.dart';

List<PolymarketPricePoint> _points(int n, double price) => [
      for (var i = 0; i < n; i++)
        PolymarketPricePoint(
            timestamp: DateTime.fromMillisecondsSinceEpoch(
                (1791000000 + i * 600) * 1000),
            price: price),
    ];

void main() {
  late Directory dir;
  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('pm_history_disk');
    Hive.init(dir.path);
  });
  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  test('a saved series reads back while it is young enough for its range',
      () async {
    await PolyPriceHistoryDiskCache.write('tok-a', 'max', _points(30, 0.4));
    final saved = await PolyPriceHistoryDiskCache.read('tok-a', 'max');
    expect(saved?.points, hasLength(30));
    expect(saved?.points.first.price, 0.4);
    expect(saved?.points.first.timestamp,
        DateTime.fromMillisecondsSinceEpoch(1791000000 * 1000));
    expect(await PolyPriceHistoryDiskCache.read('tok-a', '1h'), isNull);
    expect(PolyPriceHistoryDiskCache.maxAgeFor('1h'),
        lessThan(PolyPriceHistoryDiskCache.maxAgeFor('max')));
  });

  test('the chart draws the saved series, then the read', () async {
    await PolyPriceHistoryDiskCache.write('tok-b', 'max', _points(30, 0.2));
    final answer = Completer<http.Response>();
    final client = MockClient((_) => answer.future);
    await http.runWithClient(() async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const key = (tokenId: 'tok-b', interval: 'max');
      final sub = container.listen(polymarketMarketHistoryProvider(key),
          (_, __) {});
      addTearDown(sub.close);
      final first = await container
          .read(polymarketMarketHistoryProvider(key).future)
          .timeout(const Duration(seconds: 5));
      expect(first.first.price, 0.2);
      answer.complete(http.Response(
          jsonEncode({
            'data': [
              for (var i = 0; i < 40; i++)
                {'timestamp': 1791000000 + i * 600, 'price': 0.6}
            ]
          }),
          200));
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final now = container.read(polymarketMarketHistoryProvider(key));
        if (now.valueOrNull?.length == 40) break;
      }
      final next = container.read(polymarketMarketHistoryProvider(key));
      expect(next.valueOrNull, hasLength(40));
      expect(next.valueOrNull!.first.price, 0.6);
      // And the read is what the next session will find.
      for (var i = 0; i < 20; i++) {
        final saved = await PolyPriceHistoryDiskCache.read('tok-b', 'max');
        if (saved?.points.length == 40) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect((await PolyPriceHistoryDiskCache.read('tok-b', 'max'))?.points,
          hasLength(40));
    }, () => client);
  });
}
