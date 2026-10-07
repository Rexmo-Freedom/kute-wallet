import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/investment_balances_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Order;

Order _order(
        {String original = '100',
        String matched = '20',
        String price = '0.5',
        String side = 'BUY'}) =>
    Order(
        id: 'a',
        market: 'm',
        assetId: 't',
        owner: 'u',
        side: side,
        price: price,
        originalSize: original,
        sizeMatched: matched,
        outcome: 'Yes');

class _UninitializedHl extends HyperliquidTradingNotifier {
  @override
  Future<HyperliquidTradingState> build() async =>
      const HyperliquidTradingState();
}

class _UninitializedPm extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState();
}

void main() {
  test('HL cash and portfolio reconcile equity, held cash and spot', () {
    final values = hyperliquidInvestmentBalances(
      state: const HyperliquidTradingState(
        perpEquity: 200,
        withdrawable: 120,
        spotBalances: [
          HlSpotBalance(coin: 'USDC', total: 50, hold: 20),
          HlSpotBalance(coin: 'HYPE', total: 2, hold: 0),
        ],
      ),
      spotPrices: {'HYPE': 25},
    );
    expect(values.available, 150);
    expect(values.portfolio, 150); // 80 equity + 20 reserved + 50 spot
    expect(values.available! + values.portfolio!, 300);
    expect(values.hasPortfolioContent, isTrue);
  });
  test('HL cash alone hides Portfolio, trade history keeps it accessible', () {
    const state = HyperliquidTradingState(
        perpEquity: 200,
        withdrawable: 200,
        spotBalances: [HlSpotBalance(coin: 'USDC', total: 50, hold: 0)]);
    final empty = hyperliquidInvestmentBalances(state: state, spotPrices: {});
    expect(empty.available, 250);
    expect(empty.portfolio, 0);
    expect(empty.hasPortfolioContent, isFalse);
    expect(
        hyperliquidInvestmentBalances(
                state: state, spotPrices: {}, hasHistory: true)
            .hasPortfolioContent,
        isTrue);
  });
  test('HL missing spot price never displays an understated portfolio total',
      () {
    final values = hyperliquidInvestmentBalances(
      state: const HyperliquidTradingState(
          perpEquity: 100,
          withdrawable: 100,
          spotBalances: [HlSpotBalance(coin: 'HYPE', total: 2, hold: 0)]),
      spotPrices: {},
    );
    expect(values.portfolio, isNull);
    expect(values.available, 100);
    expect(values.hasPortfolioContent, isTrue);
  });
  test(
      'PM remaining buy reservations are counted once and sell orders do not reserve cash',
      () {
    final values = polymarketInvestmentBalances(
        state: const PolymarketTradingState(usdcBalance: 100),
        orders: [_order(), _order(side: 'SELL')]);
    expect(values.available, 60);
    expect(values.portfolio, 40);
    expect(values.total, 100);
    expect(values.available! + values.portfolio!, values.total);
    expect(values.hasPortfolioContent, isTrue);
  });
  test('PM cash alone hides Portfolio while history retains access', () {
    const state = PolymarketTradingState(usdcBalance: 100);
    expect(
        polymarketInvestmentBalances(state: state, orders: [])
            .hasPortfolioContent,
        isFalse);
    expect(
        polymarketInvestmentBalances(state: state, orders: [], hasHistory: true)
            .hasPortfolioContent,
        isTrue);
  });
  test(
      'PM unknown order reservations preserve unknown balance instead of overstating available',
      () {
    final values = polymarketInvestmentBalances(
        state: const PolymarketTradingState(usdcBalance: 100), orders: null);
    expect(values.available, isNull);
    expect(values.portfolio, isNull);
  });
  for (final order in [
    _order(price: 'bad'),
    _order(price: 'NaN'),
    _order(price: 'Infinity'),
    _order(original: 'bad'),
    _order(matched: 'NaN'),
    _order(price: '-1')
  ]) {
    test(
        'PM malformed reservation ${order.price}/${order.originalSize}/${order.sizeMatched} keeps amounts unknown',
        () {
      final values = polymarketInvestmentBalances(
          state: const PolymarketTradingState(usdcBalance: 100),
          orders: [order]);
      expect(values.available, isNull);
      expect(values.portfolio, isNull);
      expect(values.hasPortfolioContent, isTrue);
    });
  }
  test('uninitialized providers do not show a fabricated zero balance',
      () async {
    final container = ProviderContainer(overrides: [
      hyperliquidTradingProvider.overrideWith(_UninitializedHl.new),
      polymarketTradingProvider.overrideWith(_UninitializedPm.new),
    ]);
    addTearDown(container.dispose);
    for (final product in InvestmentsProduct.values) {
      final sub =
          container.listen(investmentBalancesProvider(product), (_, __) {});
      addTearDown(sub.close);
    }
    await container.read(hyperliquidTradingProvider.future);
    await container.read(polymarketTradingProvider.future);
    for (final product in InvestmentsProduct.values) {
      final values = container.read(investmentBalancesProvider(product));
      expect(values.available, isNull);
      expect(values.portfolio, isNull);
    }
  });
}
