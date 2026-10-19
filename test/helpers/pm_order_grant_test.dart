// placeOrder's own grant check (`PmGrants.consumeOrder`) against the
// grants the queued-bet autofire hands it. A funded bet's one approval
// also binds its funding leg (cap, venue, venue-cash legs, Bitcoin leg);
// placeOrder cannot know those and moves no funding, so they are carried
// from the grant. Every order bound is still rebuilt and compared: a
// wider order (price, amount, token, side) throws ReauthRequired, nothing
// is signed. Pure: no venue, nothing sent.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/providers/pending_bet_autofire.dart'
    show autofireRetryGrant;
import 'package:kute/services/tracking_service.dart';

const _token = '9001';

void main() {
  final btcLeg = BitcoinLegGrants.limit(maxSats: 6000, ownSpark: 'spark1own');
  final directLegs = <String, Object?>{
    'to': IntentVenue.polymarket,
    'legs': {'hyperliquid': '300000'},
    'total': '300000',
  };

  /// The slip's one approval for a $5 bet funded from Bitcoin: worst price
  /// 0.81, slippage 5%, funding cap $5.30.
  AuthGrant approval() {
    final review = PmGrants.betReview(
      walletId: 'spending',
      tokenId: _token,
      maxCostUsd: 5.02,
      worstPrice: 0.81,
      orderType: 'fak',
    );
    return AuthGrants.issue(
      PmGrants.fundedBetReview(
        review.copyWith(limits: {
          ...review.limits,
          IntentLimit.maxSlippageBps: 500,
        }),
        fundUsd: 5.30,
        venue: IntentVenue.polymarket,
        directLegs: directLegs,
        btcLeg: btcLeg,
      ),
      method: AuthGrantMethod.biometric,
    );
  }

  /// What the autofire builds for the order it places (pending_bet_autofire
  /// `withFunding(PmIntents.order(...))`).
  SensitiveIntent autofireOrder(AuthGrant parent,
      {double shares = 6.19, double price = 0.807, String token = _token}) {
    final order = PmIntents.order(
      walletId: 'spending',
      tokenId: token,
      isBuy: true,
      amountMax: PmGrants.buyCostMicros(shares, price),
      limitPrice: price,
      orderType: 'fak',
      maxSlippageBps: 500,
    );
    return order.copyWith(limits: {
      ...order.limits,
      ...PmGrants.fundingLimits(
          fundUsd: 5.30,
          venue: IntentVenue.polymarket,
          directLegs: directLegs,
          btcLeg: btcLeg),
    });
  }

  void place(AuthGrant grant,
          {double shares = 6.19,
          double price = 0.807,
          String token = _token,
          bool isBuy = true,
          String orderType = 'fak'}) =>
      PmGrants.consumeOrder(grant,
          walletId: 'spending',
          tokenId: token,
          isBuy: isBuy,
          size: shares,
          price: price,
          orderType: orderType);

  test('the chained order grant of a funded bet passes placeOrder\'s check',
      () {
    final parent = approval();
    final actual = autofireOrder(parent);
    AuthGrants.consume(parent, actual);
    final child = GrantGuard.chain(parent, actual);
    expect(() => place(child), returnsNormally);
    expect(child.consumed, isTrue);
  });

  test('the funding leg is carried from the grant, unchanged', () {
    final parent = approval();
    final child = GrantGuard.chain(parent, autofireOrder(parent));
    final executed = PmGrants.executedOrder(child,
        walletId: 'spending',
        tokenId: _token,
        isBuy: true,
        size: 6.19,
        price: 0.807,
        orderType: 'fak');
    for (final key in PmGrants.fundingLegKeys) {
      expect(executed.limits[key], child.boundIntent.limits[key], reason: key);
    }
    // An unfunded grant carries nothing it does not bind.
    final plain = AuthGrants.issue(
        PmGrants.betReview(
            walletId: 'spending',
            tokenId: _token,
            maxCostUsd: 5,
            worstPrice: 0.81,
            orderType: 'fak'),
        method: AuthGrantMethod.biometric);
    final bare = PmGrants.executedOrder(plain,
        walletId: 'spending',
        tokenId: _token,
        isBuy: true,
        size: 6,
        price: 0.8,
        orderType: 'fak');
    expect(bare.limits.keys.toSet().intersection(PmGrants.fundingLegKeys),
        isEmpty);
  });

  group('a wider order still throws, nothing consumed', () {
    void refused(void Function(AuthGrant) placeIt, DriftField field,
        {String? key}) {
      final parent = approval();
      final child = GrantGuard.chain(parent, autofireOrder(parent));
      late ReauthRequired e;
      try {
        placeIt(child);
        fail('placed');
      } on ReauthRequired catch (err) {
        e = err;
      }
      expect(e.fieldClasses, contains(field));
      if (key != null) expect(e.toString(), contains('${field.name}: $key'));
      expect(child.consumed, isFalse);
    }

    test('higher price', () {
      refused((g) => place(g, price: 0.82), DriftField.price,
          key: IntentLimit.limitPrice);
    });
    test('more shares (amount)', () {
      refused((g) => place(g, shares: 6.5), DriftField.amount);
    });
    test('another token', () {
      refused((g) => place(g, token: '9002'), DriftField.destination);
    });
    test('the other side', () {
      refused((g) => place(g, isBuy: false), DriftField.action);
    });
    test('another order type', () {
      refused((g) => place(g, orderType: 'gtc'), DriftField.other,
          key: VenueLimit.orderType);
    });
  });

  test('a builder run grant is never carried into a single order', () {
    final leg = PmGrants.betReview(
        walletId: 'spending',
        tokenId: _token,
        maxCostUsd: 5,
        worstPrice: 0.81,
        orderType: 'fak');
    final run = AuthGrants.issue(
        PmGrants.builderRun(walletId: 'spending', legs: [leg]),
        method: AuthGrantMethod.biometric);
    expect(() => place(run, shares: 6, price: 0.8),
        throwsA(isA<ReauthRequired>()));
    expect(run.consumed, isFalse);
  });

  group('the autofire\'s send again (autofireRetryGrant)', () {
    test('inside the approval: chained, and placeOrder takes it', () {
      final parent = approval();
      AuthGrants.consume(parent, autofireOrder(parent));
      final retry = autofireRetryGrant(
          parent, autofireOrder(parent, shares: 6.1, price: 0.80));
      expect(() => place(retry, shares: 6.1, price: 0.80), returnsNormally);
    });

    test('a worse price than approved: ReauthRequired(price)', () {
      final parent = approval();
      AuthGrants.consume(parent, autofireOrder(parent));
      expect(
          () => autofireRetryGrant(
              parent, autofireOrder(parent, shares: 6, price: 0.83)),
          throwsA(isA<ReauthRequired>().having(
              (e) => e.fieldClasses, 'fields', contains(DriftField.price))));
    });

    test('a different funding leg: ReauthRequired(funding), key named', () {
      final parent = approval();
      final wider = autofireOrder(parent);
      final drifted = wider.copyWith(limits: {
        ...wider.limits,
        VenueLimit.fundingUsd: IntentUnits.usd(9).toString(),
      });
      expect(
          () => autofireRetryGrant(parent, drifted),
          throwsA(isA<ReauthRequired>()
              .having((e) => e.fieldClasses, 'fields', {DriftField.funding})
              .having((e) => e.toString(), 'toString',
                  'ReauthRequired(funding: fundingUsd)')));
    });
  });

  group('ReauthRequired diagnostics', () {
    test('every funding key maps to DriftField.funding', () {
      expect(AuthGrants.fundingKeys, PmGrants.fundingLegKeys);
      final parent = approval();
      final actual = autofireOrder(parent);
      final bare = actual.copyWith(limits: {
        for (final e in actual.limits.entries)
          if (!PmGrants.fundingLegKeys.contains(e.key)) e.key: e.value,
      });
      final e = AuthGrants.driftError(parent.boundIntent, bare)!;
      expect(e.fieldClasses, {DriftField.funding});
      expect(e.limitKeys[DriftField.funding], PmGrants.fundingLegKeys);
      expect(e.toString(),
          'ReauthRequired(funding: directLegs,fundBtc,fundingUsd,fundingVenue)');
    });

    test('names only, never values; analytics categories unchanged', () {
      final e = ReauthRequired(const {DriftField.price, DriftField.fee},
          limitKeys: const {
            DriftField.price: {'limitPrice'},
            DriftField.fee: {'maxFee'},
          });
      expect(e.toString(), 'ReauthRequired(price: limitPrice; fee: maxFee)');
      expect(e.fieldSummary, 'ReauthRequired(price,fee)');
      // Classified on the field classes, as before the key names.
      expect(TrackingService.errorCategory(e),
          TrackingService.errorCategory('ReauthRequired(price,fee)'));
      expect(
          TrackingService.errorCategory(
              ReauthRequired(const {DriftField.price},
                  limitKeys: const {DriftField.price: {'limitPrice'}})),
          isNot('above_limit'));
    });
  });
}
