import 'dart:convert';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';

class PendingTrailingStopException implements Exception {
  const PendingTrailingStopException();
  @override
  String toString() => 'The previous trailing stop is not confirmed. Check '
      'your open orders or contact support. No replacement order was sent.';
}

/// Native trailing stops have no client order ID or expiry. An ambiguous POST
/// must remain blocked across restarts: absence from open orders alone does not
/// establish rejection (the order may already have triggered and filled).
class TrailingStopGuard {
  static const boxName = 'hyperliquid_trailing_submissions';
  static final _busy = <String>{};

  /// Check before leverage/funding changes as well as before signing.
  Future<void> ensureAvailable(
      {required String address, required int assetId}) async {
    final key = '${address.toLowerCase()}:$assetId';
    final box = await Hive.openBox<String>(boxName);
    final raw = box.get(key);
    if (raw != null) {
      try {
        final previous = jsonDecode(raw);
        if (previous is! Map ||
            !const ['accepted', 'rejected'].contains(previous['stage'])) {
          throw const PendingTrailingStopException();
        }
      } catch (_) {
        throw const PendingTrailingStopException();
      }
    }
  }

  Future<HlOrderResult> run(
      {required String address,
      required int assetId,
      required Future<HlOrderResult> Function(
              Future<void> Function(HlPendingPost), void Function())
          send}) async {
    final key = '${address.toLowerCase()}:$assetId';
    if (!_busy.add(key)) throw const PendingTrailingStopException();
    try {
      await ensureAvailable(address: address, assetId: assetId);
      final box = await Hive.openBox<String>(boxName);
      Map<String, Object?>? record;
      var started = false;
      Future<void> write(String stage) async {
        record!['stage'] = stage;
        await box.put(key, jsonEncode(record));
        await box.flush();
      }

      try {
        final result = await send((post) async {
          if (record != null ||
              post.action['type'] != 'trailingStop' ||
              post.action['asset'] != assetId) {
            throw const PendingTrailingStopException();
          }
          record = {
            'address': address.toLowerCase(),
            'nonce': post.nonce,
            'action': post.action
          };
          await write('submitting');
        }, () {
          if (record == null || started) {
            throw const PendingTrailingStopException();
          }
          started = true;
        });
        if (!started || record == null) {
          throw const PendingTrailingStopException();
        }
        await write('accepted');
        return result;
      } catch (error) {
        if (record == null) rethrow;
        if (!started || error is HyperliquidRejectedException) {
          await write('rejected');
          rethrow;
        }
        // Undo an in-memory accepted checkpoint if its durable write failed.
        try {
          await write('submitting');
        } catch (_) {}
        throw const PendingTrailingStopException();
      }
    } finally {
      _busy.remove(key);
    }
  }
}
