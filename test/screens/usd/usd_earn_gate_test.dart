// The Dollars Earn tab is a rate display gated by the backend `usd.earn`
// capability. Off, or with no policy to read, the tab does not exist:
// the strip is Activity and Balance, the rewards API is never asked and
// no `usd_earn_*` event fires. On, the tab leads the strip as before.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/usd_rewards_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/providers/usd_rewards_provider.dart';
import 'package:kute/screens/usd/components/usd_earn_chart.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/api/usd_rewards_api.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Records every rewards read so a test can prove none happened.
class _RecordingRewardsApi implements UsdRewardsApi {
  final calls = <String>[];

  @override
  Future<UserRewardsSummary> getUserSummary(String pubkey) async {
    calls.add('summary');
    return const UserRewardsSummary(
      pubkey: 'pub',
      usdbBalanceRaw: 0,
      usdbBalanceDisplay: 0,
      swapSats: 0,
      swapCount: 0,
      rewardsBracket: 0,
      rewardsPercent: 4.5,
      estimatedSatsToday: 0,
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
  CapabilityDecision decision(String id) => id == 'usd.earn'
      ? _decision
      : const CapabilityDecision(allowed: true);

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
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = _RecordingRewardsApi();
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

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('capability off: no Earn tab and no rewards read',
      (tester) async {
    final api = await _pump(tester, earn: _earnOff);
    final l10n = tester.element(find.byType(UsdAccountBody)).l10n;
    expect(find.byType(UsdEarnChart), findsNothing);
    expect(find.text(l10n.usdEarnTitle), findsNothing);
    expect(find.text(l10n.usdEarnRate), findsNothing);
    // The strip is still there for Activity (showing, so its pill reads
    // "See all") and Balance.
    expect(find.text(l10n.seeAll), findsOneWidget);
    expect(find.text(l10n.balance), findsOneWidget);
    expect(api.calls, isEmpty);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('capability on: the Earn tab leads the strip', (tester) async {
    final api = await _pump(tester, earn: _earnOn);
    final l10n = tester.element(find.byType(UsdAccountBody)).l10n;
    expect(find.byType(UsdEarnChart), findsOneWidget);
    expect(find.text(l10n.usdEarnTitle), findsWidgets);
    expect(find.text(l10n.activity), findsOneWidget);
    expect(find.text(l10n.balance), findsOneWidget);
    expect(api.calls, contains('summary'));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('policy unavailable: the tab is hidden (fail closed)',
      (tester) async {
    final api = await _pump(tester, earn: _policyUnavailable);
    final l10n = tester.element(find.byType(UsdAccountBody)).l10n;
    expect(find.byType(UsdEarnChart), findsNothing);
    expect(find.text(l10n.usdEarnTitle), findsNothing);
    expect(find.text(l10n.seeAll), findsOneWidget);
    expect(api.calls, isEmpty);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  // The founder rule: gating hides the Earn UI only. The dollar balance
  // is the user's own money and shows in every country, whatever
  // usd.earn (or the policy) says.
  for (final (label, earn) in [
    ('usd.earn denied (country block)',
        const CapabilityDecision(allowed: false, reason: 'country_blocked')),
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

  testWidgets('an older policy that never heard of the id hides the tab',
      (tester) async {
    final api = await _pump(tester, earn: _unknownCapability);
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
      expect(
          await container.read(payoutHistoryProvider(earnPayoutPage).future),
          isNull);
      expect(api.calls, isEmpty);
    });
  });
}
