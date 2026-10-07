// Chart tags never cover each other or the latest price: the shared rule
// every chart's right-edge tags are laid out by (kute_chart_tag_layout),
// the trade-lines layer drawing through it, and the Investing chart from
// the SP500 report (the entry on the latest price, the liquidation far
// under the window) end to end. One number format for every tag.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/shared/charts/kute_chart_drawings.dart';
import 'package:kute/screens/shared/charts/kute_chart_tag_layout.dart';
import 'package:kute/screens/shared/charts/kute_chart_trade_lines.dart';
import 'package:kute/theme/app_theme.dart';

bool _overlaps(double topA, double hA, double topB, double hB) =>
    topA < topB + hB && topB < topA + hA;

const _palette = ChartTradeLinePalette(
  up: Colors.green,
  down: Colors.red,
  warning: Colors.orange,
  neutral: Colors.grey,
  tagBackground: Colors.white,
  tagText: Colors.white,
);

/// A 400 x 300 price area over 50..150.
const _geom = KuteDrawingGeometry(
  timesMs: [0, 1, 2, 3],
  width: 400,
  priceH: 300,
  loP: 50,
  rangeP: 100,
  bucketMs: 1,
);

double _y(double price) => _geom.yForPrice(price);

/// The latest price's tag at [price]: 18 high, centred on its line.
KuteLatestTag _latest(double price) =>
    (y: _y(price), top: _y(price) - 9, height: 18);

/// Paints [lines] with the latest price at [latestAt] and returns the
/// tags' rects in the order drawn.
List<ChartTradeLineHit> _paint(List<ChartTradeLine> lines,
    {double? latestAt}) {
  final hits = <ChartTradeLineHit>[];
  final painter = KuteChartTradeLinesPainter(
    lines: lines,
    dragging: null,
    palette: _palette,
    resolveGeometry: (_) => _geom,
    repaintKey: null,
    hits: hits,
    formatPrice: (p) => '\$$p',
    latestTags: latestAt == null ? null : (_, __) => [_latest(latestAt)],
  );
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(400, 360));
  recorder.endRecording().dispose();
  return hits;
}

void main() {
  group('the shared rule', () {
    test('tags with room stay on their lines', () {
      expect(
        kuteLayoutTags([(top: 10, height: 16), (top: 100, height: 16)],
            fixed: [(top: 200, height: 18)], maxBottom: 300),
        [10, 100],
      );
    });

    test('a tag on a fixed tag goes to its own side of it', () {
      // Line just above the latest price's line: above its tag.
      final above = kuteLayoutTags([(top: 92, height: 16)],
          fixed: [(top: 95, height: 18)], maxBottom: 300);
      expect(above.single + 16, lessThanOrEqualTo(95 - 2));
      // Just below: under it.
      final below = kuteLayoutTags([(top: 98, height: 16)],
          fixed: [(top: 95, height: 18)], maxBottom: 300);
      expect(below.single, greaterThanOrEqualTo(95 + 18 + 2));
    });

    test('with no room on its own side it takes the other', () {
      // The latest price is at the very top of the plot.
      final tops = kuteLayoutTags([(top: 0, height: 16)],
          fixed: [(top: 0, height: 18)], maxBottom: 300);
      expect(tops.single, greaterThanOrEqualTo(18 + 2));
      // And at the very bottom.
      final low = kuteLayoutTags([(top: 284, height: 16)],
          fixed: [(top: 282, height: 18)], maxBottom: 300);
      expect(low.single + 16, lessThanOrEqualTo(282 - 2));
    });

    test('many tags around a fixed one: none overlaps, all inside', () {
      final tags = [
        for (final t in [80.0, 84.0, 90.0, 95.0, 99.0])
          (top: t, height: 17.0),
      ];
      const fixed = (top: 88.0, height: 18.0);
      final tops = kuteLayoutTags(tags, fixed: [fixed], maxBottom: 300);
      for (var i = 0; i < tops.length; i++) {
        expect(tops[i], greaterThanOrEqualTo(0));
        expect(tops[i] + 17, lessThanOrEqualTo(300));
        expect(_overlaps(tops[i], 17, fixed.top, fixed.height), isFalse,
            reason: 'tag $i on the latest price');
        for (var j = i + 1; j < tops.length; j++) {
          expect(_overlaps(tops[i], 17, tops[j], 17), isFalse,
              reason: 'tags $i and $j');
        }
      }
    });
  });

  group('trade-line tags', () {
    test('an entry on the latest price is written beside it, not over it',
        () {
      const entry = ChartTradeLine(
          id: 'position',
          kind: ChartTradeLineKind.entry,
          price: 120,
          label: 'Entry',
          detail: r'$120.0');
      final latest = _latest(120.1);
      final merged = _paint([entry], latestAt: 120.1).single.rect;
      expect(
          _overlaps(merged.top, merged.height, latest.top, latest.height),
          isFalse);
      // "Entry ≈" is shorter than "Entry · $120.0": the figure is the
      // latest price's, written once.
      final apart = _paint([entry], latestAt: 140).single.rect;
      expect(merged.width, lessThan(apart.width));
      // Away from the latest price it keeps its own line.
      expect(apart.center.dy, closeTo(_y(120), 0.5));
    });

    test('an entry just over the liquidation: both whole, apart', () {
      final hits = _paint(const [
        ChartTradeLine(
            id: 'position',
            kind: ChartTradeLineKind.entry,
            price: 80.4,
            label: 'Entry',
            detail: r'$80.4'),
        ChartTradeLine(
            id: 'liq',
            kind: ChartTradeLineKind.liquidation,
            price: 80,
            label: 'Liq',
            detail: r'$80.0'),
      ], latestAt: 140);
      final a = hits[0].rect, b = hits[1].rect;
      expect(_overlaps(a.top, a.height, b.top, b.height), isFalse);
    });

    test('a liquidation far under the window is pinned in the price area',
        () {
      final hits = _paint(const [
        ChartTradeLine(
            id: 'liq',
            kind: ChartTradeLineKind.liquidation,
            price: 1.486,
            label: 'Liq',
            detail: r'$1.5'),
      ], latestAt: 52);
      final r = hits.single.rect;
      // Inside the price area (never under it, where a volume strip
      // sits), and off the latest price's tag near the floor.
      expect(r.bottom, lessThanOrEqualTo(_geom.priceH));
      expect(r.top, greaterThanOrEqualTo(0));
      final latest = _latest(52);
      expect(_overlaps(r.top, r.height, latest.top, latest.height), isFalse);
    });
  });

  test('every tag of a chart writes prices in one format', () {
    // The SP500 report: "$1.486" beside "$7,748.3" read as a thousand.
    expect(formatHlPrice(7748.3), r'$7,748.3');
    expect(formatHlPriceLike(1.486, 7748.6), r'$1.5');
    expect(formatHlPriceLike(7748.3, 7748.6), r'$7,748.3');
    expect(formatHlPriceLike(64250.5, 110234), r'$64,251');
  });

  testWidgets('the SP500 chart: no tag over the live price or another tag',
      (tester) async {
    // Fifteen-minute bars climbing into the latest price; the entry sits
    // on it and the liquidation is far under the window.
    final candles = [
      for (var i = 0; i < 26; i++)
        HyperliquidCandle(
          openTime: DateTime.fromMillisecondsSinceEpoch(
              1790000000000 + i * 900000),
          closeTime: DateTime.fromMillisecondsSinceEpoch(
              1790000900000 + i * 900000),
          open: 7700 + (i > 18 ? (i - 18) * 6.0 : 0),
          high: 7704 + (i > 18 ? (i - 18) * 6.0 : 0),
          low: 7698 + (i > 18 ? (i - 18) * 6.0 : 0),
          close: 7702 + (i > 18 ? (i - 18) * 6.5 : 0),
          volume: i > 18 ? 60 : 5,
        ),
    ];
    final last = candles.last.close;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
            fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: HlCandlestickChart(
              marketKey: 'hl:perp:xyz:SP500',
              candles: candles,
              height: 380,
              showVolume: true,
              isLive: true,
              tradeLines: [
                ChartTradeLine(
                    id: 'position',
                    kind: ChartTradeLineKind.entry,
                    price: last - 0.3,
                    label: 'Entry',
                    detail: formatHlPriceLike(last - 0.3, last)),
                ChartTradeLine(
                    id: 'liq',
                    kind: ChartTradeLineKind.liquidation,
                    price: 1.486,
                    label: 'Liq',
                    detail: formatHlPriceLike(1.486, last)),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));
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
    final geom = layer.resolveGeometry(size)!;
    final latest = layer.latestTags!(size, geom);
    expect(latest, hasLength(1));
    final hits = layer.hits;
    expect(hits, hasLength(2));
    for (final h in hits) {
      for (final t in latest) {
        expect(_overlaps(h.rect.top, h.rect.height, t.top, t.height), isFalse,
            reason: '${h.id} covers the live price');
      }
      // Inside the price area: never over the volume strip.
      expect(h.rect.bottom, lessThanOrEqualTo(geom.priceH + 0.01));
    }
    expect(
        _overlaps(hits[0].rect.top, hits[0].rect.height, hits[1].rect.top,
            hits[1].rect.height),
        isFalse);
    expect(tester.takeException(), isNull);
  });
}
