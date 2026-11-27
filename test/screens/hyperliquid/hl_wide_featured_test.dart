// The wide web Investing home's featured card (founder, 27 November 2026:
// "on Investing and Predictions maybe have one big one"): on the web at
// MEDIUM and EXPANDED, Trending's featured set as ONE large card in place
// of the four squares, previous / next stepping through the set and
// wrapping, a click opening the shown market; the phone layout keeps the
// four squares. Then every wide web Investing page ("watch list should
// have the same effect"; of Perps, "the big options should also show
// here"): the Watchlist through all of it, in its order, its rows under
// the card from two markets; a category or subcategory its first four
// over its unchanged list; one market, no pager.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/providers/hyperliquid_candles_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/providers/hyperliquid_watchlist_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_moving_now_strip.dart';
import 'package:kute/screens/hyperliquid/components/hl_wide_featured.dart';
import 'package:kute/screens/hyperliquid/hyperliquid_screen.dart';
import 'package:kute/screens/shared/kute_wide_featured_frame.dart';
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

class _Stars extends HlWatchlistNotifier {
  _Stars(this.keys);
  final List<String> keys;
  @override
  List<String> build() => keys;
}

/// A main-dex perp in strictIsolated margin: a Pre-launch market.
HlMarket _preLaunch(String coin) => HlMarket(
      coin: coin,
      wireCoin: coin,
      assetId: coin.hashCode & 0xffff,
      kind: HlMarketKind.perp,
      szDecimals: 2,
      maxLeverage: 3,
      onlyIsolated: true,
      marginMode: 'strictIsolated',
      markPx: 2,
      midPx: 2,
      prevDayPx: 1.9,
      dayNtlVlm: 1e6,
      category: 'crypto',
    );

List<Override> _overridesFor(List<HlMarket> universe) => [
      hyperliquidBrowseUniverseProvider
          .overrideWithValue(AsyncValue.data(universe)),
      hyperliquidBuilderMarketsMissingProvider.overrideWithValue(false),
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidSparklineStoreProvider.overrideWithValue(HlSparklineStore(
          fetch: (_) async => const [100, 104, 102, 108, 112])),
      hyperliquidLiveCandlesProvider
          .overrideWith((ref, key) => Stream.value(const HlLiveCandlesState())),
    ];

Future<void> _pumpScreen(WidgetTester tester, Size size,
    {List<HlMarket>? universe,
    List<String> stars = const [],
    HlBrowseSelection? selection}) async {
  HyperliquidScreen.debugWideWeb = true;
  addTearDown(() => HyperliquidScreen.debugWideWeb = false);
  await pumpInvestments(tester,
      browseInvesting: true,
      size: size,
      designSize: KuteLayout.designSizeFor(size),
      child: const Scaffold(body: HyperliquidScreen(embedded: true)),
      hlStars: stars.isEmpty ? null : () => _Stars(stars),
      overrides: _overridesFor(universe ?? hlTrendingFixture));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (selection != null) {
    ProviderScope.containerOf(
            tester.element(find.byType(HyperliquidScreen)),
            listen: false)
        .read(hlBrowseSelectionProvider.notifier)
        .state = selection;
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

List<String> _featuredWires(WidgetTester tester) => [
      for (final m in tester
          .widget<HlWideFeatured>(find.byType(HlWideFeatured))
          .markets)
        m.wireCoin
    ];

/// The markets drawn as the page's list under the card: its rows, or a
/// short category page's squares.
Set<String> _rowWires(WidgetTester tester) => {
      for (final c in tester.widgetList<HlMarketCard>(find.byType(HlMarketCard)))
        c.market.wireCoin,
      for (final c
          in tester.widgetList<HlMovingNowCard>(find.byType(HlMovingNowCard)))
        c.market.wireCoin,
    };

bool _pager(WidgetTester tester) =>
    find.byKey(const ValueKey('hl-wide-featured-next')).evaluate().isNotEmpty;

String _shownWire(WidgetTester tester) {
  final header = tester
      .widgetList(find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          RegExp(r'^hl-wide-featured-(perp|spot)-')
              .hasMatch((w.key as ValueKey<String>).value)))
      .first;
  final key = (header.key as ValueKey<String>).value;
  return key.substring(key.indexOf('-', 'hl-wide-featured-'.length) + 1);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  // The featured set lists only markets with a logo of their own: here
  // every market has one.
  setUp(() => HlIconAvailability.debugEveryLogoKnown = true);
  tearDown(() => HlIconAvailability.debugEveryLogoKnown = false);

  testWidgets('wide web (EXPANDED): one featured card, no row of four; the '
      'pager steps through the strip\'s set in order and wraps',
      (tester) async {
    await _pumpScreen(tester, const Size(1440, 900));
    expect(find.byType(HlWideFeatured), findsOneWidget);
    expect(find.byType(HlMovingNowStrip), findsNothing);
    expect(find.byType(HlMovingNowCard), findsNothing);
    final set =
        tester.widget<HlWideFeatured>(find.byType(HlWideFeatured)).markets;
    expect([for (final m in set) m.wireCoin],
        ['xyz:TSLA', 'xyz:NVDA', 'xyz:GOLD', 'xyz:SILVER']);
    // As tall as the Predictions card, the chart on a card this wide.
    expect(tester.getSize(find.byKey(const ValueKey('hl-wide-featured'))).height,
        kKuteWideFeaturedHeight);
    expect(find.byKey(const ValueKey('hl-wide-featured-chart-xyz:TSLA')),
        findsOneWidget);

    expect(_shownWire(tester), 'xyz:TSLA');
    final seen = <String>[];
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const ValueKey('hl-wide-featured-next')));
      await tester.pump();
      seen.add(_shownWire(tester));
    }
    expect(seen, ['xyz:NVDA', 'xyz:GOLD', 'xyz:SILVER', 'xyz:TSLA']);
    await tester.tap(find.byKey(const ValueKey('hl-wide-featured-prev')));
    await tester.pump();
    expect(_shownWire(tester), 'xyz:SILVER');
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets('wide web (MEDIUM): the featured card too', (tester) async {
    await _pumpScreen(tester, const Size(800, 900));
    expect(find.byType(HlWideFeatured), findsOneWidget);
    expect(find.byType(HlMovingNowStrip), findsNothing);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets('the phone layout keeps the four squares', (tester) async {
    await _pumpScreen(tester, const Size(390, 844));
    expect(find.byType(HlWideFeatured), findsNothing);
    expect(find.byType(HlMovingNowStrip), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets('a click opens the shown market', (tester) async {
    final opened = <HlMarket>[];
    await pumpInvestments(tester,
        size: const Size(1200, 400),
        designSize: const Size(1200, 400),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: HlWideFeatured(
              markets: hlTrendingFixture.take(3).toList(),
              chart: false,
              onTap: opened.add,
            ),
          ),
        ),
        overrides: [
          hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
        ]);
    await tester.tap(find.byKey(const ValueKey('hl-wide-featured-next')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('hl-wide-featured-name')));
    await tester.pump();
    expect(opened.single.wireCoin, hlTrendingFixture[1].wireCoin);
    // The stats: the 24h volume at least, never leverage.
    expect(find.text('24h Volume'), findsOneWidget);
    expect(find.textContaining('×'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  group('the Watchlist', () {
    String key(HlMarket m) => hlWatchlistKey(m);
    final eth = hlTrendingFixture[1];
    final btc = hlTrendingFixture[0];
    final six = hlTrendingFixture.take(6).toList();
    const watchlist = HlBrowseSelection(tab: HlBrowseTab.watchlist);

    testWidgets('none: no Watchlist page, as before (Trending in its '
        'place, its own card; no Edit)', (tester) async {
      await _pumpScreen(tester, const Size(1440, 900),
          selection: watchlist);
      expect(find.byKey(const ValueKey('hl-wide-featured-watchlist-all')),
          findsNothing);
      expect(find.byKey(const ValueKey('hl-wide-featured-trending-all')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('hl-watchlist-edit')), findsNothing);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets('one: the featured card alone, no pager, no rows, Edit',
        (tester) async {
      await _pumpScreen(tester, const Size(1440, 900),
          stars: [key(eth)], selection: watchlist);
      expect(find.byType(HlWideFeatured), findsOneWidget);
      expect(_featuredWires(tester), [eth.wireCoin]);
      expect(_pager(tester), isFalse);
      expect(find.byType(HlMarketCard), findsNothing);
      expect(find.byKey(const ValueKey('hl-watchlist-squares')), findsNothing);
      expect(find.byKey(const ValueKey('hl-watchlist-edit')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets('two: the card steps through both in order and wraps, both '
        'as rows under it', (tester) async {
      await _pumpScreen(tester, const Size(1440, 900),
          stars: [key(eth), key(btc)], selection: watchlist);
      expect(_featuredWires(tester), [eth.wireCoin, btc.wireCoin]);
      expect(_shownWire(tester), eth.wireCoin);
      await tester.tap(find.byKey(const ValueKey('hl-wide-featured-next')));
      await tester.pump();
      expect(_shownWire(tester), btc.wireCoin);
      await tester.tap(find.byKey(const ValueKey('hl-wide-featured-next')));
      await tester.pump();
      expect(_shownWire(tester), eth.wireCoin);
      await tester.tap(find.byKey(const ValueKey('hl-wide-featured-prev')));
      await tester.pump();
      expect(_shownWire(tester), btc.wireCoin);
      expect(_rowWires(tester), {eth.wireCoin, btc.wireCoin});
      expect(find.byKey(const ValueKey('hl-watchlist-squares')), findsNothing);
      expect(find.byKey(const ValueKey('hl-watchlist-edit')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets('six: all six through the card, all six as rows',
        (tester) async {
      await _pumpScreen(tester, const Size(1440, 900),
          stars: [for (final m in six) key(m)], selection: watchlist);
      expect(_featuredWires(tester), [for (final m in six) m.wireCoin]);
      expect(_rowWires(tester), {for (final m in six) m.wireCoin});
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets('medium shows the card; the phone keeps its squares',
        (tester) async {
      await _pumpScreen(tester, const Size(800, 900),
          stars: [key(eth), key(btc)], selection: watchlist);
      expect(find.byType(HlWideFeatured), findsOneWidget);
      await unmountInvestments(tester);
      await _pumpScreen(tester, const Size(390, 844),
          stars: [key(eth), key(btc)], selection: watchlist);
      expect(find.byType(HlWideFeatured), findsNothing);
      expect(
          find.byKey(const ValueKey('hl-watchlist-squares')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });
  });

  group('every category page', () {
    final universe = [
      ...hlTrendingFixture,
      _preLaunch('NEWCOIN'),
    ];
    final cases = <String, HlBrowseSelection>{
      'Perps': const HlBrowseSelection(tab: HlBrowseTab.perps),
      'Spot': const HlBrowseSelection(tab: HlBrowseTab.spot),
      'Stocks': const HlBrowseSelection(
          tab: HlBrowseTab.tradfi,
          subs: {HlBrowseTab.tradfi: HlBrowseSub.stocks}),
      'Pre-launch': const HlBrowseSelection(tab: HlBrowseTab.prelaunch),
    };
    for (final MapEntry(key: name, value: selection) in cases.entries) {
      testWidgets('$name: one featured card, its first four in its order, '
          'over its unchanged list', (tester) async {
        await _pumpScreen(tester, const Size(1440, 900),
            universe: universe, selection: selection);
        final listed = hlBrowseListForTab(selection.tab, universe,
            sub: selection.sub);
        expect(listed, isNotEmpty);
        expect(find.byType(HlWideFeatured), findsOneWidget);
        expect(_featuredWires(tester),
            [for (final m in listed.take(4)) m.wireCoin]);
        // Nothing left out of the list: the featured ones stay rows.
        final rows = _rowWires(tester);
        expect(rows, containsAll([for (final m in listed.take(8)) m.wireCoin]));
        expect(_pager(tester), listed.length > 1);
        expect(tester.takeException(), isNull);
        await unmountInvestments(tester);
      });
    }

    testWidgets('a category of one market: no pager; the phone keeps its '
        'plain list', (tester) async {
      final pre = cases['Pre-launch']!;
      await _pumpScreen(tester, const Size(1440, 900),
          universe: universe, selection: pre);
      expect(_featuredWires(tester), ['NEWCOIN']);
      expect(_pager(tester), isFalse);
      await unmountInvestments(tester);
      await _pumpScreen(tester, const Size(390, 844),
          universe: universe, selection: cases['Perps']);
      expect(find.byType(HlWideFeatured), findsNothing);
      expect(find.byType(HlMovingNowStrip), findsNothing);
      expect(find.byType(HlMarketCard), findsWidgets);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });
  });
}
