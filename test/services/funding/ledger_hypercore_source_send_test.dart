import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart' show appL10n;
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/funding/ledger_hypercore_source_send.dart';
import 'package:kute/services/hardware/ledger/ledger_action_intent.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'package:kute/services/hyperliquid/hypercore_transfer_proof.dart';
import 'package:kute/services/hyperliquid/hypercore_activation_fee.dart';

const _source = '0x1111111111111111111111111111111111111111';
const _deposit = '0x2222222222222222222222222222222222222222';
const _hash =
    '0x3333333333333333333333333333333333333333333333333333333333333333';

OrchestraRoutesCatalog _catalog({String token = orchestraHypercoreUsdcId}) =>
    OrchestraRoutesCatalog.fromJson({
      'assets': [
        {
          'id': 'hypercore:USDC',
          'chain': 'hypercore',
          'asset': 'USDC',
          'decimals': 8,
          'contractAddress': token,
          'route': {
            'to': ['bitcoin:BTC']
          }
        },
      ],
    }, source: OrchestraCatalogSource.live, fetchedAt: DateTime.now());

HlAccountSnapshot _snapshot(
        {double spot = 0, double held = 0, double perps = 0}) =>
    HlAccountSnapshot(
        accountValue: perps,
        withdrawable: perps,
        totalMarginUsed: 0,
        positions: const [],
        spotBalances: [
          HlSpotBalance(coin: 'USDC', total: spot, hold: held),
        ]);

LedgerHypercoreSourceSendNative _sender({
  required HlAccountSnapshot snapshot,
  String token = orchestraHypercoreUsdcId,
  void Function(int nonce)? proofRequested,
  Future<BigInt> Function(String)? activationFee,
  Future<HlAccountSnapshot> Function(String)? snapshots,
}) =>
    LedgerHypercoreSourceSendNative(
      <T>(ProviderListenable<T> _) => _catalog(token: token) as T,
      snapshot: snapshots ?? (_) async => snapshot,
      activationFee: activationFee ?? (_) async => BigInt.zero,
      verifyToken: () async {},
      transferHash: (
          {required source,
          required destination,
          required amountBaseUnits,
          required nonce}) async {
        expect(source, _source);
        expect(destination, _deposit);
        expect(amountBaseUnits, BigInt.from(1234567800));
        proofRequested?.call(nonce);
        return _hash;
      },
    );

void main() {
  test(
      'perpetuals cash withdraws exact amount through one reviewed Ledger action',
      () async {
    final intents = <LedgerActionIntent>[];
    var persisted = false;
    final sender = _sender(
        snapshot: _snapshot(perps: 20),
        proofRequested: (nonce) {
          expect(persisted, isTrue);
          expect(nonce, 77);
        });
    final hash = await sender.sendToDeposit(
      walletId: 'ledger-1',
      evmAddress: _source,
      depositAddress: _deposit,
      amountBaseUnits: BigInt.from(1234567800),
      reviewedActivationFeeBaseUnits: BigInt.zero,
      onBeforeInternalSend: () async {},
      quoteId: 'quote-1',
      onBeforeSend: (nonce) async {
        expect(nonce, 77);
        persisted = true;
      },
      approve: (intent, {onBeforeSend, beforeSend}) async {
        intents.add(intent);
        await onBeforeSend!(77);
        beforeSend?.call();
        return 77;
      },
    );
    expect(hash, _hash);
    expect(intents.single.kind, LedgerActionKind.hlUsdSend);
    expect(intents.single.params['amount'], '12.345678');
    expect(intents.single.params.containsKey('token'), isFalse);
    expect(intents.single.sensitive.requiresStepUp, isTrue);
  });

  test(
      'moves only spot shortfall with a separate approval before exact perpetuals send',
      () async {
    final intents = <LedgerActionIntent>[];
    var moved = false;
    final sender = _sender(
        snapshot: _snapshot(),
        snapshots: (_) async => moved
            ? _snapshot(spot: 1.654322, perps: 12.345678)
            : _snapshot(spot: 11, held: 1, perps: 4));
    await sender.sendToDeposit(
      walletId: 'ledger-1',
      evmAddress: _source,
      depositAddress: _deposit,
      amountBaseUnits: BigInt.from(1234567800),
      reviewedActivationFeeBaseUnits: BigInt.zero,
      onBeforeInternalSend: () async {},
      quoteId: 'quote-1',
      onBeforeSend: (_) async {},
      approve: (intent, {onBeforeSend, beforeSend}) async {
        intents.add(intent);
        await onBeforeSend!(77);
        beforeSend?.call();
        if (intent.kind == LedgerActionKind.hlUsdClassTransfer) moved = true;
        return 77;
      },
    );
    expect(intents.map((i) => i.kind),
        [LedgerActionKind.hlUsdClassTransfer, LedgerActionKind.hlUsdSend]);
    expect(intents.first.params,
        {'amount': '8.345678', 'toPerp': true, 'withdrawalQuoteId': 'quote-1'});
    expect(intents.last.params['amount'], '12.345678');
  });

  test('held funds and an unexpected catalog token cannot reach approval',
      () async {
    for (final sender in [
      _sender(snapshot: _snapshot(spot: 15, held: 5)),
      _sender(snapshot: _snapshot(perps: 20), token: '0xwrong'),
    ]) {
      var approvals = 0;
      await expectLater(
          sender.sendToDeposit(
            walletId: 'ledger-1',
            evmAddress: _source,
            depositAddress: _deposit,
            amountBaseUnits: BigInt.from(1234567800),
            reviewedActivationFeeBaseUnits: BigInt.zero,
            onBeforeInternalSend: () async {},
            quoteId: 'quote-1',
            onBeforeSend: (_) async => fail('must not reach POST'),
            approve: (_, {onBeforeSend, beforeSend}) async {
              approvals++;
              return 77;
            },
          ),
          throwsStateError);
      expect(approvals, 0);
    }
  });

  test('declining the internal move never offers the external transfer',
      () async {
    final intents = <LedgerActionIntent>[];
    final sender = _sender(snapshot: _snapshot(spot: 20));
    await expectLater(
        sender.sendToDeposit(
          walletId: 'ledger-1',
          evmAddress: _source,
          depositAddress: _deposit,
          amountBaseUnits: BigInt.from(1234567800),
          reviewedActivationFeeBaseUnits: BigInt.zero,
          onBeforeInternalSend: () async {},
          quoteId: 'quote-1',
          onBeforeSend: (_) async => fail('must not reach POST'),
          approve: (intent, {onBeforeSend, beforeSend}) async {
            intents.add(intent);
            throw const LedgerFailure(LedgerFailureCode.rejected);
          },
        ),
        throwsA(isA<LedgerFailure>()));
    expect(intents.single.kind, LedgerActionKind.hlUsdClassTransfer);
  });
  test('activation fee is reserved and bound without reducing quoted USDC',
      () async {
    final intents = <LedgerActionIntent>[];
    final sender = _sender(
        snapshot: _snapshot(perps: 20),
        activationFee: (_) async => hypercoreAccountActivationFee);
    await sender.sendToDeposit(
      walletId: 'ledger-1',
      evmAddress: _source,
      depositAddress: _deposit,
      amountBaseUnits: BigInt.from(1234567800),
      reviewedActivationFeeBaseUnits: hypercoreAccountActivationFee,
      quoteId: 'quote-1',
      onBeforeInternalSend: () async => fail('perpetuals already cover total'),
      onBeforeSend: (_) async {},
      approve: (intent, {onBeforeSend, beforeSend}) async {
        intents.add(intent);
        await onBeforeSend!(77);
        beforeSend?.call();
        return 77;
      },
    );
    expect(intents.single.params['amount'], '12.345678');
    expect(
        intents.single.sensitive.limits['activationFeeBaseUnits'], '100000000');
  });

  test('quote-only balance cannot reach a device prompt with activation fee',
      () async {
    final sender = _sender(
        snapshot: _snapshot(spot: 12.345678),
        activationFee: (_) async => hypercoreAccountActivationFee);
    await expectLater(
        sender.sendToDeposit(
          walletId: 'ledger-1',
          evmAddress: _source,
          depositAddress: _deposit,
          amountBaseUnits: BigInt.from(1234567800),
          reviewedActivationFeeBaseUnits: hypercoreAccountActivationFee,
          quoteId: 'quote-1',
          onBeforeInternalSend: () async => fail('must not POST'),
          onBeforeSend: (_) async => fail('must not POST'),
          approve: (_, {onBeforeSend, beforeSend}) async =>
              fail('must not request approval'),
        ),
        throwsA(isA<HypercoreActivationFeeBalanceRequired>()));
  });

  test('fee increase during device approval prevents the external POST',
      () async {
    var approving = false;
    final sender = _sender(
        snapshot: _snapshot(perps: 20),
        activationFee: (_) async =>
            approving ? hypercoreAccountActivationFee : BigInt.zero);
    await expectLater(
        sender.sendToDeposit(
          walletId: 'ledger-1',
          evmAddress: _source,
          depositAddress: _deposit,
          amountBaseUnits: BigInt.from(1234567800),
          reviewedActivationFeeBaseUnits: BigInt.zero,
          quoteId: 'quote-1',
          onBeforeInternalSend: () async => fail('must not POST'),
          onBeforeSend: (_) async => fail('must not POST'),
          approve: (_, {onBeforeSend, beforeSend}) async {
            approving = true;
            await onBeforeSend!(77);
            beforeSend?.call();
            return 77;
          },
        ),
        throwsA(isA<HypercoreActivationFeeChanged>()));
  });

  test('100% of perpetuals cash goes out with no activation reserve or row',
      () async {
    final intents = <LedgerActionIntent>[];
    // The production default: no injected fee lookup.
    final sender = LedgerHypercoreSourceSendNative(
      <T>(ProviderListenable<T> _) => _catalog() as T,
      snapshot: (_) async => _snapshot(perps: 12.345678),
      verifyToken: () async {},
      transferHash: (
              {required source,
              required destination,
              required amountBaseUnits,
              required nonce}) async =>
          _hash,
    );
    expect(await sender.activationFeeForDestination(_deposit), BigInt.zero);
    await sender.sendToDeposit(
      walletId: 'ledger-1',
      evmAddress: _source,
      depositAddress: _deposit,
      amountBaseUnits: BigInt.from(1234567800),
      reviewedActivationFeeBaseUnits:
          await sender.activationFeeForDestination(_deposit),
      quoteId: 'quote-1',
      onBeforeInternalSend: () async => fail('perpetuals cover the amount'),
      onBeforeSend: (_) async {},
      approve: (intent, {onBeforeSend, beforeSend}) async {
        intents.add(intent);
        await onBeforeSend!(77);
        beforeSend?.call();
        return 77;
      },
    );
    expect(intents.single.params['amount'], '12.345678');
    expect(intents.single.summary.keys,
        isNot(contains(appL10n().ledgerSummaryActivationFeeMax)));
  });
}
