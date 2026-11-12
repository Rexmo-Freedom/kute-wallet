// "What happened to the NVIDIA perp? It does not show up?" (founder,
// 12 November 2026, build 115). Search for "nv" offered only the NVDAX and
// EQNVDA tokens; xyz:NVDA, the most traded stock perp on Hyperliquid, was
// gone, and so were io:NVDA and every other stock-linked perp.
//
// The fixtures are the venue's own public answers on 12 November 2026
// (metaAndAssetCtxs for the main dex and the builder dexes that list a
// big-tech stock, perpConciseAnnotations, perpDexs, spotMetaAndAssetCtxs),
// trimmed to the most traded markets and every listing of NVDA, TSLA,
// AAPL, GOOGL, META, AMZN and MSFT. Run through the app's own parsing,
// browse lists, Trending strip and search, they show:
//
// * with `hyperliquid.stocks` allowed, xyz:NVDA is Nvidia's primary
//   listing everywhere (Stocks, Trending, the Trending strip, search for
//   "nvidia", "nvda" and "nv"), with io:NVDA, NVDAX and EQNVDA behind it,
//   and the other big-tech names list under Stocks from xyz;
// * with `hyperliquid.stocks` refused, as the live policy refuses it in
//   the UK (country_blocked), every stock-linked perp leaves browse and
//   search by design (hlMarketsOfferedUnderPolicy) and the stock tokens
//   are what remains: exactly the founder's screenshot.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_search_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_moving_now_strip.dart'
    show hlTrendingStrip;

import '../helpers/runtime_policy_fixture.dart';

const _dir = 'test/fixtures/hyperliquid_live_2026_11_12';

dynamic _read(String name) =>
    jsonDecode(File('$_dir/$name').readAsStringSync());

/// The perps and spot pairs as the app loads them: every builder dex in
/// the venue's order, a dex settling in another stablecoin left out
/// (HyperliquidModel._loadAllPerpMarkets).
List<HlMarket> _liveUniverse() {
  final annotations =
      HlPerpAnnotation.parseList(_read('perp_concise_annotations.json'));
  final perps =
      HlMarket.parsePerpList(_read('meta_main.json'), annotations: annotations);
  final dexes = _read('perp_dexs.json') as List;
  for (var i = 0; i < dexes.length; i++) {
    final dex = dexes[i];
    if (dex == null) continue;
    final file = File('$_dir/meta_${dex['name']}.json');
    if (!file.existsSync()) continue;
    final decoded = jsonDecode(file.readAsStringSync());
    if (hlMetaCollateralToken(decoded) != hlUsdcCollateralToken) continue;
    perps.addAll(HlMarket.parsePerpList(decoded,
        dex: dex['name'] as String, dexIndex: i, annotations: annotations));
  }
  final spots = HlMarket.parseSpotList(_read('spot_meta.json'));
  return resolveHlBrowseUniverse(perps, spots);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AffiliateService.debugSessionToken = 'test-session');
  tearDown(() => AffiliateService.debugSessionToken = null);

  const bigTech = ['NVDA', 'TSLA', 'AAPL', 'GOOGL', 'META', 'AMZN', 'MSFT'];

  test('the venue lists Nvidia as xyz:NVDA, io:NVDA, NVDAX and EQNVDA', () {
    final universe = _liveUniverse();
    final nvidia = [
      for (final m in universe)
        if (m.underlyingTicker == 'NVDA') m.wireCoin
    ];
    // Volume order: xyz:NVDA traded about $1.6B in the day.
    expect(nvidia, ['xyz:NVDA', 'io:NVDA', '@702', '@1155']);
    final xyz = universe.firstWhere((m) => m.wireCoin == 'xyz:NVDA');
    expect(xyz.category, 'stocks');
    expect(xyz.dayNtlVlm, greaterThan(1e9));
    expect(xyz.iconUrl, HlMarket.hlIconUrl('xyz:NVDA'));
    // The delisted NVDA perps on km, mkts and cash never load.
    for (final dead in ['km:NVDA', 'mkts:NVDA', 'cash:NVDA']) {
      expect(universe.any((m) => m.wireCoin == dead), isFalse, reason: dead);
    }
  });

  test(
      'with stock perps allowed, xyz:NVDA is the one Nvidia row in Stocks, '
      'Trending, the strip and search', () async {
    final policy = runtimePolicyFixture();
    addTearDown(policy.dispose);
    expect(await policy.refresh(), isTrue);
    final universe = hlMarketsOfferedUnderPolicy(_liveUniverse(), policy);

    final stocks = hlBrowseListForTab(HlBrowseTab.tradfi, universe,
        sub: HlBrowseSub.stocks);
    expect(stocks.first.wireCoin, 'xyz:NVDA');
    for (final t in bigTech) {
      expect(
          [
            for (final m in stocks)
              if (m.underlyingTicker == t) m.wireCoin
          ],
          ['xyz:$t'],
          reason: '$t lists once under Stocks, from xyz');
    }

    final trending = hlBrowseListForTab(HlBrowseTab.trending, universe);
    expect(trending.take(2).map((m) => m.wireCoin), ['BTC', 'xyz:NVDA']);
    expect(trending.where((m) => m.underlyingTicker == 'NVDA'), hasLength(1));
    expect(hlTrendingStrip(universe, trending).first.wireCoin, 'xyz:NVDA');

    for (final q in ['nvidia', 'nvda', 'nv', 'NVIDIA']) {
      final hits = await hlSearchMarkets(universe, q);
      expect(hits.first.wireCoin, 'xyz:NVDA', reason: q);
      expect(hits.first.alternatives.map((a) => a.wireCoin),
          ['io:NVDA', '@702', '@1155'],
          reason: q);
      expect(hits.where((h) => h.groupTicker == 'NVDA'), hasLength(1),
          reason: '"$q" shows Nvidia once');
    }
  });

  test(
      'with stock perps refused (the UK today), search for "nv" offers the '
      'Nvidia tokens alone: the founder\'s screenshot', () async {
    final policy = runtimePolicyFixture(
      blocked: {'hyperliquid.stocks', 'hyperliquid.trade'},
      reasons: {
        'hyperliquid.stocks': 'country_blocked',
        'hyperliquid.trade': 'country_blocked',
      },
    );
    addTearDown(policy.dispose);
    expect(await policy.refresh(), isTrue);
    final universe = hlMarketsOfferedUnderPolicy(_liveUniverse(), policy);

    expect(universe.where(isHlStockPerp), isEmpty);
    final hits = await hlSearchMarkets(universe, 'nv');
    expect(hits.first.coin, 'NVDAX');
    expect(hits.first.alternatives.map((a) => a.coin), ['EQNVDA']);
    expect(
        hits.expand((h) => [h, ...h.alternatives]).where((h) => h.isPerp),
        isEmpty);
    final stocks = hlBrowseListForTab(HlBrowseTab.tradfi, universe,
        sub: HlBrowseSub.stocks);
    expect(stocks.every((m) => m.isSpot), isTrue);
  });
}
