// On demand: renders the whole Dollars page on its Overview pill into PNGs
// for a look by eye: with positions, without, and with Investing's browsing
// withheld, light and dark, 320 and 375 wide; the end of the tab, scrolled,
// over the bar; the pill row in the longest locale; and the one card of an
// order on its way, Placing then placed (a prediction in the order's own
// card, an Investing order on a listed position's row), light and dark;
// and three predictions with long names, two squares and the full-width
// card, every name whole (founder, 10 November 2026, on 2.2.0 (99): "on
// the overview the text is cut"), light and dark.
// Logos are not fetched, so the big tiles show their category glyph or
// letter tile.
//
//   flutter test test/screens/usd/dollars_overview_render_test.dart \
//     --dart-define=DOLLARS_OVERVIEW_RENDER_OUT=<dir>
//
// Without the define the file does nothing.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart' show HyperliquidCandle;
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketActivePositionsProvider;
import 'package:kute/providers/polymarket_live_prices_provider.dart'
    show livePriceProvider;
import 'package:kute/providers/open_pnl_history_provider.dart'
    show OpenPnlSources;
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/standing_orders/standing_orders_provider.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/portfolio_overrides.dart' show PortfolioTestTrading;
import '../hyperliquid/hl_market_map_fixture.dart';
import 'dollars_overview_no_cut_test.dart'
    show NoLivePolyPrices, longPositions;
import 'investments_harness.dart';

const _out = String.fromEnvironment('DOLLARS_OVERVIEW_RENDER_OUT');
final _shotKey = GlobalKey();

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

HlPerpPosition _perp(String coin, double pnl) => HlPerpPosition(
    coin: coin,
    szi: 1,
    entryPx: 100,
    positionValue: 100 + pnl,
    unrealizedPnl: pnl,
    returnOnEquity: pnl / 50,
    liquidationPx: null,
    marginUsed: 50,
    leverageType: 'cross',
    leverageValue: 2,
    maxLeverage: 40);

HlFill _opened(String coin, DateTime now) => HlFill(
      coin: coin,
      px: 100,
      sz: 1,
      side: 'B',
      time: now.subtract(const Duration(days: 10)).millisecondsSinceEpoch,
      closedPnl: 0,
      fee: 0,
      feeToken: 'USDC',
      oid: coin.hashCode,
      hash: '0xopen-$coin',
      dir: 'Open Long',
      cloid: null,
      startPosition: 0,
    );

Future<void> _render(WidgetTester tester, String name,
    {required Size size,
    bool dark = false,
    bool positions = false,
    bool withheld = false,
    bool scrolled = false,
    List<StandingOrder> standing = const [],
    List<Override> extra = const [],
    Locale? locale}) async {
  final now = DateTime.now();
  const coins = ['BTC', 'ETH', 'SOL', 'HYPE'];
  await pumpInvestments(tester,
      browseInvesting: !withheld,
      dark: dark,
      size: size,
      locale: locale,
      // The app's own theme and the Material the shell gives the page.
      child: RepaintBoundary(
        key: _shotKey,
        child: Theme(
          data: (dark ? buildDarkTheme() : buildLightTheme()).copyWith(
              textTheme: (dark ? buildDarkTheme() : buildLightTheme())
                  .textTheme
                  .apply(fontFamily: 'Inter')),
          child: const Scaffold(body: UsdAccountScreen()),
        ),
      ),
      openPnlSources: OpenPnlSources(
        activity: (_) async => const [],
        candles: (_, wire, interval, window) async => [
          for (var t = now.subtract(window);
              t.isBefore(now);
              t = t.add(const Duration(hours: 4)))
            HyperliquidCandle(
                openTime: t,
                closeTime: t.add(const Duration(hours: 4)),
                open: 103,
                high: 103,
                low: 103,
                close: 103,
                volume: 1),
        ],
        polyHistory: (_, __, ___) async => null,
      ),
      overrides: [
        hyperliquidBrowseUniverseProvider
            .overrideWithValue(AsyncValue.data(hlMarketMapFixture)),
        hyperliquidBuilderMarketsMissingProvider.overrideWithValue(false),
        hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
        hyperliquidSparklineStoreProvider.overrideWithValue(
            HlSparklineStore(fetch: (_) async => const [100, 101, 99, 102])),
        if (positions)
          hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
              HyperliquidTradingState(
                  isInitialized: true,
                  positions: [
                    for (final (i, c) in coins.indexed)
                      _perp(c, i.isEven ? 3 : -1.5),
                  ],
                  recentFills: [for (final c in coins) _opened(c, now)]))),
        ...extra,
      ]);
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (standing.isNotEmpty) {
    ProviderScope.containerOf(
            tester.element(find.byType(InvestmentsBody, skipOffstage: false)))
        .read(standingOrdersProvider.notifier)
        .debugReplace(standing);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  if (scrolled) {
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(NestedScrollView), const Offset(0, -500));
      for (var f = 0; f < 15; f++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
  }
  for (Object? e = tester.takeException();
      e != null;
      e = tester.takeException()) {
    final text = '$e'.split('\n').first;
    if (!text.contains('MissingPlugin') && !text.contains('HTTP')) {
      // ignore: avoid_print
      print('RENDER problem: $text');
    }
  }
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
  // ignore: avoid_print
  print('RENDER wrote $_out/$name.png');
  await unmountInvestments(tester);
}

void main() {
  if (_out.isEmpty) {
    test('Dollars Overview render', () {},
        skip: 'on demand: --dart-define=DOLLARS_OVERVIEW_RENDER_OUT=<dir>');
    return;
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Directory(_out).createSync(recursive: true);
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
      final inter = FontLoader(family);
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    }
    // The category glyphs: the SDK's Material icon font (tests draw tofu
    // without it).
    final root = Platform.environment['FLUTTER_ROOT'];
    final icons = File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (root != null && icons.existsSync()) {
      final bytes = icons.readAsBytesSync();
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    for (final width in [320.0, 375.0]) {
      final size = Size(width, width == 320 ? 568 : 812);
      final w = width.round();
      testWidgets('positions $w $mode', (tester) => _render(
          tester, 'positions_${w}_$mode',
          size: size, dark: dark, positions: true));
      testWidgets('no positions $w $mode', (tester) => _render(
          tester, 'no_positions_${w}_$mode',
          size: size, dark: dark));
      testWidgets('withheld $w $mode', (tester) => _render(
          tester, 'withheld_${w}_$mode',
          size: size, dark: dark, withheld: true));
      testWidgets('withheld positions $w $mode', (tester) => _render(
          tester, 'withheld_positions_${w}_$mode',
          size: size, dark: dark, withheld: true, positions: true));
      testWidgets('scrolled end $w $mode', (tester) => _render(
          tester, 'scrolled_end_${w}_$mode',
          size: size, dark: dark, positions: true, scrolled: true));
    }
  }
  // The one card of an order on its way: Placing, then placed (founder, 10
  // November 2026: "show the actual one, with placing and when it's
  // placed, we just show placed").
  StandingOrder prediction(StandingOrderState state) => StandingOrder(
        id: 'so_render_p',
        walletId: 'spending',
        venue: StandingOrderVenue.predictions,
        marketKey: 'tok-render',
        marketTitle: 'Will it rain in Lisbon tomorrow?',
        sideLabel: 'Yes',
        isBuy: true,
        size: 19.23,
        approvedPrice: 0.52,
        amountUsd: 10,
        orderKind: 'market',
        state: state,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        filledSize: state == StandingOrderState.filled ? 19.6 : null,
        filledUsd: state == StandingOrderState.filled ? 9.8 : null,
      );
  StandingOrder investing(StandingOrderState state) => StandingOrder(
        id: 'so_render_i',
        walletId: 'spending',
        venue: StandingOrderVenue.investing,
        marketKey: 'ETH',
        marketTitle: 'ETH · Perp',
        sideLabel: 'long',
        isBuy: true,
        size: 20,
        approvedPrice: 3000,
        amountUsd: 20,
        orderKind: 'market',
        state: state,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        leverage: 2,
        marketKind: 'perp',
      );
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    const size = Size(375, 812);
    for (final (name, state) in [
      ('placing', StandingOrderState.funding),
      ('placed', StandingOrderState.filled),
    ]) {
      testWidgets('one card $name prediction $mode', (tester) => _render(
          tester, 'one_card_${name}_prediction_$mode',
          size: size,
          dark: dark,
          positions: true,
          standing: [prediction(state)]));
      testWidgets('one card $name investing $mode', (tester) => _render(
          tester, 'one_card_${name}_investing_$mode',
          size: size,
          dark: dark,
          positions: true,
          standing: [investing(state)]));
      testWidgets('one card $name alone $mode', (tester) => _render(
          tester, 'one_card_${name}_alone_$mode',
          size: size,
          dark: dark,
          standing: [prediction(state)]));
    }
  }
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('long names $mode', (tester) => _render(
        tester, 'overview_long_names_$mode',
        size: const Size(375, 812),
        dark: dark,
        extra: [
          polymarketActivePositionsProvider
              .overrideWith((_) => longPositions()),
          livePriceProvider.overrideWith(NoLivePolyPrices.new),
        ]));
  }
  // The longest name the pill takes (Romanian, "Prezentare generală"), then
  // German and Greek, on the narrowest phone.
  for (final code in ['ro', 'de', 'el']) {
    for (final width in [320.0, 375.0]) {
      final w = width.round();
      testWidgets('locale $code $w', (tester) => _render(
          tester, 'locale_${code}_$w',
          size: Size(width, 568), locale: Locale(code)));
    }
    // The compact bar, its chevron beside the row, on the narrowest.
    testWidgets('locale $code 320 compact', (tester) => _render(
        tester, 'locale_${code}_320_compact',
        size: const Size(320, 568),
        locale: Locale(code),
        positions: true,
        scrolled: true));
  }
}
