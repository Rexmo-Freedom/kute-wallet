// THE DOLLARS BALANCE CARRIES THE OPEN P&L (founder, 13 November 2026: "on
// the main balance we should have a % of up and down of open positions
// also, to know how much we earned, right?").
//
// Under "Invested $X · Available $Y" the hero writes "Open profits ▲ $1.23
// (+4.8%)": the Overview's "Open profits" card's own figure
// (dollarsOpenPnl: the open Predictions and Investing positions at the live
// prices, a prediction whose cost is not known yet counting for none), the
// percent of what those positions cost, green up and red down; dots with
// balances hidden; no line with nothing open that has a known cost. Nothing
// on it is cut on a 320-wide phone at 1.5x text, light or dark.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart'
    show formatDollars;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlPerpPosition;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show openPnlPercent;
import 'package:kute/screens/shared/charts/kute_chart_format.dart'
    show kuteChangeSign;
import 'package:kute/screens/shared/investment_balance_header.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/shared/pool_balance_header.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/portfolio_overrides.dart' show PortfolioTestTrading;
import 'investments_harness.dart';

class _NoLive extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState(live: false, prices: {});
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void pause() {}
  @override
  void resume() {}
}

/// An open prediction: [size] shares bought at [avg] (0: its cost not
/// known yet), now at [now].
PolymarketPosition _prediction(
        {String token = 'tok-a',
        double size = 30,
        double avg = 0.4,
        double now = 0.5}) =>
    PolymarketPosition(
        marketId: 'c-$token',
        marketQuestion: 'Will it happen ($token)?',
        outcome: 'Yes',
        size: size,
        avgPrice: avg,
        currentPrice: now,
        pnl: 0,
        pnlPercent: 0,
        isResolved: false,
        tokenId: token);

/// A cross perp up $2.00 on $50.00 of margin.
const _perp = HlPerpPosition(
    coin: 'BTC',
    szi: 1,
    entryPx: 100,
    positionValue: 102,
    unrealizedPnl: 2,
    returnOnEquity: 0,
    liquidationPx: null,
    marginUsed: 50,
    leverageType: 'cross',
    leverageValue: 2,
    maxLeverage: 40);

List<Override> _held(List<PolymarketPosition> predictions,
        {List<HlPerpPosition> perps = const []}) =>
    [
      livePriceProvider.overrideWith(_NoLive.new),
      polymarketActivePositionsProvider.overrideWith((_) => predictions),
      if (perps.isNotEmpty)
        hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
            HyperliquidTradingState(isInitialized: true, positions: perps))),
    ];

final _line = find.byKey(const ValueKey('investments-balance-open-pnl'));
final _figure =
    find.byKey(const ValueKey('investments-balance-open-pnl-figure'));
final _card = find.byKey(const ValueKey('dollars-pnl-figure'));

Future<void> _pump(WidgetTester tester, List<Override> overrides,
    {bool dark = false,
    Size size = const Size(390, 1400),
    double textScale = 1,
    int balancePrivacy = 0}) async {
  await pumpInvestments(tester,
      size: size,
      dark: dark,
      textScale: textScale,
      balancePrivacy: balancePrivacy,
      overrides: overrides);
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

RollingNumberText _text(WidgetTester tester, Finder f) =>
    tester.widget<RollingNumberText>(f);

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(PoolBalanceHeader)));

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });

  group('the figure (pure)', () {
    test(
        'the arrow, the amount and the signed percent; under a cent, '
        r'"$0.00" alone', () {
      expect(OneBalanceOpenPnlLine.figure(1.23, 4.8), r'▲ $1.23 (+4.8%)');
      expect(OneBalanceOpenPnlLine.figure(-0.15, -1), r'▼ $0.15 (−1.0%)');
      expect(OneBalanceOpenPnlLine.figure(2, null), r'▲ $2.00');
      expect(OneBalanceOpenPnlLine.figure(0.004, 0.1), r'$0.00');
      expect(OneBalanceOpenPnlLine.figure(1234.5, 123.45),
          r'▲ $1,234.50 (+123.5%)');
    });

    test(
        'the percent is of what the open positions cost, only when each '
        'has a cost of its own', () {
      expect(openPnlPercent((usd: 5, costUsd: 62, count: 2, costed: true)),
          closeTo(8.0645, 1e-3));
      expect(openPnlPercent((usd: 5, costUsd: 62, count: 2, costed: false)),
          isNull);
      expect(
          openPnlPercent((usd: 5, costUsd: 0, count: 1, costed: true)), isNull);
    });
  });

  for (final dark in [false, true]) {
    testWidgets(
        'down${dark ? ', dark' : ''}: one prediction of 30 shares bought '
        'at 50¢, now 49.5¢: "Open profits ▼ \$0.15 (−1.0%)" in red, under '
        'the split, the Overview card\'s own figure', (tester) async {
      await _pump(tester, _held([_prediction(avg: 0.5, now: 0.495)]),
          dark: dark);
      expect(tester.takeException(), isNull);
      final l10n = _l10n(tester);
      expect(_line, findsOneWidget);
      expect(
          find.descendant(
              of: _line, matching: find.text('${l10n.portfolioStatOpenPnl} ')),
          findsOneWidget);
      expect(_text(tester, _figure).text, r'▼ $0.15 (−1.0%)');
      expect(_text(tester, _figure).style.color, AppColors.marketDown);
      // The card's figure is the same amount, written its own way.
      expect(_text(tester, _card).text, r'−$0.15');
      // Under the split, inside the hero.
      final split = tester
          .getRect(find.byKey(const ValueKey('investments-balance-split')));
      final line = tester.getRect(_line);
      expect(line.top, greaterThanOrEqualTo(split.bottom));
      expect(
          line.bottom,
          lessThanOrEqualTo(
              tester.getRect(find.byType(PoolBalanceHeader)).bottom));
      await unmountInvestments(tester);
    });
  }

  testWidgets(
      'up, both venues: a prediction up \$3.00 on \$12.00 and a perp up '
      '\$2.00 on \$50.00: "▲ \$5.00 (+8.1%)" in green, equal to the '
      "Overview's Open profits card", (tester) async {
    await _pump(tester, _held([_prediction()], perps: [_perp]));
    expect(tester.takeException(), isNull);
    expect(_text(tester, _figure).text, r'▲ $5.00 (+8.1%)');
    expect(_text(tester, _figure).style.color, AppColors.marketUp);
    // One source of truth: the card writes the same amount.
    final card = _text(tester, _card).text;
    expect(card, '${kuteChangeSign(5)}${formatDollars(5)}');
    expect(_text(tester, _figure).text, startsWith('▲ ${card.substring(1)}'));
    await unmountInvestments(tester);
  });

  testWidgets(
      'a prediction whose cost is not known yet counts for none: alone, no '
      'line (and no card); beside a costed one, only the costed one',
      (tester) async {
    await _pump(tester, _held([_prediction(avg: 0)]));
    expect(tester.takeException(), isNull);
    expect(_line, findsNothing);
    expect(_card, findsNothing);
    await unmountInvestments(tester);

    await _pump(
        tester, _held([_prediction(avg: 0, token: 'tok-new'), _prediction()]));
    expect(_text(tester, _figure).text, r'▲ $3.00 (+25.0%)');
    expect(_text(tester, _card).text, r'+$3.00');
    await unmountInvestments(tester);
  });

  testWidgets('nothing open: no line', (tester) async {
    await _pump(tester, _held(const []));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('investments-balance-split')),
        findsOneWidget);
    expect(_line, findsNothing);
    await unmountInvestments(tester);
  });

  for (final privacy in [1, 2]) {
    testWidgets(
        'balances hidden (level $privacy): the figure is dots, no arrow, no '
        'percent, no colour', (tester) async {
      await _pump(tester, _held([_prediction()], perps: [_perp]),
          balancePrivacy: privacy);
      expect(tester.takeException(), isNull);
      expect(_line, findsOneWidget);
      final figure = _text(tester, _figure);
      expect(figure.text, '••••••');
      expect(figure.style.color, isNot(AppColors.marketUp));
      expect(figure.style.color, isNot(AppColors.marketDown));
      expect(find.textContaining('5.00'), findsNothing);
      expect(find.textContaining('8.1%'), findsNothing);
      await unmountInvestments(tester);
    });
  }

  for (final dark in [false, true]) {
    testWidgets(
        'nothing cut on a 320-wide phone at 1.5x text${dark ? ', dark' : ''}'
        ': the line fits the screen, a large figure included', (tester) async {
      await _pump(tester,
          _held([_prediction(size: 4000, avg: 0.1, now: 0.4)], perps: [_perp]),
          dark: dark, size: const Size(320, 900), textScale: 1.5);
      expect(tester.takeException(), isNull);
      expect(_text(tester, _figure).text, r'▲ $1,202.00 (+267.1%)');
      final line = tester.getRect(_line);
      expect(line.left, greaterThanOrEqualTo(0));
      expect(line.right, lessThanOrEqualTo(320));
      // The figure is drawn whole inside the line (scaled, never clipped).
      final figure = tester.getRect(_figure);
      expect(figure.left, greaterThanOrEqualTo(line.left - 0.5));
      expect(figure.right, lessThanOrEqualTo(line.right + 0.5));
      await unmountInvestments(tester);
    });
  }
}
