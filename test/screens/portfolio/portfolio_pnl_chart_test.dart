import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/analytics/components/chart.dart'
    show ChartChangeText;
import 'package:kute/screens/portfolio/components/portfolio_pnl_chart.dart';
import 'package:kute/screens/shared/charts/kute_chart_crosshair.dart';
import 'package:kute/screens/shared/charts/kute_chart_range_pills.dart';
import 'package:kute/screens/shared/charts/kute_chart_time_axis.dart';
import 'package:kute/screens/shared/charts/kute_chart_viewport.dart';
import 'package:kute/screens/shared/charts/kute_chart_zoom_hint.dart';
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The chart leading the Statistics tab: the venue's whole P&L history
/// from zero, the headline, the colour of the sign, the dashed baseline,
/// no range row, the market charts' pinch and pan, and a scrub that
/// writes the header.
void main() {
  final now = DateTime.utc(2026, 10, 12, 12);

  /// Two years of observations ending now, from zero (+105 in all).
  PortfolioPerformance series() => PortfolioPerformance(
        points: [
          PortfolioPnlPoint(timestamp: DateTime.utc(2024, 6, 1), pnlUsd: 0),
          PortfolioPnlPoint(timestamp: DateTime.utc(2025, 1, 1), pnlUsd: 50),
          PortfolioPnlPoint(timestamp: DateTime.utc(2025, 10, 1), pnlUsd: 80),
          PortfolioPnlPoint(timestamp: DateTime.utc(2026, 1, 1), pnlUsd: 100),
          PortfolioPnlPoint(timestamp: DateTime.utc(2026, 7, 1), pnlUsd: 60),
          PortfolioPnlPoint(timestamp: DateTime.utc(2026, 9, 1), pnlUsd: 120),
          PortfolioPnlPoint(timestamp: DateTime.utc(2026, 10, 1), pnlUsd: 90),
          PortfolioPnlPoint(
              timestamp: DateTime.utc(2026, 10, 11, 12), pnlUsd: 110),
          PortfolioPnlPoint(
              timestamp: DateTime.utc(2026, 10, 11, 18), pnlUsd: 95),
          PortfolioPnlPoint(timestamp: now, pnlUsd: 105),
        ],
        totalPnlUsd: 105,
        asOf: now,
        sourceLabel: 'Polymarket',
        basisLabel: 'Economic P&L',
        coverageLabel: 'All time',
      );

  /// Sixty daily observations ending now, from zero: enough points to
  /// pinch well in.
  PortfolioPerformance daily() => PortfolioPerformance(
        points: [
          for (var i = 0; i < 60; i++)
            PortfolioPnlPoint(
                timestamp: now.subtract(Duration(days: 59 - i)),
                pnlUsd: i * 2.0),
        ],
        totalPnlUsd: 118,
        asOf: now,
        sourceLabel: 'Hyperliquid',
        basisLabel: 'Reported account P&L',
        coverageLabel: 'All time',
      );

  Future<void> pump(WidgetTester tester,
      {PortfolioPerformance? data,
      bool hidden = false,
      double textScale = 1,
      Size size = const Size(390, 844),
      bool reduceMotion = false,
      String? eventVenue,
      PortfolioPerformanceVenue venue =
          PortfolioPerformanceVenue.predictions}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: '',
            reviewDone: true,
            balancePrivacy: hidden ? 1 : 0))),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
              fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(textScale),
                  disableAnimations: reduceMotion),
              child: child!),
          home: Scaffold(
            body: ListView(children: [
              PortfolioPnlChart(
                  venue: venue,
                  data: data ?? series(),
                  now: now,
                  eventVenue: eventVenue),
            ]),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  String headline(WidgetTester tester) => tester
      .widget<RollingNumberText>(
          find.byKey(const ValueKey('statistics-pnl-headline')))
      .text;

  KuteLineChart chart(WidgetTester tester) =>
      tester.widget<KuteLineChart>(find.byType(KuteLineChart));

  /// The change rows on screen (the hidden placeholder aside).
  List<ChartChangeText> changes(WidgetTester tester) => tester
      .widgetList<ChartChangeText>(find.byType(ChartChangeText))
      .where((w) => w.label != '+0')
      .toList();

  Iterable<PnlBaselinePainter> baselines(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((p) => p.painter)
      .whereType<PnlBaselinePainter>();

  KuteTimeAxis axis(WidgetTester tester) =>
      tester.widget<KuteTimeAxis>(find.byType(KuteTimeAxis));

  /// The window the baseline is drawn through: the one on screen.
  KuteIndexWindow window(WidgetTester tester) =>
      baselines(tester).single.window!;

  Future<TestGesture> press(WidgetTester tester, Offset at) async {
    final g = await tester.startGesture(at);
    await tester.pump(const Duration(milliseconds: 600));
    return g;
  }

  /// Two fingers from [gap] apart to [to] apart about the plot's centre.
  Future<void> pinch(WidgetTester tester,
      {double gap = 40, double to = 160}) async {
    final rect = tester.getRect(find.byType(KuteLineChart));
    final c = Offset(rect.center.dx, rect.center.dy - 20);
    final a = await tester.startGesture(c - Offset(gap / 2, 0), pointer: 7);
    final b = await tester.startGesture(c + Offset(gap / 2, 0), pointer: 8);
    await tester.pump(const Duration(milliseconds: 16));
    const steps = 6;
    final d = (to - gap) / 2 / steps;
    for (var i = 0; i < steps; i++) {
      await a.moveBy(Offset(-d, 0));
      await b.moveBy(Offset(d, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
  }

  testWidgets(
      'opens on the whole history: the P&L as the headline, no range row, '
      'the line from zero in the colour of its sign', (tester) async {
    await pump(tester);
    expect(find.text('Profit and loss'), findsOneWidget);
    expect(headline(tester), r'+$105.00');
    // ALL: the headline is the change, the row under it is empty.
    expect(changes(tester), isEmpty);
    expect(chart(tester).values, [0, 50, 80, 100, 60, 120, 90, 110, 95, 105]);
    expect(chart(tester).lineColor, AppColors.marketUp);
    expect(chart(tester).zoomable, isTrue);
    expect(baselines(tester).single.baseline, 0);
    // The whole series on screen.
    expect(window(tester), const KuteIndexWindow(0, 9));
    // No range chips of any kind.
    expect(find.byType(KuteRangePills), findsNothing);
    expect(find.byType(KuteRangePill), findsNothing);
    for (final label in ['1D', '1W', '1M', '3M', 'YTD', '1Y', 'ALL']) {
      expect(find.text(label), findsNothing);
    }
    // The plot keeps its height; the time axis sits under it, from the
    // first observation to now.
    expect(tester.getSize(find.byType(KuteLineChart)).height,
        closeTo(kPnlChartPlotHeight * 844 / 932, 1));
    expect(axis(tester).end, 'Now');
    expect(axis(tester).start, contains('2024'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a pinch zooms the time window in on the newest point; a drag then '
      'pans it back in time, the time axis following', (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    await pump(tester, data: daily(), venue: PortfolioPerformanceVenue.trading);
    final whole = window(tester);
    expect(whole, const KuteIndexWindow(0, 59));
    final wholeStart = axis(tester).start;

    await pinch(tester);
    final zoomed = window(tester);
    // Fingers four times as far apart: a quarter of the span, still
    // ending on the newest point.
    expect(zoomed.span, closeTo(whole.span / 4, 1.5));
    expect(zoomed.end, whole.end);
    expect(axis(tester).end, 'Now');
    expect(axis(tester).start, isNot(wholeStart));
    // The figures do not move with the window.
    expect(headline(tester), r'+$118.00');
    expect(changes(tester), isEmpty);

    // One finger sideways pans once zoomed: right walks back in time.
    await tester.drag(find.byType(KuteLineChart), const Offset(120, 0));
    await tester.pumpAndSettle();
    final panned = window(tester);
    expect(panned.span, closeTo(zoomed.span, 1e-6));
    expect(panned.end, lessThan(zoomed.end));
    expect(axis(tester).end, isNot('Now'));

    // And back to the live edge, where it stops.
    await tester.drag(find.byType(KuteLineChart), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(window(tester).end, whole.end);
    expect(axis(tester).end, 'Now');

    // Zoom and pan send nothing, as on the market charts; the range event
    // is gone.
    expect(events, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('at the whole history a sideways drag does not move the window',
      (tester) async {
    await pump(tester, data: daily());
    await tester.drag(find.byType(KuteLineChart), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(window(tester), const KuteIndexWindow(0, 59));
    expect(axis(tester).end, 'Now');
  });

  testWidgets('another series (the toggle) starts on the whole history again',
      (tester) async {
    await pump(tester, data: daily(), eventVenue: 'all');
    await pinch(tester);
    expect(window(tester).span, lessThan(59));
    await pump(tester, data: daily(), eventVenue: 'hyperliquid');
    expect(window(tester), const KuteIndexWindow(0, 59));
  });

  testWidgets(
      'a long press scrubs: the header writes the point under the finger, '
      'its change from the line\'s start and its date, then snaps back',
      (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    await pump(tester);
    final rect = tester.getRect(find.byType(KuteLineChart));
    // Ten points across the width: a quarter of the way is the third,
    // the October 1, 2025 observation.
    final touch = await press(
        tester, Offset(rect.left + rect.width * 0.25, rect.center.dy - 10));
    await tester.pump(const Duration(milliseconds: 150));
    expect(headline(tester), r'+$80.00');
    final scrubbed = find.byKey(const ValueKey('statistics-pnl-scrub'));
    expect(scrubbed, findsOneWidget);
    expect(changes(tester).single.label, r'+$80.00');
    expect(changes(tester).single.direction, 1);
    expect(find.descendant(of: scrubbed, matching: find.text('Oct 1, 2025')),
        findsOneWidget);
    // The hairline rides the line; no scrub card of the chart's own (the
    // header is the card).
    expect(find.byType(KuteScrubCard), findsNothing);
    expect(chart(tester).lineColor, AppColors.marketUp);
    // Scrubbing never moves the window.
    expect(window(tester), const KuteIndexWindow(0, 9));
    expect(events.where((e) => e.$1 == 'portfolio_performance_chart_scrubbed')
        .single.$2, {'venue': 'predictions'});

    // Sliding on writes the next point.
    await touch.moveBy(Offset(rect.width * 0.33, 0));
    await tester.pump(const Duration(milliseconds: 150));
    expect(headline(tester), r'+$120.00');
    expect(changes(tester).single.label, r'+$120.00');
    // One event for the gesture.
    expect(
        events
            .where((e) => e.$1 == 'portfolio_performance_chart_scrubbed')
            .length,
        1);

    // Released: the headline comes back, the row empties.
    await touch.up();
    await tester.pumpAndSettle();
    expect(headline(tester), r'+$105.00');
    expect(scrubbed, findsNothing);
    expect(changes(tester), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zoomed in, a scrub reads the points of the window on screen',
      (tester) async {
    await pump(tester, data: daily());
    await pinch(tester);
    final w = window(tester);
    final rect = tester.getRect(find.byType(KuteLineChart));
    final touch =
        await press(tester, Offset(rect.left + 1, rect.center.dy - 10));
    await tester.pump(const Duration(milliseconds: 150));
    // The window's first point, not the series' first.
    final i = w.start.round();
    expect(i, greaterThan(30));
    expect(headline(tester), '+\$${(i * 2).toStringAsFixed(2)}');
    await touch.up();
    await tester.pumpAndSettle();
    // The window is where the pinch left it.
    expect(window(tester), w);
  });

  testWidgets('a scrub over hours writes the time of day', (tester) async {
    await pump(
        tester,
        data: PortfolioPerformance(
            points: [
              PortfolioPnlPoint(
                  timestamp: DateTime.utc(2026, 10, 11, 12), pnlUsd: 0),
              PortfolioPnlPoint(
                  timestamp: DateTime.utc(2026, 10, 11, 18), pnlUsd: 95),
              PortfolioPnlPoint(timestamp: now, pnlUsd: 105),
            ],
            totalPnlUsd: 105,
            sourceLabel: 'Polymarket',
            basisLabel: 'Economic P&L',
            coverageLabel: 'All time'));
    final rect = tester.getRect(find.byType(KuteLineChart));
    // Three points: the middle one is yesterday 18:00 UTC.
    final touch =
        await press(tester, Offset(rect.center.dx, rect.center.dy - 10));
    await tester.pump(const Duration(milliseconds: 150));
    expect(headline(tester), r'+$95.00');
    final at = DateTime.utc(2026, 10, 11, 18).toLocal();
    final hour = at.hour.toString().padLeft(2, '0');
    final minute = at.minute.toString().padLeft(2, '0');
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('statistics-pnl-scrub')),
            matching: find.textContaining('$hour:$minute')),
        findsOneWidget);
    await touch.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a loss reads in the down colour; a flat line in the accent',
      (tester) async {
    await pump(
        tester,
        data: PortfolioPerformance(
            points: [
              PortfolioPnlPoint(
                  timestamp: now.subtract(const Duration(days: 40)),
                  pnlUsd: 10),
              PortfolioPnlPoint(
                  timestamp: now.subtract(const Duration(days: 5)),
                  pnlUsd: -20),
              PortfolioPnlPoint(timestamp: now, pnlUsd: -20),
            ],
            totalPnlUsd: -20,
            sourceLabel: 'Hyperliquid',
            basisLabel: 'Reported account P&L',
            coverageLabel: 'All time'),
        venue: PortfolioPerformanceVenue.trading);
    expect(headline(tester), r'−$20.00');
    expect(
        tester
            .widget<RollingNumberText>(
                find.byKey(const ValueKey('statistics-pnl-headline')))
            .style
            .color,
        AppColors.marketDown);
    // From zero (the day before the first observation) down to −20.
    expect(chart(tester).values, [0, 10, -20, -20]);
    expect(chart(tester).lineColor, AppColors.marketDown);
    expect(changes(tester), isEmpty);

    await pump(
        tester,
        data: PortfolioPerformance(
            points: [
              PortfolioPnlPoint(
                  timestamp: now.subtract(const Duration(days: 5)), pnlUsd: 0),
              PortfolioPnlPoint(timestamp: now, pnlUsd: 0),
            ],
            totalPnlUsd: 0,
            sourceLabel: 'Hyperliquid',
            basisLabel: 'Reported account P&L',
            coverageLabel: 'All time'),
        venue: PortfolioPerformanceVenue.trading);
    expect(chart(tester).lineColor, AppColorsExtension.light().accent);
    // A line that never moves needs no baseline.
    expect(baselines(tester), isEmpty);
  });

  testWidgets('hidden balances mask the headline and drop the change',
      (tester) async {
    await pump(tester, hidden: true);
    expect(headline(tester), '••••••');
    expect(changes(tester), isEmpty);
    expect(find.textContaining(r'$'), findsNothing);
    // The line itself still draws, in its colour.
    expect(chart(tester).values.length, 10);
    expect(chart(tester).lineColor, AppColors.marketUp);
    final rect = tester.getRect(find.byType(KuteLineChart));
    final touch = await press(
        tester, Offset(rect.left + rect.width * 0.25, rect.center.dy - 10));
    await tester.pump(const Duration(milliseconds: 150));
    expect(headline(tester), '••••••');
    expect(find.textContaining(r'$'), findsNothing);
    await touch.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'the baseline is drawn where the line puts zero, on the scale of the '
      'window on screen', (tester) async {
    await pump(tester);
    final painter = baselines(tester).single;
    final values = chart(tester).values;
    final plot = tester.getSize(find.byType(KuteLineChart));
    final h = plot.height - kKuteTimeAxisHeight;
    final d = kuteLineDomain(values, painter.window!);
    final y = kuteLineY(painter.baseline, h, d);
    // Zero is the line's low: the baseline is its row, inside the plot.
    expect(y, closeTo(kuteLineY(0, h, d), 1e-9));
    expect(y, inInclusiveRange(0, h));
    expect(
        y,
        greaterThanOrEqualTo(
            kuteLineY(values.reduce((a, b) => a > b ? a : b), h, d)));

    // Zoomed in, the painter follows the window.
    await pump(tester, data: daily());
    await pinch(tester);
    expect(baselines(tester).single.window!.span, lessThan(59));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the zoom nudge plays once on the whole history',
      (tester) async {
    KuteZoomHint.debugReset(read: () => false, write: () {});
    addTearDown(KuteZoomHint.debugReset);
    await pump(tester, data: daily());
    // Past the wait, mid-nudge: zoomed in a little on the newest point.
    await tester.pump(kKuteZoomNudgeDelay + const Duration(milliseconds: 50));
    await tester.pump(kKuteZoomNudgeDuration ~/ 2);
    expect(window(tester).span, lessThan(59));
    expect(window(tester).end, 59);
    await tester.pumpAndSettle();
    expect(window(tester), const KuteIndexWindow(0, 59));
  });

  testWidgets('under Reduce Motion nothing animates: no nudge, no morph',
      (tester) async {
    KuteZoomHint.debugReset(read: () => false, write: () {});
    addTearDown(KuteZoomHint.debugReset);
    await pump(tester, data: daily(), reduceMotion: true);
    await tester.pump(kKuteZoomNudgeDelay + const Duration(milliseconds: 50));
    await tester.pump(kKuteZoomNudgeDuration ~/ 2);
    expect(window(tester), const KuteIndexWindow(0, 59));
    expect(tester.hasRunningAnimations, isFalse);
    // A pinch lands at once.
    await pinch(tester);
    expect(window(tester).span, lessThan(59));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('fits accessibility text without squeezing the plot',
      (tester) async {
    await pump(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(KuteLineChart)).height,
        closeTo(kPnlChartPlotHeight * 844 / 932, 1));
  });

  testWidgets('375pt wide at 1.3x text: no overflow at rest, zoomed or '
      'scrubbing', (tester) async {
    await pump(tester,
        data: daily(), textScale: 1.3, size: const Size(375, 812));
    expect(tester.takeException(), isNull);
    await pinch(tester);
    expect(tester.takeException(), isNull);
    final rect = tester.getRect(find.byType(KuteLineChart));
    final touch = await press(
        tester, Offset(rect.left + rect.width * 0.5, rect.center.dy - 10));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const ValueKey('statistics-pnl-scrub')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await touch.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing published draws nothing', (tester) async {
    await pump(
        tester,
        data: const PortfolioPerformance(
            points: [],
            sourceLabel: 'Polymarket',
            basisLabel: 'Economic P&L',
            coverageLabel: 'No observations'));
    expect(find.byType(KuteLineChart), findsNothing);
    expect(find.byKey(const ValueKey('statistics-pnl-card')), findsNothing);
  });
}
