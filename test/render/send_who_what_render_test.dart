// A look by eye at the approved Send (founder, 7 November 2026: "ok do it,
// just make sure that people realise they can send to different cryptos
// also"): the Who step empty, Another crypto under the field; the Who
// step after a 0x address is pasted, the network asked in the "Where to?"
// sheet filtered to it; the What step over a contact; and the Dollars
// Send's Who step and What step (the From toggle on Dollars). Light and
// dark, on a 375 pt phone. Every frame lays out without an overflow; the PNGs are
// written only when asked:
//
//   SEND_WHO_RENDER=<dir> flutter test test/render/send_who_what_render_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' show Contact;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_contacts_provider.dart';
import 'package:kute/screens/pay/components/confirm_send.dart';
import 'package:kute/screens/shared/sal_sprite.dart' show SalSpriteCache;
import 'package:kute/screens/shared/send/send_sheet.dart';
import 'package:kute/screens/shared/send/send_what_step.dart'
    show SendWhatSheet;
import 'package:kute/screens/usd/usd_withdraw_screen.dart'
    show showUsdWithdrawSheet;
import 'package:kute/services/api/share_links_api.dart';
import 'package:kute/services/contacts/send_contacts_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/share_links_store.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/kute_bar_test_support.dart';
import '../helpers/runtime_policy_fixture.dart';
import '../helpers/spark_contacts_fixtures.dart';
import '../mocks/fake_send_contacts_gateway.dart';
import '../mocks/fake_share_links_api.dart';
import '../screens/share/cards/share_card_test_fonts.dart';

final _dir = Platform.environment['SEND_WHO_RENDER'];

Map<String, dynamic> _row(String chain, String asset, {int decimals = 6}) => {
      'id': '$chain:$asset',
      'chain': chain,
      'asset': asset,
      'decimals': decimals,
      'route': {'to': 'all', 'fixedTo': [], 'exactOutTo': []},
    };

/// A live catalogue as wide as the real one: USDC, USDT and ETH on several
/// networks, and a long tail of coins on one.
OrchestraRoutesCatalog _catalog() => OrchestraRoutesCatalog.fromJson(
      {
        'assets': [
          _row('spark', 'BTC', decimals: 8),
          _row('spark', 'USDB'),
          for (final chain in [
            'arbitrum',
            'base',
            'ethereum',
            'optimism',
            'polygon',
            'solana'
          ])
            _row(chain, 'USDC'),
          for (final chain in ['tron', 'ethereum', 'bsc', 'arbitrum'])
            _row(chain, 'USDT'),
          for (final chain in ['ethereum', 'base', 'arbitrum'])
            _row(chain, 'ETH', decimals: 18),
          _row('solana', 'SOL', decimals: 9),
          _row('bsc', 'BNB', decimals: 18),
          _row('polygon', 'POL', decimals: 18),
          _row('tron', 'TRX'),
          _row('litecoin', 'LTC', decimals: 8),
          _row('zcash', 'ZEC', decimals: 8),
          _row('ethereum', 'DAI', decimals: 18),
          _row('ethereum', 'LINK', decimals: 18),
          _row('ethereum', 'UNI', decimals: 18),
          _row('ethereum', 'AAVE', decimals: 18),
          _row('arbitrum', 'ARB', decimals: 18),
          _row('optimism', 'OP', decimals: 18),
          _row('ethereum', 'PEPE', decimals: 18),
          _row('ethereum', 'SHIB', decimals: 18),
          _row('avalanche', 'AVAX', decimals: 18),
          _row('ethereum', 'WBTC', decimals: 8),
          _row('ethereum', 'MKR', decimals: 18),
          _row('ethereum', 'LDO', decimals: 18),
        ],
      },
      source: OrchestraCatalogSource.live,
      fetchedAt: DateTime(2026, 11, 7),
    );

class _Routes extends OrchestraSupportedRoutesNotifier {
  _Routes(OrchestraRoutesCatalog catalog) {
    state = catalog;
  }

  @override
  Future<void> init() async {}

  @override
  Future<bool> refresh() async => false;
}

class _Paid extends SparkContactsNotifier {
  @override
  Future<List<Contact>> build() async => [
        contact('rita@paykute.com', 300),
        contact('alice@getalby.com', 200),
      ];
}

Settings _settings() => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: 'Blockstream',
      reviewDone: true,
      activeWalletId: 'spending',
      wallets: [WalletConfig(id: 'spending', name: 'Spending')],
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final error = tester.takeException();
  expect(error, isNull, reason: '$name overflowed: $error');
  final dir = _dir;
  if (dir == null) return;
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image =
        await layer.toImage(Offset.zero & view.size, pixelRatio: 3);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(dir).createSync(recursive: true);
    File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('send_who_render');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SalSpriteCache.debugSetManifest(null);
    ShareLinksStore.debugMemory = <String, String>{};
    WidgetsApp.debugAllowBannerOverride = false;
  });

  tearDown(() {
    SalSpriteCache.debugReset();
    ShareLinksStore.debugMemory = null;
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
    WidgetsApp.debugAllowBannerOverride = true;
  });

  Future<void> pumpSend(WidgetTester tester, {required bool dark}) async {
    await tester.runAsync(loadShareCardFonts);
    AffiliateService.debugSessionToken = 'test-session';
    final policy = runtimePolicyFixture(
        also: const {'polymarket.browse', 'hyperliquid.browse'});
    RuntimeCapabilitiesService.debugInstance = policy;
    await tester.runAsync(policy.refresh);
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => context.pushNamed('pay_send'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/send',
        name: 'pay_send',
        pageBuilder: (context, state) => SendSheetPage<void>(
          key: state.pageKey,
          name: state.name,
          child: const ConfirmSend(),
        ),
      ),
    ]);
    addTearDown(router.dispose);
    final base = dark ? buildDarkTheme() : buildLightTheme();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((_) => SettingsModel(_settings())),
        sendContactsGatewayProvider.overrideWithValue(FakeSendContactsGateway(
            permission: SendContactsPermission.granted,
            contacts: fakeContacts())),
        shareLinksApiProvider.overrideWithValue(FakeShareLinksApi()),
        sparkContactsProvider.overrideWith(_Paid.new),
        orchestraSupportedRoutesProvider
            .overrideWith((_) => _Routes(_catalog())),
        orchestraRoutesReadyProvider.overrideWith((_) async {}),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp.router(
          builder: withKuteShellBar,
          routerConfig: router,
          theme: base.copyWith(
              textTheme: base.textTheme.apply(fontFamily: 'Inter')),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    ));
    await _settle(tester);
    await tester.tap(find.text('open'));
    await _settle(tester);
  }

  Future<void> pumpDollars(WidgetTester tester, {required bool dark}) async {
    await tester.runAsync(loadShareCardFonts);
    AffiliateService.debugSessionToken = 'test-session';
    final policy = runtimePolicyFixture(
        also: const {'polymarket.browse', 'hyperliquid.browse'});
    RuntimeCapabilitiesService.debugInstance = policy;
    await tester.runAsync(policy.refresh);
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final base = dark ? buildDarkTheme() : buildLightTheme();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((_) => SettingsModel(_settings())),
        sendContactsGatewayProvider.overrideWithValue(FakeSendContactsGateway(
            permission: SendContactsPermission.granted,
            contacts: fakeContacts())),
        orchestraSupportedRoutesProvider
            .overrideWith((_) => _Routes(_catalog())),
        orchestraRoutesReadyProvider.overrideWith((_) async {}),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          builder: withKuteShellBar,
          theme: base.copyWith(
              textTheme: base.textTheme.apply(fontFamily: 'Inter')),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showUsdWithdrawSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await _settle(tester);
    await tester.tap(find.text('open'));
    await _settle(tester);
  }

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';

    testWidgets('render: usd-send-who-empty-$theme', (tester) async {
      await pumpDollars(tester, dark: dark);
      expect(find.byKey(const ValueKey('send-another-crypto')), findsOneWidget);
      await _capture(tester, 'usd-send-who-empty-$theme');
    });

    testWidgets('render: usd-send-what-$theme', (tester) async {
      await pumpDollars(tester, dark: dark);
      await tester.tap(find.byKey(const ValueKey('send-person-contact:c2')));
      await _settle(tester);
      expect(find.byType(SendWhatSheet), findsOneWidget);
      await _capture(tester, 'usd-send-what-$theme');
    });

    testWidgets('render: send-who-empty-$theme', (tester) async {
      await pumpSend(tester, dark: dark);
      expect(find.byKey(const ValueKey('send-another-crypto')), findsOneWidget);
      await _capture(tester, 'send-who-empty-$theme');
    });

    testWidgets('render: send-who-pasted-0x-$theme', (tester) async {
      await pumpSend(tester, dark: dark);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          return {'text': '0x742d35cc6634c0532925a3b844bc454e4438f44e'};
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.tap(find.byKey(const ValueKey('send-field-paste')));
      await _settle(tester);
      await _capture(tester, 'send-who-pasted-0x-sheet-$theme');
      // Closed, the question stays under the field.
      Navigator.of(tester.element(find.text('Where to?'))).pop();
      await _settle(tester);
      await _capture(tester, 'send-who-pasted-0x-$theme');
    });

    testWidgets('render: send-what-$theme', (tester) async {
      await pumpSend(tester, dark: dark);
      final maria =
          find.byKey(const ValueKey('send-person-contact:c2'), skipOffstage: false);
      await tester.ensureVisible(maria);
      await _settle(tester);
      await tester.tap(maria);
      await _settle(tester);
      expect(find.byType(SendWhatSheet), findsOneWidget);
      await _capture(tester, 'send-what-$theme');
    });
  }
}
