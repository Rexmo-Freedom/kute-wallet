// The Bitcoin receive's own codes (the unified code, Bitcoin only, and
// Lightning only) show no minimum: the network sets none. Other coins are
// taken through the "other coins" line: a coin sheet over this one that
// delivers bitcoin (spark:BTC) through one-time addresses, titled Bitcoin,
// with no Investments note and no Bitcoin-to-Investments row; a coin
// picked there asks its amount in the Lightning receive's own "Request
// amount" sheet. The line lists only coins a one-time quote can serve,
// and is gone when none can. The rails are stubbed.

import 'dart:io';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/account.dart';
import 'package:kute/models/breez/lnurl_model.dart';
import 'package:kute/models/breez/sdk_instance.dart' show BreezSdkSpark;
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/accounts_provider.dart';
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/breez_provider.dart' show setupLnAddressProvider;
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show walletAddressProvider;
import 'package:kute/screens/receive/components/confirm_receive.dart';
import 'package:kute/screens/receive/components/request_amount_sheet.dart';
import 'package:kute/screens/shared/account_switcher_pill.dart';
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/screens/usd/usd_receive_screen.dart';
import 'package:kute/services/orchestra/receive_minimums.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart'
    show StandingDepositStore;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:mocktail/mocktail.dart';
import 'package:money2/money2.dart';

import '../../helpers/runtime_policy_fixture.dart';

class _Sdk extends Mock implements BreezSdk {}

class _Wrapper extends Mock implements BreezSdkSpark {}

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

final _l10n = AppLocalizationsEn();

const _address = 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';
const _lnAddress = 'satoshi@paykute.com';
const _lnurl =
    'lnurl1dp68gurn8ghj7ctsdyhxwetewdjhytnxw4hxgtmvde6hymp0wpshj0mswfhk5etrw3ykg0f3xqcs2mcx97';
const _spark =
    'spark1pgss9qn2e5ej2t0wf6l0ndr0uw3nqcwyznzuu7flm8xvk4nw0jxcvyxtfsk2';

final _wallet = WalletConfig(id: 'spending', name: 'Spending');

Future<void> _pump(WidgetTester tester,
    {List<Map<String, dynamic>>? assets}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final sdk = _Sdk();
  when(() => sdk.receivePayment(request: any(named: 'request'))).thenAnswer(
      (_) async =>
          ReceivePaymentResponse(paymentRequest: _spark, fee: BigInt.zero));
  final wrapper = _Wrapper();
  when(() => wrapper.instance).thenReturn(sdk);
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
      orchestraSupportedRoutesProvider.overrideWith((_) => _Routes(
            OrchestraRoutesCatalog.fromJson(
              {
                'assets': assets ??
                    [
                      _row('spark', 'BTC', decimals: 8),
                      _row('spark', 'USDB'),
                      _row('ethereum', 'USDT'),
                    ],
              },
              source: OrchestraCatalogSource.live,
              fetchedAt: DateTime.now(),
            ),
          )),
      orchestraRoutesReadyProvider.overrideWith((_) async {}),
      // No limits read answers: the $1.00 floor.
      receiveMinimumsProvider
          .overrideWithValue(ReceiveMinimums(fetch: (_) async => null)),
      // Bitcoin at $60,000.
      selectedCurrencyProvider.overrideWith(
          (ref, code) => Money.fromIntWithCurrency(6000000, AppCurrencies.usd)),
      walletAddressProvider.overrideWith((ref, id) async => _address),
      setupLnAddressProvider.overrideWith(
          (ref) async => Lnurl(lightningAddress: _lnAddress, lnurl: _lnurl)),
      breezSDKProvider.overrideWith((_) async => wrapper),
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
        home: const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ConfirmReceive(),
          ),
        ),
      ),
    ),
  ));
  await _settle(tester);
}

/// The store's queue answers on the real event loop (see setUpAll), the
/// screen on the test clock.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

/// Unmounts the sheet before its 5 s balance watch fires.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6));
}

Future<void> _format(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump();
}

final _minimum = find.byKey(const ValueKey('receive-minimum'));

void main() {
  late List<(String, Map<String, Object>?)> events;

  setUpAll(() async {
    // See usd_receive_minimum_test.dart: an open, empty standing box, and
    // the store's queue started outside any one test's fake clock.
    Hive.init((await Directory.systemTemp.createTemp('receive_minimum_')).path);
    await Hive.openBox<String>(StandingDepositStore.boxName);
    await StandingDepositStore.records('none');
    registerFallbackValue(const ReceivePaymentRequest(
        paymentMethod: ReceivePaymentMethod.sparkAddress()));
  });

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    TrackingService.debugTrackObserver = null;
  });

  List<Map<String, Object>?> addressEvents() => events
      .where((e) => e.$1 == 'receive_address_generated')
      .map((e) => e.$2)
      .toList();

  testWidgets(
      'Bitcoin only: the wallet address shows no minimum (the network sets '
      'none), and the event records the address once', (tester) async {
    await _pump(tester);
    expect(_minimum, findsNothing);
    expect(addressEvents(), isEmpty);

    await _format(tester, _l10n.receiveQrFormatBitcoinOnly);
    expect(find.byType(ReceiveAddressLine), findsWidgets);
    expect(_minimum, findsNothing);
    expect(find.textContaining(_l10n.amountMinimumInline('')), findsNothing);
    expect(addressEvents(), [
      {
        'asset': 'btc',
        'network': 'bitcoin',
        'provider': 'breez',
        'destination': 'spark_btc',
        'address_kind': 'static_deposit',
      },
    ]);

    // Away and back: the same address is not recorded twice.
    await _format(tester, _l10n.receiveQrFormatUnified);
    await _format(tester, _l10n.receiveQrFormatBitcoinOnly);
    expect(addressEvents(), hasLength(1));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('Lightning only shows no minimum', (tester) async {
    await _pump(tester);
    await _format(tester, _l10n.receiveQrFormatLightningOnly);
    expect(find.byType(ReceiveAddressLine), findsOneWidget);
    expect(_minimum, findsNothing);
    expect(find.textContaining(_l10n.amountMinimumInline('')), findsNothing);
    expect(addressEvents(), isEmpty);
    await _unmount(tester);
  });

  testWidgets(
      'other coins opens the Bitcoin one-time sheet over this one: titled '
      'Bitcoin, no Investments note, no Bitcoin row, and a coin opens the '
      '"Request amount" sheet', (tester) async {
    await _pump(tester);
    expect(find.text(_l10n.receiveAlsoAccepts), findsOneWidget);
    await tester.tap(find.text(_l10n.receiveAlsoAccepts));
    await _settle(tester);

    final sheet =
        tester.widget<UsdReceiveScreen>(find.byType(UsdReceiveScreen));
    expect(sheet.destinationAsset, 'BTC');
    // A bottom sheet over the Bitcoin receive, which stays underneath.
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(ConfirmReceive, skipOffstage: false), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AccountSwitcherPill),
            matching: find.text(_l10n.bitcoin)),
        findsOneWidget);
    expect(find.text(_l10n.assetDollars), findsNothing);
    expect(find.text(_l10n.usdReceiveFromYourWallet), findsNothing);
    expect(find.byKey(const ValueKey('usd-receive-from-bitcoin')),
        findsNothing);
    expect(names(events), isNot(contains('usd_receive_opened')));
    expect(events.where((e) => e.$1 == 'receive_also_accepts_opened'),
        hasLength(1));

    // A coin picked there asks its amount in the Lightning request sheet,
    // in the receive unit with its picker, and the route's minimum once
    // known.
    await tester.tap(find.widgetWithText(CoinAssetTile, 'USDT').first);
    await _settle(tester);
    final amount =
        tester.widget<RequestAmountSheet>(find.byType(RequestAmountSheet));
    expect(amount.fixedCurrency, isNull);
    // The limits read gave nothing: no minimum line (no app floor).
    expect(amount.limits!.value.minimumLabel, isNull);
    expect(
        find.descendant(
            of: find.byType(RequestAmountSheet),
            matching: find.text(_l10n.receiveRequestAmount)),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(RequestAmountSheet),
            matching: find.text(_l10n.receiveCreateRequest)),
        findsOneWidget);
    final step =
        events.where((e) => e.$1 == 'receive_step').map((e) => e.$2!).toList();
    expect(step.any((p) => p['step'] == 'coin_selected' &&
        p['address_kind'] == 'onetime' &&
        p['destination'] == 'spark_btc'), isTrue);
    expect(addressEvents(), isEmpty);
    await _unmount(tester);
  });

  testWidgets(
      'only coins a one-time quote can serve are listed, and with none left '
      'the line is gone', (tester) async {
    // No own refund address and not refund-optional: never offered.
    await _pump(tester, assets: [
      _row('spark', 'BTC', decimals: 8),
      _row('spark', 'USDB'),
      _row('litecoin', 'LTC', decimals: 8),
      _row('ton', 'USDT'),
    ]);
    expect(find.text(_l10n.receiveAlsoAccepts), findsNothing);
    await _unmount(tester);

    // One-time addresses off: nothing to offer either.
    final off =
        runtimePolicyFixture(blocked: {'orchestra.onetime_addresses'});
    expect(await off.refresh(), isTrue);
    RuntimeCapabilitiesService.debugInstance = off;
    await _pump(tester);
    expect(find.text(_l10n.receiveAlsoAccepts), findsNothing);
    await _unmount(tester);
    off.dispose();
  });
}

Iterable<String> names(List<(String, Map<String, Object>?)> events) =>
    events.map((e) => e.$1);
