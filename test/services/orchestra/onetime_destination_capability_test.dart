// `orchestra.onetime_addresses.bitcoin` and `.dollars`: the destination
// classes that refine the one-time switch. A one-time receive needs the
// master AND the class of what it lands in. Only an explicit denial
// counts: a backend older than the classes names neither, and everything
// keeps working.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart';
import 'package:kute/services/orchestra/reusable_deposit_address.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import '../../helpers/runtime_policy_fixture.dart';

Map<String, dynamic> _row(String chain, String asset, {int decimals = 6}) => {
      'id': '$chain:$asset',
      'chain': chain,
      'asset': asset,
      'decimals': decimals,
      'route': {'to': 'all', 'fixedTo': [], 'exactOutTo': []},
    };

OrchestraRoutesCatalog _catalog() => OrchestraRoutesCatalog.fromJson(
      {
        'assets': [
          _row('spark', 'BTC', decimals: 8),
          _row('spark', 'USDB'),
          // Served by the reusable (standing) route.
          _row('base', 'USDC'),
          _row('solana', 'USDC'),
          // Only a one-time quote serves it: standing takes only USDT on
          // Tron.
          _row('tron', 'TRX'),
        ],
      },
      source: OrchestraCatalogSource.live,
      fetchedAt: DateTime(2026, 10, 1),
    );

List<OrchestraReceiveOption> _rows(
        RuntimeCapabilitiesService policy, String destination) =>
    [
      for (final g in coinGroupsOfferedUnderPolicyWith(
          policy,
          receiveCoinGroups(_catalog(), l10nForLanguage('en'),
              destinationAsset: destination, policy: policy),
          destination))
        ...g.options,
    ];

/// What the receive screens offer: [coinGroupsOfferedUnderPolicy] reads the
/// app singleton, so the same filter is applied here with [policy].
List<CoinAssetGroup> coinGroupsOfferedUnderPolicyWith(
    RuntimeCapabilitiesService policy,
    List<CoinAssetGroup> groups,
    String destination) {
  final out = <CoinAssetGroup>[];
  for (final g in groups) {
    final offered = orchestraOptionsOfferedUnderPolicy(g.options, policy,
            otherLegAsset: destination,
            depositAddress: true,
            reusableLegAsset: 'USDB')
        .offered;
    if (offered.isEmpty) continue;
    out.add(CoinAssetGroup(
        key: g.key,
        displayName: g.displayName,
        displaySymbol: g.displaySymbol,
        options: offered));
  }
  return out;
}

String _id(OrchestraReceiveOption o) => '${o.chain}:${o.assetCode}';

OrchestraReceiveOption _option(String chain, String asset,
        {bool reusable = false}) =>
    OrchestraReceiveOption(
      assetCode: asset,
      displayName: asset,
      displaySymbol: asset,
      chain: chain,
      chainDisplayName: chain,
      decimals: 6,
      reusableAddress: reusable,
    );

Future<RuntimeCapabilitiesService> _policy(
    {Set<String> blocked = const {},
    Set<String> also = const {},
    Map<String, String> reasons = const {}}) async {
  final policy =
      runtimePolicyFixture(blocked: blocked, also: also, reasons: reasons);
  addTearDown(policy.dispose);
  expect(await policy.refresh(), isTrue);
  return policy;
}

const _classes = {kOneTimeBitcoinCapability, kOneTimeDollarsCapability};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AffiliateService.debugSessionToken = 'test-session');
  tearDown(() => AffiliateService.debugSessionToken = null);

  test('each destination names its class', () {
    expect(oneTimeDestinationCapability('BTC'), kOneTimeBitcoinCapability);
    expect(oneTimeDestinationCapability(' btc '), kOneTimeBitcoinCapability);
    expect(oneTimeDestinationCapability('USDB'), kOneTimeDollarsCapability);
    // The strict list stays ensureAllAllowed-safe on an older backend.
    final caps = orchestraOptionCapabilities(_option('tron', 'TRX'),
        otherLegAsset: 'USDB', depositAddress: true);
    expect(caps, isNot(contains(kOneTimeDollarsCapability)));
    expect(caps, isNot(contains(kOneTimeBitcoinCapability)));
  });

  test('absent ids (an older backend) count as allowed', () async {
    final policy = await _policy();
    for (final destination in ['BTC', 'USDB']) {
      final id = oneTimeDestinationCapability(destination);
      expect(policy.decision(id).reason, 'unknown_capability');
      expect(oneTimeDestinationDecision(policy, destination).allowed, isTrue);
      expect(oneTimeReceiveAllowed(policy, destinationAsset: destination),
          isTrue);
      expect(() => ensureOneTimeDestinationAllowed(policy, destination),
          returnsNormally);
      // The one-time-only coin is offered as a one-time row.
      final trx = _rows(policy, destination).where((o) => _id(o) == 'tron:TRX');
      expect(trx, hasLength(1));
      expect(trx.single.reusableAddress, isFalse);
    }
  });

  test('published and allowed: both destinations offer one-time', () async {
    final policy = await _policy(also: _classes);
    for (final destination in ['BTC', 'USDB']) {
      expect(oneTimeReceiveAllowed(policy, destinationAsset: destination),
          isTrue);
      expect(_rows(policy, destination).map(_id), contains('tron:TRX'));
    }
  });

  test(
      'Dollars denied: the Dollars receive keeps only reusable rows; the '
      'Bitcoin receive still falls back to one-time into bitcoin', () async {
    final policy =
        await _policy(also: _classes, blocked: {kOneTimeDollarsCapability});
    final catalog = _catalog();

    expect(oneTimeReceiveAllowed(policy), isTrue);
    expect(oneTimeReceiveAllowed(policy, destinationAsset: 'USDB'), isFalse);
    expect(oneTimeReceiveAllowed(policy, destinationAsset: 'BTC'), isTrue);

    final dollars = _rows(policy, 'USDB');
    expect(dollars.map(_id), unorderedEquals(['base:USDC', 'solana:USDC']));
    expect(dollars.every((o) => o.reusableAddress), isTrue);
    // A reusable row whose standing address fails has no one-time fallback.
    expect(
        oneTimeFallbackOption(catalog, _option('base', 'USDC', reusable: true),
            destinationAsset: 'USDB', policy: policy),
        isNull);
    // The picker hides a one-time row into Dollars and says why.
    final picker = orchestraOptionsOfferedUnderPolicy(
        [_option('tron', 'TRX'), _option('base', 'USDC', reusable: true)],
        policy,
        otherLegAsset: 'USDB',
        depositAddress: true,
        reusableLegAsset: 'USDB');
    expect(picker.offered.map(_id), ['base:USDC']);
    expect(picker.hiddenReason, isNotNull);
    expect(() => ensureOneTimeDestinationAllowed(policy, 'USDB'),
        throwsA(isA<CapabilityUnavailableException>().having(
            (e) => e.capability, 'capability', kOneTimeDollarsCapability)));

    final bitcoin = _rows(policy, 'BTC');
    expect(bitcoin.map(_id), contains('tron:TRX'));
    expect(
        oneTimeFallbackOption(catalog, _option('base', 'USDC', reusable: true),
                destinationAsset: 'BTC', policy: policy)
            ?.reusableAddress,
        isFalse);
    expect(() => ensureOneTimeDestinationAllowed(policy, 'BTC'),
        returnsNormally);
  });

  test(
      'Bitcoin denied: the Bitcoin receive offers only the reusable route '
      'into dollars; the Dollars receive keeps its one-time fallback',
      () async {
    final policy =
        await _policy(also: _classes, blocked: {kOneTimeBitcoinCapability});
    final catalog = _catalog();

    final bitcoin = _rows(policy, 'BTC');
    expect(bitcoin.map(_id), unorderedEquals(['base:USDC', 'solana:USDC']));
    expect(bitcoin.every((o) => o.reusableAddress), isTrue);
    expect(
        oneTimeFallbackOption(catalog, _option('base', 'USDC', reusable: true),
            destinationAsset: 'BTC', policy: policy),
        isNull);
    expect(() => ensureOneTimeDestinationAllowed(policy, 'BTC'),
        throwsA(isA<CapabilityUnavailableException>()));

    expect(_rows(policy, 'USDB').map(_id), contains('tron:TRX'));
    expect(
        oneTimeFallbackOption(catalog, _option('base', 'USDC', reusable: true),
            destinationAsset: 'USDB', policy: policy),
        isNotNull);
  });

  test('a region denial of a class is an explicit denial', () async {
    final policy = await _policy(
        also: _classes,
        blocked: {kOneTimeDollarsCapability},
        reasons: {kOneTimeDollarsCapability: 'country_blocked'});
    expect(oneTimeReceiveAllowed(policy, destinationAsset: 'USDB'), isFalse);
    expect(oneTimeReceiveAllowed(policy, destinationAsset: 'BTC'), isTrue);
  });

  test('the master still decides: off, no class can re-open it', () async {
    final policy = await _policy(
        also: _classes, blocked: {kOneTimeAddressCapability});
    for (final destination in ['BTC', 'USDB']) {
      expect(oneTimeReceiveAllowed(policy, destinationAsset: destination),
          isFalse);
      expect(_rows(policy, destination).every((o) => o.reusableAddress),
          isTrue);
    }
  });

  test('no readable policy: the master fails closed whatever the class',
      () async {
    final policy = RuntimeCapabilitiesService.forTesting(
      client: MockClient((_) async => http.Response('', 503)),
      baseUrl: () => 'https://policy.test',
      sessionToken: () => AffiliateService.sessionToken,
    );
    addTearDown(policy.dispose);
    expect(await policy.refresh(), isFalse);
    for (final destination in ['BTC', 'USDB']) {
      expect(oneTimeReceiveAllowed(policy, destinationAsset: destination),
          isFalse);
    }
  });
}
