import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_activity_provider.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';

class _Model extends PolymarketModel {
  final addresses = <String>[];
  bool fail = false;
  @override
  Future<List<Activity>> getUserActivityOrThrow(
    String walletAddress, {
    http.Client? client,
  }) async {
    addresses.add(walletAddress);
    if (fail) throw StateError('Offline');
    return const [];
  }
}

void main() {
  test('Ledger history resolves and reads only that wallet venue address',
      () async {
    final model = _Model();
    final container = ProviderContainer(overrides: [
      ledgerIdentityProvider('ledger-a').overrideWith((_) =>
          const LedgerIdentity(
              walletId: 'ledger-a',
              evmAddress: 'ledger-eoa',
              evmVerifiedAtMs: 1)),
      ledgerPolymarketActivityModelProvider.overrideWithValue(model),
      ledgerPmAccountProvider('ledger-a')
          .overrideWith((_) async => const LedgerPmAccount(
                walletId: 'ledger-a',
                eoa: 'ledger-eoa',
                account: PolymarketLedgerAccount.depositWallet(
                    'ledger-deposit', DepositWalletVariant.uups),
              )),
    ]);
    addTearDown(container.dispose);
    await container.read(ledgerPmActivityProvider('ledger-a').future);
    expect(model.addresses, ['ledger-deposit']);
  });

  test('failed Ledger history stays an error, not empty activity', () async {
    final model = _Model()..fail = true;
    final container = ProviderContainer(overrides: [
      ledgerIdentityProvider('ledger-a').overrideWith((_) =>
          const LedgerIdentity(
              walletId: 'ledger-a',
              evmAddress: 'ledger-eoa',
              evmVerifiedAtMs: 1)),
      ledgerPolymarketActivityModelProvider.overrideWithValue(model),
      ledgerPmAccountProvider('ledger-a')
          .overrideWith((_) async => const LedgerPmAccount(
                walletId: 'ledger-a',
                eoa: 'ledger-eoa',
                account: PolymarketLedgerAccount.legacySafe('ledger-safe'),
              )),
    ]);
    addTearDown(container.dispose);
    await expectLater(
        container.read(ledgerPmActivityProvider('ledger-a').future),
        throwsStateError);
    expect(model.addresses, ['ledger-safe']);
  });

  test('uncertain Ledger account never falls back to spending address',
      () async {
    final model = _Model();
    final container = ProviderContainer(overrides: [
      ledgerIdentityProvider('ledger-a').overrideWith((_) =>
          const LedgerIdentity(
              walletId: 'ledger-a',
              evmAddress: 'ledger-eoa',
              evmVerifiedAtMs: 1)),
      ledgerPolymarketActivityModelProvider.overrideWithValue(model),
      ledgerPmAccountProvider('ledger-a')
          .overrideWith((_) async => const LedgerPmAccount(
                walletId: 'ledger-a',
                eoa: 'ledger-eoa',
                account: PolymarketLedgerAccount.uncertain(),
              )),
    ]);
    addTearDown(container.dispose);
    await expectLater(
        container.read(ledgerPmActivityProvider('ledger-a').future),
        throwsStateError);
    expect(model.addresses, isEmpty);
  });
  test('mismatched venue identity never sends an activity request', () async {
    final model = _Model();
    final container = ProviderContainer(overrides: [
      ledgerIdentityProvider('ledger-a').overrideWith((_) =>
          const LedgerIdentity(
              walletId: 'ledger-a',
              evmAddress: 'ledger-eoa',
              evmVerifiedAtMs: 1)),
      ledgerPolymarketActivityModelProvider.overrideWithValue(model),
      ledgerPmAccountProvider('ledger-a')
          .overrideWith((_) async => const LedgerPmAccount(
                walletId: 'ledger-a',
                eoa: 'other-ledger-eoa',
                account:
                    PolymarketLedgerAccount.legacySafe('other-ledger-safe'),
              )),
    ]);
    addTearDown(container.dispose);
    await expectLater(
        container.read(ledgerPmActivityProvider('ledger-a').future),
        throwsStateError);
    expect(model.addresses, isEmpty);
  });
}
