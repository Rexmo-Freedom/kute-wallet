// The share cards as images, for a look by eye, at 1080 × 1350 with the
// real Sal stills: bitcoin and dollars sends, a prediction pick, a
// prediction market, a stock pick (Tesla), a stock market (Nasdaq 100),
// oil, and the claim hero. Every frame lays out without an overflow; the
// PNGs are written only when asked:
//
//   SHARE_CARD_FRAMES=<dir> flutter test test/screens/share/cards/share_card_render_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart';
import 'package:kute/screens/share/cards/share_cards.dart';
import 'package:kute/theme/app_theme.dart';

import 'share_card_test_fonts.dart';
import 'share_card_fixtures.dart';

void main() {
  final dir = Platform.environment['SHARE_CARD_FRAMES'];

  testWidgets('share cards render to PNG', (tester) async {
    await tester.runAsync(loadShareCardFonts);
    ShareCardSal.debugReset();
    addTearDown(ShareCardSal.debugReset);
    await tester.runAsync(ShareCardSal.loadAll);
    tester.view.physicalSize = const Size(1080, 1350);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final frames = <String, (ShareCardData, int, Locale)>{
      '1_send_bitcoin': (fakeBitcoinCard(), 0, const Locale('en')),
      '1_send_dollars': (fakeDollarsCard(), 2, const Locale('en')),
      '2_send_prediction': (fakePredictionPick(), 0, const Locale('en')),
      '3_send_stock_tesla': (fakeTeslaPick(), 0, const Locale('en')),
      '3_market_nasdaq100': (fakeNasdaqMarket(), 1, const Locale('en')),
      '3_market_crude_oil': (fakeOilMarket(), 2, const Locale('en')),
      '4_market_prediction': (fakePredictionMarket(), 0, const Locale('en')),
      'de_send_stock_tesla': (fakeTeslaPick(), 2, const Locale('de')),
      'ja_send_prediction': (fakePredictionPick(), 1, const Locale('ja')),
    };
    for (final MapEntry(key: name, value: (data, seed, locale))
        in frames.entries) {
      final key = GlobalKey();
      await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: locale,
                theme: ThemeData(
                    fontFamily: 'Inter',
                    extensions: [AppColorsExtension.light()]),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Align(
                  alignment: Alignment.topLeft,
                  child: RepaintBoundary(
                    key: key,
                    child: ShareCard(
                      data: data,
                      sal: ShareCardSal.peek(shareCardSalAsset(data)),
                      lineSeed: seed,
                    ),
                  ),
                ),
              )));
      await tester.pump();
      final error = tester.takeException();
      expect(error, isNull, reason: '$name overflowed: $error');
      if (dir == null) continue;
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: kShareCardPixelRatio);
        expect(image.width, 1080);
        expect(image.height, 1350);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(dir).createSync(recursive: true);
        File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
  });
}
