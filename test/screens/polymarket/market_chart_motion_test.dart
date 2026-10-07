// How a Predictions chart moves between ranges (there is no range row:
// the chart moves when what it picks its range from changes, such as a
// game's kickoff becoming known): the window and the scale ease from the
// old range's to the new one's, the view at rest is the same one the
// chart draws with no motion at all, and under Reduce Motion the new
// range is drawn at once.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart';
import 'package:kute/theme/app_theme.dart';

const _min = 60000;
const _hour = 60 * _min;
const _day = 24 * _hour;

/// The newest point of every series.
const _nowMs = 1790000000000;

/// ALL: a month drifting from 20% up to 80%.
final _all = [
  for (var i = 0; i <= 120; i++)
    PolymarketPricePoint(
      timestamp: DateTime.fromMillisecondsSinceEpoch(
          _nowMs - 30 * _day + i * (30 * _day ~/ 120)),
      price: 0.20 + 0.60 * i / 120,
    ),
];

/// 1H: the last hour, between 76% and 80%.
final _hourly = [
  for (var i = 0; i <= 60; i++)
    PolymarketPricePoint(
      timestamp: DateTime.fromMillisecondsSinceEpoch(_nowMs - _hour + i * _min),
      price: 0.76 + 0.04 * i / 60,
    ),
];

/// A second outcome on ALL, far under the first: 5% to 15%.
final _low = [
  for (final p in _all)
    PolymarketPricePoint(
        timestamp: p.timestamp, price: 0.05 + (p.price - 0.2) / 6),
];

class _Quiet extends LivePriceNotifier {
  _Quiet({this.live = false});
  final bool live;
  @override
  LivePriceState build() => LivePriceState(live: live);
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

const _shotKey = ValueKey('chart');

/// The default chart's game kickoff, set by [_kickOff]. A fresh one per
/// pump.
ValueNotifier<DateTime?> _kickoff = ValueNotifier(null);

/// [n] + 1 points from [startMs] to [endMs], drifting from [from] to [to].
List<PolymarketPricePoint> _ramp(
        int startMs, int endMs, int n, double from, double to) =>
    [
      for (var i = 0; i <= n; i++)
        PolymarketPricePoint(
          timestamp: DateTime.fromMillisecondsSinceEpoch(
              startMs + (endMs - startMs) * i ~/ n),
          price: from + (to - from) * i / n,
        ),
    ];

Future<void> _pumpChart(
  WidgetTester tester, {
  bool reduceMotion = false,
  ValueNotifier<List<MarketChartLine>>? lines,
  Widget? chart,
  Map<String, List<PolymarketPricePoint>>? history,
  bool live = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  _kickoff = ValueNotifier(null);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      livePriceProvider.overrideWith(() => _Quiet(live: live)),
      polymarketMarketHistoryProvider.overrideWith((ref, arg) async =>
          history?[arg.interval] ??
          (arg.tokenId == 'low'
              ? _low
              : arg.interval == '1h'
                  ? _hourly
                  : _all)),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: RepaintBoundary(
                  key: _shotKey,
                  child: chart ??
                      (lines == null
                          ? ValueListenableBuilder<DateTime?>(
                              valueListenable: _kickoff,
                              builder: (_, kickoff, __) => MarketChart(
                                  tokenId: 'tok',
                                  height: 200,
                                  gameStart: kickoff),
                            )
                          : ValueListenableBuilder<List<MarketChartLine>>(
                              valueListenable: lines,
                              builder: (_, v, __) =>
                                  MarketChart(lines: v, height: 200),
                            )),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  // The history lands, then the chart draws it.
  await tester.pump();
  await tester.pump();
  if (live) {
    // The live pulse never settles.
    await tester.pump(const Duration(seconds: 1));
  } else {
    await tester.pumpAndSettle();
  }
}

/// What the chart's line layer paints this frame: its scale and window.
({double minY, double maxY, int start, int end}) _painted(WidgetTester tester) {
  final layer = find.descendant(
    of: find.byKey(const ValueKey('lines')),
    matching: find.byType(CustomPaint),
  );
  final painter = (tester.widget<CustomPaint>(layer.first).painter as dynamic);
  return (
    minY: painter.domain.minY as double,
    maxY: painter.domain.maxY as double,
    start: painter.start as int,
    end: painter.end as int,
  );
}

Future<Uint8List> _pixels(WidgetTester tester) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  return bytes!;
}

/// The game kicks off half an hour ago: the chart moves from the month
/// it opened on to 1H, the shortest range that holds the game.
Future<void> _kickOff(WidgetTester tester,
    {Duration ago = const Duration(minutes: 30)}) async {
  _kickoff.value = DateTime.now().subtract(ago);
  // The rebuild, then the new range's history landing.
  await tester.pump();
  await tester.pump();
}

bool _between(double v, double a, double b) =>
    v > math.min(a, b) + 1e-9 && v < math.max(a, b) - 1e-9;

void main() {
  testWidgets(
      'mid-motion the scale and the window sit between the two '
      'ranges', (tester) async {
    await _pumpChart(tester);
    final before = _painted(tester);
    await _kickOff(tester);
    await tester.pump(const Duration(milliseconds: 125));
    final mid = _painted(tester);
    await tester.pumpAndSettle();
    final after = _painted(tester);

    // The scale fits each range's lines: wide on ALL, tight on 1H.
    expect(after.maxY - after.minY, lessThan((before.maxY - before.minY) / 4));
    expect(_between(mid.minY, before.minY, after.minY), isTrue,
        reason: 'minY $mid between $before and $after');
    expect(
        _between(mid.maxY - mid.minY, before.maxY - before.minY,
            after.maxY - after.minY),
        isTrue);
    // The window narrows from a month toward the hour.
    final midSpan = (mid.end - mid.start).toDouble();
    expect(
        _between(midSpan, (before.end - before.start).toDouble(),
            (after.end - after.start).toDouble()),
        isTrue);
    // The old lines are still fading out mid-motion, and gone at rest.
    expect(find.byKey(const ValueKey('lines-from')), findsNothing);
  });

  testWidgets('the old range\'s lines fade out while the new fade in',
      (tester) async {
    await _pumpChart(tester);
    await _kickOff(tester);
    await tester.pump(const Duration(milliseconds: 100));
    final out = find.byKey(const ValueKey('lines-from'));
    expect(out, findsOneWidget);
    final fadingOut = tester
        .widget<Opacity>(
            find.descendant(of: out, matching: find.byType(Opacity)))
        .opacity;
    final fadingIn = tester
        .widget<Opacity>(find.descendant(
            of: find.byKey(const ValueKey('lines')),
            matching: find.byType(Opacity)))
        .opacity;
    expect(fadingOut, greaterThan(0));
    expect(fadingOut, lessThan(1));
    expect(fadingIn, closeTo(1 - fadingOut, 1e-9));
    await tester.pumpAndSettle();
    expect(out, findsNothing);
  });

  testWidgets('at rest the chart is drawn exactly as with no motion at all',
      (tester) async {
    await _pumpChart(tester);
    await _kickOff(tester);
    await tester.pumpAndSettle();
    final moved = _painted(tester);
    final movedPixels = await _pixels(tester);

    await _pumpChart(tester, reduceMotion: true);
    await _kickOff(tester);
    await tester.pumpAndSettle();
    expect(_painted(tester), moved);
    expect(await _pixels(tester), movedPixels);
  });

  testWidgets('under Reduce Motion the new range is drawn at once',
      (tester) async {
    await _pumpChart(tester);
    await _kickOff(tester);
    await tester.pumpAndSettle();
    final settled = _painted(tester);

    await _pumpChart(tester, reduceMotion: true);
    await _kickOff(tester);
    // No time has passed: the first frame is already the final one.
    expect(_painted(tester), settled);
    expect(find.byKey(const ValueKey('lines-from')), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('under Reduce Motion a live chart\'s pulses stop',
      (tester) async {
    await _pumpChart(tester, live: true);
    // Live and moving: the endpoint pulse breathes. No LIVE pip or range
    // row over or under the plot.
    expect(find.text('LIVE'), findsNothing);
    expect(tester.binding.hasScheduledFrame, isTrue);

    await _pumpChart(tester, live: true, reduceMotion: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a line added glides the scale to its new fit', (tester) async {
    const first =
        MarketChartLine(tokenId: 'tok', color: Colors.green, label: 'A');
    const second =
        MarketChartLine(tokenId: 'low', color: Colors.blue, label: 'B');
    final lines = ValueNotifier<List<MarketChartLine>>([first]);
    addTearDown(lines.dispose);
    await _pumpChart(tester, lines: lines);
    final before = _painted(tester);

    lines.value = [first, second];
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final mid = _painted(tester);
    await tester.pump(const Duration(milliseconds: 120));
    final after = _painted(tester);
    await tester.pumpAndSettle();
    expect(_painted(tester), after, reason: 'settled within 150ms');

    // The scale reaches down to the new line, by way of the frames between.
    expect(after.minY, lessThan(before.minY - 0.1));
    expect(_between(mid.minY, before.minY, after.minY), isTrue,
        reason: '$mid between $before and $after');
  });

  testWidgets(
      'a game\'s chart moves from the game\'s window to the new '
      'range\'s, clamped to the game as at rest', (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final kickoff = now - 2 * _hour;
    final start = ValueNotifier<DateTime?>(
        DateTime.fromMillisecondsSinceEpoch(kickoff));
    addTearDown(start.dispose);
    // Opens on 6H (a game two hours old) zoomed to the game. The kickoff
    // then turns out to be half an hour ago: 1H, zoomed to the game.
    await _pumpChart(
      tester,
      chart: ValueListenableBuilder<DateTime?>(
        valueListenable: start,
        builder: (_, kickoff, __) =>
            MarketChart(tokenId: 'tok', height: 200, gameStart: kickoff),
      ),
      history: {
        '6h': _ramp(now - 6 * _hour, now, 360, 0.50, 0.70),
        '1h': _ramp(now - _hour, now, 60, 0.66, 0.70),
      },
    );
    final open = _painted(tester);
    final game = polyGameWindow(
        dataStartMs: now - 6 * _hour, dataEndMs: now, gameStartMs: kickoff)!;
    expect((open.start, open.end), (game.start, game.end));

    final late = now - 30 * _min;
    start.value = DateTime.fromMillisecondsSinceEpoch(late);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));
    final mid = _painted(tester);
    await tester.pumpAndSettle();
    final after = _painted(tester);
    final lateGame = polyGameWindow(
        dataStartMs: now - _hour, dataEndMs: now, gameStartMs: late)!;
    expect((after.start, after.end), (lateGame.start, lateGame.end));
    expect(after.end, now);
    expect(
        _between((mid.end - mid.start).toDouble(),
            (open.end - open.start).toDouble(),
            (after.end - after.start).toDouble()),
        isTrue);
    // Never outside what the two windows span.
    expect(mid.start, greaterThanOrEqualTo(open.start));
    expect(mid.end, lessThanOrEqualTo(now));
  });

  testWidgets('a pan moves the scale with the finger, no glide behind it',
      (tester) async {
    await _pumpChart(tester);
    await _kickOff(tester);
    await tester.pumpAndSettle();
    // Zoom into the newest ten minutes so there is room to pan.
    final chart = tester.getRect(find.byType(MarketChart));
    final plotY = chart.top + 100;
    final g1 = await tester.startGesture(Offset(chart.center.dx - 40, plotY));
    final g2 = await tester.startGesture(Offset(chart.center.dx + 40, plotY));
    await g1.moveTo(Offset(chart.left + 10, plotY));
    await g2.moveTo(Offset(chart.right - 10, plotY));
    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();

    final zoomed = _painted(tester);
    expect(zoomed.end - zoomed.start, lessThan(_hour ~/ 2));

    final g = await tester.startGesture(Offset(chart.center.dx, plotY));
    await g.moveBy(const Offset(20, 0));
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await g.moveBy(const Offset(40, 0));
      // The frame the drag lands in already paints the scale it fits.
      await tester.pump();
      final now = _painted(tester);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_painted(tester), now);
    }
    // The drag walked back in time, and the scale refitted as it went.
    final panned = _painted(tester);
    expect(panned.end, lessThan(zoomed.end));
    expect(panned.maxY, lessThan(zoomed.maxY));
    await g.up();
    await tester.pumpAndSettle();
  });
}
