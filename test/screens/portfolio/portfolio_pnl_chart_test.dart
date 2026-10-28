import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/portfolio/components/portfolio_pnl_chart.dart';
import 'package:kute/screens/shared/charts/kute_chart_core.dart'
    show kuteMonotonePath;
import 'package:kute/screens/shared/charts/kute_chart_crosshair.dart';
import 'package:kute/screens/shared/charts/kute_chart_range_pills.dart';
import 'package:kute/screens/shared/charts/kute_chart_time_axis.dart';
import 'package:kute/screens/shared/charts/kute_chart_viewport.dart';
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The P&L chart leading the Portfolio ("P&L charts"), restyled as the
/// Balance charts were: a range row under the plot (1M to start,
/// remembered for the session), the closing P&L per bucket ending on the
/// P&L now drawn as straight segments, no scale or gridlines, a solid
/// hairline at zero, the line, its one soft fade and its solid end dot in
/// the range's result colour, a quiet change line (never a percent), the
/// scrubbed P&L written there, a calm empty state, the Balance charts'
/// pinch, and the spending account's one block (the ring row, the rows,
/// the plot).
void main() {
  // Inter loaded before any layout here (see loadAppFonts): its figures
  // change colour alone, which a font landing mid-test turns into
  // TextPainter's debugSize assertion on slow runners.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  final now = DateTime(2026, 10, 25, 17, 0);
  DateTime ago(Duration d) => now.subtract(d);

  PortfolioPerformance perf(List<(Duration, double)> obs, {double? total}) =>
      PortfolioPerformance(
        points: [
          for (final o in obs)
            PortfolioPnlPoint(timestamp: ago(o.$1), pnlUsd: o.$2),
        ],
        totalPnlUsd: total ?? (obs.isEmpty ? null : obs.last.$2),
        sourceLabel: 'Hyperliquid',
        basisLabel: 'Reported account P&L',
        coverageLabel: 'All time',
      );

  /// Zero for months, the first trade 50 days ago, up to +45, down
  /// through zero to −25, back to −6.38 now.
  PortfolioPerformance upThenDown() => perf([
        (const Duration(days: 200), 0),
        (const Duration(days: 50), 20),
        (const Duration(days: 40), 45),
        (const Duration(days: 30), 30),
        (const Duration(days: 20), -10),
        (const Duration(days: 10), -25),
        (const Duration(days: 5), -12),
        (const Duration(days: 2), 0.02),
      ], total: -6.38);

  /// Up $12.40 over the past month: 100 since long ago, 112.40 now.
  PortfolioPerformance upMonth() => perf([
        (const Duration(days: 120), 100),
        (const Duration(days: 3), 112.40),
      ]);

  group('the series', () {
    test(
        'a short lead-in at zero before the first trade, ending on the '
        'P&L now', () {
      final s = pnlSeries(upThenDown(), now);
      final first = ago(const Duration(days: 50));
      // A twelfth of the 50 days of trading before the first trade: never
      // the months of zero before it.
      expect(s.times.first, first.subtract(const Duration(days: 4, hours: 4)));
      expect(s.values.first, 0);
      expect(s.times.last, now);
      // The last point is the P&L now (the headline), not the last
      // observation.
      expect(s.values.last, -6.38);
      // Below zero is kept, never floored as a balance is.
      expect(s.values.reduce((a, b) => a < b ? a : b), -25);
    });

    test('a range longer than the history opens on the first trade', () {
      final s = pnlSeries(upThenDown(), now);
      expect(s.spanFor(BalanceRange.year), s.extent);
      expect(s.spanFor(BalanceRange.all), s.extent);
      expect(s.spanFor(BalanceRange.month), lessThan(s.extent));
    });

    test('each bucket draws its close: a swing inside one never shows', () {
      // Steady at +10 for weeks; yesterday +500 for twenty minutes.
      final spike = DateTime(2026, 10, 24, 15, 5);
      final p = PortfolioPerformance(
        points: [
          PortfolioPnlPoint(
              timestamp: ago(const Duration(days: 40)), pnlUsd: 10),
          PortfolioPnlPoint(timestamp: spike, pnlUsd: 500),
          PortfolioPnlPoint(
              timestamp: spike.add(const Duration(minutes: 20)), pnlUsd: 10),
        ],
        totalPnlUsd: 10,
        sourceLabel: 'Hyperliquid',
        basisLabel: 'Reported account P&L',
        coverageLabel: 'All time',
      );
      final s = pnlSeries(p, now);
      // The grid saw it...
      expect(s.values, contains(500));
      // ...the month's daily closes do not.
      final w =
          KuteIndexWindow(s.extent - s.spanFor(BalanceRange.month), s.extent);
      final buckets = KuteLineBuckets(strideFor: s.strideFor, phase: s.phase);
      final drawn = [
        for (final i in buckets.indicesFor(s.length, w))
          if (i >= w.start - 1e-6) s.values[i]
      ];
      expect(drawn.toSet(), {10});
    });

    test('a P&L that never left zero: the last week, flat at zero', () {
      final s = pnlSeries(
          perf([(const Duration(days: 9), 0), (Duration.zero, 0)]), now);
      expect(s.times.last.difference(s.times.first), const Duration(days: 7));
      expect(s.values.every((v) => v == 0), isTrue);
      final none = pnlSeries(perf(const []), now);
      expect(none.values.every((v) => v == 0), isTrue);
    });
  });

  group('on screen', () {
    Settings settings({int privacy = 0}) => Settings(
        currency: 'USD',
        language: 'en',
        btcFormat: 'sats',
        backup: false,
        biometricsEnabled: false,
        bitcoinElectrumNode: '',
        nodeType: '',
        reviewDone: true,
        balancePrivacy: privacy);

    Widget app(PortfolioPerformance data,
            {String? eventVenue, double textScale = 1}) =>
        ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildLightTheme(),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!),
            home: Scaffold(
              body: ListView(children: [
                PortfolioPnlChart(
                    venue: PortfolioPerformanceVenue.trading,
                    data: data,
                    now: now,
                    eventVenue: eventVenue),
              ]),
            ),
          ),
        );

    Future<void> pump(WidgetTester tester, PortfolioPerformance data,
        {int privacy = 0,
        String? eventVenue,
        double textScale = 1,
        Size size = const Size(390, 844),
        ProviderContainer? container}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final child = app(data, eventVenue: eventVenue, textScale: textScale);
      await tester.pumpWidget(container != null
          ? UncontrolledProviderScope(container: container, child: child)
          : ProviderScope(overrides: [
              settingsProvider.overrideWith(
                  (_) => SettingsModel(settings(privacy: privacy))),
            ], child: child));
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 8));
    }

    String header(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey('statistics-pnl-header')))
        .textSpan!
        .toPlainText();

    /// The coloured part of the header (the amount).
    TextSpan amountSpan(WidgetTester tester) {
      final root = tester
          .widget<Text>(find.byKey(const ValueKey('statistics-pnl-header')))
          .textSpan! as TextSpan;
      return root.children!
          .cast<TextSpan>()
          .firstWhere((s) => s.style?.fontWeight == FontWeight.w700);
    }

    String headline(WidgetTester tester) => tester
        .widget<RollingNumberText>(
            find.byKey(const ValueKey('statistics-pnl-headline')))
        .text;

    KuteLineChart chart(WidgetTester tester) =>
        tester.widget<KuteLineChart>(find.byType(KuteLineChart));

    dynamic painter(WidgetTester tester) => [
          for (final cp in tester.widgetList<CustomPaint>(find.descendant(
              of: find.byType(KuteLineChart),
              matching: find.byType(CustomPaint))))
            if (cp.painter.runtimeType.toString() == '_KuteLinePainter')
              cp.painter
        ].single;

    KuteIndexWindow window(WidgetTester tester) =>
        painter(tester).window as KuteIndexWindow;

    Future<void> pinch(WidgetTester tester,
        {double from = 60, double to = 180, int pointer = 10}) async {
      final rect = tester.getRect(find.byType(KuteLineChart));
      final c = rect.center;
      final a =
          await tester.startGesture(c - Offset(from / 2, 0), pointer: pointer);
      final b = await tester.startGesture(c + Offset(from / 2, 0),
          pointer: pointer + 1);
      await tester.pump();
      const steps = 8;
      final d = (to - from) / 2 / steps;
      for (var i = 0; i < steps; i++) {
        await a.moveBy(Offset(-d, 0));
        await b.moveBy(Offset(d, 0));
        await tester.pump();
      }
      await a.up();
      await b.up();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets(
        'the range row: 1W to ALL under the plot, 1M to start, a '
        'tap sets the window and the change line', (tester) async {
      final s = pnlSeries(upMonth(), now);
      await pump(tester, upMonth());
      final pills = tester.widget<KuteRangePills>(find.byType(KuteRangePills));
      expect(pills.labels, ['1W', '1M', '3M', '1Y', 'ALL']);
      expect(pills.selectedIndex, BalanceRange.month.index);
      // Under the plot.
      expect(tester.getTopLeft(find.byType(KuteRangePills)).dy,
          greaterThan(tester.getBottomLeft(find.byType(KuteLineChart)).dy));
      expect(chart(tester).defaultSpan, s.spanFor(BalanceRange.month));
      expect(header(tester), r'+$12.40 past month');

      await tester.tap(find.text('1W'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(chart(tester).defaultSpan, s.spanFor(BalanceRange.week));
      expect(header(tester), r'+$12.40 past week');

      await tester.tap(find.text('ALL'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(chart(tester).defaultSpan, s.extent);
      // From the lead-in's zero.
      expect(header(tester), r'+$112.40 all time');
      await settle(tester);
    });

    testWidgets('the range is remembered for the session', (tester) async {
      final container = ProviderContainer(overrides: [
        settingsProvider.overrideWith((_) => SettingsModel(settings())),
      ]);
      addTearDown(container.dispose);
      await pump(tester, upMonth(), container: container);
      await tester.tap(find.text('3M'));
      await tester.pump(const Duration(milliseconds: 300));
      // Built afresh (the screen left and opened again, another series).
      await tester.pumpWidget(const SizedBox.shrink());
      await pump(tester, upThenDown(), container: container);
      expect(
          tester
              .widget<KuteRangePills>(find.byType(KuteRangePills))
              .selectedIndex,
          BalanceRange.threeMonths.index);
      expect(container.read(pnlChartRangeProvider), BalanceRange.threeMonths);
      await settle(tester);
    });

    testWidgets(
        'the look: straight segments in the result colour, one soft fade '
        'under the line, a solid hairline at zero kept on the scale, a '
        'solid end dot, no scale', (tester) async {
      await pump(tester, upMonth());
      final c = chart(tester);
      // Up over the month: the up colour, never the neutral chart colour.
      expect(c.lineColor, AppColors.marketUp);
      expect(c.straight, isTrue);
      expect(c.stepped, isFalse);
      expect(c.filledEndpoint, isTrue);
      expect(c.showScale, isFalse);
      expect(c.scaleLabel, isNull);
      expect(c.startBaseline, isFalse);
      expect(c.baselineAt, 0);
      expect(c.solidBaseline, isTrue);
      expect(c.showFill, isTrue);
      // One fade in the line's colour, not a two-colour fill.
      expect(c.fillAboveColor, isNull);
      expect(c.fillBelowColor, isNull);
      final p = painter(tester);
      expect(p.straight, isTrue);
      expect(p.solidBaseline, isTrue);
      expect(p.filledEndpoint, isTrue);
      expect(p.lineColor, AppColors.marketUp);
      expect(p.fillAbove, isNull);
      expect(p.fillBelow, isNull);
      expect(p.baseline, 0);
      expect(p.includeBaseline, isTrue);
      expect(p.showScale, isFalse);
      // The P&L sits at +100..+112 in the month: zero is still on the
      // scale, so the baseline spans the plot.
      final d = kuteLineDomain(c.values, window(tester),
          indices: p.indices as List<int>, include: 0);
      expect(d.minY, lessThanOrEqualTo(0));
      expect(d.maxY, greaterThanOrEqualTo(112.4));
      await settle(tester);
    });

    test('straight segments: through the points and nothing else', () {
      // A flat stretch, a jump, a flat stretch: a curve through these
      // would swing above the top and below the bottom.
      const pts = [
        Offset(0, 80),
        Offset(40, 80),
        Offset(50, 10),
        Offset(90, 10),
        Offset(100, 60),
      ];
      final path = kuteStraightPath(pts);
      // Never past the box the points span: no high or low invented.
      final b = path.getBounds();
      expect(b.top, 10);
      expect(b.bottom, 80);
      expect(b.left, 0);
      expect(b.right, 100);
      // Its length is the straight segments' and nothing more.
      var expected = 0.0;
      for (var i = 1; i < pts.length; i++) {
        expected += (pts[i] - pts[i - 1]).distance;
      }
      final length = path
          .computeMetrics()
          .fold<double>(0, (sum, m) => sum + m.length);
      expect(length, closeTo(expected, 0.01));
      // The monotone curve the chart drew before is longer: it bends.
      final curve = kuteMonotonePath(pts)
          .computeMetrics()
          .fold<double>(0, (sum, m) => sum + m.length);
      expect(curve, greaterThan(expected + 0.5));
    });

    testWidgets(
        'the result colour: red when the range fell, green when it rose, '
        'the neutral grey when flat; the fade under the line in it',
        (tester) async {
      // Down over the month (30 to −6.38).
      await pump(tester, upThenDown());
      expect(chart(tester).lineColor, AppColors.marketDown);
      final p = painter(tester);
      final values = chart(tester).values;
      final w = window(tester);
      final indices = p.indices as List<int>;
      final boundary = tester.renderObject<RenderRepaintBoundary>(find
          .descendant(
              of: find.byType(KuteLineChart),
              matching: find.byType(RepaintBoundary))
          .first);
      final size = boundary.size;
      final d = kuteLineDomain(values, w, indices: indices, include: 0);
      final bytes = (await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return data!;
      }))!;
      final width = size.width.round();
      // Under the line, half way to the bottom of the plot, where the line
      // is above zero: the fade is red there too (one colour, not green
      // above zero).
      final i = indices.firstWhere(
          (i) => i >= w.start && i <= w.end && values[i] > 10);
      final x = w.xOf(i.toDouble(), size.width);
      final yLine = kuteLineY(values[i], size.height, d);
      final o = (((yLine + size.height) / 2).round() * width + x.round()) * 4;
      expect(bytes.getUint8(o + 3), greaterThan(0), reason: 'faded');
      expect(bytes.getUint8(o), greaterThan(bytes.getUint8(o + 1)),
          reason: 'red under the line');
      await settle(tester);

      // Up over the month.
      await pump(tester, upMonth());
      expect(chart(tester).lineColor, AppColors.marketUp);
      await settle(tester);

      // Flat over the month (8 since two months ago).
      await pump(
          tester,
          perf([
            (const Duration(days: 120), 5),
            (const Duration(days: 60), 8),
          ]));
      expect(chart(tester).lineColor, AppColorsExtension.light().textTertiary);
      expect(pnlResultColor(AppColorsExtension.light(), 0),
          AppColorsExtension.light().textTertiary);
      expect(pnlResultColor(AppColorsExtension.light(), -0.01),
          AppColors.marketDown);
      expect(pnlResultColor(AppColorsExtension.light(), 0.01),
          AppColors.marketUp);
      await settle(tester);
    });

    testWidgets(
        'the one block: the ring, then the caption, figure and change line '
        'beside it, the pair at the end, the rows between, then the plot',
        (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsProvider.overrideWith((_) => SettingsModel(settings())),
        ],
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildLightTheme(),
            home: Scaffold(
              body: ListView(children: [
                PortfolioPnlChart(
                  venue: null,
                  data: upThenDown(),
                  now: now,
                  leading: const SizedBox(
                      key: ValueKey('ring'), width: 50, height: 50),
                  trailing: const SizedBox(
                      key: ValueKey('pair'), width: 100, height: 30),
                  middle: const SizedBox(
                      key: ValueKey('rows'), width: 10, height: 120),
                ),
              ]),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      Rect at(String key) => tester.getRect(find.byKey(ValueKey(key)));
      final ring = at('ring');
      final pair = at('pair');
      final rows = at('rows');
      final figure = at('statistics-pnl-headline');
      final line = at('statistics-pnl-header');
      final plot = tester.getRect(find.byType(KuteLineChart));
      // One row: the ring, the figure and its change line, the pair.
      expect(figure.left, greaterThan(ring.right));
      expect(line.left, greaterThan(ring.right));
      expect(line.top, greaterThan(figure.bottom - 1));
      expect(pair.left, greaterThan(figure.right));
      expect(find.text('Profit and loss'), findsOneWidget);
      // The rows under it, the plot under them, the ranges under that.
      expect(rows.top, greaterThan(line.bottom));
      final plotTop = tester
          .getRect(find
              .descendant(
                  of: find.byType(KuteLineChart),
                  matching: find.byType(RepaintBoundary))
              .first)
          .top;
      expect(plotTop, greaterThan(rows.bottom));
      expect(tester.getTopLeft(find.byType(KuteRangePills)).dy,
          greaterThan(plot.bottom - 1));
      // The plot keeps its height under the rows.
      expect(plot.bottom - plotTop, greaterThan(150));
      await settle(tester);
    });

    testWidgets('the change line: up, down, no change, never a percent',
        (tester) async {
      await pump(tester, upThenDown());
      await tester.tap(find.text('1W'));
      await tester.pump(const Duration(milliseconds: 300));
      // −25 a week ago to −6.38 now: +18.62.
      expect(header(tester), r'+$18.62 past week');
      expect(amountSpan(tester).style!.color, AppColors.marketUp);

      // A month: +30 to −6.38.
      await tester.tap(find.text('1M'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(header(tester), '−\$36.38 past month');
      expect(amountSpan(tester).style!.color, AppColors.marketDown);
      // The P&L went from +30 to below zero: never "−121.3%".
      expect(find.textContaining('%'), findsNothing);
      // The hero is the P&L now, in the down colour.
      expect(headline(tester), '−\$6.38');
      expect(
          tester
              .widget<RollingNumberText>(
                  find.byKey(const ValueKey('statistics-pnl-headline')))
              .style
              .color,
          AppColors.marketDown);

      await pump(
          tester,
          perf([
            (const Duration(days: 90), 25),
            (const Duration(days: 60), 40),
          ]));
      expect(header(tester), 'No change in the past month');
      expect(find.textContaining('%'), findsNothing);

      // Up from a base: still no percent.
      await pump(tester, upMonth());
      expect(header(tester), r'+$12.40 past month');
      expect(find.textContaining('%'), findsNothing);
      await settle(tester);
    });

    testWidgets(
        'a scrub writes the P&L under the finger and its moment in '
        'the header, with no card; release puts the change back',
        (tester) async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      await pump(tester, upThenDown());
      final rect = tester.getRect(find.byType(KuteLineChart));
      final touch =
          await tester.startGesture(rect.centerRight.translate(-2, 0));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 150));
      expect(header(tester), startsWith('−\$6.38 · '));
      expect(header(tester), contains('Oct 25'));
      expect(amountSpan(tester).style!.color, AppColors.marketDown);
      expect(find.byType(KuteScrubCard), findsNothing);
      // The hero stays the P&L now.
      expect(headline(tester), '−\$6.38');

      await touch.moveTo(rect.centerLeft.translate(4, 0));
      await tester.pump(const Duration(milliseconds: 150));
      // A month back: +30, in the up colour.
      expect(header(tester), startsWith(r'+$30.00 · Sep '));
      expect(amountSpan(tester).style!.color, AppColors.marketUp);
      await touch.up();
      await tester.pump(const Duration(milliseconds: 150));
      expect(header(tester), '−\$36.38 past month');
      expect(
          events.where((e) => e.$1 == 'portfolio_performance_chart_scrubbed'),
          hasLength(1));
      await settle(tester);
    });

    testWidgets('nothing traded: a calm flat line at zero and one sentence',
        (tester) async {
      for (final data in [
        perf(const []),
        perf([(const Duration(days: 9), 0), (Duration.zero, 0)]),
      ]) {
        await pump(tester, data);
        expect(
            find.text(
                'Your profit and loss shows here once you trade or predict'),
            findsOneWidget);
        expect(chart(tester).showFill, isFalse);
        expect(chart(tester).values.every((v) => v == 0), isTrue);
        expect(chart(tester).baselineAt, 0);
        expect(header(tester).trim(), isEmpty);
        expect(find.byType(KuteRangePills), findsOneWidget);
      }
      await settle(tester);
    });

    testWidgets('balances hidden: dots for every figure', (tester) async {
      await pump(tester, upThenDown(), privacy: 1);
      expect(header(tester), '•••••• past month');
      expect(headline(tester), '••••••');
      expect(find.textContaining(r'$'), findsNothing);
      await settle(tester);
    });

    testWidgets(
        'the Balance charts\' pinch: around the fingers, clamped, '
        're-bucketed; a range tap puts the view back', (tester) async {
      final s = pnlSeries(upThenDown(), now);
      await pump(tester, upThenDown());
      final c = chart(tester);
      expect(c.zoomAroundFingers, isTrue);
      expect(c.minSpan, s.minSpan);
      expect(c.buckets, isNotNull);
      expect(c.resetViewOnLengthChange, isFalse);
      expect(c.animateChanges, isFalse);
      expect(c.timeAxis, isNotNull);
      final before = window(tester);
      final stride = s.strideFor(before.span);

      // Fingers ten times as far apart: three days of the month, hourly.
      await pinch(tester, from: 20, to: 200);
      final zoomed = window(tester);
      expect(zoomed.span, closeTo(before.span / 10, before.span * 0.02));
      // Finer buckets for the narrower window.
      expect(s.strideFor(zoomed.span), lessThan(stride));
      // Around the fingers in the middle: no longer ending now.
      expect(zoomed.end, lessThan(before.end));
      expect(header(tester), contains(' – '));

      // Pinched all the way in: never under four hours.
      for (var i = 0; i < 6; i++) {
        await pinch(tester, from: 20, to: 300, pointer: 20 + 2 * i);
      }
      expect(window(tester).span, closeTo(s.minSpan, 1e-6));

      // The range tapped again: back on the month, ending now.
      await tester.tap(find.text('1M'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(window(tester), before);
      expect(header(tester), '−\$36.38 past month');
      expect(tester.widget<KuteTimeAxis>(find.byType(KuteTimeAxis)).end, 'Now');
      await settle(tester);
    });

    testWidgets('another series (a venue row picked) opens afresh on the range',
        (tester) async {
      await pump(tester, upThenDown(), eventVenue: 'all');
      final before = window(tester);
      await pinch(tester);
      expect(window(tester).span, lessThan(before.span));
      await pump(tester, upThenDown(), eventVenue: 'hyperliquid');
      expect(window(tester), before);
      await settle(tester);
    });

    testWidgets(
        'large text and a narrow phone: no overflow at rest, zoomed '
        'or scrubbing', (tester) async {
      await pump(tester, upThenDown(),
          textScale: 1.3, size: const Size(375, 812));
      expect(tester.takeException(), isNull);
      await pinch(tester);
      expect(tester.takeException(), isNull);
      final rect = tester.getRect(find.byType(KuteLineChart));
      final touch = await tester.startGesture(rect.center);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);
      await touch.up();
      await pump(tester, upThenDown(), textScale: 2);
      expect(tester.takeException(), isNull);
      await settle(tester);
    });
  });
}
