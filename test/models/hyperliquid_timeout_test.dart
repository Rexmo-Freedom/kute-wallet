// An `info` read that times out (15 s, `_infoOrThrow`) must reach the
// caller that awaited it and nothing else. 2.1.0 started parallel reads
// and awaited them one after another, so a timeout landing on a future
// nobody was awaiting yet was reported to the zone as uncaught, which is
// a fatal on Android. These pin that every read path reports a timeout
// once, on the awaited future, with nothing left for the zone.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/hyperliquid_model.dart';

void main() {
  setUp(() {
    HyperliquidModel.resetBuilderCache();
    HyperliquidModel.referenceRetryGap = Duration.zero;
  });

  /// Answers like the venue, slowly. Reads named in [timeOutNow] throw a
  /// TimeoutException at once, those in [timeOutLate] after the ordinary
  /// answers have landed, and [builderTimesOut] fails only the builder
  /// (HIP-3) dex metas.
  http.Client venue({
    Set<String> timeOutNow = const {},
    Set<String> timeOutLate = const {},
    bool builderTimesOut = false,
    List<String>? calls,
  }) =>
      MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final type = body['type'] as String;
        final dex = body['dex'] as String?;
        calls?.add(dex == null ? type : '$type:$dex');
        final timeout = TimeoutException('Future not completed', Duration(seconds: 15));
        if (timeOutNow.contains(type) || (builderTimesOut && dex != null)) {
          throw timeout;
        }
        if (timeOutLate.contains(type)) {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          throw timeout;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        switch (type) {
          case 'perpDexs':
            return http.Response(
                jsonEncode([null, {'name': 'xyz', 'fullName': 'xyz'}]), 200);
          case 'perpConciseAnnotations':
            return http.Response(
                jsonEncode([['xyz:TSLA', {'category': 'stocks'}]]), 200);
          case 'metaAndAssetCtxs':
            return http.Response(
                jsonEncode([
                  {
                    'universe': [
                      {
                        'name': dex == null ? 'BTC' : 'TSLA',
                        'szDecimals': 2,
                        'maxLeverage': 10
                      }
                    ]
                  },
                  [
                    {
                      'markPx': '10',
                      'midPx': '10',
                      'prevDayPx': '9',
                      'dayNtlVlm': '100',
                      'funding': '0',
                      'openInterest': '1'
                    }
                  ]
                ]),
                200);
          case 'spotClearinghouseState':
            return http.Response(jsonEncode({'balances': <Object>[]}), 200);
        }
        return http.Response('{}', 200);
      });

  /// Runs [body] in a guarded zone and returns what reached the zone's
  /// uncaught-error handler, after leaving late futures time to land.
  Future<List<Object>> uncaughtDuring(Future<void> Function() body) async {
    final uncaught = <Object>[];
    final finished = Completer<void>();
    runZonedGuarded(() async {
      try {
        await body();
      } finally {
        finished.complete();
      }
    }, (error, _) => uncaught.add(error));
    await finished.future;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return uncaught;
  }

  test('core perp list: a meta timeout is thrown to the caller only',
      () async {
    final model = HyperliquidModel(
        client: venue(
            timeOutNow: {'metaAndAssetCtxs'},
            timeOutLate: {'perpConciseAnnotations'}));
    final uncaught = await uncaughtDuring(() async {
      await expectLater(
          model.getCorePerpMarkets(), throwsA(isA<TimeoutException>()));
    });
    expect(uncaught, isEmpty);
  });

  test('perp catalogue: a meta timeout is thrown to the caller only',
      () async {
    final model = HyperliquidModel(
        client: venue(
            timeOutNow: {'metaAndAssetCtxs'},
            timeOutLate: {'perpDexs', 'perpConciseAnnotations'}));
    final uncaught = await uncaughtDuring(() async {
      await expectLater(
          model.getPerpCatalogue(), throwsA(isA<TimeoutException>()));
      // The failed read is not left in flight: the next call reads again.
      await expectLater(
          model.getPerpCatalogue(), throwsA(isA<TimeoutException>()));
    });
    expect(uncaught, isEmpty);
  });

  test('perp catalogue: builder dex timeouts leave a partial list, no error',
      () async {
    final model = HyperliquidModel(client: venue(builderTimesOut: true));
    late HlPerpCatalogue catalogue;
    final uncaught = await uncaughtDuring(() async {
      catalogue = await model.getPerpCatalogue();
    });
    expect(uncaught, isEmpty);
    expect(catalogue.complete, isFalse);
    expect(catalogue.markets.map((m) => m.wireCoin), ['BTC']);
  });

  test('account snapshot: two timeouts, one late, are reported once',
      () async {
    final model = HyperliquidModel(
        client: venue(
            timeOutNow: {'clearinghouseState'},
            timeOutLate: {'spotClearinghouseState'}));
    final uncaught = await uncaughtDuring(() async {
      await expectLater(model.getAccountSnapshot('0xabc'),
          throwsA(isA<TimeoutException>()));
    });
    expect(uncaught, isEmpty);
  });

  test('open orders: a builder read timing out fails the whole read once',
      () async {
    final model = HyperliquidModel(
        client: venue(timeOutNow: {'frontendOpenOrders'}));
    final uncaught = await uncaughtDuring(() async {
      await expectLater(model.getOpenOrders('0xabc', dexes: ['xyz', 'km']),
          throwsA(isA<TimeoutException>()));
    });
    expect(uncaught, isEmpty);
  });
}
