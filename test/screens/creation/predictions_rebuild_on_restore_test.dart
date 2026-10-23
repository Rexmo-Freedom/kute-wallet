// Every path that adds, restores or removes the spending wallet rebuilds
// Predictions explicitly (belt and braces beside the trading notifier's own
// identity watch): a build that ended on a placeholder for the same
// identity (no phrase readable yet) must not stick for the session. A
// recovery whose EVM format check could not finish schedules its retry in
// the same session and provisions nothing until it settles.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/source_scan.dart';

String _code(String path) => stripComments(File(path).readAsStringSync());

/// Every index of [needle] in [code].
List<int> _all(String code, String needle) {
  final at = <int>[];
  var i = code.indexOf(needle);
  while (i >= 0) {
    at.add(i);
    i = code.indexOf(needle, i + needle.length);
  }
  return at;
}

void main() {
  const invalidate = 'invalidate(polymarketTradingProvider)';

  test('phrase recovery rebuilds Predictions after the wallet is saved', () {
    final code = _code('lib/screens/creation/recover_wallet.dart');
    final add = code.indexOf('addWallet(newWallet)');
    expect(add, greaterThanOrEqualTo(0));
    final rebuild = code.indexOf(invalidate, add);
    expect(rebuild, greaterThan(add));
    expect(code.indexOf('invalidate(polymarketBalanceProvider)', add),
        greaterThan(add));
    // Its format retry runs in this session; provisioning waits for it.
    expect(code.indexOf('EvmFormatSettle.schedule(', add), greaterThan(add));
    final provision = code.indexOf('provisionPolymarketAccount(', add);
    expect(
        code.indexOf('evmFormatPending:', provision), greaterThan(provision));
  });

  test('every restore in the restore picker rebuilds Predictions', () {
    final code = _code('lib/screens/creation/recover_choice.dart');
    final adds = _all(code, 'addWallet(config)');
    expect(adds, hasLength(3), reason: 'legacy copy, passkey, old passkey');
    for (final add in adds) {
      final rebuild = code.indexOf('_rebuildPredictions()', add);
      final nextAdd = adds.where((a) => a > add).firstOrNull ?? code.length;
      expect(rebuild, inInclusiveRange(add, nextAdd),
          reason: 'addWallet at $add rebuilds Predictions');
    }
    final helper = code.indexOf('void _rebuildPredictions()');
    expect(helper, greaterThanOrEqualTo(0));
    expect(code.indexOf(invalidate, helper), greaterThan(helper));
    // The legacy-copy restore is a phrase recovery: same format rules.
    expect(code, contains('EvmFormatSettle.schedule('));
    expect(code, contains('evmFormatPending: config.evmFormatCheckPending'));
  });

  test('a created wallet rebuilds Predictions', () {
    final code = _code('lib/screens/creation/add_wallet.dart');
    final add = code.indexOf('addWallet(newWallet)');
    expect(code.indexOf(invalidate, add), greaterThan(add));
  });

  test('removing the spending wallet rebuilds Predictions', () {
    final code = _code('lib/screens/portfolio/wallet_detail_screen.dart');
    final remove = code.indexOf('.removeWallet(wallet.id)');
    expect(remove, greaterThanOrEqualTo(0));
    expect(code.indexOf(invalidate, remove), greaterThan(remove));
  });

  test('a restored secret rebuilds Predictions', () {
    final code = _code('lib/screens/recovery/restore_secrets_screen.dart');
    final mark = code.indexOf('void _markRestored(');
    expect(mark, greaterThanOrEqualTo(0));
    final end = code.indexOf('\n  }', mark);
    expect(code.substring(mark, end), contains(invalidate));
  });

  test(
      'the trading notifier watches the spending identity before any '
      'early return', () {
    final code = _code('lib/providers/polymarket_trading_provider.dart');
    final build = code.indexOf('Future<PolymarketTradingState> build()');
    final identity = code.indexOf(
        'ref.watch(settingsProvider.select(_predictionsSpendingIdentity))',
        build);
    final session = code.indexOf(
        'ref.watch(sessionAuthProvider.select((s) => s != null))', build);
    final firstReturn =
        code.indexOf('return const PolymarketTradingState', build);
    expect(identity, greaterThan(build));
    expect(session, greaterThan(build));
    expect(identity, lessThan(firstReturn));
    expect(session, lessThan(firstReturn));
  });
}
