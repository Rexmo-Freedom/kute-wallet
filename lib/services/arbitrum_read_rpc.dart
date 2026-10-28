// lib/services/arbitrum_read_rpc.dart
//
// Read-only Arbitrum One JSON-RPC over public endpoints, with the same
// fallback rules as the Polygon reads in PolymarketOnboardingService: each
// endpoint must first answer `eth_chainId` with Arbitrum One, one that
// times out or errors is skipped for the next and tried last for a minute,
// and a read throws when no endpoint answers, so callers never mistake a
// failure for an empty account. Nothing is ever signed or sent here.

import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

class ArbitrumReadException implements Exception {
  const ArbitrumReadException(this.message);
  final String message;

  @override
  String toString() => 'ArbitrumReadException: $message';
}

/// keccak256("Transfer(address,address,uint256)").
const String kErc20TransferTopic =
    '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef';

/// One token mint read from Arbitrum logs.
class ArbitrumTokenMint {
  const ArbitrumTokenMint(
      {required this.amount, required this.txHash, required this.block});

  /// Token base units.
  final BigInt amount;
  final String txHash;
  final int block;
}

class ArbitrumReadRpc {
  static const int chainId = 42161;

  /// Circle's native USDC on Arbitrum One (what Hyperliquid's bridge takes).
  static const String usdcAddress =
      '0xaf88d065e77c8cC2239327C5EDb3A432268e5831';

  /// Public endpoints, tried in order. Each answered `eth_chainId` 0xa4b1,
  /// `eth_getBalance`, `eth_getTransactionCount` and a USDC `balanceOf`
  /// when added.
  @visibleForTesting
  static const endpoints = [
    'https://arbitrum-one-rpc.publicnode.com',
    'https://arb1.arbitrum.io/rpc',
    'https://arbitrum.drpc.org',
    'https://arbitrum.gateway.tenderly.co',
  ];

  /// Per-request timeout for one endpoint.
  @visibleForTesting
  static Duration requestTimeout = const Duration(seconds: 5);

  static const _cooldown = Duration(minutes: 1);
  static final Map<String, DateTime> _cooldownUntil = {};
  static final Map<String, Future<bool?>> _chainChecks = {};

  @visibleForTesting
  static void debugReset() {
    _cooldownUntil.clear();
    _chainChecks.clear();
    requestTimeout = const Duration(seconds: 5);
  }

  /// Native ETH balance of [owner] in wei.
  Future<BigInt> nativeBalance(String owner) =>
      _quantity('eth_getBalance', [owner, 'latest']);

  /// Transactions [owner] has sent on Arbitrum (its nonce).
  Future<BigInt> nonce(String owner) =>
      _quantity('eth_getTransactionCount', [owner, 'latest']);

  /// ERC-20 `balanceOf(owner)` on [token].
  Future<BigInt> erc20Balance(
      {required String token, required String owner}) async {
    final hex = owner.toLowerCase().replaceFirst('0x', '');
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(hex)) {
      throw ArgumentError.value(owner, 'owner', 'not an address');
    }
    final result = await _firstAnswer('eth_call', [
      {'to': token, 'data': '0x70a08231${hex.padLeft(64, '0')}'},
      'latest',
    ]);
    final word = result.substring(2);
    if (word.length != 64) {
      throw const ArbitrumReadException('balanceOf returned no uint256');
    }
    return BigInt.parse(word, radix: 16);
  }

  /// The latest Arbitrum One block number.
  Future<int> blockNumber() async =>
      (await _quantity('eth_blockNumber', const [])).toInt();

  /// ERC-20 `Transfer` events on [token] minted (from the zero address)
  /// to [to], from block [fromBlock] to [toBlock] (the latest when null).
  /// Public endpoints cap an `eth_getLogs` range, so a caller pages a
  /// long search in windows. Throws when no endpoint answers, so a
  /// failed read is never an empty list.
  Future<List<ArbitrumTokenMint>> mintsTo({
    required String token,
    required String to,
    required int fromBlock,
    int? toBlock,
  }) async {
    final hex = to.toLowerCase().replaceFirst('0x', '');
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(hex) || fromBlock < 0) {
      throw ArgumentError.value(to, 'to', 'not an address');
    }
    if (toBlock != null && toBlock < fromBlock) {
      throw ArgumentError.value(toBlock, 'toBlock', 'before fromBlock');
    }
    final logs = await _firstListAnswer('eth_getLogs', [
      {
        'address': token,
        'fromBlock': '0x${fromBlock.toRadixString(16)}',
        'toBlock': toBlock == null ? 'latest' : '0x${toBlock.toRadixString(16)}',
        'topics': [
          kErc20TransferTopic,
          '0x${'0' * 64}',
          '0x${hex.padLeft(64, '0')}',
        ],
      }
    ]);
    final out = <ArbitrumTokenMint>[];
    for (final log in logs) {
      if (log is! Map) continue;
      final data = log['data'];
      final tx = log['transactionHash'];
      final block = log['blockNumber'];
      if (data is! String || tx is! String || block is! String) continue;
      final amount = BigInt.tryParse(data.replaceFirst('0x', ''), radix: 16);
      final number = int.tryParse(block.replaceFirst('0x', ''), radix: 16);
      if (amount == null || number == null) continue;
      out.add(ArbitrumTokenMint(amount: amount, txHash: tx, block: number));
    }
    return out;
  }

  Future<List<Object?>> _firstListAnswer(
      String method, List<Object> params) async {
    for (final rpc in _order()) {
      if (!await _isArbitrum(rpc)) continue;
      final result = (await _request(rpc, method, params))?.result;
      if (result is List) {
        _cooldownUntil.remove(rpc);
        return result;
      }
      _failed(rpc);
    }
    throw ArbitrumReadException('$method: no Arbitrum RPC answered');
  }

  Future<BigInt> _quantity(String method, List<Object> params) async {
    final result = await _firstAnswer(method, params);
    final value = BigInt.tryParse(result.substring(2), radix: 16);
    if (value == null) {
      throw ArbitrumReadException('$method returned no quantity');
    }
    return value;
  }

  /// The first `0x…` result among [endpoints]; throws when none answers.
  Future<String> _firstAnswer(String method, List<Object> params) async {
    for (final rpc in _order()) {
      if (!await _isArbitrum(rpc)) continue;
      final result = (await _request(rpc, method, params))?.result;
      if (result is String && result.startsWith('0x')) {
        _cooldownUntil.remove(rpc);
        return result;
      }
      _failed(rpc);
    }
    throw ArbitrumReadException('$method: no Arbitrum RPC answered');
  }

  static List<String> _order() {
    final now = DateTime.now();
    final ready = <String>[];
    final cooling = <String>[];
    for (final rpc in endpoints) {
      final until = _cooldownUntil[rpc];
      (until != null && now.isBefore(until) ? cooling : ready).add(rpc);
    }
    return [...ready, ...cooling];
  }

  static void _failed(String rpc) =>
      _cooldownUntil[rpc] = DateTime.now().add(_cooldown);

  /// True once [rpc] answered `eth_chainId` with Arbitrum One. A wrong chain
  /// is remembered for the session; no answer is retried on a later read.
  Future<bool> _isArbitrum(String rpc) async {
    final check = _chainChecks.putIfAbsent(rpc, () async {
      final result = (await _request(rpc, 'eth_chainId', const []))?.result;
      if (result is! String) return null;
      return int.tryParse(result.replaceFirst('0x', ''), radix: 16) ==
          chainId;
    });
    final ok = await check;
    if (ok == null) {
      if (identical(_chainChecks[rpc], check)) _chainChecks.remove(rpc);
      _failed(rpc);
    }
    return ok ?? false;
  }

  /// Null on timeout, a non-200 status, a JSON-RPC error or a malformed
  /// body.
  Future<({Object? result})?> _request(
      String rpc, String method, List<Object> params) async {
    try {
      final body = jsonEncode(
          {'jsonrpc': '2.0', 'method': method, 'params': params, 'id': 1});
      final response = await http
          .post(Uri.parse(rpc),
              headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(requestTimeout);
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      if (json is! Map || json['error'] != null) return null;
      return (result: json['result']);
    } catch (_) {
      return null;
    }
  }
}
