import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/advisor/advisor_capability_manifest.dart';

void main() {
  test('Sal rejects legacy order placement and money actions', () {
    for (final id in [
      'place_bet',
      'open_bet_slip',
      'hyperliquid_invest',
      'send_money',
      'move_funds',
      'backup_wallet',
      'receive_money'
    ]) {
      expect(AdvisorCapabilityManifest.validParams(id, {}), isFalse,
          reason: id);
    }
  });
  test('market actions reject private or executable parameters', () {
    expect(
        AdvisorCapabilityManifest.validParams(
            'open_hl_market', {'coin': 'xyz:TSLA', 'kind': 'perp'}),
        isTrue);
    for (final extra in ['side', 'amountUsd', 'leverage', 'walletId']) {
      expect(
          AdvisorCapabilityManifest.validParams(
              'open_hl_market', {'coin': 'xyz:TSLA', extra: '1'}),
          isFalse);
    }
    expect(
        AdvisorCapabilityManifest.validParams(
            'open_market_by_slug', {'slug': 'public-event'}),
        isTrue);
    expect(
        AdvisorCapabilityManifest.validParams(
            'open_market_by_slug', {'slug': 'https://evil.example/path'}),
        isFalse);
    expect(
        AdvisorCapabilityManifest.validParams(
            'open_predictions_tab', {'autoSheet': 'deposit'}),
        isFalse);
  });
  test('local slip controls cannot carry model-selected values', () {
    expect(
        AdvisorCapabilityManifest.validParams('switch_to_limit', {}), isTrue);
    expect(
        AdvisorCapabilityManifest.validParams('switch_to_limit', {'price': 1}),
        isFalse);
    expect(
        AdvisorCapabilityManifest.validParams(
            'open_leverage_settings', {'leverage': 5}),
        isFalse);
  });
}
