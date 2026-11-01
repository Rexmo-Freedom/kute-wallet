// On demand: renders the Trending strip from a fake universe into PNGs for
// a look by eye: the hyped strip alone (light and dark, wide enough for
// every card), the same over the top of the Investing list, and the
// movers fallback (no builder dex loaded). Logos are not fetched, so every
// card shows its category glyph or letter tile.
//
//   flutter test test/screens/hyperliquid/hl_trending_strip_render_test.dart \
//     --dart-define=HL_STRIP_RENDER_OUT=<dir>
//
// Without the define the file does nothing.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_moving_now_strip.dart';
import 'package:kute/screens/hyperliquid/hyperliquid_screen.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';
import 'package:kute/theme/app_theme.dart';

import '../usd/investments_harness.dart';
import 'hl_trending_strip_fixture.dart';

const _out = String.fromEnvironment('HL_STRIP_RENDER_OUT');
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

/// A different week per market, so the sparklines are not all one line.
final _sparks = HlSparklineStore(fetch: (wire) async {
  final seed = wire.codeUnits.fold<int>(0, (a, b) => a * 31 + b);
  return [
    for (var i = 0; i < 7; i++) 100 + ((seed >> (i * 3)) % 9) - 4.0 + i * 0.6,
  ];
});

List<Override> get _overrides => [
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidSparklineStoreProvider.overrideWithValue(_sparks),
    ];

Future<void> _shot(WidgetTester tester, String name) async {
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
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
  // ignore: avoid_print
  print('RENDER wrote $_out/$name.png');
}

/// The strip alone on a canvas wide enough for every card.
Future<void> _renderStrip(WidgetTester tester, List<HlMarket> strip,
    {required bool dark, required String name}) async {
  const size = Size(1000, 240);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: _overrides,
    child: ScreenUtilInit(
      designSize: size,
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RepaintBoundary(
          key: _shotKey,
          child: Builder(
            builder: (context) => ColoredBox(
              color: context.colors.background,
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: HlMovingNowStrip(markets: strip),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await _shot(tester, name);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 7));
}

void main() {
  if (_out.isEmpty) {
    test('trending strip render', () {},
        skip: 'on demand: --dart-define=HL_STRIP_RENDER_OUT=<dir>');
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

  final trending =
      hlBrowseListForTab(HlBrowseTab.trending, hlTrendingFixture);
  final hyped = hlTrendingStrip(hlTrendingFixture, trending);

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('hyped strip $mode', (tester) async {
      await _renderStrip(tester, hyped, dark: dark, name: 'strip_$mode');
    });
  }

  testWidgets('movers fallback light', (tester) async {
    final crypto = [
      for (final m in hlTrendingFixture)
        if (!m.isHip3 && !m.isSpot) m,
    ];
    final strip = hlTrendingStrip(
        crypto, hlBrowseListForTab(HlBrowseTab.trending, crypto));
    await _renderStrip(tester, strip, dark: false, name: 'fallback_light');
  });

  testWidgets('investing top light', (tester) async {
    await pumpInvestments(tester,
        browseInvesting: true,
        child: RepaintBoundary(
          key: _shotKey,
          child: const Scaffold(body: HyperliquidScreen()),
        ),
        overrides: [
          hyperliquidBrowseUniverseProvider
              .overrideWithValue(AsyncValue.data(hlTrendingFixture)),
          hyperliquidBuilderMarketsMissingProvider.overrideWithValue(false),
          ..._overrides,
        ]);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _shot(tester, 'investing_top_light');
    await unmountInvestments(tester);
  });
}
