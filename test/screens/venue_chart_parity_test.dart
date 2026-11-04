// One chart size for both venues (founder, 4 November 2026: the
// Predictions charts "sometimes just occupy way too much of the screen";
// "should the Polymarket graphs follow the same new fintech style in size
// and such"): the Investing market chart and every Predictions market,
// event and game chart draw their plot at one shared height
// (kKuteMarketChartHeight, scaled by height the same way), whatever the
// number of lines, and a Predictions chart no longer grows into the room
// a short list leaves. Every line is drawn at the one line width.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart'
    show HlCandlestickChart;
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart'
    show HlCandleChart;
import 'package:kute/screens/shared/charts/kute_chart_core.dart';
import 'package:kute/screens/shared/charts/kute_chart_time_axis.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/hl_chart_edit_harness.dart';

class _NoStars extends PolyWatchlistNotifier {
  @override
  List<String> build() => const [];
}

class _NoGames extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => const {};
  @override
  void connect() {}
}

class _NoTimeline extends PolyGameTimelineNotifier {
  @override
  PolyGameTimeline build(String arg) => PolyGameTimeline.empty;
}

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState(live: true);
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
  @override
  void acquire() {}
  @override
  void release() {}
}

PolymarketEvent _event(List<PolymarketOutcome> outcomes) => PolymarketEvent(
      id: '9',
      slug: 'brazil-presidential-election',
      title: 'Brazil Presidential Election',
      volume: 1000000,
      liquidity: 50000,
      category: 'politics',
      conditionId: '0x9',
      endDate: DateTime.now().add(const Duration(days: 30)),
      outcomes: outcomes,
    );

final _two = _event(const [
  PolymarketOutcome(
      gammaMarketId: 'a',
      name: 'Flávio Bolsonaro',
      price: 0.79,
      tokenId: 'ya',
      noTokenId: 'na'),
  PolymarketOutcome(
      gammaMarketId: 'b',
      name: 'Luiz Inácio Lula da Silva',
      price: 0.21,
      tokenId: 'yb',
      noTokenId: 'nb'),
]);

final _many = _event([
  for (var i = 0; i < 25; i++)
    PolymarketOutcome(
        gammaMarketId: 'm$i',
        name: 'Candidate $i',
        price: 0.18 - i * 0.006,
        tokenId: 't$i',
        noTokenId: 'n$i'),
]);

final _yesNo = _event(const [
  PolymarketOutcome(gammaMarketId: 'y', name: 'Yes', price: 0.6, tokenId: 'y'),
  PolymarketOutcome(gammaMarketId: 'y', name: 'No', price: 0.4, tokenId: 'n'),
]);

Future<void> _pump(WidgetTester tester, PolymarketEvent event,
    {Size size = const Size(430, 932)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      livePriceProvider.overrideWith(_Prices.new),
      sportsLiveProvider.overrideWith(_NoGames.new),
      polyGameTimelineProvider.overrideWith(_NoTimeline.new),
      polymarketActivePositionsProvider.overrideWithValue(const []),
      polymarketClaimablePositionsProvider.overrideWithValue(const []),
      aiEnabledProvider.overrideWith((ref) async => false),
      polyWatchlistProvider.overrideWith(_NoStars.new),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MarketDetailSheet(event: event),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

double _chartHeight(WidgetTester tester) =>
    tester.widget<MarketChart>(find.byType(MarketChart)).height;

/// The plot the Predictions chart draws: its height less the time axis
/// row under the plot.
double _pmPlot(WidgetTester tester) =>
    tester.getSize(find.byType(MarketChart)).height - kKuteTimeAxisHeight;

/// The plot the Investing market chart draws ([HlCandlestickChart.height]
/// in design units, scaled by height as the chart scales it).
double _hlPlot(WidgetTester tester) =>
    tester.widget<HlCandlestickChart>(find.byType(HlCandlestickChart)).height.h;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('one plot height and one line width for both venues', () {
    expect(kKuteMarketChartHeight, 260);
    expect(kuteStrokePaint(Colors.blue).strokeWidth, kKuteChartLineWidth);
    expect(kKuteChartLineWidth, 2.0);
  });

  for (final (name, event) in [
    ('a Yes / No market', _yesNo),
    ('two outcomes', _two),
    ('25 outcomes', _many),
  ]) {
    testWidgets('$name on a tall phone: the Investing plot over the time '
        'axis, never grown into the room, and it stays put', (tester) async {
      await http.runWithClient(() async {
        await _pump(tester, event);
        final expected = kKuteMarketChartHeight.h + kKuteTimeAxisHeight;
        expect(polyMarketChartHeight(), moreOrLessEquals(expected));
        expect(_chartHeight(tester), moreOrLessEquals(expected));
        expect(tester.getSize(find.byType(MarketChart)).height,
            moreOrLessEquals(expected));
        // Settled: later frames do not move it.
        await tester.pump(const Duration(seconds: 1));
        expect(_chartHeight(tester), moreOrLessEquals(expected));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => MockClient((_) async => http.Response('{}', 404)));
    });
  }

  for (final size in const [Size(390, 844), Size(320, 568)]) {
    testWidgets('${size.width.toInt()} x ${size.height.toInt()}: the '
        'Predictions and Investing market charts draw one plot height',
        (tester) async {
      double pm = 0;
      await http.runWithClient(() async {
        await _pump(tester, _two, size: size);
        pm = _pmPlot(tester);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => MockClient((_) async => http.Response('{}', 404)));

      await pumpHlEditSheet(tester, width: size.width, height: size.height);
      expect(tester.widget<HlCandleChart>(find.byType(HlCandleChart)).height,
          kKuteMarketChartHeight);
      final hl = _hlPlot(tester);
      expect(pm, moreOrLessEquals(hl, epsilon: 0.01));
      expect(hl, moreOrLessEquals(kKuteMarketChartHeight.h, epsilon: 0.01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
