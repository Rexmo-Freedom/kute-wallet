// A new wallet's Spark connect starts right after the wallet is saved, on
// every creation path, instead of when home first watches the provider.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/source_scan.dart';

void main() {
  test('every onboarding save is followed by primeSparkConnect', () {
    for (final path in [
      'lib/screens/creation/passkey_choice.dart',
      'lib/screens/creation/recover_wallet.dart',
    ]) {
      final code = stripComments(File(path).readAsStringSync());
      final saves = 'addWallet('.allMatches(code).map((m) => m.start).toList();
      expect(saves, isNotEmpty, reason: path);
      for (final save in saves) {
        // The helper's own definition and the orchestrator field are not
        // call sites.
        final prime = code.indexOf('primeSpark', save);
        expect(prime, greaterThan(save),
            reason: '$path: a wallet is saved at offset $save without '
                'priming the Spark connect afterwards');
      }
    }
  });

  test('the priming mirrors completeUnlock', () {
    final helper = stripComments(
        File('lib/screens/creation/passkey_choice.dart').readAsStringSync());
    final unlock = stripComments(
        File('lib/helpers/session_unlock.dart').readAsStringSync());
    for (final line in [
      'ref.read(breezSDKProvider.future).then((_) {}, onError: (_) {});',
      'ref.invalidate(breezSDKProvider);',
    ]) {
      expect(helper, contains(line));
      expect(unlock, contains(line));
    }
  });
}
