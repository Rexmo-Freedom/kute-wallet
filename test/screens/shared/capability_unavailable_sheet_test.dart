// The one "unavailable" sheet a blocked Bet, order, Deposit or Add money
// opens: a region block reads "Not available in your region" over the
// network / VPN sentence, and its one button is "Check connection";
// anything else reads the generic title over the policy's own reason, and
// one "Got it" closes it. Never a reason code.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/services/region_freshness.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/runtime_policy_snapshot_store.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _pt = lookupAppLocalizations(const Locale('pt'));

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<BuildContext> pumpHost(WidgetTester tester,
      {Locale locale = const Locale('en')}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext captured;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        locale: locale,
        theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            fontFamily: 'Inter',
            extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          captured = context;
          return const Scaffold();
        }),
      ),
    ));
    return captured;
  }

  /// Dismissed the way every sheet is: a tap outside it.
  Future<void> dismiss(WidgetTester tester) async {
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
  }

  testWidgets('region block: region title and the VPN sentence',
      (tester) async {
    final context = await pumpHost(tester);
    const decision =
        CapabilityDecision(allowed: false, reason: 'country_blocked');
    showCapabilityDecisionSheet(context, decision);
    await tester.pumpAndSettle();

    expect(find.byType(CapabilityUnavailableSheet), findsOneWidget);
    // Built like every other sheet: the shared container and header.
    expect(find.byType(AppBottomSheetContainer), findsOneWidget);
    expect(find.byType(AppBottomSheetHeader), findsOneWidget);
    expect(find.text(_en.capabilityRegionTitle), findsOneWidget);
    expect(find.text(_en.capabilityRegionRestricted), findsOneWidget);
    expect(_en.capabilityRegionRestricted, contains('VPN'));
    expect(find.text(_en.gateUnavailableTitle), findsNothing);
    expect(find.textContaining('country_blocked'), findsNothing);
    // Its one button asks again, never "Got it".
    expect(find.text(_en.checkConnection), findsOneWidget);
    expect(find.text(_en.gotIt), findsNothing);

    await dismiss(tester);
    expect(find.byType(CapabilityUnavailableSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a region the backend named: "Not available in …" over the one VPN '
      'sentence, Check connection, counted once without the region',
      (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    final context = await pumpHost(tester);
    final decision = CapabilityDecision.fromJson({
      'allowed': false,
      'reason': 'country_blocked',
      'blockedBy': 'orchestra.swap',
      'message': 'The operator text of orchestra.swap.',
      'regions': {
        'label': 'the European Union, the UK and Switzerland',
        'labels': {'pt': 'na União Europeia, no Reino Unido e na Suíça'},
        'groups': ['EU', 'UK'],
        'countries': ['CH'],
      },
    });
    showCapabilityDecisionSheet(context, decision,
        capability: 'hyperliquid.deposit', surface: 'investing_deposit');
    await tester.pumpAndSettle();

    expect(
        find.text(
            'Not available in the European Union, the UK and Switzerland'),
        findsOneWidget);
    expect(find.text("If this isn't where you are, check your VPN settings."),
        findsOneWidget);
    expect(find.text(_en.capabilityRegionTitle), findsNothing);
    expect(find.textContaining('operator text'), findsNothing);
    expect(find.text(_en.checkConnection), findsOneWidget);
    expect(find.textContaining(RegExp(r'use (a )?VPN', caseSensitive: false)),
        findsNothing);
    expect(
        events
            .where((e) => e.$1 == 'capability_region_blocked')
            .map((e) => e.$2)
            .toList(),
        [
          {
            'capability': 'hyperliquid.deposit',
            'blocked_by': 'orchestra.swap',
            'surface': 'investing_deposit',
          }
        ]);
    await dismiss(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('generic block: generic title and the generic reason',
      (tester) async {
    final context = await pumpHost(tester);
    const decision = CapabilityDecision(allowed: false, reason: 'switched_off');
    showCapabilityDecisionSheet(context, decision);
    await tester.pumpAndSettle();

    expect(find.text(_en.gateUnavailableTitle), findsOneWidget);
    expect(find.text(_en.capabilityUnavailable), findsOneWidget);
    expect(find.text(_en.capabilityRegionTitle), findsNothing);
    expect(find.text(_en.capabilityRegionRestricted), findsNothing);
    expect(find.textContaining('switched_off'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a caller title replaces the generic one, never the region one',
      (tester) async {
    final context = await pumpHost(tester);
    showCapabilityDecisionSheet(
        context, const CapabilityDecision(allowed: false, reason: 'off'),
        title: _en.gatePredictionsUnavailable);
    await tester.pumpAndSettle();
    expect(find.text(_en.gatePredictionsUnavailable), findsOneWidget);
    expect(find.text(_en.checkConnection), findsNothing);
    await tester.tap(find.text(_en.gotIt));
    await tester.pumpAndSettle();

    showCapabilityDecisionSheet(context,
        const CapabilityDecision(allowed: false, reason: 'country_not_allowed'),
        title: _en.gatePredictionsUnavailable);
    await tester.pumpAndSettle();
    expect(find.text(_en.capabilityRegionTitle), findsOneWidget);
    expect(find.text(_en.gatePredictionsUnavailable), findsNothing);
  });

  testWidgets('the venue\'s own region answer reads as a region block',
      (tester) async {
    final context = await pumpHost(tester);
    bool? shown;
    showCapabilityErrorSheet(
            context,
            const ProviderAvailabilityException(ProviderAvailability(
                InvestmentProvider.polymarket,
                ProviderAvailabilityStatus.restricted)))
        .then((value) => shown = value);
    await tester.pumpAndSettle();
    expect(find.text(_en.capabilityRegionTitle), findsOneWidget);
    expect(find.text(_en.providerRegionRestricted('Polymarket')),
        findsOneWidget);
    expect(find.text(_en.checkConnection), findsOneWidget);
    await dismiss(tester);
    expect(shown, isTrue);
  });

  testWidgets('a second tap never stacks another sheet', (tester) async {
    final context = await pumpHost(tester);
    const decision =
        CapabilityDecision(allowed: false, reason: 'country_blocked');
    showCapabilityDecisionSheet(context, decision);
    showCapabilityDecisionSheet(context, decision);
    await tester.pumpAndSettle();
    expect(find.byType(CapabilityUnavailableSheet), findsOneWidget);
    await dismiss(tester);
    expect(find.byType(CapabilityUnavailableSheet), findsNothing);
  });

  testWidgets('European Portuguese copy', (tester) async {
    final context = await pumpHost(tester, locale: const Locale('pt'));
    showCapabilityDecisionSheet(context,
        const CapabilityDecision(allowed: false, reason: 'country_blocked'));
    await tester.pumpAndSettle();
    expect(find.text(_pt.capabilityRegionTitle), findsOneWidget);
    expect(find.text(_pt.capabilityRegionRestricted), findsOneWidget);
    expect(find.text(_pt.checkConnection), findsOneWidget);
  });

  group('"Check connection"', () {
    // Kute's policy and both venues, answering as the test says.
    late bool policyBlocked;
    late bool venueBlocked;
    late List<String> triggers;
    late List<ContinuousHapticsCall> haptics;
    late RuntimeCapabilitiesService policy;
    late InvestmentProviderAvailability venues;

    setUp(() {
      policyBlocked = true;
      venueBlocked = false;
      triggers = [];
      haptics = ContinuousHaptics.debugLog = [];
      KuteHaptics.debugReset();
      KuteHaptics.debugForeground = () => true;
      policy = RuntimeCapabilitiesService.forTesting(
        client: MockClient((_) async {
          final now = DateTime.now().toUtc();
          return http.Response(
              jsonEncode({
                'schemaVersion': 1,
                'revision': 1,
                'evaluatedAt': now.toIso8601String(),
                'expiresAt':
                    now.add(const Duration(minutes: 15)).toIso8601String(),
                'capabilities': {
                  'polymarket.deposit': policyBlocked
                      ? {'allowed': false, 'reason': 'country_blocked'}
                      : {'allowed': true},
                },
              }),
              200);
        }),
        baseUrl: () => 'https://backend.test',
        sessionToken: () => 'wallet-a',
        store: MemoryRuntimePolicySnapshotStore(),
      );
      venues = InvestmentProviderAvailability(
        client: MockClient((request) async => request.url.host ==
                'api.hyperliquid.xyz'
            ? http.Response(
                jsonEncode({
                  'acceptedTerms': true,
                  'userAllowed': true,
                  'restrictions': 'n',
                }),
                200)
            : http.Response(jsonEncode({'blocked': venueBlocked}), 200)),
        report: ({
          required String venue,
          required String trigger,
          required bool changed,
          required String result,
        }) =>
            triggers.add(trigger),
      );
      RuntimeCapabilitiesService.debugInstance = policy;
      RegionFreshness.debugVenues = venues;
    });

    tearDown(() {
      RuntimeCapabilitiesService.debugInstance = null;
      RegionFreshness.debugVenues = null;
      ContinuousHaptics.debugLog = null;
      ContinuousHaptics.debugReset();
      KuteHaptics.debugReset();
      venues.dispose();
    });

    Future<void> frames(WidgetTester tester, [int n = 20]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<bool?> open(WidgetTester tester) async {
      final context = await pumpHost(tester);
      expect(await policy.refresh(), isTrue);
      final decision = policy.decision('polymarket.deposit');
      expect(decision.regionRestricted, isTrue);
      bool? result;
      showCapabilityDecisionSheet(context, decision,
              capability: 'polymarket.deposit')
          .then((value) => result = value);
      await tester.pumpAndSettle();
      expect(find.text(_en.checkConnection), findsOneWidget);
      // Not a dead button.
      expect(
          tester
              .widget<AppButton>(find.byKey(const ValueKey(
                  'capability-unavailable-check-connection')))
              .onPressed,
          isNotNull);
      return result;
    }

    Future<void> release(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      policy.dispose();
    }

    testWidgets('now allowed: the sheet closes and the door may go on',
        (tester) async {
      bool? result;
      final context = await pumpHost(tester);
      expect(await policy.refresh(), isTrue);
      showCapabilityDecisionSheet(context, policy.decision('polymarket.deposit'),
              capability: 'polymarket.deposit')
          .then((value) => result = value);
      await tester.pumpAndSettle();

      // Another VPN server, same VPN app: no path change, so the person
      // taps.
      policyBlocked = false;
      await tester.tap(find.text(_en.checkConnection));
      await frames(tester);
      await tester.pumpAndSettle();

      expect(find.byType(CapabilityUnavailableSheet), findsNothing);
      expect(result, isTrue);
      expect(policy.allows('polymarket.deposit'), isTrue);
      // Both venues asked live, reported as a manual check.
      expect(triggers, ['manual', 'manual']);
      expect(haptics.where((c) => c.method == 'softTap'), isEmpty);
      await release(tester);
    });

    testWidgets('still restricted: the sheet stays, with a failure tap',
        (tester) async {
      await open(tester);
      await tester.tap(find.text(_en.checkConnection));
      await frames(tester);
      await tester.pumpAndSettle();

      expect(find.byType(CapabilityUnavailableSheet), findsOneWidget);
      expect(find.text(_en.capabilityRegionRestricted), findsOneWidget);
      // Still "Check connection", ready for another try.
      expect(find.text(_en.checkConnection), findsOneWidget);
      expect(
          tester
              .widget<AppButton>(find.byKey(const ValueKey(
                  'capability-unavailable-check-connection')))
              .onPressed,
          isNotNull);
      expect(haptics.where((c) => c.method == 'softTap'), hasLength(1));

      // The VPN changes again; the next tap lifts it.
      policyBlocked = false;
      await tester.tap(find.text(_en.checkConnection));
      await frames(tester);
      await tester.pumpAndSettle();
      expect(find.byType(CapabilityUnavailableSheet), findsNothing);
      await release(tester);
    });

    testWidgets('the venue still refuses: restricted, whatever Kute says',
        (tester) async {
      await open(tester);
      policyBlocked = false;
      venueBlocked = true;
      await tester.tap(find.text(_en.checkConnection));
      await frames(tester);
      await tester.pumpAndSettle();
      expect(find.byType(CapabilityUnavailableSheet), findsOneWidget);
      expect(haptics.where((c) => c.method == 'softTap'), hasLength(1));
      await dismiss(tester);
      await release(tester);
    });
  });
}
