// A look by eye at the top of the homes (founder, 8 November 2026, option
// A; 12 November 2026, "occupy all available space"): the Bitcoin | Dollars
// switch filling the bar from the 16 margin up to the round +-and-gear at
// the right, written only when asked:
//   TOP_SWITCH_RENDER=<dir> flutter test test/render/top_switch_render_test.dart
// Light and dark, 320, 375, 393 and 430 wide, a long locale, 1.3x and 1.5x
// text, and the thumb in the middle of a swipe. Written or not, each case
// checks that the switch runs from the margin to the button's gap.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/screens/home/home.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';

import '../screens/home/top_switch_harness.dart';

final _dir = Platform.environment['TOP_SWITCH_RENDER'];

Future<void> _fonts(WidgetTester tester) => tester.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });

Future<void> _shoot(WidgetTester tester, String name) async {
  debugDisableShadows = false;
  for (final o in tester.allRenderObjects) {
    o.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    // The top of the screen, as far as the action row.
    final top = Offset.zero & Size(view.size.width, 280);
    final image = await layer.toImage(top, pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_dir!).createSync(recursive: true);
    File('$_dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
  debugDisableShadows = true;
  await tester.pump();
}

final _thumb = find.byKey(const ValueKey('home-tab-switch-thumb'));
final _track = find.byKey(const ValueKey('home-tab-switch-track'));

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  final cases = <(String, Size, bool, Locale?, double)>[
    ('w320_light', const Size(320, 568), false, null, 1),
    ('w320_dark', const Size(320, 568), true, null, 1),
    ('w375_light', const Size(375, 812), false, null, 1),
    ('w375_dark', const Size(375, 812), true, null, 1),
    ('w430_light', const Size(430, 932), false, null, 1),
    ('w430_dark', const Size(430, 932), true, null, 1),
    ('w320_ja_light', const Size(320, 568), false, const Locale('ja'), 1),
    ('w375_de_dark', const Size(375, 812), true, const Locale('de'), 1),
    ('w320_scale13_light', const Size(320, 568), false, null, 1.3),
    ('w375_scale13_dark', const Size(375, 812), true, null, 1.3),
    ('w430_scale13_light', const Size(430, 932), false, null, 1.3),
    ('w393_light', const Size(393, 852), false, null, 1),
    ('w393_dark', const Size(393, 852), true, null, 1),
    ('w320_scale15_light', const Size(320, 568), false, null, 1.5),
    ('w320_scale15_dark', const Size(320, 568), true, null, 1.5),
    ('w430_scale15_dark', const Size(430, 932), true, null, 1.5),
  ];
  for (final (name, size, dark, locale, scale) in cases) {
    for (final location in ['/home', '/usd']) {
      testWidgets('$name $location', (tester) async {
        debugDisableShadows = true;
        addTearDown(() => debugDisableShadows = true);
        await _fonts(tester);
        await pumpTopSwitchShell(tester,
            size: size,
            dark: dark,
            locale: locale,
            textScale: scale,
            location: location,
            home: const Home(),
            dollars: const UsdAccountScreen());
        // Past the hub glyph's first play: its rest frame.
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final track = tester.getRect(_track);
        final button = tester
            .getRect(find.byKey(const ValueKey('financial-hub-square')));
        final slot = 46.w < 44 ? 44.0 : 46.w;
        expect(track.left, moreOrLessEquals(16.w, epsilon: 0.01));
        expect(track.right,
            moreOrLessEquals(button.left - 8.w - (slot - 46.w) / 2,
                epsilon: 0.01));
        expect(tester.takeException(), isNull);
        if (_dir != null) await _shoot(tester, '${name}_${location == '/usd' ? 'dollars' : 'bitcoin'}');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 7));
      });
    }
  }

  for (final (name, dark) in [('mid_swipe_light', false), ('mid_swipe_dark', true)]) {
    testWidgets(name, (tester) async {
      debugDisableShadows = true;
      addTearDown(() => debugDisableShadows = true);
      await _fonts(tester);
      await pumpTopSwitchShell(tester,
          size: const Size(375, 812),
          dark: dark,
          home: const Home(),
          dollars: const UsdAccountScreen());
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // Held 40% of the way to Dollars (the first step wins the arena).
      final finger = await tester.startGesture(const Offset(300, 170));
      await finger.moveBy(const Offset(-40, 0));
      await tester.pump();
      await finger.moveBy(const Offset(-150, 0));
      await tester.pump();
      expect(tester.getTopLeft(_thumb).dx,
          greaterThan(tester.getTopLeft(_track).dx + 30));
      if (_dir != null) await _shoot(tester, name);
      await finger.up();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 7));
    });
  }
}
