// The Predictions funder's rules: what its estimate says, when the one
// approval of a funded bet covers the move, when the sweeper may pay a
// withdrawal without a tap, and the Activity row it writes.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/settlement_operation.dart' show SettlementFlow;
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementAuthorizationIntent;
import 'package:kute/services/one_balance/predictions_venue_funder.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/one_balance/venue_sweeper.dart'
    show SweepableVenueFunder;
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';

const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _pmWallet = '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359';
const _otherEvm = '0x0000000000000000000000000000000000000001';
const _flashnetEvm = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
final _now = DateTime.utc(2026, 9, 15, 12);

OrchestraQuote _quote(String name) => OrchestraQuote.fromJson(
    jsonDecode(File('test/services/fixtures/orchestra_quote_$name.json')
        .readAsStringSync()) as Map<String, dynamic>);

/// Polymarket USDC.e → own Spark, verified through the quote gate.
VerifiedOrchestraQuote _sweepQuote({
  RecipientKind kind = RecipientKind.ownSpark,
  String recipient = _ownSpark,
}) =>
    verifyOrchestraQuote(
      OrchestraQuoteRequest(
        sourceChain: 'polygon',
        sourceAsset: 'USDC.e',
        destinationChain: 'spark',
        destinationAsset: 'BTC',
        amountBaseUnits: BigInt.from(50000000),
        recipientAddress: recipient,
        refundAddress: _pmWallet,
        recipientKind: kind,
        ownAddress: recipient,
      ),
      _quote('polygon_to_spark'),
      now: _now,
      bounds: OrchestraQuoteBounds.forSource('polygon',
          inputValueInOutputUnits: 83333),
      mainnet: true,
    );

/// Spark → Polymarket wallet, verified through the quote gate.
VerifiedOrchestraQuote _fundingQuote({String recipient = _pmWallet}) =>
    verifyOrchestraQuote(
      OrchestraQuoteRequest(
        sourceChain: 'spark',
        sourceAsset: 'BTC',
        destinationChain: 'polygon',
        destinationAsset: 'USDC.e',
        amountBaseUnits: BigInt.from(100000),
        recipientAddress: recipient,
        refundAddress: _ownSpark,
        recipientKind: RecipientKind.ownPmWallet,
        ownAddress: recipient,
      ),
      _quote('spark_to_polygon'),
      now: _now,
      bounds: OrchestraQuoteBounds.forSource('spark',
          inputValueInOutputUnits: 60000000),
      mainnet: true,
    );

AuthGrant _fundedGrant({double fundUsd = 5.3, String venue = 'polymarket'}) =>
    AuthGrants.issue(
      PmGrants.fundedBetReview(
        PmGrants.betReview(
          walletId: 'w',
          tokenId: 't',
          maxCostUsd: 10.2,
          worstPrice: 0.6,
          orderType: 'fak',
        ),
        fundUsd: fundUsd,
        venue: venue,
      ),
      method: AuthGrantMethod.biometric,
      now: _now,
    );

SettlementAuthorizationIntent _intent({
  SettlementFlow flow = SettlementFlow.moveUsdToPredictions,
  String recipient = _pmWallet,
  BigInt? amountIn,
  VerifiedOrchestraQuote? reviewed,
}) =>
    SettlementAuthorizationIntent(
      flow: flow,
      walletId: 'w',
      destination: '$recipient|v1',
      routeLabel: 'spark:USDB->polygon:USDC.e',
      amountIn: amountIn ?? BigInt.from(5300000),
      minReceive: BigInt.from(5200000),
      maxFeeBps: 100,
      reviewedQuote: reviewed,
    );

void main() {
  tearDown(() => PredictionsVenueFunder.debugRouteShare = null);

  group('estimate', () {
    test('answers from the route share, the app minimum as the floor',
        () async {
      PredictionsVenueFunder.debugRouteShare = (usd) async => 0.006;
      final funder = PredictionsVenueFunder(<T>(_) => throw StateError('no'));
      final q = await funder.estimate(10);
      expect(q.arrivingUsd, closeTo(9.94, 1e-9));
      expect(q.feeUsd, closeTo(0.06, 1e-9));
      expect(q.fixedCostUsd, 0);
      expect(q.minUsd, kPredictionsMinMoveUsd);
      expect(await funder.minimumUsd(), 1.0);
    });

    test('routeShareFrom folds the Kute rate in when the estimate left it out',
        () {
      OrchestraEstimate est({bool? includes, int? bps}) => OrchestraEstimate(
          estimatedOut: '0',
          feeAmount: '0',
          feeBps: 0,
          route: const [],
          kuteAppFeeBps: bps,
          estimateIncludesAppFee: includes);
      expect(
          PredictionsVenueFunder.routeShareFrom(est(includes: true, bps: 50),
              sentUsd: 10, arrivingUsd: 9.94),
          closeTo(0.006, 1e-9));
      final folded = PredictionsVenueFunder.routeShareFrom(
          est(includes: false, bps: 50),
          sentUsd: 10,
          arrivingUsd: 9.94)!;
      expect(folded, closeTo(1 - 0.994 * 0.995, 1e-9));
      expect(
          PredictionsVenueFunder.routeShareFrom(est(includes: false),
              sentUsd: 10, arrivingUsd: 9.94),
          isNull);
      expect(
          PredictionsVenueFunder.routeShareFrom(est(includes: true),
              sentUsd: 10, arrivingUsd: 0),
          isNull);
    });
  });

  group('fundingAuthorized', () {
    test('the funded bet grant covers a quote to the own account', () {
      expect(
          PredictionsVenueFunder.fundingAuthorized(
              UserGrantAuthorization(_fundedGrant()), _intent(),
              ownAccount: _pmWallet, sessionUnlocked: true, now: _now),
          isTrue);
    });

    test('refuses a recipient that is not the wallet\'s own account', () {
      expect(
          PredictionsVenueFunder.fundingAuthorized(
              UserGrantAuthorization(_fundedGrant()),
              _intent(recipient: _otherEvm),
              ownAccount: _pmWallet,
              sessionUnlocked: true,
              now: _now),
          isFalse);
    });

    test('refuses a move above the approved cap, another venue, a sweep',
        () {
      expect(
          PredictionsVenueFunder.fundingAuthorized(
              UserGrantAuthorization(_fundedGrant()),
              _intent(amountIn: BigInt.from(5300001)),
              ownAccount: _pmWallet,
              sessionUnlocked: true,
              now: _now),
          isFalse);
      expect(
          PredictionsVenueFunder.fundingAuthorized(
              UserGrantAuthorization(_fundedGrant(venue: 'hyperliquid')),
              _intent(),
              ownAccount: _pmWallet,
              sessionUnlocked: true,
              now: _now),
          isFalse);
      expect(
          PredictionsVenueFunder.fundingAuthorized(
              SweepAuthorization.automatic, _intent(),
              ownAccount: _pmWallet, sessionUnlocked: true, now: _now),
          isFalse);
    });

    test('refuses a locked session, a spent or expired grant, another flow',
        () {
      final grant = _fundedGrant();
      expect(
          PredictionsVenueFunder.fundingAuthorized(
              UserGrantAuthorization(grant), _intent(),
              ownAccount: _pmWallet, sessionUnlocked: false, now: _now),
          isFalse);
      expect(
          PredictionsVenueFunder.fundingAuthorized(
              UserGrantAuthorization(grant), _intent(),
              ownAccount: _pmWallet,
              sessionUnlocked: true,
              now: _now.add(const Duration(hours: 1))),
          isFalse);
      grant.revoke();
      expect(
          PredictionsVenueFunder.fundingAuthorized(
              UserGrantAuthorization(grant), _intent(),
              ownAccount: _pmWallet, sessionUnlocked: true, now: _now),
          isFalse);
      expect(
          PredictionsVenueFunder.fundingAuthorized(
              UserGrantAuthorization(_fundedGrant()),
              _intent(flow: SettlementFlow.moveBtcToPredictions),
              ownAccount: _pmWallet,
              sessionUnlocked: true,
              now: _now),
          isFalse);
    });

    test('a reviewed quote must name the own Predictions account kind', () {
      final ok = _intent(reviewed: _fundingQuote());
      expect(
          PredictionsVenueFunder.fundingAuthorized(
              UserGrantAuthorization(_fundedGrant()), ok,
              ownAccount: _pmWallet, sessionUnlocked: true, now: _now),
          isTrue);
    });
  });

  group('sweepAuthorized', () {
    test('only an unlocked session, the cash-out flow and an own-Spark quote',
        () {
      final good = _intent(
          flow: SettlementFlow.movePredictionsToDollars,
          recipient: _ownSpark,
          reviewed: _sweepQuote());
      expect(
          PredictionsVenueFunder.sweepAuthorized(good, sessionUnlocked: true),
          isTrue);
      expect(
          PredictionsVenueFunder.sweepAuthorized(good, sessionUnlocked: false),
          isFalse);
      expect(
          PredictionsVenueFunder.sweepAuthorized(
              _intent(
                  flow: SettlementFlow.movePredictionsToDollars,
                  recipient: _ownSpark),
              sessionUnlocked: true),
          isFalse,
          reason: 'no reviewed quote');
      expect(
          PredictionsVenueFunder.sweepAuthorized(
              _intent(flow: SettlementFlow.moveUsdToPredictions,
                  reviewed: _sweepQuote()),
              sessionUnlocked: true),
          isFalse);
    });
  });

  group('PmGrants.sweepCoversWithdrawal', () {
    test('exact quote amount, bridged, to the quote deposit address', () {
      final quote = _sweepQuote();
      bool covers({
        String to = _flashnetEvm,
        BigInt? exact,
        bool bridged = true,
        RecipientKind kind = RecipientKind.ownSpark,
      }) =>
          PmGrants.sweepCoversWithdrawal(
            recipientKind: kind,
            quoteDepositAddress: quote.depositAddress,
            quoteAmountIn: quote.amountIn,
            toAddress: to,
            exactMicroUsdc: exact ?? quote.amountIn,
            bridged: bridged,
          );
      expect(covers(), isTrue);
      expect(covers(to: _flashnetEvm.toLowerCase()), isTrue);
      expect(covers(to: _otherEvm), isFalse);
      expect(covers(exact: null, bridged: true), isTrue);
      expect(
          PmGrants.sweepCoversWithdrawal(
            recipientKind: RecipientKind.ownSpark,
            quoteDepositAddress: quote.depositAddress,
            quoteAmountIn: quote.amountIn,
            toAddress: _flashnetEvm,
            exactMicroUsdc: null,
            bridged: true,
          ),
          isFalse,
          reason: 'a clamp-to-balance send is never a sweep');
      expect(covers(exact: quote.amountIn + BigInt.one), isFalse);
      expect(covers(bridged: false), isFalse);
      expect(covers(kind: RecipientKind.ownPmWallet), isFalse);
      expect(covers(kind: RecipientKind.external), isFalse);
    });
  });

  group('PmGrants.fundingGrantCovers', () {
    test('binds the cap and the venue exactly', () {
      final g = _fundedGrant(fundUsd: 5.3);
      expect(
          PmGrants.fundingGrantCovers(g,
              amountIn: BigInt.from(5300000), venue: 'polymarket', now: _now),
          isTrue);
      expect(
          PmGrants.fundingGrantCovers(g,
              amountIn: BigInt.from(100), venue: 'polymarket', now: _now),
          isTrue);
      expect(
          PmGrants.fundingGrantCovers(g,
              amountIn: BigInt.zero, venue: 'polymarket', now: _now),
          isFalse);
      expect(
          PmGrants.fundingGrantCovers(g,
              amountIn: BigInt.from(5300001), venue: 'polymarket', now: _now),
          isFalse);
      expect(
          PmGrants.fundingGrantCovers(g,
              amountIn: BigInt.from(100), venue: 'hyperliquid', now: _now),
          isFalse);
      final plain = AuthGrants.issue(
          PmGrants.betReview(
              walletId: 'w',
              tokenId: 't',
              maxCostUsd: 10,
              worstPrice: 0.6,
              orderType: 'fak'),
          method: AuthGrantMethod.pin,
          now: _now);
      expect(
          PmGrants.fundingGrantCovers(plain,
              amountIn: BigInt.from(100), venue: 'polymarket', now: _now),
          isFalse,
          reason: 'a bet approval without the funding leg never funds');
    });

    test('fundedBetReview keeps the bet review and adds the two limits', () {
      final review = PmGrants.betReview(
          walletId: 'w',
          tokenId: 't',
          maxCostUsd: 10,
          worstPrice: 0.6,
          orderType: 'fak');
      final funded = PmGrants.fundedBetReview(review,
          fundUsd: 5.3, venue: 'polymarket');
      expect(funded.action, SensitiveAction.pmBet);
      expect(funded.amountMax, review.amountMax);
      expect(funded.limits[VenueLimit.fundingUsd], '5300000');
      expect(funded.limits[VenueLimit.fundingVenue], 'polymarket');
      expect(funded.limits[IntentLimit.limitPrice], 0.6);
    });
  });

  test('the Activity row reads as the Move sheet\'s Dollars deposit', () {
    final row = PredictionsVenueFunder.usdToPredictionsRow(
      id: 'q_fixture_spark_polygon',
      quote: _fundingQuote(),
      evm: _pmWallet,
      sparkRefund: _ownSpark,
      operationId: 'op',
      walletId: 'wallet',
    );
    expect(row.coinFrom, 'USDB');
    expect(row.networkFrom, 'SPARK');
    expect(row.coinTo, 'USDC');
    expect(row.networkTo, 'POLYGON');
    expect(row.withdrawalAmount, '58.80');
    expect(row.withdrawalAddress, _pmWallet);
    expect(row.refundAddress, _ownSpark);
    expect(row.status, 'exchanging');
    expect(row.provider, 'Orchestra');
    expect(row.operationId, 'op');
    expect(row.walletId, 'wallet');
  });

  test('quote flows are the strings the backend tags rows by', () {
    expect(kOrderFundingPredictionsFlow, 'order_funding_predictions');
    expect(kSweepPredictionsFlow, 'sweep_predictions');
    expect(predictionsQuoteTag('order_funding'),
        'kute:order_funding_predictions');
    expect(predictionsQuoteTag('sweep'), 'kute:sweep_predictions');
    expect(predictionsQuoteTag('rollout_sweep'),
        'kute:rollout_sweep_predictions');
    expect(predictionsQuoteTag('other'), 'kute:sweep_predictions');
  });

  test('the funder is both the order-funding and the sweeper door', () {
    final funder = PredictionsVenueFunder(<T>(_) => throw StateError('no'));
    expect(funder, isA<SweepableVenueFunder>());
    expect(funder, isA<VenueFunder>());
  });
}
