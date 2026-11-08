// A look by eye at the approved Send (founder, 7 November 2026: "ok do it,
// just make sure that people realise they can send to different cryptos
// also"; then "another crypto should be implied not a button"): the Who
// step empty, the contacts right under the field; the Who step with a 0x
// address typed (the network question under the field) and after one is
// pasted, the network asked in the "Where to?" sheet filtered to it; the What step over a contact (Bitcoin and the
// gift as two squares, the gift wearing Sal, the bar its Back); and the
// Dollars Send's Who step and What step (Dollars and the gift), also in
// German, Finnish, Hungarian and Portuguese. Then THE FIRST STEPS' HEADER
// (founder, 7 November 2026: "it is strange the size"): the Bitcoin Send,
// the Dollars Send and both Receives open on the same header ("Send" or
// "Receive" big on the left, the compact X at the top right), and the
// drag handle, the title, the X and the first content line up to the
// point on all four. Light and dark, on a 375 pt phone, Sal's sheets
// loaded. Every frame lays out without an overflow; the PNGs are written
// only when asked:
//
//   SEND_WHO_RENDER=<dir> flutter test test/render/send_who_what_render_test.dart

import 'dart:convert';
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
import 'dart:async' show Completer;

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/account.dart' show BtcSpendingAccount;
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/models/breez/sdk_instance.dart' show BreezSdkSpark;
import 'package:kute/models/balance_model.dart' show WalletBalance;
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/accounts_provider.dart'
    show selectedAccountProvider, swapOffersEnabledProvider;
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/balance_provider.dart'
    show WalletBalanceCacheNotifier, walletBalanceCacheProvider;
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_contacts_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider, usdBalanceUnknownProvider;
import 'package:kute/screens/pay/components/confirm_send.dart';
import 'package:kute/screens/receive/receive_sheet.dart'
    show showBitcoinReceiveSheet, showUsdReceiveSheet;
import 'package:kute/screens/shared/kute_back_button.dart' show KuteCloseButton;
import 'package:kute/screens/shared/receive_surface.dart'
    show ReceiveSheetFrame, SheetTitleHeader;
import 'package:kute/screens/shared/sal_sprite.dart'
    show SalSpriteCache, kSalSpriteDir;
import 'package:kute/screens/shared/send/send_sheet.dart';
import 'package:kute/screens/shared/send/send_what_step.dart'
    show SendWhatSheet;
import 'package:kute/screens/usd/usd_withdraw_screen.dart'
    show showUsdWithdrawSheet;
import 'package:kute/services/api/share_links_api.dart';
import 'package:kute/services/contacts/send_contacts_service.dart';
import 'package:kute/services/orchestra/receive_minimums.dart'
    show ReceiveMinimums, receiveMinimumsProvider;
import 'package:kute/services/orchestra/reusable_deposit_address.dart'
    show standingDestinationsProvider;
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

/// The spending wallet's bitcoin, for the What step's Bitcoin card.
class _Balances extends WalletBalanceCacheNotifier {
  _Balances() {
    state = {
      'spending':
          WalletBalance(onChainBtcBalance: 0, sparkBitcoinbalance: 328686),
    };
  }
}

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

/// Sal's sheets, read for real: the What step's gift wears his face.
Future<void> _sal(WidgetTester tester) => tester.runAsync(() async {
      SalSpriteCache.debugSetManifest(jsonDecode(await rootBundle
          .loadString('$kSalSpriteDir/manifest.json')) as Map<String, dynamic>);
      for (final density in [2, 3]) {
        await SalSpriteCache.clip('share', density);
      }
    });

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
  // The cards' soft shadows drawn as on a phone for the shot (a test
  // draws them unblurred), then flat again.
  debugDisableShadows = false;
  for (final o in tester.allRenderObjects) {
    o.markNeedsPaint();
  }
  await tester.pump();
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image =
        await layer.toImage(Offset.zero & view.size, pixelRatio: 3);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(dir).createSync(recursive: true);
    File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
  debugDisableShadows = true;
  await tester.pump();
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

  Future<void> pumpSend(WidgetTester tester,
      {required bool dark, Locale? locale}) async {
    await tester.runAsync(loadShareCardFonts);
    await _sal(tester);
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
        walletBalanceCacheProvider.overrideWith((_) => _Balances()),
        orchestraSupportedRoutesProvider
            .overrideWith((_) => _Routes(_catalog())),
        orchestraRoutesReadyProvider.overrideWith((_) async {}),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp.router(
          builder: withKuteShellBar,
          routerConfig: router,
          locale: locale,
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

  Future<void> pumpDollars(WidgetTester tester,
      {required bool dark, Locale? locale}) async {
    await tester.runAsync(loadShareCardFonts);
    await _sal(tester);
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
        usdBalanceProvider.overrideWithValue(12.34),
        usdBalanceUnknownProvider.overrideWithValue(false),
        orchestraSupportedRoutesProvider
            .overrideWith((_) => _Routes(_catalog())),
        orchestraRoutesReadyProvider.overrideWith((_) async {}),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          builder: withKuteShellBar,
          locale: locale,
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

  /// Opens a Receive ([open]) over a screen, as the home's rows do.
  Future<void> pumpReceive(WidgetTester tester,
      {required bool dark,
      required Future<void> Function(BuildContext) open}) async {
    await tester.runAsync(loadShareCardFonts);
    final policy = runtimePolicyFixture();
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
        selectedAccountProvider.overrideWithValue(
            BtcSpendingAccount(WalletConfig(id: 'spending', name: 'Spending'))),
        swapOffersEnabledProvider.overrideWithValue(true),
        walletBalanceCacheProvider.overrideWith((_) => _Balances()),
        usdBalanceProvider.overrideWithValue(12.34),
        usdBalanceUnknownProvider.overrideWithValue(false),
        orchestraSupportedRoutesProvider
            .overrideWith((_) => _Routes(_catalog())),
        orchestraRoutesReadyProvider.overrideWith((_) async {}),
        standingDestinationsProvider.overrideWith((_) async => {'spark:USDB'}),
        receiveMinimumsProvider
            .overrideWithValue(ReceiveMinimums(fetch: (_) async => null)),
        breezSDKProvider
            .overrideWith((_) => Completer<BreezSdkSpark>().future),
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
                  onPressed: () => open(context),
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

  /// The first step's header, measured from the sheet's top edge: the drag
  /// handle's top, the title's box, the X's circle and where the content
  /// starts ([content]: the field on a Send, the lead card on a Receive).
  Map<String, Rect> headerGeometry(
      WidgetTester tester, Finder sheet, Finder content) {
    final top = tester.getRect(sheet).top;
    Rect fromTop(Rect r) => r.translate(0, -top);
    final handle = find.descendant(
        of: sheet,
        matching: find.byWidgetPredicate((w) =>
            w is Container &&
            w.constraints ==
                BoxConstraints.tightFor(
                    width: ScreenUtil().setWidth(36),
                    height: ScreenUtil().setHeight(4))));
    final header = find.byType(SheetTitleHeader);
    final title = find.descendant(
        of: header, matching: find.byType(RichText)).first;
    final circle = find
        .descendant(
            of: find.descendant(
                of: find.byKey(SheetTitleHeader.closeKey),
                matching: find.byType(KuteCloseButton)),
            matching: find.byType(CustomPaint))
        .first;
    return {
      'handle': fromTop(tester.getRect(handle.first)),
      'title': fromTop(tester.getRect(title)),
      'close': fromTop(tester.getRect(circle)),
      'content': fromTop(tester.getRect(content)),
    };
  }

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';

    testWidgets(
        'the first steps\' header lines up on all four sheets ($theme): the '
        'handle, the big title on the left, the compact X at the top right '
        'and the first content at the same place', (tester) async {
      final shapes = <String, Map<String, Rect>>{};

      await pumpSend(tester, dark: dark);
      shapes['bitcoin send'] = headerGeometry(
          tester,
          find.byKey(const ValueKey('send-sheet')),
          find.byKey(const ValueKey('send-recipient-search')));
      await _capture(tester, 'header-bitcoin-send-$theme');
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);

      await pumpDollars(tester, dark: dark);
      shapes['dollars send'] = headerGeometry(
          tester,
          find.byType(ReceiveSheetFrame),
          find.byKey(const ValueKey('send-recipient-search')));
      await _capture(tester, 'header-dollars-send-$theme');
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);

      await pumpReceive(tester, dark: dark, open: showBitcoinReceiveSheet);
      shapes['bitcoin receive'] = headerGeometry(
          tester,
          find.byType(ReceiveSheetFrame),
          find.byKey(const ValueKey('bitcoin-receive-bitcoin')));
      await _capture(tester, 'header-bitcoin-receive-$theme');
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);

      await pumpReceive(tester, dark: dark, open: showUsdReceiveSheet);
      shapes['dollars receive'] = headerGeometry(
          tester,
          find.byType(ReceiveSheetFrame),
          find.byKey(const ValueKey('usd-receive-dollars')));
      await _capture(tester, 'header-dollars-receive-$theme');

      final reference = shapes['bitcoin send']!;
      for (final entry in shapes.entries) {
        for (final part in ['handle', 'title', 'close']) {
          final a = reference[part]!;
          final b = entry.value[part]!;
          expect(b.top, moreOrLessEquals(a.top, epsilon: 0.5),
              reason: '${entry.key}: $part top');
          expect(b.left, moreOrLessEquals(a.left, epsilon: 0.5),
              reason: '${entry.key}: $part left');
          expect(b.height, moreOrLessEquals(a.height, epsilon: 0.5),
              reason: '${entry.key}: $part height');
        }
        // The title is "Send" or "Receive": its start lines up, its width
        // is its word's. The content starts at the same height, on the
        // same edges.
        final c = entry.value['content']!;
        final r = reference['content']!;
        expect(c.top, moreOrLessEquals(r.top, epsilon: 0.5),
            reason: '${entry.key}: content top');
        expect(c.left, moreOrLessEquals(r.left, epsilon: 0.5),
            reason: '${entry.key}: content left');
        expect(c.right, moreOrLessEquals(r.right, epsilon: 0.5),
            reason: '${entry.key}: content right');
        // The X: its circle's right edge on the content's, centred on the
        // title's line, smaller than the 40 circle.
        final x = entry.value['close']!;
        final t = entry.value['title']!;
        expect(x.right, moreOrLessEquals(c.right, epsilon: 0.5),
            reason: '${entry.key}: X right edge');
        expect(x.center.dy, moreOrLessEquals(t.center.dy, epsilon: 1.5),
            reason: '${entry.key}: X on the title line');
        expect(t.left, moreOrLessEquals(c.left, epsilon: 0.5),
            reason: '${entry.key}: title on the content edge');
      }
      // ignore: avoid_print
      print('first steps\' header ($theme): ${{
        for (final e in shapes.entries)
          e.key: {
            for (final p in e.value.entries)
              p.key: '${p.value.left.toStringAsFixed(1)},'
                  '${p.value.top.toStringAsFixed(1)} '
                  '${p.value.width.toStringAsFixed(1)}x'
                  '${p.value.height.toStringAsFixed(1)}'
          }
      }}');
    });

    testWidgets('render: usd-send-who-empty-$theme', (tester) async {
      await pumpDollars(tester, dark: dark);
      expect(find.byKey(const ValueKey('send-another-crypto')), findsNothing);
      await _capture(tester, 'usd-send-who-empty-$theme');
    });

    testWidgets('render: usd-send-who-typed-0x-$theme', (tester) async {
      await pumpDollars(tester, dark: dark);
      await tester.enterText(find.byType(TextField).first,
          '0x742d35cc6634c0532925a3b844bc454e4438f44e');
      await _settle(tester);
      expect(find.byKey(const ValueKey('usd-withdraw-pick-network')),
          findsOneWidget);
      await _capture(tester, 'usd-send-who-typed-0x-$theme');
    });

    for (final language in ['en', 'de', 'fi', 'hu', 'pt']) {
      final suffix = language == 'en' ? '' : '-$language';
      testWidgets('render: usd-send-what$suffix-$theme', (tester) async {
        await pumpDollars(tester, dark: dark, locale: Locale(language));
        await tester
            .tap(find.byKey(const ValueKey('send-person-contact:c2')));
        await _settle(tester);
        expect(find.byType(SendWhatSheet), findsOneWidget);
        await _capture(tester, 'usd-send-what$suffix-$theme');
      });
    }

    testWidgets('render: send-who-empty-$theme', (tester) async {
      await pumpSend(tester, dark: dark);
      expect(find.byKey(const ValueKey('send-another-crypto')), findsNothing);
      await _capture(tester, 'send-who-empty-$theme');
    });

    testWidgets('render: send-who-typed-0x-$theme', (tester) async {
      await pumpSend(tester, dark: dark);
      await tester.enterText(find.byType(TextField).first,
          '0x742d35cc6634c0532925a3b844bc454e4438f44e');
      await _settle(tester);
      expect(find.text('Which network is this address on?'), findsOneWidget);
      await _capture(tester, 'send-who-typed-0x-$theme');
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

    testWidgets('render: send-amount-header-$theme', (tester) async {
      // An inner step keeps its own header (the back chevron on the left,
      // "Send" centred), on the first step's title line, as tall.
      await pumpSend(tester, dark: dark);
      final sheet = find.byKey(const ValueKey('send-sheet'));
      final field = tester
          .getRect(find.byKey(const ValueKey('send-recipient-search')))
          .top -
          tester.getRect(sheet).top;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          return {'text': 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq'};
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.tap(find.byKey(const ValueKey('send-field-paste')));
      await _settle(tester);
      final header = find.byType(SheetTitleHeader);
      expect(header, findsOneWidget);
      expect(find.byKey(SheetTitleHeader.closeKey), findsNothing);
      // The header is as tall as on the Who step: the pages did not move.
      expect(tester.getRect(header).bottom - tester.getRect(sheet).top,
          moreOrLessEquals(field - (4 * 812 / 932 + 1), epsilon: 0.5));
      await _capture(tester, 'send-amount-header-$theme');
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
