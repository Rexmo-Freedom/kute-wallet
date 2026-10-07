import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/spark_deposit_actions.dart';
import 'package:mocktail/mocktail.dart';

class MockSdk extends Mock implements BreezSdk {}

Matcher throwsReason(SparkDepositActionReason reason) => throwsA(
    isA<SparkDepositActionException>().having((e) => e.reason, 'reason', reason));

Matcher throwsMessage(String text) => throwsA(
    isA<Exception>().having((e) => e.toString(), 'message', contains(text)));

void main() {
  late MockSdk sdk;
  late SparkDepositActions actions;
  String? wallet;

  DepositInfo pending(int vout,
          {bool mature = true, String? refundTxId, DepositClaimError? error}) =>
      DepositInfo(
          txid: 'tx',
          vout: vout,
          amountSats: BigInt.from(1000),
          isMature: mature,
          refundTxId: refundTxId,
          claimError: error);
  Payment depositPayment(String txid, int vout,
          {PaymentStatus status = PaymentStatus.pending}) =>
      Payment(
          id: 'claim',
          paymentType: PaymentType.receive,
          status: status,
          amount: BigInt.from(750),
          fees: BigInt.zero,
          timestamp: BigInt.one,
          method: PaymentMethod.deposit,
          details: PaymentDetails.deposit(txId: txid, vout: vout));
  void stubPending(List<DepositInfo> deposits) =>
      when(() => sdk.listUnclaimedDeposits(request: any(named: 'request')))
          .thenAnswer(
              (_) async => ListUnclaimedDepositsResponse(deposits: deposits));
  void stubPayments(List<Payment> payments) =>
      when(() => sdk.listPayments(request: any(named: 'request'))).thenAnswer(
          (_) async => ListPaymentsResponse(payments: payments));

  setUpAll(() {
    registerFallbackValue(const ListUnclaimedDepositsRequest());
    registerFallbackValue(const ListPaymentsRequest());
    registerFallbackValue(const ClaimDepositRequest(txid: 'tx', vout: 0));
    registerFallbackValue(RefundDepositRequest(
        txid: 'tx',
        vout: 0,
        destinationAddress: 'bc1test',
        fee: Fee.rate(satPerVbyte: BigInt.one)));
  });
  setUp(() {
    sdk = MockSdk();
    wallet = 'spending';
    stubPending([for (final vout in [0, 1, 3]) pending(vout)]);
    stubPayments([]);
    actions = SparkDepositActions(
        loadSdk: (_) async => sdk, currentWalletId: () => wallet);
  });

  Future<SparkDepositClaimResult> claim(
          {String txid = 'tx', int vout = 0, int fee = 250}) =>
      actions.claim(
          walletId: 'spending',
          txid: txid,
          vout: vout,
          maxFeeSats: BigInt.from(fee),
          depositAmountSats: BigInt.from(1000));

  test('failed attempt is retryable with the same account, outpoint and fee',
      () async {
    DepositClaimError? stored;
    when(() => sdk.listUnclaimedDeposits(request: any(named: 'request')))
        .thenAnswer((_) async =>
            ListUnclaimedDepositsResponse(deposits: [pending(0, error: stored)]));
    var calls = 0;
    when(() => sdk.claimDeposit(request: any(named: 'request')))
        .thenAnswer((_) async {
      if (++calls == 1) {
        // The SDK records a rejected claim on the deposit before failing.
        stored = const DepositClaimError.generic(message: 'offline');
        throw const SdkError.sparkError('offline');
      }
      return ClaimDepositResponse(
          outcome: ClaimDepositOutcome.settled(
              payment: depositPayment('tx', 0)));
    });
    await expectLater(claim(), throwsMessage('offline'));
    final result = await claim();
    expect(result.outcome, SparkDepositClaimOutcome.submitted);
    expect(result.paymentStatus, PaymentStatus.pending);
    expect(calls, 2);
  });

  test('passes the reviewed total cap, not a mining rate', () async {
    when(() => sdk.claimDeposit(request: any(named: 'request')))
        .thenAnswer((_) async => const ClaimDepositResponse(
            outcome: ClaimDepositOutcome.submitted()));
    await claim(vout: 3);
    final request =
        verify(() => sdk.claimDeposit(request: captureAny(named: 'request')))
            .captured
            .single as ClaimDepositRequest;
    expect(request.vout, 3);
    expect(request.maxFee, MaxFee.fixed(amount: BigInt.from(250)));
  });

  test('simultaneous claim/refund for same output never sends twice', () async {
    final result = Completer<ClaimDepositResponse>();
    when(() => sdk.claimDeposit(request: any(named: 'request')))
        .thenAnswer((_) => result.future);
    final first = claim();
    await expectLater(claim(fee: 300), throwsReason(SparkDepositActionReason.busy));
    await expectLater(
        actions.refund(
            walletId: 'spending',
            txid: 'tx',
            vout: 0,
            address: 'bc1test',
            satPerVbyte: BigInt.one),
        throwsReason(SparkDepositActionReason.busy));
    result.complete(const ClaimDepositResponse(
            outcome: ClaimDepositOutcome.submitted()));
    await first;
    verify(() => sdk.claimDeposit(request: any(named: 'request'))).called(1);
    verifyNever(() => sdk.refundDeposit(request: any(named: 'request')));
  });

  test('different outputs can be claimed independently', () async {
    when(() => sdk.claimDeposit(request: any(named: 'request')))
        .thenAnswer((_) async => const ClaimDepositResponse(
            outcome: ClaimDepositOutcome.submitted()));
    await Future.wait([claim(), claim(vout: 1)]);
    verify(() => sdk.claimDeposit(request: any(named: 'request'))).called(2);
  });

  test('wallet change while SDK initializes prevents a stale-screen claim',
      () async {
    final ready = Completer<BreezSdk>();
    actions = SparkDepositActions(
        loadSdk: (_) => ready.future, currentWalletId: () => wallet);
    final request = claim();
    final expectation =
        expectLater(request, throwsReason(SparkDepositActionReason.walletChanged));
    wallet = 'replacement';
    ready.complete(sdk);
    await expectation;
    verifyNever(() => sdk.claimDeposit(request: any(named: 'request')));
  });

  test('an SDK that never becomes ready fails as unavailable, not a spinner',
      () async {
    actions = SparkDepositActions(
        loadSdk: (_) => Completer<BreezSdk>().future,
        currentWalletId: () => wallet,
        sdkLoadTimeout: const Duration(milliseconds: 20));
    await expectLater(
        claim(), throwsReason(SparkDepositActionReason.walletUnavailable));
    actions = SparkDepositActions(
        loadSdk: (_) async => throw StateError('connect failed'),
        currentWalletId: () => wallet);
    await expectLater(
        claim(), throwsReason(SparkDepositActionReason.walletUnavailable));
    verifyNever(() => sdk.claimDeposit(request: any(named: 'request')));
  });

  test('invalid caps and refund inputs never call SDK', () async {
    for (final fee in [0, -1, 1000, 1001]) {
      await expectLater(
          claim(fee: fee), throwsReason(SparkDepositActionReason.invalidFee));
    }
    await expectLater(
        actions.refund(
            walletId: 'spending',
            txid: 'tx',
            vout: 0,
            address: ' ',
            satPerVbyte: BigInt.one),
        throwsReason(SparkDepositActionReason.invalidAddress));
    await expectLater(
        actions.refund(
            walletId: 'spending',
            txid: 'tx',
            vout: 0,
            address: 'bc1test',
            satPerVbyte: BigInt.zero),
        throwsReason(SparkDepositActionReason.invalidFee));
    verifyNever(() => sdk.claimDeposit(request: any(named: 'request')));
    verifyNever(() => sdk.refundDeposit(request: any(named: 'request')));
  });

  test('a deposit claimed before the tap reconciles instead of failing',
      () async {
    stubPending([]);
    stubPayments([depositPayment('TX', 0)]);
    expect((await claim()).outcome, SparkDepositClaimOutcome.alreadyReceived);
    stubPayments([
      depositPayment('tx', 1),
      depositPayment('tx', 0, status: PaymentStatus.failed),
    ]);
    expect((await claim()).outcome, SparkDepositClaimOutcome.noLongerPending);
    when(() => sdk.listPayments(request: any(named: 'request')))
        .thenThrow(Exception('storage'));
    expect((await claim()).outcome, SparkDepositClaimOutcome.noLongerPending);
    verifyNever(() => sdk.claimDeposit(request: any(named: 'request')));
    stubPayments([depositPayment('tx', 3)]);
    expect(
        (await actions.missingDepositOutcome(
                walletId: 'spending', txid: 'TX', vout: 3))
            .outcome,
        SparkDepositClaimOutcome.alreadyReceived);
  });

  test('a claim that errors after auto-claim settled the deposit reconciles',
      () async {
    var reads = 0;
    when(() => sdk.listUnclaimedDeposits(request: any(named: 'request')))
        .thenAnswer((_) async => ListUnclaimedDepositsResponse(
            deposits: ++reads == 1 ? [pending(0)] : const []));
    when(() => sdk.claimDeposit(request: any(named: 'request')))
        .thenThrow(const SdkError.missingUtxo(tx: 'tx', vout: 0));
    stubPayments([depositPayment('tx', 0)]);
    expect((await claim()).outcome, SparkDepositClaimOutcome.alreadyReceived);
    expect(reads, 2);
  });

  test('a transfer lookup that fails after the service accepted is not a failure',
      () async {
    // The SDK keeps the row, with no new claim error, until the transfer
    // event deletes it.
    when(() => sdk.claimDeposit(request: any(named: 'request')))
        .thenThrow(const SdkError.sparkError('transfer lookup timed out'));
    final unknown = await claim();
    expect(unknown.outcome, SparkDepositClaimOutcome.statusUnknown);
    expect(unknown.paymentStatus, isNull);
    stubPayments([depositPayment('tx', 0)]);
    expect((await claim()).outcome, SparkDepositClaimOutcome.alreadyReceived);
  });

  test('errors before the service accepts a claim keep the original error',
      () async {
    when(() => sdk.claimDeposit(request: any(named: 'request')))
        .thenThrow(const SdkError.missingUtxo(tx: 'tx', vout: 0));
    await expectLater(claim(), throwsMessage('UTXO'));
    when(() => sdk.claimDeposit(request: any(named: 'request')))
        .thenThrow(const SdkError.chainServiceError('esplora down'));
    await expectLater(claim(), throwsMessage('esplora down'));
    var reads = 0;
    when(() => sdk.listUnclaimedDeposits(request: any(named: 'request')))
        .thenAnswer((_) async {
      if (++reads == 2) throw Exception('storage');
      return ListUnclaimedDepositsResponse(deposits: [pending(0)]);
    });
    when(() => sdk.claimDeposit(request: any(named: 'request')))
        .thenThrow(const SdkError.sparkError('transfer lookup timed out'));
    await expectLater(claim(), throwsMessage('transfer lookup timed out'));
    verifyNever(() => sdk.listPayments(request: any(named: 'request')));
  });

  test('fee rejection keeps the deposit pending and reports required sats',
      () async {
    when(() => sdk.claimDeposit(request: any(named: 'request'))).thenThrow(
        SdkError.maxDepositClaimFeeExceeded(
            tx: 'tx',
            vout: 0,
            requiredFeeSats: BigInt.from(400),
            requiredFeeRateSatPerVbyte: BigInt.from(5)));
    await expectLater(
        claim(),
        throwsA(isA<SparkDepositActionException>()
            .having((e) => e.reason, 'reason',
                SparkDepositActionReason.feeExceeded)
            .having((e) => e.requiredFeeSats, 'requiredFeeSats',
                BigInt.from(400))));
    verifyNever(() => sdk.listPayments(request: any(named: 'request')));
  });

  test('a claim the SDK defers over the fee reports required sats', () async {
    when(() => sdk.claimDeposit(request: any(named: 'request'))).thenAnswer(
        (_) async => ClaimDepositResponse(
            outcome: ClaimDepositOutcome.deferred_(
                reason: ClaimDeferredReason.maxFeeExceeded(
                    requiredFeeSats: BigInt.from(400),
                    maxFeeSats: BigInt.from(250)))));
    await expectLater(
        claim(),
        throwsA(isA<SparkDepositActionException>()
            .having((e) => e.reason, 'reason',
                SparkDepositActionReason.feeExceeded)
            .having((e) => e.requiredFeeSats, 'requiredFeeSats',
                BigInt.from(400))));
  });

  test('a claim the SDK is already running for the output reports busy',
      () async {
    when(() => sdk.claimDeposit(request: any(named: 'request')))
        .thenThrow(const SdkError.depositClaimInProgress(tx: 'tx', vout: 0));
    await expectLater(claim(), throwsReason(SparkDepositActionReason.busy));
    verifyNever(() => sdk.listPayments(request: any(named: 'request')));
  });

  test('refunding deposits are not blindly submitted again', () async {
    stubPending([pending(0, refundTxId: 'refund')]);
    await expectLater(
        claim(), throwsReason(SparkDepositActionReason.refundInProgress));
    verifyNever(() => sdk.claimDeposit(request: any(named: 'request')));
  });

  test('immature deposits wait for confirmations before manual submission',
      () async {
    stubPending([pending(0, mature: false)]);
    await expectLater(claim(), throwsReason(SparkDepositActionReason.immature));
    verifyNever(() => sdk.claimDeposit(request: any(named: 'request')));
  });

  test('live deposit reads the exact outpoint for the current wallet',
      () async {
    stubPending([
      pending(0),
      DepositInfo(
          txid: 'TX',
          vout: 3,
          amountSats: BigInt.from(1000),
          isMature: true,
          refundTx: 'signed'),
    ]);
    final live =
        await actions.liveDeposit(walletId: 'spending', txid: 'tx', vout: 3);
    expect(live?.refundTx, 'signed');
    expect(
        await actions.liveDeposit(walletId: 'spending', txid: 'tx', vout: 9),
        isNull);
    wallet = 'replacement';
    await expectLater(
        actions.liveDeposit(walletId: 'spending', txid: 'tx', vout: 3),
        throwsReason(SparkDepositActionReason.walletChanged));
    await expectLater(
        actions.missingDepositOutcome(walletId: 'spending', txid: 'tx', vout: 3),
        throwsReason(SparkDepositActionReason.walletChanged));
  });
}
