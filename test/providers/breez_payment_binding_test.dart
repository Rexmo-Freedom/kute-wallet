import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:mocktail/mocktail.dart';

class _Sdk extends Mock implements BreezSdk {}

class _Wrapper extends Mock implements BreezSdkSpark {}

class _LnurlRequest extends Mock implements LnurlPayRequestDetails {}

class _LnurlPrepared extends Mock implements PrepareLnurlPayResponse {}

class _LnurlResult extends Mock implements LnurlPayResponse {}

class _Invoice extends Mock implements Bolt11InvoiceDetails {}

class _BitcoinAddress extends Mock implements BitcoinAddressDetails {}

class _OnchainFees extends Mock implements SendOnchainFeeQuote {}

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
          reviewDone: false,
          wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          activeWalletId: 'spending',
        ));

  void replaceWallet() {
    state = state.copyWith(
      wallets: [WalletConfig(id: 'replacement', name: 'Replacement')],
      activeWalletId: 'replacement',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const address = 'spark-test-recipient';
  final invoiceAmount = BigInt.from(2500);
  final sparkInvoice = SparkInvoiceDetails(
    invoice: address,
    identityPublicKey: 'test-key',
    network: BitcoinNetwork.bitcoin,
    amount: invoiceAmount,
  );
  final sparkPreparation = PrepareSendPaymentResponse(
    paymentMethod: SendPaymentMethod.sparkInvoice(
        sparkInvoiceDetails: sparkInvoice, fee: BigInt.one),
    amount: invoiceAmount,
    feePolicy: FeePolicy.feesExcluded,
  );
  final result = SendPaymentResponse(
      payment: Payment(
    id: 'sent',
    paymentType: PaymentType.send,
    status: PaymentStatus.completed,
    amount: invoiceAmount,
    fees: BigInt.one,
    timestamp: BigInt.one,
    method: PaymentMethod.spark,
  ));
  setUpAll(() {
    registerFallbackValue(PrepareSendPaymentRequest(
        paymentRequest: const PaymentRequest.input(input: address)));
    registerFallbackValue(
        SendPaymentRequest(prepareResponse: sparkPreparation));
    registerFallbackValue(PrepareLnurlPayRequest(
        payRequest: _LnurlRequest(), amount: invoiceAmount));
    registerFallbackValue(LnurlPayRequest(prepareResponse: _LnurlPrepared()));
  });

  late _Sdk sdk;
  late _Wrapper wrapper;
  late _Settings settings;
  late ProviderContainer container;
  BreezSdk? activeSdk;
  void Function()? duringPreparation;
  late PrepareSendPaymentResponse sdkPreparation;

  setUp(() {
    sdk = _Sdk();
    wrapper = _Wrapper();
    settings = _Settings();
    activeSdk = sdk;
    duringPreparation = null;
    sdkPreparation = sparkPreparation;
    when(() => wrapper.instance).thenAnswer((_) => activeSdk);
    when(() => sdk.parse(input: any(named: 'input')))
        .thenAnswer((_) async => InputType.sparkInvoice(sparkInvoice));
    when(() => sdk.prepareSendPayment(request: any(named: 'request')))
        .thenAnswer((_) async {
      await Future<void>.value();
      duringPreparation?.call();
      return sdkPreparation;
    });
    when(() => sdk.sendPayment(request: any(named: 'request')))
        .thenAnswer((_) async => result);
    container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((_) => settings),
      breezSDKProvider.overrideWith((_) async => wrapper),
    ]);
  });
  tearDown(() => container.dispose());

  Future<PrepareSendPaymentResponse> prepareSpark(
          {bool drain = false, int enteredAmount = 100}) =>
      container.read(prepareGenericPaymentProvider((
        destination: address,
        amountSats: enteredAmount,
        isDraining: drain
      )).future);

  for (final drain in [false, true]) {
    test('fixed Spark invoice overrides entered amount, including drain=$drain',
        () async {
      final prepared = await prepareSpark(drain: drain);
      final request = verify(() =>
              sdk.prepareSendPayment(request: captureAny(named: 'request')))
          .captured
          .single as PrepareSendPaymentRequest;
      expect(request.amount, invoiceAmount);
      expect(request.feePolicy, isNull);
      expect(prepared.amount, invoiceAmount);
      expect(
          await container
              .read(executeSparkTransactionProvider(prepared).future),
          result);
      final sent =
          verify(() => sdk.sendPayment(request: captureAny(named: 'request')))
              .captured
              .single as SendPaymentRequest;
      expect(identical(sent.prepareResponse, prepared), isTrue);
    });
  }

  test('a stale amount above balance cannot override a smaller fixed invoice',
      () async {
    final prepared = await prepareSpark(enteredAmount: 999999);
    final request = verify(
            () => sdk.prepareSendPayment(request: captureAny(named: 'request')))
        .captured
        .single as PrepareSendPaymentRequest;
    expect(request.amount, invoiceAmount);
    expect(prepared.amount, invoiceAmount);
    verifyNever(() => sdk.getInfo(request: const GetInfoRequest()));
  });

  for (final replaceSdk in [false, true]) {
    test('onchain execution retains its prepared signer; replaced=$replaceSdk',
        () async {
      final recipient = _BitcoinAddress();
      when(() => sdk.parse(input: any(named: 'input')))
          .thenAnswer((_) async => InputType.bitcoinAddress(recipient));
      sdkPreparation = PrepareSendPaymentResponse(
          paymentMethod: SendPaymentMethod.bitcoinAddress(
              address: recipient, feeQuote: _OnchainFees()),
          amount: BigInt.from(100),
          feePolicy: FeePolicy.feesExcluded);
      final prepared = await prepareSpark();
      if (replaceSdk) activeSdk = _Sdk();
      final send = container.read(executeOnchainTransactionProvider(
              (prepareResponse: prepared, speed: OnchainConfirmationSpeed.fast))
          .future);
      if (replaceSdk) {
        await expectLater(send, throwsException);
        verifyNever(() => sdk.sendPayment(request: any(named: 'request')));
      } else {
        await send;
        final sent =
            verify(() => sdk.sendPayment(request: captureAny(named: 'request')))
                .captured
                .single as SendPaymentRequest;
        expect(identical(sent.prepareResponse, prepared), isTrue);
      }
    });
  }

  test('wallet replacement during preparation refuses the prepared payment',
      () async {
    duringPreparation = settings.replaceWallet;
    await expectLater(prepareSpark(), throwsException);
    verifyNever(() => sdk.sendPayment(request: any(named: 'request')));
  });

  for (final changed in ['wallet', 'sdk', 'disconnect']) {
    test('Spark $changed change after review cannot use another signer',
        () async {
      final prepared = await prepareSpark();
      if (changed == 'wallet') {
        settings.replaceWallet();
      } else {
        activeSdk = changed == 'sdk' ? _Sdk() : null;
      }
      await expectLater(
          container.read(executeSparkTransactionProvider(prepared).future),
          throwsException);
      verifyNever(() => sdk.sendPayment(request: any(named: 'request')));
    });
  }

  test('an unbound or copied preparation cannot bypass wallet binding',
      () async {
    final unbound = PrepareSendPaymentResponse(
        paymentMethod: sparkPreparation.paymentMethod,
        amount: invoiceAmount,
        feePolicy: FeePolicy.feesExcluded);
    await expectLater(
        container.read(executeSparkTransactionProvider(unbound).future),
        throwsException);
    verifyNever(() => sdk.sendPayment(request: any(named: 'request')));
  });

  for (final changeWallet in [false, true]) {
    test(
        'fixed Lightning invoice uses its amount; wallet replacement=$changeWallet',
        () async {
      final invoice = _Invoice();
      when(() => invoice.amountMsat)
          .thenReturn(invoiceAmount * BigInt.from(1000));
      when(() => invoice.invoice).thenReturn(const Bolt11Invoice(
          bolt11: 'test-lightning-invoice', source: PaymentRequestSource()));
      when(() => sdk.parse(input: any(named: 'input')))
          .thenAnswer((_) async => InputType.bolt11Invoice(invoice));
      sdkPreparation = PrepareSendPaymentResponse(
          paymentMethod: SendPaymentMethod.bolt11Invoice(
              invoiceDetails: invoice, lightningFeeSats: BigInt.one),
          amount: invoiceAmount,
          feePolicy: FeePolicy.feesExcluded);
      final prepared = await container.read(prepareLightningPaymentProvider((
        address: 'test-lightning-invoice',
        amount: 100,
        comment: null,
        isDraining: true
      )).future);
      final request = verify(() =>
              sdk.prepareSendPayment(request: captureAny(named: 'request')))
          .captured
          .single as PrepareSendPaymentRequest;
      expect(request.amount, isNull); // The SDK reads the fixed invoice amount.
      expect(request.feePolicy, isNull);
      expect((prepared.prepareResponse as PrepareSendPaymentResponse).amount,
          invoiceAmount);
      if (changeWallet) settings.replaceWallet();
      final send = container.read(
          executeLightningPaymentProvider(prepared.prepareResponse).future);
      if (changeWallet) {
        await expectLater(send, throwsException);
        verifyNever(() => sdk.sendPayment(request: any(named: 'request')));
      } else {
        await send;
        final sent =
            verify(() => sdk.sendPayment(request: captureAny(named: 'request')))
                .captured
                .single as SendPaymentRequest;
        expect(
            identical(sent.prepareResponse, prepared.prepareResponse), isTrue);
      }
    });
  }

  for (final replaceSdk in [false, true]) {
    test('LNURL executes only its original SDK; replaced=$replaceSdk',
        () async {
      final request = _LnurlRequest();
      final prepared = _LnurlPrepared();
      when(() => prepared.feeSats).thenReturn(BigInt.one);
      when(() => prepared.amountSats).thenReturn(invoiceAmount);
      when(() => sdk.parse(input: any(named: 'input')))
          .thenAnswer((_) async => InputType.lnurlPay(request));
      when(() => sdk.prepareLnurlPay(request: any(named: 'request')))
          .thenAnswer((_) async => prepared);
      when(() => sdk.lnurlPay(request: any(named: 'request')))
          .thenAnswer((_) async => _LnurlResult());
      final response = await container.read(prepareLightningPaymentProvider((
        address: 'test-lnurl',
        amount: 2500,
        comment: null,
        isDraining: false
      )).future);
      if (replaceSdk) activeSdk = _Sdk();
      final send = container.read(
          executeLightningPaymentProvider(response.prepareResponse).future);
      if (replaceSdk) {
        await expectLater(send, throwsException);
        verifyNever(() => sdk.lnurlPay(request: any(named: 'request')));
      } else {
        await send;
        final sent =
            verify(() => sdk.lnurlPay(request: captureAny(named: 'request')))
                .captured
                .single as LnurlPayRequest;
        expect(identical(sent.prepareResponse, prepared), isTrue);
      }
    });
  }
}
