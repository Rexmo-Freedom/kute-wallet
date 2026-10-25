// The Portfolio's open positions as plain list rows ("option B"): the
// real picture in a circle (a market's image, a coin's logo), a short
// title (the held outcome's own name, the asset's name), "event · side"
// or "Long · 0.0125 BTC" (never a leverage figure), a Predictions row's
// chance bar for the held side (none once settled), the value with its
// P&L % in a tinted pill (quiet when under a cent), and the taps of the
// old cards.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart'
    show PolymarketEvent, PolymarketOutcome;
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition;
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_position_detail_sheet.dart';
import 'package:kute/screens/polymarket/components/market_card.dart'
    show PolyCardThumbnail;
import 'package:kute/screens/portfolio/components/position_rows.dart';
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyPositionEventProvider;
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/portfolio_overrides.dart';

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => _livePrices;

  @override
  void acquire() {}

  @override
  void release() {}

  @override
  void registerCardTokens(List<String> tokens) {}

  @override
  void unregisterCardTokens(List<String> tokens) {}
}

/// The live feed the rows read (none by default).
LivePriceState _livePrices = const LivePriceState();

/// The Ballon d'Or event, Harry Kane's market among its sub-markets.
const _ballonDor = PolymarketEvent(
  id: 'bdo',
  slug: 'ballon-dor-2026',
  title: "Ballon d'Or 2026",
  volume: 1e6,
  liquidity: 1e5,
  category: 'sports',
  conditionId: 'kane',
  outcomes: [
    PolymarketOutcome(
        name: 'Harry Kane',
        price: 0.72,
        conditionId: 'kane',
        tokenId: 'kane-yes',
        noTokenId: 'kane-no'),
    PolymarketOutcome(
        name: 'Lamine Yamal',
        price: 0.2,
        conditionId: 'yamal',
        tokenId: 'yamal-yes',
        noTokenId: 'yamal-no'),
  ],
);

const _kane = PolymarketPosition(
    marketId: 'kane',
    marketQuestion: "Will Harry Kane win the 2026 Ballon d'Or?",
    marketImage: 'https://example.invalid/kane.jpg',
    outcome: 'Yes',
    size: 4.99,
    avgPrice: 0.72,
    currentPrice: 0.718,
    pnl: 0,
    pnlPercent: 0,
    isResolved: false,
    tokenId: 'kane-yes',
    eventSlug: 'ballon-dor-2026');

const _btc = HlPerpPosition(
    coin: 'BTC',
    szi: 0.00012,
    entryPx: 90120,
    positionValue: 11.22,
    unrealizedPnl: 0.4,
    returnOnEquity: 0.04,
    liquidationPx: null,
    marginUsed: 10.82,
    leverageType: 'cross',
    leverageValue: 3,
    maxLeverage: 40);

const _nvda = HlPerpPosition(
    coin: 'xyz:NVDA',
    szi: -3,
    entryPx: 182.4,
    positionValue: 558.3,
    unrealizedPnl: -11.1,
    returnOnEquity: -0.02,
    liquidationPx: 360,
    marginUsed: 547.2,
    leverageType: 'isolated',
    leverageValue: 1,
    maxLeverage: 10);

final _nvdaMarket = HlMarket(
    coin: 'NVDA',
    wireCoin: 'xyz:NVDA',
    assetId: 1,
    kind: HlMarketKind.perp,
    szDecimals: 3,
    maxLeverage: 10,
    onlyIsolated: true,
    markPx: 186.1,
    midPx: 186.1,
    prevDayPx: 180,
    dayNtlVlm: 1e6,
    category: 'stocks',
    dex: 'xyz',
    isHip3: true);

Future<void> _pump(WidgetTester tester, Widget row) async {
  tester.view.physicalSize = const Size(390, 400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...portfolioOverrides(),
      livePriceProvider.overrideWith(_Prices.new),
      polyPositionEventProvider('ballon-dor-2026')
          .overrideWith((_) => _ballonDor),
      hyperliquidLiveMidProvider('BTC').overrideWith((_) => null),
      hyperliquidLiveMidProvider('xyz:NVDA').overrideWith((_) => null),
      hyperliquidPerpMarketsProvider.overrideWith((_) async => [_nvdaMarket]),
      hyperliquidSpotMarketsProvider.overrideWith((_) async => <HlMarket>[]),
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: '',
          reviewDone: true))),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
            body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(children: [row]))),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

RollingFigure _figure(WidgetTester tester, String key) =>
    tester.widget<RollingFigure>(find.byKey(ValueKey(key)));

Color _pillColor(WidgetTester tester) => ((tester
        .widget<DecoratedBox>(
            find.byKey(const ValueKey('portfolio-row-pnl-pill')))
        .decoration) as BoxDecoration)
    .color!;

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    _livePrices = const LivePriceState();
  });

  group('the P&L pill', () {
    test('a gain, a loss: the % alone, signed with the app\'s signs', () {
      final up = portfolioPnlPill(0.42, percent: 4.0)!;
      expect(up.text, '+4.0%');
      expect(up.tone, PortfolioPnlTone.up);
      final down = portfolioPnlPill(-0.42, percent: -4.0)!;
      expect(down.text, '−4.0%');
      expect(down.tone, PortfolioPnlTone.down);
    });

    test('under a cent, or a % that rounds to nothing: "0.0%", flat', () {
      for (final pnl in [-0.004, 0.0, 0.0049, -0.0]) {
        final pill = portfolioPnlPill(pnl, percent: -0.1)!;
        expect(pill.text, '0.0%');
        expect(pill.tone, PortfolioPnlTone.flat);
      }
      expect(
          portfolioPnlPill(0.02, percent: 0.01)!.tone, PortfolioPnlTone.flat);
      expect(portfolioPnlPill(-0.42), isNull);
    });
  });

  group('a Predictions row\'s names', () {
    String date(DateTime d) => 'Oct ${d.day}';

    test('a many-outcome event: the sub-market\'s own name, "event · side"',
        () {
      final names = polyPositionRowNames(
          question: _kane.marketQuestion,
          side: 'Yes',
          marketId: 'kane',
          tokenId: 'kane-yes',
          event: _ballonDor);
      expect(names.title, 'Harry Kane');
      expect(polyPositionRowLine(names, 'Yes'), "Ballon d'Or 2026 · Yes");
      expect(polyPositionRowLine(names, 'Yes', status: 'Settled'),
          "Ballon d'Or 2026 · Settled");
      // Held through its No token, matched the same way.
      expect(
          polyPositionRowNames(
                  question: _kane.marketQuestion,
                  side: 'No',
                  tokenId: 'kane-no',
                  event: _ballonDor)
              .title,
          'Harry Kane');
    });

    test('a named side is the title; a plain side never is', () {
      final f1 = polyPositionRowNames(
          question: 'Who will finish higher: Verstappen or Hadjar?',
          side: 'Verstappen');
      expect(f1.title, 'Verstappen');
      expect(polyPositionRowLine(f1, 'Verstappen'), 'Who will finish higher');
      expect(polyPositionRowLine(f1, 'Verstappen', status: 'Settled'),
          'Who will finish higher · Settled');
      final updown = polyPositionRowNames(
          question: 'Bitcoin Up or Down - October 25, 9AM ET', side: 'Up');
      expect(updown.title, 'Bitcoin Up or Down');
      expect(polyPositionRowLine(updown, 'Up'), 'Up');
    });

    test(
        'a binary market: the event\'s short title, else the question '
        'shortened; before its event loads, the candidate it names', () {
      const single = PolymarketEvent(
          id: 'fed',
          slug: 'fed',
          title: 'Fed rate cut in December?',
          volume: 0,
          liquidity: 0,
          category: 'economy',
          conditionId: 'fed',
          outcomes: [
            PolymarketOutcome(name: 'Yes', price: 0.3, conditionId: 'fed'),
            PolymarketOutcome(name: 'No', price: 0.7, conditionId: 'fed'),
          ]);
      final fed = polyPositionRowNames(
          question: 'Will the Fed cut rates in December?',
          side: 'No',
          marketId: 'fed',
          event: single);
      expect(fed.title, 'Fed rate cut in December');
      expect(polyPositionRowLine(fed, 'No'), 'No');

      final madrid = polyPositionRowNames(
          question: 'Will Real Madrid CF win on 2026-10-25?',
          side: 'No',
          date: date);
      expect(madrid.title, 'Real Madrid CF');
      expect(polyPositionRowLine(madrid, 'No'), 'Win Oct 25 · No');

      final long = polyPositionRowNames(
          question: 'Will the Fed cut rates in December?', side: 'Yes');
      expect(long.title, 'The Fed cut rates in December');
      // A "Will it …?" question stays a sentence.
      expect(
          polyPositionRowNames(question: 'Will it rain tomorrow?', side: 'Yes')
              .title,
          'Will it rain tomorrow?');
    });
  });

  testWidgets(
      'a Polymarket row: its image in a circle, the outcome\'s own name, '
      '"event · side", the held side\'s chance, the value and the loss',
      (tester) async {
    await _pump(tester, const PolyPositionRow(position: _kane));
    expect(
        find.descendant(
            of: find.byType(ClipOval),
            matching: find.byType(PolyCardThumbnail)),
        findsOneWidget);
    final title =
        tester.widget<Text>(find.byKey(const ValueKey('portfolio-row-title')));
    expect(title.data, 'Harry Kane');
    // Short by construction: two lines at most, never one cut short.
    expect(title.maxLines, 2);
    expect(_text(tester, 'portfolio-row-subtitle'), "Ballon d'Or 2026 · Yes");
    final bar = tester.widget<PortfolioChanceBar>(
        find.byKey(const ValueKey('portfolio-row-chance')));
    expect(bar.chance, closeTo(0.718, 1e-9));
    expect(_figure(tester, 'portfolio-row-value').text, r'$3.58');
    final pnl = _figure(tester, 'portfolio-row-pnl');
    // The % alone: the $ P&L is on the position screen.
    expect(pnl.text, '−0.3%');
    expect(pnl.style.color, AppColors.marketDown);
    expect(_pillColor(tester), AppColors.marketDown.withValues(alpha: 0.12));
    expect(find.textContaining('shares'), findsNothing);
    // No card: no surface, no border around the row.
    expect(
        find.byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            ((w.decoration! as BoxDecoration).boxShadow != null ||
                (w.decoration! as BoxDecoration).border != null)),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the chance bar follows the held side\'s live price',
      (tester) async {
    _livePrices = const LivePriceState(live: true, prices: {'kane-yes': 0.81});
    await _pump(tester, const PolyPositionRow(position: _kane));
    expect(
        tester
            .widget<PortfolioChanceBar>(
                find.byKey(const ValueKey('portfolio-row-chance')))
            .chance,
        0.81);
    expect(_figure(tester, 'portfolio-row-pnl').text, '+12.5%');
    expect(_pillColor(tester), AppColors.marketUp.withValues(alpha: 0.12));
  });

  testWidgets('a P&L that rounds to no cent reads flat in the quiet colour',
      (tester) async {
    const flat = PolymarketPosition(
        marketId: 'f',
        marketQuestion: 'Flat?',
        outcome: 'No',
        size: 10,
        avgPrice: 0.5,
        currentPrice: 0.5003,
        pnl: 0,
        pnlPercent: 0,
        isResolved: false,
        tokenId: 'f-no');
    await _pump(tester, const PolyPositionRow(position: flat));
    final pnl = _figure(tester, 'portfolio-row-pnl');
    expect(pnl.text, '0.0%');
    expect(pnl.style.color, AppColorsExtension.light().textSecondary);
    expect(_pillColor(tester), AppColorsExtension.light().surfaceLight);
    expect(find.textContaining('−'), findsNothing);
  });

  testWidgets('a settled position says so in place of the side, no bar',
      (tester) async {
    const won = PolymarketPosition(
        marketId: 'w',
        marketQuestion: 'Won?',
        outcome: 'Up',
        size: 4.67,
        avgPrice: 0.56,
        currentPrice: 1,
        pnl: 0,
        pnlPercent: 0,
        isResolved: true,
        won: true,
        tokenId: 'w-up');
    await _pump(tester, const PolyPositionRow(position: won));
    expect(_text(tester, 'portfolio-row-title'), 'Won');
    expect(_text(tester, 'portfolio-row-subtitle'), 'Up · Settled');
    expect(find.byType(PortfolioChanceBar), findsNothing);
    expect(_figure(tester, 'portfolio-row-pnl').text, '+78.6%');
  });

  testWidgets(
      'a Hyperliquid long: the coin logo, "Long · 0.00012 BTC", no entry '
      'price, no chance bar, never a leverage figure', (tester) async {
    await _pump(tester, const HlPositionRow(position: _btc));
    expect(find.byType(HlCoinIcon), findsOneWidget);
    expect(_text(tester, 'portfolio-row-title'), 'Bitcoin');
    expect(_text(tester, 'portfolio-row-subtitle'), 'Long · 0.00012 BTC');
    expect(find.textContaining('entry'), findsNothing);
    expect(find.byType(PortfolioChanceBar), findsNothing);
    expect(find.textContaining('3x'), findsNothing);
    expect(find.textContaining('Liq'), findsNothing);
    final pnl = _figure(tester, 'portfolio-row-pnl');
    expect(pnl.text, '+3.7%');
    expect(pnl.style.color, AppColors.marketUp);
  });

  testWidgets('a HIP-3 short: the ticker without its dex, the name, the logo',
      (tester) async {
    await _pump(tester, const HlPositionRow(position: _nvda));
    await tester.pump();
    final icon = tester.widget<HlCoinIcon>(find.byType(HlCoinIcon));
    expect(icon.wireCoin, 'xyz:NVDA');
    expect(_text(tester, 'portfolio-row-title'), 'Nvidia');
    expect(_text(tester, 'portfolio-row-subtitle'), 'Short · 3 NVDA');
    expect(
        _figure(tester, 'portfolio-row-pnl').style.color, AppColors.marketDown);
    expect(_pillColor(tester), AppColors.marketDown.withValues(alpha: 0.12));
  });

  testWidgets('a tap opens what the card opened, with the same event',
      (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    var tapped = 0;
    await _pump(
        tester,
        PortfolioPositionRow(
            leading: const SizedBox(),
            title: 't',
            subtitle: 's',
            value: r'$1.00',
            onTap: () => tapped++));
    await tester.tap(find.text('t'));
    expect(tapped, 1);

    await _pump(tester, const HlPositionRow(position: _btc));
    await tester.tap(find.text('Bitcoin'));
    await tester.pump();
    final taps =
        events.where((e) => e.$1 == 'open_investments_position_tapped');
    expect(taps.length, 1);
    expect(taps.single.$2, {'product': 'trading'});
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(HlPositionDetailSheet), findsOneWidget);
    // The position sheet opened; drain it and its timers.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  });
}
