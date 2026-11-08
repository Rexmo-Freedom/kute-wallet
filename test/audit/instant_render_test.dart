// Render harness for Predictions › Instant (founder, 8 November 2026): the
// sheet with its Instant card, the Instant screen at each length, the strip
// with Now and with Next picked, a round without prices, a held round's
// marker and row, the blocked screen; light and dark, 320 and 375 wide, a
// long locale. Writes PNGs.
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
import 'package:kute/screens/polymarket/components/instant_round_strip.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/services/polymarket/instant_rounds.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';
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

/// A clock a minute into a five-minute round, so the strip reads "Now ·
/// 04:00"; [late] two and a half minutes in, past the roll's moment.
DateTime _clock({bool late = false}) {
  final now = DateTime.now().toUtc();
  final start = DateTime.fromMillisecondsSinceEpoch(
      (now.millisecondsSinceEpoch ~/ 300000) * 300000,
      isUtc: true);
  return start.add(Duration(seconds: late ? 150 : 60));
}

void _quote(String token, double bid, double ask) =>
    PolymarketLiveBooks.instance.debugSeed(PolymarketBookMessage(
      assetId: token,
      market: 'm',
      timestamp: 0,
      hash: '',
      bids: [PolymarketOrderSummary(price: bid, size: 500)],
      asks: [PolymarketOrderSummary(price: ask, size: 500)],
    ));

/// A world with the next round listed and quoted ([priced]), and one after
/// listed but without prices.
InstantWorld _world(
    {PolyInstantChoice choice = kPolyInstantDefault,
    bool late = false,
    bool priced = true}) {
  const all = ['btc', 'eth', 'sol', 'xrp', 'doge', 'bnb', 'hype'];
  final world = InstantWorld()
    ..now = _clock(late: late)
    ..choice = choice
    ..feeds = {
      const PolyFeedQuery(pill: PolyPill.trending): _trending(),
      const PolyFeedQuery(pill: PolyPill.crypto, sub: '15m'):
          feedRounds(all, 15),
      const PolyFeedQuery(pill: PolyPill.crypto, sub: '1h'):
          feedRounds(all, 60),
      const PolyFeedQuery(pill: PolyPill.crypto, sub: '4h'):
          feedRounds(all, 240),
    };
  final minutes = choice.minutes;
  final live = world.liveStart(minutes);
  world.ahead[live + minutes * 60] =
      roundEvent(choice.asset, minutes, live + minutes * 60, tokens: 'next');
  world.ahead[live + 2 * minutes * 60] = roundEvent(
      choice.asset, minutes, live + 2 * minutes * 60,
      tokens: 'later');
  PolymarketLiveBooks.instance
    ..reset()
    ..clock = () => world.now;
  if (priced) {
    _quote('next-up', 0.50, 0.51);
    _quote('next-down', 0.49, 0.50);
  }
  return world;
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

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    PolymarketLiveBooks.instance.reset();
  });

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

  shots('sheet', german: true, run: (t, size, dark, locale) async {
    await pumpPredictionsSheet(t, _world(),
        size: size, dark: dark, locale: locale);
  });

  Future<void> Function(WidgetTester, Size, bool, Locale?) screen(
          InstantWorld Function() world) =>
      (t, size, dark, locale) =>
          pumpInstant(t, world(), size: size, dark: dark, locale: locale);

  shots('instant_btc_5m', german: true, run: screen(_world));
  shots('instant_sol_5m',
      allSizes: false,
      run: screen(() => _world(
          choice: const PolyInstantChoice(asset: 'SOL', length: '5m'))));
  shots('instant_btc_15m',
      german: true,
      run: screen(() => _world(
          choice: const PolyInstantChoice(asset: 'BTC', length: '15m'))));
  shots('instant_eth_1h',
      run: screen(() => _world(
          choice: const PolyInstantChoice(asset: 'ETH', length: '1h'))));
  shots('instant_bnb_4h',
      run: screen(() => _world(
          choice: const PolyInstantChoice(asset: 'BNB', length: '4h'))));
  // Past the roll's moment with the next round priced: Next picked by the
  // roll, the line over the buttons names it.
  shots('instant_next_selected', german: true,
      run: screen(() => _world(late: true)));
  // The person taps Next early: picked by hand.
  shots('instant_next_tapped', allSizes: false,
      run: (t, size, dark, locale) async {
    final world = _world();
    await pumpInstant(t, world, size: size, dark: dark, locale: locale);
    await t.tap(find.byKey(InstantRoundStrip.pillKey(world.liveStart(5) + 300)));
    await t.pump(const Duration(milliseconds: 300));
  });
  // Nothing ahead has prices: "No prices yet" on both.
  shots('instant_no_prices', run: screen(() => _world(priced: false)));
  shots('instant_own_round',
      german: true,
      run: screen(() => _world()..positions = [heldRound(now: _clock())]));
  shots('instant_blocked', allSizes: false,
      run: (t, size, dark, locale) => pumpInstantScreen(t, _world(),
          size: size, dark: dark, locale: locale, browse: false));
}
