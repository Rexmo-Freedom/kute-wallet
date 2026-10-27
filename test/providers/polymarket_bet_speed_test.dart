// From tapping Place to the receipt, with the slip already warm. The slip
// shows fee terms from the minute cache and streams the market's book, so
// the tap has nothing to fetch: the quote and the send-time price come
// from the live book, neg-risk and the increment from the saved market
// terms, the order is built while the approval is on screen, success is
// shown the moment the venue says "matched" (settlement finishes behind
// it), and the timeline is sent for the successful bet. Fakes only:
// nothing is signed or sent.
import 'dart:convert';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_bet_controller.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/market_terms_store.dart';
import 'package:kute/services/polymarket/placement_timeline.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show OrderSide, OrderType;

const _token = '1234';
final _orderId = '0x${'ab' * 32}';

class _Trading extends PolymarketTradingNotifier {
  final orders = <({double price, double size, bool negRisk})>[];
  var prefetches = 0;
  var balanceReads = 0;
  Map<String, dynamic> Function()? answer;

  @override
  Future<PolymarketTradingState> build() async => const PolymarketTradingState(
      usdcBalance: 100, proxyWalletAddress: '0xdeposit');

  @override
  String? get signingWalletId => 'spending';

  @override
  void prefetchOrderReads() => prefetches++;

  @override
  Future<void> refreshBalanceAfterMatch() async => balanceReads++;

  @override
  void refreshAfterSale() {}

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
    orders.add((price: price, size: size, negRisk: negRisk));
    final reply = answer;
    if (reply == null) throw StateError('stopped by the test');
    return reply();
  }
}

PolymarketBookMessage _feedBook(String ask, {String size = '100'}) =>
    PolymarketBookMessage.fromJson({
      'event_type': 'book',
      'asset_id': _token,
      'market': 'm',
      'asks': [
        {'price': ask, 'size': size}
      ],
      'bids': [
        {'price': '0.30', 'size': '100'}
      ],
      'hash': 'h',
    });

PolymarketWsMessage _askMoves(String from, String to) =>
    polymarketWsMessagesOf(jsonEncode({
      'event_type': 'price_change',
      'asset_id': _token,
      'price_changes': [
        {'price': from, 'size': '0', 'side': 'SELL'},
        {'price': to, 'size': '100', 'side': 'SELL'},
      ],
    })).single;

const _terms = PolymarketFeeTerms(
    rate: 0.05, exponent: 1, builderTakerBps: 20, builderMakerBps: 0);

PendingBetIntent _intent() => const PendingBetIntent(
      tokenId: _token,
      amount: 5,
      slippagePct: 5,
      marketQuestion: 'Bitcoin Up or Down',
      outcomeName: 'Down',
      expectedPrice: 0.4,
    );

void main() {
  // The success sound reaches for the audio plugin's channels: answered
  // here so its fire-and-forget init never lands as an unhandled error.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    for (final name in ['xyz.luan/audioplayers.global', 'xyz.luan/audioplayers']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (_) async => 1);
    }
  });
  late List<(String, Map<String, Object>?)> tracked;

  setUp(() {
    PolymarketFeeTerms.resetCacheForTest();
    PolymarketMarketTermsStore.resetForTest();
    PolymarketLiveBooks.instance.reset();
    tracked = [];
    TrackingService.debugTrackObserver = (event, params) =>
        tracked.add((event, params));
  });
  tearDown(() {
    TrackingService.debugTrackObserver = null;
    PolymarketFeeTerms.resetCacheForTest();
    PolymarketMarketTermsStore.resetForTest();
    PolymarketLiveBooks.instance.reset();
  });

  /// A slip open for a few seconds: fee terms shown from the minute
  /// cache, the market's book streaming, its terms saved.
  void warmSlip({bool negRisk = false, String ask = '0.40'}) {
    PolymarketFeeTerms.primeCacheForTest(_token, _terms);
    PolymarketMarketTermsStore.save(_token,
        negRisk: negRisk, tickSize: '0.01');
    PolymarketLiveBooks.instance.debugSeed(_feedBook(ask));
  }

  Future<(ProviderContainer, PolymarketBetController, _Trading)> boot() async {
    final trading = _Trading();
    final container = ProviderContainer(overrides: [
      polymarketTradingProvider.overrideWith(() => trading),
    ]);
    addTearDown(container.dispose);
    container.listen(polymarketTradingProvider, (_, __) {});
    await container.read(polymarketTradingProvider.future);
    return (container, container.read(polymarketBetControllerProvider), trading);
  }

  /// Every request the tap would make, counted and refused.
  MockClient venue(List<String> paths) => MockClient((req) async {
        paths.add(req.url.path);
        return http.Response('offline', 503);
      });

  test('a warm slip: the tap fetches nothing, the quote is the live book',
      () async {
    warmSlip();
    final (_, controller, _) = await boot();
    final paths = <String>[];
    final prepared = await http.runWithClient(
        () => controller.prepareIntent(_intent()), () => venue(paths));
    expect(paths, isEmpty, reason: 'no fee-terms or REST book call');
    expect(controller.debugBookSource, 'feed');
    final quote = prepared.marketQuote!;
    expect(quote.bestAsk, 0.40);
    expect(quote.maxPrice, 0.42);
    expect(quote.tickSize, '0.01');
    expect(identical(prepared.feeTerms, _terms), isTrue);
    expect(quote.fees.rate, 0.05);
  });

  test('without a live book the REST book is read once and its terms saved',
      () async {
    PolymarketFeeTerms.primeCacheForTest(_token, _terms);
    final (_, controller, _) = await boot();
    final paths = <String>[];
    final prepared = await http.runWithClient(
        () => controller.prepareIntent(_intent()),
        () => MockClient((req) async {
              paths.add(req.url.path);
              return http.Response(
                  jsonEncode({
                    'market': 'm',
                    'asset_id': _token,
                    'tick_size': '0.01',
                    'neg_risk': true,
                    'asks': [
                      {'price': '0.40', 'size': '100'}
                    ],
                    'bids': [
                      {'price': '0.30', 'size': '100'}
                    ],
                  }),
                  200);
            }));
    expect(paths, ['/book']);
    expect(controller.debugBookSource, 'rest');
    expect(prepared.marketQuote?.negRisk, isTrue);
    // Saved for good: the next quote and the signing read it here.
    expect(PolymarketMarketTermsStore.read(_token)?.negRisk, isTrue);
    expect(PolymarketMarketTermsStore.currentTickSize(_token), '0.01');
  });

  test('neg-risk comes from the saved terms, into the quote and the order',
      () async {
    warmSlip(negRisk: true);
    final (container, controller, trading) = await boot();
    final prepared = await http.runWithClient(
        () => controller.prepareIntent(_intent()), () => venue([]));
    expect(prepared.marketQuote?.negRisk, isTrue);
    container.read(pendingPolymarketBetProvider.notifier).setIntent(prepared);
    final grant = AuthGrants.issue(controller.reviewIntent(prepared)!,
        method: AuthGrantMethod.allowance);
    await http.runWithClient(
        () => controller.place('usdc', grant: grant), () => venue([]));
    expect(trading.orders.single.negRisk, isTrue);
  });

  test('the live book prices the order at send time, no REST read', () async {
    warmSlip();
    final (container, controller, trading) = await boot();
    final paths = <String>[];
    await http.runWithClient(() async {
      final prepared = await controller.prepareIntent(_intent());
      container.read(pendingPolymarketBetProvider.notifier).setIntent(prepared);
      final review = controller.reviewIntent(prepared)!;
      controller.prefetchForSend(prepared);
      // The approval is on screen; the feed moves the best ask to 38¢.
      PolymarketLiveBooks.instance.apply(_askMoves('0.40', '0.38'));
      final grant = AuthGrants.issue(review, method: AuthGrantMethod.allowance);
      await controller.place('usdc', grant: grant);
    }, () => venue(paths));
    expect(paths, isEmpty);
    expect(trading.prefetches, 1);
    // Quoted at 40¢ (cap 42¢ approved); 38¢ when signed: cap 39¢.
    expect(trading.orders.single.price, 0.39);
  });

  test('the order built during the approval goes out as it was', () async {
    warmSlip();
    final (container, controller, trading) = await boot();
    await http.runWithClient(() async {
      final prepared = await controller.prepareIntent(_intent());
      container.read(pendingPolymarketBetProvider.notifier).setIntent(prepared);
      final review = controller.reviewIntent(prepared)!;
      controller.prefetchForSend(prepared);
      final plan = controller.debugPlan!;
      expect(plan.price, 0.42);
      expect(plan.shares, PolymarketOrderPlan.sharesFor(5, 0.42));
      expect(plan.tickSize, '0.01');
      final grant = AuthGrants.issue(review, method: AuthGrantMethod.allowance);
      await controller.place('usdc', grant: grant);
      expect(controller.debugPlanBuilds, 1, reason: 'reused, not rebuilt');
      expect(trading.orders.single.price, plan.price);
      expect(trading.orders.single.size, plan.shares);
    }, () => venue([]));
  });

  test('a send-time price other than the approved one builds a new plan',
      () async {
    warmSlip();
    final (container, controller, trading) = await boot();
    await http.runWithClient(() async {
      final prepared = await controller.prepareIntent(_intent());
      container.read(pendingPolymarketBetProvider.notifier).setIntent(prepared);
      final review = controller.reviewIntent(prepared)!;
      controller.prefetchForSend(prepared);
      PolymarketLiveBooks.instance.apply(_askMoves('0.40', '0.38'));
      final grant = AuthGrants.issue(review, method: AuthGrantMethod.allowance);
      await controller.place('usdc', grant: grant);
    }, () => venue([]));
    expect(controller.debugPlanBuilds, 2);
    expect(trading.orders.single.size, PolymarketOrderPlan.sharesFor(5, 0.39));
  });

  test('the one-dollar floor is met within the stake plus the rounding cent',
      () {
    // $1 at 0.42: 2.38 shares cost $0.9996; 2.39 cost $1.0038, within $1.01.
    expect(PolymarketOrderPlan.sharesFor(1, 0.42), 2.39);
    // $5 at 0.42: no bump needed.
    expect(PolymarketOrderPlan.sharesFor(5, 0.42), 11.9);
  });

  test('success is shown as the venue says matched; settlement follows '
      'behind it; the balance is read once at once; the timeline is sent',
      () async {
    warmSlip();
    final (container, controller, trading) = await boot();
    trading.answer = () => {
          'success': true,
          'status': 'matched',
          'orderID': _orderId,
          'makingAmount': '5',
          'takingAmount': '12.5',
        };
    PolymarketPlacementTimeline.begin();
    final clock = Stopwatch()..start();
    await http.runWithClient(() async {
      final prepared = await controller.prepareIntent(_intent());
      container.read(pendingPolymarketBetProvider.notifier).setIntent(prepared);
      final review = controller.reviewIntent(prepared)!;
      controller.prefetchForSend(prepared);
      final grant = AuthGrants.issue(review, method: AuthGrantMethod.allowance);
      // The slip's own confirmation fires the haptic, as for every market bet.
      await controller.place('usdc', grant: grant, successHaptic: false);
    }, () => venue([]));
    // Not held behind "Matched · confirming" (12 s of chain polling).
    expect(clock.elapsed, lessThan(const Duration(seconds: 3)));
    final pending = container.read(pendingPolymarketBetProvider)!;
    expect(pending.status, PendingBetStatus.done);
    expect(pending.filledShares, 12.5);
    expect(pending.filledCost, 5);
    expect(pending.orderedShares, PolymarketOrderPlan.sharesFor(5, 0.42));
    expect(trading.balanceReads, 1);

    final timeline =
        tracked.where((e) => e.$1 == 'polymarket_bet_timeline').toList();
    expect(timeline, hasLength(1));
    final params = timeline.single.$2!;
    expect(params['outcome'], 'filled');
    expect(params['ms_total'], isA<int>());
    expect(params['ms_matched'], isA<int>());
    expect(params['ms_fees'], isA<int>());
    expect(params['fees_source'], 'cached');
    expect(params['book_source'], 'feed');
    expect(params['send_book_source'], 'feed');
    expect(params.keys.where((k) => k.contains('id')), isEmpty);
  });

  test('a stopped placement sends the timeline too, as failed', () async {
    warmSlip();
    final (container, controller, _) = await boot();
    PolymarketPlacementTimeline.begin();
    await http.runWithClient(() async {
      final prepared = await controller.prepareIntent(_intent());
      container.read(pendingPolymarketBetProvider.notifier).setIntent(prepared);
      final grant = AuthGrants.issue(controller.reviewIntent(prepared)!,
          method: AuthGrantMethod.allowance);
      await controller.place('usdc', grant: grant);
    }, () => venue([]));
    final timeline =
        tracked.where((e) => e.$1 == 'polymarket_bet_timeline').toList();
    expect(timeline, hasLength(1));
    expect(timeline.single.$2!['outcome'], 'failed');
    expect(PolymarketPlacementTimeline.isActive, isFalse);
  });
}
