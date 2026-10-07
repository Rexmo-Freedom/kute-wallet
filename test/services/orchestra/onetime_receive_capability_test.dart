// `orchestra.onetime_addresses`: the operator switch for receiving from
// another network through a one-time quoted deposit address. Denied (or
// no readable policy) leaves only the reusable-address receive options;
// allowed changes nothing.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart';
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
          // Reusable deposit addresses.
          _row('base', 'USDC'),
          _row('arbitrum', 'USDT'),
          // One-time quotes only.
          _row('litecoin', 'LTC', decimals: 8),
          _row('ton', 'USDT'),
          _row('bitcoin', 'BTC', decimals: 8),
        ],
      },
      source: OrchestraCatalogSource.live,
      fetchedAt: DateTime(2026, 10, 1),
    );

List<String> _ids(List<CoinAssetGroup> groups) => [
      for (final g in groups)
        for (final o in g.options) '${o.chain}:${o.assetCode}',
    ];

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
  final l10n = l10nForLanguage('en');
  setUp(() => AffiliateService.debugSessionToken = 'test-session');
  tearDown(() => AffiliateService.debugSessionToken = null);

  test('only one-time receive rows ask for the switch', () {
    final oneTime = _option('litecoin', 'LTC', reusable: false);
    final reusable = _option('base', 'USDC');
    expect(orchestraOptionCapabilities(oneTime, depositAddress: true),
        contains(kOneTimeAddressCapability));
    expect(orchestraOptionCapabilities(reusable, depositAddress: true),
        isNot(contains(kOneTimeAddressCapability)));
    // Sends and venue flows never consult it.
    expect(orchestraOptionCapabilities(oneTime),
        isNot(contains(kOneTimeAddressCapability)));
    expect(
        orchestraCapabilityRequirements(
            sourceChain: 'bitcoin',
            sourceAsset: 'BTC',
            destinationChain: 'spark',
            destinationAsset: 'USDB'),
        isNot(contains(kOneTimeAddressCapability)));
  });

  group('allowed', () {
    late RuntimeCapabilitiesService policy;
    setUp(() async {
      policy = runtimePolicyFixture();
      expect(await policy.refresh(), isTrue);
    });
    tearDown(() => policy.dispose());

    test('bitcoin and dollar receive offer one-time and reusable rows', () {
      expect(oneTimeReceiveAllowed(policy), isTrue);
      expect(
          _ids(receiveCoinGroups(_catalog(), l10n, policy: policy)),
          unorderedEquals(
              ['base:USDC', 'arbitrum:USDT', 'litecoin:LTC', 'ton:USDT']));
      expect(
          _ids(receiveCoinGroups(_catalog(), l10n,
              destinationChain: 'spark',
              destinationAsset: 'USDB',
              policy: policy)),
          containsAll(['base:USDC', 'litecoin:LTC', 'bitcoin:BTC']));
    });

    test('the picker offers one-time rows and starting a quote passes',
        () async {
      final rows = [
        _option('base', 'USDC'),
        _option('litecoin', 'LTC', reusable: false),
      ];
      final offered = orchestraOptionsOfferedUnderPolicy(rows, policy,
          depositAddress: true);
      expect(offered.offered, hasLength(2));
      expect(offered.hiddenReason, isNull);
      await policy.ensureAllAllowed(const [kOneTimeAddressCapability]);
    });
  });

  group('denied', () {
    late RuntimeCapabilitiesService policy;
    setUp(() async {
      policy = runtimePolicyFixture(blocked: {kOneTimeAddressCapability});
      expect(await policy.refresh(), isTrue);
    });
    tearDown(() => policy.dispose());

    test('only reusable rows remain, on bitcoin and on dollars', () {
      expect(oneTimeReceiveAllowed(policy), isFalse);
      expect(_ids(receiveCoinGroups(_catalog(), l10n, policy: policy)),
          unorderedEquals(['base:USDC', 'arbitrum:USDT']));
      final dollars = _ids(receiveCoinGroups(_catalog(), l10n,
          destinationChain: 'spark', destinationAsset: 'USDB', policy: policy));
      expect(dollars, contains('base:USDC'));
      // Bitcoin into dollars, Litecoin and TON are one-time quotes only.
      expect(dollars, isNot(contains('bitcoin:BTC')));
      expect(dollars, isNot(contains('litecoin:LTC')));
      expect(dollars, isNot(contains('ton:USDT')));
    });

    test('the picker hides one-time rows with a reason and no quote starts',
        () async {
      final rows = [
        _option('base', 'USDC'),
        _option('litecoin', 'LTC', reusable: false),
      ];
      final receive = orchestraOptionsOfferedUnderPolicy(rows, policy,
          depositAddress: true);
      expect(receive.offered.map((o) => o.chain), ['base']);
      expect(receive.hiddenReason, isNotNull);
      // Sends are unaffected.
      expect(orchestraOptionsOfferedUnderPolicy(rows, policy).offered,
          hasLength(2));
      // The quoted receive screen's execution-time gate refuses.
      await expectLater(
          policy.ensureAllAllowed(const [kOneTimeAddressCapability]),
          throwsA(isA<CapabilityUnavailableException>()));
    });
  });

  test('no readable policy fails closed to reusable rows only', () async {
    final policy = RuntimeCapabilitiesService.forTesting(
      client: MockClient((_) async => http.Response('', 503)),
      baseUrl: () => 'https://policy.test',
      sessionToken: () => AffiliateService.sessionToken,
    );
    addTearDown(policy.dispose);
    expect(await policy.refresh(), isFalse);
    expect(oneTimeReceiveAllowed(policy), isFalse);
    expect(policy.decision(kOneTimeAddressCapability).reason,
        'policy_unavailable');
    expect(_ids(receiveCoinGroups(_catalog(), l10n, policy: policy)),
        unorderedEquals(['base:USDC', 'arbitrum:USDT']));
  });
}
