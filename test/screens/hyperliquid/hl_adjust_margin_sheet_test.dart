// The margin ticket says in plain words what the tap does, with the
// figures that change: the money in the position, the liquidation price
// and the Investing balance. Chips fill $10 / $25 / $50 / Max. An Add /
// Remove pill pair at the top switches the mode, and the summary and Max
// follow it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_adjust_margin_sheet.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
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

const _long = HlPerpPosition(
  coin: 'xyz:TSLA',
  szi: 2,
  entryPx: 350,
  positionValue: 740,
  unrealizedPnl: 40,
  returnOnEquity: 0.2,
  liquidationPx: 300,
  marginUsed: 200,
  leverageType: 'isolated',
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
  markPx: 370,
  midPx: 370,
  prevDayPx: 360,
  dayNtlVlm: 1,
  dex: 'xyz',
  isHip3: true,
);

Future<void> _pump(WidgetTester tester,
    {required bool add,
    HlMarket market = _market,
    String source = HlMarginSource.liquidationRow}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidTradingProvider.overrideWith(_Trading.new),
      hyperliquidPerpPositionsProvider.overrideWith((_) => const [_long]),
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
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: HlAdjustMarginSheet(
                position: _long, market: market, add: add, source: source),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('adding: the chips, then what moves where', (tester) async {
    await _pump(tester, add: true);
    expect(find.text('Add margin to TSLA'), findsOneWidget);
    for (final chip in const [r'$10', r'$25', r'$50', 'Max']) {
      expect(find.text(chip), findsOneWidget);
    }
    // Nothing typed: the CTA waits.
    final cta = tester.widget<PolySlipCta>(find.byType(PolySlipCta));
    expect(cta.enabled, isFalse);

    await tester.tap(find.text(r'$25'));
    await tester.pump();
    expect(
        find.textContaining(
            r'Adds $25.00 from your Investing balance to this position.'),
        findsOneWidget);
    expect(
        find.textContaining(r'Your Investing balance goes from $100.00 to '
            r'$75.00.'),
        findsOneWidget);
    expect(find.textContaining('Liquidation price moves from'),
        findsOneWidget);
    // The money in the position moves; its value (size x price) does not.
    expect(find.text('Your money in it'), findsOneWidget);
    expect(find.text(r'$200.00 → $225.00'), findsOneWidget);
    expect(find.text(r'$100.00 → $75.00'), findsOneWidget);
    expect(tester.widget<PolySlipCta>(find.byType(PolySlipCta)).enabled,
        isTrue);

    // Max is the whole Investing balance.
    await tester.tap(find.text('Max'));
    await tester.pump();
    expect(find.text(r'$100.00 → $0.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing: capped at what the venue lets come out',
      (tester) async {
    await _pump(tester, add: false);
    expect(find.text('Remove margin from TSLA'), findsOneWidget);
    // 740 at 5x keeps 148; 52 can come out.
    expect(find.text(r'Can remove: $52.00'), findsOneWidget);
    await tester.tap(find.text(r'$10'));
    await tester.pump();
    expect(
        find.textContaining(r'Takes $10.00 out of this position back to '
            'your Investing balance.'),
        findsOneWidget);
    expect(find.text(r'$200.00 → $190.00'), findsOneWidget);
    // $50 is within the 52 that can come out.
    await tester.tap(find.text(r'$50'));
    await tester.pump();
    expect(tester.widget<PolySlipCta>(find.byType(PolySlipCta)).enabled,
        isTrue);
    await tester.tap(find.text('Max'));
    await tester.pump();
    expect(find.text(r'$200.00 → $148.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Add / Remove pills switch the mode, the summary and Max',
      (tester) async {
    await _pump(tester, add: true);
    // Add by default.
    final pills = tester.widget<KutePillTabs>(find.byType(KutePillTabs));
    expect(pills.selectedIndex, 0);
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    expect(find.text(r'Available: $100.00'), findsOneWidget);
    await tester.tap(find.text('Max'));
    await tester.pump();
    expect(find.text(r'$100.00 → $0.00'), findsOneWidget);

    // Remove: the title, the cap and Max are the removable margin; what
    // was typed for Add starts afresh.
    await tester.tap(find.text('Remove'));
    await tester.pump();
    expect(
        tester.widget<KutePillTabs>(find.byType(KutePillTabs)).selectedIndex,
        1);
    expect(find.text('Remove margin from TSLA'), findsOneWidget);
    expect(find.text(r'Can remove: $52.00'), findsOneWidget);
    expect(find.text(r'$100.00 → $0.00'), findsNothing);
    expect(tester.widget<PolySlipCta>(find.byType(PolySlipCta)).enabled,
        isFalse);
    await tester.tap(find.text('Max'));
    await tester.pump();
    expect(find.text(r'$200.00 → $148.00'), findsOneWidget);
    expect(find.textContaining('Takes \$52.00 out of this position'),
        findsOneWidget);

    // And back.
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(find.text('Add margin to TSLA'), findsOneWidget);
    expect(find.text(r'Available: $100.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a market that locks isolated margin: Add only, no pills',
      (tester) async {
    const locked = HlMarket(
      coin: 'TSLA',
      wireCoin: 'xyz:TSLA',
      assetId: 110001,
      kind: HlMarketKind.perp,
      szDecimals: 3,
      maxLeverage: 10,
      onlyIsolated: true,
      marginMode: 'strictIsolated',
      markPx: 370,
      midPx: 370,
      prevDayPx: 360,
      dayNtlVlm: 1,
      dex: 'xyz',
      isHip3: true,
    );
    await _pump(tester, add: true, market: locked);
    expect(find.byType(KutePillTabs), findsNothing);
    expect(find.text('Add margin to TSLA'), findsOneWidget);
  });

  testWidgets('started says where the sheet was opened from', (tester) async {
    final seen = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => seen.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    await _pump(tester, add: true, source: HlMarginSource.alertBanner);
    final started =
        seen.lastWhere((e) => e.$1 == 'hyperliquid_margin_adjust_started').$2!;
    expect(started['source'], 'alert_banner');
    expect(started['action'], 'add');
    // No ids, addresses or balances.
    expect(started.keys, isNot(contains('address')));
    expect(started.keys, isNot(contains('balance')));
  });
}
