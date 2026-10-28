// The Bitcoin receive sheet's layout: the header row (close + "Receive
// into") is the top, with no "Receive" title under it; the QR plate is as
// large as the sheet allows; the address and the Copy / Share row sit
// right under it, above the fold on a 390x844 phone; request amount is a
// quiet text action under the row; the format chips and "also accepts"
// follow, reachable by scroll. The wallet never answers here, so nothing
// reaches a money call: the address and the Lightning address are
// stubbed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/account.dart';
import 'package:kute/models/breez/lnurl_model.dart';
import 'package:kute/models/breez/sdk_instance.dart' show BreezSdkSpark;
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/accounts_provider.dart';
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/breez_provider.dart'
    show setupLnAddressProvider;
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show walletAddressProvider;
import 'package:kute/screens/receive/components/confirm_receive.dart';
import 'package:kute/screens/shared/coin_asset_grid.dart' show CoinMarksLine;
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/runtime_policy_fixture.dart';
import 'package:kute/services/orchestra/reusable_deposit_address.dart'
    show standingDestinationsProvider;

final _l10n = AppLocalizationsEn();

const _address = 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';
const _lnAddress = 'satoshi@paykute.com';
const _lnurl =
    'lnurl1dp68gurn8ghj7ctsdyhxwetewdjhytnxw4hxgtmvde6hymp0wpshj0mswfhk5etrw3ykg0f3xqcs2mcx97';

class _Routes extends OrchestraSupportedRoutesNotifier {
  _Routes(OrchestraRoutesCatalog catalog) {
    state = catalog;
  }

  @override
  Future<void> init() async {}

  @override
  Future<bool> refresh() async => false;
}

Map<String, dynamic> _row(String chain, String asset, {int decimals = 6}) => {
      'id': '$chain:$asset',
      'chain': chain,
      'asset': asset,
      'decimals': decimals,
      'route': {'to': 'all', 'fixedTo': [], 'exactOutTo': []},
    };

final _wallet = WalletConfig(id: 'spending', name: 'Spending');

Future<void> _pump(WidgetTester tester,
    {Size size = const Size(390, 844), double textScale = 1.0}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
            activeWalletId: 'spending',
            wallets: [_wallet],
          ))),
      selectedAccountProvider.overrideWithValue(BtcSpendingAccount(_wallet)),
      swapOffersEnabledProvider.overrideWithValue(true),
      // The provider lists spark:USDB as a standing destination.
      standingDestinationsProvider.overrideWith((_) async => {'spark:USDB'}),
      orchestraSupportedRoutesProvider.overrideWith((_) => _Routes(
            OrchestraRoutesCatalog.fromJson(
              {
                'assets': [
                  _row('spark', 'BTC', decimals: 8),
                  _row('spark', 'USDB'),
                  _row('ethereum', 'USDT'),
                  _row('base', 'USDC'),
                ],
              },
              source: OrchestraCatalogSource.live,
              fetchedAt: DateTime.now(),
            ),
          )),
      walletAddressProvider.overrideWith((ref, id) async => _address),
      setupLnAddressProvider.overrideWith(
          (ref) async => Lnurl(lightningAddress: _lnAddress, lnurl: _lnurl)),
      // The wallet never answers: nothing here reaches a money call.
      breezSDKProvider.overrideWith((_) => Completer<BreezSdkSpark>().future),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            fontFamily: 'Inter',
            extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // The sheet's own height, at the bottom of the screen.
        home: const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ConfirmReceive(),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Unmounts the sheet before its 5 s balance watch fires, then lets the
/// copy toast's own timer run out.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6));
}

Finder _button(String label) => find.widgetWithText(AppButton, label);

Size _plate(WidgetTester tester) => tester.getSize(find
    .descendant(
        of: find.byType(ReceiveQrPlate), matching: find.byType(Container))
    .first);

void main() {
  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    TrackingService.debugTrackObserver = (_, __) {};
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    TrackingService.debugTrackObserver = null;
  });

  testWidgets(
      'the header row is the top: no "Receive" title, and the QR plate '
      'right under it is between 330 and 380pt at 390pt', (tester) async {
    await _pump(tester);
    expect(find.byType(KuteCloseButton), findsOneWidget);
    expect(find.text(_l10n.receive), findsNothing);
    expect(find.text(_l10n.receiveScanOrShareSubtitle), findsNothing);

    final side = _plate(tester);
    expect(side.width, side.height);
    expect(side.width, greaterThanOrEqualTo(330));
    expect(side.width, lessThanOrEqualTo(380));
    // Nothing sits between the header row and the plate.
    final headerBottom =
        tester.getBottomLeft(find.byType(KuteCloseButton)).dy;
    final plateTop = tester.getTopLeft(find.byType(ReceiveQrPlate)).dy;
    expect(plateTop - headerBottom, lessThan(32));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'Share is one full-width filled button under the address, with no '
      'Copy beside it (the address line copies), and request amount is a '
      'text action under it; all of it above the fold at 390x844',
      (tester) async {
    await _pump(tester);
    final address = find.byType(ReceiveAddressLine);
    final share = _button(_l10n.share);
    final request = find.byKey(const ValueKey('receive-request-amount'));
    expect(address, findsOneWidget);
    expect(share, findsOneWidget);
    expect(_button(_l10n.copy), findsNothing);
    expect(request, findsOneWidget);

    expect(tester.widget<AppButton>(share).variant, AppButtonVariant.primary);
    expect(tester.widget(request), isA<AppTextButton>());
    expect(find.text(_l10n.receiveRequestAmount), findsOneWidget);
    // Request amount is not a big button.
    expect(find.widgetWithText(AppButton, _l10n.receiveRequestAmount),
        findsNothing);

    final shareRect = tester.getRect(share);
    final addressRect = tester.getRect(address);
    // Full width: as wide as the address line's column.
    expect(shareRect.width, greaterThan(addressRect.width * 0.9));
    expect(shareRect.top, greaterThan(addressRect.bottom));
    expect(tester.getRect(request).top, greaterThan(shareRect.bottom));

    // Above the fold: the address and Share end inside the screen
    // without a scroll.
    expect(addressRect.bottom, lessThan(844));
    expect(shareRect.bottom, lessThan(844));

    // Format chips and "also accepts" follow, reachable by scroll.
    final chips = find.text(_l10n.receiveQrFormatUnified);
    expect(chips, findsOneWidget);
    expect(tester.getTopLeft(chips).dy, greaterThan(shareRect.bottom));
    final accepts = find.byType(CoinMarksLine);
    await tester.scrollUntilVisible(accepts, 200,
        scrollable: find.byType(Scrollable).first);
    expect(accepts, findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'the address line copies the address it shows and Share shares the '
      'exact QR payload', (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final shared = <MethodCall>[];
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        shareChannel, (call) async {
      shared.add(call);
      return 'dev.fluttercommunity.plus/share/unavailable';
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, null));

    await _pump(tester);
    await tester.tap(find.descendant(
        of: find.byType(ReceiveAddressLine),
        matching: find.byIcon(Icons.copy_rounded)));
    await tester.pump();
    expect(copied, [_lnAddress]);
    expect(
        events.where((e) => e.$1 == 'receive_qr_shared').map((e) => e.$2),
        [
          {'method': 'copy', 'invoice_type': 'bip21'},
        ]);
    // Under the sheet's 5 s balance watch, which would reach real storage.
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(_button(_l10n.share));
    await tester.pump();
    expect(shared, isNotEmpty);
    expect(shared.single.arguments.toString(),
        contains('bitcoin:$_address?lightning=$_lnurl'));
    expect(events.where((e) => e.$1 == 'receive_qr_shared').last.$2,
        {'method': 'share', 'invoice_type': 'bip21'});
    await _unmount(tester);
  });

  testWidgets(
      'swaps blocked for a region (and the cascade): plain bitcoin is '
      'untouched (the on-chain address, the Lightning address and LNURL, '
      'Share), and "also accepts" still lists its coins', (tester) async {
    const regions = {'label': 'the European Union, the UK and Switzerland'};
    const cascade = [
      'orchestra.swap.stablecoins',
      'orchestra.swap.altcoins',
      'crypto.deposit',
      'orchestra.onetime_addresses',
      'hyperliquid.deposit',
      'hyperliquid.trade',
      'polymarket.deposit',
      'polymarket.trade',
    ];
    final policy = runtimePolicyFixture(blocked: {
      'orchestra.swap',
      ...cascade
    }, reasons: {
      'orchestra.swap': 'country_blocked',
      for (final id in cascade) id: 'country_blocked',
    }, decorations: {
      'orchestra.swap': {'regions': regions},
      for (final id in cascade)
        id: {'blockedBy': 'orchestra.swap', 'regions': regions},
    });
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await _pump(tester);
    expect(find.byType(ReceiveQrPlate), findsOneWidget);
    expect(find.byType(ReceiveAddressLine), findsOneWidget);
    expect(_button(_l10n.share), findsOneWidget);
    expect(tester.widget<AppButton>(_button(_l10n.share)).onPressed,
        isNotNull);
    expect(find.textContaining('Not available'), findsNothing);
    await tester.tap(find.descendant(
        of: find.byType(ReceiveAddressLine),
        matching: find.byIcon(Icons.copy_rounded)));
    await tester.pump();
    expect(copied, [_lnAddress]);
    // The other formats are the plain bitcoin ones.
    await tester.tap(find.text(_l10n.receiveQrFormatBitcoinOnly));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.descendant(
        of: find.byType(ReceiveAddressLine),
        matching: find.byIcon(Icons.copy_rounded)));
    await tester.pump();
    expect(copied.last, contains(_address));

    final accepts = find.byType(CoinMarksLine);
    await tester.scrollUntilVisible(accepts, 200,
        scrollable: find.byType(Scrollable).first);
    expect(accepts, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 300));
    await _unmount(tester);
    policy.dispose();
  });

  testWidgets('no overflow at 375pt with text at 1.3x (scroll allowed)',
      (tester) async {
    await _pump(tester, size: const Size(375, 812), textScale: 1.3);
    expect(tester.takeException(), isNull);
    final side = _plate(tester);
    expect(side.width, closeTo(375 * 0.87, 0.5));
    expect(_button(_l10n.share), findsOneWidget);
    expect(_button(_l10n.copy), findsNothing);
    await tester.scrollUntilVisible(find.byType(CoinMarksLine), 200,
        scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });
}
