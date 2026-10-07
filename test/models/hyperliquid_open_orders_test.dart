// frontendOpenOrders answers for the main perp dex and spot unless a
// builder (HIP-3) dex is named, so getOpenOrders reads each builder dex
// the account uses and merges the lists (verified live against
// api.hyperliquid.xyz: a user with xyz:* orders gets none of them back
// without `dex`).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/hyperliquid_model.dart';

Map<String, dynamic> _order(String coin, int oid, {String tif = 'Gtc'}) => {
      'coin': coin,
      'side': 'A',
      'limitPx': '371.5',
      'sz': '1',
      'origSz': '1',
      'oid': oid,
      'timestamp': oid,
      'orderType': 'Limit',
      'isTrigger': false,
      'triggerPx': '0.0',
      'reduceOnly': false,
      'tif': tif,
      'isPositionTpsl': false,
    };

void main() {
  test('reads the main dex plus each named builder dex, merged by oid',
      () async {
    final dexesAsked = <Object?>[];
    final model = HyperliquidModel(
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['type'], 'frontendOpenOrders');
        dexesAsked.add(body['dex']);
        final orders = switch (body['dex']) {
          null => [_order('@107', 1), _order('BTC', 2)],
          'xyz' => [_order('xyz:TSLA', 3, tif: 'Alo')],
          'km' => [_order('km:AAPL', 4)],
          _ => <Map<String, dynamic>>[],
        };
        return http.Response(jsonEncode(orders), 200);
      }),
    );

    final orders =
        await model.getOpenOrders('0xabc', dexes: {'xyz', 'km', ''});

    expect(dexesAsked.toSet(), {null, 'xyz', 'km'});
    expect(orders.map((o) => o.coin).toSet(),
        {'@107', 'BTC', 'xyz:TSLA', 'km:AAPL'});
    // Newest first across dexes.
    expect(orders.first.oid, 4);
    expect(orders.firstWhere((o) => o.oid == 3).tif, 'Alo');
  });

  test('a builder dex that fails fails the whole read', () async {
    final model = HyperliquidModel(
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['dex'] == 'xyz') return http.Response('down', 500);
        return http.Response(jsonEncode([_order('BTC', 1)]), 200);
      }),
    );
    expect(model.getOpenOrders('0xabc', dexes: ['xyz']),
        throwsA(isA<HyperliquidInfoException>()));
  });

  test('no builder dexes reads the main dex only', () async {
    var calls = 0;
    final model = HyperliquidModel(
      client: MockClient((request) async {
        calls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.containsKey('dex'), isFalse);
        return http.Response(jsonEncode([_order('BTC', 1)]), 200);
      }),
    );
    final orders = await model.getOpenOrders('0xabc');
    expect(calls, 1);
    expect(orders.single.coin, 'BTC');
  });
}
