// The bar's idle labels fit ONE line on a 375 pt phone in every shipped
// language (founder, 2 November 2026: "search predictions and manage with
// AI"): "Search predictions or manage with AI" with Predictions picked,
// "Search investments or manage with AI" with Investing, "Search or
// manage with AI" everywhere else. Each is drawn in the floating pill at
// the shell bar's own gutters, in Inter, and its line must not be cut.
// The English pills are written as a PNG when asked:
//
//   BAR_LABEL_FRAMES=<dir> flutter test test/screens/home/kute_sal_pill_label_fit_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart'
    show KuteSalPill;
import 'package:kute/screens/shared/sal_sprite.dart'
    show SalSpriteCache, kSalSpriteDir;
import 'package:kute/theme/app_theme.dart';

Future<void> _loadInter() async {
  final inter = FontLoader('Inter');
  for (final f in ['Regular', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
  }
  await inter.load();
}

void main() {
  final dir = Platform.environment['BAR_LABEL_FRAMES'];

  testWidgets('the bar labels fit one line at 375 pt in every language',
      (tester) async {
    await tester.runAsync(_loadInter);
    // Sal's real 3D face in the pill (the bundle's manifest, read
    // directly; the test config nulls it), decoded before the pump.
    await tester.runAsync(() async {
      SalSpriteCache.debugSetManifest(jsonDecode(
              await rootBundle.loadString('$kSalSpriteDir/manifest.json'))
          as Map<String, dynamic>);
      await SalSpriteCache.clip('search', 3);
    });
    addTearDown(() => SalSpriteCache.debugSetManifest(null));
    tester.view.physicalSize = const Size(375, 812) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final boundary = GlobalKey();
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = l10nForLanguage(locale.languageCode);
      final labels = [
        l10n.searchPredictionsOrManageAi,
        l10n.searchInvestmentsOrManageAi,
        l10n.searchOrManageAi,
      ];
      await tester.pumpWidget(ProviderScope(
        overrides: [aiEnabledProvider.overrideWith((_) async => true)],
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: 'Inter',
              splashFactory: NoSplash.splashFactory,
              extensions: [AppColorsExtension.light()],
            ),
            home: Scaffold(
              backgroundColor: const Color(0xFFF4F4F6),
              body: Center(
                child: RepaintBoundary(
                  key: boundary,
                  child: ColoredBox(
                    color: const Color(0xFFF4F4F6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final label in labels)
                          Padding(
                            // The shell bar's gutters around the pill.
                            padding: EdgeInsets.fromLTRB(12.w, 8, 12.w, 8),
                            child: Center(
                              child: KuteSalPill(
                                  label: label,
                                  onTap: () {}),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(seconds: 1));
      for (final label in labels) {
        final p = tester.renderObject<RenderParagraph>(find.text(label));
        final needed = p.getMaxIntrinsicWidth(double.infinity);
        expect(needed, lessThanOrEqualTo(p.size.width + 0.5),
            reason: '${locale.languageCode}: "$label" is cut '
                '(${needed.toStringAsFixed(1)} > '
                '${p.size.width.toStringAsFixed(1)})');
      }
      if (dir != null && locale.languageCode == 'en') {
        final ro = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await ro.toImage(pixelRatio: 3);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory(dir).createSync(recursive: true);
          File('$dir/bar_labels_en.png')
              .writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
    }
  });
}
