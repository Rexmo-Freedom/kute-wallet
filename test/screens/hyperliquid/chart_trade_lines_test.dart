// Trade lines on the Hyperliquid chart: the position and working orders
// are tagged price lines; an editable line can be dragged by its tag
// and reports the dropped price once, in chart (price) coordinates.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/shared/charts/kute_chart_trade_lines.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/theme/app_theme.dart';

List<HyperliquidCandle> _candles() => [
      for (var i = 0; i < 10; i++)
        HyperliquidCandle(
          openTime:
              DateTime.fromMillisecondsSinceEpoch(1700000000000 + i * 60000),
          closeTime:
              DateTime.fromMillisecondsSinceEpoch(1700000060000 + i * 60000),
          open: 100 + i.toDouble(),
          high: 102 + i.toDouble(),
          low: 98 + i.toDouble(),
          close: 101 + i.toDouble(),
          volume: 10,
        ),
    ];

KuteChartTradeLinesPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<KuteChartTradeLinesPainter>()
    .single;

Finder get _surface => find.descendant(
    of: find.byType(HlCandlestickChart),
    matching: find.byWidgetPredicate(
        (w) => w is GestureDetector && w.onPanUpdate != null));

Future<void> _pump(
  WidgetTester tester, {
  required List<ChartTradeLine> lines,
  void Function(String, double)? onMoved,
  ValueChanged<String>? onTapped,
}) async {
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
          fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 400,
            child: HlCandlestickChart(
              marketKey: 'hl:perp::BTC',
              candles: _candles(),
              height: 240,
              showVolume: false,
              tradeLines: lines,
              onTradeLineMoved: onMoved,
              onTradeLineTapped: onTapped,
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

const _lines = [
  ChartTradeLine(
      id: 'position',
      kind: ChartTradeLineKind.entry,
      price: 104,
      label: 'Entry'),
  ChartTradeLine(
      id: 'order:7',
      kind: ChartTradeLineKind.limit,
      price: 100,
      label: 'Buy',
      detail: '0.5 @ 100',
      editable: true),
  ChartTradeLine(
      id: 'order:8',
      kind: ChartTradeLineKind.takeProfit,
      price: 300,
      label: 'TP',
      editable: true),
];

void main() {
  group('tags of lines close in price', () {
    // A stop just over the liquidation price, which is off the bottom of
    // the window and pinned to it: the stop's tag covered half of it.
    test('a stop beside the pinned liquidation tag moves up clear of it',
        () {
      final tops = spreadTradeTags(
        [(top: 318, height: 24), (top: 323, height: 17)],
        maxBottom: 340,
      );
      expect(tops[1], 323);
      expect(tops[0] + 24, lessThanOrEqualTo(tops[1] - 2));
    });

    test('a take-profit just over the entry: both stay whole, in order', () {
      final tops = spreadTradeTags(
        [(top: 100, height: 17), (top: 96, height: 24)],
        maxBottom: 340,
      );
      expect(tops[1], 96);
      expect(tops[0], greaterThanOrEqualTo(96 + 24 + 2));
    });

    test('tags with room stay on their lines', () {
      expect(
        spreadTradeTags(
          [(top: 10, height: 24), (top: 80, height: 17), (top: 300, height: 24)],
          maxBottom: 340,
        ),
        [10, 80, 300],
      );
    });

    test('three at the top keep off each other and inside the plot', () {
      final tops = spreadTradeTags(
        [(top: 0, height: 24), (top: 0, height: 17), (top: 4, height: 24)],
        maxBottom: 340,
      );
      final sorted = [...tops]..sort();
      expect(sorted.first, greaterThanOrEqualTo(0));
      expect(tops.toSet().length, 3);
      expect(tops[1], greaterThanOrEqualTo(tops[0] + 24 + 2));
      expect(tops[2], greaterThanOrEqualTo(tops[1] + 17 + 2));
    });
  });

  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('every line paints a tag; off-window lines pin to the edge',
      (tester) async {
    await _pump(tester, lines: _lines);
    final painter = _painter(tester);
    expect(painter.hits.map((h) => h.id), ['position', 'order:7', 'order:8']);
    final surface = tester.getRect(_surface);
    // The take-profit at 300 is far above the tape: its tag is pinned to
    // the top edge instead of vanishing. The live price's own tag holds
    // the very top (the tape ends on its high), so the pinned tag sits
    // just under it, never over it.
    final tp = painter.hits.firstWhere((h) => h.id == 'order:8');
    final size = surface.size;
    final live = painter.latestTags!(size, painter.resolveGeometry(size)!)
        .single;
    expect(live.top, lessThan(20));
    expect(tp.rect.top, closeTo(live.top + live.height + 2, 0.01));
    expect(tp.rect.right, closeTo(surface.width, 0.01));
  });

  testWidgets('dragging an editable tag reports the dropped price once',
      (tester) async {
    final moves = <(String, double)>[];
    await _pump(tester, lines: _lines, onMoved: (id, px) => moves.add((id, px)));
    final painter = _painter(tester);
    final surface = tester.getRect(_surface);
    final hit = painter.hits.firstWhere((h) => h.id == 'order:7');
    final start = surface.topLeft + hit.rect.center;
    final gesture = await tester.startGesture(start);
    await tester.pump();
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    // Mid-drag the line follows the finger.
    expect(_painter(tester).dragging?.id, 'order:7');
    expect(_painter(tester).dragging!.price, greaterThan(100));
    await gesture.up();
    await tester.pump();
    expect(moves.length, 1);
    expect(moves.single.$1, 'order:7');
    expect(moves.single.$2, greaterThan(100));
    expect(_painter(tester).dragging, isNull);
  });

  testWidgets('a non-editable tag never drags; a tap reports the line',
      (tester) async {
    final moves = <String>[];
    final taps = <String>[];
    await _pump(tester,
        lines: _lines,
        onMoved: (id, _) => moves.add(id),
        onTapped: taps.add);
    final painter = _painter(tester);
    final surface = tester.getRect(_surface);
    final entry = painter.hits.firstWhere((h) => h.id == 'position');
    final at = surface.topLeft + entry.rect.center;
    final gesture = await tester.startGesture(at);
    await gesture.moveBy(const Offset(0, 30));
    await gesture.up();
    await tester.pump();
    expect(moves, isEmpty);
    await tester.tapAt(at);
    await tester.pump();
    expect(taps, ['position']);
  });
}
