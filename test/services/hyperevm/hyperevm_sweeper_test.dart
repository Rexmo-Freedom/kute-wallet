import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/hyperevm/hyperevm_bridge.dart';
import 'package:kute/services/hyperevm/hyperevm_constants.dart';
import 'package:kute/services/hyperevm/hyperevm_rpc.dart' show HyperEvmReceipt;
import 'package:kute/services/hyperevm/hyperevm_gas_float.dart';
import 'package:kute/services/hyperevm/hyperevm_vault.dart';

import 'hyperevm_fakes.dart';

void main() {
  late FakeReader reader;
  late FakeSigner signer;
  late MemoryHyperEvmTxJournal journal;
  late DateTime now;
  late List<BigInt> parked;
  late List<BigInt> swept;
  var reserved = false;
  HyperEvmSigner? Function() signerFor = () => null;

  setUp(() {
    reader = FakeReader()..evmUsdcMicros = usdcMicros(50);
    signer = FakeSigner(reader);
    journal = MemoryHyperEvmTxJournal();
    now = DateTime.utc(2026, 10, 12, 12);
    parked = [];
    swept = [];
    reserved = false;
    signerFor = () => signer;
  });

  HyperEvmSweeper sweeper() => HyperEvmSweeper(
        reader: reader,
        journal: journal,
        keeper: HyperEvmFloatKeeper(
            reader: reader, journal: journal, clock: () => now, sleep: noSleep),
        openSigner: (_) async => signerFor(),
        reservedByWithdrawal: (_) async => reserved,
        onParked: (_, micros) => parked.add(micros),
        onSwept: (_, micros) => swept.add(micros),
        clock: () => now,
        sleep: noSleep,
      );

  test('USDC on HyperEVM goes into HyperCore perpetuals, once', () async {
    expect(await sweeper().sweepOnce(kEoa), HyperEvmSweepOutcome.swept);
    final deposit = signer.calls.singleWhere((c) => c.kind == 'depositToCore');
    expect(deposit.amount, usdcMicros(50));
    expect(deposit.dex, HyperEvmChain.perpsDex);
    expect(reader.perpUsdc, coreUsdc(50));
    expect(reader.evmUsdcMicros, BigInt.zero);
    expect(parked, [usdcMicros(50), BigInt.zero]);
    expect(swept, [usdcMicros(50)]);
    expect(journal.entries, isEmpty);
    // Nothing left: idle, nothing signed.
    final before = signer.calls.length;
    expect(await sweeper().sweepOnce(kEoa), HyperEvmSweepOutcome.idle);
    expect(signer.calls.length, before);
  });

  test('a unified account is credited on spot', () async {
    reader.mode = HyperCoreAccountMode.unified;
    await sweeper().sweepOnce(kEoa);
    expect(signer.calls.single.dex, HyperEvmChain.spotDex);
    expect(reader.spotUsdc, coreUsdc(50));
  });

  test('a withdrawal that may still spend the USDC holds the sweep', () async {
    reserved = true;
    expect(await sweeper().sweepOnce(kEoa), HyperEvmSweepOutcome.waiting);
    expect(signer.calls, isEmpty);
  });

  test('a locked session waits; the USDC is shown as pending', () async {
    signerFor = () => null;
    expect(await sweeper().sweepOnce(kEoa), HyperEvmSweepOutcome.waiting);
    expect(parked, [usdcMicros(50)]);
  });

  test('no HYPE and nothing to rebalance: waits for the float', () async {
    reader
      ..evmHypeWei = BigInt.zero
      ..spotHype = BigInt.zero;
    expect(await sweeper().sweepOnce(kEoa), HyperEvmSweepOutcome.noGas);
    expect(signer.calls, isEmpty);
    expect(reader.evmUsdcMicros, usdcMicros(50));
  });

  test('HyperCore HYPE tops HyperEVM up before the deposit', () async {
    reader
      ..evmHypeWei = BigInt.zero
      ..spotHype = coreHype(0.01);
    expect(await sweeper().sweepOnce(kEoa), HyperEvmSweepOutcome.swept);
    expect(signer.calls.map((c) => c.kind),
        containsAllInOrder(['coreToEvm', 'depositToCore']));
    expect(signer.calls.first.token, HyperCoreTokens.hype);
  });

  test('a journaled unmined transaction blocks a second signature', () async {
    await journal.write(kEoa,
        HyperEvmJournalEntry(hash: '0xaa', nonce: 3, kind: 'deposit', at: now));
    reader.known.add('0xaa');
    expect(await sweeper().sweepOnce(kEoa), HyperEvmSweepOutcome.waiting);
    expect(signer.calls, isEmpty);
    // A restart after it was mined: the journal clears and the sweep runs.
    reader.receipts['0xaa'] = const HyperEvmReceipt(success: true, blockNumber: 1);
    expect(await sweeper().sweepOnce(kEoa), HyperEvmSweepOutcome.swept);
  });

  test('a journaled transaction nobody saw for three minutes is forgotten',
      () async {
    await journal.write(kEoa,
        HyperEvmJournalEntry(hash: '0xaa', nonce: 3, kind: 'deposit', at: now));
    expect(await sweeper().sweepOnce(kEoa), HyperEvmSweepOutcome.waiting);
    now = now.add(const Duration(minutes: 4));
    expect(await sweeper().sweepOnce(kEoa), HyperEvmSweepOutcome.swept);
  });

  test('a hung deposit leaves its hash in the journal for the next run',
      () async {
    signer.hangEvmTx = true;
    expect(await sweeper().sweepOnce(kEoa), HyperEvmSweepOutcome.waiting);
    expect(journal.entries[kEoa]!.kind, 'deposit');
    expect(journal.entries[kEoa]!.nonce, 3);
  });

  test('a reverted deposit moves nothing and reports failed', () async {
    final failing = _RevertingSigner(reader);
    signerFor = () => failing;
    expect(await sweeper().sweepOnce(kEoa), HyperEvmSweepOutcome.failed);
    expect(reader.evmUsdcMicros, usdcMicros(50));
    expect(swept, isEmpty);
  });

  test('the sweep is single flight per address', () async {
    final s = sweeper();
    final results =
        await Future.wait([s.sweepOnce(kEoa), s.sweepOnce(kEoa)]);
    expect(results, [HyperEvmSweepOutcome.swept, HyperEvmSweepOutcome.idle]);
    expect(signer.calls.where((c) => c.kind == 'depositToCore').length, 1);
  });

  test('a watch sweeps on a backoff until something lands, then stops',
      () async {
    reader.evmUsdcMicros = BigInt.zero;
    var ticks = 0;
    final s = HyperEvmSweeper(
      reader: reader,
      journal: journal,
      keeper: HyperEvmFloatKeeper(reader: reader, journal: journal),
      openSigner: (_) async => signer,
      reservedByWithdrawal: (_) async => false,
      clock: () => now,
      sleep: (d) async {
        ticks++;
        now = now.add(d);
        if (ticks == 3) reader.evmUsdcMicros = usdcMicros(5);
      },
    );
    await s.watch(kEoa);
    expect(ticks, 3);
    expect(reader.perpUsdc, coreUsdc(5));
    // Nothing in flight: a second watch with nothing arriving gives up
    // after its budget, on a backoff capped at a minute.
    ticks = 0;
    await s.watch(kEoa, total: const Duration(minutes: 5));
    expect(ticks, lessThanOrEqualTo(10));
  });

  test('the float keeper buys and waits when a move is not covered',
      () async {
    reader
      ..evmHypeWei = BigInt.zero
      ..spotHype = BigInt.zero;
    final keeper = HyperEvmFloatKeeper(
        reader: reader, journal: journal, clock: () => now, sleep: noSleep);
    final plan = await keeper.plan(kEoa, HyperEvmMove.withdraw);
    expect(plan.buy && plan.mustWait, isTrue);
    var bought = 0;
    await keeper.prepare(
      address: kEoa,
      move: HyperEvmMove.withdraw,
      signer: signer,
      plan: plan,
      buy: () async {
        bought++;
        reader.evmHypeWei = hype(0.0113);
      },
    );
    expect(bought, 1);
    // Split: HyperCore got its share, HyperEVM kept its threshold.
    final toCore = signer.calls.where((c) => c.kind == 'hypeToCore');
    expect(toCore.length, 1);
    expect(reader.spotHype, greaterThan(BigInt.zero));
    expect(reader.evmHypeWei,
        greaterThanOrEqualTo(hyperEvmEvmThresholdWei(reader.gasPrice)));
    final after = await keeper.plan(kEoa, HyperEvmMove.withdraw);
    expect(after.ready, isTrue);
    expect(after.buy, isFalse);
  });

  test('the float keeper gives up when the purchase never lands', () async {
    reader
      ..evmHypeWei = BigInt.zero
      ..spotHype = BigInt.zero;
    final keeper = HyperEvmFloatKeeper(
        reader: reader, journal: journal, clock: () => now, sleep: noSleep);
    await expectLater(
        keeper.prepare(
          address: kEoa,
          move: HyperEvmMove.deposit,
          signer: signer,
          plan: await keeper.plan(kEoa, HyperEvmMove.deposit),
          buy: () async {},
          arrivalTimeout: const Duration(seconds: 10),
        ),
        throwsA(isA<HyperEvmFloatUnavailable>()
            .having((e) => e.reason, 'reason', 'arrival_timeout')));
  });
}

/// Signs a deposit that the chain then reverts.
class _RevertingSigner extends FakeSigner {
  _RevertingSigner(super.reader);

  @override
  Future<String> sendEvmTx({
    required HyperEvmTxKind kind,
    required BigInt amount,
    String? to,
    int? destinationDex,
    required Future<void> Function(String hash, int nonce) onSigned,
  }) async {
    const hash = '0xreverted';
    await onSigned(hash, reader.latestNonce);
    reader.latestNonce++;
    reader.pendingNonce = reader.latestNonce;
    reader.receipts[hash] = HyperEvmReceipt(success: false, blockNumber: 1);
    return hash;
  }
}
