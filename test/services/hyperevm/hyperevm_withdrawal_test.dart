import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/services/funding/settlement_funding_outcome.dart';
import 'package:kute/services/funding/settlement_reconciler.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/hyperevm/hyperevm_bridge.dart';
import 'package:kute/services/hyperevm/hyperevm_constants.dart';
import 'package:kute/services/hyperevm/hyperevm_rpc.dart' show HyperEvmReceipt;
import 'package:kute/services/hyperevm/hyperevm_tx.dart';
import 'package:kute/services/hyperevm/hyperevm_vault.dart';
import 'package:kute/services/hyperevm/hyperevm_withdrawal.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';

import 'hyperevm_fakes.dart';

void main() {
  late FakeReader reader;
  late FakeSigner signer;
  late MemoryHyperEvmTxJournal journal;
  late DateTime now;
  late List<SettlementFunding> persisted;
  late List<String> steps;

  setUp(() {
    reader = FakeReader()..perpUsdc = coreUsdc(25);
    signer = FakeSigner(reader);
    journal = MemoryHyperEvmTxJournal();
    now = DateTime.utc(2026, 10, 12, 12);
    persisted = [];
    steps = [];
  });

  HyperEvmWithdrawalSteps stepsRunner() => HyperEvmWithdrawalSteps(
      reader: reader, journal: journal, clock: () => now, sleep: noSleep);

  Future<String> run({BigInt? amount, void Function()? ensurePayable}) =>
      stepsRunner().run(
        signer: signer,
        depositAddress: kDeposit,
        amountMicros: amount ?? usdcMicros(20),
        ensurePayable: ensurePayable ?? () {},
        persist: (patch) async {
          persisted.add(patch(persisted.isEmpty
              ? const SettlementFunding(kind: SettlementFundingKind.evm)
              : persisted.last));
        },
        onStep: (step, _) => steps.add(step),
      );

  test('happy path: HyperCore → HyperEVM, wait, transfer; every write first',
      () async {
    final hash = await run();
    expect(steps, ['core_to_evm', 'evm_arrived', 'provider_sent']);
    expect(signer.calls.map((c) => c.kind),
        ['coreToEvm', 'usdcTransfer']);
    expect(signer.calls[0].amount, coreUsdc(20));
    expect(signer.calls[0].token, HyperCoreTokens.usdc);
    expect(signer.calls[1].to, kDeposit);
    expect(signer.calls[1].amount, usdcMicros(20));
    // The nonce was on disk before the POST, the hash before the broadcast.
    expect(persisted[0].hlNonce, 1780000000000);
    expect(persisted[0].kind, SettlementFundingKind.evm);
    expect(persisted[1].evmTxHash, hash);
    expect(persisted[1].evmNonce, 3);
    expect(reader.evmUsdcMicros, BigInt.zero);
    expect(reader.perpUsdc, coreUsdc(5));
  });

  test('a unified account moves from its one (spot) balance', () async {
    reader
      ..mode = HyperCoreAccountMode.unified
      ..perpUsdc = BigInt.zero
      ..spotUsdc = coreUsdc(25);
    await run();
    expect(reader.spotUsdc, coreUsdc(5));
  });

  test('USDC already on HyperEVM counts first; none is moved twice',
      () async {
    reader.evmUsdcMicros = usdcMicros(7);
    await run();
    expect(signer.calls[0].amount, coreUsdc(13));
    expect(reader.evmUsdcMicros, BigInt.zero);
    // All of it already there: no HyperCore step at all.
    signer.calls.clear();
    steps.clear();
    reader.evmUsdcMicros = usdcMicros(20);
    await run();
    expect(steps, ['provider_sent']);
    expect(signer.calls.map((c) => c.kind), ['usdcTransfer']);
  });

  test('HyperCore refusing the transfer stops before anything is sent',
      () async {
    signer.failures['coreToEvm'] =
        const HyperliquidRejectedException('Action disabled');
    await expectLater(
        run(),
        throwsA(isA<SettlementFundingRefused>().having(
            (e) => e.cause, 'cause', isA<HyperEvmCoreTransferRefused>())));
    expect(signer.calls, isEmpty);
    expect(reader.evmUsdcMicros, BigInt.zero);
  });

  test('USDC not landing in time stops, with the provider never paid',
      () async {
    signer.holdArrival = true;
    await expectLater(
        run(),
        throwsA(isA<SettlementFundingRefused>()
            .having((e) => e.cause, 'cause', isA<HyperEvmArrivalTimeout>())));
    expect(signer.calls.map((c) => c.kind), ['coreToEvm']);
    expect(persisted.last.evmTxHash, isNull);
    // It lands later: the account's own, for the sweeper.
    signer.landCore();
    expect(reader.evmUsdcMicros, usdcMicros(20));
  });

  test('polling is bounded: about a dozen reads over a minute', () {
    final schedule = hyperEvmPollSchedule(const Duration(seconds: 60));
    expect(schedule.length, inInclusiveRange(10, 14));
    expect(schedule.fold(Duration.zero, (a, b) => a + b),
        greaterThanOrEqualTo(const Duration(seconds: 60)));
  });

  test('an expired quote stops before each transfer', () async {
    var expired = false;
    await expectLater(
        run(ensurePayable: () {
          if (expired) throw StateError('expired');
        }..call()),
        completes);
    expired = true;
    persisted.clear();
    signer.calls.clear();
    await expectLater(
        run(ensurePayable: () {
          if (expired) throw StateError('expired');
        }),
        throwsA(isA<SettlementFundingRefused>()));
    expect(signer.calls, isEmpty);
  });

  test('no HYPE for gas stops before the provider transfer', () async {
    signer.failures['usdcTransfer'] = const HyperEvmGasShort();
    await expectLater(
        run(),
        throwsA(isA<SettlementFundingRefused>()
            .having((e) => e.cause, 'cause', isA<HyperEvmGasShort>())));
    // The USDC crossed and waits on HyperEVM.
    expect(reader.evmUsdcMicros, usdcMicros(20));
  });

  test('a pending transaction of the account blocks a new one', () async {
    reader.pendingNonce = 4;
    await expectLater(run(), throwsA(isA<SettlementFundingRefused>()));
    expect(signer.calls, isEmpty);
  });

  test('a journaled, unmined transaction blocks until it settles', () async {
    await journal.write(
        kEoa,
        HyperEvmJournalEntry(
            hash: '0xdead', nonce: 3, kind: 'deposit', at: now));
    reader.known.add('0xdead');
    await expectLater(run(), throwsA(isA<SettlementFundingRefused>()));
    expect(signer.calls, isEmpty);
    // Mined: cleared, and the withdrawal goes ahead.
    reader.receipts['0xdead'] =
        const HyperEvmReceipt(success: true, blockNumber: 2);
    await run();
    expect(journal.entries, isEmpty);
  });

  test('a transfer the node did not confirm stays unresolved for the probe',
      () async {
    signer.hangEvmTx = true;
    await expectLater(run(), throwsA(isA<HyperEvmTransferUnconfirmed>()));
    expect(persisted.last.evmTxHash, isNotNull);
  });

  test('the deposit address is never the CoreDepositWallet or ourselves',
      () async {
    for (final bad in [HyperEvmChain.coreDepositWallet, kEoa]) {
      await expectLater(
          stepsRunner().run(
            signer: signer,
            depositAddress: bad,
            amountMicros: usdcMicros(1),
            ensurePayable: () {},
            persist: (_) async {},
          ),
          throwsA(isA<SettlementFundingRefused>()
              .having((e) => e.cause, 'cause', isA<HyperEvmTxRefused>())));
    }
    expect(signer.calls, isEmpty);
  });

  group('recovery probe after a kill', () {
    SettlementOperation op({
      String? hash,
      int? evmNonce,
      SettlementStage stage = SettlementStage.broadcasting,
    }) =>
        SettlementOperation(
          operationId: 'op',
          walletId: 'w',
          accountKind: SettlementAccountKind.hlHot,
          flow: SettlementFlow.investingToSparkUsdDirect,
          route: RouteKey(
              fromChain: 'hyperevm',
              fromAsset: 'USDC',
              toChain: 'spark',
              toAsset: 'USDB'),
          amountInBaseUnits: '20000000',
          stage: stage,
          refund: const SettlementAddressRef(
              address: kEoa, kind: OwnedAddressKind.hyperliquidEoa),
          funding: SettlementFunding(
              kind: SettlementFundingKind.evm,
              hlNonce: 1780000000000,
              evmTxHash: hash,
              evmNonce: evmNonce),
          quote: SettlementQuoteTerms(
              quoteId: 'q',
              depositAddress: kDeposit,
              amountIn: '20000000',
              estimatedOut: '19900000',
              feeBps: 10,
              expiresAt: now.add(const Duration(minutes: 2))),
          createdAt: now,
          updatedAt: now,
        );

    Future<HyperEvmFundingProbe> probe(SettlementOperation o) async =>
        (await probeHyperEvmWithdrawal(op: o, reader: reader, now: now)).probe;

    test('killed before the provider transfer was signed: not sent', () async {
      expect(await probe(op()), HyperEvmFundingProbe.provenNotSent);
    });

    test('mined and successful: confirmed, with the hash', () async {
      reader.receipts['0xaa'] =
          const HyperEvmReceipt(success: true, blockNumber: 9);
      final result = await probeHyperEvmWithdrawal(
          op: op(hash: '0xaa', evmNonce: 3), reader: reader, now: now);
      expect(result.probe, HyperEvmFundingProbe.confirmed);
      expect(result.hash, '0xaa');
    });

    test('mined and reverted: not sent', () async {
      reader.receipts['0xaa'] =
          const HyperEvmReceipt(success: false, blockNumber: 9);
      expect(await probe(op(hash: '0xaa', evmNonce: 3)),
          HyperEvmFundingProbe.provenNotSent);
    });

    test('still in a mempool: inconclusive', () async {
      reader.known.add('0xaa');
      expect(await probe(op(hash: '0xaa', evmNonce: 3)),
          HyperEvmFundingProbe.inconclusive);
    });

    test('unknown and the nonce slot taken by another transaction: not sent',
        () async {
      reader.latestNonce = 4;
      expect(await probe(op(hash: '0xaa', evmNonce: 3)),
          HyperEvmFundingProbe.provenNotSent);
    });

    test('unknown, nonce unused: inconclusive until long after expiry',
        () async {
      final orphan = op(hash: '0xaa', evmNonce: 3);
      expect(await probe(orphan), HyperEvmFundingProbe.inconclusive);
      now = now.add(const Duration(minutes: 40));
      expect(await probe(orphan), HyperEvmFundingProbe.provenNotSent);
    });

    test('the planner leaves a running HyperEVM withdrawal to its runner',
        () {
      final state = op().toReconcileState(ownedByLiveFlow: true);
      expect(
          planSettlementReconcile(state,
                  now: now, sessionUnlocked: true, foregroundedAt: now)
              .isIdle,
          isTrue);
      final orphan = op().toReconcileState();
      expect(
          planSettlementReconcile(orphan,
                  now: now, sessionUnlocked: true, foregroundedAt: now)
              .probeFundingSource,
          isTrue);
    });
  });
}
