// The Dollars receive address says the smallest deposit it takes: the
// larger of the route's live minimum and the $1.00 floor, in the caption
// style under the address. A failed limits read shows the floor and never
// holds the address back. `receive_address_generated` carries the exact
// minimum shown and where it came from. The rails are stubbed: the
// wallet answers with a Spark address and the address resolver with a
// fixed deposit address.

import 'dart:async';
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
import 'package:kute/models/breez/sdk_instance.dart' show BreezSdkSpark;
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/receive/receive_sheet.dart'
    show showUsdReceiveSheet;
import 'package:kute/screens/shared/asset_network_picker.dart' show PickerRow;
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

class _Balances extends WalletBalanceCacheNotifier {
  _Balances() {
    state = const {};
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

Map<String, dynamic> _row(String chain, String asset, {int decimals = 6}) => {
      'id': '$chain:$asset',
      'chain': chain,
      'asset': asset,
      'decimals': decimals,
      'route': {'to': 'all', 'fixedTo': [], 'exactOutTo': []},
    };

final _l10n = AppLocalizationsEn();

const _deposit = '7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU';
const _spark =
    'spark1pgss9qn2e5ej2t0wf6l0ndr0uw3nqcwyznzuu7flm8xvk4nw0jxcvyxtfsk2';

Future<void> _pump(WidgetTester tester, ReceiveMinimums minimums) async {
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
            wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          ))),
      orchestraSupportedRoutesProvider.overrideWith((_) => _Routes(
            OrchestraRoutesCatalog.fromJson(
              {
                'assets': [
                  _row('spark', 'BTC', decimals: 8),
                  _row('spark', 'USDB'),
                  _row('base', 'USDC'),
                  _row('solana', 'USDC'),
                ],
              },
              source: OrchestraCatalogSource.live,
              fetchedAt: DateTime.now(),
            ),
          )),
      orchestraRoutesReadyProvider.overrideWith((_) async {}),
      selectedCurrencyProvider.overrideWith(
          (ref, code) => Money.fromIntWithCurrency(6000000, AppCurrencies.usd)),
      walletBalanceCacheProvider.overrideWith((_) => _Balances()),
      breezSDKProvider.overrideWith((_) async => wrapper),
      receiveMinimumsProvider.overrideWithValue(minimums),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            fontFamily: 'Inter',
            extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showUsdReceiveSheet(context),
                child: const Text('open receive'),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open receive'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// USDC, then Solana: the address step for solana:USDC → spark:USDB.
Future<void> _openSolanaUsdc(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(CoinAssetTile, 'USDC').first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.byWidgetPredicate(
      (w) => w is PickerRow && w.title.toLowerCase().contains('solana')));
  await _settle(tester);
}

/// Lets the address resolve: the store's queue answers on the real event
/// loop (see setUpAll), the screen on the test clock.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

final _route = RouteKey(
    fromChain: 'solana', fromAsset: 'USDC', toChain: 'spark', toAsset: 'USDB');

void main() {
  late List<(String, Map<String, Object>?)> events;
  late List<RouteKey> asked;

  setUpAll(() async {
    // The screen reads the standing records before it asks for an
    // address: an open, empty box answers at once. Reading once here
    // starts the store's queue outside any one test's fake clock, so a
    // later test does not wait on a finished test's zone.
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
    asked = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    ReusableDepositAddressService.debugResolver = (
            {required sourceChain,
            required sourceAsset,
            required destinationAsset}) async =>
        const ReusableDepositAddress(
            address: _deposit,
            id: 'sda_test',
            kuteFeeBps: null,
            model: DepositAddressModel.standing);
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    TrackingService.debugTrackObserver = null;
    ReusableDepositAddressService.debugResolver = null;
  });

  ReceiveMinimums minimumsAnswering(
          Future<OrchestraRouteLimits?> Function() answer) =>
      ReceiveMinimums(fetch: (route) {
        asked.add(route);
        return answer();
      });

  Map<String, Object>? addressEvent() => events
      .where((e) => e.$1 == 'receive_address_generated')
      .map((e) => e.$2)
      .lastOrNull;

  testWidgets(
      'a live minimum of \$0.80 shows the \$1.00 floor under the address, '
      'and the event carries it as a live read', (tester) async {
    await _pump(
        tester,
        minimumsAnswering(
            () async => const OrchestraRouteLimits(orderMinUsdCents: 80)));
    await _openSolanaUsdc(tester);
    expect(find.byType(ReceiveAddressLine), findsOneWidget);
    expect(find.text(_l10n.amountMinimumInline('\$1.00')), findsOneWidget);
    expect(asked, [_route]);
    // Directly under the address, in the caption style.
    final caption = find.byKey(const ValueKey('receive-minimum'));
    expect(
        tester.getTopLeft(caption).dy,
        greaterThan(
            tester.getBottomLeft(find.byType(ReceiveAddressLine)).dy));
    expect(find.descendant(of: caption, matching: find.byType(ReceiveCaption)),
        findsOneWidget);
    final event = addressEvent()!;
    expect(event['min_deposit_usd'], 1.0);
    expect(event['min_source'], 'live');
    expect(event['provider'], 'orchestra');
    expect(event['destination'], 'spark_usd');
    expect(event.values.whereType<String>(), isNot(contains(_deposit)));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('a live minimum of \$1.50 shows \$1.50', (tester) async {
    await _pump(
        tester,
        minimumsAnswering(
            () async => const OrchestraRouteLimits(orderMinUsdCents: 150)));
    await _openSolanaUsdc(tester);
    expect(find.text(_l10n.amountMinimumInline('\$1.50')), findsOneWidget);
    expect(addressEvent()!['min_deposit_usd'], 1.5);
    expect(addressEvent()!['min_source'], 'live');
    await _unmount(tester);
  });

  testWidgets(
      'a failed limits read shows the \$1.00 floor and the address anyway',
      (tester) async {
    await _pump(tester, minimumsAnswering(() async => throw StateError('x')));
    await _openSolanaUsdc(tester);
    expect(find.byType(ReceiveAddressLine), findsOneWidget);
    expect(find.text(_l10n.amountMinimumInline('\$1.00')), findsOneWidget);
    expect(find.textContaining('\$0.00'), findsNothing);
    expect(addressEvent()!['min_deposit_usd'], 1.0);
    expect(addressEvent()!['min_source'], 'floor');
    await _unmount(tester);
  });

  testWidgets(
      'a limits read that never answers does not hold the address back',
      (tester) async {
    final never = Completer<OrchestraRouteLimits?>();
    await _pump(tester, minimumsAnswering(() => never.future));
    await _openSolanaUsdc(tester);
    expect(find.byType(ReceiveAddressLine), findsOneWidget);
    expect(find.byKey(const ValueKey('receive-minimum')), findsNothing);
    never.complete(const OrchestraRouteLimits(orderMinUsdCents: 120));
    await _settle(tester);
    expect(find.text(_l10n.amountMinimumInline('\$1.20')), findsOneWidget);
    expect(addressEvent()!['min_deposit_usd'], 1.2);
    await _unmount(tester);
  });
}
