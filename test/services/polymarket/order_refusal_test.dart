// A second "not enough balance / allowance" used to fall into the approvals
// repair because it says "allowance": the slip showed "Setting up your
// Predictions wallet…", re-ran setup for up to 90 s and usually ended on
// "Your approval expired". The balance refusal is refreshed once and then
// ends the placement; only approval and maker refusals run the repair.
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/services/polymarket/order_refusal.dart';
import 'package:kute/services/polymarket_backend_service.dart';

const _balance = 'not enough balance / allowance: the balance is not '
    'enough -> balance: 8130000, order amount: 8050000';

PolymarketRefusalHeal _spender(String reason, {bool balance = false}) =>
    polymarketRefusalHeal(reason,
        balanceRefreshed: balance,
        keyRebound: false,
        approvalsFixed: false,
        spenderApproved: true);

PolymarketRefusalHeal _heal(String reason,
        {bool balance = false, bool key = false, bool approvals = false}) =>
    polymarketRefusalHeal(reason,
        balanceRefreshed: balance, keyRebound: key, approvalsFixed: approvals);

void main() {
  group('the balance refusal', () {
    test('is refreshed once', () {
      expect(_heal(_balance), PolymarketRefusalHeal.refreshBalance);
      expect(_heal('not enough balance / allowance'),
          PolymarketRefusalHeal.refreshBalance);
    });

    test('then ends the placement, never the setup repair', () {
      expect(_heal(_balance, balance: true), PolymarketRefusalHeal.stop);
      expect(_heal(_balance, balance: true, approvals: false),
          isNot(PolymarketRefusalHeal.repairSetup));
      expect(isPolymarketApprovalRefusal(_balance), isFalse);
    });

    test('is still a definitive refusal, told apart', () {
      const e = PolymarketBalanceRefused(_balance);
      expect(e, isA<PolymarketOrderNotAcceptedException>());
      expect(e.reason, _balance);
    });
  });

  group('a refusal naming a missing allowance', () {
    // What the venue said for every 3-way buy while the Neg Risk Adapter
    // approval was missing.
    const allowance = 'not enough balance / allowance: the allowance is not '
        'enough -> spender: 0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296, '
        'allowance: 0, balance: 8132422, order amount (inc. fees): 8080200';

    test('approves the pinned spender once, then refreshes, then stops', () {
      expect(_heal(allowance), PolymarketRefusalHeal.approveSpender);
      expect(_spender(allowance), PolymarketRefusalHeal.refreshBalance);
      expect(_spender(allowance, balance: true), PolymarketRefusalHeal.stop);
    });

    test('an unknown spender is never approved and ends the placement', () {
      const unknown = 'not enough balance / allowance: the allowance is not '
          'enough -> spender: 0x3333333333333333333333333333333333333333, '
          'allowance: 0';
      expect(_heal(unknown), PolymarketRefusalHeal.stop);
      expect(polymarketRefusalParams(unknown)['spender'], 'unknown');
    });

    test('without a spender it runs the approvals check once', () {
      const bare = 'not enough balance / allowance: the allowance is not '
          'enough';
      expect(_heal(bare), PolymarketRefusalHeal.repairSetup);
      expect(_heal(bare, approvals: true),
          PolymarketRefusalHeal.refreshBalance);
    });

    test('records the spender by name, never its address', () {
      final params = polymarketRefusalParams(allowance);
      expect(params['spender'], 'neg_risk_adapter');
      expect(params.values.join(' '), isNot(contains('0x')));
    });

    test('a short balance never runs the approvals check', () {
      expect(isPolymarketAllowanceShortfall(allowance), isTrue);
      expect(isPolymarketAllowanceShortfall(_balance), isFalse);
      expect(_heal(_balance), isNot(PolymarketRefusalHeal.repairSetup));
    });

    test('is recorded with its detail, without the spender or figures', () {
      expect(polymarketRefusalForAnalytics(allowance),
          'not enough balance / allowance: the allowance is not enough');
    });
  });

  group('approval and maker refusals', () {
    for (final reason in [
      'the order is not approved',
      'ERC20: transfer amount exceeds allowance',
      'maker address 0x1111111111111111111111111111111111111111 has no allowance',
      'maker address not allowed',
    ]) {
      test('"$reason" runs the setup repair once', () {
        expect(_heal(reason), PolymarketRefusalHeal.repairSetup);
        expect(_heal(reason, approvals: true), PolymarketRefusalHeal.stop);
      });
    }
  });

  test('a stale API key is re-bound once', () {
    const reason =
        'the order signer address has to be the address of the API KEY';
    expect(_heal(reason), PolymarketRefusalHeal.rebindKey);
    expect(_heal(reason, key: true), PolymarketRefusalHeal.stop);
  });

  test('anything else ends the placement', () {
    expect(_heal('invalid tick size'), PolymarketRefusalHeal.stop);
    expect(_heal('the market is not yet ready to process new orders'),
        PolymarketRefusalHeal.stop);
  });

  group('the refusal for analytics', () {
    test('keeps the venue words and drops the figures', () {
      expect(polymarketRefusalForAnalytics(_balance),
          'not enough balance / allowance: the balance is not enough');
    });

    test('never carries an address or a hash', () {
      final text = polymarketRefusalForAnalytics(
          'maker address 0x1111111111111111111111111111111111111111 '
          'has no allowance for order 0x${'a' * 64}');
      expect(text, isNot(contains('0x')));
      expect(text, isNot(contains('1111')));
      expect(text, 'maker address has no allowance for order');
    });

    test('is bounded and never empty', () {
      expect(polymarketRefusalForAnalytics('x' * 500).length,
          lessThanOrEqualTo(120));
      expect(polymarketRefusalForAnalytics(''), 'unknown');
      expect(polymarketRefusalForAnalytics(r'{"a":1}'), isNotEmpty);
    });
  });

  group('an approval that runs out during the repair', () {
    test('surfaces the refusal that started it, not the expiry', () async {
      await expectLater(
          polymarketSurfaceRefusalOnExpiry((refused) async {
            refused(const PolymarketOrderNotAcceptedException(_balance));
            // The repair took longer than the approval lasts.
            throw const GrantExpired();
          }),
          throwsA(isA<PolymarketRefusalOutlivedApproval>()
              .having((e) => e.reason, 'reason', _balance)));
    });

    test('an expiry before any refusal stays an expiry', () async {
      await expectLater(
          polymarketSurfaceRefusalOnExpiry(
              (_) async => throw const GrantExpired()),
          throwsA(isA<GrantExpired>()));
    });

    test('other failures pass through untouched', () async {
      await expectLater(
          polymarketSurfaceRefusalOnExpiry((refused) async {
            refused(const PolymarketOrderNotAcceptedException(_balance));
            throw const PolymarketBalanceRefused(_balance);
          }),
          throwsA(isA<PolymarketBalanceRefused>()));
    });
  });

  test('refusals fall into closed classes', () {
    expect(polymarketRefusalClass(_balance), 'not_enough_balance');
    expect(
        polymarketRefusalClass('not enough balance / allowance: the allowance '
            'is not enough -> spender: 0x1'),
        'allowance_not_enough');
    expect(
        polymarketRefusalClass("order couldn't be fully filled. FOK orders "
            'are fully filled or killed.'),
        'fok_not_filled');
    expect(
        polymarketRefusalClass('no orders found to match with FAK order. FAK '
            'orders are partially filled or killed if no match is found.'),
        'fak_no_match');
    expect(polymarketRefusalClass('invalid tick size'), 'invalid_tick');
    expect(
        polymarketRefusalClass(
            'the market is not yet ready to process new orders'),
        'market_not_ready');
    expect(polymarketRefusalClass('invalid expiration'), 'order_expired');
    expect(polymarketRefusalClass('something new'), 'other');
    expect(polymarketRefusalParams('invalid tick size'),
        {'refusal_class': 'invalid_tick', 'venue_refusal': 'invalid tick size'});
  });

  group('a stale matched-orders reservation (py-clob-client-v2#112)', () {
    const stale = 'not enough balance / allowance: the balance is not enough '
        '-> balance: 8132422, sum of matched orders: 5000000, order amount: '
        '8080200';
    test('is told apart from a shortage', () {
      expect(isPolymarketStaleReservation(stale), isTrue);
      expect(polymarketRefusalClass(stale), 'stale_matched_orders');
      // The balance does not cover the order: a real shortage.
      expect(
          isPolymarketStaleReservation('not enough balance / allowance: the '
              'balance is not enough -> balance: 1000, sum of matched orders: '
              '5, order amount: 8080200'),
          isFalse);
      // Nothing matched is reserved.
      expect(
          isPolymarketStaleReservation('not enough balance / allowance: the '
              'balance is not enough -> balance: 9000000, sum of matched '
              'orders: 0, order amount: 8080200'),
          isFalse);
      expect(isPolymarketStaleReservation(_balance), isFalse);
    });

    test('is refreshed once like any balance refusal', () {
      expect(_heal(stale), PolymarketRefusalHeal.refreshBalance);
      expect(_heal(stale, balance: true), PolymarketRefusalHeal.stop);
      expect(const PolymarketStaleReservation(stale),
          isA<PolymarketBalanceRefused>());
    });
  });
}
