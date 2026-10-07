// The builder dex list (perpDexs) and the annotations
// (perpConciseAnnotations) decide whether the builder (HIP-3) markets and
// their categories exist at all. One slow or blocked read used to drop
// them for the session. These pin the retries, the remembered last good
// answer and what a list looks like when there has never been one.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';

void main() {
  Map<String, dynamic> meta(String coin) => {
        'universe': [
          {'name': coin, 'szDecimals': 2, 'maxLeverage': 10}
        ],
      };
  List<dynamic> ctxs() => [
        {
          'markPx': '10',
          'midPx': '10',
          'prevDayPx': '9',
          'dayNtlVlm': '100',
          'funding': '0',
          'openInterest': '1'
        }
      ];
  final dexList = jsonEncode([
    null,
    {'name': 'xyz', 'fullName': 'xyz'},
  ]);
  final annotations = jsonEncode([
    ['xyz:TSLA', {'category': 'stocks'}],
  ]);

  /// Answers like the venue. [fail] names the request types that throw
  /// (a timeout, a blocked host); [calls] records every request.
  http.Client venue(List<String> calls, {required Set<String> Function() fail}) =>
      MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final type = body['type'] as String;
        final dex = body['dex'] as String?;
        calls.add(dex == null ? type : '$type:$dex');
        if (fail().contains(type) && dex == null) {
          throw http.ClientException('unreachable');
        }
        if (type == 'perpDexs') return http.Response(dexList, 200);
        if (type == 'perpConciseAnnotations') {
          return http.Response(annotations, 200);
        }
        return http.Response(
            jsonEncode([meta(dex == null ? 'BTC' : 'TSLA'), ctxs()]), 200);
      });

  setUp(() {
    HyperliquidModel.resetBuilderCache();
    HyperliquidModel.referenceRetryGap = Duration.zero;
    hlResetPerpListMemoryForTest();
  });

  test('a read that fails once is tried again and the list is whole',
      () async {
    final calls = <String>[];
    // Each read fails on its first attempt only (the request is recorded
    // before it is answered).
    final model = HyperliquidModel(
        client: venue(calls,
            fail: () => {
                  for (final t in const ['perpDexs', 'perpConciseAnnotations'])
                    if (calls.where((c) => c == t).length <= 1) t
                }));

    final catalogue = await model.getPerpCatalogue();
    expect(catalogue.complete, isTrue);
    expect(catalogue.annotated, isTrue);
    expect(catalogue.markets.map((m) => m.wireCoin), ['BTC', 'xyz:TSLA']);
    expect(catalogue.markets.last.category, 'stocks');
    expect(calls.where((c) => c == 'perpDexs').length, 2);
    expect(calls.where((c) => c == 'perpConciseAnnotations').length, 2);
  });

  test(
      'after one good answer, failing reads keep the builder markets and '
      'their categories', () async {
    final calls = <String>[];
    var fail = <String>{};
    final model = HyperliquidModel(client: venue(calls, fail: () => fail));

    expect((await model.getPerpCatalogue()).complete, isTrue);

    // The remembered answers have gone old and the venue stops answering
    // for both: the remembered copies are served at once.
    HyperliquidModel.ageReferenceForTest();
    fail = {'perpDexs', 'perpConciseAnnotations'};
    calls.clear();
    final second = await model.getPerpCatalogue();
    expect(second.complete, isTrue);
    expect(second.annotated, isTrue);
    expect(second.markets.map((m) => m.wireCoin), ['BTC', 'xyz:TSLA']);
    expect(second.markets.last.category, 'stocks');
    // The refresh behind it runs out of attempts without touching the list.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls.where((c) => c == 'perpDexs').length, 3);
    final third = await model.getPerpCatalogue();
    expect(third.markets.map((m) => m.wireCoin), ['BTC', 'xyz:TSLA']);
  });

  test(
      'with no answer ever, the list says it is short instead of passing '
      'for a venue without builder markets', () async {
    final calls = <String>[];
    final model = HyperliquidModel(
        client: venue(calls,
            fail: () => {'perpDexs', 'perpConciseAnnotations'}));

    final catalogue = await model.getPerpCatalogue();
    expect(catalogue.complete, isFalse);
    expect(catalogue.annotated, isFalse);
    expect(catalogue.markets.map((m) => m.wireCoin), ['BTC']);
    expect(calls.where((c) => c == 'perpDexs').length, 3);

    // Nothing remembered: the screen is told the builder markets are
    // missing, so Stocks and Commodities show their loading state.
    final container = ProviderContainer(overrides: [
      hyperliquidTradingModelProvider.overrideWithValue(model),
    ]);
    addTearDown(container.dispose);
    final sub = container.listen(
        hyperliquidBuilderMarketsMissingProvider, (_, __) {});
    final perps = await container.read(hyperliquidPerpMarketsProvider.future);
    expect(perps.map((m) => m.wireCoin), ['BTC']);
    expect(sub.read(), isTrue);
    expect(hlTabNeedsBuilderMarkets(HlBrowseTab.tradfi), isTrue);
    expect(hlTabNeedsBuilderMarkets(HlBrowseTab.crypto), isFalse);
    expect(hlTabNeedsBuilderMarkets(HlBrowseTab.perps), isFalse);
  });

  test('a short answer never shrinks the list below the last known one', () {
    HlMarket m(String coin, {String dex = '', String category = 'crypto'}) =>
        HlMarket(
          coin: coin,
          wireCoin: dex.isEmpty ? coin : '$dex:$coin',
          assetId: 1,
          kind: HlMarketKind.perp,
          szDecimals: 2,
          maxLeverage: 10,
          onlyIsolated: false,
          markPx: 1,
          midPx: 1,
          prevDayPx: 1,
          dayNtlVlm: 1,
          category: category,
          dex: dex,
          isHip3: dex.isNotEmpty,
        );
    final lastKnown = [
      m('BTC'),
      m('TSLA', dex: 'xyz', category: 'stocks'),
      m('GOLD', dex: 'flx', category: 'commodities'),
    ];

    // The dex list could not be read: every builder market is kept.
    final noDexes = hlKeepLastKnownBuilderMarkets(
        HlPerpCatalogue(markets: [m('BTC')], complete: false, annotated: true),
        lastKnown);
    expect(noDexes.map((x) => x.wireCoin), ['BTC', 'xyz:TSLA', 'flx:GOLD']);

    // One dex answered, one did not: only the silent one is kept.
    final oneDex = hlKeepLastKnownBuilderMarkets(
        HlPerpCatalogue(
            markets: [m('BTC'), m('TSLA', dex: 'xyz', category: 'stocks')],
            complete: false,
            annotated: true),
        lastKnown);
    expect(oneDex.map((x) => x.wireCoin), ['BTC', 'xyz:TSLA', 'flx:GOLD']);

    // The categories could not be read: a builder market keeps its last.
    final noCategories = hlKeepLastKnownBuilderMarkets(
        HlPerpCatalogue(markets: [
          m('BTC'),
          m('TSLA', dex: 'xyz', category: 'other'),
          m('GOLD', dex: 'flx', category: 'other'),
        ], complete: true, annotated: false),
        lastKnown);
    expect({for (final x in noCategories) x.wireCoin: x.category}, {
      'BTC': 'crypto',
      'xyz:TSLA': 'stocks',
      'flx:GOLD': 'commodities',
    });

    // A whole answer is final: a dex that left the venue is gone.
    final whole = hlKeepLastKnownBuilderMarkets(
        HlPerpCatalogue(
            markets: [m('BTC'), m('TSLA', dex: 'xyz', category: 'stocks')],
            complete: true,
            annotated: true),
        lastKnown);
    expect(whole.map((x) => x.wireCoin), ['BTC', 'xyz:TSLA']);

    // Nothing known: the short answer stands as it is.
    final nothing = hlKeepLastKnownBuilderMarkets(
        HlPerpCatalogue(markets: [m('BTC')], complete: false, annotated: false),
        null);
    expect(nothing.map((x) => x.wireCoin), ['BTC']);
  });
}
