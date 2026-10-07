import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/hyperliquid_model.dart';

// The builder (HIP-3) dex catalogue used to be re-read in one burst on every
// 30 s refresh, which Hyperliquid answered with 429s. These pin the cache,
// the single in-flight load and the pause after a rate limit.
void main() {
  Map<String, dynamic> meta(String coin) => {
        'universe': [
          {'name': coin, 'szDecimals': 2, 'maxLeverage': 10}
        ],
      };
  List<dynamic> ctxs() => [
        {'markPx': '10', 'midPx': '10', 'prevDayPx': '9', 'dayNtlVlm': '100', 'funding': '0', 'openInterest': '1'}
      ];

  setUp(HyperliquidModel.resetBuilderCache);

  test('builder dex metas are cached and a 429 pauses the wave', () async {
    final calls = <String>[];
    var rateLimit = false;
    final client = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final type = body['type'] as String;
      final dex = body['dex'] as String?;
      calls.add(dex == null ? type : '$type:$dex');
      if (type == 'perpDexs') {
        return http.Response(jsonEncode([null, {'name': 'km', 'fullName': 'km'}, {'name': 'xyz', 'fullName': 'xyz'}]), 200);
      }
      if (type == 'perpConciseAnnotations') return http.Response('[]', 200);
      if (dex != null && rateLimit) return http.Response('rate limited', 429);
      return http.Response(jsonEncode([meta(dex == null ? 'BTC' : dex.toUpperCase()), ctxs()]), 200);
    });
    final model = HyperliquidModel(client: client);

    // Two overlapping callers share one load.
    final results = await Future.wait([model.getAllPerpMarkets(), model.getAllPerpMarkets()]);
    expect(results[0].map((m) => m.coin).toSet(), containsAll(['BTC', 'KM', 'XYZ']));
    expect(calls.where((c) => c.startsWith('metaAndAssetCtxs:')).length, 2);

    // A refresh inside the TTL reads only the default dex again.
    calls.clear();
    await model.getAllPerpMarkets();
    expect(calls.where((c) => c.startsWith('metaAndAssetCtxs:')), isEmpty);
    expect(calls, contains('metaAndAssetCtxs'));

    // Expire the cache and rate limit: the stale copies still serve, and
    // the next refresh does not touch the builder dexes at all.
    HyperliquidModel.resetBuilderCache();
    rateLimit = true;
    calls.clear();
    final limited = await model.getAllPerpMarkets();
    expect(limited.map((m) => m.coin), contains('BTC'));
    expect(calls.where((c) => c.startsWith('metaAndAssetCtxs:')).length, 2);
    calls.clear();
    await model.getAllPerpMarkets();
    expect(calls.where((c) => c.startsWith('metaAndAssetCtxs:')), isEmpty);
  });
}
