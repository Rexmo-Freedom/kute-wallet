// The one-time receive of another coin, end to end with the rails stubbed:
// a coin tapped in the Dollars receive (or the Bitcoin receive's "other
// coins") asks its amount in the Lightning "Request amount" sheet, checked
// against the route's minimum, then quotes a one-time Orchestra deposit
// address into spark:USDB (or spark:BTC), paid to the wallet's own Spark
// address and refunded to its own EVM address, persists it as a pending
// quote (never an Activity row before a deposit), and shows the address
// with the exact amount and the expiry. No standing or legacy address is
// ever registered. A reconnect (a rebuilt SDK) never ends the screen; a
// wallet switch does.

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/breez/sdk_instance.dart' show BreezSdkSpark;
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/screens/receive/components/request_amount_sheet.dart';
import 'package:kute/screens/receive/quoted_receive_screen.dart';
import 'package:kute/screens/receive/receive_sheet.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart'
    show AmountKeypad, BigAmountDisplay;
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/shared/custom_button.dart' show AppButton;
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/services/orchestra/onetime_receive.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/orchestra/receive_minimums.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:mocktail/mocktail.dart';
import 'package:money2/money2.dart';

import '../../helpers/runtime_policy_fixture.dart';

class _Sdk extends Mock implements BreezSdk {}

class _Wrapper extends Mock implements BreezSdkSpark {}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency()
      : super(CurrencyState({
          'USD': Fixed.fromInt(60000),
          'BTC': Fixed.fromNum(1 / 60000, decimalDigits: 16),
        }));

  @override
  Future<void> updateRates() async {}
}

class _Settings extends SettingsModel {
  _Settings(super.state);

  void switchTo(String walletId) =>
      state = state.copyWith(activeWalletId: walletId);
}

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

const _spark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _ownEvm = '0x52908400098527886e0f7030069857d2e4169ee7';
const _deposit = '0x1111111111111111111111111111111111111111';

/// The Breez SDK the provider answers now; replaced to model a reconnect.
late _Wrapper _wrapper;
late _Settings _settings;
late ProviderContainer _container;

/// A fresh SDK instance (what a reconnect builds). [onReceive] runs while
/// the recipient address is read.
_Wrapper _newWrapper({void Function()? onReceive}) {
  final sdk = _Sdk();
  when(() => sdk.receivePayment(request: any(named: 'request')))
      .thenAnswer((_) async {
    onReceive?.call();
    return ReceivePaymentResponse(paymentRequest: _spark, fee: BigInt.zero);
  });
  final wrapper = _Wrapper();
  when(() => wrapper.instance).thenReturn(sdk);
  return wrapper;
}

/// Models a reconnect: the provider rebuilds with a new SDK instance.
void _reconnect() {
  _wrapper = _newWrapper();
  _container.invalidate(breezSDKProvider);
}

Future<void> _pump(WidgetTester tester,
    {bool bitcoin = false, _Wrapper? wrapper}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _wrapper = wrapper ?? _newWrapper();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => _settings = _Settings(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: true,
            activeWalletId: 'spending',
            wallets: [
              WalletConfig(id: 'spending', name: 'Spending'),
              WalletConfig(id: 'other', name: 'Other'),
            ],
          ))),
      orchestraSupportedRoutesProvider.overrideWith((_) => _Routes(
            OrchestraRoutesCatalog.fromJson(
              {
                'assets': [
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
      // Bitcoin at $60,000.
      selectedCurrencyProvider.overrideWith(
          (ref, code) => Money.fromIntWithCurrency(6000000, AppCurrencies.usd)),
      walletBalanceCacheProvider.overrideWith((_) => _Balances()),
      currencyProvider.overrideWith((_) => _Currency()),
      breezSDKProvider.overrideWith((_) async => _wrapper),
      sparkSelfAddressProvider.overrideWith((_) async => _spark),
      hyperliquidAddressProvider.overrideWith((_) async => _ownEvm),
      // A live minimum of $2.00.
      receiveMinimumsProvider.overrideWithValue(ReceiveMinimums(
          fetch: (_) async =>
              const OrchestraRouteLimits(orderMinUsdCents: 200))),
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
  _container =
      ProviderScope.containerOf(tester.element(find.text('open receive')));
  await tester.tap(find.text('open receive'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

/// Unmounts the screens, and disposes the policy: the quote's own fresh
/// policy read arms its expiry timer on the test clock.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  RuntimeCapabilitiesService.instance.dispose();
}

/// USDT on Ethereum, typed [amount] in the request sheet.
Future<void> _requestUsdt(WidgetTester tester, String amount) async {
  await tester.tap(find.widgetWithText(CoinAssetTile, 'USDT').first);
  await _settle(tester);
  expect(find.byType(RequestAmountSheet), findsOneWidget);
  tester.widget<AmountKeypad>(find.byType(AmountKeypad)).onChanged(amount);
  await tester.pump();
}

AppButton _createRequest(WidgetTester tester) => tester.widget<AppButton>(
    find.widgetWithText(AppButton, _l10n.receiveCreateRequest));

void main() {
  late List<(String, Map<String, Object>?)> events;
  late List<OrchestraQuoteRequest> quoted;
  late List<SwapOrder> recorded;
  late List<String> standingCalls;
  late Future<Map<String, dynamic>> Function(
      {required String operation,
      String? label,
      required bool Function() current,
      Map<String, dynamic>? body,
      String? idempotencyKey,
      int offset}) realStanding;

  setUpAll(() {
    registerFallbackValue(const ReceivePaymentRequest(
        paymentMethod: ReceivePaymentMethod.sparkAddress()));
    realStanding = StandingDepositStore.standingRequest;
  });

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    events = [];
    quoted = [];
    recorded = [];
    standingCalls = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    StandingDepositStore.standingRequest = (
        {required operation,
        label,
        required current,
        body,
        idempotencyKey,
        offset = 0}) async {
      standingCalls.add(operation);
      return <String, dynamic>{};
    };
    OneTimeReceive.debugFetch = (request) async {
      quoted.add(request);
      final now = DateTime.now();
      return verifyOrchestraQuote(
        request,
        OrchestraQuote.fromJson({
          'quoteId': 'q_onetime_1',
          'depositAddress': _deposit,
          'amountIn': request.amountBaseUnits.toString(),
          'estimatedOut':
              request.destinationAsset == 'BTC' ? '41000' : '24800000',
          'feeAmount': '0',
          'feeBps': 10,
          'appFees': [
            {'feeBps': 50}
          ],
          'route': <String>[],
          'expiresAt':
              now.add(const Duration(minutes: 2)).toUtc().toIso8601String(),
        }),
        now: now,
        bounds: OrchestraQuoteBounds.forSource(request.sourceChain,
            inputValueInOutputUnits: null),
        mainnet: true,
      );
    };
    OneTimeReceive.debugRecord = (row, expiresAt, scope) async {
      recorded.add(row);
    };
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    TrackingService.debugTrackObserver = null;
    OneTimeReceive.debugFetch = null;
    OneTimeReceive.debugRecord = null;
    StandingDepositStore.standingRequest = realStanding;
  });

  testWidgets(
      'Dollars: an amount under the route minimum keeps "Create request" '
      'off and says the minimum in the error colour', (tester) async {
    await _pump(tester);
    await _requestUsdt(tester, '1.5');
    final display =
        tester.widget<BigAmountDisplay>(find.byType(BigAmountDisplay));
    expect(display.minimumLabel, _l10n.routeAmountTooSmall('\$2.00'));
    expect(display.minimumIsError, isTrue);
    expect(_createRequest(tester).onPressed, isNull);

    tester.widget<AmountKeypad>(find.byType(AmountKeypad)).onChanged('2');
    await tester.pump();
    final ok = tester.widget<BigAmountDisplay>(find.byType(BigAmountDisplay));
    expect(ok.minimumLabel, _l10n.amountMinimumInline('\$2.00'));
    expect(ok.minimumIsError, isFalse);
    expect(_createRequest(tester).onPressed, isNotNull);
    expect(quoted, isEmpty);
    await _unmount(tester);
  });

  testWidgets(
      'Dollars: "Create request" quotes a one-time address into spark:USDB, '
      'own Spark recipient and own EVM refund, persists the pending quote '
      'and shows the exact amount and the expiry', (tester) async {
    await _pump(tester);
    await _requestUsdt(tester, '25');
    await tester
        .tap(find.widgetWithText(AppButton, _l10n.receiveCreateRequest));
    await _settle(tester);
    await _settle(tester);

    final request = quoted.single;
    expect(request.sourceChain, 'ethereum');
    expect(request.sourceAsset, 'USDT');
    expect(request.destinationChain, 'spark');
    expect(request.destinationAsset, 'USDB');
    expect(request.amountBaseUnits, BigInt.from(25000000));
    expect(request.recipientAddress, _spark);
    expect(request.recipientKind, RecipientKind.ownSpark);
    expect(request.ownAddress, _spark);
    expect(request.refundAddress, _ownEvm);
    expect(request.refundOptional, isFalse);

    // The pending quote is persisted before the address is on screen; it
    // is not an Activity row (the screen writes nothing else).
    final row = recorded.single;
    expect(row.id, 'q_onetime_1');
    expect(row.coinTo, 'USDB');
    expect(row.networkTo, 'SPARK');
    expect(row.status, 'wait');
    expect(row.purchaseSource, 'crypto_receive');
    expect(row.activityDirection, 'receive');
    expect(row.refundAddress, _ownEvm);
    expect(isOneTimeReceiveQuoteRow(row), isTrue);

    // The address screen: the code, the exact amount, the network
    // warning, the expiry and what arrives.
    expect(find.byType(QuotedReceiveScreen), findsOneWidget);
    expect(
        find.byWidgetPredicate(
            (w) => w is ReceiveAddressLine && w.address == _deposit),
        findsOneWidget);
    expect(
        find.text(_l10n.quotedReceiveExactAmount('25 USDT')), findsOneWidget);
    expect(find.text(_l10n.usdReceiveShareSubtitle('USDT', 'ethereum')),
        findsOneWidget);
    expect(find.textContaining('Expires in'), findsOneWidget);
    // The Kute fee is charged but never shown under a receive address.
    expect(find.text(_l10n.feeUiKuteFee), findsNothing);
    expect(find.text(_l10n.quotedReceiveExpectedOutput('\$24.80')),
        findsOneWidget);
    expect(find.text('0.50%'), findsNothing);

    final generated =
        events.where((e) => e.$1 == 'receive_address_generated').single.$2!;
    expect(generated['address_kind'], 'onetime');
    expect(generated['destination'], 'spark_usd');
    expect(generated['amount_usd'], 25.0);
    expect(generated['min_deposit_usd'], 2.0);
    expect(generated['kute_fee_bps'], 50);
    expect(generated['quote_expiry_seconds'], greaterThan(100));
    expect(generated.keys, isNot(contains('address')));
    expect(generated.keys, isNot(contains('quote_id')));

    // No standing or legacy address was asked for.
    expect(standingCalls, isEmpty);
    await _unmount(tester);
  });

  testWidgets(
      'Bitcoin other coins: the amount in the receive unit, a one-time quote '
      'into spark:BTC', (tester) async {
    await _pump(tester, bitcoin: true);
    // The person's receive unit, sats: 50,000 sats at $60,000 is $30.
    await _requestUsdt(tester, '50000');
    expect(
        tester
            .widget<RequestAmountSheet>(find.byType(RequestAmountSheet))
            .fixedCurrency,
        isNull);
    await tester
        .tap(find.widgetWithText(AppButton, _l10n.receiveCreateRequest));
    await _settle(tester);
    await _settle(tester);
    final request = quoted.single;
    expect(request.destinationAsset, 'BTC');
    expect(request.amountBaseUnits, BigInt.from(30000000));
    expect(request.refundAddress, _ownEvm);
    expect(recorded.single.coinTo, 'BTC');
    final generated =
        events.where((e) => e.$1 == 'receive_address_generated').single.$2!;
    expect(generated['destination'], 'spark_btc');
    expect(generated['entry_source'], 'bitcoin_receive');
    expect(standingCalls, isEmpty);
    await _unmount(tester);
  });

  Future<void> createUsdtRequest(WidgetTester tester) async {
    await _requestUsdt(tester, '25');
    await tester
        .tap(find.widgetWithText(AppButton, _l10n.receiveCreateRequest));
    await _settle(tester);
    await _settle(tester);
  }

  Finder addressLine() => find.byWidgetPredicate(
      (w) => w is ReceiveAddressLine && w.address == _deposit);

  testWidgets(
      'a reconnect after the address is shown (a rebuilt SDK) keeps the '
      'address and never says the account changed', (tester) async {
    await _pump(tester);
    await createUsdtRequest(tester);
    expect(addressLine(), findsOneWidget);

    _reconnect();
    await _settle(tester);
    // The 1-second ticker runs on.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(_l10n.quotedReceiveWalletChanged), findsNothing);
    expect(addressLine(), findsOneWidget);
    expect(find.textContaining('Expires in'), findsOneWidget);
    expect(quoted, hasLength(1));
    await _unmount(tester);
  });

  testWidgets(
      'a reconnect while the quote is made quietly starts it again on the '
      'new SDK', (tester) async {
    var reconnected = false;
    await _pump(tester, wrapper: _newWrapper(onReceive: () {
      if (reconnected) return;
      reconnected = true;
      _reconnect();
    }));
    await createUsdtRequest(tester);
    await _settle(tester);
    expect(reconnected, isTrue);
    expect(find.text(_l10n.quotedReceiveWalletChanged), findsNothing);
    // Only the attempt on the new SDK was quoted and shown.
    expect(quoted, hasLength(1));
    expect(recorded, hasLength(1));
    expect(addressLine(), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a real wallet switch still ends the address', (tester) async {
    await _pump(tester);
    await createUsdtRequest(tester);
    expect(addressLine(), findsOneWidget);

    _settings.switchTo('other');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(_l10n.quotedReceiveWalletChanged), findsOneWidget);
    expect(addressLine(), findsNothing);
    await _unmount(tester);
  });
}
