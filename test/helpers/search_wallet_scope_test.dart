import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';

class _Cache extends WalletTransactionCacheNotifier {
  _Cache() {
    state = {
      for (final wallet in ['hardware', 'spending'])
        wallet: Transaction(
          bitcoinTransactions: [
            BitcoinTransaction.fromCache(
              id: '$wallet-tx',
              timestamp: DateTime(2026),
              isConfirmed: true,
              receivedSats: 1000,
              sentSats: 0,
            )
          ],
          sparkTransactions: [],
          sparkUnclaimedDeposits: [],
        ),
    };
  }
}

void main() {
  test('hardware search keeps account results within its wallet',
      () async {
    final container = ProviderContainer(overrides: [
      walletTransactionCacheProvider.overrideWith((_) => _Cache()),
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: '',
            reviewDone: true,
          ))),
    ]);
    addTearDown(container.dispose);
    container.read(searchWalletScopeProvider.notifier).state = 'hardware';
    container.read(searchQueryProvider.notifier).state = 'btc';
    container.read(selectedSearchCategoryProvider.notifier).state =
        SearchCategory.all;
    final result = await container.read(unifiedSearchResultsProvider.future);
    expect(result.transactions.map((r) => r.transaction.id), ['hardware-tx']);
    expect(result.ownedPositions, isEmpty);
    expect(container.read(globalMarketResultsProvider).value, isEmpty);
    expect(container.read(globalHyperliquidResultsProvider).value, isEmpty);
  });
  test('locked market search does not include wallet holdings',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(searchQueryProvider.notifier).state = 'bitcoin';
    container.read(selectedSearchCategoryProvider.notifier).state =
        SearchCategory.predictions;
    container.read(searchMarketsOnlyProvider.notifier).state = true;
    final results = await container.read(unifiedSearchResultsProvider.future);
    expect(results.ownedPositions, isEmpty);
    expect(results.transactions, isEmpty);
  });
}
