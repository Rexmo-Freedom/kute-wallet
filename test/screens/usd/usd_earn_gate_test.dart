// The Dollars Earn view is a rate display gated by the backend `usd.earn`
// capability. It lives INSIDE the Balance tab as the second of two pills
// (Balance | Earn, the Breakdown tab's nested-pill pattern). Off, or with
// no policy to read, the pills do not exist: Balance is the bare dollar
// balance chart, the rewards API is never asked and no `usd_earn_*`
// event fires. On, Balance still opens on the balance chart; the Earn
// pill mounts the chart, reads the API and fires the open event.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/usd_rewards_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/providers/usd_rewards_provider.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/screens/usd/components/usd_balance_chart.dart';
import 'package:kute/screens/usd/components/usd_balance_tabs.dart';
import 'package:kute/screens/usd/components/usd_earn_chart.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/api/usd_rewards_api.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Records every rewards read so a test can prove none happened.
class _RecordingRewardsApi implements UsdRewardsApi {
  _RecordingRewardsApi({this.estimatedSatsToday = 0});

  final calls = <String>[];

  /// What the venue says today pays: the Earn headline.
  final int estimatedSatsToday;

  @override
  Future<UserRewardsSummary> getUserSummary(String pubkey) async {
    calls.add('summary');
    return UserRewardsSummary(
      pubkey: 'pub',
      usdbBalanceRaw: 25000000,
      usdbBalanceDisplay: 25,
      swapSats: 0,
      swapCount: 0,
      rewardsBracket: 0,
      rewardsPercent: 4.5,
      estimatedSatsToday: estimatedSatsToday,
    );
  }

  @override
  Future<PayoutHistoryResponse> getPayoutHistory(String pubkey,
      {int limit = 30, int offset = 0}) async {
    calls.add('payouts');
    return const PayoutHistoryResponse(
        pubkey: 'pub', payouts: [], total: 0, limit: 30, offset: 0);
  }
}

/// What the real service answers for `usd.earn` in each state; the unit
/// test at the bottom pins those answers against the real service, and
/// the widget tests take them from here so no policy timer outlives the
/// widget tree.
class _FakePolicy extends Fake implements RuntimeCapabilitiesService {
  _FakePolicy(this._decision);
  final CapabilityDecision _decision;

  @override
  CapabilityDecision decision(String id) =>
      id == 'usd.earn' ? _decision : const CapabilityDecision(allowed: true);

  @override
  bool allows(String id) => decision(id).allowed && !decision(id).comingSoon;

  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

const _earnOn = CapabilityDecision(allowed: true);
const _earnOff = CapabilityDecision(allowed: false, reason: 'disabled');
const _policyUnavailable =
    CapabilityDecision(allowed: false, reason: 'policy_unavailable');
const _unknownCapability =
    CapabilityDecision(allowed: false, reason: 'unknown_capability');

/// A real policy service answering with the given capability map, or
/// failing every fetch when [capabilities] is null (policy unavailable).
RuntimeCapabilitiesService _policy(Map<String, bool>? capabilities) =>
    RuntimeCapabilitiesService.forTesting(
      client: MockClient((request) async {
        if (capabilities == null) return http.Response('down', 503);
        final now = DateTime.now().toUtc();
        return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'revision': 1,
              'evaluatedAt': now.toIso8601String(),
              'expiresAt':
                  now.add(const Duration(minutes: 5)).toIso8601String(),
              'capabilities': {
                for (final entry in capabilities.entries)
                  entry.key: {
                    'allowed': entry.value,
                    'reason': entry.value ? '' : 'disabled',
                  },
              },
              'fees': const <String, Object>{},
              'ai': const {'dailyLimit': 5},
            }),
            200);
      }),
      baseUrl: () => 'https://policy.test',
      sessionToken: () => 'wallet-a',
      appVersion: () async => '2.0.4',
    );

Future<_RecordingRewardsApi> _pump(
  WidgetTester tester, {
  required CapabilityDecision earn,
  int estimatedSatsToday = 0,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = _RecordingRewardsApi(estimatedSatsToday: estimatedSatsToday);
  final settings = Settings(
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
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(settings)),
      runtimeCapabilitiesProvider.overrideWithValue(_FakePolicy(earn)),
      usdBalanceProvider.overrideWithValue(25),
      usdBalanceHistoryProvider.overrideWithValue(const {}),
      usdBalanceStepsProvider.overrideWithValue(
          const BalanceHistory(opening: 25, changes: [], current: 25)),
      sparkIdentityPubkeyProvider.overrideWith((_) async => 'pub'),
      usdRewardsApiProvider.overrideWithValue(api),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: UsdAccountBody()),
      ),
    ),
  ));
  // The Earn chart keeps a one-second countdown timer, so settle by
  // hand rather than waiting for a quiet frame that never comes.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return api;
}

/// The dollar ledger's empty state rotates its tagline on a delayed
/// future it never cancels; unmount the tree and let that one elapse so
/// the test ends with no timer pending. Every widget test ends here.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 7));
}

/// Taps a pill by its label and lets the switch settle (the Earn chart's
/// own one-second timer means no quiet frame, so pump by hand).
Future<void> _tapPill(WidgetTester tester, Finder pill) async {
  await tester.tap(pill);
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The strip's Balance pill: the first "Balance" on screen. Once the tab
/// is open and the programme is shown, the second one is the nested pill.
Finder _stripBalancePill(WidgetTester tester, AppLocalizations l10n) =>
    find.text(l10n.balance).first;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('capability off: Balance is the bare chart, no rewards read',
      (tester) async {
    final api = await _pump(tester, earn: _earnOff);
    final l10n = tester.element(find.byType(UsdAccountBody)).l10n;
    expect(find.byType(UsdEarnChart), findsNothing);
    expect(find.text(l10n.usdEarnTitle), findsNothing);
    expect(find.text(l10n.usdEarnRate), findsNothing);
    // The strip is still there for Activity (showing, so its pill reads
    // "See all"), Balance and Breakdown.
    expect(find.text(l10n.seeAll), findsOneWidget);
    expect(find.text(l10n.balance), findsOneWidget);

    // Opening Balance: the chart alone, with no nested pills at all.
    await _tapPill(tester, _stripBalancePill(tester, l10n));
    expect(find.byType(UsdBalanceChart), findsOneWidget);
    expect(find.byType(UsdBalanceTabs), findsNothing);
    expect(find.byKey(const ValueKey('usd-balance-view-earn')), findsNothing);
    expect(find.text(l10n.balance), findsOneWidget);
    expect(find.text(l10n.usdEarnTitle), findsNothing);
    expect(find.byType(UsdEarnChart), findsNothing);
    expect(api.calls, isEmpty);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('capability on: Earn is a pill inside Balance, not a tab',
      (tester) async {
    final api = await _pump(tester, earn: _earnOn, estimatedSatsToday: 1234);
    final l10n = tester.element(find.byType(UsdAccountBody)).l10n;
    // The strip opens on Activity and carries no Earn pill of its own;
    // nothing has read the rewards API yet.
    expect(find.text(l10n.seeAll), findsOneWidget);
    expect(find.text(l10n.balance), findsOneWidget);
    expect(find.text(l10n.usdEarnTitle), findsNothing);
    expect(find.byType(UsdEarnChart), findsNothing);
    expect(api.calls, isEmpty);

    // Balance opens on the balance chart, with Balance | Earn above it.
    await _tapPill(tester, _stripBalancePill(tester, l10n));
    expect(find.byType(UsdBalanceTabs), findsOneWidget);
    expect(
        find.byKey(const ValueKey('usd-balance-view-balance')), findsOneWidget);
    expect(find.byKey(const ValueKey('usd-balance-view-earn')), findsOneWidget);
    expect(find.text(l10n.balance), findsNWidgets(2));
    expect(find.text(l10n.usdEarnTitle), findsOneWidget);
    expect(find.byType(UsdBalanceChart), findsOneWidget);
    expect(find.byType(UsdEarnChart), findsNothing);
    expect(api.calls, isEmpty);

    // Earn swaps the chart and is the first thing to read the API.
    await _tapPill(tester, find.byKey(const ValueKey('usd-balance-view-earn')));
    expect(find.byType(UsdEarnChart), findsOneWidget);
    expect(find.byType(UsdBalanceChart), findsNothing);
    expect(api.calls, contains('summary'));
    // The headline is the next payment — the venue's own estimate — with
    // the countdown under it and the rate beside it, each said once.
    expect(find.text(l10n.usdEarnNextPayment), findsOneWidget);
    final headline = tester.widget<RollingNumberText>(find.descendant(
        of: find.byType(UsdEarnChart),
        matching: find.byType(RollingNumberText)));
    expect(headline.text, '1,234 sats');
    expect(
        find.textContaining(RegExp(
            '^${RegExp.escape(l10n.usdEarnNextPaymentIn)} \\d+h \\d\\dm \\d\\ds\$')),
        findsOneWidget);
    expect(find.text(l10n.usdEarnRate), findsOneWidget);
    expect(find.text('4.5%'), findsOneWidget);

    // And back again: the balance chart, the Earn chart gone.
    await _tapPill(
        tester, find.byKey(const ValueKey('usd-balance-view-balance')));
    expect(find.byType(UsdBalanceChart), findsOneWidget);
    expect(find.byType(UsdEarnChart), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('policy unavailable: the Earn pill is hidden (fail closed)',
      (tester) async {
    final api = await _pump(tester, earn: _policyUnavailable);
    final l10n = tester.element(find.byType(UsdAccountBody)).l10n;
    expect(find.byType(UsdEarnChart), findsNothing);
    expect(find.text(l10n.usdEarnTitle), findsNothing);
    expect(find.text(l10n.seeAll), findsOneWidget);
    await _tapPill(tester, _stripBalancePill(tester, l10n));
    expect(find.byType(UsdBalanceTabs), findsNothing);
    expect(find.text(l10n.usdEarnTitle), findsNothing);
    expect(api.calls, isEmpty);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  // The founder rule: gating hides the Earn UI only. The dollar balance
  // is the user's own money and shows in every country, whatever
  // usd.earn (or the policy) says.
  for (final (label, earn) in [
    (
      'usd.earn denied (country block)',
      const CapabilityDecision(allowed: false, reason: 'country_blocked')
    ),
    ('usd.earn switched off', _earnOff),
    ('policy unavailable', _policyUnavailable),
    ('usd.earn allowed', _earnOn),
  ]) {
    testWidgets('$label: the dollar balance still shows', (tester) async {
      await _pump(tester, earn: earn);
      expect(find.textContaining('25.00'), findsWidgets);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  }

  testWidgets('an older policy that never heard of the id hides the pill',
      (tester) async {
    final api = await _pump(tester, earn: _unknownCapability);
    final l10n = tester.element(find.byType(UsdAccountBody)).l10n;
    await _tapPill(tester, _stripBalancePill(tester, l10n));
    expect(find.byType(UsdBalanceTabs), findsNothing);
    expect(find.byType(UsdEarnChart), findsNothing);
    expect(api.calls, isEmpty);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  group('the real policy service', () {
    late RuntimeCapabilitiesService policy;
    tearDown(() => policy.dispose());

    test('allows usd.earn only when a loaded policy says so', () async {
      policy = _policy({'usd.earn': true, 'orchestra.swap': true});
      expect(await policy.refresh(), isTrue);
      expect(policy.decision('usd.earn').allowed, _earnOn.allowed);
      expect(policy.allows('usd.earn'), isTrue);
    });

    test('denies usd.earn when the policy switches it off', () async {
      policy = _policy({'usd.earn': false, 'orchestra.swap': true});
      await policy.refresh();
      expect(policy.decision('usd.earn').allowed, isFalse);
      expect(policy.decision('usd.earn').reason, _earnOff.reason);
    });

    test('fails closed while the policy cannot be fetched', () async {
      policy = _policy(null);
      expect(await policy.refresh(), isFalse);
      expect(policy.snapshot, isNull);
      expect(policy.decision('usd.earn').allowed, isFalse);
      expect(policy.decision('usd.earn').reason, _policyUnavailable.reason);
      expect(policy.allows('usd.earn'), isFalse);
    });

    test('fails closed on a policy that never heard of the id', () async {
      policy = _policy({'orchestra.swap': true});
      await policy.refresh();
      expect(policy.decision('usd.earn').allowed, isFalse);
      expect(policy.decision('usd.earn').reason, _unknownCapability.reason);
      expect(policy.allows('usd.earn'), isFalse);
    });

    test('the rewards providers never ask the API while the tab is off',
        () async {
      policy = _policy({'usd.earn': false});
      await policy.refresh();
      final api = _RecordingRewardsApi();
      final container = ProviderContainer(overrides: [
        runtimeCapabilitiesProvider.overrideWithValue(policy),
        sparkIdentityPubkeyProvider.overrideWith((_) async => 'pub'),
        usdRewardsApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);
      expect(container.read(usdEarnEnabledProvider), isFalse);
      expect(await container.read(userRewardsSummaryProvider.future), isNull);
      expect(await container.read(payoutHistoryProvider(earnPayoutPage).future),
          isNull);
      expect(api.calls, isEmpty);
    });
  });
}
