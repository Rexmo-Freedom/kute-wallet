// Ledger Predictions and Ledger Investing answer to the runtime
// capabilities `ledger.polymarket` / `ledger.hyperliquid` alone (founder
// decision, October 2026: no build switch). Denied, or with no readable
// policy, a venue is absent on a Ledger (no tab, no logo, no wallet-row
// mark, no Add Wallet badge, no "Invest with your Ledger" step after
// connecting), never disabled. Allowed, the tabs and the setup step come
// back.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/shell_wallet_provider.dart';
import 'package:kute/screens/home/components/action_pill.dart';
import 'package:kute/screens/home/shell_venue_tabs.dart';
import 'package:kute/screens/hyperliquid/hyperliquid_screen.dart';
import 'package:kute/screens/ledger/ledger_hyperliquid_tab.dart';
import 'package:kute/screens/ledger/ledger_polymarket_tab.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart';
import 'package:kute/screens/ledger/ledger_account_body.dart';
import 'package:kute/screens/ledger/ledger_investing_setup_screen.dart';
import 'package:kute/screens/ledger/ledger_investment_gate.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

class _Policy extends Fake implements RuntimeCapabilitiesService {
  _Policy(this.allowed);

  /// The capability ids this policy allows; every other id is denied.
  final Set<String> allowed;

  @override
  CapabilityDecision decision(String id) =>
      CapabilityDecision(allowed: allowed.contains(id));
  @override
  bool allows(String id) => allowed.contains(id);
}

final _allVenues = _Policy({
  ledgerPredictionsCapability,
  ledgerInvestingCapability,
  'polymarket.trade',
  'hyperliquid.trade',
});

final _ledger = WalletConfig(
  id: 'ledger-1',
  name: 'Ledger',
  sparkEnabled: false,
  isHardware: true,
  isWatchOnly: true,
  walletType: 'ledger',
);
final _spending = WalletConfig(id: 'spending', name: 'Spending');

/// Every Ledger venue surface's answer for [policy].
({
  bool investingTab,
  bool predictionsTab,
  bool investingAccountTab,
  bool predictionsAccountTab,
  String? setupAfterImport,
}) _surfaces(RuntimeCapabilitiesService policy) {
  RuntimeCapabilitiesService.debugInstance = policy;
  return (
    investingTab: shellShowsTradingTab(_ledger),
    predictionsTab: shellShowsPredictionsTab(_ledger),
    investingAccountTab: ledgerAccountTabOffered(LedgerAccountTab.investing),
    predictionsAccountTab:
        ledgerAccountTabOffered(LedgerAccountTab.predictions),
    setupAfterImport: ledgerVenueSetupAfterImport(
        importedWalletId: _ledger.id, importedWalletType: 'ledger'),
  );
}

Future<void> _pumpSetupStep(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/setup',
    routes: [
      GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('home'))),
      GoRoute(
          path: '/setup',
          builder: (_, __) => LedgerInvestingSetupScreen(
              walletId: _ledger.id, fromImport: true)),
    ],
  );
  addTearDown(router.dispose);
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
            reviewDone: false,
            activeWalletId: 'spending',
            wallets: [_spending, _ledger],
          ))),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp.router(
        routerConfig: router,
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Settings _settings(List<WalletConfig> wallets, String? activeWalletId) =>
    Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: 'Blockstream',
      reviewDone: false,
      activeWalletId: activeWalletId,
      wallets: wallets,
    );

/// The shell's top strip plus both venue tab bodies, as the shell mounts
/// them, for [wallets] with [shellWalletId] picked in the wallets menu and
/// [activeWalletId] active.
Future<AppLocalizations> _pumpShell(
  WidgetTester tester, {
  required RuntimeCapabilitiesService policy,
  required List<WalletConfig> wallets,
  String? activeWalletId,
  String? shellWalletId,
  bool bodies = true,
}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  RuntimeCapabilitiesService.debugInstance = policy;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      runtimeCapabilitiesProvider.overrideWithValue(policy),
      settingsProvider.overrideWith(
          (_) => SettingsModel(_settings(wallets, activeWalletId))),
      shellWalletIdProvider.overrideWith((_) => shellWalletId),
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
          body: Column(children: [
            const FloatingActionPill(),
            if (bodies) ...const [
              SizedBox(height: 200, child: ShellTradingTab()),
              SizedBox(height: 200, child: ShellPredictionsTab()),
            ],
          ]),
        ),
      ),
    ),
  ));
  await tester.pump();
  return AppLocalizations.of(tester.element(find.byType(FloatingActionPill)));
}

Finder _venueLogo(String name) => find.byWidgetPredicate((w) =>
    w is SvgPicture &&
    w.bytesLoader is SvgAssetLoader &&
    (w.bytesLoader as SvgAssetLoader).assetName.contains(name));

/// No Hyperliquid or Polymarket element of any kind: logo, tab, or venue
/// screen (the spending account's or the Ledger's).
void _expectNoVenues(AppLocalizations l10n) {
  expect(_venueLogo('hyperliquid'), findsNothing);
  expect(_venueLogo('polymarket'), findsNothing);
  expect(find.bySemanticsLabel(l10n.trading), findsNothing);
  expect(find.bySemanticsLabel(l10n.predictions), findsNothing);
  expect(find.text(l10n.trading), findsNothing);
  expect(find.text(l10n.predictions), findsNothing);
  for (final screen in [
    HyperliquidScreen,
    PolymarketScreen,
    LedgerHyperliquidTab,
    LedgerPolymarketTab,
  ]) {
    expect(find.byType(screen), findsNothing, reason: '$screen');
  }
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
  });

  test('capability denied: no Ledger venue anywhere', () {
    final s = _surfaces(_Policy(const {'polymarket.trade', 'hyperliquid.trade'}));
    expect(s.investingTab, isFalse);
    expect(s.predictionsTab, isFalse);
    expect(s.investingAccountTab, isFalse);
    expect(s.predictionsAccountTab, isFalse);
    RuntimeCapabilitiesService.debugInstance =
        _Policy(const {'polymarket.trade', 'hyperliquid.trade'});
    expect(ledgerAnyVenueAllowed(), isFalse);
    // Connecting a Ledger goes straight to Home, no setup step.
    expect(s.setupAfterImport, isNull);
    // The spending account keeps its venues; Bitcoin stays on a Ledger.
    expect(shellShowsTradingTab(_spending), isTrue);
    expect(shellShowsPredictionsTab(_spending), isTrue);
    expect(ledgerAccountTabOffered(LedgerAccountTab.bitcoin), isTrue);
  });

  test('no readable policy: hidden', () {
    final s = _surfaces(RuntimeCapabilitiesService.instance);
    expect(s.investingTab, isFalse);
    expect(s.predictionsTab, isFalse);
    expect(s.investingAccountTab, isFalse);
    expect(s.predictionsAccountTab, isFalse);
    expect(s.setupAfterImport, isNull);
  });

  test('capability allowed: tabs and the setup step appear', () {
    final s = _surfaces(_allVenues);
    expect(s.investingTab, isTrue);
    expect(s.predictionsTab, isTrue);
    expect(s.investingAccountTab, isTrue);
    expect(s.predictionsAccountTab, isTrue);
    expect(s.setupAfterImport, _ledger.id);

    // Each venue follows its own capability.
    final onlyPredictions = _surfaces(_Policy({ledgerPredictionsCapability}));
    expect(onlyPredictions.predictionsTab, isTrue);
    expect(onlyPredictions.investingTab, isFalse);
    expect(onlyPredictions.setupAfterImport, _ledger.id);
  });

  test('a Ledger Home is showing owns the strip, not the spending account',
      () {
    ProviderContainer container(
        List<WalletConfig> wallets, String? active, String? shell) {
      final c = ProviderContainer(overrides: [
        settingsProvider.overrideWith(
            (_) => SettingsModel(_settings(wallets, active))),
        shellWalletIdProvider.overrideWith((_) => shell),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    String? owner(ProviderContainer c) =>
        c.read(shellVenueOwnerProvider)?.id;
    // The spending account on Home.
    expect(owner(container([_spending, _ledger], 'spending', null)), isNull);
    // The Ledger picked in the wallets menu.
    expect(owner(container([_spending, _ledger], 'spending', 'ledger-1')),
        _ledger.id);
    // No wallet picked, but Home is showing the Ledger.
    expect(owner(container([_spending, _ledger], 'ledger-1', null)),
        _ledger.id);
    // A Ledger-only install: no active wallet, no spending account.
    expect(owner(container([_ledger], null, null)), _ledger.id);
  });

  final offPolicies = <String, RuntimeCapabilitiesService Function()>{
    'denied': () => _Policy(const {'polymarket.trade', 'hyperliquid.trade'}),
    'unavailable': () => RuntimeCapabilitiesService.instance,
  };
  final ledgerScreens = <String,
      ({List<WalletConfig> wallets, String? active, String? shell})>{
    'picked in the wallets menu': (
      wallets: [_spending, _ledger],
      active: 'spending',
      shell: 'ledger-1'
    ),
    'active on Home': (
      wallets: [_spending, _ledger],
      active: 'ledger-1',
      shell: null
    ),
    'the only wallet': (wallets: [_ledger], active: null, shell: null),
  };
  for (final policy in offPolicies.entries) {
    for (final screen in ledgerScreens.entries) {
      testWidgets(
          'Ledger ${screen.key}, venues ${policy.key}: '
          'no Hyperliquid or Polymarket element anywhere', (tester) async {
        final l10n = await _pumpShell(tester,
            policy: policy.value(),
            wallets: screen.value.wallets,
            activeWalletId: screen.value.active,
            shellWalletId: screen.value.shell);
        _expectNoVenues(l10n);
        // A Ledger has no dollars of its own either.
        expect(find.bySemanticsLabel(l10n.usdAccountTab), findsNothing);
      });
    }
  }

  testWidgets('Ledger venues allowed: both tabs are drawn for the Ledger',
      (tester) async {
    final l10n = await _pumpShell(tester,
        policy: _allVenues,
        wallets: [_spending, _ledger],
        activeWalletId: 'spending',
        shellWalletId: 'ledger-1',
        bodies: false);
    expect(_venueLogo('hyperliquid'), findsOneWidget);
    expect(_venueLogo('polymarket'), findsOneWidget);
    expect(find.bySemanticsLabel(l10n.usdAccountTab), findsNothing);
  });

  testWidgets('venues off: "Invest with your Ledger" is never shown',
      (tester) async {
    RuntimeCapabilitiesService.debugInstance =
        _Policy(const {'polymarket.trade', 'hyperliquid.trade'});
    await _pumpSetupStep(tester);
    expect(find.text('Invest with your Ledger'), findsNothing);
    expect(find.text('Turn on investing'), findsNothing);
    expect(find.text('Keep Bitcoin only'), findsNothing);
    // It leaves as if "Keep Bitcoin only" had been tapped.
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('venues on: the setup step asks as before', (tester) async {
    RuntimeCapabilitiesService.debugInstance = _allVenues;
    await _pumpSetupStep(tester);
    expect(find.text('Invest with your Ledger'), findsOneWidget);
    expect(find.text('Keep Bitcoin only'), findsOneWidget);
  });
}
