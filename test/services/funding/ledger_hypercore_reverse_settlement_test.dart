import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/handlers/response_handlers.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/bitcoin/ledger_btc_send_service.dart';
import 'package:kute/services/funding/ledger_hypercore_funding_service.dart';
import 'package:kute/services/funding/settlement_funding_outcome.dart';
import 'package:kute/services/hyperliquid/hypercore_activation_fee.dart';
import 'package:kute/services/funding/ledger_settlement.dart';
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';

const _evm = '0x1111111111111111111111111111111111111111';
const _deposit = '0x2222222222222222222222222222222222222222';
const _btc = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
const _hash =
    '0x3333333333333333333333333333333333333333333333333333333333333333';
final _wallet = WalletConfig(
    id: 'ledger-1',
    name: 'Ledger',
    isHardware: true,
    walletType: 'ledger',
    sparkEnabled: false,
    evmAddress: _evm,
    evmVerifiedAtMs: 1,
    scriptType: 'bip84');

class _Availability implements FundingRouteAvailability {
  @override
  Future<RouteAvailability> availability(RouteKey route) async =>
      RouteAvailability.available;
}

class _Source implements HypercoreReverseSourceSend {
  _Source(this.send, {this.internal});
  final Future<void> Function(Future<void> Function())? internal;
  final Future<String> Function(Future<void> Function(int nonce)) send;
  @override
  bool get isReady => true;
  @override
  int get deviceConfirmations => 1;
  @override
  Future<BigInt> activationFeeForDestination(String depositAddress) async =>
      BigInt.zero;
  @override
  Future<String> sendToDeposit(
      {required String walletId,
      required String evmAddress,
      required String depositAddress,
      required BigInt amountBaseUnits,
      required BigInt reviewedActivationFeeBaseUnits,
      required String quoteId,
      required LedgerHypercoreApproval approve,
      required Future<void> Function() onBeforeInternalSend,
      required Future<void> Function(int nonce) onBeforeSend}) async {
    expect(LedgerOperationScope.currentWalletId, _wallet.id);
    expect(evmAddress, _evm);
    expect(depositAddress, _deposit);
    await internal?.call(onBeforeInternalSend);
    return send(onBeforeSend);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late SettlementStore store;
  late DateTime now;
  late LedgerBtcSendService btc;
  late LedgerVerifiedBtcAddress recipient;
  late LedgerSettlementRecords records;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('ledger_reverse');
    Hive.init(temporary.path);
    now = DateTime.utc(2026, 9, 22, 12);
    store = SettlementStore(
        box: await Hive.openBox<String>('operations'),
        quarantine: await Hive.openBox<String>('quarantine'),
        clock: () => now);
    records = LedgerSettlementRecords(
        store: () async => store,
        clock: () => now,
        newId: () => 'operation-1',
        submit: (op, key) async {
          expect(op.funding!.hlNonce, 77);
          expect(op.funding!.evmTxHash, _hash);
          expect(op.recipient!.address, _btc);
          expect(op.refund!.address, _evm);
          return Result<OrchestraSubmitResponse>(
              data: OrchestraSubmitResponse(
                  orderId: 'order-1', status: 'processing'),
              statusCode: 200);
        });
    btc = LedgerBtcSendService(
        modelFor: (_) async => throw UnimplementedError(),
        signPsbt: (_,
                {required scriptType, required expectedFingerprint}) async =>
            throw UnimplementedError(),
        displayAddress: ({required scriptType, required addressIndex}) async =>
            _btc,
        clock: () => now);
    recipient = await LedgerOperationScope.run(
        _wallet.id,
        () =>
            btc.verifyReceiveAddress(wallet: _wallet, address: _btc, index: 0));
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await temporary.delete(recursive: true);
  });

  LedgerHypercoreFundingService service(_Source source) =>
      LedgerHypercoreFundingService(
        btcSend: btc,
        records: records,
        availability: _Availability(),
        reverseSource: source,
        clock: () => now,
        fetchQuote: (request, {required usdPerBtc, required flow}) async {
          final quote = OrchestraQuote.fromJson({
            'quoteId': 'quote-1',
            'depositAddress': _deposit,
            'amountIn': request.amountBaseUnits.toString(),
            'estimatedOut': '16600',
            'feeAmount': '10',
            'feeBps': 20,
            'route': ['hypercore', 'bitcoin'],
            'expiresAt': now.add(const Duration(minutes: 2)).toIso8601String(),
          });
          return (
            quote: verifyOrchestraQuote(request, quote,
                now: now,
                bounds: OrchestraQuoteBounds.forSource('hypercore',
                    inputValueInOutputUnits: 16666),
                mainnet: true),
            skew: Duration.zero
          );
        },
      );

  Future<HypercoreLedgerWithdrawReview> review(
          LedgerHypercoreFundingService s) =>
      LedgerOperationScope.run(
          _wallet.id,
          () => s.quoteReverse(
              wallet: _wallet,
              amountBaseUnits: BigInt.from(1000000000),
              recipient: recipient,
              usdPerBtc: 60000));

  test(
      'native nonce is on disk before sending; funded proof keeps Ledger ownership',
      () async {
    final s = service(_Source((beforePost) async {
      await beforePost(77);
      final op = await store.get('operation-1');
      expect(op!.stage, SettlementStage.broadcasting);
      expect(op.funding!.kind, SettlementFundingKind.hyperliquid);
      expect(op.funding!.hlNonce, 77);
      return _hash;
    }));
    final r = await review(s);
    final result = await LedgerOperationScope.run(
        _wallet.id,
        () => s.executeReverse(r,
            approve: (_, {onBeforeSend, beforeSend}) async => throw UnimplementedError()));
    expect(result, isA<LedgerFundingSubmitted>());
    expect((await store.get(r.operationId))!.stage, SettlementStage.submitted);
  });

  test('quote expiring during approval abandons without an external POST',
      () async {
    var posted = false;
    final s = service(_Source((beforePost) async {
      now = now.add(const Duration(seconds: 110));
      await beforePost(77);
      posted = true;
      return _hash;
    }));
    final r = await review(s);
    final result = await LedgerOperationScope.run(
        _wallet.id,
        () => s.executeReverse(r,
            approve: (_, {onBeforeSend, beforeSend}) async => throw UnimplementedError()));
    expect(result, isA<LedgerFundingQuoteExpired>());
    expect(posted, isFalse);
    expect((await store.get(r.operationId))!.stage, SettlementStage.abandoned);
  });

  test('refusal abandons; unknown POST retains nonce for reconciliation',
      () async {
    var afterPost = false;
    final s = service(_Source((beforePost) async {
      if (!afterPost) throw const LedgerFailure(LedgerFailureCode.rejected);
      await beforePost(77);
      throw StateError('response lost');
    }));
    final first = await review(s);
    await expectLater(
        LedgerOperationScope.run(
            _wallet.id,
            () => s.executeReverse(first,
                approve: (_, {onBeforeSend, beforeSend}) async =>
                    throw UnimplementedError())),
        throwsA(isA<LedgerFailure>()));
    expect(
        (await store.get(first.operationId))!.stage, SettlementStage.abandoned);
    // A fresh independent operation after restarting the in-memory test store.
    await Hive.box<String>('operations').clear();
    afterPost = true;
    final second = await review(s);
    await expectLater(
        LedgerOperationScope.run(
            _wallet.id,
            () => s.executeReverse(second,
                approve: (_, {onBeforeSend, beforeSend}) async =>
                    throw UnimplementedError())),
        throwsA(isA<LedgerFundingOutcomeUnknown>()));
    final persisted = await store.get(second.operationId);
    expect(persisted!.stage, SettlementStage.fundingUnknown);
    expect(persisted.funding!.hlNonce, 77);
    await expectLater(review(s), throwsA(anything),
        reason: 'unknown funding blocks a new quote');
  });
  test('confirmed internal move followed by refusal records notFunded', () async {
    final s = service(_Source((_) async {
      throw const SettlementFundingRefused(HypercoreActivationFeeChanged());
    }, internal: (beforeInternal) async => beforeInternal()));
    final r = await review(s);
    await expectLater(
        LedgerOperationScope.run(_wallet.id,
            () => s.executeReverse(r, approve: (_, {onBeforeSend, beforeSend}) async =>
                throw UnimplementedError())),
        throwsA(isA<HypercoreActivationFeeChanged>()));
    final persisted = await store.get(r.operationId);
    expect(persisted!.stage, SettlementStage.notFunded);
    expect(persisted.funding?.hlNonce, isNull);
  });

  test('unknown internal move blocks without inventing an external nonce', () async {
    final s = service(_Source((_) async => fail('no external send'),
        internal: (beforeInternal) async {
      await beforeInternal();
      throw StateError('internal response lost');
    }));
    final r = await review(s);
    await expectLater(
        LedgerOperationScope.run(_wallet.id,
            () => s.executeReverse(r, approve: (_, {onBeforeSend, beforeSend}) async =>
                throw UnimplementedError())),
        throwsA(isA<LedgerFundingOutcomeUnknown>()));
    final persisted = await store.get(r.operationId);
    expect(persisted!.stage, SettlementStage.fundingUnknown);
    expect(persisted.funding?.hlNonce, isNull);
    await expectLater(review(s), throwsA(anything));
  });

}
