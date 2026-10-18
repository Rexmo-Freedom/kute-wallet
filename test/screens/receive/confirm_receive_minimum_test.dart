// The Bitcoin receive says the smallest deposit an address takes, in the
// caption style under it. The wallet's own Bitcoin address (the Spark
// static deposit address, "Bitcoin only") shows the claim-fee minimum in
// sats with its dollar value; Lightning and the unified code show none;
// another coin's Orchestra address shows the route minimum with the
// $1.00 floor. `receive_address_generated` carries the minimum shown and
// where it came from. The rails are stubbed.

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
import 'package:kute/models/breez/init.dart' show kSparkAutoClaimMaxFeeSats;
import 'package:kute/models/breez/lnurl_model.dart';
import 'package:kute/models/breez/sdk_instance.dart' show BreezSdkSpark;
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/accounts_provider.dart';
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/breez_provider.dart'
    show setupLnAddressProvider;
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/pending_asset_provider.dart'
    show pendingReceiveOpenOtherAssetsProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show walletAddressProvider;
import 'package:kute/screens/receive/components/confirm_receive.dart';
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/services/orchestra/receive_minimums.dart';
import 'package:kute/services/orchestra/reusable_deposit_address.dart';
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
const _deposit = '0x52908400098527886E0F7030069857D2E4169EE7';
const _spark =
    'spark1pgss9qn2e5ej2t0wf6l0ndr0uw3nqcwyznzuu7flm8xvk4nw0jxcvyxtfsk2';

final _wallet = WalletConfig(id: 'spending', name: 'Spending');

Future<void> _pump(WidgetTester tester,
    {ReceiveMinimums? minimums, bool openOtherAssets = false}) async {
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
                'assets': [
                  _row('spark', 'BTC', decimals: 8),
                  _row('ethereum', 'USDT'),
                ],
              },
              source: OrchestraCatalogSource.live,
              fetchedAt: DateTime.now(),
            ),
          )),
      orchestraRoutesReadyProvider.overrideWith((_) async {}),
      // Bitcoin at $60,000.
      selectedCurrencyProvider.overrideWith(
          (ref, code) => Money.fromIntWithCurrency(6000000, AppCurrencies.usd)),
      walletAddressProvider.overrideWith((ref, id) async => _address),
      setupLnAddressProvider.overrideWith(
          (ref) async => Lnurl(lightningAddress: _lnAddress, lnurl: _lnurl)),
      breezSDKProvider.overrideWith((_) async => wrapper),
      if (minimums != null) receiveMinimumsProvider.overrideWithValue(minimums),
      pendingReceiveOpenOtherAssetsProvider
          .overrideWith((_) => openOtherAssets),
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
    ReusableDepositAddressService.debugResolver = (
            {required sourceChain,
            required sourceAsset,
            required destinationAsset}) async =>
        const ReusableDepositAddress(
            address: _deposit,
            id: 'acc_test',
            kuteFeeBps: null,
            model: DepositAddressModel.accumulation);
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    TrackingService.debugTrackObserver = null;
    ReusableDepositAddressService.debugResolver = null;
  });

  List<Map<String, Object>?> addressEvents() => events
      .where((e) => e.$1 == 'receive_address_generated')
      .map((e) => e.$2)
      .toList();

  test('the on-chain minimum is the auto-claim fee ceiling plus dust', () {
    expect(kSparkOnchainReceiveMinimumSats,
        kSparkAutoClaimMaxFeeSats + kSparkDepositDustSats);
    expect(kSparkOnchainReceiveMinimumSats, 2975);
    // 2,975 sats at $60,000 is $1.785, shown rounded up.
    expect(sparkOnchainReceiveMinimum(usdPerBtc: 60000).usdCents, 179);
    expect(sparkOnchainReceiveMinimum(usdPerBtc: 0).usdCents, isNull);
  });

  testWidgets(
      'Bitcoin only: the wallet address shows its claim-fee minimum in sats '
      'with the dollar value, and the event records it once', (tester) async {
    await _pump(tester);
    // The unified code (the default) shows the Lightning address: none.
    expect(_minimum, findsNothing);
    expect(addressEvents(), isEmpty);

    await _format(tester, _l10n.receiveQrFormatBitcoinOnly);
    expect(
        find.text(_l10n.amountMinimumInline(
            _l10n.sendFeeSatsWithFiat('2,975', '\$1.79'))),
        findsOneWidget);
    expect(tester.getTopLeft(_minimum).dy,
        greaterThan(tester.getBottomLeft(find.byType(ReceiveAddressLine)).dy));
    expect(
        find.descendant(of: _minimum, matching: find.byType(ReceiveCaption)),
        findsOneWidget);
    expect(addressEvents(), [
      {
        'asset': 'btc',
        'network': 'bitcoin',
        'provider': 'breez',
        'destination': 'spark_btc',
        'address_kind': 'static_deposit',
        'min_deposit_usd': 1.79,
        'min_deposit_sats': 2975,
        'min_source': 'breez',
      },
    ]);

    // Away and back: the same address is not recorded twice.
    await _format(tester, _l10n.receiveQrFormatUnified);
    expect(_minimum, findsNothing);
    await _format(tester, _l10n.receiveQrFormatBitcoinOnly);
    expect(_minimum, findsOneWidget);
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
      'another coin into Bitcoin: the Orchestra address shows the route '
      'minimum with the \$1.00 floor, read for that exact pair',
      (tester) async {
    final asked = <RouteKey>[];
    await _pump(tester,
        openOtherAssets: true,
        minimums: ReceiveMinimums(fetch: (route) async {
          asked.add(route);
          return const OrchestraRouteLimits(orderMinUsdCents: 80);
        }));
    expect(find.byType(CoinAssetPickerSheet), findsOneWidget);
    await tester.tap(find.widgetWithText(CoinAssetTile, 'USDT').first);
    await _settle(tester);
    expect(
        tester
            .widget<ReceiveAddressLine>(find.byType(ReceiveAddressLine))
            .address,
        _deposit);
    expect(find.text(_l10n.amountMinimumInline('\$1.00')), findsOneWidget);
    expect(asked, [
      RouteKey(
          fromChain: 'ethereum',
          fromAsset: 'USDT',
          toChain: 'spark',
          toAsset: 'BTC'),
    ]);
    final event = addressEvents().single!;
    expect(event['provider'], 'orchestra');
    expect(event['destination'], 'spark_btc');
    expect(event['min_deposit_usd'], 1.0);
    expect(event['min_source'], 'live');
    await _unmount(tester);
  });
}
