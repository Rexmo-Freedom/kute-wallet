// Gating audit (fw36, v2.2): Add wallet and the Settings top cards, read
// against a real backend policy under each way it withholds a capability.
//
//   * Add wallet: every option is drawn whatever the policy says; a tap on
//     a withheld one starts nothing and opens the shared unavailable
//     sheet with the policy's reason: a region block names the backend's
//     regions over the one VPN sentence and its button is "Check
//     connection"; a platform rule, the switch off or coming soon say so
//     under "Got it". A block on swaps never reaches the wallet switches.
//   * Settings: the referral card is there only while `affiliate.program`
//     is allowed; withheld in any way (a region, a platform, off, coming
//     soon, no policy readable) Rate the app takes its card. A block on
//     swaps never touches it.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/settings_model.dart' as settings_model;
import 'package:kute/models/settings_model.dart'
    show SettingsModel, WalletConfig;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/creation/add_wallet.dart';
import 'package:kute/screens/creation/bitcoin_wallet_setup.dart';
import 'package:kute/screens/settings/settings.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/services/add_wallet_capabilities.dart';
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/region_freshness.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/runtime_policy_snapshot_store.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/kute_bar_test_support.dart';
import 'market_gating_fixtures.dart'
    show
        MarketDenial,
        MarketDenialLabel,
        kGatingNamedTitle,
        kGatingRegions,
        kGatingVpnSentence,
        kSwapCascade,
        kSwapMaster;

final _en = AppLocalizationsEn();

const _ids = [
  kSwapMaster,
  ...kSwapCascade,
  'affiliate.program',
  'export.transactions',
  'settings.advanced',
  kHardwareWalletCapability,
  kSavingsWalletCapability,
  kTrackedAddressCapability,
];

/// One denial of [how] for a capability that is not part of the swap
/// cascade (its own region block, named).
Map<String, Object?> _denial(MarketDenial how) => switch (how) {
      MarketDenial.swapCountryBlock => {
          'allowed': false,
          'reason': 'country_blocked',
          'regions': kGatingRegions,
        },
      MarketDenial.platform => {
          'allowed': false,
          'reason': 'platform_not_allowed'
        },
      MarketDenial.masterOff => {'allowed': false, 'reason': 'disabled'},
      MarketDenial.comingSoon => {
          'allowed': false,
          'reason': 'coming_soon',
          'comingSoon': true,
        },
    };

/// The swap master blocked for named regions and its cascade.
Map<String, Map<String, Object?>> get _swapBlock => {
      kSwapMaster: {
        'allowed': false,
        'reason': 'country_blocked',
        'regions': kGatingRegions,
      },
      for (final id in kSwapCascade)
        id: {
          'allowed': false,
          'reason': 'country_blocked',
          'blockedBy': kSwapMaster,
          'regions': kGatingRegions,
        },
    };

/// A backend that answers [decisions] (everything else allowed), or, with
/// [reachable] false, never answers.
RuntimeCapabilitiesService _policy(
        {Map<String, Map<String, Object?>> decisions = const {},
        bool reachable = true}) =>
    RuntimeCapabilitiesService.forTesting(
      client: MockClient((_) async {
        if (!reachable) return http.Response('unavailable', 503);
        final now = DateTime.now().toUtc();
        return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'revision': 1,
              'evaluatedAt': now.toIso8601String(),
              'expiresAt':
                  now.add(const Duration(minutes: 2)).toIso8601String(),
              'capabilities': {
                for (final id in _ids) id: decisions[id] ?? {'allowed': true},
              },
            }),
            200);
      }),
      baseUrl: () => 'https://policy.test',
      sessionToken: () => AffiliateService.sessionToken,
      appVersion: () async => '2.2.0',
      store: MemoryRuntimePolicySnapshotStore(),
    );

Future<RuntimeCapabilitiesService> _install(WidgetTester tester,
    {Map<String, Map<String, Object?>> decisions = const {},
    bool reachable = true}) async {
  final policy = _policy(decisions: decisions, reachable: reachable);
  RuntimeCapabilitiesService.debugInstance = policy;
  final loaded = await tester.runAsync(policy.refresh);
  expect(loaded, reachable);
  return policy;
}

Future<void> _pumpSettings(
    WidgetTester tester, RuntimeCapabilitiesService policy) async {
  tester.view.physicalSize = const Size(390, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final never = Completer<settings_model.Settings>();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      initialSettingsProvider.overrideWith((ref) => never.future),
      biometricsAvailableProvider.overrideWith((ref) async => false),
      appVersionLabelProvider.overrideWith((ref) async => '2.2.0 (91)'),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Settings(),
      ),
    ),
  ));
  await tester.pump();
}

class _MemorySettings extends SettingsModel {
  _MemorySettings(super.state);
}

Future<void> _pumpAddWallet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider
          .overrideWith((_) => _MemorySettings(settings_model.Settings(
                currency: 'USD',
                language: 'en',
                btcFormat: 'sats',
                backup: false,
                biometricsEnabled: false,
                bitcoinElectrumNode: '',
                nodeType: 'Blockstream',
                reviewDone: false,
                wallets: [WalletConfig(id: 'spending', name: 'Spending')],
                activeWalletId: 'spending',
              ))),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        builder: withKuteShellBar,
        theme: ThemeData(
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AddWallet(),
      ),
    ),
  ));
  await tester.pump();
}

/// Unmounts and disposes the policy inside the test's clock: a tap's
/// re-check leaves the policy's expiry timer running.
Future<void> _release(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  RuntimeCapabilitiesService.debugInstance?.dispose();
  RuntimeCapabilitiesService.debugInstance = null;
  await tester.pump(const Duration(seconds: 1));
}

Finder _card(String id) => find.byKey(ValueKey('settings-card-$id'));

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TrackingService.setDisabled(true);
    AffiliateService.debugSessionToken = 'gating-audit-session';
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
    TrackingService.setDisabled(false);
  });

  group('Settings: the referral card', () {
    testWidgets('allowed: the referral card, no Rate the app card',
        (tester) async {
      final policy = await _install(tester);
      await _pumpSettings(tester, policy);
      expect(_card('referral'), findsOneWidget);
      expect(_card('rate'), findsNothing);
    });

    for (final how in MarketDenial.values) {
      testWidgets(
          'affiliate.program withheld (${how == MarketDenial.swapCountryBlock ? 'its own region block' : how.label}): '
          'Rate the app takes its card, no reason shown', (tester) async {
        final policy = await _install(tester,
            decisions: {'affiliate.program': _denial(how)});
        await _pumpSettings(tester, policy);
        expect(_card('referral'), findsNothing);
        expect(_card('rate'), findsOneWidget);
        expect(find.text(_en.settingsRateTheApp), findsOneWidget);
        expect(find.textContaining('Not available'), findsNothing);
      });
    }

    testWidgets(
        'no policy readable: the referral card waits (Rate the app); the '
        'local Export and Bitcoin server stay', (tester) async {
      final policy = await _install(tester, reachable: false);
      expect(policy.allows('affiliate.program'), isFalse);
      expect(policy.allows('export.transactions'), isTrue);
      await _pumpSettings(tester, policy);
      expect(_card('rate'), findsOneWidget);
      expect(_card('referral'), findsNothing);
    });

    testWidgets('a swap country block never touches the referral card',
        (tester) async {
      final policy = await _install(tester, decisions: _swapBlock);
      await _pumpSettings(tester, policy);
      expect(_card('referral'), findsOneWidget);
      expect(_card('rate'), findsNothing);
    });
  });

  group('Add wallet: hardware.wallet', () {
    Future<void> tapLedger(WidgetTester tester) async {
      final ledger = find.byKey(const ValueKey('add-wallet-option-ledger'));
      expect(ledger, findsOneWidget, reason: 'every option is drawn');
      await tester.ensureVisible(ledger);
      await tester.tap(ledger);
      await tester.pumpAndSettle();
    }

    testWidgets(
        'its own region block: Ledger is drawn; its tap names the regions '
        'over the one VPN sentence, the button is Check connection, '
        'nothing pairs', (tester) async {
      await _install(tester, decisions: {
        kHardwareWalletCapability: _denial(MarketDenial.swapCountryBlock),
      });
      await _pumpAddWallet(tester);
      await tapLedger(tester);
      expect(find.byType(CapabilityUnavailableSheet), findsOneWidget);
      expect(find.text(kGatingNamedTitle), findsOneWidget);
      expect(find.text(kGatingVpnSentence), findsOneWidget);
      expect(find.textContaining('use a VPN'), findsNothing);
      expect(kuteBarPrimaryWithText(_en.checkConnection), findsOneWidget);
      expect(find.byType(BitcoinWalletSetup), findsNothing);
      // The check asks hardware.wallet again: still blocked, still here.
      await tester.runAsync(() async {
        await tester.tap(kuteBarPrimary);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.byType(AddWallet), findsOneWidget);
      await _release(tester);
    });

    testWidgets(
        'Check connection asks hardware.wallet itself: allowed again while '
        'swaps stay blocked for a region, the sheet closes', (tester) async {
      final venues = InvestmentProviderAvailability(
        client: MockClient((request) async => request.url.host ==
                'api.hyperliquid.xyz'
            ? http.Response(
                '{"acceptedTerms":true,"userAllowed":true,"restrictions":"n"}',
                200)
            : http.Response('{"blocked":false}', 200)),
        report: ({
          required String venue,
          required String trigger,
          required bool changed,
          required String result,
        }) {},
      );
      RegionFreshness.debugVenues = venues;
      addTearDown(() {
        RegionFreshness.debugVenues = null;
        venues.dispose();
      });
      final decisions = {
        ..._swapBlock,
        kHardwareWalletCapability: _denial(MarketDenial.swapCountryBlock),
      };
      await _install(tester, decisions: decisions);
      await _pumpAddWallet(tester);
      await tapLedger(tester);
      expect(find.byType(CapabilityUnavailableSheet), findsOneWidget);
      // The VPN changed: the hardware switch answers yes, swaps still no.
      decisions.remove(kHardwareWalletCapability);
      await tester.tap(kuteBarPrimary);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(RuntimeCapabilitiesService.instance.allows(kSwapMaster), isFalse);
      expect(find.byType(CapabilityUnavailableSheet), findsNothing);
      expect(find.byType(AddWallet), findsOneWidget);
      await _release(tester);
    });

    for (final how in [
      MarketDenial.platform,
      MarketDenial.masterOff,
      MarketDenial.comingSoon,
    ]) {
      testWidgets(
          '${how.label}: Ledger is drawn; its tap says why under Got it, '
          'nothing pairs', (tester) async {
        await _install(tester,
            decisions: {kHardwareWalletCapability: _denial(how)});
        await _pumpAddWallet(tester);
        await tapLedger(tester);
        expect(find.byType(CapabilityUnavailableSheet), findsOneWidget);
        expect(find.text(how.message), findsOneWidget);
        expect(kuteBarPrimaryWithText(_en.gotIt), findsOneWidget);
        await tester.tap(kuteBarPrimary);
        await tester.pumpAndSettle();
        expect(find.byType(CapabilityUnavailableSheet), findsNothing);
        expect(find.byType(AddWallet), findsOneWidget);
        await _release(tester);
      });
    }

    test(
        'a swap country block never reaches the wallet switches: hardware, '
        'Other wallet, another bitcoin wallet and a tracked address pass',
        () async {
      final policy = _policy(decisions: _swapBlock);
      addTearDown(policy.dispose);
      expect(await policy.refresh(), isTrue);
      for (final type in [
        'ledger',
        'jade',
        'generic',
        'bitcoin',
        'external_address',
        'spark'
      ]) {
        expect(await addWalletOptionDenial(policy, type), isNull, reason: type);
      }
    });

    test('no policy readable: adding a wallet waits for one', () async {
      final policy = _policy(reachable: false);
      addTearDown(policy.dispose);
      expect(await policy.refresh(), isFalse);
      final denial = await addWalletOptionDenial(policy, 'ledger');
      expect(denial?.reason, 'policy_unavailable');
      expect(await addWalletOptionDenial(policy, 'spark'), isNull);
    });
  });
}
