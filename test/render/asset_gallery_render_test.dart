// The asset gallery (tool/asset_gallery) rendered in the Dart VM, one PNG
// per section in light and dark, to compare with the same page served as
// a web build (`flutter build web -t tool/asset_gallery/main.dart`). Every
// SVG, raster, Sal clip, rig scene, icon font and glass surface is read
// from the real bundle. Nothing reads the network.
//
// Not part of the normal suite; it only runs when asked:
//
//   flutter test test/render/asset_gallery_render_test.dart \
//     --dart-define=ASSET_GALLERY_RENDER=true \
//     --dart-define=ASSET_GALLERY_RENDER_OUT=/tmp/kute_asset_gallery

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';

import '../../tool/asset_gallery/asset_gallery.dart';

const _enabled = bool.fromEnvironment('ASSET_GALLERY_RENDER');
const _outDefine = String.fromEnvironment('ASSET_GALLERY_RENDER_OUT');

final String _out = _outDefine.isNotEmpty
    ? _outDefine
    : '${Directory.systemTemp.path}/kute_asset_gallery';

const _shotKey = ValueKey('asset-gallery-shot');

late List<String> _svgs;
late List<String> _rasters;
late List<String> _clips;

Future<void> _load(WidgetTester tester) => tester.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
      await (FontLoader('packages/bootstrap_icons/BootstrapIcons')
            ..addFont(rootBundle
                .load('packages/bootstrap_icons/fonts/BootstrapIcons.ttf')))
          .load();
      final manifest = jsonDecode(
              await rootBundle.loadString('$kSalSpriteDir/manifest.json'))
          as Map<String, dynamic>;
      SalSpriteCache.debugSetManifest(manifest);
      _svgs = await galleryAssets(const ['.svg']);
      _rasters = await galleryAssets(const ['.png', '.gif', '.webp', '.jpg'],
          skip: const ['lib/assets/sal/']);
      _clips = await gallerySalClips();
    });

Future<void> _pump(WidgetTester tester,
    {required bool dark, required String section}) async {
  tester.view.physicalSize = const Size(1440 * 2, 1300 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final base = dark ? buildDarkTheme() : buildLightTheme();
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme:
          base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Inter')),
      home: RepaintBoundary(
        key: _shotKey,
        child: Material(
          child: AssetGallery(
            sections: {section},
            svgs: _svgs,
            rasters: _rasters,
            clips: _clips,
          ),
        ),
      ),
    ),
  ));
  // Asset reads and decodes land on real time; the sprites tick on fake.
  for (var i = 0; i < 30; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_out).createSync(recursive: true);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
  // ignore: avoid_print
  print('RENDER wrote $_out/$name.png');
}

void main() {
  if (!_enabled) {
    test('asset gallery render', () {},
        skip: 'on demand: --dart-define=ASSET_GALLERY_RENDER=true');
    return;
  }

  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(SalSpriteCache.debugReset);

  for (final dark in [false, true]) {
    for (final section in const [
      AssetGallery.wallets,
      AssetGallery.svg,
      AssetGallery.raster,
      AssetGallery.sal,
      AssetGallery.rig,
      AssetGallery.fonts,
      AssetGallery.surfaces,
    ]) {
      final name = '${section}_${dark ? 'dark' : 'light'}';
      testWidgets('asset gallery $name', (tester) async {
        await _load(tester);
        await _pump(tester, dark: dark, section: section);
        await _shot(tester, name);
        // Let go of every looping ticker before the test ends.
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
