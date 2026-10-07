// Render harness for the dock's search glyph (Sal's face in the lens) and
// the top bar's hub glyph (a "+" with a gear badge): each in its real chip
// chrome, light and dark, at rest and at a few frames of its motion, at
// 3x, plus a nearest-neighbour zoom and one contact sheet. Writes PNGs.
//
// Not part of the normal suite; it only runs when asked:
//
//   fvm flutter test test/audit/dock_icons_render_test.dart \
//     --dart-define=ICON_OUT=/tmp/kute_dock_icons
//
// Add --dart-define=ICON_ONLY=hub to draw only the hub glyph's frames (the
// sheet is then hub_sheet.png).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/home/components/kute_top_nav_bar.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart';
import 'package:kute/theme/app_theme.dart';

const _out = String.fromEnvironment('ICON_OUT');
const _hubOnly = String.fromEnvironment('ICON_ONLY') == 'hub';
const _key = ValueKey('shot');
const _dpr = 3.0;

/// The chrome the dock's search square and the hub chip both wear.
BoxDecoration _chrome(bool light, AppColorsExtension c) => BoxDecoration(
      color: light ? Colors.white : c.surface,
      borderRadius: AppRadius.buttonBorder,
      border: Border.all(
          color: light ? c.border : c.borderSubtle, width: light ? 1.0 : 0.5),
      boxShadow: light
          ? [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2)),
            ]
          : null,
    );

Widget _chip(bool light, AppColorsExtension c, double side, Widget glyph) =>
    Container(
        width: side,
        height: side,
        alignment: Alignment.center,
        decoration: _chrome(light, c),
        child: glyph);

Widget _search(bool light, AppColorsExtension c) =>
    _chip(light, c, 54, KuteDogMagnifier(size: 46, lensColor: c.textPrimary));

Widget _hub(bool light, AppColorsExtension c) =>
    _chip(light, c, 46, HubPlusGearGlyph(color: c.textPrimary, size: 24));

Widget _dockAction(bool light, AppColorsExtension c, IconData icon, String l) =>
    Expanded(
      child: Container(
        height: 54,
        decoration: _chrome(light, c),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 20, color: c.textPrimary),
          const SizedBox(width: 8),
          Text(l,
              style: TextStyle(
                  fontFamily: 'Inter',
                  color: c.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2)),
        ]),
      ),
    );

/// A frame: null [ms] is Reduce Motion's rest frame; otherwise the first
/// play is pumped to [ms].
typedef _Frame = ({String name, String caption, int? ms});

const List<_Frame> _searchFrames = [
  (name: 'rest', caption: 'rest', ms: null),
  (name: 'scan_left', caption: 'scan left', ms: 350),
  (name: 'ear_flick', caption: 'ear flick', ms: 470),
  (name: 'scan_right', caption: 'scan right', ms: 1050),
  (name: 'blink', caption: 'blink', ms: 1575),
];

const List<_Frame> _hubFrames = [
  (name: 'rest', caption: 'rest', ms: null),
  (name: 'gear_rising', caption: 'gear rising', ms: 325),
  (name: 'gear_prominent', caption: 'gear prominent', ms: 850),
  (name: 'swapping_back', caption: 'swapping back', ms: 1375),
  (name: 'settling', caption: 'settling', ms: 1550),
];

Future<ui.Image> _shoot(WidgetTester tester, Widget child, Color bg,
    {int? ms}) async {
  // A fresh tree each shot, so the glyph plays from its start.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(
        devicePixelRatio: _dpr,
        disableAnimations: ms == null,
        size: const Size(430, 932)),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: _key,
          child: Container(
              color: bg, padding: const EdgeInsets.all(10), child: child),
        ),
      ),
    ),
  ));
  if (ms != null) {
    await tester.pump(); // the play's first tick
    await tester.pump(Duration(milliseconds: ms));
  } else {
    await tester.pump();
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  final image =
      (await tester.runAsync(() => boundary.toImage(pixelRatio: _dpr)))!;
  return image;
}

Future<void> _png(WidgetTester tester, ui.Image image, String name) =>
    tester.runAsync(() async {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });

/// Nearest-neighbour zoom: every device pixel becomes [z]x[z].
Future<ui.Image> _zoom(WidgetTester tester, ui.Image src, int z) async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawImageRect(
      src,
      Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      Rect.fromLTWH(0, 0, src.width * z.toDouble(), src.height * z.toDouble()),
      Paint()..filterQuality = FilterQuality.none);
  return (await tester.runAsync(
      () => rec.endRecording().toImage(src.width * z, src.height * z)))!;
}

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

/// Every frame of [frames], light and dark, saved and zoomed.
Future<Map<bool, List<(ui.Image, ui.Image)>>> _renderFrames(
    WidgetTester tester,
    String icon,
    List<_Frame> frames,
    Widget Function(bool, AppColorsExtension) build) async {
  final shots = <bool, List<(ui.Image, ui.Image)>>{true: [], false: []};
  for (final light in [true, false]) {
    final c = light ? AppColorsExtension.light() : AppColorsExtension.dark();
    for (final f in frames) {
      final img = await _shoot(tester, build(light, c), c.background, ms: f.ms);
      final z = await _zoom(tester, img, 3);
      final mode = light ? 'light' : 'dark';
      await _png(tester, img, '${icon}_${f.name}_$mode');
      await _png(tester, z, '${icon}_${f.name}_${mode}_zoom3x');
      shots[light]!.add((img, z));
    }
  }
  return shots;
}

void main() {
  if (_out.isEmpty) {
    test('dock icons render', () {},
        skip: 'on demand: --dart-define=ICON_OUT=<dir>');
    return;
  }

  setUpAll(() async {
    Directory(_out).createSync(recursive: true);
    final inter = FontLoader('Inter');
    for (final f in ['Regular', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
    }
    await inter.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  testWidgets('search and hub glyphs, frames and contact sheet',
      (tester) async {
    final hub = await _renderFrames(tester, 'hub', _hubFrames, _hub);
    final rows = [
      if (!_hubOnly)
        (await _renderFrames(tester, 'search', _searchFrames, _search),
            _searchFrames),
      (hub, _hubFrames),
    ];

    // In context: the dock row and the hub chip, at rest.
    final context = <bool, ui.Image>{};
    for (final light in [true, false]) {
      final c = light ? AppColorsExtension.light() : AppColorsExtension.dark();
      context[light] = await _shoot(
          tester,
          SizedBox(
            width: 390,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                _hub(light, c),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                _dockAction(light, c, Icons.south_west_rounded, 'Receive'),
                const SizedBox(width: 10),
                _dockAction(light, c, Icons.north_east_rounded, 'Send'),
                const SizedBox(width: 10),
                _search(light, c),
              ]),
            ]),
          ),
          c.background);
      await _png(tester, context[light]!,
          'in_context_${light ? 'light' : 'dark'}');
    }

    // The sheet: per theme a band with the in-context shot, then a row of
    // search frames (shot over zoom) and a row of hub frames.
    const pad = 40.0, gap = 40.0, head = 90.0, cap = 44.0;
    final light = AppColorsExtension.light(), dark = AppColorsExtension.dark();
    double rowW(List<(ui.Image, ui.Image)> row) =>
        row.fold(0.0, (w, s) => w + s.$2.width) + gap * (row.length - 1);
    double rowH(List<(ui.Image, ui.Image)> row) =>
        cap + row.first.$1.height + 20 + row.first.$2.height;
    final width = pad * 2 +
        [
          for (final (shots, _) in rows) rowW(shots[true]!),
          context[true]!.width.toDouble(),
        ].reduce((a, b) => a > b ? a : b);
    final bandH = pad +
        context[true]!.height +
        pad +
        rows.fold(0.0, (h, r) => h + rowH(r.$1[true]!) + pad);
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(Rect.fromLTWH(0, 0, width, head + bandH * 2),
        Paint()..color = Colors.white);
    _label(
        canvas,
        _hubOnly
            ? 'Hub (+ and gear swap)'
            : 'Dock search (Sal in the lens) and hub (+ and gear swap)',
        const Offset(pad, 26), light.textPrimary, size: 36);
    for (final isLight in [true, false]) {
      final c = isLight ? light : dark;
      var y = head + (isLight ? 0 : bandH);
      canvas.drawRect(Rect.fromLTWH(0, y, width, bandH),
          Paint()..color = c.background);
      y += pad;
      canvas.drawImage(context[isLight]!, Offset(pad, y), Paint());
      y += context[isLight]!.height + pad;
      for (final (all, frames) in rows) {
        final shots = all[isLight]!;
        var x = pad;
        for (var i = 0; i < shots.length; i++) {
          final (s, z) = shots[i];
          final f = frames[i];
          _label(
              canvas,
              f.ms == null ? f.caption : '${f.caption} · ${f.ms} ms',
              Offset(x, y),
              c.textSecondary,
              size: 24,
              weight: FontWeight.w400);
          canvas.drawImage(
              s, Offset(x + (z.width - s.width) / 2, y + cap), Paint());
          canvas.drawImage(z, Offset(x, y + cap + s.height + 20), Paint());
          x += z.width + gap;
        }
        y += rowH(shots) + pad;
      }
    }
    final sheet = (await tester.runAsync(() => rec
        .endRecording()
        .toImage(width.ceil(), (head + bandH * 2).ceil())))!;
    await _png(tester, sheet, _hubOnly ? 'hub_sheet' : 'final_sheet');
    await tester.pumpWidget(const SizedBox());
  });
}
