// Gating audit (fw42, v2.2): the Bitcoin home's Purchase door against a
// real backend policy. Purchase is Cash App (`onramp.cashapp`), which the
// backend offers on an allow list: "US only" (mode `only`, countries
// ['US']). Asked from anywhere else the backend refuses with
// `country_not_allowed` and sends the allow list's places as `regions`:
// where Cash App IS offered.
//
// Founder, 7 November 2026, in Lisbon: "not avaliable in usa? my vpn is in
// lisbon. please just say not avaliable right now". So an allow list's
// refusal reads just "Not available right now": no region, no VPN
// sentence, the plain "Got it", nothing counted as
// `capability_region_blocked`. A block list's region refusal (the swap
// master's, inherited) keeps the standing copy: the named regions over
// the one VPN sentence, "Check connection", counted once.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/bitcoin_wallet_actions.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/screens/shared/money_movement_sheet.dart';
import 'package:kute/services/onramp_visibility.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/kute_bar_test_support.dart';
import 'market_gating_fixtures.dart';

final _en = marketGatingEn;
final _spending = WalletConfig(id: 'spending', name: 'Spending');

/// Cash App's allow list refusing a caller in Portugal, as the backend
/// writes it (internal/policy: `country_not_allowed`, the allow list's
/// places as `regions`).
const _usOnly = {
  'allowed': false,
  'reason': 'country_not_allowed',
  'regions': {
    'label': 'the United States',
    'labels': {'pt': 'nos Estados Unidos'},
    'countries': ['US'],
  },
};

/// Cash App following the swap master's block list (a `requires`
/// cascade): `country_blocked`, the block list's places named.
const _swapBlocked = {
  'allowed': false,
  'reason': 'country_blocked',
  'blockedBy': kSwapMaster,
  'regions': kGatingRegions,
};

Future<RuntimeCapabilitiesService> _install(WidgetTester tester,
    {Map<String, Object?>? cashApp}) async {
  AffiliateService.debugSessionToken = 'gating-audit-session';
  final policy = marketGatingPolicy(null, overrides: {
    if (cashApp != null) kOnrampCashApp: cashApp,
  });
  RuntimeCapabilitiesService.debugInstance = policy;
  expect(await tester.runAsync(policy.refresh), isTrue);
  return policy;
}

/// Unmounts and disposes the policy inside the test's clock: a tap's
/// re-check leaves the policy's expiry timer running.
Future<void> _release(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  RuntimeCapabilitiesService.debugInstance?.dispose();
  RuntimeCapabilitiesService.debugInstance = null;
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: true,
            activeWalletId: _spending.id,
            wallets: [_spending],
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
        home: Scaffold(
          body: BitcoinWalletPrimaryActions(wallet: _spending, source: 'home'),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tapPurchase(WidgetTester tester) async {
  await tester.tap(find.text('Purchase Bitcoin'));
  await tester.pumpAndSettle();
}

void main() {
  late List<String?> purchases;
  late List<MoneyMovementRequest> moves;
  late List<(String, Map<String, Object>?)> events;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    purchases = [];
    moves = [];
    events = [];
    debugBitcoinPurchaseOpener =
        (_, {fiatDepositWalletId}) => purchases.add(fiatDepositWalletId);
    debugMoneyMovementSheetOpener = (_, request) => moves.add(request);
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    debugBitcoinPurchaseOpener = null;
    debugMoneyMovementSheetOpener = null;
    TrackingService.debugTrackObserver = null;
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  });

  testWidgets('Cash App on offer (in the US): Purchase opens it, no sheet',
      (tester) async {
    await _install(tester);
    await _pumpHome(tester);
    await _tapPurchase(tester);
    expect(find.byType(CapabilityUnavailableSheet), findsNothing);
    expect(purchases, [null]);
    await _release(tester);
  });

  testWidgets(
      'outside Cash App\'s allow list (Portugal): just "Not available right '
      'now", no United States, no VPN sentence, Got it, nothing counted as '
      'a region block, nothing opened', (tester) async {
    await _install(tester, cashApp: _usOnly);
    await _pumpHome(tester);
    await _tapPurchase(tester);

    expect(find.byType(CapabilityUnavailableSheet), findsOneWidget);
    expect(find.text('Not available right now'), findsOneWidget);
    expect(
        tester
            .widget<AppBottomSheetHeader>(find.byType(AppBottomSheetHeader))
            .subtitle,
        isNull,
        reason: 'the title alone');
    expect(find.textContaining('United States'), findsNothing);
    expect(find.textContaining('Not available in'), findsNothing);
    expect(find.textContaining('VPN'), findsNothing);
    expect(find.text(_en.capabilityRegionTitle), findsNothing);
    expect(find.text(_en.buyUnavailableTitle), findsNothing);
    expect(kuteBarPrimaryWithText(_en.gotIt), findsOneWidget);
    expect(kuteBarPrimaryWithText(_en.checkConnection), findsNothing);
    expect(events.where((e) => e.$1 == 'capability_region_blocked'), isEmpty);

    await tester.tap(kuteBarPrimary);
    await tester.pumpAndSettle();
    expect(find.byType(CapabilityUnavailableSheet), findsNothing);
    expect(purchases, isEmpty);
    expect(moves, isEmpty);
    await _release(tester);
  });

  testWidgets(
      'a block list\'s region refusal (the swap master\'s, inherited): the '
      'named regions over the one VPN sentence, Check connection, counted '
      'once on bitcoin_purchase', (tester) async {
    await _install(tester, cashApp: _swapBlocked);
    await _pumpHome(tester);
    await _tapPurchase(tester);

    expect(find.byType(CapabilityUnavailableSheet), findsOneWidget);
    expect(find.text(kGatingNamedTitle), findsOneWidget);
    expect(find.text(kGatingVpnSentence), findsOneWidget);
    expect(find.textContaining('use a VPN'), findsNothing);
    expect(find.text(_en.capabilityNotAvailableNow), findsNothing);
    expect(kuteBarPrimaryWithText(_en.checkConnection), findsOneWidget);
    expect(
        events
            .where((e) => e.$1 == 'capability_region_blocked')
            .map((e) => e.$2),
        [
          {
            'capability': kOnrampCashApp,
            'blocked_by': kSwapMaster,
            'surface': kBitcoinPurchaseSurface,
          },
        ]);
    expect(purchases, isEmpty);
    await _release(tester);
  });
}
