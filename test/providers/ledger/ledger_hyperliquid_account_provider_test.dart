import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/hardware/ledger/ledger_venue_descriptor_store.dart';

const _ledgerEvm = '0x14791697260E4c9A71f18484C9f997B308e59325';

class _MemoryDescriptors extends LedgerVenueDescriptorStore {
  final merges = <String, String?>{};

  @override
  Future<LedgerVenueDescriptor> merge(String walletId,
      {String? hlAddress,
      LedgerPmAccountKind? pmAccountKind,
      String? pmAddress,
      int? pmSignatureType}) async {
    merges[walletId] = hlAddress;
    return LedgerVenueDescriptor(hlAddress: hlAddress, resolvedAtMs: 1);
  }
}

Settings _settings({bool paired = true}) => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'x',
      nodeType: 'x',
      reviewDone: true,
      activeWalletId: 'ledger-1',
      wallets: [
        WalletConfig(id: 'spend', name: 'Spending Wallet'),
        WalletConfig(
          id: 'ledger-1',
          name: 'Ledger',
          sparkEnabled: false,
          isWatchOnly: true,
          isHardware: true,
          walletType: 'ledger',
          masterFingerprint: 'aabbccdd',
          evmAddress: paired ? _ledgerEvm : null,
          evmDerivationPath: paired ? "m/44'/60'/0'/0/0" : null,
          evmVerifiedAtMs: paired ? 1 : null,
        ),
      ],
    );

typedef _Handler = Object? Function(Map<String, dynamic> body);

({ProviderContainer container, List<Map<String, dynamic>> requests,
    _MemoryDescriptors descriptors}) _setup(_Handler handler,
    {bool paired = true}) {
  final requests = <Map<String, dynamic>>[];
  final client = MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    requests.add(body);
    final result = handler(body);
    if (result is http.Response) return result;
    return http.Response(jsonEncode(result), 200);
  });
  final descriptors = _MemoryDescriptors();
  final container = ProviderContainer(overrides: [
    settingsProvider
        .overrideWith((ref) => SettingsModel(_settings(paired: paired))),
    ledgerHyperliquidModelProvider
        .overrideWithValue(HyperliquidModel(client: client)),
    ledgerVenueDescriptorStoreProvider.overrideWithValue(descriptors),
  ]);
  addTearDown(container.dispose);
  return (container: container, requests: requests, descriptors: descriptors);
}

Map<String, dynamic> _perp(String accountValue) => {
      'marginSummary': {'accountValue': accountValue, 'totalMarginUsed': '0'},
      'withdrawable': accountValue,
      'assetPositions': [],
    };

Object? _happy(Map<String, dynamic> body) {
  switch (body['type']) {
    case 'clearinghouseState':
      return switch (body['dex']) {
        null => _perp('100'),
        'xyz' => _perp('7'),
        _ => _perp('3'),
      };
    case 'spotClearinghouseState':
      return {
        'balances': [
          {'coin': 'USDC', 'total': '10', 'hold': '0'},
        ],
      };
    case 'perpDexs':
      return [
        null,
        {'name': 'xyz', 'fullName': 'XYZ'},
        {'name': 'abc', 'fullName': 'ABC'},
      ];
    case 'frontendOpenOrders':
    case 'userFills':
      return [];
  }
  return http.Response('unknown', 500);
}

void main() {
  test('aggregates perps, spot and every HIP-3 dex', () async {
    final s = _setup(_happy);
    final account =
        await s.container.read(ledgerHlAccountProvider('ledger-1').future);

    expect(account.address, _ledgerEvm);
    expect(account.partialFailures, isEmpty);
    expect(account.account!.accountValue, 100);
    expect(account.account!.spotBalances.single.total, 10);
    expect(account.dexAccounts.keys.toSet(), {'xyz', 'abc'});
    expect(account.dexAccounts['xyz']!.accountValue, 7);
    expect(account.openOrders, isEmpty);
    expect(account.fills, isEmpty);
    expect(s.descriptors.merges['ledger-1'], _ledgerEvm);

    // Every user-scoped read is bound to the Ledger's verified address,
    // and the retired vault product is never read.
    for (final body in s.requests) {
      if (body.containsKey('user')) expect(body['user'], _ledgerEvm);
      expect(body['type'], isNot(anyOf('userVaultEquities', 'vaultDetails')));
    }
    expect(
        s.requests
            .where((b) => b['type'] == 'clearinghouseState')
            .map((b) => b['dex'])
            .toSet(),
        {null, 'xyz', 'abc'});
  });

  test('a partial failure is flagged and never zeroed', () async {
    final s = _setup((body) {
      if (body['type'] == 'frontendOpenOrders') {
        return http.Response('down', 500);
      }
      if (body['type'] == 'clearinghouseState' && body['dex'] == 'abc') {
        return http.Response('down', 502);
      }
      return _happy(body);
    });
    final account =
        await s.container.read(ledgerHlAccountProvider('ledger-1').future);

    expect(account.partialFailures, {
      LedgerHlReadCategory.openOrders,
      LedgerHlReadCategory.hip3Dexes,
    });
    expect(account.openOrders, isNull);
    expect(account.dexAccounts.keys, ['xyz']);
    expect(account.account!.accountValue, 100);
  });

  test('a failed dex list is flagged instead of hiding HIP-3 positions',
      () async {
    final s = _setup((body) => body['type'] == 'perpDexs'
        ? http.Response('down', 500)
        : _happy(body));
    final account =
        await s.container.read(ledgerHlAccountProvider('ledger-1').future);
    // Without the dex list the builder-dex orders cannot be read either,
    // so the orders read is incomplete rather than "no orders".
    expect(account.partialFailures, {
      LedgerHlReadCategory.hip3Dexes,
      LedgerHlReadCategory.openOrders,
    });
    expect(account.dexAccounts, isEmpty);
    expect(account.openOrders, isNull);
  });

  test('reads resting orders on every builder dex the account uses',
      () async {
    Map<String, dynamic> order(String coin, int oid) => {
          'coin': coin,
          'side': 'B',
          'limitPx': '1.0',
          'sz': '2',
          'origSz': '2',
          'oid': oid,
          'timestamp': oid,
          'orderType': 'Limit',
          'isTrigger': false,
          'triggerPx': '0.0',
          'reduceOnly': false,
          'tif': 'Alo',
          'isPositionTpsl': false,
        };
    final s = _setup((body) {
      if (body['type'] == 'clearinghouseState' && body['dex'] == 'abc') {
        return _perp('0'); // nothing on abc: its orders are not read
      }
      if (body['type'] == 'frontendOpenOrders') {
        return switch (body['dex']) {
          null => [order('@107', 1)],
          'xyz' => [order('xyz:TSLA', 2)],
          _ => [order('abc:X', 3)],
        };
      }
      return _happy(body);
    });
    final account =
        await s.container.read(ledgerHlAccountProvider('ledger-1').future);

    expect(account.partialFailures, isEmpty);
    expect(account.openOrders!.map((o) => o.coin).toSet(),
        {'@107', 'xyz:TSLA'});
    expect(account.openOrders!.firstWhere((o) => o.oid == 2).tif, 'Alo');
    expect(
        s.requests
            .where((b) => b['type'] == 'frontendOpenOrders')
            .map((b) => b['dex'])
            .toSet(),
        {null, 'xyz'});
  });

  test('an unpaired Ledger makes no network reads', () async {
    final s = _setup(_happy, paired: false);
    final account =
        await s.container.read(ledgerHlAccountProvider('ledger-1').future);
    expect(account.isPaired, isFalse);
    expect(s.requests, isEmpty);
  });

  test('a wallet that is not a Ledger has no identity', () async {
    final s = _setup(_happy);
    expect(s.container.read(ledgerIdentityProvider('spend')), isNull);
    final account =
        await s.container.read(ledgerHlAccountProvider('spend').future);
    expect(account.isPaired, isFalse);
    expect(s.requests, isEmpty);
  });
}
