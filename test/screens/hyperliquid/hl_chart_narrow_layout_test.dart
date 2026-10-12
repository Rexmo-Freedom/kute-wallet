// The pro chart must lay out without throwing however little it is given:
// a plot narrower than one date label, an empty tape, or a single bar.
// 2.1.0/2.1.1 looped on an ArgumentError from the date axis (the clamp's
// upper bound fell below its lower one) and fell over on StateErrors from
// first/last on empty lists.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/theme/app_theme.dart';

HyperliquidCandle _bar(int i, double close) => HyperliquidCandle(
      openTime: DateTime.fromMillisecondsSinceEpoch(1700000000000 + i * 300000),
      closeTime:
          DateTime.fromMillisecondsSinceEpoch(1700000299999 + i * 300000),
      open: close - 1,
      high: close + 2,
      low: close - 2,
      close: close,
      volume: 10,
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<HyperliquidCandle> candles,
  required double width,
  bool drawingMode = true,
}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      theme: buildLightTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: HlCandlestickChart(
              candles: candles,
              height: 160,
              drawingMode: drawingMode,
            ),
          ),
        ),
      ),
    ),
  ));
  // Two frames: the first lays the plot out, the second paints the axis
  // and overlays against the measured size.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a plot narrower than one date label lays out', (tester) async {
    await _pump(tester,
        candles: [for (var i = 0; i < 40; i++) _bar(i, 100 + i.toDouble())],
        width: 50);
    expect(tester.takeException(), isNull);
    expect(find.byType(HlCandlestickChart), findsOneWidget);
  });

  testWidgets('an empty tape shows the no-data copy, no exception',
      (tester) async {
    await _pump(tester, candles: const [], width: 50);
    expect(tester.takeException(), isNull);
    await _pump(tester, candles: const [], width: 320, drawingMode: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single bar lays out at any width', (tester) async {
    await _pump(tester, candles: [_bar(0, 100)], width: 50);
    expect(tester.takeException(), isNull);
    await _pump(tester, candles: [_bar(0, 100)], width: 320);
    expect(tester.takeException(), isNull);
    await _pump(tester, candles: [_bar(0, 100)], width: 320, drawingMode: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a zero-width plot neither divides by zero nor throws',
      (tester) async {
    await _pump(tester, candles: [_bar(0, 100), _bar(1, 101)], width: 0);
    expect(tester.takeException(), isNull);
  });
}
