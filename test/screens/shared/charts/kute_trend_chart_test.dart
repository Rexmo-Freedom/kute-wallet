import 'package:flutter/material.dart';
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
          emptyCaption: 'Your P&L shows up after your first position.',
          rangeLabels: ['1W', '1M'],
          onScrub: null,
        ));
    final caption =
        tester.widget<Text>(find.byKey(const ValueKey('trend-chart-empty')));
    expect(caption.data, 'Your P&L shows up after your first position.');
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

  testWidgets('Reduce Motion: no draw-in, no morph, no breathing; it paints',
      (tester) async {
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
}
