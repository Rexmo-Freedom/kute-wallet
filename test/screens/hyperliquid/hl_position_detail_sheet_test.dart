// The open-position screen of an Investing position reads like the
// market sheet's header (ticker, the kind, the live price) and shows the
// position itself as plain rows, with nothing written twice.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/advisor_provider.dart'
    show aiEnabledProvider;
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
    show
        HlCandleChart,
        HlChartEditBody,
        HlMarketDetailSheet,
        debugResetHlChartRail;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart'
    show KuteDogGlance, SalAiRing;
import 'package:kute/screens/hyperliquid/components/close_position_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_liquidation_distance.dart'
    show HlLiquidationTile, hlLossAtLiquidation;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/screens/shared/charts/kute_chart_trade_lines.dart'
    show ChartTradeLineKind;
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/shared/position_rows_card.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/screens/shared/market_pair_button.dart';
import 'package:kute/screens/shared/kute_bar_context.dart'
    show KuteBarPrimaryStyle, kuteBarScrollClearance;
import 'package:kute/theme/app_theme.dart';

import '../../helpers/shell_bar_harness.dart';

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

  testWidgets('the market sheet\'s header, the price over the position in '
      'plain words, the position as rows', (tester) async {
    await _pump(tester);
    final c = AppColorsExtension.light();

    // Header: the smaller logo, the ticker alone (no kind chip, no
    // price). The big figure under it is what the position is worth now
    // (6,400 + 1,000, the Portfolio card's own figure), in the primary
    // colour.
    expect(find.text('BTC'), findsOneWidget);
    expect(find.byType(HlKindBadge), findsNothing);
    expect(tester.widget<HlCoinIcon>(find.byType(HlCoinIcon).first).size, 32);
    final hero = tester.widget<HlTickPrice>(find.byType(HlTickPrice));
    expect(hero.price, 7400);
    expect(hero.text, r'$7,400.00');
    expect(hero.style.color, c.textPrimary);
    expect(hero.style.fontSize, greaterThan(30));

    // Under it the P&L, amount and return on the margin, in the up
    // colour, then the one quiet line. No side chip, no "Profit" word on
    // screen, no "If you close now" headline.
    expect(find.text('If you close now'), findsNothing);
    expect(find.text('Position value'), findsNothing);
    expect(find.byType(HlSideChip), findsNothing);
    expect(find.text('Long · 5x'), findsNothing);
    expect(find.text(r'+$1,000.00 (+15.6%)'), findsOneWidget);
    expect(find.text(r'Long · 0.5 BTC · $66,000'), findsOneWidget);

    // On the screen two tiles: what was put in (an isolated position's
    // margin; what it is worth now is the hero, not said again), and the
    // liquidation price with how far the live mark (66,000) is from it:
    // 8,000 / 66,000.
    final marginTile = find.byKey(const ValueKey('hl-position-margin'));
    expect(find.descendant(of: marginTile, matching: find.text('You put in')),
        findsOneWidget);
    expect(find.descendant(of: marginTile, matching: find.text(r'$6,400.00')),
        findsOneWidget);
    // Under the amount, the position's leverage, said only.
    expect(find.descendant(of: marginTile, matching: find.text('5x leverage')),
        findsOneWidget);
    expect(find.textContaining('Worth'), findsNothing);
    expect(find.text('Collateral'), findsNothing);
    final liqTile = find.byKey(HlLiquidationTile.tileKey);
    expect(find.descendant(of: liqTile, matching: find.text('Liquidation')),
        findsOneWidget);
    expect(find.descendant(of: liqTile, matching: find.text(r'$58,000')),
        findsOneWidget);
    expect(find.descendant(of: liqTile, matching: find.text('12% away')),
        findsOneWidget);
    // No card of rows. The market has not loaded, so nothing
    // can sign margin or place a protective order yet: no such rows.
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
    expect(find.text('Entry'), findsOneWidget);
    expect(find.text('Bought at'), findsNothing);
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
    // The price is the big figure under the header row, not in it.
    expect(find.descendant(of: header, matching: find.byType(HlTickPrice)),
        findsNothing);
    // Nothing to share in the page (founder, 4 November 2026): no pill
    // beside the figure, no card under the tiles. The round Sal button
    // floats beside Close position: in profit, the brag card.
    for (final key in [
      'kute-sal-header-button',
      'position-share-pill',
      'position-share-card',
    ]) {
      expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
    }
    final close = tester
        .widget<KuteBarContextScope>(find.byWidgetPredicate(
            (w) => w is KuteBarContextScope && w.barContext.isPrimary))
        .barContext;
    expect(close.label, 'Close position');
    expect(close.share, isNotNull);
    expect(close.share!.barContext!.market, isTrue);
    expect(close.share!.brag, isNotNull, reason: 'in profit: the card');
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

  testWidgets('a short cross position: Short on the quiet line, no sentence on '
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
    // The loss in the down colour: (64,000 - 66,000) x 0.5 at the live
    // mark; the side and the size on the quiet line.
    final loss = find.text(r'−$1,000.00 (−15.6%)');
    expect(loss, findsOneWidget);
    expect(tester.widget<Text>(loss).style?.color, AppColors.marketDown);
    expect(find.text(r'Short · 0.5 BTC · $66,000'), findsOneWidget);
    // Worth now: the 6,400 collateral less the 1,000 lost.
    expect(tester.widget<HlTickPrice>(find.byType(HlTickPrice)).text,
        r'$5,400.00');
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
    // Closing gives the collateral back with the live P&L (6,400 + 1,000):
    // the hero.
    expect(tester.widget<HlTickPrice>(find.byType(HlTickPrice)).text,
        r'$7,400.00');
    expect(find.text('Liquidation'), findsOneWidget);
    expect(find.text(r'$62,000'), findsOneWidget);
    expect(find.text('6.1% away'), findsOneWidget);
    // Inside the alert's 10%: the distance alone in the warning colour.
    expect(tester.widget<Text>(find.text('6.1% away')).style?.color,
        AppColorsExtension.light().warning);
    expect(find.byKey(const ValueKey('hl-add-margin')), findsNothing);
    expect(find.text('Add margin'), findsNothing);
    // A cross position's margin (the collateral it ties up) is what was
    // put in, in the same plain words; cross is in Details.
    expect(find.text('You put in'), findsOneWidget);
    expect(find.text('Collateral'), findsNothing);
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
        double height = 844,
        HlPerpPosition position = _position,
        HlLivePricesNotifier Function() prices = _LivePrices.new,
        bool dark = false,
        bool bar = false,
        StateProvider<List<HlPerpPosition>>? held,
        List<Override> extra = const []}) async {
      // [bar]: the shell's floating bar over the page, as in the app
      // (Close position is the bar's button).
      if (bar) installShellBar();
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          hyperliquidLivePricesProvider.overrideWith(prices),
          hyperliquidAccountMarketProvider('BTC').overrideWith((_) => btc),
          // The market sheet's own reads (no network in a test).
          hyperliquidExactMarketProvider.overrideWith((ref, key) => btc),
          hyperliquidActiveAssetCtxProvider
              .overrideWith((ref, wire) => const Stream.empty()),
          hyperliquidOrderbookProvider
              .overrideWith((ref, wire) => const Stream.empty()),
          hyperliquidPerpPositionsProvider.overrideWith((ref) =>
              held == null ? [position] : ref.watch(held)),
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
              brightness: dark ? Brightness.dark : Brightness.light,
              fontFamily: font,
              splashFactory: NoSplash.splashFactory,
              extensions: [
                dark ? AppColorsExtension.dark() : AppColorsExtension.light()
              ],
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            navigatorObservers: bar ? shellBarObservers() : const [],
            // A boundary to shoot the page from (the PNG renders), the
            // bar over it when mounted.
            builder: (context, child) => RepaintBoundary(
                key: const ValueKey('shot'),
                child: bar ? shellBarBuilder(context, child) : child),
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
      // The "Advanced chart" row under the chart (the pencil is gone).
      final row = find.byKey(const ValueKey('hl-advanced-chart'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// Close position is the bar's button, up and taking taps.
    bool closeOnBar(WidgetTester tester) =>
        barIsPrimary(tester) &&
        barIsUp(tester) &&
        barPrimaryContext(tester).label == 'Close position';

    testWidgets(
        'Close position carries the round Sal button at its right, read '
        'as Brag about it in profit, both taking taps; the chart editor '
        'takes both away', (tester) async {
      await pumpScreen(
          tester, const HlPositionDetailSheet(position: _position, market: btc),
          bar: true);
      await pumpBar(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(closeOnBar(tester), isTrue);
      final share = find.byKey(const ValueKey('kute-bar-share'));
      expect(share, findsOneWidget);
      final close = tester.getRect(findBarPrimary());
      final circle = tester.getRect(share);
      expect(circle.left, greaterThan(close.right));
      expect(circle.center.dy, moreOrLessEquals(close.center.dy, epsilon: 1));
      expect(find.bySemanticsLabel('Brag about it'), findsOneWidget);
      for (final f in [findBarPrimary(), share]) {
        final hit = tester.hitTestOnBinding(tester.getCenter(f));
        expect(hit.path.any((e) => e.target == tester.renderObject(f)),
            isTrue);
      }
      // Nothing beside the figure.
      expect(find.byKey(const ValueKey('position-share-pill')), findsNothing);
      expect(find.byKey(const ValueKey('kute-sal-header-button')),
          findsNothing);

      await enterEdit(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(barIsUp(tester), isFalse);
      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await pumpBar(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(closeOnBar(tester), isTrue);
      expect(share, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the position screen edits on the whole screen, like the '
        'market sheet', (tester) async {
      await pumpScreen(
          tester, const HlPositionDetailSheet(position: _position, market: btc),
          bar: true);
      await pumpBar(tester);
      expect(find.byType(KuteCloseButton), findsOneWidget);
      expect(closeOnBar(tester), isTrue);
      expect(find.byType(HlChartEditBody), findsNothing);
      final reading = tester.state(find.byType(HlCandleChart));

      await enterEdit(tester);
      // The market sheet's edit body: the header, the position and the
      // Close bar give way; the same chart (same state) fills the screen
      // and keeps the position's own lines, whose tags never reopen it.
      expect(find.byType(HlChartEditBody), findsOneWidget);
      expect(find.byType(KuteCloseButton), findsNothing);
      await tester.pump(const Duration(milliseconds: 600));
      expect(closeOnBar(tester), isFalse);
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
      await pumpBar(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(closeOnBar(tester), isTrue);
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
      // The star stays in the header. Nothing to share there or beside
      // the price (founder, 4 November 2026): Send to a friend is the
      // round Sal button at the end of the floating trade row.
      expect(
          find.descendant(of: header.first, matching: find.byType(HlWatchStar)),
          findsOneWidget);
      expect(find.byKey(const ValueKey('kute-sal-header-button')),
          findsNothing);
      final row = tester
          .widget<KuteBarContextScope>(find.byWidgetPredicate(
              (w) => w is KuteBarContextScope && w.barContext.isTrade))
          .barContext;
      expect(row.trades.map((t) => t.label), ['Invest', 'Short']);
      expect(row.share!.barContext!.market, isTrue);
      expect(tester.takeException(), isNull);
    });

    Future<void> loadInter(WidgetTester tester) => tester.runAsync(() async {
          final inter = FontLoader('Inter');
          for (final f in ['Regular', 'SemiBold', 'Bold']) {
            inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
          }
          await inter.load();
        });

    // The open position's header (founder, 2 November 2026): one big
    // number, what the position is worth now, the P&L under it, and one
    // quiet line with the side, the size and the market price with its
    // change today.
    testWidgets('the hero is the value now, the P&L under it, then one '
        'quiet line', (tester) async {
      await pumpScreen(
          tester, const HlPositionDetailSheet(position: _position, market: btc));
      final c = AppColorsExtension.light();
      final heroFinder = find.byKey(const ValueKey('hl-position-price'));
      final hero = tester.widget<HlTickPrice>(heroFinder);
      // 6,400 margin + (66,000 - 64,000) x 0.5.
      expect(hero.text, r'$7,400.00');
      expect(hero.style.fontSize, greaterThan(30));
      expect(hero.style.fontFeatures, contains(const FontFeature.tabularFigures()));

      final result = find.byKey(const ValueKey('hl-position-result'));
      final resultText = tester.widget<Text>(result);
      expect(resultText.data, r'+$1,000.00 (+15.6%)');
      expect(resultText.style?.color, AppColors.marketUp);
      expect(resultText.maxLines, 1);
      // Read aloud with its word: the colour carries it on screen.
      expect(
          find.bySemanticsLabel(r'Profit +$1,000.00 (+15.6%)'), findsOneWidget);

      final meta = find.byKey(const ValueKey('hl-position-meta'));
      final metaText = tester.widget<Text>(meta);
      // 66,000 against yesterday's 65,000: +1.5% today.
      expect(metaText.textSpan!.toPlainText(),
          r'Long · 0.5 BTC · $66,000 (+1.5% today)');
      expect(metaText.maxLines, 1);
      expect(metaText.overflow, TextOverflow.ellipsis);
      expect(metaText.style?.color, c.textSecondary);
      expect(metaText.style!.fontSize!, lessThan(resultText.style!.fontSize!));
      // The order down the page: hero, P&L, the quiet line, the chart.
      expect(tester.getRect(heroFinder).bottom,
          lessThanOrEqualTo(tester.getRect(result).top + 1));
      expect(tester.getRect(result).bottom,
          lessThanOrEqualTo(tester.getRect(meta).top));
      expect(tester.getRect(meta).bottom,
          lessThan(tester.getRect(find.byType(HlCandleChart)).top));
      // Nothing of the old header: no side chip, no leverage, no "Profit"
      // word, no separate change today; the leverage is said once, under
      // "You put in", and entry waits in Details.
      expect(find.byType(HlSideChip), findsNothing);
      expect(find.byKey(const ValueKey('hl-position-change')), findsNothing);
      expect(find.textContaining('5x'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('hl-position-margin')),
              matching: find.text('5x leverage')),
          findsOneWidget);
      expect(find.textContaining('Profit'), findsNothing);
      expect(find.textContaining('Worth'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    // The leverage under "You put in" (founder, 2 November 2026): said in
    // the Liquidation tile's sub-line style, both tiles one height;
    // display only, nothing to change it with.
    for (final (lev, text) in [(2, '2x leverage'), (1, 'No leverage')]) {
      testWidgets('"You put in" says "$text" under the amount',
          (tester) async {
        final pos = HlPerpPosition(
          coin: 'BTC',
          szi: 0.5,
          entryPx: 64000,
          positionValue: 32000,
          unrealizedPnl: 0,
          returnOnEquity: 0,
          liquidationPx: 58000,
          marginUsed: 6400,
          leverageType: 'isolated',
          leverageValue: lev,
          maxLeverage: 40,
        );
        await pumpScreen(tester, HlPositionDetailSheet(position: pos, market: btc),
            position: pos);
        final c = AppColorsExtension.light();
        final tile = find.byKey(const ValueKey('hl-position-margin'));
        final caption = find.byKey(const ValueKey('hl-position-leverage'));
        expect(find.descendant(of: tile, matching: caption), findsOneWidget);
        final captionText = tester.widget<Text>(caption);
        expect(captionText.data, text);
        expect(captionText.maxLines, 1);
        // The Liquidation tile's "12% away" sub-line style, in the quiet
        // colour.
        final away = tester.widget<Text>(find.text('12% away'));
        expect(captionText.style?.fontSize, away.style?.fontSize);
        expect(captionText.style?.fontWeight, away.style?.fontWeight);
        expect(captionText.style?.color, c.textSecondary);
        // Under the amount, and the two tiles stay one height.
        expect(tester.getRect(caption).top,
            greaterThanOrEqualTo(
                tester.getRect(find.text(r'$6,400.00')).bottom));
        final liq = find.byKey(HlLiquidationTile.tileKey);
        expect(tester.getRect(tile).height, tester.getRect(liq).height);
        expect(tester.getRect(tile).top, tester.getRect(liq).top);
        // Display only: no leverage control or hint anywhere.
        expect(find.byType(Slider), findsNothing);
        expect(find.textContaining('Max '), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the leverage reads whole numbers plainly, else one decimal',
        (tester) async {
      await pumpScreen(
          tester, const HlPositionDetailSheet(position: _position, market: btc));
      final l10n = AppLocalizations.of(
          tester.element(find.byType(HlPositionDetailSheet)));
      expect(hlLeverageCaption(l10n, 3.5), '3.5x leverage');
      expect(hlLeverageCaption(l10n, 2), '2x leverage');
      expect(hlLeverageCaption(l10n, 2.0), '2x leverage');
      expect(hlLeverageCaption(l10n, 10), '10x leverage');
      expect(hlLeverageCaption(l10n, 1), 'No leverage');
      expect(hlLeverageCaption(l10n, 1.0), 'No leverage');
    });

    testWidgets('a price tick changes the figures, never the layout',
        (tester) async {
      final feed = _DrivenPrices();
      // The app's font, so the figure lays out at its real width.
      await loadInter(tester);
      await pumpScreen(
          tester, const HlPositionDetailSheet(position: _position, market: btc),
          font: 'Inter',
          prices: () => feed);
      final hero = find.byKey(const ValueKey('hl-position-price'));
      final result = find.byKey(const ValueKey('hl-position-result'));
      final meta = find.byKey(const ValueKey('hl-position-meta'));
      final chart = find.byType(HlCandleChart);
      final tile = find.byKey(HlLiquidationTile.tileKey);
      List<double> layout() => [
            tester.getRect(hero).top,
            tester.getRect(hero).height,
            tester.getRect(result).top,
            tester.getRect(result).height,
            tester.getRect(meta).top,
            tester.getRect(meta).height,
            tester.getRect(chart).top,
            tester.getRect(tile).top,
          ];
      final before = layout();
      // Up and down, with every digit moving (and the P&L flipping to a
      // loss and back); each frame of the flash and the roll is checked.
      for (final px in [66012.5, 65987.25, 66480.0, 63211.75, 64999.0, 66000.0]) {
        feed.put(px);
        for (var f = 0; f < 12; f++) {
          await tester.pump(const Duration(milliseconds: 80));
          expect(layout(), before, reason: 'at $px, frame $f');
        }
      }
      // The figures did move.
      feed.put(66480);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<HlTickPrice>(hero).text, r'$7,640.00');
      expect(tester.widget<Text>(result).data, r'+$1,240.00 (+19.4%)');
      expect(tester.takeException(), isNull);
    });

    // Light and dark PNGs of a short in a loss and a long in profit:
    // flutter test --dart-define=HL_POSITION_SHOT_OUT=<dir>.
    const shotOut = String.fromEnvironment('HL_POSITION_SHOT_OUT');
    for (final dark in [false, true]) {
      for (final short in [true, false]) {
        final name =
            '${short ? 'short_loss' : 'long_profit'}_${dark ? 'dark' : 'light'}';
        testWidgets('render: $name', (tester) async {
          await loadInter(tester);
          // Sal on the bar's Close position, as in the app.
          await tester.runAsync(() async {
            SalSpriteCache.debugSetManifest(jsonDecode(await rootBundle
                    .loadString('$kSalSpriteDir/manifest.json'))
                as Map<String, dynamic>);
            for (final clip in ['idle', 'curious', 'think', 'share']) {
              for (final density in [1, 2, 3]) {
                await SalSpriteCache.clip(clip, density);
              }
            }
            final icons = FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
            await icons.load();
          });
          await pumpScreen(
              tester,
              HlPositionDetailSheet(
                  position: short ? _shortIsolated : _position, market: btc),
              font: 'Inter',
              dark: dark,
              height: 1000,
              bar: true,
              position: short ? _shortIsolated : _position);
          await pumpBar(tester);
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
          if (shotOut.isEmpty) return;
          final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('shot')));
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 3);
            final data =
                await image.toByteData(format: ui.ImageByteFormat.png);
            Directory(shotOut).createSync(recursive: true);
            File('$shotOut/position_$name.png')
                .writeAsBytesSync(data!.buffer.asUint8List());
          });
        });
      }
    }

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
    // About: the option card beside Advanced chart.
    final aboutRow = find.ancestor(
        of: find.text('About Bitcoin'),
        matching: find.byKey(const ValueKey('hl-about')));
    Finder headerRow() => find
        .ancestor(
            of: find.byType(KuteCircleBackButton), matching: find.byType(Row))
        .first;

    testWidgets('a calm market (+1.5% today): no "Why is it moving?" row, '
        'no question pill, no button; About stays', (tester) async {
      await pumpScreen(tester, const HlMarketDetailSheet(market: btc),
          ai: true);
      // The row is gone (31 October 2026): the question is the Sal
      // sheet's first chip, nothing under the chart.
      expect(find.text('Why is it moving?'), findsNothing);
      expect(find.text('What drives the price of BTC?'), findsNothing);
      expect(find.textContaining('protect'), findsNothing);
      expect(aboutRow, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final width in [320.0, 375.0]) {
      testWidgets('a big move at ${width.toInt()} wide, text x1.3: the star '
          'in the header, no "Why is it moving?" row under the chart, About '
          'stays', (tester) async {
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
        // The row is gone (31 October 2026): nothing between the chart
        // and About asks the question.
        expect(find.text('Why is it moving?'), findsNothing);
        expect(find.byType(SalAiRing), findsNothing);
        expect(aboutRow, findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('a big move with Sal on: no "Why is it moving?" row to tap '
        '(the question lives in the Sal sheet)', (tester) async {
      await pumpScreen(tester, const HlMarketDetailSheet(market: moving),
          ai: true, extra: movingOverrides);
      expect(find.text('Why is it moving?'), findsNothing);
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
      // An isolated position on its own market: "Add margin" is an option
      // card of its own, beside "Protect it" (no chip beside the price),
      // the two as tall as each other.
      final add = find.byKey(const ValueKey('hl-add-margin'));
      expect(add, findsOneWidget);
      expect(find.descendant(of: add, matching: find.text('Add margin')),
          findsOneWidget);
      expect(tester.getRect(add).top, tester.getRect(protect).top);
      expect(tester.getRect(add).right,
          lessThan(tester.getRect(protect).left));
      expect(tester.getRect(add).height, tester.getRect(protect).height);
      expect(find.descendant(of: protect, matching: find.text('Stop loss')),
          findsOneWidget);
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

    testWidgets('Close position is the floating bar\'s red pill, not a pinned '
        'panel: a tap opens the same close ticket and its event',
        (tester) async {
      OpenOnce.reset();
      addTearDown(OpenOnce.reset);
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      await pumpScreen(
          tester, const HlPositionDetailSheet(position: _position, market: btc),
          bar: true,
          extra: [
            runtimeCapabilitiesProvider.overrideWithValue(_Allowed()),
            hyperliquidAddressProvider.overrideWith((_) async => null),
          ]);
      await pumpBar(tester);
      // No button of the page's own: the bar is Close position.
      expect(find.byType(MarketPairButton), findsNothing);
      expect(closeOnBar(tester), isTrue);
      final ctx = barPrimaryContext(tester);
      expect(ctx.enabled, isTrue);
      expect(ctx.busy, isFalse);
      expect(ctx.disabledLabel, 'Position closed');
      // The red the pinned button had, lettered white.
      expect(ctx.style, same(KuteBarPrimaryStyle.destructive));
      expect(ctx.style!.fill, AppColors.marketDown);
      expect(barPrimaryInk(tester), const Color(0xFFFFFFFF));
      // The body scrolls clear of the floating bar.
      final scroll = tester.widget<SingleChildScrollView>(find
          .ancestor(
              of: find.byKey(const ValueKey('hl-advanced-chart')),
              matching: find.byType(SingleChildScrollView))
          .first);
      expect((scroll.padding! as EdgeInsets).bottom,
          closeTo(kuteBarScrollClearance.h, 0.01));

      await tapBarPrimary(tester, settle: false);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(HlClosePositionSheet), findsOneWidget);
      final started =
          events.where((e) => e.$1 == 'hyperliquid_close_started').toList();
      expect(started, hasLength(1));
      expect(started.single.$2!['entry_source'], 'position_detail');
      expect(started.single.$2!['coin'], 'BTC');
      expect(started.single.$2!['side'], 'long');
      expect(started.single.$2!['wallet_kind'], 'hot');
      // The ticket's own button is the bar while it is up.
      await pumpBar(tester);
      expect(barPrimaryContext(tester).label, isNot('Close position'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('closed under the screen: the bar says "Position closed" and '
        'takes no tap', (tester) async {
      OpenOnce.reset();
      addTearDown(OpenOnce.reset);
      final held = StateProvider<List<HlPerpPosition>>((_) => [_position]);
      await pumpScreen(
          tester, const HlPositionDetailSheet(position: _position, market: btc),
          bar: true, held: held);
      await pumpBar(tester);
      expect(closeOnBar(tester), isTrue);
      expect(barPrimaryEnabled(tester), isTrue);

      // The account drops the position (it closed).
      ProviderScope.containerOf(
              tester.element(find.byType(HlPositionDetailSheet)))
          .read(held.notifier)
          .state = const [];
      await pumpBar(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(barPrimaryEnabled(tester), isFalse);
      expect(barPrimaryText('Position closed'), findsOneWidget);
      await tapBarPrimary(tester, settle: false);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(HlClosePositionSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an account still loading says nothing: Close position stays '
        'live on the screen\'s own position', (tester) async {
      OpenOnce.reset();
      addTearDown(OpenOnce.reset);
      final held = StateProvider<List<HlPerpPosition>>((_) => const []);
      await pumpScreen(
          tester, const HlPositionDetailSheet(position: _position, market: btc),
          bar: true, held: held);
      await pumpBar(tester);
      expect(closeOnBar(tester), isTrue);
      expect(barPrimaryEnabled(tester), isTrue);
      expect(tester.takeException(), isNull);
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
      // The interval pills stay; the pencil left them for the
      // "Advanced chart" row.
      expect(find.text('1h'), findsOneWidget);
      expect(find.byIcon(Icons.draw_rounded), findsNothing);
      expect(find.byKey(const ValueKey('hl-advanced-chart')), findsOneWidget);
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

    testWidgets('the market sheet shows no "Your investment" card',
        (tester) async {
      await pumpScreen(tester, const HlMarketDetailSheet(market: btc));
      expect(find.text('Your investment'), findsNothing);
      expect(find.byKey(const ValueKey('hl-investment-manage')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'the tool rail opens out, tucks away from its button, comes back '
        'from its tab, and stays as last left for the session', (tester) async {
      debugResetHlChartRail();
      addTearDown(debugResetHlChartRail);
      final rail = find.byKey(const ValueKey('hl-chart-tool-rail'));
      final show = find.byKey(const ValueKey('hl-chart-rail-show'));
      final hide = find.byKey(const ValueKey('hl-chart-rail-hide'));
      double plotWidth() =>
          tester.getSize(find.byType(HlCandlestickChart)).width;

      await pumpScreen(tester, const HlMarketDetailSheet(market: btc));
      await enterEdit(tester);
      // Out on the first Advanced of the session: every tool in sight.
      expect(rail, findsOneWidget);
      expect(show, findsNothing);
      for (final key in [
        'cursor',
        'trendline',
        'level',
        'rect',
        'dateAndPriceRange',
        'fibonacci',
        'text',
        'more',
      ]) {
        expect(find.byKey(ValueKey('hl-chart-rail-$key')), findsOneWidget);
      }
      final withRail = plotWidth();

      await tester.tap(hide);
      await tester.pump();
      expect(rail, findsNothing);
      expect(show, findsOneWidget);
      // The rail's width (44) and its gap go back to the plot.
      expect(plotWidth(), greaterThan(withRail + 44));

      // Next time Advanced opens, the rail stays tucked as it was left.
      await tester.tap(find.text('Done'));
      await tester.pump(const Duration(milliseconds: 400));
      await enterEdit(tester);
      expect(rail, findsNothing);
      expect(show, findsOneWidget);

      await tester.tap(show);
      await tester.pump();
      expect(rail, findsOneWidget);
      expect(show, findsNothing);
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

/// The mids socket, driven by the test.
class _DrivenPrices extends _LivePrices {
  void put(double btc) => state = HlLivePriceState(mids: {'BTC': btc});
}

/// A short in a loss: (64,000 - 66,000) x 0.5 at the live mark.
const _shortIsolated = HlPerpPosition(
  coin: 'BTC',
  szi: -0.5,
  entryPx: 64000,
  positionValue: 33000,
  unrealizedPnl: -1000,
  returnOnEquity: 0,
  liquidationPx: 76000,
  marginUsed: 6400,
  leverageType: 'isolated',
  leverageValue: 5,
  maxLeverage: 40,
);
