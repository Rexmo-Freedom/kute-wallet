import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:kute/services/api/api_client.dart';
import 'package:kute/services/bitcoin/tx_details_cache.dart';

class MempoolAddressData {
  final int balanceSats;
  final int txCount;
  final int fundedSum;
  final int spentSum;

  MempoolAddressData({
    required this.balanceSats,
    required this.txCount,
    required this.fundedSum,
    required this.spentSum,
  });
}

class MempoolTransaction {
  final String txid;
  final int? blockHeight;
  final int? blockTime;
  final bool confirmed;
  final int fee;
  final int balanceChange;

  MempoolTransaction({
    required this.txid,
    this.blockHeight,
    this.blockTime,
    required this.confirmed,
    required this.fee,
    required this.balanceChange,
  });

  Map<String, dynamic> toJson() => {
        'txid': txid,
        'blockHeight': blockHeight,
        'blockTime': blockTime,
        'confirmed': confirmed,
        'fee': fee,
        'balanceChange': balanceChange,
      };

  factory MempoolTransaction.fromJson(Map<String, dynamic> json) =>
      MempoolTransaction(
        txid: json['txid'] as String,
        blockHeight: json['blockHeight'] as int?,
        blockTime: json['blockTime'] as int?,
        confirmed: json['confirmed'] as bool? ?? false,
        fee: (json['fee'] as num?)?.toInt() ?? 0,
        balanceChange: (json['balanceChange'] as num?)?.toInt() ?? 0,
      );
}

/// One spent input of a transaction as mempool.space reports it (a `vin[]`
/// entry). [valueSats] and [address] come from the embedded `prevout`, so no
/// second lookup per input is needed. Both are null for a coinbase input, and
/// [address] is null for non-address scripts (bare multisig, OP_RETURN).
class MempoolTxInput {
  final String prevTxid;
  final int prevVout;
  final int? valueSats;
  final String? address;
  final bool isCoinbase;

  const MempoolTxInput({
    required this.prevTxid,
    required this.prevVout,
    this.valueSats,
    this.address,
    this.isCoinbase = false,
  });

  Map<String, dynamic> toJson() => {
        'prevTxid': prevTxid,
        'prevVout': prevVout,
        'valueSats': valueSats,
        'address': address,
        'isCoinbase': isCoinbase,
      };

  factory MempoolTxInput.fromJson(Map<String, dynamic> json) => MempoolTxInput(
        prevTxid: json['prevTxid'] as String? ?? '',
        prevVout: (json['prevVout'] as num?)?.toInt() ?? 0,
        valueSats: (json['valueSats'] as num?)?.toInt(),
        address: json['address'] as String?,
        isCoinbase: json['isCoinbase'] as bool? ?? false,
      );
}

/// One output of a transaction (a `vout[]` entry). [address] is null for
/// non-address scripts.
class MempoolTxOutput {
  final int valueSats;
  final String? address;

  const MempoolTxOutput({required this.valueSats, this.address});

  Map<String, dynamic> toJson() => {
        'valueSats': valueSats,
        'address': address,
      };

  factory MempoolTxOutput.fromJson(Map<String, dynamic> json) =>
      MempoolTxOutput(
        valueSats: (json['valueSats'] as num?)?.toInt() ?? 0,
        address: json['address'] as String?,
      );
}

/// Inputs + outputs view of a single transaction from `GET /tx/{txid}`.
class MempoolTxDetails {
  final String txid;
  final List<MempoolTxInput> inputs;
  final List<MempoolTxOutput> outputs;
  final int fee;
  final bool confirmed;
  final int? blockHeight;
  final int? blockTime;

  const MempoolTxDetails({
    required this.txid,
    required this.inputs,
    required this.outputs,
    required this.fee,
    required this.confirmed,
    this.blockHeight,
    this.blockTime,
  });

  factory MempoolTxDetails.fromMempoolJson(Map<String, dynamic> json) {
    final status = json['status'] as Map<String, dynamic>? ?? const {};
    final confirmed = status['confirmed'] as bool? ?? false;

    final inputs = <MempoolTxInput>[];
    for (final raw in (json['vin'] as List<dynamic>? ?? const [])) {
      final vin = raw as Map<String, dynamic>;
      final prevout = vin['prevout'] as Map<String, dynamic>?;
      inputs.add(MempoolTxInput(
        prevTxid: vin['txid'] as String? ?? '',
        prevVout: (vin['vout'] as num?)?.toInt() ?? 0,
        valueSats: (prevout?['value'] as num?)?.toInt(),
        address: prevout?['scriptpubkey_address'] as String?,
        isCoinbase: vin['is_coinbase'] as bool? ?? false,
      ));
    }

    final outputs = <MempoolTxOutput>[];
    for (final raw in (json['vout'] as List<dynamic>? ?? const [])) {
      final vout = raw as Map<String, dynamic>;
      outputs.add(MempoolTxOutput(
        valueSats: (vout['value'] as num?)?.toInt() ?? 0,
        address: vout['scriptpubkey_address'] as String?,
      ));
    }

    return MempoolTxDetails(
      txid: json['txid'] as String,
      inputs: inputs,
      outputs: outputs,
      fee: (json['fee'] as num?)?.toInt() ?? 0,
      confirmed: confirmed,
      blockHeight: confirmed ? (status['block_height'] as num?)?.toInt() : null,
      blockTime: confirmed ? (status['block_time'] as num?)?.toInt() : null,
    );
  }

  /// Round-trip shape for [TxDetailsCache]; distinct from the explorer's own
  /// `vin`/`vout` wire format so a schema change here never has to reinterpret
  /// an explorer payload.
  Map<String, dynamic> toJson() => {
        'txid': txid,
        'inputs': inputs.map((i) => i.toJson()).toList(),
        'outputs': outputs.map((o) => o.toJson()).toList(),
        'fee': fee,
        'confirmed': confirmed,
        'blockHeight': blockHeight,
        'blockTime': blockTime,
      };

  factory MempoolTxDetails.fromJson(Map<String, dynamic> json) =>
      MempoolTxDetails(
        txid: json['txid'] as String? ?? '',
        inputs: [
          for (final raw in (json['inputs'] as List<dynamic>? ?? const []))
            MempoolTxInput.fromJson(Map<String, dynamic>.from(raw as Map)),
        ],
        outputs: [
          for (final raw in (json['outputs'] as List<dynamic>? ?? const []))
            MempoolTxOutput.fromJson(Map<String, dynamic>.from(raw as Map)),
        ],
        fee: (json['fee'] as num?)?.toInt() ?? 0,
        confirmed: json['confirmed'] as bool? ?? false,
        blockHeight: (json['blockHeight'] as num?)?.toInt(),
        blockTime: (json['blockTime'] as num?)?.toInt(),
      );
}

class MempoolAddressService {
  static const _hosts = [
    'https://mempool.space/api',
    'https://blockstream.info/api',
  ];

  /// Grace period for the fallback host, which is only reached once the
  /// primary has already cost us [_primaryTimeout].
  static const requestTimeout = Duration(seconds: 7);

  /// The primary host answers in well under a second when it is healthy, so
  /// waiting 7 s before trying the fallback only ever delayed the graph.
  static const _primaryTimeout = Duration(seconds: 4);

  /// One long-lived HTTP client per host, so back-to-back reads (prefetching
  /// a list of rows, resolving a transaction's input values) reuse the open
  /// TLS connection instead of paying a fresh handshake each time. A failed
  /// attempt drops its client, so a stalled connection is never reused.
  static final Map<String, http.Client> _clients = {};

  static http.Client _clientFor(String base) =>
      _clients[base] ??= http.Client();

  static void _dropClient(String base) {
    final client = _clients.remove(base);
    try {
      client?.close();
    } catch (_) {}
  }

  /// The host that answered the previous read, so the log names a host
  /// only when the answering host changes (a fallback or a recovery)
  /// instead of once per read.
  static String? _lastAnsweringHost;

  /// When the primary host last failed to answer. For a minute after,
  /// reads go straight to the fallback instead of each paying the
  /// primary's timeout first; a sync of a few addresses otherwise took
  /// longer than its own budget on a network that blocks the primary.
  static DateTime? _primaryDownAt;
  static const _primaryRetryAfter = Duration(minutes: 1);

  /// Both hosts expose the same Esplora read API.
  static Future<T> _read<T>(String path, T Function(String) parse) async {
    for (var i = 0; i < _hosts.length; i++) {
      final base = _hosts[i];
      final downAt = _primaryDownAt;
      if (i == 0 &&
          downAt != null &&
          DateTime.now().difference(downAt) < _primaryRetryAfter) {
        continue;
      }
      try {
        final response = await ApiClient(base, client: _clientFor(base))
            .getRaw(path)
            .timeout(i == 0 ? _primaryTimeout : requestTimeout);
        // A non-2xx is the host's answer, not a broken connection: keep the
        // client and just try the next host.
        if (!response.isSuccess) continue;
        final result = parse(response.data!);
        final host = Uri.parse(base).host;
        if (kDebugMode && host != _lastAnsweringHost) {
          debugPrint('Bitcoin explorer answered: $host');
        }
        _lastAnsweringHost = host;
        return result;
      } catch (_) {
        // Transport and malformed-response failures both try the next host,
        // and the connection that carried them is thrown away.
        _dropClient(base);
        if (i == 0) _primaryDownAt = DateTime.now();
      }
    }
    throw StateError('Bitcoin explorer unavailable');
  }

  static Future<T> _readJson<T>(String path, T Function(dynamic) parse) =>
      _read(path, (body) => parse(jsonDecode(body)));

  static Future<int> fetchBlockTipHeight() async {
    return _read('/blocks/tip/height', (body) {
      final height = int.parse(body.trim());
      if (height < 0) throw const FormatException('Invalid block height');
      return height;
    });
  }

  static Future<MempoolAddressData> fetchAddressData(String address) async {
    return _readJson('/address/${Uri.encodeComponent(address)}', (json) {
      final data = json as Map<String, dynamic>;
      final chain = data['chain_stats'] as Map<String, dynamic>;
      final mempool = data['mempool_stats'] as Map<String, dynamic>;

      final fundedChain = (chain['funded_txo_sum'] as num).toInt();
      final spentChain = (chain['spent_txo_sum'] as num).toInt();
      final fundedMempool = (mempool['funded_txo_sum'] as num).toInt();
      final spentMempool = (mempool['spent_txo_sum'] as num).toInt();

      final totalFunded = fundedChain + fundedMempool;
      final totalSpent = spentChain + spentMempool;

      return MempoolAddressData(
        balanceSats: totalFunded - totalSpent,
        txCount: (chain['tx_count'] as num).toInt() +
            (mempool['tx_count'] as num).toInt(),
        fundedSum: totalFunded,
        spentSum: totalSpent,
      );
    });
  }

  static Future<List<MempoolTransaction>> fetchAddressTransactions(
    String address,
  ) async {
    return _readJson('/address/${Uri.encodeComponent(address)}/txs', (json) {
      return (json as List<dynamic>).map((tx) {
        final txMap = tx as Map<String, dynamic>;
        final status = txMap['status'] as Map<String, dynamic>;
        final confirmed = status['confirmed'] as bool? ?? false;

        int received = 0;
        int sent = 0;

        for (final output in (txMap['vout'] as List<dynamic>? ?? [])) {
          if (output['scriptpubkey_address'] == address) {
            received += (output['value'] as num).toInt();
          }
        }

        for (final input in (txMap['vin'] as List<dynamic>? ?? [])) {
          final prevout = input['prevout'] as Map<String, dynamic>?;
          if (prevout != null && prevout['scriptpubkey_address'] == address) {
            sent += (prevout['value'] as num).toInt();
          }
        }

        return MempoolTransaction(
          txid: txMap['txid'] as String,
          blockHeight:
              confirmed ? (status['block_height'] as num?)?.toInt() : null,
          blockTime: confirmed ? (status['block_time'] as num?)?.toInt() : null,
          confirmed: confirmed,
          fee: (txMap['fee'] as num?)?.toInt() ?? 0,
          balanceChange: received - sent,
        );
      }).toList();
    });
  }

  /// Recent [fetchTransaction] results keyed by txid, so reopening a detail
  /// sheet never refetches. A txid's inputs, outputs and fee are immutable
  /// (an RBF replacement is a different txid); only the status fields can go
  /// stale, and the sheets read status from their own rows, not from here.
  static final Map<String, MempoolTxDetails> _txCache = {};
  static const int _txCacheMax = 64;

  static final RegExp _txidPattern = RegExp(r'^[0-9a-f]{64}$');

  /// In-flight lookups keyed by txid, so two sheets (or a prefetch racing a
  /// tap) share one round trip.
  static final Map<String, Future<MempoolTxDetails?>> _txInFlight = {};

  static void _remember(String id, MempoolTxDetails details) {
    if (!_txCache.containsKey(id) && _txCache.length >= _txCacheMax) {
      _txCache.remove(_txCache.keys.first);
    }
    _txCache[id] = details;
  }

  /// Inputs and outputs (values + addresses) of one transaction. Returns
  /// null on any failure (offline, non-2xx, malformed payload); it never
  /// throws, so the UI can render nothing instead of an error.
  ///
  /// Served from memory, then from the on-disk [TxDetailsCache] (a confirmed
  /// transaction's braid is immutable), then from the explorer. Pass
  /// [refresh] to skip both caches and go straight to the network.
  static Future<MempoolTxDetails?> fetchTransaction(
    String txid, {
    bool refresh = false,
  }) {
    final id = txid.toLowerCase();
    if (!_txidPattern.hasMatch(id)) {
      return Future.value(null);
    }
    if (!refresh) {
      final cached = _txCache[id];
      if (cached != null) return Future.value(cached);
      final inFlight = _txInFlight[id];
      if (inFlight != null) return inFlight;
    }
    final future = _loadTransaction(id, refresh: refresh);
    _txInFlight[id] = future;
    unawaited(future.whenComplete(() {
      if (identical(_txInFlight[id], future)) _txInFlight.remove(id);
    }));
    return future;
  }

  static Future<MempoolTxDetails?> _loadTransaction(
    String id, {
    required bool refresh,
  }) async {
    if (!refresh) {
      final stored = await TxDetailsCache.read(id);
      if (stored != null) {
        _remember(id, stored);
        return stored;
      }
    }
    try {
      final details = await _readJson('/tx/$id', (json) {
        final result =
            MempoolTxDetails.fromMempoolJson(json as Map<String, dynamic>);
        if (result.txid.toLowerCase() != id) {
          throw const FormatException('Explorer returned another transaction');
        }
        return result;
      });
      _remember(id, details);
      // Persisting is best-effort and must never delay the caller.
      unawaited(TxDetailsCache.write(details));
      return details;
    } catch (_) {
      return null;
    }
  }

  /// Warm the caches for [txids] ahead of a tap, so opening a detail sheet
  /// paints its flow graph straight away instead of waiting on a round trip.
  /// Bounded to two concurrent requests so it never starves the sheet the
  /// person is actually looking at, skips anything already cached or in
  /// flight, and swallows every failure.
  static Future<void> prefetchTransactions(List<String> txids) async {
    final pending = <String>[];
    for (final raw in txids) {
      final id = raw.toLowerCase();
      if (!_txidPattern.hasMatch(id)) continue;
      if (_txCache.containsKey(id) || _txInFlight.containsKey(id)) continue;
      if (pending.contains(id)) continue;
      pending.add(id);
    }
    if (pending.isEmpty) return;

    var cursor = 0;
    Future<void> worker() async {
      while (cursor < pending.length) {
        await fetchTransaction(pending[cursor++]);
      }
    }

    await Future.wait(List.generate(min(2, pending.length), (_) => worker()));
  }
}

/// Event emitted by [MempoolWebSocketService] when address data changes.
class MempoolAddressUpdate {
  /// New transaction detected (from `address-transactions` event).
  final Map<String, dynamic>? newTx;

  /// A new block was mined (may confirm pending txs).
  final bool newBlock;

  MempoolAddressUpdate({this.newTx, this.newBlock = false});
}

/// WebSocket-based real-time updates from mempool.space.
///
/// Connects to `wss://mempool.space/api/v1/ws`, subscribes to address tracking,
/// and emits [MempoolAddressUpdate] events for new transactions and blocks.
/// Automatically reconnects with exponential backoff on failure.
class MempoolWebSocketService {
  static const String _wsUrl = 'wss://mempool.space/api/v1/ws';
  static const int _maxBackoffSeconds = 300; // 5 minutes

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  String? _trackedAddress;
  bool _disposed = false;
  int _reconnectAttempt = 0;

  final _controller = StreamController<MempoolAddressUpdate>.broadcast();

  /// Stream of real-time address updates.
  Stream<MempoolAddressUpdate> get updates => _controller.stream;

  /// Whether the WebSocket is currently connected.
  bool get isConnected => _channel != null;

  /// Connect to the WebSocket and start tracking [address].
  Future<void> connect(String address) async {
    if (_disposed) return;
    _trackedAddress = address;
    _reconnectAttempt = 0;
    await _connectInternal();
  }

  Future<void> _connectInternal() async {
    if (_disposed || _trackedAddress == null) return;

    // Clean up any existing connection
    await _closeChannel();

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));

      // Wait for connection to be ready
      await _channel!.ready;

      // Subscribe to address tracking
      _channel!.sink.add(jsonEncode({
        'track-address': _trackedAddress,
      }));

      _reconnectAttempt = 0;

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: (error) {
          _scheduleReconnect();
        },
        onDone: () {
          _scheduleReconnect();
        },
      );
    } catch (e) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;

      // New transaction for tracked address
      if (data.containsKey('address-transactions')) {
        final txData = data['address-transactions'];
        if (txData is Map<String, dynamic>) {
          // Single tx notification
          _controller.add(MempoolAddressUpdate(newTx: txData));
        } else if (txData is List) {
          for (final tx in txData) {
            _controller
                .add(MempoolAddressUpdate(newTx: tx as Map<String, dynamic>));
          }
        }
      }

      // New block mined — may confirm pending transactions
      if (data.containsKey('block')) {
        _controller.add(MempoolAddressUpdate(newBlock: true));
      }
    } catch (_) {
      // intentionally empty
    }
  }

  void _scheduleReconnect() {
    if (_disposed || _trackedAddress == null) return;

    _reconnectTimer?.cancel();
    _reconnectAttempt++;
    final delaySeconds = min(
      pow(2, _reconnectAttempt).toInt(),
      _maxBackoffSeconds,
    );
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _connectInternal();
    });
  }

  Future<void> _closeChannel() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  /// Disconnect and stop tracking.
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _trackedAddress = null;
    await _closeChannel();
  }

  /// Permanently dispose this service. Cannot be reused after calling this.
  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _controller.close();
  }
}
