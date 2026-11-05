// "More markets" render harness: the sheets of real Gamma games
// (test/fixtures/polymarket_games/) with their period chips, lines and
// folded groups, light and dark, written as PNGs. Nothing reads the
// network.
//
// Not part of the normal suite; it only runs when asked:
//
//   fvm flutter test test/audit/game_more_markets_render_test.dart \
//     --dart-define=GAME_LINES_RENDER=true \
//     --dart-define=GAME_LINES_RENDER_OUT=/tmp/kute_game_lines
//
// The shots: a LoL best-of-five (All, Game 1), a Dota 2 best-of-three
// (All, Game 2), a CS2 best-of-three's Map 1 with its settled lines open,
// and a football match's More Markets (All, 1st half).

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart'
    show BaseCacheManager;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/shared/charts/kute_chart_zoom_hint.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/theme/app_theme.dart';

import '../screens/polymarket/game_more_markets_test.dart'
    show moreMarketsFixture, moreMarketsOverrides;

const _enabled = bool.fromEnvironment('GAME_LINES_RENDER');
const _outDefine = String.fromEnvironment('GAME_LINES_RENDER_OUT');

final String _out = _outDefine.isNotEmpty
    ? _outDefine
    : '${Directory.systemTemp.path}/kute_game_lines';

const _shotKey = ValueKey('game-lines-render-shot');

/// No crests in a test (their cache wants a database): the fallback.
class _NoArtwork implements BaseCacheManager {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      invocation.memberName == #getFileStream
          ? Stream<Never>.error(const HttpException('no artwork in a render'))
          : Future<Never>.error(const HttpException('no artwork in a render'));
}

Future<void> _show(WidgetTester tester, PolymarketEvent event,
    {required bool dark, double height = 2600}) async {
  final size = Size(393, height);
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      ...moreMarketsOverrides(event),
      polymarketMarketHistoryProvider
          .overrideWith((ref, arg) async => const []),
    ],
    child: ScreenUtilInit(
      // The phone's proportions at this height, so .h scales as .w does.
      designSize: Size(430, 430 * height / 393),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            RepaintBoundary(key: _shotKey, child: child),
        home: MarketDetailSheet(event: event),
      ),
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
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
}

/// Scrolls the sheet so "More markets" is at the top.
Future<void> _toMore(WidgetTester tester) async {
  final title = find.text('More markets');
  await tester.scrollUntilVisible(title, 300,
      scrollable: find.byType(Scrollable).first);
  await tester.pump();
  final box = tester.getTopLeft(title);
  final position =
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;
  position.jumpTo((position.pixels + box.dy - 90)
      .clamp(position.minScrollExtent, position.maxScrollExtent));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _chip(WidgetTester tester, String label) async {
  final chip = find.descendant(
      of: find.byKey(const ValueKey('game-period-chips')),
      matching: find.widgetWithText(KutePill, label));
  await tester.ensureVisible(chip);
  await tester.pump();
  await tester.tap(chip);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  if (!_enabled) {
    test('game more markets render', () {},
        skip: 'on demand: --dart-define=GAME_LINES_RENDER=true');
    return;
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    PolyCrestImage.debugCacheManager = _NoArtwork();
    Directory(_out).createSync(recursive: true);
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in [
      GoogleFonts.inter().fontFamily!,
      'Inter',
      'FlutterTest'
    ]) {
      final inter = FontLoader(family);
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => '$_out/cache');
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  tearDownAll(() => PolyCrestImage.debugCacheManager = null);

  setUp(() {
    var seen = true;
    KuteZoomHint.debugReset(read: () => seen, write: () => seen = true);
  });
  tearDown(KuteZoomHint.debugReset);

  Future<void> offline(Future<void> Function() body) => http.runWithClient(
      body, () => MockClient((_) async => http.Response('{}', 404)));

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('lol_bo5 $mode', (tester) async {
      await offline(() async {
        await _show(tester, moreMarketsFixture('lol_dk_blg_bo5'), dark: dark);
        await _shot(tester, 'lol_bo5_page_$mode');
        await _toMore(tester);
        await _shot(tester, 'lol_bo5_all_$mode');
        await _chip(tester, 'Game 1');
        await _shot(tester, 'lol_bo5_game1_$mode');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      });
    });

    testWidgets('dota_bo3 $mode', (tester) async {
      await offline(() async {
        await _show(tester, moreMarketsFixture('dota_yes_gl_bo3'), dark: dark);
        await _toMore(tester);
        await _shot(tester, 'dota_bo3_all_$mode');
        await _chip(tester, 'Game 2');
        await tester.tap(find.textContaining('Not trading yet'));
        await tester.pump(const Duration(milliseconds: 300));
        await _shot(tester, 'dota_bo3_game2_open_$mode');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      });
    });

    testWidgets('cs2_bo3 $mode', (tester) async {
      await offline(() async {
        await _show(tester, moreMarketsFixture('cs2_inox_honved_bo3'),
            dark: dark, height: 1800);
        await _toMore(tester);
        await _chip(tester, 'Map 1');
        await tester.tap(find.textContaining('Settled'));
        await tester.pump(const Duration(milliseconds: 300));
        await _shot(tester, 'cs2_bo3_map1_settled_$mode');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      });
    });

    testWidgets('football_more_markets $mode', (tester) async {
      await offline(() async {
        await _show(tester, moreMarketsFixture('arsenal_hull_more_markets'),
            dark: dark);
        await _toMore(tester);
        await _shot(tester, 'football_all_$mode');
        await _chip(tester, '1st half');
        await _shot(tester, 'football_half1_$mode');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      });
    });

    testWidgets('tennis $mode', (tester) async {
      await offline(() async {
        await _show(tester, moreMarketsFixture('tennis_fils_fritz'),
            dark: dark, height: 1800);
        await _toMore(tester);
        await _shot(tester, 'tennis_all_$mode');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      });
    });
  }
}
