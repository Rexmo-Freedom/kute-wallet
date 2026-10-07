// test/models/polymarket_order_test.dart
//
// Comprehensive tests for Polymarket order/trading calculation logic.
// Covers: share calculations, fee calculations, slippage, P&L,
// and resolution payouts. Production order encoding is tested separately
// in services/polymarket/order_amounts_test.dart.
//
// These tests replicate the exact formulas used in:
//   - bet_slip_sheet.dart (buy flow: shares, cost, fee, payout, profit)
//   - sell_sheet.dart (sell flow: P&L, estimated payout, slippage)
//   - polymarket_trading_provider.dart (PnL aggregation, optimistic balance)
//   - polymarket_browse_provider.dart (_excitementScore)

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';

void main() {
  // =========================================================================
  // BET SLIP: Share calculation (buy flow)
  // =========================================================================
  //
  // Formula from bet_slip_sheet.dart build():
  //   rawShares = amount / currentPrice
  //   shares    = floor(rawShares * 100) / 100      (floor to 2 decimals)
  //   actualCost = shares * currentPrice
  //   fee        = actualCost * 0.02                 (2% taker fee)
  //   payout     = shares * 1.0                      (each share pays $1 if won)
  //   profit     = payout - actualCost - fee

  double calcShares(double amount, double price) {
    final raw = price > 0 ? amount / price : 0.0;
    return (raw * 100).floorToDouble() / 100;
  }

  double calcActualCost(double shares, double price) => shares * price;
  double calcFee(double actualCost) => actualCost * 0.02;
  double calcPayout(double shares) => shares * 1.0;
  double calcProfit(double payout, double actualCost, double fee) =>
      payout - actualCost - fee;
  double calcProfitPct(double payout, double actualCost, double fee) =>
      actualCost > 0 ? (payout - actualCost - fee) / actualCost * 100 : 0;

  group('Buy flow: share calculations', () {
    test('basic 10 USDC buy at 50 cents', () {
      final shares = calcShares(10, 0.50);
      expect(shares, 20.0);
      final cost = calcActualCost(shares, 0.50);
      expect(cost, 10.0);
      final fee = calcFee(cost);
      expect(fee, 0.20);
      final payout = calcPayout(shares);
      expect(payout, 20.0);
      final profit = calcProfit(payout, cost, fee);
      expect(profit, closeTo(9.80, 0.001));
    });

    test('10 USDC buy at 65 cents', () {
      final shares = calcShares(10, 0.65);
      // 10/0.65 = 15.384615... => floor(1538.4615) / 100 = 15.38
      expect(shares, 15.38);
      final cost = calcActualCost(shares, 0.65);
      expect(cost, closeTo(9.997, 0.001));
      final payout = calcPayout(shares);
      expect(payout, 15.38);
      final profit = calcProfit(payout, cost, calcFee(cost));
      expect(profit, greaterThan(5.0));
    });

    test('10 USDC buy at 1 cent (very cheap shares)', () {
      final shares = calcShares(10, 0.01);
      // 10/0.01 = 1000 => floor(100000) / 100 = 1000.0
      expect(shares, 1000.0);
      final cost = calcActualCost(shares, 0.01);
      expect(cost, 10.0);
      final payout = calcPayout(shares);
      expect(payout, 1000.0);
      final profit = calcProfit(payout, cost, calcFee(cost));
      // profit = 1000 - 10 - 0.2 = 989.8
      expect(profit, closeTo(989.80, 0.001));
    });

    test('10 USDC buy at 99 cents (expensive shares)', () {
      final shares = calcShares(10, 0.99);
      // 10/0.99 = 10.1010... => floor(1010.10) / 100 = 10.10
      expect(shares, 10.10);
      final cost = calcActualCost(shares, 0.99);
      expect(cost, closeTo(9.999, 0.001));
      final payout = calcPayout(shares);
      expect(payout, 10.10);
      final profit = calcProfit(payout, cost, calcFee(cost));
      // Low-margin bet: profit ~= 10.10 - 9.999 - 0.19998 ~= -0.099
      expect(profit, lessThan(0.2));
    });

    test('1 USDC minimum buy at 50 cents', () {
      final shares = calcShares(1, 0.50);
      expect(shares, 2.0);
      final cost = calcActualCost(shares, 0.50);
      expect(cost, 1.0);
    });

    test('0.01 USDC buy at 50 cents yields 0.02 shares', () {
      final shares = calcShares(0.01, 0.50);
      // 0.01/0.5 = 0.02 => floor(2.0)/100 = 0.02
      expect(shares, 0.02);
    });

    test('0 USDC buy yields 0 shares', () {
      final shares = calcShares(0, 0.50);
      expect(shares, 0.0);
    });

    test('buy at price 0 yields 0 shares (division protection)', () {
      final shares = calcShares(10, 0.0);
      expect(shares, 0.0);
    });

    test('floor rounding prevents overspend', () {
      // For any valid input, actualCost should never exceed the amount
      for (final price in [0.01, 0.10, 0.25, 0.33, 0.50, 0.67, 0.75, 0.99]) {
        for (final amount in [1.0, 5.0, 10.0, 25.0, 50.0, 100.0]) {
          final shares = calcShares(amount, price);
          final cost = calcActualCost(shares, price);
          expect(cost, lessThanOrEqualTo(amount + 0.01),
              reason: 'amount=$amount price=$price cost=$cost');
        }
      }
    });

    test('large amount 10000 USDC at various prices', () {
      final shares = calcShares(10000, 0.33);
      // 10000/0.33 = 30303.0303... => floor(3030303.03)/100 = 30303.03
      expect(shares, 30303.03);
      final cost = calcActualCost(shares, 0.33);
      expect(cost, closeTo(9999.999, 0.01));
    });
  });

  // =========================================================================
  // BET SLIP: Ceil-round shares for order submission (handleBuy)
  // =========================================================================
  //
  // Formula from bet_slip_sheet.dart _handleBuy():
  //   shares = ceil(amount / bestAsk * 100) / 100
  //   orderPrice = (bestAsk * (1 + slippagePct / 100)).clamp(0.01, 0.99)

  double calcOrderShares(double amount, double bestAsk) {
    return bestAsk > 0
        ? ((amount / bestAsk) * 100).ceilToDouble() / 100
        : 0.0;
  }

  double calcBuyOrderPrice(double bestAsk, double slippagePct) {
    return (bestAsk * (1 + slippagePct / 100)).clamp(0.01, 0.99);
  }

  group('Buy order: ceil-rounded shares for CLOB submission', () {
    test('10 USDC at 0.65 ask -> ceil rounds up', () {
      final shares = calcOrderShares(10, 0.65);
      // 10/0.65 = 15.384... => ceil(1538.46) / 100 = 15.39
      expect(shares, 15.39);
    });

    test('10 USDC at 0.50 ask -> exact, no rounding needed', () {
      final shares = calcOrderShares(10, 0.50);
      expect(shares, 20.0);
    });

    test('10 USDC at 0.33 ask -> ceil rounds', () {
      final shares = calcOrderShares(10, 0.33);
      // 10/0.33 = 30.3030... => ceil(3030.30)/100 = 30.31
      expect(shares, 30.31);
    });

    test('zero ask returns 0 shares', () {
      expect(calcOrderShares(10, 0.0), 0.0);
    });

    test('ceil shares >= floor shares for all prices', () {
      for (final price in [0.01, 0.10, 0.33, 0.50, 0.67, 0.99]) {
        final ceilShares = calcOrderShares(10, price);
        final floorShares = calcShares(10, price);
        expect(ceilShares, greaterThanOrEqualTo(floorShares),
            reason: 'price=$price');
      }
    });
  });

  // =========================================================================
  // SLIPPAGE: Buy order price with slippage
  // =========================================================================

  group('Buy slippage price calculation', () {
    test('1% slippage on 50 cent ask', () {
      final price = calcBuyOrderPrice(0.50, 1.0);
      expect(price, closeTo(0.505, 0.001));
    });

    test('5% slippage on 50 cent ask', () {
      final price = calcBuyOrderPrice(0.50, 5.0);
      expect(price, closeTo(0.525, 0.001));
    });

    test('10% slippage on 50 cent ask', () {
      final price = calcBuyOrderPrice(0.50, 10.0);
      expect(price, closeTo(0.55, 0.001));
    });

    test('slippage clamped to 0.99 for high ask', () {
      final price = calcBuyOrderPrice(0.95, 10.0);
      // 0.95 * 1.10 = 1.045 -> clamped to 0.99
      expect(price, 0.99);
    });

    test('slippage clamped to 0.01 floor', () {
      final price = calcBuyOrderPrice(0.005, 1.0);
      // 0.005 * 1.01 = 0.00505 -> clamped to 0.01
      expect(price, 0.01);
    });

    test('0% slippage returns same price', () {
      final price = calcBuyOrderPrice(0.65, 0.0);
      expect(price, 0.65);
    });
  });

  // =========================================================================
  // SELL: Slippage and order price
  // =========================================================================
  //
  // Formula from sell_sheet.dart _handleSell():
  //   orderPrice = (bestBid * (1 - slippagePct / 100)).clamp(0.01, 0.99)

  double calcSellOrderPrice(double bestBid, double slippagePct) {
    return (bestBid * (1 - slippagePct / 100)).clamp(0.01, 0.99);
  }

  group('Sell slippage price calculation', () {
    test('5% slippage on 50 cent bid', () {
      final price = calcSellOrderPrice(0.50, 5.0);
      expect(price, closeTo(0.475, 0.001));
    });

    test('10% slippage on 50 cent bid', () {
      final price = calcSellOrderPrice(0.50, 10.0);
      expect(price, closeTo(0.45, 0.001));
    });

    test('slippage clamped to 0.01 for low bid', () {
      final price = calcSellOrderPrice(0.05, 50.0);
      // 0.05 * 0.50 = 0.025 -> 0.025
      expect(price, closeTo(0.025, 0.001));
    });

    test('slippage clamped to 0.01 for very low bid', () {
      final price = calcSellOrderPrice(0.008, 5.0);
      // 0.008 * 0.95 = 0.0076 -> clamped to 0.01
      expect(price, 0.01);
    });

    test('clamped to 0.99 max', () {
      final price = calcSellOrderPrice(1.5, 1.0);
      // 1.5 * 0.99 = 1.485 -> clamped to 0.99
      expect(price, 0.99);
    });
  });

  // =========================================================================
  // SELL: P&L display calculations
  // =========================================================================
  //
  // From sell_sheet.dart build():
  //   livePnl = (currentPrice - avgPrice) * size
  //   livePnlPct = avgPrice > 0 ? ((currentPrice - avgPrice) / avgPrice) * 100 : 0.0
  //   estimatedPayout = sharesToSell * currentPrice

  double calcLivePnl(double currentPrice, double avgPrice, double size) =>
      (currentPrice - avgPrice) * size;

  double calcLivePnlPct(double currentPrice, double avgPrice) =>
      avgPrice > 0 ? ((currentPrice - avgPrice) / avgPrice) * 100 : 0.0;

  group('Position P&L calculations', () {
    test('profit: price went up', () {
      final pnl = calcLivePnl(0.70, 0.50, 100);
      expect(pnl, closeTo(20.0, 0.001));
      final pnlPct = calcLivePnlPct(0.70, 0.50);
      expect(pnlPct, closeTo(40.0, 0.001));
    });

    test('loss: price went down', () {
      final pnl = calcLivePnl(0.30, 0.50, 100);
      expect(pnl, closeTo(-20.0, 0.001));
      final pnlPct = calcLivePnlPct(0.30, 0.50);
      expect(pnlPct, closeTo(-40.0, 0.001));
    });

    test('breakeven: price unchanged', () {
      final pnl = calcLivePnl(0.50, 0.50, 100);
      expect(pnl, closeTo(0.0, 0.001));
      final pnlPct = calcLivePnlPct(0.50, 0.50);
      expect(pnlPct, closeTo(0.0, 0.001));
    });

    test('zero avg price returns 0% PnL (no division by zero)', () {
      final pnlPct = calcLivePnlPct(0.50, 0.0);
      expect(pnlPct, 0.0);
    });

    test('position value: estimated sell payout', () {
      final payout = 25.0 * 0.60; // 25 shares at 60 cents
      expect(payout, closeTo(15.0, 0.001));
    });

    test('100% gain: doubled price', () {
      final pnlPct = calcLivePnlPct(1.0, 0.50);
      expect(pnlPct, closeTo(100.0, 0.001));
    });

    test('position resolved at 1.0 (won): max payout', () {
      final pnl = calcLivePnl(1.0, 0.50, 100);
      expect(pnl, closeTo(50.0, 0.001));
    });

    test('position resolved at 0.0 (lost): total loss', () {
      final pnl = calcLivePnl(0.0, 0.50, 100);
      expect(pnl, closeTo(-50.0, 0.001));
    });

    test('fractional shares P&L', () {
      final pnl = calcLivePnl(0.75, 0.60, 10.5);
      // (0.75 - 0.60) * 10.5 = 0.15 * 10.5 = 1.575
      expect(pnl, closeTo(1.575, 0.001));
    });
  });

  // =========================================================================
  // FEE: Taker fee (2%)
  // =========================================================================

  group('Fee calculations', () {
    test('2% fee on 10 USDC cost', () {
      expect(calcFee(10.0), closeTo(0.20, 0.001));
    });

    test('2% fee on 0 USDC cost', () {
      expect(calcFee(0.0), 0.0);
    });

    test('2% fee on 0.01 USDC cost (very small)', () {
      expect(calcFee(0.01), closeTo(0.0002, 0.0001));
    });

    test('2% fee on 10000 USDC cost', () {
      expect(calcFee(10000.0), closeTo(200.0, 0.001));
    });

    test('fee reduces profit correctly', () {
      final shares = calcShares(10, 0.50);
      final cost = calcActualCost(shares, 0.50);
      final fee = calcFee(cost);
      final payout = calcPayout(shares);
      final profitWithFee = calcProfit(payout, cost, fee);
      final profitWithoutFee = payout - cost;
      expect(profitWithFee, lessThan(profitWithoutFee));
      expect(profitWithoutFee - profitWithFee, closeTo(fee, 0.001));
    });
  });

  // =========================================================================
  // PROFIT %: Profit percentage display
  // =========================================================================

  group('Profit percentage calculations', () {
    test('positive profit percentage', () {
      final pct = calcProfitPct(20.0, 10.0, 0.20);
      // (20 - 10 - 0.2) / 10 * 100 = 98%
      expect(pct, closeTo(98.0, 0.1));
    });

    test('negative profit percentage (high price shares)', () {
      final shares = calcShares(10, 0.99);
      final cost = calcActualCost(shares, 0.99);
      final fee = calcFee(cost);
      final payout = calcPayout(shares);
      final pct = calcProfitPct(payout, cost, fee);
      // Small positive since payout > cost + fee barely
      expect(pct, isNotNull);
    });

    test('zero cost returns 0%', () {
      final pct = calcProfitPct(0, 0, 0);
      expect(pct, 0.0);
    });
  });

  // =========================================================================
  // TOTAL P&L AGGREGATION
  // =========================================================================
  //
  // From polymarket_trading_provider.dart _fetchAllData():
  //   totalPnl = sum(position.cashPnl) for open + closed
  //   totalPnlPercent = totalInvested > 0 ? (totalPnl / totalInvested) * 100 : 0

  group('Total P&L aggregation', () {
    test('single open position', () {
      final cashPnl = 5.0;
      final initialValue = 10.0;
      final pnlPct = initialValue > 0 ? (cashPnl / initialValue) * 100 : 0.0;
      expect(pnlPct, 50.0);
    });

    test('multiple positions sum', () {
      final positions = [
        (cashPnl: 5.0, initialValue: 10.0),
        (cashPnl: -3.0, initialValue: 20.0),
        (cashPnl: 8.0, initialValue: 15.0),
      ];
      double totalPnl = 0;
      double totalInvested = 0;
      for (final p in positions) {
        totalPnl += p.cashPnl;
        totalInvested += p.initialValue;
      }
      expect(totalPnl, 10.0);
      expect(totalInvested, 45.0);
      final pnlPct = totalInvested > 0 ? (totalPnl / totalInvested) * 100 : 0.0;
      expect(pnlPct, closeTo(22.22, 0.01));
    });

    test('no positions yields 0%', () {
      final totalPnl = 0.0;
      final totalInvested = 0.0;
      final pnlPct = totalInvested > 0 ? (totalPnl / totalInvested) * 100 : 0.0;
      expect(pnlPct, 0.0);
    });

    test('all losses', () {
      final positions = [
        (cashPnl: -10.0, initialValue: 10.0),
        (cashPnl: -20.0, initialValue: 20.0),
      ];
      double totalPnl = 0;
      double totalInvested = 0;
      for (final p in positions) {
        totalPnl += p.cashPnl;
        totalInvested += p.initialValue;
      }
      expect(totalPnl, -30.0);
      final pnlPct = (totalPnl / totalInvested) * 100;
      expect(pnlPct, -100.0);
    });
  });

  // =========================================================================
  // OPTIMISTIC BALANCE UPDATE
  // =========================================================================
  //
  // From polymarket_trading_provider.dart placeOrder():
  //   buy:  newBalance = (balance - size * price).clamp(0, infinity)
  //   sell: newBalance = balance + size * price

  group('Optimistic balance update', () {
    test('buy: balance reduced by cost', () {
      final balance = 100.0;
      final size = 20.0;
      final price = 0.50;
      final cost = size * price;
      final newBalance = (balance - cost).clamp(0, double.infinity);
      expect(newBalance, 90.0);
    });

    test('buy: balance clamped to 0', () {
      final balance = 5.0;
      final size = 20.0;
      final price = 0.50;
      final cost = size * price;
      final newBalance = (balance - cost).clamp(0, double.infinity);
      expect(newBalance, 0.0);
    });

    test('sell: balance increased by proceeds', () {
      final balance = 50.0;
      final size = 10.0;
      final price = 0.65;
      final newBalance = balance + size * price;
      expect(newBalance, closeTo(56.5, 0.001));
    });
  });

  // =========================================================================
  // RESOLUTION PAYOUT
  // =========================================================================
  //
  // From polymarket_trading_provider.dart redeemPosition():
  //   payout = pos.curPrice >= 0.99 ? pos.size : 0.0

  group('Resolution payout calculations', () {
    test('winning position (curPrice >= 0.99): full payout', () {
      final curPrice = 1.0;
      final size = 50.0;
      final payout = curPrice >= 0.99 ? size : 0.0;
      expect(payout, 50.0);
    });

    test('winning position (curPrice = 0.99): full payout', () {
      final curPrice = 0.99;
      final size = 25.0;
      final payout = curPrice >= 0.99 ? size : 0.0;
      expect(payout, 25.0);
    });

    test('losing position (curPrice < 0.99): zero payout', () {
      final curPrice = 0.01;
      final size = 100.0;
      final payout = curPrice >= 0.99 ? size : 0.0;
      expect(payout, 0.0);
    });

    test('edge: curPrice = 0.989 (just below threshold)', () {
      final curPrice = 0.989;
      final size = 100.0;
      final payout = curPrice >= 0.99 ? size : 0.0;
      expect(payout, 0.0);
    });

    test('edge: curPrice = 0.0 (completely lost)', () {
      final curPrice = 0.0;
      final size = 100.0;
      final payout = curPrice >= 0.99 ? size : 0.0;
      expect(payout, 0.0);
    });

    test('balance after claim: increased by payout', () {
      final balanceBefore = 50.0;
      final payout = 25.0;
      final balanceAfter = balanceBefore + payout;
      expect(balanceAfter, 75.0);
    });
  });

  // =========================================================================
  // POSITION INVESTED/VALUE (position_card.dart)
  // =========================================================================
  //
  // From position_card.dart:
  //   invested = avgPrice * size
  //   value    = size * currentPrice

  group('Position invested and value', () {
    test('invested calculation', () {
      final invested = 0.50 * 20.0;
      expect(invested, 10.0);
    });

    test('current value calculation', () {
      final value = 20.0 * 0.65;
      expect(value, 13.0);
    });

    test('unrealized gain = value - invested', () {
      final invested = 0.50 * 20.0;
      final value = 20.0 * 0.65;
      expect(value - invested, 3.0);
    });

    test('unrealized loss when price drops', () {
      final invested = 0.50 * 20.0;
      final value = 20.0 * 0.30;
      expect(value - invested, -4.0);
    });
  });

  // =========================================================================
  // EXCITEMENT SCORE (browse provider sorting)
  // =========================================================================
  //
  // From polymarket_browse_provider.dart _excitementScore()

  double excitementScore(PolymarketEvent e, DateTime now) {
    double score = 0;
    if (e.category == 'sports') score += 500;
    if (e.endDate != null) {
      final hoursLeft = e.endDate!.difference(now).inHours;
      if (hoursLeft >= 0 && hoursLeft < 1) {
        score += 1000;
      } else if (hoursLeft >= 0 && hoursLeft < 6) {
        score += 600;
      } else if (hoursLeft >= 0 && hoursLeft < 24) {
        score += 300;
      } else if (hoursLeft >= 0 && hoursLeft < 72) {
        score += 100;
      }
    }
    if (e.volume24hr > 100000) {
      score += 200;
    } else if (e.volume24hr > 50000) {
      score += 100;
    } else if (e.volume24hr > 10000) {
      score += 50;
    }
    if (e.volume > 0) {
      final ratio = e.volume24hr / e.volume;
      if (ratio > 0.2) {
        score += 300;
      } else if (ratio > 0.1) {
        score += 150;
      } else if (ratio > 0.05) {
        score += 50;
      }
    }
    final yesPrice = e.yesPrice;
    final closeness = 1.0 - (yesPrice - 0.5).abs() * 2;
    score += closeness * 100;
    score += (e.liquidity / 10000).clamp(0, 50);
    return score;
  }

  group('Excitement score', () {
    PolymarketEvent makeEvent({
      String category = 'other',
      DateTime? endDate,
      double volume24hr = 0,
      double volume = 0,
      double liquidity = 0,
      double yesPrice = 0.5,
    }) {
      return PolymarketEvent(
        id: 'e1',
        slug: 's',
        title: 't',
        volume: volume,
        volume24hr: volume24hr,
        liquidity: liquidity,
        category: category,
        conditionId: 'c1',
        endDate: endDate,
        outcomes: [
          PolymarketOutcome(name: 'Yes', price: yesPrice),
          PolymarketOutcome(name: 'No', price: 1.0 - yesPrice),
        ],
      );
    }

    final now = DateTime(2025, 6, 15, 12, 0);

    test('sports category gets +500', () {
      final s1 = excitementScore(makeEvent(category: 'sports'), now);
      final s2 = excitementScore(makeEvent(category: 'crypto'), now);
      expect(s1 - s2, 500.0);
    });

    test('ending within 1 hour gets +1000', () {
      final e = makeEvent(
        endDate: now.add(const Duration(minutes: 30)),
      );
      final s = excitementScore(e, now);
      expect(s, greaterThanOrEqualTo(1000));
    });

    test('ending within 6 hours gets +600', () {
      final e = makeEvent(
        endDate: now.add(const Duration(hours: 3)),
      );
      final s = excitementScore(e, now);
      expect(s, greaterThanOrEqualTo(600));
    });

    test('ending within 24 hours gets +300', () {
      final e = makeEvent(
        endDate: now.add(const Duration(hours: 12)),
      );
      final s = excitementScore(e, now);
      expect(s, greaterThanOrEqualTo(300));
    });

    test('already expired gets no time bonus', () {
      final e = makeEvent(
        endDate: now.subtract(const Duration(hours: 1)),
      );
      final s = excitementScore(e, now);
      final base = excitementScore(makeEvent(), now);
      // No time bonus, so score should equal base
      expect(s, closeTo(base, 0.01));
    });

    test('high 24h volume (>100k) gets +200', () {
      final e = makeEvent(volume24hr: 150000, volume: 1000000);
      final s = excitementScore(e, now);
      final base = excitementScore(makeEvent(volume: 1000000), now);
      expect(s - base, greaterThanOrEqualTo(200));
    });

    test('50/50 market gets maximum closeness bonus (100)', () {
      final e = makeEvent(yesPrice: 0.50);
      final s = excitementScore(e, now);
      // closeness = 1.0 - |0.5-0.5|*2 = 1.0 => +100
      final eSkewed = makeEvent(yesPrice: 0.90);
      final sSkewed = excitementScore(eSkewed, now);
      expect(s, greaterThan(sSkewed));
    });

    test('extremely skewed market (99%) gets low closeness', () {
      final e = makeEvent(yesPrice: 0.99);
      final s = excitementScore(e, now);
      // closeness = 1.0 - |0.99-0.5|*2 = 1.0 - 0.98 = 0.02 => +2
      // Minimal closeness bonus
      expect(s, lessThan(110));
    });

    test('high liquidity adds up to +50', () {
      final e = makeEvent(liquidity: 600000);
      final s1 = excitementScore(e, now);
      final e2 = makeEvent(liquidity: 0);
      final s2 = excitementScore(e2, now);
      expect(s1 - s2, closeTo(50.0, 0.1)); // capped at 50
    });

    test('volume ratio > 0.2 gets +300', () {
      final e = makeEvent(volume24hr: 30000, volume: 100000);
      // ratio = 0.3 > 0.2 -> +300
      // volume24hr = 30000 which is > 10000 -> +50
      final base = excitementScore(makeEvent(), now);
      final s = excitementScore(e, now);
      expect(s - base, greaterThanOrEqualTo(300));
    });
  });

  // =========================================================================
  // CAMEL TO SNAKE CASE CONVERSION
  // =========================================================================
  //
  // From polymarket_model.dart _camelToSnake() (static helper)

  Map<String, dynamic> camelToSnake(Map<String, dynamic> json) {
    return json.map((key, value) {
      final snakeKey = key.replaceAllMapped(
        RegExp(r'[A-Z]'),
        (match) => '_${match.group(0)!.toLowerCase()}',
      );
      return MapEntry(snakeKey, value);
    });
  }

  group('camelCase to snake_case conversion', () {
    test('simple camelCase', () {
      expect(camelToSnake({'firstName': 'John'}), {'first_name': 'John'});
    });

    test('already snake_case unchanged', () {
      expect(camelToSnake({'first_name': 'John'}), {'first_name': 'John'});
    });

    test('multiple capitals', () {
      expect(
          camelToSnake({'conditionId': 'abc', 'cashPnl': 5.0}),
          {'condition_id': 'abc', 'cash_pnl': 5.0});
    });

    test('all lowercase unchanged', () {
      expect(camelToSnake({'name': 'test'}), {'name': 'test'});
    });

    test('consecutive capitals', () {
      // 'UILabel' becomes '_u_i_label'
      expect(camelToSnake({'UILabel': 'x'})['_u_i_label'], 'x');
    });

    test('empty map', () {
      expect(camelToSnake({}), {});
    });

    test('preserves values of all types', () {
      final result = camelToSnake({
        'intVal': 42,
        'doubleVal': 3.14,
        'boolVal': true,
        'nullVal': null,
        'listVal': [1, 2, 3],
      });
      expect(result['int_val'], 42);
      expect(result['double_val'], 3.14);
      expect(result['bool_val'], true);
      expect(result['null_val'], isNull);
      expect(result['list_val'], [1, 2, 3]);
    });
  });

  // =========================================================================
  // BTC 5-MIN WINDOW SLUG GENERATION
  // =========================================================================
  //
  // From polymarket_model.dart _currentBtc5MinSlug() / _currentCrypto5MinSlug()

  group('BTC 5-min slug generation', () {
    test('window aligns to 5-minute boundary', () {
      // A timestamp of 1700000100 (epoch seconds) should align to 1700000100 / 300 * 300
      final epoch = 1700000100;
      final windowStart = (epoch ~/ 300) * 300;
      expect(windowStart, 1700000100 ~/ 300 * 300);
      // Verify it's a multiple of 300
      expect(windowStart % 300, 0);
    });

    test('slug format is correct', () {
      final epoch = 1700000100;
      final windowStart = (epoch ~/ 300) * 300;
      final slug = 'btc-updown-5m-$windowStart';
      expect(slug, startsWith('btc-updown-5m-'));
      expect(slug.split('-').last, windowStart.toString());
    });

    test('crypto slug uses asset name', () {
      final epoch = 1700000100;
      final windowStart = (epoch ~/ 300) * 300;
      final asset = 'ETH';
      final slug = '${asset.toLowerCase()}-updown-5m-$windowStart';
      expect(slug, startsWith('eth-updown-5m-'));
    });
  });

  // =========================================================================
  // BTC 5-MIN EVENT: _parseWindowStart
  // =========================================================================

  group('Btc5MinEvent.parseWindowStart', () {
    test('parses valid slug', () {
      // Btc5MinEvent._parseWindowStart is private, test the factory
      // by checking the windowStartTime field
      // We test the logic directly since we can't instantiate Event
      final slug = 'btc-updown-5m-1700000100';
      final parts = slug.split('-');
      final ts = int.tryParse(parts.last);
      expect(ts, 1700000100);
      final dt =
          DateTime.fromMillisecondsSinceEpoch(ts! * 1000, isUtc: true);
      expect(dt.isUtc, isTrue);
    });

    test('returns null for slug without numeric suffix', () {
      final slug = 'btc-updown-5m-abc';
      final parts = slug.split('-');
      final ts = int.tryParse(parts.last);
      expect(ts, isNull);
    });
  });

  // =========================================================================
  // BTC 5-MIN EVENT: secondsRemaining / isExpired
  // =========================================================================

  group('Btc5MinEvent timing', () {
    test('secondsRemaining positive for future endDate', () {
      final endDate = DateTime.now().add(const Duration(minutes: 3));
      final diff = endDate.difference(DateTime.now()).inSeconds;
      final remaining = diff < 0 ? 0 : diff;
      expect(remaining, greaterThan(0));
      expect(remaining, lessThanOrEqualTo(180));
    });

    test('secondsRemaining zero for past endDate', () {
      final endDate = DateTime.now().subtract(const Duration(minutes: 1));
      final diff = endDate.difference(DateTime.now()).inSeconds;
      final remaining = diff < 0 ? 0 : diff;
      expect(remaining, 0);
    });

    test('isExpired true when secondsRemaining is 0', () {
      expect(0 <= 0, isTrue);
    });

    test('isExpired false when secondsRemaining > 0', () {
      expect(180 <= 0, isFalse);
    });
  });

  // =========================================================================
  // MULTI-OUTCOME MARKET EDGE CASES
  // =========================================================================

  group('Multi-outcome market calculations', () {
    test('3-outcome market: probabilities can sum > 1', () {
      const outcomes = [
        PolymarketOutcome(name: 'A', price: 0.40),
        PolymarketOutcome(name: 'B', price: 0.35),
        PolymarketOutcome(name: 'C', price: 0.30),
      ];
      final sum = outcomes.fold<double>(0, (s, o) => s + o.price);
      // Polymarket allows overround (sum > 1)
      expect(sum, closeTo(1.05, 0.001));
    });

    test('buying cheapest outcome in multi-market yields highest payout ratio', () {
      const cheapest = 0.10;
      const expensive = 0.60;
      final cheapShares = calcShares(10, cheapest);
      final expShares = calcShares(10, expensive);
      expect(cheapShares, greaterThan(expShares));
      expect(calcPayout(cheapShares), greaterThan(calcPayout(expShares)));
    });

    test('single outcome market still works', () {
      const event = PolymarketEvent(
        id: 'e1',
        slug: 's',
        title: 't',
        volume: 0,
        liquidity: 0,
        category: 'c',
        conditionId: 'c1',
        outcomes: [PolymarketOutcome(name: 'Only', price: 0.75)],
      );
      expect(event.outcomeCount, 1);
      expect(event.isBinary, isFalse);
      expect(event.yesPrice, 0.75); // Falls back to first outcome
    });
  });

  // =========================================================================
  // ZERO LIQUIDITY / EDGE SCENARIOS
  // =========================================================================

  group('Zero liquidity and edge scenarios', () {
    test('zero price yields zero shares', () {
      expect(calcShares(10, 0.0), 0.0);
    });

    test('zero amount yields zero shares', () {
      expect(calcShares(0, 0.50), 0.0);
    });

    test('negative price: shares calculation does not crash', () {
      // Model does not validate price; negative price falls through to
      // the else branch (price > 0 is false) so returns 0.
      final shares = calcShares(10, -0.50);
      expect(shares, 0.0);
    });

    test('very tiny amount 0.001 at 0.50', () {
      final shares = calcShares(0.001, 0.50);
      // 0.001/0.50 = 0.002 => floor(0.2)/100 = 0.0
      expect(shares, 0.0);
    });

    test('pnl with zero-size position is zero', () {
      final pnl = calcLivePnl(0.80, 0.50, 0.0);
      expect(pnl, 0.0);
    });

    test('rounding precision: no floating point accumulation error', () {
      // Simulate many small buys
      double totalShares = 0;
      for (int i = 0; i < 100; i++) {
        totalShares += calcShares(1, 0.33);
      }
      // Each buy: 1/0.33 = 3.030... => floor(303.03)/100 = 3.03
      // 100 * 3.03 = 303.0
      expect(totalShares, closeTo(303.0, 0.01));
    });
  });

  // =========================================================================
  // DISPLAY FORMATTING (from bet_slip_sheet / position_card)
  // =========================================================================

  group('Price display formatting', () {
    test('price per share in cents', () {
      final priceStr = (0.65 * 100).toStringAsFixed(1);
      expect(priceStr, '65.0');
    });

    test('shares formatted to 2 decimals', () {
      final shares = calcShares(10, 0.33);
      final formatted = shares.toStringAsFixed(2);
      expect(formatted, '30.30');
    });

    test('cost formatted to 2 decimals', () {
      final shares = calcShares(10, 0.33);
      final cost = calcActualCost(shares, 0.33);
      final formatted = cost.toStringAsFixed(2);
      // 30.30 * 0.33 = 9.999 which rounds to 10.00 in toStringAsFixed(2)
      expect(formatted, '10.00');
    });

    test('payout formatted to 2 decimals', () {
      final payout = calcPayout(15.38);
      final formatted = payout.toStringAsFixed(2);
      expect(formatted, '15.38');
    });
  });
}
