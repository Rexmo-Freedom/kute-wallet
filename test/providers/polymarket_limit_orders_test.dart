// A resting limit buy through the placement engine, with fakes only
// (nothing is signed or sent; the fake account records what it would
// place):
//   * P1: a price off the market's tick, read from the book before the
//     approval, is refused there with what to change, never by the encoder
//     after Face ID;
//   * P2: the minimum stake at 28¢ signs 5.00 shares, never 4.99; a stake
//     under the venue's minimum in shares is refused before approval;
//   * P9: the collateral check of a crossing limit covers its fee ceiling;
//   * P5: open orders that could not be read are unknown, never "nothing
//     reserved": a failed read keeps the last known list, and with none
//     known nothing is spendable.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/providers/investment_balances_provider.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_bet_controller.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/services/polymarket/limit_order_rules.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Order, OrderSide, OrderType;

const _token = '5678';

Order _buy(String size, String price) => Order(
    id: 'o-$size-$price',
    market: 'm',
    assetId: 'a',
    owner: 'k',
    side: 'BUY',
    price: price,
    originalSize: size,
    sizeMatched: '0',
    outcome: 'Yes');

class _Trading extends PolymarketTradingNotifier {
  _Trading({this.ordersKnown = true});
  final bool ordersKnown;

  final placed = <({double size, double price, double? feeReserve})>[];

  @override
  Future<PolymarketTradingState> build() async => PolymarketTradingState(
      usdcBalance: 50,
      proxyWalletAddress: '0xdeposit',
      openOrdersKnown: ordersKnown);

  @override
  String? get signingWalletId => 'spending';

  @override
  void prefetchOrderReads() {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> enableTrading({
    void Function(String status)? onProgress,
    bool force = false,
  }) async {}

  @override
  Future<Map<String, dynamic>> placeOrder({
    required String tokenId,
    required OrderSide side,
    required double size,
    required double price,
    bool negRisk = false,
    PolymarketMarketBuyQuote? marketQuote,
    OrderType orderType = OrderType.fok,
    double? spendUsd,
    double? feeReserveUsd,
    String? marketTitle,
    String? marketImage,
    String? marketOutcome,
    String? conditionId,
    String? eventSlug,
    String? endDate,
    String? marketCategory,
    String? source,
    String? entrySource,
    Map<String, Object>? analytics,
    required AuthGrant grant,
    void Function(String step)? onStep,
  }) async {
    placed.add((size: size, price: price, feeReserve: feeReserveUsd));
    throw StateError('stopped by the test');
  }
}

Map<String, dynamic> _book({String tick = '0.01', String min = '5'}) => {
      'market': 'm',
      'asset_id': _token,
      'tick_size': tick,
      'neg_risk': false,
      'min_order_size': min,
      'asks': [
        {'price': '0.60', 'size': '1000'}
      ],
      'bids': [
        {'price': '0.20', 'size': '100'}
      ],
    };

PendingBetIntent _limit(double amount, double price) => PendingBetIntent(
      tokenId: _token,
      amount: amount,
      slippagePct: 5,
      marketQuestion: 'Will it rain?',
      outcomeName: 'Yes',
      expectedPrice: price,
      isLimit: true,
      limitPrice: price,
    );

void main() {
  Future<({Object? error, _Trading trading, PendingBetIntent? pending})> run(
      PendingBetIntent intent,
      {Map<String, dynamic>? book,
      bool ordersKnown = true}) async {
    final trading = _Trading(ordersKnown: ordersKnown);
    final container = ProviderContainer(overrides: [
      polymarketTradingProvider.overrideWith(() => trading),
    ]);
    addTearDown(container.dispose);
    container.listen(polymarketTradingProvider, (_, __) {});
    await container.read(polymarketTradingProvider.future);
    final controller = container.read(polymarketBetControllerProvider);
    Object? error;
    await http.runWithClient(() async {
      final PendingBetIntent prepared;
      try {
        prepared = await controller.prepareIntent(intent);
      } catch (e) {
        error = e;
        return;
      }
      container.read(pendingPolymarketBetProvider.notifier).setIntent(prepared);
      final review = controller.reviewIntent(prepared)!;
      final grant = AuthGrants.issue(review, method: AuthGrantMethod.allowance);
      await controller.place('usdc', grant: grant);
    },
        () => MockClient((req) async => req.url.path == '/book'
            ? http.Response(jsonEncode(book ?? _book()), 200)
            : http.Response('offline', 503)));
    return (
      error: error,
      trading: trading,
      pending: container.read(pendingPolymarketBetProvider)
    );
  }

  test('P2: the minimum stake at 28¢ signs 5.00 shares, never 4.99',
      () async {
    for (final cents in [28, 33, 56, 66]) {
      final price = cents / 100;
      final minimum = polymarketLimitBuyMinimumUsd(5, price);
      final r = await run(_limit(minimum, price));
      expect(r.error, isNull, reason: '$cents¢');
      expect(r.trading.placed.single.size, 5.0, reason: '$cents¢');
      expect(r.trading.placed.single.price, price);
      // P9: the fee ceiling of a crossing limit rides with it.
      expect(r.trading.placed.single.feeReserve, greaterThan(0));
    }
  });

  test('P1: a price off the market\'s tick is refused before approval',
      () async {
    final r = await run(_limit(10, 0.535));
    expect(r.error, isA<PolymarketLimitRefused>());
    expect((r.error as PolymarketLimitRefused).reason,
        PolymarketLimitRefusal.offTick);
    expect((r.error as PolymarketLimitRefused).tick, 0.01);
    expect(r.trading.placed, isEmpty);
    // On a half-cent market the same price rests.
    final fine = await run(_limit(10, 0.535), book: _book(tick: '0.005'));
    expect(fine.error, isNull);
    expect(fine.trading.placed, hasLength(1));
  });

  test('P2: under the venue\'s minimum in shares is refused before approval',
      () async {
    final r = await run(_limit(1.39, 0.28));
    expect(r.error, isA<PolymarketLimitRefused>());
    expect((r.error as PolymarketLimitRefused).reason,
        PolymarketLimitRefusal.belowMinimum);
    expect((r.error as PolymarketLimitRefused).minShares, 5);
    expect(r.trading.placed, isEmpty);
    // A market quoting 15 shares asks for more.
    final big = await run(_limit(4.19, 0.28), book: _book(min: '15'));
    expect((big.error as PolymarketLimitRefused).minShares, 15);
    expect((await run(_limit(4.20, 0.28), book: _book(min: '15'))).error,
        isNull);
  });

  test('P9: under 1¢ and over 99¢ on a 0.1¢ market are placed as set',
      () async {
    for (final price in [0.005, 0.995]) {
      final r = await run(_limit(10, price), book: _book(tick: '0.001'));
      expect(r.error, isNull, reason: '$price');
      expect(r.trading.placed.single.price, price);
    }
  });

  group('P5: open orders that could not be read', () {
    test('a failed read keeps the account\'s last list; none known is unknown',
        () {
      final previous = PolymarketTradingState(openOrders: [_buy('10', '0.3')]);
      final kept = polymarketOrdersAfterRead(read: null, previous: previous);
      expect(kept.known, isTrue);
      expect(kept.orders, previous.openOrders);
      final fresh =
          polymarketOrdersAfterRead(read: const [], previous: previous);
      expect(fresh.known, isTrue);
      expect(fresh.orders, isEmpty);
      final none = polymarketOrdersAfterRead(read: null, previous: null);
      expect(none.known, isFalse);
      final unknownBefore = polymarketOrdersAfterRead(
          read: null,
          previous: const PolymarketTradingState(openOrdersKnown: false));
      expect(unknownBefore.known, isFalse);
    });

    test('with none known nothing is spendable and nothing is signed',
        () async {
      final r = await run(
          const PendingBetIntent(
              tokenId: _token,
              amount: 5,
              slippagePct: 5,
              marketQuestion: 'Will it rain?',
              outcomeName: 'Yes',
              expectedPrice: 0.6),
          ordersKnown: false);
      expect(r.trading.placed, isEmpty);
      expect(r.pending?.status, PendingBetStatus.failed);
    });

    test('the Investments figures read the reserve as unknown, never \$0',
        () {
      const state = PolymarketTradingState(
          isAuthenticated: true, usdcBalance: 40, openOrdersKnown: false);
      final balances = polymarketInvestmentBalances(
          state: state,
          orders: state.openOrdersKnown ? state.openOrders : null);
      expect(balances.available, isNull);
    });
  });
}
