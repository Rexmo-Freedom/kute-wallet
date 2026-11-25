// Gating audit (fw36, v2.2): the Bitcoin home's goals nudge ("Move $X to
// Dollars") is a swap, Bitcoin into Dollars, and asks the one route
// classifier (orchestra_capability_requirements.dart), exactly as the
// Move sheet it opens does. Read here through the provider the home
// watches, against a real backend policy: any refusal of that route (a
// swap country block, a platform rule, the switch off, coming soon) takes
// the nudge away; Dollars into Bitcoin, the exit, is never asked of it.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/analytics/components/balance_goals.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:money2/money2.dart';

import 'market_gating_fixtures.dart';

class _Balances extends WalletBalanceCacheNotifier {
  _Balances(Map<String, WalletBalance> values) {
    state = values;
  }
}

BalanceGoalInput _input(RuntimeCapabilitiesService policy) {
  final balance =
      WalletBalance(onChainBtcBalance: 0, sparkBitcoinbalance: 100000);
  final container = ProviderContainer(overrides: [
    settingsProvider.overrideWith((_) => SettingsModel(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: 'Blockstream',
          reviewDone: true,
          activeWalletId: 'spending',
          wallets: [WalletConfig(id: 'spending', name: 'Spending')],
        ))),
    viewedWalletBalanceProvider.overrideWithValue(balance),
    walletBalanceCacheProvider
        .overrideWith((_) => _Balances({'spending': balance})),
    selectedCurrencyProvider.overrideWith(
        (ref, code) => Money.fromIntWithCurrency(6000000, AppCurrencies.usd)),
    selectedCurrencyProviderFromUSD.overrideWith(
        (ref, code) => Money.fromIntWithCurrency(100, AppCurrencies.usd)),
    oneBalanceProvider.overrideWithValue(const OneBalanceState(
        dollarsUsd: 25,
        investedUsd: 0,
        investingKnown: true,
        predictionsKnown: true)),
    runtimeCapabilitiesProvider.overrideWithValue(policy),
  ]);
  addTearDown(container.dispose);
  final input = container.read(balanceGoalInputProvider);
  expect(input, isNotNull, reason: 'the spending wallet has milestones');
  return input!;
}

void main() {
  tearDown(uninstallMarketGatingPolicy);

  test('nothing withheld: the nudge may show, both venues live', () async {
    final policy = await installMarketGatingPolicy(null);
    final input = _input(policy);
    expect(input.canMoveToDollars, isTrue);
    expect(input.investing, isTrue);
    expect(input.predictions, isTrue);
  });

  test(
      'swap country block: Bitcoin into Dollars is refused, so no nudge; '
      'the exit the other way stays open', () async {
    final policy =
        await installMarketGatingPolicy(MarketDenial.swapCountryBlock);
    expect(_input(policy).canMoveToDollars, isFalse);
  });

  for (final how in [
    MarketDenial.platform,
    MarketDenial.masterOff,
    MarketDenial.comingSoon,
  ]) {
    test('${how.label} on the swap master: no nudge', () async {
      final policy =
          await installMarketGatingPolicy(how, targets: {kSwapMaster});
      expect(_input(policy).canMoveToDollars, isFalse);
    });
  }

  test(
      'a block on the other classes (stablecoins, altcoins) never reaches '
      'Bitcoin into Dollars: the nudge stays', () async {
    final policy = await installMarketGatingPolicy(MarketDenial.masterOff,
        targets: {'$kSwapMaster.stablecoins', '$kSwapMaster.altcoins'});
    expect(_input(policy).canMoveToDollars, isTrue);
  });

  test('browsing both venues withheld: nowhere to point, no venue live',
      () async {
    final policy = await installMarketGatingPolicy(MarketDenial.masterOff,
        targets: {'hyperliquid.browse', 'polymarket.browse'});
    final input = _input(policy);
    expect(input.investing, isFalse);
    expect(input.predictions, isFalse);
  });
}
