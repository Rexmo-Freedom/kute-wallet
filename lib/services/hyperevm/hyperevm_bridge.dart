// lib/services/hyperevm/hyperevm_bridge.dart
//
// The account's two sides of Hyperliquid, as the Investing moves see them:
// HyperCore (where Investing trades) and HyperEVM (where Orchestra now
// picks up and delivers USDC, because it no longer accepts HyperCore as a
// source). Reads need only the address; anything that moves money goes
// through a [HyperEvmSigner] opened for one operation with the spending
// wallet's Hyperliquid key, the same key that signs every Hyperliquid
// action.
//
// Every signed transfer hands its nonce or transaction hash to the caller
// BEFORE it is sent, so the caller persists it first: a kill at any point
// leaves a record that says exactly what may have gone out.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kute/constants/hyperliquid_constants.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlAccountSnapshot;
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/services/hyperevm/hyperevm_constants.dart';
import 'package:kute/services/hyperevm/hyperevm_rpc.dart';
import 'package:kute/services/hyperevm/hyperevm_tx.dart';
import 'package:kute/services/hyperliquid/hypercore_activation_fee.dart';
import 'package:kute/services/hyperliquid/hypercore_cash.dart';
import 'package:kute/services/hyperliquid/hypercore_dex_cash.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/security/address_guard.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;

/// How HyperCore keeps this account's balances (Hyperliquid docs,
/// "Account abstraction modes"): separate perpetuals and spot balances, or
/// one balance per asset (unified account and portfolio margin), held in
/// the spot clearinghouse.
enum HyperCoreAccountMode {
  standard,
  unified;

  /// From the `userAbstraction` info answer. Anything but the two unified
  /// modes (`default`, `disabled`, the retired dex abstraction) keeps
  /// separate balances.
  static HyperCoreAccountMode fromAbstraction(Object? value) =>
      value == 'unifiedAccount' || value == 'portfolioMargin'
          ? HyperCoreAccountMode.unified
          : HyperCoreAccountMode.standard;
}

/// The HyperCore balances a move reads, in eight-decimal units.
class HyperCoreHoldings {
  const HyperCoreHoldings({
    required this.mode,
    required this.perpUsdc,
    required this.spotUsdc,
    required this.spotHype,
  });

  final HyperCoreAccountMode mode;

  /// Withdrawable USDC on the default perpetuals dex.
  final BigInt perpUsdc;

  /// Unheld spot USDC.
  final BigInt spotUsdc;

  /// Unheld spot HYPE: the HyperCore side of the gas float.
  final BigInt spotHype;

  /// USDC a single `sendAsset` can take without an internal move.
  BigInt get usdcInOnePool =>
      mode == HyperCoreAccountMode.unified ? spotUsdc : _max(perpUsdc, spotUsdc);

  static BigInt _max(BigInt a, BigInt b) => a > b ? a : b;
}

/// A HyperEVM transaction from this account is still waiting to be mined.
/// Nothing new is signed until it settles, so two never race.
class HyperEvmTransactionPending implements Exception {
  const HyperEvmTransactionPending();
  @override
  String toString() => 'HyperEvmTransactionPending';
}

/// The account's HYPE does not cover a transaction's gas.
class HyperEvmGasShort implements Exception {
  const HyperEvmGasShort();
  @override
  String toString() => 'HyperEvmGasShort';
}

/// HyperEVM gas is in a spike: no move starts.
class HyperEvmGasSpike implements Exception {
  const HyperEvmGasSpike();
  @override
  String toString() => 'HyperEvmGasSpike';
}

/// Funds did not show up on HyperEVM in time. They are the account's own
/// and are swept back once they land; nothing was sent onward.
class HyperEvmArrivalTimeout implements Exception {
  const HyperEvmArrivalTimeout();
  @override
  String toString() => 'HyperEvmArrivalTimeout';
}

/// The account reads every Investing move starts from. No keys.
abstract interface class HyperEvmReader {
  Future<HyperEvmAccountRead> evm(String address);
  Future<BigInt> evmUsdc(String address);
  Future<BigInt> evmHype(String address);
  Future<HyperCoreHoldings> core(String address);
  Future<HyperEvmReceipt?> receipt(String hash);
  Future<bool> isKnownTransaction(String hash);
  Future<int> nonce(String address);
}

class HyperEvmReaderNative implements HyperEvmReader {
  HyperEvmReaderNative({HyperEvmRpc? rpc, http.Client? client})
      : _rpc = rpc ?? HyperEvmRpc.shared,
        _client = client;

  final HyperEvmRpc _rpc;
  final http.Client? _client;

  @override
  Future<HyperEvmAccountRead> evm(String address) => _rpc.account(address);

  @override
  Future<BigInt> evmUsdc(String address) => _rpc.usdcBalance(address);

  @override
  Future<BigInt> evmHype(String address) => _rpc.hypeBalance(address);

  @override
  Future<HyperEvmReceipt?> receipt(String hash) => _rpc.receipt(hash);

  @override
  Future<bool> isKnownTransaction(String hash) =>
      _rpc.isKnownTransaction(hash);

  @override
  Future<int> nonce(String address) => _rpc.nonce(address);

  /// `clearinghouseState` + `spotClearinghouseState` (weight 2 each) and
  /// `userAbstraction` (weight 20), against Hyperliquid's 1,200 per minute.
  /// Throws on any failure: a guessed mode or balance never moves money.
  @override
  Future<HyperCoreHoldings> core(String address) async {
    final results = await Future.wait([
      HyperliquidModel(client: _client).getAccountSnapshot(address),
      _abstraction(address),
    ]);
    final snapshot = results[0] as HlAccountSnapshot;
    final mode = results[1] as HyperCoreAccountMode;
    BigInt spot(String coin) {
      var total = 0.0;
      for (final b in snapshot.spotBalances) {
        if (b.coin == coin) total += b.available;
      }
      return hypercoreBalanceBaseUnits(total);
    }

    return HyperCoreHoldings(
      mode: mode,
      perpUsdc: hypercoreBalanceBaseUnits(snapshot.withdrawable),
      spotUsdc: spot('USDC'),
      spotHype: spot('HYPE'),
    );
  }

  Future<HyperCoreAccountMode> _abstraction(String address) async {
    final body = jsonEncode({'type': 'userAbstraction', 'user': address});
    const headers = {'content-type': 'application/json'};
    final client = _client;
    final response = await (client == null
            ? http.post(HyperliquidConstants.infoUri,
                headers: headers, body: body)
            : client.post(HyperliquidConstants.infoUri,
                headers: headers, body: body))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError('Account mode unavailable');
    }
    return HyperCoreAccountMode.fromAbstraction(jsonDecode(response.body));
  }
}

/// What a signed HyperEVM transaction does.
enum HyperEvmTxKind {
  /// USDC `transfer` to an Orchestra deposit address.
  usdcTransfer,

  /// CoreDepositWallet `depositWithAuth`: USDC into HyperCore.
  depositToCore,

  /// HYPE to 0x2222…2222: part of the gas float into HyperCore spot.
  hypeToCore,
}

/// Moves money for one operation with the spending wallet's Hyperliquid
/// key. Opened right before the first transfer, dropped after it.
abstract interface class HyperEvmSigner {
  String get address;

  /// Gathers [amount] USDC (eight decimals) into one HyperCore pool a
  /// single `sendAsset` can take it from, and names that pool ('' for
  /// perpetuals, 'spot'). Unified accounts already hold one balance;
  /// standard ones may need builder-dex cash or a spot-to-perpetuals move,
  /// which stays inside the account.
  Future<String> gatherUsdc(BigInt amount, {void Function()? beforeSend});

  /// HyperCore → own HyperEVM address through the token's system address.
  /// [amount] in eight decimals. [onBeforePost] receives the signed nonce
  /// before the POST and must persist it.
  Future<int> coreToEvm({
    required String token,
    required BigInt amount,
    required String sourceDex,
    required Future<void> Function(int nonce) onBeforePost,
    void Function()? beforeSend,
  });

  /// Signs a HyperEVM transaction of [kind], hands its hash and nonce to
  /// [onSigned] (which must persist them), then broadcasts it. Returns
  /// the hash. Refuses while another transaction of this account is
  /// pending, when gas is in a spike, and when HYPE does not cover it.
  Future<String> sendEvmTx({
    required HyperEvmTxKind kind,
    required BigInt amount,
    String? to,
    int? destinationDex,
    required Future<void> Function(String hash, int nonce) onSigned,
  });
}

class HyperEvmSignerNative implements HyperEvmSigner {
  HyperEvmSignerNative({
    required EthPrivateKey credentials,
    required this.address,
    required this.ensureAuthorized,
    HyperEvmRpc? rpc,
    HyperliquidModel? model,
    DateTime Function()? clock,
  })  : _credentials = credentials,
        _rpc = rpc ?? HyperEvmRpc.shared,
        _model = model ?? HyperliquidModel(),
        _clock = clock ?? DateTime.now {
    if (!sameEvmAddress(credentials.address.hexEip55, address)) {
      throw StateError('The Hyperliquid key does not match the account.');
    }
  }

  final EthPrivateKey _credentials;
  final HyperEvmRpc _rpc;
  final HyperliquidModel _model;
  final DateTime Function() _clock;

  /// Re-checks the session and spending wallet right before a signature
  /// leaves the app. Throws when either changed.
  final void Function() ensureAuthorized;

  @override
  final String address;

  HyperliquidExchangeService _exchange(
          Future<void> Function(int nonce)? onBeforePost) =>
      HyperliquidExchangeService(
        credentials: _credentials,
        walletAddress: address,
        allowNonceRetry: false,
        onBeforePost: onBeforePost == null
            ? null
            : (post) async {
                ensureAuthorized();
                await onBeforePost(post.nonce);
                ensureAuthorized();
              },
      );

  @override
  Future<String> gatherUsdc(BigInt amount, {void Function()? beforeSend}) async {
    final reader = HyperEvmReaderNative();
    final holdings = await reader.core(address);
    if (holdings.mode == HyperCoreAccountMode.unified) {
      if (holdings.spotUsdc < amount) throw HypercoreBalanceShortfall();
      return HyperCoreTokens.spotDex;
    }
    if (holdings.perpUsdc >= amount) return HyperCoreTokens.perpsDex;
    if (holdings.spotUsdc >= amount) return HyperCoreTokens.spotDex;
    // Split across pools: builder-dex cash into perpetuals first, then the
    // spot shortfall, exactly as the old withdrawal gathered it. Both
    // moves stay inside this account; held cash is never touched.
    final exchange = _exchange(null);
    void guard() {
      ensureAuthorized();
      beforeSend?.call();
    }

    final portfolio = await _model.getPortfolioSnapshot(address);
    final spotAvailable = hypercoreAvailableUsdc(0, portfolio.spotBalances);
    final spotMove = hypercorePerpShortfall(
        requiredBaseUnits: amount,
        spotAvailable: spotAvailable,
        perpAvailable: portfolio.withdrawable);
    await collectOwnDexCash(
        model: _model,
        exchange: exchange,
        requiredDefaultUsd: (amount - spotMove).toDouble() / 1e8,
        beforeSend: guard);
    final base = await _model.getAccountSnapshot(address);
    final internalMove = hypercorePerpShortfall(
        requiredBaseUnits: amount,
        spotAvailable: hypercoreAvailableUsdc(0, base.spotBalances),
        perpAvailable: base.withdrawable);
    if (internalMove > BigInt.zero) {
      await exchange.usdClassTransfer(
          amount: internalMove.toDouble() / 1e8,
          toPerp: true,
          beforeSend: guard);
    }
    final last = await reader.core(address);
    if (last.perpUsdc < amount) throw HypercoreBalanceShortfall();
    return HyperCoreTokens.perpsDex;
  }

  @override
  Future<int> coreToEvm({
    required String token,
    required BigInt amount,
    required String sourceDex,
    required Future<void> Function(int nonce) onBeforePost,
    void Function()? beforeSend,
  }) {
    ensureAuthorized();
    return _exchange(onBeforePost).sendAssetToEvm(
      token: token,
      amount: hyperCoreAmountWire(amount,
          decimals: token == HyperCoreTokens.usdc ? 6 : 8),
      sourceDex: sourceDex,
      beforeSend: () {
        ensureAuthorized();
        beforeSend?.call();
      },
    );
  }

  @override
  Future<String> sendEvmTx({
    required HyperEvmTxKind kind,
    required BigInt amount,
    String? to,
    int? destinationDex,
    required Future<void> Function(String hash, int nonce) onSigned,
  }) async {
    ensureAuthorized();
    final account = await _rpc.account(address);
    if (account.hasPendingTransaction) {
      throw const HyperEvmTransactionPending();
    }
    if (account.gasPriceWei > HyperEvmGas.maxGasPriceWei) {
      throw const HyperEvmGasSpike();
    }
    final String target;
    final String data;
    BigInt? value;
    switch (kind) {
      case HyperEvmTxKind.usdcTransfer:
        final recipient = to ?? '';
        if (sameEvmAddress(recipient, address)) {
          throw const HyperEvmTxRefused('self');
        }
        if (account.usdcMicros < amount) throw HypercoreBalanceShortfall();
        target = HyperEvmChain.usdc;
        data = usdcTransferData(to: recipient, amountMicros: amount);
      case HyperEvmTxKind.depositToCore:
        if (account.usdcMicros < amount) throw HypercoreBalanceShortfall();
        final now = _clock().millisecondsSinceEpoch ~/ 1000;
        target = HyperEvmChain.coreDepositWallet;
        data = await depositWithAuthData(
          key: _credentials,
          amountMicros: amount,
          validAfter: BigInt.zero,
          validBefore: BigInt.from(now + 3600),
          nonce: randomAuthorizationNonce(),
          destinationDex: destinationDex ?? HyperEvmChain.perpsDex,
        );
        await _checkUsdcDomain();
      case HyperEvmTxKind.hypeToCore:
        if (amount <= BigInt.zero ||
            amount % HyperEvmChain.hypeCoreQuantumWei != BigInt.zero) {
          throw const HyperEvmTxRefused('amount');
        }
        target = HyperEvmChain.hypeSystemAddress;
        data = '0x';
        value = amount;
    }
    final estimate = await _rpc.estimateGas(
        from: address, to: target, data: data, valueWei: value);
    final gasLimit = hyperEvmGasLimit(estimate);
    final maxFee = hyperEvmMaxFeePerGas(account.gasPriceWei);
    if (account.hypeWei < gasLimit * maxFee + (value ?? BigInt.zero)) {
      throw const HyperEvmGasShort();
    }
    final signed = await signHyperEvmTx(
      key: _credentials,
      to: target,
      data: data,
      valueWei: value,
      nonce: account.latestNonce,
      gasLimit: gasLimit,
      maxFeePerGasWei: maxFee,
    );
    ensureAuthorized();
    await onSigned(signed.hash, signed.nonce);
    ensureAuthorized();
    await _rpc.sendRawTransaction(signed.raw, hash: signed.hash);
    return signed.hash;
  }

  static bool _domainChecked = false;

  /// The live USDC domain must equal the one the authorization was signed
  /// for. Read once per session.
  Future<void> _checkUsdcDomain() async {
    if (_domainChecked) return;
    final live =
        await _rpc.call(to: HyperEvmChain.usdc, data: '0x3644e515');
    if (live.toLowerCase() != HyperEvmChain.usdcDomainSeparator) {
      throw const HyperEvmTxRefused('usdc_domain');
    }
    _domainChecked = true;
  }
}

/// An eight-decimal HyperCore amount as the wire string, floored to
/// [decimals] places (6 for USDC, whose HyperEVM side has six).
String hyperCoreAmountWire(BigInt amount, {required int decimals}) {
  if (amount <= BigInt.zero) throw ArgumentError.value(amount, 'amount');
  final quantum = BigInt.from(10).pow(8 - decimals);
  final floored = (amount ~/ quantum) * quantum;
  if (floored <= BigInt.zero) throw ArgumentError.value(amount, 'amount');
  final whole = floored ~/ BigInt.from(100000000);
  final fraction = (floored % BigInt.from(100000000))
      .toString()
      .padLeft(8, '0')
      .substring(0, decimals);
  return '$whole.$fraction';
}

/// Waits between polls: quick first, then slower, never more than
/// [total] in all. Each poll is one RPC call, so a minute of waiting is
/// about a dozen calls, far under the endpoint limit.
List<Duration> hyperEvmPollSchedule(Duration total) {
  const steps = [1, 1, 2, 2, 3, 3, 5, 5, 8, 10];
  final out = <Duration>[];
  var spent = 0;
  var i = 0;
  while (spent < total.inSeconds) {
    final next = i < steps.length ? steps[i] : 15;
    out.add(Duration(seconds: next));
    spent += next;
    i++;
  }
  return out;
}

/// Polls [read] until [done] holds, or throws [HyperEvmArrivalTimeout]
/// once [schedule] is spent. A read that fails is retried at the next
/// step; it never counts as an answer.
Future<T> pollHyperEvm<T>({
  required Future<T> Function() read,
  required bool Function(T value) done,
  required List<Duration> schedule,
  Future<void> Function(Duration)? sleep,
}) async {
  final wait = sleep ?? (Duration d) => Future<void>.delayed(d);
  for (var i = 0; i <= schedule.length; i++) {
    try {
      final value = await read();
      if (done(value)) return value;
    } catch (_) {
      // Next step.
    }
    if (i == schedule.length) break;
    await wait(schedule[i]);
  }
  throw const HyperEvmArrivalTimeout();
}
