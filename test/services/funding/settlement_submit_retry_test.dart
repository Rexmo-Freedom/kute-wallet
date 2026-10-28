import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/handlers/response_handlers.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/services/funding/ledger_settlement.dart'
    show LedgerSettlementRecords;
import 'package:kute/services/funding/owned_address_resolver.dart';
import 'package:kute/services/funding/settlement_http.dart'
    show IdempotentRetryPolicy;
import 'package:kute/services/funding/settlement_quote_policy.dart';
import 'package:kute/services/funding/settlement_reconciler.dart';
import 'package:kute/services/funding/settlement_registration.dart'
    show withSettlementOrderId;
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';

const _spark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _recipient = '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359';
final _now = DateTime.utc(2026, 9, 15, 12);
const _tokenHash =
    '3f1c9a7be0d24c55a1f0e6b8c2d47a9e5b6c8d0f1a2b3c4d5e6f708192a3b4c5';

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

Result<OrchestraSubmitResponse> _accepted(String orderId) =>
    Result<OrchestraSubmitResponse>(
        statusCode: 200,
        data: OrchestraSubmitResponse(orderId: orderId, status: 'processing'));

Result<OrchestraSubmitResponse> _refused() => Result<OrchestraSubmitResponse>(
    statusCode: 400, error: 'invalid_tx_hash', errorCode: 'invalid_tx_hash');

Result<OrchestraSubmitResponse> _inProgress() =>
    Result<OrchestraSubmitResponse>(
        statusCode: 409,
        error: 'Request is already being processed',
        errorCode: 'idempotency_in_progress');

Result<OrchestraSubmitResponse> _unavailable() =>
    Result<OrchestraSubmitResponse>(statusCode: 503, error: 'down');

void main() {
  final quote = _quote();

  group('sparkTxHash for a Spark payment id', () {
    test('a bitcoin transfer id is sent as it is', () {
      const transferId = '0199c0de-7a4b-7c3e-9d2f-5e6a7b8c9d0e';
      expect(sparkSubmitTxHash(transferId), transferId);
    });

    test('a token payment id is sent as its token transaction hash', () {
      expect(sparkSubmitTxHash('$_tokenHash:0'), _tokenHash);
      expect(sparkSubmitTxHash('$_tokenHash:12'), _tokenHash);
    });

    test('the submit body carries the hash, the record keeps the payment id',
        () {
      final op = SettlementOperation(
        operationId: 'op',
        walletId: 'spending',
        accountKind: SettlementAccountKind.sparkHot,
        flow: SettlementFlow.moveUsdToPredictions,
        route: RouteKey(
            fromChain: 'spark',
            fromAsset: 'USDB',
            toChain: 'polygon',
            toAsset: 'USDC.e'),
        amountInBaseUnits: '1000000',
        recipient: const SettlementAddressRef(
            address: _recipient,
            kind: OwnedAddressKind.polymarketDepositWallet),
        refund: const SettlementAddressRef(
            address: _spark, kind: OwnedAddressKind.sparkSelf),
        quote: settlementQuoteTermsFor(quote, skew: Duration.zero),
        funding: const SettlementFunding(
            kind: SettlementFundingKind.spark,
            sparkPaymentId: '$_tokenHash:0'),
        stage: SettlementStage.funded,
        createdAt: _now,
        updatedAt: _now,
      );
      final body = settlementSubmitBody(op);
      expect(body['sparkTxHash'], _tokenHash);
      expect(body['sourceSparkAddress'], _spark);
      expect(op.funding!.sparkPaymentId, '$_tokenHash:0');
    });
  });

  group('submit after a Spark send', () {
    late Directory temporary;
    late SettlementStore store;
    late List<Duration> sleeps;
    late List<String> keys;
    late List<Result<OrchestraSubmitResponse> Function()> replies;
    late int lookups;
    String? detectedOrder;
    var id = 0;

    SettlementRunner runner() => SettlementRunner(
          store: store,
          clock: () => _now,
          generateId: () => 'id-${++id}',
          submit: (_, key) async {
            keys.add(key);
            return replies[keys.length - 1]();
          },
          sleep: (d) async => sleeps.add(d),
          findOrder: (_) async {
            lookups++;
            return detectedOrder;
          },
        );

    SettlementPlan plan(
            {bool background = false,
            String toChain = 'polygon',
            SettlementFundingProof Function()? fund}) =>
        SettlementPlan(
          walletId: 'spending',
          flow: SettlementFlow.moveBtcToUsdc,
          route: RouteKey(
              fromChain: 'spark',
              fromAsset: 'BTC',
              toChain: toChain,
              toAsset: 'USDC.e'),
          sourceAccount: SettlementAccountKind.sparkHot,
          destinationAccount: SettlementAccountKind.pmHot,
          payer: SettlementPayer.sparkHot,
          resolveOwnership: () async => const SettlementOwnership(
            refund: SettlementAddressRef(
                address: _spark, kind: OwnedAddressKind.sparkSelf),
            recipient: SettlementAddressRef(
                address: _recipient,
                kind: OwnedAddressKind.polymarketDepositWallet),
          ),
          requestQuote: (_) async =>
              SettlementQuoteResult(quote, skew: Duration.zero),
          fund: (_, __) async =>
              fund?.call() ?? const SettlementFundingProof.spark('transfer-1'),
          registerInBackground: background,
        );

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('settlement-submit');
      Hive.init(temporary.path);
      store = SettlementStore(
        box: await Hive.openBox<String>('operations'),
        quarantine: await Hive.openBox<String>('quarantine'),
        clock: () => _now,
      );
      sleeps = [];
      keys = [];
      lookups = 0;
      detectedOrder = null;
    });
    tearDown(() async {
      await Hive.deleteFromDisk();
      await temporary.delete(recursive: true);
    });

    test(
        'F11: while a send on the route may have left unconfirmed, a new one '
        'on that wallet and route is refused before any quote; another '
        'route still goes', () async {
      replies = [() => _accepted('ord_1')];
      final r = runner();
      await expectLater(
          r.run(plan(fund: () => throw TimeoutException('send'))),
          throwsA(isA<SettlementFundingUnknown>()));
      final unknown = (await store.all()).single;
      expect(unknown.stage, SettlementStage.fundingUnknown);
      expect(
          await r.blockedByUnresolved('spending', unknown.route), isTrue);

      await expectLater(
          r.run(plan()),
          throwsA(isA<SettlementStopped>().having(
              (e) => e.reason, 'reason', SettlementStopReason.blockedPending)));
      // Nothing was created, quoted or paid for the refused one.
      expect(await store.all(), hasLength(1));
      expect(keys, isEmpty);

      // Another route is not held up.
      final other = await r.run(plan(toChain: 'arbitrum'));
      expect(other.orderId, 'ord_1');
    });

    test(
        'F11: an unresolved send the reconciler cannot settle (not Spark) '
        'holds its route only until 30 min past its quote', () async {
      replies = [() => _accepted('ord_1')];
      await expectLater(
          runner().run(plan(fund: () => throw TimeoutException('send'))),
          throwsA(isA<SettlementFundingUnknown>()));
      final unknown = (await store.all()).single;
      final expiresAt = unknown.quote!.expiresAt;
      SettlementRunner at(DateTime t) =>
          SettlementRunner(store: store, clock: () => t);

      // A Spark payment is held until the reconciler settles it.
      expect(
          await at(expiresAt.add(const Duration(days: 3)))
              .blockedByUnresolved('spending', unknown.route),
          isTrue);

      await store.update(unknown.operationId,
          stage: unknown.stage,
          expectedVersion: unknown.version,
          patch: (c) => c.copyWith(
              funding:
                  const SettlementFunding(kind: SettlementFundingKind.relayer)));
      expect(
          await at(expiresAt.add(const Duration(minutes: 29)))
              .blockedByUnresolved('spending', unknown.route),
          isTrue);
      expect(
          await at(expiresAt.add(const Duration(minutes: 31)))
              .blockedByUnresolved('spending', unknown.route),
          isFalse);
    });

    test('a refusal is resubmitted quickly with a new key until accepted',
        () async {
      replies = [_refused, () => _accepted('ord_1')];
      final result = await runner().run(plan());

      expect(result.orderId, 'ord_1');
      expect(keys, hasLength(2));
      expect(keys.toSet(), hasLength(2), reason: 'a new key after a 4xx');
      expect(sleeps, const [Duration(milliseconds: 1500)]);
      expect(lookups, 1);
      final stored = await store.get(result.operation.operationId);
      expect(stored!.stage, SettlementStage.submitted);
      expect(stored.orderId, 'ord_1');
      // One burst, one attempt for the reconciler's schedule.
      expect(stored.submit.attempts, 1);
    });

    test('the quick resubmits are bounded and leave the operation funded',
        () async {
      replies = [_refused, _refused, _refused, _refused];
      final result = await runner().run(plan());

      expect(result.registered, isFalse);
      expect(keys, hasLength(4));
      expect(keys.toSet(), hasLength(4));
      expect(sleeps, kSettlementSubmitRejectRetryDelays);
      final stored = await store.get(result.operation.operationId);
      expect(stored!.stage, SettlementStage.funded);
      expect(stored.submit.attempts, 1);
      // The reconciler's next submit uses a key never sent before.
      expect(keys, isNot(contains(stored.submitKeys!.current)));
    });

    test('an order Orchestra already detected ends the resubmits', () async {
      replies = [_refused];
      detectedOrder = 'ord_detected';
      final result = await runner().run(plan());

      expect(keys, hasLength(1));
      expect(result.orderId, 'ord_detected');
      final stored = await store.get(result.operation.operationId);
      expect(stored!.stage, SettlementStage.submitted);
      expect(stored.orderId, 'ord_detected');
      expect(stored.submit.providerDetected, isTrue);
    });

    test('a 5xx keeps its key and gets no quick resubmit', () async {
      replies = [_refused, _refused, _refused, _refused];
      final op = await _fundedOperation(runner(), plan(), store);
      keys.clear();
      sleeps.clear();
      final submitted = await submitSettlementDeposit(
        store,
        op,
        submit: (_, key) async {
          keys.add(key);
          return _unavailable();
        },
        clock: () => _now,
        policy: const IdempotentRetryPolicyForTest(),
        sleep: (d) async => sleeps.add(d),
        findOrder: (_) async => 'ord_never_read',
      );
      expect(submitted.outcome, SubmitAttemptOutcome.transient);
      expect(keys, hasLength(1));
      expect(sleeps, isEmpty);
      expect(submitted.op.submitKeys!.current, keys.single);
    });

    test('in the background the run returns at funded and holds the lease',
        () async {
      final reply = Completer<Result<OrchestraSubmitResponse>>();
      replies = [];
      final r = SettlementRunner(
        store: store,
        clock: () => _now,
        generateId: () => 'id-${++id}',
        submit: (_, key) {
          keys.add(key);
          return reply.future;
        },
        sleep: (d) async => sleeps.add(d),
        findOrder: (_) async => null,
      );
      final result = await r.run(plan(background: true));

      expect(result.orderId, isNull);
      expect(result.registration, isNotNull);
      final operationId = result.operation.operationId;
      expect((await store.get(operationId))!.stage, SettlementStage.funded);
      // The reconciler sees a live owner and plans no second submit.
      expect(store.isLeased(operationId), isTrue);
      final state = (await store.get(operationId))!
          .toReconcileState(ownedByLiveFlow: store.isLeased(operationId));
      final reconcile = planSettlementReconcile(state,
          now: _now, sessionUnlocked: true, foregroundedAt: _now);
      expect(reconcile.submitDeposit, isFalse);

      reply.complete(_accepted('ord_bg'));
      expect(await result.registration, 'ord_bg');
      expect(store.isLeased(operationId), isFalse);
      final stored = await store.get(operationId);
      expect(stored!.stage, SettlementStage.submitted);
      expect(stored.orderId, 'ord_bg');
    });

    test('409 in progress keeps the key and gets no new-key resubmit',
        () async {
      replies = [_inProgress, () => _accepted('ord_never')];
      final result = await runner().run(plan());

      expect(result.registered, isFalse);
      expect(keys, hasLength(1));
      expect(sleeps, isEmpty);
      expect(lookups, 0);
      final stored = (await store.get(result.operation.operationId))!;
      expect(stored.stage, SettlementStage.funded);
      // The reconciler's later check sends the SAME key.
      expect(stored.submitKeys!.current, keys.single);
      expect(stored.submitKeys!.history, isEmpty);
    });

    test('a source-chain proof always registers in the background', () async {
      final reply = Completer<Result<OrchestraSubmitResponse>>();
      final r = SettlementRunner(
        store: store,
        clock: () => _now,
        generateId: () => 'id-${++id}',
        submit: (_, key) {
          keys.add(key);
          return reply.future;
        },
        sleep: (d) async => sleeps.add(d),
        findOrder: (_) async => null,
      );
      final base = plan();
      final relayerPlan = SettlementPlan(
        walletId: base.walletId,
        flow: SettlementFlow.movePredictionsToDollars,
        route: base.route,
        sourceAccount: base.sourceAccount,
        destinationAccount: base.destinationAccount,
        payer: base.payer,
        resolveOwnership: base.resolveOwnership,
        requestQuote: base.requestQuote,
        fund: (_, __) async => const SettlementFundingProof.relayer('0xhash'),
      );
      final result = await r.run(relayerPlan);
      expect(result.registration, isNotNull);
      expect(result.orderId, isNull);
      expect(store.isLeased(result.operation.operationId), isTrue);
      reply.complete(_accepted('ord_evm'));
      expect(await result.registration, 'ord_evm');
      expect(store.isLeased(result.operation.operationId), isFalse);
    });

    test('a Ledger EVM submit runs in the background holding the operation',
        () async {
      final op = await store.create(SettlementOperation(
        operationId: 'ledger-op',
        walletId: 'ledger',
        accountKind: SettlementAccountKind.hlLedger,
        flow: SettlementFlow.investingToLedgerBtc,
        route: RouteKey(
            fromChain: 'hypercore',
            fromAsset: 'USDC',
            toChain: 'bitcoin',
            toAsset: 'BTC'),
        amountInBaseUnits: '1000000',
        quote: settlementQuoteTermsFor(quote, skew: Duration.zero),
        funding: const SettlementFunding(
            kind: SettlementFundingKind.hyperliquid, evmTxHash: '0xusdsend'),
        keys: const SettlementKeys(submit: 'persisted-submit-key'),
        stage: SettlementStage.funded,
        recoveredFrom: 'test',
        createdAt: _now,
        updatedAt: _now,
      ));
      expect(settlementProofIsEvm(op), isTrue);
      final reply = Completer<Result<OrchestraSubmitResponse>>();
      final records = LedgerSettlementRecords(
        store: () async => store,
        clock: () => _now,
        submit: (_, key) {
          keys.add(key);
          return reply.future;
        },
        sleep: (d) async => sleeps.add(d),
        findOrder: (_) async => null,
      );
      await records.hold(op.operationId);
      final submitted = await records.submit(op.operationId);
      // The flow is answered at once; the submit is still in flight.
      expect(submitted.accepted, isFalse);
      await records.release(op.operationId);
      expect(store.isLeased(op.operationId), isTrue,
          reason: 'the background submit holds it now');
      reply.complete(_accepted('ord_ledger'));
      await records.debugBackgroundSubmitsIdle();
      expect(store.isLeased(op.operationId), isFalse);
      final stored = (await store.get(op.operationId))!;
      expect(stored.stage, SettlementStage.submitted);
      expect(stored.orderId, 'ord_ledger');
      expect(keys, ['persisted-submit-key']);
    });

    test('background analytics wait for the order id, else the quote id',
        () async {
      final ids = <String>[];
      replies = [() => _accepted('ord_late')];
      final registered = await runner().run(plan(background: true));
      withSettlementOrderId(registered, ids.add);
      expect(ids, isEmpty, reason: 'nothing before the submit returns');
      await registered.registration;
      await Future<void>.delayed(Duration.zero);
      expect(ids, ['ord_late']);

      keys.clear();
      replies = [_refused, _refused, _refused, _refused];
      final unregistered = await runner().run(plan(background: true));
      withSettlementOrderId(unregistered, ids.add);
      await unregistered.registration;
      await Future<void>.delayed(Duration.zero);
      expect(ids.last, unregistered.quote.quoteId);

      // Inline runs report at once.
      final inline = <String>[];
      keys.clear();
      replies = [() => _accepted('ord_inline')];
      withSettlementOrderId(await runner().run(plan()), inline.add);
      expect(inline, ['ord_inline']);
    });

    test('a background submit that fails leaves the reconciler in charge',
        () async {
      replies = [_refused, _refused, _refused, _refused];
      final result = await runner().run(plan(background: true));
      expect(await result.registration, isNull);
      final operationId = result.operation.operationId;
      expect(store.isLeased(operationId), isFalse);
      final stored = (await store.get(operationId))!;
      expect(stored.stage, SettlementStage.funded);
      // The reconciler's first submit is due 30 s after the burst, as
      // after any single failed submit.
      final state = stored.toReconcileState(ownedByLiveFlow: false);
      expect(
          planSettlementReconcile(state,
                  now: _now.add(const Duration(seconds: 20)),
                  sessionUnlocked: true,
                  foregroundedAt: _now)
              .submitDeposit,
          isFalse);
      expect(
          planSettlementReconcile(state,
                  now: _now.add(const Duration(seconds: 30)),
                  sessionUnlocked: true,
                  foregroundedAt: _now)
              .submitDeposit,
          isTrue);
    });
  });
}

/// One attempt per call, so a 5xx is not retried in real time here.
class IdempotentRetryPolicyForTest extends IdempotentRetryPolicy {
  const IdempotentRetryPolicyForTest() : super(maxAttempts: 1);
}

/// Runs [plan] with every submit refused, leaving it funded.
Future<SettlementOperation> _fundedOperation(
    SettlementRunner runner, SettlementPlan plan, SettlementStore store) async {
  final result = await runner.run(plan);
  final op = await store.get(result.operation.operationId);
  expect(op!.stage, SettlementStage.funded);
  return op;
}
