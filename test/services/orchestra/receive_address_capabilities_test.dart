import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart';

import '../../helpers/runtime_policy_fixture.dart';

OrchestraReceiveOption _option(String chain, String asset,
        {bool reusable = true}) =>
    OrchestraReceiveOption(
      assetCode: asset,
      displayName: asset,
      displaySymbol: asset,
      chain: chain,
      chainDisplayName: chain,
      decimals: 6,
      reusableAddress: reusable,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AffiliateService.debugSessionToken = 'test-session');
  tearDown(() => AffiliateService.debugSessionToken = null);

  test('a deposit address asks what the backend operation guard asks', () {
    // POST /api/v1/orchestra/accumulation-addresses: crypto.deposit plus
    // operationCapabilities(source, asset, "spark", destinationAsset).
    expect(
        orchestraReceiveAddressCapabilities(
            sourceChain: 'base', sourceAsset: 'USDC', destinationAsset: 'BTC'),
        ['crypto.deposit', 'orchestra.swap', 'orchestra.swap.stablecoins']);
    expect(
        orchestraReceiveAddressCapabilities(
            sourceChain: 'solana', sourceAsset: 'SOL', destinationAsset: 'BTC'),
        ['crypto.deposit', 'orchestra.swap', 'orchestra.swap.altcoins']);
    expect(
        orchestraReceiveAddressCapabilities(
            sourceChain: 'base', sourceAsset: 'USDC', destinationAsset: 'USDB'),
        ['crypto.deposit', 'orchestra.swap']);
  });

  test('only reusable receive rows need crypto.deposit', () {
    final reusable = _option('base', 'USDC');
    final oneTime = _option('bitcoin', 'BTC', reusable: false);
    expect(orchestraOptionCapabilities(reusable, depositAddress: true),
        contains('crypto.deposit'));
    // A one-time row is a quote; the backend's quote guard has no
    // crypto.deposit.
    expect(
        orchestraOptionCapabilities(oneTime,
            otherLegAsset: 'USDB', depositAddress: true),
        isNot(contains('crypto.deposit')));
    // Sends never ask it.
    expect(orchestraOptionCapabilities(reusable),
        isNot(contains('crypto.deposit')));
  });

  test('with crypto deposits off, receive rows are withdrawn with a reason',
      () async {
    final policy = runtimePolicyFixture(blocked: {'crypto.deposit'});
    addTearDown(policy.dispose);
    expect(await policy.refresh(), isTrue);
    final rows = [
      _option('base', 'USDC'),
      _option('bitcoin', 'BTC', reusable: false),
    ];

    final receive = orchestraOptionsOfferedUnderPolicy(rows, policy,
        otherLegAsset: 'USDB', depositAddress: true);
    expect(receive.offered.map((o) => o.chain), ['bitcoin']);
    expect(receive.hiddenReason, isNotNull);

    final send = orchestraOptionsOfferedUnderPolicy(rows, policy);
    expect(send.offered, hasLength(2));
    expect(send.hiddenReason, isNull);
  });
}
