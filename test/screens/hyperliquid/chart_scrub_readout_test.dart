// Scrubbing the Investing chart shows the shared scrub card (the price,
// its change since the first bar on screen, the time) inside the plot on
// a phone, and leaves the row under the plot on the change over the
// window: the scrubbed bar is written once.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/shared/charts/kute_chart_crosshair.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/theme/app_theme.dart';

List<HyperliquidCandle> _candles(int n) => [
      for (var i = 0; i < n; i++)
        HyperliquidCandle(
          openTime:
              DateTime.fromMillisecondsSinceEpoch(1700000000000 + i * 300000),
          closeTime:
              DateTime.fromMillisecondsSinceEpoch(1700000300000 + i * 300000),
          open: 86000 + (i % 7) * 40,
          high: 86200 + (i % 7) * 40,
          low: 85900 + (i % 7) * 40,
          close: 86100 + (i % 5) * 40,
          volume: 10,
        ),
    ];

void main() {
  for (final size in const [Size(393, 852), Size(430, 932), Size(360, 780)]) {
    testWidgets('the scrub card fits at ${size.width.round()} pt',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // The app's theme is Material 3: its body text is 1.43 high.
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: HlCandlestickChart(
                marketKey: 'hl:perp::BTC',
                candles: _candles(96),
                height: 380,
                style: HlChartStyle.area,
                summaryBelow: true,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      final plot = tester.getRect(find.byType(HlCandlestickChart));
      final gesture = await tester.startGesture(
          Offset(plot.left + plot.width * 0.4, plot.top + 150));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 300));
      final card = find.byType(KuteScrubCard);
      expect(card, findsOneWidget);
      expect(
          find.descendant(of: card, matching: find.textContaining('Nov 1')),
          findsOneWidget);
      expect(find.descendant(of: card, matching: find.textContaining(r'$')),
          findsOneWidget);
      expect(tester.getRect(card).right,
          lessThanOrEqualTo(tester.getRect(find.byType(HlCandlestickChart)).right));
      // The row keeps the window's change, not the bar's time.
      expect(find.textContaining('past'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
    });
  }
}
