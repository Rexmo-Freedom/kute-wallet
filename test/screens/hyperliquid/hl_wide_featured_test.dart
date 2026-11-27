// The wide web Investing home's featured card (founder, 27 November 2026:
// "on Investing and Predictions maybe have one big one"): on the web at
// MEDIUM and EXPANDED, Trending's featured set as ONE large card in place
// of the four squares, previous / next stepping through the set and
// wrapping, a click opening the shown market; the phone layout keeps the
// four squares.

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

List<Override> get _overrides => [
      hyperliquidBrowseUniverseProvider
          .overrideWithValue(AsyncValue.data(hlTrendingFixture)),
      hyperliquidBuilderMarketsMissingProvider.overrideWithValue(false),
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidSparklineStoreProvider.overrideWithValue(HlSparklineStore(
          fetch: (_) async => const [100, 104, 102, 108, 112])),
      hyperliquidLiveCandlesProvider
          .overrideWith((ref, key) => Stream.value(const HlLiveCandlesState())),
    ];

Future<void> _pumpScreen(WidgetTester tester, Size size) async {
  HyperliquidScreen.debugWideWeb = true;
  addTearDown(() => HyperliquidScreen.debugWideWeb = false);
  await pumpInvestments(tester,
      browseInvesting: true,
      size: size,
      designSize: KuteLayout.designSizeFor(size),
      child: const Scaffold(body: HyperliquidScreen(embedded: true)),
      overrides: _overrides);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

String _shownWire(WidgetTester tester) {
  final header = tester
      .widgetList(find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('hl-wide-featured-') &&
          !(w.key as ValueKey<String>).value.contains('-chart-') &&
          (w.key as ValueKey<String>).value.contains(':')))
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
}
