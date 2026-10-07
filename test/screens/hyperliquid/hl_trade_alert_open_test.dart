// A tap on a trade alert opens what it is about. The liquidation-risk
// banner on an isolated position opens the margin sheet in Add mode
// straight away, over the position screen; tapped again while they are
// up, nothing stacks (OpenOnce). On a cross position it opens the
// position screen alone: there is no margin to add there.

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
import 'package:kute/providers/hyperliquid_trade_alerts_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_adjust_margin_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_intervals.dart';
import 'package:kute/screens/hyperliquid/components/hl_position_detail_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_trade_alerts_host.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/tracking_service.dart';
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

HlPerpPosition _position(String type) => HlPerpPosition(
      coin: 'xyz:TSLA',
      szi: 2,
      entryPx: 350,
      positionValue: 620,
      unrealizedPnl: -80,
      returnOnEquity: -0.4,
      liquidationPx: 300,
      marginUsed: 120,
      leverageType: type,
      leverageValue: 5,
      maxLeverage: 10,
    );

const _market = HlMarket(
  coin: 'TSLA',
  wireCoin: 'xyz:TSLA',
  assetId: 110001,
  kind: HlMarketKind.perp,
  szDecimals: 3,
  maxLeverage: 10,
  onlyIsolated: false,
  markPx: 310,
  midPx: 310,
  prevDayPx: 360,
  dayNtlVlm: 1,
  dex: 'xyz',
  isHip3: true,
);

const _risk = HlTradeAlert(
  seq: 1,
  type: HlTradeAlertType.liquidationRisk,
  coin: 'TSLA',
  wire: 'xyz:TSLA',
  distance: 0.032,
  price: 300,
);

Future<void> _pump(WidgetTester tester, HlPerpPosition position,
    void Function(BuildContext) onTap) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidTradingProvider.overrideWith(_Trading.new),
      hyperliquidPerpPositionsProvider.overrideWith((_) => [position]),
      hyperliquidAccountMarketProvider('xyz:TSLA').overrideWith((_) => _market),
      hyperliquidSpotBalancesProvider.overrideWith((_) => const []),
      hyperliquidActivityFillsProvider.overrideWith((_) => const []),
      hyperliquidTradeFlowProvider
          .overrideWith((ref, coin) => Stream.value(const HlTradeFlowState())),
      hlChartLayoutProvider.overrideWith(_Layout.new),
      hlChartPreferencesProvider.overrideWith(_Prefs.new),
      aiEnabledProvider.overrideWith((ref) async => false),
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
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => onTap(context),
            child: const Text('banner'),
          ),
        ),
      ),
    ),
  ));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// The chart's own short timers go with the tree.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });

  testWidgets(
      'liquidation risk on an isolated position: the margin sheet '
      'in Add mode, once', (tester) async {
    final seen = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => seen.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    final p = _position('isolated');
    await _pump(tester, p, (context) {
      // Tapped twice, as a double tap on the banner would.
      openHlTradeAlert(context, _risk, held: [p], market: _market);
      openHlTradeAlert(context, _risk, held: [p], market: _market);
    });
    await tester.tap(find.text('banner'));
    await _settle(tester);

    expect(find.byType(HlPositionDetailSheet), findsOneWidget);
    expect(find.byType(HlAdjustMarginSheet), findsOneWidget);
    final sheet =
        tester.widget<HlAdjustMarginSheet>(find.byType(HlAdjustMarginSheet));
    expect(sheet.add, isTrue);
    expect(sheet.source, HlMarginSource.alertBanner);
    expect(tester.widget<KutePillTabs>(find.byType(KutePillTabs)).selectedIndex,
        0);
    expect(OpenOnce.isOpen(HlAdjustMarginSheet.routeName), isTrue);
    final started =
        seen.where((e) => e.$1 == 'hyperliquid_margin_adjust_started').toList();
    expect(started, hasLength(1));
    expect(started.single.$2!['source'], 'alert_banner');

    // Tapped again while it is up: still one of each.
    openHlTradeAlert(tester.element(find.byType(HlAdjustMarginSheet)), _risk,
        held: [p], market: _market);
    await _settle(tester);
    expect(find.byType(HlPositionDetailSheet), findsOneWidget);
    expect(find.byType(HlAdjustMarginSheet), findsOneWidget);
    await _close(tester);
  });

  testWidgets(
      'liquidation risk on a cross position: the position screen, '
      'no margin sheet', (tester) async {
    final p = _position('cross');
    await _pump(tester, p, (context) {
      openHlTradeAlert(context, _risk, held: [p], market: _market);
    });
    await tester.tap(find.text('banner'));
    await _settle(tester);
    expect(find.byType(HlPositionDetailSheet), findsOneWidget);
    expect(find.byType(HlAdjustMarginSheet), findsNothing);
    await _close(tester);
  });

  testWidgets(
      'a stop-loss alert about the position opens the position '
      'screen, not the margin sheet', (tester) async {
    final p = _position('isolated');
    const near = HlTradeAlert(
      seq: 2,
      type: HlTradeAlertType.stopLossNear,
      coin: 'TSLA',
      wire: 'xyz:TSLA',
      distance: 0.008,
      price: 305,
    );
    await _pump(tester, p, (context) {
      openHlTradeAlert(context, near, held: [p], market: _market);
    });
    await tester.tap(find.text('banner'));
    await _settle(tester);
    expect(find.byType(HlPositionDetailSheet), findsOneWidget);
    expect(find.byType(HlAdjustMarginSheet), findsNothing);
    await _close(tester);
  });
}
