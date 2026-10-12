// Fakes shared by the HyperEVM tests: a reader over scripted balances and
// a signer that records what it was asked to move. No network, no keys.

import 'dart:async';

import 'package:kute/services/hyperevm/hyperevm_bridge.dart';
import 'package:kute/services/hyperevm/hyperevm_constants.dart';
import 'package:kute/services/hyperevm/hyperevm_rpc.dart';

const kEoa = '0x1111111111111111111111111111111111111111';
const kDeposit = '0x3333333333333333333333333333333333333333';

BigInt gwei(double g) => BigInt.from((g * 1e9).round());
BigInt hype(double h) => BigInt.from((h * 1e18).round());
BigInt coreHype(double h) => BigInt.from((h * 1e8).round());
BigInt usdcMicros(double usd) => BigInt.from((usd * 1e6).round());
BigInt coreUsdc(double usd) => BigInt.from((usd * 1e8).round());

class FakeReader implements HyperEvmReader {
  BigInt evmHypeWei = hype(0.01);
  BigInt evmUsdcMicros = BigInt.zero;
  int latestNonce = 3;
  int pendingNonce = 3;
  BigInt gasPrice = gwei(0.13);
  HyperCoreAccountMode mode = HyperCoreAccountMode.standard;
  BigInt perpUsdc = BigInt.zero;
  BigInt spotUsdc = BigInt.zero;
  BigInt spotHype = coreHype(0.01);
  final Map<String, HyperEvmReceipt?> receipts = {};
  final Set<String> known = {};
  int reads = 0;

  /// Thrown by every read while set.
  Object? failure;

  void _check() {
    reads++;
    final f = failure;
    if (f != null) throw f;
  }

  @override
  Future<HyperEvmAccountRead> evm(String address) async {
    _check();
    return HyperEvmAccountRead(
        hypeWei: evmHypeWei,
        usdcMicros: evmUsdcMicros,
        latestNonce: latestNonce,
        pendingNonce: pendingNonce,
        gasPriceWei: gasPrice);
  }

  @override
  Future<BigInt> evmUsdc(String address) async {
    _check();
    return evmUsdcMicros;
  }

  @override
  Future<BigInt> evmHype(String address) async {
    _check();
    return evmHypeWei;
  }

  @override
  Future<HyperCoreHoldings> core(String address) async {
    _check();
    return HyperCoreHoldings(
        mode: mode, perpUsdc: perpUsdc, spotUsdc: spotUsdc, spotHype: spotHype);
  }

  @override
  Future<HyperEvmReceipt?> receipt(String hash) async {
    _check();
    return receipts[hash];
  }

  @override
  Future<bool> isKnownTransaction(String hash) async {
    _check();
    return known.contains(hash) || receipts[hash] != null;
  }

  @override
  Future<int> nonce(String address) async {
    _check();
    return latestNonce;
  }
}

class SignerCall {
  SignerCall(this.kind, this.amount, {this.to, this.dex, this.token});
  final String kind;
  final BigInt amount;
  final String? to;
  final int? dex;
  final String? token;
}

/// Moves balances on [reader] the way the chain would, after a delay the
/// test controls.
class FakeSigner implements HyperEvmSigner {
  FakeSigner(this.reader, {this.address = kEoa});

  final FakeReader reader;
  @override
  final String address;
  final List<SignerCall> calls = [];
  var hashes = 0;

  /// Thrown instead of moving money, per kind.
  final Map<String, Object> failures = {};

  /// The HyperCore → HyperEVM USDC arrival is deferred until [landCore]
  /// runs when set.
  bool holdArrival = false;
  final List<void Function()> _pendingArrivals = [];

  /// Runs the hooks but not the broadcast; the transaction "hangs".
  bool hangEvmTx = false;

  Future<void> Function(int nonce)? lastOnBeforePost;

  void landCore() {
    for (final land in _pendingArrivals) {
      land();
    }
    _pendingArrivals.clear();
  }

  @override
  Future<String> gatherUsdc(BigInt amount, {void Function()? beforeSend}) async {
    final f = failures['gather'];
    if (f != null) throw f;
    if (reader.mode == HyperCoreAccountMode.unified) {
      if (reader.spotUsdc < amount) throw StateError('short');
      return HyperCoreTokens.spotDex;
    }
    if (reader.perpUsdc >= amount) return HyperCoreTokens.perpsDex;
    if (reader.spotUsdc >= amount) return HyperCoreTokens.spotDex;
    if (reader.perpUsdc + reader.spotUsdc < amount) throw StateError('short');
    beforeSend?.call();
    calls.add(SignerCall('usdClassTransfer', amount - reader.perpUsdc));
    reader.spotUsdc -= amount - reader.perpUsdc;
    reader.perpUsdc = amount;
    return HyperCoreTokens.perpsDex;
  }

  @override
  Future<int> coreToEvm({
    required String token,
    required BigInt amount,
    required String sourceDex,
    required Future<void> Function(int nonce) onBeforePost,
    void Function()? beforeSend,
  }) async {
    final f = failures['coreToEvm'];
    if (f != null) throw f;
    lastOnBeforePost = onBeforePost;
    const nonce = 1780000000000;
    await onBeforePost(nonce);
    beforeSend?.call();
    calls.add(SignerCall('coreToEvm', amount, token: token, dex: null));
    void land() {
      if (token == HyperCoreTokens.usdc) {
        if (sourceDex == HyperCoreTokens.spotDex) {
          reader.spotUsdc -= amount;
        } else {
          reader.perpUsdc -= amount;
        }
        reader.evmUsdcMicros += amount ~/ BigInt.from(100);
      } else {
        reader.spotHype -= amount;
        reader.evmHypeWei += amount * HyperEvmChain.hypeCoreQuantumWei;
      }
    }

    if (holdArrival) {
      _pendingArrivals.add(land);
    } else {
      land();
    }
    return nonce;
  }

  @override
  Future<String> sendEvmTx({
    required HyperEvmTxKind kind,
    required BigInt amount,
    String? to,
    int? destinationDex,
    required Future<void> Function(String hash, int nonce) onSigned,
  }) async {
    final f = failures[kind.name];
    if (f != null) throw f;
    if (reader.pendingNonce > reader.latestNonce) {
      throw const HyperEvmTransactionPending();
    }
    if (reader.gasPrice > HyperEvmGas.maxGasPriceWei) {
      throw const HyperEvmGasSpike();
    }
    if (reader.evmHypeWei < gwei(1)) throw const HyperEvmGasShort();
    final hash = '0x${(++hashes).toRadixString(16).padLeft(64, '0')}';
    final nonce = reader.latestNonce;
    await onSigned(hash, nonce);
    if (hangEvmTx) {
      reader.known.add(hash);
      reader.pendingNonce = nonce + 1;
      return hash;
    }
    calls.add(SignerCall(kind.name, amount, to: to, dex: destinationDex));
    switch (kind) {
      case HyperEvmTxKind.usdcTransfer:
        reader.evmUsdcMicros -= amount;
      case HyperEvmTxKind.depositToCore:
        reader.evmUsdcMicros -= amount;
        final core = amount * BigInt.from(100);
        if (destinationDex == HyperEvmChain.spotDex) {
          reader.spotUsdc += core;
        } else {
          reader.perpUsdc += core;
        }
      case HyperEvmTxKind.hypeToCore:
        reader.evmHypeWei -= amount;
        reader.spotHype += amount ~/ HyperEvmChain.hypeCoreQuantumWei;
    }
    reader.evmHypeWei -= gwei(0.13) * BigInt.from(100000);
    reader.latestNonce = nonce + 1;
    reader.pendingNonce = reader.latestNonce;
    reader.receipts[hash] = const HyperEvmReceipt(success: true, blockNumber: 1);
    return hash;
  }
}

/// A sleep that never waits: polls run back to back.
Future<void> noSleep(Duration _) async {}
