// lib/services/hyperevm/hyperevm_gas_float.dart
//
// The small HYPE float that pays HyperEVM and HyperCore gas for the
// Investing moves. HyperEVM transactions pay gas in HYPE on HyperEVM; a
// HyperCore → HyperEVM transfer pays 200,000 gas in HYPE from the HyperCore
// spot balance. So the float lives on both sides.
//
// Source: Orchestra `spark:USDB → hyperevm:HYPE` for $1 (Dollars first,
// Bitcoin when Dollars are short), delivered to the account's own HyperEVM
// address, then split by the gas each side spends (see [HyperEvmGas]).
// Buying on HyperCore spot is ruled out: Hyperliquid's minimum order is
// $10. Before buying, one side's surplus tops up the other: moving HYPE
// between sides costs only gas.
//
// Each side is topped up when it holds less than five of its largest
// transaction at twice today's gas price (never below 0.5 gwei). A move
// whose own gas is already covered goes ahead and the top-up runs beside
// it; a move that is not covered waits for the float to land.

import 'package:kute/services/hyperevm/hyperevm_constants.dart';

/// Which Investing move the float has to pay for.
enum HyperEvmMove {
  /// HyperCore → HyperEVM (HyperCore gas) then an ERC-20 transfer (HyperEVM).
  withdraw,

  /// `depositWithAuth` on HyperEVM.
  deposit,
}

/// Both sides of the float, read together.
class HyperEvmFloatState {
  const HyperEvmFloatState({
    required this.evmHypeWei,
    required this.coreHype,
    required this.gasPriceWei,
  });

  final BigInt evmHypeWei;

  /// HyperCore spot HYPE in eight decimals.
  final BigInt coreHype;
  final BigInt gasPriceWei;

  BigInt get coreHypeWei => coreHype * HyperEvmChain.hypeCoreQuantumWei;
}

/// What the float needs before (or beside) a move.
class HyperEvmGasPlan {
  const HyperEvmGasPlan({
    required this.gasSpike,
    required this.buy,
    required this.mustWait,
    required this.toCoreWei,
    required this.toEvmCore,
  });

  /// The network is in a spike: stop before anything moves.
  final bool gasSpike;

  /// Buy another $1 of HYPE (folded into this move's fee).
  final bool buy;

  /// This move's own gas is not covered until the purchase lands.
  final bool mustWait;

  /// HYPE to move HyperEVM → HyperCore now (wei, whole 10^10 units).
  final BigInt toCoreWei;

  /// HYPE to move HyperCore → HyperEVM now (eight decimals).
  final BigInt toEvmCore;

  bool get rebalances => toCoreWei > BigInt.zero || toEvmCore > BigInt.zero;
  bool get ready => !gasSpike && !mustWait;
}

/// The gas price thresholds and per-move costs are priced at.
BigInt hyperEvmThresholdGasPrice(BigInt gasPriceWei) {
  final doubled = gasPriceWei * BigInt.two;
  return doubled > HyperEvmGas.thresholdGasPriceFloorWei
      ? doubled
      : HyperEvmGas.thresholdGasPriceFloorWei;
}

/// HyperEVM side threshold: five deposits (its largest transaction).
BigInt hyperEvmEvmThresholdWei(BigInt gasPriceWei) =>
    BigInt.from(HyperEvmGas.thresholdTransactions) *
    HyperEvmGas.depositToCore *
    hyperEvmThresholdGasPrice(gasPriceWei);

/// HyperCore side threshold: five HyperCore → HyperEVM transfers.
BigInt hyperEvmCoreThresholdWei(BigInt gasPriceWei) =>
    BigInt.from(HyperEvmGas.thresholdTransactions) *
    HyperEvmGas.coreToEvm *
    hyperEvmThresholdGasPrice(gasPriceWei);

BigInt _floorToQuantum(BigInt wei) =>
    (wei ~/ HyperEvmChain.hypeCoreQuantumWei) *
    HyperEvmChain.hypeCoreQuantumWei;

BigInt _max(BigInt a, BigInt b) => a > b ? a : b;
BigInt _min(BigInt a, BigInt b) => a < b ? a : b;

/// Decides what the float needs for [move]. Pure.
HyperEvmGasPlan planHyperEvmGas(HyperEvmFloatState s, HyperEvmMove move) {
  if (s.gasPriceWei > HyperEvmGas.maxGasPriceWei) {
    return HyperEvmGasPlan(
        gasSpike: true,
        buy: false,
        mustWait: true,
        toCoreWei: BigInt.zero,
        toEvmCore: BigInt.zero);
  }
  final p = hyperEvmThresholdGasPrice(s.gasPriceWei);
  final needsCore = move == HyperEvmMove.withdraw;
  final evmThreshold = hyperEvmEvmThresholdWei(s.gasPriceWei);
  final coreThreshold = hyperEvmCoreThresholdWei(s.gasPriceWei);
  final evmForMove =
      (move == HyperEvmMove.withdraw
          ? HyperEvmGas.erc20Transfer
          : HyperEvmGas.depositToCore) *
      p;
  final coreForMove = needsCore ? HyperEvmGas.coreToEvm * p : BigInt.zero;
  final toCoreGas = HyperEvmGas.hypeToCore * p;
  final toEvmGas = HyperEvmGas.coreToEvm * p;

  var evm = s.evmHypeWei;
  var core = s.coreHypeWei;
  var toCore = BigInt.zero;
  var toEvm = BigInt.zero;

  final coreLow = needsCore && core < coreThreshold;
  final evmLow = evm < evmThreshold;
  if (coreLow && !evmLow) {
    // HyperEVM's surplus over its own threshold (and the transfer's gas)
    // tops HyperCore up to twice its threshold, if it covers the gap.
    final surplus = evm - evmThreshold - toCoreGas;
    final gap = coreThreshold - core;
    if (surplus >= gap) {
      toCore = _floorToQuantum(_min(surplus, coreThreshold * BigInt.two - core));
      if (toCore >= gap) {
        evm -= toCore + toCoreGas;
        core += toCore;
      } else {
        toCore = BigInt.zero;
      }
    }
  } else if (evmLow && (!needsCore || !coreLow)) {
    final coreKeep = needsCore ? coreThreshold : BigInt.zero;
    final surplus = core - coreKeep - toEvmGas;
    final gap = evmThreshold - evm;
    if (surplus >= gap) {
      final amount =
          _floorToQuantum(_min(surplus, evmThreshold * BigInt.two - evm));
      if (amount >= gap) {
        toEvm = amount ~/ HyperEvmChain.hypeCoreQuantumWei;
        core -= amount + toEvmGas;
        evm += amount;
      }
    }
  }
  final stillLow =
      evm < evmThreshold || (needsCore && core < coreThreshold);
  final covered = evm >= evmForMove && core >= coreForMove;
  return HyperEvmGasPlan(
    gasSpike: false,
    buy: stillLow,
    mustWait: !covered,
    toCoreWei: toCore,
    toEvmCore: toEvm,
  );
}

/// How much of the HyperEVM float to send to HyperCore after a purchase,
/// so the two sides split the total by the gas each spends (200 of 410
/// to HyperCore), keeping HyperEVM above its own threshold. Wei, whole
/// 10^10 units; zero when HyperCore already holds its share.
BigInt hyperEvmSplitToCoreWei(HyperEvmFloatState s) {
  final p = hyperEvmThresholdGasPrice(s.gasPriceWei);
  final total = s.evmHypeWei + s.coreHypeWei;
  final coreTarget = total *
      BigInt.from(HyperEvmGas.coreShareNumerator) ~/
      BigInt.from(HyperEvmGas.coreShareDenominator);
  final want = coreTarget - s.coreHypeWei;
  final evmKeep =
      hyperEvmEvmThresholdWei(s.gasPriceWei) + HyperEvmGas.hypeToCore * p;
  final available = s.evmHypeWei - evmKeep;
  final amount = _floorToQuantum(_max(BigInt.zero, _min(want, available)));
  // Less than one HyperCore → HyperEVM transfer's gas is not worth a
  // transaction of its own.
  return amount < HyperEvmGas.coreToEvm * p ? BigInt.zero : amount;
}

/// Which Spark balance pays for the float.
enum HyperEvmFloatSource {
  dollars,
  bitcoin;

  String get analytics => this == HyperEvmFloatSource.dollars ? 'usd' : 'btc';
}

/// Dollars first, Bitcoin when Dollars are short, nothing when both are.
/// [usdMicros] and [sats] are the balances left AFTER the move itself
/// (a deposit spends from one of them). [satsPerDollar] prices $1.
HyperEvmFloatSource? pickHyperEvmFloatSource({
  required BigInt usdMicros,
  required int sats,
  required double satsPerDollar,
}) {
  if (usdMicros >= HyperEvmGas.floatSourceMicros) {
    return HyperEvmFloatSource.dollars;
  }
  final needed = hyperEvmFloatSats(satsPerDollar);
  if (needed != null && sats >= (needed * 105) ~/ 100) {
    return HyperEvmFloatSource.bitcoin;
  }
  return null;
}

/// $1 in sats at [satsPerDollar], never below Orchestra's 1,200 sat
/// minimum. Null without a usable price.
int? hyperEvmFloatSats(double satsPerDollar) {
  if (!satsPerDollar.isFinite || satsPerDollar <= 0) return null;
  final sats = (HyperEvmGas.floatUsd * satsPerDollar).ceil();
  return sats < HyperEvmGas.minFloatSats ? HyperEvmGas.minFloatSats : sats;
}
