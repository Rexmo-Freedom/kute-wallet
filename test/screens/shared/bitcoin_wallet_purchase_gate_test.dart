// Purchase is Cash App, or Unavailable (founder, 7 November 2026: "only
// when Cash App is available should it show the purchase"). Both Purchase
// doors (the compact row's square and the big Purchase Bitcoin button),
// on the spending wallet and on a savings wallet, open the Cash App
// purchase while `onramp.cashapp` is on offer, and the shared Unavailable
// sheet otherwise, never another flow (not the Dollars into Bitcoin move).
// Outside Cash App's allow list (US only) the sheet reads just "Not
// available right now" (founder, 7 November 2026: "not avaliable in usa?
// my vpn is in lisbon"), naming no region and counting nothing; a block
// list's region refusal names the region and is counted on
// `bitcoin_purchase`. The door is always drawn and follows the policy live.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/screens/shared/bitcoin_wallet_actions.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/screens/shared/money_movement_sheet.dart';
import 'package:kute/services/onramp_visibility.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/kute_bar_test_support.dart';

class _Policy extends ChangeNotifier implements RuntimeCapabilitiesService {
  _Policy(
      {this.cashApp = true,
      this.reason = 'disabled',
      this.regions,
      this.blockedBy = ''});

  /// Whether `onramp.cashapp` is on offer.
  bool cashApp;

  /// The refusal's reason while it is not.
  String reason;

  /// The places the backend names with a country refusal, as it sends
  /// them (`regions`), and the capability a cascaded block inherits.
  final Map<String, Object?>? regions;
  final String blockedBy;

  /// Every capability asked about again ([confirmCapability]).
  final asked = <String>[];

  void set(bool value) {
    cashApp = value;
    notifyListeners();
  }

  @override
  CapabilityDecision decision(String id) => id == kOnrampCashApp && !cashApp
      ? CapabilityDecision.fromJson({
          'allowed': false,
          'reason': reason,
          if (regions != null) 'regions': regions,
          if (blockedBy.isNotEmpty) 'blockedBy': blockedBy,
        })
      : const CapabilityDecision(allowed: true);

  @override
  bool allows(String id) => decision(id).allowed && !decision(id).comingSoon;

  @override
  Future<CapabilityDecision> confirmDecision(String id) async {
    asked.add(id);
    return decision(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _l10n = AppLocalizationsEn();
final _spending = WalletConfig(id: 'spending', name: 'Spending');
final _savings = WalletConfig(
  id: 'cold',
  name: 'Cold',
  sparkEnabled: false,
  isHardware: true,
);

const _compact = ValueKey('compact-purchase');

Future<void> _pump(
    WidgetTester tester, _Policy policy, WalletConfig wallet) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      runtimeCapabilitiesProvider.overrideWith((ref) {
        policy.addListener(ref.notifyListeners);
        ref.onDispose(() => policy.removeListener(ref.notifyListeners));
        return policy;
      }),
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: true,
            activeWalletId: wallet.id,
            wallets: [_spending, _savings],
          ))),
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
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => Column(children: [
              BitcoinWalletPrimaryActions(wallet: wallet, source: 'test'),
              KuteCompactActions(
                  key: _compact,
                  source: 'home',
                  actions: [
                    bitcoinPurchaseDockAction(context, ref, wallet,
                        source: 'home'),
                  ]),
            ]),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The two Purchase doors.
final _doors = {
  'the big button': find.text('Purchase Bitcoin'),
  'the compact square': find.descendant(
      of: find.byKey(_compact), matching: find.text('Purchase')),
};

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
  });

  for (final wallet in [_spending, _savings]) {
    for (final door in _doors.entries) {
      testWidgets(
          '${wallet.name}, ${door.key}: Cash App on offer opens the Cash '
          'App purchase into that wallet, no sheet', (tester) async {
        await _pump(tester, _Policy(), wallet);
        await tester.tap(door.value);
        await tester.pumpAndSettle();
        expect(purchases, [wallet.isSparkWallet ? null : wallet.id]);
        expect(find.byType(CapabilityUnavailableSheet), findsNothing);
        expect(moves, isEmpty);
        expect(
            events.where((e) => e.$1 == 'quick_action_tapped'), isNotEmpty);
      });

      testWidgets(
          '${wallet.name}, ${door.key}: no Cash App opens the Unavailable '
          'sheet, never the purchase nor a move from Dollars',
          (tester) async {
        final policy = _Policy(cashApp: false);
        await _pump(tester, policy, wallet);
        await tester.tap(door.value);
        await tester.pumpAndSettle();
        expect(find.byType(CapabilityUnavailableSheet), findsOneWidget);
        expect(find.text(_l10n.buyUnavailableTitle), findsOneWidget);
        expect(find.text(_l10n.buyUnavailableBody), findsOneWidget);
        // The policy was asked again before saying so.
        expect(policy.asked, [kOnrampCashApp]);
        expect(purchases, isEmpty);
        expect(moves, isEmpty);
        // Not a region refusal: nothing counted as one.
        expect(events.where((e) => e.$1 == 'capability_region_blocked'),
            isEmpty);
      });
    }
  }

  testWidgets(
      'outside Cash App\'s allow list (US only, asked from Portugal) the '
      'sheet reads just "Not available right now": no country, no VPN '
      'sentence, Got it, nothing counted as a region block', (tester) async {
    final policy = _Policy(
        cashApp: false,
        reason: 'country_not_allowed',
        // What the backend sends with an allow list's refusal: where the
        // feature IS offered.
        regions: {
          'label': 'the United States',
          'countries': ['US'],
        });
    await _pump(tester, policy, _spending);
    await tester.tap(_doors['the big button']!);
    await tester.pumpAndSettle();
    final sheet = tester.widget<CapabilityUnavailableSheet>(
        find.byType(CapabilityUnavailableSheet));
    expect(sheet.regionRestricted, isFalse);
    expect(sheet.title, _l10n.capabilityNotAvailableNow);
    expect(sheet.message, isEmpty);
    expect(find.text('Not available right now'), findsOneWidget);
    expect(find.textContaining('United States'), findsNothing);
    expect(find.textContaining('VPN'), findsNothing);
    expect(find.text(_l10n.capabilityRegionTitle), findsNothing);
    expect(find.text(_l10n.buyUnavailableTitle), findsNothing);
    expect(find.text(_l10n.buyUnavailableBody), findsNothing);
    // The plain dismiss, never "Check connection".
    expect(kuteBarPrimaryContext(tester).label, _l10n.gotIt);
    expect(find.text(_l10n.checkConnection), findsNothing);
    expect(policy.asked, [kOnrampCashApp]);
    expect(events.where((e) => e.$1 == 'capability_region_blocked'), isEmpty);
    expect(purchases, isEmpty);
    expect(moves, isEmpty);
  });

  testWidgets(
      'a block list\'s region refusal (the swap cascade) still names the '
      'regions over the VPN sentence, offers Check connection and is '
      'counted once on bitcoin_purchase', (tester) async {
    await _pump(
        tester,
        _Policy(
            cashApp: false,
            reason: 'country_blocked',
            blockedBy: 'orchestra.swap',
            regions: {
              'label': 'the European Union, the UK and Switzerland',
              'groups': ['EU', 'UK'],
              'countries': ['CH'],
            }),
        _spending);
    await tester.tap(_doors['the big button']!);
    await tester.pumpAndSettle();
    final sheet = tester.widget<CapabilityUnavailableSheet>(
        find.byType(CapabilityUnavailableSheet));
    expect(sheet.regionRestricted, isTrue);
    expect(sheet.capabilities, [kOnrampCashApp]);
    expect(
        find.text(
            'Not available in the European Union, the UK and Switzerland'),
        findsOneWidget);
    expect(find.text(_l10n.capabilityRegionCheckVpn), findsOneWidget);
    expect(kuteBarPrimaryContext(tester).label, _l10n.checkConnection);
    expect(find.text(_l10n.capabilityNotAvailableNow), findsNothing);
    expect(
        events
            .where((e) => e.$1 == 'capability_region_blocked')
            .map((e) => e.$2),
        [
          {
            'capability': kOnrampCashApp,
            'blocked_by': 'orchestra.swap',
            'surface': kBitcoinPurchaseSurface,
          },
        ]);
    expect(purchases, isEmpty);
  });

  testWidgets(
      'the door stays drawn and follows the policy live: Cash App switched '
      'off, then on again', (tester) async {
    final policy = _Policy();
    await _pump(tester, policy, _savings);
    policy.set(false);
    await tester.pumpAndSettle();
    expect(find.text('Purchase Bitcoin'), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_scanner_rounded), findsOneWidget);
    await tester.tap(find.text('Purchase Bitcoin'));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.buyUnavailableTitle), findsOneWidget);
    Navigator.of(tester.element(find.byType(CapabilityUnavailableSheet)))
        .pop();
    await tester.pumpAndSettle();
    policy.set(true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Purchase Bitcoin'));
    await tester.pumpAndSettle();
    expect(purchases, ['cold']);
  });
}
