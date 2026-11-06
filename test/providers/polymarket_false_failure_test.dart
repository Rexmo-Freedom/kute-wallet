// Founder, on device: "sometimes the predictions say failed, and they
// don't actually fail". The placement paths that could end a placed
// prediction as failed, or as "check your positions" when the venue had
// the answer, each reproduced here with fakes (nothing is signed or sent):
//
//  * an order whose answer proved nothing (a timeout, a dropped
//    connection, a 5xx after the venue took it) ended "pending" without
//    asking the venue; it is now looked up by its id first, and a match
//    shows the receipt with the venue's own figures;
//  * the venue took the order and the receipt's bookkeeping threw: that
//    ended as a failed prediction although the shares were bought.


import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/l10n/l10n.dart' show l10nForLanguage;
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_bet_controller.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/services/polymarket/hot_order_guard.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/market_terms_store.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show OrderSide, OrderType;

const _token = '1234';
final _orderId = '0x${'ab' * 32}';

/// The venue's order and trade reads, answered from [orders] in turn
/// (the last repeats; null is "no such order yet").
class _Backend extends PolymarketBackendService {
  _Backend(this.orders, {this.trade})
      : super(
            apiKey: 'k',
            secret: 'c2VjcmV0',
            passphrase: 'p',
            walletAddress: '0xeoa');
  final List<Map<String, dynamic>?> orders;
  final Map<String, dynamic>? trade;
  var orderReads = 0;

  @override
  Future<Map<String, dynamic>?> getOrderById(String orderId) async {
    expect(orderId, _orderId);
    final i = orderReads < orders.length ? orderReads : orders.length - 1;
    orderReads++;
    return orders[i];
  }

  @override
  Future<Map<String, dynamic>?> getTradeById(String tradeId) async => trade;
}

class _Trading extends PolymarketTradingNotifier {
  _Trading(this.answer, {this.backend, this.throwOnFill = false});
  final Map<String, dynamic> Function() answer;
  final _Backend? backend;
  final bool throwOnFill;
  var journalChecks = 0;

  @override
  Future<PolymarketTradingState> build() async => const PolymarketTradingState(
      usdcBalance: 100, proxyWalletAddress: '0xdeposit');

  @override
  String? get signingWalletId => 'spending';

  @override
  PolymarketBackendService? get backendService => backend;

  @override
  void prefetchOrderReads() {}

  @override
  Future<void> refreshBalanceAfterMatch() async {}

  @override
  void refreshAfterSale() {}

  @override
  Future<void> refresh() async {}

  @override
  void invalidateBalanceCache() {}

  @override
  Future<void> checkPendingOrder({String? tokenId}) async => journalChecks++;

  @override
  void notePendingFill({
    required String key,
    required String tokenId,
    required double shares,
    required double costUsd,
  }) {
    // A bookkeeping step after the match, made to throw.
    if (throwOnFill) throw StateError('bookkeeping broke');
  }

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
  }) async =>
      answer();
}

PolymarketBookMessage _feedBook(String ask) => PolymarketBookMessage.fromJson({
      'event_type': 'book',
      'asset_id': _token,
      'market': 'm',
      'asks': [
        {'price': ask, 'size': '100'}
      ],
      'bids': [
        {'price': '0.30', 'size': '100'}
      ],
      'hash': 'h',
    });

const _terms = PolymarketFeeTerms(
    rate: 0.05, exponent: 1, builderTakerBps: 20, builderMakerBps: 0);

PendingBetIntent _intent() => const PendingBetIntent(
      tokenId: _token,
      amount: 5,
      slippagePct: 5,
      marketQuestion: 'Lakers vs. Celtics',
      outcomeName: 'Lakers',
      expectedPrice: 0.4,
    );

/// The venue's order record once it matched 12.5 shares.
Map<String, dynamic> _matchedOrder() => {
      'id': _orderId,
      'status': 'MATCHED',
      'size_matched': '12.5',
      'original_size': '12.5',
      'associate_trades': ['t1'],
    };

/// The trade behind it, mined: 12.5 shares at 40¢ from one maker.
Map<String, dynamic> _minedTrade() => {
      'id': 't1',
      'status': 'MINED',
      'taker_order_id': _orderId,
      'maker_orders': [
        {
          'order_id': '0xmaker',
          'matched_amount': '12.5',
          'price': '0.40',
          'asset_id': _token,
        }
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    for (final name in ['xyz.luan/audioplayers.global', 'xyz.luan/audioplayers']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (_) async => 1);
    }
  });
  final l10n = l10nForLanguage('en');
  late List<(String, Map<String, Object>?)> events;

  setUp(() {
    PolymarketFeeTerms.resetCacheForTest();
    PolymarketMarketTermsStore.resetForTest();
    PolymarketLiveBooks.instance.reset();
    PolymarketFeeTerms.primeCacheForTest(_token, _terms);
    PolymarketMarketTermsStore.save(_token, negRisk: false, tickSize: '0.01');
    PolymarketLiveBooks.instance.debugSeed(_feedBook('0.40'));
    PolymarketBetController.reconcileWindow = const Duration(seconds: 3);
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });
  tearDown(() {
    TrackingService.debugTrackObserver = null;
    PolymarketBetController.reconcileWindow = const Duration(seconds: 20);
    PolymarketFeeTerms.resetCacheForTest();
    PolymarketMarketTermsStore.resetForTest();
    PolymarketLiveBooks.instance.reset();
  });

  /// Prepares, approves and places one $5 bet against [trading]; returns
  /// every status and stage the slip saw, and the end state.
  Future<
      ({
        PendingBetIntent? end,
        List<PendingBetStatus> statuses,
        List<PendingBetStage> stages,
      })> place(_Trading trading) async {
    final container = ProviderContainer(overrides: [
      polymarketTradingProvider.overrideWith(() => trading),
    ]);
    addTearDown(container.dispose);
    container.listen(polymarketTradingProvider, (_, __) {});
    await container.read(polymarketTradingProvider.future);
    final statuses = <PendingBetStatus>[];
    final stages = <PendingBetStage>[];
    container.listen<PendingBetIntent?>(pendingPolymarketBetProvider,
        (_, next) {
      if (next == null) return;
      statuses.add(next.status);
      stages.add(next.stage);
    });
    final controller = container.read(polymarketBetControllerProvider);
    await http.runWithClient(() async {
      final prepared = await controller.prepareIntent(_intent());
      container.read(pendingPolymarketBetProvider.notifier).setIntent(prepared);
      final grant = AuthGrants.issue(controller.reviewIntent(prepared)!,
          method: AuthGrantMethod.biometric);
      await controller.place('usdc', grant: grant, successHaptic: false);
    }, () => MockClient((_) async => http.Response('offline', 503)));
    return (
      end: container.read(pendingPolymarketBetProvider),
      statuses: statuses,
      stages: stages,
    );
  }

  Iterable<(String, Map<String, Object>?)> named(String event) =>
      events.where((e) => e.$1 == event);

  group('an order whose answer proved nothing is looked up first', () {
    test('matched at the venue: the receipt with the venue\'s figures',
        () async {
      // The POST timed out after the venue took it; the venue has not
      // filed it on the first read, then shows it matched.
      final backend = _Backend([null, _matchedOrder()], trade: _minedTrade());
      final trading = _Trading(
          () => throw PolymarketOrderOutcomeUnknown(orderId: _orderId),
          backend: backend);
      final r = await place(trading);
      // Before: ended awaitingConfirmation ("check your positions").
      expect(r.end?.status, PendingBetStatus.done);
      expect(r.end?.filledShares, 12.5);
      expect(r.end?.filledCost, closeTo(5.0, 1e-9));
      expect(r.statuses, isNot(contains(PendingBetStatus.failed)));
      expect(r.statuses, isNot(contains(PendingBetStatus.awaitingConfirmation)));
      // "Confirming with Polymarket…" while it was looked up.
      expect(r.stages, contains(PendingBetStage.reconciling));
      expect(named('polymarket_bet_failed'), isEmpty);
      // The fill reported once, from the venue's own cost (revenue).
      final placed = named('polymarket_bet_placed').single.$2!;
      expect(placed['amount_usd'], 5.0);
      expect(placed['price'], closeTo(0.40, 1e-9));
      final reconciled =
          named('polymarket_order_outcome_reconciled').single.$2!;
      expect(reconciled['outcome'], 'filled');
      expect(reconciled.values.join(' '), isNot(contains(_orderId)));
      // The order journal is settled from the venue's answer.
      expect(trading.journalChecks, 1);
    });

    test('killed with nothing bought: said so (the venue\'s answer)',
        () async {
      final backend = _Backend([
        {
          'id': _orderId,
          'status': 'CANCELED',
          'size_matched': '0',
          'original_size': '12.5',
        }
      ]);
      final r = await place(_Trading(
          () => throw PolymarketOrderOutcomeUnknown(orderId: _orderId),
          backend: backend));
      expect(r.end?.status, PendingBetStatus.failed);
      expect(r.end?.errorMessage, l10n.betBuyNotMatched);
      expect(named('polymarket_order_outcome_reconciled').single.$2!['outcome'],
          'not_filled');
    });

    test('never filed in the window: pending as before, never failed',
        () async {
      final backend = _Backend([null]);
      final r = await place(_Trading(
          () => throw PolymarketOrderOutcomeUnknown(orderId: _orderId),
          backend: backend));
      expect(r.end?.status, PendingBetStatus.awaitingConfirmation);
      expect(r.statuses, isNot(contains(PendingBetStatus.failed)));
      expect(named('polymarket_bet_failed'), isEmpty);
      expect(backend.orderReads, greaterThan(1));
      expect(named('polymarket_order_outcome_reconciled').single.$2!['outcome'],
          'unconfirmed');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  test('the venue took it and the receipt\'s bookkeeping threw: the '
      'receipt, never failed', () async {
    final trading = _Trading(
        () => {
              'success': true,
              'status': 'matched',
              'orderID': _orderId,
              'makingAmount': '5',
              'takingAmount': '12.5',
            },
        throwOnFill: true);
    final r = await place(trading);
    // Before: the throw reached the placement's catch and ended it as a
    // failed prediction ("This action did not complete").
    expect(r.end?.status, PendingBetStatus.done);
    expect(r.statuses, isNot(contains(PendingBetStatus.failed)));
    expect(named('polymarket_bet_failed'), isEmpty);
  });
}
