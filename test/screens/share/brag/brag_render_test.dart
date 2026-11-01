// The brag cards as images, for a look by eye: a big win, a small win, a
// loss, flat, and the positions (a winning prediction, a losing Investing
// position), at 1080 × 1350 with Sal's real face in the footer mark. Every frame lays out without an overflow; the PNGs are
// written only when asked:
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
import 'package:kute/screens/share/cards/share_card_frame.dart'
    show ShareCardSal;
import 'package:kute/theme/app_theme.dart';

import 'brag_fixtures.dart';
import '../cards/share_card_test_fonts.dart' show loadShareCardSal;
import 'brag_test_fonts.dart';

void main() {
  final dir = Platform.environment['BRAG_FRAMES'];

  testWidgets('brag cards render to PNG', (tester) async {
    await tester.runAsync(loadBragFonts);
    ShareCardSal.debugReset();
    addTearDown(ShareCardSal.debugReset);
    await tester.runAsync(loadShareCardSal);
    expect(ShareCardSal.peek(), isNotNull, reason: "Sal's face decodes");
    tester.view.physicalSize = const Size(1080, 1350);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final frames = <String, BragData>{
      'big_win': fakeBragPortfolio(),
      'small_win': fakeBragSmallWinPortfolio(),
      'loss': fakeBragLosingPortfolio(),
      'flat': fakeBragFlatPortfolio(),
      'position_win': fakeBragPosition(),
      'position_loss': fakeBragLosingPosition(),
    };
    for (final MapEntry(key: name, value: data) in frames.entries) {
      final key = GlobalKey();
      await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                    fontFamily: 'Inter',
                    extensions: [AppColorsExtension.light()]),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Align(
                  alignment: Alignment.topLeft,
                  child: RepaintBoundary(
                    key: key,
                    child: BragCard(data: data, mark: ShareCardSal.peek()),
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
        File('$dir/brag_$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
  });
}
