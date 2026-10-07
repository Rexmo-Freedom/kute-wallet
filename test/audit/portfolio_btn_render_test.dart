// Render harness for the venue dock (InvestmentActionBar ->
// KuteBottomActionBar): Portfolio in the solid CTA fill beside Withdraw and
// the search square, light and dark, Predictions and Investing, at 3x, plus
// a labelled contact sheet portfolio_sheet.png. Writes PNGs.
//
// Not part of the normal suite; it only runs when asked:
//
//   fvm flutter test test/audit/portfolio_btn_render_test.dart \
//     --dart-define=PORTFOLIO_BTN_OUT=/tmp/portfolio-btn

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/screens/shared/investment_action_bar.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/theme/app_theme.dart';

const _out = String.fromEnvironment('PORTFOLIO_BTN_OUT');
const _key = ValueKey('shot');
const _dpr = 3.0;
const _w = 430.0;

const _products = [
  (InvestmentsProduct.predictions, 'predictions', 'Predictions'),
  (InvestmentsProduct.trading, 'investing', 'Investing'),
];

Future<ui.Image> _shoot(
    WidgetTester tester, InvestmentsProduct product, bool dark) async {
  await tester.pumpWidget(const SizedBox());
  final c = dark ? AppColorsExtension.dark() : AppColorsExtension.light();
  await tester.pumpWidget(ProviderScope(
    overrides: [aiEnabledProvider.overrideWith((ref) async => true)],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          backgroundColor: c.background,
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: _key,
              child: Container(
                width: _w,
                color: c.background,
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: InvestmentActionBar(product: product),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  return (await tester.runAsync(() => boundary.toImage(pixelRatio: _dpr)))!;
}

Future<void> _png(WidgetTester tester, ui.Image image, String name) =>
    tester.runAsync(() async {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });

void _label(Canvas canvas, String text, Offset at, Color color,
    {double size = 34, FontWeight weight = FontWeight.w700}) {
  TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              fontFamily: 'Inter',
              fontSize: size,
              fontWeight: weight,
              color: color)),
      textDirection: TextDirection.ltr)
    ..layout()
    ..paint(canvas, at);
}

void main() {
  if (_out.isEmpty) {
    test('portfolio button render', () {},
        skip: 'on demand: --dart-define=PORTFOLIO_BTN_OUT=<dir>');
    return;
  }

  setUpAll(() async {
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
    final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'))
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

  testWidgets('venue dock with solid Portfolio, and contact sheet',
      (tester) async {
    tester.view.devicePixelRatio = _dpr;
    tester.view.physicalSize = const Size(_w * _dpr, 932 * _dpr);
    addTearDown(tester.view.reset);

    // rows: product; columns: light, dark.
    final rows = <(String, List<ui.Image>)>[];
    for (final (product, pid, pname) in _products) {
      final shots = <ui.Image>[];
      for (final dark in [false, true]) {
        final img = await _shoot(tester, product, dark);
        await _png(tester, img, '${pid}_${dark ? 'dark' : 'light'}');
        shots.add(img);
      }
      rows.add((pname, shots));
    }

    const pad = 40.0, gap = 40.0, head = 150.0, cap = 56.0;
    final light = AppColorsExtension.light();
    final sw = rows.first.$2.first.width.toDouble();
    final sh = rows.first.$2.first.height.toDouble();
    final width = pad * 2 + sw * 2 + gap;
    final height = head + rows.length * (cap + sh + pad) + pad;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, width, height), Paint()..color = Colors.white);
    _label(canvas, 'Venue dock: solid Portfolio', const Offset(pad, 24),
        light.textPrimary, size: 44);
    _label(canvas, 'Light', Offset(pad, head - 46), light.textSecondary,
        size: 30, weight: FontWeight.w600);
    _label(canvas, 'Dark', Offset(pad + sw + gap, head - 46),
        light.textSecondary,
        size: 30, weight: FontWeight.w600);
    var y = head;
    for (var r = 0; r < rows.length; r++) {
      final (caption, shots) = rows[r];
      _label(canvas, caption, Offset(pad, y + 8), light.textPrimary, size: 32);
      y += cap;
      canvas.drawImage(shots[0], Offset(pad, y), Paint());
      canvas.drawImage(shots[1], Offset(pad + sw + gap, y), Paint());
      y += sh + pad;
    }
    final sheet = (await tester.runAsync(
        () => rec.endRecording().toImage(width.ceil(), height.ceil())))!;
    await _png(tester, sheet, 'portfolio_sheet');
    await tester.pumpWidget(const SizedBox());
  });
}
