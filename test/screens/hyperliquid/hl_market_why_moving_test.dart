// "Why is it moving?" sits under the chart on every Investing market
// screen: a calm perp, a calm HIP-3 perp and a spot token all carry it
// (founder, 2026-10-25). Before, a 3 % gate left most perps without it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/chart_drawings_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_insights_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_intervals.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/screens/shared/ask_sal_chip.dart';
import 'package:kute/theme/app_theme.dart';

class _LivePrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState(mids: {});
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
      const HyperliquidTradingState(isInitialized: true, withdrawable: 100);
}

class _Layout extends HlChartLayoutNotifier {
  @override
  HlChartLayout build() => const HlChartLayout();
}

class _Prefs extends ChartPreferencesNotifier {
  @override
  ChartPreferences build(String arg) => const ChartPreferences();
}

// Calm: no change at all today.
const _btc = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 80000,
  midPx: 80000,
  prevDayPx: 80000,
  dayNtlVlm: 1e9,
  funding: 0.0000125,
);

const _nvda = HlMarket(
  coin: 'NVDA',
  wireCoin: 'xyz:NVDA',
  assetId: 110002,
  kind: HlMarketKind.perp,
  szDecimals: 3,
  maxLeverage: 10,
  onlyIsolated: false,
  markPx: 212.4,
  midPx: 212.4,
  prevDayPx: 211.3,
  dayNtlVlm: 1e7,
  dex: 'xyz',
  isHip3: true,
);

const _purr = HlMarket(
  coin: 'PURR',
  wireCoin: 'PURR/USDC',
  assetId: 10000,
  kind: HlMarketKind.spot,
  szDecimals: 0,
  maxLeverage: 1,
  onlyIsolated: false,
  markPx: 0.2,
  midPx: 0.2,
  prevDayPx: 0.2,
  dayNtlVlm: 1000,
);

Future<void> _pump(WidgetTester tester, HlMarket m) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidTradingProvider.overrideWith(_Trading.new),
      hyperliquidPerpPositionsProvider.overrideWith((_) => const []),
      hyperliquidSpotBalancesProvider.overrideWith((_) => const []),
      hyperliquidActivityFillsProvider.overrideWith((_) => const []),
      hyperliquidActiveAssetCtxProvider
          .overrideWith((ref, wire) => const Stream.empty()),
      hyperliquidExactMarketProvider.overrideWith((ref, key) => null),
      hyperliquidTradeFlowProvider
          .overrideWith((ref, coin) => Stream.value(const HlTradeFlowState())),
      hlChartLayoutProvider.overrideWith(_Layout.new),
      hlChartPreferencesProvider.overrideWith(_Prefs.new),
      aiEnabledProvider.overrideWith((ref) async => true),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HlMarketDetailSheet(market: m),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final m in [_btc, _nvda, _purr]) {
    testWidgets('${m.coin} (${m.kind.name}${m.isHip3 ? ', HIP-3' : ''}), '
        'calm: the row is there, asking why it moves', (tester) async {
      await _pump(tester, m);
      expect(find.byKey(const ValueKey('sal-why-moving-row')), findsOneWidget);
      final row = tester.widget<SalWhyMovingRow>(find.byType(SalWhyMovingRow));
      expect(row.question!.template, 'hl.moving_today');
      expect(row.question!.text, 'Why is ${m.coin} moving today?');
      expect(row.advisorContext.marketId, m.wireCoin);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
