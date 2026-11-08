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

import '../../helpers/euro_settings.dart';

/// The P&L chart leading the Portfolio ("P&L charts") on the modern line
/// chart: the range row 16 px under the plot (1M to start, remembered for
/// the session), the closing P&L per bucket ending on the P&L now as one
/// line in the range's result colour, the headline (the P&L over the range
/// picked, ALL the all-time P&L) over the line naming the range ("Past
/// month", never a percent without a base) that follow a scrubbing
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
    Settings settings({int privacy = 0, String currency = 'USD'}) => Settings(
        currency: currency,
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
        String currency = 'USD',
        ProviderContainer? container}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final child = app(data, eventVenue: eventVenue, textScale: textScale);
      await tester.pumpWidget(container != null
          ? UncontrolledProviderScope(container: container, child: child)
          : ProviderScope(overrides: [
              if (currency == 'EUR') euroRateOverride(),
              settingsProvider.overrideWith((_) =>
                  SettingsModel(settings(privacy: privacy, currency: currency))),
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

    String headline(WidgetTester tester) => tester
        .widget<RollingNumberText>(
            find.byKey(const ValueKey('statistics-pnl-headline')))
        .text;

    Color? headlineColor(WidgetTester tester) => tester
        .widget<RollingNumberText>(
            find.byKey(const ValueKey('statistics-pnl-headline')))
        .style
        .color;

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

    testWidgets('euros in Settings: the P&L reads the same dollars, no euro',
        (tester) async {
      await pump(tester, upMonth(), currency: 'EUR');
      expect(headline(tester), '+\$12.40');
      expect(chart(tester).values, monthValues(upMonth()));
      expectNoEuroOnScreen(tester);
      await settle(tester);
    });

    testWidgets(
        'the range row: 1W to ALL 16 px under the plot, 1M to start, a '
        'tap sets the points drawn, the figure (the P&L over the range; '
        'ALL the all-time P&L) and the line naming the range',
        (tester) async {
      await pump(tester, upMonth());
      final row = tester
          .widget<KuteChartRangeRow>(find.byType(KuteChartRangeRow));
      expect(row.labels, ['1W', '1M', '3M', '1Y', 'ALL']);
      expect(row.selectedIndex, BalanceRange.month.index);
      expect(tester.getTopLeft(find.byType(KuteChartRangeRow)).dy,
          closeTo(tester.getBottomLeft(plot()).dy + 16 * 390 / 430, 1));
      expect(chart(tester).values, monthValues(upMonth()));
      expect(headline(tester), '+\$12.40');
      expect(header(tester), 'Past month');

      await tester.tap(find.text('1W'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(chart(tester).selectedRange, BalanceRange.week.index);
      expect(headline(tester), '+\$12.40');
      expect(header(tester), 'Past week');

      await tester.tap(find.text('ALL'));
      await tester.pump(const Duration(milliseconds: 400));
      // From the lead-in's zero: the whole P&L, the all-time figure.
      expect(chart(tester).values.first, 0);
      expect(headline(tester), '+\$112.40');
      expect(header(tester), 'All time');
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
      expect(tester.getSize(plot()).height, closeTo(220 * 844 / 932, 1));
      // The P&L fill: up above zero, down below.
      expect(chart(tester).zeroSplit, isTrue);
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

    Future<void> pumpSection(WidgetTester tester,
        {PnlStatsFigures? stats, double? percentBase}) async {
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
                  flat: true,
                  percentBaseUsd: percentBase,
                  stats: stats ??
                      const PnlStatsFigures(
                          realisedUsd: -6.39, unrealisedUsd: 0.01),
                  footer: const SizedBox(
                      key: ValueKey('lines'), width: 10, height: 60),
                ),
              ]),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 700));
    }

    testWidgets(
        'the flat section (founder, 1 November 2026): no card; the caption, '
        'the P&L now 34 w700 in the result colour, the change line, the '
        'plot full width at 220, the ranges centred, the stats strip, "By '
        'venue" and the rows; a scrub writes the point and when, release '
        'puts the P&L now back', (tester) async {
      await pumpSection(tester);
      Rect at(String key) => tester.getRect(find.byKey(ValueKey(key)));
      expect(find.byKey(const ValueKey('statistics-pnl-card')), findsNothing);
      expect(find.byKey(const ValueKey('statistics-pnl-section')),
          findsOneWidget);
      final caption = at('statistics-pnl-caption');
      final figure = at('statistics-pnl-headline');
      final change = at('statistics-pnl-header');
      final plotRect = tester.getRect(plot());
      final ranges = tester.getRect(find.byType(KuteChartRangeRow));
      final stats = at('statistics-pnl-stats');
      final byVenue = at('statistics-pnl-by-venue');
      final lines = at('lines');
      expect(find.text('Profit and loss'), findsOneWidget);
      expect(find.text('By venue'), findsOneWidget);
      final captionStyle = tester
          .widget<Text>(find.byKey(const ValueKey('statistics-pnl-caption')))
          .style!;
      expect(captionStyle.fontSize, closeTo(13 * 390 / 430, 0.01));
      expect(captionStyle.color, AppColorsExtension.light().textSecondary);
      // The P&L over the month (+30 to −6.38), in the result colour, 34
      // w700 tabular.
      expect(headline(tester), '−\$36.38');
      final style = tester
          .widget<RollingNumberText>(
              find.byKey(const ValueKey('statistics-pnl-headline')))
          .style;
      expect(style.color, AppColors.marketDown);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.fontSize, closeTo(34 * 390 / 430, 0.01));
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
      // No base given: no percent; the line names the range.
      expect(header(tester), 'Past month');
      // Top down.
      expect(figure.top, greaterThan(caption.bottom - 1));
      expect(change.top, greaterThan(figure.bottom - 1));
      expect(plotRect.top, greaterThan(change.bottom - 1));
      expect(ranges.top, closeTo(plotRect.bottom + 16 * 1200 / 932, 1));
      expect(stats.top, greaterThan(ranges.bottom));
      expect(byVenue.top, greaterThan(stats.bottom));
      expect(lines.top, greaterThan(byVenue.bottom));
      // Full width (the host's gutters), 220 tall; the ranges centred.
      expect(plotRect.width, 390);
      expect(plotRect.height, closeTo(220 * 1200 / 932, 1));
      expect(ranges.center.dx, closeTo(195, 0.5));
      expect(ranges.width, lessThan(390));
      // The stats strip in its soft card; no hairline in a one-row card.
      expect(find.byKey(const ValueKey('statistics-pnl-stats-card')),
          findsOneWidget);
      expect(find.byType(Divider), findsNothing);

      // A scrub: the P&L under the finger since the range's start, and
      // when.
      final touch = await scrub(tester, plotRect.centerRight.translate(-8, 0));
      expect(headline(tester), '−\$36.38');
      expect(header(tester), contains('Oct 25'));
      expect(find.text('Profit and loss'), findsOneWidget);
      await touch.moveTo(plotRect.centerLeft.translate(2, 0));
      await tester.pump(const Duration(milliseconds: 150));
      // The range's start: nothing made or lost since.
      expect(headline(tester), '\$0.00');
      expect(headlineColor(tester), AppColorsExtension.light().textPrimary);
      await touch.up();
      await tester.pump(const Duration(milliseconds: 150));
      expect(headline(tester), '−\$36.38');
      expect(header(tester), 'Past month');
      await settle(tester);
    });

    testWidgets('the change line carries a percent only of a real base',
        (tester) async {
      await pumpSection(tester, percentBase: 100);
      expect(header(tester), '−36.4% · Past month');
      await settle(tester);
      await pumpSection(tester, percentBase: 0);
      expect(header(tester), 'Past month');
      await settle(tester);
    });

    testWidgets(
        'the stats strip: All time realised, All time unrealised (totals, '
        'never the range\'s), Win rate in equal thirds, '
        '12 sp labels over 15 w600 figures; a figure not given leaves its '
        'column out; none at all, no strip', (tester) async {
      Finder stat(String id) =>
          find.byKey(ValueKey('statistics-pnl-stat-$id'));
      await pumpSection(tester,
          stats: const PnlStatsFigures(
              realisedUsd: 12.5, unrealisedUsd: -3.25, winRate: 0.625));
      expect(stat('realised'), findsOneWidget);
      expect(stat('unrealised'), findsOneWidget);
      expect(stat('win-rate'), findsOneWidget);
      expect(
          find.descendant(
              of: stat('realised'), matching: find.text('All time realised')),
          findsOneWidget);
      final realised = tester.widget<Text>(find.descendant(
          of: stat('realised'), matching: find.text('+\$12.50')));
      expect(realised.style!.color, AppColors.marketUp);
      expect(realised.style!.fontWeight, FontWeight.w600);
      expect(realised.style!.fontSize, closeTo(15 * 390 / 430, 0.01));
      final label = tester.widget<Text>(find.text('All time unrealised'));
      expect(label.style!.fontSize, closeTo(12 * 390 / 430, 0.01));
      expect(label.style!.color, AppColorsExtension.light().textSecondary);
      expect(
          tester
              .widget<Text>(find.descendant(
                  of: stat('unrealised'), matching: find.text('−\$3.25')))
              .style!
              .color,
          AppColors.marketDown);
      expect(find.descendant(of: stat('win-rate'), matching: find.text('63%')),
          findsOneWidget);
      // Equal thirds of the soft card's inside (16 inset each side).
      const inside = 390 - 2 * 16 * 390 / 430;
      final w = tester.getSize(stat('realised')).width;
      expect(tester.getSize(stat('win-rate')).width, closeTo(w, 0.5));
      expect(w, closeTo(inside / 3, 0.5));
      await settle(tester);

      // No closed-trade counts: no Win rate column, the others keep their
      // thirds.
      await pumpSection(tester,
          stats: const PnlStatsFigures(realisedUsd: 12.5, unrealisedUsd: 0));
      expect(stat('win-rate'), findsNothing);
      expect(find.text('Win rate'), findsNothing);
      expect(stat('unrealised'), findsOneWidget);
      expect(tester.getSize(stat('realised')).width, closeTo(inside / 3, 0.5));
      await settle(tester);

      // The open P&L not read: its column out too.
      await pumpSection(tester,
          stats: const PnlStatsFigures(realisedUsd: 12.5));
      expect(stat('realised'), findsOneWidget);
      expect(stat('unrealised'), findsNothing);
      expect(stat('win-rate'), findsNothing);
      await settle(tester);

      // Nothing given: no strip.
      await pumpSection(tester, stats: const PnlStatsFigures());
      expect(find.byKey(const ValueKey('statistics-pnl-stats')), findsNothing);
      expect(find.text('All time realised'), findsNothing);
      await settle(tester);
    });

    testWidgets(
        'the figure over the range: up, down, nothing, never a percent',
        (tester) async {
      await pump(tester, upThenDown());
      await tester.tap(find.text('1W'));
      await tester.pump(const Duration(milliseconds: 400));
      // −25 a week ago to −6.38 now: +18.62 over the week, in the up
      // colour, though the P&L now is below zero.
      expect(headline(tester), '+\$18.62');
      expect(headlineColor(tester), AppColors.marketUp);
      expect(header(tester), 'Past week');

      // A month: +30 to −6.38.
      await tester.tap(find.text('1M'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(headline(tester), '−\$36.38');
      expect(headlineColor(tester), AppColors.marketDown);
      expect(header(tester), 'Past month');
      // The P&L went from +30 to below zero: never "−121.3%".
      expect(find.textContaining('%'), findsNothing);

      await pump(
          tester,
          perf([
            (const Duration(days: 90), 25),
            (const Duration(days: 60), 40),
          ]));
      expect(headline(tester), '\$0.00');
      expect(headlineColor(tester), AppColorsExtension.light().textPrimary);
      expect(header(tester), 'Past month');
      expect(find.textContaining('%'), findsNothing);

      // Up from a base: still no percent.
      await pump(tester, upMonth());
      expect(headline(tester), '+\$12.40');
      expect(header(tester), 'Past month');
      expect(find.textContaining('%'), findsNothing);
      await settle(tester);
    });

    testWidgets(
        'a scrub writes the P&L under the finger since the range\'s start '
        'in the headline and its moment in the line under it; release puts '
        'the range\'s P&L back', (tester) async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      await pump(tester, upThenDown());
      final rect = tester.getRect(plot());
      final touch = await scrub(tester, rect.centerRight.translate(-8, 0));
      // The newest point: down $36.38 from the month's +30.
      expect(headline(tester), '−\$36.38');
      expect(headlineColor(tester), AppColors.marketDown);
      expect(header(tester), contains('Oct 25'));

      await touch.moveTo(rect.centerLeft.translate(2, 0));
      await tester.pump(const Duration(milliseconds: 150));
      // A month back, where the range starts: nothing yet.
      expect(headline(tester), '\$0.00');
      expect(header(tester), startsWith('Sep '));
      await touch.up();
      await tester.pump(const Duration(milliseconds: 150));
      expect(headline(tester), '−\$36.38');
      expect(header(tester), 'Past month');
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
      expect(header(tester), 'Past month');
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
      expect(headline(tester), '+\$12.40');
      expect(header(tester), 'Past week');
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
