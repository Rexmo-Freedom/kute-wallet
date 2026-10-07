import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The jurisdiction gates are one rule with one wording wherever an order
/// is signed: the spending wallet and a Ledger consult the same capability
/// lists from the same helpers at the same points. A Ledger signs on the
/// device and posts straight to the venue, so the backend cannot refuse it;
/// these scans fail if either path stops sharing a helper with the other.
void main() {
  String source(String path) => File(path)
      .readAsLinesSync()
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  test('Investing: hot and Ledger orders share the stock gate and leverage cap',
      () {
    final hot = source('lib/providers/hyperliquid_trading_provider.dart');
    final ledger = source(
        'lib/screens/ledger/hyperliquid/ledger_hl_execution_target.dart');
    final executor =
        source('lib/providers/ledger/ledger_executors_provider.dart');
    for (final helper in ['hlOpenCapabilities(', 'ensureLeverageAllowed(']) {
      expect(hot, contains(helper), reason: 'hot path: $helper');
      expect(ledger, contains(helper), reason: 'Ledger path: $helper');
    }
    expect(executor, contains('ensureLeverageAllowed('),
        reason: 'the Ledger executor checks the cap it is about to sign');
    // Neither path hard-codes the new-exposure capability on its own.
    expect(hot, isNot(contains("ensureAllowed('hyperliquid.trade')")));
    expect(ledger, isNot(contains("ensureAllowed('hyperliquid.trade')")));
  });

  test('Predictions: hot and Ledger bets share the category gate', () {
    final hot = source('lib/providers/polymarket_trading_provider.dart');
    final ledger =
        source('lib/screens/ledger/polymarket/ledger_pm_bet_target.dart');
    final slip =
        source('lib/screens/polymarket/components/bet_slip_sheet.dart');
    expect(hot, contains('polymarketBetCapabilitiesFor('));
    expect(ledger, contains('polymarketBetCapabilitiesFor('));
    expect(slip, contains('_betCapabilities()'));
    expect(ledger, isNot(contains("ensureAllowed('polymarket.trade')")));
  });

  test('Orchestra: one route classifier serves every caller', () {
    final api = source('lib/services/api/orchestra_api.dart');
    final picker = source('lib/screens/shared/coin_asset_grid.dart');
    expect(api, contains('orchestraCapabilityRequirements('));
    expect(picker, contains('orchestraOptionsOfferedUnderPolicy('));
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.dart') &&
            !f.path.endsWith('orchestra_capability_requirements.dart') &&
            source(f.path).contains("'orchestra.swap"))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty,
        reason: 'swap capability ids belong to the route classifier only');
  });
}
