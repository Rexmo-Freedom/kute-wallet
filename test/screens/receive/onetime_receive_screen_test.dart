// The one-time receive of another coin, end to end with the rails stubbed:
// a coin tapped in the Dollars receive (or the Bitcoin receive's "other
// coins") asks its amount in the Lightning "Request amount" sheet, checked
// against the route's minimum, then quotes a one-time Orchestra deposit
// address into spark:USDB (or spark:BTC), paid to the wallet's own Spark
// address and refunded to the return address the person gives in the step
// before (or to none when skipped; never the wallet's own EVM address),
// persists it as a pending
// quote (never an Activity row before a deposit), and shows the address
// with the exact amount and the expiry. It is the fallback of the
// reusable address: here the policy denies `orchestra.standing_addresses`,
// so no standing address is asked for (and no legacy one ever is), and
// every address says why it fell back. A reconnect (a rebuilt SDK) never
// ends the screen; a wallet switch does.

import 'dart:async';

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
import 'package:kute/screens/receive/onetime_refund_step.dart';
import 'package:kute/screens/receive/quoted_receive_screen.dart';
import 'package:kute/screens/receive/receive_sheet.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart'
    show AmountKeypad, BigAmountDisplay;
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/shared/custom_button.dart' show AppButton;
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show sendShortAddress;
import 'package:kute/services/orchestra/onetime_receive.dart';
import 'package:kute/services/orchestra/onetime_refund_address_store.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart'
    show kStandingAddressCapability;
import 'package:kute/services/orchestra/receive_minimums.dart';
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
const _refund = '0x2222222222222222222222222222222222222222';
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
    {bool bitcoin = false,
    _Wrapper? wrapper,
    ReceiveLimitsFetcher? fetch}) async {
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
      // The wallet's own EVM address is never a refund: reading it fails
      // the quote.
      hyperliquidAddressProvider.overrideWith(
          (_) async => throw StateError('own EVM address read: $_ownEvm')),
      // A live minimum of $2.00.
      receiveMinimumsProvider.overrideWithValue(ReceiveMinimums(
          fetch: fetch ??
              (_) async => const OrchestraRouteLimits(orderMinUsdCents: 200))),
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

final _refundField = find.descendant(
    of: find.byKey(const ValueKey('onetime-refund-address')),
    matching: find.byType(TextField));

AppButton _continueButton(WidgetTester tester) => tester
    .widget<AppButton>(find.widgetWithText(AppButton, _l10n.continueLabel));

/// "Create request", then the return-address step: [refund] typed and
/// Continue, or Skip when null.
Future<void> _createWithRefund(WidgetTester tester, String? refund) async {
  await tester.tap(find.widgetWithText(AppButton, _l10n.receiveCreateRequest));
  await _settle(tester);
  expect(find.byType(OneTimeRefundStep), findsOneWidget);
  if (refund == null) {
    await tester.tap(find.widgetWithText(AppButton, _l10n.skip));
  } else {
    await tester.enterText(_refundField, refund);
    await tester.pump();
    await tester.tap(find.widgetWithText(AppButton, _l10n.continueLabel));
  }
  await _settle(tester);
  await _settle(tester);
}

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
    // Standing denied: the one-time flow, with no standing request.
    final policy = runtimePolicyFixture(
        also: {kStandingAddressCapability},
        blocked: {kStandingAddressCapability});
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
    OneTimeRefundAddressStore.debugMemory = {};
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    TrackingService.debugTrackObserver = null;
    OneTimeReceive.debugFetch = null;
    OneTimeReceive.debugRecord = null;
    OneTimeRefundAddressStore.debugMemory = null;
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
      'own Spark recipient, refunded to the return address given, persists '
      'the pending quote and shows the exact amount and the expiry',
      (tester) async {
    await _pump(tester);
    await _requestUsdt(tester, '25');
    await _createWithRefund(tester, _refund);

    final request = quoted.single;
    expect(request.sourceChain, 'ethereum');
    expect(request.sourceAsset, 'USDT');
    expect(request.destinationChain, 'spark');
    expect(request.destinationAsset, 'USDB');
    expect(request.amountBaseUnits, BigInt.from(25000000));
    expect(request.recipientAddress, _spark);
    expect(request.recipientKind, RecipientKind.ownSpark);
    expect(request.ownAddress, _spark);
    expect(request.refundAddress, _refund);
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
    expect(row.refundAddress, _refund);
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
    // What arrives is not shown; the countdown sits above the QR.
    expect(
        find.text(_l10n.quotedReceiveExpectedOutput('\$24.80')), findsNothing);
    expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('onetime-receive-expiry')))
            .dy,
        lessThan(tester.getTopLeft(find.byType(ReceiveQrPlate)).dy));
    expect(find.text('0.50%'), findsNothing);
    // Where a failed deposit goes, shortened.
    expect(find.text(_l10n.quotedReceiveReturnsTo), findsOneWidget);
    expect(find.text(sendShortAddress(_refund)), findsOneWidget);

    final generated =
        events.where((e) => e.$1 == 'receive_address_generated').single.$2!;
    expect(generated['address_kind'], 'onetime');
    expect(generated['destination'], 'spark_usd');
    expect(generated['amount_usd'], 25.0);
    expect(generated['min_deposit_usd'], 2.0);
    expect(generated['kute_fee_bps'], 50);
    expect(generated['quote_expiry_seconds'], greaterThan(100));
    expect(generated['refund_address_set'], isTrue);
    expect(generated['fallback_reason'], 'standing_policy_off');
    expect(generated.keys, isNot(contains('address')));
    expect(generated.keys, isNot(contains('quote_id')));
    // Only whether a return address was set reaches analytics.
    final entered = events
        .where((e) => e.$1 == 'usd_receive_step')
        .map((e) => e.$2!)
        .where((p) => p['step'] == 'refund_address_entered')
        .single;
    expect(entered['refund_address_set'], isTrue);
    for (final e in events) {
      expect(e.$2?.values ?? const [], isNot(contains(_refund)), reason: e.$1);
    }

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
    await _createWithRefund(tester, _refund);
    final request = quoted.single;
    expect(request.destinationAsset, 'BTC');
    expect(request.amountBaseUnits, BigInt.from(30000000));
    expect(request.refundAddress, _refund);
    expect(recorded.single.coinTo, 'BTC');
    final generated =
        events.where((e) => e.$1 == 'receive_address_generated').single.$2!;
    expect(generated['destination'], 'spark_btc');
    expect(generated['entry_source'], 'bitcoin_receive');
    expect(generated['fallback_reason'], 'standing_policy_off');
    expect(standingCalls, isEmpty);
    await _unmount(tester);
  });

  testWidgets(
      'Bitcoin other coins: the standing route refused, the one-time quote '
      'into spark:BTC says so', (tester) async {
    // A policy that does not name the switch (an older backend): the
    // standing route is tried, and refused.
    final policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    final asked = <String>[];
    ReusableDepositAddressService.debugResolver = (
        {required sourceChain,
        required sourceAsset,
        required destinationAsset}) async {
      asked.add('$sourceChain:$sourceAsset:$destinationAsset');
      throw StandingUnavailableException(
          sourceChain: sourceChain,
          sourceAsset: sourceAsset,
          reason: StandingFallbackReason.standingRefused);
    };
    addTearDown(() => ReusableDepositAddressService.debugResolver = null);
    await _pump(tester, bitcoin: true);
    await tester.tap(find.widgetWithText(CoinAssetTile, 'USDT').first);
    await _settle(tester);
    await _settle(tester);
    expect(asked, ['ethereum:USDT:USDB']);
    expect(find.byType(RequestAmountSheet), findsOneWidget);
    tester.widget<AmountKeypad>(find.byType(AmountKeypad)).onChanged('50000');
    await tester.pump();
    await _createWithRefund(tester, _refund);
    expect(quoted.single.destinationAsset, 'BTC');
    final generated =
        events.where((e) => e.$1 == 'receive_address_generated').single.$2!;
    expect(generated['address_kind'], 'onetime');
    expect(generated['destination'], 'spark_btc');
    expect(generated['fallback_reason'], 'standing_refused');
    // Nothing from this address shows as a Dollars deposit in Bitcoin.
    expect(find.text(_l10n.moveDestDollarsSubtitle), findsNothing);
    await _unmount(tester);
  });

  Future<void> createUsdtRequest(WidgetTester tester) async {
    await _requestUsdt(tester, '25');
    await _createWithRefund(tester, _refund);
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

  testWidgets(
      'the amount sheet opens at once with no minimum line while the read '
      'is out; the grid already asked for it; the line follows the read',
      (tester) async {
    final reads = <RouteKey>[];
    final answer = Completer<OrchestraRouteLimits?>();
    await _pump(tester, fetch: (route) {
      reads.add(route);
      return answer.future;
    });
    // Shown the grid: its route's minimum is already being read.
    expect(reads.map((r) => '${r.fromChain}:${r.fromAsset}>${r.toAsset}'),
        ['ethereum:USDT>USDB']);

    await tester.tap(find.widgetWithText(CoinAssetTile, 'USDT').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(RequestAmountSheet), findsOneWidget);
    var display =
        tester.widget<BigAmountDisplay>(find.byType(BigAmountDisplay));
    expect(display.minimumLabel, isNull);

    // Flashnet's own minimum, under a dollar: no floor.
    answer.complete(const OrchestraRouteLimits(orderMinUsdCents: 75));
    await _settle(tester);
    display = tester.widget<BigAmountDisplay>(find.byType(BigAmountDisplay));
    expect(display.minimumLabel, _l10n.amountMinimumInline('\$0.75'));
    tester.widget<AmountKeypad>(find.byType(AmountKeypad)).onChanged('0.5');
    await tester.pump();
    display = tester.widget<BigAmountDisplay>(find.byType(BigAmountDisplay));
    expect(display.minimumLabel, _l10n.routeAmountTooSmall('\$0.75'));
    await _unmount(tester);
  });

  group('the return-address step', () {
    testWidgets(
        'Continue only for an address of the source network; a wrong one '
        'says so', (tester) async {
      await _pump(tester);
      await _requestUsdt(tester, '25');
      await tester
          .tap(find.widgetWithText(AppButton, _l10n.receiveCreateRequest));
      await _settle(tester);
      expect(find.text(_l10n.onetimeRefundTitle), findsOneWidget);
      expect(find.text(_l10n.onetimeRefundSubtitle('ethereum', 'USDT')),
          findsOneWidget);
      expect(find.text(_l10n.onetimeRefundSkipNote), findsOneWidget);
      // Nothing is filled in from the clipboard or the wallet.
      expect(tester.widget<TextField>(_refundField).controller!.text, isEmpty);
      expect(_continueButton(tester).onPressed, isNull);

      // A Spark address, a Bitcoin address, a Solana one: not Ethereum.
      for (final wrong in [
        _spark,
        'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq',
        '7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU',
      ]) {
        await tester.enterText(_refundField, wrong);
        await tester.pump();
        expect(find.text(_l10n.usdSendAddressWrongNetwork('ethereum')),
            findsOneWidget,
            reason: wrong);
        expect(_continueButton(tester).onPressed, isNull, reason: wrong);
      }
      await tester.enterText(_refundField, _refund);
      await tester.pump();
      expect(find.text(_l10n.usdSendAddressWrongNetwork('ethereum')),
          findsNothing);
      expect(_continueButton(tester).onPressed, isNotNull);
      expect(quoted, isEmpty, reason: 'no quote before the step is done');
      await _unmount(tester);
    });

    testWidgets(
        'Skip quotes with no return address, says nothing of one, and '
        'records only that none was set', (tester) async {
      await _pump(tester);
      await _requestUsdt(tester, '25');
      await _createWithRefund(tester, null);
      final request = quoted.single;
      expect(request.refundAddress, isEmpty);
      expect(request.refundOptional, isTrue);
      expect(recorded.single.refundAddress, isEmpty);
      expect(find.text(_l10n.quotedReceiveReturnsTo), findsNothing);
      final generated =
          events.where((e) => e.$1 == 'receive_address_generated').single.$2!;
      expect(generated['refund_address_set'], isFalse);
      expect(
          events.any((e) =>
              e.$1 == 'usd_receive_step' &&
              e.$2!['step'] == 'refund_address_skipped' &&
              e.$2!['refund_address_set'] == false),
          isTrue);
      expect(OneTimeRefundAddressStore.debugMemory, isEmpty);
      await _unmount(tester);
    });

    testWidgets(
        'the last return address for this wallet and network is filled in '
        'next time', (tester) async {
      await _pump(tester);
      await _requestUsdt(tester, '25');
      await _createWithRefund(tester, _refund);
      expect(await OneTimeRefundAddressStore.read('spending', 'ethereum'),
          _refund);
      // Closed, and a new receive started on the same network.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));

      await _pump(tester);
      await _requestUsdt(tester, '25');
      await tester
          .tap(find.widgetWithText(AppButton, _l10n.receiveCreateRequest));
      await _settle(tester);
      expect(tester.widget<TextField>(_refundField).controller!.text, _refund);
      expect(_continueButton(tester).onPressed, isNotNull);
      // Another network's is never used.
      expect(await OneTimeRefundAddressStore.read('spending', 'base'), isNull);
      await _unmount(tester);
    });
  });
}
