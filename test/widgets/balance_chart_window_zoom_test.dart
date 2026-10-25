import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/analytics/components/balance_history_chart.dart';
import 'package:kute/screens/shared/charts/kute_chart_viewport.dart';
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/theme/app_theme.dart';

/// How the Balance charts open and zoom (the founder's 2026-10-25
/// report: "the balance graph in bitcoin just opens up bad, the zoom
/// sometimes is so strange"): the window they open on, the closing
/// balance per bucket so money passing through never spikes the line or
/// the scale, the scale fitted to the line on screen, and a pinch that
/// keeps what is under the fingers under them, clamps, pans within the
/// history and is never undone by data landing.
void main() {
  // The founder's screenshot: 17:55, a wallet holding 6,938 sats.
  final now = DateTime(2026, 10, 25, 17, 55);

  /// Money that came and went within minutes 19 days ago, nothing since,
  /// then yesterday a top-up that mostly passed on within 20 minutes.
  BalanceHistory founder() {
    final early = DateTime(2026, 10, 6, 10, 0);
    final top = DateTime(2026, 10, 24, 15, 55);
    return BalanceHistory(
      opening: 0,
      changes: [
        (early, 5000),
        (early.add(const Duration(minutes: 30)), 0),
        (top, 110000),
        (top.add(const Duration(minutes: 5)), 90000),
        (top.add(const Duration(minutes: 12)), 52000),
        (top.add(const Duration(minutes: 20)), 6938),
      ],
      current: 6938,
    );
  }

  /// The window a range shows, and the points drawn in it.
  KuteIndexWindow opening(BalanceSeries s,
          [BalanceRange range = BalanceRange.month]) =>
      KuteIndexWindow(s.extent - s.spanFor(range), s.extent);
  KuteLineBuckets bucketsOf(BalanceSeries s) =>
      KuteLineBuckets(strideFor: s.strideFor, phase: s.phase);
  List<double> drawnIn(BalanceSeries s, KuteIndexWindow w) => [
        for (final i in bucketsOf(s).indicesFor(s.length, w))
          if (i >= w.start - 1e-6 && i <= w.end + 1e-6) s.values[i]
      ];

  group('how it opens', () {
    test('never on weeks of zero or a pass-through: the money that stayed, '
        'rising from nothing, ending now', () {
      final s = balanceSeries(founder(), now);
      final w = opening(s);
      // Oct 6 came and went the same morning: the history starts shortly
      // before the top-up of Oct 24 that stayed.
      expect(s.times.first.isAfter(DateTime(2026, 10, 24)), isTrue);
      expect(w.start, 0);
      expect(w.end, s.extent);
      expect(s.times.last, now);
      final drawn = drawnIn(s, w);
      // Nothing, then what stayed: no 110,000 spike.
      expect(drawn.toSet(), {0, 6938});
      expect(drawn.last, 6938);
    });

    test('a pass-through inside one bucket never reaches the line or the '
        'scale', () {
      // Funded three weeks ago and steady; yesterday 110,000 sats came in
      // and left again within 20 minutes.
      final top = now.subtract(const Duration(hours: 26));
      final h = BalanceHistory(
        opening: 0,
        changes: [
          (now.subtract(const Duration(days: 20)), 7000),
          (top, 117000),
          (top.add(const Duration(minutes: 20)), 7000),
        ],
        current: 7000,
      );
      final s = balanceSeries(h, now);
      final w = opening(s);
      // The month reaches past the start: all of it, in daily closes.
      expect(w.start, 0);
      expect(s.strideFor(w.span) * s.cellMinutes, 1440);
      expect(drawnIn(s, w).every((v) => v == 7000 || v == 0), isTrue);
      final d = kuteLineDomain(s.values, w,
          indices: bucketsOf(s).indicesFor(s.length, w), minShare: 0.2);
      expect(d.maxY, lessThan(10000));
      // On the week (hourly closes) it still never shows.
      final week = opening(s, BalanceRange.week);
      expect(drawnIn(s, week).every((v) => v == 7000), isTrue);
    });

    test('a long history shows each range ending now', () {
      final h = BalanceHistory(
        opening: 0,
        changes: [
          (now.subtract(const Duration(days: 200)), 50000),
          (now.subtract(const Duration(days: 9)), 80000),
        ],
        current: 80000,
      );
      final s = balanceSeries(h, now);
      final w = opening(s);
      // The first grid point of the last 30 days.
      final cut = now.subtract(const Duration(days: 30));
      final start = s.times[w.start.round()];
      expect(start.isBefore(cut), isFalse);
      expect(start.difference(cut).inMinutes, lessThan(s.cellMinutes));
      expect(w.end, s.extent);
      expect(drawnIn(s, w).toSet(), {50000, 80000});
      expect(opening(s, BalanceRange.all).start, 0);
    });

    test('a short history shows all of it on the month', () {
      final h = BalanceHistory(
        opening: 0,
        changes: [
          (now.subtract(const Duration(days: 10)), 20000),
          (now.subtract(const Duration(days: 2)), 26000),
        ],
        current: 26000,
      );
      final s = balanceSeries(h, now);
      expect(s.spanFor(BalanceRange.month), s.extent);
      expect(s.spanFor(BalanceRange.week), lessThan(s.extent));
    });

    test('a pinch re-buckets: quarter hours, hours, days, weeks', () {
      final s = balanceSeries(founder(), now);
      int bucket(Duration span) =>
          s.strideFor(span.inMinutes / s.cellMinutes) * s.cellMinutes;
      expect(bucket(const Duration(hours: 6)), 15);
      expect(bucket(const Duration(days: 3)), 60);
      expect(bucket(const Duration(days: 19)), 1440);
      // Never closer than a few hours.
      expect(s.minSpan * s.cellMinutes, 240);
    });
  });

  group('the scale', () {
    test('fits the line on screen, zero only when the line reaches it', () {
      const w = KuteIndexWindow(0, 4);
      final above = kuteLineDomain([100000, 104000, 110000, 120000, 118000], w,
          minShare: 0.2);
      expect(above.minY, greaterThan(0));
      expect(kuteScaleLevels(above.minY, above.maxY), isNot(contains(0)));
      final touching =
          kuteLineDomain([0, 50000, 80000, 120000, 118000], w, minShare: 0.2);
      expect(touching.minY, lessThan(0));
      expect(kuteScaleLevels(touching.minY, touching.maxY), contains(0));
    });

    test('a balance that barely moved is not magnified into a cliff', () {
      const w = KuteIndexWindow(0, 2);
      final d = kuteLineDomain([100000, 100000, 100050], w, minShare: 0.2);
      expect(d.maxY - d.minY, greaterThanOrEqualTo(20000));
      // Without the floor (prices) the 50 sats fill the plot.
      final tight = kuteLineDomain([100000, 100000, 100050], w);
      expect(tight.maxY - tight.minY, lessThan(100));
    });

    test('a line flat at zero sits in the middle with one level, zero', () {
      final d = kuteLineDomain([0, 0, 0], const KuteIndexWindow(0, 2),
          minShare: 0.2);
      expect(kuteLineY(0, 200, d), closeTo(100, 1e-6));
      expect(kuteScaleLevels(d.minY, d.maxY), [0]);
    });
  });

  group('the zoom', () {
    const n = 2000;
    final values = [
      for (var i = 0; i < n; i++) 1000 + 300 * math.sin(i / 40) + i * 0.2
    ];

    late List<KuteIndexWindow> windows;
    KuteIndexWindow window() => windows.last;

    Widget line(List<double> v, {double defaultSpan = 400}) => KuteLineChart(
          values: v,
          lineColor: Colors.green,
          valueTextBuilder: (i) => '$i',
          defaultSpan: defaultSpan,
          minSpan: 20,
          zoomAroundFingers: true,
          resetViewOnLengthChange: false,
          buckets: KuteLineBuckets(strideFor: (span) => span > 600 ? 4 : 1),
          plotOverlay: (w) {
            windows.add(w);
            return const SizedBox.shrink();
          },
        );

    Future<void> pumpLine(WidgetTester tester, Widget chart,
        {ScrollController? scroll}) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: ListView(
            controller: scroll,
            children: [
              SizedBox(height: 240, child: chart),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// Two fingers [from] px apart to [to] px apart about [x] (a share of
    /// the plot's width), moving by [drift] together on the way.
    Future<void> pinch(WidgetTester tester, double x,
        {double from = 60,
        double to = 180,
        Offset drift = Offset.zero,
        int pointer = 10}) async {
      final rect = tester.getRect(find.byType(KuteLineChart));
      final c = Offset(rect.left + rect.width * x, rect.center.dy);
      final a = await tester.startGesture(c - Offset(from / 2, 0),
          pointer: pointer);
      final b = await tester.startGesture(c + Offset(from / 2, 0),
          pointer: pointer + 1);
      await tester.pump();
      const steps = 8;
      final d = (to - from) / 2 / steps;
      for (var i = 0; i < steps; i++) {
        await a.moveBy(Offset(-d, 0) + drift / steps.toDouble());
        await b.moveBy(Offset(d, 0) + drift / steps.toDouble());
        await tester.pump();
      }
      await a.up();
      await b.up();
      await tester.pump(const Duration(milliseconds: 100));
    }

    /// The (fractional) index under [x], a share of the plot's width.
    double indexAt(WidgetTester tester, double x) {
      final w = tester.getSize(find.byType(KuteLineChart)).width;
      return window().indexAt(w * x, w);
    }

    setUp(() => windows = []);

    testWidgets('opens on the default span, ending on the newest point',
        (tester) async {
      await pumpLine(tester, line(values));
      expect(window(), const KuteIndexWindow(n - 401, n - 1));
    });

    testWidgets('a pinch keeps the point under the fingers under them, and '
        'never drifts', (tester) async {
      await pumpLine(tester, line(values));
      final under = indexAt(tester, 0.3);
      final before = window();
      await pinch(tester, 0.3);
      // Three times as far apart: a third of the span, the same point
      // under the fingers.
      expect(window().span, closeTo(before.span / 3, 1));
      expect(indexAt(tester, 0.3), closeTo(under, 1));
      // And back out where it began.
      await pinch(tester, 0.3, from: 180, to: 60, pointer: 20);
      expect(window().start, closeTo(before.start, 1));
      expect(window().end, closeTo(before.end, 1));
      for (final w in windows) {
        expect(w.start.isFinite && w.end.isFinite, isTrue);
        expect(w.span, greaterThan(0));
      }
    });

    testWidgets('a pinch stops at the closest span and at the whole history',
        (tester) async {
      await pumpLine(tester, line(values));
      for (var i = 0; i < 4; i++) {
        await pinch(tester, 0.5, from: 20, to: 300, pointer: 10 + 2 * i);
      }
      expect(window().span, closeTo(20, 1e-6));
      for (var i = 0; i < 8; i++) {
        await pinch(tester, 0.5, from: 300, to: 20, pointer: 40 + 2 * i);
      }
      expect(window(), const KuteIndexWindow(0, n - 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a drag pans within the history, never past either end',
        (tester) async {
      await pumpLine(tester, line(values));
      final span = window().span;
      // Back in time as far as it goes.
      for (var i = 0; i < 8; i++) {
        await tester.drag(find.byType(KuteLineChart), const Offset(300, 0));
        await tester.pump();
      }
      expect(window().start, 0);
      expect(window().span, closeTo(span, 1e-6));
      // And forward: it stops on now.
      for (var i = 0; i < 8; i++) {
        await tester.drag(find.byType(KuteLineChart), const Offset(-300, 0));
        await tester.pump();
      }
      expect(window().end, n - 1);
      expect(window().span, closeTo(span, 1e-6));
    });

    testWidgets('data landing late re-fits the opening view only until the '
        'first pinch', (tester) async {
      final short = values.sublist(0, 1000);
      await pumpLine(tester, line(short, defaultSpan: 200));
      expect(window(), const KuteIndexWindow(799, 999));
      // The rest of the history lands before anyone touched the chart.
      await pumpLine(tester, line(values));
      expect(window(), const KuteIndexWindow(n - 401, n - 1));

      await pinch(tester, 0.4);
      final zoomed = window();
      // A point more (time passing) and a new opening span: the window
      // stays where the pinch left it.
      await pumpLine(
          tester, line([...values, 1500], defaultSpan: 300));
      expect(window(), zoomed);
    });

    testWidgets('a pinch never scrolls the page around the chart',
        (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpLine(tester, line(values), scroll: scroll);
      final before = window();
      // Fingers spreading diagonally, the way a thumb and finger do.
      await pinch(tester, 0.5, drift: const Offset(0, -60));
      expect(scroll.offset, 0);
      expect(window().span, lessThan(before.span));
      // One finger dragging up still scrolls the page.
      await tester.drag(find.byType(KuteLineChart), const Offset(0, -200));
      await tester.pump();
      expect(scroll.offset, greaterThan(0));
    });

    testWidgets('a bucketed line draws, scales and scrubs only bucket closes',
        (tester) async {
      await pumpLine(tester, line(values, defaultSpan: 1600));
      // 1,600 points on screen: every fourth is drawn.
      final chart = tester.widget<KuteLineChart>(find.byType(KuteLineChart));
      final drawn = chart.buckets!.indicesFor(n, window());
      final inside = drawn.where((i) => i < n - 1);
      expect(inside.every((i) => i % 4 == 0), isTrue);
      expect(drawn.last, n - 1);
    });
  });

  group('on the Balance chart', () {
    Settings settings() => Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: '',
          reviewDone: true,
          activeWalletId: 'spending',
          wallets: [WalletConfig(id: 'spending', name: 'Spending')],
        );

    testWidgets('the founder\'s wallet: what stayed, never the pass-through',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsProvider.overrideWith((_) => SettingsModel(settings())),
        ],
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            locale: const Locale('en'),
            theme: buildLightTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                height: 300,
                child: BalanceHistoryChart(
                  history: founder(),
                  format: (v) => '₿${v.round()}',
                  emptyMessage: 'Nothing held yet',
                  trackingChart: 'valuation',
                  now: now,
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      final chart = tester.widget<KuteLineChart>(find.byType(KuteLineChart));
      expect(chart.stepped, isFalse);
      expect(chart.animateChanges, isFalse);
      expect(chart.zoomAroundFingers, isTrue);
      expect(chart.resetViewOnLengthChange, isFalse);
      final w = KuteIndexWindow(
          chart.values.length - 1 - chart.defaultSpan!,
          (chart.values.length - 1).toDouble());
      final drawn = [
        for (final i in chart.buckets!.indicesFor(chart.values.length, w))
          if (i >= w.start - 1e-6) chart.values[i]
      ];
      // Nothing, then what stayed; never the 110,000 that passed on.
      expect(drawn.toSet(), {0, 6938});
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('kute-time-axis-start')))
              .data,
          'Oct 24');
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('kute-time-axis-end')))
              .data,
          'Now');
      // Up from nothing this month: the amount, no percent.
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('balance-chart-header')))
              .textSpan!
              .toPlainText(),
          '+₿6938 past month');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 8));
    });
  });
}
