// A long press on a Predictions chart shows the shared scrub card (the
// chance, its move since the start of the window, the time); nothing sits
// above the plot, so the scrubbed point is written once. A tap on a game
// event's marker puts the crosshair on it and the card names it. A many-outcome chart lists its lines on the
// card, leaders first. A position's "Bought" tag at the price now keeps
// off the line's value tag.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart';
import 'package:kute/screens/shared/charts/kute_chart_crosshair.dart';
import 'package:kute/screens/shared/charts/kute_chart_range_pills.dart';
import 'package:kute/screens/shared/charts/kute_chart_trade_lines.dart';
import 'package:kute/theme/app_theme.dart';

const _min = 60000;
const _nowMs = 1790000000000;

/// A week climbing from 20% to 80%.
final _week = [
  for (var i = 0; i <= 168; i++)
    PolymarketPricePoint(
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(_nowMs - (168 - i) * 60 * _min),
      price: 0.20 + 0.60 * i / 168,
    ),
];

final _low = [
  for (final p in _week)
    PolymarketPricePoint(timestamp: p.timestamp, price: p.price / 4),
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

Future<void> _pump(WidgetTester tester, Widget chart) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      livePriceProvider.overrideWith(_Quiet.new),
      polymarketMarketHistoryProvider.overrideWith(
          (ref, arg) async => arg.tokenId == 'low' ? _low : _week),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: chart),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<TestGesture> _press(WidgetTester tester, double at) async {
  final rect = tester.getRect(find.byType(MarketChart));
  final g = await tester.startGesture(
      Offset(rect.left + rect.width * at, rect.top + rect.height * 0.4));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 200));
  return g;
}

void main() {
  // Every layout's chart: a binary market's one line, a multi-outcome
  // market's lines, a game in play with its markers, a short round, a
  // resolved market. None has the change / LIVE row over the plot or the
  // range row under it.
  final layouts = <String, MarketChart>{
    'binary': const MarketChart(tokenId: 'tok', height: 200),
    'multi-outcome': const MarketChart(height: 200, lines: [
      MarketChartLine(tokenId: 'tok', label: 'High', color: Colors.blue),
      MarketChartLine(tokenId: 'low', label: 'Low', color: Colors.red),
    ]),
    'game in play': MarketChart(
      height: 200,
      inPlay: true,
      lines: const [
        MarketChartLine(tokenId: 'tok', label: 'NAVI', color: Colors.blue),
        MarketChartLine(tokenId: 'low', label: 'PARIVISION', color: Colors.red),
      ],
      gameStart: DateTime.fromMillisecondsSinceEpoch(_nowMs - 13 * 60 * _min),
      markers: const [
        MarketChartMarker(
            tMs: _nowMs - 60 * _min, label: 'Map 1 won', color: Colors.blue),
      ],
    ),
    'short round': const MarketChart(
        tokenId: 'tok', height: 200, shortMarket: true),
    'resolved': const MarketChart(tokenId: 'tok', height: 200, resolved: true),
  };
  for (final MapEntry(key: name, value: chart) in layouts.entries) {
    testWidgets('$name: no change / LIVE row and no range row', (tester) async {
      await _pump(tester, chart);
      expect(find.byType(KuteRangePills), findsNothing);
      for (final label in ['LIVE', '1H', '6H', '1D', '1W', '1M', 'ALL']) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(find.textContaining('past'), findsNothing);
      // The chart is the plot alone.
      expect(tester.getSize(find.byType(MarketChart)).height, 200);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('one line: the chance, its move and the time, once',
      (tester) async {
    await _pump(tester, const MarketChart(tokenId: 'tok', height: 200));
    // No change / LIVE row over the plot: the screen's hero has the figure.
    final summary = find.textContaining('past');
    expect(summary, findsNothing);
    final g = await _press(tester, 0.5);
    final card = find.byType(KuteScrubCard);
    expect(card, findsOneWidget);
    final texts = tester
        .widgetList<Text>(find.descendant(of: card, matching: find.byType(Text)))
        .map((t) => t.data!)
        .toList();
    // Value, move since the window's first point (up, so plus), time.
    expect(texts, hasLength(3));
    expect(texts[0], endsWith('%'));
    expect(texts[1], startsWith('+'));
    expect(texts[1], endsWith('%'));
    expect(texts[2], contains(':'));
    // The chance under the finger is written on the card alone.
    expect(summary, findsNothing);
    expect(find.text(texts[0]), findsOneWidget);
    expect(tester.takeException(), isNull);
    await g.up();
    await tester.pumpAndSettle();
    expect(card, findsNothing);
  });

  testWidgets('a tap on a game event names it on the scrub card, then lets go',
      (tester) async {
    final shown = <String>[];
    await _pump(
      tester,
      MarketChart(
        tokenId: 'tok',
        height: 200,
        markers: const [
          MarketChartMarker(
              tMs: _nowMs - 84 * 60 * _min,
              label: "Goal 38' 1-0",
              color: Colors.blue,
              kind: 'goal'),
        ],
        onMarkerShown: (m, n, via) => shown.add('${m.kind}:$n:$via'),
      ),
    );
    expect(find.textContaining('past'), findsNothing);
    final rect = tester.getRect(find.byType(MarketChart));
    // The week fills the plot; the marker sits half way across it.
    await tester.tapAt(Offset(rect.left + (rect.width - 12) / 2, rect.top + 100));
    await tester.pump();
    final card = find.byType(KuteScrubCard);
    expect(card, findsOneWidget);
    expect(
        find.descendant(of: card, matching: find.textContaining('Goal 38')),
        findsOneWidget);
    expect(shown, ['goal:1:tap']);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    expect(shown, ['goal:1:tap']);
  });

  testWidgets('many lines: every line on the card, leaders first',
      (tester) async {
    await _pump(
      tester,
      const MarketChart(height: 200, lines: [
        MarketChartLine(tokenId: 'low', label: 'Low', color: Colors.red),
        MarketChartLine(tokenId: 'tok', label: 'High', color: Colors.blue),
      ]),
    );
    final g = await _press(tester, 0.5);
    final card = find.byType(KuteScrubCard);
    expect(card, findsOneWidget);
    final labels = tester
        .widgetList<Text>(find.descendant(of: card, matching: find.byType(Text)))
        .map((t) => t.data!)
        .toList();
    expect(labels.indexOf('High'), lessThan(labels.indexOf('Low')));
    expect(tester.takeException(), isNull);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a Bought line at the price now keeps off the value tag',
      (tester) async {
    await _pump(
      tester,
      MarketChart(
        tokenId: 'tok',
        height: 200,
        surface: 'position',
        bought: [MarketChartBought(tokenId: 'tok', price: _week.last.price)],
      ),
    );
    final layer = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<KuteChartTradeLinesPainter>()
        .single;
    final size = tester.getSize(find
        .ancestor(
            of: find.byWidgetPredicate((w) =>
                w is CustomPaint && w.painter is KuteChartTradeLinesPainter),
            matching: find.byType(RepaintBoundary))
        .first);
    final latest = layer.latestTags!(size, layer.resolveGeometry(size)!);
    expect(latest, hasLength(1));
    final tag = layer.hits.single.rect;
    final value = latest.single;
    expect(
        tag.top >= value.top + value.height || tag.bottom <= value.top, isTrue,
        reason: 'the Bought tag covers the value tag');
    expect(tester.takeException(), isNull);
  });
}
