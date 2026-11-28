// The Orders sheet and protective orders:
//
//   * a row names its kind in the app's words ("Stop market"), never the
//     venue's raw "Stop Market", and its fill in a localized line;
//   * Cancel all asks first, saying how many orders it removes and how
//     many of them protect a position; nothing is cancelled without the
//     tap;
//   * on EXPANDED (the web) the sheet opens as the side panel, never a
//     sheet across the window.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/platform/kute_layout.dart' show KuteLayout;
import 'package:kute/platform/kute_wide_frames.dart'
    show KuteSideFlow, kuteSidePanelWidth;
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/hyperliquid_user_events_provider.dart';
import 'package:kute/screens/hyperliquid/components/open_orders_sheet.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/theme/app_theme.dart';

const _btc = HlMarket(
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

const _orders = [
  HlOpenOrder(
    coin: 'BTC',
    oid: 1,
    isBuy: false,
    limitPx: 57000,
    sz: 0.5,
    origSz: 0.5,
    timestamp: 2,
    cloid: null,
    reduceOnly: true,
    orderType: 'Stop Market',
    isTrigger: true,
    triggerPx: 60000,
  ),
  HlOpenOrder(
    coin: 'BTC',
    oid: 2,
    isBuy: true,
    limitPx: 64000,
    sz: 0.25,
    origSz: 0.5,
    timestamp: 1,
    cloid: null,
    reduceOnly: false,
    orderType: 'Limit',
    isTrigger: false,
    triggerPx: null,
  ),
];

class _Trading extends HyperliquidTradingNotifier {
  int cancelAlls = 0;
  @override
  Future<HyperliquidTradingState> build() async =>
      const HyperliquidTradingState(isInitialized: true, openOrders: _orders);
  @override
  Future<int> cancelAllOrders() async {
    cancelAlls++;
    return 0;
  }
}

class _Events extends HlUserEventsNotifier {
  @override
  HlUserEventsState build() => const HlUserEventsState();
}

Future<_Trading> _pump(WidgetTester tester,
    {Size size = const Size(430, 932), bool asSheet = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final trading = _Trading();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      hyperliquidTradingProvider.overrideWith(() => trading),
      hyperliquidUserEventsProvider.overrideWith(_Events.new),
      hyperliquidWireMarketProvider.overrideWith((ref, wire) => _btc),
      hyperliquidAccountMarketProvider.overrideWith((ref, coin) => _btc),
    ],
    child: ScreenUtilInit(
      designSize: KuteLayout.designSizeFor(size),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: asSheet
              ? Builder(
                  builder: (context) => Center(
                      child: TextButton(
                          onPressed: () => showHlOpenOrdersSheet(context),
                          child: const Text('open orders'))))
              : const HlOpenOrdersSheet(),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return trading;
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('rows name their kind in the app\'s words, the fill localized',
      (tester) async {
    await _pump(tester);
    expect(find.text('Stop market'), findsOneWidget);
    expect(find.text('Stop Market'), findsNothing);
    expect(find.text('Limit'), findsOneWidget);
    expect(find.text('0.25 of 0.5 left'), findsOneWidget);
    expect(find.text('50% filled'), findsOneWidget);
    expect(find.textContaining('partially matched'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cancel all asks first, saying what it removes; only the tap '
      'cancels', (tester) async {
    final trading = await _pump(tester);
    await tester.tap(find.text('Cancel all'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel all orders?'), findsOneWidget);
    expect(
        find.text('This cancels every open order (2), the stops protecting '
            'a position included (1).'),
        findsOneWidget);
    // Cancel: nothing happens.
    await tester.tap(find.descendant(
        of: find.byType(AppBottomSheetTextButton),
        matching: find.text('Cancel')));
    await tester.pumpAndSettle();
    expect(trading.cancelAlls, 0);
    // The confirm's own button cancels.
    await tester.tap(find.text('Cancel all'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hl-order-confirm-cta')));
    await tester.pumpAndSettle();
    expect(trading.cancelAlls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('EXPANDED (the web): the Orders sheet opens as the side panel',
      (tester) async {
    KuteSideFlow.reset();
    addTearDown(KuteSideFlow.reset);
    const laptop = Size(1440, 900);
    await _pump(tester, size: laptop, asSheet: true);
    await tester.tap(find.text('open orders'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final card = find.ancestor(
        of: find.byType(HlOpenOrdersSheet),
        matching: find.byKey(const ValueKey('kute-dialog-card')));
    expect(card, findsOneWidget);
    final rect = tester.getRect(card);
    expect(rect.right, laptop.width);
    expect(rect.top, 0);
    expect(rect.height, laptop.height);
    expect(rect.width, kuteSidePanelWidth);
    expect(tester.takeException(), isNull);
  });
}
