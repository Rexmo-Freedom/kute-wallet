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
import 'package:kute/screens/shared/charts/kute_chart_time_axis.dart';
import 'package:kute/screens/shared/charts/kute_chart_viewport.dart';
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The chart leading the Statistics tab: the venue's P&L series from the
/// range's start, the headline and its change, the colour of the sign,
/// the dashed baseline, the range pills and a scrub that writes the header.
void main() {
  final now = DateTime.utc(2026, 10, 12, 12);

  /// Two years of observations ending now. Each range starts on the
  /// observation at or before its start: 1D on 110 (−5), 1W on 90 (+15),
  /// 1M on 120 (−15), 3M on 60 (+45), YTD on 100 (+5), 1Y on 80 (+25),
  /// ALL on the first point, 0 (+105).
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

  Future<void> pump(WidgetTester tester,
      {PortfolioPerformance? data,
      bool hidden = false,
      double textScale = 1,
      PortfolioPerformanceVenue venue =
          PortfolioPerformanceVenue.predictions}) async {
    tester.view.physicalSize = const Size(390, 844);
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
          theme:
              ThemeData(fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!),
          home: Scaffold(
            body: ListView(children: [
              PortfolioPnlChart(venue: venue, data: data ?? series(), now: now),
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

  PnlBaselinePainter baseline(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((p) => p.painter)
      .whereType<PnlBaselinePainter>()
      .single;

  Future<void> pick(WidgetTester tester, String range) async {
    await tester.tap(find.text(range));
    await tester.pumpAndSettle();
  }

  Future<TestGesture> press(WidgetTester tester, Offset at) async {
    final g = await tester.startGesture(at);
    await tester.pump(const Duration(milliseconds: 600));
    return g;
  }

  testWidgets(
      'opens on 1M: the P&L as the headline, the change over the month '
      'under it, the line from the month\'s start in the colour of its sign',
      (tester) async {
    await pump(tester);
    expect(find.text('Profit and loss'), findsOneWidget);
    expect(headline(tester), r'+$105.00');
    final change = changes(tester).single;
    expect(change.label, r'−$15.00 past 1m');
    expect(change.direction, -1);
    // The baseline (120, the last point before the month began), then
    // every point since.
    expect(chart(tester).values, [120, 90, 110, 95, 105]);
    expect(chart(tester).lineColor, AppColors.marketDown);
    expect(chart(tester).zoomable, isFalse);
    expect(baseline(tester).baseline, 120);
    // The range pills every chart shares, 1M picked.
    for (final label in ['1D', '1W', '1M', '3M', 'YTD', '1Y', 'ALL']) {
      expect(find.text(label), findsOneWidget);
    }
    // The plot keeps its height; the time axis sits under it, ending now.
    expect(tester.getSize(find.byType(KuteLineChart)).height,
        closeTo(kPnlChartPlotHeight * 844 / 932, 1));
    expect(find.byType(KuteTimeAxis), findsOneWidget);
    expect(find.text('Now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each range starts on its own baseline; colour follows sign',
      (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    await pump(tester);
    final cases = <String, (double, List<double>, String?, Color)>{
      '1D': (110, [110, 95, 105], r'−$5.00 past 1d', AppColors.marketDown),
      '1W': (90, [90, 110, 95, 105], r'+$15.00 past 1w', AppColors.marketUp),
      '3M': (
        60,
        [60, 120, 90, 110, 95, 105],
        r'+$45.00 past 3m',
        AppColors.marketUp
      ),
      'YTD': (
        100,
        [100, 60, 120, 90, 110, 95, 105],
        r'+$5.00',
        AppColors.marketUp
      ),
      '1Y': (
        80,
        [80, 100, 60, 120, 90, 110, 95, 105],
        r'+$25.00 past 1y',
        AppColors.marketUp
      ),
      'ALL': (
        0,
        [0, 50, 80, 100, 60, 120, 90, 110, 95, 105],
        null,
        AppColors.marketUp
      ),
    };
    var from = '1M';
    for (final entry in cases.entries) {
      await pick(tester, entry.key);
      final (start, values, change, color) = entry.value;
      expect(chart(tester).values, values, reason: entry.key);
      expect(chart(tester).lineColor, color, reason: entry.key);
      expect(baseline(tester).baseline, start, reason: entry.key);
      // The headline is the account's P&L whatever the range.
      expect(headline(tester), r'+$105.00');
      if (change == null) {
        // ALL: the headline is the change.
        expect(changes(tester), isEmpty, reason: entry.key);
      } else {
        expect(changes(tester).single.label, change, reason: entry.key);
      }
      expect(events.last.$1, 'portfolio_performance_range_changed');
      expect(events.last.$2,
          {'venue': 'predictions', 'from': from, 'to': entry.key});
      from = entry.key;
    }
    // The picked pill again sends nothing.
    events.clear();
    await pick(tester, 'ALL');
    expect(events, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a long press scrubs: the header writes the point under the finger, '
      'its change from the range\'s start and its date, then snaps back',
      (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    await pump(tester);
    final rect = tester.getRect(find.byType(KuteLineChart));
    // Five points across the width: a quarter of the way is the second,
    // the October 1 observation.
    final touch = await press(
        tester, Offset(rect.left + rect.width * 0.25, rect.center.dy - 10));
    await tester.pump(const Duration(milliseconds: 150));
    expect(headline(tester), r'+$90.00');
    final scrubbed = find.byKey(const ValueKey('statistics-pnl-scrub'));
    expect(scrubbed, findsOneWidget);
    expect(changes(tester).single.label, r'−$30.00');
    expect(changes(tester).single.direction, -1);
    expect(find.descendant(of: scrubbed, matching: find.text('Oct 1, 2026')),
        findsOneWidget);
    // The hairline rides the line; no scrub card of the chart's own (the
    // header is the card).
    expect(find.byType(KuteScrubCard), findsNothing);
    // The line keeps the range's colour under the finger.
    expect(chart(tester).lineColor, AppColors.marketDown);
    expect(events.where((e) => e.$1 == 'portfolio_performance_chart_scrubbed')
        .single.$2, {'venue': 'predictions', 'range': '1M'});

    // Sliding on writes the next point.
    await touch.moveBy(Offset(rect.width * 0.25, 0));
    await tester.pump(const Duration(milliseconds: 150));
    expect(headline(tester), r'+$110.00');
    expect(changes(tester).single.label, r'−$10.00');
    // One event for the gesture.
    expect(
        events.where((e) => e.$1 == 'portfolio_performance_chart_scrubbed').length,
        1);

    // Released: the headline and the month's change come back.
    await touch.up();
    await tester.pumpAndSettle();
    expect(headline(tester), r'+$105.00');
    expect(scrubbed, findsNothing);
    expect(changes(tester).single.label, r'−$15.00 past 1m');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a day\'s scrub writes the time of day', (tester) async {
    await pump(tester);
    await pick(tester, '1D');
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

  testWidgets('a loss reads in the down colour; a flat range in the accent',
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
    // 1M: from 10 down to −20.
    expect(chart(tester).lineColor, AppColors.marketDown);
    expect(changes(tester).single.label, r'−$30.00 past 1m');
    // 1D: flat at −20, the accent, no sign.
    await pick(tester, '1D');
    expect(chart(tester).lineColor, AppColorsExtension.light().accent);
    expect(changes(tester).single.label, r'$0.00 past 1d');
    expect(changes(tester).single.direction, 0);
  });

  testWidgets('hidden balances mask the headline and drop the change',
      (tester) async {
    await pump(tester, hidden: true);
    expect(headline(tester), '••••••');
    expect(changes(tester), isEmpty);
    expect(find.textContaining(r'$'), findsNothing);
    // The line itself still draws, in its colour.
    expect(chart(tester).values.length, 5);
    expect(chart(tester).lineColor, AppColors.marketDown);
    final rect = tester.getRect(find.byType(KuteLineChart));
    final touch = await press(
        tester, Offset(rect.left + rect.width * 0.25, rect.center.dy - 10));
    await tester.pump(const Duration(milliseconds: 150));
    expect(headline(tester), '••••••');
    expect(find.textContaining(r'$'), findsNothing);
    await touch.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the baseline is drawn where the line puts that value',
      (tester) async {
    await pump(tester);
    final painter = baseline(tester);
    final values = chart(tester).values;
    // On the shared scale the start value's row is inside the plot and
    // sits between the line's high and low.
    final plot = tester.getSize(find.byType(KuteLineChart));
    final h = plot.height - kKuteTimeAxisHeight;
    final d = kuteLineDomain(
        values, KuteIndexWindow(0, (values.length - 1).toDouble()));
    final y = kuteLineY(painter.baseline, h, d);
    // (1M starts on the month's high, so the baseline is its row.)
    expect(y,
        greaterThanOrEqualTo(
            kuteLineY(values.reduce((a, b) => a > b ? a : b), h, d)));
    expect(y,
        lessThanOrEqualTo(
            kuteLineY(values.reduce((a, b) => a < b ? a : b), h, d)));
    expect(y, inInclusiveRange(0, h));
  });

  testWidgets('fits accessibility text without squeezing the plot',
      (tester) async {
    await pump(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(KuteLineChart)).height,
        closeTo(kPnlChartPlotHeight * 844 / 932, 1));
    await pick(tester, 'ALL');
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
