import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/orchestra/orchestra_fee_amount.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import '../../helpers/runtime_policy_fixture.dart';

void main() {
  setUp(() => AffiliateService.debugSessionToken = 'test-session');
  tearDown(() => AffiliateService.debugSessionToken = null);

  test('venue-to-venue funding requires both withdrawal and deposit', () {
    expect(
        orchestraCapabilityRequirements(
            sourceChain: 'hypercore',
            sourceAsset: 'USDC',
            destinationChain: 'polygon',
            destinationAsset: 'USDC.e'),
        ['hyperliquid.withdraw', 'polymarket.deposit']);
    expect(
        orchestraCapabilityRequirements(
            sourceChain: 'polygon',
            sourceAsset: 'USDC.e',
            destinationChain: 'hypercore',
            destinationAsset: 'USDC'),
        ['polymarket.withdraw', 'hyperliquid.deposit']);
  });

  test('Polygon USDC.e exits are separate from generic Polygon crypto swaps',
      () {
    expect(
        orchestraCapabilityRequirements(
            sourceChain: 'polygon',
            sourceAsset: 'USDC.e',
            destinationChain: 'bitcoin',
            destinationAsset: 'BTC'),
        ['polymarket.withdraw']);
    expect(
        orchestraCapabilityRequirements(
            sourceChain: 'polygon',
            sourceAsset: 'MATIC',
            destinationChain: 'bitcoin',
            destinationAsset: 'BTC'),
        ['orchestra.swap', 'orchestra.swap.altcoins']);
  });

  // The backend's classification, mirrored: a non-venue route needs the
  // master switch and its class; bitcoin-only and dollar-balance moves need
  // the master alone; a venue leg answers to the venue rule only.
  test('cross-chain swaps need the master switch and their class', () {
    List<String> caps(String sc, String sa, String dc, String da) =>
        orchestraCapabilityRequirements(
            sourceChain: sc,
            sourceAsset: sa,
            destinationChain: dc,
            destinationAsset: da);
    expect(caps('bitcoin', 'BTC', 'base', 'USDC'),
        ['orchestra.swap', 'orchestra.swap.stablecoins']);
    expect(caps('tron', 'usdt', 'lightning', 'btc'),
        ['orchestra.swap', 'orchestra.swap.stablecoins']);
    expect(caps('base', 'USDC', 'solana', 'USDT'),
        ['orchestra.swap', 'orchestra.swap.stablecoins']);
    expect(caps('spark', 'BTC', 'ethereum', 'ETH'),
        ['orchestra.swap', 'orchestra.swap.altcoins']);
    expect(caps('solana', 'SOL', 'base', 'USDC'),
        ['orchestra.swap', 'orchestra.swap.altcoins']);
    expect(caps('spark', 'BTC', 'lightning', 'BTC'), ['orchestra.swap']);
    expect(caps('base', 'USDC', 'spark', 'USDB'), ['orchestra.swap']);
    expect(
        caps('ethereum', 'ETH', 'hypercore', 'USDC'), ['hyperliquid.deposit']);
    expect(
        caps('hypercore', 'USDC', 'solana', 'SOL'), ['hyperliquid.withdraw']);
    expect(caps('solana', 'SOL', 'polygon', 'USDC.e'), ['polymarket.deposit']);
  });

  test('swap gates hide picker rows by class and never touch venue legs',
      () async {
    OrchestraReceiveOption row(String chain, String asset) =>
        OrchestraReceiveOption(
          assetCode: asset,
          displayName: asset,
          displaySymbol: asset,
          chain: chain,
          chainDisplayName: chain,
          decimals: 6,
          chainIconUrl: null,
          assetIconUrl: null,
          reusableAddress: true,
        );
    final rows = [
      row('base', 'USDC'),
      row('tron', 'USDT'),
      row('ethereum', 'ETH'),
      row('solana', 'SOL'),
      row('hypercore', 'USDC'),
      row('polygon', 'USDC.e'),
    ];
    Future<List<String>> offered(Set<String> blocked) async {
      final policy = runtimePolicyFixture(blocked: blocked);
      addTearDown(policy.dispose);
      expect(await policy.refresh(), isTrue);
      return orchestraOptionsOfferedUnderPolicy(rows, policy)
          .offered
          .map((o) => '${o.chain}:${o.assetCode}')
          .toList();
    }

    // Nothing blocked: everything.
    expect(await offered({}), [
      'base:USDC',
      'tron:USDT',
      'ethereum:ETH',
      'solana:SOL',
      'hypercore:USDC',
      'polygon:USDC.e',
    ]);
    // Only the altcoin class blocked: stablecoins and bitcoin still move.
    expect(await offered({'orchestra.swap.altcoins'}),
        ['base:USDC', 'tron:USDT', 'hypercore:USDC', 'polygon:USDC.e']);
    // The master blocked: no cross-chain swap of any kind, while the
    // Investing and Predictions legs are untouched.
    expect(
        await offered({
          'orchestra.swap',
          'orchestra.swap.stablecoins',
          'orchestra.swap.altcoins'
        }),
        ['hypercore:USDC', 'polygon:USDC.e']);
    // Only the venue rule blocks a venue leg.
    expect(await offered({'hyperliquid.withdraw', 'polymarket.withdraw'}),
        ['base:USDC', 'tron:USDT', 'ethereum:ETH', 'solana:SOL']);
    // Without a readable policy the swap gates fail closed and the venue
    // rows follow their own (advisory) rule.
    final unavailable = runtimePolicyFixture();
    addTearDown(unavailable.dispose);
    final result = orchestraOptionsOfferedUnderPolicy(rows, unavailable);
    expect(result.offered.map((o) => o.chain), ['hypercore', 'polygon']);
    expect(result.hiddenReason, contains('Unable to check availability'));
  });

  test(
      'a fully blocked swap policy still lets venue moves through the quote gate',
      () async {
    final policy = runtimePolicyFixture(blocked: {
      'orchestra.swap',
      'orchestra.swap.stablecoins',
      'orchestra.swap.altcoins'
    });
    addTearDown(policy.dispose);
    expect(await policy.refresh(), isTrue);
    List<String> caps(String sc, String sa, String dc, String da) =>
        orchestraCapabilityRequirements(
            sourceChain: sc,
            sourceAsset: sa,
            destinationChain: dc,
            destinationAsset: da);
    await policy.ensureAllAllowed(caps('spark', 'BTC', 'hypercore', 'USDC'));
    await policy.ensureAllAllowed(caps('polygon', 'USDC.e', 'bitcoin', 'BTC'));
    await expectLater(
        policy.ensureAllAllowed(caps('spark', 'BTC', 'base', 'USDC')),
        throwsA(isA<CapabilityUnavailableException>()));
    final venueBlocked = runtimePolicyFixture(blocked: {'hyperliquid.deposit'});
    addTearDown(venueBlocked.dispose);
    expect(await venueBlocked.refresh(), isTrue);
    await expectLater(
        venueBlocked
            .ensureAllAllowed(caps('spark', 'BTC', 'hypercore', 'USDC')),
        throwsA(isA<CapabilityUnavailableException>()));
  });

  test('provider estimate explicitly excludes the configured Kute fee', () {
    final body = jsonDecode(File(
            'test/services/fixtures/orchestra_estimate_spark_to_hypercore.json')
        .readAsStringSync()) as Map<String, dynamic>;
    final estimate = OrchestraEstimate.fromJson(body, headers: {
      'X-Kute-Estimate-Includes-App-Fee': 'false',
      'X-Kute-App-Fee-Bps': '50',
      'X-Kute-Fee-Policy-Revision': '7',
    });
    expect(estimate.estimateIncludesAppFee, isFalse);
    expect(estimate.kuteAppFeeBps, 50);
    expect(estimate.feePolicyRevision, 7);
    expect(orchestraFeeAmount(estimate).usd, closeTo(1.041619, 0.000001));
    // The fee metadata does not modify the provider's gross estimate and never
    // pretends that it is an already charged, final amount.
    expect(estimate.estimatedOut, body['estimatedOut']);
  });

  test('provider-default Kute fee remains unknown, never zero', () {
    final estimate = OrchestraEstimate.fromJson({
      'estimatedOut': '10000'
    }, headers: {
      'x-kute-estimate-includes-app-fee': 'false',
    });
    expect(estimate.kuteAppFeeBps, isNull);
    expect(estimate.estimateIncludesAppFee, isFalse);
  });

  test(
      'final quote keeps app fees separate without subtracting net receive twice',
      () {
    final quote = OrchestraQuote.fromJson({
      'quoteId': 'q1',
      'estimatedOut': '9850000',
      'feeBps': 10,
      'appFees': [
        {'feeBps': 50, 'affiliateId': 'kute'}
      ],
    });
    expect(quote.feeBps, 10);
    expect(quote.appFeeBps, 50);
    expect(quote.estimatedOut, '9850000');
    expect(OrchestraQuote.fromJson({'appFees': []}).appFeeBps, 0);
    expect(OrchestraQuote.fromJson({}).appFeeBps, isNull);
  });
}
