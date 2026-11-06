// The market map under the Investing list (hl_market_map.dart): which
// markets it shows (four classes, one per underlying, the most traded,
// thin and unverified ones left out, a hysteresis at the edge), its layout
// (one scale, blocks with their labels, no overlaps, the same markets
// always laid out the same, kept while the sizes barely move), the colour
// of a change (neutral at 0.0 %, full from 5 %, the market pair), the
// labels a tile can carry, and the card: header, tap to the market,
// colours following the live price with the layout untouched, the loading
// state and no card at all with too few markets.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_candles_provider.dart';
import 'package:kute/providers/hyperliquid_insights_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_map.dart';
import 'package:kute/screens/hyperliquid/hyperliquid_screen.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../usd/investments_harness.dart';
import 'hl_market_map_fixture.dart';
import 'hl_trending_strip_fixture.dart' show hlFixtureMarket;

class _LivePrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState();
  void set(Map<String, double> mids) => state = HlLivePriceState(mids: mids);
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

/// [n] crypto markets, the first most traded.
List<HlMarket> _ladder(int n, {double change = 1}) => [
      for (var i = 0; i < n; i++)
        hlFixtureMarket('C$i', px: 100 + change, prev: 100, vlm: 1e9 / (i + 1)),
    ];

Future<ProviderContainer> _pumpCard(
  WidgetTester tester,
  List<HlMarket> universe, {
  bool loading = false,
  bool dark = false,
  void Function(HlMarket)? onTap,
}) async {
  tester.view.physicalSize = const Size(390, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: _Universe(
                key: UniqueKey(),
                universe: universe,
                loading: loading,
                onTap: onTap),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  return container;
}

/// Unmounts the card and lets the providers' disposal run.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 10));
}

/// Lets a test hand the card a new universe (a 30 s refresh).
class _Universe extends StatefulWidget {
  const _Universe(
      {super.key, required this.universe, this.loading = false, this.onTap});
  final List<HlMarket> universe;
  final bool loading;
  final void Function(HlMarket)? onTap;

  @override
  State<_Universe> createState() => _UniverseState();
}

class _UniverseState extends State<_Universe> {
  late List<HlMarket> universe = widget.universe;

  void refresh(List<HlMarket> next) => setState(() => universe = next);

  @override
  Widget build(BuildContext context) => HlMarketMapCard(
      universe: universe, loading: widget.loading, onTap: widget.onTap);
}

HlMarketMapPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.descendant(
        of: find.byKey(const ValueKey('hl-market-map')),
        matching: find.byType(CustomPaint)))
    .map((p) => p.painter)
    .whereType<HlMarketMapPainter>()
    .single;

/// Where a tile is on screen.
Offset _tileCenter(WidgetTester tester, String id) {
  final layout = _painter(tester).layout;
  final tile = layout.tiles.firstWhere((t) => t.id == id);
  final origin = tester.getTopLeft(find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is HlMarketMapPainter));
  return origin + tile.rect.center;
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the markets', () {
    test(
        'four classes, one per underlying, the most traded first; thin, '
        'unknown, FX and unverified tokens left out', () {
      final entries = hlMarketMapEntries(hlMarketMapFixture);
      final ids = entries.map((e) => e.id).toList();
      expect(entries, hasLength(kHlMarketMapMaxTiles));
      expect(ids.first, 'perp:BTC');
      // Most traded first.
      for (var i = 1; i < entries.length; i++) {
        expect(entries[i - 1].weight, greaterThanOrEqualTo(entries[i].weight));
      }
      // Gold once, the most traded of its builders; HYPE once, the perp.
      expect(ids, contains('perp:xyz:GOLD'));
      expect(ids, isNot(contains('perp:flx:GOLD')));
      expect(ids, contains('perp:HYPE'));
      expect(ids, isNot(contains('spot:@107')));
      // The token named like a stock, the thin stock, the stock with no
      // previous-day price, FX: never.
      expect(ids, isNot(contains('spot:@901')));
      expect(ids, isNot(contains('perp:xyz:THIN')));
      expect(ids, isNot(contains('perp:xyz:NOPREV')));
      expect(entries.where((e) => e.market.category == 'fx'), isEmpty);
      // The classes.
      final group = {for (final e in entries) e.market.coin: e.group};
      expect(group['BTC'], HlMarketMapGroup.crypto);
      expect(group['SKHX'], HlMarketMapGroup.stocks);
      expect(group['XYZ100'], HlMarketMapGroup.indices);
      expect(group['BRENTOIL'], HlMarketMapGroup.commodities);
      expect(hlMarketMapGroupOf(hlFixtureMarket('ANT', category: 'preipo')),
          HlMarketMapGroup.stocks);
      expect(
          hlMarketMapGroupOf(hlFixtureMarket('EUR', category: 'fx')), isNull);
      expect(
          hlMarketMapGroupOf(hlFixtureMarket('X', category: 'other')), isNull);
    });

    test(
        'a market on the map stays while it ranks in the top 56; a new one '
        'enters only in the top 48', () {
      final universe = _ladder(70);
      final first = hlMarketMapEntries(universe).map((e) => e.id).toSet();
      expect(first, hasLength(48));
      expect(first, contains('perp:C47'));
      expect(first, isNot(contains('perp:C48')));
      // C47 and C10 lose volume: C47 to rank 52 (stays), C10 to rank 65
      // (leaves); C48 and C49 move up into the top 48 and enter.
      final next = [
        for (final m in universe)
          if (m.coin == 'C47')
            hlFixtureMarket('C47', px: 101, prev: 100, vlm: 1e9 / 52.5)
          else if (m.coin == 'C10')
            hlFixtureMarket('C10', px: 101, prev: 100, vlm: 1e9 / 65.5)
          else
            m,
      ];
      final again =
          hlMarketMapEntries(next, previous: first).map((e) => e.id).toSet();
      expect(again, contains('perp:C47'));
      expect(again, isNot(contains('perp:C10')));
      expect(again, containsAll(['perp:C48', 'perp:C49']));
      // Without the map on screen, the plain top 48.
      expect(hlMarketMapEntries(next).map((e) => e.id),
          isNot(contains('perp:C47')));
    });
  });

  group('the layout', () {
    const size = Size(334, 334);
    final entries = hlMarketMapEntries(hlMarketMapFixture);

    test(
        'blocks by class with no titles; tiles inside, no overlaps, one '
        'scale', () {
      final layout = HlMarketMapLayout.compute(entries, size);
      expect(layout.blocks.map((b) => b.group).toSet(),
          HlMarketMapGroup.values.toSet());
      final tiles = layout.tiles.toList();
      final bounds = Offset.zero & size;
      for (final b in layout.blocks) {
        expect(b.header, isNull, reason: 'no group titles');
        for (final t in b.tiles) {
          expect(b.rect.inflate(1e-6).contains(t.rect.topLeft), isTrue);
          expect(b.rect.inflate(1e-6).contains(t.rect.bottomRight), isTrue);
        }
      }
      for (var i = 0; i < tiles.length; i++) {
        expect(
            bounds.inflate(1e-6).contains(tiles[i].rect.bottomRight), isTrue);
        for (var j = i + 1; j < tiles.length; j++) {
          final o = tiles[i].rect.intersect(tiles[j].rect);
          expect(o.width <= 1e-6 || o.height <= 1e-6, isTrue,
              reason: '${tiles[i].id} overlaps ${tiles[j].id}');
        }
      }
      // One scale: area per unit of volume the same in every block (the
      // label strips are added to their blocks, so within a few percent).
      final weight = {for (final e in entries) e.id: e.weight};
      final perUnit = [
        for (final t in tiles) t.rect.width * t.rect.height / weight[t.id]!,
      ];
      final mean = perUnit.reduce((a, b) => a + b) / perUnit.length;
      for (final v in perUnit) {
        expect(v, closeTo(mean, mean * 0.06));
      }
      // The biggest market is the biggest tile.
      final biggest = tiles.reduce((a, b) =>
          a.rect.width * a.rect.height >= b.rect.width * b.rect.height ? a : b);
      expect(biggest.id, 'perp:BTC');
      // A tap finds its tile.
      expect(layout.tileAt(biggest.rect.center)?.id, 'perp:BTC');
    });

    test('the same markets always lay out the same, in any order', () {
      final a = HlMarketMapLayout.compute(entries, size);
      final b = HlMarketMapLayout.compute(entries.reversed.toList(), size);
      expect([for (final t in b.tiles) (t.id, t.rect)],
          [for (final t in a.tiles) (t.id, t.rect)]);
    });

    test('one class is one block with no label', () {
      final crypto = hlMarketMapEntries(_ladder(20));
      final layout = HlMarketMapLayout.compute(crypto, size);
      expect(layout.blocks, hasLength(1));
      expect(layout.blocks.single.header, isNull);
      expect(layout.blocks.single.rect, Offset.zero & size);
    });

    test('a market too small for a tile is left off', () {
      final tail = [
        ...hlMarketMapEntries(_ladder(10)),
        HlMarketMapEntry(
            market: hlFixtureMarket('DUST', px: 101, prev: 100, vlm: 1e5),
            group: HlMarketMapGroup.crypto),
      ];
      final layout = HlMarketMapLayout.compute(tail, size);
      expect(layout.tiles.map((t) => t.id), isNot(contains('perp:DUST')));
      expect(layout.tiles, hasLength(10));
    });

    test(
        'kept while the same markets barely move; laid out again for a new '
        'market, a real shift of size, or a new width', () {
      final layout = HlMarketMapLayout.compute(entries, size);
      expect(layout.fits(entries, size), isTrue);
      HlMarketMapEntry scaled(HlMarketMapEntry e, double by) =>
          HlMarketMapEntry(
              market: hlFixtureMarket(e.market.coin,
                  dex: e.market.dex,
                  category: e.market.category,
                  px: e.market.markPx,
                  prev: e.market.prevDayPx,
                  vlm: e.weight * by),
              group: e.group);
      // A refresh: every volume a little different.
      final drift = [
        for (var i = 0; i < entries.length; i++)
          scaled(entries[i], i.isEven ? 1.03 : 0.98),
      ];
      expect(layout.fits(drift, size), isTrue);
      // BTC's volume up a half: its share moves by points.
      final shift = [scaled(entries.first, 1.5), ...entries.skip(1)];
      expect(layout.fits(shift, size), isFalse);
      // Another market.
      expect(layout.fits(entries.take(entries.length - 1).toList(), size),
          isFalse);
      expect(layout.fits(entries, const Size(300, 300)), isFalse);
    });
  });

  group('colour', () {
    test('neutral at 0.0 %, full from 5 %, a curve in between', () {
      expect(hlMarketMapIntensity(null), 0);
      expect(hlMarketMapIntensity(0), 0);
      expect(hlMarketMapIntensity(0.0004), 0);
      expect(hlMarketMapIntensity(-0.0004), 0);
      expect(hlMarketMapIntensity(0.05), 1);
      expect(hlMarketMapIntensity(-0.12), 1);
      var last = 0.0;
      for (final c in [0.001, 0.005, 0.01, 0.02, 0.03, 0.04, 0.05]) {
        final t = hlMarketMapIntensity(c);
        expect(t, greaterThan(last));
        expect(hlMarketMapIntensity(-c), t);
        last = t;
      }
      // A 1 % day is seen (over a quarter of the colour).
      expect(hlMarketMapIntensity(0.01), greaterThan(0.25));
    });

    test('red down, green up, the app\'s market pair, from each mode\'s grey',
        () {
      for (final dark in [false, true]) {
        final neutral = hlMarketMapNeutral(dark: dark);
        expect(hlMarketMapFill(0, dark: dark), neutral);
        expect(hlMarketMapFill(null, dark: dark), neutral);
        expect(hlMarketMapFill(0.08, dark: dark), AppColors.marketUp);
        expect(hlMarketMapFill(-0.05, dark: dark), AppColors.marketDown);
        final up = hlMarketMapFill(0.02, dark: dark);
        final down = hlMarketMapFill(-0.02, dark: dark);
        expect(up.g, greaterThan(up.r));
        expect(down.r, greaterThan(down.g));
        expect(hlMarketMapFill(0.02, dark: dark).a, 1);
      }
      expect(hlMarketMapNeutral(dark: true),
          isNot(hlMarketMapNeutral(dark: false)));
    });

    test(
        'white on the full colours and the dark grey, ink on the light '
        'grey', () {
      expect(hlMarketMapInk(AppColors.marketUp), Colors.white);
      expect(hlMarketMapInk(AppColors.marketDown), Colors.white);
      expect(hlMarketMapInk(hlMarketMapNeutral(dark: true)), Colors.white);
      expect(hlMarketMapInk(hlMarketMapNeutral(dark: false)),
          const Color(0xFF1D2024));
    });
  });

  group('labels', () {
    // A face 0.6 em wide per character, 1.2 em tall.
    Size measure(String text, double size, FontWeight _) =>
        Size(text.length * size * 0.6, size * 1.2);

    test('logo, title and change; title and change; title; nothing', () {
      final big = hlMarketMapLabelFor(
          const Rect.fromLTWH(0, 0, 150, 120), ['BTC'], measure);
      expect(big.level, HlMarketMapLabelLevel.logo);
      expect(big.title, 'BTC');
      expect(big.iconSize, inInclusiveRange(18, 30));
      final mid = hlMarketMapLabelFor(
          const Rect.fromLTWH(0, 0, 60, 40), ['NVDA'], measure);
      expect(mid.level, HlMarketMapLabelLevel.tickerChange);
      final small = hlMarketMapLabelFor(
          const Rect.fromLTWH(0, 0, 30, 18), ['MU'], measure);
      expect(small.level, HlMarketMapLabelLevel.ticker);
      final tiny = hlMarketMapLabelFor(
          const Rect.fromLTWH(0, 0, 10, 10), ['MU'], measure);
      expect(tiny.level, HlMarketMapLabelLevel.none);
      // Nothing is drawn wider than its tile.
      for (final r in [
        const Rect.fromLTWH(0, 0, 150, 120),
        const Rect.fromLTWH(0, 0, 60, 40),
        const Rect.fromLTWH(0, 0, 30, 18),
      ]) {
        final l = hlMarketMapLabelFor(r, ['SOXL'], measure);
        expect(measure(l.title, l.titleSize, FontWeight.w700).width,
            lessThanOrEqualTo(r.width));
      }
    });

    test(
        'an index or a commodity by its name where it fits, else its short '
        'name, else its ticker', () {
      final nasdaq = hlFixtureMarket('XYZ100', dex: 'xyz', category: 'indices');
      expect(hlMarketMapTitles(nasdaq, HlMarketMapGroup.indices),
          ['Nasdaq 100', 'Nasdaq', 'XYZ100']);
      final brent =
          hlFixtureMarket('BRENTOIL', dex: 'xyz', category: 'commodities');
      expect(hlMarketMapTitles(brent, HlMarketMapGroup.commodities),
          ['Brent oil', 'Brent', 'BRENTOIL']);
      expect(
          hlMarketMapLabelFor(const Rect.fromLTWH(0, 0, 150, 120),
                  hlMarketMapTitles(nasdaq, HlMarketMapGroup.indices), measure)
              .title,
          'Nasdaq 100');
      expect(
          hlMarketMapLabelFor(
                  const Rect.fromLTWH(0, 0, 44, 40),
                  hlMarketMapTitles(brent, HlMarketMapGroup.commodities),
                  measure)
              .title,
          'Brent');
      // Stocks and crypto by their tickers; a Unit token as its asset.
      expect(
          hlMarketMapTitles(hlFixtureMarket('NVDA', category: 'stocks'),
              HlMarketMapGroup.stocks),
          ['NVDA']);
      expect(
          hlMarketMapTicker(
              hlFixtureMarket('UBTC', spot: true, unitAssetName: 'Bitcoin')),
          'BTC');
    });
  });

  group('the card', () {
    testWidgets('no title, the map, and a tile opens its market',
        (tester) async {
      final tapped = <HlMarket>[];
      await _pumpCard(tester, hlMarketMapFixture, onTap: tapped.add);
      expect(find.text('Market map'), findsNothing);
      expect(find.text('24h'), findsNothing);
      final painter = _painter(tester);
      expect(painter.layout.tiles.length, greaterThan(30));
      // The big tiles carry a logo: BTC's.
      expect(
          find.byKey(const ValueKey('hl-map-logo-perp:BTC')), findsOneWidget);

      await tester.tapAt(_tileCenter(tester, 'perp:ZEC'));
      await tester.pump();
      expect(tapped.map((m) => m.coin), ['ZEC']);
      await tester.tapAt(_tileCenter(tester, 'perp:xyz:SKHX'));
      await tester.pump();
      expect(tapped.map((m) => m.coin), ['ZEC', 'SKHX']);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });

    testWidgets(
        'the live price recolours a tile in place; a refresh that '
        'barely moves the sizes keeps the layout', (tester) async {
      final container = await _pumpCard(tester, hlMarketMapFixture);
      final before = _painter(tester);
      final btc = hlMarketMapFixture.first;
      expect(before.fillOf('perp:BTC'),
          hlMarketMapFill(btc.dayChangePct, dark: false));

      // BTC up 6 % on the live feed.
      (container.read(hyperliquidLivePricesProvider.notifier) as _LivePrices)
          .set({'BTC': btc.prevDayPx * 1.06});
      await tester.pump();
      final after = _painter(tester);
      expect(identical(after.layout, before.layout), isTrue);
      expect(after.fillOf('perp:BTC'), AppColors.marketUp);
      expect(after.fillOf('perp:ETH'), before.fillOf('perp:ETH'));

      // A 30 s refresh: new market objects, volumes a little different.
      final state = tester.state<_UniverseState>(find.byType(_Universe));
      state.refresh([
        for (final m in hlMarketMapFixture)
          hlFixtureMarket(m.coin,
              dex: m.dex,
              category: m.category,
              px: m.markPx,
              prev: m.prevDayPx,
              vlm: m.dayNtlVlm * 1.02,
              spot: m.isSpot,
              wire: m.wireCoin),
      ]);
      await tester.pump();
      expect(identical(_painter(tester).layout, before.layout), isTrue);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });

    testWidgets('once shown, a short re-read keeps the card and its height',
        (tester) async {
      await _pumpCard(tester, hlMarketMapFixture);
      final card = find.byKey(const ValueKey('hl-market-map'));
      final height = tester.getSize(card).height;
      tester.state<_UniverseState>(find.byType(_Universe)).refresh(_ladder(3));
      await tester.pump();
      expect(card, findsOneWidget);
      expect(tester.getSize(card).height, height);
      expect(_painter(tester).layout.tiles, hasLength(3));
      tester.state<_UniverseState>(find.byType(_Universe)).refresh(const []);
      await tester.pump();
      expect(card, findsNothing);
      await _unmount(tester);
    });

    testWidgets(
        'loading: the card with its skeleton; too few markets: no '
        'card', (tester) async {
      await _pumpCard(tester, hlMarketMapFixture, loading: true);
      expect(
          find.byKey(const ValueKey('hl-market-map-loading')), findsOneWidget);
      expect(find.byKey(const ValueKey('hl-market-map')), findsNothing);

      await _pumpCard(tester, _ladder(kHlMarketMapMinTiles - 1));
      expect(find.byKey(const ValueKey('hl-market-map')), findsNothing);
      expect(find.text('Market map'), findsNothing);

      await _pumpCard(tester, const []);
      expect(find.byKey(const ValueKey('hl-market-map')), findsNothing);

      await _pumpCard(tester, _ladder(kHlMarketMapMinTiles), dark: true);
      expect(find.byKey(const ValueKey('hl-market-map')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  });

  group('on the Investing list', () {
    Future<void> pumpScreen(WidgetTester tester, List<HlMarket> universe,
        {List<Override> overrides = const []}) async {
      await pumpInvestments(tester,
          browseInvesting: true,
          size: const Size(390, 3000),
          child: const Scaffold(body: HyperliquidScreen()),
          overrides: [
            hyperliquidBrowseUniverseProvider
                .overrideWithValue(AsyncValue.data(universe)),
            hyperliquidBuilderMarketsMissingProvider.overrideWithValue(false),
            hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
            hyperliquidSparklineStoreProvider.overrideWithValue(
                HlSparklineStore(fetch: (_) async => const [1, 2, 3])),
            ...overrides,
          ]);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    final map =
        find.byKey(const ValueKey('hl-market-map'), skipOffstage: false);

    testWidgets('under the Trending list; not under a picked category',
        (tester) async {
      await pumpScreen(tester, hlMarketMapFixture);
      expect(map, findsOneWidget);
      final lastRow = find.byType(HlMarketCard, skipOffstage: false).last;
      expect(tester.getTopLeft(map).dy,
          greaterThan(tester.getBottomLeft(lastRow).dy));
      // The map is the whole universe, not the six rows over it.
      expect(_painter(tester).layout.tiles.length, greaterThan(30));

      final container = ProviderScope.containerOf(
          tester.element(find.byType(HyperliquidScreen)));
      container.read(hlBrowseSelectionProvider.notifier).state = container
          .read(hlBrowseSelectionProvider)
          .copyWith(tab: HlBrowseTab.perps);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(map, findsNothing);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets('its loading state while the builder markets are missing',
        (tester) async {
      await pumpScreen(tester, hlMarketMapFixture, overrides: [
        hyperliquidBuilderMarketsMissingProvider.overrideWithValue(true),
      ]);
      expect(
          find.byKey(const ValueKey('hl-market-map-loading'),
              skipOffstage: false),
          findsOneWidget);
      expect(map, findsNothing);
      await unmountInvestments(tester);
    });

    testWidgets('a tile opens the market sheet with the map as its source',
        (tester) async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final zec = hlMarketMapFixture.firstWhere((m) => m.coin == 'ZEC');
      await pumpScreen(tester, hlMarketMapFixture, overrides: [
        // The sheet's own reads (no network in a test).
        hyperliquidExactMarketProvider.overrideWith((ref, key) => zec),
        hyperliquidActiveAssetCtxProvider
            .overrideWith((ref, wire) => const Stream.empty()),
        hyperliquidOrderbookProvider
            .overrideWith((ref, wire) => const Stream.empty()),
        hyperliquidPerpPositionsProvider.overrideWith((_) => const []),
        hyperliquidSpotBalancesProvider.overrideWith((_) => const []),
        hyperliquidActivityFillsProvider.overrideWith((_) => const []),
        hyperliquidLiveCandlesProvider.overrideWith(
            (ref, key) => Stream.value(const HlLiveCandlesState(candles: []))),
        hyperliquidTradeFlowProvider.overrideWith(
            (ref, coin) => Stream.value(const HlTradeFlowState())),
      ]);
      await tester.tapAt(_tileCenter(tester, 'perp:ZEC'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      final sheet =
          tester.widget<HlMarketDetailSheet>(find.byType(HlMarketDetailSheet));
      expect(sheet.market.coin, 'ZEC');
      expect(sheet.source, kHlMarketMapSource);
      final viewed =
          events.where((e) => e.$1 == 'hyperliquid_market_viewed').single;
      expect(viewed.$2?['coin'], 'ZEC');
      expect(viewed.$2?['entry_source'], 'market_map');
      expect(tester.takeException(), isNull);
    });
  });
}
