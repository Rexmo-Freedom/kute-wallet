// A Predictions chart's time axis and its one-time zoom nudge: the start
// and end of the window on screen under the plot (the end "Now" at the
// live edge, a time or a date once panned away from it), out of the
// chart's own height; and the nudge, which plays once ever, never under
// Reduce Motion and stops at a touch.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart';
import 'package:kute/screens/shared/charts/kute_chart_time_axis.dart';
import 'package:kute/screens/shared/charts/kute_chart_zoom_hint.dart';
import 'package:kute/theme/app_theme.dart';

const _min = 60000;
const _nowMs = 1790000000000;

/// A week of hourly points.
final _week = [
  for (var i = 0; i <= 168; i++)
    PolymarketPricePoint(
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(_nowMs - (168 - i) * 60 * _min),
      price: 0.20 + 0.60 * i / 168,
    ),
];

/// Six hours of minute points.
final _sixHours = [
  for (var i = 0; i <= 360; i++)
    PolymarketPricePoint(
      timestamp: DateTime.fromMillisecondsSinceEpoch(_nowMs - (360 - i) * _min),
      price: 0.40 + 0.2 * i / 360,
    ),
];

class _Quiet extends LivePriceNotifier {
  @override
  LivePriceState build() => LivePriceState(live: false);
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void pause() {}
  @override
  void resume() {}
  @override
  void subscribeTokens(List<String> tokenIds) {}
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
  @override
  void registerCardTokens(List<String> tokenIds) {}
  @override
  void unregisterCardTokens(List<String> tokenIds) {}
  @override
  void removeTokens(List<String> tokenIds) {}
  @override
  void unsubscribeAll() {}
}

Future<void> _pump(
  WidgetTester tester,
  Widget chart, {
  List<PolymarketPricePoint>? points,
  bool reduceMotion = false,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      livePriceProvider.overrideWith(_Quiet.new),
      polymarketMarketHistoryProvider
          .overrideWith((ref, arg) async => points ?? _week),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        locale: locale,
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: chart),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

String _start(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('kute-time-axis-start')))
    .data!;

String _end(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('kute-time-axis-end'))).data!;

const _chart = MarketChart(tokenId: 'tok', height: 200);

void main() {
  // No device has seen the nudge unless a test says so.
  var seen = true;
  setUp(() {
    seen = true;
    KuteZoomHint.debugReset(read: () => seen, write: () => seen = true);
  });
  tearDown(KuteZoomHint.debugReset);

  group('the time axis', () {
    testWidgets('a week: the day it starts, "Now" at the live edge',
        (tester) async {
      await _pump(tester, _chart);
      final start = DateTime.fromMillisecondsSinceEpoch(_week.first.timestamp
          .millisecondsSinceEpoch);
      expect(_start(tester), DateFormat.MMMd('en').format(start));
      expect(_end(tester), 'Now');
      // Out of the plot's height: the chart keeps its own.
      expect(tester.getSize(find.byType(MarketChart)).height, 200);
      expect(tester.getSize(find.byType(KuteTimeAxis)).height,
          kKuteTimeAxisHeight);
      // At the plot's two edges.
      final chart = tester.getRect(find.byType(MarketChart));
      final s = tester.getRect(find.byKey(const ValueKey('kute-time-axis-start')));
      final e = tester.getRect(find.byKey(const ValueKey('kute-time-axis-end')));
      expect(s.left, closeTo(chart.left, 0.5));
      expect(e.right, closeTo(chart.right, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('six hours: the time of day', (tester) async {
      await _pump(tester, _chart, points: _sixHours);
      expect(_start(tester),
          DateFormat.Hm('en').format(_sixHours.first.timestamp));
      expect(_end(tester), 'Now');
    });

    testWidgets('after a pinch and a pan the end is a time, not "Now"',
        (tester) async {
      await _pump(tester, _chart, points: _sixHours);
      final rect = tester.getRect(find.byType(MarketChart));
      final y = rect.top + 80;
      // Two fingers apart: zoom in.
      final a = await tester.startGesture(Offset(rect.center.dx - 30, y));
      final b = await tester.startGesture(Offset(rect.center.dx + 30, y),
          pointer: 2);
      for (var i = 1; i <= 6; i++) {
        await a.moveTo(Offset(rect.center.dx - 30 - i * 15, y));
        await b.moveTo(Offset(rect.center.dx + 30 + i * 15, y));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await tester.pump(const Duration(milliseconds: 300));
      final zoomedStart = _start(tester);
      expect(zoomedStart, isNot(DateFormat.Hm('en').format(_sixHours.first.timestamp)));
      // One finger to the right: back in time.
      final d = await tester.startGesture(Offset(rect.center.dx - 60, y));
      for (var i = 1; i <= 8; i++) {
        await d.moveTo(Offset(rect.center.dx - 60 + i * 20, y));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await d.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_end(tester), isNot('Now'));
      expect(_end(tester), matches(RegExp(r'^\d{2}:\d{2}$')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a resolved market never ends on "Now"', (tester) async {
      await _pump(
          tester, const MarketChart(tokenId: 'tok', height: 200, resolved: true));
      expect(_end(tester), isNot('Now'));
    });

    testWidgets('Portuguese: its own word and dates', (tester) async {
      await _pump(tester, _chart, locale: const Locale('pt'));
      expect(_end(tester), 'Agora');
      expect(_start(tester), DateFormat.MMMd('pt').format(_week.first.timestamp));
    });
  });

  group('the zoom nudge', () {
    testWidgets('plays once: in and back out, then never again',
        (tester) async {
      seen = false;
      await _pump(tester, _chart, points: _sixHours);
      final rest = _start(tester);
      await tester.pump(kKuteZoomNudgeDelay);
      expect(seen, isTrue, reason: 'the flag is written when it starts');
      // Halfway: zoomed in, so the window starts later.
      await tester.pump(const Duration(milliseconds: 400));
      expect(_start(tester), isNot(rest));
      expect(_end(tester), 'Now', reason: 'anchored on the newest point');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_start(tester), rest);

      // Another chart: no nudge.
      await _pump(tester, _chart, points: _sixHours);
      await tester.pump(kKuteZoomNudgeDelay);
      await tester.pump(const Duration(milliseconds: 400));
      expect(_start(tester), rest);
    });

    testWidgets('never under Reduce Motion, which counts as seen',
        (tester) async {
      seen = false;
      await _pump(tester, _chart, points: _sixHours, reduceMotion: true);
      final rest = _start(tester);
      await tester.pump(kKuteZoomNudgeDelay);
      await tester.pump(const Duration(milliseconds: 400));
      expect(_start(tester), rest);
      expect(seen, isTrue);
    });

    testWidgets('a touch stops it at once, the window back where it was',
        (tester) async {
      seen = false;
      await _pump(tester, _chart, points: _sixHours);
      final rest = _start(tester);
      await tester.pump(kKuteZoomNudgeDelay);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_start(tester), isNot(rest));
      final g = await tester.startGesture(
          tester.getCenter(find.byType(MarketChart)) - const Offset(0, 20));
      await tester.pump();
      expect(_start(tester), rest);
      await g.up();
      await tester.pump(const Duration(milliseconds: 600));
      expect(_start(tester), rest);
    });

    testWidgets('a finger already on the chart: no nudge', (tester) async {
      seen = false;
      await _pump(tester, _chart, points: _sixHours);
      final rest = _start(tester);
      final g = await tester.startGesture(
          tester.getCenter(find.byType(MarketChart)) - const Offset(0, 20));
      await tester.pump(kKuteZoomNudgeDelay);
      await tester.pump(const Duration(milliseconds: 400));
      await g.up();
      await tester.pump();
      expect(_start(tester), rest);
      expect(seen, isFalse, reason: 'still to be seen');
    });

    testWidgets('a chart with few points: no nudge', (tester) async {
      seen = false;
      await _pump(tester, _chart, points: _sixHours.take(10).toList());
      await tester.pump(kKuteZoomNudgeDelay);
      await tester.pump(const Duration(milliseconds: 400));
      expect(seen, isFalse);
    });
  });
}
