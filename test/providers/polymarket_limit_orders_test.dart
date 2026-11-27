// A resting limit buy through the placement engine, with fakes only
// (nothing is signed or sent; the fake account records what it would
// place):
//   * P1: a price off the market's tick, read from the book before the
//     approval, is refused there with what to change, never by the encoder
//     after Face ID;
//   * P2: the minimum stake at 28¢ signs 5.00 shares, never 4.99; a stake
//     under the venue's minimum in shares is refused before approval;
//   * P9: the collateral check of a crossing limit covers its fee ceiling;
//   * P5: a failed open-orders read keeps the account's last known list
//     (a known reserve stays held), and with none known it is nothing
//     reserved as before: a cold boot, or an orders read that keeps
//     failing, never blocks or slows a plain market buy;
//   * a plain market buy (Advanced off) end to end: its fee figure inside
//     1c-99c exactly as before.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/providers/pending_bet_autofire.dart'
    show autofireLimitOrder;
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_bet_controller.dart';
import 'package:kute/providers/polymarket_resting_fills_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/polymarket_user_channel_provider.dart';
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart'
    show betSlipWorstFeePrice;
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
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
  _Trading({this.balance = 50, this.orders = const []});
  final double balance;
  final List<Order> orders;

  /// The venue's answer: null throws (the default fake stops there).
  Map<String, dynamic>? answer;

  /// The account changes while the order is placed (a wallet switch).
  String? switchTo;

  final placed = <({double size, double price, double? feeReserve})>[];

  @override
  Future<PolymarketTradingState> build() async => PolymarketTradingState(
      isAuthenticated: true,
      usdcBalance: balance,
      proxyWalletAddress: '0xdeposit',
      openOrders: orders);

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
    final to = switchTo;
    if (to != null) {
      state = AsyncData(PolymarketTradingState(
          isAuthenticated: true, usdcBalance: balance, proxyWalletAddress: to));
    }
    final a = answer;
    if (a == null) throw StateError('stopped by the test');
    return a;
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

class _Channel extends UserChannelNotifier {
  @override
  UserChannelState build() => const UserChannelState();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // A placed bet plays its sound: no audio plugin in a test.
  for (final channel in const [
    'xyz.luan/audioplayers.global',
    'xyz.luan/audioplayers',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
  }
  Future<({Object? error, _Trading trading, PendingBetIntent? pending})> run(
      PendingBetIntent intent,
      {Map<String, dynamic>? book,
      double balance = 50,
      List<Order> orders = const [],
      Map<String, dynamic>? answer,
      String? switchTo,
      double? receiptShares,
      List<PolymarketRestingFill>? fills}) async {
    final trading = _Trading(balance: balance, orders: orders)
      ..answer = answer
      ..switchTo = switchTo;
    final container = ProviderContainer(overrides: [
      polymarketTradingProvider.overrideWith(() => trading),
      userChannelProvider.overrideWith(_Channel.new),
    ]);
    addTearDown(container.dispose);
    container.listen(polymarketTradingProvider, (_, __) {});
    await container.read(polymarketTradingProvider.future);
    // The Predictions screen's fills tracker, when the test follows it.
    if (fills != null) {
      container.listen<PolymarketRestingFill?>(polymarketRestingFillsProvider,
          (_, f) {
        if (f != null) fills.add(f);
      });
    }
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
      container.read(pendingPolymarketBetProvider.notifier).setIntent(
          receiptShares == null
              ? prepared
              : prepared.copyWith(filledShares: receiptShares));
      final review = controller.reviewIntent(prepared)!;
      final grant = AuthGrants.issue(review, method: AuthGrantMethod.allowance);
      await controller.place('usdc', grant: grant);
    },
        () => MockClient((req) async => req.url.path == '/book'
            ? http.Response(jsonEncode(book ?? _book()), 200)
            : http.Response('offline', 503)));
    // A list read after the placement that no longer carries the order:
    // its record is read (it filled whole, 10 shares).
    if (fills != null) {
      trading.state = AsyncData(trading.state.requireValue
          .copyWith(openOrders: const <Order>[]));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return (
      error: error,
      trading: trading,
      pending: container.read(pendingPolymarketBetProvider)
    );
  }

  group('a resting buy registered for its fills (the controller path)', () {
    final live = {
      'success': true,
      'status': 'live',
      'orderID': '0x${'a' * 64}',
    };
    setUp(() => PolymarketRestingFillsNotifier.lookup =
        (ref, id) async => {'status': 'MATCHED', 'size_matched': '10'});

    test(
        'counted from the larger of the settlement and the receipt: the '
        'toast says only the shares beyond what the receipt said', () async {
      final fills = <PolymarketRestingFill>[];
      // 10 shares at 50c; the receipt already said 4 bought on arrival.
      await run(_limit(5, 0.5), answer: live, receiptShares: 4, fills: fills);
      expect(fills.single.orderId, live['orderID']);
      expect(fills.single.filledShares, 6);
    });

    test('placed while the wallet switched: never registered on the next',
        () async {
      final fills = <PolymarketRestingFill>[];
      await run(_limit(5, 0.5),
          answer: live, switchTo: '0xother', fills: fills);
      expect(fills, isEmpty);
    });
  });

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

  const market = PendingBetIntent(
      tokenId: _token,
      amount: 4,
      slippagePct: 5,
      marketQuestion: 'Will it rain?',
      outcomeName: 'Yes',
      expectedPrice: 0.6);

  group('P5: open orders that could not be read', () {
    test('a failed read keeps the account\'s last list; none known is none',
        () {
      final previous = PolymarketTradingState(openOrders: [_buy('10', '0.3')]);
      expect(polymarketOrdersAfterRead(read: null, previous: previous),
          previous.openOrders);
      expect(
          polymarketOrdersAfterRead(read: const [], previous: previous), isEmpty);
      // A cold boot (no cache) whose orders read failed: nothing reserved,
      // exactly as before; the venue's own refusal is the guard.
      expect(polymarketOrdersAfterRead(read: null, previous: null), isEmpty);
    });

    test(
        'a cold boot with no cache, or an orders read that keeps failing: a '
        'plain market buy is placed', () async {
      // The state such a boot reaches: a balance, no orders list.
      final r = await run(market, balance: 5);
      expect(r.error, isNull);
      expect(r.trading.placed, hasLength(1));
      // Reached the venue: the fake stops it there, after every check.
      expect(r.trading.placed.single.size, greaterThan(0));
    });

    test(
        'an account with a resting buy whose read fails keeps that reserve: '
        'a stake that fits the balance but not what is free stops before '
        'signing; without the buy the same stake is placed', () async {
      // \$5 held, \$3 reserved by a resting buy (10 at 30c) kept from the
      // last list: \$2 free, so \$4 does not fit.
      final held = await run(market, balance: 5, orders: [_buy('10', '0.30')]);
      expect(held.trading.placed, isEmpty);
      expect(held.pending?.status, PendingBetStatus.failed);
      final free = await run(market, balance: 5);
      expect(free.trading.placed, hasLength(1));
    });
  });

  group('a plain market buy (Advanced off)', () {
    test('its fee ceiling is sized inside 1c-99c, as before limits', () {
      const terms = PolymarketFeeTerms.worstCase;
      const high = PendingBetIntent(
          tokenId: _token,
          amount: 20,
          slippagePct: 5,
          marketQuestion: 'q',
          outcomeName: 'Yes',
          expectedPrice: 0.995);
      expect(PolymarketBetController.allInMax(high),
          terms.allInCost(20, 0.99));
      const low = PendingBetIntent(
          tokenId: _token,
          amount: 20,
          slippagePct: 5,
          marketQuestion: 'q',
          outcomeName: 'Yes',
          expectedPrice: 0.004);
      expect(PolymarketBetController.allInMax(low), terms.allInCost(20, 0.01));
      // The slip's figure (what a funding move is sized on): the shown
      // price plus slippage, inside 1c-99c.
      expect(
          betSlipWorstFeePrice(limitPrice: null, shown: 0.97, slippagePct: 5),
          0.99);
      expect(
          betSlipWorstFeePrice(limitPrice: null, shown: 0.5, slippagePct: 5),
          closeTo(0.525, 1e-12));
      expect(
          betSlipWorstFeePrice(limitPrice: null, shown: 0.002, slippagePct: 5),
          0.01);
      // A limit at its own price, under 1c on a 0.1c market.
      expect(
          betSlipWorstFeePrice(limitPrice: 0.005, shown: 0.5, slippagePct: 5),
          0.005);
    });
  });

  group('a funded or queued limit (the autofire posts it)', () {
    const terms = PolymarketFeeTerms.worstCase;

    test(
        'it posts the size checked before Confirm: the minimum stake at 28c '
        'is 5.00 shares even when the cash landed a hair over it', () {
      // The old sizing: min(stake, 99% of the cash) = 1.3959 -> 4.98.
      final r =
          autofireLimitOrder(amount: 1.40, balance: 1.41, price: 0.28, feeTerms: terms);
      expect(r.shares, 5.0);
      expect(
          polymarketMeetsMinimumShares(r.shares, kPolymarketDefaultMinOrderShares),
          isTrue);
    });

    test(
        'its fee reserve is what the cash carries past the cost, so the '
        'collateral wait can always end', () {
      final tight =
          autofireLimitOrder(amount: 1.40, balance: 1.41, price: 0.28, feeTerms: terms);
      expect(tight.feeReserveUsd, closeTo(0.01, 1e-9));
      expect(5.0 * 0.28 + tight.feeReserveUsd, lessThanOrEqualTo(1.41 + 1e-9));
      final ample =
          autofireLimitOrder(amount: 10, balance: 20, price: 0.5, feeTerms: terms);
      expect(ample.feeReserveUsd,
          terms.feeCeilingForNotional(ample.shares * 0.5, 0.5));
    });
  });
}
