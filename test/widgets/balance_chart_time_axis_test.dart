import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/screens/analytics/components/balance_history_chart.dart';
import 'package:kute/screens/shared/charts/kute_chart_time_axis.dart';
import 'package:kute/screens/shared/charts/kute_chart_zoom_hint.dart';
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/screens/usd/components/usd_balance_chart.dart';
import 'package:kute/theme/app_theme.dart';

/// The Balance charts (Bitcoin wallets, the Ledger Bitcoin tab and
/// Dollars all draw [BalanceHistoryChart]) write when the window on
/// screen starts and ends under the plot, following pinch and pan, and
/// play the one-time zoom nudge shared with the Predictions chart.
void main() {
  final now = DateTime(2026, 10, 5, 18, 0);

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

  BalanceHistory since(Duration ago) => BalanceHistory(
        opening: 0,
        changes: [(now.subtract(ago), 150)],
        current: 150,
      );

  Widget chart(BalanceHistory history, {Key? key}) => SizedBox(
        key: key,
        height: 300,
        child: BalanceHistoryChart(
          history: history,
          format: (v) => '\$${v.toStringAsFixed(2)}',
          scaleLabel: dollarScaleLabel,
          trackingChart: 'valuation',
          now: now,
        ),
      );

  Future<void> pump(WidgetTester tester, Widget child,
      {bool reduceMotion = false, List<Override> overrides = const []}) async {
    tester.view.physicalSize = const Size(393, 852) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((_) => SettingsModel(settings())),
        ...overrides,
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          locale: const Locale('en'),
          theme: buildLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(disableAnimations: reduceMotion),
                child: child,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  String startText(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('kute-time-axis-start')))
      .data!;
  String endText(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('kute-time-axis-end')))
      .data!;

  /// What the start label reads for [history]'s whole window.
  String wholeStart(BalanceHistory history) {
    final s = sampleBalanceHistory(history, now);
    final start = s.first.$1, end = s.last.$1;
    return kuteAxisTime(start, end.difference(start), 'en');
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 8));
  }

  group('the time axis', () {
    final hour = RegExp(r'^\d{2}:\d{2}$');
    final day = RegExp(r'^[A-Z][a-z]{2} \d{1,2}$');
    final month = RegExp(r'^[A-Z][a-z]{2} \d{4}$');

    testWidgets('a window hours long: the time of day, then "Now"',
        (tester) async {
      final h = since(const Duration(hours: 3));
      await pump(tester, chart(h));
      expect(find.byType(KuteTimeAxis), findsOneWidget);
      expect(startText(tester), matches(hour));
      expect(startText(tester), wholeStart(h));
      // A twelfth of the three hours of lead-in before the deposit.
      expect(startText(tester), '14:45');
      expect(endText(tester), 'Now');
      await dispose(tester);
    });

    testWidgets('a window months long: the day', (tester) async {
      final h = since(const Duration(days: 60));
      await pump(tester, chart(h));
      expect(startText(tester), matches(day));
      expect(startText(tester), wholeStart(h));
      expect(startText(tester), 'Aug 1');
      expect(endText(tester), 'Now');
      await dispose(tester);
    });

    testWidgets('a window years long: the month', (tester) async {
      final h = since(const Duration(days: 730));
      await pump(tester, chart(h));
      expect(startText(tester), matches(month));
      expect(startText(tester), wholeStart(h));
      expect(endText(tester), 'Now');
      await dispose(tester);
    });

    testWidgets('the Dollars chart has it, under the plot', (tester) async {
      final h = BalanceHistory(
        opening: 0,
        changes: [(DateTime.now().subtract(const Duration(days: 60)), 5.02)],
        current: 5.02,
      );
      await pump(tester, const UsdBalanceChart(),
          overrides: [usdBalanceStepsProvider.overrideWithValue(h)]);
      final plot = tester.getRect(find.byType(KuteLineChart));
      final axis = tester.getRect(find.byType(KuteTimeAxis));
      expect(axis.height, kKuteTimeAxisHeight);
      expect(axis.bottom, closeTo(plot.bottom, 0.01));
      expect(startText(tester), matches(day));
      expect(endText(tester), 'Now');
      // The end label sits at the plot's right edge.
      final end = tester.getRect(
          find.byKey(const ValueKey('kute-time-axis-end')));
      expect(end.right, closeTo(plot.right, 0.5));
      await dispose(tester);
    });

    testWidgets('a pinch narrows the dates; a pan leaves "Now"',
        (tester) async {
      final h = since(const Duration(days: 60));
      await pump(tester, chart(h));
      final before = startText(tester);
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
      await tester.pump(const Duration(milliseconds: 300));
      // Zoomed in on the newest third: a later start, still "Now".
      expect(startText(tester), isNot(before));
      expect(startText(tester), matches(day));
      expect(endText(tester), 'Now');

      // A drag to the right walks back in time: the end is a date now.
      await tester.dragFrom(rect.center, const Offset(120, 0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(endText(tester), isNot('Now'));
      expect(endText(tester), matches(day));
      await dispose(tester);
    });
  });

  group('the zoom nudge', () {
    late bool stored;
    setUp(() {
      stored = false;
      KuteZoomHint.debugReset(read: () => stored, write: () => stored = true);
    });
    tearDown(() => KuteZoomHint.debugReset());

    final h = since(const Duration(days: 60));

    testWidgets('plays once, on the first chart only, and comes back',
        (tester) async {
      await pump(tester, chart(h, key: const ValueKey('first')));
      final rest = startText(tester);
      expect(rest, wholeStart(h));
      // Not before the wait.
      await tester.pump(const Duration(milliseconds: 500));
      expect(startText(tester), rest);
      expect(stored, isFalse);
      await tester.pump(const Duration(milliseconds: 100));
      expect(stored, isTrue);
      // Halfway: zoomed in by the nudge's depth, anchored on now.
      await tester.pump(const Duration(milliseconds: 400));
      expect(startText(tester), isNot(rest));
      expect(endText(tester), 'Now');
      // Done: back where it was.
      await tester.pump(const Duration(milliseconds: 500));
      expect(startText(tester), rest);

      // Another chart (Dollars after Bitcoin): never again.
      await pump(tester, chart(h, key: const ValueKey('second')));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(startText(tester), rest);
      }
      await dispose(tester);
    });

    testWidgets('Reduce Motion: no nudge, and it counts as seen',
        (tester) async {
      await pump(tester, chart(h), reduceMotion: true);
      final rest = startText(tester);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(startText(tester), rest);
      }
      expect(stored, isTrue);
      await dispose(tester);
    });

    testWidgets('a touch stops it at once, the window back',
        (tester) async {
      await pump(tester, chart(h));
      final rest = startText(tester);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 250));
      expect(startText(tester), isNot(rest));
      final rect = tester.getRect(find.byType(KuteLineChart));
      final touch = await tester.startGesture(rect.center);
      await tester.pump();
      expect(startText(tester), rest);
      await touch.up();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(startText(tester), rest);
      }
      await dispose(tester);
    });

    testWidgets('a finger already down when the wait ends: no nudge',
        (tester) async {
      await pump(tester, chart(h));
      final rest = startText(tester);
      final rect = tester.getRect(find.byType(KuteLineChart));
      final touch = await tester.startGesture(rect.center);
      await tester.pump(const Duration(milliseconds: 300));
      await touch.up();
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(startText(tester), rest);
      }
      expect(stored, isFalse);
      await dispose(tester);
    });

    testWidgets('a chart with fewer than 20 points never nudges',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: KuteLineChart(
              values: const [1, 2, 3, 4, 5],
              lineColor: Colors.green,
              valueTextBuilder: (i) => '$i',
              zoomHint: true,
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(seconds: 2));
      expect(stored, isFalse);
    });
  });
}
