// The brag cards as images, for a look by eye: the position card (a
// winning prediction and a losing Investing position) and the portfolio
// card, amounts off and on, at 1080 × 1350 with the real Sal sheets.
// Written only when asked:
//
//   BRAG_FRAMES=<dir> flutter test test/screens/share/brag/brag_render_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/share/brag/brag_card.dart';
import 'package:kute/screens/share/brag/brag_data.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';

import 'brag_fixtures.dart';
import 'brag_test_fonts.dart';

void main() {
  final dir = Platform.environment['BRAG_FRAMES'];

  testWidgets('brag cards render to PNG', (tester) async {
    await tester.runAsync(loadBragFonts);
    SalSpriteCache.debugReset();
    addTearDown(() => SalSpriteCache.debugSetManifest(null));
    final wink =
        await tester.runAsync(() => SalSpriteCache.clip(kBragWinkClip, 3));
    final shake =
        await tester.runAsync(() => SalSpriteCache.clip(kBragShakeNoClip, 3));
    tester.view.physicalSize = const Size(1080, 1350);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final frames = <String, BragData>{
      'position_win': fakeBragPosition(),
      'position_loss': fakeBragLosingPosition(),
      'portfolio': fakeBragPortfolio(),
    };
    for (final MapEntry(key: name, value: data) in frames.entries) {
      for (final amounts in [false, true]) {
        final key = GlobalKey();
        await tester.pumpWidget(ScreenUtilInit(
            designSize: const Size(430, 932),
            builder: (_, __) => MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: ThemeData(
                      fontFamily: 'Inter',
                      extensions: [AppColorsExtension.light()]),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: Align(
                    alignment: Alignment.topLeft,
                    child: RepaintBoundary(
                      key: key,
                      child: BragCard(
                        data: data,
                        showAmounts: amounts,
                        sal: data.up ? wink : shake,
                      ),
                    ),
                  ),
                )));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$name overflowed');
        if (dir == null) continue;
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: kBragCardPixelRatio);
          expect(image.width, 1080);
          expect(image.height, 1350);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory(dir).createSync(recursive: true);
          File('$dir/brag_${name}_${amounts ? 'amounts_on' : 'amounts_off'}.png')
              .writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
    }
  });
}
