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
//     cards' width; with nothing open Sal over "No open positions", no map; the map's
//     skeleton in its place; a tile, scrolled to, opens its market, the
//     page clearing the bar; no category picked on Investing touches it;
//   * Investing is its plain list: no map, on any category;
//   * the map reads its own data: a new universe lands on Overview with the
//     pill on screen, and a pull re-reads the market lists, reporting
//     `tab: activity`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/refresh_everything_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_map.dart';
import 'package:kute/screens/hyperliquid/hyperliquid_screen.dart';
import 'package:kute/screens/portfolio/investments_portfolio.dart'
    show PortfolioSection;
import 'package:kute/screens/shared/kute_motion.dart' show SelectionFade;
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/usd/components/dollars_activity_tab.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_instant_provider.dart';
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show HlPositionRow;
import 'package:kute/services/polymarket/instant_rounds.dart';
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
/// [_pump] with a position open.
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
final _empty = find.byKey(const ValueKey('dollars-activity-empty'));
final _squares = find.byKey(const ValueKey('dollars-activity-squares'));
final _pnl = find.byKey(const ValueKey('dollars-pnl-strip'));
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
        'the market lists', (tester) async {
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

  group('Overview holds the open positions and the P&L, nothing else', () {
    testWidgets('positions held: the squares and the open P&L, no map',
        (tester) async {
      await _pumpHeld(tester, overrides: [
        _holding([_perp('BTC', 100), _perp('ETH', 500)]),
      ]);
      expect(_squares, findsOneWidget);
      expect(_pnl, findsOneWidget);
      expect(find.byType(HlMarketMapCard), findsNothing);
      expect(_empty, findsNothing);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets('at most four squares, however many are open',
        (tester) async {
      await _pumpHeld(tester, overrides: [
        _holding([
          _perp('BTC', 100),
          _perp('ETH', 500),
          _perp('SOL', 400),
          _perp('HYPE', 300),
          _perp('DOGE', 200),
          _perp('XRP', 150),
        ]),
      ]);
      expect(
          find.descendant(of: _squares, matching: find.byType(HlPositionRow)),
          findsNWidgets(4));
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets('nothing open: Sal over "No open positions", no heading',
        (tester) async {
      await _pump(tester);
      expect(find.byType(HlMarketMapCard), findsNothing);
      expect(_squares, findsNothing);
      expect(_pnl, findsNothing);
      expect(_empty, findsOneWidget);
      expect(find.text('No open positions'), findsOneWidget);
      expect(find.byKey(const ValueKey('dollars-activity-positions-heading')),
          findsNothing);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });
  });

  group('the last category is not remembered', () {
    testWidgets('leaving Predictions: Trending, Bitcoin five minutes',
        (tester) async {
      final container = await _pumpHeld(tester);
      await tapPill(tester, 'Predictions');
      container.read(polyBrowseSelectionProvider.notifier).state =
          const PolyBrowseSelection(pill: PolyPill.instant);
      container
          .read(polyInstantChoiceProvider.notifier)
          .pick(const PolyInstantChoice(asset: 'SOL', length: '15m'));
      await _frames(tester);

      await tapPill(tester, 'Investing');
      expect(container.read(polyBrowseSelectionProvider).pill,
          PolyPill.trending);
      expect(container.read(polyInstantChoiceProvider), kPolyInstantDefault);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets('leaving Investing: Trending', (tester) async {
      final container = await _pumpHeld(tester);
      await tapPill(tester, 'Investing');
      container.read(hlBrowseSelectionProvider.notifier).state =
          const HlBrowseSelection(tab: HlBrowseTab.perps);
      await _frames(tester);

      await tapPill(tester, 'Overview');
      expect(container.read(hlBrowseSelectionProvider).tab,
          HlBrowseTab.trending);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets('coming back to Dollars: Trending again', (tester) async {
      final container = await _pumpHeld(tester);
      await tapPill(tester, 'Predictions');
      container.read(polyBrowseSelectionProvider.notifier).state =
          const PolyBrowseSelection(pill: PolyPill.instant);
      await _frames(tester);

      openInvestmentsOnDefaultTab(_ref(tester));
      await tester.pump();
      expect(container.read(polyBrowseSelectionProvider).pill,
          PolyPill.trending);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });

    testWidgets('a pick stays while its pill is on screen', (tester) async {
      final container = await _pumpHeld(tester);
      await tapPill(tester, 'Predictions');
      container.read(polyBrowseSelectionProvider.notifier).state =
          const PolyBrowseSelection(pill: PolyPill.instant);
      await _frames(tester);
      expect(
          container.read(polyBrowseSelectionProvider).pill, PolyPill.instant);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });
  });
}
