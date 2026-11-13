// A rolling figure's digits stay in their own box. Each reel's window is
// the digit's height off its baseline, so mid-roll nothing hangs under the
// neighbours' baseline and no fragment floats over their tops ("$75,73"
// with a stray 7 below the line); the figure's baseline and cells hold at
// every animation value, whatever the font size or line height. The ink is
// measured from real renders in the app's Inter at several animation
// values. With --dart-define=ROLL_OUT=<dir> it also writes the mid-roll
// frames as PNGs.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';

const _roll = Duration(milliseconds: 250);
const _key = ValueKey('figure');
const _out = String.fromEnvironment('ROLL_OUT');

/// The inked rows and columns of the render, in logical pixels.
class _Ink {
  _Ink(this.top, this.bottom, this.left, this.right, this.size);
  final double top, bottom, left, right;
  final Size size;
}

Future<_Ink> _ink(WidgetTester tester, double ratio, {String? name}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final w = image.width, h = image.height;
    final bytes = data!.buffer.asUint8List();
    var top = h, bottom = -1, left = w, right = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        // Dark ink on white: count what is clearly drawn.
        if (bytes[(y * w + x) * 4] < 160) {
          top = math.min(top, y);
          bottom = math.max(bottom, y);
          left = math.min(left, x);
          right = math.max(right, x);
        }
      }
    }
    if (_out.isNotEmpty && name != null) {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    }
    return _Ink(top / ratio, (bottom + 1) / ratio, left / ratio,
        (right + 1) / ratio, Size(w / ratio, h / ratio));
  }))!;
}

Widget _app(String text, TextStyle style) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Inter', splashFactory: NoSplash.splashFactory),
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: RepaintBoundary(
            key: _key,
            child: ColoredBox(
              color: Colors.white,
              child: RollingNumberText(
                text: text,
                style: style,
                duration: _roll,
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      final file = File('lib/assets/fonts/Inter-$f.ttf');
      if (file.existsSync()) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
    }
    await inter.load();
  });

  for (final size in [13.0, 16.0, 28.0, 44.0, 64.0]) {
    for (final height in [null, 1.0, 1.15, 1.4]) {
      testWidgets(
          'at $size pt (line height $height) the roll stays inside the '
          "digits' box and the baseline holds", (tester) async {
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final style = TextStyle(
          color: Colors.black,
          fontSize: size,
          fontWeight: FontWeight.w700,
          height: height,
          fontFeatures: const [ui.FontFeature.tabularFigures()],
        );
        // Digits only, so the box is the digits' ink: a comma or a dollar
        // sign reaches past it by design.
        await tester.pumpWidget(_app('888', style));
        await tester.pump();
        final settled = await _ink(tester, 3);
        final cell = tester.getRect(find.byType(Row)).size;

        await tester.pumpWidget(_app('747', style));
        final tolerance = math.max(1.0, size * 0.02);
        // Every step of the roll, a frame at a time.
        var previous = Duration.zero;
        for (final at in const [1, 8, 20, 40, 70, 110, 160, 210, 245]) {
          await tester.pump(Duration(milliseconds: at) - previous);
          previous = Duration(milliseconds: at);
          final mid = await _ink(tester, 3,
              name: size == 44 && height == 1.15 ? 'digits_44_at_$at' : null);
          expect(mid.top, greaterThanOrEqualTo(settled.top - tolerance),
              reason: 'ink over the digits at $at ms');
          expect(mid.bottom, lessThanOrEqualTo(settled.bottom + tolerance),
              reason: 'ink under the baseline at $at ms');
          expect(tester.getRect(find.byType(Row)).size, cell,
              reason: 'the line box moved at $at ms');
        }
        await tester.pump(const Duration(milliseconds: 100));
        final after = await _ink(tester, 3);
        // Settled again on other digits: the same baseline, the same tops.
        expect(after.bottom, moreOrLessEquals(settled.bottom, epsilon: tolerance));
        expect(after.top, moreOrLessEquals(settled.top, epsilon: tolerance));
        expect(tester.getRect(find.byType(Row)).size, cell);
      });
    }
  }

  testWidgets(
      "a figure's rolling digit shares its neighbours' baseline, and the "
      'neighbours do not move', (tester) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    const style = TextStyle(
      color: Colors.black,
      fontSize: 44,
      fontWeight: FontWeight.w700,
      height: 1.1,
      letterSpacing: -1,
    );

    Map<String, double> baselines() {
      final out = <String, double>{};
      for (final p in tester
          .renderObjectList<RenderParagraph>(find.byType(RichText))) {
        final y = p.localToGlobal(Offset.zero).dy +
            p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
        out['${out.length}:${p.text.toPlainText()}'] = y;
      }
      return out;
    }

    await tester.pumpWidget(_app(r'$75,738', style));
    await tester.pump();
    final at = baselines();
    expect(at.values.toSet(), hasLength(1), reason: '$at');
    final baseline = at.values.first;

    await tester.pumpWidget(_app(r'$75,749', style));
    for (final ms in const [16, 50, 100, 180]) {
      await tester.pump(const Duration(milliseconds: 16));
      await _ink(tester, 3, name: 'figure_at_$ms');
      await tester.pump(Duration(milliseconds: ms ~/ 4));
      // The ones that did not change sit on the same baseline.
      for (final e in baselines().entries) {
        if (RegExp(r':[$75,]$').hasMatch(e.key)) {
          expect(e.value, moreOrLessEquals(baseline), reason: e.key);
        }
      }
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(baselines().values.toSet(), {moreOrLessEquals(baseline)});
  });

  testWidgets('a settled digit paints whole: no clip, no leftover reel',
      (tester) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    const style = TextStyle(color: Colors.black, fontSize: 40);
    await tester.pumpWidget(_app('5', style));
    await tester.pump();
    expect(find.text('5'), findsOneWidget);
    expect(find.byType(ClipRect), findsNothing);

    await tester.pumpWidget(_app('6', style));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('5'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.byType(ClipRect), findsOneWidget);
    await tester.pump(_roll);
    expect(find.text('5'), findsNothing);
    expect(find.text('6'), findsOneWidget);
    expect(find.byType(ClipRect), findsNothing);
  });

  testWidgets('Reduce Motion snaps with no reel at all', (tester) async {
    addTearDown(tester.view.reset);
    Widget app(String t) => MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: _app(t, const TextStyle(fontSize: 30, color: Colors.black)),
        );
    await tester.pumpWidget(app('1'));
    await tester.pumpWidget(app('2'));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsNothing);
  });
}
