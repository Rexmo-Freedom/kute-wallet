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

class _BitcoinAddress extends Mock implements BitcoinAddressDetails {}

class _LnurlRequest extends Mock implements LnurlPayRequestDetails {}

class _LnurlPrepared extends Mock implements PrepareLnurlPayResponse {}

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
}

SendOnchainSpeedFeeQuote _speed(int user, int l1) => SendOnchainSpeedFeeQuote(
    userFeeSat: BigInt.from(user), l1BroadcastFeeSat: BigInt.from(l1));

final _quote = SendOnchainFeeQuote(
  id: 'quote',
  expiresAt: BigInt.from(4102444800),
  speedFast: _speed(300, 900),
  speedMedium: _speed(200, 600),
  speedSlow: _speed(100, 300),
  isEstimate: false,
);

PrepareSendPaymentResponse _onchain(int amount, FeePolicy policy) =>
    PrepareSendPaymentResponse(
      paymentMethod: SendPaymentMethod.bitcoinAddress(
          address: _BitcoinAddress(), feeQuote: _quote),
      amount: BigInt.from(amount),
      feePolicy: policy,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Spark fee and 100% arithmetic', () {
    test('on-chain fee is the service fee plus the L1 broadcast fee', () {
      expect(sparkOnchainFeeSats(_quote, OnchainConfirmationSpeed.fast), 1200);
      expect(sparkOnchainFeeSats(_quote, OnchainConfirmationSpeed.medium), 800);
      expect(sparkOnchainFeeSats(_quote, OnchainConfirmationSpeed.slow), 400);
    });

    test('the picker splits each speed into the network and service fee it pays',
        () {
      // The service fee is quoted per speed (300 / 200 / 100 here); the
      // picker used to show the fast one under every speed.
      final service = sparkOnchainServiceFeesBySpeed(_quote);
      expect(service, {
        OnchainConfirmationSpeed.fast: 300,
        OnchainConfirmationSpeed.medium: 200,
        OnchainConfirmationSpeed.slow: 100,
      });
      final network = {
        OnchainConfirmationSpeed.fast: _quote.speedFast.l1BroadcastFeeSat,
        OnchainConfirmationSpeed.medium: _quote.speedMedium.l1BroadcastFeeSat,
        OnchainConfirmationSpeed.slow: _quote.speedSlow.l1BroadcastFeeSat,
      };
      for (final speed in OnchainConfirmationSpeed.values) {
        expect(service[speed]! + network[speed]!.toInt(),
            sparkOnchainFeeSats(_quote, speed));
      }
    });

    test('a fees-included drain delivers the balance less the chosen speed fee',
        () {
      final prepared = _onchain(100000, FeePolicy.feesIncluded);
      expect(
          sparkPreparedRecipientSats(prepared, OnchainConfirmationSpeed.medium),
          99200);
      expect(sparkPreparedRecipientSats(prepared, OnchainConfirmationSpeed.fast),
          98800);
    });

    test('a fees-excluded send delivers exactly its amount', () {
      final prepared = _onchain(50000, FeePolicy.feesExcluded);
      expect(sparkPreparedRecipientSats(prepared, OnchainConfirmationSpeed.fast),
          50000);
    });

    test('a Spark address drain takes its transfer fee out of the balance', () {
      final prepared = PrepareSendPaymentResponse(
        paymentMethod: SendPaymentMethod.sparkAddress(
            address: 'spark1test', fee: BigInt.from(7)),
        amount: BigInt.from(1000),
        feePolicy: FeePolicy.feesIncluded,
      );
      expect(sparkPreparedRecipientSats(prepared, OnchainConfirmationSpeed.fast),
          993);
    });

    test('the recipient amount is never negative', () {
      final prepared = _onchain(500, FeePolicy.feesIncluded);
      expect(sparkPreparedRecipientSats(prepared, OnchainConfirmationSpeed.fast),
          0);
    });

    test('an LNURL drain is capped at the recipient maximum', () {
      final cap = BigInt.from(50000 * 1000);
      expect(lnurlDrainAmountSats(80000, cap), 50000);
      expect(lnurlDrainAmountSats(30000, cap), 30000);
      // A zero cap is no cap.
      expect(lnurlDrainAmountSats(30000, BigInt.zero), 30000);
    });
  });

  group('100% preparation', () {
    late _Sdk sdk;
    late _Wrapper wrapper;
    late ProviderContainer container;
    var syncFails = false;

    setUpAll(() {
      registerFallbackValue(PrepareSendPaymentRequest(
          paymentRequest: const PaymentRequest.input(input: 'x')));
      registerFallbackValue(PrepareLnurlPayRequest(
          payRequest: _LnurlRequest(), amount: BigInt.one));
      registerFallbackValue(const SyncWalletRequest());
      registerFallbackValue(const GetInfoRequest());
    });

    setUp(() {
      sdk = _Sdk();
      wrapper = _Wrapper();
      syncFails = false;
      when(() => wrapper.instance).thenAnswer((_) => sdk);
      when(() => sdk.syncWallet(request: any(named: 'request')))
          .thenAnswer((_) async {
        if (syncFails) throw Exception('offline');
        return const SyncWalletResponse();
      });
      when(() => sdk.getInfo(request: any(named: 'request'))).thenAnswer(
          (_) async => GetInfoResponse(
              identityPubkey: 'pk',
              balanceSats: BigInt.from(100000),
              tokenBalances: const {}));
      container = ProviderContainer(overrides: [
        settingsProvider.overrideWith((_) => _Settings()),
        breezSDKProvider.overrideWith((_) async => wrapper),
      ]);
    });
    tearDown(() => container.dispose());

    for (final syncFailure in [false, true]) {
      test(
          'on-chain 100% sends the synced balance with fees included; '
          'sync failure=$syncFailure', () async {
        syncFails = syncFailure;
        when(() => sdk.parse(input: any(named: 'input'))).thenAnswer(
            (_) async => InputType.bitcoinAddress(_BitcoinAddress()));
        when(() => sdk.prepareSendPayment(request: any(named: 'request')))
            .thenAnswer((_) async => _onchain(100000, FeePolicy.feesIncluded));

        final prepared = await container.read(prepareGenericPaymentProvider((
          destination: 'bc1qtest',
          // The placeholder the chip wrote; a drain ignores it.
          amountSats: 0,
          isDraining: true,
        )).future);

        verify(() => sdk.syncWallet(request: any(named: 'request'))).called(1);
        final request = verify(() =>
                sdk.prepareSendPayment(request: captureAny(named: 'request')))
            .captured
            .single as PrepareSendPaymentRequest;
        expect(request.amount, BigInt.from(100000));
        expect(request.feePolicy, FeePolicy.feesIncluded);
        expect(
            sparkPreparedRecipientSats(prepared, OnchainConfirmationSpeed.slow),
            99600);
      });
    }

    test('a typed on-chain amount is sent as typed, fees on top', () async {
      when(() => sdk.parse(input: any(named: 'input'))).thenAnswer(
          (_) async => InputType.bitcoinAddress(_BitcoinAddress()));
      when(() => sdk.prepareSendPayment(request: any(named: 'request')))
          .thenAnswer((_) async => _onchain(40000, FeePolicy.feesExcluded));
      await container.read(prepareGenericPaymentProvider((
        destination: 'bc1qtest',
        amountSats: 40000,
        isDraining: false,
      )).future);
      final request = verify(() =>
              sdk.prepareSendPayment(request: captureAny(named: 'request')))
          .captured
          .single as PrepareSendPaymentRequest;
      expect(request.amount, BigInt.from(40000));
      expect(request.feePolicy, isNull);
      verifyNever(() => sdk.syncWallet(request: any(named: 'request')));
    });

    test('LNURL 100% above the recipient maximum asks for the maximum',
        () async {
      final payRequest = _LnurlRequest();
      when(() => payRequest.maxSendable).thenReturn(BigInt.from(60000 * 1000));
      when(() => sdk.parse(input: any(named: 'input')))
          .thenAnswer((_) async => InputType.lnurlPay(payRequest));
      final prepared = _LnurlPrepared();
      when(() => prepared.feeSats).thenReturn(BigInt.from(12));
      when(() => sdk.prepareLnurlPay(request: any(named: 'request')))
          .thenAnswer((_) async => prepared);

      await container.read(prepareLightningPaymentProvider((
        address: 'lnurl-test',
        amount: 0,
        comment: null,
        isDraining: true,
      )).future);

      final request = verify(
              () => sdk.prepareLnurlPay(request: captureAny(named: 'request')))
          .captured
          .single as PrepareLnurlPayRequest;
      expect(request.amount, BigInt.from(60000));
      expect(request.feePolicy, FeePolicy.feesIncluded);
    });

    test('LNURL 100% below the recipient maximum asks for the whole balance',
        () async {
      final payRequest = _LnurlRequest();
      when(() => payRequest.maxSendable)
          .thenReturn(BigInt.from(1000000 * 1000));
      when(() => sdk.parse(input: any(named: 'input')))
          .thenAnswer((_) async => InputType.lnurlPay(payRequest));
      final prepared = _LnurlPrepared();
      when(() => prepared.feeSats).thenReturn(BigInt.from(12));
      when(() => sdk.prepareLnurlPay(request: any(named: 'request')))
          .thenAnswer((_) async => prepared);

      await container.read(prepareLightningPaymentProvider((
        address: 'lnurl-test',
        amount: 0,
        comment: null,
        isDraining: true,
      )).future);

      final request = verify(
              () => sdk.prepareLnurlPay(request: captureAny(named: 'request')))
          .captured
          .single as PrepareLnurlPayRequest;
      expect(request.amount, BigInt.from(100000));
      expect(request.feePolicy, FeePolicy.feesIncluded);
    });

    test('amountless invoice 100% sends the synced balance, fees included',
        () async {
      final invoice = _Invoice();
      when(() => invoice.amountMsat).thenReturn(null);
      when(() => invoice.invoice).thenReturn(const Bolt11Invoice(
          bolt11: 'lnbc-test', source: PaymentRequestSource()));
      when(() => sdk.parse(input: any(named: 'input')))
          .thenAnswer((_) async => InputType.bolt11Invoice(invoice));
      when(() => sdk.prepareSendPayment(request: any(named: 'request')))
          .thenAnswer((_) async => PrepareSendPaymentResponse(
                paymentMethod: SendPaymentMethod.bolt11Invoice(
                    invoiceDetails: invoice, lightningFeeSats: BigInt.from(5)),
                amount: BigInt.from(100000),
                feePolicy: FeePolicy.feesIncluded,
              ));
      await container.read(prepareLightningPaymentProvider((
        address: 'lnbc-test',
        amount: 0,
        comment: null,
        isDraining: true,
      )).future);
      verify(() => sdk.syncWallet(request: any(named: 'request'))).called(1);
      final request = verify(() =>
              sdk.prepareSendPayment(request: captureAny(named: 'request')))
          .captured
          .single as PrepareSendPaymentRequest;
      expect(request.amount, BigInt.from(100000));
      expect(request.feePolicy, FeePolicy.feesIncluded);
    });
  });
}

class _Invoice extends Mock implements Bolt11InvoiceDetails {}
