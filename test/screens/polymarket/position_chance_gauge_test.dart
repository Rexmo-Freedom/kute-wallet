// The open-position screen's chance gauge (position_chance_gauge.dart):
// the bar's spec on a half circle. The fill's sweep and the tick's angle
// off the painter's own geometry (no goldens), the "Bought · X¢" tag
// outside the arc at every price (beside its ends at 0–10% and 90–100%),
// the chance in the middle with the localised "chance" under it, and no
// tick or tag without a price paid.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/polymarket/components/position_chance_bar.dart';
import 'package:kute/screens/polymarket/components/position_chance_gauge.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';

const _w = 330.0;

Future<void> _pump(WidgetTester tester, PolyChanceBarSpec spec,
    {double chance = 0.5,
    String? label = 'Bought · 78¢',
    bool dark = false,
    bool reduceMotion = false,
    double width = _w}) async {
  tester.view.physicalSize = Size(math.max(390, width + 60), 400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(extensions: [
          dark ? AppColorsExtension.dark() : AppColorsExtension.light()
        ]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
              size: const Size(390, 400), disableAnimations: reduceMotion),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: PolyPositionChanceGauge(
                    spec: spec, chance: chance, tickLabel: label),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

PolyChanceBarSpec _yes(double p, {double? bought = 0.78}) =>
    polyPositionChanceBarSpec(
        outcome: 'Yes', chance: p, bought: bought, fallbackColor: Colors.blue);

PolyChanceGaugePainter _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(find.byKey(PolyPositionChanceGauge.paintKey))
    .painter! as PolyChanceGaugePainter;

/// The figure in the middle (rolling digits: one widget per character).
String _figure(WidgetTester tester) => tester
    .widget<RollingNumberText>(find.descendant(
        of: find.byKey(PolyPositionChanceGauge.figureKey),
        matching: find.byType(RollingNumberText)))
    .text;

/// The tag in the gauge's own box.
Rect _label(WidgetTester tester) {
  final box = tester.getRect(find.byKey(PolyPositionChanceGauge.gaugeKey));
  return tester
      .getRect(find.byKey(PolyPositionChanceGauge.labelKey))
      .shift(-box.topLeft);
}

/// The nearest a rect comes to [p].
double _distance(Rect r, Offset p) {
  final x = p.dx.clamp(r.left, r.right);
  final y = p.dy.clamp(r.top, r.bottom);
  return (Offset(x.toDouble(), y.toDouble()) - p).distance;
}

PolyChanceGaugeGeometry _geometry(double? tick) => polyChanceGaugeGeometry(
      width: _w,
      outerRadius: 42,
      stroke: 10,
      overhang: 3,
      gap: 2,
      belowCenter: 15,
      tick: tick,
      tag: const Size(70, 17),
    );

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the painter\'s angles', () {
    test('the half circle runs from π on the left over 3π/2 to 2π', () {
      expect(polyGaugeAngle(0), closeTo(math.pi, 1e-12));
      expect(polyGaugeAngle(0.5), closeTo(1.5 * math.pi, 1e-12));
      expect(polyGaugeAngle(1), closeTo(2 * math.pi, 1e-12));
      expect(polyGaugeAngle(0.78), closeTo(1.78 * math.pi, 1e-12));
      // Out of range clamps to the ends.
      expect(polyGaugeAngle(-0.2), closeTo(math.pi, 1e-12));
      expect(polyGaugeAngle(1.4), closeTo(2 * math.pi, 1e-12));
    });

    test('the fill sweeps its share of π', () {
      expect(polyGaugeSweep(0), 0);
      expect(polyGaugeSweep(0.758), closeTo(0.758 * math.pi, 1e-12));
      expect(polyGaugeSweep(1), closeTo(math.pi, 1e-12));
    });

    test('the tick sits at the price paid; none without one', () {
      expect(_geometry(0.78).tickAngle, closeTo(1.78 * math.pi, 1e-12));
      expect(_geometry(null).tickAngle, isNull);
      expect(_geometry(null).labelRect, isNull);
    });

    test('the tag never touches the arc or the tick, at any price', () {
      for (var i = 0; i <= 100; i++) {
        final g = _geometry(i / 100);
        expect(_distance(g.labelRect!, g.center), greaterThan(g.tickOuter),
            reason: 'at $i%');
        // Inside the box.
        expect(g.labelRect!.top, greaterThanOrEqualTo(-1e-9));
        expect(g.labelRect!.bottom, lessThanOrEqualTo(g.size.height + 1e-9));
        expect(g.labelRect!.left, greaterThanOrEqualTo(0));
        expect(g.labelRect!.right, lessThanOrEqualTo(_w));
      }
    });

    test(
        'at the ends the tag flips beside the arc: left of it at 0–10%, '
        'right of it at 90–100%; above it in the middle', () {
      for (final t in [0.0, 0.03, 0.1]) {
        final g = _geometry(t);
        expect(
            g.labelRect!.right, lessThan(g.center.dx - g.radius - g.stroke / 2),
            reason: 'at $t');
      }
      for (final t in [0.9, 0.97, 1.0]) {
        final g = _geometry(t);
        expect(g.labelRect!.left,
            greaterThan(g.center.dx + g.radius + g.stroke / 2),
            reason: 'at $t');
      }
      final mid = _geometry(0.5);
      expect(mid.labelRect!.bottom, lessThan(mid.center.dy - mid.tickOuter));
      expect(mid.labelRect!.center.dx, closeTo(mid.center.dx, 1e-9));
    });

    test('the box is no taller than it needs: arc, tag and caption', () {
      final none = _geometry(null);
      expect(none.size.height, closeTo(42 + 15, 1e-9));
      final mid = _geometry(0.5);
      expect(mid.size.height, closeTo(42 + 3 + 2 + 17 + 15, 1e-9));
    });
  });

  group('the chance in the middle', () {
    test('the figure and the caption, cut from one sentence', () {
      expect(polyGaugeChanceParts('75.8% chance', '75.8'),
          (figure: '75.8%', caption: 'chance'));
      expect(polyGaugeChanceParts('75.8 % de chances', '75.8'),
          (figure: '75.8 %', caption: 'de chances'));
      expect(polyGaugeChanceParts('Szansa 75.8%', '75.8'),
          (figure: '75.8%', caption: 'Szansa'));
      expect(polyGaugeChanceParts('確率75.8%', '75.8'),
          (figure: '75.8%', caption: '確率'));
    });

    testWidgets(
        'Yes at 75.8% bought at 78¢: filled to 75.8%, ticked at 78%, '
        '"75.8%" over "chance", the tag beside the tick', (tester) async {
      await _pump(tester, _yes(0.758), chance: 0.758);
      final p = _painter(tester);
      expect(p.value, closeTo(0.758, 1e-9));
      expect(p.fillArc.start, closeTo(math.pi, 1e-12));
      expect(p.fillArc.sweep, closeTo(0.758 * math.pi, 1e-9));
      expect(p.geometry.tickAngle, closeTo(1.78 * math.pi, 1e-9));
      expect(p.fill, AppColors.marketUp);
      expect(p.track, AppColors.marketDown);
      expect(p.split, isTrue);
      expect(_figure(tester), '75.8%');
      expect(find.text('chance'), findsOneWidget);
      expect(find.text('Bought · 78¢'), findsOneWidget);
      // Outside the arc, on the tick's side.
      final label = _label(tester);
      expect(_distance(label, p.geometry.center),
          greaterThan(p.geometry.tickOuter));
      expect(label.center.dx, greaterThan(p.geometry.center.dx));
      // The chance and the price paid are read out, once.
      expect(
          find.bySemanticsLabel('75.8% chance, Bought · 78¢'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a fill in an outcome\'s own colour runs on the neutral '
        'track', (tester) async {
      await _pump(
          tester,
          polyPositionChanceBarSpec(
              outcome: 'Lakers',
              chance: 0.64,
              bought: 0.42,
              lineColor: Colors.purple,
              fallbackColor: Colors.blue),
          chance: 0.64,
          label: 'Bought · 42¢');
      final p = _painter(tester);
      expect(p.fill, Colors.purple);
      expect(p.split, isFalse);
      expect(p.track, AppColorsExtension.light().border);
      expect(p.tickColor, AppColorsExtension.light().textPrimary);
    });

    testWidgets('at the extremes the tag flips beside the arc\'s end',
        (tester) async {
      // The dial leaves room for the tag beside either end, so it sits
      // level with the arc's end, never lifted to a corner. The test font
      // draws a tag about twice the real one, so the surface is wider in
      // the same proportion (a 390 pt phone with the real font).
      await _pump(tester, _yes(0.5, bought: 0.03),
          label: 'Bought · 3¢', width: 700);
      var g = _painter(tester).geometry;
      expect(_label(tester).right, lessThan(g.center.dx - g.radius));
      expect(_label(tester).center.dy, greaterThan(g.center.dy - g.radius));
      await _pump(tester, _yes(0.5, bought: 0.97),
          label: 'Bought · 97¢', width: 700);
      g = _painter(tester).geometry;
      expect(_label(tester).left, greaterThan(g.center.dx + g.radius));
      expect(_label(tester).center.dy, greaterThan(g.center.dy - g.radius));
      expect(tester.takeException(), isNull);
    });

    testWidgets('chance 0 and 100: empty and full, the figure flat',
        (tester) async {
      await _pump(tester, _yes(0), chance: 0);
      expect(_painter(tester).fillArc.sweep, 0);
      expect(_figure(tester), '0%');
      await _pump(tester, _yes(1), chance: 1);
      // The fill eases from empty.
      await tester.pump(const Duration(milliseconds: 400));
      expect(_painter(tester).fillArc.sweep, closeTo(math.pi, 1e-12));
      expect(_figure(tester), '100%');
      expect(tester.takeException(), isNull);
    });

    testWidgets('no price paid: no tick, no tag; the chance alone is read',
        (tester) async {
      await _pump(tester, _yes(0.62, bought: null), chance: 0.62);
      expect(_painter(tester).geometry.tickAngle, isNull);
      expect(find.byKey(PolyPositionChanceGauge.labelKey), findsNothing);
      expect(find.bySemanticsLabel('62% chance'), findsOneWidget);
    });

    testWidgets('a new price eases over 300 ms; at once under reduced motion',
        (tester) async {
      await _pump(tester, _yes(0.4), chance: 0.4);
      await _pump(tester, _yes(0.8), chance: 0.8);
      await tester.pump(const Duration(milliseconds: 100));
      final mid = _painter(tester).value;
      expect(mid, greaterThan(0.4));
      expect(mid, lessThan(0.8));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_painter(tester).value, closeTo(0.8, 1e-9));

      await _pump(tester, _yes(0.4), chance: 0.4, reduceMotion: true);
      await _pump(tester, _yes(0.8), chance: 0.8, reduceMotion: true);
      await tester.pump();
      expect(_painter(tester).value, closeTo(0.8, 1e-9));
    });

    testWidgets('dark: the dark track and tick', (tester) async {
      await _pump(
          tester,
          polyPositionChanceBarSpec(
              outcome: 'Lakers',
              chance: 0.64,
              bought: 0.42,
              lineColor: Colors.purple,
              fallbackColor: Colors.blue),
          chance: 0.64,
          dark: true);
      final p = _painter(tester);
      expect(p.track, AppColorsExtension.dark().border);
      expect(p.tickColor, AppColorsExtension.dark().textPrimary);
      expect(tester.takeException(), isNull);
    });
  });
}
