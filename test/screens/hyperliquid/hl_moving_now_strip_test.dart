// "Moving now": the strip of large cards above the Investing browse list
// (founder, November 2026): the category's largest 24h moves, up to five,
// ties by volume, thin markets left out; a card taps through to the
// market sheet with 'moving_now' as its entry source; no strip under
// three movers or on an empty list. The list under it keeps its own
// (volume) order.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart';
import 'package:kute/screens/hyperliquid/components/hl_moving_now_strip.dart';
import 'package:kute/screens/hyperliquid/hyperliquid_screen.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/screens/shared/kute_motion.dart' show KutePressable;
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

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

/// The cards on screen, left to right (the row builds lazily: the ones
/// past its right edge are not built until it scrolls).
List<String> _cards(WidgetTester tester) => [
      for (final c in tester.widgetList<HlMovingNowCard>(
          find.byType(HlMovingNowCard)))
        c.market.coin,
    ];

Future<void> _pump(WidgetTester tester, List<HlMarket> universe,
    {List<Override> overrides = const []}) async {
  await pumpInvestments(tester,
      browseInvesting: true,
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
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('the movers: largest absolute change first, ties by volume, thin '
      'and unknown left out, none under three', () {
    expect(hlMovingNow(_universe).map((m) => m.coin),
        ['ZEC', 'HYPE', 'DOGE', 'NEAR', 'SOL']);
    expect(hlMovingNow(_universe, max: 3).map((m) => m.coin),
        ['ZEC', 'HYPE', 'DOGE']);
    // A thin market's change is noise: left out even when it is largest.
    final thin = _market('MU', px: 150, prev: 100, vlm: 100);
    expect(hlMovingNow([..._universe, thin]).map((m) => m.coin),
        isNot(contains('MU')));
    // Two movers make no strip; three do.
    expect(hlMovingNow(_universe.take(3).toList()), isEmpty);
    expect(hlMovingNow(_universe.take(4).toList()).map((m) => m.coin),
        ['HYPE', 'SOL', 'BTC']);
    expect(hlMovingNow(const []), isEmpty);
  });

  testWidgets('the strip shows the top movers in order over the list, which '
      'keeps its own order without them', (tester) async {
    await _pump(tester, _universe);

    expect(_strip(), findsOneWidget);
    // No title over the strip (founder, 1 November 2026).
    expect(find.text('Moving now'), findsNothing);
    expect(tester.widget<HlMovingNowStrip>(_strip()).markets.map((m) => m.coin),
        ['ZEC', 'HYPE', 'DOGE', 'NEAR', 'SOL']);
    // The first cards are on screen, the rest past the right edge.
    final cards = _cards(tester);
    expect(cards.length, inInclusiveRange(2, 5));
    expect(cards, ['ZEC', 'HYPE', 'DOGE', 'NEAR', 'SOL'].take(cards.length));
    // The strip sits above the list, and the list does not repeat the
    // strip's markets (founder, 1 November 2026).
    final stripBottom = tester.getBottomLeft(_strip()).dy;
    final rows = tester.widgetList<HlMarketCard>(find.byType(HlMarketCard));
    expect(rows.first.market.coin, 'BTC');
    expect(rows.map((r) => r.market.coin),
        isNot(contains(anyOf('ZEC', 'HYPE', 'DOGE', 'NEAR', 'SOL'))));
    expect(tester.getTopLeft(find.byType(HlMarketCard).first).dy,
        greaterThan(stripBottom));

    // The card: logo, name, ticker, a line across it, the short price and
    // the arrowed change in the change's colour.
    final zec = find.byKey(const ValueKey('hl-mover-perp-ZEC'));
    expect(zec, findsOneWidget);
    expect(find.descendant(of: zec, matching: find.text('ZEC')), findsOneWidget);
    expect(
        find.descendant(of: zec, matching: find.byType(KutePressable)),
        findsOneWidget);
    final line = tester.widget<HlLineSparkline>(
        find.descendant(of: zec, matching: find.byType(HlLineSparkline)));
    expect(line.baseline, isFalse);
    expect(line.closes, isNotEmpty);
    final numbers = tester
        .widgetList<RollingNumberText>(
            find.descendant(of: zec, matching: find.byType(RollingNumberText)))
        .toList();
    expect(numbers.map((n) => n.text), [r'$112.00', '▲ 12.0%']);
    expect(numbers[1].style.color, AppColors.marketUp);
    final hype = find.byKey(const ValueKey('hl-mover-perp-HYPE'));
    expect(
        tester
            .widgetList<RollingNumberText>(find.descendant(
                of: hype, matching: find.byType(RollingNumberText)))
            .last
            .text,
        '▼ 8.0%');

    // The cards run past the right edge, where the row scrolls.
    final first = tester.getRect(zec);
    expect(first.left, moreOrLessEquals(16, epsilon: 2));
    // Square (founder, 1 November 2026): 148 design units on a side.
    expect(first.width, moreOrLessEquals(148 * 390 / 430, epsilon: 1));
    expect(first.height, moreOrLessEquals(first.width, epsilon: 1));
    final last = tester.getRect(find.byType(HlMovingNowCard).last);
    expect(last.right, greaterThan(390));
    await tester.drag(_strip(), const Offset(-400, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('hl-mover-perp-SOL')), findsOneWidget);
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

  testWidgets('no strip on an empty list, nor under three movers',
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
}
