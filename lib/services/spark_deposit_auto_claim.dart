import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kute/models/breez/deposit_update.dart';
import 'package:kute/models/breez/init.dart' show kSparkAutoClaimMaxFeeSats;
import 'package:kute/models/transactions_model.dart';
import 'package:kute/services/spark_deposit_actions.dart';
import 'package:kute/services/tracking_service.dart';

/// The one automatic claim the SDK never makes again: an early claim the
/// provider accepted but never settled. The SDK's sync skips such a deposit
/// on every later pass (an early claim cannot be made twice), even once it
/// matures, so it would sit as "pending" forever with nobody claiming it.
///
/// Every other mature deposit is already retried by the SDK itself on each
/// sync (every 60 s, and on connect): failures and network errors are
/// claimed again under the normal cap, and a claim refused for its fee is
/// kept until the fee fits. Claiming those from here too would only race
/// the SDK's own claim guard, so this leaves them alone.
///
/// Runs after every deposit snapshot (connect, each sync, pull-to-refresh):
/// at most one attempt per outpoint per snapshot, never two at once for
/// the same outpoint, with a growing wait between attempts. Holds nothing
/// but outpoint keys in memory.
class SparkDepositAutoClaimer {
  SparkDepositAutoClaimer({
    required this.actions,
    DateTime Function()? now,
    this.onClaimed,
  }) : _now = now ?? DateTime.now;

  final SparkDepositActions actions;
  final DateTime Function() _now;

  /// Called after an attempt the SDK accepted, so the feed can refresh.
  final void Function()? onClaimed;

  /// Waits between attempts on one outpoint: the first runs at once.
  static const backoff = [
    Duration.zero,
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(hours: 1),
  ];

  final Map<String, ({int attempts, DateTime last})> _history = {};
  final Set<String> _inFlight = {};

  /// Outpoints with an attempt running now.
  @visibleForTesting
  Set<String> get inFlight => Set.unmodifiable(_inFlight);

  /// Reviews one snapshot of [walletId]'s pending deposits. Returns once
  /// every attempt it started has finished.
  Future<void> review(
      String walletId, List<SparkUnclaimedDeposit> deposits) async {
    final listed = <String>{};
    final attempts = <Future<void>>[];
    for (final deposit in deposits) {
      final key = sparkOutpointKey(deposit.txid, deposit.vout);
      listed.add(key);
      if (!deposit.hasStaleEarlyClaim) continue;
      if (deposit.stage == SparkDepositStage.refunding) continue;
      if (_inFlight.contains(key)) continue;
      final past = _history[key];
      if (past != null) {
        final wait = backoff[past.attempts.clamp(0, backoff.length - 1)];
        if (_now().difference(past.last) < wait) continue;
      }
      attempts.add(_attempt(walletId, deposit, key));
    }
    // A deposit the SDK no longer lists starts over if it ever returns.
    _history.removeWhere((key, _) => !listed.contains(key));
    await Future.wait(attempts);
  }

  Future<void> _attempt(
      String walletId, SparkUnclaimedDeposit deposit, String key) async {
    _inFlight.add(key);
    final attempts = (_history[key]?.attempts ?? 0) + 1;
    _history[key] = (attempts: attempts, last: _now());
    final amount = deposit.amount.toInt();
    try {
      final result = await actions.claim(
        walletId: walletId,
        txid: deposit.txid,
        vout: deposit.vout,
        maxFeeSats: BigInt.from(kSparkAutoClaimMaxFeeSats),
        depositAmountSats: BigInt.from(amount),
      );
      TrackingService.sparkDepositClaimed(
        outcome: switch (result.outcome) {
          SparkDepositClaimOutcome.submitted => 'submitted',
          SparkDepositClaimOutcome.alreadyReceived => 'already_received',
          SparkDepositClaimOutcome.noLongerPending => 'no_longer_pending',
          SparkDepositClaimOutcome.statusUnknown => 'status_unknown',
        },
        status: result.paymentStatus?.name,
        amountSats: amount > 0 ? amount : null,
        trigger: 'stale_early_claim',
      );
      onClaimed?.call();
    } on SparkDepositActionException catch (e) {
      // Busy means the SDK or the sheet holds the outpoint right now: not
      // an attempt, so it does not grow the wait.
      if (e.reason == SparkDepositActionReason.busy) {
        _history[key] = (attempts: attempts - 1, last: _now());
      } else {
        TrackingService.autoClaimFailed(
            amountSats: amount, reason: 'stale_${e.reason.name}');
      }
    } catch (_) {
      TrackingService.autoClaimFailed(
          amountSats: amount, reason: 'stale_sdk_error');
    } finally {
      _inFlight.remove(key);
    }
  }
}
