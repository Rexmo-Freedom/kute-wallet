// P3.8 / B8: the hot auto-fire listeners (claim, pending bet, pending
// Hyperliquid order) and the EOA sweep never act for a Ledger wallet.
// They are bound to the hot providers, which load only the spending wallet;
// Ledger providers never register them.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart' show sessionUnlockedProvider;
import 'package:kute/providers/claim_auto_fire.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Position;

import '../helpers/source_scan.dart';

const _ledgerEvm = '0x14791697260E4c9A71f18484C9f997B308e59325';

final _ledger = WalletConfig(
  id: 'ledger-1',
  name: 'Ledger',
  sparkEnabled: false,
  isWatchOnly: true,
  isHardware: true,
  walletType: 'ledger',
  evmAddress: _ledgerEvm,
  evmDerivationPath: "m/44'/60'/0'/0/0",
  evmVerifiedAtMs: 1,
);

Settings _settings(List<WalletConfig> wallets) => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'x',
      nodeType: 'x',
      reviewDone: true,
      activeWalletId: 'ledger-1',
      wallets: wallets,
    );

Position _redeemable() => const Position(
      proxyWallet: _ledgerEvm,
      asset: '1',
      conditionId: '0xc0',
      size: 5,
      avgPrice: 0.5,
      initialValue: 2.5,
      currentValue: 5,
      cashPnl: 2.5,
      percentPnl: 100,
      totalBought: 5,
      realizedPnl: 0,
      percentRealizedPnl: 0,
      curPrice: 1,
      redeemable: true,
      title: 'Resolved market',
      slug: 'resolved',
      eventSlug: 'resolved',
      outcome: 'Yes',
      outcomeIndex: 0,
      oppositeOutcome: 'No',
      oppositeAsset: '2',
    );

class _FakeHotTrading extends PolymarketTradingNotifier {
  final redeemed = <String>[];

  @override
  Future<PolymarketTradingState> build() async =>
      PolymarketTradingState(openPositions: [_redeemable()]);

  @override
  Future<double?> redeemPosition({
    required String conditionId,
    List<int> indexSets = const [1, 2],
    String? trigger,
    String? surface,
    bool reportFailure = true,
  }) async {
    redeemed.add(conditionId);
    return 0;
  }
}

const _hotFiles = [
  'lib/providers/claim_auto_fire.dart',
  'lib/providers/pending_bet_autofire.dart',
  'lib/providers/pending_hyperliquid_order_provider.dart',
  'lib/providers/hyperliquid_account_provider.dart',
];

const _ledgerSymbols = [
  'providers/ledger/',
  'hardware/ledger/',
  'evmAddress',
  'isLedger',
  'hasVerifiedEvm',
  'ledgerHlAccountProvider',
  'ledgerPmAccountProvider',
  'ledgerIdentityProvider',
  'LedgerHyperliquidExecutor',
  'LedgerPolymarketExecutor',
];

void main() {
  test('hot auto-fire and sweep code has no Ledger-scoped reference', () {
    for (final path in _hotFiles) {
      final code = stripComments(File(path).readAsStringSync());
      for (final symbol in _ledgerSymbols) {
        expect(code.contains(symbol), isFalse, reason: '$path uses $symbol');
      }
    }
  });

  test('the listeners act only through hot, spending-bound providers', () {
    String code(String path) => stripComments(File(path).readAsStringSync());
    expect(code('lib/providers/claim_auto_fire.dart'),
        contains('polymarketTradingProvider'));
    expect(code('lib/providers/pending_bet_autofire.dart'),
        contains('polymarketTradingProvider'));
    expect(code('lib/providers/pending_hyperliquid_order_provider.dart'),
        contains('hyperliquidTradingProvider'));
    // The account poll remains spending-wallet scoped and no longer recovers
    // funds from the retired Arbitrum funding route.
    final account = code('lib/providers/hyperliquid_account_provider.dart');
    expect(account, isNot(contains('HyperliquidEoaSweepService')));
    expect(account, contains('pickSpendingWallet(settings)'));
    final trading = code('lib/providers/polymarket_trading_provider.dart');
    expect(trading, contains('pickSpendingWallet(settings)'));
  });

  test('the spending wallet is never the Ledger, even when it is active', () {
    expect(pickSpendingWallet(_settings([_ledger])), isNull);
    final spend = WalletConfig(id: 'spend', name: 'Spending Wallet');
    expect(pickSpendingWallet(_settings([_ledger, spend]))!.id, 'spend');
  });

  test(
      'with a Ledger holding redeemable positions and no spending wallet, '
      'auto-claim makes no call and never touches Ledger providers', () async {
    final fake = _FakeHotTrading();
    Never touched(String name) =>
        throw StateError('$name must not be read by hot auto-fire');
    final container = ProviderContainer(overrides: [
      settingsProvider
          .overrideWith((ref) => SettingsModel(_settings([_ledger]))),
      sessionUnlockedProvider.overrideWith((ref) => true),
      polymarketTradingProvider.overrideWith(() => fake),
      ledgerPmAccountProvider.overrideWith((ref, id) => touched('pm')),
      ledgerHlAccountProvider.overrideWith((ref, id) => touched('hl')),
    ]);
    addTearDown(container.dispose);

    container.read(claimAutoFireProvider);
    await container.read(polymarketTradingProvider.future);
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(fake.redeemed, isEmpty);
  });
}
