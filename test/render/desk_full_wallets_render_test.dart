// The wallet pages and the referral pages across the window (round three;
// founder, 25 November 2026: "lots of screens are vertical only. It must
// be all occupying full screen when we can"): Wallets, Add wallet and its
// Bitcoin chooser, the two imports, the hardware signing page, the
// Referral program and the share-code step. Checked for stretch at every
// EXPANDED size; shot when asked: DESK_FULL_RENDER=<dir> (DESK_FULL_SUFFIX
// names a set, e.g. `_before`).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/models/settings_model.dart' as settings_model;
import 'package:kute/models/settings_model.dart' hide Settings;
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:money2/money2.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/creation/add_wallet.dart';
import 'package:kute/screens/shared/kute_motion.dart' show KutePressable;
import 'package:kute/screens/creation/bitcoin_wallet_setup.dart';
import 'package:kute/screens/creation/external_address_import_screen.dart';
import 'package:kute/screens/creation/share_code_screen.dart';
import 'package:kute/screens/creation/xpub_import_screen.dart';
import 'package:kute/screens/ledger/ledger_investing_setup_screen.dart';
import 'package:kute/screens/pay/components/watch_only_screen.dart';
import 'package:kute/screens/portfolio/wallet_detail_screen.dart';
import 'package:kute/screens/settings/affiliate_screen.dart';
import 'package:kute/screens/settings/settings.dart' as settings_screen;
import 'package:kute/screens/settings/wallets_screen.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_page_route.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/kute_motion.dart';

import '../helpers/runtime_policy_fixture.dart';
import 'desk_full_support.dart';

final String _suffix = Platform.environment['DESK_FULL_SUFFIX'] ?? '';

// Public addresses of the abandon x11 about vector. Never fund them.
const _eoa = '0x9858EfFD232B4033E47d90003D41EC34EcaEda94';
const _pm = '0x1111111111111111111111111111111111112222';

// An unsigned one-input PSBT (BIP 174's test vector), only drawn.
const _psbt =
    'cHNidP8BAHUCAAAAASaBcTce3/KF6Tet7qSze3gADAVmy7OtZGQXE8pCFxv2AAAAAAD+////'
    'AtPf9QUAAAAAGXapFNDFmQPFusKGh2DpD9UhpGZap2UgiKwA4fUFAAAAABepFDVF5uM7gyxH'
    'BQ8k0+65PJwDlIvHh7MuEwAAAQD9pQEBAAAAAAECiaPHHqtNIOA3G7ukzGmPopXJRjr6Ljl/'
    'hTPMti+VZ+UBAAAAFxYAFL4Y0VKpsBIDna89p95PUzSe7LmF/////4b4qkOnHf8USIk6Ugpy'
    'CQfFBvzJ1aVaHjDOrZ/LDDafAQAAABcWABRzHaZpXdlyBxkBeG7m2gfvsiWLXf////8CAMLr'
    'CwAAAAAZdqkU0MWZA8W6woaHYOkP1SGkZlqnZSCIrADh9QUAAAAAF6kUNUXm4zuDLEcFDyTT'
    '7rk8nAOUi8eHAkgwRQIhAOHvkfh+Tbz8a7+8sIpBGGFUP0NAI2DbiH5dZ3YUu/3dAiBVaImU'
    'tQ+V6IuA3cSFlI+yvQ2jW5n3x5U6t4PnKAm5tQEhA9CTv+oP35YW1Kpz3jOpPUVuuwOyuXXW'
    'Ao10lGyBRhAPAkgwRQIhAKu8ZadE6ZMbkcBDyAG5ETBm49lgNbu3+tc8ZezEX6ugAiB2HKsr'
    'jDCzgDb/7Cy6qbAd+V4W1y5YSKJYTNbngnRVQwEhA+ZVZM4xcSIZfZfzxUNHjZdFqnWHq/+b'
    'zKbqo6pRxbLgAAAAAAAA';

settings_model.Settings _settings(List<WalletConfig> wallets) =>
    settings_model.Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: 'Blockstream',
      reviewDone: true,
      wallets: wallets,
      activeWalletId: wallets.firstOrNull?.id,
    );

final _wallets = [
  WalletConfig(
      id: 'spending',
      name: 'Spending Wallet',
      evmDerivationVersion: EvmDerivationVersion.legacySha256),
  WalletConfig(
      id: 'ledger-1',
      name: 'My Ledger',
      sparkEnabled: false,
      isHardware: true,
      isWatchOnly: true),
  WalletConfig(
      id: 'savings', name: 'Savings', sparkEnabled: false, isWatchOnly: true),
];

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency()
      : super(CurrencyState(
            {'USD': Fixed.fromInt(1), 'BTC': Fixed.parse('0.0000105')}));
  @override
  Future<void> updateRates() async {}
}

List<Override> _overrides({List<WalletConfig>? wallets}) {
  final never = Completer<settings_model.Settings>();
  return [
    initialSettingsProvider.overrideWith((ref) => never.future),
    currencyProvider.overrideWith((_) => _Currency()),
    settingsProvider
        .overrideWith((_) => SettingsModel(_settings(wallets ?? _wallets))),
    settings_screen.biometricsAvailableProvider
        .overrideWith((ref) async => true),
    settings_screen.appVersionLabelProvider
        .overrideWith((ref) async => '2.1.2 (90)'),
    hyperliquidAddressProvider.overrideWith((ref) async => _eoa),
    polymarketDepositWalletAddressProvider
        .overrideWith((ref, walletId) async => _pm),
  ];
}

/// The program's rules as the backend publishes them (affiliate_me.go).
const Map<String, Object> _rules = {
  'referee_discount_pct': 20,
  'base_rate_pct': 5.0,
  'max_rate_pct': 25.0,
  'tiers': [
    {'activated_referees': 50, 'rate_pct': 10.0},
    {'activated_referees': 100, 'rate_pct': 20.0},
  ],
};

http.Client _backend() => MockClient((request) async {
      switch (request.url.path) {
        case '/api/v1/affiliate/me':
          return http.Response(
              jsonEncode({
                'affiliate_code': 'EKVGUY',
                'commission_rate_pct': 10,
                'referees_bound': 62,
                'referees_activated': 62,
                'accrued_usd': 12.4,
                'paid_usd': 30,
                'is_referred': false,
                'payments': [
                  {'paid_at': '2026-10-01T10:00:00Z', 'amount_usd': 18.0},
                  {'paid_at': '2026-11-01T10:00:00Z', 'amount_usd': 12.0},
                ],
                'referee_discount_pct': 20,
                'rules': _rules,
              }),
              200);
        case '/api/v1/affiliate/me/history':
          return http.Response(
              jsonEncode({
                'history': [
                  for (var i = 0; i < 30; i++)
                    {
                      'date': DateTime.utc(2026, 10, 9 + i).toIso8601String(),
                      'cumulative_usd': 42.4 * (i * i) / (29 * 29),
                    },
                ]
              }),
              200);
        case '/api/v1/affiliate/me/referees':
          return http.Response(jsonEncode({'referees': []}), 200);
        default:
          return http.Response('not found', 404);
      }
    });

/// One page of the group: its name, the page, how its route frames it.
typedef _Page = (String, Widget Function(), KuteWideMode);

final List<_Page> _pages = [
  ('wallets', () => const WalletsScreen(), KuteWideMode.full),
  ('add_wallet', () => const AddWallet(), KuteWideMode.full),
  ('bitcoin_setup', () => const BitcoinWalletSetup(), KuteWideMode.full),
  ('bitcoin_create', () => const BitcoinWalletCreate(), KuteWideMode.column),
  ('xpub_import', () => const XPubImportScreen(), KuteWideMode.full),
  (
    'address_import',
    () => const ExternalAddressImportScreen(),
    KuteWideMode.full
  ),
  (
    'watch_only_signing',
    () => const WatchOnlySigningScreen(
        psbtBase64: _psbt,
        walletType: 'ledger',
        walletId: 'ledger-1',
        recipientAddressOverride: 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq',
        recipientSatsOverride: 125000,
        feeSatsOverride: 840),
    KuteWideMode.full
  ),
  (
    'wallet_detail',
    () => const WalletDetailScreen(walletId: 'savings'),
    KuteWideMode.full
  ),
  (
    'ledger_setup',
    () => const LedgerInvestingSetupScreen(walletId: 'ledger-1'),
    KuteWideMode.column
  ),
  ('affiliate', () => const AffiliateScreen(), KuteWideMode.full),
  ('share_code', () => const ShareCodeScreen(), KuteWideMode.full),
];

/// The pages Settings shows as its detail.
final List<_Page> _details = [
  ('wallets', () => const WalletsScreen(), KuteWideMode.full),
  ('affiliate', () => const AffiliateScreen(), KuteWideMode.full),
];

RuntimeCapabilitiesService? _live;

Future<void> _up(WidgetTester tester) async {
  final policy = _live = runtimePolicyFixture(also: {
    'affiliate.program',
    'export.transactions',
    'settings.advanced',
    'hardware.wallet',
    'wallet.savings',
    'wallet.tracked',
    'ledger.hyperliquid',
    'ledger.polymarket',
  });
  RuntimeCapabilitiesService.debugInstance = policy;
  await tester.runAsync(policy.refresh);
}

Future<void> _pump(WidgetTester tester,
    {required Size size,
    required bool dark,
    required Widget page,
    required KuteWideMode mode}) async {
  await http.runWithClient(() async {
    await pumpDeskPage(tester,
        size: size,
        dark: dark,
        page: page,
        mode: mode,
        overrides: _overrides(),
        frames: 2);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await deskFullFrames(tester, 12);
  }, _backend);
}

Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  _live?.dispose();
  _live = null;
  await deskFullEnd(tester);
  // The wallet page's live price feed closes 30 s after its last reader.
  await tester.pump(const Duration(seconds: 40));
}

/// A page as app_router.dart builds it (`_buildFadeScalePage`): a Settings
/// detail ([masterDetail]) under the one detail key, its motion played by
/// the [KuteMasterDetail].
CustomTransitionPage<void> _routerPage(GoRouterState state, Widget child,
        {bool masterDetail = false}) =>
    CustomTransitionPage<void>(
      key: masterDetail ? kuteSettingsDetailPageKey : state.pageKey,
      child: KutePageFrame(mode: KuteWideMode.full, child: child),
      transitionDuration: KuteMotion.settleDuration,
      reverseTransitionDuration: KuteMotion.settleDuration,
      transitionsBuilder: (context, animation, _, child) =>
          kutePageTransition(context, animation, child,
              masterDetail: masterDetail),
    );

CustomTransitionPage<void> _detailPage(
        GoRouterState state, Widget page, String selected) =>
    _routerPage(
      state,
      state.extra == kuteSettingsDetailExtra
          ? KuteMasterDetail(
              master: const settings_screen.Settings(),
              detail: page,
              selected: selected)
          : page,
      masterDetail: state.extra == kuteSettingsDetailExtra,
    );

/// Settings over a root page, its two details routed as the app routes
/// them, at [size].
Future<GoRouter> _pumpSettingsFlow(WidgetTester tester,
    {required Size size, required bool dark}) async {
  final router = GoRouter(initialLocation: '/settings', routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const Scaffold(body: SizedBox.expand()),
      routes: [
        GoRoute(
          path: 'settings',
          pageBuilder: (context, state) =>
              _routerPage(state, const settings_screen.Settings()),
        ),
      ],
    ),
    GoRoute(
      path: '/wallets',
      name: 'wallets',
      pageBuilder: (context, state) =>
          _detailPage(state, const WalletsScreen(), 'wallets'),
    ),
    GoRoute(
      path: '/affiliate',
      pageBuilder: (context, state) =>
          _detailPage(state, const AffiliateScreen(), 'affiliate'),
    ),
  ]);
  addTearDown(router.dispose);
  await http.runWithClient(() async {
    await pumpDeskRouter(tester,
        size: size,
        dark: dark,
        router: router,
        overrides: _overrides(),
        frames: 2);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await deskFullFrames(tester, 8);
  }, _backend);
  return router;
}

/// Lets a page's loads land (the referral program's backend calls).
Future<void> _settle(WidgetTester tester) => http.runWithClient(() async {
      await deskFullFrames(tester, 2);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)));
      await deskFullFrames(tester, 8);
    }, _backend);

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    FlutterSecureStorage.setMockInitialValues({});
    dotenv.loadFromString(
        envString: 'BACKEND=https://backend.test\n'
            'APPSFLYER_ONELINK_TEMPLATE=kute.onelink.me/aBcD');
    AffiliateService.debugSessionToken = 'render-session';
    AffiliateService.debugAffiliateCode = 'EKVGUY';
    AffiliateService.debugCommissionTopRatePct = 25;
    TrackingService.setDisabled(true);
  });
  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
    AffiliateService.debugAffiliateCode = null;
  });

  for (final (name, build, mode) in _pages) {
    for (final (label, size) in deskFullExpanded) {
      testWidgets('$name at $label: nothing stretched', (tester) async {
        await _up(tester);
        await _pump(tester, size: size, dark: false, page: build(), mode: mode);
        expect(tester.takeException(), isNull);
        expectDeskNothingStretched(tester,
            maxCard: kuteWideColumnMax + 1,
            // Add wallet's Other Wallet row spans its section's two
            // square cards exactly (a grid row, not a stretched card).
            allow: [
              if (name == 'add_wallet')
                find.ancestor(
                    of: find.text('Other Wallet'),
                    matching: find.byType(KutePressable)),
            ]);
        await _end(tester);
      });
    }
  }
  for (final (name, build, mode) in _details) {
    for (final (label, size) in deskFullExpanded) {
      testWidgets('$name beside Settings at $label: nothing stretched',
          (tester) async {
        await _up(tester);
        await _pump(tester,
            size: size,
            dark: false,
            page: KuteMasterDetail(
                master: const settings_screen.Settings(), detail: build()),
            mode: mode);
        expect(tester.takeException(), isNull);
        // The detail is the window less the Settings column: from about
        // 1300 wide it is EXPANDED and lays itself out; narrower it is a
        // MEDIUM detail, the page's phone column (as asked).
        if (kuteMasterDetailLayout(size.width).detailWidth >= 900) {
          expectDeskNothingStretched(tester, maxCard: kuteWideColumnMax + 1);
        }
        await _end(tester);
      });
    }
  }

  for (final (name, build, mode) in _pages) {
    final narrow = const {'wallets', 'add_wallet', 'affiliate', 'xpub_import'}
        .contains(name);
    for (final (label, size) in [
      ...deskFullExpanded,
      if (narrow) ...deskFullNarrow,
    ]) {
      for (final dark in [false, true]) {
        final tone = dark ? 'dark' : 'light';
        testWidgets('render: $name $label $tone', skip: deskFullDir == null,
            (tester) async {
          await deskFullAssets(tester, clips: const [
            'idle',
            'body_idle',
            'blink',
            'happy',
            'share',
            'body_wag'
          ]);
          await _up(tester);
          await _pump(tester,
              size: size, dark: dark, page: build(), mode: mode);
          await deskFullShoot(tester, '${name}_${label}_$tone$_suffix');
          await _end(tester);
        });
      }
    }
  }
  for (final (name, build, mode) in _details) {
    for (final (label, size) in [
      ('1440x900', const Size(1440, 900)),
      ('1920x1080', const Size(1920, 1080)),
    ]) {
      for (final dark in [false, true]) {
        final tone = dark ? 'dark' : 'light';
        testWidgets('render: $name detail $label $tone',
            skip: deskFullDir == null, (tester) async {
          await deskFullAssets(tester,
              clips: const ['idle', 'body_idle', 'blink', 'share', 'body_wag']);
          await _up(tester);
          await _pump(tester,
              size: size,
              dark: dark,
              page: KuteMasterDetail(
                  master: const settings_screen.Settings(), detail: build()),
              mode: mode);
          await deskFullShoot(tester, '${name}_detail_${label}_$tone$_suffix');
          await _end(tester);
        });
      }
    }
  }
  // The split itself: Settings opening Backup and recovery beside it
  // (the full page settling into the master column, the detail sliding
  // in), the referral program swapped in from the master (the detail
  // cross-fading, the master still), and back.
  for (final (label, size) in [
    ('1440x900', const Size(1440, 900)),
    ('1920x1080', const Size(1920, 1080)),
    ('1300x800', const Size(1300, 800)),
  ]) {
    testWidgets('settings split at $label: the master on the page gutter, '
        'the detail swapped in place, back to the full page',
        (tester) async {
      await deskFullAssets(tester);
      await _up(tester);
      await http.runWithClient(() async {
        await _pumpSettingsFlow(tester, size: size, dark: false);
        final layout = kuteMasterDetailLayout(size.width);
        final fullBack = tester.getRect(find.byType(KuteBackButton).last);
        final fullTitle = tester.getRect(find.text('Settings').last);
        await tester.tap(find.byKey(const ValueKey('settings-card-backup')));
        await deskFullFrames(tester, 6);
        expect(tester.takeException(), isNull);
        // The master's back button and title where the full page's were.
        final masterTitle = tester.getRect(find.text('Settings').last);
        expect(masterTitle.left, closeTo(fullTitle.left, 0.5));
        expect(masterTitle.top, closeTo(fullTitle.top, 0.5));
        final backs = find.byType(KuteBackButton).evaluate().toList();
        expect(
            tester.getRect(find.byWidget(backs[backs.length - 2].widget)).left,
            closeTo(fullBack.left, 0.5));
        // The four cards are rows of the master's list, Backup marked.
        final row = tester.getRect(
            find.byKey(const ValueKey('settings-master-backup')));
        expect(row.left, closeTo(layout.gutter, 0.5));
        expect(row.width, closeTo(kuteMasterWidth, 0.5));
        expect(find.text('Investing and Predictions'), findsWidgets);
        // Referral from the master: the same route, the detail swapped.
        await tester
            .tap(find.byKey(const ValueKey('settings-master-referral')));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(AffiliateScreen), findsOneWidget);
        expect(find.byType(WalletsScreen), findsNothing);
        expect(
            tester
                .getRect(find.byKey(const ValueKey('settings-master-backup')))
                .top,
            closeTo(row.top, 0.5));
        // The detail's back: the full page again.
        await tester.tap(find.byType(KuteBackButton).last);
        await deskFullFrames(tester, 6);
        expect(find.byType(KuteMasterDetail), findsNothing);
        expect(find.byKey(const ValueKey('settings-card-backup')),
            findsOneWidget);
      }, _backend);
      await _end(tester);
    });
  }

  for (final (label, size) in [
    ('1440x900', const Size(1440, 900)),
    ('1920x1080', const Size(1920, 1080)),
    ('1300x800', const Size(1300, 800)),
  ]) {
    for (final dark in [false, true]) {
      final tone = dark ? 'dark' : 'light';
      testWidgets('render: settings split $label $tone',
          skip: deskFullDir == null, (tester) async {
        await deskFullAssets(tester,
            clips: const ['idle', 'body_idle', 'blink', 'share', 'body_wag']);
        await _up(tester);
        await http.runWithClient(() async {
          await _pumpSettingsFlow(tester, size: size, dark: dark);
          await deskFullShoot(tester, 'split_${label}_${tone}_0_full');
          await tester
              .tap(find.byKey(const ValueKey('settings-card-backup')));
          // Through the open: the route's 300 ms at four points (the
          // first frame starts it).
          await tester.pump();
          var at = 0;
          for (final ms in [40, 80, 120, 200]) {
            await tester.pump(Duration(milliseconds: ms - at));
            at = ms;
            await deskFullShoot(tester, 'split_${label}_${tone}_1_open_$ms');
          }
          await deskFullFrames(tester, 6);
          await deskFullShoot(tester, 'split_${label}_${tone}_2_wallets');
          await tester
              .tap(find.byKey(const ValueKey('settings-master-referral')));
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          await deskFullShoot(tester, 'split_${label}_${tone}_3_swap_mid');
          await _settle(tester);
          await deskFullShoot(tester, 'split_${label}_${tone}_4_referral');
          await tester.tap(find.byType(KuteBackButton).last);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 60));
          await deskFullShoot(tester, 'split_${label}_${tone}_5_back_60');
          await tester.pump(const Duration(milliseconds: 80));
          await deskFullShoot(tester, 'split_${label}_${tone}_5_back_140');
          await deskFullFrames(tester, 6);
          await deskFullShoot(tester, 'split_${label}_${tone}_6_full_again');
        }, _backend);
        await _end(tester);
      });
    }
  }
}
