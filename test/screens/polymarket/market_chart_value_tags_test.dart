// The value tags of a Predictions chart keep a column of their own past
// the end of the lines (market_chart.dart, poly_chart_tags.dart): a tag
// never covers a line and its text is never cut. An event whose outcomes
// carry the market question ("Will Flávio Bolsonaro win the 2026
// Brazilian presidential election?") writes the candidate, on a phone's
// width with large text too.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart';
import 'package:kute/screens/polymarket/components/poly_chart_tags.dart';
import 'package:kute/screens/shared/charts/kute_chart_core.dart';
import 'package:kute/theme/app_theme.dart';

const _hour = 3600000;
const _nowMs = 1790000000000;

/// A week of hourly points from [from] to [to].
List<PolymarketPricePoint> _week(double from, double to) => [
      for (var i = 0; i <= 168; i++)
        PolymarketPricePoint(
          timestamp:
              DateTime.fromMillisecondsSinceEpoch(_nowMs - (168 - i) * _hour),
          price: from + (to - from) * i / 168,
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

typedef _Line = ({String label, double from, double to});

const _flavio = 'Will Flávio Bolsonaro win the 2026 Brazilian presidential '
    'election?';
const _lula = 'Will Luiz Inácio Lula da Silva win the 2026 Brazilian '
    'presidential election?';

/// A tag's text as the chart lays it out ([_endpointTp]'s style).
double _measure(String text, double fontSize) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: kuteChartFontFamily,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

Future<void> _pump(WidgetTester tester, List<_Line> lines,
    {double width = 375, double textScale = 1.0}) async {
  tester.view.physicalSize = Size(width, 812);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final history = {
    for (var i = 0; i < lines.length; i++)
      'tok$i': _week(lines[i].from, lines[i].to),
  };
  await tester.pumpWidget(ProviderScope(
    overrides: [
      livePriceProvider.overrideWith(_Quiet.new),
      polymarketMarketHistoryProvider.overrideWith(
          (ref, arg) async => history[arg.tokenId] ?? const []),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: MarketChart(
              lines: [
                for (var i = 0; i < lines.length; i++)
                  MarketChartLine(
                    tokenId: 'tok$i',
                    color: [Colors.blue, Colors.purple, Colors.orange][i % 3],
                    label: lines[i].label,
                    livePrice: lines[i].to,
                  ),
              ],
              height: polyChartHeightFor(lines.length),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
  await tester.pumpAndSettle();
}

RenderBox _layer(WidgetTester tester, String painter) => tester.renderObject(
      find.byWidgetPredicate((w) =>
          w is CustomPaint && w.painter?.runtimeType.toString() == painter),
    );

/// The pills the tags layer draws.
List<Rect> _pills(WidgetTester tester) {
  final out = <Rect>[];
  expect(
    _layer(tester, '_TagsPainter'),
    paints
      ..everything((method, args) {
        if (method == #drawRRect) out.add((args.first as RRect).outerRect);
        return true;
      }),
  );
  return out;
}

/// How far right the lines (and their fill) reach.
double _linesRight(WidgetTester tester) {
  var right = 0.0;
  expect(
    _layer(tester, '_LinesPainter'),
    paints
      ..everything((method, args) {
        if (method == #drawPath) {
          final b = (args.first as Path).getBounds();
          if (b.right > right) right = b.right;
        }
        if (method == #drawCircle) {
          final c = args.first as Offset;
          final r = args[1] as double;
          if (c.dx + r > right) right = c.dx + r;
        }
        return true;
      }),
  );
  return right;
}

/// Each pill clear of the lines and whole: inside the chart, as wide as
/// its full text, never cut.
void _expectWholeAndClear(WidgetTester tester, List<_Line> lines) {
  final layer = _layer(tester, '_TagsPainter');
  final width = layer.size.width;
  final pills = _pills(tester);
  final right = _linesRight(tester);
  expect(pills, isNotEmpty);
  for (final p in pills) {
    expect(p.left, greaterThanOrEqualTo(right),
        reason: 'a pill at ${p.left} covers the lines (they reach $right)');
    expect(p.right, lessThanOrEqualTo(width + 0.01),
        reason: 'a pill runs past the chart');
  }

  // What the tags write: each line's name and chance, or its chance
  // alone; never an ellipsis.
  final style = polyTagStyle(
    labels: [for (final l in lines) l.label],
    width: width,
    measure: _measure,
  );
  for (final n in style.names) {
    expect(n, isNot(contains('…')));
  }
  final expected = <double>[];
  for (var i = 0; i < lines.length; i++) {
    final pct = polyChartTagPct(lines[i].to);
    final whole = '${style.names[i]} $pct';
    final text = style.names[i].isNotEmpty &&
            _measure(whole, style.fontSize) + 10 <=
                style.gutter - kPolyTagLead + 0.01
        ? whole
        : pct;
    expected.add(_measure(text, style.fontSize) + 10);
  }
  for (final p in pills) {
    expect(expected.any((w) => (w - p.width).abs() < 0.5), isTrue,
        reason: 'a pill ${p.width} wide writes none of the whole texts '
            '$expected');
  }
}

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final f in ['Regular', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
    }
    await inter.load();
  });

  final brazil = <_Line>[
    (label: _flavio, from: 0.55, to: 0.859),
    (label: _lula, from: 0.40, to: 0.135),
  ];

  test('a market question names its candidate', () {
    expect(polyChartOutcomeName(_flavio), 'Flávio Bolsonaro');
    expect(polyChartOutcomeName(_lula), 'Luiz Inácio Lula da Silva');
    expect(polyChartShortName(_flavio), 'Bolsonaro');
    final style = polyTagStyle(
        labels: [_flavio, _lula], width: 343, measure: _measure);
    expect(style.names.first, 'Bolsonaro');
    expect(style.names.last, isNot(contains('…')));
    expect(style.gutter, lessThanOrEqualTo(343 * kPolyTagMaxGutterShare));
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets(
        'the Brazil event at 375pt, text x$scale: tags whole, right of the '
        'lines, nothing overflows', (tester) async {
      await _pump(tester, brazil, textScale: scale);
      expect(tester.takeException(), isNull);
      _expectWholeAndClear(tester, brazil);
      expect(_pills(tester), hasLength(2));
    });
  }

  testWidgets('four candidates, two of them Bolsonaros', (tester) async {
    final lines = <_Line>[
      (label: 'Flávio Bolsonaro', from: 0.40, to: 0.62),
      (label: 'Luiz Inácio Lula da Silva', from: 0.35, to: 0.24),
      (label: 'Michelle Bolsonaro', from: 0.10, to: 0.08),
      (label: 'Tarcisio de Freitas', from: 0.15, to: 0.03),
    ];
    await _pump(tester, lines, textScale: 1.3);
    expect(tester.takeException(), isNull);
    _expectWholeAndClear(tester, lines);
    final style = polyTagStyle(
      labels: [for (final l in lines) l.label],
      width: _layer(tester, '_TagsPainter').size.width,
      measure: _measure,
    );
    // Told apart, not both "Bolsonaro".
    expect(style.names[0], isNot(style.names[2]));
  });

  testWidgets('a binary market: the line ends before its "Yes" tag',
      (tester) async {
    final lines = <_Line>[(label: 'Yes', from: 0.31, to: 0.18)];
    await _pump(tester, lines);
    expect(tester.takeException(), isNull);
    _expectWholeAndClear(tester, lines);
  });
}
