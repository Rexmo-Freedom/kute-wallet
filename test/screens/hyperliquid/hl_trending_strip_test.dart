// The Trending strip (founder, 1 November 2026): the big cards at the top
// of Investing are the hyped names, stocks and shares and commodities, not
// the day's obscure crypto movers. Ranked by volume × (1 + |change %| / 10),
// six at most, at least two commodities when two qualify, one card per
// underlying (the most traded), none of them repeated in the list under
// the strip; the old movers when fewer than three qualify.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart';
import 'package:kute/screens/hyperliquid/components/hl_moving_now_strip.dart';
import 'package:kute/screens/hyperliquid/hyperliquid_screen.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';

import '../usd/investments_harness.dart';
import 'hl_trending_strip_fixture.dart';

class _LivePrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState();
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
  @override
  void focus(String coin, {String? wire}) {}
  @override
  void unfocus(String coin) {}
  @override
  void acquire() {}
  @override
  void release() {}
}

List<String> _wires(List<HlMarket> ms) => [for (final m in ms) m.wireCoin];

List<HlMarket> _trendingList(List<HlMarket> universe) =>
    hlBrowseListForTab(HlBrowseTab.trending, universe);

List<HlMarket> _strip(List<HlMarket> universe) =>
    hlTrendingStrip(universe, _trendingList(universe));

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('hype: volume raised by the move, a 10% move doubles it', () {
    expect(hlHypeScore(hlFixtureMarket('X', px: up(10), vlm: 1e6)),
        moreOrLessEquals(2e6, epsilon: 1e-3));
    expect(hlHypeScore(hlFixtureMarket('X', px: up(-5), vlm: 1e6)),
        moreOrLessEquals(1.5e6, epsilon: 1e-3));
    expect(hlHypeScore(hlFixtureMarket('X', vlm: 1e6)), moreOrLessEquals(1e6));
    expect(hlHypeScore(hlFixtureMarket('X', prev: 0)), isNull);
  });

  test('the strip: stocks and shares and commodities by hype, two '
      'commodities at least, one per underlying, never crypto', () {
    final strip = _strip(hlTrendingFixture);
    // AAPL (1.22e8) would be sixth with one commodity; SILVER takes its
    // place. Best first.
    expect(_wires(strip), [
      'xyz:TSLA',
      'xyz:NVDA',
      'xyz:GOLD',
      'io:ANTH',
      'xyz:SP500',
      'xyz:SILVER',
    ]);
    expect(strip.where((m) => m.category == 'commodities').length, 2);
    // The obscure crypto movers, the thin stock, the stock with no
    // previous-day price and the FX pair are never on it.
    expect(_wires(strip),
        isNot(contains(anyOf('XPL', 'LIT', 'NEAR', 'xyz:MU', 'xyz:META',
            'xyz:EUR'))));
    // No two cards for one underlying.
    expect({for (final m in strip) hlUnderlyingKey(m)}.length, strip.length);
  });

  test('two markets on one underlying: the more traded one, even when the '
      'other moved more', () {
    final strip = _strip(hlTrendingFixture);
    // xyz:ANT moved 30% (hype 4e8, above io:ANTH's 2.7e8) on less volume;
    // para:ANTH and the ANT token are Anthropic too.
    expect(_wires(strip), contains('io:ANTH'));
    expect(_wires(strip), isNot(contains(anyOf('xyz:ANT', 'para:ANTH', '@62'))));
    // flx:GOLD is the same gold as xyz:GOLD.
    expect(_wires(strip), isNot(contains('flx:GOLD')));
    expect(hlUnderlyingKey(hlTrendingFixture.firstWhere((m) => m.wireCoin == 'xyz:ANT')),
        hlUnderlyingKey(hlTrendingFixture.firstWhere((m) => m.wireCoin == 'io:ANTH')));
    // The aliases are tradfi only: the main dex's GAS is a crypto coin,
    // flx:GAS is natural gas.
    expect(hlUnderlyingKey(hlFixtureMarket('GAS')),
        isNot(hlUnderlyingKey(hlFixtureMarket('NATGAS',
            dex: 'xyz', category: 'commodities'))));
    expect(
        hlUnderlyingKey(
            hlFixtureMarket('GAS', dex: 'flx', category: 'commodities')),
        hlUnderlyingKey(
            hlFixtureMarket('NATGAS', dex: 'xyz', category: 'commodities')));
    expect(
        hlUnderlyingKey(hlFixtureMarket('XAUT0',
            spot: true, wire: '@182', category: 'commodities')),
        hlUnderlyingKey(
            hlFixtureMarket('GOLD', dex: 'km', category: 'commodities')));
  });

  test('commodities that lead on hype are not capped, and one commodity is '
      'all a universe with one can give', () {
    final heavy = [
      for (final m in hlTrendingFixture)
        if (m.category == 'commodities' && m.dex == 'xyz')
          hlFixtureMarket(m.coin,
              dex: 'xyz', category: 'commodities', px: m.markPx, vlm: 1e9)
        else
          m,
    ];
    final strip = _strip(heavy);
    expect(strip.length, kHlHypeCardMax);
    expect(strip.where((m) => m.category == 'commodities').length, 4);
    expect(_wires(strip).take(4).toSet(),
        {'xyz:GOLD', 'xyz:SILVER', 'xyz:CL', 'xyz:NATGAS'});

    final oneCommodity = [
      for (final m in hlTrendingFixture)
        if (m.category != 'commodities' || m.wireCoin == 'xyz:GOLD') m,
    ];
    final s = _strip(oneCommodity);
    expect(s.where((m) => m.category == 'commodities').map((m) => m.wireCoin),
        ['xyz:GOLD']);
    expect(_wires(s), [
      'xyz:TSLA',
      'xyz:NVDA',
      'xyz:GOLD',
      'io:ANTH',
      'xyz:SP500',
      'xyz:AAPL',
    ]);
  });

  test('fewer than three qualify (builder dexes not read): the old movers, '
      'still one per underlying', () {
    final crypto = [
      hlFixtureMarket('BTC', px: up(1), vlm: 9e9),
      hlFixtureMarket('ETH', px: up(2), vlm: 8e9),
      // Bitcoin as a Unit token and on a builder dex moved more than the
      // main perp, which trades most: one Bitcoin, at its own 1% move.
      hlFixtureMarket('UBTC',
          spot: true,
          wire: '@142',
          px: up(14),
          vlm: 5e8,
          unitAssetName: 'Bitcoin'),
      hlFixtureMarket('BTC',
          dex: 'hyna', px: up(13), vlm: 4e8, wire: 'hyna:BTC'),
      hlFixtureMarket('XPL', px: up(25), vlm: 3e8),
      hlFixtureMarket('LIT', px: up(20), vlm: 2e8),
      hlFixtureMarket('NEAR', px: up(-9), vlm: 1e9),
      // Two tradfi markets: not enough for a hyped strip.
      hlFixtureMarket('TSLA', dex: 'xyz', category: 'stocks', px: up(3),
          vlm: 4e8),
      hlFixtureMarket('GOLD', dex: 'xyz', category: 'commodities',
          px: up(1.5), vlm: 2.5e8),
    ]..sort((a, b) => b.dayNtlVlm.compareTo(a.dayNtlVlm));
    final trending = _trendingList(crypto);
    final strip = hlTrendingStrip(crypto, trending);
    expect(_wires(strip), ['XPL', 'LIT', 'NEAR', 'xyz:TSLA', 'ETH']);
    expect(_wires(strip), _wires(hlMovingNow(trending)));
    expect(_wires(hlMovingNow(trending, max: 7)),
        ['XPL', 'LIT', 'NEAR', 'xyz:TSLA', 'ETH', 'xyz:GOLD', 'BTC']);
    // Nothing qualifies at all: no strip.
    expect(hlTrendingStrip(const [], const []), isEmpty);
    // The builder dexes still on their way: no movers, no strip.
    expect(hlTrendingStrip(crypto, trending, fallback: false), isEmpty);
  });

  test('the list under the strip repeats none of its names, and a strip '
      'that would leave under three rows is dropped', () {
    final trending = _trendingList(hlTrendingFixture);
    final strip = hlTrendingStrip(hlTrendingFixture, trending);
    final rest = hlListUnderStrip(trending, strip)!;
    final keys = {for (final m in strip) hlUnderlyingKey(m)};
    expect(rest.where((m) => keys.contains(hlUnderlyingKey(m))), isEmpty);
    // The other gold and the other Anthropics are not rows either.
    expect(_wires(rest),
        isNot(contains(anyOf('flx:GOLD', 'xyz:ANT', 'para:ANTH'))));
    expect(_wires(rest), containsAllInOrder(['BTC', 'ETH', 'SOL', 'NEAR']));
    expect(hlListUnderStrip(trending.take(8).toList(), trending.take(6).toList()),
        isNull);
    expect(hlListUnderStrip(trending, const []), same(trending));
  });

  testWidgets('while the full perp list is loading (main dex only), '
      'Trending opens on no strip rather than the crypto movers',
      (tester) async {
    final mainDexOnly = [
      for (final m in hlTrendingFixture)
        if (!m.isHip3) m,
    ];
    final never = Completer<List<HlMarket>>();
    await pumpInvestments(tester,
        browseInvesting: true,
        child: const Scaffold(body: HyperliquidScreen()),
        overrides: [
          hyperliquidPerpMarketsProvider.overrideWith((_) => never.future),
          hyperliquidBrowseUniverseProvider
              .overrideWithValue(AsyncValue.data(mainDexOnly)),
          hyperliquidBuilderMarketsMissingProvider.overrideWithValue(false),
          hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
          hyperliquidSparklineStoreProvider.overrideWithValue(HlSparklineStore(
              fetch: (_) async => const [100, 104, 102, 108, 112])),
        ]);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(HlMovingNowStrip), findsNothing);
    expect(find.byType(HlMarketCard), findsWidgets);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets('Trending shows the hyped strip over a list that repeats none '
      'of it', (tester) async {
    await pumpInvestments(tester,
        browseInvesting: true,
        child: const Scaffold(body: HyperliquidScreen()),
        overrides: [
          hyperliquidBrowseUniverseProvider
              .overrideWithValue(AsyncValue.data(hlTrendingFixture)),
          hyperliquidBuilderMarketsMissingProvider.overrideWithValue(false),
          hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
          hyperliquidSparklineStoreProvider.overrideWithValue(HlSparklineStore(
              fetch: (_) async => const [100, 104, 102, 108, 112])),
        ]);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final strip =
        tester.widget<HlMovingNowStrip>(find.byType(HlMovingNowStrip));
    expect(_wires(strip.markets), [
      'xyz:TSLA',
      'xyz:NVDA',
      'xyz:GOLD',
      'io:ANTH',
      'xyz:SP500',
      'xyz:SILVER',
    ]);
    final keys = {for (final m in strip.markets) hlUnderlyingKey(m)};
    final rows = tester
        .widgetList<HlMarketCard>(find.byType(HlMarketCard))
        .map((r) => r.market)
        .toList();
    expect(rows, isNotEmpty);
    expect(rows.first.coin, 'BTC');
    expect(rows.where((m) => keys.contains(hlUnderlyingKey(m))), isEmpty);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });
}
