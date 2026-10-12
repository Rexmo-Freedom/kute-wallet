// The Earn view is a rate display gated by the backend `usd.earn`
// capability. It lives under the Portfolio's Statistics tab (Investments
// › Portfolio › Statistics › Earn), beside the venue pills there. Off, or
// with no policy to read, the pill does not exist: the rewards API is
// never asked and no `usd_earn_*` event fires. On, the pill is there but
// the chart mounts only once it is picked, and only then reads the API
// and fires the open event. The Investments strip itself has no Earn
// pill in either case.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/usd_rewards_provider.dart';
import 'package:kute/screens/portfolio/portfolio_statistics.dart';
import 'package:kute/screens/shared/pool_balance_header.dart';
import 'package:kute/screens/shared/portfolio_tabs.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/screens/usd/components/usd_balance_tabs.dart';
import 'package:kute/screens/usd/components/usd_earn_chart.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import 'investments_harness.dart';

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

Finder _pill(String label) => investmentsPill(label);

AppLocalizations _l10n(WidgetTester tester) =>
    tester.element(find.byType(InvestmentsBody)).l10n;

final _earnPill = find.byKey(const ValueKey('portfolio-statistics-earn'));

/// Opens Portfolio › Statistics.
Future<void> _openStatistics(WidgetTester tester) async {
  await tapPill(tester, _l10n(tester).walletPortfolioAction);
  final context = tester.element(find.byType(PortfolioTabs));
  DefaultTabController.of(context).animateTo(3);
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('capability off: no Earn pill anywhere, no rewards read',
      (tester) async {
    final api = await pumpInvestments(tester, earn: kEarnOff);
    final l10n = _l10n(tester);
    expect(_pill(l10n.usdEarnTitle), findsNothing);
    await _openStatistics(tester);
    expect(find.byType(PortfolioStatistics), findsOneWidget);
    expect(_earnPill, findsNothing);
    expect(find.byType(UsdBalanceTabs, skipOffstage: false), findsNothing);
    expect(find.byType(UsdEarnChart, skipOffstage: false), findsNothing);
    expect(find.text(l10n.usdEarnRate), findsNothing);
    // The venue statistics are there regardless.
    expect(find.byKey(const ValueKey('portfolio-statistics-trading')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('portfolio-statistics-predictions')),
        findsOneWidget);
    expect(api.calls, isEmpty);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets(
      'capability on: Earn is a Statistics pill, never an Investments '
      'pill; its chart mounts on the pick', (tester) async {
    final events = recordEvents();
    final api =
        await pumpInvestments(tester, earn: kEarnOn, estimatedSatsToday: 1234);
    final l10n = _l10n(tester);
    expect(_pill(l10n.usdEarnTitle), findsNothing);
    await _openStatistics(tester);
    // The pill is there, after the venues; nothing has read the rewards
    // API yet, and the venue figures are on screen.
    expect(_earnPill, findsOneWidget);
    expect(find.byType(PortfolioStatistics), findsOneWidget);
    expect(find.byType(UsdEarnChart, skipOffstage: false), findsNothing);
    expect(api.calls, isEmpty);
    expect(events.any((e) => e.$1 == 'usd_earn_opened'), isFalse);

    // Earn mounts the chart, which is the first thing to read the API.
    await tapAndPump(tester, _earnPill);
    expect(find.byType(UsdBalanceTabs), findsOneWidget);
    expect(find.byType(UsdEarnChart), findsOneWidget);
    expect(find.byType(PortfolioStatistics), findsNothing);
    expect(api.calls, contains('summary'));
    expect(events.where((e) => e.$1 == 'usd_earn_opened'), hasLength(1));
    expect(events.where((e) => e.$1 == 'portfolio_tab_changed').last.$2,
        {'tab': 'statistics', 'subtab': 'earn'});
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
    // No inner Balance pill: the Earn section IS the view.
    expect(find.byKey(const ValueKey('usd-balance-view-balance')),
        findsNothing);

    // Back to a venue's figures: the chart leaves the screen.
    await tapAndPump(
        tester, find.byKey(const ValueKey('portfolio-statistics-trading')));
    expect(find.byType(UsdEarnChart), findsNothing);
    expect(
        tester
            .widget<PortfolioStatistics>(find.byType(PortfolioStatistics))
            .venue
            .name,
        'trading');
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets('policy unavailable: the Earn pill is hidden (fail closed)',
      (tester) async {
    final api = await pumpInvestments(tester, earn: _policyUnavailable);
    await _openStatistics(tester);
    expect(_earnPill, findsNothing);
    expect(find.byType(UsdEarnChart, skipOffstage: false), findsNothing);
    expect(api.calls, isEmpty);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  // The founder rule: gating hides the Earn UI only. The dollar balance
  // is the user's own money and shows in every country, whatever
  // usd.earn (or the policy) says.
  for (final (label, earn) in [
    (
      'usd.earn denied (country block)',
      const CapabilityDecision(allowed: false, reason: 'country_blocked')
    ),
    ('usd.earn switched off', kEarnOff),
    ('policy unavailable', _policyUnavailable),
    ('usd.earn allowed', kEarnOn),
  ]) {
    testWidgets('$label: the dollar balance still shows', (tester) async {
      await pumpInvestments(tester, earn: earn);
      expect(
          tester
              .widget<PoolBalanceHeader>(find.byType(PoolBalanceHeader))
              .amountText,
          r'$25.00');
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });
  }

  testWidgets('an older policy that never heard of the id hides the pill',
      (tester) async {
    final api = await pumpInvestments(tester, earn: _unknownCapability);
    await _openStatistics(tester);
    expect(_earnPill, findsNothing);
    expect(find.byType(UsdEarnChart, skipOffstage: false), findsNothing);
    expect(api.calls, isEmpty);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  group('the real policy service', () {
    late RuntimeCapabilitiesService policy;
    tearDown(() => policy.dispose());

    test('allows usd.earn only when a loaded policy says so', () async {
      policy = _policy({'usd.earn': true, 'orchestra.swap': true});
      expect(await policy.refresh(), isTrue);
      expect(policy.decision('usd.earn').allowed, kEarnOn.allowed);
      expect(policy.allows('usd.earn'), isTrue);
    });

    test('denies usd.earn when the policy switches it off', () async {
      policy = _policy({'usd.earn': false, 'orchestra.swap': true});
      await policy.refresh();
      expect(policy.decision('usd.earn').allowed, isFalse);
      expect(policy.decision('usd.earn').reason, kEarnOff.reason);
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
      final api = RecordingRewardsApi();
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
