import 'dart:convert';
import 'dart:io';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/handlers/response_handlers.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/funding/hot_settlement.dart';
import 'package:kute/services/funding/owned_address_resolver.dart';
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/services/funding/settlement_funding_outcome.dart';
import 'package:kute/services/funding/settlement_quote_policy.dart';
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:mocktail/mocktail.dart';

const _spark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _recipient = '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359';
const _otherRecipient = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
final _now = DateTime.utc(2026, 9, 15, 12);

VerifiedOrchestraQuote _quote() {
  final raw = jsonDecode(
      File('test/services/fixtures/orchestra_quote_spark_to_polygon.json')
          .readAsStringSync()) as Map<String, dynamic>;
  return verifyOrchestraQuote(
    OrchestraQuoteRequest(
      sourceChain: 'spark',
      sourceAsset: 'BTC',
      destinationChain: 'polygon',
      destinationAsset: 'USDC.e',
      amountBaseUnits: BigInt.from(100000),
      recipientAddress: _recipient,
      refundAddress: _spark,
      recipientKind: RecipientKind.ownPmWallet,
      ownAddress: _recipient,
    ),
    OrchestraQuote.fromJson(raw),
    bounds: OrchestraQuoteBounds.forSource('spark',
        inputValueInOutputUnits: 60000000),
    now: _now,
    mainnet: true,
  );
}

class _Sdk extends Mock implements BreezSdk {}

class _Wrapper extends Mock implements BreezSdkSpark {}

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
  final quote = _quote();
  final preparation = PrepareSendPaymentResponse(
    paymentMethod: SendPaymentMethod.sparkAddress(
        address: quote.depositAddress, fee: BigInt.one),
    amount: quote.amountIn,
    feePolicy: FeePolicy.feesExcluded,
  );
  setUpAll(() {
    registerFallbackValue(SendPaymentRequest(prepareResponse: preparation));
  });

  group('Spark preparation binding', () {
    late _Sdk sdk;
    late _Wrapper wrapper;
    late _Settings settings;
    late ProviderContainer container;
    BreezSdk? activeSdk;
    void Function()? duringPreparation;
    late PrepareSendPaymentResponse preparedResponse;

    setUp(() {
      sdk = _Sdk();
      wrapper = _Wrapper();
      settings = _Settings();
      activeSdk = sdk;
      duringPreparation = null;
      preparedResponse = preparation;
      when(() => wrapper.instance).thenAnswer((_) => activeSdk);
      when(() => sdk.sendPayment(request: any(named: 'request'))).thenAnswer(
        (_) async => SendPaymentResponse(
          payment: Payment(
            id: 'payment-fixture',
            paymentType: PaymentType.send,
            status: PaymentStatus.completed,
            amount: quote.amountIn,
            fees: BigInt.one,
            timestamp: BigInt.one,
            method: PaymentMethod.spark,
          ),
        ),
      );
      container = ProviderContainer(overrides: [
        settingsProvider.overrideWith((_) => settings),
        breezSDKProvider.overrideWith((_) async => wrapper),
        prepareGenericPaymentProvider.overrideWith((_, params) async {
          expect(params.destination, quote.depositAddress);
          expect(params.amountSats, quote.amountIn.toInt());
          expect(params.isDraining, isFalse);
          await Future<void>.value();
          duringPreparation?.call();
          return preparedResponse;
        }),
      ]);
    });
    tearDown(() => container.dispose());

    test('sends the exact prepared response through its original SDK',
        () async {
      final prepared = await HotSettlement.prepareSpark(container.read, quote);
      expect(await HotSettlement.sendSpark(container.read, prepared),
          'payment-fixture');
      final sent =
          verify(() => sdk.sendPayment(request: captureAny(named: 'request')))
              .captured
              .single as SendPaymentRequest;
      expect(identical(sent.prepareResponse, preparation), isTrue);
    });

    test('wallet replacement during preparation never reaches send', () async {
      duringPreparation = settings.replaceWallet;
      await expectLater(HotSettlement.prepareSpark(container.read, quote),
          throwsA(isA<WalletGuardException>()));
      verifyNever(() => sdk.sendPayment(request: any(named: 'request')));
    });

    for (final change in ['wallet', 'sdk', 'disconnect']) {
      test('$change replacement after preparation never reaches send',
          () async {
        final prepared =
            await HotSettlement.prepareSpark(container.read, quote);
        if (change == 'wallet') {
          settings.replaceWallet();
        } else {
          activeSdk = change == 'sdk' ? _Sdk() : null;
        }
        await expectLater(HotSettlement.sendSpark(container.read, prepared),
            throwsA(isA<WalletGuardException>()));
        verifyNever(() => sdk.sendPayment(request: any(named: 'request')));
      });
    }

    for (final changedField in ['amount', 'recipient']) {
      test('SDK preparation cannot change reviewed $changedField', () async {
        preparedResponse = PrepareSendPaymentResponse(
          paymentMethod: SendPaymentMethod.sparkAddress(
              address:
                  changedField == 'recipient' ? _spark : quote.depositAddress,
              fee: BigInt.one),
          amount: changedField == 'amount'
              ? quote.amountIn + BigInt.one
              : quote.amountIn,
          feePolicy: FeePolicy.feesExcluded,
        );
        await expectLater(HotSettlement.prepareSpark(container.read, quote),
            throwsA(isA<WalletGuardException>()));
        verifyNever(() => sdk.sendPayment(request: any(named: 'request')));
      });
    }
  });

  group('Settlement ownership after asynchronous approval', () {
    late Directory temporary;
    late SettlementStore store;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('settlement-binding');
      Hive.init(temporary.path);
      store = SettlementStore(
        box: await Hive.openBox<String>('operations'),
        quarantine: await Hive.openBox<String>('quarantine'),
        clock: () => _now,
      );
    });
    tearDown(() async {
      await Hive.deleteFromDisk();
      await temporary.delete(recursive: true);
    });

    for (final changedDuring in ['approval', 'preparation', 'unchanged', 'refused']) {
      test('$changedDuring addresses preserve reviewed payment terms',
          () async {
        var recipient = _recipient;
        var sends = 0;
        var id = 0;
        final runner = SettlementRunner(
          store: store,
          clock: () => _now,
          generateId: () => 'operation-${++id}',
          submit: (_, key) async => Result<OrchestraSubmitResponse>(
              statusCode: 200,
              data: OrchestraSubmitResponse(
                  orderId: 'order', status: 'processing')),
        );
        final plan = SettlementPlan(
          walletId: 'spending',
          flow: SettlementFlow.predictionsDeposit,
          route: RouteKey(
              fromChain: 'spark',
              fromAsset: 'BTC',
              toChain: 'polygon',
              toAsset: 'USDC.e'),
          sourceAccount: SettlementAccountKind.sparkHot,
          destinationAccount: SettlementAccountKind.pmHot,
          payer: SettlementPayer.sparkHot,
          resolveOwnership: () async => SettlementOwnership(
            refund: const SettlementAddressRef(
                address: _spark, kind: OwnedAddressKind.sparkSelf),
            recipient: SettlementAddressRef(
                address: recipient,
                kind: OwnedAddressKind.polymarketDepositWallet),
          ),
          requestQuote: (_) async =>
              SettlementQuoteResult(quote, skew: Duration.zero),
          review: (_, {required bool refreshed}) async =>
              SettlementReviewDecision.accept,
          stepUp: (_) async {
            if (changedDuring == 'approval') recipient = _otherRecipient;
            return true;
          },
          prepareFunding: (_, id) async {
            if (changedDuring == 'preparation') recipient = _otherRecipient;
            return null;
          },
          fund: (reviewed, _) async {
            expect(reviewed.request.recipientAddress, _recipient);
            if (changedDuring == 'refused') {
              throw SettlementFundingRefused(StateError('fee changed'));
            }
            sends++;
            return const SettlementFundingProof.spark('proof');
          },
        );
        if (changedDuring == 'unchanged') {
          expect((await runner.run(plan)).registered, isTrue);
          expect(sends, 1);
        } else if (changedDuring == 'refused') {
          await expectLater(runner.run(plan), throwsStateError);
          expect(sends, 0);
          final stored = await store.get('operation-1');
          expect(stored!.everBroadcast, isTrue);
          expect(stored.stage, SettlementStage.notFunded);
        } else {
          await expectLater(
              runner.run(plan), throwsA(isA<WalletGuardException>()));
          expect(sends, 0);
          final stored = await store.get('operation-1');
          expect(stored!.everBroadcast, isFalse);
          expect(stored.stage, SettlementStage.abandoned);
        }
      });
    }
  });
}
