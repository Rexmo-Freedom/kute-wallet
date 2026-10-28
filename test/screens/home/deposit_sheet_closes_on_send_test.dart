// The plain Bitcoin → Investments door (no order attached) closes the
// moment the bitcoin has left (founder, 15 October 2026: "it should just
// be when its in progress right? and then exit it"): the sheet never waits
// for the Orchestra order to complete. The Activity row and the header
// follow the conversion from there.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/helpers/orchestra_router.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/home/components/deposit_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart' show Fixed;

import '../../helpers/runtime_policy_fixture.dart';

const _usdPerBtc = 100000.0;
const _balanceSats = 100000; // $100.00 at the sample price.
const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _depositSpark =
    'spark1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc489gg2';

/// Orchestra's price sample: a flat route.
MockClient _orchestra() => MockClient((request) async {
      if (!request.url.path.endsWith('/estimate')) {
        return http.Response('{}', 404);
      }
      final asset = request.url.queryParameters['destinationAsset']!;
      final chain = request.url.queryParameters['destinationChain']!;
      final sats = int.tryParse(request.url.queryParameters['amount'] ?? '') ??
          _balanceSats;
      final out =
          doubleToOrchestraAmount(sats / 1e8 * _usdPerBtc, asset, chain: chain);
      return http.Response(
          jsonEncode({'estimatedOut': out, 'feeAmount': '0', 'feeBps': 0}),
          200);
    });

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency()
      : super(CurrencyState({'USD': Fixed.fromInt(_usdPerBtc.round())}));

  @override
  Future<void> updateRates() async {}
}

class _Trading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async => PolymarketTradingState(
      walletAddress: '0xeoa', proxyWalletAddress: '0xproxy');
}

class _Settings extends SettingsModel {
  _Settings()
      : super(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: 'Blockstream',
          reviewDone: true,
          wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          activeWalletId: 'spending',
        ));
}

/// What the leg returns once its sats left: the order is not registered
/// yet and Orchestra has not converted anything.
BitcoinLegSent _sent(Future<String?> registration) {
  final request = OrchestraQuoteRequest(
    sourceChain: 'spark',
    sourceAsset: 'BTC',
    destinationChain: 'spark',
    destinationAsset: 'USDB',
    amountBaseUnits: BigInt.from(5000),
    recipientAddress: _ownSpark,
    refundAddress: _ownSpark,
    recipientKind: RecipientKind.ownSpark,
    ownAddress: _ownSpark,
  );
  final quote = verifyOrchestraQuote(
    request,
    OrchestraQuote.fromJson({
      'quoteId': 'q_move',
      'depositAddress': _depositSpark,
      'amountIn': '5000',
      'estimatedOut': '5000000',
      'feeAmount': '0',
      'feeBps': 0,
      'totalFeeAmount': '0',
      'feeAsset': 'USDB',
      'route': ['spark:BTC', 'spark:USDB'],
      'expiresAt': '2026-10-15T12:02:00Z',
      'priceLockMode': 'floating',
    }),
    now: DateTime.utc(2026, 10, 15, 12),
    bounds: OrchestraQuoteBounds.forSource('spark',
        inputValueInOutputUnits: 5000000),
    mainnet: true,
  );
  return BitcoinLegSent(
    settled: SettlementRunResult(
      operation: SettlementOperation(
        operationId: 'op-move',
        walletId: 'spending',
        accountKind: SettlementAccountKind.sparkHot,
        flow: SettlementFlow.moveBtcToUsdc,
        route: BitcoinToDollarsLeg.route,
        amountInBaseUnits: '5000',
        stage: SettlementStage.funded,
        createdAt: DateTime.utc(2026, 10, 15),
        updatedAt: DateTime.utc(2026, 10, 15),
      ),
      quote: quote,
      proof: const SettlementFundingProof.spark('pay_1'),
      orderId: null,
      registration: registration,
    ),
    sats: 5000,
    estimatedOutUsd: 5,
    minOutUsd: 5,
  );
}

Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  setUp(() {
    AffiliateService.debugSessionToken = 'test-session';
    RuntimeCapabilitiesService.debugInstance = runtimePolicyFixture();
  });
  tearDown(() {
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
    SharedHttpClient.debugOverride = null;
    debugBitcoinToDollarsSend = null;
  });

  testWidgets(
      'the plain Bitcoin → Investments sheet closes once the bitcoin left, '
      'never waiting for the conversion', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The leg: answers once its sats left; the registration (and the
    // Orchestra order behind it) never finishes in this test.
    final left = Completer<BitcoinLegSent>();
    final registration = Completer<String?>();
    var sending = 0;
    debugBitcoinToDollarsSend = ({required approxUsd, required onSending}) {
      sending++;
      onSending();
      return left.future;
    };
    var completed = 0;

    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((_) => _Settings()),
      currencyProvider.overrideWith((_) => _Currency()),
      polymarketTradingProvider.overrideWith(_Trading.new),
      polymarketBalanceProvider.overrideWith((_) => 0),
      sparkBitcoinBalanceProvider.overrideWith((ref) async => BigInt.from(ref
              .watch(walletBalanceCacheProvider)['spending']
              ?.sparkBitcoinbalance ??
          0)),
      breezSDKProvider.overrideWith((_) => Completer<BreezSdkSpark>().future),
      usdBalanceProvider.overrideWith((_) => 0),
      sparkSelfAddressProvider.overrideWith((_) async => _ownSpark),
      venueCashPullerProvider.overrideWith((_) => VenueCashPuller(
          sources: const [], readDollars: () => 0, minimumUsd: (_) async => 1)),
    ]);
    container.read(walletBalanceCacheProvider.notifier).setBalance('spending',
        WalletBalance(onChainBtcBalance: 0, sparkBitcoinbalance: _balanceSats));
    SharedHttpClient.debugOverride = _orchestra();
    await http.runWithClient(
      () => tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            theme: buildLightTheme()
                .copyWith(splashFactory: NoSplash.splashFactory),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    key: const ValueKey('open'),
                    onPressed: () => showDepositSheet(
                      context,
                      lockedSide: MoveLockedSide.depositToUsd,
                      initialTargetUsd: 5,
                      onCompleted: () => completed++,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      )),
      _orchestra,
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await _frames(tester);
    expect(find.byType(DepositSheet), findsOneWidget);

    await tester.tap(find.byType(AppButton).last);
    await _frames(tester);
    // The sats are on their way: the sheet waits only for that.
    expect(sending, 1);
    expect(find.byType(DepositSheet), findsOneWidget);

    // They left. Orchestra has not even registered the order: the sheet
    // closes anyway, and the confirmation says the transfer is on its way.
    left.complete(_sent(registration.future));
    await _frames(tester, 20);
    expect(find.byType(DepositSheet), findsNothing);
    expect(completed, 1);
    expect(registration.isCompleted, isFalse);
    expect(find.text('Sent. Registering your transfer.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(minutes: 3));
  });
}
