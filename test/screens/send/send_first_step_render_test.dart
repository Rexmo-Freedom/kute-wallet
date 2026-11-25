// Frames of the recipient-first send steps for a look by eye (founder, 31
// October 2026): the bitcoin Send to step, the dollar send's coin step
// and its address step, light and dark, 390 wide at 3x. Written only when
// asked: SEND_FRAMES=<dir> flutter test test/screens/send.
//
// Nothing here reaches a money call: every frame is the first step.

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
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/spark_contacts_provider.dart';
import 'package:kute/screens/pay/components/confirm_send.dart';
import 'package:kute/screens/shared/send/send_sheet.dart';
import 'package:kute/screens/usd/usd_send_screen.dart';
import 'package:kute/services/api/share_links_api.dart';
import 'package:kute/services/contacts/send_contacts_service.dart';
import 'package:kute/services/orchestra_usd_send_routes.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/kute_bar_test_support.dart';
import '../../helpers/runtime_policy_fixture.dart';
import '../../helpers/spark_contacts_fixtures.dart';
import '../../mocks/fake_send_contacts_gateway.dart';
import '../../mocks/fake_share_links_api.dart';

const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';

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

Map<String, dynamic> _row(String chain, String asset, {int decimals = 6}) => {
      'id': '$chain:$asset',
      'chain': chain,
      'asset': asset,
      'decimals': decimals,
      'route': {'to': 'all', 'fixedTo': [], 'exactOutTo': []},
    };

OrchestraRoutesCatalog _catalog() => OrchestraRoutesCatalog.fromJson(
      {
        'assets': [
          _row('spark', 'BTC', decimals: 8),
          _row('spark', 'USDB'),
          _row('arbitrum', 'USDC'),
          _row('arbitrum', 'USDT'),
          _row('base', 'USDC'),
          _row('ethereum', 'USDC'),
          _row('ethereum', 'ETH', decimals: 18),
          _row('tron', 'USDT'),
          _row('solana', 'USDC'),
          _row('polygon', 'USDC'),
        ],
      },
      source: OrchestraCatalogSource.live,
      fetchedAt: DateTime(2026, 10, 31),
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

/// Three Lightning addresses this wallet paid.
class _Contacts extends SparkContactsNotifier {
  @override
  Future<List<Contact>> build() async => [
        contact('alice@getalby.com', 300),
        contact('bob@walletofsatoshi.com', 200),
        contact('erin@kute.money', 100),
      ];
}


ThemeData _themed(bool dark) {
  final base = dark ? buildDarkTheme() : buildLightTheme();
  return base.copyWith(
    splashFactory: NoSplash.splashFactory,
    textTheme: base.textTheme.apply(fontFamily: 'Inter'),
  );
}

List<Override> _overrides() => [
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      orchestraSupportedRoutesProvider.overrideWith((_) => _Routes(_catalog())),
      orchestraRoutesReadyProvider.overrideWith((_) async {}),
      sparkSelfAddressProvider.overrideWith((_) async => _ownSpark),
      sparkContactsProvider.overrideWith(_Contacts.new),
      sendContactsGatewayProvider.overrideWithValue(FakeSendContactsGateway(
          permission: SendContactsPermission.granted,
          contacts: fakeContacts())),
      shareLinksApiProvider.overrideWithValue(FakeShareLinksApi()),
      usdSendRouteLimitsProvider.overrideWithValue((_) async => null),
    ];

void main() {
  final framesDir = Platform.environment['SEND_FRAMES'];
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('send_frames');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    TrackingService.setDisabled(true);
    AffiliateService.debugSessionToken = 'test-session';
    final policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  });

  testWidgets('send first-step frames', skip: framesDir == null,
      (tester) async {
    await tester.runAsync(() async {
      final inter = FontLoader('Inter')
        ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'))
        ..addFont(rootBundle.load('lib/assets/fonts/Inter-SemiBold.ttf'))
        ..addFont(rootBundle.load('lib/assets/fonts/Inter-Bold.ttf'));
      await inter.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.getData':
          return null;
        case 'Clipboard.hasStrings':
          return {'value': false};
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    Directory(framesDir!).createSync(recursive: true);

    Future<void> shot(GlobalKey key, String name) => tester.runAsync(() async {
          final boundary = key.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 3);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$framesDir/$name.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
        });

    /// A second of frames: the sheet's spring and the step's reveal are
    /// through; a looping mark (a coin image still loading) never settles.
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// The sheet full, so the whole step is in the frame.
    Future<void> expand(Finder flow) async {
      final route = ModalRoute.of(tester.element(flow));
      if (route is SendSheetRoute) route.sheetController.expand();
      await settle();
    }

    for (final dark in [false, true]) {
      final suffix = dark ? 'dark' : 'light';
      final theme = _themed(dark);

      // Bitcoin: the send as the dock opens it.
      final btcKey = GlobalKey();
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => context.pushNamed('pay_send'),
                child: const Text('Open send'),
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
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(),
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => RepaintBoundary(
            key: btcKey,
            child: MaterialApp.router(
              debugShowCheckedModeBanner: false,
              builder: withKuteShellBar,
              routerConfig: router,
              theme: theme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        ),
      ));
      await settle();
      await tester.tap(find.text('Open send'));
      await settle();
      await expand(find.byType(ConfirmSend));
      await shot(btcKey, 'bitcoin-send-to-$suffix');
      router.dispose();

      // Dollars: the coin step, then the address step for Arbitrum USDC
      // (the Withdraw sheet's next step).
      for (final withCoin in [false, true]) {
        final usdKey = GlobalKey();
        final dest = withCoin
            ? usdSendDestinations(_catalog())
                .firstWhere((d) => d.chain == 'arbitrum' && d.assetCode == 'USDC')
            : null;
        await tester.pumpWidget(ProviderScope(
          overrides: _overrides(),
          child: ScreenUtilInit(
            designSize: const Size(430, 932),
            builder: (_, __) => RepaintBoundary(
              key: usdKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                builder: withKuteShellBar,
                theme: theme,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Scaffold(
                  body: Center(
                    child: Builder(
                      builder: (context) => TextButton(
                        onPressed: () => showSendSheet<bool>(context,
                            builder: (_) =>
                                UsdSendScreen(initialDestination: dest)),
                        child: const Text('Open send'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
        await settle();
        await tester.tap(find.text('Open send'));
        await settle();
        await expand(find.byType(UsdSendScreen));
        await shot(usdKey,
            withCoin ? 'dollars-address-step-$suffix' : 'dollars-coin-step-$suffix');
      }
    }
  });
}
