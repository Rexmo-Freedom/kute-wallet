// The Bitcoin leg an order's one approval covers (BitcoinLegGrants): it
// pays only a verified spark:BTC → spark:USDB quote to and from the
// wallet's own Spark address, at most the bound sats, once, while the
// grant is live and for the grant's own wallet.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/settlement_operation.dart' show SettlementFlow;
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementAuthorizationIntent;
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';

const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
// A valid Spark address that is not the wallet's.
const _foreignSpark =
    'spark1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc489gg2';
const _pmWallet = '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359';
final _now = DateTime.utc(2026, 9, 15, 12);

OrchestraQuote _usdbQuote({int sats = 100000}) => OrchestraQuote.fromJson({
      'quoteId': 'q_fixture_spark_usdb',
      'depositAddress': _foreignSpark,
      'amountIn': '$sats',
      'estimatedOut': '${(sats * 600).round()}',
      'feeAmount': '0',
      'feeBps': 0,
      'totalFeeAmount': '0',
      'feeAsset': 'USDB',
      'route': ['spark:BTC', 'spark:USDB'],
      'expiresAt': '2026-09-15T12:02:00Z',
      'priceLockMode': 'floating',
      'readToken': 'rt_fixture',
    });

/// Own bitcoin → own dollars, verified through the quote gate. [recipient]
/// and [refund] stand in for a quote to someone else's address.
VerifiedOrchestraQuote _btcToUsdb({
  int sats = 100000,
  String recipient = _ownSpark,
  String refund = _ownSpark,
}) =>
    verifyOrchestraQuote(
      OrchestraQuoteRequest(
        sourceChain: 'spark',
        sourceAsset: 'BTC',
        destinationChain: 'spark',
        destinationAsset: 'USDB',
        amountBaseUnits: BigInt.from(sats),
        recipientAddress: recipient,
        refundAddress: refund,
        recipientKind: RecipientKind.ownSpark,
        ownAddress: recipient,
      ),
      _usdbQuote(sats: sats),
      now: _now,
      bounds: OrchestraQuoteBounds.forSource('spark',
          inputValueInOutputUnits: sats * 600.0),
      mainnet: true,
    );

/// Own bitcoin → the Predictions wallet: a different route.
VerifiedOrchestraQuote _btcToPolygon() => verifyOrchestraQuote(
      OrchestraQuoteRequest(
        sourceChain: 'spark',
        sourceAsset: 'BTC',
        destinationChain: 'polygon',
        destinationAsset: 'USDC.e',
        amountBaseUnits: BigInt.from(100000),
        recipientAddress: _pmWallet,
        refundAddress: _ownSpark,
        recipientKind: RecipientKind.ownPmWallet,
        ownAddress: _pmWallet,
      ),
      OrchestraQuote.fromJson(jsonDecode(
          File('test/services/fixtures/orchestra_quote_spark_to_polygon.json')
              .readAsStringSync()) as Map<String, dynamic>),
      now: _now,
      bounds: OrchestraQuoteBounds.forSource('spark',
          inputValueInOutputUnits: 60000000),
      mainnet: true,
    );

SettlementAuthorizationIntent _settlement(
  VerifiedOrchestraQuote quote, {
  String walletId = 'w',
  String? recipient,
  String routeLabel = BitcoinLegGrants.route,
  BigInt? amountIn,
}) =>
    SettlementAuthorizationIntent(
      flow: SettlementFlow.moveBtcToUsdc,
      walletId: walletId,
      destination: '${recipient ?? quote.request.recipientAddress}|',
      routeLabel: routeLabel,
      amountIn: amountIn ?? quote.amountIn,
      minReceive: BigInt.zero,
      maxFeeBps: 0,
      reviewedQuote: quote,
    );

AuthGrant _grant({
  int maxSats = 120000,
  String ownSpark = _ownSpark,
  String walletId = 'w',
  bool withLeg = true,
  SensitiveAction action = SensitiveAction.pmBet,
}) {
  final review = PmGrants.betReview(
    walletId: walletId,
    tokenId: 't',
    maxCostUsd: 10.2,
    worstPrice: 0.6,
    orderType: 'fak',
  );
  final intent = PmGrants.fundedBetReview(
    action == SensitiveAction.pmBet
        ? review
        : SensitiveIntent(
            action: action,
            walletId: walletId,
            venue: 'hyperliquid',
            asset: 'BTC',
            amountMax: BigInt.from(5000000)),
    fundUsd: 5.3,
    venue: 'polymarket',
    btcLeg: withLeg
        ? BitcoinLegGrants.limit(maxSats: maxSats, ownSpark: ownSpark)
        : null,
  );
  return AuthGrants.issue(intent.copyWith(ttl: AuthGrants.autofireTtl),
      method: AuthGrantMethod.biometric, now: _now);
}

void main() {
  setUp(() => AuthGrants.clock = () => _now);
  tearDown(() => AuthGrants.clock = DateTime.now);

  test('covers own bitcoin to own dollars within the bound sats', () {
    final grant = _grant();
    final s = _settlement(_btcToUsdb());
    expect(BitcoinLegGrants.binds(grant), isTrue);
    expect(BitcoinLegGrants.covers(grant, s, ownSpark: _ownSpark), isTrue);
  });

  test('refuses a route other than spark:BTC → spark:USDB', () {
    final grant = _grant();
    // The settlement says another route.
    expect(
        BitcoinLegGrants.covers(
            grant, _settlement(_btcToUsdb(), routeLabel: 'spark_btc>polygon_usdc.e'),
            ownSpark: _ownSpark),
        isFalse);
    // The verified quote itself is for another route.
    expect(
        BitcoinLegGrants.covers(grant,
            _settlement(_btcToPolygon(), recipient: _ownSpark),
            ownSpark: _ownSpark),
        isFalse);
  });

  test('refuses a foreign recipient or refund', () {
    final grant = _grant();
    expect(
        BitcoinLegGrants.covers(
            grant, _settlement(_btcToUsdb(recipient: _foreignSpark)),
            ownSpark: _ownSpark),
        isFalse);
    expect(
        BitcoinLegGrants.covers(
            grant, _settlement(_btcToUsdb(refund: _foreignSpark)),
            ownSpark: _ownSpark),
        isFalse);
    // The settlement's own recipient is someone else's.
    expect(
        BitcoinLegGrants.covers(
            grant, _settlement(_btcToUsdb(), recipient: _foreignSpark),
            ownSpark: _ownSpark),
        isFalse);
    // The grant was bound to another address than the wallet's now.
    expect(
        BitcoinLegGrants.covers(_grant(ownSpark: _foreignSpark),
            _settlement(_btcToUsdb()),
            ownSpark: _ownSpark),
        isFalse);
  });

  test('refuses more sats than approved, or a sats figure off the quote',
      () {
    final grant = _grant(maxSats: 99999);
    expect(
        BitcoinLegGrants.covers(grant, _settlement(_btcToUsdb()),
            ownSpark: _ownSpark),
        isFalse);
    expect(
        BitcoinLegGrants.covers(_grant(),
            _settlement(_btcToUsdb(), amountIn: BigInt.from(90000)),
            ownSpark: _ownSpark),
        isFalse);
  });

  test('refuses an expired, consumed or revoked grant', () {
    final s = _settlement(_btcToUsdb());
    final expired = _grant();
    expect(
        BitcoinLegGrants.covers(expired, s,
            ownSpark: _ownSpark,
            now: _now.add(AuthGrants.autofireTtl + const Duration(seconds: 1))),
        isFalse);
    final revoked = _grant()..revoke();
    expect(BitcoinLegGrants.covers(revoked, s, ownSpark: _ownSpark), isFalse);
    final consumed = _grant();
    AuthGrants.consume(consumed, consumed.boundIntent);
    expect(BitcoinLegGrants.covers(consumed, s, ownSpark: _ownSpark), isFalse);
  });

  test('refuses another wallet, a grant without the leg, another action',
      () {
    final s = _settlement(_btcToUsdb());
    expect(
        BitcoinLegGrants.covers(_grant(walletId: 'other'), s,
            ownSpark: _ownSpark),
        isFalse);
    expect(BitcoinLegGrants.covers(_grant(withLeg: false), s,
            ownSpark: _ownSpark),
        isFalse);
    expect(
        BitcoinLegGrants.covers(
            _grant(action: SensitiveAction.moveTransfer), s,
            ownSpark: _ownSpark),
        isFalse);
  });

  test('single use: a second leg under the same grant is refused', () async {
    final grant = _grant();
    final hook = BitcoinLegGrants.stepUp(grant, ownSpark: _ownSpark);
    expect(await hook(_settlement(_btcToUsdb())), isTrue);
    expect(BitcoinLegGrants.takenBy(grant), isTrue);
    expect(await hook(_settlement(_btcToUsdb())), isFalse);
    // The order itself still consumes the grant later: the leg never did.
    expect(grant.consumed, isFalse);
  });

  test('the leg is bound into the order digest: the autofire rebuild '
      'with the same leg matches, without it drifts', () {
    final leg = BitcoinLegGrants.limit(maxSats: 120000, ownSpark: _ownSpark);
    final review = PmGrants.betReview(
        walletId: 'w',
        tokenId: 't',
        maxCostUsd: 10.2,
        worstPrice: 0.6,
        orderType: 'fak');
    final approved = PmGrants.fundedBetReview(review,
        fundUsd: 5.3, venue: 'polymarket', btcLeg: leg);
    final same = PmGrants.fundedBetReview(review,
        fundUsd: 5.3, venue: 'polymarket', btcLeg: Map.of(leg));
    final without =
        PmGrants.fundedBetReview(review, fundUsd: 5.3, venue: 'polymarket');
    expect(AuthGrants.driftBetween(approved, same), isEmpty);
    expect(AuthGrants.driftBetween(approved, without), isNotEmpty);
  });
}
