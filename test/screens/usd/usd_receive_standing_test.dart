// Reusable first, one-time as the fallback (founder, 2026-10-19). A coin
// the standing route serves shows its reusable `spark:USDB` address in its
// own sheet over the coin sheet (no amount, no quote, no Kute fee line, the
// minimum under it; closing it comes back to the coin sheet); from
// the Bitcoin receive the same address says it lands in Investments and is
// marked so its deposits also show in the Bitcoin Activity. A backend
// refusal (422 unsupported_route) opens the one-time amount sheet instead
// and is remembered, so the next coin asks the backend nothing; a policy
// that denies `orchestra.standing_addresses` never asks at all; a policy
// that does not name it (an older backend) tries the registration.
//
// The rails are stubbed: the wallet answers with a Spark address, the
// standing rail through `StandingDepositStore.standingRequest`, quotes
// through `OneTimeReceive.debugFetch` (which fails the test). Nothing here
// reaches a money call, and no legacy accumulation address is asked for.

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
import 'package:kute/models/affiliate_model.dart';
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
import 'package:kute/screens/receive/components/request_amount_sheet.dart';
import 'package:kute/screens/receive/receive_sheet.dart'
    show showOtherCoinsReceiveSheet, showUsdReceiveSheet;
import 'package:kute/screens/shared/account_switcher_pill.dart';
import 'package:kute/screens/shared/asset_network_picker.dart' show PickerRow;
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/shared/kute_back_button.dart' show KuteCloseButton;
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/screens/shared/stepper/stepper_widgets.dart'
    show StepperProgress;
import 'package:kute/screens/usd/flow/usd_flow_widgets.dart' show UsdFlowNote;
import 'package:kute/screens/usd/usd_receive_screen.dart';
import 'package:kute/services/api/orchestra_api.dart'
    show StandingRequestException;
import 'package:kute/services/orchestra/bitcoin_receive_marks.dart';
import 'package:kute/services/orchestra/onetime_receive.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart'
    show OrchestraQuoteRequest;
import 'package:kute/services/orchestra/receive_minimums.dart';
import 'package:kute/services/orchestra/receive_route_availability.dart';
import 'package:kute/services/orchestra/reusable_deposit_address.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart';
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

const _solanaDeposit = '7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU';
const _evmDeposit = '0x1111111111111111111111111111111111111111';
const _spark =
    'sp1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9ucez8h3s';
const _note = ValueKey('usd-receive-from-bitcoin-note');

Future<void> _pump(WidgetTester tester, {bool bitcoin = false}) async {
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
                  _row('ethereum', 'USDT'),
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
      receiveMinimumsProvider.overrideWithValue(ReceiveMinimums(
          fetch: (_) async =>
              const OrchestraRouteLimits(orderMinUsdCents: 150))),
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
                onPressed: () => bitcoin
                    ? showOtherCoinsReceiveSheet(context)
                    : showUsdReceiveSheet(context),
                child: const Text('open receive'),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open receive'));
  await _settle(tester);
}

/// Lets the rails answer: the store's queue on the real event loop, the
/// screen on the test clock.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

/// USDC, then Solana.
Future<void> _pickSolanaUsdc(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(CoinAssetTile, 'USDC').first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.byWidgetPredicate(
      (w) => w is PickerRow && w.title.toLowerCase().contains('solana')));
  for (var i = 0; i < 4; i++) {
    await _settle(tester);
  }
}

/// Unmounts the screens, and disposes the policy: a fresh policy read in
/// the test arms its expiry timer on the test clock.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  RuntimeCapabilitiesService.instance.dispose();
}

void main() {
  late List<(String, Map<String, Object>?)> events;
  late List<String> standingCalls;
  late Object? registerFailure;
  late List<OrchestraQuoteRequest> quoted;
  late Future<Map<String, dynamic>> Function(
      {required String operation,
      String? label,
      required bool Function() current,
      Map<String, dynamic>? body,
      String? idempotencyKey,
      int offset}) realStanding;

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('usd_standing_')).path);
    await Hive.openBox<String>(StandingDepositStore.boxName);
    await Hive.openBox<String>(BitcoinReceiveMarks.boxName);
    await StandingDepositStore.records('none');
    registerFallbackValue(const ReceivePaymentRequest(
        paymentMethod: ReceivePaymentMethod.sparkAddress()));
    realStanding = StandingDepositStore.standingRequest;
  });

  Future<void> usePolicy(RuntimeCapabilitiesService policy) async {
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
  }

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    AffiliateService.debugSessionToken = 'test-session';
    // The default policy does not name orchestra.standing_addresses: a
    // backend older than the switch.
    await usePolicy(runtimePolicyFixture());
    events = [];
    standingCalls = [];
    quoted = [];
    registerFailure = null;
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    StandingReceiveRefusal.clear();
    StandingDepositStore.forgetDestinations();
    StandingDepositStore.debugResetQueue();
    await ReceiveRouteAvailability.clear();
    BitcoinReceiveMarks.reset();
    StandingDepositStore.standingRequest = (
        {required operation,
        label,
        required current,
        body,
        idempotencyKey,
        offset = 0}) async {
      standingCalls.add(operation);
      switch (operation) {
        case 'destinations':
          return {
            'destinations': [
              {'chain': 'spark', 'asset': 'USDB'}
            ]
          };
        case 'mine':
          return {'references': const []};
        case 'read':
          throw const StandingRequestException(404, null);
        case 'register':
          final failure = registerFailure;
          if (failure != null) throw failure;
          return {
            'standingAddressId': 'sda_$label',
            'enabled': true,
            'addresses': {'solana': _solanaDeposit, 'base': _evmDeposit},
            'kuteFeePolicy': {'revision': 1, 'purpose': 'usdb_swap_deposit'},
          };
      }
      return <String, dynamic>{};
    };
    OneTimeReceive.debugFetch = (request) async {
      quoted.add(request);
      throw StateError('no quote in these tests');
    };
  });

  tearDown(() {
    AffiliateService.debugSessionToken = null;
    RuntimeCapabilitiesService.debugInstance = null;
    TrackingService.debugTrackObserver = null;
    StandingDepositStore.standingRequest = realStanding;
    OneTimeReceive.debugFetch = null;
    StandingReceiveRefusal.clear();
  });

  Iterable<Map<String, Object>> named(String name) =>
      events.where((e) => e.$1 == name).map((e) => e.$2 ?? const {});

  testWidgets(
      'Dollars: a coin the standing route serves shows its reusable address '
      '(registration tried with no switch in the policy): no amount sheet, '
      'no quote, no Kute fee line, the minimum under it', (tester) async {
    expect(standingAddressPolicy(RuntimeCapabilitiesService.instance),
        StandingPolicy.unknown);
    await _pump(tester);
    await _pickSolanaUsdc(tester);

    expect(
        find.byWidgetPredicate(
            (w) => w is ReceiveAddressLine && w.address == _solanaDeposit),
        findsOneWidget);
    expect(find.byType(RequestAmountSheet), findsNothing);
    expect(quoted, isEmpty);
    expect(standingCalls.where((c) => c == 'register'), hasLength(1));
    expect(find.text(_l10n.feeUiKuteFee), findsNothing);
    expect(find.text('0.50%'), findsNothing);
    expect(find.text(_l10n.amountMinimumInline('\$1.50')), findsOneWidget);
    // Under the address only the minimum: no "Send only … on …" line.
    expect(find.textContaining('Send only'), findsNothing);
    // Only from the Bitcoin receive does it say where the money lands.
    expect(find.byKey(_note), findsNothing);
    expect(BitcoinReceiveMarks.current, isEmpty);

    final selected = named('usd_receive_coin_selected').single;
    expect(selected['address_kind'], 'standing');
    expect(selected.keys, isNot(contains('fallback_reason')));
    final generated = named('receive_address_generated').single;
    expect(generated['address_kind'], 'standing');
    expect(generated['destination'], 'spark_usd');
    expect(generated['min_deposit_usd'], 1.5);
    expect(generated.keys, isNot(contains('fallback_reason')));
    expect(generated.values, isNot(contains(_solanaDeposit)));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'the reusable address is its own bottom sheet over the coin sheet '
      '(no Scaffold route pushed, no step bar, no boxed note), and its '
      'close comes back to the coin grid as it was', (tester) async {
    // The standing rail answers through the resolver seam, so the address
    // does not depend on what an earlier test registered.
    ReusableDepositAddressService.debugResolver = (
            {required sourceChain,
            required sourceAsset,
            required destinationAsset}) async =>
        const ReusableDepositAddress(
            address: _solanaDeposit,
            id: 'sda_sheet',
            kuteFeeBps: 50,
            model: DepositAddressModel.standing);
    addTearDown(() => ReusableDepositAddressService.debugResolver = null);
    await _pump(tester);
    final coin = ModalRoute.of(tester.element(find.byType(UsdReceiveScreen)));
    expect(coin, isA<ModalBottomSheetRoute<void>>());
    await _pickSolanaUsdc(tester);

    final line = find.byWidgetPredicate(
        (w) => w is ReceiveAddressLine && w.address == _solanaDeposit);
    expect(line, findsOneWidget);
    final sheet = find.byType(UsdStandingAddressSheet);
    expect(sheet, findsOneWidget);
    final route = ModalRoute.of(tester.element(sheet));
    expect(route, isA<ModalBottomSheetRoute<dynamic>>());
    expect(route, isNot(same(coin)));
    // The coin sheet stays underneath, mounted.
    expect(find.byType(UsdReceiveScreen), findsOneWidget);
    // The receive sheet's frame with its close X and "Investments"; only
    // the host's Scaffold.
    expect(find.descendant(of: sheet, matching: find.byType(ReceiveSheetFrame)),
        findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.byType(KuteCloseButton)),
        findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text(_l10n.assetDollars)),
        findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(StepperProgress), findsNothing);
    expect(find.byType(UsdFlowNote), findsNothing);
    expect(
        find.descendant(
            of: sheet,
            matching: find.widgetWithText(
                ReceiveCaption, _l10n.ledgerArrivesAfterNetwork)),
        findsOneWidget);
    expect(named('usd_receive_step').map((p) => p['step']),
        contains('deposit_address_shown'));

    await tester.tap(
        find.descendant(of: sheet, matching: find.byType(KuteCloseButton)));
    await _settle(tester);
    expect(find.byType(UsdStandingAddressSheet), findsNothing);
    expect(line, findsNothing);
    expect(find.byType(UsdReceiveScreen), findsOneWidget);
    expect(find.widgetWithText(CoinAssetTile, 'USDC'), findsWidgets);
    expect(find.text(_l10n.usdReceiveFromAnotherWallet), findsOneWidget);
    expect(named('usd_receive_abandoned'), isEmpty,
        reason: 'the Dollars receive is still open underneath');
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'Dollars: 422 unsupported_route opens the one-time amount sheet, and '
      'the next coin asks the backend nothing', (tester) async {
    registerFailure = const StandingRequestException(422, 'unsupported_route');
    await _pump(tester);
    await _pickSolanaUsdc(tester);

    expect(find.byType(RequestAmountSheet), findsOneWidget);
    expect(
        tester
            .widget<RequestAmountSheet>(find.byType(RequestAmountSheet))
            .fixedCurrency,
        'USD');
    expect(find.byType(ReceiveAddressLine), findsNothing);
    // The address sheet closed itself; the amount sheet is over the coin
    // sheet.
    expect(find.byType(UsdStandingAddressSheet), findsNothing);
    expect(standingCalls.where((c) => c == 'register'), hasLength(1));
    expect(named('receive_address_failed'), isEmpty,
        reason: 'a fallback is not a failure');

    // Dismissed: back on the coin step. Another coin goes straight to
    // one-time: the refusal is remembered.
    Navigator.of(tester.element(find.byType(RequestAmountSheet))).pop();
    await _settle(tester);
    standingCalls.clear();
    await tester.tap(find.widgetWithText(CoinAssetTile, 'USDT').first);
    await _settle(tester);
    expect(find.byType(RequestAmountSheet), findsOneWidget);
    expect(standingCalls, isEmpty);
    final selected = named('usd_receive_coin_selected').last;
    expect(selected['address_kind'], 'onetime');
    expect(selected['fallback_reason'], 'standing_refused');
    expect(quoted, isEmpty);
    await _unmount(tester);
  });

  testWidgets(
      'Dollars: the policy denies orchestra.standing_addresses: no standing '
      'request at all, the coin goes straight to one-time', (tester) async {
    await usePolicy(runtimePolicyFixture(
        also: {kStandingAddressCapability},
        blocked: {kStandingAddressCapability}));
    await _pump(tester);
    await _pickSolanaUsdc(tester);
    expect(find.byType(RequestAmountSheet), findsOneWidget);
    expect(standingCalls, isEmpty);
    final selected = named('usd_receive_coin_selected').single;
    expect(selected['address_kind'], 'onetime');
    expect(selected['fallback_reason'], 'standing_policy_off');
    await _unmount(tester);
  });

  testWidgets(
      'Bitcoin other coins: the standing Dollars address, titled Investments '
      'with the note, and marked for the Bitcoin Activity', (tester) async {
    // The standing rail answers through the resolver seam here (the
    // registration itself is exercised above).
    final asked = <String>[];
    ReusableDepositAddressService.debugResolver = (
        {required sourceChain,
        required sourceAsset,
        required destinationAsset}) async {
      asked.add('$sourceChain:$sourceAsset:$destinationAsset');
      return const ReusableDepositAddress(
          address: _solanaDeposit,
          id: 'sda_bitcoin',
          kuteFeeBps: 50,
          model: DepositAddressModel.standing);
    };
    addTearDown(() => ReusableDepositAddressService.debugResolver = null);
    await _pump(tester, bitcoin: true);
    // The coin step is the Bitcoin receive's.
    expect(
        find.descendant(
            of: find.byType(AccountSwitcherPill),
            matching: find.text(_l10n.bitcoin)),
        findsOneWidget);
    await _pickSolanaUsdc(tester);

    expect(
        find.byWidgetPredicate(
            (w) => w is ReceiveAddressLine && w.address == _solanaDeposit),
        findsOneWidget);
    expect(find.byKey(_note), findsOneWidget);
    expect(find.text(_l10n.moveDestDollarsSubtitle), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AccountSwitcherPill),
            matching: find.text(_l10n.assetDollars)),
        findsOneWidget);
    expect(find.byType(RequestAmountSheet), findsNothing);
    expect(quoted, isEmpty);
    // The Dollars address: spark:USDB, never spark:BTC.
    expect(asked, ['solana:USDC:USDB']);
    final mark = BitcoinReceiveMarks.current.single;
    expect(mark.walletId, 'spending');
    expect(mark.sourceChain, 'solana');
    expect(mark.address, _solanaDeposit);
    final generated = named('receive_address_generated').single;
    expect(generated['address_kind'], 'standing');
    expect(generated['destination'], 'spark_usd');
    expect(generated['entry_source'], 'bitcoin_receive');
    await _unmount(tester);
  });

  testWidgets(
      'Bitcoin other coins: standing refused falls back to the one-time '
      'Bitcoin flow (the amount in the receive unit) and marks nothing',
      (tester) async {
    registerFailure = const StandingRequestException(422, 'unsupported_route');
    await _pump(tester, bitcoin: true);
    await _pickSolanaUsdc(tester);
    final amount =
        tester.widget<RequestAmountSheet>(find.byType(RequestAmountSheet));
    expect(amount.fixedCurrency, isNull);
    expect(find.byKey(_note), findsNothing);
    expect(BitcoinReceiveMarks.current, isEmpty);
    await _unmount(tester);
  });
}
