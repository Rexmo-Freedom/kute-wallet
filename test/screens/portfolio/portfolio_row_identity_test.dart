import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_order_metadata_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/open_orders_sheet.dart';
import 'package:kute/screens/polymarket/components/open_orders_sheet.dart';
import 'package:kute/screens/polymarket/components/position_card.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Order;

class _HlTrading extends HyperliquidTradingNotifier {
  @override
  Future<HyperliquidTradingState> build() async => HyperliquidTradingState(
        openOrders: [
          HlOpenOrder.fromJson({
            'coin': '@142',
            'oid': 10,
            'side': 'B',
            'sz': '1',
            'origSz': '1',
            'limitPx': '100',
            'orderType': 'Limit',
          })
        ],
      );
}

class _PmTrading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState();
}

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
}

const _market = HlMarket(
    coin: 'TSLA',
    wireCoin: '@142',
    assetId: 10142,
    kind: HlMarketKind.spot,
    szDecimals: 2,
    maxLeverage: 1,
    onlyIsolated: false,
    markPx: 100,
    midPx: 100,
    prevDayPx: 100,
    dayNtlVlm: 1000,
    category: 'stocks',
    iconUrl: 'https://example.com/tsla.svg');

Future<void> _pump(WidgetTester tester, Widget child, List<Override> overrides,
    {double textScale = 1}) async {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      )));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets('HL resting orders resolve wire identity and use shared actions',
      (tester) async {
    await _pump(
        tester,
        const HlOpenOrdersSheet(embedded: true),
        [
          hyperliquidTradingProvider.overrideWith(_HlTrading.new),
          hyperliquidAccountMarketProvider('@142').overrideWith((_) => _market),
          // Order rows resolve by exact wire coin since 2de2d1f8.
          hyperliquidWireMarketProvider('@142').overrideWith((_) => _market),
        ],
        textScale: 2);
    final icon = tester.widget<HlCoinIcon>(find.byType(HlCoinIcon));
    expect(icon.coin, 'TSLA');
    expect(icon.wireCoin, '@142');
    expect(icon.iconUrl, 'https://example.com/tsla.svg');
    expect(icon.category, 'stocks');
    // The market's name over its ticker and the order's side; never the
    // raw wire id.
    expect(find.text('Tesla'), findsOneWidget);
    expect(find.text('TSLA · Buy'), findsOneWidget);
    expect(find.textContaining('@142'), findsNothing);
    // The order's price is the number on the right.
    expect(find.text('Limit'), findsOneWidget);
    expect(find.byType(AppButton), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets('PM resting orders show market identity and retain outcome',
      (tester) async {
    const order = Order(
        id: 'order',
        market: 'condition',
        assetId: 'token',
        owner: 'owner',
        side: 'BUY',
        price: '0.4',
        originalSize: '10',
        sizeMatched: '0',
        outcome: 'Yes');
    await _pump(
        tester,
        const OpenOrdersSheet(embedded: true),
        [
          polymarketOpenOrdersProvider
              .overrideWith((_) => Stream.value([order])),
          polymarketOrderMetadataProvider.overrideWith((_) async => {
                'condition': const PolymarketOrderMetadata(
                    title: 'Will this market resolve?', imageUrl: ''),
              }),
          polymarketTradingProvider.overrideWith(_PmTrading.new),
          livePriceProvider.overrideWith(_Prices.new),
        ],
        textScale: 2);
    expect(find.text('Will this market resolve?'), findsOneWidget);
    expect(find.text('BUY · Yes'), findsOneWidget);
    // The portfolio's card: the order's price on the right with its
    // kind under it.
    expect(find.byType(PolyTitledCard), findsOneWidget);
    // The figure rolls its digits ([RollingNumberText]).
    expect(
        find.byWidgetPredicate(
            (w) => w is RollingNumberText && w.text == '40%'),
        findsOneWidget);
    expect(find.text('Limit · pending'), findsOneWidget);
    expect(find.byType(AppButton), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
