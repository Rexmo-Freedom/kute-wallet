// P3.9: Polymarket CLOB credentials are saved, heal-deleted and refreshed
// under the spending wallet ID, never the carousel's active wallet (which
// can be a Ledger page).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';

import '../helpers/source_scan.dart';

Settings _settings({required String active, bool withSpending = true}) =>
    Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'x',
      nodeType: 'x',
      reviewDone: true,
      activeWalletId: active,
      wallets: [
        WalletConfig(
          id: 'ledger-1',
          name: 'Ledger',
          sparkEnabled: false,
          isWatchOnly: true,
          isHardware: true,
          walletType: 'ledger',
          evmAddress: '0x14791697260E4c9A71f18484C9f997B308e59325',
          evmVerifiedAtMs: 1,
        ),
        if (withSpending) WalletConfig(id: 'spend', name: 'Spending Wallet'),
      ],
    );

void main() {
  test('a Ledger page being active never selects the Ledger wallet ID', () {
    final settings = _settings(active: 'ledger-1');
    expect(polymarketCredentialsWalletId(settings), 'spend');
    expect(polymarketCredentialsWalletId(settings, pinnedWalletId: 'spend'),
        'spend');
  });

  test('the build-pinned spending wallet wins over later settings', () {
    final settings = _settings(active: 'ledger-1');
    expect(polymarketCredentialsWalletId(settings, pinnedWalletId: 'old-spend'),
        'old-spend');
  });

  test('no spending wallet means no credential writes', () {
    final settings = _settings(active: 'ledger-1', withSpending: false);
    expect(polymarketCredentialsWalletId(settings), isNull);
  });

  test('save, heal-delete and refresh never read activeWalletId', () {
    final code = stripComments(
        File('lib/providers/polymarket_trading_provider.dart')
            .readAsStringSync());
    expect(code.contains('activeWalletId'), isFalse);

    // Every credential write, delete and read goes through a wallet ID that
    // is either the pinned spending ID or `spending.id`.
    final keyed = RegExp(r'(_saveCredentials|_credsKey)\(([^,)]+)')
        .allMatches(code)
        .map((m) => m.group(2)!.trim())
        .toSet();
    expect(keyed, isNotEmpty);
    for (final arg in keyed) {
      expect([
        'walletId',
        'credsWalletId',
        'orderWalletId',
        'String walletId'
      ], contains(arg), reason: 'credential key built from $arg');
    }
    expect(code.contains('_spendingWalletId = walletId;'), isTrue);
    // placeOrder captures the credentials wallet once, up front, and saves
    // healed credentials under that same ID (858facab): it is the pinned
    // spending wallet, never the carousel's active page.
    expect(
        code.contains('final orderWalletId = _credentialsWalletId();'), isTrue);
    expect(
        RegExp(r'String\? _credentialsWalletId\(\) =>\s*'
                r'polymarketCredentialsWalletId\(ref\.read\(settingsProvider\),\s*'
                r'pinnedWalletId: _spendingWalletId\);')
            .hasMatch(code),
        isTrue);
  });
}
