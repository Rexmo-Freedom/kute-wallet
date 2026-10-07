// A market buy against a book that cannot fill it within the price cap
// (an Up/Down window's last minute, when sellers pull out). The owner saw
// "There are not enough shares available at this price" for $8 with $36
// available: the fill-and-kill was killed for want of sellers under the
// cap and the slip said nothing more. Now the book's own figures are said:
// what fills within the approved price, or where the price went. Fakes
// only: nothing is signed or sent.
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
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show OrderSide, OrderType;

const _token = '1234';
const _noMatch = 'no orders found to match with FAK order. FAK orders are '
    'partially filled or killed if no match is found.';

class _Trading extends PolymarketTradingNotifier {
  _Trading(this.refusal);
  final String refusal;
  final orders = <double>[];

  @override
  Future<PolymarketTradingState> build() async => const PolymarketTradingState(
      usdcBalance: 100, proxyWalletAddress: '0xdeposit');

  @override
  String? get signingWalletId => 'spending';

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
    orders.add(price);
    throw PolymarketOrderNotAcceptedException(refusal);
  }
}

Map<String, dynamic> _book(List<(String, String)> asks) => {
      'market': 'm',
      'asset_id': _token,
      'tick_size': '0.01',
      'neg_risk': false,
      'min_order_size': '1',
      'asks': [
        for (final (p, s) in asks) {'price': p, 'size': s}
      ],
      'bids': [
        {'price': '0.30', 'size': '100'}
      ],
    };

/// Serves [books] in turn for each book read (the last one repeats); any
/// other request (fee terms) is offline, so the documented maxima apply.
MockClient _venue(List<Map<String, dynamic>> books) {
  var reads = 0;
  return MockClient((req) async {
    if (req.url.path == '/book') {
      final book = books[reads < books.length ? reads : books.length - 1];
      reads++;
      return http.Response(jsonEncode(book), 200);
    }
    return http.Response('offline', 503);
  });
}

PendingBetIntent _intent(double amount, {double? spendAll}) => PendingBetIntent(
      tokenId: _token,
      amount: amount,
      slippagePct: 5,
      marketQuestion: 'Bitcoin Up or Down',
      outcomeName: 'Down',
      expectedPrice: 0.4,
      spendAllBudgetUsd: spendAll,
    );

void main() {
  ProviderContainer containerWith(_Trading trading) {
    final container = ProviderContainer(overrides: [
      polymarketTradingProvider.overrideWith(() => trading),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('the quote says what the asks within its cap add up to', () {
    final quote = PolymarketMarketBuyQuote.fromBook(
        parsePolymarketOrderBook(_book([('0.40', '10'), ('0.60', '100')])),
        tokenId: _token,
        amount: 8,
        slippagePct: 5);
    // $4 at 40¢; the $60 at 60¢ sits under the 63¢ cap the walk reached.
    expect(quote.price, 0.60);
    expect(quote.fillableUsd, closeTo(64, 1e-9));
    final thin = PolymarketMarketBuyQuote.fromBook(
        parsePolymarketOrderBook(_book([('0.40', '10')])),
        tokenId: _token,
        amount: 8,
        slippagePct: 5);
    expect(thin.fillableUsd, closeTo(4, 1e-9));
    expect(
        polymarketDepthWithin(
            parsePolymarketOrderBook(_book([('0.40', '10'), ('0.60', '100')])),
            0.5),
        closeTo(4, 1e-9));
  });

  test('a Max stake takes what fills when the book is thinner than it',
      () async {
    final trading = _Trading(_noMatch);
    final container = containerWith(trading);
    await container.read(polymarketTradingProvider.future);
    final venue = _venue([
      _book([('0.40', '10')])
    ]);
    final prepared = await http.runWithClient(
        () => container
            .read(polymarketBetControllerProvider)
            .prepareIntent(_intent(50, spendAll: 50)),
        () => venue);
    expect(prepared.amount, 4.0);
    expect(prepared.marketQuote!.fillableUsd,
        greaterThanOrEqualTo(prepared.amount));
  });

  test('a typed stake keeps its amount; the quote shows it cannot fill',
      () async {
    final trading = _Trading(_noMatch);
    final container = containerWith(trading);
    await container.read(polymarketTradingProvider.future);
    final venue = _venue([
      _book([('0.40', '10')])
    ]);
    final prepared = await http.runWithClient(
        () => container
            .read(polymarketBetControllerProvider)
            .prepareIntent(_intent(8)),
        () => venue);
    expect(prepared.amount, 8);
    expect(prepared.marketQuote!.fillableUsd, lessThan(8));
  });

  group('a killed fill-and-kill says what the book holds now', () {
    Future<(String?, _Trading)> placeAgainst(List<Map<String, dynamic>> books,
        {String refusal = _noMatch}) async {
      final trading = _Trading(refusal);
      final container = containerWith(trading);
      await container.read(polymarketTradingProvider.future);
      final controller = container.read(polymarketBetControllerProvider);
      // One venue for every client the code opens, so book reads go in turn.
      final venue = _venue(books);
      await http.runWithClient(() async {
        final prepared = await controller.prepareIntent(_intent(8));
        container
            .read(pendingPolymarketBetProvider.notifier)
            .setIntent(prepared);
        final review = controller.reviewIntent(prepared)!;
        final grant =
            AuthGrants.issue(review, method: AuthGrantMethod.allowance);
        await controller.place('usdc', grant: grant);
      }, () => venue);
      final pending = container.read(pendingPolymarketBetProvider);
      expect(pending?.status, PendingBetStatus.failed);
      return (pending?.errorMessage, trading);
    }

    final l10n = l10nForLanguage('en');

    test('some sellers left within the approved price: what fills', () async {
      // Quoted at 40¢ (cap 42¢), still 40¢ when signed; by the post the
      // book moved: $4.20 at 42¢ is all that is left under the cap.
      final (message, trading) = await placeAgainst([
        _book([('0.40', '100')]),
        _book([('0.40', '100')]),
        _book([('0.42', '10'), ('0.70', '100')]),
      ]);
      expect(trading.orders, hasLength(1));
      expect(message, l10n.betBuyFillsUpTo(r'$4.20'));
    });

    test('nothing left within it: where the price went', () async {
      final (message, trading) = await placeAgainst([
        _book([('0.40', '100')]),
        _book([('0.40', '100')]),
        _book([('0.70', '100')]),
      ]);
      expect(trading.orders, hasLength(1));
      expect(message, l10n.betBuyPriceMoved('70¢', '42¢'));
    });

    test('still killed after the retry inside the approval: same figures',
        () async {
      final (message, trading) = await placeAgainst([
        _book([('0.40', '100')]),
        _book([('0.40', '100')]),
        _book([('0.41', '100')]),
        _book([('0.70', '100')]),
      ]);
      expect(trading.orders, hasLength(2));
      expect(message, l10n.betBuyPriceMoved('70¢', '42¢'));
    });

    test('a balance refusal is never called a liquidity problem', () async {
      final (message, _) = await placeAgainst([
        _book([('0.40', '100')]),
        _book([('0.40', '100')]),
        _book([('0.70', '100')]),
      ],
          refusal: 'not enough balance / allowance: the balance is not enough '
              '-> balance: 0, order amount: 8000000');
      expect(message, l10n.betAddFundsToPredict);
    });
  });
}
