// The slip shows "available" as the balance less what resting BUY orders
// reserve, and the venue counts those reservations too; sizing and the
// pre-sign check used the whole balance, so a stake the slip said did not
// fit could still be signed and refused. Fakes only: nothing is signed.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/l10n/l10n.dart' show l10nForLanguage;
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_bet_controller.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/venue_collateral.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Order, OrderSide, OrderType;

const _token = '1234';

Order _buy(String size, String price, {String matched = '0'}) => Order(
    id: 'o',
    market: 'm',
    assetId: 'a',
    owner: 'k',
    side: 'BUY',
    price: price,
    originalSize: size,
    sizeMatched: matched,
    outcome: 'Yes');

class _Trading extends PolymarketTradingNotifier {
  _Trading({this.reads, this.changeAccountOnRead = false});
  final PolyBuyReads? reads;
  final bool changeAccountOnRead;
  int generation = 0;
  @override
  int get accountGeneration => generation;
  @override
  Future<PolyBuyReads?> readBuyReadiness({bool refreshVenue = false}) async {
    expect(refreshVenue, isTrue);
    if (changeAccountOnRead) generation++;
    return reads;
  }

  final orders = <double>[];

  @override
  Future<PolymarketTradingState> build() async => PolymarketTradingState(
      usdcBalance: 8.13,
      proxyWalletAddress: '0xdeposit',
      // A resting limit buy reserves 10 × 0.30 = $3.00.
      openOrders: [_buy('10', '0.30')]);

  @override
  String? get signingWalletId => 'spending';

  @override
  void prefetchOrderReads() {}

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
    orders.add(size * price);
    throw StateError('stopped by the test');
  }
}

Map<String, dynamic> _book() => {
      'market': 'm',
      'asset_id': _token,
      'tick_size': '0.01',
      'neg_risk': true,
      'min_order_size': '1',
      'asks': [
        {'price': '0.61', 'size': '1000'}
      ],
      'bids': [
        {'price': '0.30', 'size': '100'}
      ],
    };

void main() {
  test('resting BUY orders are taken off the balance, filled parts are not',
      () {
    expect(
        PolymarketBetController.spendableUsdc(
            8.13, [_buy('10', '0.30'), _buy('10', '0.50', matched: '4')]),
        closeTo(8.13 - 3.0 - 3.0, 1e-9));
    expect(PolymarketBetController.spendableUsdc(1, [_buy('10', '0.50')]), 0);
  });

  Future<(PendingBetIntent?, PendingBetIntent, _Trading)> run(
      PendingBetIntent intent,
      {bool fresh = false,
      PolyBuyReads? reads,
      bool changeAccountOnRead = false}) async {
    final trading =
        _Trading(reads: reads, changeAccountOnRead: changeAccountOnRead);
    final container = ProviderContainer(overrides: [
      polymarketTradingProvider.overrideWith(() => trading),
    ]);
    addTearDown(container.dispose);
    container.listen(polymarketTradingProvider, (_, __) {});
    await container.read(polymarketTradingProvider.future);
    final controller = container.read(polymarketBetControllerProvider);
    late PendingBetIntent prepared;
    await http.runWithClient(() async {
      prepared =
          await controller.prepareIntent(intent, requireFreshCollateral: fresh);
      container.read(pendingPolymarketBetProvider.notifier).setIntent(prepared);
      final review = controller.reviewIntent(prepared)!;
      final grant = AuthGrants.issue(review, method: AuthGrantMethod.allowance);
      await controller.place('usdc',
          grant: grant, requireFreshCollateral: fresh);
    },
        () => MockClient((req) async => req.url.path == '/book'
            ? http.Response(jsonEncode(_book()), 200)
            : http.Response('offline', 503)));
    return (container.read(pendingPolymarketBetProvider), prepared, trading);
  }

  test(
      'a typed stake that fits the balance but not what is available stops '
      'before signing', () async {
    // $5.13 available; $5 plus its fee reserve does not fit.
    final (pending, _, trading) = await run(const PendingBetIntent(
        tokenId: _token,
        amount: 5,
        slippagePct: 5,
        marketQuestion: 'Portugal vs. Northern Ireland',
        outcomeName: 'Portugal',
        expectedPrice: 0.61));
    expect(trading.orders, isEmpty);
    expect(pending?.status, PendingBetStatus.failed);
    expect(pending?.errorMessage, l10nForLanguage('en').betAddFundsToPredict);
  });

  test('Max is fitted to what is available, stake plus fees included',
      () async {
    final (_, prepared, trading) = await run(const PendingBetIntent(
        tokenId: _token,
        amount: 8.13,
        slippagePct: 5,
        marketQuestion: 'Portugal vs. Northern Ireland',
        outcomeName: 'Portugal',
        expectedPrice: 0.61,
        spendAllBudgetUsd: 8.13));
    expect(prepared.marketQuote!.allInMax, lessThanOrEqualTo(5.13 + 1e-9));
    expect(prepared.amount, greaterThan(4.5));
    // Signed, and never above the fitted stake plus the rounding cent.
    expect(trading.orders.single,
        lessThanOrEqualTo(prepared.amount + 0.01 + 1e-9));
  });
  PolyBuyReads cash(double pusd, {double? venue, double usdce = 0}) => (
        pusd: BigInt.from((pusd * 1e6).round()),
        usdce: BigInt.from((usdce * 1e6).round()),
        setupDone: true,
        venue: PolyVenueCount(
            balance: BigInt.from(((venue ?? pusd) * 1e6).round())),
      );
  const prefunded = PendingBetIntent(
      tokenId: _token,
      amount: 5,
      slippagePct: 5,
      marketQuestion: 'Bitcoin Up or Down',
      outcomeName: 'Up',
      expectedPrice: 0.61);

  test('prefunded bet reaches placement using fresh cash despite stale display',
      () async {
    final (_, _, trading) = await run(prefunded, fresh: true, reads: cash(20));
    expect(trading.orders, hasLength(1));
  });

  test(
      'prefunded bet cannot use unconverted cash, stale venue count or reservations',
      () async {
    for (final reads in [
      cash(0, usdce: 20),
      cash(20, venue: 2),
      cash(8.13),
      null
    ]) {
      final (pending, _, trading) =
          await run(prefunded, fresh: true, reads: reads);
      expect(trading.orders, isEmpty);
      expect(pending?.status, PendingBetStatus.failed);
    }
  });

  test('prefunded Max sizes against fresh spendable cash', () async {
    final (_, prepared, trading) = await run(
        const PendingBetIntent(tokenId: _token, amount: 20, spendAllBudgetUsd: 20,
            slippagePct: 5, marketQuestion: 'Bitcoin Up or Down',
            outcomeName: 'Up', expectedPrice: 0.61),
        fresh: true,
        reads: cash(20));
    expect(prepared.marketQuote!.allInMax, lessThanOrEqualTo(17 + 1e-9));
    expect(prepared.amount, greaterThan(15));
    expect(trading.orders, hasLength(1));
  });

  test('account generation change during fresh read refuses before placement',
      () async {
    final (pending, _, trading) = await run(prefunded,
        fresh: true, reads: cash(20), changeAccountOnRead: true);
    expect(trading.orders, isEmpty);
    expect(pending?.status, PendingBetStatus.failed);
  });
}
