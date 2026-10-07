import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/hardware/ledger/ledger_venue_descriptor_store.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';

import '../../helpers/source_scan.dart';
import '../../services/polymarket/polymarket_account_resolver_test.dart'
    show FakeReads, position;

const _ledgerEvm = '0x14791697260E4c9A71f18484C9f997B308e59325';
const _uups = '0x1111111111111111111111111111111111111111';
const _safe = '0x3333333333333333333333333333333333333333';

class _MemoryDescriptors extends LedgerVenueDescriptorStore {
  final merges = <({LedgerPmAccountKind? kind, String? address, int? sigType})>[];

  @override
  Future<LedgerVenueDescriptor> merge(String walletId,
      {String? hlAddress,
      LedgerPmAccountKind? pmAccountKind,
      String? pmAddress,
      int? pmSignatureType}) async {
    merges.add((kind: pmAccountKind, address: pmAddress, sigType: pmSignatureType));
    return const LedgerVenueDescriptor(resolvedAtMs: 1);
  }
}

Settings _settings() => Settings(
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
          evmAddress: _ledgerEvm,
          evmDerivationPath: "m/44'/60'/0'/0/0",
          evmVerifiedAtMs: 1,
        ),
      ],
    );

({ProviderContainer container, _MemoryDescriptors descriptors}) _setup(
    FakeReads reads) {
  final descriptors = _MemoryDescriptors();
  final container = ProviderContainer(overrides: [
    settingsProvider.overrideWith((ref) => SettingsModel(_settings())),
    ledgerPolymarketReadsProvider.overrideWithValue(reads),
    ledgerVenueDescriptorStoreProvider.overrideWithValue(descriptors),
  ]);
  addTearDown(container.dispose);
  return (container: container, descriptors: descriptors);
}

void main() {
  test('reads a deposit wallet account, positions and cash', () async {
    final reads = FakeReads()
      ..relayer[_uups] = true
      ..positionsBy[_uups] = [position('77')]
      ..balances[PolymarketConstants.pusdAddress] = BigInt.from(1500000)
      ..balances[PolymarketConstants.usdcEAddress] = BigInt.from(250000);
    final s = _setup(reads);

    final account =
        await s.container.read(ledgerPmAccountProvider('ledger-1').future);

    expect(account.eoa, _ledgerEvm);
    expect(account.account!.kind, PolymarketAccountKind.depositWallet);
    expect(account.positions!.single.asset, '77');
    expect(account.pusdBalance, BigInt.from(1500000));
    expect(account.usdceBalance, BigInt.from(250000));
    expect(account.partialFailures, isEmpty);
    expect(s.descriptors.merges.single,
        (kind: LedgerPmAccountKind.depositWallet, address: _uups, sigType: 3));
  });

  test('an RPC failure on cash is flagged, not zero', () async {
    final reads = FakeReads()
      ..relayer[_uups] = true
      ..balances[PolymarketConstants.pusdAddress] = Exception('rpc down');
    final s = _setup(reads);
    final account =
        await s.container.read(ledgerPmAccountProvider('ledger-1').future);
    expect(account.partialFailures, {LedgerPmReadCategory.cash});
    expect(account.pusdBalance, isNull);
    expect(account.usdceBalance, isNull);
    expect(account.positions, isEmpty);
  });

  test('a failed positions read is flagged, not empty', () async {
    final reads = FakeReads()
      ..relayer[_uups] = true
      ..positionsBy[_uups] = Exception('data api');
    final s = _setup(reads);
    final account =
        await s.container.read(ledgerPmAccountProvider('ledger-1').future);
    expect(account.partialFailures, {LedgerPmReadCategory.positions});
    expect(account.positions, isNull);
  });

  test('an uncertain account is flagged and caches nothing', () async {
    final reads = FakeReads()..code[_uups] = Exception('rpc down');
    final s = _setup(reads);
    final account =
        await s.container.read(ledgerPmAccountProvider('ledger-1').future);
    expect(account.account!.kind, PolymarketAccountKind.uncertain);
    expect(account.partialFailures, {LedgerPmReadCategory.account});
    expect(account.positions, isNull);
    expect(account.pusdBalance, isNull);
    expect(s.descriptors.merges, isEmpty);
  });

  test('a legacy Safe is shown read-only', () async {
    final reads = FakeReads()
      ..code[_safe] = true
      ..positionsBy[_safe] = [position('9')];
    final s = _setup(reads);
    final account =
        await s.container.read(ledgerPmAccountProvider('ledger-1').future);
    expect(account.isReadOnly, isTrue);
    expect(account.account!.canAct, isFalse);
    expect(account.positions, hasLength(1));
  });

  test('the identity follows the wallet ID, not the active wallet', () {
    final s = _setup(FakeReads());
    expect(s.container.read(ledgerIdentityProvider('ledger-1'))!.evmAddress,
        _ledgerEvm);
    expect(s.container.read(ledgerIdentityProvider('spend')), isNull);
  });

  test('no ClobAuth, API key, deploy or approval path exists in the read '
      'providers or the resolver', () {
    const files = [
      'lib/providers/ledger/ledger_polymarket_account_provider.dart',
      'lib/providers/ledger/ledger_hyperliquid_account_provider.dart',
      'lib/providers/ledger/ledger_identity_provider.dart',
      'lib/services/polymarket/polymarket_account_resolver.dart',
    ];
    const forbidden = [
      'ClobAuth',
      'deriveOrCreateApiKey',
      'api-key',
      'signClobAuth',
      'deployDepositWallet',
      'enableTrading',
      'setApprovals',
      'fixMissingApprovals',
      'executeDepositWalletBatch',
      'submitDepositWalletCall',
      'wrapUsdceToPusd',
      'ensurePusdBalance',
      'submitSafeTx',
      'PolymarketBackendService',
      'secureStorage',
    ];
    for (final path in files) {
      final code = stripComments(File(path).readAsStringSync());
      for (final token in forbidden) {
        expect(code.contains(token), isFalse, reason: '$path uses $token');
      }
    }
  });
}
