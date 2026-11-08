import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/charts/kute_trend_chart.dart';
import 'package:kute/theme/app_theme.dart';

/// The modern line chart: a horizontal drag (or a long press) scrubs and
/// hands the host the nearest point, null on release; no history draws
/// one caption and no plot; the range row's pills; the colour by result.
void main() {
  final times = [for (var i = 0; i < 5; i++) DateTime(2026, 10, 20 + i, 12)];

  Widget app(Widget child, {bool reduceMotion = false}) => ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(disableAnimations: reduceMotion),
                // In a list, as every host puts it: a vertical drag is
                // the list's.
                child: ListView(
                    padding: const EdgeInsets.all(16), children: [child]),
              ),
            ),
          ),
        ),
      );

  Future<void> pump(WidgetTester tester, Widget child,
      {bool reduceMotion = false}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(child, reduceMotion: reduceMotion));
    await tester.pump(const Duration(milliseconds: 700));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  Finder plot() => find.byKey(const ValueKey('trend-chart-plot'));

  testWidgets(
      'a horizontal drag reports the nearest point, then null on release; '
      'a selection click on each new point', (tester) async {
    final reported = <KuteTrendPoint?>[];
    var starts = 0;
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pump(
        tester,
        KuteTrendChart(
          values: const [10, 12, 11, 15, 14],
          times: times,
          onScrub: reported.add,
          onScrubStart: () => starts++,
        ));
    final rect = tester.getRect(plot());
    // The plot keeps 6 px on the right for the end dot: the points sit
    // at 0, 1/4, 1/2, 3/4 and 1 of the width less that.
    final w = rect.width - 6;
    final touch = await tester.startGesture(rect.centerLeft + Offset(w / 2, 0));
    // Past the slop: a horizontal drag.
    await touch.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(reported, isNotEmpty);
    // 30 px right of the middle on a ~360 wide plot: still nearest the
    // middle point.
    expect(reported.last, KuteTrendPoint(index: 2, value: 11, time: times[2]));
    expect(starts, 1);

    await touch.moveTo(rect.centerLeft + Offset(w * 0.78, 0));
    await tester.pump();
    expect(reported.last, KuteTrendPoint(index: 3, value: 15, time: times[3]));
    // Past the right edge: the last point, never beyond.
    await touch.moveTo(rect.centerRight + const Offset(40, 0));
    await tester.pump();
    expect(reported.last, KuteTrendPoint(index: 4, value: 14, time: times[4]));
    await touch.up();
    await tester.pump();
    expect(reported.last, isNull);
    expect(starts, 1);
    expect(haptics, contains('HapticFeedbackType.selectionClick'));
    // Throttled: three new points inside a frame, one click.
    expect(haptics.length, lessThanOrEqualTo(2));
    await settle(tester);
  });

  testWidgets('a long press scrubs too, and a vertical drag never does',
      (tester) async {
    final reported = <KuteTrendPoint?>[];
    await pump(
        tester,
        KuteTrendChart(
          values: const [1, 2, 3, 4, 5],
          onScrub: reported.add,
        ));
    final rect = tester.getRect(plot());
    final touch = await tester.startGesture(rect.centerLeft + const Offset(2, 0));
    await tester.pump(const Duration(milliseconds: 600));
    expect(reported.last, const KuteTrendPoint(index: 0, value: 1, time: null));
    await touch.up();
    await tester.pump();
    expect(reported.last, isNull);
    reported.clear();

    final drag = await tester.startGesture(rect.center);
    await drag.moveBy(const Offset(0, 40));
    await tester.pump();
    await drag.up();
    await tester.pump();
    expect(reported, isEmpty);
    await settle(tester);
  });

  testWidgets(
      'no history: one 12 sp textSecondary caption, no plot, no range row',
      (tester) async {
    await pump(
        tester,
        const KuteTrendChart(
          values: [],
          emptyCaption: 'Your profits show up after your first position.',
          rangeLabels: ['1W', '1M'],
          onScrub: null,
        ));
    final caption =
        tester.widget<Text>(find.byKey(const ValueKey('trend-chart-empty')));
    expect(caption.data, 'Your profits show up after your first position.');
    expect(caption.style!.fontSize, closeTo(12 * 400 / 430, 0.1));
    expect(caption.style!.color, AppColorsExtension.light().textSecondary);
    expect(plot(), findsNothing);
    expect(find.byType(KuteChartRangeRow), findsNothing);
    expect(
        find.descendant(
            of: find.byType(KuteTrendChart),
            matching: find.byType(CustomPaint)),
        findsNothing);
    await settle(tester);
  });

  testWidgets(
      'the range row: 12 sp pills sharing the width 16 px under the plot, '
      'the white thumb on the picked one, a tap reports its index',
      (tester) async {
    final picked = <int>[];
    await pump(
        tester,
        KuteTrendChart(
          values: const [1, 2, 3],
          rangeLabels: const ['1W', '1M', '3M', '1Y', 'ALL'],
          selectedRange: 1,
          onRangeSelected: picked.add,
        ));
    final row = find.byType(KuteChartRangeRow);
    expect(row, findsOneWidget);
    expect(tester.getTopLeft(row).dy,
        closeTo(tester.getBottomLeft(plot()).dy + 16 * 800 / 932, 0.5));
    final thumb = tester.getRect(find.byKey(const ValueKey('range-row-thumb')));
    final rowRect = tester.getRect(row);
    expect(thumb.width, closeTo(rowRect.width / 5, 0.5));
    expect(thumb.left, closeTo(rowRect.left + rowRect.width / 5, 0.5));
    final decoration = tester
        .widget<Container>(find.byKey(const ValueKey('range-row-thumb')))
        .decoration as BoxDecoration;
    expect(decoration.color, Colors.white);
    expect(decoration.border, isNotNull);
    expect(decoration.boxShadow, isNotEmpty);
    final label = tester.widget<AnimatedDefaultTextStyle>(find
        .ancestor(
            of: find.text('1M'), matching: find.byType(AnimatedDefaultTextStyle))
        .first);
    expect(label.style.fontSize, closeTo(12 * 400 / 430, 0.1));
    expect(label.style.fontWeight, FontWeight.w600);
    await tester.tap(find.text('1Y'));
    expect(picked, [3]);
    await settle(tester);
  });

  testWidgets('the colour: up, down, flat; a host override wins',
      (tester) async {
    final c = AppColorsExtension.light();
    expect(kuteTrendResultColor(c, 1, 2), AppColors.marketUp);
    expect(kuteTrendResultColor(c, 2, 1), AppColors.marketDown);
    expect(kuteTrendResultColor(c, 2, 2), c.textPrimary);
    await pump(tester,
        const KuteTrendChart(values: [1, 2], lineColor: Colors.purple));
    expect(
        tester.widget<KuteTrendChart>(find.byType(KuteTrendChart)).lineColor,
        Colors.purple);
    await settle(tester);
  });

  testWidgets('the plot is 200 tall (160 compact) and bleeds to its width',
      (tester) async {
    await pump(tester, const KuteTrendChart(values: [1, 2, 3]));
    expect(tester.getSize(plot()).height, closeTo(200, 0.01));
    expect(tester.getSize(plot()).width, 400 - 32);
    await pump(
        tester,
        const KuteTrendChart(
            values: [1, 2, 3], height: kKuteTrendPlotHeightCompact));
    expect(tester.getSize(plot()).height, closeTo(160, 0.01));
    await settle(tester);
  });

  testWidgets('the live dot breathes (a 1.6 s loop), not under flutter test',
      (tester) async {
    await pump(tester, const KuteTrendChart(values: [1, 2, 3]));
    dynamic painter() => tester
        .widget<CustomPaint>(find.descendant(
            of: find.byType(KuteTrendChart),
            matching: find.byType(CustomPaint)))
        .painter;
    // The runner's default: still, so pumpAndSettle settles.
    expect(painter().breath, 0.0);
    await tester.pumpAndSettle();

    KuteTrendChart.debugBreathe = true;
    addTearDown(() => KuteTrendChart.debugBreathe = null);
    // pump() left 700 ms of the 1600 ms loop behind: near the top.
    await pump(tester, const KuteTrendChart(values: [1, 2, 3, 4]));
    expect(painter().breath, greaterThan(0.9));
    await tester.pump(const Duration(milliseconds: 900));
    expect(painter().breath, closeTo(0, 0.05));
    await tester.pump(const Duration(milliseconds: 400));
    expect(painter().breath, closeTo(0.707, 0.05));
    await tester.pump(const Duration(milliseconds: 400));
    expect(painter().breath, closeTo(1, 0.05));
    // Not live: still.
    await pump(tester,
        const KuteTrendChart(values: [1, 2, 3, 4], live: false));
    expect(painter().breath, 0.0);
    await settle(tester);
  });

  testWidgets('Reduce Motion: no draw-in, no morph, no breathing; it paints',
      (tester) async {
    KuteTrendChart.debugBreathe = true;
    addTearDown(() => KuteTrendChart.debugBreathe = null);
    await pump(tester, const KuteTrendChart(values: [1, 2, 3]),
        reduceMotion: true);
    await tester.pumpWidget(app(const KuteTrendChart(values: [3, 2, 1]),
        reduceMotion: true));
    await tester.pump();
    expect(tester.takeException(), isNull);
    dynamic painter() => tester
        .widget<CustomPaint>(find.descendant(
            of: find.byType(KuteTrendChart),
            matching: find.byType(CustomPaint)))
        .painter;
    // Drawn whole at once, the new series in place, the dot still.
    expect(painter().drawIn, 1.0);
    expect(painter().breath, 0.0);
    expect(painter().values, [3.0, 2.0, 1.0]);
    await tester.pump(const Duration(seconds: 1));
    expect(painter().breath, 0.0);
    await settle(tester);
  });

  testWidgets(
      'a live tick (only the last point moved) repaints in place, no morph; '
      'another series morphs; a baseline puts the dashed line (and the '
      'scale) at it, zero dropping the solid zero line', (tester) async {
    dynamic painter() => tester
        .widget<CustomPaint>(find.descendant(
            of: find.byType(KuteTrendChart),
            matching: find.byType(CustomPaint)))
        .painter;
    await pump(tester,
        const KuteTrendChart(values: [1, 2, 3, 4], zeroSplit: true, baseline: 0));
    expect(painter().startValue, 0.0);
    expect(painter().zeroLine, isFalse);
    // The newest point moves: the series as given, at once.
    await tester.pumpWidget(app(const KuteTrendChart(
        values: [1, 2, 3, 4.5], zeroSplit: true, baseline: 0)));
    await tester.pump();
    expect(painter().values, [1.0, 2.0, 3.0, 4.5]);
    // Another series: the morph's resampled line on its way.
    await tester.pumpWidget(app(const KuteTrendChart(
        values: [4, 1, 3, 2], zeroSplit: true, baseline: 0)));
    await tester.pump(const Duration(milliseconds: 16));
    expect((painter().values as List<double>).length, kKuteTrendMorphSamples);
    await tester.pump(const Duration(seconds: 1));
    expect(painter().values, [4.0, 1.0, 3.0, 2.0]);
    // No baseline: the period's first value, the solid zero line kept.
    await tester.pumpWidget(
        app(const KuteTrendChart(values: [-1, 2, 3], zeroSplit: true)));
    await tester.pump(const Duration(seconds: 1));
    expect(painter().startValue, -1.0);
    expect(painter().zeroLine, isTrue);
    await settle(tester);
  });

  group('the scale with a goal (KuteTrendScale)', () {
    test('no goal, or a goal the line has touched: the band alone, linear',
        () {
      final s = KuteTrendScale.fit([100.0, 300.0, 200.0]);
      expect(s.gap, 0);
      expect(s.compressed, isFalse);
      expect(s.unit(100), 0);
      expect(s.unit(300), 1);
      expect(s.unit(200), closeTo(0.5, 1e-9));
      final touched = KuteTrendScale.fit([400.0, 300.0], goal: 380);
      expect(touched.gap, 0);
      expect(touched.unit(380), closeTo(0.8, 1e-9));
    });

    test('a goal within the band\'s height above it: to scale, linear over '
        'band and gap', () {
      final s = KuteTrendScale.fit([100.0, 300.0], goal: 450);
      expect(s.gap, 150);
      expect(s.compressed, isFalse);
      expect(s.gapShare, closeTo(150 / 350, 1e-9));
      expect(s.unit(100), 0);
      expect(s.unit(300), closeTo(200 / 350, 1e-9));
      expect(s.unit(450), closeTo(1, 1e-9));
      // Exactly linear: the midpoint of the gap is the midpoint in units.
      expect(s.unit(375), closeTo(275 / 350, 1e-9));
    });

    test('a far goal: the gap squeezed to half, the band keeps the other '
        'half; a flat band is padded a tenth each way first', () {
      final s = KuteTrendScale.fit([100.0, 300.0], goal: 2000);
      expect(s.compressed, isTrue);
      expect(s.gapShare, 0.5);
      expect(s.unit(300), closeTo(0.5, 1e-9));
      expect(s.unit(2000), closeTo(1, 1e-9));
      expect(s.unit(1150), closeTo(0.75, 1e-9));
      // A tiny flat balance under a far goal still reads: centred in its
      // half.
      final flat = KuteTrendScale.fit([5.0, 5.0], goal: 100);
      expect(flat.lo, closeTo(4.5, 1e-9));
      expect(flat.hi, closeTo(5.5, 1e-9));
      expect(flat.compressed, isTrue);
      expect(flat.unit(5), closeTo(0.25, 1e-9));
      expect(flat.unit(100), closeTo(1, 1e-9));
    });

    test('the squeeze starts exactly where the true share would pass half:'
        ' no jump', () {
      // Band 200 tall, gap 200: the true share is half; one more and it is
      // capped at half, the same picture.
      final at = KuteTrendScale.fit([100.0, 300.0], goal: 500);
      final past = KuteTrendScale.fit([100.0, 300.0], goal: 501);
      expect(at.gapShare, closeTo(0.5, 1e-9));
      expect(at.compressed, isFalse);
      expect(past.gapShare, 0.5);
      expect(past.compressed, isTrue);
      expect(past.unit(300), closeTo(at.unit(300), 1e-9));
    });

    test('nothing finite: a unit band around zero', () {
      final s = KuteTrendScale.fit([double.nan], goal: double.infinity);
      expect(s.lo, -1);
      expect(s.hi, 1);
      expect(s.gap, 0);
    });
  });

  test('the split gradient: up at 8% down to zero, down at 8% from it, a '
      'hard stop', () {
    final g = kuteZeroSplitGradient(
        zeroFraction: 0.4,
        up: AppColors.marketUp,
        down: AppColors.marketDown);
    expect(g.stops, [0, 0.4, 0.4, 1]);
    expect(g.colors, [
      AppColors.marketUp.withValues(alpha: 0.08),
      AppColors.marketUp.withValues(alpha: 0.08),
      AppColors.marketDown.withValues(alpha: 0.08),
      AppColors.marketDown.withValues(alpha: 0.08),
    ]);
    // Zero off the plot: the whole plot one side.
    expect(
        kuteZeroSplitGradient(
                zeroFraction: 1.6,
                up: AppColors.marketUp,
                down: AppColors.marketDown)
            .stops,
        [0, 1, 1, 1]);
  });

  testWidgets(
      'zeroSplit paints the area above zero green and below zero red, the '
      'zero line where the series crosses it; off, the one-colour fade',
      (tester) async {
    const key = ValueKey('split-shot');
    // Down at −10, then up at +10: below zero on the left, above on the
    // right.
    const values = [-10.0, -10.0, -10.0, 10.0, 10.0, 10.0];
    Future<Color Function(double, double)> shoot(bool split) async {
      await pump(
          tester,
          const RepaintBoundary(
              key: key,
              child: ColoredBox(
                  color: Colors.white,
                  child: KuteTrendChart(
                      values: values, live: false, zeroSplit: true))),
          reduceMotion: true);
      if (!split) {
        await pump(
            tester,
            const RepaintBoundary(
                key: key,
                child: ColoredBox(
                    color: Colors.white,
                    child: KuteTrendChart(values: values, live: false))),
            reduceMotion: true);
      }
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final image = (await tester.runAsync(() => boundary.toImage()))!;
      final bytes = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
      return (double x, double y) {
        final i = (y.round() * image.width + x.round()) * 4;
        return Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i),
            bytes.getUint8(i + 1), bytes.getUint8(i + 2));
      };
    }

    final pixel = await shoot(true);
    final size = tester.getSize(plot());
    final w = size.width;
    final y0 = size.height / 2; // −12…12 on screen: zero in the middle.
    int r(Color c) => (c.r * 255).round();
    int g(Color c) => (c.g * 255).round();
    // Left, between the line (−10) and zero: red.
    final below = pixel(w * 0.1, y0 + 20);
    expect(r(below), greaterThan(g(below)));
    // Right, between zero and the line (+10): green.
    final above = pixel(w * 0.9, y0 - 20);
    expect(g(above), greaterThan(r(above)));
    // Left, above zero (outside the area): untinted.
    final clear = pixel(w * 0.1, y0 - 20);
    expect(r(clear), 255);
    expect(g(clear), 255);
    // The zero line, faint, at zero.
    final zero = pixel(w * 0.05, y0);
    expect(r(zero), lessThan(250));
    expect(g(zero), lessThan(250));

    // Off (a balance chart): the one-colour fade under the line, nothing
    // above it, no zero line.
    final plain = await shoot(false);
    final clearPlain = plain(w * 0.1, y0 - 20);
    expect(r(clearPlain), 255);
    final zeroPlain = plain(w * 0.05, y0);
    expect(r(zeroPlain), 255);
    expect(g(zeroPlain), 255);
    await settle(tester);
  });
}
