// Three-way football render harness: the market sheet of a real Gamma
// game (test/fixtures/polymarket_games/) and the slip its WINNER board
// opens, in light, written as PNGs. Nothing reads the network.
//
// Not part of the normal suite; it only runs when asked:
//
//   fvm flutter test test/audit/game_three_way_render_test.dart \
//     --dart-define=GAME_FIXES_RENDER=true \
//     --dart-define=GAME_FIXES_RENDER_OUT=/tmp/kute_game_fixes
//
// The shots: Sunderland vs Brighton's sheet (team header, WINNER of
// three, chart tags by short name), its slip opened from Draw (three
// sides, Draw picked), and Leeds vs Man United's slip opened from
// Man Utd.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/shared/charts/kute_chart_zoom_hint.dart';
import 'package:kute/theme/app_theme.dart';

import '../screens/polymarket/game_three_way_test.dart'
    show gameFixture, gameOverrides;

const _enabled = bool.fromEnvironment('GAME_FIXES_RENDER');
const _outDefine = String.fromEnvironment('GAME_FIXES_RENDER_OUT');

final String _out = _outDefine.isNotEmpty
    ? _outDefine
    : '${Directory.systemTemp.path}/kute_game_fixes';

const _phone = Size(393, 852);
const _shotKey = ValueKey('game-fixes-render-shot');

final int _nowMs = DateTime.now().millisecondsSinceEpoch;
const _hour = 3600000;

/// A week of a line drifting from [from] to [to].
List<PolymarketPricePoint> _line(double from, double to, int seed) => [
      for (var i = 0; i <= 168; i++)
        PolymarketPricePoint(
          timestamp:
              DateTime.fromMillisecondsSinceEpoch(_nowMs - (168 - i) * _hour),
          price: (from +
                  (to - from) * i / 168 +
                  (i == 168 ? 0 : 0.02 * math.sin(i / (5 + seed))))
              .clamp(0.002, 0.998),
        ),
    ];

Future<void> _show(
    WidgetTester tester, PolymarketEvent event, Size size) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final history = {
    for (final (i, o) in event.outcomes.indexed)
      if (o.tokenId != null) o.tokenId!: _line(o.price - 0.06, o.price, i),
  };
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      ...gameOverrides(),
      polymarketMarketHistoryProvider
          .overrideWith((ref, arg) async => history[arg.tokenId] ?? const []),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // The boundary holds the navigator, so a slip opened over the
        // sheet is in the shot.
        builder: (context, child) =>
            RepaintBoundary(key: _shotKey, child: child),
        home: MarketDetailSheet(event: event),
      ),
    ),
  ));
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _settle(WidgetTester tester) async {
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

Future<void> _tapBoard(WidgetTester tester, String label) async {
  final button = find.text(label).hitTestable();
  await tester.tap(button.last);
  await _settle(tester);
}

void main() {
  if (!_enabled) {
    test('game three-way render', () {},
        skip: 'on demand: --dart-define=GAME_FIXES_RENDER=true');
    return;
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
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

  setUp(() {
    var seen = true;
    KuteZoomHint.debugReset(read: () => seen, write: () => seen = true);
  });
  tearDown(KuteZoomHint.debugReset);

  Future<void> offline(Future<void> Function() body) => http.runWithClient(
      body, () => MockClient((_) async => http.Response('{}', 404)));

  testWidgets('sunderland_brighton_sheet', (tester) async {
    await offline(() async {
      await _show(
          tester, gameFixture('sunderland_brighton'), const Size(393, 1300));
      await _shot(tester, 'sunderland_brighton_sheet_light');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });
  });

  testWidgets('sunderland_brighton_slip_draw', (tester) async {
    await offline(() async {
      await _show(tester, gameFixture('sunderland_brighton'), _phone);
      await tester.scrollUntilVisible(find.text('WINNER'), 200,
          scrollable: find.byType(Scrollable).first);
      await _settle(tester);
      await _tapBoard(tester, 'Draw');
      await _shot(tester, 'sunderland_brighton_slip_draw_light');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });
  });

  testWidgets('leeds_man_united_slip', (tester) async {
    await offline(() async {
      await _show(tester, gameFixture('leeds_man_united'), _phone);
      await tester.scrollUntilVisible(find.text('WINNER'), 200,
          scrollable: find.byType(Scrollable).first);
      await _settle(tester);
      await _tapBoard(tester, 'Man Utd');
      await _shot(tester, 'leeds_man_united_slip_light');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
