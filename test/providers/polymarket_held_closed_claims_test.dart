// A closed position comes back on the Claim rail only for tokens the wallet
// still holds once the result is on chain, at what it holds now. On 5 Oct
// 2026 a CS2 position (G2, 2.072917 shares bought at 96¢) was sold down to
// 0.002917 shares at 94.8¢; the Data API closed it at its lifetime size
// 2.0729 while the market still traded at 99.95¢ and the result was not
// reported on chain, and the app showed "Ready to claim · Claim $2.07".

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart';

const _g2 = 'g2-token';
const _condition = '0xad72';

ClosedPosition _closed({double size = 2.0729, bool won = true}) =>
    ClosedPosition(
      proxyWallet: 'wallet',
      asset: _g2,
      conditionId: _condition,
      size: size,
      avgPrice: 0.9638,
      initialValue: size * 0.9638,
      payout: 1.9562,
      cashPnl: -0.0417,
      percentPnl: -2.09,
      title: 'Counter-Strike: ShindeN vs G2 (BO3)',
      slug: 'cs2-shin-g2-2026-10-05',
      eventSlug: 'cs2-shin-g2-2026-10-05',
      outcome: 'G2',
      outcomeIndex: 1,
      won: won,
    );

Position _open({required bool redeemable, String condition = _condition}) =>
    Position(
      proxyWallet: 'wallet',
      asset: _g2,
      conditionId: condition,
      size: 2.07,
      avgPrice: 0.96,
      initialValue: 1.99,
      currentValue: 2.07,
      cashPnl: 0.08,
      percentPnl: 3.8,
      totalBought: 2.07,
      realizedPnl: 0,
      percentRealizedPnl: 0,
      curPrice: 1,
      redeemable: redeemable,
      title: 'Counter-Strike: ShindeN vs G2 (BO3)',
      slug: 'cs2-shin-g2-2026-10-05',
      eventSlug: 'cs2-shin-g2-2026-10-05',
      outcome: 'G2',
      outcomeIndex: 1,
      oppositeOutcome: 'ShindeN',
      oppositeAsset: 'shinden-token',
    );

List<Position> _claims({
  required BigInt held,
  double? payout,
  ClosedPosition? closed,
  Set<String> negRisk = const {},
}) =>
    PolymarketTradingNotifier.heldClosedClaims(
      closed: [closed ?? _closed()],
      openConditionIds: const {},
      balances: {_g2: held},
      settledPayouts: {if (payout != null) _g2: payout},
      negRiskConditionIds: negRisk,
    );

void main() {
  group('heldClosedClaims', () {
    test('the dust a sale left is never a claim, before or after the result',
        () {
      final dust = BigInt.from(2917); // 0.002917 shares
      expect(_claims(held: dust), isEmpty);
      expect(_claims(held: dust, payout: 1), isEmpty);
    });

    test('tokens held but no result on chain yet: not claimable', () {
      expect(_claims(held: BigInt.from(2072917)), isEmpty);
    });

    test('a result on chain claims what the wallet holds now', () {
      final claims =
          _claims(held: BigInt.from(1500000), payout: 1, closed: _closed());
      expect(claims, hasLength(1));
      final c = claims.single;
      expect(c.size, closeTo(1.5, 1e-9));
      expect(c.currentValue, closeTo(1.5, 1e-9));
      expect(c.curPrice, 1);
      expect(c.redeemable, isTrue);
      expect(c.negativeRisk, isFalse);
    });

    test('a lost side comes back to be cleared, worth nothing', () {
      final c = _claims(held: BigInt.from(2000000), payout: 0).single;
      expect(c.curPrice, 0);
      expect(c.currentValue, 0);
      expect(c.redeemable, isTrue);
    });

    test('a neg-risk market keeps its redeem path', () {
      final c = _claims(
              held: BigInt.from(2000000), payout: 1, negRisk: {_condition})
          .single;
      expect(c.negativeRisk, isTrue);
    });

    test('a condition already open is not added twice', () {
      expect(
          PolymarketTradingNotifier.heldClosedClaims(
            closed: [_closed()],
            openConditionIds: const {_condition},
            balances: {_g2: BigInt.from(2000000)},
            settledPayouts: const {_g2: 1},
          ),
          isEmpty);
    });
  });

  group('holdUntilFinalized', () {
    final hold = PolymarketTradingNotifier.holdUntilFinalized;

    test('redeemable on the Data API but not on chain: waits', () {
      final out = hold([_open(redeemable: true)], {_condition: false});
      expect(out.single.redeemable, isFalse);
      expect(out.single.size, 2.07);
    });

    test('on chain: claimable', () {
      expect(hold([_open(redeemable: true)], {_condition: true}).single
          .redeemable, isTrue);
    });

    test('unknown (RPC failure): the flag stays, a claim is not blocked', () {
      expect(hold([_open(redeemable: true)], {_condition: null}).single
          .redeemable, isTrue);
    });

    test('other positions are untouched', () {
      final other = _open(redeemable: true, condition: '0xother');
      final out = hold([other, _open(redeemable: false)], {_condition: false});
      expect(out.first.redeemable, isTrue);
      expect(out.last.redeemable, isFalse);
    });
  });

  group('nothingHeldToClaim', () {
    final check = PolymarketTradingNotifier.nothingHeldToClaim;
    const ids = [_g2, 'shinden-token'];

    test('sold down to dust on both sides: nothing to claim', () {
      expect(
          check(ids, {_g2: BigInt.from(2917), 'shinden-token': BigInt.zero}),
          isTrue);
    });

    test('shares still held: the claim goes ahead', () {
      expect(
          check(ids, {_g2: BigInt.from(2072917), 'shinden-token': BigInt.zero}),
          isFalse);
    });

    test('a failed read never blocks a claim', () {
      expect(check(ids, const {}), isFalse);
      expect(check(ids, {_g2: BigInt.zero}), isFalse);
    });
  });
}
