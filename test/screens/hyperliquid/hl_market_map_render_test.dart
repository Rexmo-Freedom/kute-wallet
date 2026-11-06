// On demand: renders the market map from a fake universe shaped on the
// venue's own lists (hl_market_map_fixture.dart) into PNGs for a look by
// eye: the card alone at a phone's width (390), light and dark, its
// loading state, and the bottom of the Investing default view with the
// card under the list. Logos are not fetched, so the big tiles show their
// category glyph or letter tile.
//
//   flutter test test/screens/hyperliquid/hl_market_map_render_test.dart \
//     --dart-define=HL_MAP_RENDER_OUT=<dir>
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
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_map.dart';
import 'package:kute/screens/hyperliquid/hyperliquid_screen.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';
import 'package:kute/theme/app_theme.dart';

import '../usd/investments_harness.dart';
import 'hl_market_map_fixture.dart';

const _out = String.fromEnvironment('HL_MAP_RENDER_OUT');
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

List<Override> get _overrides => [
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidSparklineStoreProvider.overrideWithValue(
          HlSparklineStore(fetch: (_) async => const [100, 101, 99, 102])),
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

/// The card alone at a phone's width.
Future<void> _renderCard(WidgetTester tester,
    {required bool dark, required String name, bool loading = false}) async {
  const size = Size(390, 520);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: _overrides,
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: (dark ? buildDarkTheme() : buildLightTheme()).copyWith(
            textTheme: (dark ? buildDarkTheme() : buildLightTheme())
                .textTheme
                .apply(fontFamily: 'Inter')),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RepaintBoundary(
          key: _shotKey,
          child: Builder(
            builder: (context) => Material(
              color: context.colors.background,
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: HlMarketMapCard(
                      universe: hlMarketMapFixture, loading: loading),
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
    test('market map render', () {},
        skip: 'on demand: --dart-define=HL_MAP_RENDER_OUT=<dir>');
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
    testWidgets('card $mode', (tester) async {
      await _renderCard(tester, dark: dark, name: 'map_$mode');
    });
    testWidgets('loading $mode', (tester) async {
      await _renderCard(tester,
          dark: dark, name: 'map_loading_$mode', loading: true);
    });
    testWidgets('investing bottom $mode', (tester) async {
      await pumpInvestments(tester,
          browseInvesting: true,
          dark: dark,
          size: const Size(390, 844),
          child: RepaintBoundary(
            key: _shotKey,
            child: const Scaffold(body: HyperliquidScreen()),
          ),
          overrides: [
            hyperliquidBrowseUniverseProvider
                .overrideWithValue(AsyncValue.data(hlMarketMapFixture)),
            hyperliquidBuilderMarketsMissingProvider.overrideWithValue(false),
            ..._overrides,
          ]);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.drag(
          find.byType(CustomScrollView).first, const Offset(0, -600));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _shot(tester, 'investing_bottom_$mode');
      await unmountInvestments(tester);
    });
  }
}
