// The big squares above the Investing browse list (founder, November
// 2026; 2 November 2026: four, two by two, as the Bitcoin home's Latest
// squares), on the default view (Trending) only: with no stocks or
// commodities loaded, the largest 24h moves, four, ties by volume, thin
// markets left out; a square taps through to the market sheet with
// 'moving_now' as its entry source; no squares under four movers or on an
// empty list, and none on a category the person picks (the full plain
// list). The list under them keeps its own (volume) order. A square: logo
// and change, then the name over the price, no sparkline. Only markets
// with a logo of their own (founder, 11 November 2026: "don't show Moving
// now without svg"): one without is skipped for the next; the squares'
// skeleton while logos that could fill them are unknown, never letter
// tiles.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart';
import 'package:kute/screens/hyperliquid/components/hl_moving_now_strip.dart';
import 'package:kute/screens/hyperliquid/hyperliquid_screen.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/screens/shared/kute_motion.dart' show KutePressable;
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';

import '../usd/investments_harness.dart';

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

HlMarket _market(String coin,
        {double px = 100,
        double prev = 100,
        double vlm = 1e6,
        HlMarketKind kind = HlMarketKind.perp,
        String? wire}) =>
    HlMarket(
      coin: coin,
      wireCoin: wire ?? coin,
      assetId: 0,
      kind: kind,
      szDecimals: 2,
      maxLeverage: 20,
      onlyIsolated: false,
      markPx: px,
      midPx: px,
      prevDayPx: prev,
      dayNtlVlm: vlm,
      category: 'crypto',
    );

/// By volume: BTC, ETH, SOL, HYPE, XRP, DOGE, NEAR, ZEC. By move: ZEC
/// (+12%), HYPE (−8%), DOGE (+5%), NEAR (−5%, the same move with less
/// volume than DOGE), SOL (+3%), then XRP (+2%), BTC (+1%); ETH has no
/// change to show.
final _universe = [
  _market('BTC', px: 101, prev: 100, vlm: 9e9),
  _market('ETH', px: 4000, prev: 0, vlm: 8e9),
  _market('SOL', px: 103, prev: 100, vlm: 7e9),
  _market('HYPE', px: 46, prev: 50, vlm: 6e9),
  _market('XRP', px: 2.04, prev: 2, vlm: 5e9),
  _market('DOGE', px: 105, prev: 100, vlm: 4e9),
  _market('NEAR', px: 95, prev: 100, vlm: 3e9),
  _market('ZEC', px: 112, prev: 100, vlm: 2e9),
];

Finder _strip() => find.byType(HlMovingNowStrip);

/// The squares, row by row.
List<String> _cards(WidgetTester tester) => [
      for (final c in tester.widgetList<HlMovingNowCard>(
          find.byType(HlMovingNowCard)))
        c.market.coin,
    ];

Future<void> _pump(WidgetTester tester, List<HlMarket> universe,
    {List<Override> overrides = const [],
    Size size = const Size(390, 844)}) async {
  await pumpInvestments(tester,
      browseInvesting: true,
      size: size,
      child: const Scaffold(body: HyperliquidScreen()),
      overrides: [
        hyperliquidBrowseUniverseProvider
            .overrideWithValue(AsyncValue.data(universe)),
        hyperliquidBuilderMarketsMissingProvider.overrideWithValue(false),
        hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
        hyperliquidSparklineStoreProvider.overrideWithValue(HlSparklineStore(
            fetch: (_) async => const [100, 104, 102, 108, 112])),
        ...overrides,
      ]);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  // The Investing squares list only markets with a logo of their own:
  // here every market has one.
  setUp(() => HlIconAvailability.debugEveryLogoKnown = true);
  tearDown(() => HlIconAvailability.debugEveryLogoKnown = false);
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('the movers: largest absolute change first, ties by volume, thin '
      'and unknown left out, none under four', () {
    expect(hlMovingNow(_universe).map((m) => m.coin),
        ['ZEC', 'HYPE', 'DOGE', 'NEAR']);
    expect(hlMovingNow(_universe, max: 3).map((m) => m.coin),
        ['ZEC', 'HYPE', 'DOGE']);
    // A thin market's change is noise: left out even when it is largest.
    final thin = _market('MU', px: 150, prev: 100, vlm: 100);
    expect(hlMovingNow([..._universe, thin]).map((m) => m.coin),
        isNot(contains('MU')));
    // Three movers make no squares (a grid with a hole); four do.
    expect(hlMovingNow(_universe.take(4).toList()), isEmpty);
    expect(hlMovingNow(_universe.take(5).toList()).map((m) => m.coin),
        ['HYPE', 'SOL', 'XRP', 'BTC']);
    expect(hlMovingNow(const []), isEmpty);
  });

  testWidgets('the strip shows the top movers in order over the list, which '
      'keeps its own order without them', (tester) async {
    await _pump(tester, _universe);

    expect(_strip(), findsOneWidget);
    // No title over the strip (founder, 1 November 2026).
    expect(find.text('Moving now'), findsNothing);
    expect(tester.widget<HlMovingNowStrip>(_strip()).markets.map((m) => m.coin),
        ['ZEC', 'HYPE', 'DOGE', 'NEAR']);
    expect(_cards(tester), ['ZEC', 'HYPE', 'DOGE', 'NEAR']);
    // The strip sits above the list, and the list does not repeat the
    // strip's markets (founder, 1 November 2026).
    final stripBottom = tester.getBottomLeft(_strip()).dy;
    final rows = tester.widgetList<HlMarketCard>(find.byType(HlMarketCard));
    expect(rows.first.market.coin, 'BTC');
    expect(rows.map((r) => r.market.coin),
        isNot(contains(anyOf('ZEC', 'HYPE', 'DOGE', 'NEAR'))));
    expect(tester.getTopLeft(find.byType(HlMarketCard).first).dy,
        greaterThan(stripBottom));

    // The square: logo, the arrowed change in the change's colour, the
    // name, the short price large; no sparkline and no ticker line.
    final zec = find.byKey(const ValueKey('hl-mover-perp-ZEC'));
    expect(zec, findsOneWidget);
    expect(find.descendant(of: zec, matching: find.text('ZEC')), findsOneWidget);
    expect(
        find.descendant(of: zec, matching: find.byType(KutePressable)),
        findsOneWidget);
    expect(find.descendant(of: zec, matching: find.byType(HlLineSparkline)),
        findsNothing);
    expect(
        find.descendant(
            of: zec,
            matching: find.byWidgetPredicate(
                (w) => w is Text && (w.data ?? '').contains('·'))),
        findsNothing);
    final numbers = tester
        .widgetList<RollingNumberText>(
            find.descendant(of: zec, matching: find.byType(RollingNumberText)))
        .toList();
    expect(numbers.map((n) => n.text), ['▲ 12.0%', r'$112.00']);
    expect(numbers[1].style.fontSize, moreOrLessEquals(22 * 390 / 430, epsilon: 0.5));
    expect(numbers[1].style.fontWeight, FontWeight.w700);
    expect(numbers[0].style.color, AppColors.marketUp);
    final hype = find.byKey(const ValueKey('hl-mover-perp-HYPE'));
    expect(
        tester
            .widgetList<RollingNumberText>(find.descendant(
                of: hype, matching: find.byType(RollingNumberText)))
            .first
            .text,
        '▼ 8.0%');

    // Two by two, as the home's Latest squares: half the row less the
    // 10 gap each, at least the Latest square's 140 tall.
    const u = 390 / 430;
    final first = tester.getRect(zec);
    expect(first.left, moreOrLessEquals(16 * u, epsilon: 2));
    expect(first.width,
        moreOrLessEquals((390 - 32 * u - 10 * u) / 2, epsilon: 1));
    expect(first.height, greaterThanOrEqualTo(140 * u - 1));
    final second = tester.getRect(find.byType(HlMovingNowCard).at(1));
    final third = tester.getRect(find.byType(HlMovingNowCard).at(2));
    final fourth = tester.getRect(find.byType(HlMovingNowCard).at(3));
    expect(second.top, moreOrLessEquals(first.top, epsilon: 0.5));
    expect(second.left - first.right, moreOrLessEquals(10 * u, epsilon: 1));
    expect(second.right, moreOrLessEquals(390 - 16 * u, epsilon: 2));
    expect(third.left, moreOrLessEquals(first.left, epsilon: 0.5));
    expect(third.top - first.bottom, moreOrLessEquals(10 * u, epsilon: 1));
    expect(fourth.top, moreOrLessEquals(third.top, epsilon: 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a card opens the market sheet with the strip as its source',
      (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    final zec = _universe.last;
    await _pump(tester, _universe, overrides: [
      // The sheet's own reads (no network in a test).
      hyperliquidExactMarketProvider.overrideWith((ref, key) => zec),
      hyperliquidActiveAssetCtxProvider
          .overrideWith((ref, wire) => const Stream.empty()),
      hyperliquidOrderbookProvider
          .overrideWith((ref, wire) => const Stream.empty()),
      hyperliquidPerpPositionsProvider.overrideWith((_) => const []),
      hyperliquidSpotBalancesProvider.overrideWith((_) => const []),
      hyperliquidActivityFillsProvider.overrideWith((_) => const []),
      hyperliquidLiveCandlesProvider.overrideWith((ref, key) =>
          Stream.value(const HlLiveCandlesState(candles: []))),
      hyperliquidTradeFlowProvider.overrideWith(
          (ref, coin) => Stream.value(const HlTradeFlowState())),
    ]);

    await tester.tap(find.byKey(const ValueKey('hl-mover-perp-ZEC')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final sheet =
        tester.widget<HlMarketDetailSheet>(find.byType(HlMarketDetailSheet));
    expect(sheet.market.coin, 'ZEC');
    expect(sheet.source, 'moving_now');
    final viewed =
        events.where((e) => e.$1 == 'hyperliquid_market_viewed').single;
    expect(viewed.$2?['coin'], 'ZEC');
    expect(viewed.$2?['entry_source'], 'moving_now');
    expect(tester.takeException(), isNull);
  });

  testWidgets('no squares on an empty list, nor under four movers',
      (tester) async {
    await _pump(tester, const []);
    expect(_strip(), findsNothing);
    expect(find.text('Moving now'), findsNothing);

    // Markets, but only two with a change to show.
    await _pump(tester, [
      _market('BTC', px: 101, prev: 100, vlm: 9e9),
      _market('ETH', px: 4000, prev: 0, vlm: 8e9),
      _market('SOL', px: 103, prev: 100, vlm: 7e9),
    ]);
    expect(find.byType(HlMarketCard), findsNWidgets(3));
    expect(_strip(), findsNothing);
  });

  test('the list price is short: four figures, two decimals at least', () {
    expect(formatHlListPrice(47.912), r'$47.91');
    expect(formatHlListPrice(4128.4), r'$4,128.40');
    expect(formatHlListPrice(114236), r'$114,236.00');
    expect(formatHlListPrice(2.6312), r'$2.631');
    expect(formatHlListPrice(0.2051), r'$0.2051');
    expect(formatHlListPrice(0.012345), r'$0.01235');
    // Trailing zeros go, down to two decimals; the market's cap holds.
    expect(formatHlListPrice(2.63), r'$2.63');
    expect(formatHlListPrice(0.2), r'$0.20');
    expect(formatHlListPrice(0.2051, decimalCap: 2), r'$0.21');
    expect(formatHlListPrice(0), '—');
  });

  test('the default view keeps six rows; any other list is whole', () {
    final rows = List.generate(20, (i) => i);
    expect(hlBrowseRowsShown(true, rows), [0, 1, 2, 3, 4, 5]);
    expect(kHlTrendingListRows, 6);
    expect(hlBrowseRowsShown(false, rows), rows);
    expect(hlBrowseRowsShown(true, rows.take(4).toList()), [0, 1, 2, 3]);
  });

  test('only Trending at its default list has a strip', () {
    expect(hlBrowseIsDefaultView(HlBrowseTab.trending, HlBrowseSub.all),
        isTrue);
    expect(hlBrowseIsDefaultView(HlBrowseTab.perps, HlBrowseSub.all),
        isFalse);
    expect(hlBrowseIsDefaultView(HlBrowseTab.trending, HlBrowseSub.meme),
        isFalse);
  });

  testWidgets('Trending lists six rows under the strip and nothing after; '
      'a picked category has no strip and lists every market',
      (tester) async {
    final many = [
      for (var i = 0; i < 24; i++)
        _market('C$i', px: 100 + i.toDouble(), prev: 100, vlm: 9e9 - i * 1e8),
    ];
    await _pump(tester, many, size: const Size(390, 4000));
    expect(_strip(), findsOneWidget);
    expect(find.byType(HlMarketCard, skipOffstage: false), findsNWidgets(6));
    final onStrip = _cards(tester).toSet();
    final rows = [
      for (final c in tester.widgetList<HlMarketCard>(
          find.byType(HlMarketCard, skipOffstage: false)))
        c.market.coin,
    ];
    expect(rows.toSet().intersection(onStrip), isEmpty);
    // Perps (picked at the top): no strip, the whole plain list, nothing
    // left out (the markets Trending's strip carried are rows here).
    final container = ProviderScope.containerOf(
        tester.element(find.byType(HyperliquidScreen)));
    container.read(hlBrowseSelectionProvider.notifier).state = container
        .read(hlBrowseSelectionProvider)
        .copyWith(tab: HlBrowseTab.perps);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_strip(), findsNothing);
    final perpsRows = [
      for (final c in tester.widgetList<HlMarketCard>(
          find.byType(HlMarketCard, skipOffstage: false)))
        c.market.coin,
    ];
    expect(perpsRows, hasLength(24));
    expect(perpsRows.toSet().containsAll(onStrip), isTrue);
    expect(tester.takeException(), isNull);
  });

  group('only markets with a logo of their own', () {
    HlLogoStatus Function(HlMarket) statuses(Map<String, HlLogoStatus> s) =>
        (m) => s[m.coin] ?? HlLogoStatus.hit;
    List<String> coins(List<HlMarket> ms) => [for (final m in ms) m.coin];

    test('a mover with no logo is skipped; the next with one takes its place',
        () {
      final pick = hlStripWithLogos(
          (keep) => hlMovingNow(_universe, keep: keep),
          status: statuses({'HYPE': HlLogoStatus.miss}));
      expect(coins(pick.shown), ['ZEC', 'DOGE', 'NEAR', 'SOL']);
      expect(pick.pending, isEmpty);
      expect(pick.loading, isFalse);
    });

    test('the liquidity floor still applies to markets with a logo', () {
      final thin = _market('MU', px: 150, prev: 100, vlm: 100);
      final pick = hlStripWithLogos(
          (keep) => hlMovingNow([..._universe, thin], keep: keep),
          status: (_) => HlLogoStatus.hit);
      expect(coins(pick.shown), ['ZEC', 'HYPE', 'DOGE', 'NEAR']);
    });

    test('a higher logo not known yet: the four known show meanwhile', () {
      final pick = hlStripWithLogos(
          (keep) => hlMovingNow(_universe, keep: keep),
          status: statuses({'ZEC': HlLogoStatus.unknown}));
      expect(coins(pick.shown), ['HYPE', 'DOGE', 'NEAR', 'SOL']);
      expect(coins(pick.best), ['ZEC', 'HYPE', 'DOGE', 'NEAR']);
      expect(coins(pick.pending), ['ZEC']);
      expect(pick.loading, isFalse);
    });

    test('unknown logos that could fill the squares: loading; a miss among '
        'four: no squares (no hole)', () {
      // Four movers: HYPE, SOL, XRP, BTC.
      final four = _universe.take(5).toList();
      final unknown = hlStripWithLogos(
          (keep) => hlMovingNow(four, keep: keep),
          status: statuses({'HYPE': HlLogoStatus.unknown}));
      expect(unknown.shown, isEmpty);
      expect(unknown.loading, isTrue);
      expect(coins(unknown.pending), ['HYPE']);
      final miss = hlStripWithLogos(
          (keep) => hlMovingNow(four, keep: keep),
          status: statuses({'HYPE': HlLogoStatus.miss}));
      expect(miss.shown, isEmpty);
      expect(miss.loading, isFalse);
    });

    testWidgets('on the screen: HYPE has no logo, SOL takes its square',
        (tester) async {
      HlIconAvailability.debugEveryLogoKnown = false;
      HlIconPrefetch.debugReset();
      addTearDown(HlIconPrefetch.debugReset);
      for (final m in _universe) {
        HlIconAvailability.debugSeed(m, hit: m.coin != 'HYPE');
      }
      await _pump(tester, _universe);
      expect(_cards(tester), ['ZEC', 'DOGE', 'NEAR', 'SOL']);
      expect(find.descendant(of: _strip(), matching: find.byType(HlLetterBadge)),
          findsNothing);
      final rows = tester.widgetList<HlMarketCard>(find.byType(HlMarketCard));
      expect(rows.map((r) => r.market.coin), isNot(contains('SOL')));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'on the screen: the skeleton while logos are unknown, never letter '
        'tiles; settled, the squares; HYPE, whose only logo is CoinCap\'s, '
        'is not on them', (tester) async {
      HlIconAvailability.debugEveryLogoKnown = false;
      HlIconPrefetch.debugReset();
      addTearDown(HlIconPrefetch.debugReset);
      final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4PlnqPwgzwBgAX8AKjR/k5lsAAAAASUVORK5CYII=');
      final asked = <String>[];
      final venue = Completer<void>();
      SharedHttpClient.debugOverride = MockClient((req) async {
        final url = req.url.toString();
        asked.add(url);
        await venue.future;
        if (url.endsWith('/HYPE.svg')) {
          return http.Response('<!doctype html><html></html>', 200,
              headers: {'content-type': 'text/html'});
        }
        return http.Response.bytes(png, 200,
            headers: {'content-type': 'image/png'});
      });
      addTearDown(() => SharedHttpClient.debugOverride = null);

      await _pump(tester, _universe);
      expect(find.byType(HlMovingNowStripSkeleton), findsOneWidget);
      expect(find.byType(HlMovingNowCard), findsNothing);
      // The strip asks only for the markets' own logos.
      expect(asked.where((u) => u.contains('coincap')), isEmpty);
      expect(
          find.descendant(
              of: find.byType(HlMovingNowStripSkeleton),
              matching: find.byType(HlLetterBadge)),
          findsNothing);

      venue.complete();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(HlMovingNowStripSkeleton), findsNothing);
      expect(_cards(tester), ['ZEC', 'DOGE', 'NEAR', 'SOL']);
      // HYPE's row in the list draws CoinCap's PNG (the icon's last
      // resort); that is no logo of its own, so no square.
      expect(asked,
          contains('https://assets.coincap.io/assets/icons/hype@2x.png'));
      expect(HlIconAvailability.of(_universe[3]), HlLogoStatus.miss);
      expect(tester.takeException(), isNull);
    });
  });
}
