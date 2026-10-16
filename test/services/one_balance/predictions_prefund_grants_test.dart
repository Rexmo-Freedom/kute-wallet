import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/services/one_balance/predictions_venue_funder.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';

const _spark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _foreignSpark =
    'spark1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc489gg2';
const _pm = '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359';
const _otherPm = '0x0000000000000000000000000000000000000001';
final _now = DateTime.utc(2026, 9, 15, 12);

SensitiveIntent _review({String ownPredictions = _pm, double usd = 10}) =>
    PredictionPrefundGrants.review(
      walletId: 'w',
      ownPredictions: ownPredictions,
      ownSpark: _spark,
      fundUsd: usd,
      dollarsUsd: usd,
      bitcoinUsd: 6,
      directLegs: DirectLegGrants.limit(
          destination: 'predictions', capsUsd: {'investing': 4}),
      btcLeg: BitcoinLegGrants.limitWithDirect(
          maxSats: 120000,
          ownSpark: _spark,
          venue: 'predictions',
          ownVenue: ownPredictions,
          directMaxSats: 120000),
    );

AuthGrant _grant([SensitiveIntent? intent]) =>
    AuthGrants.issue(intent ?? _review(),
        method: AuthGrantMethod.biometric, now: _now);

SettlementAuthorizationIntent _settlement({
  String source = 'USDB',
  String recipient = _pm,
  String refund = _spark,
  String wallet = 'w',
  int amount = 6000000,
  String id = 'q_prefund',
  bool viaDollars = false,
  String? route,
}) {
  final destination = viaDollars ? _spark : recipient;
  final toChain = viaDollars ? 'spark' : 'polygon';
  final toAsset = viaDollars ? 'USDB' : 'USDC.e';
  final request = OrchestraQuoteRequest(
      sourceChain: 'spark',
      sourceAsset: source,
      destinationChain: toChain,
      destinationAsset: toAsset,
      amountBaseUnits: BigInt.from(amount),
      recipientAddress: destination,
      refundAddress: refund,
      recipientKind:
          viaDollars ? RecipientKind.ownSpark : RecipientKind.ownPmWallet,
      ownAddress: destination);
  final quote = verifyOrchestraQuote(
      request,
      OrchestraQuote.fromJson({
        'quoteId': id,
        'depositAddress': _foreignSpark,
        'amountIn': '$amount',
        'estimatedOut': '5900000',
        'feeAmount': '0',
        'feeBps': 0,
        'totalFeeAmount': '0',
        'feeAsset': toAsset,
        'route': ['spark:$source', '$toChain:$toAsset'],
        'expiresAt': '2026-09-15T12:02:00Z',
        'priceLockMode': 'floating',
        'readToken': 'fixture',
      }),
      now: _now,
      bounds: OrchestraQuoteBounds.forSource('spark',
          inputValueInOutputUnits: 6000000),
      mainnet: true);
  return SettlementAuthorizationIntent(
      flow: viaDollars
          ? SettlementFlow.moveBtcToUsdc
          : source == 'BTC'
              ? SettlementFlow.moveBtcToPredictions
              : SettlementFlow.moveUsdToPredictions,
      walletId: wallet,
      destination: '$destination|v1',
      routeLabel: route ?? request.routeLabel,
      amountIn: BigInt.from(amount),
      minReceive: BigInt.zero,
      maxFeeBps: 0,
      reviewedQuote: quote);
}

void main() {
  setUp(() => AuthGrants.clock = () => _now);
  tearDown(() => AuthGrants.clock = DateTime.now);

  test('transfer purpose uses the backend-supported manual move quote tag', () {
    expect(
        predictionsQuoteTag('predictions_prefund'), kManualMoveQuoteTag);
  });

  test('transfer approval cannot pass a buy or funded-bet grant gate', () {
    final grant = _grant();
    expect(PredictionPrefundGrants.isTransfer(grant), isTrue);
    expect(grant.action, SensitiveAction.moveTransfer);
    expect(
        () => GrantGuard.consume(grant, grant.boundIntent,
            allowed: PmGrants.orderActions(true)),
        throwsA(isA<ReauthRequired>()));
    expect(
        PmGrants.fundingGrantCovers(grant,
            amountIn: BigInt.one, venue: IntentVenue.polymarket),
        isFalse);
  });

  test('Dollars guard accepts verified own route within its cumulative cap',
      () {
    final grant = _grant();
    bool take(int amount, String id) =>
        PredictionsVenueFunder.fundingAuthorized(
            UserGrantAuthorization(grant), _settlement(amount: amount, id: id),
            ownAccount: _pm, sessionUnlocked: true);
    expect(take(6000000, 'first'), isTrue);
    expect(take(6000000, 'first'), isFalse, reason: 'same accepted quote');
    expect(take(4000000, 'second'), isTrue);
    expect(take(1, 'over'), isFalse);
  });

  test('Dollars guard rejects generic Move and altered transfer markers', () {
    final review = _review();
    for (final intent in [
      review.copyWith(limits: {}),
      SensitiveIntent(
          action: review.action,
          walletId: review.walletId,
          venue: IntentVenue.hyperliquid,
          asset: review.asset,
          amountMax: review.amountMax,
          limits: review.limits,
          destination: review.destination),
      review.copyWith(asset: 'BTC'),
      review.copyWith(amountMax: IntentUnits.usd(11)),
      review.copyWith(destination: ''),
    ]) {
      expect(
          PredictionsVenueFunder.fundingAuthorized(
              UserGrantAuthorization(_grant(intent)), _settlement(),
              ownAccount: _pm, sessionUnlocked: true),
          isFalse);
    }
  });

  test('Dollars guard binds wallet, recipient, refund and source route', () {
    for (final settlement in [
      _settlement(wallet: 'other'),
      _settlement(recipient: _otherPm),
      _settlement(refund: _foreignSpark),
      _settlement(source: 'BTC', amount: 100000),
      _settlement(route: 'spark_usdb>hypercore_usdc'),
    ]) {
      expect(
          PredictionsVenueFunder.fundingAuthorized(
              UserGrantAuthorization(_grant()), settlement,
              ownAccount: _pm, sessionUnlocked: true),
          isFalse);
    }
    expect(
        PredictionsVenueFunder.fundingAuthorized(
            UserGrantAuthorization(_grant()), _settlement(),
            ownAccount: _otherPm, sessionUnlocked: true),
        isFalse);
  });

  test('Dollars require a verified quote for exactly the amount being paid',
      () {
    final real = _settlement();
    for (final verified in [null, real.reviewedQuote]) {
      final attempted = SettlementAuthorizationIntent(
          flow: real.flow,
          walletId: real.walletId,
          destination: real.destination,
          routeLabel: real.routeLabel,
          amountIn: real.amountIn + BigInt.one,
          minReceive: BigInt.zero,
          maxFeeBps: 0,
          reviewedQuote: verified);
      expect(
          PredictionPrefundGrants.takeFunding(_grant(), attempted,
              ownPredictions: _pm),
          isFalse);
    }
  });

  test('Dollars route cap cannot be borrowed from unspent direct source caps',
      () {
    final review = _review();
    final grant = _grant(review.copyWith(limits: {
      ...review.limits,
      'dollarsUsd': '2000000',
    }));
    expect(
        PredictionPrefundGrants.takeFunding(grant, _settlement(amount: 3000000),
            ownPredictions: _pm),
        isFalse);
    expect(
        PredictionPrefundGrants.takeFunding(grant, _settlement(amount: 2000000),
            ownPredictions: _pm),
        isTrue);
  });

  test('parallel destination legs share one aggregate cap in every order', () {
    for (final order in ['DBV', 'DVB', 'BDV', 'BVD', 'VDB', 'VBD']) {
      final grant = _grant(_review(usd: 12));
      for (final source in order.split('')) {
        final accepted = switch (source) {
          'D' => PredictionPrefundGrants.takeFunding(
              grant, _settlement(amount: 2000000),
              ownPredictions: _pm),
          'B' => BitcoinLegGrants.takeDirect(
              grant, _settlement(source: 'BTC', amount: 100000),
              ownVenue: _pm, ownSpark: _spark),
          _ => DirectLegGrants.take(grant,
              venue: 'investing',
              destination: 'predictions',
              amount: BigInt.from(4000000)),
        };
        expect(accepted, isTrue, reason: order);
      }
      expect(
          PredictionPrefundGrants.takeFunding(
              grant, _settlement(amount: 1, id: 'extra'),
              ownPredictions: _pm),
          isFalse);
    }
  });

  test('direct Bitcoin consumes aggregate budget before any other send', () {
    final grant = _grant();
    expect(
        BitcoinLegGrants.takeDirect(
            grant, _settlement(source: 'BTC', amount: 100000),
            ownVenue: _pm, ownSpark: _spark),
        isTrue);
    expect(
        PredictionPrefundGrants.takeFunding(grant, _settlement(amount: 5000000),
            ownPredictions: _pm),
        isFalse);
    expect(
        PredictionPrefundGrants.takeFunding(grant, _settlement(amount: 4000000),
            ownPredictions: _pm),
        isTrue);
    expect(
        DirectLegGrants.take(grant,
            venue: 'investing', destination: 'predictions', amount: BigInt.one),
        isFalse);
  });

  test('via Dollars Bitcoin is counted only on its onward destination send',
      () {
    final grant = _grant();
    expect(
        BitcoinLegGrants.take(
            grant, _settlement(source: 'BTC', amount: 100000, viaDollars: true),
            ownSpark: _spark),
        isTrue);
    expect(
        PredictionPrefundGrants.takeFunding(grant, _settlement(amount: 6000000),
            ownPredictions: _pm),
        isTrue);
    expect(
        DirectLegGrants.take(grant,
            venue: 'investing',
            destination: 'predictions',
            amount: BigInt.from(4000000)),
        isTrue);
    expect(
        PredictionPrefundGrants.takeFunding(
            grant, _settlement(amount: 1, id: 'extra'),
            ownPredictions: _pm),
        isFalse);
  });

  test('a full Dollars send prevents an additional direct Bitcoin payment', () {
    final grant = _grant();
    expect(
        PredictionPrefundGrants.takeFunding(
            grant, _settlement(amount: 10000000),
            ownPredictions: _pm),
        isTrue);
    expect(
        BitcoinLegGrants.takeDirect(
            grant, _settlement(source: 'BTC', amount: 100000),
            ownVenue: _pm, ownSpark: _spark),
        isFalse);
    expect(BitcoinLegGrants.takenBy(grant), isFalse);
  });

  test('Dollars guard rejects locked, expired, revoked and consumed grants',
      () {
    final revoked = _grant()..revoke();
    final consumed = _grant();
    AuthGrants.consume(consumed, consumed.boundIntent);
    for (final grant in [revoked, consumed]) {
      expect(
          PredictionPrefundGrants.takeFunding(grant, _settlement(),
              ownPredictions: _pm),
          isFalse);
    }
    expect(
        PredictionPrefundGrants.takeFunding(_grant(), _settlement(),
            ownPredictions: _pm, now: _now.add(const Duration(hours: 1))),
        isFalse);
    expect(
        PredictionsVenueFunder.fundingAuthorized(
            UserGrantAuthorization(_grant()), _settlement(),
            ownAccount: _pm, sessionUnlocked: false),
        isFalse);
  });

  test('Bitcoin direct or via Dollars shares one capped payment', () {
    final grant = _grant();
    expect(
        BitcoinLegGrants.takeDirect(
            grant, _settlement(source: 'BTC', amount: 100000),
            ownVenue: _pm, ownSpark: _spark),
        isTrue);
    expect(
        BitcoinLegGrants.take(
            grant, _settlement(source: 'BTC', amount: 100000, viaDollars: true),
            ownSpark: _spark),
        isFalse);
    final via = _grant();
    expect(
        BitcoinLegGrants.take(
            via, _settlement(source: 'BTC', amount: 100000, viaDollars: true),
            ownSpark: _spark),
        isTrue);
    expect(
        BitcoinLegGrants.takeDirect(
            via, _settlement(source: 'BTC', amount: 100000),
            ownVenue: _pm, ownSpark: _spark),
        isFalse);
  });

  test('Bitcoin transfer refuses another account, route, refund and overcap',
      () {
    final grant = _grant();
    for (final s in [
      _settlement(source: 'BTC', amount: 120001),
      _settlement(source: 'BTC', amount: 100000, recipient: _otherPm),
      _settlement(source: 'BTC', amount: 100000, refund: _foreignSpark),
      _settlement(source: 'BTC', amount: 100000, wallet: 'other'),
      _settlement(
          source: 'BTC',
          amount: 100000,
          route: BitcoinLegGrants.directInvestingRoute),
    ]) {
      expect(
          BitcoinLegGrants.coversDirect(grant, s,
              ownVenue: _pm, ownSpark: _spark),
          isFalse);
    }
    expect(
        BitcoinLegGrants.coversDirect(_grant(_review(ownPredictions: _otherPm)),
            _settlement(source: 'BTC', amount: 100000),
            ownVenue: _pm, ownSpark: _spark),
        isFalse);
    expect(
        BitcoinLegGrants.covers(
            _grant(_review().copyWith(limits: {
              ..._review().limits,
              IntentLimit.orderKind: 'other_move',
            })),
            _settlement(source: 'BTC', amount: 100000, viaDollars: true),
            ownSpark: _spark),
        isFalse);
  });

  test('venue source caps target Predictions only and remain cumulative', () {
    final grant = _grant();
    bool take(String to, int amount) => DirectLegGrants.take(grant,
        venue: 'investing', destination: to, amount: BigInt.from(amount));
    expect(take('bitcoin', 1), isFalse);
    expect(take('predictions', 3000000), isTrue);
    expect(take('predictions', 1000000), isTrue);
    expect(take('predictions', 1), isFalse);
    expect(
        PredictionPrefundGrants.matchesAccount(grant,
            walletId: 'other', ownPredictions: _pm),
        isFalse);
    expect(
        PredictionPrefundGrants.matchesAccount(grant,
            walletId: 'w', ownPredictions: _otherPm),
        isFalse);
  });
}
