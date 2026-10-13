// Earn (the dollar rewards programme) is shown NOWHERE in the app
// (owner decision, 2026-10-13), whatever the backend `usd.earn`
// capability says: allowed, switched off, country-blocked, unknown to an
// older policy or with no policy at all. Portfolio › Statistics never
// shows an Earn figure, chart or heading; the rewards API is never asked
// and no `usd_earn_*` event fires. The policy still parses the id, and
// the dollar balance (the user's own money) shows in every case.

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

/// The heading the old Earn section wore.
final _earnSection = find.byKey(const ValueKey('portfolio-statistics-earn'));

/// Any Earn copy anywhere in the tree, on screen or not.
Finder _earnCopy() => find.textContaining(
    RegExp(r'^Earn$|Next payment|Pays in|Recent yearly rate|'
        r'No payments yet|Rewards start once'),
    skipOffstage: false);

/// Opens Portfolio › Statistics.
Future<void> _openStatistics(WidgetTester tester) async {
  await tapPill(tester,
      tester.element(find.byType(InvestmentsBody)).l10n.walletPortfolioAction);
  final context = tester.element(find.byType(PortfolioTabs));
  DefaultTabController.of(context).animateTo(3);
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls the Statistics list by [dy]: to its end, or back up.
Future<void> _scrollStatistics(WidgetTester tester, double dy) async {
  await tester.drag(find.byType(PortfolioStatisticsOverview), Offset(0, dy));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _scrollToEnd(WidgetTester tester) =>
    _scrollStatistics(tester, -800);

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final (label, earn) in [
    ('usd.earn allowed', kEarnOn),
    ('usd.earn switched off', kEarnOff),
    (
      'usd.earn denied (country block)',
      const CapabilityDecision(allowed: false, reason: 'country_blocked')
    ),
    ('policy unavailable', _policyUnavailable),
    ('a policy that never heard of the id', _unknownCapability),
  ]) {
    testWidgets(
        '$label: no Earn anywhere, Statistics is the one empty state, no '
        'rewards read', (tester) async {
      final events = recordEvents();
      final api = await pumpInvestments(tester,
          earn: earn, estimatedSatsToday: 1234);
      expect(_earnCopy(), findsNothing);
      await _openStatistics(tester);
      await _scrollToEnd(tester);
      expect(_earnSection, findsNothing);
      expect(_earnCopy(), findsNothing);
      // Never traded: the venues' one empty state, nothing above it.
      expect(find.byType(PortfolioStatisticsOverview), findsOneWidget);
      expect(find.byKey(const ValueKey('statistics-chart-empty')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('statistics-active')), findsNothing);
      expect(find.byKey(const ValueKey('statistics-figures')), findsNothing);
      expect(api.calls, isEmpty);
      expect(events.where((e) => e.$1.startsWith('usd_earn_')), isEmpty);
      expect(events.where((e) => e.$1 == 'usd_chart_range_changed'), isEmpty);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });
  }

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

    test('the rewards providers never ask the API while usd.earn is off',
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
