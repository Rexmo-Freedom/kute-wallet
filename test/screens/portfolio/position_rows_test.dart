// The Portfolio's open positions as plain list rows: the real picture
// (a market's image, a coin's logo), one-line title, one line of facts
// (never a leverage figure), the value with its P&L, a P&L that rounds to
// no cent in the quiet colour, and the taps of the old cards.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
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
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/portfolio_overrides.dart';

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();

  @override
  void acquire() {}

  @override
  void release() {}

  @override
  void registerCardTokens(List<String> tokens) {}

  @override
  void unregisterCardTokens(List<String> tokens) {}
}

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
    tokenId: 'kane-yes');

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

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the P&L line', () {
    String money(double v) => '\$${v.toStringAsFixed(2)}';

    test('a gain, a loss, signed with the app\'s signs', () {
      final up = portfolioPnlLine(money, 0.42, percent: 4.0);
      expect(up.text, r'+$0.42 (+4.0%)');
      expect(up.tone, PortfolioPnlTone.up);
      final down = portfolioPnlLine(money, -0.42, percent: -4.0);
      expect(down.text, r'−$0.42 (−4.0%)');
      expect(down.tone, PortfolioPnlTone.down);
    });

    test('rounding to no cent: "\$0.00 (0.0%)", flat, never a red minus', () {
      for (final pnl in [-0.004, 0.0, 0.0049, -0.0]) {
        final line = portfolioPnlLine(money, pnl, percent: -0.1);
        expect(line.text, r'$0.00 (0.0%)');
        expect(line.tone, PortfolioPnlTone.flat);
      }
      expect(portfolioPnlLine(money, -0.001).text, r'$0.00');
    });
  });

  testWidgets(
      'a Polymarket row: its image, the whole question, '
      '"Yes · 4.99 shares · avg 72¢", the value and the loss', (tester) async {
    await _pump(tester, const PolyPositionRow(position: _kane));
    expect(find.byType(PolyCardThumbnail), findsOneWidget);
    final title =
        tester.widget<Text>(find.byKey(const ValueKey('portfolio-row-title')));
    expect(title.data, "Will Harry Kane win the 2026 Ballon d'Or?");
    // The whole question shows, wrapping, never cut with an ellipsis.
    expect(title.maxLines, isNull);
    expect(title.overflow, isNull);
    expect(
        _text(tester, 'portfolio-row-subtitle'), 'Yes · 4.99 shares · avg 72¢');
    expect(_figure(tester, 'portfolio-row-value').text, r'$3.58');
    final pnl = _figure(tester, 'portfolio-row-pnl');
    expect(pnl.text, r'−$0.01 (−0.3%)');
    expect(pnl.style.color, AppColors.marketDown);
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
    expect(pnl.text, r'$0.00 (0.0%)');
    expect(pnl.style.color, AppColorsExtension.light().textSecondary);
    expect(find.textContaining('−'), findsNothing);
  });

  testWidgets('a settled position says so in place of the facts',
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
    expect(_text(tester, 'portfolio-row-subtitle'), 'Up · Settled');
  });

  testWidgets(
      'a Hyperliquid long: the coin logo, "Long · 0.00012 BTC · entry '
      '\$90,120", never a leverage figure', (tester) async {
    await _pump(tester, const HlPositionRow(position: _btc));
    expect(find.byType(HlCoinIcon), findsOneWidget);
    expect(_text(tester, 'portfolio-row-title'), 'Bitcoin');
    expect(_text(tester, 'portfolio-row-subtitle'),
        r'Long · 0.00012 BTC · entry $90,120');
    expect(find.textContaining('3x'), findsNothing);
    expect(find.textContaining('Liq'), findsNothing);
    final pnl = _figure(tester, 'portfolio-row-pnl');
    expect(pnl.text, startsWith(r'+$0.40'));
    expect(pnl.style.color, AppColors.marketUp);
  });

  testWidgets('a HIP-3 short: the ticker without its dex, the name, the logo',
      (tester) async {
    await _pump(tester, const HlPositionRow(position: _nvda));
    await tester.pump();
    final icon = tester.widget<HlCoinIcon>(find.byType(HlCoinIcon));
    expect(icon.wireCoin, 'xyz:NVDA');
    expect(_text(tester, 'portfolio-row-title'), 'Nvidia');
    expect(_text(tester, 'portfolio-row-subtitle'),
        r'Short · 3 NVDA · entry $182.40');
    expect(
        _figure(tester, 'portfolio-row-pnl').style.color, AppColors.marketDown);
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
