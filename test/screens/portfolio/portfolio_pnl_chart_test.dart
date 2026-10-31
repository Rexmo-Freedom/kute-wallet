import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/portfolio/components/portfolio_pnl_chart.dart';
import 'package:kute/screens/shared/charts/kute_chart_viewport.dart';
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/screens/shared/charts/kute_trend_chart.dart';
import 'package:kute/screens/shared/charts/kute_trend_window.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The P&L chart leading the Portfolio ("P&L charts") on the modern line
/// chart: the range row 16 px under the plot (1M to start, remembered for
/// the session), the closing P&L per bucket ending on the P&L now as one
/// line in the range's result colour, the headline and a "▲ \$12.40 ·
/// Past month" change line (never a percent) that follow a scrubbing
/// finger, no chart at all before the first position, and the spending
/// account's one block (the realised figure, the plot, the ranges, the
/// venue lines).
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
      // Past the draw-in.
      await tester.pump(const Duration(milliseconds: 700));
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 8));
    }

    String header(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey('statistics-pnl-header')))
        .textSpan!
        .toPlainText();

    /// The coloured part of the header (the arrow and the amount).
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

    KuteTrendChart chart(WidgetTester tester) =>
        tester.widget<KuteTrendChart>(find.byType(KuteTrendChart));

    Finder plot() => find.byKey(const ValueKey('trend-chart-plot'));

    /// The points the month draws out of [data].
    List<double> monthValues(PortfolioPerformance data) {
      final s = pnlSeries(data, now);
      return kuteTrendWindow(s, s.spanFor(BalanceRange.month)).values;
    }

    /// A long press, then a slide: the scrub.
    Future<TestGesture> scrub(WidgetTester tester, Offset at) async {
      final touch = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 150));
      return touch;
    }

    testWidgets(
        'the range row: 1W to ALL 16 px under the plot, 1M to start, a '
        'tap sets the points drawn and the change line', (tester) async {
      await pump(tester, upMonth());
      final row = tester
          .widget<KuteChartRangeRow>(find.byType(KuteChartRangeRow));
      expect(row.labels, ['1W', '1M', '3M', '1Y', 'ALL']);
      expect(row.selectedIndex, BalanceRange.month.index);
      expect(tester.getTopLeft(find.byType(KuteChartRangeRow)).dy,
          closeTo(tester.getBottomLeft(plot()).dy + 16 * 390 / 430, 1));
      expect(chart(tester).values, monthValues(upMonth()));
      expect(header(tester), '▲ \$12.40 · Past month');

      await tester.tap(find.text('1W'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(chart(tester).selectedRange, BalanceRange.week.index);
      expect(header(tester), '▲ \$12.40 · Past week');

      await tester.tap(find.text('ALL'));
      await tester.pump(const Duration(milliseconds: 400));
      // From the lead-in's zero: the whole P&L.
      expect(chart(tester).values.first, 0);
      expect(header(tester), '▲ \$112.40 · All time');
      await settle(tester);
    });

    testWidgets('the range is remembered for the session', (tester) async {
      final container = ProviderContainer(overrides: [
        settingsProvider.overrideWith((_) => SettingsModel(settings())),
      ]);
      addTearDown(container.dispose);
      await pump(tester, upMonth(), container: container);
      await tester.tap(find.text('3M'));
      await tester.pump(const Duration(milliseconds: 400));
      await pump(tester, upThenDown(), container: container);
      expect(
          tester
              .widget<KuteChartRangeRow>(find.byType(KuteChartRangeRow))
              .selectedIndex,
          BalanceRange.threeMonths.index);
      expect(container.read(pnlChartRangeProvider), BalanceRange.threeMonths);
      await settle(tester);
    });

    testWidgets(
        'the result colour: red when the range fell, green when it rose, '
        'the text colour when flat; no axes, no scale, the one plot',
        (tester) async {
      // Down over the month (30 to −6.38).
      await pump(tester, upThenDown());
      expect(chart(tester).lineColor, AppColors.marketDown);
      expect(chart(tester).lines, isEmpty);
      expect(plot(), findsOneWidget);
      expect(tester.getSize(plot()).height, closeTo(200 * 844 / 932, 1));
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
      expect(chart(tester).lineColor, AppColorsExtension.light().textPrimary);
      expect(pnlResultColor(AppColorsExtension.light(), 0),
          AppColorsExtension.light().textPrimary);
      expect(pnlResultColor(AppColorsExtension.light(), -0.01),
          AppColors.marketDown);
      expect(
          pnlResultColor(AppColorsExtension.light(), 0.01), AppColors.marketUp);
      await settle(tester);
    });

    testWidgets(
        'the one block (founder, 28 October 2026): the caption and the '
        'realised figure, the plot directly under them, the ranges, a '
        'hairline and the footer; no change line; a scrub writes the P&L '
        'under the finger and when, release puts the realised figure back',
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
                  figureUsd: -6.39,
                  footer: const SizedBox(
                      key: ValueKey('lines'), width: 10, height: 60),
                ),
              ]),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 700));
      Rect at(String key) => tester.getRect(find.byKey(ValueKey(key)));
      final caption = at('statistics-pnl-caption');
      final figure = at('statistics-pnl-headline');
      final lines = at('lines');
      final plotRect = tester.getRect(plot());
      final ranges = tester.getRect(find.byType(KuteChartRangeRow));
      expect(find.text('Profit and loss'), findsOneWidget);
      // The realised figure, in the result colour; no change line.
      expect(headline(tester), '−\$6.39');
      expect(
          tester
              .widget<RollingNumberText>(
                  find.byKey(const ValueKey('statistics-pnl-headline')))
              .style
              .color,
          AppColors.marketDown);
      expect(find.byKey(const ValueKey('statistics-pnl-header')), findsNothing);
      expect(find.textContaining('Past month'), findsNothing);
      // Top down: caption, figure, plot, ranges, the footer.
      expect(figure.top, greaterThan(caption.bottom - 1));
      expect(plotRect.top, greaterThan(figure.bottom - 1));
      expect(plotRect.top - figure.bottom, lessThan(40));
      expect(ranges.top, greaterThan(plotRect.bottom - 1));
      expect(lines.top, greaterThan(ranges.bottom));
      expect(plotRect.height, greaterThan(150));

      // A scrub: the P&L under the finger and when, in the caption.
      final touch = await scrub(tester, plotRect.centerRight.translate(-8, 0));
      expect(headline(tester), '−\$6.38');
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('statistics-pnl-caption')))
              .data,
          allOf(startsWith('Profit and loss · '), contains('Oct 25')));
      await touch.up();
      await tester.pump(const Duration(milliseconds: 150));
      expect(headline(tester), '−\$6.39');
      expect(find.text('Profit and loss'), findsOneWidget);
      await settle(tester);
    });

    testWidgets('the change line: up, down, no change, never a percent',
        (tester) async {
      await pump(tester, upThenDown());
      await tester.tap(find.text('1W'));
      await tester.pump(const Duration(milliseconds: 400));
      // −25 a week ago to −6.38 now: +18.62.
      expect(header(tester), '▲ \$18.62 · Past week');
      expect(amountSpan(tester).style!.color, AppColors.marketUp);

      // A month: +30 to −6.38.
      await tester.tap(find.text('1M'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(header(tester), '▼ \$36.38 · Past month');
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
      expect(header(tester), 'No change · Past month');
      expect(find.textContaining('%'), findsNothing);

      // Up from a base: still no percent.
      await pump(tester, upMonth());
      expect(header(tester), '▲ \$12.40 · Past month');
      expect(find.textContaining('%'), findsNothing);
      await settle(tester);
    });

    testWidgets(
        'a scrub writes the P&L under the finger in the headline, its '
        'change since the range\'s start and its moment in the change line; '
        'release puts the P&L now back', (tester) async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      await pump(tester, upThenDown());
      final rect = tester.getRect(plot());
      final touch = await scrub(tester, rect.centerRight.translate(-8, 0));
      // The newest point: the P&L now, down from the month's +30.
      expect(headline(tester), '−\$6.38');
      expect(header(tester), startsWith('▼ \$36.38 · '));
      expect(header(tester), contains('Oct 25'));
      expect(amountSpan(tester).style!.color, AppColors.marketDown);

      await touch.moveTo(rect.centerLeft.translate(2, 0));
      await tester.pump(const Duration(milliseconds: 150));
      // A month back: +30, where the range starts: no change yet.
      expect(headline(tester), '+\$30.00');
      expect(header(tester), startsWith('No change · Sep '));
      await touch.up();
      await tester.pump(const Duration(milliseconds: 150));
      expect(headline(tester), '−\$6.38');
      expect(header(tester), '▼ \$36.38 · Past month');
      expect(
          events.where((e) => e.$1 == 'portfolio_performance_chart_scrubbed'),
          hasLength(1));
      await settle(tester);
    });

    testWidgets(
        'nothing traded: Sal with "No P&L yet" and the caption, no chart, '
        'no range row, no headline', (tester) async {
      // Founder, 31 October 2026: no history shows Sal, the same empty
      // state as Activity, instead of a headline over an empty plot.
      for (final data in [
        perf(const []),
        perf([(const Duration(days: 9), 0), (Duration.zero, 0)]),
      ]) {
        await pump(tester, data);
        final sal = find.byKey(const ValueKey('statistics-pnl-no-history'));
        expect(sal, findsOneWidget);
        expect(find.descendant(of: sal, matching: find.text('No P&L yet')),
            findsOneWidget);
        expect(
            find.descendant(
                of: sal,
                matching: find
                    .text('Your P&L shows up after your first position.')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('statistics-pnl-empty')),
            findsNothing);
        expect(find.byKey(const ValueKey('statistics-pnl-headline')),
            findsNothing);
        expect(find.text('Profit and loss'), findsNothing);
        expect(plot(), findsNothing);
        expect(find.byType(KuteChartRangeRow), findsNothing);
        expect(find.byKey(const ValueKey('statistics-pnl-header')),
            findsNothing);
      }
      await settle(tester);
    });

    testWidgets('balances hidden: dots for every figure', (tester) async {
      await pump(tester, upThenDown(), privacy: 1);
      expect(header(tester), '•••••• · Past month');
      expect(headline(tester), '••••••');
      expect(find.textContaining('\$'), findsNothing);
      await settle(tester);
    });

    testWidgets('another series (a venue row picked) keeps the range',
        (tester) async {
      await pump(tester, upThenDown(), eventVenue: 'all');
      await tester.tap(find.text('1W'));
      await tester.pump(const Duration(milliseconds: 400));
      await pump(tester, upMonth(), eventVenue: 'hyperliquid');
      expect(chart(tester).selectedRange, BalanceRange.week.index);
      expect(header(tester), '▲ \$12.40 · Past week');
      await settle(tester);
    });

    testWidgets(
        'large text and a narrow phone: no overflow at rest or scrubbing',
        (tester) async {
      await pump(tester, upThenDown(),
          textScale: 1.3, size: const Size(375, 812));
      expect(tester.takeException(), isNull);
      final rect = tester.getRect(plot());
      final touch = await scrub(tester, rect.center);
      expect(tester.takeException(), isNull);
      await touch.up();
      await pump(tester, upThenDown(), textScale: 2);
      expect(tester.takeException(), isNull);
      await settle(tester);
    });
  });
}
