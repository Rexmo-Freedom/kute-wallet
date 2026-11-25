// The Funding pane in the Advanced chart: switched on from the Chart
// sheet's Funding card on a perp it adds a pane under the price (its
// legend names the bar and its columns follow the history); a spot market
// offers no card and never draws the pane; an empty or failed history
// says so in the pane while the price chart stays.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/chart_drawings_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_catalog.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_sheet.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/hl_chart_edit_harness.dart';

const _pane = ValueKey('hl-chart-funding-pane');
const _legend = ValueKey('hl-chart-funding-legend');
const _state = ValueKey('hl-chart-funding-state');
const _card = ValueKey('hl-chart-indicator-$kHlFundingKey');

const _spot = HlMarket(
  coin: 'HYPE/USDC',
  wireCoin: '@107',
  assetId: 10107,
  kind: HlMarketKind.spot,
  szDecimals: 2,
  maxLeverage: 1,
  onlyIsolated: false,
  markPx: 40,
  midPx: 40,
  prevDayPx: 39,
  dayNtlVlm: 1e7,
);

/// One settlement an hour over the harness' tape, alternating sign.
Future<List<({int timeMs, double rate})>> _history(
    String coin, int start, int end) async {
  final tape = hlEditCandles();
  final first = tape.first.openTime.millisecondsSinceEpoch;
  final last = tape.last.closeTime.millisecondsSinceEpoch;
  return [
    for (var t = first + 3600000; t <= last; t += 3600000)
      if (t >= start && t <= end)
        (timeMs: t, rate: (t ~/ 3600000).isEven ? 0.00002 : -0.00001),
  ];
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

String _text(WidgetTester tester, ValueKey<String> key) {
  final text = tester.widget<Text>(find.byKey(key));
  return text.data ?? text.textSpan!.toPlainText();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('switching Funding on adds its pane on a perp', (tester) async {
    await pumpHlEditSheet(tester, fundingFetch: _history);
    await enterHlEdit(tester);
    expect(find.byKey(_pane), findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('hl-chart-edit-sheet-button')).last);
    await _settle(tester);
    final card = find.byKey(_card);
    await tester.ensureVisible(card);
    await tester.pump();
    await tester.tap(card);
    await _settle(tester);
    expect(
        hlEditContainer(tester)
            .read(hlChartPreferencesProvider(hlEditBtcKey))
            .indicators,
        contains(kHlFundingKey));
    await tester.tap(find.byKey(const ValueKey('hl-chart-sheet-close')).last);
    await _settle(tester);

    expect(find.byKey(_pane), findsOneWidget);
    expect(_text(tester, _legend), startsWith('Funding 1h'));
    expect(_text(tester, _legend), contains('Cumulative'));
    expect(find.byKey(_state), findsNothing);
  });

  testWidgets('an empty history says so',
      (tester) async {
    await pumpHlEditSheet(tester);
    hlEditContainer(tester)
        .read(hlChartPreferencesProvider(hlEditBtcKey).notifier)
        .setIndicators(['vol', kHlFundingKey]);
    await enterHlEdit(tester);
    await _settle(tester);
    expect(find.byKey(_pane), findsOneWidget);
    expect(_text(tester, _state), 'No funding for these dates');
  });

  testWidgets('a failed history says so; the price chart stays',
      (tester) async {
    await pumpHlEditSheet(tester,
        fundingFetch: (coin, start, end) async => throw Exception('down'));
    hlEditContainer(tester)
        .read(hlChartPreferencesProvider(hlEditBtcKey).notifier)
        .setIndicators(['vol', kHlFundingKey]);
    await enterHlEdit(tester);
    await _settle(tester);
    expect(_text(tester, _state), "Couldn't load funding");
    // The price chart is drawn all the same.
    expect(find.byKey(const ValueKey('hl-chart-edit-sheet-button')),
        findsOneWidget);
  });

  testWidgets('a spot market offers no Funding and never draws it',
      (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(390, 844) * 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: buildLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: HlChartSheet(
                market: _spot,
                marketKey: hlChartDrawingMarketKey(_spot),
                candles: hlEditCandles(),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    final scroll = find.byKey(const ValueKey('hl-chart-sheet-scroll'));
    await tester.drag(scroll, const Offset(0, -4000));
    await tester.pump();
    expect(find.byKey(const ValueKey('hl-chart-indicator-obv')), findsOneWidget);
    expect(find.byKey(_card), findsNothing);
  });

  testWidgets('a stored Funding on a spot market draws nothing',
      (tester) async {
    await pumpHlEditSheet(tester, market: _spot, fundingFetch: _history);
    hlEditContainer(tester)
        .read(hlChartPreferencesProvider(hlChartDrawingMarketKey(_spot))
            .notifier)
        .setIndicators(['vol', kHlFundingKey]);
    await _settle(tester);
    expect(find.byKey(_pane), findsNothing);
  });
}
