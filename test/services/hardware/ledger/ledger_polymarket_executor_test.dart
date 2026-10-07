import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:kute/services/hardware/ledger/deposit_wallet_call_allowlist.dart';
import 'package:kute/services/hardware/ledger/ledger_action_intent.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/ledger/ledger_hyperliquid_executor.dart'
    show LedgerSubmissionUnknownException;
import 'package:kute/services/hardware/ledger/ledger_polymarket_executor.dart';
import 'package:kute/services/hardware/ledger/ledger_submitted_action_store.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'package:kute/services/polymarket/deposit_wallet_batch_signer.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';
import 'package:kute/services/polymarket_order_v2.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show ApiCredentials, EthPrivateKey, OrderType;

final _key = EthPrivateKey.fromHex(
    '0x0123456789012345678901234567890101234567890123456789012345678901');
final _eoa = _key.address.hexEip55;
const _wallet = '0x5555555555555555555555555555555555555555';
const _orchestra = '0x7777777777777777777777777777777777777777';
const _condition =
    '0xc0ffee00c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00';

class _FakeClob implements LedgerPolymarketClob {
  final derives = <Map<String, String>>[];
  Object? deriveError;
  final submitted = <SignedOrderV2>[];
  final cancels = <String>[];
  final authAddresses = <String>[];
  Map<String, dynamic> Function(SignedOrderV2 order)? respond;

  @override
  Future<ApiCredentials> deriveApiKey(Map<String, String> l1Headers) async {
    derives.add(l1Headers);
    if (deriveError != null) throw deriveError!;
    return const ApiCredentials(apiKey: 'k', secret: 'c2VjcmV0', passphrase: 'p');
  }

  @override
  Future<Map<String, dynamic>> submitOrder({
    required ApiCredentials credentials,
    required String polyAddress,
    required SignedOrderV2 order,
    required OrderType orderType,
  }) async {
    authAddresses.add(polyAddress);
    submitted.add(order);
    return respond!(order);
  }

  @override
  Future<void> cancelOrder({
    required ApiCredentials credentials,
    required String polyAddress,
    required String orderId,
  }) async {
    authAddresses.add(polyAddress);
    cancels.add(orderId);
  }
}

class _FakeRelayer implements LedgerPolymarketRelayer {
  Future<String> Function(
    List<DepositWalletCall> calls,
    Future<void> Function(String) beforeSubmit,
    Future<void> Function(String) onSubmitted,
  )? handler;
  final batches = <List<DepositWalletCall>>[];
  ({String state, String? hash})? state;

  @override
  Future<String> executeBatch({
    required String eoa,
    required DepositWalletBatchSigner signer,
    required String wallet,
    required List<DepositWalletCall> calls,
    required int deadline,
    required Future<void> Function(String relayerNonce) beforeSubmit,
    required Future<void> Function(String relayerTxId) onSubmitted,
  }) {
    batches.add(calls);
    return handler!(calls, beforeSubmit, onSubmitted);
  }

  @override
  Future<({String state, String? hash})?> transactionState(String txId) async =>
      state;
}

class _MemoryCredentials implements LedgerCredentialStorage {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _FailingFlushBox implements Box<String> {
  _FailingFlushBox(this.inner);
  final Box<String> inner;
  bool fail = false;
  @override
  Iterable<dynamic> get keys => inner.keys;
  @override
  String? get(dynamic key, {String? defaultValue}) =>
      inner.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, String value) => inner.put(key, value);
  @override
  Future<void> flush() async {
    if (fail) throw StateError('disk unavailable');
    await inner.flush();
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  _Harness({
    PolymarketLedgerAccount account = const PolymarketLedgerAccount.depositWallet(
        _wallet, DepositWalletVariant.beacon),
    bool withdrawEnabled = false,
    bool Function(String)? belongsToLedger,
    LedgerPolymarketRelayer? relayer,
    Completer<void>? holdSign,
    LedgerSubmittedActionStore? actionStore,
    Future<void> Function(String capability)? checkCapability,
  }) : store = actionStore ?? LedgerSubmittedActionStore() {
    executor = LedgerPolymarketExecutor(
      walletId: 'ledger-1',
      pairedAddress: _eoa,
      signer: EvmExternalSigner(
        address: _eoa,
        sign: (request) async {
          prompts.add(request);
          if (!signStarted.isCompleted) signStarted.complete();
          if (holdSign != null) await holdSign.future;
          return _key.signToSignature(request.digest);
        },
      ),
      account: account,
      store: store,
      clob: clob,
      relayer: relayer ?? this.relayer,
      credentials: credentials,
      withdrawEnabled: withdrawEnabled,
      belongsToLedger: belongsToLedger,
      checkCapability: checkCapability,
      clock: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
  }

  final LedgerSubmittedActionStore store;
  final clob = _FakeClob();
  final relayer = _FakeRelayer();
  final credentials = _MemoryCredentials();
  final prompts = <EvmSigningRequest>[];
  final signStarted = Completer<void>();
  late final LedgerPolymarketExecutor executor;
}

LedgerActionIntent _sell() => LedgerPolymarketIntents.sell(
      walletId: 'ledger-1',
      depositWallet: _wallet,
      tokenId: '123456789',
      shares: BigInt.from(5000000),
      minProceeds: BigInt.from(2400000),
      negRisk: false,
      salt: BigInt.from(987654321),
      timestampMs: 1700000000000,
      orderType: OrderType.fok,
      builderCode: '0x${'ab' * 32}',
      summary: const {'market': 'Will it rain?', 'outcome': 'Yes'},
    );

LedgerActionIntent _redeem() => LedgerPolymarketIntents.redeem(
      walletId: 'ledger-1',
      depositWallet: _wallet,
      conditionId: _condition,
      negRisk: false,
      summary: const {'market': 'Will it rain?'},
    );

LedgerActionIntent _withdraw() => LedgerPolymarketIntents.withdraw(
      walletId: 'ledger-1',
      depositWallet: _wallet,
      amount: BigInt.from(1000000),
      binding: const LedgerWithdrawalBinding(
        depositAddress: _orchestra,
        refundAddress: _wallet,
        recipientAddress: 'bc1qledgerrecipient',
      ),
      summary: const {'amount': '1.00 USDC'},
    );

DepositWalletCall _call(String target, String data) =>
    (target: target, value: BigInt.zero, data: data);

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ledger_pm_executor');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  group('allowlist', () {
    DepositWalletCallAllowlist allowlist({bool withdraw = false}) =>
        DepositWalletCallAllowlist(
          depositWallet: _wallet,
          withdrawEnabled: withdraw,
          withdrawalBinding: const LedgerWithdrawalBinding(
            depositAddress: _orchestra,
            refundAddress: _wallet,
            recipientAddress: 'bc1qledgerrecipient',
          ),
          belongsToLedger: (a) => a == _wallet || a == 'bc1qledgerrecipient',
        );

    Matcher rejected(String reason) => throwsA(isA<DepositWalletCallRejected>()
        .having((e) => e.reason, 'reason', contains(reason)));

    test('allows the pinned wrap, unwrap and redeem calls', () {
      final ops = allowlist().validate([
        _call(PolymarketConstants.usdcEAddress,
            encodeApproveCall(PolymarketConstants.collateralOnrampAddress, BigInt.one)),
        _call(PolymarketConstants.collateralOnrampAddress,
            encodeWrapCall(PolymarketConstants.usdcEAddress, _wallet, BigInt.one)),
        _call(PolymarketConstants.collateralOfframpAddress,
            encodeUnwrapCall(PolymarketConstants.usdcEAddress, _wallet, BigInt.one)),
        _call(PolymarketConstants.negRiskCtfCollateralAdapterAddress,
            encodeAdapterRedeemCall(_condition)),
      ]);
      expect(ops, [
        DepositWalletCallOp.approve,
        DepositWalletCallOp.wrap,
        DepositWalletCallOp.unwrap,
        DepositWalletCallOp.redeem,
      ]);
    });

    test('allows the unwrap batch the funding service validates', () {
      expect(allowlist().validate(ledgerPmUnwrapCalls(_wallet, BigInt.two)), [
        DepositWalletCallOp.approve,
        DepositWalletCallOp.unwrap,
      ]);
    });

    test('allows the one-time share approvals for all five operators', () {
      expect(
          ledgerPmShareOperators.map((o) => o.toLowerCase()),
          unorderedEquals([
            for (final o in [
              PolymarketConstants.exchangeAddress,
              PolymarketConstants.negRiskExchangeAddress,
              PolymarketConstants.legacyNegRiskAdapterAddress,
              PolymarketConstants.ctfCollateralAdapterAddress,
              PolymarketConstants.negRiskCtfCollateralAdapterAddress,
            ])
              o.toLowerCase()
          ]));
      expect(
          allowlist()
              .validate(ledgerPmShareApprovalCalls(ledgerPmShareOperators)),
          List.filled(5, DepositWalletCallOp.setApprovalForAll));
    });

    test('allows approvals to the CLOB v1 Neg Risk Adapter but never a redeem',
        () {
      // Labelled deprecated (redeems ended 2026-07-17), but the CLOB still
      // checks pUSD and CTF approvals to it for neg-risk orders.
      const legacy = PolymarketConstants.legacyNegRiskAdapterAddress;
      final operatorWord = legacy.toLowerCase().substring(2).padLeft(64, '0');
      final setApprovalForAll = '0x$kSelectorSetApprovalForAll$operatorWord'
          '${BigInt.one.toRadixString(16).padLeft(64, '0')}';
      expect(
          allowlist().validate([
            _call(PolymarketConstants.pusdAddress,
                encodeApproveCall(legacy, BigInt.one)),
            _call(PolymarketConstants.ctfAddress, setApprovalForAll),
          ]),
          hasLength(2));
      expect(
          () => allowlist().validate([
                _call(legacy, encodeAdapterRedeemCall(_condition)),
              ]),
          rejected('redeem target not pinned'));
    });

    test('rejects an unknown target', () {
      expect(
          () => allowlist().validate([
                _call('0x${'99' * 20}',
                    encodeApproveCall(PolymarketConstants.exchangeAddress, BigInt.one)),
              ]),
          rejected('approve target not pinned'));
    });

    test('rejects an unknown selector', () {
      expect(
          () => allowlist().validate(
              [_call(PolymarketConstants.usdcEAddress, '0xdeadbeef${'0' * 64}')]),
          rejected('selector not allowed'));
    });

    test('rejects an unpinned spender', () {
      expect(
          () => allowlist().validate([
                _call(PolymarketConstants.pusdAddress,
                    encodeApproveCall('0x${'66' * 20}', BigInt.one)),
              ]),
          rejected('spender not pinned'));
    });

    test('rejects a wrap to someone else', () {
      expect(
          () => allowlist().validate([
                _call(PolymarketConstants.collateralOnrampAddress,
                    encodeWrapCall(PolymarketConstants.usdcEAddress, _orchestra, BigInt.one)),
              ]),
          rejected('recipient is not this wallet'));
    });

    test('rejects an unbound transfer recipient and transfers with O3 off',
        () {
      final toOrchestra = _call(PolymarketConstants.usdcEAddress,
          encodeTransferCall(_orchestra, BigInt.one));
      expect(() => allowlist().validate([toOrchestra]),
          rejected('withdrawal is disabled'));
      expect(allowlist(withdraw: true).validate([toOrchestra]),
          [DepositWalletCallOp.transfer]);
      expect(
          () => allowlist(withdraw: true).validate([
                _call(PolymarketConstants.usdcEAddress,
                    encodeTransferCall('0x${'88' * 20}', BigInt.one)),
              ]),
          rejected('not the bound deposit address'));
      expect(
          () => DepositWalletCallAllowlist(
                depositWallet: _wallet,
                withdrawEnabled: true,
                withdrawalBinding: LedgerWithdrawalBinding(
                  depositAddress: _orchestra,
                  refundAddress: '0x${'44' * 20}',
                  recipientAddress: 'bc1qledgerrecipient',
                ),
                belongsToLedger: (a) => a == 'bc1qledgerrecipient',
              ).validate([toOrchestra]),
          rejected('refund or recipient'));
    });

    test('rejects value, dirty words and malformed calldata', () {
      expect(
          () => allowlist().validate([
                (
                  target: PolymarketConstants.usdcEAddress,
                  value: BigInt.one,
                  data: encodeApproveCall(
                      PolymarketConstants.exchangeAddress, BigInt.one),
                ),
              ]),
          rejected('non-zero value'));
      expect(
          () => allowlist().validate([
                _call(PolymarketConstants.usdcEAddress,
                    '0x$kSelectorApprove${'f' * 24}${'1' * 40}${'0' * 64}'),
              ]),
          rejected('dirty address word'));
      expect(
          () => allowlist().validate(
              [_call(PolymarketConstants.usdcEAddress, '0x095ea7b3abc')]),
          rejected('malformed'));
    });
  });

  group('executor', () {
    test('withdrawal is refused with O3 off before any prompt', () async {
      final h = _Harness();
      expect(() => h.executor.withdraw(_withdraw()),
          throwsA(isA<LedgerActionBlockedException>()));
      expect(h.prompts, isEmpty);
      expect(h.relayer.batches, isEmpty);
    });

    test('a transfer whose refund is not this Ledger is rejected before any '
        'prompt, even with O3 on', () async {
      final h = _Harness(withdrawEnabled: true, belongsToLedger: (_) => false);
      expect(() => h.executor.withdraw(_withdraw()),
          throwsA(isA<DepositWalletCallRejected>()));
      expect(h.prompts, isEmpty);
      expect(h.relayer.batches, isEmpty);
    });

    test('credentials are keyed by the Ledger wallet ID and ClobAuth runs '
        'once', () async {
      final h = _Harness();
      h.clob.respond = (order) => {
            'success': true,
            'orderID': exchangeOrderId(
                order.order, PolymarketConstants.exchangeAddress),
            'status': 'matched',
          };

      await h.executor.sell(_sell());
      expect(h.credentials.values.keys, ['pm_api_credentials_ledger-1']);
      expect(h.clob.derives.single['POLY_ADDRESS'], _eoa);
      expect(h.clob.derives.single['POLY_NONCE'], '0');
      expect(h.clob.derives.single['POLY_SIGNATURE'], hasLength(132));
      expect(h.clob.authAddresses.single, _eoa);
      expect(h.clob.submitted.single.order.signer, _wallet);
      final stored = jsonDecode(h.credentials.values.values.single);
      expect(stored['ownerAddress'], _eoa);
      expect(stored['authAddress'], _eoa);
      expect(h.prompts.map((p) => p.kind),
          [LedgerActionKind.pmClobAuth, LedgerActionKind.pmOrder]);

      await h.executor.sell(_sell());
      expect(h.clob.derives, hasLength(1));
      expect(h.prompts, hasLength(3));
    });

    test('EOA credential binding survives a new executor for cancellation', () async {
      final h = _Harness();
      h.credentials.values['pm_api_credentials_ledger-1'] = jsonEncode({
        'apiKey': 'k', 'secret': 's', 'passphrase': 'p', 'nonce': 0,
        'authAddress': _eoa, 'ownerAddress': _eoa,
      });
      await h.executor.cancelOrder('existing-order');
      expect(h.clob.authAddresses.single, _eoa);
      expect(h.prompts, isEmpty);
    });

    test('legacy wallet-bound credentials retain cancellation access', () async {
      final h = _Harness();
      h.credentials.values['pm_api_credentials_ledger-1'] = jsonEncode({
        'apiKey': 'k', 'secret': 's', 'passphrase': 'p', 'nonce': 12,
      });
      await h.executor.cancelOrder('legacy-order');
      expect(h.clob.authAddresses.single, _wallet);
      expect(h.prompts, isEmpty);
    });

    test('a new trade upgrades legacy wallet-bound auth without changing order identity', () async {
      final h = _Harness();
      h.credentials.values['pm_api_credentials_ledger-1'] = jsonEncode({
        'apiKey': 'legacy', 'secret': 's', 'passphrase': 'p', 'nonce': 12,
      });
      h.clob.respond = (order) => {
        'success': true,
        'orderID': exchangeOrderId(order.order, PolymarketConstants.exchangeAddress),
        'status': 'matched',
      };
      await h.executor.sell(_sell());
      expect(h.clob.derives.single['POLY_ADDRESS'], _eoa);
      expect(h.clob.authAddresses.single, _eoa);
      expect(h.clob.submitted.single.order.signer, _wallet);
      expect(h.clob.submitted.single.order.maker, _wallet);
      expect(h.prompts.map((p) => p.kind),
          [LedgerActionKind.pmClobAuth, LedgerActionKind.pmOrder]);
    });

    test('failed auth upgrade preserves cached cancellation credentials', () async {
      final h = _Harness();
      final legacy = jsonEncode({
        'apiKey': 'legacy', 'secret': 's', 'passphrase': 'p', 'nonce': 12,
      });
      h.credentials.values['pm_api_credentials_ledger-1'] = legacy;
      h.clob.deriveError = const SocketException('offline');
      await expectLater(h.executor.sell(_sell()), throwsA(isA<SocketException>()));
      expect(h.credentials.values['pm_api_credentials_ledger-1'], legacy);
      expect(h.clob.submitted, isEmpty);
      await h.executor.cancelOrder('old-order');
      expect(h.clob.authAddresses.single, _wallet);
    });

    test('credentials for a different EOA cannot be reused', () async {
      final h = _Harness();
      h.credentials.values['pm_api_credentials_ledger-1'] = jsonEncode({
        'apiKey': 'k', 'secret': 's', 'passphrase': 'p',
        'authAddress': _eoa, 'ownerAddress': _orchestra,
      });
      await expectLater(h.executor.cancelOrder('old-order'),
          throwsA(isA<LedgerPolymarketAuthException>()));
      expect(h.clob.cancels, isEmpty);
      expect(h.prompts, isEmpty);
    });

    test('the recorded order ID is the Exchange-domain Order hash', () async {
      final h = _Harness();
      h.clob.respond = (order) => {
            'success': true,
            'orderID': exchangeOrderId(
                order.order, PolymarketConstants.exchangeAddress),
            'status': 'live',
          };
      final result = await h.executor.sell(_sell());

      final signed = h.clob.submitted.single;
      expect(signed.order.signatureType, 3);
      expect(signed.order.maker, _wallet);
      expect(signed.order.signer, _wallet);
      final expected = orderV2TypedData(
              order: signed.order,
              verifyingContract: PolymarketConstants.exchangeAddress)
          .digest;
      final expectedHex =
          '0x${expected.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
      expect(result.orderId, expectedHex);
      // Not the wrapped TypedDataSign digest the device signed.
      final deviceDigest = h.prompts.last.digest;
      expect(expectedHex,
          isNot('0x${deviceDigest.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}'));
      final record =
          await h.store.get('ledger-1', 'pm-order-$expectedHex');
      expect(record!.orderId, expectedHex);
      expect(record.stage, LedgerSubmissionStage.accepted);
    });

    test('a sell signs the backend builder code it was reviewed with',
        () async {
      for (final code in ['0x${'ab' * 32}', PolymarketConstants.bytes32Zero]) {
        final h = _Harness();
        h.clob.respond = (order) => {
              'success': true,
              'orderID': exchangeOrderId(
                  order.order, PolymarketConstants.exchangeAddress),
              'status': 'live',
            };
        final intent = LedgerPolymarketIntents.sell(
          walletId: 'ledger-1',
          depositWallet: _wallet,
          tokenId: '123456789',
          shares: BigInt.from(5000000),
          minProceeds: BigInt.from(2400000),
          negRisk: false,
          salt: BigInt.from(987654321),
          timestampMs: 1700000000000,
          orderType: OrderType.fok,
          builderCode: code,
          summary: const {'market': 'Will it rain?', 'outcome': 'Yes'},
        );
        await h.executor.sell(intent);
        final order = h.clob.submitted.single.order;
        expect(order.side, 1);
        expect(order.builder, code);
      }
    });

    test('a different response order ID is recorded as a mismatch', () async {
      final h = _Harness();
      h.clob.respond = (_) => {'success': true, 'orderID': '0x${'00' * 32}'};
      await expectLater(h.executor.sell(_sell()),
          throwsA(isA<LedgerOrderIdMismatchException>()));
      final records = await h.store.forWallet('ledger-1');
      expect(records.single.stage, LedgerSubmissionStage.orderIdMismatch);
    });

    test('the batch record is written before the relayer submit', () async {
      final h = _Harness();
      h.relayer.handler = (calls, beforeSubmit, onSubmitted) async {
        await beforeSubmit('41');
        final record = await h.store.get('ledger-1', 'pm-batch-41');
        expect(record!.stage, LedgerSubmissionStage.submitting);
        expect(record.relayerNonce, '41');
        await onSubmitted('tx-1');
        return '0xhash';
      };
      expect(await h.executor.redeem(_redeem()), '0xhash');
      final record = await h.store.get('ledger-1', 'pm-batch-41');
      expect(record!.stage, LedgerSubmissionStage.confirmed);
      expect(record.relayerTxId, 'tx-1');
      expect(h.relayer.batches.single.single.target,
          PolymarketConstants.ctfCollateralAdapterAddress);
    });

    test('a relayer timeout after submit is unknown and reconcile never '
        're-signs', () async {
      final h = _Harness();
      h.relayer.handler = (calls, beforeSubmit, onSubmitted) async {
        await beforeSubmit('42');
        await onSubmitted('tx-2');
        throw TimeoutException('poll');
      };
      await expectLater(h.executor.redeem(_redeem()),
          throwsA(isA<LedgerSubmissionUnknownException>()));
      expect((await h.store.get('ledger-1', 'pm-batch-42'))!.stage,
          LedgerSubmissionStage.submittedUnknown);

      h.relayer.state = (state: 'STATE_CONFIRMED', hash: '0x${'a' * 64}');
      expect(await h.executor.reconcileBatch('pm-batch-42'),
          LedgerSubmissionStage.confirmed);
      expect(h.relayer.batches, hasLength(1));
    });

    for (final message in ['status request failed', 'RPC reverted its response']) {
      test('post-submit error text cannot reject an uncertain batch: $message',
          () async {
        final h = _Harness();
        h.relayer.handler = (calls, beforeSubmit, onSubmitted) async {
          await beforeSubmit('42');
          await onSubmitted('tx-2');
          throw StateError(message);
        };
        await expectLater(h.executor.redeem(_redeem()),
            throwsA(isA<LedgerSubmissionUnknownException>()));
        final record = await h.store.get('ledger-1', 'pm-batch-42');
        expect(record!.stage, LedgerSubmissionStage.submittedUnknown);
        expect(record.relayerTxId, 'tx-2');
        expect(h.relayer.batches, hasLength(1));
      });
    }

    for (final status in [
      (state: 'UNCONFIRMED', hash: '0x${'a' * 64}'),
      (state: 'NOT_CONFIRMED', hash: '0x${'a' * 64}'),
      (state: 'STATE_MINED', hash: '0x${'a' * 64}'),
      (state: 'STATE_EXECUTED', hash: '0x${'a' * 64}'),
      (state: 'STATE_CONFIRMED', hash: 'tx-2'),
      (state: 'STATE_CONFIRMED', hash: null),
      (state: 'ERROR', hash: null),
    ]) {
      test('reconciliation preserves uncertainty for $status', () async {
        final h = _Harness();
        h.relayer.handler = (calls, beforeSubmit, onSubmitted) async {
          await beforeSubmit('42');
          await onSubmitted('tx-2');
          throw TimeoutException('response unavailable');
        };
        await expectLater(h.executor.redeem(_redeem()),
            throwsA(isA<LedgerSubmissionUnknownException>()));
        h.relayer.state = status;
        expect(await h.executor.reconcileBatch('pm-batch-42'),
            LedgerSubmissionStage.submittedUnknown);
        expect(h.relayer.batches, hasLength(1));
      });
    }

    test('an explicit failed relayer state resolves the batch without signing',
        () async {
      final h = _Harness();
      h.relayer.handler = (calls, beforeSubmit, onSubmitted) async {
        await beforeSubmit('42');
        await onSubmitted('tx-2');
        throw TimeoutException('response unavailable');
      };
      await expectLater(h.executor.redeem(_redeem()),
          throwsA(isA<LedgerSubmissionUnknownException>()));
      h.relayer.state = (state: 'STATE_FAILED', hash: null);
      expect(await h.executor.reconcileBatch('pm-batch-42'),
          LedgerSubmissionStage.rejected);
      expect(h.relayer.batches, hasLength(1));
    });

    for (final accepted in [false, true]) {
      test('direct withdrawal survives reopen without resubmission; ID=$accepted',
          () async {
        final first = _Harness(withdrawEnabled: true, belongsToLedger: (_) => true);
        first.relayer.handler = (calls, beforeSubmit, onSubmitted) async {
          await beforeSubmit('42');
          if (accepted) await onSubmitted('tx-2');
          throw TimeoutException('response lost');
        };
        await expectLater(first.executor.withdraw(_withdraw()),
            throwsA(isA<LedgerSubmissionUnknownException>()));
        await Hive.close();

        final reopened = _Harness(withdrawEnabled: true, belongsToLedger: (_) => true);
        await expectLater(reopened.executor.withdraw(_withdraw()),
            throwsA(isA<LedgerSubmissionUnknownException>()));
        expect(reopened.relayer.batches, isEmpty);
        expect(reopened.prompts, isEmpty);
        expect(first.relayer.batches, hasLength(1));
        if (accepted) {
          reopened.relayer.state = (state: 'STATE_CONFIRMED', hash: '0x${'a' * 64}');
          // This tap reports the previous outcome, but never transfers again.
          await expectLater(reopened.executor.withdraw(_withdraw()), throwsStateError);
          expect(reopened.relayer.batches, isEmpty);
          reopened.relayer.handler = (calls, beforeSubmit, onSubmitted) async {
            await beforeSubmit('43');
            await onSubmitted('tx-3');
            return '0x${'b' * 64}';
          };
          expect(await reopened.executor.withdraw(_withdraw()), '0x${'b' * 64}');
          expect(reopened.relayer.batches, hasLength(1));
        }
      });
    }

    test('corrupt persisted batch prevents direct withdrawal before signing', () async {
      final box = await Hive.openBox<String>(LedgerSubmittedActionStore.boxName);
      await box.put('ledger-1|pm-batch-42', '{broken');
      final h = _Harness(withdrawEnabled: true, belongsToLedger: (_) => true);
      await expectLater(h.executor.withdraw(_withdraw()),
          throwsA(isA<LedgerSubmissionUnknownException>()));
      expect(h.relayer.batches, isEmpty);
      expect(h.prompts, isEmpty);
    });

    test('legacy accepted batch is reconciled before a new direct withdrawal', () async {
      final h = _Harness(withdrawEnabled: true, belongsToLedger: (_) => true);
      await h.store.recordBeforeSubmit(LedgerSubmittedAction(
        id: 'pm-batch-42', walletId: 'ledger-1', kind: 'pmWithdrawal',
        paramsHash: _withdraw().paramsHash, stage: LedgerSubmissionStage.accepted,
        submittedAtMs: 1700000000000, relayerNonce: '42', relayerTxId: 'tx-2',
      ));
      h.relayer.state = (state: 'STATE_MINED', hash: '0x${'a' * 64}');
      await expectLater(h.executor.withdraw(_withdraw()),
          throwsA(isA<LedgerSubmissionUnknownException>()));
      expect(h.relayer.batches, isEmpty);
      expect(h.prompts, isEmpty);
    });

    test('a persisted terminal outcome is surfaced after restart before another send',
        () async {
      final box = await Hive.openBox<String>(LedgerSubmittedActionStore.boxName);
      for (final nonce in [1, 2]) {
        final record = LedgerSubmittedAction(
          id: 'pm-batch-$nonce', walletId: 'ledger-1', kind: 'pmWithdrawal',
          paramsHash: _withdraw().paramsHash, stage: LedgerSubmissionStage.confirmed,
          submittedAtMs: nonce, relayerNonce: '$nonce', relayerTxId: 'tx-$nonce',
        );
        // Data already on disk at startup, with no in-process acknowledgement.
        await box.put('ledger-1|pm-batch-$nonce', jsonEncode(record.toJson()));
      }
      await box.close();
      final h = _Harness(withdrawEnabled: true, belongsToLedger: (_) => true);
      expect((await h.store.blockingPolymarketBatch('ledger-1'))!.id, 'pm-batch-2');
      h.relayer.state = (state: 'STATE_CONFIRMED', hash: '0x${'a' * 64}');
      await expectLater(h.executor.withdraw(_withdraw()), throwsStateError);
      expect(h.relayer.batches, isEmpty);
      expect(h.prompts, isEmpty);
      // Older resolved history does not require a separate tap per row.
      expect(await h.store.blockingPolymarketBatch('ledger-1'), isNull);
    });

    test('failed terminal flush cannot authorize another withdrawal via Hive cache',
        () async {
      final box = _FailingFlushBox(
          await Hive.openBox<String>(LedgerSubmittedActionStore.boxName));
      final store = LedgerSubmittedActionStore(openBox: () async => box);
      final h = _Harness(withdrawEnabled: true, belongsToLedger: (_) => true,
          actionStore: store);
      await store.recordBeforeSubmit(LedgerSubmittedAction(
        id: 'pm-batch-42', walletId: 'ledger-1', kind: 'pmWithdrawal',
        paramsHash: _withdraw().paramsHash, stage: LedgerSubmissionStage.submittedUnknown,
        submittedAtMs: 1700000000000, relayerNonce: '42', relayerTxId: 'tx-2',
      ));
      box.fail = true;
      await expectLater(store.updateStage('ledger-1', 'pm-batch-42',
          LedgerSubmissionStage.confirmed), throwsStateError);
      expect((await store.get('ledger-1', 'pm-batch-42'))!.stage,
          LedgerSubmissionStage.confirmed); // The in-memory Hive value changed.
      expect(await store.blockingPolymarketBatch('ledger-1'), isNotNull);
      await expectLater(h.executor.withdraw(_withdraw()), throwsStateError);
      expect(h.relayer.batches, isEmpty);
      expect(h.prompts, isEmpty);
      box.fail = false;
      h.relayer.state = (state: 'STATE_CONFIRMED', hash: '0x${'a' * 64}');
      await expectLater(h.executor.withdraw(_withdraw()), throwsStateError);
      expect(await store.blockingPolymarketBatch('ledger-1'), isNull);
      expect(h.relayer.batches, isEmpty);
    });

    test('a concurrent batch for the same wallet is busy and never gets '
        "another batch's hash", () async {
      final hold = Completer<void>();
      var submits = 0;
      await http.runWithClient(() async {
        final first = _Harness(
            relayer: OnboardingLedgerPolymarketRelayer(), holdSign: hold);
        final second = _Harness(relayer: OnboardingLedgerPolymarketRelayer());

        final inFlight = first.executor.redeem(_redeem());
        // Wait for the actual device boundary; filesystem I/O can exceed
        // a fixed number of event-loop turns on a loaded CI runner.
        await first.signStarted.future.timeout(const Duration(seconds: 10));
        expect(first.prompts, hasLength(1));

        await expectLater(
            second.executor.redeem(_redeem()),
            throwsA(isA<LedgerFailure>()
                .having((f) => f.code, 'code', LedgerFailureCode.busy)));
        expect(second.prompts, isEmpty);

        hold.completeError(const LedgerFailure(LedgerFailureCode.rejected));
        await expectLater(inFlight, throwsA(isA<LedgerFailure>()));
        expect(await first.store.forWallet('ledger-1'), isEmpty,
            reason: 'nothing was sent, so nothing was recorded');
      }, () => MockClient((request) async {
            if (request.url.path == '/v1/account/transactions/params') {
              return http.Response(jsonEncode({'nonce': '7'}), 200);
            }
            submits++;
            return http.Response('unexpected', 500);
          }));
      expect(submits, 0);
    });

    test('a legacy Safe account is read-only', () {
      final h = _Harness(account: const PolymarketLedgerAccount.legacySafe(_wallet));
      expect(() => h.executor.redeem(_redeem()),
          throwsA(isA<LedgerPolymarketAccountUnsupportedException>()));
      expect(h.prompts, isEmpty);
    });

    test('cancel uses stored credentials and never prompts (O8)', () async {
      final h = _Harness();
      h.credentials.values['pm_api_credentials_ledger-1'] = jsonEncode(
          {'apiKey': 'k', 'secret': 's', 'passphrase': 'p', 'nonce': 1});
      await h.executor.cancelOrder('0xorder');
      expect(h.clob.cancels, ['0xorder']);
      expect(h.prompts, isEmpty);
    });

    test('a neg-risk trade approval also approves the v1 Neg Risk Adapter',
        () async {
      final amount = BigInt.from(2500000);
      for (final negRisk in [false, true]) {
        final h = _Harness();
        h.relayer.handler = (calls, beforeSubmit, onSubmitted) async {
          await beforeSubmit('${negRisk ? 1 : 0}');
          await onSubmitted('tx');
          return '0xhash';
        };
        final intent = LedgerPolymarketIntents.approveTrading(
          walletId: 'ledger-1',
          depositWallet: _wallet,
          amount: amount,
          negRisk: negRisk,
          summary: const {'action': 'Allow'},
        );
        expect(await h.executor.approveTrading(intent), '0xhash');
        final spenders = negRisk
            ? [
                PolymarketConstants.negRiskExchangeAddress,
                PolymarketConstants.legacyNegRiskAdapterAddress,
              ]
            : [PolymarketConstants.exchangeAddress];
        expect(h.relayer.batches.single, [
          for (final s in spenders)
            _call(PolymarketConstants.pusdAddress, encodeApproveCall(s, amount)),
        ]);
        // The digest names every spender that is signed for.
        expect(intent.toSensitiveIntent().limits['spenders'],
            [for (final s in spenders) s.toLowerCase()]);
      }
    });

    test('a trade approval whose reviewed spenders differ is refused', () {
      final h = _Harness();
      final params = {
        'op': 'approveTrade',
        'depositWallet': _wallet,
        'amount': BigInt.one,
        'negRisk': true,
        // Reviewed without the adapter: never signed as a neg-risk batch.
        'spenders': [PolymarketConstants.negRiskExchangeAddress.toLowerCase()],
      };
      final stale = LedgerActionIntent.restore(
        walletId: 'ledger-1',
        kind: LedgerActionKind.pmDepositWalletBatch,
        params: params,
        summary: const {},
        paramsHash: LedgerActionIntent.computeHash(
            walletId: 'ledger-1',
            kind: LedgerActionKind.pmDepositWalletBatch,
            params: params,
            summary: const {}),
        createdAtMs: 0,
        sensitive: LedgerSensitiveIntentDraft(
          action: 'pmBet',
          walletId: 'ledger-1',
          venue: 'polymarket',
          asset: 'PUSD',
          amountMax: BigInt.one,
          requiresStepUp: false,
        ),
      );
      expect(() => h.executor.approveTrading(stale),
          throwsA(isA<LedgerIntentMismatchException>()));
      expect(h.relayer.batches, isEmpty);
      expect(h.prompts, isEmpty);
    });

    test('an unwrap approves the offramp for the exact pUSD amount first',
        () async {
      final h = _Harness();
      h.relayer.handler = (calls, beforeSubmit, onSubmitted) async {
        await beforeSubmit('7');
        await onSubmitted('tx-7');
        return '0xhash';
      };
      final amount = BigInt.from(1250000);
      final intent = LedgerPolymarketIntents.unwrap(
        walletId: 'ledger-1',
        depositWallet: _wallet,
        amount: amount,
        summary: const {'action': 'Make funds withdrawable'},
      );
      expect(intent.toSensitiveIntent().limits['spender'],
          PolymarketConstants.collateralOfframpAddress.toLowerCase());
      expect(await h.executor.unwrap(intent), '0xhash');
      // CollateralOfframp.unwrap pulls pUSD with safeTransferFrom: without
      // the approval in the same batch it reverts.
      expect(h.relayer.batches.single, [
        _call(PolymarketConstants.pusdAddress,
            encodeApproveCall(PolymarketConstants.collateralOfframpAddress, amount)),
        _call(PolymarketConstants.collateralOfframpAddress,
            encodeUnwrapCall(PolymarketConstants.usdcEAddress, _wallet, amount)),
      ]);
      expect(h.relayer.batches.single, ledgerPmUnwrapCalls(_wallet, amount));
    });

    test('an unwrap reviewed without its offramp approval is refused', () {
      final h = _Harness();
      final params = {
        'op': 'unwrap',
        'depositWallet': _wallet,
        'amount': BigInt.one,
      };
      final stale = LedgerActionIntent.restore(
        walletId: 'ledger-1',
        kind: LedgerActionKind.pmDepositWalletBatch,
        params: params,
        summary: const {},
        paramsHash: LedgerActionIntent.computeHash(
            walletId: 'ledger-1',
            kind: LedgerActionKind.pmDepositWalletBatch,
            params: params,
            summary: const {}),
        createdAtMs: 0,
        sensitive: LedgerSensitiveIntentDraft(
          action: 'venueWithdraw',
          walletId: 'ledger-1',
          venue: 'polymarket',
          asset: 'USDC.e',
          amountMax: BigInt.one,
          requiresStepUp: false,
        ),
      );
      expect(() => h.executor.unwrap(stale),
          throwsA(isA<LedgerIntentMismatchException>()));
      expect(h.relayer.batches, isEmpty);
    });

    test('missing share operators are read on-chain; unknown is never missing',
        () async {
      final approved = {
        PolymarketConstants.exchangeAddress.toLowerCase(),
        PolymarketConstants.ctfCollateralAdapterAddress.toLowerCase(),
      };
      final owners = <String>{};
      final missing = await ledgerPmMissingShareOperators(_wallet,
          ({required owner, required operator}) async {
        owners.add(owner);
        return approved.contains(operator.toLowerCase());
      });
      expect(owners, {_wallet});
      expect(missing, [
        PolymarketConstants.negRiskExchangeAddress,
        PolymarketConstants.negRiskCtfCollateralAdapterAddress,
        PolymarketConstants.legacyNegRiskAdapterAddress,
      ]);
      expect(
          await ledgerPmMissingShareOperators(
              _wallet, ({required owner, required operator}) async => true),
          isEmpty);
      await expectLater(
          ledgerPmMissingShareOperators(_wallet,
              ({required owner, required operator}) async =>
                  throw StateError('rpc down')),
          throwsStateError);
    });

    test('share approvals send setApprovalForAll for the reviewed operators',
        () async {
      final capabilities = <String>[];
      final h = _Harness(checkCapability: (c) async => capabilities.add(c));
      h.relayer.handler = (calls, beforeSubmit, onSubmitted) async {
        await beforeSubmit('9');
        await onSubmitted('tx-9');
        return '0xhash';
      };
      final operators = [
        PolymarketConstants.negRiskExchangeAddress,
        PolymarketConstants.legacyNegRiskAdapterAddress,
      ];
      final intent = LedgerPolymarketIntents.enableShareTrading(
        walletId: 'ledger-1',
        depositWallet: _wallet,
        operators: operators,
        summary: const {'action': 'Allow selling and claiming'},
      );
      // The digest names every operator that is approved.
      expect(intent.toSensitiveIntent().limits['operators'],
          [for (final o in operators) o.toLowerCase()]);
      expect(await h.executor.enableShareTrading(intent), '0xhash');
      expect(h.relayer.batches.single, [
        for (final o in operators)
          _call(PolymarketConstants.ctfAddress,
              '0x$kSelectorSetApprovalForAll${o.toLowerCase().substring(2).padLeft(64, '0')}'
              '${'0' * 63}1'),
      ]);
      expect(capabilities, ['polymarket.close']);
    });

    test('share approvals refuse an empty, repeated or unpinned operator list',
        () {
      for (final operators in [
        <String>[],
        [
          PolymarketConstants.exchangeAddress,
          PolymarketConstants.exchangeAddress.toLowerCase(),
        ],
        ['0x${'66' * 20}'],
      ]) {
        final h = _Harness();
        final intent = LedgerPolymarketIntents.enableShareTrading(
          walletId: 'ledger-1',
          depositWallet: _wallet,
          operators: operators,
          summary: const {},
        );
        expect(() => h.executor.enableShareTrading(intent),
            throwsA(isA<LedgerIntentMismatchException>()),
            reason: '$operators');
        expect(h.relayer.batches, isEmpty);
      }
    });

    test('an intent for another deposit wallet is refused before any prompt',
        () {
      final h = _Harness();
      final other = LedgerPolymarketIntents.redeem(
        walletId: 'ledger-1',
        depositWallet: '0x${'12' * 20}',
        conditionId: _condition,
        negRisk: false,
        summary: const {},
      );
      expect(() => h.executor.redeem(other),
          throwsA(isA<LedgerIntentMismatchException>()));
      expect(h.prompts, isEmpty);
    });
  });

  test('the intent produces a SensitiveIntent with a stable digest', () {
    final draft = _redeem().toSensitiveIntent();
    const canonical = '{"account":"$_wallet","action":"pmSell","amountMax":"0",'
        '"asset":"PUSD","destination":"$_condition","limits":{},'
        '"ttlSeconds":60,"venue":"polymarket","walletId":"ledger-1"}';
    expect(ledgerCanonicalJson(draft.toCanonicalMap()), canonical);
    expect(draft.digest, sha256.convert(utf8.encode(canonical)).toString());
    expect(_redeem().toSensitiveIntent().digest, draft.digest);

    // Key order and hex case never change the digest; a value does.
    expect(ledgerCanonicalDigest({'b': 1, 'a': '0xABcd'}),
        ledgerCanonicalDigest({'a': '0xabcd', 'b': 1}));
    expect(ledgerCanonicalDigest({'a': BigInt.from(2)}),
        isNot(ledgerCanonicalDigest({'a': BigInt.from(3)})));
    expect(() => ledgerCanonicalJson({'a': 1.5}), throwsArgumentError);

    final withdraw = _withdraw().toSensitiveIntent();
    expect(withdraw.action, 'venueWithdraw');
    expect(withdraw.destination, _orchestra);
    expect(withdraw.requiresStepUp, isTrue);
  });
}
