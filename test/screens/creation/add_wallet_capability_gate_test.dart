// Each way to add a wallet beyond the spending account answers to its own
// runtime capability: hardware.wallet (hardware signers and the "Other
// wallet" watch-only xpub), wallet.savings (another hot bitcoin wallet) and
// wallet.tracked (a single address). Every option is always shown; a tap
// on a withheld one starts nothing and opens the shared unavailable sheet.
// "Add wallet" itself is never hidden.
//
// Add wallet names only the hardware wallets that pair natively over
// Bluetooth (Ledger, Blockstream Jade), then "Other wallet" (any other
// signer's public key by QR code, file or paste) full width under them.
// Every option is a card, not a list row, as tall as what it holds.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/add_wallet_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/creation/add_wallet.dart';
import 'package:kute/screens/creation/bitcoin_wallet_setup.dart';
import 'package:kute/screens/creation/xpub_import_screen.dart';
import 'package:kute/services/add_wallet_capabilities.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/kute_bar_test_support.dart';

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

Future<AppLocalizations> _pump(WidgetTester tester, _Policy policy,
    {List<WalletConfig>? wallets, GoRouter? router}) async {
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
          .overrideWith((_) =>
              _MemorySettings(_settings(wallets ?? [_spending, _ledger]))),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) {
        final theme = ThemeData(
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        );
        return router == null
            ? MaterialApp(
                // The shell bar over the page (kute_bar_test_support.dart):
                // the unavailable sheet's "Got it" is the bar.
                builder: withKuteShellBar,
                theme: theme,
                localizationsDelegates:
                    AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const AddWallet(),
              )
            : MaterialApp.router(
                routerConfig: router,
                builder: withKuteShellBar,
                theme: theme,
                localizationsDelegates:
                    AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
              );
      },
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
          l10n.addWalletOther,
        ],
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
    // The 12-word wallet and the watched address share the Bitcoin row.
    expect(find.text(l10n.bitcoin), findsOneWidget);
  });

  testWidgets(
      'hardware: the named devices pair over Bluetooth, then Other wallet',
      (tester) async {
    final l10n = await _pump(tester, _Policy({}));
    // QR, SD-card and USB-only signers are not named; they come in
    // through Other wallet.
    for (final hidden in [
      'Keystone',
      'Foundation Passport',
      'SeedSigner',
      'Krux',
    ]) {
      expect(find.text(hidden), findsNothing, reason: hidden);
    }
    for (final id in ['ledger', 'jade']) {
      final card = find.byKey(ValueKey('add-wallet-option-$id'));
      expect(card, findsOneWidget, reason: id);
      expect(
          find.descendant(of: card, matching: find.text(l10n.bluetooth)),
          findsOneWidget,
          reason: id);
    }
    final other = find.byKey(const ValueKey('add-wallet-option-generic'));
    expect(other, findsOneWidget);
    expect(
        find.descendant(of: other, matching: find.text(l10n.addWalletOther)),
        findsOneWidget);
    expect(
        find.descendant(
            of: other, matching: find.text(l10n.addWalletOtherSubtitle)),
        findsOneWidget);
    expect(find.descendant(of: other, matching: find.text(l10n.bluetooth)),
        findsNothing);
    // After the devices, under Hardware wallets, before Bitcoin.
    final ledger = tester
        .getRect(find.byKey(const ValueKey('add-wallet-option-ledger')));
    final otherRect = tester.getRect(other);
    expect(otherRect.top, greaterThan(ledger.bottom));
    expect(otherRect.bottom,
        lessThan(tester.getTopLeft(find.text(l10n.bitcoin)).dy));
  });

  testWidgets('Other wallet opens the xpub import: QR code, file or paste',
      (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const AddWallet()),
      GoRoute(
        path: '/import-xpub',
        name: 'importXpub',
        builder: (_, __) => const XPubImportScreen(),
      ),
    ]);
    addTearDown(router.dispose);
    final l10n = await _pump(tester, _Policy({}), router: router);
    final other = find.byKey(const ValueKey('add-wallet-option-generic'));
    await tester.ensureVisible(other);
    await tester.tap(other);
    await tester.pumpAndSettle();
    expect(find.byType(XPubImportScreen), findsOneWidget);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(XPubImportScreen)));
    expect(container.read(addWalletProvider).selectedWalletConfigId,
        'generic');
    // Its ways in: scan the QR code, load the file, paste the key; no
    // Bluetooth pairing.
    for (final method in [l10n.scanQrCode, l10n.importFile, l10n.paste]) {
      expect(find.text(method), findsWidgets, reason: method);
    }
    expect(find.text(l10n.bluetooth), findsNothing);
  });

  testWidgets(
      'cards two side by side, as tall as their content; Other wallet a '
      'full-width band', (tester) async {
    final l10n = await _pump(tester, _Policy({}), wallets: [_ledger]);
    Finder option(String id) => find.byKey(ValueKey('add-wallet-option-$id'));
    Finder soon(String feature) =>
        find.byKey(ValueKey('add-wallet-soon-$feature'));
    // Pairs: each card shares its row with its neighbour, equally tall.
    final pairs = [
      [option('create_spark'), option('recover_spark')],
      [option('ledger'), option('jade')],
      [option('bitcoin'), option('track_address')],
      [soon('open_banking'), soon('exchange_import')],
      [soon('wallet_connect'), soon('nostr_wallet_connect')],
    ];
    for (final pair in pairs) {
      final a = tester.getRect(pair[0]);
      final b = tester.getRect(pair[1]);
      final reason = '${pair[0]} / ${pair[1]}';
      expect(a.top, b.top, reason: reason);
      expect(a.width, closeTo(b.width, 0.01), reason: reason);
      expect(a.height, closeTo(b.height, 0.01), reason: reason);
      expect(a.right, lessThan(b.left), reason: reason);
      // Sized to what they hold, never a 170 floor.
      expect(a.height, lessThan(170), reason: reason);
    }
    // Other wallet: the full width under Ledger and Jade, one compact
    // band, no half-width square left alone.
    final ledger = tester.getRect(option('ledger'));
    final jade = tester.getRect(option('jade'));
    final other = tester.getRect(option('generic'));
    expect(other.left, closeTo(ledger.left, 0.01));
    expect(other.right, closeTo(jade.right, 0.01));
    expect(other.top, greaterThan(ledger.bottom));
    expect(other.height, lessThan(ledger.height));
    expect(
        find.descendant(
            of: option('generic'),
            matching: find.byIcon(Icons.chevron_right_rounded)),
        findsOneWidget);
    // Coming soon cards carry the pill.
    expect(find.text(l10n.walletsSoon.toUpperCase()), findsNWidgets(4));
  });

  test('the catalog keeps every vendor; Add wallet offers the Bluetooth ones',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final state = container.read(addWalletProvider);
    // Wallets already added from a QR or file signer still find their
    // signing methods here.
    expect(state.coldWallets.map((c) => c.id),
        containsAll(['keystone', 'passport', 'seedsigner', 'krux', 'generic']));
    expect(state.bluetoothWallets.map((c) => c.id), ['ledger', 'jade']);
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
        expect(kuteBarPrimaryWithText(l10n.gotIt), findsOneWidget,
            reason: title);
        expect(find.byType(BitcoinWalletSetup), findsNothing, reason: title);
        await tester.tap(kuteBarPrimary);
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
