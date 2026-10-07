import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:kute/models/bitcoin_model.dart' show BitcoinFeeModel;
import 'package:kute/services/api/api_client.dart';

/// No fee estimate could be produced: the network calls failed and the
/// last known good rates are missing or older than a day. Callers map
/// this to one plain sentence; the [cause] is for logs only.
class BitcoinFeeUnavailableException implements Exception {
  const BitcoinFeeUnavailableException([this.cause]);
  final Object? cause;

  @override
  String toString() =>
      'BitcoinFeeUnavailableException(${cause ?? 'no fee estimate'})';
}

/// Fetches mempool.space recommended fee rates, then Blockstream's
/// Esplora estimates if the primary fails. Requests have a timeout and
/// bounded retries, followed by a last known good cache fallback.
///
/// The fallback lives in memory and in the `settings` Hive box, is served
/// only while younger than [maxCacheAge], and is flagged
/// [BitcoinFeeModel.isStale] so the UI can say the rates are recent, not
/// live. Concurrent callers share one in-flight request.
class BitcoinFeeEstimateService {
  BitcoinFeeEstimateService._();
  static final BitcoinFeeEstimateService instance =
      BitcoinFeeEstimateService._();

  static const String cacheKey = 'last_fee_rates_v1';
  static const Duration maxCacheAge = Duration(hours: 24);
  static const Duration requestTimeout = Duration(seconds: 10);
  static const int attempts = 3;
  static const List<Duration> _backoff = [
    Duration(milliseconds: 500),
    Duration(milliseconds: 1500),
  ];

  BitcoinFeeModel? _memory;
  DateTime? _memoryAt;
  Future<BitcoinFeeModel>? _inFlight;

  /// Forgets the in-memory last known good rates and any in-flight
  /// request, so each test starts from a cold service.
  @visibleForTesting
  void debugReset() {
    _memory = null;
    _memoryAt = null;
    _inFlight = null;
  }

  Future<BitcoinFeeModel> fetch() {
    final running = _inFlight;
    if (running != null) return running;
    final future = _fetch().whenComplete(() => _inFlight = null);
    _inFlight = future;
    return future;
  }

  Future<BitcoinFeeModel> _fetch() async {
    Object? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_backoff[attempt - 1]);
      }
      // Switch hosts after the first failure instead of retrying a host
      // the device cannot reach. At most three requests (32s including
      // backoff): one primary request, then two fallback attempts.
      final isPrimary = attempt == 0;
      final baseUrl = isPrimary
          ? 'https://mempool.space/api'
          : 'https://blockstream.info/api';
      final path = isPrimary ? '/v1/fees/recommended' : '/fee-estimates';
      final client = http.Client();
      try {
        final response = await ApiClient(baseUrl, client: client)
            .get<Map<String, dynamic>>(
              path,
              (json) => json as Map<String, dynamic>,
            )
            .timeout(requestTimeout);
        if (response.isSuccess && response.data != null) {
          final fees = isPrimary
              ? _parse(response.data!)
              : _parseEsplora(response.data!);
          _remember(fees);
          if (kDebugMode) {
            debugPrint('BitcoinFeeEstimateService: ${Uri.parse(baseUrl).host}');
          }
          return fees;
        }
        lastError = response.error ?? 'HTTP ${response.statusCode}';
      } catch (e) {
        lastError = e;
      } finally {
        client.close();
      }
    }
    final cached = lastKnownGood();
    if (cached != null) return cached;
    throw BitcoinFeeUnavailableException(lastError);
  }

  BitcoinFeeModel _parse(Map<String, dynamic> data) {
    double read(String key) {
      final value = data[key];
      if (value is num && value.isFinite && value > 0) return value.toDouble();
      throw const FormatException('Malformed fee estimate');
    }

    return BitcoinFeeModel(
      read('fastestFee'),
      read('halfHourFee'),
      read('hourFee'),
      read('economyFee'),
      read('minimumFee'),
    );
  }

  /// Esplora returns sat/vB keyed by the confirmation target in blocks:
  /// https://github.com/Blockstream/esplora/blob/master/API.md#fee-estimates
  /// The named time tiers use 1/3/6 blocks. The two slower tiers use
  /// 144/1008 blocks; the final tier is an estimate, not a relay-policy
  /// minimum (Esplora does not expose that in this response).
  BitcoinFeeModel _parseEsplora(Map<String, dynamic> data) => _parse({
        'fastestFee': data['1'],
        'halfHourFee': data['3'],
        'hourFee': data['6'],
        'economyFee': data['144'],
        'minimumFee': data['1008'],
      });

  /// The most recent successful rates, marked stale, or null when none
  /// exist or they are older than [maxCacheAge].
  BitcoinFeeModel? lastKnownGood() {
    final now = DateTime.now();
    var fees = _memory;
    var at = _memoryAt;
    if (fees == null || at == null) {
      final stored = _readStored();
      if (stored != null) {
        fees = stored.fees;
        at = stored.at;
      }
    }
    if (fees == null || at == null) return null;
    final age = now.difference(at);
    if (age.isNegative || age > maxCacheAge) return null;
    return BitcoinFeeModel(fees.fastestFee, fees.halfHourFee, fees.hourFee,
        fees.economyFee, fees.minimumFee,
        isStale: true);
  }

  void _remember(BitcoinFeeModel fees) {
    _memory = fees;
    _memoryAt = DateTime.now();
    try {
      if (!Hive.isBoxOpen('settings')) return;
      Hive.box('settings').put(cacheKey, {
        'fastestFee': fees.fastestFee,
        'halfHourFee': fees.halfHourFee,
        'hourFee': fees.hourFee,
        'economyFee': fees.economyFee,
        'minimumFee': fees.minimumFee,
        'at': _memoryAt!.millisecondsSinceEpoch,
      }).ignore();
    } catch (_) {
      // The cache is a convenience; never let storage failures block a send.
    }
  }

  ({BitcoinFeeModel fees, DateTime at})? _readStored() {
    try {
      if (!Hive.isBoxOpen('settings')) return null;
      final raw = Hive.box('settings').get(cacheKey);
      if (raw is! Map) return null;
      double? read(String key) {
        final value = raw[key];
        return value is num && value.isFinite && value > 0
            ? value.toDouble()
            : null;
      }

      final fastest = read('fastestFee');
      final halfHour = read('halfHourFee');
      final hour = read('hourFee');
      final economy = read('economyFee');
      final minimum = read('minimumFee');
      final at = raw['at'];
      if (fastest == null ||
          halfHour == null ||
          hour == null ||
          economy == null ||
          minimum == null ||
          at is! int) {
        return null;
      }
      return (
        fees: BitcoinFeeModel(fastest, halfHour, hour, economy, minimum),
        at: DateTime.fromMillisecondsSinceEpoch(at),
      );
    } catch (_) {
      return null;
    }
  }
}
