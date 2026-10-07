import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/funding/venue_shortfall.dart';

void main() {
  group('shortfallUsd', () {
    test('zero when ready cash covers the order', () {
      expect(ShortfallRules.shortfallUsd(requiredUsd: 10, readyUsd: 10), 0);
      expect(ShortfallRules.shortfallUsd(requiredUsd: 10, readyUsd: 12), 0);
    });

    test('rounds the gap up to the cent', () {
      expect(ShortfallRules.shortfallUsd(requiredUsd: 10.204, readyUsd: 3),
          closeTo(7.21, 1e-9));
      expect(ShortfallRules.shortfallUsd(requiredUsd: 10, readyUsd: 3),
          closeTo(7, 1e-9));
    });

    test('treats a missing or negative balance as nothing ready', () {
      expect(ShortfallRules.shortfallUsd(requiredUsd: 5, readyUsd: double.nan),
          closeTo(5, 1e-9));
      expect(ShortfallRules.shortfallUsd(requiredUsd: 5, readyUsd: -2),
          closeTo(5, 1e-9));
    });

    test('no order, no shortfall', () {
      expect(ShortfallRules.shortfallUsd(requiredUsd: 0, readyUsd: 0), 0);
      expect(
          ShortfallRules.shortfallUsd(
              requiredUsd: double.infinity, readyUsd: 0),
          0);
    });
  });

  group('topUp', () {
    test('a balance of 3 and an order of 5 prefill the order: 5', () {
      final t = ShortfallRules.topUp(
          orderUsd: 5, requiredUsd: 5.08, readyUsd: 3, routeFee: 0.006);
      expect(t.usd, closeTo(5, 1e-9));
      expect(t.rule, ShortfallRules.ruleOrderAmount);
    });

    test('nothing ready, no route fee: the order plus its slip fee, 5.08',
        () {
      final t = ShortfallRules.topUp(
          orderUsd: 5, requiredUsd: 5.08, readyUsd: 0);
      expect(t.usd, closeTo(5.08, 1e-9));
      expect(t.rule, ShortfallRules.ruleOrderPlusFee);
    });

    test(
        'Dollars route keeping 0.6% of the amount: the route fee is added too, '
        'so what arrives covers the order and its fee', () {
      // 5 sent lands 4.97; 0.11 is missing, grossed up by 0.6% → 5.12.
      final t = ShortfallRules.topUp(
          orderUsd: 5, requiredUsd: 5.08, readyUsd: 0, routeFee: 0.006);
      expect(t.usd, closeTo(5.12, 1e-9));
      expect(t.rule, ShortfallRules.ruleOrderPlusFee);
      expect(t.usd * (1 - 0.006), greaterThanOrEqualTo(5.08));
    });

    test('route fee only: a fee-free order still covers what the route keeps',
        () {
      // 10 at 1%: 9.90 arrives, 0.10 missing → 10 + 0.10 / 0.99 = 10.11.
      expect(
          ShortfallRules.topUpUsd(
              orderUsd: 10, requiredUsd: 10, readyUsd: 0, routeFee: 0.01),
          closeTo(10.11, 1e-9));
    });

    test('a few cents ready that cover what the route keeps: the order alone',
        () {
      // 4.97 arrives + 0.11 ready = 5.08.
      expect(
          ShortfallRules.topUpUsd(
              orderUsd: 5, requiredUsd: 5.08, readyUsd: 0.11, routeFee: 0.006),
          closeTo(5, 1e-9));
      expect(
          ShortfallRules.topUpUsd(
              orderUsd: 5, requiredUsd: 5.08, readyUsd: 0.05, routeFee: 0.006),
          closeTo(5.07, 1e-9));
    });

    test('an unreadable route fee counts the fallback', () {
      // 2% fallback: 4.90 arrives, 0.18 missing → 5 + 0.18 / 0.98 = 5.19.
      expect(
          ShortfallRules.topUpUsd(
              orderUsd: 5,
              requiredUsd: 5.08,
              readyUsd: 0,
              routeFee: double.nan),
          closeTo(5.19, 1e-9));
    });

    test('no headroom on top: a large order prefills itself', () {
      expect(
          ShortfallRules.topUpUsd(
              orderUsd: 20, requiredUsd: 20.4, readyUsd: 1, routeFee: 0.01),
          closeTo(20, 1e-9));
    });

    test('rounds up to the cent', () {
      expect(
          ShortfallRules.topUpUsd(
              orderUsd: 7.333, requiredUsd: 7.333, readyUsd: 0),
          closeTo(7.34, 1e-9));
      expect(
          ShortfallRules.topUpUsd(
              orderUsd: 5, requiredUsd: 5.0812, readyUsd: 0),
          closeTo(5.09, 1e-9));
    });

    test('never under the Move minimum', () {
      expect(
          ShortfallRules.topUpUsd(
              orderUsd: 0.25, requiredUsd: 0.26, readyUsd: 0),
          1.0);
    });

    test('a required figure under the order (or unreadable) is the order',
        () {
      expect(
          ShortfallRules.topUpUsd(orderUsd: 5, requiredUsd: 4, readyUsd: 0),
          closeTo(5, 1e-9));
      expect(
          ShortfallRules.topUpUsd(
              orderUsd: 5, requiredUsd: double.nan, readyUsd: double.nan),
          closeTo(5, 1e-9));
    });

    test('nothing typed, nothing to prefill', () {
      expect(
          ShortfallRules.topUpUsd(orderUsd: 0, requiredUsd: 0, readyUsd: 0),
          0);
    });
  });

  group('routeFeeFrom', () {
    test('the share the estimate keeps', () {
      expect(ShortfallRules.routeFeeFrom(sentUsd: 5, arrivingUsd: 4.97),
          closeTo(0.006, 1e-9));
    });

    test('more arriving than sent is no fee', () {
      expect(ShortfallRules.routeFeeFrom(sentUsd: 5, arrivingUsd: 5.01), 0);
    });

    test('an implausible or unreadable estimate is not believed', () {
      expect(ShortfallRules.routeFeeFrom(sentUsd: 5, arrivingUsd: 0.05),
          isNull);
      expect(ShortfallRules.routeFeeFrom(sentUsd: 0, arrivingUsd: 5), isNull);
      expect(
          ShortfallRules.routeFeeFrom(sentUsd: 5, arrivingUsd: double.nan),
          isNull);
    });
  });

  group('fundingState', () {
    test('nothing on its way: the deposit button', () {
      expect(
          ShortfallRules.fundingState(shortfallUsd: 5, incomingUsd: 0),
          SlipFundingState.deposit);
      expect(
          ShortfallRules.fundingState(shortfallUsd: 5, incomingUsd: 0.004),
          SlipFundingState.deposit);
    });

    test('a deposit on its way that covers the shortfall', () {
      expect(
          ShortfallRules.fundingState(shortfallUsd: 5.08, incomingUsd: 5.08),
          SlipFundingState.incoming);
      expect(
          ShortfallRules.fundingState(shortfallUsd: 2.08, incomingUsd: 4.97),
          SlipFundingState.incoming);
    });

    test('nothing typed yet: any deposit on its way covers it', () {
      expect(
          ShortfallRules.fundingState(shortfallUsd: 0, incomingUsd: 5),
          SlipFundingState.incoming);
    });

    test('a deposit on its way that falls short', () {
      expect(
          ShortfallRules.fundingState(shortfallUsd: 10, incomingUsd: 5),
          SlipFundingState.incomingShort);
    });
  });

  group('remainingTopUpUsd', () {
    test('the rest grossed up by the route fee', () {
      // 10.08 − 4.97 = 5.11, at 1%: 5.1617… → 5.17.
      expect(
          ShortfallRules.remainingTopUpUsd(
              shortfallUsd: 10.08, incomingUsd: 4.97, routeFee: 0.01),
          closeTo(5.17, 1e-9));
    });

    test('the rest, up to the cent', () {
      expect(
          ShortfallRules.remainingTopUpUsd(
              shortfallUsd: 10.08, incomingUsd: 4.971),
          closeTo(5.11, 1e-9));
    });

    test('never under the Move minimum', () {
      expect(
          ShortfallRules.remainingTopUpUsd(
              shortfallUsd: 5.08, incomingUsd: 4.97),
          1.0);
    });

    test('nothing when the deposit on its way covers it', () {
      expect(
          ShortfallRules.remainingTopUpUsd(shortfallUsd: 5, incomingUsd: 5),
          0);
    });
  });

  group('chooseSource', () {
    test('Dollars first when they cover everything', () {
      expect(
          ShortfallRules.chooseSource(
              topUpUsd: 10, dollarsUsd: 10, bitcoinUsd: 500),
          ShortfallSource.dollars);
    });

    test('Bitcoin when Dollars fall short and Bitcoin covers it alone', () {
      expect(
          ShortfallRules.chooseSource(
              topUpUsd: 10, dollarsUsd: 9.99, bitcoinUsd: 10),
          ShortfallSource.bitcoin);
    });

    test('never splits: neither alone leaves the Move default', () {
      expect(
          ShortfallRules.chooseSource(
              topUpUsd: 10, dollarsUsd: 6, bitcoinUsd: 6),
          isNull);
    });

    test('nothing to top up, nothing to choose', () {
      expect(
          ShortfallRules.chooseSource(
              topUpUsd: 0, dollarsUsd: 100, bitcoinUsd: 100),
          isNull);
    });

    test('an unreadable balance never pays', () {
      expect(
          ShortfallRules.chooseSource(
              topUpUsd: 5, dollarsUsd: double.nan, bitcoinUsd: double.nan),
          isNull);
    });
  });

  group('hyperliquidRequiredUsd', () {
    test('margin with price headroom plus fees on notional', () {
      // 100 * 1.01 * (1 + 5 * 0.0019) = 101.95950
      expect(
          ShortfallRules.hyperliquidRequiredUsd(
              marginUsd: 100, leverage: 5, slippagePct: 1),
          closeTo(101.9595, 1e-9));
    });

    test('spot (leverage 1, no slippage)', () {
      expect(ShortfallRules.hyperliquidRequiredUsd(marginUsd: 50),
          closeTo(50.095, 1e-9));
    });
  });

  group('Kute app fee on the top-up', () {
    // What lands from [sent]: the route keeps its share, then Kute's rate
    // is taken from what remains, the way the provider applies both.
    double landed(double sent, double routeFee, int bps) =>
        sent * (1 - routeFee) * (1 - bps / 10000);

    test(r'a $20 order at 50 bps lands the whole $20, not $19.90', () {
      final t = ShortfallRules.topUp(
          orderUsd: 20, requiredUsd: 20, readyUsd: 0, kuteFeeBps: 50);
      expect(t.usd, closeTo(20.11, 1e-9));
      expect(t.rule, ShortfallRules.ruleOrderPlusFee);
      expect(landed(t.usd, 0, 50), greaterThanOrEqualTo(20));
    });

    const amounts = [1.0, 1.37, 5.0, 20.0, 99.99, 2500.0, 125000.0];
    const routes = [0.0, 0.006, 0.0134];
    const rates = {'50 bps': 50, 'discounted 25 bps': 25, '0 bps': 0};

    for (final rate in rates.entries) {
      test('landed amount covers the order and its slip fee at ${rate.key}',
          () {
        for (final order in amounts) {
          for (final route in routes) {
            final required = order * 1.016;
            final usd = ShortfallRules.topUpUsd(
                orderUsd: order,
                requiredUsd: required,
                readyUsd: 0,
                routeFee: route,
                kuteFeeBps: rate.value);
            expect(landed(usd, route, rate.value) + 1e-9,
                greaterThanOrEqualTo(required),
                reason: 'order $order route $route');
            // Never more than a cent over what is needed.
            expect(landed(usd - 0.01, route, rate.value),
                lessThan(required),
                reason: 'order $order route $route');
          }
        }
      });

      test('"Add more" lands the rest at ${rate.key}', () {
        for (final rest in amounts) {
          for (final route in routes) {
            final usd = ShortfallRules.remainingTopUpUsd(
                shortfallUsd: rest + 3,
                incomingUsd: 3,
                routeFee: route,
                kuteFeeBps: rate.value);
            expect(landed(usd, route, rate.value) + 1e-9,
                greaterThanOrEqualTo(rest),
                reason: 'rest $rest route $route');
          }
        }
      });
    }

    test('0 bps is the route fee alone', () {
      expect(
          ShortfallRules.topUpUsd(
              orderUsd: 10,
              requiredUsd: 10,
              readyUsd: 0,
              routeFee: 0.01,
              kuteFeeBps: 0),
          closeTo(10.11, 1e-9));
    });

    test('a tiny order stays at the Move minimum when that covers it', () {
      expect(
          ShortfallRules.topUpUsd(
              orderUsd: 0.25, requiredUsd: 0.26, readyUsd: 0, kuteFeeBps: 50),
          1.0);
      expect(
          ShortfallRules.remainingTopUpUsd(
              shortfallUsd: 3.05, incomingUsd: 3, kuteFeeBps: 50),
          1.0);
    });

    test('ready cash that covers the Kute fee keeps the order amount', () {
      // 20 at 50 bps lands 19.90; 0.10 ready covers the rest.
      final t = ShortfallRules.topUp(
          orderUsd: 20, requiredUsd: 20, readyUsd: 0.10, kuteFeeBps: 50);
      expect(t.usd, closeTo(20, 1e-9));
      expect(t.rule, ShortfallRules.ruleOrderAmount);
    });

    test('a Kute rate no quote could carry is counted at the 4% ceiling', () {
      expect(
          ShortfallRules.topUpUsd(
              orderUsd: 10, requiredUsd: 10, readyUsd: 0, kuteFeeBps: 9000),
          ShortfallRules.topUpUsd(
              orderUsd: 10, requiredUsd: 10, readyUsd: 0, kuteFeeBps: 400));
      expect(
          ShortfallRules.topUpUsd(
              orderUsd: 10, requiredUsd: 10, readyUsd: 0, kuteFeeBps: -5),
          closeTo(10, 1e-9));
    });
  });
}
