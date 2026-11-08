// Render harness for Predictions › Instant (founder, 8 November 2026): the
// sheet with either card picked, the Instant page at each filter, an empty
// length, own rounds on top, the blocked page and Trending without its
// card; light and dark, 320 and 375 wide, a long locale. Writes PNGs.
//
// Not part of the normal suite; it only runs when asked:
//
//   fvm flutter test test/audit/instant_render_test.dart \
//     --dart-define=INSTANT_OUT=/tmp/instant

import 'dart:io';
import 'dart:ui' as ui;

import 'package:file/file.dart' as fs;
import 'package:file/local.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/services/polymarket/instant_rounds.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import '../screens/polymarket/instant_predictions_test.dart';
import '../screens/usd/investments_harness.dart' show unmountInvestments;

const _out = String.fromEnvironment('INSTANT_OUT');

class _LocalArtwork implements BaseCacheManager {
  @override
  Future<fs.File> getSingleFile(String url,
      {String key = '', Map<String, String> headers = const {}}) async {
    final path = url.contains('btc') || url.contains('img-0')
        ? 'lib/assets/bitcoin-logo.png'
        : url.contains('img-1')
            ? 'lib/assets/arbitrum-logo.png'
            : 'lib/assets/kute_icon.png';
    // On the disk under this test's working directory, from the real clock.
    return await const LocalFileSystem().file(path).absolute.exists()
        ? const LocalFileSystem().file(path).absolute
        : throw const HttpException('no local artwork');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _shot(WidgetTester tester, String name) async {
  for (var i = 0; i < 14; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  debugDisableShadows = false;
  for (final o in tester.allRenderObjects) {
    o.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
  debugDisableShadows = true;
}

/// Markets for Trending, images and a day's volume.
List<PolymarketEvent> _trending() => [
      for (var i = 0; i < 12; i++)
        PolymarketEvent(
          id: 't$i',
          slug: 't$i',
          title: 'Trending market $i, a question of the usual length?',
          imageUrl: 'https://polymarket-upload.example/img-$i.png',
          volume: 9e7,
          volume24hr: 3e6 - i * 1e5,
          liquidity: 1e5,
          category: 'politics',
          conditionId: 't$i',
          endDate: DateTime(2026, 12, 31),
          outcomes: [
            PolymarketOutcome(name: 'Yes', price: 0.4, tokenId: 't$i-y'),
            PolymarketOutcome(name: 'No', price: 0.6, tokenId: 't$i-n'),
          ],
        ),
    ];

InstantWorld _world({PolyInstantChoice choice = kPolyInstantDefault}) {
  const all = ['btc', 'eth', 'sol', 'xrp', 'doge', 'bnb', 'hype'];
  return InstantWorld()
    ..choice = choice
    ..feeds = {
      const PolyFeedQuery(pill: PolyPill.trending): _trending(),
      const PolyFeedQuery(pill: PolyPill.crypto, sub: '15m'):
          feedRounds(all, 15),
      const PolyFeedQuery(pill: PolyPill.crypto, sub: '1h'):
          feedRounds(all, 60),
    };
}

void main() {
  if (_out.isEmpty) {
    test('instant render', () {},
        skip: 'on demand: --dart-define=INSTANT_OUT=<dir>');
    return;
  }

  setUpAll(() async {
    Directory(_out).createSync(recursive: true);
    GoogleFonts.config.allowRuntimeFetching = false;
    PolyCrestImage.debugCacheManager = _LocalArtwork();
    final inter = FontLoader('Inter');
    for (final f in ['Regular', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
    }
    await inter.load();
    for (final w in FontWeight.values) {
      final file = w.value <= 400
          ? 'Regular'
          : w.value <= 600
              ? 'SemiBold'
              : 'Bold';
      await (FontLoader(GoogleFonts.inter(fontWeight: w).fontFamily!)
            ..addFont(rootBundle.load('lib/assets/fonts/Inter-$file.ttf')))
          .load();
    }
    await (FontLoader('packages/bootstrap_icons/BootstrapIcons')
          ..addFont(rootBundle
              .load('packages/bootstrap_icons/fonts/BootstrapIcons.ttf')))
        .load();
    final root = Platform.environment['FLUTTER_ROOT'];
    final icons = File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (root != null && icons.existsSync()) {
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
          .load();
    }
  });

  tearDown(() => RuntimeCapabilitiesService.debugInstance = null);

  const sizes = {
    '375': Size(375, 812),
    '320': Size(320, 640),
  };

  void shots(
    String name, {
    required Future<void> Function(WidgetTester, Size, bool, Locale?) run,
    bool allSizes = true,
    bool german = false,
  }) {
    for (final dark in [false, true]) {
      for (final s in sizes.entries) {
        if (!allSizes && s.key != '375') continue;
        final shot = '${name}_${s.key}_${dark ? 'dark' : 'light'}';
        testWidgets(shot, (tester) async {
          await run(tester, s.value, dark, null);
          await _shot(tester, shot);
          expect(tester.takeException(), isNull);
          await unmountInvestments(tester);
        });
      }
    }
    if (german) {
      testWidgets('${name}_375_de', (tester) async {
        await run(tester, sizes['375']!, false, const Locale('de'));
        await _shot(tester, '${name}_375_de');
        expect(tester.takeException(), isNull);
        await unmountInvestments(tester);
      });
    }
  }

  for (final pick in [PolyPill.trending, PolyPill.instant]) {
    shots('sheet_${pick.key}', german: true, run: (t, size, dark, locale) async {
      await pumpInstant(t, _world(),
          size: size,
          dark: dark,
          locale: locale,
          selection: PolyBrowseSelection(pill: pick));
      await openPredictionsSheet(t);
    });
  }

  shots('trending', run: (t, size, dark, locale) async {
    await pumpInstant(t, _world(),
        size: size,
        dark: dark,
        locale: locale,
        selection: const PolyBrowseSelection());
  });

  Future<void> Function(WidgetTester, Size, bool, Locale?) page(
          InstantWorld Function() world) =>
      (t, size, dark, locale) => pumpInstant(t, world(),
          size: size, dark: dark, locale: locale);

  shots('instant_btc_5m', german: true, run: page(_world));
  shots('instant_sol_5m',
      allSizes: false,
      run: page(() => _world(
          choice: const PolyInstantChoice(asset: 'SOL', length: '5m'))));
  shots('instant_btc_15m',
      german: true,
      run: page(() => _world(
          choice: const PolyInstantChoice(asset: 'BTC', length: '15m'))));
  shots('instant_eth_1h',
      allSizes: false,
      run: page(() => _world(
          choice: const PolyInstantChoice(asset: 'ETH', length: '1h'))));
  shots('instant_empty_4h',
      run: page(() => _world(
          choice: const PolyInstantChoice(asset: 'BTC', length: '4h'))));
  shots('instant_own_rounds',
      german: true,
      run: page(() => _world()..positions = [heldRound()]));
  shots('instant_blocked', allSizes: false,
      run: (t, size, dark, locale) => pumpInstant(t, _world(),
          size: size, dark: dark, locale: locale, browse: false));
}
