// The Dollars page opens on Investing, the middle pill (founder, 7
// November 2026: "when stiching to dollars open up in th einvesting in the
// middle one, not in the activity right?"), and on Investing the market
// map is the second item, under the four moving squares and over the list
// ("put this as second item on investng"):
//
//   * the first open and every Bitcoin | Dollars switch land on Investing
//     (investmentsDefaultTab, openInvestmentsOnDefaultTab), the switch put
//     back in place with no motion of its own; a pick still switches in;
//     a link naming a pill keeps it (`?tab=activity`);
//   * with Investing's browsing withheld, Predictions while it is live,
//     else Activity (the gating audit runs every denial on the page);
//   * on Investing: the squares, the map, the list, at the cards' width
//     and the squares' rhythm; the map's skeleton holds its height, so
//     the list never moves when the map lands; a tile opens its market;
//   * a pull on the page it opened on reports `tab: investing`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_candles_provider.dart';
import 'package:kute/providers/hyperliquid_insights_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/providers/refresh_everything_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_map.dart';
import 'package:kute/screens/hyperliquid/components/hl_moving_now_strip.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/screens/shared/all_activity.dart'
    show ActivitySquareGrid;
import 'package:kute/screens/shared/kute_motion.dart' show SelectionFade;
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/usd/components/dollars_activity_tab.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';

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

/// The Dollars page over the market map's universe (its squares, its map
/// and its rows), tall enough to hold the three; [link] is the pill a
/// link names (`/usd?tab=…`).
Future<ProviderContainer> _pump(WidgetTester tester,
    {InvestmentsTab? link,
    bool browseInvesting = true,
    bool browsePredictions = false,
    Size size = const Size(390, 2400),
    List<Override> overrides = const []}) async {
  await pumpInvestments(tester,
      browseInvesting: browseInvesting,
      browsePredictions: browsePredictions,
      size: size,
      child: link == null ? null : UsdAccountScreen(initialTab: link),
      overrides: [
        hyperliquidBrowseUniverseProvider
            .overrideWithValue(AsyncValue.data(hlMarketMapFixture)),
        hyperliquidBuilderMarketsMissingProvider
            .overrideWith((ref) => ref.watch(_buildersMissing)),
        hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
        hyperliquidSparklineStoreProvider.overrideWithValue(
            HlSparklineStore(fetch: (_) async => const [1, 2, 3])),
        ...overrides,
      ]);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return ProviderScope.containerOf(
      tester.element(find.byType(InvestmentsBody, skipOffstage: false)));
}

/// The page's own [WidgetRef] (its body's element), as the shell's.
WidgetRef _ref(WidgetTester tester) =>
    tester.element(find.byType(InvestmentsBody)) as WidgetRef;

KutePillTabs _strip(WidgetTester tester) =>
    tester.widget<KutePillTabs>(find.byType(KutePillTabs).first);

final _squares = find.byType(HlMovingNowStrip);
final _map = find.byKey(const ValueKey('hl-market-map'));
final _mapBones = find.byKey(const ValueKey('hl-market-map-loading'));
final _rows = find.byType(HlMarketCard);

/// The map's card itself (inside its margin): the clip on its ground.
Rect _cardOf(WidgetTester tester, Finder frame) => tester.getRect(
    find.descendant(of: frame, matching: find.byType(ClipRRect)).first);

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
    test(
        'Investing; with its browsing withheld Predictions while live, '
        'else Activity', () {
      InvestmentsTab tabFor({required bool investing, required bool poly}) =>
          investmentsDefaultTab(InvestmentsTestPolicy(kEarnOff,
              browseInvesting: investing, browsePredictions: poly));
      expect(tabFor(investing: true, poly: true), InvestmentsTab.investing);
      expect(tabFor(investing: true, poly: false), InvestmentsTab.investing);
      expect(tabFor(investing: false, poly: true), InvestmentsTab.predictions);
      expect(tabFor(investing: false, poly: false), InvestmentsTab.activity);
      // The middle pill of the switch.
      expect(kInvestmentsPills.indexOf(InvestmentsTab.investing), 1);
    });

    testWidgets(
        'first open: Investing, the middle pill, picked and on screen, with '
        'no pick reported', (tester) async {
      final events = recordEvents();
      final container = await _pump(tester);
      expect(container.read(investmentsTabProvider), InvestmentsTab.investing);
      expect(_strip(tester).selectedIndex, 1);
      expect(_strip(tester).items[1].label, 'Investing');
      expect(_squares, findsOneWidget);
      expect(_map, findsOneWidget);
      expect(find.byType(DollarsActivityTab), findsNothing,
          reason: 'mounted behind the stack, not on screen');
      expect(events.where((e) => e.$1 == 'analytics_tab_selected'), isEmpty);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets('a link naming Activity still opens Activity',
        (tester) async {
      final container = await _pump(tester, link: InvestmentsTab.activity);
      expect(container.read(investmentsTabProvider), InvestmentsTab.activity);
      expect(_strip(tester).selectedIndex, 0);
      expect(find.byType(DollarsActivityTab), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets(
        'every Bitcoin | Dollars switch lands on Investing again, in place; '
        'a pick still switches in', (tester) async {
      final container = await _pump(tester);
      await tapPill(tester, 'Predictions');
      expect(
          container.read(investmentsTabProvider), InvestmentsTab.predictions);

      // The shell's switch to Dollars (app_shell.dart, a tap or a swipe).
      openInvestmentsOnDefaultTab(_ref(tester));
      await tester.pump();
      expect(container.read(investmentsTabProvider), InvestmentsTab.investing);
      expect(_strip(tester).selectedIndex, 1);
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
      await tester.tap(investmentsPill('Activity'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.widget<SelectionFade>(find.byType(SelectionFade)).animate,
          isTrue);
      expect(_bodyOpacity(tester), lessThan(1));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(container.read(investmentsTabProvider), InvestmentsTab.activity);
      // And back on Investing by a pick: switched in too.
      await tester.tap(investmentsPill('Investing'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_bodyOpacity(tester), lessThan(1));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets('a pull on the page it opened on reports tab investing',
        (tester) async {
      final events = recordEvents();
      // A phone's height: the pull arms at a share of it.
      final container = await _pump(tester, size: const Size(390, 844));
      await tester.drag(find.byType(NestedScrollView), const Offset(0, 300));
      await tester.pump();
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
          events.where((e) =>
              e.$1 == 'pull_to_refresh_executed' &&
              e.$2?['screen'] == 'usd' &&
              e.$2?['tab'] == 'investing'),
          hasLength(1));
      final refresh =
          container.read(refreshEverythingProvider) as RecordingRefresh;
      expect(refresh.triggers.map((t) => t.tab), everyElement('investing'));
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });
  });

  group('the market map on Investing', () {
    testWidgets(
        'the second item: the squares, then the map, then the list, at the '
        'cards\' width and the squares\' rhythm', (tester) async {
      await _pump(tester);
      expect(_squares, findsOneWidget);
      expect(_map, findsOneWidget);
      expect(_rows, findsWidgets);
      // In this order down the tab, and nothing of the tab's before the
      // squares.
      final items = <(String, double)>[
        ('squares', tester.getTopLeft(_squares).dy),
        ('map', tester.getTopLeft(_map).dy),
        for (final e in _rows.evaluate())
          ('row', tester.getTopLeft(find.byWidget(e.widget)).dy),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      expect(items.take(3).map((i) => i.$1), ['squares', 'map', 'row']);
      expect(items.skip(2).map((i) => i.$1), everyElement('row'));

      // The map's card spans the squares' grid, edge to edge.
      final grid = tester.getRect(find.descendant(
          of: _squares, matching: find.byType(ActivitySquareGrid)));
      final card = _cardOf(tester, _map);
      expect(card.left, closeTo(grid.left, 0.5));
      expect(card.right, closeTo(grid.right, 0.5));
      // Square, as it always was.
      expect(card.height, closeTo(card.width, 1));
      // 12 from the squares to the map, 12 from the map to the list (to
      // the pixel: the grid and the map round their own heights).
      final firstRow = items[2].$2;
      expect(card.top - grid.bottom, closeTo(12.h, 1));
      expect(firstRow - card.bottom, closeTo(12.h, 1));
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets(
        'loading, its skeleton holds the map\'s place: the list does not '
        'move when the map lands', (tester) async {
      final container = await _pump(tester);
      final rowTop = tester.getTopLeft(_rows.first).dy;
      final mapHeight = tester.getSize(_map).height;

      container.read(_buildersMissing.notifier).state = true;
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(_map, findsNothing);
      expect(_mapBones, findsOneWidget);
      expect(tester.getSize(_mapBones).height, mapHeight);
      expect(tester.getTopLeft(_mapBones).dy,
          greaterThan(tester.getBottomLeft(_squares).dy));
      expect(tester.getTopLeft(_rows.first).dy, rowTop);

      container.read(_buildersMissing.notifier).state = false;
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(_map, findsOneWidget);
      expect(tester.getTopLeft(_rows.first).dy, rowTop);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets('a picked category is the plain list: no squares, no map',
        (tester) async {
      final container = await _pump(tester);
      container.read(hlBrowseSelectionProvider.notifier).state = container
          .read(hlBrowseSelectionProvider)
          .copyWith(tab: HlBrowseTab.perps);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(_squares, findsNothing);
      expect(_map, findsNothing);
      expect(_mapBones, findsNothing);
      expect(_rows, findsWidgets);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets(
        'a tile at its new place opens its market, with the map as the '
        'source', (tester) async {
      final events = recordEvents();
      final zec = hlMarketMapFixture.firstWhere((m) => m.coin == 'ZEC');
      await _pump(tester, overrides: [
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
      final paint = find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is HlMarketMapPainter);
      final painter = tester.widget<CustomPaint>(paint).painter!
          as HlMarketMapPainter;
      final tile = painter.layout.tiles.firstWhere((t) => t.id == 'perp:ZEC');
      final at = tester.getTopLeft(paint) + tile.rect.center;
      expect(at.dy, greaterThan(tester.getBottomLeft(_squares).dy));
      expect(at.dy, lessThan(tester.getTopLeft(_rows.first).dy));
      await tester.tapAt(at);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      final sheet =
          tester.widget<HlMarketDetailSheet>(find.byType(HlMarketDetailSheet));
      expect(sheet.market.coin, 'ZEC');
      expect(sheet.source, kHlMarketMapSource);
      final viewed =
          events.where((e) => e.$1 == 'hyperliquid_market_viewed').single;
      expect(viewed.$2?['entry_source'], 'market_map');
      expect(tester.takeException(), isNull);
    });
  });
}
