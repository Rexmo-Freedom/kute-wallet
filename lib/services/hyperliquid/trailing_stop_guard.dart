import 'dart:convert';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';

class PendingTrailingStopException implements Exception {
  const PendingTrailingStopException();
  @override
  String toString() => 'The previous trailing stop is not confirmed yet. '
      'Check your open orders. No replacement order was sent.';
}

/// What the venue shows of an unclear trailing-stop send, read from its
/// open orders and its order history.
enum TrailingStopVenueState {
  /// A trailing stop on the asset, placed at or after the send, is resting
  /// or in the history (it triggered, filled or was cancelled): the send
  /// landed.
  found,

  /// Both lists read cleanly and neither has it.
  absent,

  /// A list could not be read.
  unknown,
}

/// Looks the send signed at [sentAtMs] (its nonce, epoch ms) up on the
/// venue.
typedef TrailingStopLookup = Future<TrailingStopVenueState> Function(
    int sentAtMs);

/// Native trailing stops have no client order ID or expiry. An ambiguous POST
/// must remain blocked across restarts: absence from open orders alone does not
/// establish rejection (the order may already have triggered and filled).
///
/// It is reconciled, though, never left blocking until storage is wiped: a
/// [TrailingStopLookup] that finds the stop resting or in the order history
/// clears the block (it landed), and one that finds it in neither list,
/// both read cleanly, once [absentAfter] has passed since the send, clears
/// it too (it never reached the book). Only while the venue cannot say
/// does the asset stay blocked, the copy pointing at the open orders.
class TrailingStopGuard {
  TrailingStopGuard({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const boxName = 'hyperliquid_trailing_submissions';
  static final _busy = <String>{};

  /// How long after the send a stop absent from both lists counts as
  /// never placed: the POST is answered (or dropped) within seconds, so a
  /// stop that reached the book is listed well inside this. Checked on
  /// the next attempt only, never by a timer.
  static const absentAfter = Duration(minutes: 2);

  final DateTime Function() _clock;

  /// Check before leverage/funding changes as well as before signing.
  /// With [lookup], an unclear earlier send is reconciled first.
  Future<void> ensureAvailable({
    required String address,
    required int assetId,
    TrailingStopLookup? lookup,
  }) async {
    final key = '${address.toLowerCase()}:$assetId';
    final box = await Hive.openBox<String>(boxName);
    final raw = box.get(key);
    if (raw == null) return;
    Map<dynamic, dynamic>? previous;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) previous = decoded;
    } catch (_) {}
    if (previous != null &&
        const ['accepted', 'rejected'].contains(previous['stage'])) {
      return;
    }
    final sentAt = previous?['nonce'];
    if (lookup == null || sentAt is! int) {
      throw const PendingTrailingStopException();
    }
    TrailingStopVenueState seen;
    try {
      seen = await lookup(sentAt);
    } catch (_) {
      seen = TrailingStopVenueState.unknown;
    }
    final age =
        _clock().difference(DateTime.fromMillisecondsSinceEpoch(sentAt));
    final String settled;
    if (seen == TrailingStopVenueState.found) {
      settled = 'accepted';
    } else if (seen == TrailingStopVenueState.absent && age >= absentAfter) {
      settled = 'rejected';
    } else {
      throw const PendingTrailingStopException();
    }
    previous!['stage'] = settled;
    previous['reconciled'] = true;
    await box.put(key, jsonEncode(previous));
    await box.flush();
  }

  Future<HlOrderResult> run(
      {required String address,
      required int assetId,
      TrailingStopLookup? lookup,
      required Future<HlOrderResult> Function(
              Future<void> Function(HlPendingPost), void Function())
          send}) async {
    final key = '${address.toLowerCase()}:$assetId';
    if (!_busy.add(key)) throw const PendingTrailingStopException();
    try {
      await ensureAvailable(
          address: address, assetId: assetId, lookup: lookup);
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
