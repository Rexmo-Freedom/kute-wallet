// One Available and one open P&L across the app (founder, 4 November
// 2026: "Balance wrong in dollars … show invested and available in a good
// way"; 24 November 2026: "only show available, and instead of invested
// have the amount we are up or down"): for the same one-balance state, the
// Dollars header's "▲ $X (+P%) · Available $Y" prints the Portfolio hero's
// Available to the cent, whatever is on a rail, and the Overview's "Open
// profits" card's amount; the hero's Invested and Available add up to the
// Dollars total less what its in-flight lines name, and that is the
// Portfolio hero's total (the redesign of 7 November 2026: the open
// positions' worth plus Available).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlPerpPosition;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/screens/portfolio/components/balances_overview.dart'
    show BalancesLiveFigure;
import 'package:kute/screens/portfolio/components/portfolio_hero.dart';
import 'package:kute/screens/shared/pool_balance_header.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/screens/usd/usd_account_screen.dart'
    show InvestmentsTab, UsdAccountScreen;

import '../../helpers/portfolio_overrides.dart' show PortfolioTestTrading;
import 'investments_harness.dart';

/// Odd cents everywhere, a sweep on its way home (no line: Available) and
/// dollars arriving (a line: left out of Available).
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
  inFlight: [
    InFlightMove(
        kind: InFlightKind.fromVenue,
        venue: OneBalanceVenue.investing,
        usd: 1.111),
    InFlightMove(kind: InFlightKind.incomingDollars, usd: 2.5),
  ],
);

/// A cross perp up $1.234 on $10.00 of margin: the open positions' P&L.
const _perp = HlPerpPosition(
    coin: 'BTC',
    szi: 1,
    entryPx: 100,
    positionValue: 101.234,
    unrealizedPnl: 1.234,
    returnOnEquity: 0,
    liquidationPx: null,
    marginUsed: 10,
    leverageType: 'cross',
    leverageValue: 2,
    maxLeverage: 40);

String _rolling(WidgetTester tester, String key) => tester
    .widget<RollingNumberText>(find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(RollingNumberText)))
    .text;

String _live(WidgetTester tester, String key) =>
    tester.widget<BalancesLiveFigure>(find.byKey(ValueKey(key))).figure.text;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'the Dollars header prints the Portfolio hero\'s Available and the '
      'Overview\'s Open profits for the same state', (tester) async {
    // $39.29 in all: $12.35 invested, $2.50 arriving (its line), $24.44
    // Available (Dollars $20.00, Investing's cash $3.33, the sweep home
    // $1.11); the open perp up $1.23 on its $10.00.
    await pumpInvestments(tester,
        // Overview by its link: the page opens on Investing (founder, 25
        // November 2026).
        child: const UsdAccountScreen(initialTab: InvestmentsTab.activity),
        balance: _state,
        size: const Size(390, 1400),
        overrides: [
          hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
              const HyperliquidTradingState(
                  isInitialized: true, positions: [_perp]))),
        ]);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
        tester
            .widget<PoolBalanceHeader>(find.byType(PoolBalanceHeader))
            .amountText,
        r'$39.29');
    // Invested is not on the Dollars page: the up or down is, in its
    // place.
    expect(find.byKey(const ValueKey('investments-balance-invested')),
        findsNothing);
    final dollarsPnl = tester
        .widget<RollingNumberText>(
            find.byKey(const ValueKey('investments-balance-open-pnl-figure')))
        .text;
    final overviewPnl = tester
        .widget<RollingNumberText>(
            find.byKey(const ValueKey('dollars-pnl-figure')))
        .text;
    expect(dollarsPnl, r'▲ $1.23 (+12.3%)');
    expect(overviewPnl, r'+$1.23');
    // The same amount, each written its own way: the arrow for the sign.
    expect(dollarsPnl, startsWith('▲ ${overviewPnl.substring(1)} '));
    final dollarsAvailable = _rolling(tester, 'investments-balance-available');
    expect(dollarsAvailable, r'$24.44');
    expect(find.text(r'Incoming $2.50'), findsOneWidget);
    await unmountInvestments(tester);

    await pumpInvestments(tester,
        balance: _state,
        child: const Scaffold(
            body: SingleChildScrollView(child: PortfolioHero())));
    expect(_live(tester, 'portfolio-hero-available'), dollarsAvailable);
    expect(_live(tester, 'portfolio-hero-invested'), r'$12.35');
    // The total: Invested and Available added, as written ($12.35 +
    // $24.44); the Dollars total less the $2.50 on its line.
    expect(_live(tester, 'portfolio-hero-value'), r'$36.79');
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });
}
