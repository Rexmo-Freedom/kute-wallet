import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/charts/kute_chart_crosshair.dart';
import 'package:kute/screens/shared/charts/kute_chart_viewport.dart';
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/theme/app_theme.dart';

/// The shared line chart behaves like the venue charts: a long press
/// (then slide) scrubs and shows the one scrub card, a plain drag never
/// scrubs, two fingers zoom and a drag then pans. `onScrubStart` fires
/// once per scrub gesture, never on the moves that follow, and not at all
/// on a chart that takes no touches.
void main() {
  Future<void> pump(WidgetTester tester,
      {VoidCallback? onScrubStart,
      bool interactive = true,
      List<double> values = const [1, 2, 3, 4, 5, 6, 7, 8],
      Widget? Function(int, int)? summary}) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 200,
          child: KuteLineChart(
            values: values,
            lineColor: Colors.green,
            animateChanges: false,
            valueTextBuilder: interactive ? (i) => 'v${values[i]}' : null,
            timeTextBuilder: (i) => 'day $i',
            changeFormatter: (m) => '\$$m',
            onScrubStart: onScrubStart,
            summaryBuilder: summary,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<TestGesture> press(WidgetTester tester, Offset at) async {
    final g = await tester.startGesture(at);
    await tester.pump(const Duration(milliseconds: 600));
    return g;
  }

  testWidgets('one start per long press, none for the moves', (tester) async {
    var starts = 0;
    await pump(tester, onScrubStart: () => starts++);
    final rect = tester.getRect(find.byType(KuteLineChart));

    final touch = await press(tester, rect.centerLeft + const Offset(10, 0));
    await touch.moveBy(const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await touch.moveBy(const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 50));
    expect(starts, 1);

    await touch.up();
    await tester.pumpAndSettle();

    final again = await press(tester, rect.center);
    await again.up();
    await tester.pumpAndSettle();
    expect(starts, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a quick drag or a tap never scrubs', (tester) async {
    var starts = 0;
    await pump(tester, onScrubStart: () => starts++);
    final rect = tester.getRect(find.byType(KuteLineChart));
    await tester.dragFrom(rect.center, const Offset(80, 0));
    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();
    expect(starts, 0);
    expect(find.byType(KuteScrubCard), findsNothing);
  });

  testWidgets('the scrub card writes the value, the change and the date',
      (tester) async {
    await pump(tester);
    final rect = tester.getRect(find.byType(KuteLineChart));
    // Index 4 of 0..7 sits at 4/7 of the width.
    final touch =
        await press(tester, rect.topLeft + Offset(300 * 4 / 7, 100));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(KuteScrubCard), findsOneWidget);
    expect(find.text('v5.0'), findsOneWidget);
    // From the first point on screen (1) to 5: +4, +400.0%.
    expect(find.text('+\$4.0 (+400.0%)'), findsOneWidget);
    expect(find.text('day 4'), findsOneWidget);
    final change = tester.widget<Text>(find.text('+\$4.0 (+400.0%)'));
    expect(change.style!.color, AppColors.marketUp);
    // The card is the one place the point is written.
    expect(find.text('v5.0'), findsOneWidget);
    await touch.up();
    await tester.pumpAndSettle();
    expect(find.byType(KuteScrubCard), findsNothing);
  });

  testWidgets('the card stays inside the chart at its right edge',
      (tester) async {
    await pump(tester);
    final rect = tester.getRect(find.byType(KuteLineChart));
    final touch = await press(tester, rect.centerRight - const Offset(2, 0));
    await tester.pump(const Duration(milliseconds: 200));
    final card = tester.getRect(find.byType(KuteScrubCard));
    expect(card.right, lessThanOrEqualTo(rect.right + 0.01));
    expect(card.left, greaterThanOrEqualTo(rect.left - 0.01));
    // It sits on the left of the hairline there, off the finger.
    expect(card.right, lessThan(rect.right - 2));
    await touch.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a pinch zooms in, a drag then pans, the summary follows',
      (tester) async {
    final values = [for (var i = 0; i < 60; i++) i.toDouble()];
    final windows = <(int, int)>[];
    await pump(tester, values: values, summary: (a, b) {
      windows.add((a, b));
      return const SizedBox(height: 10);
    });
    expect(windows.last, (0, 59));
    final rect = tester.getRect(find.byType(KuteLineChart));
    final a = await tester.startGesture(rect.center - const Offset(30, 0));
    final b = await tester.startGesture(rect.center + const Offset(30, 0),
        pointer: 99);
    await tester.pump();
    await a.moveBy(const Offset(-60, 0));
    await b.moveBy(const Offset(60, 0));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    // Three times as far apart: a third of the points, still ending on
    // the newest.
    final zoomed = windows.last;
    expect(zoomed.$2, 59);
    expect(zoomed.$2 - zoomed.$1, inInclusiveRange(18, 21));

    // Zoomed in, a drag to the right walks back in time.
    await tester.dragFrom(rect.center, const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(windows.last.$2, lessThan(59));
    expect(tester.takeException(), isNull);
  });

  test('the scale fits the points on screen, a flat line centred', () {
    // A tenth of the plot free above and below the visible high and low.
    final series = [10.0, 20.0, 30.0, 100.0, 40.0];
    final whole = kuteLineDomain(series, const KuteIndexWindow(0, 4));
    expect(whole.minY, closeTo(10 - 90 * 0.125, 1e-9));
    expect(whole.maxY, closeTo(100 + 90 * 0.125, 1e-9));
    // Zoomed onto the first three points the spike leaves the scale.
    final zoomed = kuteLineDomain(series, const KuteIndexWindow(0, 2));
    expect(zoomed.maxY, lessThan(40));
    // A flat line sits in the middle, never on an edge.
    final flat = kuteLineDomain([5, 5, 5, 5], const KuteIndexWindow(0, 3));
    expect(kuteLineY(5, 200, flat), closeTo(100, 1e-9));
    final zero = kuteLineDomain([0, 0, 0], const KuteIndexWindow(0, 2));
    expect(kuteLineY(0, 200, zero), closeTo(100, 1e-6));
  });

  testWidgets('a chart that takes no touches never starts a scrub',
      (tester) async {
    var starts = 0;
    await pump(tester, onScrubStart: () => starts++, interactive: false);
    final rect = tester.getRect(find.byType(KuteLineChart));
    final touch = await press(tester, rect.center);
    await touch.up();
    await tester.pumpAndSettle();
    expect(starts, 0);
    expect(find.byType(KuteScrubCard), findsNothing);
  });
}
