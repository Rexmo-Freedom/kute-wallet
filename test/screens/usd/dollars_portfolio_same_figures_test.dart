// One Invested and one Available across the app (founder, 4 November
// 2026: "Balance wrong in dollars … show invested and available in a good
// way"): for the same one-balance state, the Dollars header's "Invested $X
// · Available $Y" and the Portfolio hero's "Invested $X · Available $Y"
// print the same amounts, to the cent, whatever is on a rail; the two add
// up to the Dollars total less what its in-flight lines name, and that is
// the Portfolio hero's total (the redesign of 7 November 2026: the open
// positions' worth plus Available).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/screens/portfolio/components/balances_overview.dart'
    show BalancesLiveFigure;
import 'package:kute/screens/portfolio/components/portfolio_hero.dart';
import 'package:kute/screens/shared/pool_balance_header.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';

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
      'the Dollars header and the Portfolio hero print the same Invested and '
      'Available for the same state', (tester) async {
    // $39.29 in all: $12.35 invested, $2.50 arriving (its line), $24.44
    // Available (Dollars $20.00, Investing's cash $3.33, the sweep home
    // $1.11).
    await pumpInvestments(tester, balance: _state);
    expect(
        tester
            .widget<PoolBalanceHeader>(find.byType(PoolBalanceHeader))
            .amountText,
        r'$39.29');
    final dollarsInvested = _rolling(tester, 'investments-balance-invested');
    final dollarsAvailable = _rolling(tester, 'investments-balance-available');
    expect(dollarsInvested, r'$12.35');
    expect(dollarsAvailable, r'$24.44');
    expect(find.text(r'Incoming $2.50'), findsOneWidget);
    await unmountInvestments(tester);

    await pumpInvestments(tester,
        balance: _state,
        child: const Scaffold(
            body: SingleChildScrollView(child: PortfolioHero())));
    expect(_live(tester, 'portfolio-hero-invested'), dollarsInvested);
    expect(_live(tester, 'portfolio-hero-available'), dollarsAvailable);
    // The total: Invested and Available added, as written ($12.35 +
    // $24.44); the Dollars total less the $2.50 on its line.
    expect(_live(tester, 'portfolio-hero-value'), r'$36.79');
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });
}
