// The Dollars page opens on Overview, the first pill (founder, 8 November
// 2026, reversing the 7 November opening on Investing), and the market map
// lives on Overview, moved from Investing:
//
//   * the first open and every Bitcoin | Dollars switch land on Overview
//     (kInvestmentsDefaultTab, openInvestmentsOnDefaultTab), whatever the
//     policy withholds, the switch put back in place with no motion of its
//     own; a pick still switches in; a link naming a pill keeps it
//     (`?tab=predictions`), `?tab=activity` and `?tab=overview` name Overview;
//   * on Overview: the open positions, the open P&L, then the map, at the
//     cards' width; with nothing open the tab shows nothing under the pills; the map's
//     skeleton in its place; a tile, scrolled to, opens its market, the
//     page clearing the bar; no category picked on Investing touches it;
//   * Investing is its plain list: no map, on any category;
//   * the map reads its own data: a new universe lands on Overview with the
//     pill on screen, and a pull re-reads the market lists, reporting
//     `tab: activity`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
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
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/refresh_everything_provider.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart'
    show kuteDockScrollClearance;
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_map.dart';
import 'package:kute/screens/hyperliquid/components/hl_moving_now_strip.dart';
import 'package:kute/screens/hyperliquid/hyperliquid_screen.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/screens/portfolio/investments_portfolio.dart'
    show PortfolioSection;
import 'package:kute/screens/shared/all_activity.dart'
    show ActivitySquareGrid;
import 'package:kute/screens/shared/kute_motion.dart' show SelectionFade;
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/usd/components/dollars_activity_tab.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';

import '../../helpers/portfolio_overrides.dart' show PortfolioTestTrading;
import '../hyperliquid/hl_market_map_fixture.dart';
import 'investments_harness.dart';

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

/// Whether the builder-dex markets are still to be read (the map's
/// skeleton), switchable mid-test.
final _buildersMissing = StateProvider<bool>((_) => false);

/// The browse universe, switchable mid-test.
final _universe = StateProvider<List<HlMarket>>((_) => hlMarketMapFixture);

Override _holding(List<HlPerpPosition> positions) =>
    hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
        HyperliquidTradingState(isInitialized: true, positions: positions)));

HlPerpPosition _perp(String coin, double margin) => HlPerpPosition(
    coin: coin,
    szi: 1,
    entryPx: 100,
    positionValue: margin * 2,
    unrealizedPnl: 3,
    returnOnEquity: 0.03,
    liquidationPx: null,
    marginUsed: margin,
    leverageType: 'cross',
    leverageValue: 2,
    maxLeverage: 40);

/// The Dollars page over the market map's universe, tall enough to hold what
/// is on it; [link] is the pill a link names (`/usd?tab=…`).
/// [_pump] with a position open, as the map needs (nothing open: no map).
Future<ProviderContainer> _pumpHeld(WidgetTester tester,
        {bool browseInvesting = true,
        AsyncValue<List<HlMarket>>? universe,
        Size size = const Size(390, 2400),
        List<Override> overrides = const []}) =>
    _pump(tester,
        browseInvesting: browseInvesting,
        universe: universe,
        size: size,
        overrides: [
          _holding([_perp('BTC', 100)]),
          ...overrides
        ]);

Future<ProviderContainer> _pump(WidgetTester tester,
    {InvestmentsTab? link,
    bool browseInvesting = true,
    bool browsePredictions = false,
    Size size = const Size(390, 2400),
    AsyncValue<List<HlMarket>>? universe,
    List<Override> overrides = const []}) async {
  await pumpInvestments(tester,
      browseInvesting: browseInvesting,
      browsePredictions: browsePredictions,
      size: size,
      child: link == null ? null : UsdAccountScreen(initialTab: link),
      overrides: [
        if (universe == null)
          hyperliquidBrowseUniverseProvider.overrideWith(
              (ref) => AsyncValue.data(ref.watch(_universe)))
        else
          hyperliquidBrowseUniverseProvider.overrideWithValue(universe),
        hyperliquidBuilderMarketsMissingProvider
            .overrideWith((ref) => ref.watch(_buildersMissing)),
        hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
        hyperliquidSparklineStoreProvider.overrideWithValue(
            HlSparklineStore(fetch: (_) async => const [1, 2, 3])),
        ...overrides,
      ]);
  await _frames(tester);
  return ProviderScope.containerOf(
      tester.element(find.byType(InvestmentsBody, skipOffstage: false)));
}

Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The page's own [WidgetRef] (its body's element), as the shell's.
WidgetRef _ref(WidgetTester tester) =>
    tester.element(find.byType(InvestmentsBody)) as WidgetRef;

KutePillTabs _strip(WidgetTester tester) =>
    tester.widget<KutePillTabs>(find.byType(KutePillTabs).first);

final _overview = find.byType(DollarsActivityTab);
final _map = find.byKey(const ValueKey('hl-market-map'));
final _mapBones = find.byKey(const ValueKey('hl-market-map-loading'));
final _empty = find.byKey(const ValueKey('dollars-activity-empty'));
final _squares = find.byKey(const ValueKey('dollars-activity-squares'));
final _pnl = find.byKey(const ValueKey('dollars-pnl-strip'));
final _paint = find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is HlMarketMapPainter,
    skipOffstage: false);

HlMarketMapPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_paint).painter! as HlMarketMapPainter;

/// The map's card itself, inside its margin: the clip on its ground and the
/// card's 1 px border around it.
Rect _cardOf(WidgetTester tester, Finder frame) => tester
    .getRect(
        find.descendant(of: frame, matching: find.byType(ClipRRect)).first)
    .inflate(1);

/// The body's fade: 1 at rest.
double _bodyOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(find
        .descendant(
            of: find.byType(SelectionFade),
            matching: find.byType(FadeTransition))
        .first)
    .opacity
    .value;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the pill the page opens on', () {
    test('Overview, the first pill', () {
      expect(kInvestmentsDefaultTab, InvestmentsTab.activity);
      expect(kInvestmentsPills.first, InvestmentsTab.activity);
    });

    test('links: activity and overview name the pill, its key stays', () {
      expect(InvestmentsTab.activity.key, 'activity');
      expect(investmentsTabLocation(InvestmentsTab.activity),
          '/usd?tab=activity');
      expect(InvestmentsTab.fromKey('activity'), InvestmentsTab.activity);
      expect(InvestmentsTab.fromKey('overview'), InvestmentsTab.activity);
      expect(InvestmentsTab.fromKey('investing'), InvestmentsTab.investing);
      expect(InvestmentsTab.fromKey('predictions'), InvestmentsTab.predictions);
      // Neither is a Portfolio section: the Portfolio does not open over it.
      expect(PortfolioSection.forLink('activity'), isNull);
      expect(PortfolioSection.forLink('overview'), isNull);
    });

    testWidgets(
        'first open: Overview, the first pill, picked and on screen, with no '
        'pick reported', (tester) async {
      final events = recordEvents();
      final container = await _pumpHeld(tester);
      expect(container.read(investmentsTabProvider), InvestmentsTab.activity);
      expect(_strip(tester).selectedIndex, 0);
      expect(_strip(tester).items[0].label, 'Overview');
      expect(_overview, findsOneWidget);
      expect(_map, findsOneWidget);
      expect(find.byType(HyperliquidScreen), findsNothing,
          reason: 'mounted behind the stack, not on screen');
      expect(events.where((e) => e.$1 == 'analytics_tab_selected'), isEmpty);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets(
        'both venues\' browsing withheld: still Overview, first open and after '
        'the switch', (tester) async {
      final container = await _pump(tester, browseInvesting: false);
      expect(container.read(investmentsTabProvider), InvestmentsTab.activity);
      await tapPill(tester, 'Predictions');
      openInvestmentsOnDefaultTab(_ref(tester));
      await tester.pump();
      expect(container.read(investmentsTabProvider), InvestmentsTab.activity);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    for (final tab in [InvestmentsTab.investing, InvestmentsTab.predictions]) {
      testWidgets('a link naming ${tab.key} still opens it', (tester) async {
        final container = await _pump(tester, link: tab);
        expect(container.read(investmentsTabProvider), tab);
        expect(_strip(tester).selectedIndex, kInvestmentsPills.indexOf(tab));
        expect(_overview, findsNothing);
        expect(tester.takeException(), isNull);
        await unmountInvestments(tester);
      });
    }

    testWidgets(
        'every Bitcoin | Dollars switch lands on Overview again, in place; a '
        'pick still switches in', (tester) async {
      final container = await _pumpHeld(tester);
      await tapPill(tester, 'Predictions');
      expect(
          container.read(investmentsTabProvider), InvestmentsTab.predictions);

      // The shell's switch to Dollars (app_shell.dart, a tap or a swipe).
      openInvestmentsOnDefaultTab(_ref(tester));
      await tester.pump();
      expect(container.read(investmentsTabProvider), InvestmentsTab.activity);
      expect(_strip(tester).selectedIndex, 0);
      // At rest on its first frame: the shell's slide is the motion.
      expect(tester.widget<SelectionFade>(find.byType(SelectionFade)).animate,
          isFalse);
      expect(_bodyOpacity(tester), 1);
      expect(_map, findsOneWidget);

      // Already on it: nothing written, nothing moves.
      openInvestmentsOnDefaultTab(_ref(tester));
      await tester.pump();
      expect(_bodyOpacity(tester), 1);

      // A pick switches in as every switch does.
      await tester.tap(investmentsPill('Investing'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.widget<SelectionFade>(find.byType(SelectionFade)).animate,
          isTrue);
      expect(_bodyOpacity(tester), lessThan(1));
      await _frames(tester);
      expect(container.read(investmentsTabProvider), InvestmentsTab.investing);
      // And back on Overview by a pick: switched in too.
      await tester.tap(investmentsPill('Overview'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_bodyOpacity(tester), lessThan(1));
      await _frames(tester);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets(
        'a pull on the page it opened on reports tab activity and re-reads '
        'the market lists the map is drawn from', (tester) async {
      final events = recordEvents();
      var reads = 0;
      // A phone's height: the pull arms at a share of it.
      final container = await _pump(tester,
          size: const Size(390, 844),
          overrides: [
            hyperliquidPerpMarketsProvider.overrideWith((_) async {
              reads++;
              return const <HlMarket>[];
            }),
          ]);
      final before = reads;
      await tester.drag(find.byType(NestedScrollView), const Offset(0, 300));
      await tester.pump();
      await _frames(tester, 15);
      expect(
          events.where((e) =>
              e.$1 == 'pull_to_refresh_executed' &&
              e.$2?['screen'] == 'usd' &&
              e.$2?['tab'] == 'activity'),
          hasLength(1));
      final refresh =
          container.read(refreshEverythingProvider) as RecordingRefresh;
      expect(refresh.triggers.map((t) => t.tab), everyElement('activity'));
      expect(reads, greaterThan(before));
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });
  });

  group('the market map on Overview', () {
    testWidgets(
        'positions held: the squares, the open P&L, then the map, at the '
        'cards\' width, 12 under the P&L', (tester) async {
      await _pumpHeld(tester, overrides: [
        _holding([_perp('BTC', 100), _perp('ETH', 500)]),
      ]);
      expect(_squares, findsOneWidget);
      expect(_pnl, findsOneWidget);
      expect(_map, findsOneWidget);
      expect(_empty, findsNothing);
      final grid = tester.getRect(find.descendant(
          of: _squares, matching: find.byType(ActivitySquareGrid)));
      final pnl = tester.getRect(_pnl);
      final card = _cardOf(tester, _map);
      expect(grid.bottom, lessThanOrEqualTo(pnl.top));
      expect(card.top - pnl.bottom, closeTo(12.h, 1));
      expect(card.left, closeTo(grid.left, 0.5));
      expect(card.right, closeTo(grid.right, 0.5));
      expect(pnl.left, closeTo(grid.left, 0.5));
      // Square, as it always was.
      expect(card.height, closeTo(card.width, 1));
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets(
        'nothing open: nothing under the pills, no map, no heading, no empty '
        'state', (tester) async {
      await _pump(tester);
      expect(_map, findsNothing);
      expect(_mapBones, findsNothing);
      expect(_squares, findsNothing);
      expect(_pnl, findsNothing);
      expect(find.text('No open positions'), findsNothing);
      expect(find.byKey(const ValueKey('dollars-activity-positions-heading')),
          findsNothing);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets('Investing\'s browsing withheld, nothing open: nothing',
        (tester) async {
      await _pump(tester, browseInvesting: false);
      expect(_map, findsNothing);
      expect(_mapBones, findsNothing);
      expect(find.text('No open positions'), findsNothing);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets(
        'Investing\'s browsing withheld, a position held: the square and the '
        'P&L, no map, no empty state', (tester) async {
      await _pump(tester, browseInvesting: false, overrides: [
        _holding([_perp('BTC', 100)]),
      ]);
      expect(_squares, findsOneWidget);
      expect(_pnl, findsOneWidget);
      expect(_map, findsNothing);
      expect(_empty, findsNothing);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets('too few markets, a position held: no map, the square stays',
        (tester) async {
      await _pumpHeld(tester, universe: const AsyncValue.data(<HlMarket>[]));
      expect(_map, findsNothing);
      expect(_mapBones, findsNothing);
      expect(_squares, findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets(
        'loading, its skeleton in the map\'s place and height: it does not '
        'move when the map lands', (tester) async {
      final container = await _pumpHeld(tester);
      final map = tester.getRect(_map);

      container.read(_buildersMissing.notifier).state = true;
      await _frames(tester);
      expect(_map, findsNothing);
      expect(_mapBones, findsOneWidget);
      expect(_empty, findsNothing);
      expect(tester.getRect(_mapBones), map);

      container.read(_buildersMissing.notifier).state = false;
      await _frames(tester);
      expect(_map, findsOneWidget);
      expect(_mapBones, findsNothing);
      expect(tester.getRect(_map), map);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets(
        'a category picked on Investing leaves the map whole; Investing has '
        'no map on any category', (tester) async {
      final container = await _pumpHeld(tester);
      final tiles = _painter(tester).layout.tiles.map((t) => t.id).toList();
      await tapPill(tester, 'Investing');
      expect(_map, findsNothing);
      expect(find.byType(HlMovingNowStrip), findsOneWidget);
      expect(find.byType(HlMarketCard), findsWidgets);
      expect(
          find.descendant(
              of: find.byType(HyperliquidScreen),
              matching: find.byKey(const ValueKey('hl-market-map'),
                  skipOffstage: false)),
          findsNothing);

      container.read(hlBrowseSelectionProvider.notifier).state = container
          .read(hlBrowseSelectionProvider)
          .copyWith(tab: HlBrowseTab.perps);
      await _frames(tester, 8);
      expect(_map, findsNothing);
      expect(_mapBones, findsNothing);

      await tapPill(tester, 'Overview');
      expect(_map, findsOneWidget);
      expect(_painter(tester).layout.tiles.map((t) => t.id), tiles);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets('a new universe lands on the map while Overview is on screen',
        (tester) async {
      final container = await _pumpHeld(tester);
      final before = _painter(tester).layout.tiles.length;
      container.read(_universe.notifier).state =
          hlMarketMapFixture.take(20).toList();
      await _frames(tester);
      expect(_painter(tester).layout.tiles.length, lessThan(before));
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets(
        'the tab on its own, with Investing never built: the map still reads '
        'its data', (tester) async {
      await pumpInvestments(tester,
          browseInvesting: true,
          size: const Size(390, 1200),
          child: const Scaffold(body: DollarsActivityTab()),
          overrides: [
            _holding([_perp('BTC', 100)]),
            hyperliquidBrowseUniverseProvider
                .overrideWithValue(AsyncValue.data(hlMarketMapFixture)),
            hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
          ]);
      await _frames(tester);
      expect(find.byType(HyperliquidScreen, skipOffstage: false), findsNothing);
      expect(_map, findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets(
        'behind another pill the card keeps still: a new universe waits until '
        'Overview is back', (tester) async {
      final container = await _pumpHeld(tester);
      await tapPill(tester, 'Predictions');
      final tiles = _painter(tester).layout.tiles.length;
      container.read(_universe.notifier).state =
          hlMarketMapFixture.take(20).toList();
      await _frames(tester);
      expect(_painter(tester).layout.tiles.length, tiles);
      await tapPill(tester, 'Overview');
      await _frames(tester);
      expect(_painter(tester).layout.tiles.length, lessThan(tiles));
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets(
        'a tile, scrolled to, opens its market with the map as the source; '
        'the page scrolls clear of the bar', (tester) async {
      final events = recordEvents();
      final zec = hlMarketMapFixture.firstWhere((m) => m.coin == 'ZEC');
      // A small phone, positions over the map: it runs below the screen.
      await _pumpHeld(tester, size: const Size(375, 640), overrides: [
        _holding([_perp('BTC', 100), _perp('ETH', 500), _perp('HYPE', 300)]),
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
      // To the end of the tab: drags until it stops moving.
      double? at;
      for (var i = 0; i < 20; i++) {
        await tester.drag(find.byType(NestedScrollView), const Offset(0, -300));
        await _frames(tester, 20);
        final now = _map.evaluate().isEmpty ? null : tester.getTopLeft(_map).dy;
        if (now != null && now == at) break;
        at = now;
      }
      expect(_map, findsOneWidget);
      // Only the clearance under it: the dock and 24 more, nothing cut.
      final card = _cardOf(tester, _map);
      final view = tester.getRect(
          find.ancestor(of: _map, matching: find.byType(Scrollable)).first);
      expect(view.bottom - card.bottom,
          closeTo(24.h + kuteDockScrollClearance(tester.element(_map)), 1));

      final tile =
          _painter(tester).layout.tiles.firstWhere((t) => t.id == 'perp:ZEC');
      await tester.tapAt(tester.getTopLeft(_paint) + tile.rect.center);
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
