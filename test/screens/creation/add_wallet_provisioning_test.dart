// P3.9 / B12: Polymarket provisioning (Safe or deposit wallet deploy plus
// CLOB credentials) runs only when a hot, mnemonic-backed wallet is created
// or recovered. A Ledger import never provisions anything.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';

import '../../helpers/source_scan.dart';

const _hotCreationFiles = {
  'lib/screens/creation/add_wallet.dart',
  'lib/screens/creation/recover_wallet.dart',
  'lib/screens/creation/recover_choice.dart',
  'lib/screens/creation/passkey_choice.dart',
  'lib/screens/login/open_pin.dart',
  'lib/screens/home/home.dart',
};

void main() {
  test('only hot creation and recovery paths call provisioning', () {
    final callers = <String>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path == 'lib/providers/polymarket_trading_provider.dart') continue;
      final code = stripComments(entity.readAsStringSync());
      if (code.contains('provisionPolymarketAccount(')) callers.add(path);
    }
    expect(callers, isNotEmpty);
    for (final path in callers) {
      expect(_hotCreationFiles, contains(path),
          reason: '$path provisions Polymarket');
      expect(path.toLowerCase().contains('ledger'), isFalse);
    }
  });

  test('provisioning needs a mnemonic, which a Ledger never has', () {
    final code = stripComments(
        File('lib/providers/polymarket_trading_provider.dart').readAsStringSync());
    final signature = RegExp(
            r'Future<void> provisionPolymarketAccount\(\{([^}]*)\}')
        .firstMatch(code);
    expect(signature, isNotNull);
    expect(signature!.group(1), contains('required String mnemonic'));
  });

  test('Add Wallet provisions only right after creating a Spark wallet', () {
    final code = stripComments(
        File('lib/screens/creation/add_wallet.dart').readAsStringSync());
    final call = code.indexOf('provisionPolymarketAccount(');
    final create = code.lastIndexOf('Future<void> _handleCreateSparkWallet', call);
    expect(create, greaterThanOrEqualTo(0));
    final body = code.substring(create, call);
    expect(body, contains('sparkEnabled: true'));
    expect(body, contains('generateMnemonic'));
  });

  test('a Ledger wallet is never a spending (Spark) wallet', () {
    final ledger = WalletConfig(
      id: 'ledger-1',
      name: 'Ledger',
      isHardware: true,
      isWatchOnly: true,
      walletType: 'ledger',
      evmAddress: '0x14791697260E4c9A71f18484C9f997B308e59325',
      evmVerifiedAtMs: 1,
    );
    // Even with sparkEnabled left at its default, hardware excludes it.
    expect(ledger.sparkEnabled, isTrue);
    expect(ledger.isSparkWallet, isFalse);
  });
}
