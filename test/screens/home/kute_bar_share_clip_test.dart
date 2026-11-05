// The round share button's Sal (kute_bar_trade_row.dart, THE SHARE CLIP;
// founder, 5 November 2026: "Kute symbol here should be with the share"):
// the `face_share` clip, Sal presenting the share glyph, is in the
// bundle's manifest as a 48-frame face loop at 24 fps, both sheets decode
// to the manifest's grid, its first cell carries the glyph's ink at the
// right, and the round button (the trade row's, the one beside Close or
// Sell) wears it, looping; under Reduce Motion it holds frame 0. The
// spoken labels stay "Send to a friend" / "Brag about it".

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/home/components/kute_bar_trade_row.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';

const _market = KuteBarContext(
  label: 'Send to a friend',
  sublabel: 'Send the market',
  clip: 'share',
);

Future<Map<String, dynamic>> _manifest(WidgetTester tester) async =>
    (await tester.runAsync(() async =>
        jsonDecode(await rootBundle.loadString('$kSalSpriteDir/manifest.json'))
            as Map<String, dynamic>))!;

/// The bundle's manifest installed and `face_share` decoded at [density].
Future<SalClip> _load(WidgetTester tester, int density) async {
  SalSpriteCache.debugSetManifest(await _manifest(tester));
  final clip = await tester
      .runAsync(() => SalSpriteCache.clip(kSalShareButtonClip, density));
  expect(clip, isNotNull, reason: 'face_share@${density}x decodes');
  return clip!;
}

Future<void> _pumpButton(WidgetTester tester,
    {VoidCallback? brag, bool reduce = false}) async {
  tester.view.physicalSize = const Size(390 * 3, 200 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      theme: ThemeData(extensions: [AppColorsExtension.light()]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: KuteBarShareButton(
            share: KuteBarShare(barContext: _market, brag: brag),
            onTap: (_) {},
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

final Finder _share = find.byKey(const ValueKey('kute-bar-share'));

void main() {
  tearDown(() {
    SalSprite.debugPaintLog = null;
    SalSpriteCache.debugSetManifest(null);
  });

  testWidgets(
      'face_share is a 48-frame face loop at 24 fps in the manifest; both '
      'sheets decode to its grid and frame 0 carries the glyph\'s ink',
      (tester) async {
    final entry =
        (await _manifest(tester))[kSalShareButtonClip] as Map<String, dynamic>;
    expect(entry['framing'], 'face');
    expect(entry['fps'], 24);
    expect(entry['frames'], 48);
    expect(entry['columns'], 8);
    expect(entry['rows'], 6);
    expect(entry['cell'], 48);
    expect(entry['loop'], isTrue);
    expect(entry['group'], 'pill');
    for (final density in [2, 3]) {
      final files = (entry['files'] as Map)['${density}x'] as Map;
      expect(files['file'], 'face_share@${density}x.webp');
      final clip = await _load(tester, density);
      expect(clip.frames, 48);
      expect(clip.fps, 24);
      expect(clip.loop, isTrue);
      expect(clip.body, isFalse);
      expect(clip.image.width, 8 * 48 * density);
      expect(clip.image.height, 6 * 48 * density);
      expect(clip.image.width, files['width']);
      expect(clip.image.height, files['height']);
      expect(clip.cellWidth, 48.0 * density);
      expect(clip.cellHeight, 48.0 * density);

      // Frame 0 (the Reduce Motion still): Sal's orange fills the cell,
      // and the glyph's dark ink sits in its right half, not its left.
      final bytes = (await tester.runAsync(() =>
          clip.image.toByteData(format: ui.ImageByteFormat.rawStraightRgba)))!;
      final cell = clip.cell(0);
      int ink(bool right) {
        var n = 0;
        final w = cell.width.toInt();
        for (var y = 0; y < cell.height.toInt(); y++) {
          for (var x = right ? w ~/ 2 : 0; x < (right ? w : w ~/ 2); x++) {
            final i = (y * clip.image.width + x) * 4;
            final r = bytes.getUint8(i), g = bytes.getUint8(i + 1);
            final b = bytes.getUint8(i + 2), a = bytes.getUint8(i + 3);
            if (a > 200 && r < 70 && g < 70 && b < 70) n++;
          }
        }
        return n;
      }

      int orange() {
        var n = 0;
        final w = cell.width.toInt();
        for (var y = 0; y < cell.height.toInt(); y++) {
          for (var x = 0; x < w; x++) {
            final i = (y * clip.image.width + x) * 4;
            if (bytes.getUint8(i + 3) > 200 &&
                bytes.getUint8(i) > 200 &&
                bytes.getUint8(i + 2) < 120) {
              n++;
            }
          }
        }
        return n;
      }

      final area = cell.width * cell.height;
      expect(ink(true) / area, greaterThan(0.06),
          reason: 'the glyph at ${density}x');
      expect(ink(true), greaterThan(ink(false) * 3));
      expect(orange() / area, greaterThan(0.2), reason: 'Sal at ${density}x');
    }
  });

  testWidgets(
      'the round button wears face_share and loops it, read aloud as Send '
      'to a friend', (tester) async {
    await _load(tester, 3);
    SalSprite.debugPaintLog = [];
    await _pumpButton(tester);
    final sprite = find.descendant(
        of: _share,
        matching: find.byWidgetPredicate(
            (w) => w is SalSprite && w.clip == kSalShareButtonClip));
    expect(sprite, findsOneWidget);
    expect(tester.getSize(sprite), const Size(38, 38));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 1000 ~/ 24));
    }
    final log = SalSprite.debugPaintLog!;
    expect(log, isNotEmpty);
    expect(log.map((f) => f.name).toSet(), {kSalShareButtonClip});
    expect(log.map((f) => f.frame).toSet().length, greaterThan(10),
        reason: 'it plays');
    expect(find.bySemanticsLabel('Send to a friend'), findsOneWidget);
    expect(
        find.descendant(of: _share, matching: find.byType(Text)), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'in profit the same clip, read aloud as Brag about it; Reduce Motion '
      'holds frame 0', (tester) async {
    await _load(tester, 3);
    SalSprite.debugPaintLog = [];
    await _pumpButton(tester, brag: () {}, reduce: true);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 1000 ~/ 24));
    }
    final log = SalSprite.debugPaintLog!;
    expect(log, isNotEmpty);
    expect(
        log.every((f) => f.name == kSalShareButtonClip && f.frame == 0), isTrue,
        reason: '$log');
    expect(find.bySemanticsLabel('Brag about it'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no sheet: the share face stands in, then the rig',
      (tester) async {
    // The test config's null manifest: nothing reads, nothing breaks.
    await _pumpButton(tester);
    // The failed reads settle on the real event loop (the manifest's
    // future is the test config's, outside the fake clock).
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(
        find.descendant(
            of: _share,
            matching: find
                .byWidgetPredicate((w) => w is SalSprite && w.clip == 'share')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
