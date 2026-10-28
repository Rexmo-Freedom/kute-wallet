import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/one_balance/empty_slip_sources.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';

void main() {
  const empty = OneBalanceState(investingKnown: true, predictionsKnown: true);
  bool check(
          {int? bitcoin = 0,
          double? dollars = 0,
          OneBalanceState investments = empty,
          bool dollarsUnknown = false,
          bool sparkSynced = true}) =>
      slipSourcesKnownEmpty(
          bitcoinSats: bitcoin,
          sdkDollarsUsd: dollars,
          investments: investments,
          dollarsUnknown: dollarsUnknown,
          sparkSynced: sparkSynced);

  test('only confirmed zero in every source qualifies', () {
    expect(check(), isTrue);
    expect(check(bitcoin: null), isFalse);
    expect(check(dollars: null), isFalse);
    expect(check(dollarsUnknown: true), isFalse);
    expect(check(sparkSynced: false), isFalse);
    expect(check(investments: const OneBalanceState()), isFalse);
    expect(check(investments: empty.copyWith(investingKnown: false)), isFalse);
    expect(
        check(investments: empty.copyWith(predictionsKnown: false)), isFalse);
  });
  test('a positive or partial balance stays on in-place funding', () {
    expect(check(bitcoin: 1), isFalse);
    expect(check(dollars: 0.01), isFalse);
    expect(check(investments: empty.copyWith(dollarsUsd: 0.01)), isFalse);
    for (final venue in OneBalanceVenue.values) {
      expect(check(investments: empty.copyWith(venueCash: {venue: 0.01})),
          isFalse);
      expect(check(investments: empty.copyWith(waiting: {venue: 1})), isFalse);
    }
    expect(check(investments: empty.copyWith(investedUsd: 5)), isFalse);
  });
  test('no spending wallet is unknown rather than a confirmed empty wallet',
      () async {
    final c = ProviderContainer(overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: '',
          reviewDone: false))),
    ]);
    addTearDown(c.dispose);
    expect(await c.read(slipKnownEmptySourcesProvider)(), isFalse);
  });
}
