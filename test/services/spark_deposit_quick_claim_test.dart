import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/breez/deposit_update.dart';
import 'package:kute/models/breez/claim_policy.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/services/mempool_address_service.dart';
import 'package:kute/services/spark_deposit_actions.dart';
import 'package:kute/services/spark_deposit_auto_claim.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:mocktail/mocktail.dart';

class MockSdk extends Mock implements BreezSdk {}

/// Records claims; [gate] holds a claim open until completed.
class _Actions extends SparkDepositActions {
  _Actions()
      : super(
            loadSdk: (_) => throw UnimplementedError(),
            currentWalletId: () => 'spending');

  final claims = <String>[];
  Completer<void>? gate;
  Object? failure;

  @override
  Future<SparkDepositClaimResult> claim({
    required String walletId,
    required String txid,
    required int vout,
    required BigInt maxFeeSats,
    required BigInt depositAmountSats,
    bool early = false,
  }) async {
    claims.add('$txid:$vout@$maxFeeSats');
    await gate?.future;
    final error = failure;
    if (error != null) throw error;
    return const SparkDepositClaimResult(SparkDepositClaimOutcome.submitted,
        paymentStatus: PaymentStatus.pending);
  }
}

DepositInfo _info(String txid,
        {bool mature = true,
        DepositClaimError? error,
        InstantClaimStatus? instant,
        String? refundTxId,
        int sats = 11900000}) =>
    DepositInfo(
        txid: txid,
        vout: 0,
        amountSats: BigInt.from(sats),
        isMature: mature,
        claimError: error,
        instantClaimStatus: instant,
        refundTxId: refundTxId);

SparkUnclaimedDeposit _row(DepositInfo info) => SparkUnclaimedDeposit(
    id: '${info.txid}:${info.vout}',
    timestamp: DateTime.utc(2026, 10, 20),
    depositInfo: info);

DepositClaimError _feeExceeded(String txid, int fee) =>
    DepositClaimError.maxDepositClaimFeeExceeded(
        tx: txid,
        vout: 0,
        requiredFeeSats: BigInt.from(fee),
        requiredFeeRateSatPerVbyte: BigInt.from(fee ~/ 99));

SparkPendingDeposit _mempoolRow(String txid, int confirmations) =>
    SparkPendingDeposit(
      id: 'spark_pending_$txid',
      timestamp: DateTime.utc(2026, 10, 20),
      confirmations: confirmations,
      mempoolTx: MempoolTransaction(
          txid: txid, confirmed: true, fee: 0, balanceChange: 11900000),
    );

SparkTransaction _depositPayment(String txid,
        {PaymentStatus status = PaymentStatus.completed}) =>
    SparkTransaction(
      id: 'pay_$txid',
      timestamp: DateTime.utc(2026, 10, 20),
      isConfirmed: status == PaymentStatus.completed,
      details: Payment(
          id: 'pay_$txid',
          paymentType: PaymentType.receive,
          status: status,
          amount: BigInt.from(11890000),
          fees: BigInt.from(10000),
          timestamp: BigInt.one,
          method: PaymentMethod.deposit,
          details: PaymentDetails.deposit(txId: txid, vout: 0)),
    );

Transaction _feed({
  List<SparkUnclaimedDeposit> unclaimed = const [],
  List<SparkPendingDeposit> pending = const [],
  List<SparkTransaction> payments = const [],
}) =>
    Transaction(
      bitcoinTransactions: const [],
      sparkTransactions: payments,
      sparkUnclaimedDeposits: unclaimed,
      sparkPendingDeposits: pending,
    );

void main() {
  final stale = InstantClaimStatus.submitted(claimId: 'claim');

  group('deposit stage', () {
    test('reads each SDK state in the person\'s terms', () {
      expect(
          _row(_info('a', mature: false)).stage, SparkDepositStage.confirming);
      expect(_row(_info('a')).stage, SparkDepositStage.adding);
      // 0.25 % of 0.119 BTC is 29,750 sats: a 40,000 sat quote waits for
      // the person, an 11,900 sat one is claimed by the app on its own.
      expect(_row(_info('a', error: _feeExceeded('a', 40000))).stage,
          SparkDepositStage.waitingForFee);
      expect(_row(_info('a', error: _feeExceeded('a', 11900))).stage,
          SparkDepositStage.adding);
      expect(
          _row(_info('a',
                  error: const DepositClaimError.generic(message: 'boom')))
              .stage,
          SparkDepositStage.failed);
      expect(_row(_info('a', instant: stale)).stage, SparkDepositStage.failed);
      expect(_row(_info('a', instant: stale, mature: false)).stage,
          SparkDepositStage.confirming);
      expect(
          _row(_info('a', refundTxId: 'r')).stage, SparkDepositStage.refunding);
    });

    test('the required fee survives the cache round trip', () {
      final row = _row(_info('a', error: _feeExceeded('a', 40000)));
      expect(row.requiredFeeSats, 40000);
      final cached = SparkUnclaimedDeposit.fromCache(
          id: row.id,
          timestamp: row.timestamp,
          txid: 'a',
          vout: 0,
          amountSats: 11900000,
          isMature: true,
          hasClaimError: true,
          requiredFeeSats: row.requiredFeeSats);
      expect(cached.stage, SparkDepositStage.waitingForFee);
      expect(cached.needsAction, isTrue);
    });
  });

  group('mempool rows bridge until the SDK lists the deposit', () {
    test('below 3 confirmations the mempool row hides its unclaimed twin', () {
      final rows = applySparkDepositUpdate(
        const [],
        SparkDepositUpdate(SparkDepositUpdateKind.snapshot,
            [_info('young', mature: false), _info('old')]),
        now: DateTime.utc(2026, 10, 20),
        mempoolTxids: sparkConfirmingTxids(
            [_mempoolRow('young', 2), _mempoolRow('old', 5)]),
      );
      expect(rows.map((r) => r.txid), ['old']);
    });

    test('a matured deposit the SDK has not listed keeps its row', () {
      final feed = _feed(pending: [_mempoolRow('a', 60)]);
      expect(
          feed.allTransactions.whereType<SparkPendingDeposit>(), hasLength(1));
    });

    test('the SDK listing the outpoint takes over from the bridge row', () {
      final listed = _feed(
          pending: [_mempoolRow('a', 60)],
          unclaimed: [_row(_info('a', error: _feeExceeded('a', 11900)))]);
      expect(listed.allTransactions.whereType<SparkPendingDeposit>(), isEmpty);
      expect(listed.allTransactions.whereType<SparkUnclaimedDeposit>(),
          hasLength(1));

      final credited = _feed(
          pending: [_mempoolRow('a', 4)],
          payments: [_depositPayment('a', status: PaymentStatus.pending)]);
      expect(
          credited.allTransactions.whereType<SparkPendingDeposit>(), isEmpty);
    });
  });

  group('SparkDepositAutoClaimer', () {
    late _Actions actions;
    late DateTime now;
    late SparkDepositAutoClaimer claimer;
    late List<(String, Map<String, Object?>?)> events;

    setUp(() {
      actions = _Actions();
      now = DateTime.utc(2026, 10, 26, 12);
      claimer = SparkDepositAutoClaimer(actions: actions, now: () => now);
      events = [];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    });
    tearDown(() => TrackingService.debugTrackObserver = null);

    // A deposit left over from a previous version: its early claim was
    // accepted there and never settled, so the SDK skips it forever.
    test(
        'a stale early claim from a previous version is claimed on the '
        'first snapshot, under the normal cap', () async {
      await claimer.review('spending', [_row(_info('left', instant: stale))]);
      // Under the app's automatic ceiling: 0.25 % of the deposit.
      expect(actions.claims, ['left:0@29750']);
      expect(events.map((e) => e.$1), contains('spark_deposit_claimed'));
      final params =
          events.firstWhere((e) => e.$1 == 'spark_deposit_claimed').$2!;
      expect(params['trigger'], 'auto');
      expect(params['path'], 'auto_stale_early_claim');
      expect(
          params.values.whereType<String>(), isNot(contains(contains('left'))));
    });

    test('deposits the SDK retries itself are left to it', () async {
      await claimer.review('spending', [
        _row(_info('fee', error: _feeExceeded('fee', 40000))),
        _row(_info('fresh')),
        _row(_info('young', mature: false, instant: stale)),
        _row(_info('err',
            error: const DepositClaimError.generic(message: 'timeout'))),
      ]);
      expect(actions.claims, isEmpty);
    });

    test('retries wait longer each time and once per snapshot', () async {
      actions.failure = Exception('network');
      final rows = [_row(_info('left', instant: stale))];
      await claimer.review('spending', rows);
      await claimer.review('spending', rows);
      expect(actions.claims, hasLength(1));
      now = now.add(const Duration(seconds: 61));
      await claimer.review('spending', rows);
      expect(actions.claims, hasLength(2));
      now = now.add(const Duration(minutes: 2));
      await claimer.review('spending', rows);
      expect(actions.claims, hasLength(2));
      now = now.add(const Duration(minutes: 4));
      await claimer.review('spending', rows);
      expect(actions.claims, hasLength(3));
      expect(
          events
              .where((e) => e.$1 == 'auto_claim_failed')
              .map((e) => e.$2!['reason']),
          everyElement('stale_sdk_error'));
    });

    test('never two claims at once for the same outpoint', () async {
      actions.gate = Completer<void>();
      final rows = [_row(_info('left', instant: stale))];
      final first = claimer.review('spending', rows);
      await Future<void>.delayed(Duration.zero);
      expect(claimer.inFlight, hasLength(1));
      now = now.add(const Duration(hours: 2));
      await claimer.review('spending', rows);
      expect(actions.claims, hasLength(1));
      actions.gate!.complete();
      await first;
      expect(claimer.inFlight, isEmpty);
    });

    test('the 0.119 BTC case: an 11,900 sat quote is claimed on its own',
        () async {
      expect(sparkAutoClaimCeilingSats(11900000), 29750);
      await claimer.review(
          'spending', [_row(_info('big', error: _feeExceeded('big', 11900)))]);
      // Quote plus the usual headroom (10 %), within the 29,750 ceiling.
      expect(actions.claims, ['big:0@13090']);
      final params =
          events.firstWhere((e) => e.$1 == 'spark_deposit_claimed').$2!;
      expect(params['path'], 'auto_percent');
      expect(params['amount_sats'], 11900000);
      expect(params['fee_sats'], 11900);
    });

    test('the headroom never passes the ceiling', () async {
      await claimer.review(
          'spending', [_row(_info('big', error: _feeExceeded('big', 29000)))]);
      expect(actions.claims, ['big:0@29750']);
    });

    test('a quote above 0.25 % waits for the person', () async {
      final row = _row(_info('big', error: _feeExceeded('big', 29751)));
      await claimer.review('spending', [row]);
      expect(actions.claims, isEmpty);
      expect(row.stage, SparkDepositStage.waitingForFee);
      expect(row.needsAction, isTrue);
    });

    test('a small deposit uses the 2,475 sat floor', () async {
      expect(sparkAutoClaimCeilingSats(100000), kSparkAutoClaimMaxFeeSats);
      await claimer.review('spending', [
        _row(_info('small', sats: 100000, error: _feeExceeded('small', 2000))),
        _row(_info('over', sats: 100000, error: _feeExceeded('over', 2600))),
      ]);
      expect(actions.claims, ['small:0@2200']);
    });

    test('a deposit claimed once is never claimed again', () async {
      final rows = [_row(_info('big', error: _feeExceeded('big', 11900)))];
      await claimer.review('spending', rows);
      now = now.add(const Duration(hours: 3));
      await claimer.review('spending', rows);
      expect(actions.claims, hasLength(1));
    });

    test("immature deposits are left to the SDK's own early claim", () async {
      await claimer.review('spending', [
        _row(_info('young', mature: false)),
        _row(_info('young2',
            mature: false, error: _feeExceeded('young2', 1000))),
      ]);
      expect(actions.claims, isEmpty);
      expect(SparkDepositAutoClaimer.plan(_row(_info('young', mature: false))),
          isNull);
      // The SDK's own cap (and so its early claims within it) is unchanged.
      expect(kSparkAutoClaimMaxFeeSats, 2475);
    });

    test('a busy outpoint does not count as an attempt', () async {
      actions.failure =
          const SparkDepositActionException(SparkDepositActionReason.busy);
      final rows = [_row(_info('left', instant: stale))];
      await claimer.review('spending', rows);
      await claimer.review('spending', rows);
      expect(actions.claims, hasLength(2));
    });
  });

  group('one guard for every claim of an outpoint', () {
    late MockSdk sdk;
    late SparkDepositActions actions;
    late SparkDepositAutoClaimer claimer;
    late Completer<ClaimDepositResponse> sdkClaim;
    final big = _info('big', error: _feeExceeded('big', 11900));

    setUpAll(() {
      registerFallbackValue(const ListUnclaimedDepositsRequest());
      registerFallbackValue(const ListPaymentsRequest());
      registerFallbackValue(const ClaimDepositRequest(txid: 'tx', vout: 0));
    });
    setUp(() {
      sdk = MockSdk();
      actions = SparkDepositActions(
          loadSdk: (_) async => sdk, currentWalletId: () => 'spending');
      claimer = SparkDepositAutoClaimer(actions: actions);
      sdkClaim = Completer<ClaimDepositResponse>();
      when(() => sdk.listUnclaimedDeposits(request: any(named: 'request')))
          .thenAnswer(
              (_) async => ListUnclaimedDepositsResponse(deposits: [big]));
      when(() => sdk.listPayments(request: any(named: 'request')))
          .thenAnswer((_) async => const ListPaymentsResponse(payments: []));
      when(() => sdk.claimDeposit(request: any(named: 'request')))
          .thenAnswer((_) => sdkClaim.future);
    });

    Future<SparkDepositClaimResult> manual() => actions.claim(
        walletId: 'spending',
        txid: 'big',
        vout: 0,
        maxFeeSats: BigInt.from(13090),
        depositAmountSats: BigInt.from(11900000));

    test('a manual claim during the automatic one never claims twice',
        () async {
      final auto = claimer.review('spending', [_row(big)]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(actions.isBusy('big', 0), isTrue);
      await expectLater(
          manual(),
          throwsA(isA<SparkDepositActionException>().having(
              (e) => e.reason, 'reason', SparkDepositActionReason.busy)));
      sdkClaim.complete(
          const ClaimDepositResponse(outcome: ClaimDepositOutcome.submitted()));
      await auto;
      verify(() => sdk.claimDeposit(request: any(named: 'request'))).called(1);
      expect(actions.isBusy('big', 0), isFalse);
    });

    test('the automatic claim skips while a manual one runs', () async {
      final running = manual();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(actions.busyOutpoints.value, {sparkOutpointKey('big', 0)});
      await claimer.review('spending', [_row(big)]);
      sdkClaim.complete(
          const ClaimDepositResponse(outcome: ClaimDepositOutcome.submitted()));
      await running;
      verify(() => sdk.claimDeposit(request: any(named: 'request'))).called(1);
    });

    test('a refund waits for a running claim', () async {
      final running = manual();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await expectLater(
          actions.refund(
              walletId: 'spending',
              txid: 'big',
              vout: 0,
              address: 'bc1qtest',
              satPerVbyte: BigInt.from(3)),
          throwsA(isA<SparkDepositActionException>().having(
              (e) => e.reason, 'reason', SparkDepositActionReason.busy)));
      sdkClaim.complete(
          const ClaimDepositResponse(outcome: ClaimDepositOutcome.submitted()));
      await running;
    });

    test('"already been claimed" is a received deposit, not a failure',
        () async {
      when(() => sdk.claimDeposit(request: any(named: 'request'))).thenAnswer(
          (_) async =>
              throw const SdkError.generic('Deposit has already been claimed'));
      final result = await manual();
      expect(result.outcome, SparkDepositClaimOutcome.alreadyReceived);
    });
  });

  group('SparkDepositActions quick claim', () {
    late MockSdk sdk;
    late SparkDepositActions actions;

    setUpAll(() {
      registerFallbackValue(const ListUnclaimedDepositsRequest());
      registerFallbackValue(const ListPaymentsRequest());
      registerFallbackValue(const ClaimDepositRequest(txid: 'tx', vout: 0));
      registerFallbackValue(
          const FetchClaimDepositQuoteRequest(txid: 'tx', vout: 0));
    });
    setUp(() {
      sdk = MockSdk();
      actions = SparkDepositActions(
          loadSdk: (_) async => sdk, currentWalletId: () => 'spending');
      when(() => sdk.listUnclaimedDeposits(request: any(named: 'request')))
          .thenAnswer((_) async => ListUnclaimedDepositsResponse(
              deposits: [_info('young', mature: false)]));
    });

    test('quotes both ways of claiming', () async {
      when(() => sdk.fetchClaimDepositQuote(request: any(named: 'request')))
          .thenAnswer((_) async => FetchClaimDepositQuoteResponse(
                amountSats: BigInt.from(11900000),
                confirmations: 1,
                instant: ClaimDepositQuote(
                    confirmationsRequired: 1,
                    creditAmountSats: BigInt.from(11870000),
                    feeSats: BigInt.from(30000),
                    feeRateSatPerVbyte: BigInt.from(303),
                    isEstimate: false),
                mature: ClaimDepositQuote(
                    confirmationsRequired: 3,
                    creditAmountSats: BigInt.from(11888000),
                    feeSats: BigInt.from(12000),
                    feeRateSatPerVbyte: BigInt.from(121),
                    isEstimate: true),
              ));
      final quote =
          await actions.quote(walletId: 'spending', txid: 'young', vout: 0);
      expect(quote.confirmations, 1);
      expect(quote.earlyFeeSats, 30000);
      expect(quote.earlyConfirmations, 1);
      expect(quote.matureFeeSats, 12000);
      expect(quote.matureIsEstimate, isTrue);
    });

    test('finds a mempool row\'s deposit by its txid', () async {
      final found =
          await actions.depositForTxid(walletId: 'spending', txid: 'YOUNG');
      expect(found?.vout, 0);
    });

    test('an immature deposit is claimed early only when asked', () async {
      when(() => sdk.claimDeposit(request: any(named: 'request'))).thenAnswer(
          (_) async => const ClaimDepositResponse(
              outcome: ClaimDepositOutcome.submitted()));
      Future<SparkDepositClaimResult> claim({required bool early}) =>
          actions.claim(
              walletId: 'spending',
              txid: 'young',
              vout: 0,
              maxFeeSats: BigInt.from(33000),
              depositAmountSats: BigInt.from(11900000),
              early: early);
      await expectLater(
          claim(early: false),
          throwsA(isA<SparkDepositActionException>().having(
              (e) => e.reason, 'reason', SparkDepositActionReason.immature)));
      final result = await claim(early: true);
      expect(result.outcome, SparkDepositClaimOutcome.submitted);
      final request =
          verify(() => sdk.claimDeposit(request: captureAny(named: 'request')))
              .captured
              .single as ClaimDepositRequest;
      expect(request.maxFee, MaxFee.fixed(amount: BigInt.from(33000)));
    });
  });
}
