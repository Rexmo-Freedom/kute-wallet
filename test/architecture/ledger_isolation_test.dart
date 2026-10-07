// Architecture guard for Ledger isolation (Wallet hardening Phase 3, B8).
//
// Ledger folders must never reach the hot trading providers, the spending
// wallet picker, seed resolution, private keys or the EOA sweep. Comments
// are stripped first, so documentation may name what is forbidden.
//
// This is a guard, not a proof: reused hot screens outside these folders
// (Phase 4) are covered by widget tests with throwing hot-provider
// overrides instead.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

const _scannedDirs = [
  'lib/providers/ledger',
  'lib/services/hardware/ledger',
  'lib/services/ledger',
  'lib/screens/ledger',
];

const _forbidden = [
  'polymarketTradingProvider',
  'hyperliquidTradingProvider',
  'hyperliquidAddressProvider',
  'hyperliquidAccountProvider',
  'usdcBalanceProvider',
  'pickSpendingWallet',
  'resolveBip39MnemonicFor',
  'EthPrivateKey',
  'HdWallet',
  'HyperliquidEoaSweepService',
];

List<String> violationsIn(String path, String source) {
  final code = stripComments(source);
  return [
    for (final token in _forbidden)
      if (RegExp('\\b$token\\b').hasMatch(code)) '$path: $token',
  ];
}

void main() {
  test('Ledger folders never reference hot providers, seeds or keys', () {
    final violations = <String>[];
    var scanned = 0;
    for (final dir in _scannedDirs) {
      final directory = Directory(dir);
      if (!directory.existsSync()) continue;
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        scanned++;
        violations.addAll(violationsIn(entity.path, entity.readAsStringSync()));
      }
    }
    expect(scanned, greaterThan(10));
    expect(violations, isEmpty);
  });

  test('the scan catches a forbidden token in code but not in comments', () {
    expect(violationsIn('x.dart', 'final k = EthPrivateKey.fromHex(h);'),
        ['x.dart: EthPrivateKey']);
    expect(violationsIn('x.dart', '// never an EthPrivateKey here\nfinal a = 1;'),
        isEmpty);
    expect(violationsIn('x.dart', '/* HdWallet */ final a = 1;'), isEmpty);
    expect(violationsIn('x.dart', "ref.read(pickSpendingWallet)"),
        ['x.dart: pickSpendingWallet']);
    expect(
        violationsIn('x.dart', "final s = 'http://a'; usdcBalanceProvider;"),
        ['x.dart: usdcBalanceProvider']);
  });
}
