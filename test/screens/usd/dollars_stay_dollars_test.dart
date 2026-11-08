// "Portfolio also do not translate to euros or whatever, keep it in dollars"
// (founder, 8 November 2026). With euros in Settings and a rate far from 1:
// the Dollars header, the Portfolio's hero and positions, the Dollars
// Activity (the squares, the Open P&L, Latest) read the USD figures, each
// equal to the USD input, with no euro on screen. Bitcoin's own conversion
// still follows Settings.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/open_pnl_history_provider.dart'
    show OpenPnlSources;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/portfolio/components/balances_overview.dart'
    show BalancesLiveFigure;
import 'package:kute/screens/portfolio/components/portfolio_hero.dart';
import 'package:kute/screens/portfolio/components/position_rows.dart';
import 'package:kute/screens/portfolio/investments_portfolio.dart';
import 'package:kute/screens/share/brag/brag_data.dart'
    show bragMoney, bragSignedMoney;
import 'package:kute/screens/shared/pool_balance_header.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:money2/money2.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Activity;

import '../../helpers/euro_settings.dart';
import '../../helpers/portfolio_overrides.dart' show PortfolioTestTrading;
import 'investments_harness.dart';

const _state = OneBalanceState(
  dollarsUsd: 20.004,
  investedUsd: 12.346,
  investedByVenue: {
    OneBalanceVenue.investing: 8.123,
    OneBalanceVenue.predictions: 4.223,
  },
  investingKnown: true,
  predictionsKnown: true,
  venueCash: {OneBalanceVenue.investing: 3.333},
);

HlPerpPosition _perp(String coin, double pnl) => HlPerpPosition(
    coin: coin,
    szi: 1,
    entryPx: 100,
    positionValue: 100 + pnl,
    unrealizedPnl: pnl,
    returnOnEquity: 0,
    liquidationPx: null,
    marginUsed: 1,
    leverageType: 'cross',
    leverageValue: 2,
    maxLeverage: 40);

HlFill _opened(String coin, DateTime now) => HlFill(
      coin: coin,
      px: 100,
      sz: 1,
      side: 'B',
      time: now.subtract(const Duration(days: 10)).millisecondsSinceEpoch,
      closedPnl: 0,
      fee: 0,
      feeToken: 'USDC',
      oid: coin.hashCode,
      hash: '0xopen-$coin',
      dir: 'Open Long',
      cloid: null,
      startPosition: 0,
    );

PolymarketTransaction _bet() {
  final at = DateTime.utc(2026, 11, 4, 12);
  return PolymarketTransaction(
    id: 'bet1',
    timestamp: at,
    activity: Activity(
      proxyWallet: '0xself',
      timestamp: at.millisecondsSinceEpoch ~/ 1000,
      conditionId: '0xrain',
      type: 'TRADE',
      size: 10,
      usdcSize: 5.25,
      transactionHash: '0xbet1',
      side: 'BUY',
      asset: 'yes',
      outcomeIndex: 0,
      title: 'Will it rain tomorrow?',
      outcome: 'Yes',
      eventSlug: '',
    ),
  );
}

String _rolling(WidgetTester tester, String key) => tester
    .widget<RollingNumberText>(find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(RollingNumberText)))
    .text;

String _live(WidgetTester tester, String key) =>
    tester.widget<BalancesLiveFigure>(find.byKey(ValueKey(key))).figure.text;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('the formatter takes no rate: dollars are dollars', () {
    expect(formatDollars(1.04), r'$1.04');
    expect(formatDollars(1234.5), r'$1,234.50');
    expect(formatDollars(1500, decimalDigits: 0), r'$1,500');
    expect(bragMoney(36.9), r'$36.90');
    expect(bragSignedMoney(36.9), r'+$36.90');
    expect(bragSignedMoney(-12), r'−$12.00');
  });

  testWidgets('the Dollars header: the USD figures, no euro', (tester) async {
    await pumpInvestments(tester,
        balance: _state, currency: 'EUR', overrides: [euroRateOverride()]);
    expect(
        tester
            .widget<PoolBalanceHeader>(find.byType(PoolBalanceHeader))
            .amountText,
        r'$35.68');
    expect(_rolling(tester, 'investments-balance-invested'), r'$12.35');
    expect(_rolling(tester, 'investments-balance-available'), r'$23.33');
    expectNoEuroOnScreen(tester);
    await unmountInvestments(tester);
  });

  testWidgets('the Portfolio hero: total, Invested, Available in dollars',
      (tester) async {
    await pumpInvestments(tester,
        balance: _state,
        currency: 'EUR',
        overrides: [euroRateOverride()],
        child: const Scaffold(
            body: SingleChildScrollView(child: PortfolioHero())));
    expect(_live(tester, 'portfolio-hero-value'), r'$35.68');
    expect(_live(tester, 'portfolio-hero-invested'), r'$12.35');
    expect(_live(tester, 'portfolio-hero-available'), r'$23.33');
    expectNoEuroOnScreen(tester);
    await unmountInvestments(tester);
  });

  testWidgets('the Portfolio\'s positions: every row in dollars',
      (tester) async {
    await pumpInvestments(tester,
        balance: _state,
        currency: 'EUR',
        size: const Size(390, 1400),
        overrides: [
          euroRateOverride(),
          hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
              HyperliquidTradingState(
                  isInitialized: true, positions: [_perp('BTC', -0.02)]))),
          portfolioSectionProvider.overrideWith((_) => PortfolioSection.balances),
        ],
        child: Scaffold(body: InvestmentsPortfolio(onSection: (_) {})));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(HlPositionRow), findsWidgets);
    expectNoEuroOnScreen(tester);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'the founder\'s screenshot, the Dollars Activity: the position squares, '
      'the Open P&L and Latest read the real dollars', (tester) async {
    final now = DateTime.now();
    await pumpInvestments(tester,
        size: const Size(390, 1400),
        currency: 'EUR',
        history: Transaction(
          bitcoinTransactions: const [],
          sparkTransactions: const [],
          sparkUnclaimedDeposits: const [],
          polymarketTransactions: [_bet()],
        ),
        openPnlSources: OpenPnlSources(
          activity: (_) async => const [],
          candles: (_, wire, interval, window) async => const [],
          polyHistory: (_, __, ___) async => null,
        ),
        overrides: [
          euroRateOverride(),
          hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
              HyperliquidTradingState(isInitialized: true, positions: [
                _perp('BTC', -0.02)
              ], recentFills: [
                _opened('BTC', now)
              ]))),
        ]);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final squares = find.byKey(const ValueKey('dollars-activity-squares'));
    expect(squares, findsOneWidget);
    final figures = [
      for (final w in tester.widgetList<RollingNumberText>(find.descendant(
          of: squares, matching: find.byType(RollingNumberText))))
        w.text,
    ];
    // Worth $0.98 (the $1 margin, down 2 cents), down 2 cents, 2%: the USD
    // inputs, no rate on either, the percent untouched.
    expect(figures, [r'$0.98', r'▼ $0.02', '2.0%']);
    expect(
        tester
            .widget<RollingNumberText>(
                find.byKey(const ValueKey('dollars-pnl-figure')))
            .text,
        r'−$0.02');
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('dollars-activity-rows')),
            matching: find.text(r'$5.25')),
        findsOneWidget);
    expectNoEuroOnScreen(tester);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  test('Bitcoin\'s conversion line still follows the Settings currency', () {
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
          currency: 'EUR',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: '',
          reviewDone: true))),
      currencyProvider.overrideWith((_) => _Rates()),
    ]);
    addTearDown(container.dispose);
    final fiat = container.read(conversionToFiatProvider(100000));
    expect(fiat, contains('€'));
    expect(fiat, isNot(contains(r'$')));
  });
}

class _Rates extends StateNotifier<CurrencyState> implements CurrencyNotifier {
  _Rates()
      : super(CurrencyState({
          'BTC': Fixed.parse('0.00001'),
          'EUR': Fixed.parse('0.92'),
        }));
  @override
  Future<void> updateRates() async {}
}
