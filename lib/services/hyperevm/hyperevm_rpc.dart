// lib/services/hyperevm/hyperevm_rpc.dart
//
// HyperEVM JSON-RPC for the Investing moves, over public endpoints.
//
// Limits (Hyperliquid docs, "Rate limits and user limits"): at most 100
// EVM JSON-RPC requests per minute per IP on rpc.hyperliquid.xyz/evm. This
// client counts every call inside a batch and stops at [maxCallsPerMinute]
// (60 by default) per endpoint, well under that, then moves to the next
// endpoint. Callers poll on their own backoff (2 s and growing, capped per
// step) and only while something is in flight.
//
// Fallback endpoints are well-known public HyperEVM RPCs. Each one must
// answer `eth_chainId` with 0x3e7 (999) before anything it says is used;
// all of them did on 2026-10-12. A 429, a 5xx, a JSON-RPC rate-limit error,
// a timeout or a socket error cools that endpoint down and the same
// request goes to the next one. A read throws when no endpoint answers, so
// a caller never mistakes a failure for an empty balance.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:kute/services/hyperevm/hyperevm_constants.dart';

/// No HyperEVM endpoint gave a usable answer, or a node refused the call.
class HyperEvmRpcException implements Exception {
  const HyperEvmRpcException(this.message, {this.code, this.busy = false});

  final String message;

  /// The JSON-RPC error code when a node answered with an error (a
  /// deterministic refusal, never retried on another endpoint).
  final int? code;

  /// Every endpoint was rate limited or over this app's own budget.
  final bool busy;

  bool get isNodeError => code != null;

  @override
  String toString() => 'HyperEvmRpcException($message)';
}

/// A raw transaction whose broadcast may or may not have reached a node.
/// Its hash is known; only a receipt or a nonce read settles it.
class HyperEvmBroadcastUncertain implements Exception {
  const HyperEvmBroadcastUncertain(this.hash);
  final String hash;

  @override
  String toString() => 'HyperEvmBroadcastUncertain';
}

/// One JSON-RPC call.
class HyperEvmRpcCall {
  const HyperEvmRpcCall(this.method, [this.params = const []]);

  final String method;
  final List<Object?> params;

  Map<String, Object?> toJson(int id) =>
      {'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params};
}

/// The account reads every step starts from, in one batch.
class HyperEvmAccountRead {
  const HyperEvmAccountRead({
    required this.hypeWei,
    required this.usdcMicros,
    required this.latestNonce,
    required this.pendingNonce,
    required this.gasPriceWei,
  });

  /// Native HYPE, 18 decimals.
  final BigInt hypeWei;

  /// Native USDC, 6 decimals.
  final BigInt usdcMicros;
  final int latestNonce;
  final int pendingNonce;
  final BigInt gasPriceWei;

  /// A transaction from this account is waiting in a mempool.
  bool get hasPendingTransaction => pendingNonce > latestNonce;
}

/// A mined transaction.
class HyperEvmReceipt {
  const HyperEvmReceipt({required this.success, required this.blockNumber});

  final bool success;
  final int blockNumber;
}

class _Endpoint {
  _Endpoint(this.url);

  final String url;
  DateTime? cooldownUntil;

  /// Null until `eth_chainId` answered; false for a wrong chain (never
  /// used again this session).
  bool? chainVerified;
  final List<DateTime> calls = [];
}

class HyperEvmRpc {
  HyperEvmRpc({
    http.Client? client,
    List<String> endpoints = kHyperEvmRpcEndpoints,
    DateTime Function()? clock,
    this.requestTimeout = const Duration(seconds: 6),
    this.maxCallsPerMinute = 60,
  })  : _client = client,
        _clock = clock ?? DateTime.now,
        _endpoints = [for (final url in endpoints) _Endpoint(url)];

  /// The app-wide client, so every caller shares one budget per endpoint.
  static final HyperEvmRpc shared = HyperEvmRpc();

  final http.Client? _client;
  final DateTime Function() _clock;
  final List<_Endpoint> _endpoints;
  final Duration requestTimeout;

  /// Calls (not HTTP requests: a batch of five counts five) this client
  /// sends to one endpoint per rolling minute.
  final int maxCallsPerMinute;

  static const Duration _cooldown = Duration(seconds: 30);
  static const Duration _window = Duration(minutes: 1);

  /// Identical read batches in flight, shared.
  final Map<String, Future<List<Object?>>> _inFlight = {};

  @visibleForTesting
  int callsSentTo(String url) =>
      _endpoints.firstWhere((e) => e.url == url).calls.length;

  // ─────────────────────────────── reads ───────────────────────────────

  /// HYPE, USDC, both nonces and the gas price of [owner], in one batch.
  Future<HyperEvmAccountRead> account(String owner) async {
    final address = _address(owner);
    final results = await batch([
      HyperEvmRpcCall('eth_getBalance', [address, 'latest']),
      HyperEvmRpcCall('eth_call', [
        {'to': HyperEvmChain.usdc, 'data': balanceOfData(address)},
        'latest'
      ]),
      HyperEvmRpcCall('eth_getTransactionCount', [address, 'latest']),
      HyperEvmRpcCall('eth_getTransactionCount', [address, 'pending']),
      const HyperEvmRpcCall('eth_gasPrice'),
    ]);
    return HyperEvmAccountRead(
      hypeWei: _quantity(results[0], 'eth_getBalance'),
      usdcMicros: _word(results[1], 'balanceOf'),
      latestNonce: _quantity(results[2], 'nonce').toInt(),
      pendingNonce: _quantity(results[3], 'pending nonce').toInt(),
      gasPriceWei: _quantity(results[4], 'eth_gasPrice'),
    );
  }

  /// USDC held by [owner], one call: what an arrival poll reads.
  Future<BigInt> usdcBalance(String owner) async {
    final address = _address(owner);
    final results = await batch([
      HyperEvmRpcCall('eth_call', [
        {'to': HyperEvmChain.usdc, 'data': balanceOfData(address)},
        'latest'
      ]),
    ]);
    return _word(results[0], 'balanceOf');
  }

  /// HYPE held by [owner], one call.
  Future<BigInt> hypeBalance(String owner) async {
    final results = await batch(
        [HyperEvmRpcCall('eth_getBalance', [_address(owner), 'latest'])]);
    return _quantity(results[0], 'eth_getBalance');
  }

  Future<int> nonce(String owner, {bool pending = false}) async {
    final results = await batch([
      HyperEvmRpcCall('eth_getTransactionCount',
          [_address(owner), pending ? 'pending' : 'latest'])
    ]);
    return _quantity(results[0], 'nonce').toInt();
  }

  Future<BigInt> gasPrice() async {
    final results = await batch([const HyperEvmRpcCall('eth_gasPrice')]);
    return _quantity(results[0], 'eth_gasPrice');
  }

  /// `eth_call` returning the raw hex result.
  Future<String> call({required String to, required String data}) async {
    final results = await batch([
      HyperEvmRpcCall('eth_call', [
        {'to': to, 'data': data},
        'latest'
      ])
    ]);
    final value = results[0];
    if (value is! String || !value.startsWith('0x')) {
      throw const HyperEvmRpcException('eth_call returned no data');
    }
    return value;
  }

  Future<BigInt> estimateGas({
    required String from,
    required String to,
    required String data,
    BigInt? valueWei,
  }) async {
    final results = await batch([
      HyperEvmRpcCall('eth_estimateGas', [
        {
          'from': _address(from),
          'to': _address(to),
          'data': data,
          if (valueWei != null && valueWei > BigInt.zero)
            'value': '0x${valueWei.toRadixString(16)}',
        }
      ])
    ], singleFlight: false);
    return _quantity(results[0], 'eth_estimateGas');
  }

  /// The receipt of [hash], or null while it is not mined.
  Future<HyperEvmReceipt?> receipt(String hash) async {
    final results = await batch(
        [HyperEvmRpcCall('eth_getTransactionReceipt', [hash])]);
    final value = results[0];
    if (value == null) return null;
    if (value is! Map) {
      throw const HyperEvmRpcException('receipt returned no object');
    }
    final status = value['status'];
    final block = value['blockNumber'];
    if (status is! String || block is! String) {
      throw const HyperEvmRpcException('receipt without status');
    }
    return HyperEvmReceipt(
      success: _quantity(status, 'status') == BigInt.one,
      blockNumber: _quantity(block, 'blockNumber').toInt(),
    );
  }

  /// Whether a node knows [hash] (mined or waiting in a mempool).
  Future<bool> isKnownTransaction(String hash) async {
    final results = await batch(
        [HyperEvmRpcCall('eth_getTransactionByHash', [hash])]);
    return results[0] != null;
  }

  // ─────────────────────────────── writes ──────────────────────────────

  /// Broadcasts [raw] (whose hash is [hash]). The same bytes go to the
  /// next endpoint when one does not answer, which cannot double spend:
  /// a signed transaction is mined at most once. A node that already
  /// knows it counts as accepted. Throws [HyperEvmBroadcastUncertain] when
  /// no endpoint confirmed receipt, and [HyperEvmRpcException] with a code
  /// when a node refused the transaction itself.
  Future<void> sendRawTransaction(String raw, {required String hash}) async {
    final call = HyperEvmRpcCall('eth_sendRawTransaction', [raw]);
    try {
      await batch([call], singleFlight: false);
    } on HyperEvmRpcException catch (e) {
      if (e.isNodeError && _alreadyKnown(e.message)) return;
      if (e.isNodeError) rethrow;
      throw HyperEvmBroadcastUncertain(hash);
    }
  }

  static bool _alreadyKnown(String message) {
    final m = message.toLowerCase();
    return m.contains('already known') ||
        m.contains('known transaction') ||
        m.contains('already imported');
  }

  // ─────────────────────────────── transport ───────────────────────────

  /// Sends [calls] as one batch and returns their results in order.
  /// Identical read batches already in flight are shared.
  Future<List<Object?>> batch(List<HyperEvmRpcCall> calls,
      {bool singleFlight = true}) {
    if (calls.isEmpty) return Future.value(const []);
    if (!singleFlight) return _send(calls);
    final key = jsonEncode([
      for (final c in calls) [c.method, c.params]
    ]);
    final running = _inFlight[key];
    if (running != null) return running;
    final future = _send(calls);
    _inFlight[key] = future;
    void done() {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    }

    future.then((_) => done(), onError: (Object _) => done());
    return future;
  }

  Future<List<Object?>> _send(List<HyperEvmRpcCall> calls) async {
    var budgetSkipped = false;
    var rateLimited = false;
    final order = _order();
    if (order.length < _endpoints.where((e) => e.chainVerified != false).length) {
      // Some endpoint is cooling down: an answer may come from the rest,
      // but if none does the caller is told the network is busy.
      rateLimited = true;
    }
    for (final endpoint in order) {
      final verifying = endpoint.chainVerified != true;
      final needed = calls.length + (verifying ? 1 : 0);
      if (!_hasBudget(endpoint, needed)) {
        budgetSkipped = true;
        continue;
      }
      _spend(endpoint, needed);
      final payload = [
        if (verifying) const HyperEvmRpcCall('eth_chainId').toJson(0),
        for (var i = 0; i < calls.length; i++) calls[i].toJson(i + 1),
      ];
      final http.Response response;
      try {
        final post = _client == null
            ? http.post(Uri.parse(endpoint.url),
                headers: const {'content-type': 'application/json'},
                body: jsonEncode(payload))
            : _client.post(Uri.parse(endpoint.url),
                headers: const {'content-type': 'application/json'},
                body: jsonEncode(payload));
        response = await post.timeout(requestTimeout);
      } catch (_) {
        _coolDown(endpoint);
        continue;
      }
      if (response.statusCode == 429) {
        rateLimited = true;
        _coolDown(endpoint, retryAfter: response.headers['retry-after']);
        continue;
      }
      if (response.statusCode != 200) {
        _coolDown(endpoint);
        continue;
      }
      final Map<int, Map> byId;
      try {
        final decoded = jsonDecode(response.body);
        final list = decoded is List ? decoded : [decoded];
        byId = {
          for (final item in list)
            if (item is Map && item['id'] is int) item['id'] as int: item
        };
      } catch (_) {
        _coolDown(endpoint);
        continue;
      }
      if (verifying) {
        final chain = byId[0]?['result'];
        if (chain is! String) {
          _coolDown(endpoint);
          continue;
        }
        final ok = int.tryParse(chain.replaceFirst('0x', ''), radix: 16) ==
            HyperEvmChain.chainId;
        endpoint.chainVerified = ok;
        if (!ok) continue;
      }
      final results = <Object?>[];
      var retryElsewhere = false;
      for (var i = 0; i < calls.length; i++) {
        final item = byId[i + 1];
        if (item == null) {
          retryElsewhere = true;
          break;
        }
        final error = item['error'];
        if (error != null) {
          final code = error is Map && error['code'] is int
              ? error['code'] as int
              : -32000;
          final message = error is Map
              ? (error['message']?.toString() ?? 'error')
              : error.toString();
          if (_isRateLimit(code, message)) {
            rateLimited = true;
            retryElsewhere = true;
            break;
          }
          throw HyperEvmRpcException(message, code: code);
        }
        results.add(item['result']);
      }
      if (retryElsewhere) {
        _coolDown(endpoint);
        continue;
      }
      endpoint.cooldownUntil = null;
      return results;
    }
    throw HyperEvmRpcException('No HyperEVM RPC answered',
        busy: budgetSkipped || rateLimited);
  }

  static bool _isRateLimit(int code, String message) {
    final m = message.toLowerCase();
    return code == -32005 ||
        code == -32029 ||
        code == 429 ||
        m.contains('rate limit') ||
        m.contains('rate-limit') ||
        m.contains('too many requests');
  }

  /// Usable endpoints in list order. One that is cooling down (it failed
  /// or rate limited this app) is skipped until its time is up: asking a
  /// rate-limited endpoint again only extends the limit.
  List<_Endpoint> _order() {
    final now = _clock();
    return [
      for (final e in _endpoints)
        if (e.chainVerified != false &&
            (e.cooldownUntil == null || !now.isBefore(e.cooldownUntil!)))
          e
    ];
  }

  bool _hasBudget(_Endpoint endpoint, int needed) {
    final cutoff = _clock().subtract(_window);
    endpoint.calls.removeWhere((t) => !t.isAfter(cutoff));
    return endpoint.calls.length + needed <= maxCallsPerMinute;
  }

  void _spend(_Endpoint endpoint, int count) {
    final now = _clock();
    for (var i = 0; i < count; i++) {
      endpoint.calls.add(now);
    }
  }

  void _coolDown(_Endpoint endpoint, {String? retryAfter}) {
    final seconds = int.tryParse(retryAfter ?? '');
    final wait = seconds != null && seconds > 0 && seconds <= 300
        ? Duration(seconds: seconds)
        : _cooldown;
    endpoint.cooldownUntil = _clock().add(wait);
  }

  // ─────────────────────────────── parsing ─────────────────────────────

  static String _address(String value) {
    final hex = value.toLowerCase();
    if (!RegExp(r'^0x[0-9a-f]{40}$').hasMatch(hex)) {
      throw ArgumentError.value(value, 'address', 'not an EVM address');
    }
    return hex;
  }

  static BigInt _quantity(Object? value, String what) {
    if (value is! String || !value.startsWith('0x')) {
      throw HyperEvmRpcException('$what returned no quantity');
    }
    final digits = value.substring(2);
    final parsed =
        digits.isEmpty ? BigInt.zero : BigInt.tryParse(digits, radix: 16);
    if (parsed == null) throw HyperEvmRpcException('$what is not hex');
    return parsed;
  }

  static BigInt _word(Object? value, String what) {
    if (value is! String || !value.startsWith('0x') || value.length != 66) {
      throw HyperEvmRpcException('$what returned no uint256');
    }
    return BigInt.parse(value.substring(2), radix: 16);
  }
}

/// Public HyperEVM endpoints, tried in order: Hyperliquid's own, then
/// dRPC, 1RPC (Automata) and Hypurrscan. Each answered `eth_chainId`
/// 0x3e7, batches, `eth_call` and nonce reads when added (2026-10-12).
const List<String> kHyperEvmRpcEndpoints = [
  'https://rpc.hyperliquid.xyz/evm',
  'https://hyperliquid.drpc.org',
  'https://1rpc.io/hyperliquid',
  'https://rpc.hypurrscan.io',
];

/// `balanceOf(owner)` calldata.
String balanceOfData(String owner) =>
    '0x70a08231${owner.toLowerCase().replaceFirst('0x', '').padLeft(64, '0')}';
