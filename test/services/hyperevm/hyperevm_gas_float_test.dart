import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/hyperevm/hyperevm_constants.dart';
import 'package:kute/services/hyperevm/hyperevm_gas_float.dart';

import 'hyperevm_fakes.dart';

HyperEvmFloatState _state({
  double evm = 0,
  double core = 0,
  double gasGwei = 0.13,
}) =>
    HyperEvmFloatState(
        evmHypeWei: hype(evm), coreHype: coreHype(core), gasPriceWei: gwei(gasGwei));

void main() {
  test('thresholds: five of the largest transaction at 2x price, floored',
      () {
    // 0.13 gwei doubles to 0.26, below the 0.5 gwei floor.
    expect(hyperEvmThresholdGasPrice(gwei(0.13)), gwei(0.5));
    expect(hyperEvmThresholdGasPrice(gwei(1)), gwei(2));
    expect(hyperEvmEvmThresholdWei(gwei(0.13)),
        BigInt.from(5) * BigInt.from(150000) * gwei(0.5));
    expect(hyperEvmCoreThresholdWei(gwei(0.13)),
        BigInt.from(5) * BigInt.from(200000) * gwei(0.5));
  });

  test('a healthy float needs nothing', () {
    final plan = planHyperEvmGas(
        _state(evm: 0.005, core: 0.005), HyperEvmMove.withdraw);
    expect(plan.ready, isTrue);
    expect(plan.buy, isFalse);
    expect(plan.rebalances, isFalse);
  });

  test('an empty account must buy and wait', () {
    for (final move in HyperEvmMove.values) {
      final plan = planHyperEvmGas(_state(), move);
      expect(plan.buy, isTrue);
      expect(plan.mustWait, isTrue);
      expect(plan.ready, isFalse);
    }
  });

  test('a deposit only cares about the HyperEVM side', () {
    final plan = planHyperEvmGas(_state(evm: 0.005), HyperEvmMove.deposit);
    expect(plan.buy, isFalse);
    expect(plan.ready, isTrue);
    // HyperEVM empty, HyperCore rich: HyperCore pays, no purchase.
    final short = planHyperEvmGas(_state(core: 0.01), HyperEvmMove.deposit);
    expect(short.buy, isFalse);
    expect(short.toEvmCore, greaterThan(BigInt.zero));
    expect(short.ready, isTrue);
  });

  test('a withdrawal covered for itself buys beside the move, no wait', () {
    // HyperEVM just above its threshold (nothing to spare), HyperCore
    // holds one transfer's gas but not five.
    final plan = planHyperEvmGas(
        _state(evm: 0.0004, core: 0.0003), HyperEvmMove.withdraw);
    expect(plan.rebalances, isFalse);
    expect(plan.buy, isTrue);
    expect(plan.mustWait, isFalse);
    expect(plan.ready, isTrue);
  });

  test('HyperEVM surplus tops HyperCore up instead of buying', () {
    final plan =
        planHyperEvmGas(_state(evm: 0.01, core: 0), HyperEvmMove.withdraw);
    expect(plan.toCoreWei, greaterThan(BigInt.zero));
    expect(plan.toCoreWei % HyperEvmChain.hypeCoreQuantumWei, BigInt.zero);
    expect(plan.buy, isFalse);
    expect(plan.ready, isTrue);
    // After the move the HyperEVM side still holds its own threshold.
    expect(hype(0.01) - plan.toCoreWei,
        greaterThanOrEqualTo(hyperEvmEvmThresholdWei(gwei(0.13))));
  });

  test('HyperCore surplus tops HyperEVM up for a deposit', () {
    final plan =
        planHyperEvmGas(_state(evm: 0, core: 0.01), HyperEvmMove.deposit);
    expect(plan.toEvmCore, greaterThan(BigInt.zero));
    expect(plan.buy, isFalse);
    expect(plan.ready, isTrue);
  });

  test('a gas spike stops everything', () {
    final plan = planHyperEvmGas(
        _state(evm: 1, core: 1, gasGwei: 6), HyperEvmMove.withdraw);
    expect(plan.gasSpike, isTrue);
    expect(plan.ready, isFalse);
    expect(plan.buy, isFalse);
  });

  test('the split sends HyperCore its 200/410 share, keeping HyperEVM safe',
      () {
    final split = hyperEvmSplitToCoreWei(_state(evm: 0.0113, core: 0));
    final total = hype(0.0113);
    final target = total * BigInt.from(200) ~/ BigInt.from(410);
    expect(split, lessThanOrEqualTo(target));
    expect(split, greaterThan(target - HyperEvmChain.hypeCoreQuantumWei));
    expect(split % HyperEvmChain.hypeCoreQuantumWei, BigInt.zero);
    // Already balanced: nothing moves.
    expect(hyperEvmSplitToCoreWei(_state(evm: 0.0058, core: 0.0055)),
        BigInt.zero);
    // Too little to spare: nothing moves.
    expect(hyperEvmSplitToCoreWei(_state(evm: 0.0004, core: 0)), BigInt.zero);
  });

  test('one dollar lasts about 330 withdrawals or 580 deposits at today gas prices',
      () {
    final float = hype(0.0113);
    final perWithdraw = (HyperEvmGas.coreToEvm + HyperEvmGas.erc20Transfer) *
        gwei(0.13);
    final perDeposit = HyperEvmGas.depositToCore * gwei(0.13);
    expect((float ~/ perWithdraw).toInt(), inInclusiveRange(300, 360));
    expect((float ~/ perDeposit).toInt(), inInclusiveRange(540, 620));
    // An 8x spike.
    expect((float ~/ (perWithdraw * BigInt.from(8))).toInt(),
        inInclusiveRange(35, 75));
  });

  test('float source: Dollars first, then Bitcoin, then nothing', () {
    expect(
        pickHyperEvmFloatSource(
            usdMicros: usdcMicros(1.05), sats: 0, satsPerDollar: 1000),
        HyperEvmFloatSource.dollars);
    expect(
        pickHyperEvmFloatSource(
            usdMicros: usdcMicros(1.04), sats: 1300, satsPerDollar: 1000),
        HyperEvmFloatSource.bitcoin);
    // 1,200 sats plus 5% is the least bitcoin that can pay for it.
    expect(
        pickHyperEvmFloatSource(
            usdMicros: BigInt.zero, sats: 1259, satsPerDollar: 1000),
        isNull);
    expect(
        pickHyperEvmFloatSource(
            usdMicros: usdcMicros(0.5), sats: 1000, satsPerDollar: 1000),
        isNull);
    // No price: bitcoin cannot be sized.
    expect(
        pickHyperEvmFloatSource(usdMicros: BigInt.zero, sats: 1e9.toInt(), satsPerDollar: 0),
        isNull);
    // $1 in sats never goes under Orchestra's 1,200 sat minimum.
    expect(hyperEvmFloatSats(800), 1200);
    expect(hyperEvmFloatSats(1500.4), 1501);
  });
}
