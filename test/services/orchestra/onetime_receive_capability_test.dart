// `orchestra.onetime_addresses`: the operator switch for the one-time
// quoted deposit address, the fallback of the reusable (standing) one.
// Denied, only the coins the standing route may serve remain; with
// standing denied too (or no readable policy) nothing is offered.
// `crypto.deposit` gates both, as the backend asks of every new deposit
// address.
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
          // EVM: refunded to the wallet's own EVM address.
          _row('base', 'USDC'),
          _row('arbitrum', 'USDT'),
          // Listed tokens quoted with no refund address.
          _row('solana', 'USDC'),
          _row('tron', 'USDT'),
          // No own refund address and not refund-optional: not offered.
          _row('litecoin', 'LTC', decimals: 8),
          _row('ton', 'USDT'),
          _row('bitcoin', 'BTC', decimals: 8),
          // Venue rails.
          _row('hypercore', 'USDC', decimals: 8),
          _row('polygon', 'USDC.e'),
        ],
      },
      source: OrchestraCatalogSource.live,
      fetchedAt: DateTime(2026, 10, 1),
    );

List<String> _ids(List<CoinAssetGroup> groups) => [
      for (final g in groups)
        for (final o in g.options) '${o.chain}:${o.assetCode}',
    ];

OrchestraReceiveOption _option(String chain, String asset) =>
    OrchestraReceiveOption(
      assetCode: asset,
      displayName: asset,
      displaySymbol: asset,
      chain: chain,
      chainDisplayName: chain,
      decimals: 6,
      reusableAddress: false,
    );

const _offered = ['base:USDC', 'arbitrum:USDT', 'solana:USDC', 'tron:USDT'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = l10nForLanguage('en');
  setUp(() => AffiliateService.debugSessionToken = 'test-session');
  tearDown(() => AffiliateService.debugSessionToken = null);

  test('receive rows ask for the switch and crypto deposits; sends never', () {
    final row = _option('base', 'USDC');
    expect(orchestraOptionCapabilities(row, depositAddress: true),
        containsAll([kOneTimeAddressCapability, 'crypto.deposit']));
    expect(orchestraOptionCapabilities(row),
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

    test(
        'bitcoin and dollar receive list EVM, Solana and Tron, never another '
        'network or a venue rail: standing first where it may serve', () {
      expect(oneTimeReceiveAllowed(policy), isTrue);
      expect(_ids(receiveCoinGroups(_catalog(), l10n, policy: policy)),
          unorderedEquals(_offered));
      expect(
          _ids(receiveCoinGroups(_catalog(), l10n,
              destinationAsset: 'USDB', policy: policy)),
          unorderedEquals(_offered));
      // The policy does not name orchestra.standing_addresses (an older
      // backend): standing is tried for every coin it may serve.
      final every = receiveCoinGroups(_catalog(), l10n, policy: policy)
          .expand((g) => g.options);
      expect(every.every((o) => o.reusableAddress), isTrue);
    });

    test('standing denied: every row is a one-time row', () async {
      final denied = runtimePolicyFixture(
          also: {kStandingAddressCapability},
          blocked: {kStandingAddressCapability});
      addTearDown(denied.dispose);
      expect(await denied.refresh(), isTrue);
      for (final destination in ['BTC', 'USDB']) {
        final rows = receiveCoinGroups(_catalog(), l10n,
                destinationAsset: destination, policy: denied)
            .expand((g) => g.options)
            .toList();
        expect(rows.map((o) => '${o.chain}:${o.assetCode}'),
            unorderedEquals(_offered));
        expect(rows.every((o) => !o.reusableAddress), isTrue);
      }
    });

    test('the picker offers them and starting a quote passes', () async {
      final rows = [_option('base', 'USDC'), _option('solana', 'USDC')];
      final offered = orchestraOptionsOfferedUnderPolicy(rows, policy,
          depositAddress: true);
      expect(offered.offered, hasLength(2));
      expect(offered.hiddenReason, isNull);
      await policy.ensureAllAllowed(
          orchestraOptionCapabilities(rows.first, depositAddress: true));
    });
  });

  for (final blocked in [kOneTimeAddressCapability, 'crypto.deposit']) {
    group('$blocked denied', () {
      late RuntimeCapabilitiesService policy;
      setUp(() async {
        policy = runtimePolicyFixture(blocked: {blocked});
        expect(await policy.refresh(), isTrue);
      });
      tearDown(() => policy.dispose());

      test('the picker hides every receive row and no quote starts', () async {
        final rows = [_option('base', 'USDC'), _option('solana', 'USDC')];
        final receive = orchestraOptionsOfferedUnderPolicy(rows, policy,
            depositAddress: true);
        expect(receive.offered, isEmpty);
        expect(receive.hiddenReason, isNotNull);
        // Sends are unaffected.
        expect(orchestraOptionsOfferedUnderPolicy(rows, policy).offered,
            hasLength(2));
        await expectLater(
            policy.ensureAllAllowed(
                orchestraOptionCapabilities(rows.first, depositAddress: true)),
            throwsA(isA<CapabilityUnavailableException>()));
        if (blocked == kOneTimeAddressCapability) {
          expect(oneTimeReceiveAllowed(policy), isFalse);
          // Only the coins the standing route may serve remain.
          for (final destination in ['BTC', 'USDB']) {
            final rows = receiveCoinGroups(_catalog(), l10n,
                    destinationAsset: destination, policy: policy)
                .expand((g) => g.options);
            expect(rows, isNotEmpty);
            expect(rows.every((o) => o.reusableAddress), isTrue);
          }
        } else {
          // crypto.deposit off: no standing row either.
          expect(
              receiveCoinGroups(_catalog(), l10n, policy: policy)
                  .expand((g) => g.options)
                  .where((o) => o.reusableAddress),
              isEmpty);
        }
      });
    });
  }

  test('one-time and standing both denied: nothing is offered', () async {
    final policy = runtimePolicyFixture(
        also: {kStandingAddressCapability},
        blocked: {kStandingAddressCapability, kOneTimeAddressCapability});
    addTearDown(policy.dispose);
    expect(await policy.refresh(), isTrue);
    expect(receiveCoinGroups(_catalog(), l10n, policy: policy), isEmpty);
    expect(
        receiveCoinGroups(_catalog(), l10n,
            destinationAsset: 'USDB', policy: policy),
        isEmpty);
  });

  test('no readable policy fails closed: nothing is offered', () async {
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
    expect(receiveCoinGroups(_catalog(), l10n, policy: policy), isEmpty);
  });
}
