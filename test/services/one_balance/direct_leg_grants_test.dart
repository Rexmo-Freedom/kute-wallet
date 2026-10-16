// The one approval an action asks before venue cash moves for it binds
// the legs that go straight to its destination: a cap per venue and the
// total. A leg runs only while that approval is live, for that
// destination and within those caps; the automatic authorization is
// never one of them. The queued order and bet rebuild exactly what was
// approved, legs included.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/pending_hyperliquid_order_provider.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';

final _now = DateTime.utc(2026, 10, 13, 12);

AuthGrant _grant(
  Map<String, Object?>? legs, {
  SensitiveAction action = SensitiveAction.moveTransfer,
  Duration ttl = const Duration(minutes: 10),
}) =>
    AuthGrants.issue(
      SensitiveIntent(
        action: action,
        walletId: 'w',
        venue: IntentVenue.orchestra,
        destination: 'spark1self',
        asset: 'USDB',
        amountMax: IntentUnits.usd(50),
        limits: {
          IntentLimit.route: 'spark:USDB->spark:BTC',
          if (legs != null) VenueLimit.directLegs: legs,
        },
        ttl: ttl,
      ),
      method: AuthGrantMethod.biometric,
      now: _now,
    );

BigInt _usd(double usd) => IntentUnits.usd(usd);

void main() {
  group('DirectLegGrants', () {
    test('limit binds the destination, each venue cap and the total', () {
      final limit = DirectLegGrants.limit(
          destination: 'bitcoin',
          capsUsd: {'investing': 20.41, 'predictions': 5, 'none': 0})!;
      expect(limit, {
        'to': 'bitcoin',
        'legs': {'investing': '20410000', 'predictions': '5000000'},
        'total': '25410000',
      });
      expect(DirectLegGrants.limit(destination: 'bitcoin', capsUsd: {}),
          isNull);
    });

    test('a leg runs only within its venue cap, the total, once', () {
      final grant = _grant(DirectLegGrants.limit(
          destination: 'bitcoin',
          capsUsd: {'investing': 20, 'predictions': 10}));
      bool take(String venue, double usd, {String to = 'bitcoin'}) =>
          DirectLegGrants.take(grant,
              venue: venue, destination: to, amount: _usd(usd), now: _now);
      expect(take('investing', 20.01), isFalse, reason: 'past its cap');
      expect(take('investing', 12, to: 'predictions'), isFalse,
          reason: 'another destination');
      expect(take('bridge', 1), isFalse, reason: 'no such leg approved');
      expect(take('investing', 12), isTrue);
      expect(take('investing', 8), isTrue);
      expect(take('investing', 0.01), isFalse, reason: 'the cap is spent');
      expect(take('predictions', 10), isTrue);
      expect(DirectLegGrants.takenBy(grant), _usd(30));
      expect(grant.consumed, isFalse, reason: 'a leg never consumes it');
    });

    test('nothing runs once the approval is consumed, revoked or expired',
        () {
      Map<String, Object?>? legs() => DirectLegGrants.limit(
          destination: 'bitcoin', capsUsd: {'investing': 20});
      bool covers(AuthGrant g, {DateTime? at}) => DirectLegGrants.covers(g,
          venue: 'investing',
          destination: 'bitcoin',
          amount: _usd(5),
          now: at ?? _now);
      final consumed = _grant(legs());
      AuthGrants.consume(consumed, consumed.boundIntent, now: _now);
      expect(covers(consumed), isFalse, reason: 'the action already went');
      expect(covers(_grant(legs())..revoke()), isFalse);
      expect(
          covers(_grant(legs()), at: _now.add(const Duration(minutes: 11))),
          isFalse);
      expect(covers(_grant(null)), isFalse, reason: 'binds no leg');
      expect(
          covers(_grant(legs(), action: SensitiveAction.send)), isFalse,
          reason: 'only a Move, an order or a bet carries legs');
      expect(covers(_grant(legs(), action: SensitiveAction.pmBet)), isTrue);
      expect(covers(_grant(legs(), action: SensitiveAction.hlOrder)), isTrue);
    });

    test('the purchase pays under the same approval: own address, route, '
        'no more than approved', () {
      final grant = _grant(DirectLegGrants.limit(
          destination: 'bitcoin', capsUsd: {'investing': 20}));
      bool covers({
        String recipient = 'spark1self',
        String route = 'spark:USDB->spark:BTC',
        double usd = 30,
        String wallet = 'w',
      }) =>
          DirectLegGrants.coversPurchase(grant,
              walletId: wallet,
              recipient: recipient,
              routeLabel: route,
              amountIn: _usd(usd),
              now: _now);
      expect(covers(), isTrue);
      expect(covers(usd: 50.01), isFalse);
      expect(covers(recipient: 'spark1other'), isFalse);
      expect(covers(route: 'spark:USDB->polygon:USDC.e'), isFalse);
      expect(covers(wallet: 'w2'), isFalse);
      AuthGrants.consume(
          grant, GrantGuard.derive(grant, amountMax: _usd(30)), now: _now);
      expect(covers(), isFalse, reason: 'single use');
    });
  });

  group('the queued action rebuilds exactly what was approved', () {
    final legs = DirectLegGrants.limit(
        destination: 'investing', capsUsd: {'predictions': 12.25});

    test('an Investing order: the order, its funding and its legs', () {
      const market = HlMarket(
        coin: 'BTC',
        wireCoin: 'BTC',
        assetId: 0,
        kind: HlMarketKind.perp,
        szDecimals: 5,
        maxLeverage: 40,
        onlyIsolated: false,
        markPx: 100000,
        midPx: 100000,
        prevDayPx: 100000,
        dayNtlVlm: 0,
      );
      PendingHlOrderIntent pending(Map<String, Object?>? l) =>
          PendingHlOrderIntent(
            coin: 'BTC',
            kind: HlMarketKind.perp,
            isLong: true,
            marginUsd: 30,
            leverage: 2,
            slippagePct: 1,
            expectedPx: 100000,
            marketLabel: 'BTC',
            fundUsd: 20,
            directLegs: l,
          );
      final approved =
          pendingHlOrderAutofireIntent(pending(legs), market, walletId: 'w');
      expect(approved.limits[VenueLimit.directLegs], isNotNull);
      final grant = AuthGrants.issue(approved,
          method: AuthGrantMethod.biometric, now: _now);
      // The watcher's rebuild at placement time: no drift.
      final placed = pendingHlOrderAutofireIntent(
          pending(legs).copyWith(status: PendingHlOrderStatus.placing),
          market,
          walletId: 'w');
      expect(AuthGrants.driftBetween(grant.boundIntent, placed), isEmpty);
      // Different legs are a different approval.
      final other = pendingHlOrderAutofireIntent(
          pending(DirectLegGrants.limit(
              destination: 'investing', capsUsd: {'predictions': 40})),
          market,
          walletId: 'w');
      expect(AuthGrants.driftBetween(grant.boundIntent, other), isNotEmpty);
      expect(
          DirectLegGrants.covers(grant,
              venue: 'predictions',
              destination: 'investing',
              amount: _usd(12.25),
              now: _now),
          isTrue);
    });

    test('a prediction: the bet, its funding and its legs', () {
      final review = PmGrants.betReview(
          walletId: 'w',
          tokenId: 't',
          maxCostUsd: 10.2,
          worstPrice: 0.6,
          orderType: 'fak');
      final betLegs = DirectLegGrants.limit(
          destination: 'predictions', capsUsd: {'investing': 6.5});
      final approved = PmGrants.fundedBetReview(review,
          fundUsd: 8, venue: IntentVenue.polymarket, directLegs: betLegs);
      // What the autofire puts on the order it signs.
      final rebuilt = review.copyWith(limits: {
        ...review.limits,
        ...PmGrants.fundingLimits(
            fundUsd: 8, venue: IntentVenue.polymarket, directLegs: betLegs),
      });
      expect(AuthGrants.driftBetween(approved, rebuilt), isEmpty);

      // The queued bet keeps its legs through every status change.
      const bet = PendingBetIntent(
        tokenId: 't',
        amount: 10,
        slippagePct: 5,
        marketQuestion: 'Q',
        outcomeName: 'Yes',
        expectedPrice: 0.5,
      );
      final queued = bet.copyWith(fundUsd: 8, directLegs: betLegs);
      expect(queued.directLegs, betLegs);
      expect(queued.copyWith(status: PendingBetStatus.placing).directLegs,
          betLegs);
      expect(queued.copyWith(directLegs: null).directLegs, isNull);
    });
  });
}
