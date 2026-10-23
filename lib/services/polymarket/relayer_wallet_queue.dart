// lib/services/polymarket/relayer_wallet_queue.dart
//
// One relayer action at a time per Predictions deposit wallet.
//
// The deposit wallet's relayer runs one WALLET batch at a time and keeps it
// "active" until it is confirmed: a second batch submitted meanwhile is
// refused ("wallet busy: active action exists"), and one signed against
// the nonce the first is about to consume is refused too ("batch nonce N
// does not match on-chain nonce M"). On a device (15 October 2026) the
// same delivered USDC.e was converted twice, the second batch was refused
// busy, its retry loop kept the relayer occupied, and the bet placed right
// after failed with "This action did not complete".
//
// So the actions that READ the wallet and then sign a batch from that read
// (the conversion, the approvals, a missing exchange allowance) run in one
// queue per wallet, each released only once its batch is confirmed; the
// next one reads (balance, allowances, nonce) after that. A refusal that
// only says the relayer was still busy or the nonce moved is transient:
// nothing was accepted, so the batch is signed again on a fresh nonce and
// sent again, a few times at most. A conversion of the same amount the
// last confirmed one converted, read moments after it, is a balance read
// that has not caught up yet: never signed again.

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// A relayer refusal that says only that the wallet was busy with another
/// action or the nonce moved under it: nothing was accepted, a fresh nonce
/// and signature may go through.
bool isTransientRelayerRefusal(Object e) {
  final text = e.toString().toLowerCase();
  return text.contains('wallet busy') ||
      text.contains('active action exists') ||
      (text.contains('nonce') &&
          (text.contains('does not match') ||
              text.contains('too low') ||
              text.contains('invalid nonce') ||
              text.contains('already used')));
}

/// The waits between sends of a batch the relayer refused as transient.
@visibleForTesting
Duration Function(int attempt) relayerTransientBackoff =
    (attempt) => Duration(seconds: 2 * (attempt + 1));

/// How many times a transient refusal is sent again.
const int kRelayerTransientRetries = 4;

/// Runs [send] (which reads the nonce, signs and submits), sending it
/// again after a transient refusal ([isTransientRelayerRefusal]) at most
/// [kRelayerTransientRetries] times. [onRetry] hears each one.
Future<T> withTransientRelayerRetry<T>(
  Future<T> Function(int attempt) send, {
  void Function(int attempt, Object error)? onRetry,
}) async {
  for (var attempt = 0;; attempt++) {
    try {
      return await send(attempt);
    } catch (e) {
      if (!isTransientRelayerRefusal(e) ||
          attempt >= kRelayerTransientRetries) {
        rethrow;
      }
      onRetry?.call(attempt, e);
      await Future<void>.delayed(relayerTransientBackoff(attempt));
    }
  }
}

/// One action at a time per deposit wallet, in arrival order.
abstract final class RelayerWalletQueue {
  static final Map<String, Future<void>> _tails = {};

  /// Runs [action] once every action queued before it for [wallet] ended
  /// (however it ended).
  static Future<T> run<T>(String wallet, Future<T> Function() action) {
    final key = wallet.toLowerCase();
    final previous = _tails[key] ?? Future<void>.value();
    final result = previous.then((_) => action());
    final tail = result.then<void>((_) {}, onError: (Object _) {});
    _tails[key] = tail;
    tail.whenComplete(() {
      if (identical(_tails[key], tail)) _tails.remove(key);
    });
    return result;
  }

  /// Whether an action is queued or running for [wallet].
  static bool busy(String wallet) => _tails.containsKey(wallet.toLowerCase());

  @visibleForTesting
  static void reset() => _tails.clear();
}

/// The conversions confirmed lately, per wallet: a read showing the same
/// USDC.e moments after one converted it is a read that has not caught up.
abstract final class RecentUsdceWraps {
  /// How long after a confirmed conversion the same amount is distrusted.
  static const Duration staleWindow = Duration(minutes: 2);

  static final Map<String, ({BigInt amount, DateTime at})> _last = {};

  /// Test seam: the clock.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static void confirmed(String wallet, BigInt amount) =>
      _last[wallet.toLowerCase()] = (amount: amount, at: clock());

  /// Whether a read of [amount] for [wallet] may be the conversion that
  /// was just confirmed, seen by a node that has not caught up.
  static bool maybeStale(String wallet, BigInt amount) {
    final last = _last[wallet.toLowerCase()];
    if (last == null) return false;
    if (clock().difference(last.at) > staleWindow) return false;
    return amount == last.amount;
  }

  @visibleForTesting
  static void reset() {
    _last.clear();
    clock = DateTime.now;
  }
}

/// Test seam: how long a conversion waits for a fresh read before it
/// treats a repeated amount as stale.
@visibleForTesting
Duration staleReadPoll = const Duration(seconds: 1);

/// How many fresh reads a repeated amount gets before it is skipped.
const int kStaleReadTries = 8;

/// The deduplicated conversion behind every trigger: in the wallet's queue,
/// reads the USDC.e ([readUsdce]); a read equal to the conversion just
/// confirmed is read again until it changes (at most [kStaleReadTries]
/// times) and skipped if it never does; otherwise [wrap] converts exactly
/// that amount and waits for its confirmation. Returns what was converted.
Future<BigInt> convertHeldUsdceOnce({
  required String wallet,
  required Future<BigInt> Function() readUsdce,
  required Future<void> Function(BigInt amount) wrap,
  void Function(String line)? log,
}) =>
    RelayerWalletQueue.run(wallet, () async {
      var usdce = await readUsdce();
      var tries = 0;
      while (usdce > BigInt.zero &&
          RecentUsdceWraps.maybeStale(wallet, usdce) &&
          tries < kStaleReadTries) {
        tries++;
        await Future<void>.delayed(staleReadPoll);
        usdce = await readUsdce();
      }
      if (usdce <= BigInt.zero) return BigInt.zero;
      if (RecentUsdceWraps.maybeStale(wallet, usdce)) {
        log?.call('[poly-relayer] WRAP skipped: $usdce is the amount the '
            'last confirmed conversion took (a read not caught up yet)');
        return BigInt.zero;
      }
      await wrap(usdce);
      RecentUsdceWraps.confirmed(wallet, usdce);
      return usdce;
    });
