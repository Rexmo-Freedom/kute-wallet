// A look by eye at the bar's adaptive button and the surfaces this round
// touched, written only when asked: R4_BAR_RENDER=<dir> flutter test
// test/render/kute_bar_states_render_test.dart. The real Inter face and
// the real Sal sheets; 390 wide at 3x.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';

final _dir = Platform.environment['R4_BAR_RENDER'];

Future<void> _assets(WidgetTester tester) async {
  await tester.runAsync(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'))
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-SemiBold.ttf'))
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Bold.ttf'));
    await inter.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final manifest = jsonDecode(
            await rootBundle.loadString('$kSalSpriteDir/manifest.json'))
        as Map<String, dynamic>;
    SalSpriteCache.debugSetManifest(manifest);
    for (final clip in ['idle', 'curious', 'think', 'search', 'happy', 'share']) {
      await SalSpriteCache.clip(clip, 3);
    }
  });
}

ThemeData _theme(bool dark) {
  final base = dark ? buildDarkTheme() : buildLightTheme();
  return base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Inter'));
}

Future<void> _shot(WidgetTester tester, String name, List<Widget> rows,
    {bool dark = false, double height = 160, Duration settle = const Duration(milliseconds: 900)}) async {
  tester.view.physicalSize = Size(390 * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RepaintBoundary(
        key: key,
        child: Builder(
          builder: (context) => ColoredBox(
            color: context.colors.background,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: rows,
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(settle);
  Directory(_dir!).createSync(recursive: true);
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Widget _button(KuteBarContext ctx) =>
    Center(child: KuteBarPrimaryButton(barContext: ctx, onAsk: () {}));

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('render: the three states, $mode', skip: _dir == null,
        (tester) async {
      await _assets(tester);
      await _shot(
          tester,
          'bar-states-$mode',
          [
            _button(KuteBarContext.primary(
                label: 'Create request',
                disabledLabel: 'Enter an amount',
                enabled: false,
                onPrimary: () {})),
            _button(KuteBarContext.primary(
                label: 'Create request', onPrimary: () {})),
          ],
          dark: dark,
          height: 180);
    });

    testWidgets('render: busy mid-shimmer, $mode', skip: _dir == null,
        (tester) async {
      await _assets(tester);
      await _shot(
          tester,
          'bar-busy-$mode',
          [
            _button(KuteBarContext.primary(
                label: 'Send',
                busy: true,
                busyLabel: 'Sending…',
                onPrimary: () {})),
          ],
          dark: dark,
          height: 100,
          // Half way through the shimmer's 1.2 s sweep.
          settle: const Duration(milliseconds: 1200 * 3 + 600));
    });
  }

  testWidgets('render: a narrow "Create request" beside a long label',
      skip: _dir == null, (tester) async {
    await _assets(tester);
    await _shot(
        tester,
        'bar-width-adapts',
        [
          _button(KuteBarContext.primary(
              label: 'Create request', onPrimary: () {})),
          _button(KuteBarContext.primary(
              label: r'Place prediction · $1,250.00', onPrimary: () {})),
          _button(KuteBarContext.primary(label: 'OK', onPrimary: () {})),
        ],
        height: 260);
  });

  testWidgets('render: the Recover pair and a slip style', skip: _dir == null,
      (tester) async {
    await _assets(tester);
    await _shot(
        tester,
        'bar-pair-and-slip',
        [
          Builder(builder: (context) {
            final w = KuteBarSecondaryPill.widthFor(
                context, 'Use your Apple account');
            final p =
                KuteBarPrimaryButton.widthFor(context, 'Use your recovery phrase');
            final width = w > p ? w : p;
            return Column(children: [
              KuteBarSecondaryPill(
                  label: 'Use your Apple account',
                  leading: Icons.apple,
                  width: width,
                  onTap: () {}),
              const SizedBox(height: 12),
              KuteBarPrimaryButton(
                  barContext: KuteBarContext.primary(
                      label: 'Use your recovery phrase',
                      onPrimary: () {},
                      pairedWidth: width),
                  onAsk: () {}),
            ]);
          }),
          ColoredBox(
            color: const Color(0xFF1FA663),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _button(KuteBarContext.primary(
                label: r'Place $10.00 on Yes',
                onPrimary: () {},
                style: KuteBarPrimaryStyle(
                  fill: Colors.white,
                  foreground: const Color(0xFF1FA663),
                  radius: KuteBarPrimaryButton.radius,
                  fontWeight: FontWeight.w800,
                ),
              )),
            ),
          ),
        ],
        height: 300);
  });
}
