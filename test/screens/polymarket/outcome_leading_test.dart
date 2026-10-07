// What leads an outcome row: its own image, else a small dot in its
// chart line's colour, else nothing; never a colour square. Rows of one
// list keep one leading width.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/outcome_leading.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/theme/app_theme.dart';

const _dot = ValueKey('outcome-line-dot');
const _blue = Color(0xFF4FC3F7);

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  ));
}

PolymarketOutcome _o(String name, double price, {String? token}) =>
    PolymarketOutcome(name: name, price: price, tokenId: token);

/// CIELAB (D65) of a colour, to tell how far apart two look.
List<double> _lab(Color c) {
  double lin(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  final r = lin(c.r), g = lin(c.g), b = lin(c.b);
  final x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
  final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  final z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
  double f(double v) =>
      v > 0.008856 ? math.pow(v, 1 / 3).toDouble() : 7.787 * v + 16 / 116;
  return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))];
}

double _apart(Color a, Color b) {
  final p = _lab(a), q = _lab(b);
  return math.sqrt([
    for (var i = 0; i < 3; i++) (p[i] - q[i]) * (p[i] - q[i]),
  ].reduce((s, v) => s + v));
}

void main() {
  group('an Up or Down market', () {
    const up = PolymarketOutcome(name: 'Up', price: 0.425, tokenId: 'u');
    const down = PolymarketOutcome(name: 'Down', price: 0.575, tokenId: 'd');

    test('Up is the up colour and Down the down colour, whichever leads',
        () {
      final lines = polyChartedOutcomes([up, down], kPolyOutcomeColors);
      // Down leads, so it is drawn first; it is still the down colour.
      expect(lines.first.outcome.name, 'Down');
      expect(lines.first.color, AppColors.marketDown);
      expect(lines.last.color, AppColors.marketUp);
      expect(polyUpDownColor('Up', const [up, down]), AppColors.marketUp);
      expect(polyUpDownColor(' down ', const [up, down]),
          AppColors.marketDown);
    });

    test('any other market keeps the palette', () {
      const yes = PolymarketOutcome(name: 'Yes', price: 0.6, tokenId: 'y');
      const no = PolymarketOutcome(name: 'No', price: 0.4, tokenId: 'n');
      expect(polyUpDownColor('Yes', const [yes, no]), isNull);
      // "Up" among other outcomes is a name like any other.
      const flat = PolymarketOutcome(name: 'Flat', price: 0.1, tokenId: 'f');
      expect(polyUpDownColor('Up', const [up, down, flat]), isNull);
      final lines = polyChartedOutcomes([up, down, flat], kPolyOutcomeColors);
      expect(lines[0].color, kPolyOutcomeColors[0]);
      expect(lines[1].color, kPolyOutcomeColors[1]);
    });
  });

  group('the colours of a many-outcome chart', () {
    test('any two of the first eight are far apart (the first and the '
        'sixth were two light blues, 12 apart)', () {
      expect(_apart(const Color(0xFF4FC3F7), const Color(0xFF64B5F6)),
          lessThan(13));
      for (var i = 0; i < 8; i++) {
        for (var j = i + 1; j < 8; j++) {
          expect(_apart(kPolyOutcomeColors[i], kPolyOutcomeColors[j]),
              greaterThanOrEqualTo(30),
              reason: 'colours ${i + 1} and ${j + 1}');
        }
      }
    });

    test('every line a chart can draw has a colour of its own, never up '
        'or down', () {
      expect(kPolyOutcomeColors.length,
          greaterThanOrEqualTo(kPolyChartMaxLines));
      expect(kPolyOutcomeColors.toSet().length, kPolyOutcomeColors.length);
      for (final c in kPolyOutcomeColors) {
        expect(c, isNot(AppColors.marketUp));
        expect(c, isNot(AppColors.marketDown));
      }
    });
  });

  testWidgets('no image, charted, text-only list: just the dot',
      (tester) async {
    await _pump(
      tester,
      const PolyOutcomeLeading(
          imageUrl: null, lineColor: _blue, listHasImages: false),
    );
    final size = tester.getSize(find.byType(PolyOutcomeLeading));
    expect(size, const Size(8, 8));
    final dot = tester.widget<Container>(find.byKey(_dot));
    final decoration = dot.decoration! as BoxDecoration;
    expect(decoration.color, _blue);
    expect(decoration.shape, BoxShape.circle);
    expect(tester.getSize(find.byKey(_dot)), const Size(8, 8));
    expect(find.byType(PolyCrestImage), findsNothing);
  });

  testWidgets('no image, not charted: nothing drawn, the same width',
      (tester) async {
    await _pump(
      tester,
      const PolyOutcomeLeading(
          imageUrl: '', lineColor: null, listHasImages: false),
    );
    expect(find.byKey(_dot), findsNothing);
    expect(find.byType(Container), findsNothing);
    expect(tester.getSize(find.byType(PolyOutcomeLeading)), const Size(8, 8));
  });

  testWidgets('no image in a list with images: the image width, dot centred',
      (tester) async {
    await _pump(
      tester,
      const PolyOutcomeLeading(
          imageUrl: null, lineColor: _blue, listHasImages: true),
    );
    final box = tester.getRect(find.byType(PolyOutcomeLeading));
    expect(box.size, const Size(28, 28));
    final dot = tester.getRect(find.byKey(_dot));
    expect(dot.size, const Size(8, 8));
    expect(dot.center, box.center);
    // The dot is the only thing painted: no colour square behind it.
    expect(find.byType(Container), findsOneWidget);
  });

  testWidgets('an outcome with an image shows the image at the same width',
      (tester) async {
    await _pump(
      tester,
      const PolyOutcomeLeading(
        imageUrl: 'https://example.com/flag.png',
        lineColor: _blue,
        listHasImages: true,
      ),
    );
    final image = tester.widget<PolyCrestImage>(find.byType(PolyCrestImage));
    expect(image.url, 'https://example.com/flag.png');
    expect(image.size, 28);
    // No dot beside an image: the figure already carries the colour.
    expect(find.byKey(_dot), findsNothing);
  });

  test('a list leads with something only when a row has an image or a line',
      () {
    expect(PolyOutcomeLeading.listLeads(anyImage: false, anyLine: false),
        isFalse);
    expect(
        PolyOutcomeLeading.listLeads(anyImage: true, anyLine: false), isTrue);
    expect(
        PolyOutcomeLeading.listLeads(anyImage: false, anyLine: true), isTrue);
    expect(PolyOutcomeLeading.hasImage(null), isFalse);
    expect(PolyOutcomeLeading.hasImage('  '), isFalse);
    expect(PolyOutcomeLeading.hasImage('https://example.com/a.svg'), isTrue);
  });

  test('the chart draws the six most likely outcomes, palette in order', () {
    const palette = [Color(0xFF000001), Color(0xFF000002), Color(0xFF000003)];
    final charted = polyChartedOutcomes([
      _o('Corn', 0.70, token: 'corn'),
      _o('Love', 0.95, token: 'love'),
      _o('No token', 0.99),
      _o('Fake News', 0.93, token: 'fake'),
      for (var i = 0; i < 6; i++) _o('Tail $i', 0.1 - i / 100, token: 't$i'),
    ], palette);
    expect([for (final l in charted) l.outcome.name],
        ['Love', 'Fake News', 'Corn', 'Tail 0', 'Tail 1', 'Tail 2']);
    expect([for (final l in charted) l.color], [
      palette[0], palette[1], palette[2], palette[0], palette[1], palette[2], //
    ]);
    expect(polyChartedOutcomes(const [], palette), isEmpty);
  });
}
