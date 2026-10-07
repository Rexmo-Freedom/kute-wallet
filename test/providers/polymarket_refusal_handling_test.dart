// How the slip ends when the order book refuses an order. Fakes only:
// nothing is signed or sent.
//
// A repeated balance refusal used to become "Setting up your Predictions
// wallet…" and then "Your approval expired"; an unrecognised 400 used to
// become "A previous prediction is still being confirmed" with nothing to
// find. Each now ends on what the venue said, once, and the failure event
// carries the venue's refusal.
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
import 'package:kute/services/polymarket/hot_order_guard.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/order_refusal.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show OrderSide, OrderType;

const _token = '1234';

class _Trading extends PolymarketTradingNotifier {
  _Trading(this.answer);
  final Object Function() answer;
  var orders = 0;

  @override
  Future<PolymarketTradingState> build() async => const PolymarketTradingState(
      usdcBalance: 100, proxyWalletAddress: '0xdeposit');

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
    orders++;
    throw answer();
  }
}

Map<String, dynamic> _book(String ask) => {
      'market': 'm',
      'asset_id': _token,
      'tick_size': '0.01',
      'neg_risk': true,
      'min_order_size': '1',
      'asks': [
        {'price': ask, 'size': '100'}
      ],
      'bids': [
        {'price': '0.30', 'size': '100'}
      ],
    };

PendingBetIntent _intent() => const PendingBetIntent(
      tokenId: _token,
      amount: 5,
      slippagePct: 5,
      marketQuestion: 'Portugal vs. Northern Ireland',
      outcomeName: 'Portugal',
      expectedPrice: 0.61,
    );

void main() {
  final l10n = l10nForLanguage('en');
  final events = <(String, Map<String, Object>?)>[];
  setUp(() {
    events.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });
  tearDown(() => TrackingService.debugTrackObserver = null);

  Future<(PendingBetIntent?, _Trading)> run(Object Function() answer) async {
    final trading = _Trading(answer);
    final container = ProviderContainer(overrides: [
      polymarketTradingProvider.overrideWith(() => trading),
    ]);
    addTearDown(container.dispose);
    container.listen(polymarketTradingProvider, (_, __) {});
    await container.read(polymarketTradingProvider.future);
    final controller = container.read(polymarketBetControllerProvider);
    final venue = MockClient((req) async {
      if (req.url.path == '/book') {
        return http.Response(jsonEncode(_book('0.61')), 200);
      }
      return http.Response('offline', 503);
    });
    await http.runWithClient(() async {
      final prepared = await controller.prepareIntent(_intent());
      container.read(pendingPolymarketBetProvider.notifier).setIntent(prepared);
      final review = controller.reviewIntent(prepared)!;
      final grant = AuthGrants.issue(review, method: AuthGrantMethod.allowance);
      await controller.place('usdc', grant: grant);
    }, () => venue);
    return (container.read(pendingPolymarketBetProvider), trading);
  }

  Map<String, Object>? failedEvent() => events
      .where((e) => e.$1 == 'polymarket_bet_failed')
      .map((e) => e.$2)
      .single;

  group('a repeated balance refusal', () {
    test('ends on the balance message, once, with the refusal recorded',
        () async {
      final (pending, trading) = await run(() => const PolymarketBalanceRefused(
          'not enough balance / allowance: the balance is not enough -> '
          'balance: 8130000, order amount: 8050000'));
      expect(pending?.status, PendingBetStatus.failed);
      expect(pending?.errorMessage, l10n.betVenueBalanceRefused);
      // No second rung: the refresh already ran inside the placement.
      expect(trading.orders, 1);
      final params = failedEvent()!;
      expect(params['reason'], 'venue_balance_refused');
      expect(params['venue_refusal'],
          'not enough balance / allowance: the balance is not enough');
      expect(params['refusal_class'], 'not_enough_balance');
      expect(params['stage'], 'self_heal');
    });

    test('the failure event describes the order, never the wallet', () async {
      await run(() => const PolymarketBalanceRefused(
          'not enough balance / allowance: the allowance is not enough -> '
          'spender: 0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296, allowance: 0'));
      final params = failedEvent()!;
      expect(params['refusal_class'], 'allowance_not_enough');
      expect(params['venue_market_type'], 'neg_risk');
      expect(params['venue_order_type'], 'FAK');
      expect(params['side'], 'buy');
      expect(params['bet_type'], 'moneyline');
      expect(params['outcome_category'], 'game');
      expect(params['is_short_round'], false);
      expect(params['amount_usd'], 5.0);
      expect(params['expected_price'], 0.61);
      expect(params['order_price'], 0.64);
      expect(params['max_price'], 0.64);
      expect(params['sig_type'], 3);
      expect(params['approval'], 'allowance');
      final text = params.values.join(' ');
      expect(text, isNot(contains('0x')));
      expect(text, isNot(contains('d91E')));
      // The per-rung outcome carries the same refusal class.
      final outcome = events
          .where((e) => e.$1 == 'polymarket_order_outcome')
          .single
          .$2!;
      expect(outcome['refusal_class'], 'allowance_not_enough');
      expect(outcome['stage'], 'self_heal');
      expect(outcome['venue_market_type'], 'neg_risk');
      expect(outcome['price'], 0.64);
    });
  });

  group('an approval that ran out during the repair', () {
    test('a balance refusal says so, not "approval expired"', () async {
      final (pending, trading) = await run(() =>
          const PolymarketRefusalOutlivedApproval(
              'not enough balance / allowance: the allowance is not enough '
              '-> spender: 0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296'));
      expect(pending?.status, PendingBetStatus.failed);
      expect(pending?.errorMessage, l10n.betVenueBalanceRefused);
      expect(pending?.errorMessage, isNot(l10n.stepUpApprovalExpired));
      expect(trading.orders, 1);
      final params = failedEvent()!;
      expect(params['reason'], 'venue_balance_refused');
      expect(params['venue_refusal'],
          'not enough balance / allowance: the allowance is not enough');
    });

    test('any other refusal says the venue did not accept it', () async {
      final (pending, trading) = await run(
          () => const PolymarketRefusalOutlivedApproval('maker address not allowed'));
      expect(pending?.errorMessage, l10n.ledgerErrorVenueRejected);
      expect(trading.orders, 1);
      expect(failedEvent()!['reason'], 'venue_rejected');
    });
  });

  group('an unrecognised refusal', () {
    test('fails at once with the venue\'s answer, not a pending lock',
        () async {
      final (pending, trading) = await run(() =>
          const PolymarketOrderNotAcceptedException('invalid tick size'));
      expect(pending?.status, PendingBetStatus.failed);
      expect(pending?.status, isNot(PendingBetStatus.awaitingConfirmation));
      expect(pending?.errorMessage, l10n.ledgerErrorVenueRejected);
      // Not a no-match: no second rung.
      expect(trading.orders, 1);
      final params = failedEvent()!;
      expect(params['reason'], 'venue_rejected');
      expect(params['venue_refusal'], 'invalid tick size');
      expect(params['refusal_class'], 'invalid_tick');
      expect(params['stage'], 'submit');
    });

    test('a pending order still waits for confirmation, reported as declined',
        () async {
      final (pending, _) = await run(() => const PendingPolymarketOrder());
      expect(pending?.status, PendingBetStatus.awaitingConfirmation);
      expect(events.where((e) => e.$1 == 'polymarket_bet_failed'), isEmpty);
      final declined = events
          .where((e) => e.$1 == 'polymarket_placement_declined')
          .single
          .$2!;
      expect(declined['reason'], 'previous_order_unconfirmed');
      expect(declined['stage'], 'guard_pending');
      expect(declined['venue_market_type'], 'neg_risk');
    });

    test('an order whose answer proves nothing is declined at submit',
        () async {
      final (pending, _) =
          await run(() => const PolymarketOrderOutcomeUnknown());
      expect(pending?.status, PendingBetStatus.awaitingConfirmation);
      final declined = events
          .where((e) => e.$1 == 'polymarket_placement_declined')
          .single
          .$2!;
      expect(declined['reason'], 'outcome_unknown');
      expect(declined['stage'], 'submit');
    });

    test('an approval that expired before any refusal is a tracked failure',
        () async {
      final (pending, _) = await run(() => const GrantExpired());
      expect(pending?.errorMessage, l10n.stepUpApprovalExpired);
      final params = failedEvent()!;
      expect(params['reason'], 'approval_expired');
      expect(params['stage'], 'grant_expired');
    });
  });

  group('placement context', () {
    test('a five-minute round is told from its title', () {
      expect(
          PolymarketBetController.isShortRound(
              'Bitcoin Up or Down - October 7, 5:00PM-5:05PM ET'),
          isTrue);
      expect(
          PolymarketBetController.isShortRound(
              'Bitcoin Up or Down - October 7, 5PM ET'),
          isFalse);
      expect(PolymarketBetController.isShortRound('Portugal vs. Ireland'),
          isFalse);
    });

    test('every failure code has a stage', () {
      for (final code in [
        'setup_timeout',
        'insufficient_usdc',
        'region_unavailable',
        'request_timeout',
        'approval_expired',
        'approval_revoked',
        'previous_order_unconfirmed',
        'liquidity_unavailable',
      ]) {
        expect(PolymarketBetController.polymarketFailureStage(code, null),
            isNot('unknown'),
            reason: code);
      }
    });
  });

  group('venue-side refusals that are not a shortage', () {
    test('a stale matched-orders reservation says try again in a moment',
        () async {
      final (pending, trading) = await run(() => const PolymarketStaleReservation(
          'not enough balance / allowance: the balance is not enough -> '
          'balance: 8132422, sum of matched orders: 5000000, order amount: '
          '8080200'));
      expect(pending?.errorMessage, l10n.betVenueSettling);
      expect(pending?.errorMessage, isNot(l10n.betAddFundsToPredict));
      expect(trading.orders, 1);
      final params = failedEvent()!;
      expect(params['reason'], 'stale_matched_orders');
      expect(params['refusal_class'], 'stale_matched_orders');
    });

    test('an allowance to an unknown spender is not called a shortage',
        () async {
      final (pending, _) = await run(() => const PolymarketBalanceRefused(
          'not enough balance / allowance: the allowance is not enough -> '
          'spender: 0x3333333333333333333333333333333333333333, allowance: 0'));
      expect(pending?.errorMessage, l10n.ledgerErrorVenueRejected);
      final params = failedEvent()!;
      expect(params['reason'], 'venue_unknown_spender');
      expect(params['spender'], 'unknown');
    });
  });
}
