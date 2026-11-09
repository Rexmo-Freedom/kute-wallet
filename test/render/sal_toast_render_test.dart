// A look by eye at the Sal toast (sal_toast.dart), written only when
// asked: SAL_TOAST_RENDER=<dir> flutter test test/render/sal_toast_render_test.dart.
// The real Inter face and the real Sal sheets; 390 wide at 3x, under a
// 47 pt status bar as on an iPhone. A success, a failure and information,
// each in light and dark.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/screens/shared/sal_toast.dart';
import 'package:kute/theme/app_theme.dart';

final _dir = Platform.environment['SAL_TOAST_RENDER'];

Future<void> _assets(WidgetTester tester) async {
  await tester.runAsync(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'))
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-SemiBold.ttf'))
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Bold.ttf'));
    await inter.load();
    final manifest = jsonDecode(
            await rootBundle.loadString('$kSalSpriteDir/manifest.json'))
        as Map<String, dynamic>;
    SalSpriteCache.debugSetManifest(manifest);
    for (final clip in ['happy', 'sad', 'blink']) {
      await SalSpriteCache.clip(clip, 3);
    }
  });
}

ThemeData _theme(bool dark) {
  final base = dark ? buildDarkTheme() : buildLightTheme();
  return base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Inter'));
}

Future<void> _shot(
  WidgetTester tester,
  String name, {
  required bool dark,
  required String message,
  String? detail,
  required SalToastTone tone,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 150 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  // The real soft shadows for the look (the test binding paints them hard
  // unless told otherwise), back to the binding's default after the shot.
  debugDisableShadows = false;
  try {
    final key = GlobalKey();
    late BuildContext page;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // The toast lives on the root overlay: the boundary wraps the
        // navigator, with the status bar's inset as on a phone.
        builder: (context, child) => RepaintBoundary(
          key: key,
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(padding: const EdgeInsets.only(top: 47)),
            child: child!,
          ),
        ),
        home: Builder(builder: (context) {
          page = context;
          return ColoredBox(
            color: context.colors.background,
            child: const SizedBox.expand(),
          );
        }),
      ),
    ));
    await tester.pump();
    SalToast.show(page,
        message: message, detail: detail, tone: tone, haptic: false);
    await tester.pump();
    // The arrival and the mark's stroke through, Sal a few frames in.
    await tester.pump(const Duration(milliseconds: 1300));
    Directory(_dir!).createSync(recursive: true);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    SalToast.debugReset();
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  } finally {
    debugDisableShadows = true;
  }
}

void main() {
  if (_dir == null) {
    test('SAL_TOAST_RENDER not set: nothing to draw', () {});
    return;
  }

  setUpAll(() => SalToast.debugFailureFeedbackOverride = () async {});
  tearDownAll(() {
    SalToast.debugFailureFeedbackOverride = null;
    SalSpriteCache.debugReset();
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('success $mode', (tester) async {
      await _assets(tester);
      await _shot(tester, 'sal-toast-success-$mode',
          dark: dark,
          message: 'Prediction placed',
          detail: r'$5.00 on Yes · Will it rain in Lisbon on Friday?',
          tone: SalToastTone.success);
    });
    testWidgets('failure $mode', (tester) async {
      await _assets(tester);
      await _shot(tester, 'sal-toast-failure-$mode',
          dark: dark,
          message: "Couldn't place the prediction",
          detail: 'Your money is still in Dollars',
          tone: SalToastTone.failure);
    });
    testWidgets('info $mode', (tester) async {
      await _assets(tester);
      await _shot(tester, 'sal-toast-info-$mode',
          dark: dark, message: 'Address copied', tone: SalToastTone.info);
    });
  }
}
