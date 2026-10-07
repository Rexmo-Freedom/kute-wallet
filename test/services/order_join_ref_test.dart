import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_analytics.dart';

/// The database join key on money events: `order_ref` / `quote_ref` =
/// [TrackingService.orderRef] of the raw provider id, the same value the
/// backend stores in `who_did_what.order_ref`. The raw id never leaves the device,
/// and no app event carries Kute revenue or an estimate of it.
void main() {
  final events = <(String, Map<String, Object>?)>[];

  Map<String, Object> only(String name) =>
      events.singleWhere((e) => e.$1 == name).$2!;

  /// Every string value of [props], nested ones included.
  Iterable<String> strings(Object? v) sync* {
    if (v is String) yield v;
    if (v is Map) {
      for (final x in v.values) {
        yield* strings(x);
      }
    }
    if (v is List) {
      for (final x in v) {
        yield* strings(x);
      }
    }
  }

  setUp(() {
    VenueAnalytics.debugReset();
    events.clear();
    TrackingService.setDisabled(true);
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    VenueAnalytics.debugReset();
  });

  group('shared test vectors (the backend asserts the same pairs)', () {
    test('order id, quote id and a non-ASCII id', () {
      expect(TrackingService.orderRef('ord_01J8ZK4M7Q2X9V3T5R6W8Y0ABC'),
          'ref_504973ad6ad3e596');
      expect(TrackingService.orderRef('quote_01J8ZK4M7Q2X9V3T5R6W8Y0ABC'),
          'ref_8c85af203cbafb1d');
      expect(TrackingService.orderRef('\u00e9'), 'ref_9abda7604872f36a');
    });

    test('is the namespaced sha256, first 16 hex', () {
      const raw = 'ord_any_other_id';
      final digest = sha256
          .convert(utf8.encode('kute:analytics-order-ref:v1\u0000$raw'))
          .toString();
      expect(TrackingService.orderRef(raw), 'ref_${digest.substring(0, 16)}');
    });
  });

  test('Orchestra ids map to order_ref or quote_ref', () {
    final ord = TrackingService.orderRef('ord_1');
    final q = TrackingService.orderRef('q_1');
    expect(TrackingService.orchestraJoinParams('ord_1'), {'order_ref': ord});
    expect(TrackingService.orchestraJoinParams('q_1'), {'quote_ref': q});
    expect(TrackingService.orchestraJoinParams('ord_1', quoteId: 'q_1'),
        {'order_ref': ord, 'quote_ref': q});
    // Synthetic local ids never reached the database.
    expect(TrackingService.orchestraJoinParams('acu-123'), isEmpty);
    expect(TrackingService.orchestraJoinParams(null), isEmpty);
  });

  test('a raw order_ref is hashed centrally; a reference is kept', () {
    final ref = TrackingService.orderRef('ord_1');
    expect(TrackingService.sanitizeParams({'order_ref': 'ord_1'}),
        {'order_ref': ref});
    expect(
        TrackingService.sanitizeParams({'quote_ref': ref}), {'quote_ref': ref});
    // The scrubber leaves the reference intact.
    expect(TrackingService.scrubString(ref), ref);
  });

  test('swap_completed: order_ref, no raw id, no fee estimate', () {
    TrackingService.swapCompleted(
      fromCoin: 'BTC',
      toCoin: 'USDC',
      provider: 'orchestra',
      fromAmount: 0.001,
      toAmount: 99,
      amountUsd: 99,
      providerOrderId: 'ord_swap_1',
    );
    final p = only('swap_completed');
    expect(p['order_ref'], TrackingService.orderRef('ord_swap_1'));
    expect(p.keys, isNot(contains('fee_usd')));
    expect(p.keys, isNot(contains('fee_bucket')));
    expect(p.keys, isNot(contains('fee_basis')));
    expect(strings(p), isNot(contains('ord_swap_1')));
  });

  test('swap_completed of a quote only carries quote_ref', () {
    TrackingService.swapCompleted(
      fromCoin: 'USDC',
      toCoin: 'BTC',
      provider: 'orchestra',
      providerOrderId: 'q_swap_2',
    );
    final p = only('swap_completed');
    expect(p['quote_ref'], TrackingService.orderRef('q_swap_2'));
    expect(p.keys, isNot(contains('order_ref')));
  });

  test('cashapp_buy_completed carries order_ref and fee_shown_*', () {
    TrackingService.cashAppBuyCompleted(
      amountUsd: 50,
      orderId: 'ord_cash_1',
      amountSats: 50000,
      feeUsd: 1.25,
    );
    final p = only('cashapp_buy_completed');
    expect(p['order_ref'], TrackingService.orderRef('ord_cash_1'));
    expect(p['fee_shown_usd'], 1.25);
    expect(p['fee_shown_basis'], 'shown_at_quote');
    expect(p.keys, isNot(contains('fee_usd')));
    expect(p.keys, isNot(contains('fee_basis')));
    expect(strings(p), isNot(contains('ord_cash_1')));
  });

  test('polymarket_bet_placed: order_ref from the CLOB order id only', () {
    const clobId =
        '0x9a1b2c3d4e5f60718293a4b5c6d7e8f9a0b1c2d3e4f5061728394a5b6c7d8e9f';
    TrackingService.polymarketBetPlaced(
      marketId: 'tok-a',
      outcome: 'buy',
      amount: 10,
      price: 0.5,
      shares: 20,
      providerOrderId: clobId,
      logAffiliateEvent: false,
    );
    final p = only('polymarket_bet_placed');
    expect(p['order_ref'], TrackingService.orderRef(clobId));
    expect(strings(p), isNot(contains(clobId)));

    events.clear();
    TrackingService.polymarketBetPlaced(
      marketId: 'tok-a',
      outcome: 'buy',
      amount: 10,
      price: 0.5,
      shares: 20,
      logAffiliateEvent: false,
    );
    expect(only('polymarket_bet_placed').keys, isNot(contains('order_ref')));
  });

  test('polymarket_position_sold carries the sell order_ref', () {
    const clobId =
        '0x1f2e3d4c5b6a79881726354a5b6c7d8e9f0a1b2c3d4e5f60718293a4b5c6d7e8';
    TrackingService.polymarketPositionSold(
        marketId: 'tok-a', shares: 2, price: 0.4, providerOrderId: clobId);
    expect(only('polymarket_position_sold')['order_ref'],
        TrackingService.orderRef(clobId));
  });

  test('Hyperliquid orders carry no order_ref and no oid', () {
    TrackingService.hyperliquidOrderPlaced(
      coin: 'BTC',
      kind: 'perp',
      isBuy: true,
      leverage: 3,
      marginUsd: 50,
      notionalUsd: 150,
      providerOrderId: '123456789',
    );
    TrackingService.hyperliquidPositionClosed(
      coin: 'BTC',
      fractionPct: 100,
      payoutUsd: 60,
      providerOrderId: '123456790',
    );
    for (final name in [
      'hyperliquid_order_placed',
      'hyperliquid_position_closed'
    ]) {
      final p = only(name);
      expect(p.keys, isNot(contains('order_ref')));
      expect(strings(p), isNot(contains('123456789')));
      expect(strings(p), isNot(contains('123456790')));
    }
  });

  test('venue deposits and withdrawals carry the Orchestra join keys', () {
    TrackingService.polymarketDepositSubmitted(
        orderId: 'q_dep_1', amountUsd: 5);
    TrackingService.polymarketDepositCompleted(
        orderId: 'ord_dep_1', amountUsd: 5);
    TrackingService.polymarketWithdrawSubmitted(
        orderId: 'ord_wd_1', amountUsd: 5);
    TrackingService.polymarketWithdrawCompleted(
        orderId: 'ord_wd_1', amountUsd: 5);
    TrackingService.hyperliquidDepositCompleted(
        amountUsd: 5, orderId: 'ord_hl_1', quoteId: 'q_hl_1');
    TrackingService.hyperliquidWithdrawCompleted(
        amountUsd: 5, quoteId: 'q_hl_2');

    expect(only('polymarket_deposit_submitted')['quote_ref'],
        TrackingService.orderRef('q_dep_1'));
    expect(only('polymarket_deposit_completed')['order_ref'],
        TrackingService.orderRef('ord_dep_1'));
    expect(only('polymarket_withdraw_submitted')['order_ref'],
        TrackingService.orderRef('ord_wd_1'));
    expect(only('polymarket_withdraw_completed')['order_ref'],
        TrackingService.orderRef('ord_wd_1'));
    final hlDep = only('hyperliquid_deposit_completed');
    expect(hlDep['order_ref'], TrackingService.orderRef('ord_hl_1'));
    expect(hlDep['quote_ref'], TrackingService.orderRef('q_hl_1'));
    expect(only('hyperliquid_withdraw_completed')['quote_ref'],
        TrackingService.orderRef('q_hl_2'));
    for (final e in events) {
      for (final raw in [
        'q_dep_1',
        'ord_dep_1',
        'ord_wd_1',
        'ord_hl_1',
        'q_hl_1',
        'q_hl_2'
      ]) {
        expect(strings(e.$2), isNot(contains(raw)), reason: e.$1);
      }
    }
  });

  test('moneyParams names the fee the user saw, never revenue', () {
    final p = TrackingService.moneyParams(
        amountUsd: 10, feeUsd: 0.5, networkFeeUsd: 0.2, feeSats: 300);
    expect(p['fee_shown_usd'], 0.5);
    expect(p['fee_shown_basis'], 'shown_at_quote');
    expect(p['network_fee_usd'], 0.2);
    expect(p.keys.where((k) => k.contains('revenue') || k.contains('earning')),
        isEmpty);
    expect(p.keys, isNot(contains('fee_usd')));
    expect(p.keys, isNot(contains('fee_basis')));
  });
}
