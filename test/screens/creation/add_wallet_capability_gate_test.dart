// Each way to add a wallet beyond the spending account answers to its own
// runtime capability: hardware.wallet (hardware signers and the "Other
// wallet" watch-only xpub), wallet.savings (another hot bitcoin wallet) and
// wallet.tracked (a single address). Every option is always shown; a tap
// on a withheld one starts nothing and opens the shared unavailable sheet.
// "Add wallet" itself is never hidden.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/creation/add_wallet.dart';
import 'package:kute/screens/creation/bitcoin_wallet_setup.dart';
import 'package:kute/services/add_wallet_capabilities.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

class _Policy extends ChangeNotifier implements RuntimeCapabilitiesService {
  _Policy(this.denied);
  final Set<String> denied;

  @override
  CapabilityDecision decision(String id) => denied.contains(id)
      ? const CapabilityDecision(allowed: false, reason: 'disabled')
      : const CapabilityDecision(allowed: true);

  @override
  bool allows(String id) => decision(id).allowed;

  @override
  String? blockReason(String id) => allows(id) ? null : 'blocked';

  @override
  Future<void> ensureAllowed(String id,
      {Duration maxAge = Duration.zero}) async {
    if (!allows(id)) throw CapabilityUnavailableException(id, decision(id));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Settings _settings(List<WalletConfig> wallets) => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: 'Blockstream',
      reviewDone: false,
      wallets: wallets,
      activeWalletId: wallets.firstOrNull?.id,
    );

class _MemorySettings extends SettingsModel {
  _MemorySettings(super.state);
}

final _spending = WalletConfig(id: 'spending', name: 'Spending');
final _ledger = WalletConfig(
    id: 'ledger-1', name: 'My Ledger', sparkEnabled: false, isHardware: true);

Future<AppLocalizations> _pump(WidgetTester tester, _Policy policy) async {
  tester.view.physicalSize = const Size(430, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  RuntimeCapabilitiesService.debugInstance = policy;
  addTearDown(() => RuntimeCapabilitiesService.debugInstance = null);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      runtimeCapabilitiesProvider.overrideWithValue(policy),
      settingsProvider
          .overrideWith((_) => _MemorySettings(_settings([_spending, _ledger]))),
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
        home: const AddWallet(),
      ),
    ),
  ));
  await tester.pump();
  return AppLocalizations.of(tester.element(find.byType(AddWallet)));
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  /// The rows each capability governs, by visible title.
  Map<String, List<String>> rows(AppLocalizations l10n) => {
        kHardwareWalletCapability: [
          'Ledger',
          'Blockstream Jade',
          'Keystone',
          l10n.addWalletOther,
        ],
        // The Bitcoin wallet row and its section share one title.
        kSavingsWalletCapability: [l10n.walletTypeBitcoin],
        kTrackedAddressCapability: [l10n.trackAddress],
      };

  testWidgets('every option shows while every capability is on',
      (tester) async {
    final l10n = await _pump(tester, _Policy({}));
    for (final titles in rows(l10n).values) {
      for (final title in titles) {
        expect(find.text(title), findsWidgets, reason: title);
      }
    }
  });

  testWidgets('every option still shows with every capability off',
      (tester) async {
    final l10n = await _pump(tester, _Policy({...kAddWalletCapabilities}));
    for (final titles in rows(l10n).values) {
      for (final title in titles) {
        expect(find.text(title), findsWidgets, reason: title);
      }
    }
    expect(find.text(l10n.walletsHardwareWalletsSection), findsOneWidget);
    expect(find.text(l10n.walletsWatchAnAddressSection), findsOneWidget);
  });

  for (final denied in kAddWalletCapabilities) {
    testWidgets('$denied off: its options show, a tap opens the sheet only',
        (tester) async {
      final l10n = await _pump(tester, _Policy({denied}));
      for (final title in rows(l10n)[denied]!) {
        final row = find.text(title).last;
        expect(row, findsOneWidget, reason: title);
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();
        // The flow did not start: still on Add wallet (no import screen,
        // no BitcoinWalletSetup, no scan), with the unavailable sheet up.
        expect(find.byKey(const ValueKey('capability-unavailable-got-it')),
            findsOneWidget,
            reason: title);
        expect(find.byType(BitcoinWalletSetup), findsNothing, reason: title);
        await tester.tap(
            find.byKey(const ValueKey('capability-unavailable-got-it')));
        await tester.pumpAndSettle();
        expect(find.byType(AddWallet), findsOneWidget);
      }
    });
  }

  test('the tap check passes only what the policy allows', () async {
    final policy = _Policy({kHardwareWalletCapability});
    expect(await addWalletOptionDenial(policy, 'ledger'), isNotNull);
    expect(await addWalletOptionDenial(policy, 'generic'), isNotNull);
    expect(await addWalletOptionDenial(policy, 'bitcoin'), isNull);
    expect(await addWalletOptionDenial(policy, 'external_address'), isNull);
    // The spending account answers to none of these switches.
    expect(
        await addWalletOptionDenial(_Policy({...kAddWalletCapabilities}),
            'spark'),
        isNull);
  });

  test('watch-only and hardware imports share one switch', () {
    expect(kAddWalletCapabilities, isNot(contains('wallet.watchonly')));
    expect(xpubImportCapability('ledger'), kHardwareWalletCapability);
    expect(xpubImportCapability('jade'), kHardwareWalletCapability);
    expect(xpubImportCapability('keystone'), kHardwareWalletCapability);
    expect(xpubImportCapability('generic'), kHardwareWalletCapability);
    expect(addWalletOptionCapability('generic'), kHardwareWalletCapability);
  });
}
