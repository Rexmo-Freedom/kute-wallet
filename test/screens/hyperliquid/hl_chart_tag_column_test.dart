// The Investing chart keeps a tag column of its own at the right
// (hl_charts.dart, hlChartTagGutter): the candles, the line, the volume
// and the indicator panes end where it starts, and every label it writes
// beside them (the latest price, entry, liquidation, working orders, the
// price scale) sits in it, whole. No label covers the plotted data, none
// is cut, and the column holds still while the price ticks. Checked on a
// 375pt phone at text scale 1.3.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/shared/charts/kute_chart_trade_lines.dart';
import 'package:kute/theme/app_theme.dart';

/// 96 five-minute bars around Bitcoin's price, ending on [last].
List<HyperliquidCandle> _candles({double last = 86140}) => [
      for (var i = 0; i < 96; i++)
        HyperliquidCandle(
          openTime:
              DateTime.fromMillisecondsSinceEpoch(1700000000000 + i * 300000),
          closeTime:
              DateTime.fromMillisecondsSinceEpoch(1700000300000 + i * 300000),
          open: 86000 + (i % 7) * 40,
          high: 86300 + (i % 7) * 40,
          low: 85900 + (i % 7) * 40,
          close: i == 95 ? last : 86100 + (i % 5) * 40,
          volume: 10 + i % 4,
        ),
    ];

String _px(double p) => formatHlPriceLike(p, 86140);

final _lines = [
  ChartTradeLine(
      id: 'position',
      kind: ChartTradeLineKind.entry,
      price: 86120,
      label: 'Entry',
      detail: _px(86120)),
  ChartTradeLine(
      id: 'liq',
      kind: ChartTradeLineKind.liquidation,
      price: 85950,
      label: 'Liq',
      detail: _px(85950)),
  ChartTradeLine(
      id: 'order:7',
      kind: ChartTradeLineKind.limit,
      price: 86250,
      label: 'Sell',
      detail: '0.01234 @ ${_px(86250)}',
      isBuy: false,
      editable: true),
];

Future<void> _pump(
  WidgetTester tester, {
  double width = 375,
  double textScale = 1.3,
  HlChartStyle style = HlChartStyle.candles,
  bool drawingMode = false,
  double last = 86140,
  List<ChartTradeLine>? lines,
}) async {
  tester.view.physicalSize = Size(width, 812);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      theme: buildLightTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: HlCandlestickChart(
            marketKey: 'hl:perp::BTC',
            candles: _candles(last: last),
            height: 300,
            isLive: true,
            style: style,
            showVolume: true,
            indicators: const {'rsi'},
            drawingMode: drawingMode,
            tradeLines: lines ?? _lines,
            onTradeLineMoved: (_, __) {},
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

RenderBox _layer(WidgetTester tester, String painter) =>
    tester.renderObject(find.byWidgetPredicate((w) =>
        w is CustomPaint && w.painter?.runtimeType.toString() == painter));

KuteChartTradeLinesPainter _tradePainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<KuteChartTradeLinesPainter>()
    .single;

/// What a layer paints, by kind.
typedef _Calls = ({
  List<Rect> rrects,
  List<(Offset, Offset)> lines,
  List<Rect> paths,
  List<Rect> circles,
  List<Offset> texts,
});

_Calls _calls(WidgetTester tester, String painter) {
  final rrects = <Rect>[];
  final lines = <(Offset, Offset)>[];
  final paths = <Rect>[];
  final circles = <Rect>[];
  final texts = <Offset>[];
  expect(
    _layer(tester, painter),
    paints
      ..everything((method, args) {
        if (method == #drawRRect) rrects.add((args.first as RRect).outerRect);
        if (method == #drawRect) paths.add(args.first as Rect);
        if (method == #drawLine) {
          lines.add((args[0] as Offset, args[1] as Offset));
        }
        if (method == #drawPath) paths.add((args.first as Path).getBounds());
        if (method == #drawCircle) {
          circles.add(Rect.fromCircle(
              center: args[0] as Offset, radius: args[1] as double));
        }
        if (method == #drawParagraph) {
          final p = args[0] as ui.Paragraph;
          final o = args[1] as Offset;
          // A paragraph laid out wider than it writes keeps its text at
          // the start: its box is where the text is.
          texts.add(o);
          expect(p.didExceedMaxLines, isFalse, reason: 'a label is cut');
        }
        return true;
      }),
  );
  return (
    rrects: rrects,
    lines: lines,
    paths: paths,
    circles: circles,
    texts: texts,
  );
}

/// Where the plotted data must end: the chart less its tag column.
double _plotRight(WidgetTester tester) {
  final width = _layer(tester, '_HlCandlePainter').size.width;
  return width - _tradePainter(tester).tagColumn!;
}

/// The candles, the line, the volume and the price tag of the data layer:
/// the data ends where the column starts (the line's end dot may overhang
/// it by its radius), and every tag and label sits whole past the data.
void _expectDataClearOfTags(WidgetTester tester) {
  final layer = _layer(tester, '_HlCandlePainter');
  final width = layer.size.width;
  final plotRight = _plotRight(tester);
  expect(plotRight, lessThan(width));
  final c = _calls(tester, '_HlCandlePainter');
  final tags = [
    for (final r in c.rrects)
      if (r.left >= plotRight) r
  ];
  final bars = [
    for (final r in c.rrects)
      if (r.left < plotRight) r
  ];
  var dataRight = 0.0;
  for (final r in bars) {
    expect(r.right, lessThanOrEqualTo(plotRight + 0.01),
        reason: 'a bar at ${r.right} runs into the tag column');
    if (r.right > dataRight) dataRight = r.right;
  }
  for (final (a, b) in c.lines) {
    if (a.dy == b.dy) continue; // a price line runs up to its tag
    expect(a.dx, lessThanOrEqualTo(plotRight + 0.01),
        reason: 'a wick in the tag column');
    if (a.dx > dataRight) dataRight = a.dx;
  }
  for (final p in c.paths) {
    expect(p.right, lessThanOrEqualTo(plotRight + 0.01),
        reason: 'the line runs into the tag column');
    if (p.right > dataRight) dataRight = p.right;
  }
  for (final d in c.circles) {
    expect(d.center.dx, lessThanOrEqualTo(plotRight + 0.01),
        reason: 'the line ends in the tag column');
    if (d.right > dataRight) dataRight = d.right;
  }
  expect(tags, isNotEmpty, reason: 'the latest price has no tag');
  for (final r in tags) {
    expect(r.left, greaterThan(dataRight),
        reason: 'a tag at ${r.left} covers the data (it reaches $dataRight)');
    expect(r.right, lessThanOrEqualTo(width + 0.01),
        reason: 'a tag runs past the chart');
  }
  expect(c.texts, isNotEmpty);
  for (final t in c.texts) {
    expect(t.dx, greaterThan(dataRight),
        reason: 'a label at ${t.dx} covers the data (it reaches $dataRight)');
  }
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final inter = FontLoader('Inter');
    for (final f in ['Regular', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
    }
    await inter.load();
  });

  test('the price template has a digit to spare and no ellipsis', () {
    expect(hlPriceTagTemplate(85900, 86340), r'$000,000');
    expect(hlPriceTagTemplate(9990.5, 10020), r'$00,000.0');
    expect(hlPriceTagTemplate(0.012, 0.0131), r'$00.0000');
    expect(hlPriceTagTemplate(85900, 86340), isNot(contains('…')));
  });

  test('a trade tag writes a shorter whole text when the column is narrow', () {
    final line = _lines[2];
    final texts = kuteTradeTagTexts(line, price: _px(line.price));
    expect(texts, [
      'Sell · 0.01234 @ \$86,250',
      'Sell · \$86,250',
      'Sell',
    ]);
    for (final t in texts) {
      expect(t, isNot(contains('…')));
    }
  });

  for (final style in [HlChartStyle.candles, HlChartStyle.area]) {
    testWidgets(
        '${style.name} at 375pt, text x1.3: the data ends before the tag '
        'column, every label whole inside it', (tester) async {
      await _pump(tester, style: style);
      expect(tester.takeException(), isNull);
      _expectDataClearOfTags(tester);
    });
  }

  testWidgets(
      'trade-line tags sit whole in the column, their lines stop at '
      'it', (tester) async {
    await _pump(tester);
    expect(tester.takeException(), isNull);
    final painter = _tradePainter(tester);
    final layer = _layer(tester, 'KuteChartTradeLinesPainter');
    final width = layer.size.width;
    final plotRight = _plotRight(tester);
    expect(
        painter.hits.map((h) => h.id).toSet(), {'position', 'liq', 'order:7'});
    for (final h in painter.hits) {
      expect(h.rect.left, greaterThanOrEqualTo(plotRight),
          reason: '${h.id} covers the candles');
      expect(h.rect.right, lessThanOrEqualTo(width + 0.01),
          reason: '${h.id} runs past the chart');
      // As wide as one of its whole texts.
      final line = _lines.firstWhere((l) => l.id == h.id);
      final widths = [
        for (final arrow in ['', '▲ ', '▼ '])
          for (final t
              in kuteTradeTagTexts(line, price: _px(line.price), arrow: arrow))
            kuteTradeTagWidth(
                line, (kuteTradeTagPainter(t, Colors.black)..layout()).width),
        for (final t
            in kuteTradeTagTexts(line, price: _px(line.price), atLatest: true))
          kuteTradeTagWidth(
              line, (kuteTradeTagPainter(t, Colors.black)..layout()).width),
      ];
      expect(widths.any((w) => (w - h.rect.width).abs() < 0.5), isTrue,
          reason: '${h.id} is ${h.rect.width} wide, none of $widths');
    }
    final c = _calls(tester, 'KuteChartTradeLinesPainter');
    for (final (a, b) in c.lines) {
      if (a.dy != b.dy) continue;
      expect(b.dx, lessThanOrEqualTo(plotRight + 8 + 0.01),
          reason: 'a trade line runs under the tags');
    }
    for (final t in c.texts) {
      expect(t.dx, greaterThanOrEqualTo(plotRight));
    }
  });

  testWidgets(
      'the price scale and the RSI pane write their values in the '
      'column', (tester) async {
    await _pump(tester, drawingMode: true);
    expect(tester.takeException(), isNull);
    final plotRight = _plotRight(tester);
    final scale = _calls(tester, '_HlPriceScalePainter');
    expect(scale.texts, isNotEmpty);
    for (final t in scale.texts) {
      expect(t.dx, greaterThanOrEqualTo(plotRight),
          reason: 'a scale label covers the candles');
    }
    for (final (_, b) in scale.lines) {
      expect(b.dx, lessThanOrEqualTo(plotRight + 0.01));
    }
    final pane = _calls(tester, '_HlPanePainter');
    expect(pane.texts, isNotEmpty);
    for (final t in pane.texts) {
      expect(t.dx, greaterThanOrEqualTo(plotRight),
          reason: 'an RSI label covers its line');
    }
    for (final p in pane.paths) {
      expect(p.right, lessThanOrEqualTo(plotRight + 0.01));
    }
    _expectDataClearOfTags(tester);
  });

  testWidgets('the column holds still while the price ticks', (tester) async {
    await _pump(tester, last: 86140);
    final before = _tradePainter(tester).tagColumn;
    await _pump(tester, last: 86187.5);
    expect(_tradePainter(tester).tagColumn, before);
    await _pump(tester, last: 86011);
    expect(_tradePainter(tester).tagColumn, before);
  });

  testWidgets('a narrow chart still writes its tags whole', (tester) async {
    await _pump(tester, width: 320);
    expect(tester.takeException(), isNull);
    _expectDataClearOfTags(tester);
    final painter = _tradePainter(tester);
    final width = _layer(tester, 'KuteChartTradeLinesPainter').size.width;
    for (final h in painter.hits) {
      expect(h.rect.right, lessThanOrEqualTo(width + 0.01));
    }
  });
}
