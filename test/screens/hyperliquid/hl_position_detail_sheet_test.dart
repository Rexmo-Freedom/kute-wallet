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
import 'package:kute/screens/shared/kute_dog_scenes.dart' show KuteDogGlance;
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

    // The side is a row, not a chip.
    expect(find.byType(HlSideChip), findsNothing);
    expect(find.text('Side'), findsOneWidget);
    expect(find.text('Long'), findsOneWidget);
    // The position size is the notional at the live mark (66,000 x 0.5)
    // with the coin size: a row, never the headline.
    expect(find.text('Position size'), findsOneWidget);
    expect(find.text(r'$33,000.00 · 0.5 BTC'), findsOneWidget);
    expect(tester.widget<Text>(find.text(r'$33,000.00 · 0.5 BTC')).textAlign,
        TextAlign.right);

    // An isolated position's margin (what was put in), and one Liquidation
    // row with how far the live mark (66,000) is from it: 8,000 / 66,000.
    expect(find.text('Margin'), findsOneWidget);
    expect(find.text(r'$6,400.00'), findsOneWidget);
    expect(find.text('Your money in it'), findsNothing);
    expect(find.text('Collateral'), findsNothing);
    expect(find.text('Liquidation'), findsOneWidget);
    expect(find.text(r'$58,000 · 12% away'), findsOneWidget);
    // Margin lives in that row: no separate buttons, no explanation. The
    // market has not loaded, so nothing can sign margin yet: no button.
    expect(find.text('Remove margin'), findsNothing);
    expect(find.byKey(const ValueKey('hl-add-margin')), findsNothing);

    // Details: the same rows; the live price and the return are not
    // written a second time.
    expect(find.byType(PositionRowsCard), findsOneWidget);
    // Details is a row opening the shared bottom sheet, once.
    await tester.ensureVisible(find.text('Details'));
    await tester.tap(find.text('Details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AppBottomSheetContainer), findsOneWidget);
    expect(find.byType(PositionRowsCard), findsNWidgets(2));
    expect(find.text('Bought at'), findsOneWidget);
    expect(find.text('Liquidation price'), findsOneWidget);
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

  testWidgets('the header is close, logo, ticker and price, no Sal button; '
      'Sal\'s question capsule sits under the P&L, grounded on the public '
      'market, and asks its question from position_capsule', (tester) async {
    OpenOnce.reset();
    addTearDown(OpenOnce.reset);
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    final prompts = <AdvisorPrompt?>[];
    await tester.runAsync(() => AdvisorInputGuard.isSafe('Public question'));
    await _pump(tester, ai: true, extra: [
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
              markdown: 'Funding is low.')
        ])));
      }),
    ]);
    final header = find
        .ancestor(of: find.byType(KuteCloseButton), matching: find.byType(Row))
        .first;
    expect(find.descendant(of: header, matching: find.byType(HlCoinIcon)),
        findsWidgets);
    expect(find.descendant(of: header, matching: find.text('BTC')),
        findsOneWidget);
    expect(find.descendant(of: header, matching: find.byType(HlTickPrice)),
        findsOneWidget);
    expect(find.byType(AskSalChip), findsNothing);
    expect(find.byKey(const ValueKey('ask-sal-pill')), findsNothing);
    final capsule = find.byType(SalQuestionCapsule);
    expect(capsule, findsOneWidget);
    final widget = tester.widget<SalQuestionCapsule>(capsule);
    expect(widget.entry, 'position_capsule');
    expect(widget.advisorContext.surface, 'hyperliquid_position_detail');
    expect(widget.advisorContext.toRequestMarket,
        {'venue': 'hyperliquid', 'id': 'BTC'});
    expect(widget.chipSignals.holdsPosition, isTrue);
    final pnl = find.byWidgetPredicate(
        (w) => w is RollingNumberText && w.text.startsWith(r'+$1,000.00'));
    expect(
        tester.getRect(find.byKey(const ValueKey('sal-question-capsule'))).top,
        greaterThan(tester.getRect(pnl).bottom));
    final text = find.byKey(const ValueKey('sal-question-capsule-text'));
    final question = tester.widget<Text>(text).data!;
    await tester.tap(find.byKey(const ValueKey('sal-question-capsule')));
    await tester.pump();
    await tester.runAsync(() async {});
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(prompts, hasLength(1));
    expect(find.text(question), findsWidgets);
    final opened = events.firstWhere((e) => e.$1 == 'sal_opened').$2!;
    expect(opened['entry'], 'position_capsule');
    expect(opened['surface'], 'hyperliquid_position_detail');
    final asked = events.firstWhere((e) => e.$1 == 'sal_question_asked').$2!;
    expect(asked['input'], 'suggested');
    expect(asked['chip_index'], 0);
    await tester.pumpWidget(const SizedBox.shrink());
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
    // A cross position's margin is the collateral it ties up; closing
    // gives that back with the live P&L (6,400 + 1,000).
    expect(find.text('Collateral'), findsOneWidget);
    expect(find.text('Margin'), findsNothing);
    expect(find.byWidgetPredicate(
            (w) => w is RollingNumberText && w.text == r'$7,400.00'),
        findsOneWidget);
    expect(find.text('Liquidation'), findsOneWidget);
    expect(find.text(r'$62,000 · 6.1% away'), findsOneWidget);
    expect(find.byKey(const ValueKey('hl-add-margin')), findsNothing);
    expect(find.text('Add margin'), findsNothing);
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
            home: screen,
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

    const salContext = AdvisorContext(
      surface: 'hl_market_detail',
      marketVenue: 'hyperliquid',
      marketId: 'BTC',
      marketDisplayName: 'BTC',
    );
    final capsule = find.byKey(const ValueKey('sal-question-capsule'));
    final capsuleText =
        find.byKey(const ValueKey('sal-question-capsule-text'));
    final aboutRow = find.ancestor(
        of: find.text('About Bitcoin'), matching: find.byType(InkWell));
    Finder headerRow() => find
        .ancestor(
            of: find.byType(KuteCircleBackButton), matching: find.byType(Row))
        .first;

    for (final width in [320.0, 430.0]) {
      testWidgets('the market sheet at ${width.toInt()} wide: the header '
          'keeps logo, ticker and price with the star and no Sal button; '
          'Sal\'s question capsule sits under it, above the chart, never cut',
          (tester) async {
        await loadInter(tester);
        await pumpScreen(tester, const HlMarketDetailSheet(market: btc),
            ai: true, width: width, font: 'Inter');
        final header = headerRow();
        expect(find.descendant(of: header, matching: find.byType(HlCoinIcon)),
            findsWidgets);
        expect(find.descendant(of: header, matching: find.text('BTC')),
            findsWidgets);
        expect(
            find.descendant(of: header, matching: find.byType(HlTickPrice)),
            findsOneWidget);
        expect(find.descendant(of: header, matching: find.byType(HlWatchStar)),
            findsOneWidget);
        expect(find.byType(AskSalChip), findsNothing);
        expect(find.byKey(const ValueKey('ask-sal-pill')), findsNothing);
        // The capsule: under the header, above the chart, the old row
        // above About gone.
        expect(capsule, findsOneWidget);
        expect(find.byKey(const ValueKey('hl-sal-row')), findsNothing);
        expect(tester.getRect(capsule).top,
            greaterThanOrEqualTo(tester.getRect(header).bottom));
        expect(tester.getRect(capsule).bottom,
            lessThanOrEqualTo(tester.getRect(find.byType(HlCandleChart)).top));
        expect(tester.getRect(capsule).width,
            moreOrLessEquals(width - 40.w, epsilon: 1));
        final top = AskSalChip.topQuestion(
            tester.element(capsule), salContext, salSignalsForHlMarket(btc))!;
        expect(tester.widget<Text>(capsuleText).data, top.text);
        expect(find.descendant(of: capsule, matching: find.byType(KuteDogGlance)),
            findsOneWidget);
        // The whole question, in at most two lines.
        final paragraph = tester.renderObject<RenderParagraph>(capsuleText);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(
            paragraph
                .getBoxesForSelection(
                    TextSelection(baseOffset: 0, extentOffset: top.text.length))
                .map((b) => b.top.round())
                .toSet()
                .length,
            lessThanOrEqualTo(2));
        expect(aboutRow, findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('the capsule opens Sal asking its question, from '
        'market_capsule', (tester) async {
      OpenOnce.reset();
      addTearDown(OpenOnce.reset);
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final prompts = <AdvisorPrompt?>[];
      await tester.runAsync(() => AdvisorInputGuard.isSafe('Public question'));
      await pumpScreen(tester, const HlMarketDetailSheet(market: btc),
          ai: true,
          extra: [
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
      final top = AskSalChip.topQuestion(
          tester.element(capsule), salContext, salSignalsForHlMarket(btc))!;
      await tester.tap(capsule);
      await tester.pump();
      await tester.runAsync(() async {});
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(prompts.single?.template, top.template);
      expect(find.textContaining('Bitcoin moved on the rate decision.'),
          findsOneWidget);
      final opened = events.firstWhere((e) => e.$1 == 'sal_opened').$2!;
      expect(opened['entry'], 'market_capsule');
      expect(opened['surface'], 'hl_market_detail');
      expect(opened.containsKey('expanded'), isFalse);
      final asked = events.firstWhere((e) => e.$1 == 'sal_question_asked').$2!;
      expect(asked['input'], 'suggested');
      expect(asked['template'], top.template);
      expect(asked['chip_index'], 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Sal switched off: no capsule, About stays', (tester) async {
      await pumpScreen(tester, const HlMarketDetailSheet(market: btc));
      expect(capsule, findsNothing);
      expect(aboutRow, findsOneWidget);
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

class _Trading extends HyperliquidTradingNotifier {
  @override
  Future<HyperliquidTradingState> build() async =>
      const HyperliquidTradingState(isInitialized: true);
}
