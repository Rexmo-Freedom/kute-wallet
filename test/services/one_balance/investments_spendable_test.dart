// What Investments can spend: Dollars plus the venue cash the engine can
// reach (before costs) for the From row, and a Max the engine's own plan
// always covers. Dollars into Bitcoin (the Bitcoin Receive's "From your
// Dollars", the Dollars Send's "To your Bitcoin") spends the same money,
// less any venue whose own withdraw the policy withholds (fw46).

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/services/one_balance/investments_spendable.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart'
    show VenueMoveResult;
import 'package:kute/services/runtime_capabilities_service.dart';

import '../../helpers/runtime_policy_fixture.dart';

VenueCashCandidate _c(OneBalanceVenue venue, double usd,
        {double minimum = 1}) =>
    (
      venue: venue,
      availableUsd: usd,
      eta: kVenuePullEta[venue]!,
      minimumUsd: minimum,
    );

/// One venue's free cash, for the planner.
class _Source implements VenueCashSource {
  _Source(this.venue, this.available);

  @override
  final OneBalanceVenue venue;
  final double available;

  @override
  Duration get estimatedArrival => kVenuePullEta[venue]!;

  @override
  Future<double> availableUsd() async => available;

  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) =>
      throw StateError('nothing moves here');
}

Settings _settings() => Settings(
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
    );

void main() {
  test('Dollars alone: the total and Max are Dollars', () {
    final s = investmentsSpendable(dollarsUsd: 42.5, sources: const []);
    expect(s.totalUsd, 42.5);
    expect(s.maxUsd, 42.5);
    expect(s.venueCashUsd, 0);
  });

  test('venue cash counts before costs on the row, after costs in Max', () {
    final s = investmentsSpendable(dollarsUsd: 10, sources: [
      _c(OneBalanceVenue.predictions, 60),
      _c(OneBalanceVenue.investing, 40, minimum: 5),
    ]);
    expect(s.totalUsd, 110);
    // 60 x 0.98 + (40 x 0.98 - 0.30) = 58.80 + 38.90.
    expect(s.maxUsd, closeTo(107.70, 1e-9));
    expect(
        planDollarsShortfall(neededUsd: s.maxUsd, dollarsUsd: 10, sources: [
          _c(OneBalanceVenue.predictions, 60),
          _c(OneBalanceVenue.investing, 40, minimum: 5),
        ]).covers,
        isTrue);
  });

  test('a venue under its route minimum is not spendable', () {
    final s = investmentsSpendable(dollarsUsd: 10, sources: [
      _c(OneBalanceVenue.predictions, 0.6),
      _c(OneBalanceVenue.investing, 4, minimum: 5),
    ]);
    expect(s.totalUsd, 10);
    expect(s.maxUsd, 10);
  });

  test('Max is always an amount the plan covers', () {
    final random = math.Random(7);
    for (var i = 0; i < 500; i++) {
      final dollars = (random.nextDouble() * 50 * 100).floor() / 100;
      final sources = [
        _c(OneBalanceVenue.predictions,
            (random.nextDouble() * 300 * 100).floor() / 100),
        _c(OneBalanceVenue.investing,
            (random.nextDouble() * 300 * 100).floor() / 100,
            minimum: 5),
      ];
      final s = investmentsSpendable(dollarsUsd: dollars, sources: sources);
      expect(s.maxUsd, lessThanOrEqualTo(s.totalUsd + 1e-9));
      expect(s.maxUsd, greaterThanOrEqualTo(dollars));
      expect(
          planDollarsShortfall(
                  neededUsd: s.maxUsd, dollarsUsd: dollars, sources: sources)
              .covers,
          isTrue,
          reason: '$s from $sources');
    }
  });

  // fw46: Dollars into Bitcoin spends all the dollar money ("From your
  // Dollars", "To your Bitcoin"), less a venue whose withdraw is withheld.
  group('Dollars into Bitcoin', () {
    const open = CapabilityDecision(allowed: true);
    CapabilityDecision Function(String) deciding(
            Map<String, CapabilityDecision> refused) =>
        (id) => refused[id] ?? open;

    test(
        "each venue's cash leaves under its own withdraw, as the route "
        'classifier names it for the quote', () {
      expect(venueCashExitCapabilities(OneBalanceVenue.investing),
          ['hyperliquid.withdraw']);
      expect(venueCashExitCapabilities(OneBalanceVenue.predictions),
          ['polymarket.withdraw']);
    });

    test(
        'a withdraw withheld by a platform rule, a switch or coming soon '
        'closes that venue alone; an open policy closes none', () {
      expect(venueCashClosed(deciding(const {})), isEmpty);
      for (final refusal in const [
        CapabilityDecision(allowed: false, reason: 'platform_not_allowed'),
        CapabilityDecision(allowed: false, reason: 'disabled'),
        CapabilityDecision(
            allowed: false, reason: 'coming_soon', comingSoon: true),
      ]) {
        expect(
            venueCashClosed(deciding({'hyperliquid.withdraw': refusal})),
            {OneBalanceVenue.investing},
            reason: refusal.reason);
        expect(
            venueCashClosed(deciding({'polymarket.withdraw': refusal})),
            {OneBalanceVenue.predictions},
            reason: refusal.reason);
      }
      // Withholding the swap master says nothing about venue withdraws.
      expect(
          venueCashClosed(deciding(const {
            'orchestra.swap':
                CapabilityDecision(allowed: false, reason: 'disabled'),
          })),
          isEmpty);
    });

    test('the planner gives a closed venue no leg; the open one covers it',
        () async {
      final puller = VenueCashPuller(
        sources: [
          _Source(OneBalanceVenue.predictions, 60),
          _Source(OneBalanceVenue.investing, 40),
        ],
        readDollars: () => 10,
        minimumUsd: (v) async => v == OneBalanceVenue.investing ? 5 : 1,
      );
      final planned = await puller.plan(
          neededUsd: 30, destination: VenueCashDestination.bitcoin);
      expect(planned.pulls.map((p) => p.venue), [OneBalanceVenue.predictions]);
      final closed = await puller.plan(
          neededUsd: 30,
          destination: VenueCashDestination.bitcoin,
          closed: {OneBalanceVenue.predictions});
      expect(closed.pulls.map((p) => p.venue), [OneBalanceVenue.investing]);
      expect(closed.dollarsUsd, 10, reason: 'Dollars first');
      expect(closed.covers, isTrue);
      final none = await puller.plan(
          neededUsd: 30,
          destination: VenueCashDestination.bitcoin,
          closed: OneBalanceVenue.values.toSet());
      expect(none.pulls, isEmpty);
      expect(none.covers, isFalse);
    });

    test(
        'dollarsToBitcoinSpendableProvider: Dollars plus the open venues\' '
        'cash, net of the move costs, the same figure as Investments spends',
        () async {
      final policy = runtimePolicyFixture();
      RuntimeCapabilitiesService.debugInstance = policy;
      addTearDown(() {
        RuntimeCapabilitiesService.debugInstance = null;
        policy.dispose();
      });
      expect(await policy.refresh(), isTrue);
      final container = ProviderContainer(overrides: [
        usdBalanceProvider.overrideWithValue(4.75),
        settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      ]);
      addTearDown(container.dispose);
      final sources = [
        _c(OneBalanceVenue.predictions, 20),
        _c(OneBalanceVenue.investing, 40, minimum: 5),
      ];
      container.read(venueCashLastReadProvider.notifier).state =
          (walletId: 'spending', candidates: sources);
      final all = container.read(dollarsToBitcoinSpendableProvider);
      // 4.75 + 20 x 0.98 + (40 x 0.98 - 0.30).
      expect(all.maxUsd, closeTo(63.25, 1e-9));
      expect(all, container.read(investmentsSpendableProvider));
      expect(all,
          investmentsSpendable(dollarsUsd: 4.75, sources: sources));
    });

    test('a withheld Investing withdraw leaves its cash out of the figure',
        () async {
      final policy = runtimePolicyFixture(
          blocked: {'hyperliquid.withdraw'},
          reasons: {'hyperliquid.withdraw': 'platform_not_allowed'});
      RuntimeCapabilitiesService.debugInstance = policy;
      addTearDown(() {
        RuntimeCapabilitiesService.debugInstance = null;
        policy.dispose();
      });
      expect(await policy.refresh(), isTrue);
      final container = ProviderContainer(overrides: [
        usdBalanceProvider.overrideWithValue(4.75),
        settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      ]);
      addTearDown(container.dispose);
      container.read(venueCashLastReadProvider.notifier).state = (
        walletId: 'spending',
        candidates: [
          _c(OneBalanceVenue.predictions, 20),
          _c(OneBalanceVenue.investing, 40, minimum: 5),
        ],
      );
      expect(container.read(venueCashClosedProvider),
          {OneBalanceVenue.investing});
      final s = container.read(dollarsToBitcoinSpendableProvider);
      expect(s.maxUsd, closeTo(24.35, 1e-9));
      expect(s.venueCashUsd, 20);
    });
  });
}
