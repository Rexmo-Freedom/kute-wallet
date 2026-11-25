// The Investing market sheet with no network, for the Advanced chart's
// drawing tools: a BTC perp on a made-up hourly tape, every read the
// sheet makes overridden. Shared by the drawing-tools tests and their
// on-demand render.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/chart_drawing.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/chart_drawings_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_candles_provider.dart';
import 'package:kute/providers/hyperliquid_funding_history_provider.dart';
import 'package:kute/providers/hyperliquid_insights_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_drawing_rail.dart'
    show hlGroupOf;
import 'package:kute/screens/hyperliquid/components/hl_drawing_tools.dart'
    show HlRailButton;
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart'
    show HlMarketDetailSheet;
import 'package:kute/screens/share/send_pick_session.dart'
    show SendPickSession;
import 'package:kute/theme/app_theme.dart';

const hlEditBtc = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 66000,
  midPx: 66000,
  prevDayPx: 65000,
  dayNtlVlm: 1e9,
);

final String hlEditBtcKey = hlChartDrawingMarketKey(hlEditBtc);

/// A gently trending, wiggling tape of [count] bars of [step], ending
/// near 66,000, the same for every interval asked for.
List<HyperliquidCandle> hlEditCandles(
    {int count = 120, Duration step = const Duration(hours: 1)}) {
  final start = DateTime.utc(2026, 10, 1);
  final out = <HyperliquidCandle>[];
  var price = 63500.0;
  for (var i = 0; i < count; i++) {
    final open = price;
    final close = open +
        math.sin(i / 6) * 160 +
        math.cos(i / 2.3) * 70 +
        22;
    final high = math.max(open, close) + 60 + (i % 5) * 18;
    final low = math.min(open, close) - 55 - (i % 3) * 21;
    out.add(HyperliquidCandle(
      openTime: start.add(step * i),
      closeTime: start.add(step * (i + 1)),
      open: open,
      high: high,
      low: low,
      close: close,
      volume: 10 + (i % 7) * 3,
    ));
    price = close;
  }
  return out;
}

class _LivePrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState(mids: {'BTC': 66000});
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
  @override
  void focus(String coin, {String? wire}) {}
  @override
  void unfocus(String coin) {}
  @override
  void acquire() {}
  @override
  void release() {}
}

class _Trading extends HyperliquidTradingNotifier {
  @override
  Future<HyperliquidTradingState> build() async =>
      const HyperliquidTradingState(isInitialized: true);
}

/// Pumps the market sheet [width] x [height], light unless [dark], with
/// [theme] from the app when given (the render) or a plain light theme.
Future<void> pumpHlEditSheet(
  WidgetTester tester, {
  double width = 390,
  double height = 844,
  ThemeData? theme,
  Widget Function(Widget child)? wrap,
  TransitionBuilder? appBuilder,
  List<HyperliquidCandle>? candles,
  // The account's own: a position and its fills on the market.
  List<HlPerpPosition> positions = const [],
  List<HlFill> fills = const [],
  // The market's daily candles (Pivots read them only while they are on).
  List<HyperliquidCandle> daily = const [],
  // The page opened from Send in send mode (send_pick_session.dart).
  SendPickSession? sendPick,
  // The Funding pane's reads (none: an empty history, no network).
  HlFundingFetch? fundingFetch,
  // The market shown (a BTC perp unless given).
  HlMarket market = hlEditBtc,
}) async {
  tester.view.physicalSize = Size(width, height) * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  final tape = candles ?? hlEditCandles();
  final sheet = HlMarketDetailSheet(market: market, sendPick: sendPick);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidAccountMarketProvider(market.coin)
          .overrideWith((_) => market),
      hyperliquidExactMarketProvider.overrideWith((ref, key) => market),
      hlFundingFetchProvider.overrideWithValue(
          fundingFetch ?? (coin, start, end) async => const []),
      hyperliquidActiveAssetCtxProvider
          .overrideWith((ref, wire) => const Stream.empty()),
      hyperliquidOrderbookProvider
          .overrideWith((ref, wire) => const Stream.empty()),
      hyperliquidPerpPositionsProvider.overrideWith((_) => positions),
      hyperliquidSpotBalancesProvider.overrideWith((_) => const []),
      hyperliquidActivityFillsProvider.overrideWith((_) => fills),
      hyperliquidTradingProvider.overrideWith(_Trading.new),
      hyperliquidLiveCandlesProvider.overrideWith(
          (ref, key) => Stream.value(HlLiveCandlesState(candles: tape))),
      hyperliquidDailyCandlesProvider.overrideWith((ref, wire) async => daily),
      hyperliquidTradeFlowProvider.overrideWith(
          (ref, coin) => Stream.value(const HlTradeFlowState())),
      aiEnabledProvider.overrideWith((ref) async => false),
    ],
    child: ScreenUtilInit(
      // As the app: the phone design below 600, the window itself above
      // (one design pixel is one logical pixel on a laptop).
      designSize: KuteLayout.designSizeFor(Size(width, height)),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ??
            ThemeData(
              splashFactory: NoSplash.splashFactory,
              extensions: [AppColorsExtension.light()],
            ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Wraps the navigator too: what a render captures with a sheet up.
        builder: appBuilder,
        home: wrap == null ? sheet : wrap(sheet),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// Opens the Advanced chart from the row under the chart.
Future<void> enterHlEdit(WidgetTester tester) async {
  final row = find.byKey(const ValueKey('hl-advanced-chart'));
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Takes [tool] in hand from the rail: its button when it is a group's
/// face, else from its group's fly-out (a long press on the group).
Future<void> armHlTool(WidgetTester tester, ChartDrawingTool tool) async {
  final button = find.byKey(ValueKey('hl-chart-rail-${tool.name}'));
  if (button.evaluate().isNotEmpty) {
    await tester.tap(button);
    await tester.pump();
    return;
  }
  final group = hlGroupOf(tool)!;
  await tester.longPress(find.descendant(
      of: find.byKey(ValueKey('hl-chart-rail-group-${group.id.name}')),
      matching: find.byType(HlRailButton)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.byKey(ValueKey('hl-tool-flyout-${tool.name}')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// The sheet's provider container, for seeding and reading drawings.
ProviderContainer hlEditContainer(WidgetTester tester) =>
    ProviderScope.containerOf(
        tester.element(find.byType(HlMarketDetailSheet)));

List<ChartDrawing> hlEditDrawings(WidgetTester tester) =>
    hlEditContainer(tester).read(hlChartDrawingsProvider(hlEditBtcKey));

ChartDrawingsNotifier hlEditDrawingsNotifier(WidgetTester tester) =>
    hlEditContainer(tester)
        .read(hlChartDrawingsProvider(hlEditBtcKey).notifier);
