// The open-position screen of an Investing position reads like the
// market sheet's header (ticker, the kind, the live price) and shows the
// position itself as plain rows, with nothing written twice.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/advisor_provider.dart'
    show advisorStreamRequestProvider, aiEnabledProvider;
import 'package:kute/models/advisor_model.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_candles_provider.dart';
import 'package:kute/providers/hyperliquid_insights_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart'
    show HlCandlestickChart, HlLiveDot;
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_position_detail_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_tick_price.dart';
import 'package:kute/screens/hyperliquid/components/hl_watch_star.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart'
    show HlCandleChart, HlChartEditBody, HlMarketDetailSheet;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/ask_sal_chip.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart'
    show KuteDogGlance, SalAiRing;
import 'package:kute/screens/hyperliquid/components/close_position_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_liquidation_distance.dart'
    show HlLiquidationTile, hlLossAtLiquidation;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/advisor/advisor_input_guard.dart';
import 'package:kute/services/advisor/advisor_service.dart'
    show AdvisorPrompt, AdvisorStreamEvent;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/screens/shared/charts/kute_chart_trade_lines.dart'
    show ChartTradeLineKind;
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/shared/position_rows_card.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';

// No socket in a test.
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

const _position = HlPerpPosition(
  coin: 'BTC',
  szi: 0.5,
  entryPx: 64000,
  positionValue: 32000,
  unrealizedPnl: 0,
  returnOnEquity: 0,
  liquidationPx: 58000,
  marginUsed: 6400,
  leverageType: 'isolated',
  leverageValue: 5,
  maxLeverage: 40,
  fundingSinceOpen: 1.25,
);

Future<void> _pump(WidgetTester tester,
    {double width = 390,
    HlPerpPosition position = _position,
    bool ai = false,
    List<Override> extra = const []}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      // The universe has not loaded the market: the chart is its
      // skeleton, the rest of the screen is the position's own.
      hyperliquidAccountMarketProvider('BTC').overrideWith((_) => null),
      hyperliquidPerpPositionsProvider.overrideWith((_) => [position]),
      aiEnabledProvider.overrideWith((ref) async => ai),
      ...extra,
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
        home: HlPositionDetailSheet(position: position),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// Opens the position's Details sheet (left open when the test ends: the
/// one-at-a-time guard is cleared after it).
Future<void> _openDetails(WidgetTester tester) async {
  addTearDown(OpenOnce.reset);
  await tester.ensureVisible(find.text('Details'));
  await tester.tap(find.text('Details'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('the market sheet\'s header, the value over the P&L, the '
      'position as rows', (tester) async {
    await _pump(tester);
    final c = AppColorsExtension.light();

    // Header: the smaller logo, the ticker alone (no kind chip), the live
    // price in the primary colour.
    expect(find.text('BTC'), findsOneWidget);
    expect(find.byType(HlKindBadge), findsNothing);
    expect(tester.widget<HlCoinIcon>(find.byType(HlCoinIcon).first).size, 32);
    final price = tester.widget<HlTickPrice>(find.byType(HlTickPrice));
    expect(price.price, 66000);
    expect(price.style.color, c.textPrimary);

    // The headline is what closing now gives back: the margin plus the
    // live P&L (6,400 + 1,000), the Portfolio card's own figure; the P&L
    // under it with its return on the margin.
    expect(find.text('If you close now'), findsOneWidget);
    expect(find.text('Position value'), findsNothing);
    expect(find.byWidgetPredicate(
            (w) => w is RollingNumberText && w.text == r'$7,400.00'),
        findsOneWidget);
    expect(find.byWidgetPredicate(
            (w) => w is RollingNumberText && w.text.startsWith(r'+$1,000.00')),
        findsOneWidget);

    // On the screen two tiles: an isolated position's margin (what was
    // put in) with the side under it, and the liquidation price with how
    // far the live mark (66,000) is from it: 8,000 / 66,000.
    final marginTile = find.byKey(const ValueKey('hl-position-margin'));
    expect(find.descendant(of: marginTile, matching: find.text('Margin')),
        findsOneWidget);
    expect(find.descendant(of: marginTile, matching: find.text(r'$6,400.00')),
        findsOneWidget);
    expect(find.descendant(of: marginTile, matching: find.text('Long')),
        findsOneWidget);
    expect(find.text('Collateral'), findsNothing);
    final liqTile = find.byKey(HlLiquidationTile.tileKey);
    expect(find.descendant(of: liqTile, matching: find.text('Liquidation')),
        findsOneWidget);
    expect(find.descendant(of: liqTile, matching: find.text(r'$58,000')),
        findsOneWidget);
    expect(find.descendant(of: liqTile, matching: find.text('12% away')),
        findsOneWidget);
    // No side chip, no card of rows. The market has not loaded, so nothing
    // can sign margin or place a protective order yet: no such rows.
    expect(find.byType(HlSideChip), findsNothing);
    expect(find.byType(PositionRowsCard), findsNothing);
    expect(find.text('Remove margin'), findsNothing);
    expect(find.byKey(const ValueKey('hl-add-margin')), findsNothing);
    expect(find.byKey(const ValueKey('hl-position-protect')), findsNothing);
    expect(find.text('Position size'), findsNothing);

    // Details is a row opening the shared bottom sheet, once, with what
    // the tiles do not say.
    await _openDetails(tester);
    expect(find.byType(AppBottomSheetContainer), findsOneWidget);
    expect(find.byType(PositionRowsCard), findsOneWidget);
    // The position size is the notional at the live mark (66,000 x 0.5)
    // with the coin size: a row, never the headline.
    expect(find.text('Position size'), findsOneWidget);
    expect(find.text(r'$33,000.00 · 0.5 BTC'), findsOneWidget);
    expect(tester.widget<Text>(find.text(r'$33,000.00 · 0.5 BTC')).textAlign,
        TextAlign.right);
    // Nothing the tiles say written again.
    final sheet = find.byType(AppBottomSheetContainer);
    for (final label in ['Side', 'Long', 'Margin', 'Liquidation price']) {
      expect(find.descendant(of: sheet, matching: find.text(label)),
          findsNothing,
          reason: label);
    }
    expect(find.text('Your money in it'), findsNothing);
    expect(find.text('Bought at'), findsOneWidget);
    expect(find.text('Leverage'), findsOneWidget);
    expect(find.text('5x'), findsOneWidget);
    expect(find.text('Funding paid'), findsOneWidget);
    // One quiet line on what the position size is.
    expect(find.textContaining('Position size is what your leverage controls'),
        findsOneWidget);
    expect(find.text('Current price'), findsNothing);
    expect(find.text('Return on investment'), findsNothing);
    expect(find.text('Details'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('no Sal on the position: no button, no question row; no '
      'sentence on what closing at the liquidation loses', (tester) async {
    await _pump(tester, ai: true);
    final header = find
        .ancestor(of: find.byType(KuteCloseButton), matching: find.byType(Row))
        .first;
    expect(find.descendant(of: header, matching: find.byType(HlCoinIcon)),
        findsWidgets);
    expect(find.descendant(of: header, matching: find.byType(HlTickPrice)),
        findsOneWidget);
    expect(find.byType(AskSalChip), findsNothing);
    expect(find.byType(SalWhyMovingRow), findsNothing);
    expect(find.byType(KuteDogGlance), findsNothing);
    expect(find.byType(SalAiRing), findsNothing);
    // The Liquidation row says how far it is; no sentence under it on
    // what closing there loses.
    expect(find.text('Liquidation'), findsOneWidget);
    expect(find.byKey(const ValueKey('hl-position-risk-line')), findsNothing);
    expect(find.textContaining('this position closes'), findsNothing);
    // The market has not loaded: nothing can place a protective order yet.
    expect(find.byKey(const ValueKey('hl-position-protect')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short cross position: Short in Details, no sentence on '
      'the loss at the liquidation price', (tester) async {
    // (64,000 - 70,000) x -0.5 = 3,000 lost at 70,000.
    await _pump(tester,
        position: const HlPerpPosition(
          coin: 'BTC',
          szi: -0.5,
          entryPx: 64000,
          positionValue: 33000,
          unrealizedPnl: -1000,
          returnOnEquity: 0,
          liquidationPx: 70000,
          marginUsed: 6400,
          leverageType: 'cross',
          leverageValue: 5,
          maxLeverage: 40,
        ));
    // The side under the margin, in the down colour.
    expect(find.text('Short'), findsOneWidget);
    expect(find.textContaining('this position closes'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('the loss at liquidation: the isolated margin, the cross loss '
      'against the entry, nothing without a price or a loss', () {
    expect(hlLossAtLiquidation(_position), 6400);
    const cross = HlPerpPosition(
      coin: 'BTC',
      szi: 0.5,
      entryPx: 64000,
      positionValue: 32000,
      unrealizedPnl: 0,
      returnOnEquity: 0,
      liquidationPx: 62000,
      marginUsed: 6400,
      leverageType: 'cross',
      leverageValue: 5,
      maxLeverage: 40,
    );
    expect(hlLossAtLiquidation(cross), 1000);
    const noLiq = HlPerpPosition(
      coin: 'BTC',
      szi: 0.5,
      entryPx: 64000,
      positionValue: 32000,
      unrealizedPnl: 0,
      returnOnEquity: 0,
      liquidationPx: null,
      marginUsed: 6400,
      leverageType: 'cross',
      leverageValue: 1,
      maxLeverage: 40,
    );
    expect(hlLossAtLiquidation(noLiq), isNull);
    // A cross liquidation beyond the entry on the winning side is no loss.
    const odd = HlPerpPosition(
      coin: 'BTC',
      szi: 0.5,
      entryPx: 64000,
      positionValue: 32000,
      unrealizedPnl: 0,
      returnOnEquity: 0,
      liquidationPx: 65000,
      marginUsed: 6400,
      leverageType: 'cross',
      leverageValue: 5,
      maxLeverage: 40,
    );
    expect(hlLossAtLiquidation(odd), isNull);
  });

  testWidgets('the screen never stacks a second copy of itself',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
        hyperliquidAccountMarketProvider('BTC').overrideWith((_) => null),
        hyperliquidPerpPositionsProvider
            .overrideWith((_) => const [_position]),
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
              // Twice, as a price tag tapped on the open screen or a
              // double tap on its card would.
              onPressed: () {
                HlPositionDetailSheet.show(context, position: _position);
                HlPositionDetailSheet.show(context, position: _position);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(HlPositionDetailSheet), findsOneWidget);
    expect(OpenOnce.isOpen(HlPositionDetailSheet.openKey('BTC', null)),
        isTrue);

    // Closed, it opens again.
    Navigator.of(tester.element(find.byType(HlPositionDetailSheet))).pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(HlPositionDetailSheet), findsNothing);
    expect(OpenOnce.isOpen(HlPositionDetailSheet.openKey('BTC', null)),
        isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow phone: nothing overflows', (tester) async {
    await _pump(tester, width: 320);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cross: the same Liquidation row and colour, no margin button',
      (tester) async {
    // 62,000 against the live 66,000: 6.1%, inside the alert's 10%.
    await _pump(tester,
        position: const HlPerpPosition(
          coin: 'BTC',
          szi: 0.5,
          entryPx: 64000,
          positionValue: 32000,
          unrealizedPnl: 0,
          returnOnEquity: 0,
          liquidationPx: 62000,
          marginUsed: 6400,
          leverageType: 'cross',
          leverageValue: 5,
          maxLeverage: 40,
        ));
    // Closing gives the collateral back with the live P&L (6,400 + 1,000).
    expect(find.byWidgetPredicate(
            (w) => w is RollingNumberText && w.text == r'$7,400.00'),
        findsOneWidget);
    expect(find.text('Liquidation'), findsOneWidget);
    expect(find.text(r'$62,000'), findsOneWidget);
    expect(find.text('6.1% away'), findsOneWidget);
    // Inside the alert's 10%: the distance alone in the warning colour.
    expect(tester.widget<Text>(find.text('6.1% away')).style?.color,
        AppColorsExtension.light().warning);
    expect(find.byKey(const ValueKey('hl-add-margin')), findsNothing);
    expect(find.text('Add margin'), findsNothing);
    // A cross position's margin is the collateral it ties up.
    expect(find.text('Collateral'), findsOneWidget);
    expect(find.text('Margin'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no liquidation price: said plainly, no colour, no button',
      (tester) async {
    await _pump(tester,
        position: const HlPerpPosition(
          coin: 'BTC',
          szi: 0.5,
          entryPx: 64000,
          positionValue: 32000,
          unrealizedPnl: 0,
          returnOnEquity: 0,
          liquidationPx: null,
          marginUsed: 6400,
          leverageType: 'cross',
          leverageValue: 1,
          maxLeverage: 40,
        ));
    expect(find.text('Liquidation'), findsOneWidget);
    expect(find.text('No liquidation price'), findsOneWidget);
    expect(find.textContaining('away'), findsNothing);
    // No price, no risk line: nothing is made up.
    expect(find.byKey(const ValueKey('hl-position-risk-line')), findsNothing);
    expect(find.textContaining('this position closes'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('chart edit mode', () {
    const btc = HlMarket(
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
    final start = DateTime.utc(2026, 10, 1);
    final candles = [
      for (var i = 0; i < 120; i++)
        HyperliquidCandle(
          openTime: start.add(Duration(hours: i)),
          closeTime: start.add(Duration(hours: i + 1)),
          open: 65000.0 + i,
          high: 65100.0 + i,
          low: 64900.0 + i,
          close: 65050.0 + i,
          volume: 10,
        ),
    ];

    Future<void> pumpScreen(WidgetTester tester, Widget screen,
        {bool ai = false,
        double width = 390,
        String? font,
        double textScale = 1,
        List<Override> extra = const []}) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
          hyperliquidAccountMarketProvider('BTC').overrideWith((_) => btc),
          // The market sheet's own reads (no network in a test).
          hyperliquidExactMarketProvider.overrideWith((ref, key) => btc),
          hyperliquidActiveAssetCtxProvider
              .overrideWith((ref, wire) => const Stream.empty()),
          hyperliquidOrderbookProvider
              .overrideWith((ref, wire) => const Stream.empty()),
          hyperliquidPerpPositionsProvider
              .overrideWith((_) => const [_position]),
          hyperliquidSpotBalancesProvider.overrideWith((_) => const []),
          hyperliquidActivityFillsProvider.overrideWith((_) => const []),
          hyperliquidTradingProvider.overrideWith(_Trading.new),
          hyperliquidLiveCandlesProvider.overrideWith((ref, key) =>
              Stream.value(HlLiveCandlesState(candles: candles))),
          hyperliquidTradeFlowProvider.overrideWith(
              (ref, coin) => Stream.value(const HlTradeFlowState())),
          aiEnabledProvider.overrideWith((ref) async => ai),
          ...extra,
        ],
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            theme: ThemeData(
              fontFamily: font,
              splashFactory: NoSplash.splashFactory,
              extensions: [AppColorsExtension.light()],
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
                child: screen,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> enterEdit(WidgetTester tester) async {
      await tester.ensureVisible(find.byIcon(Icons.draw_rounded));
      await tester.tap(find.byIcon(Icons.draw_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('the position screen edits on the whole screen, like the '
        'market sheet', (tester) async {
      await pumpScreen(
          tester, const HlPositionDetailSheet(position: _position, market: btc));
      expect(find.byType(KuteCloseButton), findsOneWidget);
      expect(find.text('Close position'), findsOneWidget);
      expect(find.byType(HlChartEditBody), findsNothing);
      final reading = tester.state(find.byType(HlCandleChart));

      await enterEdit(tester);
      // The market sheet's edit body: the header, the position and the
      // Close bar give way; the same chart (same state) fills the screen
      // and keeps the position's own lines, whose tags never reopen it.
      expect(find.byType(HlChartEditBody), findsOneWidget);
      expect(find.byType(KuteCloseButton), findsNothing);
      expect(find.text('Close position'), findsNothing);
      expect(find.byType(PositionRowsCard), findsNothing);
      expect(tester.state(find.byType(HlCandleChart)), same(reading));
      final chart = tester.widget<HlCandleChart>(find.byType(HlCandleChart));
      expect(chart.fillHeight, isTrue);
      expect(chart.positionTagOpensPosition, isFalse);
      expect(
          tester
              .widget<HlCandlestickChart>(find.byType(HlCandlestickChart))
              .tradeLines
              .map((l) => l.kind),
          containsAll(
              [ChartTradeLineKind.entry, ChartTradeLineKind.liquidation]));
      expect(find.text('Done'), findsOneWidget);

      // Done brings the screen back, on the same chart.
      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(HlChartEditBody), findsNothing);
      expect(find.byType(KuteCloseButton), findsOneWidget);
      expect(find.text('Close position'), findsOneWidget);
      expect(tester.state(find.byType(HlCandleChart)), same(reading));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the market sheet header: a smaller logo and no market-type '
        'chip', (tester) async {
      await pumpScreen(tester, const HlMarketDetailSheet(market: btc));
      final header = find.ancestor(
          of: find.byType(KuteCircleBackButton), matching: find.byType(Row));
      expect(
          find.descendant(of: header.first, matching: find.byType(HlKindBadge)),
          findsNothing);
      expect(find.byType(HlKindBadge), findsNothing);
      final icon = tester.widget<HlCoinIcon>(find
          .descendant(of: header.first, matching: find.byType(HlCoinIcon))
          .first);
      expect(icon.size, 32);
      expect(tester.takeException(), isNull);
    });

    Future<void> loadInter(WidgetTester tester) => tester.runAsync(() async {
          final inter = FontLoader('Inter');
          for (final f in ['Regular', 'SemiBold', 'Bold']) {
            inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
          }
          await inter.load();
        });

    const moving = HlMarket(
      coin: 'BTC',
      wireCoin: 'BTC',
      assetId: 0,
      kind: HlMarketKind.perp,
      szDecimals: 5,
      maxLeverage: 40,
      onlyIsolated: false,
      markPx: 66000,
      midPx: 66000,
      // 66,000 against 62,000: +6.5% today.
      prevDayPx: 62000,
      dayNtlVlm: 1e9,
    );
    final movingOverrides = <Override>[
      hyperliquidAccountMarketProvider('BTC').overrideWith((_) => moving),
      hyperliquidExactMarketProvider.overrideWith((ref, key) => moving),
    ];
    final row = find.byKey(const ValueKey('sal-why-moving-row'));
    final aboutRow = find.ancestor(
        of: find.text('About Bitcoin'), matching: find.byType(InkWell));
    Finder headerRow() => find
        .ancestor(
            of: find.byType(KuteCircleBackButton), matching: find.byType(Row))
        .first;

    testWidgets('a calm market (+1.5% today): no Sal row, no question pill, '
        'no button', (tester) async {
      await pumpScreen(tester, const HlMarketDetailSheet(market: btc),
          ai: true);
      expect(row, findsNothing);
      expect(find.text('Why is it moving?'), findsNothing);
      expect(find.byType(AskSalChip), findsNothing);
      expect(find.byType(KuteDogGlance), findsNothing);
      expect(find.text('What drives the price of BTC?'), findsNothing);
      expect(find.textContaining('protect'), findsNothing);
      expect(aboutRow, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final width in [320.0, 375.0]) {
      testWidgets('a big move at ${width.toInt()} wide, text x1.3: one quiet '
          '"Why is it moving?" row under the chart, a one-colour dog, never '
          'cut', (tester) async {
        await loadInter(tester);
        await pumpScreen(tester, const HlMarketDetailSheet(market: moving),
            ai: true,
            width: width,
            font: 'Inter',
            textScale: 1.3,
            extra: movingOverrides);
        final header = headerRow();
        expect(find.descendant(of: header, matching: find.byType(HlWatchStar)),
            findsOneWidget);
        expect(find.byType(AskSalChip), findsNothing);
        await tester.ensureVisible(row);
        await tester.pump();
        expect(row, findsOneWidget);
        expect(find.text('Why is it moving?'), findsOneWidget);
        // Under the chart (and its interval row), above About.
        expect(tester.getRect(row).top,
            greaterThanOrEqualTo(
                tester.getRect(find.byType(HlCandleChart)).bottom));
        expect(tester.getRect(row).top,
            lessThan(tester.getRect(find.text('About Bitcoin')).top));
        // The dog as a one-colour glyph in the title's colour, no ring.
        final glyph = tester.widget<KuteDogGlance>(
            find.descendant(of: row, matching: find.byType(KuteDogGlance)));
        expect(glyph.color, AppColorsExtension.light().textPrimary);
        expect(find.byType(SalAiRing), findsNothing);
        final paragraph = tester.renderObject<RenderParagraph>(find.descendant(
            of: row, matching: find.text('Why is it moving?')));
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('the row opens Sal already asking why it is moving, from '
        'market_why_moving', (tester) async {
      OpenOnce.reset();
      addTearDown(OpenOnce.reset);
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final prompts = <AdvisorPrompt?>[];
      await tester.runAsync(() => AdvisorInputGuard.isSafe('Public question'));
      await pumpScreen(tester, const HlMarketDetailSheet(market: moving),
          ai: true,
          extra: [
            ...movingOverrides,
            advisorStreamRequestProvider.overrideWithValue((
                {required query,
                context,
                history = const [],
                required cancellation,
                locale,
                prompt}) {
              prompts.add(prompt);
              return Stream.value(const AdvisorStreamEvent.done(
                  AdvisorResponse(blocks: [
                AdvisorBlock(
                    id: 'answer',
                    kind: AdvisorBlockKind.answer,
                    markdown: 'Bitcoin moved on the rate decision.')
              ])));
            }),
          ]);
      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row);
      await tester.pump();
      await tester.runAsync(() async {});
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(prompts.single?.template, 'hl.moving_today');
      expect(find.text('Why is BTC moving today?'), findsWidgets);
      expect(find.textContaining('Bitcoin moved on the rate decision.'),
          findsOneWidget);
      final opened = events.firstWhere((e) => e.$1 == 'sal_opened').$2!;
      expect(opened['entry'], 'market_why_moving');
      expect(opened['surface'], 'hl_market_detail');
      final asked = events.firstWhere((e) => e.$1 == 'sal_question_asked').$2!;
      expect(asked['input'], 'suggested');
      expect(asked['template'], 'hl.moving_today');
      expect(asked['chip_index'], 0);
      expect(asked['entry_source'], 'market_why_moving');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Sal switched off: no row even on a big move, About stays',
        (tester) async {
      await pumpScreen(tester, const HlMarketDetailSheet(market: moving),
          extra: movingOverrides);
      expect(row, findsNothing);
      expect(aboutRow, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the position at 375 wide, text x1.3: Liquidation and '
        '"Protect it" fit, nothing overflows, no Sal', (tester) async {
      await loadInter(tester);
      await pumpScreen(
          tester, const HlPositionDetailSheet(position: _position, market: btc),
          width: 375, font: 'Inter', textScale: 1.3, ai: true);
      final protect = find.byKey(const ValueKey('hl-position-protect'));
      await tester.ensureVisible(protect);
      await tester.pump();
      expect(protect, findsOneWidget);
      expect(find.text('Liquidation'), findsOneWidget);
      expect(find.byKey(const ValueKey('hl-position-risk-line')), findsNothing);
      // An isolated position on its own market: "Add margin" is a plain
      // row of its own, over "Protect it" (no chip beside the price).
      final add = find.byKey(const ValueKey('hl-add-margin'));
      expect(add, findsOneWidget);
      expect(find.descendant(of: add, matching: find.text('Add margin')),
          findsOneWidget);
      expect(tester.getRect(add).bottom,
          lessThanOrEqualTo(tester.getRect(protect).top + 0.5));
      expect(find.descendant(of: protect, matching: find.text('Stop loss')),
          findsOneWidget);
      expect(find.byType(SalWhyMovingRow), findsNothing);
      expect(find.byType(KuteDogGlance), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Protect it" opens the close ticket\'s own Advanced page on a '
        'stop-market close of the whole position', (tester) async {
      OpenOnce.reset();
      addTearDown(OpenOnce.reset);
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      await pumpScreen(
          tester, const HlPositionDetailSheet(position: _position, market: btc),
          extra: [
            runtimeCapabilitiesProvider.overrideWithValue(_Allowed()),
            hyperliquidAddressProvider.overrideWith((_) async => null),
          ]);
      final protect = find.byKey(const ValueKey('hl-position-protect'));
      expect(protect, findsOneWidget);
      expect(find.descendant(of: protect, matching: find.text('Protect it')),
          findsOneWidget);
      expect(find.descendant(of: protect, matching: find.text('Stop loss')),
          findsOneWidget);
      await tester.ensureVisible(protect);
      await tester.pump();
      await tester.tap(protect);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(HlClosePositionSheet), findsOneWidget);
      // The Advanced page, on a stop market, its trailing stop beside it.
      expect(find.text('Stop market'), findsWidgets);
      expect(find.text('Trailing stop'), findsOneWidget);
      final tapped =
          events.firstWhere((e) => e.$1 == 'position_protect_tapped').$2!;
      expect(tapped['venue'], 'hyperliquid');
      expect(tapped['coin'], 'BTC');
      expect(tapped['side'], 'long');
      expect(tapped['wallet_kind'], 'hot');
      expect(tapped['target'], 'stop_loss');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('neither the market sheet nor the position screen has a '
        'change / LIVE row under the pills', (tester) async {
      await pumpScreen(tester, const HlMarketDetailSheet(market: btc));
      expect(tester.widget<HlCandleChart>(find.byType(HlCandleChart)).showSummary,
          isFalse);
      expect(
          tester
              .widget<HlCandlestickChart>(find.byType(HlCandlestickChart))
              .showSummary,
          isFalse);
      expect(find.textContaining('past'), findsNothing);
      expect(find.byType(HlLiveDot), findsNothing);
      // The interval pills stay.
      expect(find.byIcon(Icons.draw_rounded), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());

      await pumpScreen(
          tester, const HlPositionDetailSheet(position: _position, market: btc));
      expect(tester.widget<HlCandleChart>(find.byType(HlCandleChart)).showSummary,
          isFalse);
      expect(
          tester
              .widget<HlCandlestickChart>(find.byType(HlCandlestickChart))
              .showSummary,
          isFalse);
      expect(find.textContaining('past'), findsNothing);
      expect(find.byType(HlLiveDot), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the market sheet edits in the same body', (tester) async {
      await pumpScreen(tester, const HlMarketDetailSheet(market: btc));
      await enterEdit(tester);
      expect(find.byType(HlChartEditBody), findsOneWidget);
      expect(
          tester.widget<HlCandleChart>(find.byType(HlCandleChart)).fillHeight,
          isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}

class _Allowed extends Fake implements RuntimeCapabilitiesService {
  @override
  CapabilityDecision decision(String id) =>
      const CapabilityDecision(allowed: true);
  @override
  String? blockReason(String id) => null;
}

class _Trading extends HyperliquidTradingNotifier {
  @override
  Future<HyperliquidTradingState> build() async =>
      const HyperliquidTradingState(isInitialized: true);
}
