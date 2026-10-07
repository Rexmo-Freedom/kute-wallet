// The owner's $5 on DOWN in a five-minute round's last two minutes ended
// on "The price moved to 84¢, past your limit of 81¢": the cap came from a
// book read before the approval, and the order went out seconds later.
// Now the book is read again as the approval returns (prefetched while it
// is on screen), the order is priced from it under the approved maximum,
// and a price past that maximum stops before anything is signed, with the
// new maximum offered as the retry. Fakes only: nothing is signed or sent.
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/l10n/l10n.dart' show l10nForLanguage;
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_bet_controller.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/ledger/polymarket/ledger_pm_support.dart';
import 'package:kute/services/polymarket/ledger_pm_trade.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/polymarket_slippage_defaults.dart';
import 'package:kute/services/polymarket/send_time_read.dart';
import 'package:kute/services/polymarket/usdce_wrap_gate.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show OrderSide, OrderType;

const _token = '1234';

/// Records each order (price, and whether it carried fresh terms) and
/// stops it there, ending the placement without a retry.
class _Trading extends PolymarketTradingNotifier {
  final orders = <double>[];
  final freshTerms = <bool>[];
  var prefetches = 0;

  @override
  Future<PolymarketTradingState> build() async => const PolymarketTradingState(
      usdcBalance: 100, proxyWalletAddress: '0xdeposit');

  @override
  String? get signingWalletId => 'spending';

  @override
  void prefetchOrderReads() => prefetches++;

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
    freshTerms.add(marketQuote?.hasFreshTerms == true);
    // Not a venue refusal: ends the placement with no retry rung.
    throw StateError('stopped by the test');
  }
}

Map<String, dynamic> _book(String ask, {String size = '100'}) => {
      'market': 'm',
      'asset_id': _token,
      'tick_size': '0.01',
      'neg_risk': false,
      'min_order_size': '1',
      'asks': [
        {'price': ask, 'size': size}
      ],
      'bids': [
        {'price': '0.30', 'size': '100'}
      ],
    };

PendingBetIntent _intent() => const PendingBetIntent(
      tokenId: _token,
      amount: 5,
      slippagePct: 5,
      marketQuestion: 'Bitcoin Up or Down',
      outcomeName: 'Down',
      expectedPrice: 0.4,
    );

void main() {
  final l10n = l10nForLanguage('en');

  /// Prepares at [books]' first book, approves the quote's cap, then
  /// places; every later book read gets the next book (the last repeats).
  Future<(PendingBetIntent?, _Trading, int)> run(
      List<Map<String, dynamic>> books,
      {bool prefetch = false}) async {
    final trading = _Trading();
    final container = ProviderContainer(overrides: [
      polymarketTradingProvider.overrideWith(() => trading),
    ]);
    addTearDown(container.dispose);
    // Held open the way the slip holds it while the approval is up.
    container.listen(polymarketTradingProvider, (_, __) {});
    await container.read(polymarketTradingProvider.future);
    final controller = container.read(polymarketBetControllerProvider);
    var reads = 0;
    final venue = MockClient((req) async {
      if (req.url.path == '/book') {
        final book = books[reads < books.length ? reads : books.length - 1];
        reads++;
        return http.Response(jsonEncode(book), 200);
      }
      return http.Response('offline', 503);
    });
    await http.runWithClient(() async {
      final prepared = await controller.prepareIntent(_intent());
      container.read(pendingPolymarketBetProvider.notifier).setIntent(prepared);
      final review = controller.reviewIntent(prepared)!;
      if (prefetch) {
        controller.prefetchForSend(prepared);
        // The approval is on screen while the book is read.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      final grant = AuthGrants.issue(review, method: AuthGrantMethod.allowance);
      await controller.place('usdc', grant: grant);
    }, () => venue);
    return (container.read(pendingPolymarketBetProvider), trading, reads);
  }

  group('the order is priced from the book at send time', () {
    test('a lower ask at send: the fresh cap is used, under the approval',
        () async {
      // Quoted at 40¢ (cap 42¢ approved); 38¢ when signed: cap 39¢.
      final (_, trading, reads) = await run([_book('0.40'), _book('0.38')]);
      expect(reads, 2);
      expect(trading.orders, [0.39]);
      // Signed from the fresh quote: no negRisk / tick refetch.
      expect(trading.freshTerms, [true]);
    });

    test('moved but within the approved maximum: placed, no second prompt',
        () async {
      // 41¢ at send: its own cap would be 43¢, the approval says 42¢.
      final (pending, trading, _) =
          await run([_book('0.40'), _book('0.41')]);
      expect(trading.orders, [0.42]);
      expect(pending?.retryMaxPrice, isNull);
    });

    test('past the approved maximum: nothing is signed, retry at the new max',
        () async {
      final (pending, trading, _) =
          await run([_book('0.40'), _book('0.70')]);
      expect(trading.orders, isEmpty);
      expect(pending?.status, PendingBetStatus.failed);
      expect(pending?.errorMessage, l10n.betBuyPriceMoved('70¢', '42¢'));
      // 70¢ + 5% = 73.5¢, rounded down: what "Retry at 73¢" will approve.
      expect(pending?.retryMaxPrice, 0.73);
    });

    test('the prefetched book is used when the approval returns', () async {
      final (pending, trading, reads) =
          await run([_book('0.40'), _book('0.38')], prefetch: true);
      expect(trading.prefetches, 1);
      expect(trading.orders, [0.39]);
      // Prepare + the prefetch (still fresh at send): no read after it.
      expect(reads, 2);
    });

    test('an unreadable book at send keeps the prepared quote', () {
      final quote = PolymarketMarketBuyQuote.fromBook(
          parsePolymarketOrderBook(_book('0.40')),
          tokenId: _token,
          amount: 5,
          slippagePct: 5);
      expect(
          PolymarketBetController.sendTimeQuote(quote, null,
              approvedPrice: 0.42, slippagePct: 5),
          same(quote));
    });
  });

  group('the send-time read', () {
    test('hands out a value at most maxAge old, else reads again', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime(2026, 10, 7));
        var n = 0;
        final read = PolymarketSendTimeRead<int>(() async => ++n,
            maxAge: const Duration(seconds: 1), clock: clock.now)
          ..start();
        async.flushMicrotasks();
        int? got;
        read.take().then((v) => got = v);
        async.flushMicrotasks();
        expect(got, 1);
        expect(read.reads, 1);
        async.elapse(const Duration(seconds: 2));
        read.take().then((v) => got = v);
        async.flushMicrotasks();
        expect(got, 2);
        expect(read.reads, 2);
      });
    });

    test('keeps refreshing while the approval is open, then stops', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime(2026, 10, 7));
        var n = 0;
        final read = PolymarketSendTimeRead<int>(() async => ++n,
            maxAge: const Duration(seconds: 1),
            refreshEvery: const Duration(milliseconds: 700),
            clock: clock.now)
          ..start();
        // A 2.5 s biometric prompt: the value is never more than ~0.7 s old.
        async.elapse(const Duration(milliseconds: 2500));
        final before = read.reads;
        expect(before, greaterThanOrEqualTo(4));
        int? got;
        read.take().then((v) => got = v);
        async.flushMicrotasks();
        expect(got, n);
        expect(read.reads, before);
        async.elapse(const Duration(seconds: 5));
        expect(read.reads, before);
      });
    });
  });

  test('funds already in pUSD: no conversion before the order, so no '
      'balance refresh either', () {
    // pUSD covers the $5 stake at 42¢: nothing to wrap, and the venue's
    // balance refresh only follows a wrap (or a balance refusal).
    final cost = polyBuyCostMicros(size: 11.9, price: 0.42);
    expect(
        polyShouldWrapBeforeBuy(
            pusd: BigInt.from(36000000), usdce: BigInt.from(5000000),
            costMicros: cost),
        isFalse);
    // Only a short pUSD balance with USDC.e to cover it converts.
    expect(
        polyShouldWrapBeforeBuy(
            pusd: BigInt.from(1000000), usdce: BigInt.from(9000000),
            costMicros: cost),
        isTrue);
  });

  group('fast rounds start with more room', () {
    final now = DateTime(2026, 10, 7, 12);
    test('5- and 15-minute Up or Down: 10%, 12% in the last minute', () {
      expect(
          polymarketDefaultSlippagePct(
              slug: 'btc-updown-5m-1760000000',
              endAt: now.add(const Duration(minutes: 2)),
              now: now),
          10);
      expect(
          polymarketDefaultSlippagePct(
              slug: 'eth-updown-15m-1760000000',
              endAt: now.add(const Duration(seconds: 45)),
              now: now),
          12);
      // No slug: an Up or Down market closing within 15 minutes.
      expect(
          polymarketDefaultSlippagePct(
              question: 'Bitcoin Up or Down - October 7, 12:00PM ET',
              endAt: now.add(const Duration(minutes: 9)),
              now: now),
          10);
    });

    test('every other market keeps 5%', () {
      expect(
          polymarketDefaultSlippagePct(
              slug: 'will-it-rain-tomorrow',
              question: 'Will it rain tomorrow?',
              endAt: now.add(const Duration(minutes: 5)),
              now: now),
          5);
      expect(
          polymarketDefaultSlippagePct(
              question: 'Bitcoin Up or Down on October 8?',
              endAt: now.add(const Duration(hours: 20)),
              now: now),
          5);
    });

    test('the wider room is the maximum price the slip shows', () {
      // A 77¢ ask in a fast round: 10% gives an 84¢ maximum, enough for
      // the owner's 81¢ -> 84¢ move; 5% gave 80¢.
      expect(polymarketBuyCap(ask: 0.77, slippagePct: 10, tick: 0.01), 0.84);
      expect(polymarketBuyCap(ask: 0.77, slippagePct: 5, tick: 0.01), 0.80);
    });
  });

  group('sells mirror it', () {
    test('a bid still at or above the approved floor: the fresh floor', () {
      // Approved at a 60c bid (floor 57c); 62c at send: floor 59c.
      expect(
          polymarketSellSendPrice(
              approvedFloor: 0.57, freshBid: 0.62, slippagePct: 5, tick: 0.01),
          0.59);
      // 58c at send: its floor (55c) is under the approval, so 57c.
      expect(
          polymarketSellSendPrice(
              approvedFloor: 0.57, freshBid: 0.58, slippagePct: 5, tick: 0.01),
          0.57);
      // Unread: the approved floor.
      expect(
          polymarketSellSendPrice(
              approvedFloor: 0.57, freshBid: null, slippagePct: 5, tick: 0.01),
          0.57);
    });

    test('a bid under the approved floor: nothing is sold, retry offered', () {
      expect(
          () => polymarketSellSendPrice(
              approvedFloor: 0.57, freshBid: 0.50, slippagePct: 5, tick: 0.01),
          throwsA(isA<PolymarketSellPriceMoved>()
              .having((e) => e.price, 'price', 0.50)
              .having((e) => e.limit, 'limit', 0.57)
              .having((e) => e.retryPrice, 'retry', 0.48)));
      expect(l10n.betSellPriceMoved('50¢', '57¢'), contains('nothing was sold'));
    });
  });

  group('the Ledger path', () {
    LedgerPmMarketRules rules(String ask) => LedgerPmMarketRules(
        tokenId: '1',
        conditionId: '0x${'a' * 64}',
        tickSize: '0.01',
        minShares: BigInt.from(1),
        negRisk: false,
        asks: LedgerPmMarketSource.parseAsks([
          {'price': ask, 'size': '100'}
        ]));

    test('still fills within the signed maximum: sent', () {
      rules('0.41').ensureFillsWithin(
          budgetUsd: 5, maxPriceMicros: BigInt.from(420000), slippagePct: 5);
    });

    test('past it: nothing sent, the new maximum offered', () {
      expect(
          () => rules('0.70').ensureFillsWithin(
              budgetUsd: 5,
              maxPriceMicros: BigInt.from(420000),
              slippagePct: 5),
          throwsA(isA<LedgerPmTradeRefused>()
              .having((e) => e.reason, 'reason',
                  LedgerPmTradeRefusal.priceMoved)
              .having((e) => e.price, 'price', 0.70)
              .having((e) => e.limit, 'limit', 0.42)
              .having((e) => e.retryPrice, 'retry', 0.73)));
    });

    test('nothing for sale: liquidity unavailable', () {
      expect(
          () => LedgerPmMarketRules(
                  tokenId: '1',
                  conditionId: 'c',
                  tickSize: '0.01',
                  minShares: BigInt.one,
                  negRisk: false)
              .ensureFillsWithin(
                  budgetUsd: 5,
                  maxPriceMicros: BigInt.from(420000),
                  slippagePct: 5),
          throwsA(isA<LedgerPmTradeRefused>().having((e) => e.reason,
              'reason', LedgerPmTradeRefusal.liquidityUnavailable)));
    });

    test('the Ledger sell floor uses the same rule', () {
      expect(
          buildLedgerPmSellQuote(
                  shares: 10, bestBid: 0.12, tickSize: '0.01', slippage: 0.05)!
              .price,
          0.11);
    });
  });
}
