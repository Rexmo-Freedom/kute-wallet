// Polymarket Combos: ids, quote checks and the payout arithmetic.
//
// The combo id vectors are live combos read from the Data API
// (`/v2/positions/combos`) on 2026-10-04: legs in, condition and YES
// position ids out, as the chain minted them.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/polymarket_model.dart' show PolymarketPricePoint;
import 'package:kute/services/polymarket/combos/combo_ids.dart';
import 'package:kute/services/polymarket/combos/combo_math.dart';
import 'package:kute/services/polymarket/combos/combo_models.dart';
import 'package:kute/services/polymarket/combos/combo_order.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';

const _twoLegs = [
  '1077787417418645219992248279960657331420251824531927155180929506811903475968',
  '1012081026473256452741199912759478013204416988431123411618850678245928468480',
];
const _twoLegsCondition =
    '0x0316141d43829e3342022ccf5ed4fdbf9d0000000000000000000000000000';
const _twoLegsYes =
    '1395948005049969436883083514886051318828509168730104056302494071274545872896';

// Three legs, one of them a NO outcome (last byte 0x01).
const _threeLegs = [
  '472265456893663941330389574064928387453658359517509419957962866583880597504',
  '695125281185983284269686841902207788493652114306702834303572773781876244480',
  '896593065905147375304208106678104321719754506102029764105846164038717800449',
];
const _threeLegsCondition =
    '0x03d7e7ab698e3c186996de19a68dcb31e30000000000000000000000000000';
const _threeLegsYes =
    '1738409589350443105480231118268579223881163908189494132766065261638869581824';

Map<String, dynamic> _createResponse({
  String? yes,
  List<String>? legs,
  String total = '1000000',
  String maker = '966191',
  String taker = '1932381',
  String net = '1932381',
  int? expiresAt,
  String direction = 'BUY',
  String unit = 'notional',
}) =>
    {
      'rfq_id': 'rfq_1',
      'status': 'AWAITING_REQUESTER_ACCEPTANCE',
      'expires_at': expiresAt ?? 4102444800000,
      'request': {
        'rfq_id': 'rfq_1',
        'maker_address': '0xabc',
        'leg_position_ids': legs ?? _twoLegs,
        'condition_id': _twoLegsCondition,
        'yes_position_id': yes ?? _twoLegsYes,
        'no_position_id': '1',
        'direction': direction,
        'side': 'YES',
        'requested_size': {'unit': unit, 'value_e6': '1000000'},
        'created_at': 1773890758000,
      },
      'quote': {
        'quote_id': 'quote_1',
        'blended_price_e6': '500000',
        'maker_amount_e6': maker,
        'taker_amount_e6': taker,
        'total_required_e6': total,
        'net_receive_e6': net,
      },
    };

ComboRfqResult _parse(Map<String, dynamic> json,
        {ComboDirection direction = ComboDirection.buy}) =>
    parseComboCreateResponse(json,
        legPositionIds: ComboIds.canonicalLegs(_twoLegs),
        direction: direction,
        sizeE6: BigInt.from(1000000));

void main() {
  group('combo ids', () {
    test('derive the live combo condition and YES ids from their legs', () {
      final two = ComboIds.derive(_twoLegs);
      expect(two.conditionId, _twoLegsCondition);
      expect(two.yesPositionId, _twoLegsYes);
      expect(BigInt.parse(two.noPositionId) - BigInt.parse(two.yesPositionId),
          BigInt.one);

      final three = ComboIds.derive(_threeLegs);
      expect(three.conditionId, _threeLegsCondition);
      expect(three.yesPositionId, _threeLegsYes);
    });

    test('leg order does not matter', () {
      expect(ComboIds.derive(_twoLegs.reversed).yesPositionId, _twoLegsYes);
      expect(ComboIds.canonicalLegs(_twoLegs),
          [_twoLegs[1], _twoLegs[0]]); // ascending
    });

    test('rejects leg sets the protocol rejects', () {
      expect(() => ComboIds.canonicalLegs([_twoLegs[0]]),
          throwsA(isA<ComboLegsException>()));
      expect(() => ComboIds.canonicalLegs([_twoLegs[0], _twoLegs[0]]),
          throwsA(isA<ComboLegsException>()));
      // Both outcomes of one market.
      final yes = BigInt.parse(_twoLegs[0]);
      expect(
          () => ComboIds.canonicalLegs(
              [yes.toString(), (yes + BigInt.one).toString()]),
          throwsA(isA<ComboLegsException>()));
      // A combo position cannot be a leg (module 0x03).
      expect(() => ComboIds.canonicalLegs([_twoLegsYes, _twoLegs[0]]),
          throwsA(isA<ComboLegsException>()));
      // A CLOB token id is not a position id.
      expect(
          () => ComboIds.canonicalLegs([
                '55115078421062885512539156303747803058407616201213034911037320915726138659123',
                _twoLegs[0],
              ]),
          throwsA(isA<ComboLegsException>()));
    });

    test('split a combo position id into condition and outcome', () {
      final s = ComboIds.split(_twoLegsYes);
      expect(s.conditionId, _twoLegsCondition);
      expect(s.outcomeIndex, 0);
    });
  });

  group('quote', () {
    test('docs example: multiplier, payout, fees', () {
      final r = _parse(_createResponse());
      expect(r, isA<ComboQuoted>());
      final q = (r as ComboQuoted).quote;
      expect(q.yesPositionId, _twoLegsYes);
      expect(q.comboConditionId, _twoLegsCondition);
      expect(q.stakeUsd, 1.0);
      expect(q.payoutUsd, 1.932381);
      expect(q.multiplier, closeTo(1.932381, 1e-9));
      expect(q.feesUsd, closeTo(0.033809, 1e-9));
      expect(q.blendedPrice, 0.5);
    });

    test('multiplier is payout over cost, never overstated', () {
      expect(
          comboMultiplier(
              payoutE6: BigInt.from(5000000), costE6: BigInt.from(1000000)),
          5.0);
      expect(comboMultiplier(payoutE6: BigInt.one, costE6: BigInt.zero), 0);
      // net_receive below taker: the payout uses the lower one.
      final q = (_parse(_createResponse(net: '1900000')) as ComboQuoted).quote;
      expect(q.payoutUsd, 1.9);
      expect(q.multiplier, closeTo(1.9, 1e-9));
    });

    test('no quote is a business outcome, not an error', () {
      final r = _parse({
        'rfq_id': 'rfq_1',
        'status': 'FAILED',
        'error': {'code': 'NO_QUOTES', 'message': 'no quotes'},
      });
      expect(r, isA<ComboNoQuote>());
      expect((r as ComboNoQuote).code, 'NO_QUOTES');
    });

    test('refuses a quote for another combo, budget or window', () {
      // Another YES position than the legs derive to.
      expect(() => _parse(_createResponse(yes: _threeLegsYes)),
          throwsA(isA<ComboQuoteMismatch>()));
      // Other legs echoed.
      expect(() => _parse(_createResponse(legs: _threeLegs.sublist(0, 2))),
          throwsA(isA<ComboQuoteMismatch>()));
      // Stake above the budget.
      expect(() => _parse(_createResponse(total: '1000001')),
          throwsA(isA<ComboQuoteMismatch>()));
      // $1 or more per share.
      expect(
          () => _parse(_createResponse(
              maker: '1000000', taker: '1000000', net: '1000000')),
          throwsA(isA<ComboQuoteMismatch>()));
      // Window already closed.
      expect(() => _parse(_createResponse(expiresAt: 1000)),
          throwsA(isA<ComboQuoteMismatch>()));
      // Wrong direction echoed.
      expect(() => _parse(_createResponse(direction: 'SELL', unit: 'shares')),
          throwsA(isA<ComboQuoteMismatch>()));
    });

    test('SELL: exact proceeds, never more shares than asked', () {
      final ok = _parse(
        _createResponse(
          direction: 'SELL',
          unit: 'shares',
          maker: '1000000',
          taker: '450000',
          total: '1000000',
          net: '440000',
        ),
        direction: ComboDirection.sell,
      );
      final q = (ok as ComboQuoted).quote;
      expect(q.proceedsUsd, 0.44);
      expect(q.feesUsd, closeTo(0.01, 1e-9));
      expect(
          () => _parse(
                _createResponse(
                  direction: 'SELL',
                  unit: 'shares',
                  maker: '1000001',
                  taker: '450000',
                  total: '1000001',
                  net: '440000',
                ),
                direction: ComboDirection.sell,
              ),
          throwsA(isA<ComboQuoteMismatch>()));
    });

    test('request body matches the documented shape', () {
      final body = jsonDecode(comboRequestBody(
        depositWallet: '0xabc',
        legPositionIds: ComboIds.canonicalLegs(_twoLegs),
        direction: ComboDirection.buy,
        sizeE6: usdToE6Floor(12.29),
      )) as Map;
      expect(body['signer_address'], '0xabc');
      expect(body['maker_address'], '0xabc');
      expect(body['signature_type'], 3);
      expect(body['side'], 'YES');
      expect(body['direction'], 'BUY');
      expect(body['requested_size'], {'unit': 'notional', 'value_e6': '12290000'});
      expect(usdToE6Floor(0.29), BigInt.from(290000));
    });
  });

  group('settlement', () {
    ComboLegMark open(double p) => ComboLegMark(resolved: false, price: p);
    ComboLegMark won() => const ComboLegMark(resolved: true, price: 1);
    ComboLegMark lost() => const ComboLegMark(resolved: true, price: 0);
    ComboLegMark voided() => const ComboLegMark(resolved: true, price: 0.5);

    test('payout is the product of the leg payouts', () {
      expect(comboSettlementFactor([won(), won(), won()]), 1.0);
      expect(comboSettlementFactor([won(), voided()]), 0.5);
      expect(comboSettlementFactor([voided(), voided(), won()]), 0.25);
    });

    test('any losing leg makes it 0, even with legs still open', () {
      expect(comboSettlementFactor([won(), lost(), won()]), 0);
      expect(comboSettlementFactor([open(0.7), lost()]), 0);
    });

    test('no verdict while a leg is open and none lost', () {
      expect(comboSettlementFactor([won(), open(0.6)]), isNull);
      expect(comboSettlementFactor(const []), isNull);
    });

    test('payout in base units halves exactly per void', () {
      final shares = BigInt.from(1932381);
      expect(comboPayoutE6(sharesE6: shares, factor: 1), shares);
      expect(comboPayoutE6(sharesE6: shares, factor: 0.5), BigInt.from(966190));
      expect(
          comboPayoutE6(sharesE6: shares, factor: 0.25), BigInt.from(483095));
      expect(comboPayoutE6(sharesE6: shares, factor: 0), BigInt.zero);
    });

    test('best case and the estimate', () {
      expect(comboBestCaseFactor([won(), open(0.4), voided()]), 0.5);
      expect(comboBestCaseFactor([open(0.4), lost()]), 0);
      expect(
          comboEstimatedValue(shares: 10, legs: [open(0.5), open(0.4)]), 2.0);
      expect(
          comboEstimatedValue(shares: 10, legs: [won(), open(0.4)]), 4.0);
      expect(comboEstimatedValue(shares: 10, legs: [lost(), open(0.9)]), 0);
    });

    test('a held combo reads its legs', () {
      final p = ComboPosition.fromJson({
        'combo_condition_id': _twoLegsCondition,
        'combo_position_id': _twoLegsYes,
        'outcome_index': 0,
        'current_size': 20.0,
        'gross_entry_cost_usdc': 5.0,
        'status': 'OPEN',
        'redeemable': false,
        'legs_total': 2,
        'legs': [
          {'leg_index': 0, 'leg_status': 'RESOLVED_WIN', 'leg_current_price': 1.0,
            'leg_resolved_at': '2026-10-01T00:00:00Z'},
          {'leg_index': 1, 'leg_status': 'OPEN', 'leg_current_price': 0.3},
        ],
      });
      expect(p.potentialPayoutUsd, 20.0);
      expect(p.multiplier, 4.0);
      expect(p.estimatedValueUsd, closeTo(6.0, 1e-9));
      expect(p.settledPayoutUsd, isNull);
      expect(p.isOpen, isTrue);
      expect(p.legs.first.outcome, ComboLegOutcome.won);
      expect(p.legs.last.outcome, ComboLegOutcome.open);
    });

    test('the estimate series multiplies the legs, carried forward', () {
      PolymarketPricePoint pt(int s, double p) => PolymarketPricePoint(
          timestamp: DateTime.fromMillisecondsSinceEpoch(s * 1000), price: p);
      final series = comboEstimateSeries([
        [pt(10, 0.5), pt(30, 0.6)],
        [pt(20, 0.4), pt(30, 0.5)],
      ]);
      // Starts once both legs have a point (t=20).
      expect(series.map((p) => p.timestamp.millisecondsSinceEpoch ~/ 1000),
          [20, 30]);
      expect(series[0].price, closeTo(0.2, 1e-12));
      expect(series[1].price, closeTo(0.3, 1e-12));
      expect(comboEstimateSeries([[], [pt(1, 1)]]), isEmpty);
    });
  });

  test('Router redeem calldata: selector, bytes31, outcome, amount', () {
    final data = PolymarketOnboardingService.comboRedeemCalldata(
      conditionId: _twoLegsCondition,
      outcomeIndex: 0,
      amount: BigInt.from(1932381),
    );
    expect(data.substring(0, 10), '0xd217a3cc');
    // bytes31 is left-aligned: the 31 bytes, then one zero byte.
    expect(data.substring(10, 74), '${_twoLegsCondition.substring(2)}00');
    expect(data.substring(74, 138), '0' * 64);
    expect(BigInt.parse(data.substring(138), radix: 16), BigInt.from(1932381));
    expect(data.length, 10 + 64 * 3);
    expect(
        () => PolymarketOnboardingService.comboRedeemCalldata(
            conditionId: '0x1234', outcomeIndex: 0, amount: BigInt.one),
        throwsArgumentError);
  });

  test('combo grants: cheaper and better-paying quotes stay covered', () {
    final legs = ComboIds.canonicalLegs(_twoLegs);
    final review = PmGrants.comboBet(
      walletId: 'w',
      legPositionIds: legs,
      maxStakeE6: BigInt.from(1000000),
      minPayoutE6: BigInt.from(1900000),
    );
    SensitiveIntent exec(int stake, int payout, [List<String>? l]) =>
        PmGrants.comboBet(
          walletId: 'w',
          legPositionIds: l ?? legs,
          maxStakeE6: BigInt.from(stake),
          minPayoutE6: BigInt.from(payout),
        );
    expect(AuthGrants.driftBetween(review, exec(990000, 1932381)), isEmpty);
    expect(AuthGrants.driftBetween(review, exec(1000001, 1932381)),
        contains(DriftField.amount));
    expect(AuthGrants.driftBetween(review, exec(1000000, 1899999)),
        contains(DriftField.minReceive));
    expect(
        AuthGrants.driftBetween(
            review, exec(1000000, 1932381, ComboIds.canonicalLegs(_threeLegs))),
        contains(DriftField.legs));
  });
}
