import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/services/polymarket/placement_diagnostics.dart';
import 'package:kute/services/polymarket_order_v2.dart';

class PendingPolymarketOrder implements Exception {
  const PendingPolymarketOrder();

  @override
  String toString() =>
      'Your prediction may already have been submitted and is still being verified. '
      'Check your orders and activity before trying again.';
}

/// This order was posted and the venue's answer proves neither acceptance
/// nor refusal (a timeout, a 5xx, an acknowledgement for another order).
/// Its row keeps protecting the outcome like any [PendingPolymarketOrder];
/// the type only tells analytics that the order itself went out, rather
/// than an earlier one blocking it.
class PolymarketOrderOutcomeUnknown extends PendingPolymarketOrder {
  const PolymarketOrderOutcomeUnknown();
}

/// The earlier submission is still unaccounted for because the venue could
/// not be reached to check it, not because it answered. It is still a
/// [PendingPolymarketOrder] (nothing new may be sent), but the person is
/// told about the connection, not about a prediction they never saw.
class PolymarketOrderCheckUnavailable extends PendingPolymarketOrder {
  const PolymarketOrderCheckUnavailable();
  @override
  String toString() =>
      'Could not reach Polymarket to check an earlier prediction. '
      'Check your connection and try again.';
}

/// Another placement for this account is running in the app right now
/// (it holds the account until its own answer is in). Nothing was sent by
/// the call that got this. It is still a [PendingPolymarketOrder], so no
/// caller treats it as permission to send, but it is not an unknown
/// submission: the person is told the earlier one is still going through.
class PolymarketOrderInProgress extends PendingPolymarketOrder {
  const PolymarketOrderInProgress();
  @override
  String toString() =>
      'An earlier prediction on this account is still being placed. '
      'Wait a moment, then check again.';
}

class ResolvedPolymarketOrder implements Exception {
  const ResolvedPolymarketOrder({required this.accepted});
  final bool accepted;

  @override
  String toString() => accepted
      ? 'The previous prediction order was found. No new order was sent. '
          'Review your orders and balance before continuing.'
      : 'The previous prediction order was not accepted. No new order was sent. '
          'Review your prediction before trying again.';
}

typedef GuardedPolymarketOrderSubmit = Future<Map<String, dynamic>> Function({
  required SignedOrderV2 order,
  required String exchange,
  required void Function() ensureCurrent,
  required Future<Map<String, dynamic>> Function(void Function() beforePost)
      send,
});

/// Serializes orders for an account and persists their locally computed hash
/// before POST. A missing response or a 404 never permits a replacement order.
/// Stores public references only; credentials and signatures remain in memory.
class HotPolymarketOrderGuard {
  static const boxName = 'polymarket_order_submissions';

  /// How long a submission the venue does not know stays protected before
  /// it is settled as never accepted.
  static const unknownSubmissionGrace = Duration(minutes: 2);

  /// How long a submission the venue answered for, but not in a way that
  /// proves anything (an order that is not this one, or a status this code
  /// does not know), keeps blocking. Past it the row is settled as if the
  /// order were out there: that tap is told to review its orders and
  /// nothing new is sent, and the next one is free. Without it such a row
  /// blocked the outcome forever with no way out from the app.
  static const unresolvedSubmissionExpiry = Duration(minutes: 30);
  static final Set<String> _busy = {};

  /// Whether a placement or a check holds [depositWallet] in this app now.
  static bool isBusy(String depositWallet) =>
      _busy.contains(depositWallet.toLowerCase());

  /// Whether [depositWallet] has a submission still waiting for its answer
  /// (a row in `submitting`). A read only: it settles nothing.
  static Future<bool> hasUnsettled(String depositWallet) async {
    final key = depositWallet.toLowerCase();
    try {
      final box = await Hive.openBox<String>(boxName);
      for (final storageKey in box.keys) {
        if (storageKey != key && !storageKey.toString().startsWith('$key:')) {
          continue;
        }
        final raw = box.get(storageKey);
        if (raw == null) continue;
        try {
          final row = jsonDecode(raw) as Map<String, dynamic>;
          if (row['stage'] == 'submitting') return true;
        } catch (_) {
          // Unreadable rows block; the guarded check reports them.
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> _write(
      Box<String> box, String key, Map<String, Object?> row) async {
    await box.put(key, jsonEncode(row));
    await box.flush();
  }

  Future<T> run<T>({
    required String walletId,
    required String depositWallet,
    String? tokenId,
    required Future<Map<String, dynamic>?> Function(String orderId) lookup,
    required Future<T> Function(GuardedPolymarketOrderSubmit submit) action,
    // A check (no order of its own) may wait this long for a placement
    // that holds the account to finish, then reads the journal it left.
    // An order never waits: a second placement while one runs is refused.
    Duration busyWait = Duration.zero,
  }) async {
    final key = depositWallet.toLowerCase();
    if (!RegExp(r'^0x[0-9a-f]{40}$').hasMatch(key)) {
      throw const PendingPolymarketOrder();
    }
    if (_busy.contains(key) && busyWait > Duration.zero) {
      final until = DateTime.now().add(busyWait);
      while (_busy.contains(key) && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    if (!_busy.add(key)) {
      // Held by a placement running in this app, not by an unknown
      // submission: nothing was sent and nothing is recorded here.
      throw const PolymarketOrderInProgress();
    }
    try {
      final box = await Hive.openBox<String>(boxName);
      // Old versions used an account-wide row. Keep it readable, while new
      // attempts persist the outcome token so other markets are independent.
      final keys = box.keys
          .where((k) => k == key || k.toString().startsWith('$key:'))
          .toList();
      for (final storageKey in keys) {
        final raw = box.get(storageKey);
        if (raw == null) continue;
        Map<String, dynamic>? previous;
        try {
          previous = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {
          previous = null;
        }
        if (tokenId != null &&
            previous?['tokenId'] is String &&
            previous!['tokenId'] != tokenId) {
          continue;
        }
        final storedId = previous?['orderId'];
        final readable = previous != null &&
            previous['version'] == 1 &&
            previous['depositWallet'] == key &&
            storedId is String &&
            RegExp(r'^0x[0-9a-f]{64}$').hasMatch(storedId) &&
            const {'submitting', 'accepted', 'rejected'}
                .contains(previous['stage']);
        if (!readable) {
          // Corrupt journal data cannot prove that an earlier POST failed.
          throw const PendingPolymarketOrder();
        } else {
          final row = previous;
          final id = storedId;
          // The acknowledgement lives in the row, not in memory. It used
          // to be a static map, so every relaunch re-opened a submission
          // that had already been accounted for and spent the person's
          // next tap telling them about it.
          if (row['stage'] == 'submitting') {
            Future<void> settle(String stage) async {
              row['stage'] = stage;
              row['acknowledged'] = true;
              await _write(box, storageKey.toString(), row);
            }

            // One failed lookup used to wedge the account forever: it
            // threw PendingPolymarketOrder, which is also what the next
            // tap got, and the next, with no way out from the app. The
            // read is retried before it is believed.
            Map<String, dynamic>? evidence;
            var answered = false;
            for (var attempt = 0; attempt < 3; attempt++) {
              final clock = Stopwatch()..start();
              try {
                evidence = await lookup(id);
                answered = true;
                PolymarketPlacementDiagnostics.note('order_lookup', {
                  'attempt': attempt,
                  'ms': clock.elapsedMilliseconds,
                  'found': evidence != null,
                  'status': evidence?['status'],
                  'submittedAgoS': row['submittedAtMs'] is int
                      ? (DateTime.now().millisecondsSinceEpoch -
                              (row['submittedAtMs'] as int)) ~/
                          1000
                      : null,
                });
                break;
              } catch (e) {
                PolymarketPlacementDiagnostics.note('order_lookup_failed', {
                  'attempt': attempt,
                  'ms': clock.elapsedMilliseconds,
                  'error': '${e.runtimeType}: $e',
                });
                if (attempt < 2) {
                  await Future<void>.delayed(
                      Duration(milliseconds: 1200 * (attempt + 1)));
                }
              }
            }
            final submittedAt = row['submittedAtMs'];
            final age = submittedAt is int
                ? Duration(
                    milliseconds:
                        DateTime.now().millisecondsSinceEpoch - submittedAt)
                : Duration.zero;
            // Preserve uncertain submissions until authoritative evidence,
            // or until they are old enough that keeping the outcome shut
            // helps nobody: then the row is settled as if the order were
            // out there, which sends nothing on this tap either.
            Future<void> unaccountedFor() async {
              if (age >= unresolvedSubmissionExpiry) {
                PolymarketPlacementDiagnostics.note('order_lookup_settled', {
                  'stage': 'expired',
                  'ageS': age.inSeconds,
                });
                await settle('accepted');
                throw const ResolvedPolymarketOrder(accepted: true);
              }
              throw const PendingPolymarketOrder();
            }

            if (!answered) {
              throw const PolymarketOrderCheckUnavailable();
            } else if (evidence == null) {
              // The venue keeps every order it accepted, filled or
              // cancelled, so "no such order" from the venue means the
              // post never took. It is still not believed straight away:
              // a response can be in flight for a little while after a
              // lost POST. Past the grace period the row is settled as
              // rejected and the market is free again; inside it, the
              // row keeps blocking.
              if (age >= unknownSubmissionGrace) {
                PolymarketPlacementDiagnostics.note('order_lookup_settled', {
                  'stage': 'rejected',
                  'ageS': age.inSeconds,
                });
                await settle('rejected');
              } else {
                throw const PendingPolymarketOrder();
              }
            } else {
              final status = evidence['status']?.toString().toUpperCase();
              final mine = evidence['id']?.toString().toLowerCase() == id &&
                  evidence['maker_address']?.toString().toLowerCase() == key;
              if (!mine || status == null) {
                // Something answered that is not this order. Nothing is
                // proven either way, so the row keeps blocking.
                await unaccountedFor();
              } else if (const {'CANCELED', 'CANCELLED', 'EXPIRED'}
                  .contains(status)) {
                // The order is no longer live. Cancellation can follow a
                // partial fill; activity remains the source of filled amounts.
                await settle('rejected');
              } else if (const {'LIVE', 'MATCHED', 'DELAYED', 'UNMATCHED'}
                  .contains(status)) {
                final resolvedToken = evidence['asset_id']?.toString();
                if (resolvedToken != null) row['tokenId'] = resolvedToken;
                await settle('accepted');
                // A recovered acknowledgement for a different outcome does
                // not replace this new action and need not consume its tap.
                if (tokenId != null &&
                    resolvedToken != null &&
                    resolvedToken != tokenId) {
                  continue;
                }
                // An order that IS out there resolves the old action
                // only, never this new tap: sending a second one could
                // double a position the person already holds.
                throw const ResolvedPolymarketOrder(accepted: true);
              } else {
                // A status this code does not know is not evidence.
                await unaccountedFor();
              }
            }
          }
        }
      }

      String? acceptedId;
      Map<String, Object?>? acceptedRow;
      Future<Map<String, dynamic>> submit({
        required SignedOrderV2 order,
        required String exchange,
        required void Function() ensureCurrent,
        required Future<Map<String, dynamic>> Function(void Function()) send,
      }) async {
        ensureCurrent();
        if (order.order.maker.toLowerCase() != key || acceptedId != null) {
          throw const PendingPolymarketOrder();
        }
        final digest =
            orderV2TypedData(order: order.order, verifyingContract: exchange)
                .digest;
        final id =
            '0x${digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
        final row = <String, Object?>{
          'version': 1,
          'walletId': walletId,
          'depositWallet': key,
          'orderId': id,
          'tokenId': order.order.tokenId.toString(),
          'stage': 'submitting',
          'submittedAtMs': DateTime.now().millisecondsSinceEpoch,
        };
        if (tokenId != null && order.order.tokenId.toString() != tokenId) {
          throw const PendingPolymarketOrder();
        }
        final submissionKey = '$key:${order.order.tokenId}';
        // Flush must succeed before the transport is allowed to run.
        await _write(box, submissionKey, row);
        var postStarted = false;
        try {
          final response = await send(() {
            // Re-check after persistence and the transport's capability await.
            ensureCurrent();
            postStarted = true;
          });
          final returned = (response['orderID'] ??
                  response['orderId'] ??
                  response['order_id'])
              ?.toString()
              .toLowerCase();
          if (response['success'] == false &&
              (returned == null || returned.isEmpty || returned == id) &&
              isDefinitivePolymarketOrderRejection(response['errorMsg'])) {
            throw PolymarketOrderNotAcceptedException(
                response['errorMsg'] as String);
          }
          if (!postStarted ||
              returned != id ||
              response['success'] != true ||
              !const {'matched', 'live', 'delayed', 'unmatched'}
                  .contains(response['status']?.toString().toLowerCase())) {
            throw postStarted
                ? const PolymarketOrderOutcomeUnknown()
                : const PendingPolymarketOrder();
          }
          row['stage'] = 'accepted';
          row['acknowledged'] = true;
          await _write(box, submissionKey, row);
          acceptedId = id;
          acceptedRow = row;
          return response;
        } catch (error) {
          if (!postStarted ||
              error is PolymarketOrderNotAcceptedException ||
              error is InvalidApiKeyException ||
              error is GeoBlockException) {
            row['stage'] = 'rejected';
            row['acknowledged'] = true;
            await _write(box, submissionKey, row);
            rethrow;
          }
          // Leave the persisted order blocking; arbitrary errors prove nothing.
          if (error is PendingPolymarketOrder) rethrow;
          throw const PolymarketOrderOutcomeUnknown();
        }
      }

      final result = await action(submit);
      if (acceptedRow case final accepted?) {
        // The caller has the venue's acknowledgement in hand, so the row
        // has done its work. Recording that durably is what stops the
        // next launch re-opening an order everybody already agrees on.
        accepted['acknowledged'] = true;
        await _write(box, '$key:${accepted['tokenId']}', accepted);
      }
      return result;
    } finally {
      _busy.remove(key);
    }
  }
}
