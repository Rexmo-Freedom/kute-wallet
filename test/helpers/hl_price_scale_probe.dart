// The Advanced chart's price scale as the render tree paints it, for the
// price scale's tests and its on-demand render (hl_chart_price_scale_*):
// a gold tape, the scale's labels, its price lines and the latest price's
// tag, read from the layers' paint calls.

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_model.dart';

/// 120 hourly bars around a gold price ([base] 4,123.4: "4,120.0" labels).
List<HyperliquidCandle> goldCandles({double base = 4123.4}) => [
      for (var i = 0; i < 120; i++)
        HyperliquidCandle(
          openTime: DateTime.utc(2026, 11, 1).add(Duration(hours: i)),
          closeTime: DateTime.utc(2026, 11, 1)
              .add(Duration(hours: i + 1, milliseconds: -1)),
          open: base + (i % 9) * base * 0.002,
          high: base + (i % 9) * base * 0.002 + base * 0.004,
          low: base + (i % 9) * base * 0.002 - base * 0.003,
          close: base + ((i + 3) % 9) * base * 0.002,
          volume: 10 + (i % 4).toDouble(),
        ),
    ];

Finder hlLayerFinder(String painter) => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter?.runtimeType.toString() == painter);

/// What a layer paints: its texts' boxes, its lines and its rounded rects.
({List<Rect> texts, List<(Offset, Offset)> lines, List<Rect> rrects})
    paintedBy(WidgetTester tester, String painter) {
  final texts = <Rect>[];
  final lines = <(Offset, Offset)>[];
  final rrects = <Rect>[];
  final f = hlLayerFinder(painter);
  if (f.evaluate().isEmpty) {
    return (texts: texts, lines: lines, rrects: rrects);
  }
  expect(
    tester.renderObject(f.first),
    paints
      ..everything((method, args) {
        if (method == #drawParagraph) {
          final p = args[0] as ui.Paragraph;
          final o = args[1] as Offset;
          texts.add(Rect.fromLTWH(o.dx, o.dy, p.longestLine, p.height));
        }
        if (method == #drawLine) {
          lines.add((args[0] as Offset, args[1] as Offset));
        }
        if (method == #drawRRect) rrects.add((args.first as RRect).outerRect);
        return true;
      }),
  );
  return (texts: texts, lines: lines, rrects: rrects);
}

/// The scale's labels (empty when the layer is not there).
List<Rect> scaleLabels(WidgetTester tester) =>
    paintedBy(tester, '_HlPriceScalePainter').texts;

/// The price lines across the plot.
List<(Offset, Offset)> priceLines(WidgetTester tester) =>
    paintedBy(tester, '_HlPriceLinesPainter').lines;

/// The latest price's tag: the data layer's widest rounded rect at the
/// right (bodies are a few px wide; the pill holds the price).
Rect lastPriceTag(WidgetTester tester) {
  final layer = tester.renderObject<RenderBox>(hlLayerFinder('_HlCandlePainter'));
  final pills = [
    for (final r in paintedBy(tester, '_HlCandlePainter').rrects)
      if (r.width >= 30 && r.left > layer.size.width * 0.6) r
  ];
  expect(pills, isNotEmpty, reason: 'the latest price has no tag');
  return pills.reduce((a, b) => a.right >= b.right ? a : b);
}

