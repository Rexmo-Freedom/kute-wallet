// The Portfolio's open positions as plain list rows ("option B"): the
// real picture in a circle (a market's image, a coin's logo), a short
// title (the held outcome's own name, the asset's name), "event · side"
// or "Long · 0.0125 BTC" (never a leverage figure), a Predictions row's
// chance bar for the held side (none once settled), the value with its
// P&L in money and as a % under it (quiet when under a cent; founder, 6
// November 2026: "say how much I am actually winning in dollars"), the
// squares' corner writing the money over its %, and the taps of the old
// cards.

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
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/euro_settings.dart';
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

Future<void> _pump(WidgetTester tester, Widget row,
    {double width = 390,
    double textScale = 1,
    String currency = 'USD',
    int balancePrivacy = 0,
    double height = 400}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
      if (currency == 'EUR') euroRateOverride(),
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
          currency: currency,
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: '',
          reviewDone: true,
          balancePrivacy: balancePrivacy))),
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

Color _pillColor(WidgetTester tester) =>
    _figure(tester, 'portfolio-row-pnl').style.color!;

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    _livePrices = const LivePriceState();
  });

  testWidgets('the chance bar ticks where the position was bought',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Builder(builder: (context) {
            return const PortfolioChanceBar(
                chance: 0.71, entry: 0.5, width: 200);
          }),
        ),
      ),
      theme: ThemeData(extensions: [AppColorsExtension.light()]),
    ));
    final tick = find.byKey(const ValueKey('portfolio-row-entry-tick'));
    expect(tick, findsOneWidget);
    final bar = tester.getTopLeft(find.byType(PortfolioChanceBar));
    expect(tester.getTopLeft(tick).dx - bar.dx, closeTo(99, 0.5));
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

  group('the Portfolio screen\'s squares', () {
    test('whole rows of two only: two for two or three, four from four, one '
        'alone for one', () {
      expect([for (var n = 0; n <= 7; n++) portfolioSquareCount(n)],
          [0, 1, 2, 2, 4, 4, 4, 4]);
    });

    test('the Investing row\'s name says a side other than Yes', () {
      final kane = polyPositionRowNames(
          question: _kane.marketQuestion,
          side: 'Yes',
          marketId: 'kane',
          tokenId: 'kane-yes',
          event: _ballonDor);
      expect(polyPositionListName(kane, 'Yes'), 'Harry Kane');
      expect(polyPositionListName(kane, 'No'), 'Harry Kane · No');
      // The title is the side: alone.
      final named = polyPositionRowNames(
          question: 'Who will win the Las Vegas Grand Prix?',
          side: 'Verstappen');
      expect(polyPositionListName(named, 'Verstappen'), 'Verstappen');
      // Read before its event: a name cut from the question reads as the
      // whole short question, its rest having no line to go on.
      const question = r'Will Bitcoin reach $150,000 in 2026?';
      final cut = polyPositionRowNames(question: question, side: 'No');
      expect(cut.title, 'Bitcoin');
      expect(polyPositionListName(cut, 'No', question: question),
          r'Bitcoin reach $150,000 in 2026 · No');
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

    test('a 5-minute window is titled by its own name, event or none', () {
      const name = 'BTC up or down · 7:20–7:25';
      final held = polyPositionRowNames(
          question: 'Bitcoin Up or Down - November 8, 7:20AM-7:25AM ET',
          side: 'Up',
          windowName: name);
      expect(held.title, name);
      expect(held.context, isEmpty);
      expect(polyPositionRowChip(held, 'Up'), 'Up');
      expect(polyPositionRowLine(held, 'Up'), 'Up');
      expect(polyPositionListName(held, 'Up'), '$name · Up');
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
    // The money first, then the %: (0.718 − 0.72) × 4.99 = −$0.01, −0.3 %.
    expect(_figure(tester, 'portfolio-row-pnl-usd').text, r'$0.01');
    expect(_figure(tester, 'portfolio-row-pnl-usd').style.color,
        AppColors.marketDown);
    expect(pnl.text, '0.3%');
    expect(pnl.style.color, AppColors.marketDown);
    expect(_pillColor(tester), AppColors.marketDown);
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
    // 0.09 × 4.99 = +$0.45, +12.5 %.
    expect(_figure(tester, 'portfolio-row-pnl-usd').text, r'$0.45');
    expect(_figure(tester, 'portfolio-row-pnl').text, '12.5%');
    expect(_pillColor(tester), AppColors.marketUp);
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
    expect(_figure(tester, 'portfolio-row-pnl-usd').text, r'$0.00');
    expect(pnl.text, '0.0%');
    expect(pnl.style.color, AppColorsExtension.light().textSecondary);
    expect(_pillColor(tester), AppColorsExtension.light().textSecondary);
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
    expect(_figure(tester, 'portfolio-row-pnl').text, '78.6%');
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
    expect(_figure(tester, 'portfolio-row-pnl-usd').text, r'$0.40');
    expect(pnl.text, '3.7%');
    expect(pnl.style.color, AppColors.marketUp);
  });

  group('the P&L in money on every shape (founder, 6 November 2026)', () {
    Widget scoped(PortfolioRowLayout layout, Widget row, {double? width}) =>
        PortfolioRowLayoutScope(
          layout: layout,
          child: width == null ? row : SizedBox(width: width, child: row),
        );

    for (final scale in [1.0, 1.3]) {
      testWidgets(
          'a square at 375 pt and ${(scale * 100).round()} % text: the '
          'corner reads the money over its %, in the result\'s colour, '
          'tabular, clear of the logo and inside the square; the big number '
          'stays the value', (tester) async {
        // Two squares to a row at 375 pt: 16 gutters, a 10 gap.
        final side = (375 - 32 - 10) / 2 * 375 / 430;
        await _pump(
            tester,
            width: 375,
            textScale: scale,
            scoped(PortfolioRowLayout.square, const HlPositionRow(position: _nvda),
                width: side));
        expect(tester.takeException(), isNull);
        final usd = _figure(tester, 'portfolio-row-pnl-usd');
        final percent = _figure(tester, 'portfolio-row-pnl');
        // −3 × (186.1 − 182.4) at no live mid: the venue's −$11.10, on its
        // $558.30 margin: −2.0 %.
        expect(usd.text, r'▼ $11.10');
        expect(percent.text, '2.0%');
        expect(usd.style.color, AppColors.marketDown);
        expect(percent.style.color, AppColors.marketDown);
        for (final f in [usd, percent]) {
          expect(f.style.fontFeatures,
              contains(const FontFeature.tabularFigures()));
        }
        // The money over the %, right-aligned, inside the square, right
        // of the logo.
        final square = tester.getRect(find.byKey(const ValueKey('portfolio-square')));
        final usdRect =
            tester.getRect(find.byKey(const ValueKey('portfolio-row-pnl-usd')));
        final pctRect =
            tester.getRect(find.byKey(const ValueKey('portfolio-row-pnl')));
        final logo = tester.getRect(find.byType(HlCoinIcon));
        expect(usdRect.bottom, lessThanOrEqualTo(pctRect.top + 0.5));
        expect(usdRect.right, moreOrLessEquals(pctRect.right, epsilon: 0.5));
        expect(usdRect.left, greaterThan(logo.right));
        expect(pctRect.left, greaterThan(logo.right));
        expect(usdRect.right, lessThanOrEqualTo(square.right));
        expect(pctRect.bottom, lessThan(
            tester.getRect(find.byKey(const ValueKey('portfolio-row-title'))).top));
        // The big number is still what the position is worth.
        expect(_figure(tester, 'portfolio-row-value').text, r'$547.20');
      });
    }

    testWidgets('a square with a long name and a wide P&L: nothing overflows',
        (tester) async {
      const whale = HlPerpPosition(
          coin: 'BTC',
          szi: 12.5,
          entryPx: 60000,
          positionValue: 1312500,
          unrealizedPnl: 562500.55,
          returnOnEquity: 0.75,
          liquidationPx: null,
          marginUsed: 750000,
          leverageType: 'cross',
          leverageValue: 1,
          maxLeverage: 40);
      await _pump(
          tester,
          width: 375,
          scoped(PortfolioRowLayout.square, const HlPositionRow(position: whale),
              width: (375 - 32 - 10) / 2 * 375 / 430));
      expect(tester.takeException(), isNull);
      expect(_figure(tester, 'portfolio-row-pnl-usd').text, r'▲ $562,500.55');
      final square = tester.getRect(find.byKey(const ValueKey('portfolio-square')));
      final usd = tester.getRect(find.byKey(const ValueKey('portfolio-row-pnl-usd')));
      expect(usd.right, lessThanOrEqualTo(square.right));
      expect(usd.left,
          greaterThan(tester.getRect(find.byType(HlCoinIcon)).right));
    });

    testWidgets('a flat square: "\$0.00" over "0.0%", quietly, no arrow',
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
      await _pump(
          tester,
          width: 375,
          scoped(PortfolioRowLayout.square,
              const PolyPositionRow(position: flat),
              width: 160));
      expect(_figure(tester, 'portfolio-row-pnl-usd').text, r'$0.00');
      expect(_figure(tester, 'portfolio-row-pnl').text, '0.0%');
      expect(_figure(tester, 'portfolio-row-pnl-usd').style.color,
          AppColorsExtension.light().textSecondary);
    });

    testWidgets('the Investing list\'s row: "▲ \$0.40 · 3.7%" under the value',
        (tester) async {
      await _pump(tester,
          scoped(PortfolioRowLayout.market, const HlPositionRow(position: _btc)));
      final change = tester.widget<RollingNumberText>(find.descendant(
          of: find.byKey(const ValueKey('portfolio-row-pnl')),
          matching: find.byType(RollingNumberText)));
      expect(change.text, r'▲ $0.40 · 3.7%');
      expect(change.style.color, AppColors.marketUp);
    });

    testWidgets('euros in Settings: the same dollars, the same percent',
        (tester) async {
      await _pump(tester,
          scoped(PortfolioRowLayout.market, const HlPositionRow(position: _btc)),
          currency: 'EUR');
      final change = tester.widget<RollingNumberText>(find.descendant(
          of: find.byKey(const ValueKey('portfolio-row-pnl')),
          matching: find.byType(RollingNumberText)));
      expect(change.text, r'▲ $0.40 · 3.7%');
      expectNoEuroOnScreen(tester);
    });
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
    expect(_pillColor(tester), AppColors.marketDown);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets(
        'in the soft card at 375 pt and ${(scale * 100).round()} % text: '
        'no overflow, the figures whole inside the card\'s 16 inset, a '
        'long title cut with an ellipsis, a wide figure scaled down',
        (tester) async {
      await _pump(
          tester,
          width: 375,
          textScale: scale,
          const PortfolioCardList(rows: [
            PortfolioPositionRow(
                leading: SizedBox(),
                title: 'Democratic Presidential Nominee 2028 and some more '
                    'words that never fit',
                subtitle: 'Democratic Presidential Nominee 2028 · No',
                value: r'$10,812.37',
                chance: 0.51,
                entry: 0.5,
                pnl: (text: '+0.4%', tone: PortfolioPnlTone.up)),
            PortfolioPositionRow(
                leading: SizedBox(),
                title: 'Bitcoin',
                subtitle: 'Long · 0.1 BTC',
                value: r'$1,234,567,890.12',
                pnl: (text: '−12345.6%', tone: PortfolioPnlTone.down)),
          ]));
      expect(tester.takeException(), isNull);
      final card = tester.getRect(find.byType(PortfolioCardList));
      final inset = 16 * 375 / 430;
      expect(find.descendant(
              of: find.byType(PortfolioCardList),
              matching: find.byType(Divider)),
          findsOneWidget);
      final rows = find.byType(PortfolioPositionRow);
      for (var i = 0; i < 2; i++) {
        Rect inRow(String key) => tester.getRect(find
            .descendant(of: rows.at(i), matching: find.byKey(ValueKey(key)))
            .first);
        final title = inRow('portfolio-row-title');
        final figures = inRow('portfolio-row-figures');
        for (final key in ['portfolio-row-value', 'portfolio-row-pnl-pill']) {
          final r = inRow(key);
          expect(r.right, lessThanOrEqualTo(card.right - inset + 0.5),
              reason: 'row $i $key past the card\'s inset');
          expect(r.left, greaterThanOrEqualTo(figures.left - 0.5));
          expect(r.right, moreOrLessEquals(card.right - inset, epsilon: 0.5));
        }
        expect(title.right, lessThanOrEqualTo(figures.left));
        // The figures never take more than 45% of the row.
        expect(figures.width,
            lessThanOrEqualTo((card.width - 2 * inset) * 0.45 + 0.5));
      }
      final longTitle = tester.widget<Text>(find
          .descendant(
              of: rows.first,
              matching: find.byKey(const ValueKey('portfolio-row-title')))
          .first);
      expect(longTitle.overflow, TextOverflow.ellipsis);
      // The chance bar under the title, from where it starts, before the
      // figures.
      final bar = tester.getRect(
          find.byKey(const ValueKey('portfolio-row-chance')));
      final firstTitle = tester.getRect(find
          .descendant(
              of: rows.first,
              matching: find.byKey(const ValueKey('portfolio-row-title')))
          .first);
      expect(bar.left, moreOrLessEquals(firstTitle.left, epsilon: 0.5));
      expect(
          bar.right,
          lessThanOrEqualTo(tester
              .getRect(find
                  .descendant(
                      of: rows.first,
                      matching:
                          find.byKey(const ValueKey('portfolio-row-figures')))
                  .first)
              .left));
      expect(bar.bottom, lessThanOrEqualTo(tester.getRect(rows.first).bottom));
    });
  }

  group('the Portfolio screen\'s Positions as squares (8 November 2026)', () {
    test(
        'the line under a square\'s name leads with the side, then the state, '
        'the event last, so a narrow square never loses what is held', () {
      const held = (
        title: 'Sunderland AFC',
        context: 'Sunderland AFC vs. Chelsea FC',
        titleIsSide: false
      );
      expect(polyPositionSquareLine(held, 'Yes'),
          'Yes · Sunderland AFC vs. Chelsea FC');
      expect(polyPositionSquareLine(held, 'Yes', status: 'Settled'),
          'Yes · Settled · Sunderland AFC vs. Chelsea FC');
      // The title says the side: no side again.
      expect(
          polyPositionSquareLine(
              (title: 'Verstappen', context: 'F1', titleIsSide: true),
              'Verstappen',
              status: 'Settled'),
          'Settled · F1');
      // The event no more than the title: left out.
      expect(
          polyPositionSquareLine(
              (title: 'Bitcoin', context: 'bitcoin', titleIsSide: false),
              'Down'),
          'Down');
      // Nothing else to say: the side, never an empty line.
      expect(
          polyPositionSquareLine(
              (title: 'Verstappen', context: '', titleIsSide: true),
              'Verstappen'),
          'Verstappen');
    });

    Widget row(String title, String line) => PortfolioPositionRow(
          key: ValueKey(title),
          leading: const SizedBox(),
          title: title,
          subtitle: 'Event only',
          squareLine: line,
          hiddenSquareLine: 'Side only',
          value: r'$12.34',
          pnl: const (text: '+5.4%', tone: PortfolioPnlTone.up),
          pnlAmount: r'$0.61',
          onTap: () {},
        );

    const long = 'Will the Federal Reserve cut interest rates by more than '
        'fifty basis points at the December 2026 meeting';

    for (final scale in [1.0, 1.5]) {
      testWidgets(
          'at ${(scale * 100).round()} % text: a long name is never cut, its '
          'square grows, its neighbour with it, and nothing overflows',
          (tester) async {
        await _pump(
            tester,
            width: 375,
            height: 900,
            textScale: scale,
            PortfolioPositionSquares(
                holdings: true, rows: [row(long, 'Yes · Event'), row('B', 'No')]));
        expect(tester.takeException(), isNull);
        final title = tester.widget<Text>(
            find.byKey(const ValueKey('portfolio-row-title')).first);
        expect(title.data, long);
        expect(title.maxLines, isNull);
        expect(title.overflow, isNull);
        final squares = find.byKey(const ValueKey('portfolio-square'));
        final left = tester.getRect(squares.at(0));
        final right = tester.getRect(squares.at(1));
        expect(left.height, right.height);
        expect(
            left.height,
            greaterThan(portfolioSquareHeight(
                tester.element(find.byKey(ValueKey(long))))));
      });
    }

    testWidgets(
        'one line each: exactly the Activity tab\'s square, at the same '
        'height', (tester) async {
      await _pump(
          tester,
          width: 375,
          PortfolioPositionSquares(rows: [row('A', 'Yes'), row('B', 'No')]));
      final activity = tester.getRect(
          find.byKey(const ValueKey('portfolio-square')).first);
      await _pump(
          tester,
          width: 375,
          PortfolioPositionSquares(
              holdings: true, rows: [row('A', 'Yes'), row('B', 'No')]));
      final portfolio = tester.getRect(
          find.byKey(const ValueKey('portfolio-square')).first);
      expect(portfolio.size.width, activity.size.width);
      expect(portfolio.size.height,
          moreOrLessEquals(activity.size.height, epsilon: 2.5));
    });

    testWidgets(
        'the Activity tab\'s squares keep their subtitle, one line and the '
        'one height, and read no setting', (tester) async {
      await _pump(tester, PortfolioPositionSquares(rows: [row(long, 'Yes'), row('B', 'No')]));
      final title = tester.widget<Text>(
          find.byKey(const ValueKey('portfolio-row-title')).first);
      expect(title.maxLines, 1);
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('portfolio-row-subtitle')).first)
              .data,
          'Event only');
    });

    testWidgets(
        'an odd count: the squares two by two, the last the full-width '
        'compact card, its long name whole', (tester) async {
      await _pump(
          tester,
          width: 375,
          height: 900,
          PortfolioPositionSquares(holdings: true, rows: [
            row('A', 'Yes'),
            row('B', 'No'),
            row(long, 'Yes · Event'),
          ]));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('portfolio-square')), findsNWidgets(2));
      final wide = find.byKey(const ValueKey('portfolio-wide'));
      expect(wide, findsOneWidget);
      final title = tester.widget<Text>(find.descendant(
          of: wide, matching: find.byKey(const ValueKey('portfolio-row-title'))));
      expect(title.maxLines, isNull);
      expect(title.data, long);
    });

    for (final (name, rows) in [
      ('a square', 2),
      ('the wide card', 1),
    ]) {
      testWidgets(
          '$name with balances hidden: the value and the P&L masked with no '
          'colour, the line without a sum or a size, the tap still open',
          (tester) async {
        var tapped = 0;
        Widget hidden(String title) => PortfolioPositionRow(
              key: ValueKey(title),
              leading: const SizedBox(),
              title: title,
              subtitle: 'Long · 0.5 BTC',
              hiddenSquareLine: 'Long',
              value: r'$12.34',
              pnl: const (text: '−5.4%', tone: PortfolioPnlTone.down),
              pnlAmount: r'$0.61',
              onTap: () => tapped++,
            );
        await _pump(
            tester,
            width: 375,
            balancePrivacy: 1,
            PortfolioPositionSquares(holdings: true, rows: [
              for (var i = 0; i < rows; i++) hidden('P$i'),
            ]));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('12.34'), findsNothing);
        expect(find.textContaining('0.5 BTC'), findsNothing);
        expect(find.text('Long'), findsNWidgets(rows));
        final value =
            tester.widget<RollingFigure>(find.byKey(const ValueKey('portfolio-row-value')).first);
        final usd =
            tester.widget<RollingFigure>(find.byKey(const ValueKey('portfolio-row-pnl-usd')).first);
        final percent =
            tester.widget<RollingFigure>(find.byKey(const ValueKey('portfolio-row-pnl')).first);
        expect(value.text, '••••••');
        expect(usd.text, '••••••');
        expect(percent.text, '••%');
        expect(percent.style.color, AppColorsExtension.light().textSecondary);
        await tester.tap(find.text('P0'));
        expect(tapped, 1);
      });
    }
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
