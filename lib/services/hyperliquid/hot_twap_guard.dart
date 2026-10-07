import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';

class PendingHyperliquidTwapException implements Exception {
  const PendingHyperliquidTwapException();
}

enum HlTwapResolution { accepted, rejected, expired }

/// A previous attempt was resolved, but this invocation sent no new order.
class ResolvedHyperliquidTwapException implements Exception {
  const ResolvedHyperliquidTwapException({required bool accepted})
      : resolution =
            accepted ? HlTwapResolution.accepted : HlTwapResolution.rejected;

  /// The previous attempt's full window has passed with its result unknown.
  const ResolvedHyperliquidTwapException.expired()
      : resolution = HlTwapResolution.expired;

  final HlTwapResolution resolution;
  bool get accepted => resolution == HlTwapResolution.accepted;
}

/// A TWAP has no client order ID. Persist before transport, and never infer
/// non-submission from a missing response or a balance snapshot. An unknown
/// attempt stays unknown; it only stops blocking once its whole duration plus
/// [unlockMargin] has passed, when a new TWAP can no longer run alongside it.
/// Only public request fields and the venue's acknowledged ID are stored.
class HotHyperliquidTwapGuard {
  static const boxName = 'hyperliquid_twap_submissions';
  static const runningBoxName = 'hyperliquid_running_twaps';
  static const unlockMargin = Duration(hours: 1);
  static final Set<String> _busy = {};
  static final Map<String, String> _acknowledged = {};

  /// True once the venue would have ended the TWAP even if it did run.
  bool _windowElapsed(Map<String, dynamic> record) {
    final twap = (record['action'] as Map)['twap'] as Map;
    final deadline = (record['submittedAtMs'] as int) +
        Duration(minutes: twap['m'] as int).inMilliseconds +
        unlockMargin.inMilliseconds;
    return DateTime.now().millisecondsSinceEpoch >= deadline;
  }

  bool _validAction(Object? action) {
    if (action is! Map || action['type'] != 'twapOrder') return false;
    final twap = action['twap'];
    if (twap is! Map) return false;
    final asset = twap['a'];
    final minutes = twap['m'];
    final size = twap['s'];
    final parsedSize = size is String ? double.tryParse(size) : null;
    return asset is int &&
        asset >= 0 &&
        twap['b'] is bool &&
        twap['r'] is bool &&
        twap['t'] is bool &&
        minutes is int &&
        minutes >= HyperliquidExchangeService.minTwapMinutes &&
        minutes <= HyperliquidExchangeService.maxTwapMinutes &&
        parsedSize != null &&
        parsedSize.isFinite &&
        parsedSize > 0;
  }

  Future<void> _write(
      Box<String> box, String key, Map<String, Object?> record) async {
    await box.put(key, jsonEncode(record));
    await box.flush();
  }

  Map<String, dynamic> _readRecord(String raw, String address) {
    Map<String, dynamic> record;
    try {
      record = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      throw const PendingHyperliquidTwapException();
    }
    final nonce = record['nonce'];
    final coin = record['coin'];
    final submittedAt = record['submittedAtMs'];
    if (record['version'] != 1 ||
        record['address'] != address ||
        record['walletId'] is! String ||
        (record['walletId'] as String).isEmpty ||
        nonce is! int ||
        nonce <= 0 ||
        coin is! String ||
        coin.isEmpty ||
        submittedAt is! int ||
        submittedAt <= 0 ||
        !_validAction(record['action']) ||
        !const {'submitting', 'accepted', 'rejected', 'expired'}
            .contains(record['stage'])) {
      throw const PendingHyperliquidTwapException();
    }
    return record;
  }

  /// Preserve the cancellation handle before the checkpoint can be replaced.
  /// Signed request fields, rather than a new ticket, reconstruct the old TWAP.
  Future<void> _preserveAccepted(Map<String, dynamic> record) async {
    final id = record['twapId'];
    if (record['stage'] != 'accepted' || id is! int || id <= 0) {
      throw const PendingHyperliquidTwapException();
    }
    final address = record['address'] as String;
    final action = record['action'] as Map;
    final twap = action['twap'] as Map;
    final running = await Hive.openBox<String>(runningBoxName);
    final key = '$address:$id';
    final existing = running.get(key);
    if (existing != null) {
      final Object? decoded;
      try {
        decoded = jsonDecode(existing);
      } catch (_) {
        throw const PendingHyperliquidTwapException();
      }
      if (decoded is! Map ||
          decoded['address'] != address ||
          decoded['twapId'] != id) {
        throw const PendingHyperliquidTwapException();
      }
      if (decoded['cancelled'] == true) {
        // A confirmed cancellation must not be resurrected by startup recovery.
        await running.flush();
        return;
      }
    }
    await _write(running, key, {
      'twapId': id,
      'assetId': twap['a'],
      'coin': record['coin'],
      'address': address,
      'isBuy': twap['b'],
      'reduceOnly': twap['r'],
      'size': double.parse(twap['s'] as String),
      'durationMinutes': twap['m'],
      'startedAt': record['submittedAtMs'],
    });
  }

  /// Read-only venue behavior: repair local storage after an interrupted write.
  /// This does not acknowledge the result or allow an unknown attempt to retry.
  Future<void> restoreAccepted(String address) async {
    final key = address.toLowerCase();
    if (!_busy.add(key)) return;
    try {
      final box = await Hive.openBox<String>(boxName);
      final raw = box.get(key);
      if (raw == null) return;
      final record = _readRecord(raw, key);
      if (record['stage'] == 'accepted') await _preserveAccepted(record);
    } finally {
      _busy.remove(key);
    }
  }

  Future<HlOrderResult> run({
    required String walletId,
    required String address,
    required String coin,
    required void Function() ensureCurrent,
    required Future<HlOrderResult> Function(
      Future<void> Function(HlPendingPost post) beforeSubmit,
      void Function() beforeSend,
    ) send,
  }) async {
    final key = address.toLowerCase();
    if (walletId.isEmpty ||
        coin.isEmpty ||
        !RegExp(r'^0x[0-9a-f]{40}$').hasMatch(key) ||
        !_busy.add(key)) {
      throw const PendingHyperliquidTwapException();
    }
    try {
      ensureCurrent();
      final box = await Hive.openBox<String>(boxName);
      ensureCurrent();
      final previousRaw = box.get(key);
      if (previousRaw != null) {
        final previous = _readRecord(previousRaw, key);
        final stage = previous['stage'];
        // Missing IDs have no safe automatic recovery. A fresh tap, session,
        // process, or nonce must not turn this into another submission while
        // the venue could still be running it. After the whole window has
        // passed the result is still unknown, so it is surfaced once as such,
        // never as accepted or rejected.
        if (stage == 'submitting') {
          if (!_windowElapsed(previous)) {
            throw const PendingHyperliquidTwapException();
          }
          previous['stage'] = 'expired';
          await _write(box, key, previous);
          ensureCurrent();
          _acknowledged[key] = jsonEncode(previous);
          throw const ResolvedHyperliquidTwapException.expired();
        }
        final twapId = previous['twapId'];
        if (stage == 'accepted' && (twapId is! int || twapId <= 0)) {
          throw const PendingHyperliquidTwapException();
        }
        if (_acknowledged[key] != previousRaw) {
          // Re-flush even if Hive changed its in-memory cache before an earlier
          // write failed. This tap acknowledges the old result only.
          await _write(box, key, previous);
          if (stage == 'accepted') await _preserveAccepted(previous);
          ensureCurrent();
          _acknowledged[key] = jsonEncode(previous);
          throw stage == 'expired'
              ? const ResolvedHyperliquidTwapException.expired()
              : ResolvedHyperliquidTwapException(accepted: stage == 'accepted');
        }
      }

      Map<String, Object?>? record;
      var postStarted = false;
      Future<void> beforeSubmit(HlPendingPost post) async {
        ensureCurrent();
        if (record != null || !_validAction(post.action) || post.nonce <= 0) {
          throw const PendingHyperliquidTwapException();
        }
        record = {
          'version': 1,
          'walletId': walletId,
          'address': key,
          'coin': coin,
          'submittedAtMs': DateTime.now().millisecondsSinceEpoch,
          'nonce': post.nonce,
          'action': post.action,
          'stage': 'submitting',
        };
        _acknowledged.remove(key);
        await _write(box, key, record!);
        ensureCurrent();
      }

      void beforeSend() {
        ensureCurrent();
        if (record == null || postStarted) {
          throw const PendingHyperliquidTwapException();
        }
        postStarted = true;
      }

      try {
        final result = await send(beforeSubmit, beforeSend);
        final twapId = result.oid;
        if (!postStarted ||
            record == null ||
            result.kind != HlOrderResultKind.resting ||
            twapId == null ||
            twapId <= 0) {
          throw const PendingHyperliquidTwapException();
        }
        record!['stage'] = 'accepted';
        record!['twapId'] = twapId;
        await _write(box, key, record!);
        await _preserveAccepted(Map<String, dynamic>.from(record!));
        _acknowledged[key] = jsonEncode(record);
        return result;
      } catch (error) {
        if (record == null) rethrow;
        if (!postStarted || error is HyperliquidRejectedException) {
          record!['stage'] = 'rejected';
          await _write(box, key, record!);
          _acknowledged[key] = jsonEncode(record);
          rethrow;
        }
        // Arbitrary transport/parsing/storage failures after dispatch do not
        // prove rejection. Keep the persisted attempt blocking new TWAPs.
        throw const PendingHyperliquidTwapException();
      }
    } finally {
      _busy.remove(key);
    }
  }
}
