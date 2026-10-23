// Fill markers on the Hyperliquid chart: the user's own buys/sells are
// a dot at their time+price joined by a short stem to a ▲/▼ badge (buys
// below, sells above, flipped at an edge; same-side fills on the same or
// adjacent bars share one badge with a count). A tap on one opens a tooltip
// saying what happened (side, size, price, notional, time); a tap
// elsewhere, a scrub or a few seconds close it. Two fills on one candle
// share a single card with two rows.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlFill;
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/shared/charts/kute_chart_crosshair.dart';
import 'package:kute/theme/app_theme.dart';

const _t0 = 1700000000000;
const _minute = 60000;

List<HyperliquidCandle> _candles() => [
      for (var i = 0; i < 10; i++)
        HyperliquidCandle(
          openTime: DateTime.fromMillisecondsSinceEpoch(_t0 + i * _minute),
          closeTime:
              DateTime.fromMillisecondsSinceEpoch(_t0 + (i + 1) * _minute),
          open: 100 + i.toDouble(),
          high: 102 + i.toDouble(),
          low: 98 + i.toDouble(),
          close: 101 + i.toDouble(),
          volume: 10,
        ),
    ];

HlFill _fill({
  required String id,
  required int bar,
  required double px,
  required double sz,
  required bool buy,
  String dir = '',
  int offsetMs = 10000,
}) =>
    HlFill(
      coin: 'BTC',
      px: px,
      sz: sz,
      side: buy ? 'B' : 'A',
      time: _t0 + bar * _minute + offsetMs,
      closedPnl: 0,
      fee: 0,
      feeToken: 'USDC',
      oid: 1,
      hash: id,
      dir: dir,
      cloid: null,
      tradeId: id,
    );

/// A buy on bar 3, a sell on bar 7, and an entry + exit inside bar 5.
final _fills = [
  _fill(id: 't1', bar: 3, px: 104, sz: 0.5, buy: true, dir: 'Open Long'),
  _fill(id: 't2', bar: 7, px: 108, sz: 0.25, buy: false, dir: 'Close Long'),
  _fill(id: 't3', bar: 5, px: 105.5, sz: 1, buy: true, offsetMs: 5000),
  _fill(id: 't4', bar: 5, px: 106, sz: 1, buy: false, offsetMs: 40000),
];

Finder get _surface => find.descendant(
    of: find.byType(HlCandlestickChart),
    matching: find.byWidgetPredicate(
        (w) => w is GestureDetector && w.onPanUpdate != null));

/// The plot the data is drawn across: the chart less its tag column at
/// the right (the crosshair layer spans exactly that).
Finder get _plot => find.descendant(
    of: find.byType(HlCandlestickChart),
    matching: find.byType(KuteChartCrosshair));

HlFillTooltipPainter? _tooltip(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<HlFillTooltipPainter>()
    .singleOrNull;

List<HlFillMarker> _markers(WidgetTester tester, {bool line = false}) {
  final candles = _candles();
  return hlResolveFillMarkers(
    candles: candles,
    fills: _fills,
    size: tester.getSize(_plot),
    renderAsLine: line,
    showVolume: false,
    leadingClose: candles.last.close,
  );
}

HlFillMarker _marker(WidgetTester tester, String id, {bool line = false}) =>
    _markers(tester, line: line).firstWhere((m) => m.fill.tradeId == id);

Future<void> _pump(
  WidgetTester tester, {
  bool dark = false,
  bool line = false,
  bool drawingMode = false,
}) async {
  // Phone-sized surface so ScreenUtil scales 1:1 and the scrub readout
  // row above the plot keeps its designed height.
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        fontFamily: 'Inter',
        extensions: [
          dark ? AppColorsExtension.dark() : AppColorsExtension.light()
        ],
      ),
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
              // Candles by default; the area style exercises line geometry.
              style: line ? HlChartStyle.area : HlChartStyle.candles,
              fills: _fills,
              drawingMode: drawingMode,
              onDrawingSelected: (_) {},
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// Lets the auto-dismiss timer run out so no timer outlives the test.
Future<void> _settle(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 5));

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('markers land on the bar holding the fill, buys below sells above',
      () {
    final candles = _candles();
    const size = Size(400, 200);
    final markers = hlResolveFillMarkers(
      candles: candles,
      fills: [
        ..._fills,
        // Before the tape / after it: never plotted.
        _fill(id: 'early', bar: -3, px: 100, sz: 1, buy: true),
        _fill(id: 'late', bar: 12, px: 100, sz: 1, buy: true),
        // No price: never plotted.
        _fill(id: 'free', bar: 2, px: 0, sz: 1, buy: true),
      ],
      size: size,
      renderAsLine: false,
      showVolume: false,
    );
    expect(markers.map((m) => m.fill.tradeId), ['t1', 't2', 't3', 't4']);
    expect(markers.map((m) => m.barIndex), [3, 7, 5, 5]);
    const slot = 400 / 10;
    expect(markers[0].center.dx, closeTo(3.5 * slot, 1e-6));
    expect(markers[1].center.dx, closeTo(7.5 * slot, 1e-6));
    // The buy sits under its price, the sell above it, so an entry and an
    // exit at nearly the same price stay apart.
    final buy = markers[2], sell = markers[3];
    expect(buy.center.dx, sell.center.dx);
    expect(buy.center.dy, greaterThan(sell.center.dy));
    for (final m in markers) {
      expect(m.center.dy, inInclusiveRange(hlFillMarkerRadius, 200));
      expect(m.center.dy, lessThanOrEqualTo(200 - hlFillMarkerRadius));
      // A lone fill: its own badge, straight above/below its price dot.
      expect(m.count, 1);
      expect(m.lead, isTrue);
      expect(m.center.dx, m.dot.dx);
      expect(m.badgeAbove, !m.fill.isBuy);
      expect((m.center.dy - m.dot.dy).abs(), hlFillMarkerOffset);
      // Badge and dot never overlap: there is room for the stem.
      expect((m.center.dy - m.dot.dy).abs(),
          greaterThan(hlFillMarkerRadius + hlFillMarkerDotRadius + 4));
    }
    // The dot sits at the exact fill price.
    final geomBuy = markers[0];
    final y104 = hlResolveFillMarkers(
      candles: candles,
      fills: [_fill(id: 'x', bar: 3, px: 104, sz: 1, buy: false)],
      size: size,
      renderAsLine: false,
      showVolume: false,
    ).single.dot.dy;
    expect(geomBuy.dot.dy, closeTo(y104, 1e-9));
  });

  test('the badge is sized to read at a glance and easy to tap', () {
    expect(hlFillMarkerRadius * 2, inInclusiveRange(16, 18));
    expect(hlFillMarkerHitRadius, greaterThanOrEqualTo(22));
  });

  test('same-side fills on one or adjacent bars share one badge with a count',
      () {
    final candles = _candles();
    const size = Size(400, 200); // 40px per bar
    final markers = hlResolveFillMarkers(
      candles: candles,
      fills: [
        _fill(id: 'b1', bar: 4, px: 105, sz: 1, buy: true),
        _fill(id: 'b2', bar: 4, px: 104, sz: 1, buy: true, offsetMs: 20000),
        // The sell on the same bar keeps a badge of its own.
        _fill(id: 's1', bar: 4, px: 105.5, sz: 1, buy: false),
        // A buy far away: its own badge.
        _fill(id: 'b3', bar: 8, px: 108, sz: 1, buy: true),
      ],
      size: size,
      renderAsLine: false,
      showVolume: false,
    );
    HlFillMarker byId(String id) =>
        markers.firstWhere((m) => m.fill.tradeId == id);
    final b1 = byId('b1'), b2 = byId('b2'), s1 = byId('s1'), b3 = byId('b3');
    expect(b1.cluster, b2.cluster);
    expect(b1.center, b2.center);
    expect(b1.count, 2);
    expect(b2.count, 2);
    // A pill wide enough for the count.
    expect(b1.badgeHalfWidth, greaterThan(hlFillMarkerRadius));
    // One badge, painted once: by the lowest buy, so the badge (below it)
    // covers neither dot.
    expect([b1.lead, b2.lead].where((l) => l), hasLength(1));
    expect(b2.lead, isTrue);
    expect(b2.dot.dy, greaterThan(b1.dot.dy));
    expect(b1.center.dy, greaterThan(b2.dot.dy));
    // Each fill keeps its own dot.
    expect(b1.dot, isNot(b2.dot));
    expect(s1.cluster, isNot(b1.cluster));
    expect(s1.count, 1);
    expect(b3.cluster, isNot(b1.cluster));
    expect(b3.count, 1);

    // Adjacent bars on a dense tape merge too (10px per bar).
    final dense = hlResolveFillMarkers(
      candles: candles,
      fills: [
        _fill(id: 'd1', bar: 2, px: 103, sz: 1, buy: false),
        _fill(id: 'd2', bar: 3, px: 104, sz: 1, buy: false),
        _fill(id: 'd3', bar: 4, px: 105, sz: 1, buy: false),
      ],
      size: const Size(100, 200),
      renderAsLine: false,
      showVolume: false,
    );
    expect(dense.map((m) => m.cluster).toSet(), hasLength(1));
    expect(dense.first.count, 3);
    // The sells' badge rides the highest one.
    expect(dense.singleWhere((m) => m.lead).fill.tradeId, 'd3');

    // A tap on a shared badge opens every fill on it.
    final hit = hlHitTestFillMarkers(markers, b1.center);
    expect(hit.map((m) => m.fill.tradeId), containsAll(['b1', 'b2']));
  });

  test('a badge at the top or bottom edge flips to the other side', () {
    final candles = _candles();
    const size = Size(400, 200);
    // The highest high and the lowest low on the tape.
    final markers = hlResolveFillMarkers(
      candles: candles,
      fills: [
        _fill(id: 'top', bar: 9, px: candles[9].high, sz: 1, buy: false),
        _fill(id: 'bottom', bar: 0, px: candles[0].low, sz: 1, buy: true),
      ],
      size: size,
      renderAsLine: false,
      showVolume: false,
    );
    final top = markers.firstWhere((m) => m.fill.tradeId == 'top');
    final bottom = markers.firstWhere((m) => m.fill.tradeId == 'bottom');
    // A sell normally sits above; at the top it goes below its dot.
    expect(top.badgeAbove, isFalse);
    // A buy normally sits below; at the bottom it goes above its dot.
    expect(bottom.badgeAbove, isTrue);
    for (final m in markers) {
      expect(m.badge.top, greaterThanOrEqualTo(0));
      expect(m.badge.bottom, lessThanOrEqualTo(size.height));
      expect(m.badge.left, greaterThanOrEqualTo(0));
      expect(m.badge.right, lessThanOrEqualTo(size.width));
      expect(m.dot.dy, inInclusiveRange(0, size.height));
    }
  });

  test('crowded badges stack apart instead of piling up', () {
    final candles = _candles();
    // 15px per bar: pairs merge, and neighbouring pills would touch.
    const size = Size(150, 200);
    final markers = hlResolveFillMarkers(
      candles: candles,
      fills: [
        for (var i = 0; i < 10; i++)
          _fill(id: 'b$i', bar: i, px: 105, sz: 1, buy: true),
        for (var i = 0; i < 10; i++)
          _fill(id: 's$i', bar: i, px: 105.2, sz: 1, buy: false),
      ],
      size: size,
      renderAsLine: false,
      showVolume: false,
    );
    expect(markers, hasLength(20));
    final badges = [
      for (final m in markers)
        if (m.lead) m.badge
    ];
    expect(badges.length, lessThan(20));
    for (var i = 0; i < badges.length; i++) {
      final b = badges[i];
      expect(b.top, greaterThanOrEqualTo(0));
      expect(b.bottom, lessThanOrEqualTo(size.height));
      for (var j = i + 1; j < badges.length; j++) {
        expect(b.overlaps(badges[j]), isFalse,
            reason: 'badge $b overlaps ${badges[j]}');
      }
    }
  });

  test('the glyph takes white or the background, whichever reads better', () {
    // Light: white on both sides' colours.
    expect(hlFillGlyphColor(AppColors.marketUp, Colors.white), Colors.white);
    expect(hlFillGlyphColor(AppColors.marketDown, Colors.white), Colors.white);
    // Dark: black has the higher contrast on both.
    expect(hlFillGlyphColor(AppColors.marketUp, Colors.black), Colors.black);
    expect(hlFillGlyphColor(AppColors.marketDown, Colors.black), Colors.black);
  });

  test('hit test picks the nearest marker and groups fills on one bar', () {
    const a = Offset(100, 50), b = Offset(112, 50), c = Offset(300, 100);
    final markers = [
      HlFillMarker(fill: _fills[0], barIndex: 3, center: a),
      HlFillMarker(fill: _fills[3], barIndex: 5, center: b),
      HlFillMarker(fill: _fills[2], barIndex: 5, center: c),
    ];
    // Closer to a than to b.
    expect(hlHitTestFillMarkers(markers, const Offset(104, 52)).single.fill,
        _fills[0]);
    // Closer to b: every fill on b's bar comes back, oldest first.
    final grouped = hlHitTestFillMarkers(markers, const Offset(110, 54));
    expect(grouped.map((m) => m.fill.tradeId), ['t3', 't4']);
    // Beyond the hit radius: nothing.
    expect(
        hlHitTestFillMarkers(
            markers, Offset(100, 50 + hlFillMarkerHitRadius + 1)),
        isEmpty);
    // The price dot is a target too.
    final withDot = [
      HlFillMarker(
          fill: _fills[0],
          barIndex: 3,
          center: const Offset(100, 69),
          dot: const Offset(100, 50)),
    ];
    expect(hlHitTestFillMarkers(withDot, const Offset(100, 40)), hasLength(1));
    expect(hlHitTestFillMarkers(withDot, const Offset(100, 69 + 23)), isEmpty);
    // A pill reaches its whole width.
    final pill = [
      HlFillMarker(
          fill: _fills[0],
          barIndex: 3,
          center: const Offset(100, 50),
          badgeHalfWidth: 20),
    ];
    expect(hlHitTestFillMarkers(pill, const Offset(100 + 20 + 12, 50)),
        hasLength(1));
    expect(hlHitTestFillMarkers(const [], a), isEmpty);
  });

  test('the card stays inside the plot at every corner', () {
    const size = Size(300, 160);
    final entries = [
      HlFillTooltipEntry(
        identity: 't1',
        title: 'Bought 0.5 BTC at \$104.00',
        detail: 'Open Long · \$52.00 · 14 Nov, 22:16',
        color: AppColors.marketUp,
        detailColor: Colors.grey,
      ),
    ];
    for (final anchor in const [
      Offset(3, 3),
      Offset(297, 3),
      Offset(3, 157),
      Offset(297, 157),
      Offset(150, 80),
    ]) {
      final card = HlFillTooltipPainter.layoutCard(
        entries: entries,
        markers: [HlFillMarker(fill: _fills[0], barIndex: 0, center: anchor)],
        size: size,
        plotBottom: size.height,
      );
      expect(card.left, greaterThanOrEqualTo(0), reason: '$anchor');
      expect(card.top, greaterThanOrEqualTo(0), reason: '$anchor');
      expect(card.right, lessThanOrEqualTo(size.width), reason: '$anchor');
      expect(card.bottom, lessThanOrEqualTo(size.height), reason: '$anchor');
      expect(card.width, greaterThan(40));
      expect(card.height, greaterThan(20));
    }
    // With headroom the card sits above the marker; at the top edge it
    // drops below instead of being cut.
    final mid = HlFillTooltipPainter.layoutCard(
      entries: entries,
      markers: [
        HlFillMarker(fill: _fills[0], barIndex: 0, center: const Offset(150, 80))
      ],
      size: size,
      plotBottom: size.height,
    );
    expect(mid.bottom, lessThan(80 - hlFillMarkerRadius));
    final top = HlFillTooltipPainter.layoutCard(
      entries: entries,
      markers: [
        HlFillMarker(fill: _fills[0], barIndex: 0, center: const Offset(150, 3))
      ],
      size: size,
      plotBottom: size.height,
    );
    expect(top.top, greaterThan(3 + hlFillMarkerRadius));
    // The card never overlaps a volume strip under the price area.
    final clipped = HlFillTooltipPainter.layoutCard(
      entries: entries,
      markers: [
        HlFillMarker(
            fill: _fills[0], barIndex: 0, center: const Offset(150, 118))
      ],
      size: size,
      plotBottom: 120,
    );
    expect(clipped.bottom, lessThanOrEqualTo(120));
  });

  testWidgets('tapping a marker opens a readable tooltip; tapping away closes',
      (tester) async {
    await _pump(tester);
    expect(_tooltip(tester), isNull);
    final origin = tester.getRect(_surface).topLeft;
    await tester.tapAt(origin + _marker(tester, 't1').center);
    await tester.pump();
    final tip = _tooltip(tester);
    expect(tip, isNotNull);
    expect(tip!.entries, hasLength(1));
    final entry = tip.entries.single;
    expect(entry.title, 'Bought 0.5 BTC at \$104.00');
    final when = DateFormat('d MMM, HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(_fills[0].time));
    expect(entry.detail, 'Open Long · \$52.00 · $when');
    expect(entry.color, AppColors.marketUp);
    // A tap never starts a scrub: the crosshair stays idle.
    expect(
        tester.widget<KuteChartCrosshair>(find.byType(KuteChartCrosshair))
            .resolve,
        isNull);
    // Tap on empty plot: gone.
    await tester.tapAt(origin + const Offset(20, 5));
    await tester.pump();
    expect(_tooltip(tester), isNull);
  });

  testWidgets('a sell reads as Sold with its own colour', (tester) async {
    await _pump(tester);
    final origin = tester.getRect(_surface).topLeft;
    await tester.tapAt(origin + _marker(tester, 't2').center);
    await tester.pump();
    final entry = _tooltip(tester)!.entries.single;
    expect(entry.title, 'Sold 0.25 BTC at \$108.00');
    expect(entry.detail, startsWith('Close Long · \$27.00 · '));
    expect(entry.color, AppColors.marketDown);
    await _settle(tester);
  });

  testWidgets('two fills on one candle share a card with two rows',
      (tester) async {
    await _pump(tester);
    final origin = tester.getRect(_surface).topLeft;
    await tester.tapAt(origin + _marker(tester, 't4').center);
    await tester.pump();
    final tip = _tooltip(tester)!;
    expect(tip.entries.map((e) => e.title),
        ['Bought 1 BTC at \$105.50', 'Sold 1 BTC at \$106.00']);
    // No direction label on these: notional and time only.
    expect(tip.entries.first.detail, startsWith('\$105.50 · '));
    await _settle(tester);
  });

  testWidgets('a tap far from every marker opens nothing', (tester) async {
    await _pump(tester);
    final origin = tester.getRect(_surface).topLeft;
    final m = _marker(tester, 't1');
    // Left of the marker (bar 2 has no fill), past both badge and dot.
    await tester.tapAt(
        origin + m.center + Offset(-(hlFillMarkerHitRadius + 6), 0));
    await tester.pump();
    expect(_tooltip(tester), isNull);
  });

  testWidgets('the tooltip dismisses itself after a few seconds',
      (tester) async {
    await _pump(tester);
    final origin = tester.getRect(_surface).topLeft;
    await tester.tapAt(origin + _marker(tester, 't1').center);
    await tester.pump();
    expect(_tooltip(tester), isNotNull);
    await tester.pump(const Duration(seconds: 3));
    expect(_tooltip(tester), isNotNull);
    await tester.pump(const Duration(seconds: 2));
    expect(_tooltip(tester), isNull);
  });

  testWidgets('a scrub closes the tooltip', (tester) async {
    // Scrubbing swaps the header row for the price/time readout, which
    // under the test font runs 1px past its fixed 34px row (a pre-existing
    // layout detail of the readout, unrelated to the markers). Ignore that
    // overflow report so the gesture behaviour is what this test judges.
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
    await _pump(tester);
    final origin = tester.getRect(_surface).topLeft;
    await tester.tapAt(origin + _marker(tester, 't1').center);
    await tester.pump();
    expect(_tooltip(tester), isNotNull);
    // The crosshair is a long press, then slide (a plain drag pans).
    final gesture = await tester.startGesture(origin + const Offset(200, 40));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(_tooltip(tester), isNull);
    expect(
        tester.widget<KuteChartCrosshair>(find.byType(KuteChartCrosshair))
            .resolve,
        isNotNull);
    await gesture.up();
    await tester.pump();
  });

  testWidgets('markers and tooltip work on the area chart and in dark mode',
      (tester) async {
    await _pump(tester, line: true, dark: true);
    final origin = tester.getRect(_surface).topLeft;
    await tester.tapAt(origin + _marker(tester, 't1', line: true).center);
    await tester.pump();
    final tip = _tooltip(tester);
    expect(tip, isNotNull);
    expect(tip!.isDark, isTrue);
    expect(tip.entries.single.title, 'Bought 0.5 BTC at \$104.00');
    await _settle(tester);
  });

  testWidgets('in drawing select mode a marker tap opens the tooltip',
      (tester) async {
    await _pump(tester, drawingMode: true);
    final origin = tester.getRect(_surface).topLeft;
    await tester.tapAt(origin + _marker(tester, 't2').center);
    await tester.pump();
    expect(_tooltip(tester)?.entries.single.title, 'Sold 0.25 BTC at \$108.00');
    await _settle(tester);
  });
}
