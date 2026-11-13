// The redesigned Portfolio screen's pure rules (7 November 2026): the
// hero's percent only on a real base, the Positions rows' "+$1.20
// (+8.0%)", the Activity filters, and the ranges the screen offers.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlFill;
import 'package:kute/models/open_pnl_history.dart'
    show openPnlRangeShown, openPnlRanges;
import 'package:kute/models/polymarket_model.dart' show Activity;
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/open_pnl_history_provider.dart'
    show kPnlHistoryRanges;
import 'package:kute/screens/portfolio/components/portfolio_pnl_period.dart';
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show PortfolioPnlTone, portfolioPnlPill, portfolioSignedPnl;
import 'package:kute/screens/portfolio/portfolio_activity.dart';
import 'package:kute/screens/shared/all_activity.dart' show AllActivityEntry;

PolymarketTransaction _poly(String type, {String side = ''}) =>
    PolymarketTransaction(
      id: type,
      timestamp: DateTime.utc(2026, 11, 1),
      activity: Activity(
        proxyWallet: '0xself',
        timestamp: 0,
        conditionId: '0x',
        type: type,
        size: 1,
        usdcSize: 1,
        transactionHash: '0x',
        side: side,
        asset: 'a',
        outcomeIndex: 0,
        title: 'Will it?',
        outcome: 'Yes',
        eventSlug: '',
      ),
    );

AllActivityEntry _tx(BaseTransaction tx) =>
    (time: tx.timestamp, tx: tx, fill: null);

void main() {
  group('the hero\'s percent: only on a real base', () {
    test('the change over what was held at the start (held now less it)',
        () {
      // $25.68 held, +$7.55 over the range: $18.13 at its start, +41.6%.
      expect(portfolioPnlPercent(7.55, 25.68), closeTo(41.64, 0.01));
      // A loss: $20 held, −$5: $25 at the start, −20%.
      expect(portfolioPnlPercent(-5, 20), closeTo(-20, 1e-9));
    });

    test('a base under a dollar, a negative base or 1000 % and more: none',
        () {
      expect(portfolioPnlPercent(7.55, 8.2), isNull, reason: 'base \$0.65');
      expect(portfolioPnlPercent(20, 10), isNull, reason: 'base negative');
      expect(portfolioPnlPercent(15, 16.4), isNull, reason: '1071 %');
      expect(portfolioPnlPercent(9.99, 10.99), closeTo(999, 0.01));
      expect(portfolioPnlPercent(1, null), isNull);
      expect(portfolioPnlPercent(double.nan, 10), isNull);
      expect(kPortfolioPnlPercentBaseUsd, 1);
      expect(kPortfolioPnlPercentCap, 1000);
    });
  });

  test('a Positions row\'s P&L: "+\$1.20 (+8.0%)", "−\$0.40 (−3.1%)", flat '
      'quietly', () {
    final up = portfolioPnlPill(1.2, percent: 8)!;
    expect(up.tone, PortfolioPnlTone.up);
    expect(portfolioSignedPnl(up, r'$1.20'), r'+$1.20 (+8.0%)');
    final down = portfolioPnlPill(-0.4, percent: -3.1)!;
    expect(portfolioSignedPnl(down, r'$0.40'), r'−$0.40 (−3.1%)');
    final flat = portfolioPnlPill(0.001, percent: 0.01)!;
    expect(portfolioSignedPnl(flat, r'$0.00'), r'$0.00 (0.0%)');
    expect(portfolioSignedPnl(up, null), '+8.0%');
  });

  group('the Activity filters', () {
    final fill = (
      time: DateTime.utc(2026, 11, 1),
      tx: null,
      fill: const HlFill(
          coin: 'BTC',
          px: 1,
          sz: 1,
          side: 'B',
          time: 0,
          closedPnl: 0,
          fee: 0,
          feeToken: 'USDC',
          oid: 1,
          hash: '0x',
          dir: 'Open Long',
          cloid: null),
    );
    final buy = _tx(_poly('TRADE', side: 'BUY'));
    final sell = _tx(_poly('TRADE', side: 'SELL'));
    final redeem = _tx(_poly('REDEEM'));
    final deposit = _tx(_poly('DEPOSIT'));
    final withdraw = _tx(_poly('WITHDRAW'));
    final all = [fill, buy, sell, redeem, deposit, withdraw];
    List<AllActivityEntry> only(PortfolioActivityFilter f) =>
        [for (final e in all) if (portfolioActivityMatches(e, f)) e];

    test('All lists everything; each entry is in exactly one other chip', () {
      expect(only(PortfolioActivityFilter.all), all);
      expect(only(PortfolioActivityFilter.trades), [fill, buy, sell]);
      expect(only(PortfolioActivityFilter.payouts), [redeem]);
      expect(only(PortfolioActivityFilter.transfers), [deposit, withdraw]);
      for (final e in all) {
        expect(
            [
              PortfolioActivityFilter.trades,
              PortfolioActivityFilter.payouts,
              PortfolioActivityFilter.transfers,
            ].where((f) => portfolioActivityMatches(e, f)),
            hasLength(1));
      }
    });
  });

  group('the ranges: 1W 1M 3M ALL, the 1M default falling back to ALL', () {
    final now = DateTime(2026, 11, 7);
    List<BalanceRange> offered(Duration age) => [
          for (final r in openPnlRanges(now.subtract(age), now))
            if (kPnlHistoryRanges.contains(r)) r
        ];

    test('never 1Y; only the ranges shorter than the history, then ALL', () {
      expect(kPortfolioPnlRanges, [
        BalanceRange.week,
        BalanceRange.month,
        BalanceRange.threeMonths,
        BalanceRange.all,
      ]);
      expect(offered(const Duration(days: 3)), [BalanceRange.all]);
      expect(offered(const Duration(days: 10)),
          [BalanceRange.week, BalanceRange.all]);
      expect(offered(const Duration(days: 50)),
          [BalanceRange.week, BalanceRange.month, BalanceRange.all]);
      expect(offered(const Duration(days: 800)), kPortfolioPnlRanges);
    });

    test('1M when offered, else ALL', () {
      expect(
          openPnlRangeShown(
              BalanceRange.month, offered(const Duration(days: 50))),
          BalanceRange.month);
      expect(
          openPnlRangeShown(
              BalanceRange.month, offered(const Duration(days: 20))),
          BalanceRange.all);
      // A 1Y picked elsewhere is never drawn here: ALL.
      expect(
          openPnlRangeShown(
              BalanceRange.year, offered(const Duration(days: 800))),
          BalanceRange.all);
    });
  });
}
